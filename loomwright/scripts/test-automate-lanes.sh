#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-automate-lanes.sh — hermetic self-tests for automate-lanes.sh (parallel-automate/05, lane
# lifecycle). Fixture: a bare fake origin + a "primary" clone of it holding two items and a parent run
# file, all under one mktemp dir. `claude` is a PATH stub that records argv / env / stdin and prints
# stream-json; `gh` is a PATH stub that fails the test if called; meta-sync / setup-memory /
# automate-helpers / machine-load are stubbed through the script's seams. No network, no real claude.
#
# Groups: A create (AC1) · B leftover salvage · C meta pull failure · D hook merge · E init-check (AC12)
#   F launch authority / regime / host denial · G admission (AC10 launch-hold half) · H launch shape
#   I checksum + mutation control (AC16) · J relay hook (AC6) · K lane-answer (AC6) · L .died marker
#   M liveness + pick-guard (AC12) · N lane-remove refusals (AC3) + mutation controls (AC16)
#   O lane-info · P branch-check
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/automate-lanes.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
BG_PIDS=""
cleanup() {
  local p
  for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$(printf '%s' "$2" | head -c 600)]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3]" ;; *) ok "$1" ;; esac; }

export HOME="$T/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_PLUGIN_ROOT

BIN="$T/bin"; mkdir -p "$BIN"
export STUB_LOG="$T/claude.log"; : > "$STUB_LOG"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  if [ -n "${STUB_NO_REGIME:-}" ]; then echo "Usage: claude [options]"; else echo "--permission-prompt-tool --allowedTools --disallowedTools --plugin-dir"; fi
  exit 0
fi
{ printf 'ARGS'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  printf 'ENV CEIL=%s CC=%s PID=%s\n' "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS-unset}" "${CLAUDECODE-unset}" "${CLAUDE_PID-unset}"
  printf 'STDIN %s\n' "$(cat)"; printf 'CWD %s\n' "$PWD"; } >> "$STUB_LOG"
echo '{"type":"system","subtype":"init","session_id":"sess-123"}'
case "${STUB_MODE:-ok}" in
  sleep) trap 'kill $! 2>/dev/null; exit 143' TERM; sleep 60 & wait $! ;;
  defer) printf '%s\n' "$STUB_DEFER_LINE" ;;
  die) exit 1 ;;
  *) echo '{"type":"result","subtype":"success","stop_reason":"end_turn","session_id":"sess-123"}' ;;
esac
EOF
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "${GH_CALLS:-/dev/null}"; exit 1
EOF
export GH_CALLS="$T/gh.calls"
cat > "$T/meta-sync.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
case "$1" in
  pull) [ -n "${STUB_META_FAIL:-}" ] && exit 1; exit 0 ;;
  status) echo "${STUB_META_STATUS:-in_sync}"; exit 0 ;;
esac
EOF
cat > "$T/setup-memory.sh" <<'EOF'
#!/usr/bin/env bash
echo "${STUB_MODE_LINE:-on test-meta}"
EOF
cat > "$T/helpers.sh" <<'EOF'
#!/usr/bin/env bash
echo "helpers $*" >> "$HELPERS_LOG"
EOF
cat > "$T/load.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"load1":1,"cpus":8,"state":"%s"}\n' "${STUB_LOAD:-ok}"
EOF
chmod +x "$BIN/claude" "$BIN/gh" "$T"/*.sh
export PATH="$BIN:$PATH"
export META_LOG="$T/meta.log" HELPERS_LOG="$T/helpers.log"; : > "$META_LOG"; : > "$HELPERS_LOG"
export LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_SETUP_MEMORY="$T/setup-memory.sh"
export LOOMWRIGHT_LANES_HELPERS="$T/helpers.sh" LOOMWRIGHT_MACHINE_LOAD_CMD="$T/load.sh"
export LOOMWRIGHT_LANES_INIT_WAIT_S=5 LOOMWRIGHT_LANES_STOP_GRACE_S=2

# ---- fixture ----------------------------------------------------------------------------------------
ORIGIN="$T/origin.git"; P="$T/work/primary"
git init -q --bare "$ORIGIN"; git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
git init -q "$P"; git -C "$P" checkout -q -b main
printf '.supervisor/*\n.claude/settings.local.json\n' > "$P/.gitignore"
mkdir -p "$P/reqs"; echo "# a" > "$P/reqs/a.md"; echo "# b" > "$P/reqs/b.md"
git -C "$P" add -A; git -C "$P" commit -qm init
git -C "$P" remote add origin "$ORIGIN"; git -C "$P" push -q -u origin main 2>/dev/null
git -C "$P" branch primary-only
PARENT=automate-2026-10-07-120000
mkdir -p "$P/.supervisor/automate"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT" > "$P/.supervisor/automate/$PARENT.md"
printf '{"auto_review": true, "x": [1, 2]}\n' > "$P/.supervisor/config.json"
printf '{"desktop": false}\n' > "$P/.supervisor/notify-config.json"
RF="$P/.supervisor/automate/$PARENT.md"; TABLE="$P/.supervisor/automate/$PARENT.lanes"
LR="$T/work/primary-lanes/$PARENT"
run() { bash "$S" "$@" 2>&1; }
claude_calls() { grep -c '^ARGS' "$STUB_LOG" | tr -d ' '; }
tcol() { awk -F'\t' -v l="$1" -v c="$2" '$1 == l { print $c }' "$TABLE"; }
lane_sum() { (cd "$1" && find . -path ./.git -prune -o -type f -print | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done) | cksum; }
wait_gone() { local i=0; while pgrep -f "_lane-run $1 " >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }

# ---- A: create (AC1) --------------------------------------------------------------------------------
out="$(run lane-create "$RF" reqs/a.md 1 --parallel 2 --max-tokens 1000)"; rc=$?
check "A1 lane-create L1 exits 0" "$rc" 0
has "A1 names the lane path" "$out" "$LR/L1"
out="$(run lane-create "$RF" reqs/b.md 2 --parallel 2 --max-tokens 1000)"; check "A2 lane-create L2 exits 0" "$?" 0
L1="$LR/L1"; L2="$LR/L2"
check "A3 origin is the remote URL, not the primary" "$(git -C "$L1" remote get-url origin)" "$ORIGIN"
hasnt "A4 inherited primary-only ref pruned" "$(git -C "$L1" branch -r)" "primary-only"
check "A5 config.json byte-for-byte" "$(cmp -s "$P/.supervisor/config.json" "$L1/.supervisor/config.json" && echo same)" same
check "A6 notify-config.json byte-for-byte" "$(cmp -s "$P/.supervisor/notify-config.json" "$L2/.supervisor/notify-config.json" && echo same)" same
check "A7 lane.json shape" "$(jq -c '[.schema_version, .lane, .run_id, .parent_run_id, .primary, .parallel, .max_tokens, (.created | test("Z$"))]' "$L1/.supervisor/lane.json")" \
  "[1,\"L1\",\"$PARENT-L1\",\"$PARENT\",\"$P\",2,500,true]"
check "A8 L2 run id" "$(jq -r .run_id "$L2/.supervisor/lane.json")" "$PARENT-L2"
check "A9 one-line backlog naming the canonical path" "$(cat "$L1/.supervisor/lane-backlog.md")" "- [ ] reqs/a.md"
has "A10 meta pull passes --branch explicitly" "$(cat "$META_LOG")" "meta-sync pull --branch test-meta --root $L1"
check "A11 relay hooks installed (PreToolUse + PermissionRequest)" \
  "$(jq -r '[.hooks.PreToolUse[0].matcher, (.hooks.PreToolUse[0].hooks[0].command | test("automate-lanes.sh\" relay-hook$")), .hooks.PermissionRequest[0].matcher] | join(",")' "$L1/.claude/settings.local.json")" \
  "AskUserQuestion,true,AskUserQuestion"
check "A12 lane table rows" "$(awk -F'\t' '!/^#/ { print $1 ":" $4 ":" $8 }' "$TABLE" | tr '\n' ' ')" "L1:$PARENT-L1:created L2:$PARENT-L2:created "
has "A13 lane table records what does not carry" "$(cat "$TABLE")" "not carried into lanes"
check "A14 lane clean after create" "$(git -C "$L1" status --porcelain)" ""
check "A15 lane on the base branch" "$(git -C "$L1" rev-parse --abbrev-ref HEAD)" main
hasnt "A16 no gh call during create" "$(cat "$GH_CALLS" 2>/dev/null)" "gh"

# ---- B: leftover directory salvaged then refused ----------------------------------------------------
mkdir -p "$LR/L9/.supervisor"; echo keep > "$LR/L9/.supervisor/note.txt"
out="$(run lane-create "$RF" reqs/a.md 9)"; rc=$?
check "B1 leftover lane dir refused" "$rc" 1
has "B2 refusal names never reused" "$out" "never reused"
check "B3 leftover salvaged" "$(cat "$LR"/salvage/L9-leftover-*/supervisor/note.txt 2>/dev/null)" keep
check "B4 leftover untouched" "$(cat "$LR/L9/.supervisor/note.txt")" keep
rm -rf "$LR/L9"

# ---- C: meta pull failure aborts and removes the clone ----------------------------------------------
out="$(STUB_META_FAIL=1 run lane-create "$RF" reqs/a.md 8)"; rc=$?
check "C1 meta pull failure exits 1" "$rc" 1
has "C2 names the abort" "$out" "aborted L8"
check "C3 clone removed" "$([ -e "$LR/L8" ] && echo present || echo absent)" absent
out="$(STUB_MODE_LINE='unknown no line' run lane-create "$RF" reqs/a.md 8)"; check "C4 unknown metadata mode fails closed" "$?" 1

# ---- D: hook merge never replaces an existing hooks key ---------------------------------------------
SF="$T/settings.json"
printf '{"model":"x","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"keep-me"}]}],"Stop":[{"hooks":[]}]}}\n' > "$SF"
bash "$S" _merge-hooks "$SF" 'bash "/p/scripts/automate-lanes.sh" relay-hook'
bash "$S" _merge-hooks "$SF" 'bash "/p/scripts/automate-lanes.sh" relay-hook'
check "D1 existing hooks kept, relay entry added once" \
  "$(jq -c '[.model, (.hooks.PreToolUse | length), .hooks.PreToolUse[0].hooks[0].command, (.hooks.Stop | length), (.hooks.PermissionRequest | length)]' "$SF")" \
  '["x",2,"keep-me",1,1]'

# ---- E: init-check (AC12) ---------------------------------------------------------------------------
check "E1 --parallel 2 --auto-merge refused" "$(run init-check --parallel 2 --auto-merge)" "refuse: auto_merge_with_parallel"
run init-check --parallel 2 --auto-merge >/dev/null; check "E2 refusal exits 1" "$?" 1
check "E3 --parallel 1 --auto-merge ok" "$(run init-check --parallel 1 --auto-merge)" ok
check "E4 --parallel 11 out of range" "$(run init-check --parallel 11)" "refuse: parallel_out_of_range"
check "E5 --parallel 0 out of range" "$(run init-check --parallel 0)" "refuse: parallel_out_of_range"
check "E6 --parallel 10 ok" "$(run init-check --parallel 10)" ok

# ---- F: launch authority, regime, host denial (AC Scope 17) -----------------------------------------
SUM_L1_BEFORE="$(lane_sum "$L1")"
n0="$(claude_calls)"
out="$(run lane-launch "$L1")"; rc=$?
check "F1 no owner command ⇒ exit 3" "$rc" 3
check "F2 BLOCKED first line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: BLOCKED — L1 — no owner-invoked command — need the owner"
check "F3 no process started" "$(claude_calls)" "$n0"
check "F4 table blocked_launch" "$(tcol L1 8)" blocked_launch
out="$(STUB_NO_REGIME=1 run lane-launch "$L1" --owner-command '/automate --parallel 2')"; rc=$?
check "F5 no pinnable regime ⇒ exit 3" "$rc" 3
has "F6 regime BLOCKED line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: BLOCKED — L1 — CLI advertises no pinnable permission regime"
out="$(run lane-launch "$L2" --host-denied 'auto-mode denied: Create Unsafe Agents')"; rc=$?
check "F7 host denial ⇒ exit 3" "$rc" 3
check "F8 host denial first line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: BLOCKED — L2 — auto-mode denied: Create Unsafe Agents — need the owner"
check "F9 host denial blocked_launch, L1 row untouched by it" "$(tcol L2 8):$(tcol L1 10)" "blocked_launch:no pinnable permission regime"
check "F10 no process after either refusal" "$(claude_calls)" "$n0"

# ---- G: admission (AC10, launch-hold half) ----------------------------------------------------------
OWN='/automate --parallel 2'
out="$(STUB_LOAD=overloaded run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
check "G1 overloaded ⇒ HELD exit 4" "$rc" 4
check "G2 overloaded first line" "$(printf '%s\n' "$out" | head -1)" "lane-launch: HELD — L1 — load overloaded"
check "G3 held_for_load in table" "$(tcol L1 8)" held_for_load
touch "$P/.supervisor/automate/$PARENT.memory-pressure"
out="$(run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
check "G4 memory trip ⇒ HELD memory_pressure" "$rc:$(printf '%s\n' "$out" | head -1)" "4:lane-launch: HELD — L1 — memory_pressure"
rm -f "$P/.supervisor/automate/$PARENT.memory-pressure"
check "G5 no process while held" "$(claude_calls)" "$n0"
out="$(LOOMWRIGHT_MACHINE_LOAD_CMD="$T/absent-load.sh" CLAUDECODE=1 CLAUDE_PID=4242 run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
check "G6 unknown load admits" "$rc" 0
has "G7 launched line with session id" "$out" "launched L1"
check "G8 one process started" "$(claude_calls)" "$((n0 + 1))"
out="$(STUB_LOAD=busy run lane-launch "$L2" --owner-command "$OWN")"; rc=$?
check "G9 busy + a launch within the recheck ⇒ HELD" "$rc:$(printf '%s\n' "$out" | head -1)" "4:lane-launch: HELD — L2 — load busy"
out="$(STUB_LOAD=busy LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L2" --owner-command "$OWN")"; rc=$?
check "G10 busy past the recheck ⇒ launches (one per interval)" "$rc" 0
wait_gone "$L1"; wait_gone "$L2"

# ---- H: launch shape ----------------------------------------------------------------------------------
first="$(grep '^ARGS' "$STUB_LOG" | sed -n "$((n0 + 1))p")"
for f in "[-p]" "[--input-format] [stream-json]" "[--output-format] [stream-json]" "[--permission-prompt-tool] [stdio]" \
         "[--permission-mode] [acceptEdits]" "[--allowedTools] [Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion]" \
         "[--plugin-dir] [$(cd "$HERE/.." && pwd)]" "[--append-system-prompt] [You are running as a HEADLESS lane"; do
  has "H1 flag $f" "$first" "$f"
done
has "H2 disallow carries the merge command" "$first" "Bash(gh pr merge:*)"
has "H3 disallow carries force push" "$first" "Bash(git push --force:*)"
has "H4 disallow carries a push to the base branch" "$first" "Bash(git push origin main:*)"
hasnt "H5 no non-interactive fallback flag" "$first" "non-interactive"
has "H6 env: ceiling 0, CLAUDECODE and CLAUDE_PID unset" "$(grep '^ENV' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "CEIL=0 CC=unset PID=unset"
has "H7 prompt = namespaced backlog command" "$(grep '^STDIN' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "/loomwright:automate --backlog $L1/.supervisor/lane-backlog.md"
check "H8 runs inside the lane" "$(grep '^CWD' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "CWD $L1"
check "H9 session id from system/init recorded" "$(tcol L1 7)" sess-123
case "$(tcol L1 5)" in [0-9]*) ok "H10 pid recorded" ;; *) bad "H10 pid recorded" ;; esac
[ -n "$(tcol L1 6)" ] && [ "$(tcol L1 6)" != "-" ] && ok "H11 pid start time recorded" || bad "H11 pid start time recorded"
check "H12 stream log outside the lane" "$(grep -c 'sess-123' "$LR/L1.stream.log" | tr -d ' ')" 2
out="$(run lane-launch "$L1" --owner-command "$OWN" --resume-run "$PARENT-L2")"; check "H13 resume of another lane's run refused" "$?" 1
mkdir -p "$L1/.supervisor/automate"; printf '# Automate Run: %s-L1 — reqs/a.md\n' "$PARENT" > "$L1/.supervisor/automate/$PARENT-L1.md"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "/automate --resume $PARENT" --resume-run "$PARENT-L1")"
has "H14 resume by run id" "$(grep '^STDIN' "$STUB_LOG" | tail -1)" "/loomwright:automate --resume $PARENT-L1"
wait_gone "$L1"
rm -f "$L1/.supervisor/automate/$PARENT-L1.md"

# ---- I: coordinator never writes into a launched lane (checksum) + mutation control ------------------
check "I1 lane checksum unchanged across launches" "$(lane_sum "$L1")" "$SUM_L1_BEFORE"
MUT="$T/mut"; mkdir -p "$MUT"
awk '{ print } /# >>> spawn/ { print "  touch \"$LN_DIR/.coordinator-write\"" }' "$S" > "$MUT/automate-lanes.sh"
LOOMWRIGHT_LANE_RECHECK_S=0 bash "$MUT/automate-lanes.sh" lane-launch "$L1" --owner-command "$OWN" >/dev/null 2>&1
wait_gone "$L1"
if [ "$(lane_sum "$L1")" != "$SUM_L1_BEFORE" ]; then ok "I2 mutation (coordinator write after launch) fails the checksum"; else bad "I2 mutation control did not trip"; fi
rm -f "$L1/.coordinator-write"

# ---- J: relay hook (AC6) ----------------------------------------------------------------------------
Q2='[{"question":"Which color?","header":"Color","multiSelect":false,"options":[{"label":"Red","description":"r"},{"label":"Blue","description":"b"}]},{"question":"Which extras?","header":"Extras","multiSelect":true,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"},{"label":"C","description":"c"}]}]'
hook_in() { jq -n -c --arg ev "$1" --arg cwd "$2" --arg id "$3" --argjson q "$Q2" '{hook_event_name: $ev, cwd: $cwd, tool_use_id: $id, tool_name: "AskUserQuestion", tool_input: {questions: $q}}'; }
out="$(hook_in PermissionRequest "$L2" toolu_q1 | bash "$S" relay-hook)"
check "J1 bundled call denied" "$(jq -r '.hookSpecificOutput.decision.behavior' <<<"$out")" deny
out="$(hook_in PreToolUse "$L2" toolu_q1 | bash "$S" relay-hook)"
check "J2 unanswered question ⇒ defer" "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")" defer
QF="$L2/.supervisor/inbox/questions/toolu_q1.json"
check "J3 question file with asked_at" "$(jq -r '[.id, (.asked_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*Z$")), (.questions | length)] | map(tostring) | join(",")' "$QF")" "toolu_q1,true,2"
check "J4 outside a lane ⇒ no decision" "$(hook_in PreToolUse "$T" toolu_q9 | bash "$S" relay-hook)" "{}"
check "J5 path-unsafe id ignored" "$(hook_in PreToolUse "$L2" '../x' | bash "$S" relay-hook)" "{}"

# ---- K: lane-answer (AC6) ---------------------------------------------------------------------------
export STUB_DEFER_LINE="$(jq -n -c --argjson q "$Q2" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-123", deferred_tool_use: {id: "toolu_q1", name: "AskUserQuestion", input: {questions: $q}}}')"
STUB_MODE=defer LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L2" --owner-command "$OWN" >/dev/null; wait_gone "$L2"
AF="$L2/.supervisor/inbox/answers/toolu_q1.json"
ans() { printf '%s' "$1" | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$L2" toolu_q1 "${@:2}" 2>&1; }
out="$(ans '{"answers":{"0":"Green","1":"A"}}' --owner-command "$OWN")"; rc=$?
check "K1 unknown label refused" "$rc" 1; has "K1b names the bad label" "$out" '"Green" is not one of its options'
out="$(ans '{"note":"just do whatever"}' --owner-command "$OWN")"; check "K2 free-text-only refused" "$?" 1
out="$(ans '{"answers":{"0":"Red","1":"A,Z"}}' --owner-command "$OWN")"; check "K3 one unknown multiSelect label refuses all" "$?" 1
out="$(ans '{"answers":{"0":"Red"}}' --owner-command "$OWN")"; check "K4 missing an answer refused" "$?" 1
out="$(ans '{"answers":{"0":"Red","1":"A,B"}}')"; rc=$?
check "K5 answer without owner command ⇒ BLOCKED exit 3" "$rc" 3
check "K6 nothing recorded when blocked" "$([ -e "$AF" ] && echo written || echo none)" none
n1="$(claude_calls)"
out="$(ans '{"answers":{"0":"Red","1":"A,B"},"note":"prefer the small diff"}' --owner-command "$OWN" --via test)"; rc=$?
check "K7 valid multiSelect answer accepted" "$rc" 0
has "K8 reports the note as delivered" "$out" "note recorded and delivered"
check "K9 answer file" "$(jq -c '[.answers["Which color?"], .answers["Which extras?"], .note, .source, .via]' "$AF")" '["Red","A,B","prefer the small diff","human","test"]'
check "K10 resumed once" "$(claude_calls)" "$((n1 + 1))"
lastargs="$(grep '^ARGS' "$STUB_LOG" | tail -1)"
has "K11 resume carries --resume <session>" "$lastargs" "[--resume] [sess-123]"
has "K12 resume keeps the permission host" "$lastargs" "[--permission-prompt-tool] [stdio]"
has "K13 resume keeps the headless-lane prompt" "$lastargs" "[--append-system-prompt]"
has "K14 resume env ceiling 0" "$(grep '^ENV' "$STUB_LOG" | tail -1)" "CEIL=0 CC=unset PID=unset"
wait_gone "$L2"
out="$(hook_in PreToolUse "$L2" toolu_q1 | bash "$S" relay-hook)"
check "K15 hook on retry ⇒ allow with answers" "$(jq -r '.hookSpecificOutput.permissionDecision + "|" + .hookSpecificOutput.updatedInput.answers["Which extras?"]' <<<"$out")" "allow|A,B"
check "K16 note delivered as annotations" "$(jq -r '.hookSpecificOutput.updatedInput.annotations["Which color?"].notes' <<<"$out")" "prefer the small diff"
out="$(ans '{"answers":{"0":"Blue","1":"C"}}' --owner-command "$OWN")"; check "K17 second answer refused" "$?" 1

# ---- L: .died marker ----------------------------------------------------------------------------------
check "L1 clean exit leaves no .died marker" "$([ -e "$LR/L1.died" ] && echo yes || echo no)" no
STUB_MODE=die LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "$OWN" >/dev/null; wait_gone "$L1"
has "L2 exit with no terminal result ⇒ .died" "$(cat "$LR/L1.died" 2>/dev/null)" "died_at"

# ---- M: liveness helper + pick-guard (AC12) ---------------------------------------------------------
AD="$P/.supervisor/automate"
check "M1 pick-guard ok with no live lane" "$(run pick-guard "$AD")" ok
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "$OWN" >/dev/null
check "M2 pick-guard refuses a live lane" "$(run pick-guard "$AD")" "refuse: live_lane $PARENT-L1 L1"
run pick-guard "$AD" >/dev/null; check "M3 refusal exits 1" "$?" 1
out="$(run lane-launch "$L1" --owner-command "$OWN")"; check "M4 relaunch of a running lane refused" "$?" 1
sleep 300 & SPID=$!; BG_PIDS="$BG_PIDS $SPID"
SST="$(ps -o lstart= -p "$SPID")"
( . "$S"; lanes_proc_alive "$SPID" "$SST" "$L1" ); check "M5 recycled pid (other command line) is not alive" "$?" 1
( . "$S"; lanes_proc_alive "$(tcol L1 5)" "Mon Jan  1 00:00:00 2001" "$L1" ); check "M6 start-time mismatch is not alive" "$?" 1
( . "$S"; lanes_proc_alive "$(tcol L1 5)" "$(tcol L1 6)" "$L1" ); check "M7 recorded lane process is alive" "$?" 0
out="$(run lane-remove "$L1")"; rc=$?
check "M8 lane-remove refuses a live claude -p" "$rc" 1; has "M8b names the process" "$out" "live claude -p process"
LP="$(tcol L1 5)"
out="$(run lane-remove "$L1" --stop)"; rc=$?
check "M9 --stop TERMs then removes" "$rc" 0; has "M9b reports the stop" "$out" "stopped claude -p (pid $LP)"
check "M10 process gone after --stop" "$(kill -0 "$LP" 2>/dev/null && echo alive || echo dead)" dead
check "M11 lane dir removed, state removed" "$([ -e "$L1" ] && echo present || echo absent):$(tcol L1 8)" "absent:removed"
check "M12 pick-guard ok after the lane stopped (lock-independent)" "$(run pick-guard "$AD")" ok
mkdir -p "$L2/.supervisor/inbox/questions"; echo '{}' > "$L2/.supervisor/inbox/questions/toolu_q2.json"
check "M13 pick-guard refuses a lane holding an unanswered question" "$(run pick-guard "$AD")" "refuse: live_lane $PARENT-L2 L2"

# ---- N: lane-remove refusals (AC3) + mutation controls (AC16) ---------------------------------------
out="$(run lane-remove "$L2")"; rc=$?
check "N1 awaiting_input refused" "$rc" 1; has "N1b names the question" "$out" "awaiting_input — unanswered question toolu_q2"
awk '/# >>> awaiting-input check/ { skip = 1 } !skip { print } /# <<< awaiting-input check/ { skip = 0 }' "$S" > "$MUT/automate-lanes.sh"
out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L2" 2>&1)"
hasnt "N2 mutation (awaiting_input check deleted) no longer refuses" "$out" "awaiting_input"
rm -rf "$L2"
# live-process mutation on a fresh lane
run lane-create "$RF" reqs/a.md 3 >/dev/null; L3="$LR/L3"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L3" --owner-command "$OWN" >/dev/null
L3P="$(tcol L3 5)"
awk '/# >>> live-process check/ { skip = 1 } !skip { print } /# <<< live-process check/ { skip = 0 }' "$S" > "$MUT/automate-lanes.sh"
out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L3" 2>&1)"
hasnt "N3 mutation (live-process check deleted) no longer refuses" "$out" "live claude -p"
kill -TERM "$L3P" 2>/dev/null; wait_gone "$L3"
# the remaining refusals, on one lane, each condition set then cleared
run lane-create "$RF" reqs/b.md 4 >/dev/null; L4="$LR/L4"
echo dirty >> "$L4/reqs/b.md"
out="$(run lane-remove "$L4")"; check "N4 dirty tree refused" "$?:$(printf '%s' "$out" | grep -c 'dirty working tree' | tr -d ' ')" "1:1"
git -C "$L4" checkout -q -- reqs/b.md
touch "$L4/.supervisor/automate/$PARENT-L4.meta-push-failed"
out="$(run lane-remove "$L4")"; has "N5 meta-push failure marker refused" "$out" "meta-push failure marker"
rm -f "$L4/.supervisor/automate/$PARENT-L4.meta-push-failed"
out="$(STUB_META_STATUS='local_ahead 2' run lane-remove "$L4")"; has "N6 unpushed metadata refused" "$out" "metadata not pushed (local_ahead 2)"
has "N6b meta status passes --branch" "$(cat "$META_LOG")" "meta-sync status --branch test-meta --root $L4"
git -C "$L4" checkout -q -b feature/x; echo y > "$L4/reqs/y.md"; git -C "$L4" add reqs/y.md; git -C "$L4" commit -qm y
out="$(run lane-remove "$L4")"; has "N7 unpushed commits refused" "$out" "branch feature/x has 1 commit(s) not on origin"
git -C "$L4" checkout -q main; git -C "$L4" branch -q -D feature/x
cat > "$T/automate-merge-watch.sh" <<'EOF'
#!/usr/bin/env bash
trap 'kill $! 2>/dev/null; exit 0' TERM; sleep 300 & wait $!
EOF
bash "$T/automate-merge-watch.sh" rf item https://github.com/o/r/pull/9 & WPID=$!; BG_PIDS="$BG_PIDS $WPID"
sleep 0.3
printf 'pid\t%s\npr_url\thttps://github.com/o/r/pull/9\nstarted\tx\n' "$WPID" > "$L4/.supervisor/automate/$PARENT-L4.merge-watch"
out="$(run lane-remove "$L4")"; has "N8 live merge watcher refused" "$out" "live merge watcher (pid $WPID"
printf 'pid\t%s\npr_url\thttps://github.com/o/r/pull/77\n' "$WPID" > "$L4/.supervisor/automate/$PARENT-L4.merge-watch"
awk -F'\t' -v OFS='\t' '$1 == "L4" { $8 = "gone" } { print }' "$TABLE" > "$TABLE.t" && mv "$TABLE.t" "$TABLE"
out="$(run lane-remove "$L4")"; rc=$?
hasnt "N9 watcher marker with another pr_url (recycled) is not a refusal" "$out" "merge watcher"
check "N10 gone without --abandon refused" "$rc:$(printf '%s' "$out" | grep -c 'gone' | tr -d ' ')" "1:1"
out="$(run lane-remove "$L4" --abandon)"; rc=$?
check "N11 --abandon removes" "$rc:$([ -e "$L4" ] && echo present || echo absent):$(tcol L4 8)" "0:absent:abandoned"
has "N12 --abandon logs one Progress line" "$(cat "$HELPERS_LOG")" "progress-append $RF lane abandoned: L4"
check "N13 salvage kept the lane's .supervisor" "$(ls -d "$LR"/salvage/L4-removed-*/supervisor 2>/dev/null | wc -l | tr -d ' ')" 1
check "N14 the merge watcher process was left alone" "$(kill -0 "$WPID" 2>/dev/null && echo alive || echo dead)" alive
# recycled claude pid: a live unrelated process recorded as the lane pid does not block removal
run lane-create "$RF" reqs/a.md 5 >/dev/null; L5="$LR/L5"
awk -F'\t' -v OFS='\t' -v p="$SPID" -v s="$(printf '%s' "$SST" | tr -s ' ' | sed 's/^ //')" '$1 == "L5" { $5 = p; $6 = s } { print }' "$TABLE" > "$TABLE.t" && mv "$TABLE.t" "$TABLE"
out="$(run lane-remove "$L5")"; check "N15 recycled pid is not a refusal (lane removed)" "$?:$([ -e "$L5" ] && echo present || echo absent)" "0:absent"

# ---- O: lane-info -----------------------------------------------------------------------------------
run lane-create "$RF" reqs/a.md 6 >/dev/null; L6="$LR/L6"
check "O1 lane-info in a lane prints lane.json" "$(run lane-info --root "$L6" | jq -r .run_id)" "$PARENT-L6"
check "O2 lane-info from cwd" "$(cd "$L6" && bash "$S" lane-info | jq -r .lane)" L6
run lane-info --root "$P" >/dev/null; check "O3 lane-info outside a lane exits 1" "$?" 1

# ---- P: branch-check (Scope 14 remote branch name) ----------------------------------------------------
check "P1 free name kept" "$(run branch-check "$L6" feature/new)" feature/new
git -C "$P" push -q origin main:refs/heads/feature/taken 2>/dev/null
check "P2 remote-only hit ⇒ suffixed" "$(run branch-check "$L6" feature/taken)" feature/taken-L6
git -C "$P" push -q origin main:refs/heads/feature/taken-L6 2>/dev/null
out="$(run branch-check "$L6" feature/taken)"; check "P3 both taken ⇒ refused" "$?:$out" "1:refuse: remote_branch_exists feature/taken"

hasnt "Z1 gh never called" "$(cat "$GH_CALLS" 2>/dev/null)" "gh"
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
