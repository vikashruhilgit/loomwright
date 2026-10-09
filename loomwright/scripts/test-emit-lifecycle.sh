#!/usr/bin/env bash
# test-emit-lifecycle.sh — self-tests for emit-lifecycle.sh
# (Agent lifecycle ledger — waiting/heartbeat/failed, v15.79.0).
#
# DETERMINISTIC, NO LIVE SIDE EFFECTS. Mirrors test-progress-state.sh's
# conventions: every case runs inside a mktemp sandbox that is a REAL git
# repo (init'd per-case) since the SUT anchors via
# `git worktree list --porcelain`. The real repo's own `.supervisor/logs` is
# snapshotted and asserted untouched.
#
# Cases:
#   1.  empty stdin -> exit 0, no log
#   2.  malformed JSON -> exit 0, no log
#   3.  unknown subcommand -> exit 0, no log
#   4.  missing session_id -> exit 0, no log
#   5.  missing python3 -> exit 0, no log
#   6.  missing jq -> exit 0, no log
#   7.  not-a-git-repo cwd -> exit 0, no log anywhere
#   8.  waiting: PreToolUse[AskUserQuestion] literal reason (ask_user), agent_id present
#   9.  waiting: Notification seam, no agent_id -> agent_scope key ABSENT
#   10. waiting: Notification seam reads notification_type field
#   11. waiting: Notification seam falls back to "unknown" when no candidate field resolves
#   12. failed: reason copied verbatim across all 5 real error values
#   13. failed: missing error key -> reason: unknown
#   14. failed: agent_id present -> agent_scope subagent
#   15. failed: agent_id absent -> agent_scope main (the one grounded fallback)
#   16. heartbeat: debounce bound — N rapid calls for the SAME agent_id yield
#       exactly 1 line within the window
#   17. heartbeat: a call AFTER the debounce window yields a 2nd line
#   18. heartbeat: debounce key is per-agent_id, not per-invocation-context —
#       two DIFFERENT agent_ids are not debounced against each other
#   19. unwritable log dir -> exit 0, no log
#   20. heartbeat: Task-matcher PostToolUse shape (real committed fixture,
#       posttooluse-task-1.json — NO top-level agent_id) derives its debounce
#       key from nested `.tool_response.agentId`, not "main"
#   21. heartbeat: two DIFFERENT real agents (one Bash/Write/Edit-shaped
#       top-level agent_id, one Task-shaped tool_response.agentId) are NOT
#       collapsed into the same shared debounce bucket
#   22. heartbeat: Task-matcher fixture EMITTED ROW carries agent_id/
#       agent_scope sourced from nested tool_response.agentId (not just the
#       debounce marker filename, which case 20 already covers) — reproduces
#       the reviewer-found row-content bug on PR #231
#   23. AC-8g-style population gate: a plain repo with NO pre-existing
#       `.supervisor/` gets NOTHING written (no dir, no debounce marker, no
#       log file) for all three subcommands (waiting/heartbeat/failed) — the
#       claude-review round-4 finding on PR #231 (plugin_present() gate)
#   24. waiting ask_user: the same tool_use_id fed twice (a resumed session's
#       replay) -> exactly ONE row; the Notification seam (no $2) is never
#       de-duplicated even when the payload carries a tool_use_id
#   25. waiting ask_user: two different tool_use_ids -> two rows; no
#       tool_use_id -> every call writes a row
#   26. a first call that wrote NO row (no .supervisor/ yet) does not record
#       the id — the same ask after .supervisor/ exists still writes its row
#   27. the .lifecycle-asked-ids ledger keeps the newest 200 ids; the oldest
#       rolls off and a re-ask of it writes a row again
#   28. REAL HOOK ORDER: notify-desktop.sh THEN emit-lifecycle.sh on the same
#       payload, same cwd, twice -> one notify audit line + one skip, and one
#       row (a ledger shared between the two scripts would drop the row)
#   29. a directory / read-only .lifecycle-asked-ids -> exit 0, the row is
#       still written, and no shell redirect diagnostic reaches stderr
#   30. ended: SubagentStop seam, NON-PLUGIN agent_type (real committed
#       fixture subagentstop-1.json) -> one row, seam subagent_stop, reason stop
#   31. ended: PostToolUse[Task] blocking turn-limit return (pinned probe
#       fixture) -> one row, seam task_return, reason = tool_response.status
#   32. ended: PostToolUse[Task] background LAUNCH (async_launched) -> NO row
#   33. ended: no agent_id resolvable -> NO row (never an unjoinable terminal row)
#
# EXIT: 0 on full pass, 1 on any failed assertion.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EMITTER="$SCRIPT_DIR/emit-lifecycle.sh"

if [ ! -e "$EMITTER" ]; then
  echo "FATAL  required file not found: $EMITTER" >&2
  exit 1
fi
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
CLEANUP_DIRS=()
cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [ -n "$d" ] || continue
    chmod -R u+rwx "$d" 2>/dev/null || true
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# init_repo [branch] [with_supervisor:0|1] — with_supervisor=1 pre-creates an
# EMPTY `.supervisor/` dir so the plugin_present() gate (see emit-lifecycle.sh
# and worktree-audit.sh's identically-named gate) is satisfied — a repo where
# Loomwright has "already run" for the purposes of this suite. Omitted/0
# leaves the repo bare, the AC-8g-style negative-assertion shape (case 23).
init_repo() {
  local branch="${1:-feature/lifecycle-test}"
  local with_supervisor="${2:-0}"
  local d; d="$(mktemp -d)"
  d="$(cd "$d" && pwd -P)"
  CLEANUP_DIRS+=("$d")
  ( cd "$d" && git init -q . \
      && git config user.email test@example.com \
      && git config user.name test \
      && echo seed > seed.txt \
      && git add seed.txt \
      && git commit -qm init \
      && git branch -M "$branch" ) >/dev/null 2>&1
  if [ "$with_supervisor" = "1" ]; then
    mkdir -p "$d/.supervisor"
  fi
  printf '%s' "$d"
}

# grep: the ask_user ledger membership check. uname/find/cksum: notify-desktop.sh,
# which case 28 runs in the same curated PATH (the real hook order).
CURATED_TOOLS="cat git sed tr python3 mkdir date dirname jq mktemp awk mv rm wc head bash tail stat chmod rmdir touch grep uname find cksum"
build_curated_path() {
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

# run_lifecycle <workdir> <payload-file-or--empty> <subcommand> [extra_arg] [exclude tools]
run_lifecycle() {
  local wd="$1" payload="$2" sub="$3" extra="${4:-}" exclude="${5:-}"
  local path; path="$(build_curated_path "$exclude")"
  local out rc
  if [ "$payload" = "--empty" ]; then
    out="$( cd "$wd" && PATH="$path" "$REALBASH" "$EMITTER" "$sub" "$extra" </dev/null 2>&1 )"
  else
    out="$( cd "$wd" && PATH="$path" "$REALBASH" "$EMITTER" "$sub" "$extra" < "$payload" 2>&1 )"
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

PAYLOAD_DIR="$(mktemp -d)"
CLEANUP_DIRS+=("$PAYLOAD_DIR")

echo "== 1. empty stdin -> exit 0, no log =="
REPO1="$(init_repo)"
BEFORE1="$(logs_snapshot "$REPO1")"
OUT1="$(run_lifecycle "$REPO1" --empty waiting ask_user)"
assert_eq "case1 exit 0" "0" "$(get_rc "$OUT1")"
assert_eq "case1 no new log files" "$BEFORE1" "$(logs_snapshot "$REPO1")"

echo "== 2. malformed JSON -> exit 0, no log =="
REPO2="$(init_repo)"
BAD2="$PAYLOAD_DIR/bad2.json"
printf 'not { valid json' > "$BAD2"
BEFORE2="$(logs_snapshot "$REPO2")"
OUT2="$(run_lifecycle "$REPO2" "$BAD2" waiting ask_user)"
assert_eq "case2 exit 0" "0" "$(get_rc "$OUT2")"
assert_eq "case2 no new log files" "$BEFORE2" "$(logs_snapshot "$REPO2")"

echo "== 3. unknown subcommand -> exit 0, no log =="
REPO3="$(init_repo)"
P3="$PAYLOAD_DIR/p3.json"
jq -n '{session_id:"sid-case3", agent_id:"a3"}' > "$P3"
BEFORE3="$(logs_snapshot "$REPO3")"
OUT3="$(run_lifecycle "$REPO3" "$P3" bogus)"
assert_eq "case3 exit 0" "0" "$(get_rc "$OUT3")"
assert_eq "case3 no new log files" "$BEFORE3" "$(logs_snapshot "$REPO3")"

echo "== 4. missing session_id -> exit 0, no log =="
REPO4="$(init_repo)"
P4="$PAYLOAD_DIR/p4.json"
jq -n '{agent_id:"a4"}' > "$P4"
BEFORE4="$(logs_snapshot "$REPO4")"
OUT4="$(run_lifecycle "$REPO4" "$P4" waiting ask_user)"
assert_eq "case4 exit 0" "0" "$(get_rc "$OUT4")"
assert_eq "case4 no new log files" "$BEFORE4" "$(logs_snapshot "$REPO4")"

echo "== 5. missing python3 -> exit 0, no log =="
REPO5="$(init_repo)"
P5="$PAYLOAD_DIR/p5.json"
jq -n '{session_id:"sid-case5", agent_id:"a5"}' > "$P5"
BEFORE5="$(logs_snapshot "$REPO5")"
OUT5="$(run_lifecycle "$REPO5" "$P5" waiting ask_user "python3")"
assert_eq "case5 exit 0" "0" "$(get_rc "$OUT5")"
assert_eq "case5 no new log files (python3 absent)" "$BEFORE5" "$(logs_snapshot "$REPO5")"

echo "== 6. missing jq -> exit 0, no log =="
REPO6="$(init_repo)"
P6="$PAYLOAD_DIR/p6.json"
jq -n '{session_id:"sid-case6", agent_id:"a6"}' > "$P6"
BEFORE6="$(logs_snapshot "$REPO6")"
OUT6="$(run_lifecycle "$REPO6" "$P6" waiting ask_user "jq")"
assert_eq "case6 exit 0" "0" "$(get_rc "$OUT6")"
assert_eq "case6 no new log files (jq absent)" "$BEFORE6" "$(logs_snapshot "$REPO6")"

echo "== 7. not-a-git-repo cwd -> exit 0, no log anywhere =="
NOGIT7="$(mktemp -d)"
CLEANUP_DIRS+=("$NOGIT7")
P7="$PAYLOAD_DIR/p7.json"
jq -n '{session_id:"sid-case7", agent_id:"a7"}' > "$P7"
OUT7="$(run_lifecycle "$NOGIT7" "$P7" waiting ask_user)"
assert_eq "case7 exit 0" "0" "$(get_rc "$OUT7")"
if [ -d "$NOGIT7/.supervisor" ]; then
  no "case7 unexpectedly created .supervisor/ in a non-git cwd"
else
  ok "case7 no .supervisor/ created in a non-git cwd"
fi

echo "== 8. waiting: PreToolUse[AskUserQuestion] literal reason, agent_id present =="
REPO8="$(init_repo "" 1)"
P8="$PAYLOAD_DIR/p8.json"
jq -n '{session_id:"sid-case8", agent_id:"a8", agent_type:"loomwright:worker"}' > "$P8"
OUT8="$(run_lifecycle "$REPO8" "$P8" waiting ask_user)"
assert_eq "case8 exit 0" "0" "$(get_rc "$OUT8")"
LOG8="$REPO8/.supervisor/logs/sid-case8.jsonl"
[ -f "$LOG8" ] && ok "case8 log written" || no "case8 log missing"
LINE8="$(head -1 "$LOG8" 2>/dev/null)"
assert_eq "case8 event" "agent_lifecycle" "$(printf '%s' "$LINE8" | jq -r '.event')"
assert_eq "case8 state" "waiting" "$(printf '%s' "$LINE8" | jq -r '.state')"
assert_eq "case8 reason" "ask_user" "$(printf '%s' "$LINE8" | jq -r '.reason')"
assert_eq "case8 agent_id" "a8" "$(printf '%s' "$LINE8" | jq -r '.agent_id')"
assert_eq "case8 agent_scope" "subagent" "$(printf '%s' "$LINE8" | jq -r '.agent_scope')"
assert_eq "case8 agent_type" "loomwright:worker" "$(printf '%s' "$LINE8" | jq -r '.agent_type')"

echo "== 9. waiting: Notification seam, no agent_id -> agent_scope key ABSENT =="
REPO9="$(init_repo "" 1)"
P9="$PAYLOAD_DIR/p9.json"
jq -n '{session_id:"sid-case9", notification_type:"permission_prompt"}' > "$P9"
OUT9="$(run_lifecycle "$REPO9" "$P9" waiting)"
assert_eq "case9 exit 0" "0" "$(get_rc "$OUT9")"
LINE9="$(head -1 "$REPO9/.supervisor/logs/sid-case9.jsonl" 2>/dev/null)"
assert_eq "case9 reason" "permission_prompt" "$(printf '%s' "$LINE9" | jq -r '.reason')"
assert_eq "case9 agent_scope key ABSENT (never guessed)" "false" "$(printf '%s' "$LINE9" | jq -r 'has("agent_scope")')"
assert_eq "case9 agent_id key ABSENT" "false" "$(printf '%s' "$LINE9" | jq -r 'has("agent_id")')"

echo "== 10. waiting: Notification seam reads notification_type field =="
REPO10="$(init_repo "" 1)"
P10="$PAYLOAD_DIR/p10.json"
jq -n '{session_id:"sid-case10", notification_type:"idle_prompt", type:"should-not-win"}' > "$P10"
OUT10="$(run_lifecycle "$REPO10" "$P10" waiting)"
assert_eq "case10 exit 0" "0" "$(get_rc "$OUT10")"
LINE10="$(head -1 "$REPO10/.supervisor/logs/sid-case10.jsonl" 2>/dev/null)"
assert_eq "case10 notification_type wins over type" "idle_prompt" "$(printf '%s' "$LINE10" | jq -r '.reason')"

echo "== 11. waiting: Notification seam falls back to unknown =="
REPO11="$(init_repo "" 1)"
P11="$PAYLOAD_DIR/p11.json"
jq -n '{session_id:"sid-case11"}' > "$P11"
OUT11="$(run_lifecycle "$REPO11" "$P11" waiting)"
assert_eq "case11 exit 0" "0" "$(get_rc "$OUT11")"
LINE11="$(head -1 "$REPO11/.supervisor/logs/sid-case11.jsonl" 2>/dev/null)"
assert_eq "case11 reason falls back to unknown" "unknown" "$(printf '%s' "$LINE11" | jq -r '.reason')"

echo "== 12. failed: reason copied verbatim across all 5 real error values =="
for err in rate_limit server_error authentication_failed model_not_found unknown; do
  REPOX="$(init_repo "" 1)"
  PX="$PAYLOAD_DIR/p-err-$err.json"
  jq -n --arg e "$err" '{session_id: ("sid-err-" + $e), agent_id:"aerr", error: $e}' > "$PX"
  OUTX="$(run_lifecycle "$REPOX" "$PX" failed)"
  assert_eq "case12($err) exit 0" "0" "$(get_rc "$OUTX")"
  LINEX="$(head -1 "$REPOX/.supervisor/logs/sid-err-$err.jsonl" 2>/dev/null)"
  assert_eq "case12($err) reason copied verbatim" "$err" "$(printf '%s' "$LINEX" | jq -r '.reason')"
done

echo "== 13. failed: missing error key -> reason: unknown =="
REPO13="$(init_repo "" 1)"
P13="$PAYLOAD_DIR/p13.json"
jq -n '{session_id:"sid-case13", agent_id:"a13"}' > "$P13"
OUT13="$(run_lifecycle "$REPO13" "$P13" failed)"
assert_eq "case13 exit 0" "0" "$(get_rc "$OUT13")"
LINE13="$(head -1 "$REPO13/.supervisor/logs/sid-case13.jsonl" 2>/dev/null)"
assert_eq "case13 reason unknown (no error key)" "unknown" "$(printf '%s' "$LINE13" | jq -r '.reason')"

echo "== 14. failed: agent_id present -> agent_scope subagent =="
REPO14="$(init_repo "" 1)"
P14="$PAYLOAD_DIR/p14.json"
jq -n '{session_id:"sid-case14", agent_id:"a14", error:"rate_limit"}' > "$P14"
OUT14="$(run_lifecycle "$REPO14" "$P14" failed)"
assert_eq "case14 exit 0" "0" "$(get_rc "$OUT14")"
LINE14="$(head -1 "$REPO14/.supervisor/logs/sid-case14.jsonl" 2>/dev/null)"
assert_eq "case14 agent_scope subagent" "subagent" "$(printf '%s' "$LINE14" | jq -r '.agent_scope')"

echo "== 15. failed: agent_id absent -> agent_scope main (the one grounded fallback) =="
REPO15="$(init_repo "" 1)"
P15="$PAYLOAD_DIR/p15.json"
jq -n '{session_id:"sid-case15", error:"server_error"}' > "$P15"
OUT15="$(run_lifecycle "$REPO15" "$P15" failed)"
assert_eq "case15 exit 0" "0" "$(get_rc "$OUT15")"
LINE15="$(head -1 "$REPO15/.supervisor/logs/sid-case15.jsonl" 2>/dev/null)"
assert_eq "case15 agent_scope main (grounded fallback, unlike waiting/heartbeat)" "main" "$(printf '%s' "$LINE15" | jq -r '.agent_scope')"

echo "== 16. heartbeat: debounce bound — N rapid calls yield exactly 1 line =="
REPO16="$(init_repo "" 1)"
P16="$PAYLOAD_DIR/p16.json"
jq -n '{session_id:"sid-case16", agent_id:"a16"}' > "$P16"
i=1
while [ "$i" -le 20 ]; do
  run_lifecycle "$REPO16" "$P16" heartbeat >/dev/null
  i=$((i + 1))
done
LOG16="$REPO16/.supervisor/logs/sid-case16.jsonl"
LINES16="$( [ -f "$LOG16" ] && wc -l < "$LOG16" | tr -d '[:space:]' || echo 0)"
assert_eq "case16 20 rapid heartbeat calls yield exactly 1 line" "1" "$LINES16"

echo "== 17. heartbeat: a call AFTER the debounce window yields a 2nd line =="
# Backdate the debounce marker file beyond the (default 60s) window rather than
# sleeping in the test — deterministic and fast.
DEBOUNCE_FILE16="$REPO16/.supervisor/logs/.lifecycle-heartbeat-debounce-a16"
if [ -f "$DEBOUNCE_FILE16" ]; then
  OLD_EPOCH="$(( $(date +%s) - 120 ))"
  printf '%s' "$OLD_EPOCH" > "$DEBOUNCE_FILE16"
  run_lifecycle "$REPO16" "$P16" heartbeat >/dev/null
  LINES17="$(wc -l < "$LOG16" 2>/dev/null | tr -d '[:space:]')"
  assert_eq "case17 a call after the window yields a 2nd line" "2" "$LINES17"
else
  no "case17 debounce marker file missing — cannot backdate"
fi

echo "== 18. heartbeat: debounce key is per-agent_id, not global =="
REPO18="$(init_repo "" 1)"
P18A="$PAYLOAD_DIR/p18a.json"; P18B="$PAYLOAD_DIR/p18b.json"
jq -n '{session_id:"sid-case18", agent_id:"a18-first"}' > "$P18A"
jq -n '{session_id:"sid-case18", agent_id:"a18-second"}' > "$P18B"
run_lifecycle "$REPO18" "$P18A" heartbeat >/dev/null
run_lifecycle "$REPO18" "$P18B" heartbeat >/dev/null
LOG18="$REPO18/.supervisor/logs/sid-case18.jsonl"
LINES18="$( [ -f "$LOG18" ] && wc -l < "$LOG18" | tr -d '[:space:]' || echo 0)"
assert_eq "case18 two DIFFERENT agent_ids are not debounced against each other" "2" "$LINES18"

echo "== 19. unwritable log dir -> exit 0, no log =="
REPO19="$(init_repo)"
mkdir -p "$REPO19/.supervisor"
chmod 555 "$REPO19/.supervisor"
P19="$PAYLOAD_DIR/p19.json"
jq -n '{session_id:"sid-case19", agent_id:"a19", error:"rate_limit"}' > "$P19"
OUT19="$(run_lifecycle "$REPO19" "$P19" failed)"
RC19="$(get_rc "$OUT19")"
chmod 755 "$REPO19/.supervisor"
assert_eq "case19 exit 0" "0" "$RC19"
if [ -f "$REPO19/.supervisor/logs/sid-case19.jsonl" ]; then
  no "case19 unexpectedly wrote a log despite unwritable dir"
else
  ok "case19 no log written (unwritable log dir)"
fi

echo "== 20. heartbeat: Task-matcher fixture shape derives debounce key from tool_response.agentId =="
FIXTURE_TASK="$SCRIPT_DIR/progress-event-fixtures/spawn-probe-2026-09-02/posttooluse-task-1.json"
REPO20="$(init_repo "" 1)"
if [ ! -f "$FIXTURE_TASK" ]; then
  no "case20 fixture file not found: $FIXTURE_TASK"
else
  OUT20="$(run_lifecycle "$REPO20" "$FIXTURE_TASK" heartbeat)"
  assert_eq "case20 exit 0" "0" "$(get_rc "$OUT20")"
  DEBOUNCE_FILE20="$REPO20/.supervisor/logs/.lifecycle-heartbeat-debounce-a665151ef7efc0b49"
  if [ -f "$DEBOUNCE_FILE20" ]; then
    ok "case20 debounce key derived from nested tool_response.agentId (a665151ef7efc0b49)"
  else
    no "case20 debounce marker not keyed by tool_response.agentId (expected $DEBOUNCE_FILE20)"
  fi
  MAIN_DEBOUNCE20="$REPO20/.supervisor/logs/.lifecycle-heartbeat-debounce-main"
  if [ -f "$MAIN_DEBOUNCE20" ]; then
    no "case20 debounce key incorrectly fell back to shared 'main' bucket despite tool_response.agentId being present (no top-level agent_id on this fixture)"
  else
    ok "case20 did not fall back to the shared 'main' bucket"
  fi
fi

echo "== 21. heartbeat: two DIFFERENT real Task-spawned agents are not collapsed into one shared 'main' debounce bucket =="
REPO21="$(init_repo "" 1)"
if [ ! -f "$FIXTURE_TASK" ]; then
  no "case21 fixture file not found: $FIXTURE_TASK"
else
  P21_OTHER="$PAYLOAD_DIR/p21-other.json"
  # A SECOND Task-matcher PostToolUse shape (same session, different real
  # spawned agent) — no top-level agent_id, per this matcher's actual shape.
  # This is the reviewer-reproduced bug: BEFORE the fix, both this payload and
  # the committed fixture fall back to the shared "main" key (neither has a
  # top-level agent_id) and collide into ONE debounce bucket even though they
  # are two genuinely different agents. AFTER the fix, each derives its own
  # key from its own nested tool_response.agentId.
  jq -n '{session_id:"fixture-spawn-probe-session-0001", hook_event_name:"PostToolUse", tool_name:"Agent", tool_response:{agentId:"b21-different-real-agent", status:"completed"}}' > "$P21_OTHER"
  run_lifecycle "$REPO21" "$FIXTURE_TASK" heartbeat >/dev/null
  run_lifecycle "$REPO21" "$P21_OTHER" heartbeat >/dev/null
  LOG21="$REPO21/.supervisor/logs/fixture-spawn-probe-session-0001.jsonl"
  LINES21="$( [ -f "$LOG21" ] && wc -l < "$LOG21" | tr -d '[:space:]' || echo 0)"
  assert_eq "case21 two different real Task-spawned agents each yield their own heartbeat line (not collapsed into one shared 'main' bucket)" "2" "$LINES21"
fi

echo "== 22. heartbeat: Task-matcher fixture EMITTED ROW carries agent_id/agent_scope =="
REPO22="$(init_repo "" 1)"
if [ ! -f "$FIXTURE_TASK" ]; then
  no "case22 fixture file not found: $FIXTURE_TASK"
else
  OUT22="$(run_lifecycle "$REPO22" "$FIXTURE_TASK" heartbeat)"
  assert_eq "case22 exit 0" "0" "$(get_rc "$OUT22")"
  LOG22="$REPO22/.supervisor/logs/fixture-spawn-probe-session-0001.jsonl"
  if [ -f "$LOG22" ]; then
    ok "case22 log written"
  else
    no "case22 log missing"
  fi
  LINE22="$(head -1 "$LOG22" 2>/dev/null)"
  assert_eq "case22 agent_id sourced from nested tool_response.agentId" "a665151ef7efc0b49" "$(printf '%s' "$LINE22" | jq -r '.agent_id')"
  assert_eq "case22 agent_scope subagent" "subagent" "$(printf '%s' "$LINE22" | jq -r '.agent_scope')"
fi

echo "== 23. population gate: a plain repo with NO .supervisor/ gets NOTHING written (waiting/heartbeat/failed) =="
REPO23="$(init_repo)"
[ ! -d "$REPO23/.supervisor" ] && ok "case23 precondition: repo has no .supervisor/" || no "case23 precondition failed"

P23W="$PAYLOAD_DIR/p23-waiting.json"
jq -n '{session_id:"sid-case23-waiting", agent_id:"a23"}' > "$P23W"
OUT23W="$(run_lifecycle "$REPO23" "$P23W" waiting ask_user)"
assert_eq "case23 waiting exits 0 without .supervisor/" "0" "$(get_rc "$OUT23W")"
[ ! -e "$REPO23/.supervisor" ] && ok "case23 waiting created no .supervisor/" || no "case23 waiting created .supervisor/: $(find "$REPO23/.supervisor" 2>/dev/null | tr '\n' ' ')"

P23H="$PAYLOAD_DIR/p23-heartbeat.json"
jq -n '{session_id:"sid-case23-heartbeat", agent_id:"a23"}' > "$P23H"
OUT23H="$(run_lifecycle "$REPO23" "$P23H" heartbeat)"
assert_eq "case23 heartbeat exits 0 without .supervisor/" "0" "$(get_rc "$OUT23H")"
[ ! -e "$REPO23/.supervisor" ] && ok "case23 heartbeat created no .supervisor/ (nor a debounce marker)" || no "case23 heartbeat created .supervisor/: $(find "$REPO23/.supervisor" 2>/dev/null | tr '\n' ' ')"

P23F="$PAYLOAD_DIR/p23-failed.json"
jq -n '{session_id:"sid-case23-failed", agent_id:"a23", error:"rate_limit"}' > "$P23F"
OUT23F="$(run_lifecycle "$REPO23" "$P23F" failed)"
assert_eq "case23 failed exits 0 without .supervisor/" "0" "$(get_rc "$OUT23F")"
[ ! -e "$REPO23/.supervisor" ] && ok "case23 failed created no .supervisor/" || no "case23 failed created .supervisor/: $(find "$REPO23/.supervisor" 2>/dev/null | tr '\n' ' ')"

# POSITIVE CONTROL: the identical waiting payload against a repo where
# .supervisor/ already exists DOES write a line — proves silence above is the
# gate, not some other unrelated breakage.
REPO23B="$(init_repo "" 1)"
OUT23B="$(run_lifecycle "$REPO23B" "$P23W" waiting ask_user)"
assert_eq "case23 POSITIVE CONTROL exits 0" "0" "$(get_rc "$OUT23B")"
[ -f "$REPO23B/.supervisor/logs/sid-case23-waiting.jsonl" ] && ok "case23 POSITIVE CONTROL: with .supervisor/ present, a line IS written" || no "case23 POSITIVE CONTROL: log missing despite pre-existing .supervisor/"

# count_fixed <fixed-string> <file> — matching line count, 0 when absent. grep -c
# prints "0" and exits 1 on no match, so default the value (never `|| echo 0`).
count_fixed() {
  local n
  n="$(grep -cF -- "$1" "$2" 2>/dev/null)"
  printf '%s' "${n:-0}"
}
ask_rows() { count_fixed '"reason":"ask_user"' "$1"; }

echo "== 24. waiting ask_user: same tool_use_id twice -> exactly one row =="
REPO24="$(init_repo "" 1)"
P24="$PAYLOAD_DIR/p24.json"
jq -n '{session_id:"sid-case24", hook_event_name:"PreToolUse", tool_name:"AskUserQuestion", tool_use_id:"toolu_case24"}' > "$P24"
OUT24A="$(run_lifecycle "$REPO24" "$P24" waiting ask_user)"
OUT24B="$(run_lifecycle "$REPO24" "$P24" waiting ask_user)"
assert_eq "case24 first call exit 0" "0" "$(get_rc "$OUT24A")"
assert_eq "case24 replay exit 0" "0" "$(get_rc "$OUT24B")"
LOG24="$REPO24/.supervisor/logs/sid-case24.jsonl"
assert_eq "case24 same tool_use_id twice -> exactly 1 waiting/ask_user row" "1" "$(ask_rows "$LOG24")"
assert_eq "case24 id recorded in the lifecycle ledger" "1" "$(count_fixed 'toolu_case24' "$REPO24/.supervisor/logs/.lifecycle-asked-ids")"
REPO24N="$(init_repo "" 1)"
P24N="$PAYLOAD_DIR/p24n.json"
jq -n '{session_id:"sid-case24n", notification_type:"idle_prompt", tool_use_id:"toolu_case24n"}' > "$P24N"
run_lifecycle "$REPO24N" "$P24N" waiting >/dev/null
run_lifecycle "$REPO24N" "$P24N" waiting >/dev/null
assert_eq "case24 Notification seam (no \$2) is never de-duplicated" "2" "$(count_fixed '"reason":"idle_prompt"' "$REPO24N/.supervisor/logs/sid-case24n.jsonl")"
[ ! -e "$REPO24N/.supervisor/logs/.lifecycle-asked-ids" ] && ok "case24 Notification seam writes no ledger" || no "case24 Notification seam wrote a ledger"

echo "== 25. waiting ask_user: two ids -> two rows; no id -> every call writes =="
REPO25="$(init_repo "" 1)"
P25A="$PAYLOAD_DIR/p25a.json"; P25B="$PAYLOAD_DIR/p25b.json"; P25C="$PAYLOAD_DIR/p25c.json"
jq -n '{session_id:"sid-case25", tool_use_id:"toolu_case25_a"}' > "$P25A"
jq -n '{session_id:"sid-case25", tool_use_id:"toolu_case25_b"}' > "$P25B"
jq -n '{session_id:"sid-case25"}' > "$P25C"
run_lifecycle "$REPO25" "$P25A" waiting ask_user >/dev/null
run_lifecycle "$REPO25" "$P25B" waiting ask_user >/dev/null
assert_eq "case25 two different tool_use_ids -> 2 rows" "2" "$(ask_rows "$REPO25/.supervisor/logs/sid-case25.jsonl")"
run_lifecycle "$REPO25" "$P25C" waiting ask_user >/dev/null
run_lifecycle "$REPO25" "$P25C" waiting ask_user >/dev/null
assert_eq "case25 no tool_use_id -> both calls write (4 rows total)" "4" "$(ask_rows "$REPO25/.supervisor/logs/sid-case25.jsonl")"

echo "== 26. a no-op first call does not suppress a later legitimate row =="
REPO26="$(init_repo)"
P26="$PAYLOAD_DIR/p26.json"
jq -n '{session_id:"sid-case26", tool_use_id:"toolu_case26"}' > "$P26"
OUT26A="$(run_lifecycle "$REPO26" "$P26" waiting ask_user)"
assert_eq "case26 gated first call exit 0" "0" "$(get_rc "$OUT26A")"
[ ! -e "$REPO26/.supervisor" ] && ok "case26 precondition: gated call wrote nothing" || no "case26 gated call wrote: $(find "$REPO26/.supervisor" 2>/dev/null | tr '\n' ' ')"
mkdir -p "$REPO26/.supervisor"
run_lifecycle "$REPO26" "$P26" waiting ask_user >/dev/null
assert_eq "case26 the same ask after .supervisor/ exists writes its row" "1" "$(ask_rows "$REPO26/.supervisor/logs/sid-case26.jsonl")"

echo "== 27. ledger keeps the newest 200 ids =="
REPO27="$(init_repo "" 1)"
mkdir -p "$REPO27/.supervisor/logs"
IDS27="$REPO27/.supervisor/logs/.lifecycle-asked-ids"
i=0
while [ "$i" -lt 200 ]; do
  printf 'toolu_old_%s\n' "$i" >> "$IDS27"
  i=$((i + 1))
done
P27NEW="$PAYLOAD_DIR/p27new.json"; P27OLD="$PAYLOAD_DIR/p27old.json"
jq -n '{session_id:"sid-case27", tool_use_id:"toolu_new_201"}' > "$P27NEW"
jq -n '{session_id:"sid-case27", tool_use_id:"toolu_old_0"}' > "$P27OLD"
run_lifecycle "$REPO27" "$P27NEW" waiting ask_user >/dev/null
assert_eq "case27 ledger holds at most 200 ids" "200" "$(count_fixed '' "$IDS27")"
OLD0_27="$(grep -cxF 'toolu_old_0' "$IDS27" 2>/dev/null)"
assert_eq "case27 oldest id rolled off" "0" "${OLD0_27:-0}"
assert_eq "case27 newest id recorded" "1" "$(count_fixed 'toolu_new_201' "$IDS27")"
run_lifecycle "$REPO27" "$P27OLD" waiting ask_user >/dev/null
assert_eq "case27 re-ask of the rolled-off id writes a row again (2 rows)" "2" "$(ask_rows "$REPO27/.supervisor/logs/sid-case27.jsonl")"

echo "== 28. real hook order: notify-desktop.sh THEN emit-lifecycle.sh, fed twice =="
# Mirrors hooks.json's PreToolUse[AskUserQuestion] re-fan: both leaves, same
# payload, same cwd (the repo top level). The curated PATH has no notifier, so
# "banner once" is asserted via notify-desktop.sh's `notify` audit line.
NOTIFY_SUT="$SCRIPT_DIR/notify-desktop.sh"
run_hook_order() {
  local wd="$1" payload="$2" path
  path="$(build_curated_path)"
  ( cd "$wd" && PATH="$path" LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 LOOMWRIGHT_NOTIFY_SCOPE=all \
      LOOMWRIGHT_NOTIFY_DEBOUNCE=0 LOOMWRIGHT_NOTIFY_CLICK=off \
      DISPLAY= WAYLAND_DISPLAY= "$REALBASH" "$NOTIFY_SUT" < "$payload" ) >/dev/null 2>&1
  run_lifecycle "$wd" "$payload" waiting ask_user >/dev/null
}
REPO28="$(init_repo "" 1)"
P28="$PAYLOAD_DIR/p28.json"
jq -n '{session_id:"sid-case28", hook_event_name:"PreToolUse", tool_name:"AskUserQuestion", tool_use_id:"toolu_case28", tool_input:{questions:[{question:"Ship it?"}]}}' > "$P28"
run_hook_order "$REPO28" "$P28"
run_hook_order "$REPO28" "$P28"
NLOG28="$REPO28/.supervisor/logs/notifications.log"
assert_eq "case28 banner decided once (1 notify audit line)" "1" "$(count_fixed ' notify group=loomwright-sid-case tool_use_id=toolu_case28' "$NLOG28")"
assert_eq "case28 replay skipped by notify-desktop (1 skip line)" "1" "$(count_fixed 'skip replay tool_use_id=toolu_case28' "$NLOG28")"
assert_eq "case28 exactly 1 waiting/ask_user row (first ask NOT dropped)" "1" "$(ask_rows "$REPO28/.supervisor/logs/sid-case28.jsonl")"

echo "== 29. directory / read-only ask ledger -> exit 0, row written, stderr clean =="
# A command-level `cmd >> F 2>/dev/null` does NOT silence the shell's own
# redirect failure, so a directory/unwritable ledger leaked `line N: …: Is a
# directory` / `Permission denied` to hook stderr. run_lifecycle captures
# stderr (2>&1) into its output, so the diagnostic would show up there. The
# logs dir itself stays writable: the ledger append only runs after the row
# append succeeded, so an unwritable logs dir never reaches the ledger.
no_redirect_diag() {
  if grep -qE 'Is a directory|Permission denied|line [0-9]+:' <<<"$2"; then
    no "$1  output: $(printf '%s' "$2" | tr '\n' ' ')"
  else
    ok "$1"
  fi
}
REPO29="$(init_repo "" 1)"
mkdir -p "$REPO29/.supervisor/logs/.lifecycle-asked-ids"
P29="$PAYLOAD_DIR/p29.json"
jq -n '{session_id:"sid-case29", tool_use_id:"toolu_case29"}' > "$P29"
OUT29="$(run_lifecycle "$REPO29" "$P29" waiting ask_user)"
assert_eq "case29 directory ledger exit 0" "0" "$(get_rc "$OUT29")"
no_redirect_diag "case29 directory ledger -> no redirect diagnostic on stderr" "$OUT29"
assert_eq "case29 directory ledger -> the row is still written" "1" "$(ask_rows "$REPO29/.supervisor/logs/sid-case29.jsonl")"
if [ "$(id -u 2>/dev/null || echo 0)" = "0" ]; then
  echo "  skip: case29 read-only ledger (running as root — mode bits not enforced)"
else
  REPO29R="$(init_repo "" 1)"
  mkdir -p "$REPO29R/.supervisor/logs"
  printf 'toolu_other\n' > "$REPO29R/.supervisor/logs/.lifecycle-asked-ids"
  chmod 444 "$REPO29R/.supervisor/logs/.lifecycle-asked-ids"
  P29R="$PAYLOAD_DIR/p29r.json"
  jq -n '{session_id:"sid-case29r", tool_use_id:"toolu_case29r"}' > "$P29R"
  OUT29R="$(run_lifecycle "$REPO29R" "$P29R" waiting ask_user)"
  chmod 644 "$REPO29R/.supervisor/logs/.lifecycle-asked-ids"
  assert_eq "case29 read-only ledger exit 0" "0" "$(get_rc "$OUT29R")"
  no_redirect_diag "case29 read-only ledger -> no redirect diagnostic on stderr" "$OUT29R"
  assert_eq "case29 read-only ledger -> the row is still written" "1" "$(ask_rows "$REPO29R/.supervisor/logs/sid-case29r.jsonl")"
fi

MAXTURNS_PROBE="$SCRIPT_DIR/fixtures/subagentstop-maxturns-probe.json"
FIXTURE_STOP="$SCRIPT_DIR/progress-event-fixtures/spawn-probe-2026-09-02/subagentstop-1.json"
ended_rows() { jq -c 'select(.event=="agent_lifecycle" and .state=="ended")' "$1" 2>/dev/null; }

echo "== 30. ended: SubagentStop seam, non-plugin agent_type -> one ended row =="
REPO30="$(init_repo "" 1)"
SID30="$(jq -r .session_id "$FIXTURE_STOP")"
OUT30="$(run_lifecycle "$REPO30" "$FIXTURE_STOP" ended)"
assert_eq "case30 exit 0" "0" "$(get_rc "$OUT30")"
ROWS30="$(ended_rows "$REPO30/.supervisor/logs/$SID30.jsonl")"
assert_eq "case30 exactly one ended row" "1" "$(printf '%s\n' "$ROWS30" | grep -c '"ended"')"
assert_eq "case30 agent_id/type from payload, seam+reason" "a8c9742552b5ba8ec|probe-alpha|subagent_stop|stop" \
  "$(printf '%s' "$ROWS30" | jq -r '[.agent_id,.agent_type,.seam,.reason]|join("|")')"

echo "== 31. ended: PostToolUse[Task] blocking turn-limit return -> task_return row =="
REPO32="$(init_repo "" 1)"
P32="$PAYLOAD_DIR/p32.json"
jq '.posttooluse_task_turn_limit_return' "$MAXTURNS_PROBE" > "$P32"
OUT32="$(run_lifecycle "$REPO32" "$P32" ended)"
assert_eq "case32 exit 0" "0" "$(get_rc "$OUT32")"
assert_eq "case32 row from nested tool_response" "a3a900c6391132581|loomwright:loomwright:plan-reviewer|task_return|completed" \
  "$(ended_rows "$REPO32/.supervisor/logs/fixture-maxturns-probe-session-0001.jsonl" | jq -r '[.agent_id,.agent_type,.seam,.reason]|join("|")')"

echo "== 32. ended: PostToolUse[Task] background launch (async_launched) -> no row =="
REPO33="$(init_repo "" 1)"
P33="$PAYLOAD_DIR/p33.json"
jq '.posttooluse_task_background_launch' "$MAXTURNS_PROBE" > "$P33"
run_lifecycle "$REPO33" "$P33" ended >/dev/null
assert_eq "case33 no ended row for a still-running background child" "" \
  "$(ended_rows "$REPO33/.supervisor/logs/fixture-maxturns-probe-session-0001.jsonl")"

echo "== 33. ended: no agent_id -> no row =="
REPO34="$(init_repo "" 1)"
P34="$PAYLOAD_DIR/p34.json"
jq -n '{session_id:"sid-case34", hook_event_name:"SubagentStop"}' > "$P34"
run_lifecycle "$REPO34" "$P34" ended >/dev/null
assert_eq "case34 no row without an agent_id" "" "$(ended_rows "$REPO34/.supervisor/logs/sid-case34.jsonl")"

echo "== real repo .supervisor/logs untouched =="
assert_eq "real logs snapshot unchanged" "$REAL_BEFORE" "$(snapshot_real)"

echo ""
echo "== 40. answered (iq02 T04 3a): question answered -> working/answered row paired by tool_use_id =="
REPO40="$(init_repo "" 1)"
P40A="$PAYLOAD_DIR/p40a.json"; P40B="$PAYLOAD_DIR/p40b.json"
jq -n '{session_id:"sid-case40", tool_use_id:"toolu_case40"}' > "$P40A"
jq -n '{session_id:"sid-case40", tool_use_id:"toolu_case40"}' > "$P40B"
OUT40W="$(run_lifecycle "$REPO40" "$P40A" waiting ask_user)"
OUT40A="$(run_lifecycle "$REPO40" "$P40B" answered)"
OUT40R="$(run_lifecycle "$REPO40" "$P40B" answered)"
LOG40="$REPO40/.supervisor/logs/sid-case40.jsonl"
assert_eq "case40 answered exit 0" "0" "$(get_rc "$OUT40A")"
assert_eq "case40 replayed answered exit 0" "0" "$(get_rc "$OUT40R")"
assert_eq "case40 exactly one working/answered row (own ledger de-dups the replay)" "1" \
  "$(jq -c 'select(.event=="agent_lifecycle" and .state=="working" and .reason=="answered")' "$LOG40" 2>/dev/null | grep -c .)"
assert_eq "case40 answered row carries the payload tool_use_id" "toolu_case40" \
  "$(jq -r 'select(.reason=="answered") | .tool_use_id' "$LOG40" 2>/dev/null)"
assert_eq "case40 ask_user waiting row carries the SAME tool_use_id (pairing key)" "toolu_case40" \
  "$(jq -r 'select(.reason=="ask_user") | .tool_use_id' "$LOG40" 2>/dev/null)"
assert_eq "case40 answered uses its OWN ledger, never the ask ledger" "1" \
  "$(count_fixed 'toolu_case40' "$REPO40/.supervisor/logs/.lifecycle-answered-ids")"
assert_eq "case40 ask ledger holds the id once (not touched by answered)" "1" \
  "$(count_fixed 'toolu_case40' "$REPO40/.supervisor/logs/.lifecycle-asked-ids")"
# not debounced: a heartbeat just before must not suppress the answered row
REPO40D="$(init_repo "" 1)"
jq -n '{session_id:"sid-case40d"}' > "$PAYLOAD_DIR/p40hb.json"
jq -n '{session_id:"sid-case40d"}' > "$PAYLOAD_DIR/p40d.json"
run_lifecycle "$REPO40D" "$PAYLOAD_DIR/p40hb.json" heartbeat >/dev/null
run_lifecycle "$REPO40D" "$PAYLOAD_DIR/p40d.json" answered >/dev/null
assert_eq "case40 answered bypasses the heartbeat debounce (id-less payload -> row, no tool_use_id)" "1|null" \
  "$(jq -sr '[.[]|select(.reason=="answered")] | "\(length)|\(.[0].tool_use_id // null)"' "$REPO40D/.supervisor/logs/sid-case40d.jsonl" 2>/dev/null)"
printf 'not json' > "$PAYLOAD_DIR/p40bad.json"
assert_eq "case40 malformed payload -> exit 0" "0" "$(get_rc "$(run_lifecycle "$REPO40" "$PAYLOAD_DIR/p40bad.json" answered)")"
assert_eq "case40 empty payload -> exit 0" "0" "$(get_rc "$(run_lifecycle "$REPO40" --empty answered)")"

echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
