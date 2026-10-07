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
#   O lane-info · P branch-check · Q lane-status classification (AC7) · R lane-status --json (AC8)
#   S keep-awake · T --watch + lane-feed · U merge-readiness (AC9) · V --leaks / --resources / --tokens
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

# ---- Q: lane-status classification (AC7) ---------------------------------------------------------------
PARENT2=automate-2026-10-07-130000; RF2="$P/.supervisor/automate/$PARENT2.md"
TABLE2="$P/.supervisor/automate/$PARENT2.lanes"; LR2="$T/work/primary-lanes/$PARENT2"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT2" > "$RF2"
for n in 1 2 3 4 5 6 7; do run lane-create "$RF2" reqs/a.md "$n" --parallel 8 >/dev/null; done
t2set() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$TABLE2" > "$TABLE2.t" && mv "$TABLE2.t" "$TABLE2"; }
cat > "$T/pgrep-stub" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *caffeinate*) [ -n "${STUB_CAFF_HELD:-}" ] && { echo 777; exit 0; }; exit 1 ;;
  *"claude -p"*) [ -s "$PGREP_CLAUDE" ] && { cat "$PGREP_CLAUDE"; exit 0; }; exit 1 ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/ci-stub.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = status ] && [ -n "${STUB_CI_JSON:-}" ] && printf '%s\n' "$STUB_CI_JSON"; exit 0
EOF
cat > "$T/caff-stub" <<'EOF'
#!/usr/bin/env bash
echo "caffeinate $*" >> "$CAFF_LOG"
EOF
chmod +x "$T/pgrep-stub" "$T/ci-stub.sh" "$T/caff-stub"
export LOOMWRIGHT_LANES_PGREP="$T/pgrep-stub" LOOMWRIGHT_LANES_CI_SLOT="$T/ci-stub.sh" PGREP_CLAUDE="$T/pgrep.claude"
export LOOMWRIGHT_LANES_CAFFEINATE="$T/caff-stub" CAFF_LOG="$T/caff.log" LOOMWRIGHT_LANES_BOOT_EPOCH=1000000000
export LOOMWRIGHT_LANES_UNAME=Darwin LOOMWRIGHT_LANES_COORDINATOR_PID=4242
: > "$PGREP_CLAUDE"; : > "$CAFF_LOG"
sj() { bash "$S" lane-status "$RF2" --json 2>/dev/null; }
lf() { jq -r --arg l "$1" ".lanes[] | select(.lane == \$l) | $2" <<<"$J"; }
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR2/L1" --owner-command "$OWN" >/dev/null
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR2/L2" --owner-command "$OWN" >/dev/null
t2set L3 8 launched; t2set L3 5 99999998; t2set L3 6 "Mon Jan  1 00:00:00 2001"; t2set L3 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run lane-launch "$LR2/L4" --host-denied 'auto-mode classifier denied the spawn' >/dev/null
STUB_LOAD=overloaded run lane-launch "$LR2/L5" --owner-command "$OWN" >/dev/null
J="$(sj)"; rc=$?
check "Q1 lane-status --json exits 0 and parses" "$rc:$(jq -r '.lanes | length' <<<"$J")" "0:7"
check "Q2 launched lane is running" "$(lf L1 .state)" running
check "Q3 process gone, not parked, no question ⇒ stalled" "$(lf L3 .state)" stalled
check "Q4 host-denied spawn ⇒ blocked_launch with the reason" "$(lf L4 '.state + "|" + .reason')" "blocked_launch|auto-mode classifier denied the spawn"
check "Q5 HELD launch ⇒ held_for_load" "$(lf L5 '.state + "|" + .held_for_load')" "held_for_load|load overloaded"
check "Q6 never-launched lane ⇒ created" "$(lf L7 .state)" created
J="$(LOOMWRIGHT_LANES_BOOT_EPOCH="$(( $(date -u +%s) + 60 ))" sj)"
check "Q7 boot later than the last launch ⇒ lost_to_reset" "$(lf L3 .state)" lost_to_reset
has "Q7b lost_to_reset names the resume by run id" "$(lf L3 .reason)" "--resume-run $PARENT2-L3"
L1P="$(awk -F'\t' '$1 == "L1" { print $5 }' "$TABLE2")"; L1C="$(pgrep -P "$L1P" 2>/dev/null | head -1)"
kill -TERM "$L1C" 2>/dev/null; wait_gone "$LR2/L1"
J="$(sj)"
check "Q8 killed lane (no terminal result) ⇒ died" "$(lf L1 .state)" died
check "Q9 the other lane is unchanged (running)" "$(lf L2 .state)" running
out="$(run lane-status "$RF2")"
has "Q10 plain view: one line per lane with state and item" "$out" "L4  blocked_launch (auto-mode classifier denied the spawn)  item=reqs/a.md"
has "Q10b plain view shows held for load" "$out" "held for load: load overloaded"
check "Q11 liveness is not redefined (one lanes_proc_alive)" "$(grep -c '^lanes_proc_alive()' "$S")" 1
out="$(run lane-status "$P/.supervisor/automate/none.md" --json)"; rc=$?
check "Q12 no lane table ⇒ empty lanes, exit 0" "$rc:$(jq -r '.lanes | length' <<<"$out")" "0:0"

# ---- R: lane-status --json fields (AC8: machine, asked_at / waiting_s, last_message, CI slot) -----------
L6="$LR2/L6"; t2set L6 8 launched; t2set L6 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"id":"toolu_r1","asked_at":"2026-10-07T00:00:00Z","questions":[{"question":"Which path?","options":[{"label":"A"}]}]}\n' > "$L6/.supervisor/inbox/questions/toolu_r1.json"
LONG="$(printf 'x%.0s' $(seq 1 400))"
{ echo '{"type":"system","subtype":"init","session_id":"sess-r"}'
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"first words"}]}}\n'
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"line one\\nline two %s"}]}}\n' "$LONG"
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"loomwright:worker","description":"implement subtask 1"}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bash automate-helpers.sh current-set rf --pause ready_for_release"}}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Which path?"}]}}]}}'
  echo '{"type":"result","subtype":"success","stop_reason":"tool_deferred","deferred_tool_use":{"id":"toolu_r1"},"session_id":"sess-r"}'
} > "$LR2/L6.stream.log"
J="$(LOOMWRIGHT_MACHINE_LOAD_CMD="$T/absent-load.sh" sj)"; rc=$?
check "R1 machine-load absent ⇒ machine.state unknown, exit 0" "$rc:$(jq -r .machine.state <<<"$J")" "0:unknown"
check "R2 pending question ⇒ awaiting_input" "$(lf L6 .state)" awaiting_input
check "R3 asked_at echoed" "$(lf L6 '.questions[0].asked_at')" "2026-10-07T00:00:00Z"
W1="$(lf L6 '.questions[0].waiting_s')"
check "R4 waiting_s computed at read time" "$([ "$W1" -ge $(( $(date -u +%s) - $(jq -n '"2026-10-07T00:00:00Z" | fromdateiso8601') - 5 )) ] && echo yes)" yes
sleep 1; J="$(sj)"; W2="$(lf L6 '.questions[0].waiting_s')"
check "R5 waiting_s grows" "$([ "$W2" -gt "$W1" ] && echo yes)" yes
LM="$(lf L6 .last_message)"
check "R6 last_message is the last assistant text, trimmed to 300" "${#LM}:$(printf '%s' "$LM" | head -c 17)" "300:line one line two"
hasnt "R7 last_message is never a tool-use line" "$LM" "AskUserQuestion"
check "R8 last 3 actions" "$(lf L6 '.last_actions | length'):$(lf L6 '.last_actions[2]')" "3:AskUserQuestion"
check "R9 machine from machine-load.sh" "$(jq -r '.machine | "\(.state) \(.load1) \(.cpus) \(.keep_awake)"' <<<"$J")" "ok 1 8 not held"
J="$(STUB_CI_JSON="{\"holders\":[{\"checkout\":\"$T/elsewhere\"}],\"waiters\":[{\"checkout\":\"$T/other\",\"held\":null},{\"checkout\":\"$LR2/L2\",\"held\":\"machine busy\"}]}" sj)"
check "R10 CI-slot queue position" "$(lf L2 '.ci_slot.state + " " + (.ci_slot.position | tostring)')" "waiting 2"
check "R11 a running lane held by machine admission ⇒ held for load" "$(lf L2 .held_for_load)" "machine busy"
check "R12 no CI slot record ⇒ ci_slot none" "$(lf L6 .ci_slot.state)" none

# ---- S: keep-awake (suggest, never silently start) --------------------------------------------------
out="$(run lane-status "$RF2")"
has "S1 macOS: one-line caffeinate suggestion with the coordinator pid" "$out" "caffeinate -i -w 4242"
has "S2 keep-awake: not held" "$out" "keep-awake: not held"
check "S3 no keep-awake process started without --keep-awake" "$(wc -l < "$CAFF_LOG" | tr -d ' ')" 0
hasnt "S4 other OS: no suggestion" "$(LOOMWRIGHT_LANES_UNAME=Linux run lane-status "$RF2")" "caffeinate -i -w"
out="$(STUB_CAFF_HELD=1 run lane-status "$RF2")"
check "S5 holder seen ⇒ held, no suggestion" "$(printf '%s' "$out" | grep -c 'keep-awake: held'):$(printf '%s' "$out" | grep -c 'suggestion')" "1:0"
out="$(run lane-status "$RF2" --keep-awake)"; sleep 0.3
has "S6 --keep-awake starts it, tied to the coordinator" "$(cat "$CAFF_LOG")" "caffeinate -i -w 4242"
has "S6b and says so" "$out" "keep-awake: started (opt-in --keep-awake)"

# ---- T: --watch, lane-feed ----------------------------------------------------------------------------
out="$(LOOMWRIGHT_LANES_WATCH_ITERATIONS=1 run lane-status "$RF2" --watch)"; rc=$?
check "T1 --watch one iteration exits 0" "$rc" 0
has "T1b frame header" "$out" "lane-status --watch"
has "T1c frame carries the fleet" "$out" "L6  awaiting_input"
out="$(LOOMWRIGHT_LANES_WATCH_ITERATIONS=2 LOOMWRIGHT_LANES_WATCH_INTERVAL_S=0 run lane-status "$RF2" --watch)"
check "T2 --watch refreshes" "$(printf '%s\n' "$out" | grep -c '^lane-status --watch')" 2
out="$(run lane-feed "$L6")"
has "T3 feed prints spawns" "$out" "[spawn] loomwright:worker: implement subtask 1"
has "T4 feed prints the park write" "$out" "[park] bash automate-helpers.sh current-set"
has "T5 feed prints the deferred park" "$out" "[park] deferred toolu_r1 — awaiting input"
has "T6 feed prints messages and asks" "$out" "[ask] Which path?"
has "T7 feed resolves L<n>" "$(cd "$P" && bash "$S" lane-feed L6 2>&1)" "[init] session sess-r"
bash "$S" lane-feed "$L6" --follow > "$T/follow.out" 2>&1 & FP=$!
sleep 1.5; pkill -f "tail -n +1 -f $LR2/L6.stream.log" 2>/dev/null; kill "$FP" 2>/dev/null; wait "$FP" 2>/dev/null
has "T8 --follow narrates" "$(cat "$T/follow.out")" "[spawn] loomwright:worker"
has "T9 died lane: feed reports it" "$(run lane-feed "$LR2/L1")" "[died]"

# ---- U: merge-readiness report (AC9) -------------------------------------------------------------------
L3="$LR2/L3"
cat > "$L3/reqs/a.md" <<'EOF'
# a
## Touches
- `reqs/a.md`
- `src/`
## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch.
2. **Running system:** run it for real and paste the output.
3. **A failure this must catch:** the mutation control, shown failing.
## Notes
EOF
printf '# Automate Run: %s\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/5 | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-07T01:00:00Z children-settled: settled\n' "$PARENT2-L3" > "$L3/.supervisor/automate/$PARENT2-L3.md"
mkdir -p "$L3/.supervisor/jobs/in-progress"
printf '# brief for reqs/a.md\n- carried LOW: name the flag in the help text\n' > "$L3/.supervisor/jobs/in-progress/b.md"
cat > "$T/gh-ready" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") jq -n --arg b "$(printf 'Validation 1 baseline\n```\npassed: 5 failed: 0\n```\nValidation 2: will run later\nValidation 3 mutation\n```\nFAIL - leg x\n```\n')" '{body: $b, headRefOid: "abc123"}' ;;
  "pr diff") printf 'reqs/a.md\nsrc/x.sh\nchangelog.d/x.md\ndocs/other.md\n' ;;
  "pr checks") echo '[{"name":"ci","bucket":"pass"}]' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/gh-ready"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-readiness "$L3")"; rc=$?
RD="$L3/.supervisor/automate/$PARENT2-L3.merge-readiness.md"
check "U1 lane-readiness exits 0 and writes the report" "$rc:$([ -f "$RD" ] && echo yes)" "0:yes"
has "U2 a Validation step with pasted output ⇒ PASS" "$(cat "$RD")" "V1 Baseline: PASS"
has "U3 a running-system step with no pasted output ⇒ NOT-RUN, never PASS" "$(cat "$RD")" "V2 Running system: NOT-RUN — mentioned in the PR body without pasted output"
has "U4 scope fence lists the file outside the brief" "$(cat "$RD")" "  - docs/other.md"
has "U4b scope fence FAIL" "$(cat "$RD")" "- scope-fence: FAIL"
has "U5 carried note listed, NOT-RUN without accounting" "$(cat "$RD")" "carried-notes: NOT-RUN — 1 carried note(s)"
has "U6 gates PASS (checks green on head, decisions, children settled)" "$(cat "$RD")" "- gates: PASS"
has "U7 headline repro evidenced" "$(cat "$RD")" "V3 A failure this must catch: PASS"
has "U8 score line" "$(cat "$RD")" "- score: 2/5 | summary: ready (2/5: running-system NOT-RUN, carried-notes NOT-RUN, scope-fence FAIL)"
J="$(sj)"
check "U9 lane-status --json exposes the readiness score" "$(lf L3 '.readiness.score')" "2/5"
check "U10 parked ready lane state" "$(lf L3 .state)" ready_for_release
cat > "$T/helpers-merged.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = reconcile-item ] && echo merged
EOF
chmod +x "$T/helpers-merged.sh"
J="$(LOOMWRIGHT_LANES_HELPERS="$T/helpers-merged.sh" sj)"
check "U11 parked lane reconciled against gh (reconcile-item)" "$(lf L3 '.state + "|" + .pr_state')" "merged|merged"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$L3")"
has "U12 gh unreadable ⇒ every Validation step NOT-RUN" "$(cat "$RD")" "V1 Baseline: NOT-RUN — PR body unreadable"
out="$(LOOMWRIGHT_GH_BIN="$T/gh-ready" run lane-status "$RF2" --refresh-readiness)"
has "U13 lane-status --refresh-readiness re-writes it" "$(cat "$RD")" "V1 Baseline: PASS"
has "U13b plain view shows the score" "$out" "readiness: ready (2/5:"

# ---- V: --leaks, --resources, --tokens -----------------------------------------------------------------
out="$(run lane-status "$RF2" --leaks)"; has "V1 no snapshot ⇒ unknown, exit 0" "$out" "leaks: unknown — no snapshot"
out="$(run lane-status "$RF2" --leaks --snapshot)"; has "V2 snapshot written" "$out" "leaks: snapshot written"
check "V3 unchanged ⇒ leaks: none" "$(run lane-status "$RF2" --leaks | head -1 | cut -c1-11)" "leaks: none"
cp "$P/.supervisor/config.json" "$T/config.bak"
echo "4321 claude -p --resume x" > "$PGREP_CLAUDE"; echo '{"auto_review": false}' > "$P/.supervisor/config.json"
git -C "$P" worktree add -q "$T/wt-leak" -b leak-wt 2>/dev/null
out="$(run lane-status "$RF2" --leaks)"
check "V4 leaks found names each section" "$(printf '%s\n' "$out" | head -1)" "leaks: found — worktrees, claude-p, config-checksum"
has "V5 the leaked process is listed" "$out" "  + 4321 claude -p --resume x"
has "V6 unchanged sections say same" "$out" "- merge-watch: same"
cp "$T/config.bak" "$P/.supervisor/config.json"; : > "$PGREP_CLAUDE"; git -C "$P" worktree remove --force "$T/wt-leak" 2>/dev/null
out="$(run lane-status "$RF2" --resources)"; has "V7 no fleet.log ⇒ resources unknown" "$out" "resources: unknown"
printf '2026-10-07T10:00:00Z load1=5 load=ok L1_rss=100M L2_rss=300M nonlane_load=10%%\n2026-10-07T10:00:10Z load1=9 load=busy L1_rss=200M L2_rss=150M nonlane_load=20%%\n' > "$P/.supervisor/automate/$PARENT2.fleet.log"
out="$(run lane-status "$RF2" --resources)"
has "V8 latest line per lane" "$out" "L1: L1_rss=200M"
has "V9 wave peak" "$out" "peak: load1=9 L1_rss=200M L2_rss=300M nonlane_load=20%"
has "V10 machine part of the latest line" "$out" "machine: load1=9 load=busy nonlane_load=20%"
cat > "$T/ledger.sh" <<'EOF'
#!/usr/bin/env bash
echo "INPUT=1 OUTPUT=2 CACHE_READ=0 CACHE_CREATE=0 TOTAL=3 EVENTS=1"
EOF
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/ledger.sh" run lane-status "$RF2" --tokens)"
has "V11 per-lane tokens" "$out" "L1 INPUT=1 OUTPUT=2"
has "V12 parent tokens" "$out" "parent INPUT=1"
check "V13 total sums parent + lanes" "$(printf '%s\n' "$out" | sed -n 's/.* TOTAL=\([0-9]*\).*/\1/p' | tail -1)" 24
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/absent.sh" run lane-status "$RF2" --tokens)"; rc=$?
check "V14 ledger absent ⇒ unknown, exit 0" "$rc:$out" "0:tokens: unknown — read-token-ledger.sh absent"
for p in $(pgrep -f "_lane-run $LR2" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done

hasnt "Z1 gh never called" "$(cat "$GH_CALLS" 2>/dev/null)" "gh"
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
