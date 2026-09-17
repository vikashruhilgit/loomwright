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
#
# EXIT: 0 on full pass, 1 on any failed assertion.

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

CURATED_TOOLS="cat git sed tr python3 mkdir date dirname jq mktemp awk mv rm wc head bash tail stat chmod rmdir touch"
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

echo "== real repo .supervisor/logs untouched =="
assert_eq "real logs snapshot unchanged" "$REAL_BEFORE" "$(snapshot_real)"

echo ""
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
