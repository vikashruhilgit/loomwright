#!/usr/bin/env bash
# test-progress-state.sh — self-tests for emit-progress-event.sh + build-state.sh
# (Fix 3 / D5 — "One writer for progress state, derived state.md", Subtask 1).
#
# DETERMINISTIC, NO LIVE SIDE EFFECTS. Every case runs inside a mktemp
# sandbox that is a REAL git repo (init'd per-case) — the SUT anchors via
# `git worktree list --porcelain`, so a real repo is required to exercise
# the actual code path (not a stand-in). The real repo's own
# `.supervisor/logs` is snapshotted and asserted untouched (mirrors
# test-token-ledger.sh's convention). Any `git worktree add` created by a
# case is removed with `git worktree remove --force` before the sandbox is
# deleted — no stray worktrees left behind.
#
# Step 0 (harness assertion, not prose): confirms the EMPIRICAL 2026-07-28
# observation this subtask's anchoring design depends on — from inside a
# REAL DETACHED linked worktree, `git worktree list --porcelain`'s first
# entry correctly resolves the MAIN checkout while bare
# `git branch --show-current` there returns EMPTY. If this ever stops being
# true on a future git version, this is the assertion that will catch it.
#
# Cases:
#   0.  Step 0 — empirical worktree/branch hazard assertion
#   1.  emitter: empty stdin -> exit 0, no log
#   2.  emitter: malformed JSON stdin -> exit 0, no log
#   3.  emitter: missing session_id (no state.md, no cc session_id) -> exit 0, no log
#   4.  emitter: missing python3 -> exit 0, no log
#   5.  emitter: missing jq -> exit 0, no log
#   5b. emitter: missing git -> exit 0, no log, no .supervisor/ side effects
#   6.  emitter: not-a-git-repo cwd -> exit 0, no log anywhere
#   7.  emitter: mismatched worktree cross-check -> exit 0, no log
#   8.  emitter: unwritable log dir -> exit 0, no log
#   9.  emitter: one-event-per-invocation (two distinct payloads -> two lines)
#   10. emitter: idempotency on repeated identical payload (stays exit 0, log grows, state.md stable)
#   11. Parallel-Path: emitter run with cwd inside a (subtask-branch) worktree
#       -> event lands in MAIN checkout's log, carrying the SESSION branch
#   12. AC-6: worktree-cwd token_ledger emission lands in the SAME log file
#   13. build-state.sh: missing jq -> exit 0, no state.md
#   14. build-state.sh: absent/empty log -> no state.md written at all
#   15. build-state.sh: subtask_complete-only log -> status running / phase EXECUTE
#   16. build-state.sh: session_end(completed) -> status completed / phase LOOP
#   17. build-state.sh: session_end(completed_with_escalation) -> mapped correctly
#   18. build-state.sh: session_end(failed) -> mapped correctly
#   19. build-state.sh: session_end with unrecognized status -> falls back to "completed"
#   20. Projector round-trip byte-identity (delete + re-project twice -> identical bytes)
#   21. Projector preserves ## Decisions Log / ## Phase Flags / ## Checkpoint
#   22. AC-5: projected state.md (status running, matching branch) satisfies
#       hook-dispatch-on-pr-create.sh Source 1 -> dispatch fires
#   22b. AC-5 negative: projected state.md (status completed, terminal) does
#        NOT satisfy Source 1 -> no dispatch (falls through / fail-closed)
#   23. AC-2: committed fixture (loaded from disk via `<` redirection, NOT
#       make_payload()) carrying the FULL real SubagentStop field set —
#       session_id, transcript_path, cwd, permission_mode, agent_id,
#       agent_type, effort, hook_event_name, stop_hook_active,
#       agent_transcript_path, last_assistant_message, background_tasks,
#       session_crons — and explicitly no `result_block` key -> emitter
#       still exits 0, writes exactly one correct event, and copies only the
#       fields it actually documents (extra real-world fields are ignored,
#       not merely present-but-unused)
#
# EXIT: 0 on full pass, 1 on any failed assertion.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EMITTER="$SCRIPT_DIR/emit-progress-event.sh"
PROJECTOR="$SCRIPT_DIR/build-state.sh"
LEDGER="$SCRIPT_DIR/emit-token-ledger.sh"
DISPATCH_WRAPPER="$SCRIPT_DIR/hook-dispatch-on-pr-create.sh"
PR_FIXTURE="$SCRIPT_DIR/fixtures/posttooluse-gh-pr-create.json"
FIXDIR="$SCRIPT_DIR/progress-event-fixtures"
FULL_FIXTURE="$FIXDIR/subagentstop-full.json"

for f in "$EMITTER" "$PROJECTOR" "$LEDGER" "$DISPATCH_WRAPPER" "$PR_FIXTURE" "$FULL_FIXTURE"; do
  if [ ! -e "$f" ]; then
    echo "FATAL  required file not found: $f" >&2
    exit 1
  fi
done
for c in python3 jq git bash; do
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "FATAL  $c required to run this suite" >&2
    exit 1
  fi
done

PASS_COUNT=0
FAIL_COUNT=0
ok() { echo "  ok: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
no() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label  expected='$expected' actual='$actual'"; fi
}

# Snapshot real .supervisor/logs — must be untouched by this suite.
REAL_LOGS="$REPO_ROOT/.supervisor/logs"
snapshot_real() {
  if [ -d "$REAL_LOGS" ]; then
    find "$REAL_LOGS" -type f 2>/dev/null | sort | cksum
  else
    echo "logs:ABSENT"
  fi
}
REAL_BEFORE="$(snapshot_real)"

REALBASH="$(command -v bash)"
PAYLOAD_DIR="$(mktemp -d)"
CLEANUP_DIRS=("$PAYLOAD_DIR")
CLEANUP_WORKTREES=()  # "repo_root|worktree_path" pairs
cleanup() {
  local wt
  for wt in "${CLEANUP_WORKTREES[@]:-}"; do
    [ -n "$wt" ] || continue
    local repo="${wt%%|*}" path="${wt#*|}"
    git -C "$repo" worktree remove --force "$path" >/dev/null 2>&1 || true
  done
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [ -n "$d" ] || continue
    chmod -R u+rwx "$d" 2>/dev/null || true
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# ---- helpers ------------------------------------------------------------

# init_repo — creates a fresh git repo (with one commit, branch $1) and
# echoes its absolute path. Registered for cleanup.
init_repo() {
  local branch="${1:-feature/progress-state-test}"
  local d; d="$(mktemp -d)"
  # Canonicalize (pwd -P) immediately: on macOS /tmp and $TMPDIR resolve
  # through a /private symlink, so a raw mktemp path does NOT byte-match
  # what `git -C <path> rev-parse --show-toplevel` reports. Both SUTs derive
  # their own root via git internally (always self-consistent in real use);
  # this canonicalization is ONLY so the TEST HARNESS's own pre-resolved
  # $REPO variables agree with the SUT's git-derived values for assertions.
  d="$(cd "$d" && pwd -P)"
  CLEANUP_DIRS+=("$d")
  ( cd "$d" && git init -q . \
      && git config user.email test@example.com \
      && git config user.name test \
      && echo seed > seed.txt \
      && git add seed.txt \
      && git commit -qm init \
      && git branch -M "$branch" ) >/dev/null 2>&1
  printf '%s' "$d"
}

# A curated, EXCLUSIVE PATH so `command -v <tool>` can be made to genuinely
# fail for a specific tool without disturbing every other tool the SUT
# needs (this machine colocates python3/jq/git/sed/etc in the same real
# bin dir, so a directory-level PATH edit would break unrelated tools).
CURATED_TOOLS="cat git sed tr python3 mkdir date dirname jq mktemp awk mv rm wc head bash"
build_curated_path() {
  # Usage: build_curated_path <space-separated excluded tool names>
  local exclude=" ${1:-} "
  local dir; dir="$(mktemp -d)"
  CLEANUP_DIRS+=("$dir")
  local t real
  for t in $CURATED_TOOLS; do
    case "$exclude" in
      *" $t "*) continue ;;
    esac
    real="$(command -v "$t" 2>/dev/null || true)"
    [ -n "$real" ] || continue
    ln -sf "$real" "$dir/$t" 2>/dev/null || true
  done
  printf '%s' "$dir"
}

# run_emitter <workdir> <payload-file-or--empty> [extra PATH exclusions]
run_emitter() {
  local wd="$1" payload="$2" exclude="${3:-}"
  local path; path="$(build_curated_path "$exclude")"
  local out rc
  if [ "$payload" = "--empty" ]; then
    out="$( cd "$wd" && PATH="$path" "$REALBASH" "$EMITTER" </dev/null 2>&1 )"
  else
    out="$( cd "$wd" && PATH="$path" "$REALBASH" "$EMITTER" < "$payload" 2>&1 )"
  fi
  rc=$?
  printf '%s\n' "$out"
  printf 'RC=%s\n' "$rc"
}

get_rc() { printf '%s\n' "$1" | grep '^RC=' | tail -1 | cut -d= -f2; }

logs_snapshot() {
  local wd="$1"
  find "$wd/.supervisor/logs" -type f 2>/dev/null | sort | cksum
}

make_payload() {
  # Usage: make_payload <file> <session_id> <agent_type> <agent_id>
  local file="$1" sid="$2" atype="$3" aid="$4"
  jq -n --arg sid "$sid" --arg at "$atype" --arg aid "$aid" '{
    session_id: $sid,
    agent_id: $aid,
    agent_type: $at,
    hook_event_name: "SubagentStop",
    transcript_path: "/nonexistent/session.jsonl",
    agent_transcript_path: "/nonexistent/agent.jsonl",
    last_assistant_message: "## WORKER_RESULT\n- status: completed\n"
  }' > "$file"
}

echo "== 0. Step 0 — empirical worktree/branch hazard assertion =="
REPO0="$(init_repo "main")"
WT0="$REPO0-detached-wt"
git -C "$REPO0" worktree add -q --detach "$WT0" >/dev/null 2>&1
CLEANUP_WORKTREES+=("$REPO0|$WT0")
MAIN_VIA_PORCELAIN="$(cd "$WT0" && git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
BRANCH_VIA_NAIVE="$(cd "$WT0" && git branch --show-current 2>/dev/null || true)"
assert_eq "step0 porcelain resolves the MAIN checkout from inside the worktree" "$REPO0" "$MAIN_VIA_PORCELAIN"
assert_eq "step0 naive 'git branch --show-current' is EMPTY in a detached worktree (the hazard)" "" "$BRANCH_VIA_NAIVE"
if [ ! -d "$WT0/.supervisor" ]; then
  ok "step0 the detached worktree itself has no .supervisor/ (confirms anchoring must NOT use \$PWD)"
else
  no "step0 unexpectedly found .supervisor/ inside the worktree"
fi

echo "== 1. emitter: empty stdin -> exit 0, no log =="
REPO1="$(init_repo)"
BEFORE1="$(logs_snapshot "$REPO1")"
OUT1="$(run_emitter "$REPO1" --empty)"
assert_eq "case1 exit 0" "0" "$(get_rc "$OUT1")"
assert_eq "case1 no new log files" "$BEFORE1" "$(logs_snapshot "$REPO1")"

echo "== 2. emitter: malformed JSON stdin -> exit 0, no log =="
REPO2="$(init_repo)"
BAD2="$PAYLOAD_DIR/bad2.json"
printf 'not { valid json' > "$BAD2"
BEFORE2="$(logs_snapshot "$REPO2")"
OUT2="$(run_emitter "$REPO2" "$BAD2")"
assert_eq "case2 exit 0" "0" "$(get_rc "$OUT2")"
assert_eq "case2 no new log files" "$BEFORE2" "$(logs_snapshot "$REPO2")"

echo "== 3. emitter: missing session_id (no state.md) -> exit 0, no log =="
REPO3="$(init_repo)"
NOSID3="$PAYLOAD_DIR/nosid3.json"
jq -n '{agent_type:"loomwright:worker", agent_id:"a1", hook_event_name:"SubagentStop"}' > "$NOSID3"
BEFORE3="$(logs_snapshot "$REPO3")"
OUT3="$(run_emitter "$REPO3" "$NOSID3")"
assert_eq "case3 exit 0" "0" "$(get_rc "$OUT3")"
assert_eq "case3 no new log files" "$BEFORE3" "$(logs_snapshot "$REPO3")"

echo "== 4. emitter: missing python3 -> exit 0, no log =="
REPO4="$(init_repo)"
P4="$PAYLOAD_DIR/p4.json"
make_payload "$P4" "sid-case4" "loomwright:worker" "a4"
BEFORE4="$(logs_snapshot "$REPO4")"
OUT4="$(run_emitter "$REPO4" "$P4" "python3")"
assert_eq "case4 exit 0" "0" "$(get_rc "$OUT4")"
assert_eq "case4 no new log files (python3 absent)" "$BEFORE4" "$(logs_snapshot "$REPO4")"

echo "== 5. emitter: missing jq -> exit 0, no log =="
REPO5="$(init_repo)"
P5="$PAYLOAD_DIR/p5.json"
make_payload "$P5" "sid-case5" "loomwright:worker" "a5"
BEFORE5="$(logs_snapshot "$REPO5")"
OUT5="$(run_emitter "$REPO5" "$P5" "jq")"
assert_eq "case5 exit 0" "0" "$(get_rc "$OUT5")"
assert_eq "case5 no new log files (jq absent)" "$BEFORE5" "$(logs_snapshot "$REPO5")"

echo "== 5b. emitter: missing git -> exit 0, no log, no .supervisor/ side effects =="
REPO5B="$(init_repo)"
P5B="$PAYLOAD_DIR/p5b.json"
make_payload "$P5B" "sid-case5b" "loomwright:worker" "a5b"
BEFORE5B="$(logs_snapshot "$REPO5B")"
OUT5B="$(run_emitter "$REPO5B" "$P5B" "git")"
assert_eq "case5b exit 0" "0" "$(get_rc "$OUT5B")"
assert_eq "case5b no new log files (git absent)" "$BEFORE5B" "$(logs_snapshot "$REPO5B")"
if [ -d "$REPO5B/.supervisor" ]; then
  no "case5b unexpectedly created .supervisor/ despite git being absent"
else
  ok "case5b no .supervisor/ side effects (git absent)"
fi

echo "== 6. emitter: not-a-git-repo cwd -> exit 0, no log anywhere =="
NOGIT6="$(mktemp -d)"
CLEANUP_DIRS+=("$NOGIT6")
P6="$PAYLOAD_DIR/p6.json"
make_payload "$P6" "sid-case6" "loomwright:worker" "a6"
OUT6="$(run_emitter "$NOGIT6" "$P6")"
assert_eq "case6 exit 0" "0" "$(get_rc "$OUT6")"
if [ -d "$NOGIT6/.supervisor" ]; then
  no "case6 unexpectedly created .supervisor/ in a non-git cwd"
else
  ok "case6 no .supervisor/ created in a non-git cwd"
fi

echo "== 7. emitter: mismatched worktree cross-check -> exit 0, no log =="
REPO7="$(init_repo)"
FAKEGITDIR7="$(mktemp -d)"
CLEANUP_DIRS+=("$FAKEGITDIR7")
cat > "$FAKEGITDIR7/git" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2 \$3" = "worktree list --porcelain" ]; then
  echo "worktree $REPO7"
  exit 0
fi
case "\$*" in
  "-C $REPO7 rev-parse --path-format=absolute --show-toplevel")
    echo "/deliberately/mismatched/root"
    exit 0
    ;;
esac
exit 1
EOF
chmod +x "$FAKEGITDIR7/git"
CURATED7="$(build_curated_path "git")"
PATH7="$FAKEGITDIR7:$CURATED7"
P7="$PAYLOAD_DIR/p7.json"
make_payload "$P7" "sid-case7" "loomwright:worker" "a7"
BEFORE7="$(logs_snapshot "$REPO7")"
OUT7="$( cd "$REPO7" && PATH="$PATH7" "$REALBASH" "$EMITTER" < "$P7" 2>&1 )"
RC7=$?
assert_eq "case7 exit 0" "0" "$RC7"
assert_eq "case7 no new log files (mismatched cross-check)" "$BEFORE7" "$(logs_snapshot "$REPO7")"

echo "== 8. emitter: unwritable log dir -> exit 0, no log =="
REPO8="$(init_repo)"
mkdir -p "$REPO8/.supervisor"
chmod 555 "$REPO8/.supervisor"
P8="$PAYLOAD_DIR/p8.json"
make_payload "$P8" "sid-case8" "loomwright:worker" "a8"
OUT8="$(run_emitter "$REPO8" "$P8")"
RC8="$(get_rc "$OUT8")"
chmod 755 "$REPO8/.supervisor"
assert_eq "case8 exit 0" "0" "$RC8"
if [ -f "$REPO8/.supervisor/logs/sid-case8.jsonl" ]; then
  no "case8 unexpectedly wrote a log despite unwritable dir"
else
  ok "case8 no log written (unwritable log dir)"
fi

echo "== 9. emitter: one-event-per-invocation =="
REPO9="$(init_repo)"
P9A="$PAYLOAD_DIR/p9a.json"; P9B="$PAYLOAD_DIR/p9b.json"
make_payload "$P9A" "sid-case9" "loomwright:worker" "a9-first"
make_payload "$P9B" "sid-case9" "loomwright:worker" "a9-second"
OUT9A="$(run_emitter "$REPO9" "$P9A")"
assert_eq "case9 first call exit 0" "0" "$(get_rc "$OUT9A")"
OUT9B="$(run_emitter "$REPO9" "$P9B")"
assert_eq "case9 second call exit 0" "0" "$(get_rc "$OUT9B")"
LOG9="$REPO9/.supervisor/logs/sid-case9.jsonl"
LINES9="$(wc -l < "$LOG9" 2>/dev/null | tr -d '[:space:]')"
assert_eq "case9 exactly one line per invocation (2 calls -> 2 lines)" "2" "$LINES9"
assert_eq "case9 line1 event" "subtask_complete" "$(sed -n 1p "$LOG9" | jq -r '.event')"
assert_eq "case9 line2 agent_id" "a9-second" "$(sed -n 2p "$LOG9" | jq -r '.agent_id')"

echo "== 10. emitter: idempotency on repeated identical payload =="
REPO10="$(init_repo)"
P10="$PAYLOAD_DIR/p10.json"
make_payload "$P10" "sid-case10" "loomwright:worker" "a10"
for i in 1 2 3; do
  OUT10="$(run_emitter "$REPO10" "$P10")"
  RC10="$(get_rc "$OUT10")"
  if [ "$RC10" != "0" ]; then no "case10 call $i not exit 0 (rc=$RC10)"; fi
done
ok "case10 three identical calls all exit 0"
LOG10="$REPO10/.supervisor/logs/sid-case10.jsonl"
LINES10="$(wc -l < "$LOG10" 2>/dev/null | tr -d '[:space:]')"
assert_eq "case10 log grows by exactly one line per identical call (3 calls -> 3 lines)" "3" "$LINES10"
# Projector must still be stable/correct after repeated identical events.
bash "$PROJECTOR" "sid-case10" "$REPO10" >/dev/null 2>&1
assert_eq "case10 projected status stable after repeats" "running" "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO10/.supervisor/state.md")"

echo "== 11. Parallel-Path: worktree cwd (subtask branch) -> event lands in MAIN log with SESSION branch =="
REPO11="$(init_repo "feature/session-branch-11")"
# Bootstrap an ACTIVE session (state.md running) so subsequent worktree-cwd
# invocations resolve to the SAME plugin session id, matching real usage.
P11SEED="$PAYLOAD_DIR/p11seed.json"
make_payload "$P11SEED" "sid-case11" "loomwright:worker" "a11-seed"
run_emitter "$REPO11" "$P11SEED" >/dev/null
WT11="$REPO11-subtask-wt"
git -C "$REPO11" worktree add -q -b subtask/case11-a "$WT11" >/dev/null 2>&1
CLEANUP_WORKTREES+=("$REPO11|$WT11")
P11="$PAYLOAD_DIR/p11.json"
make_payload "$P11" "sid-case11-cc-fallback" "loomwright:worker" "a11-from-worktree"
OUT11="$(run_emitter "$WT11" "$P11")"
assert_eq "case11 exit 0" "0" "$(get_rc "$OUT11")"
if [ -d "$WT11/.supervisor" ]; then
  no "case11 unexpectedly created .supervisor/ inside the subtask worktree"
else
  ok "case11 no .supervisor/ created inside the subtask worktree"
fi
LOG11="$REPO11/.supervisor/logs/sid-case11.jsonl"
if [ -f "$LOG11" ]; then ok "case11 event landed in the MAIN checkout's log"; else no "case11 main-checkout log missing"; fi
LASTLINE11="$(tail -1 "$LOG11" 2>/dev/null)"
assert_eq "case11 event branch is the SESSION (main) branch, not the subtask branch" \
  "feature/session-branch-11" "$(printf '%s' "$LASTLINE11" | jq -r '.branch // empty')"
assert_eq "case11 event agent_id from the worktree-cwd call" "a11-from-worktree" "$(printf '%s' "$LASTLINE11" | jq -r '.agent_id')"

echo "== 12. AC-6: worktree-cwd token_ledger emission lands in the SAME log file =="
TRANSCRIPT12="$PAYLOAD_DIR/transcript12.jsonl"
printf 'ABCDEFGHIJ' > "$TRANSCRIPT12"   # 10 bytes
P12="$PAYLOAD_DIR/p12.json"
jq -n --arg tp "$TRANSCRIPT12" '{
  session_id: "sid-case12-cc-fallback",
  agent_type: "loomwright:code-reviewer",
  agent_id: "a12-reviewer",
  agent_transcript_path: $tp
}' > "$P12"
OUT12="$( cd "$WT11" && "$REALBASH" "$LEDGER" < "$P12" 2>&1 )"
RC12=$?
assert_eq "case12 ledger exit 0 from worktree cwd" "0" "$RC12"
if [ -f "$LOG11" ]; then
  LEDGERLINE12="$(tail -1 "$LOG11")"
  assert_eq "case12 token_ledger event landed in the SAME main-checkout log" \
    "token_ledger" "$(printf '%s' "$LEDGERLINE12" | jq -r '.event')"
  assert_eq "case12 token_ledger transcript bytes" "10" "$(printf '%s' "$LEDGERLINE12" | jq -r '.token_proxy_transcript_bytes')"
else
  no "case12 main-checkout log missing"
fi

echo "== 13. build-state.sh: missing jq -> exit 0, no state.md =="
REPO13="$(init_repo)"
mkdir -p "$REPO13/.supervisor/logs"
echo '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case13"}' > "$REPO13/.supervisor/logs/sid-case13.jsonl"
CURATED13="$(build_curated_path "jq")"
OUT13="$( cd "$REPO13" && PATH="$CURATED13" "$REALBASH" "$PROJECTOR" "sid-case13" 2>&1 )"
RC13=$?
assert_eq "case13 exit 0" "0" "$RC13"
if [ -f "$REPO13/.supervisor/state.md" ]; then
  no "case13 unexpectedly wrote state.md despite missing jq"
else
  ok "case13 no state.md written (jq absent)"
fi

echo "== 14. build-state.sh: absent/empty log -> no state.md written at all =="
REPO14="$(init_repo)"
OUT14A="$(bash "$PROJECTOR" "sid-case14-absent" "$REPO14" 2>&1)"
RC14A=$?
assert_eq "case14a exit 0 (absent log)" "0" "$RC14A"
[ -f "$REPO14/.supervisor/state.md" ] && no "case14a wrote state.md despite absent log" || ok "case14a no state.md (absent log)"
mkdir -p "$REPO14/.supervisor/logs"
: > "$REPO14/.supervisor/logs/sid-case14-empty.jsonl"
OUT14B="$(bash "$PROJECTOR" "sid-case14-empty" "$REPO14" 2>&1)"
RC14B=$?
assert_eq "case14b exit 0 (empty log)" "0" "$RC14B"
[ -f "$REPO14/.supervisor/state.md" ] && no "case14b wrote state.md despite empty log" || ok "case14b no state.md (empty log)"

echo "== 15. build-state.sh: subtask_complete-only -> status running / phase EXECUTE =="
REPO15="$(init_repo "feature/case15")"
mkdir -p "$REPO15/.supervisor/logs"
echo '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case15"}' > "$REPO15/.supervisor/logs/sid-case15.jsonl"
bash "$PROJECTOR" "sid-case15" "$REPO15" >/dev/null 2>&1
S15="$REPO15/.supervisor/state.md"
[ -f "$S15" ] && ok "case15 state.md written" || no "case15 state.md missing"
assert_eq "case15 status" "running" "$(sed -nE 's/^- status:[[:space:]]*//p' "$S15")"
assert_eq "case15 phase" "EXECUTE" "$(sed -nE 's/^- phase:[[:space:]]*//p' "$S15")"
assert_eq "case15 session_id" "sid-case15" "$(sed -nE 's/^- session_id:[[:space:]]*//p' "$S15")"
assert_eq "case15 branch" "feature/case15" "$(sed -nE 's/^- branch:[[:space:]]*//p' "$S15")"

echo "== 16/17/18. build-state.sh: session_end status mapping =="
for pair in "completed:completed" "completed_with_escalation:completed_with_escalation" "failed:failed"; do
  raw="${pair%%:*}"; expect="${pair#*:}"
  REPOX="$(init_repo "feature/case-$raw")"
  mkdir -p "$REPOX/.supervisor/logs"
  {
    echo "{\"event\":\"subtask_complete\",\"type\":\"subtask_complete\",\"session_id\":\"sid-$raw\"}"
    echo "{\"event\":\"session_end\",\"type\":\"session_end\",\"session_id\":\"sid-$raw\",\"status\":\"$raw\"}"
  } > "$REPOX/.supervisor/logs/sid-$raw.jsonl"
  bash "$PROJECTOR" "sid-$raw" "$REPOX" >/dev/null 2>&1
  SX="$REPOX/.supervisor/state.md"
  assert_eq "session_end($raw) status" "$expect" "$(sed -nE 's/^- status:[[:space:]]*//p' "$SX")"
  assert_eq "session_end($raw) phase" "LOOP" "$(sed -nE 's/^- phase:[[:space:]]*//p' "$SX")"
done

echo "== 19. build-state.sh: session_end with unrecognized status -> falls back to 'completed' =="
REPO19="$(init_repo "feature/case19")"
mkdir -p "$REPO19/.supervisor/logs"
{
  echo '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case19"}'
  echo '{"event":"session_end","type":"session_end","session_id":"sid-case19","status":"bogus_status"}'
} > "$REPO19/.supervisor/logs/sid-case19.jsonl"
bash "$PROJECTOR" "sid-case19" "$REPO19" >/dev/null 2>&1
S19="$REPO19/.supervisor/state.md"
assert_eq "case19 status falls back to completed" "completed" "$(sed -nE 's/^- status:[[:space:]]*//p' "$S19")"
assert_eq "case19 phase" "LOOP" "$(sed -nE 's/^- phase:[[:space:]]*//p' "$S19")"

echo "== 20. Projector round-trip byte-identity =="
REPO20="$(init_repo "feature/case20")"
mkdir -p "$REPO20/.supervisor/logs"
echo '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case20"}' > "$REPO20/.supervisor/logs/sid-case20.jsonl"
bash "$PROJECTOR" "sid-case20" "$REPO20" >/dev/null 2>&1
CONTENT20A="$(cat "$REPO20/.supervisor/state.md")"
rm -f "$REPO20/.supervisor/state.md"
bash "$PROJECTOR" "sid-case20" "$REPO20" >/dev/null 2>&1
CONTENT20B="$(cat "$REPO20/.supervisor/state.md")"
assert_eq "case20 round-trip byte-identical ## Session projection" "$CONTENT20A" "$CONTENT20B"

echo "== 21. Projector preserves ## Decisions Log / ## Phase Flags / ## Checkpoint =="
REPO21="$(init_repo "feature/case21")"
mkdir -p "$REPO21/.supervisor/logs"
cat > "$REPO21/.supervisor/state.md" <<'EOF'
# Supervisor State

## Config
- max_workers: 1
- mode: sequential

## Session
- session_id: STALE-OLD-ID
- task_id: old-task
- branch: feature/old-stale-branch
- phase: ACQUIRE
- status: running

## Decisions Log
| # | Phase | Decision | Rationale |
| 1 | ACQUIRE | did a thing | because reasons |

## Phase Flags
- **base_mismatch_detected**: true

## Checkpoint
- last_checkpoint: 2026-07-28T00:00:00Z
- resume_command: /supervisor --continue task: old-task
- completed_phases: [INIT, ACQUIRE]
- current_phase: ACQUIRE
- subtask_progress: 0/1
EOF
DECISIONS_BEFORE="$(sed -n '/^## Decisions Log/,/^## Phase Flags/p' "$REPO21/.supervisor/state.md")"
FLAGS_BEFORE="$(sed -n '/^## Phase Flags/,/^## Checkpoint/p' "$REPO21/.supervisor/state.md")"
CHECKPOINT_BEFORE="$(sed -n '/^## Checkpoint/,$p' "$REPO21/.supervisor/state.md")"
CONFIG_BEFORE="$(sed -n '/^## Config/,/^## Session/p' "$REPO21/.supervisor/state.md")"
echo '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case21"}' > "$REPO21/.supervisor/logs/sid-case21.jsonl"
bash "$PROJECTOR" "sid-case21" "$REPO21" >/dev/null 2>&1
S21="$REPO21/.supervisor/state.md"
DECISIONS_AFTER="$(sed -n '/^## Decisions Log/,/^## Phase Flags/p' "$S21")"
FLAGS_AFTER="$(sed -n '/^## Phase Flags/,/^## Checkpoint/p' "$S21")"
CHECKPOINT_AFTER="$(sed -n '/^## Checkpoint/,$p' "$S21")"
CONFIG_AFTER="$(sed -n '/^## Config/,/^## Session/p' "$S21")"
assert_eq "case21 Decisions Log preserved" "$DECISIONS_BEFORE" "$DECISIONS_AFTER"
assert_eq "case21 Phase Flags preserved" "$FLAGS_BEFORE" "$FLAGS_AFTER"
assert_eq "case21 Checkpoint preserved" "$CHECKPOINT_BEFORE" "$CHECKPOINT_AFTER"
assert_eq "case21 Config preserved (untouched, unrelated section)" "$CONFIG_BEFORE" "$CONFIG_AFTER"
# The ## Session block itself MUST have been replaced (stale id/task_id gone).
if printf '%s' "$(sed -n '/^## Session/,/^## Decisions Log/p' "$S21")" | grep -q "STALE-OLD-ID"; then
  no "case21 stale ## Session content was NOT replaced"
else
  ok "case21 ## Session block was replaced (stale content gone)"
fi
assert_eq "case21 new session_id" "sid-case21" "$(sed -nE 's/^- session_id:[[:space:]]*//p' "$S21")"
assert_eq "case21 new status" "running" "$(sed -nE 's/^- status:[[:space:]]*//p' "$S21")"
# task_id is intentionally NOT re-derived (not in scope's derivation table) —
# confirm it does not survive as a stray field either (whole block replaced).
if printf '%s' "$(sed -n '/^## Session/,/^## Decisions Log/p' "$S21")" | grep -q "^- task_id:"; then
  no "case21 unexpectedly carried forward a non-derived task_id field"
else
  ok "case21 non-derived fields (task_id) not carried forward"
fi

echo "== 22. AC-5: projected state.md (running, matching branch) satisfies hook-dispatch Source 1 =="
REPO22="$(init_repo "feature/example")"
mkdir -p "$REPO22/.supervisor/logs"
echo '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case22"}' > "$REPO22/.supervisor/logs/sid-case22.jsonl"
bash "$PROJECTOR" "sid-case22" "$REPO22" >/dev/null 2>&1
mkdir -p "$REPO22/.supervisor/jobs/in-progress"
printf 'dummy job\n' > "$REPO22/.supervisor/jobs/in-progress/job.md"
DISPATCH_OUT="$( cd "$REPO22" && LOOMWRIGHT_REVIEW_DISPATCH_DRY_RUN=1 \
    LOOMWRIGHT_HOOK_CURRENT_BRANCH="feature/example" \
    bash "$DISPATCH_WRAPPER" < "$PR_FIXTURE" 2>/dev/null )"
DISPATCH_RC=$?
assert_eq "case22 dispatch wrapper exit 0" "0" "$DISPATCH_RC"
MARKER_COUNT22="$(ls -1 "$REPO22/.supervisor/review-dispatch" 2>/dev/null | grep -c . || true)"
assert_eq "case22 exactly one dispatch marker (Source 1 authorized)" "1" "$MARKER_COUNT22"
if printf '%s' "$DISPATCH_OUT" | grep -q 'DRY_RUN_DISPATCH'; then
  ok "case22 DRY_RUN_DISPATCH observed — Source 1 authorized on the projected state.md"
else
  no "case22 no DRY_RUN_DISPATCH observed"
fi

echo "== 22b. AC-5 negative: projected state.md (terminal status) does NOT authorize Source 1 =="
REPO22B="$(init_repo "feature/example")"
mkdir -p "$REPO22B/.supervisor/logs"
{
  echo '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case22b"}'
  echo '{"event":"session_end","type":"session_end","session_id":"sid-case22b","status":"completed"}'
} > "$REPO22B/.supervisor/logs/sid-case22b.jsonl"
bash "$PROJECTOR" "sid-case22b" "$REPO22B" >/dev/null 2>&1
mkdir -p "$REPO22B/.supervisor/jobs/in-progress"
printf 'dummy job\n' > "$REPO22B/.supervisor/jobs/in-progress/job.md"
DISPATCH_OUT_B="$( cd "$REPO22B" && LOOMWRIGHT_REVIEW_DISPATCH_DRY_RUN=1 \
    LOOMWRIGHT_HOOK_CURRENT_BRANCH="feature/example" \
    bash "$DISPATCH_WRAPPER" < "$PR_FIXTURE" 2>/dev/null )"
DISPATCH_RC_B=$?
assert_eq "case22b dispatch wrapper exit 0" "0" "$DISPATCH_RC_B"
MARKER_COUNT22B="$(ls -1 "$REPO22B/.supervisor/review-dispatch" 2>/dev/null | grep -c . || true)"
assert_eq "case22b zero dispatch markers (terminal status correctly fails closed)" "0" "$MARKER_COUNT22B"

echo "== 23. AC-2: committed fixture (loaded via '<' redirection) -> full real field set, no result_block =="
REPO23="$(init_repo "feature/case23")"
BEFORE23="$(logs_snapshot "$REPO23")"
OUT23="$(run_emitter "$REPO23" "$FULL_FIXTURE")"
assert_eq "case23 exit 0" "0" "$(get_rc "$OUT23")"
FIXTURE_SID="fixture-progress-event-full-001"
LOG23="$REPO23/.supervisor/logs/${FIXTURE_SID}.jsonl"
if [ -f "$LOG23" ]; then ok "case23 log file created from committed fixture"; else no "case23 log file missing"; fi
LINES23="$(wc -l < "$LOG23" 2>/dev/null | tr -d '[:space:]')"
assert_eq "case23 exactly one JSONL line" "1" "$LINES23"
LINE23="$(head -1 "$LOG23")"
assert_eq "case23 event" "subtask_complete" "$(printf '%s' "$LINE23" | jq -r '.event')"
assert_eq "case23 session_id" "$FIXTURE_SID" "$(printf '%s' "$LINE23" | jq -r '.session_id')"
assert_eq "case23 cc_session_id retained" "$FIXTURE_SID" "$(printf '%s' "$LINE23" | jq -r '.cc_session_id')"
assert_eq "case23 agent_type copied" "loomwright:worker" "$(printf '%s' "$LINE23" | jq -r '.agent_type')"
assert_eq "case23 agent_id copied" "agent-fixture-full" "$(printf '%s' "$LINE23" | jq -r '.agent_id')"
assert_eq "case23 branch is the repo's session branch" "feature/case23" "$(printf '%s' "$LINE23" | jq -r '.branch // empty')"
TS23="$(printf '%s' "$LINE23" | jq -r '.ts // empty')"
case "$TS23" in
  ""|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ok "case23 ts iso-or-absent" ;;
  *) no "case23 ts invalid: $TS23" ;;
esac
# AC-2's actual claim: no result_block key on the source payload feeds through
# to no result_block-derived field on the emitted event either.
if printf '%s' "$LINE23" | jq -e 'has("result_block")' >/dev/null 2>&1; then
  no "case23 unexpectedly emitted a result_block field"
else
  ok "case23 no result_block field (AC-2)"
fi
# The extra real-world fields (cwd, permission_mode, effort, stop_hook_active,
# background_tasks, session_crons, transcript_path) are NOT documented as
# copied fields — assert they are genuinely ignored, not just coincidentally
# passed through raw.
for undocumented in cwd permission_mode effort stop_hook_active background_tasks session_crons transcript_path; do
  if printf '%s' "$LINE23" | jq -e --arg k "$undocumented" 'has($k)' >/dev/null 2>&1; then
    no "case23 unexpectedly copied undocumented field: $undocumented"
  else
    ok "case23 undocumented field correctly ignored: $undocumented"
  fi
done

echo "== real repo .supervisor/logs untouched =="
assert_eq "real logs snapshot unchanged" "$REAL_BEFORE" "$(snapshot_real)"

echo ""
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
