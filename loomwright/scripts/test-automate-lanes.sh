#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wait-lib.sh"   # bounded condition waits (iq02 T07)
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
#   W drain-round-1 hardening: one-call token total (D8) + mutation control · trailing value flags
#     exit promptly · unpushed count unreadable refuses + mutation control · lock holder records
#     (dead holder reclaimed, live holder waited on, foreign lock never unlocked, holder-less lock
#     reclaimed) · two concurrent launches spawn once · multiSelect labels containing commas ·
#     lane-remove --stop refuses before stopping + mutation control
#   X relay hook from a linked worktree of the lane (git common dir; older git) + mutation control
#   Y lane-convert-ready: refusals, convert + single-path push, idempotent re-run, failed push, removal
#   Z Validation 4/5 fixes (parallel-automate/23): F5 readiness report · F9 leak check after removal ·
#     F1 snapshot before the lane table · F10 no absolute path / real state · F4 resume in the last
#     session · F2 HELD answer kept + delivered under an owner command · F11 gated wave-end push + ABANDONED
#   AA Validation 4/5 fixes B (parallel-automate/24): F6 lane-park-notify (truthful per-channel delivery)
#     · F8 real transcript usage ⇒ non-zero lane TOTAL + a ceiling-check PARK · F12 lane-feed --follow leaves
#     no pipeline behind on TERM / HUP / INT, and no process naming the suite dir outlives the suite
#   AB merged lane close-out (automate-followups/38): lane-convert-ready runs `closeout --no-trail` inside
#     the lane on its awaiting_merge re-run only (OPEN ⇒ nothing written; MERGED ⇒ stamp + check-off +
#     done/awaiting_go, pushed), a done/awaiting_go re-run retries only the pushes, leftover / no-pr / mode off
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/automate-lanes.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
BG_PIDS=""
# ere <text> — <text> as a literal extended regex (pgrep / pkill -f take an ERE: an unescaped `+` in
# `tail -n +1` means "one or more spaces", so the literal never matched — parallel-automate/24 F12).
ere() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
cleanup() {
  local p
  for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
  pkill -TERM -f "$(ere "$T")" 2>/dev/null   # safety net only — the AA-F12z leg is the assertion
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
  printf 'STDIN %s\n' "$(cat)"; printf 'CWD %s\n' "$PWD"
  printf 'RESUMEPATH %s\n' "${LOOMWRIGHT_LANE_RESUME_PATH-unset}"; } >> "$STUB_LOG"
if [ -n "${STUB_RESUME_FAIL:-}" ]; then
  for a in "$@"; do [ "$a" = --resume ] && { echo "No conversation found with session ID" >&2; exit 1; }; done
fi
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
# the wave-end evidence-gated trail (F11) runs through this seam; a no-op stub everywhere but Z-F11
cat > "$T/trail-stub.sh" <<'EOF'
#!/usr/bin/env bash
echo "trail $*" >> "$T_TRAIL_LOG"; echo "trail-pr: skipped — meta no_changes"
EOF
chmod +x "$T/trail-stub.sh"; export LOOMWRIGHT_LANES_TRAIL="$T/trail-stub.sh" T_TRAIL_LOG="$T/trail.log"

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
has "H4b disallow carries the REST merge endpoint via gh api" "$first" "Bash(gh api *pulls/*/merge*)"
has "H4c disallow carries the GraphQL merge mutation via gh api" "$first" "Bash(gh api *mergePullRequest*)"
has "H4d disallow carries the GraphQL auto-merge mutation via gh api" "$first" "Bash(gh api *enablePullRequestAutoMerge*)"
hasnt "H4e gh api graphql itself is not blanket-denied" "$first" "Bash(gh api graphql"
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
# Wait until the watcher's own command line is visible to ps (lane-remove's _lanes_live_watchers
# matches it) — a fixed sleep raced the exec under load (iq02 T07).
_n8_up() { case "$(ps -o command= -p "$WPID" 2>/dev/null)" in *automate-merge-watch*pull/9*) return 0 ;; esac; return 1; }
wait_for_cmd 15 _n8_up || bad "N8 setup: the merge-watch stub (pid $WPID) never showed its command line in ps" "within 15 s"
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
out="$(run lane-status "$RF2" --keep-awake)"
# The stub is started in the background: wait for its write, never a fixed sleep (the S6 flake, iq02 T07).
wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 15 \
  || bad "S6 wait: '$CAFF_LOG' never received 'caffeinate -i -w 4242'" "within 15 s"
has "S6 --keep-awake starts it, tied to the coordinator" "$(cat "$CAFF_LOG")" "caffeinate -i -w 4242"
# S6 controls: a stub that writes 0.5 s late still passes (the old 0.3 s sleep lost this race every
# time); a stub that never writes makes the wait FAIL, naming the condition.
printf '%s\n' '#!/usr/bin/env bash' 'sleep 0.5   # fixed-sleep-ok: the delayed-writer fixture itself' 'echo "caffeinate $*" >> "$CAFF_LOG"' > "$T/caff-slow"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$T/caff-mute"
chmod +x "$T/caff-slow" "$T/caff-mute"
: > "$CAFF_LOG"; LOOMWRIGHT_LANES_CAFFEINATE="$T/caff-slow" run lane-status "$RF2" --keep-awake >/dev/null
if wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 15; then ok "S6c a 0.5 s-late keep-awake write is still seen"
else bad "S6c delayed stub" "the wait missed a write that arrived 0.5 s late"; fi
: > "$CAFF_LOG"; LOOMWRIGHT_LANES_CAFFEINATE="$T/caff-mute" run lane-status "$RF2" --keep-awake >/dev/null
werr="$(wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 1 2>&1)"; wrc=$?
check "S6d a stub that never writes ⇒ the wait fails, naming the condition" "$wrc:$(case "$werr" in *"waiting for: 'caffeinate -i -w 4242' in $CAFF_LOG"*) echo named ;; esac)" "1:named"
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
sleep 1.5; kill "$FP" 2>/dev/null; wait "$FP" 2>/dev/null   # lane-feed kills its own pipeline (F12)
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
# argument-aware like the real reader: every --root adds one root's sums into the one line
n=0; for a in "$@"; do [ "$a" = "--root" ] && n=$((n + 1)); done; [ "$n" -gt 0 ] || n=1
echo "INPUT=$((1 * n)) OUTPUT=$((2 * n)) CACHE_READ=0 CACHE_CREATE=0 TOTAL=$((3 * n)) EVENTS=$n"
EOF
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/ledger.sh" run lane-status "$RF2" --tokens)"
has "V11 per-lane tokens" "$out" "L1 INPUT=1 OUTPUT=2"
has "V12 parent tokens" "$out" "parent INPUT=1"
check "V13 total sums parent + lanes" "$(printf '%s\n' "$out" | sed -n 's/.* TOTAL=\([0-9]*\).*/\1/p' | tail -1)" 24
out="$(LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/absent.sh" run lane-status "$RF2" --tokens)"; rc=$?
check "V14 ledger absent ⇒ unknown, exit 0" "$rc:$out" "0:tokens: unknown — read-token-ledger.sh absent"
for p in $(pgrep -f "_lane-run $LR2" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done

# ---- W: drain round 1 hardening -------------------------------------------------------------------------
# W1 (D8) the total is ONE read-token-ledger.sh call over every root: a parent that ran no session of its
# own (its root alone is unreadable) with readable lanes is NOT LEDGER_UNREADABLE. The stub models the
# real reader: roots add up, LEDGER_UNREADABLE=1 only when no root reads.
export LEDGER_CALLS="$T/ledger.calls"; : > "$LEDGER_CALLS"
cat > "$T/ledger-arg.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$LEDGER_CALLS"
n=0; prev=""
for a in "$@"; do { [ "$prev" = "--root" ] && [ "$a" != "$LEDGER_EMPTY_ROOT" ]; } && n=$((n + 1)); prev="$a"; done
if [ "$n" = 0 ]; then echo "INPUT=0 OUTPUT=0 CACHE_READ=0 CACHE_CREATE=0 TOTAL=0 EVENTS=0 LEDGER_UNREADABLE=1"
else echo "INPUT=$n OUTPUT=$((2 * n)) CACHE_READ=0 CACHE_CREATE=0 TOTAL=$((3 * n)) EVENTS=$n"; fi
EOF
tokens_arg() { LOOMWRIGHT_LANES_TOKEN_LEDGER="$T/ledger-arg.sh" LEDGER_EMPTY_ROOT="$P" bash "${1:-$S}" lane-status "$RF2" --tokens 2>&1; }
out="$(tokens_arg)"; TOT="$(printf '%s\n' "$out" | grep '^total (parent + lanes):')"
has "W1 the parent alone is unreadable (no session of its own)" "$(printf '%s\n' "$out" | grep '^parent ')" "LEDGER_UNREADABLE=1"
hasnt "W1b readable lanes ⇒ the total is not LEDGER_UNREADABLE" "$TOT" "LEDGER_UNREADABLE"
has "W1c the total adds the 7 readable lane roots" "$TOT" "TOTAL=21"
check "W1d the total is one call: --run-id <parent> with the primary + 7 lane roots" \
  "$(grep "^--run-id $PARENT2 " "$LEDGER_CALLS" | awk '{ n = 0; for (i = 1; i <= NF; i++) if ($i == "--root") n++; if (n > 1) print n }')" 8
cat > "$T/mut-total.line" <<'EOF'
  to="$(for r in "${roots[@]}"; do [ "$r" = --root ] || bash "$rtl" --run-id "$3" --root "$r" 2>/dev/null | head -1; done | awk '{ for (i = 1; i <= NF; i++) { k = $i; v = $i; sub(/=.*/, "", k); sub(/^[^=]*=/, "", v); if (k == "LEDGER_UNREADABLE") u = 1; else if (v ~ /^[0-9]+$/) { if (!(k in s)) o[++n] = k; s[k] += v } } } END { for (j = 1; j <= n; j++) printf "%s%s=%s", (j > 1 ? " " : ""), o[j], s[o[j]]; if (u) printf " LEDGER_UNREADABLE=1"; print "" }')"
EOF
awk -v f="$T/mut-total.line" '/# TOTAL-CALL$/ { while ((getline l < f) > 0) print l; next } { print }' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  has "W1e mutation (independent per-root calls, ORed) trips W1b" "$(tokens_arg "$MUT/automate-lanes.sh" | grep '^total')" "LEDGER_UNREADABLE=1"
else bad "W1e mutation control not built"; fi

# W2 a value-taking flag given last exits promptly non-zero (never a `shift 2` loop), per subcommand family
bounded() { # bounded <secs> <args...> — run the script; 124 when still alive after <secs> (then killed)
  local s="$1" p i=0; shift
  bash "$S" "$@" > "$T/bounded.out" 2>&1 < /dev/null & p=$!
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $((s * 10)) ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill -KILL "$p" 2>/dev/null; wait "$p" 2>/dev/null; return 124; fi
  wait "$p"
}
prompt_nz() { case "$1" in 0) echo "rc=0" ;; 124) echo "still running after 5s" ;; *) echo prompt-nonzero ;; esac; }
for spec in "lane-create|$RF reqs/a.md 7 --parallel" "lane-create|$RF reqs/a.md 7 --max-tokens" \
            "lane-launch|$LR/L6 --owner-command" "lane-launch|$LR/L6 --host-denied" "lane-launch|$LR/L6 --resume-run" \
            "lane-answer|$LR/L6 toolu_x --owner-command" "lane-answer|$LR/L6 toolu_x --via"; do
  sub="${spec%%|*}"; args="${spec#*|}"; flag="${args##* }"
  # shellcheck disable=SC2086
  bounded 5 "$sub" $args; rc=$?
  check "W2 $sub trailing $flag exits promptly non-zero" "$(prompt_nz "$rc")" prompt-nonzero
  has "W2b $sub trailing $flag names the missing value" "$(cat "$T/bounded.out")" "$flag needs a value"
done
check "W2c lane-create left no lane behind" "$([ -e "$LR/L7" ] && echo present || echo absent)" absent
bounded 5 init-check --parallel; rc=$?
check "W2d init-check trailing --parallel keeps its refuse contract (exit 1, promptly)" "$rc:$(cat "$T/bounded.out")" "1:refuse: parallel_out_of_range"

# W3 lane-remove: an unreadable unpushed-commit count refuses (fail CLOSED), never reads as 0
run lane-create "$RF" reqs/a.md 7 >/dev/null; L7="$LR/L7"
REAL_GIT="$(command -v git)"; mkdir -p "$T/gitshim"
cat > "$T/gitshim/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = rev-list ]; then [ "\${GITSHIM_MODE:-fail}" = empty ] && exit 0; echo "fatal: shim" >&2; exit 128; fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/gitshim/git"
out="$(PATH="$T/gitshim:$PATH" run lane-remove "$L7")"; rc=$?
check "W3 failed rev-list count ⇒ refused" "$rc:$([ -d "$L7" ] && echo kept || echo removed)" "1:kept"
has "W3b names the unreadable count" "$out" "branch main: unpushed-commit count unreadable"
out="$(GITSHIM_MODE=empty PATH="$T/gitshim:$PATH" run lane-remove "$L7")"; rc=$?
check "W3c empty count ⇒ refused" "$rc:$([ -d "$L7" ] && echo kept || echo removed)" "1:kept"
grep -v '# UNPUSHED-UNREADABLE$' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  PATH="$T/gitshim:$PATH" bash "$MUT/automate-lanes.sh" lane-remove "$L7" >/dev/null 2>&1
  check "W3d mutation (count guard deleted) fails OPEN — the lane is removed" "$([ -d "$L7" ] && echo kept || echo removed)" removed
else bad "W3d mutation control not built"; fi

# W4 lock holder records: a dead holder is reclaimed, a live one waited on (bounded) and never stolen,
# a foreign lock is never unlocked, a holder-less lock is reclaimed after its grace
lst() { env LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }
sleep 0 & DPID=$!; wait "$DPID" 2>/dev/null
mkdir -p "$TABLE.lock"; printf '%s Mon Jan  1 00:00:00 2001\n' "$DPID" > "$TABLE.lock/holder"
bounded 10 lane-launch "$LR/L6" --host-denied 'w4 dead holder'; rc=$?
check "W4 dead holder's lock reclaimed promptly (the table write lands)" "$rc:$(tcol L6 10)" "3:w4 dead holder"
check "W4b no lock left behind" "$([ -e "$TABLE.lock" ] && echo present || echo absent)" absent
sleep 300 & HPID=$!; BG_PIDS="$BG_PIDS $HPID"
mkdir -p "$TABLE.lock"; printf '%s %s\n' "$HPID" "$(lst "$HPID")" > "$TABLE.lock/holder"
LOOMWRIGHT_LANES_LOCK_WAIT_S=2 bounded 10 lane-launch "$LR/L6" --host-denied 'w4 live holder'; rc=$?
check "W4c live holder: the waiter gives up at its bound (not still running)" "$([ "$rc" != 124 ] && echo bounded || echo hung)" bounded
check "W4d live holder's lock is never stolen" "$(tcol L6 10):$(sed -n 1p "$TABLE.lock/holder" | cut -d' ' -f1)" "w4 dead holder:$HPID"
has "W4e the waiter says the lock is busy" "$(cat "$T/bounded.out")" "lock busy"
( . "$S"; _lt_unlock "$TABLE" )
check "W4f _lt_unlock leaves another process's lock alone" "$(sed -n 1p "$TABLE.lock/holder" 2>/dev/null | cut -d' ' -f1)" "$HPID"
bash "$S" lane-launch "$LR/L6" --host-denied 'w4 after holder died' > /dev/null 2>&1 & WPID=$!
sleep 1
check "W4g a live holder is waited on" "$(kill -0 "$WPID" 2>/dev/null && echo waiting || echo done):$(tcol L6 10)" "waiting:w4 dead holder"
kill "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null
i=0; while kill -0 "$WPID" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
check "W4h once the holder dies the waiter reclaims and writes" "$(kill -0 "$WPID" 2>/dev/null && echo hung || echo done):$(tcol L6 10)" "done:w4 after holder died"
mkdir -p "$TABLE.lock"
bounded 15 lane-launch "$LR/L6" --host-denied 'w4 holder-less'; rc=$?
check "W4i a holder-less lock (creator died before recording) is reclaimed after its grace" "$rc:$(tcol L6 10)" "3:w4 holder-less"
rm -rf "$TABLE.lock" "$TABLE.lock.reclaim"

# W5 two overlapping launches of one lane spawn exactly once (launch lock spans check → pid write)
run lane-create "$RF" reqs/b.md 8 >/dev/null; L8="$LR/L8"
n5="$(claude_calls)"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L8" --owner-command "$OWN" > "$T/w5a.out" 2>&1 & A5=$!
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-launch "$L8" --owner-command "$OWN" > "$T/w5b.out" 2>&1 & B5=$!
wait "$A5"; ra=$?; wait "$B5"; rb=$?
check "W5 two concurrent launches ⇒ exactly one spawn" "$(( $(claude_calls) - n5 ))" 1
check "W5b one launched, one refused" "$(printf '%s\n%s\n' "$ra" "$rb" | env LC_ALL=C sort | tr '\n' ' ')" "0 1 "
has "W5c the second sees the lane running" "$(cat "$T/w5a.out" "$T/w5b.out")" "already running"
check "W5d no launch lock left behind" "$(ls -d "$TABLE".L8.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
for p in $(pgrep -f "_lane-run $L8" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done; wait_gone "$L8"

# W6 multiSelect labels that contain commas
run lane-create "$RF" reqs/b.md 9 >/dev/null; L9="$LR/L9"
Q7='[{"question":"Which shades?","header":"Shades","multiSelect":true,"options":[{"label":"Red, dark","description":"r"},{"label":"Blue","description":"b"},{"label":"Green","description":"g"}]},{"question":"Which parts?","header":"Parts","multiSelect":true,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"},{"label":"A, B","description":"ab"},{"label":"C","description":"c"}]}]'
jq -n -c --argjson q "$Q7" '{id: "toolu_w6", asked_at: "2026-10-07T00:00:00Z", questions: $q}' > "$L9/.supervisor/inbox/questions/toolu_w6.json"
jq -n -c --argjson q "$Q7" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-w6", deferred_tool_use: {id: "toolu_w6", name: "AskUserQuestion", input: {questions: $q}}}' >> "$LR/L9.stream.log"
ans6() { printf '%s' "$1" | LOOMWRIGHT_LANE_RECHECK_S=0 bash "$S" lane-answer "$L9" toolu_w6 --owner-command "$OWN" 2>&1; }
out="$(ans6 '{"answers":{"0":"Red, dark","1":"A, B,C"}}')"; rc=$?
check "W6 an answer that splits into known labels two ways is refused" "$rc" 1
has "W6b the refusal says ambiguous" "$out" '"A, B,C" is ambiguous'
out="$(ans6 '{"answers":{"0":"Red, dark, Purple","1":"C"}}')"; rc=$?
check "W6c one unknown label still refuses the whole answer" "$rc:$(printf '%s' "$out" | grep -c '"Red, dark, Purple" is not one of its options' | tr -d ' ')" "1:1"
out="$(ans6 '{"answers":{"0":"Red","1":"C"}}')"; check "W6d half of a comma label is not a label" "$?" 1
check "W6e nothing recorded by the refusals" "$([ -e "$L9/.supervisor/inbox/answers/toolu_w6.json" ] && echo written || echo none)" none
out="$(ans6 '{"answers":{"0":"Red, dark, Blue","1":"A, B"}}')"; rc=$?
check "W6f a comma label plus another label, and a whole-answer label, are accepted" "$rc" 0
check "W6g recorded labels" "$(jq -c '[.answers["Which shades?"], .answers["Which parts?"]]' "$L9/.supervisor/inbox/answers/toolu_w6.json" 2>/dev/null)" '["Red, dark,Blue","A, B"]'
wait_gone "$L9"

# W7 lane-remove --stop runs every non-liveness refusal BEFORE stopping anything: a live lane with a
# dirty tree is refused for the dirty tree and its process is left running (never stopped-but-refused)
run lane-create "$RF" reqs/a.md 10 >/dev/null; L10="$LR/L10"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L10" --owner-command "$OWN" >/dev/null
L10P="$(tcol L10 5)"; L10S="$(tcol L10 6)"
echo dirty >> "$L10/reqs/a.md"
out="$(run lane-remove "$L10" --stop)"; rc=$?
check "W7 --stop on a dirty live lane ⇒ refused, lane kept" "$rc:$([ -d "$L10" ] && echo kept || echo removed)" "1:kept"
has "W7b refused with the dirty-tree reason" "$out" "refused — L10 — dirty working tree"
hasnt "W7c nothing was stopped" "$out" "lane-remove: stopped"
( . "$S"; lanes_proc_alive "$L10P" "$L10S" "$L10" ); check "W7d the lane process is still alive" "$?" 0
grep -v '# REFUSE-BEFORE-STOP$' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L10" --stop 2>&1)"
  has "W7e mutation (pre-stop refusal pass deleted) stops the process first" "$out" "lane-remove: stopped"
  has "W7f … and is then refused anyway (the old stopped-but-refused order)" "$out" "dirty working tree"
  check "W7g … leaving the lane process dead" "$(kill -0 "$L10P" 2>/dev/null && echo alive || echo dead)" dead
else bad "W7e mutation control not built"; fi
wait_gone "$L10"
git -C "$L10" checkout -q -- reqs/a.md
out="$(run lane-remove "$L10" --stop)"; check "W7h once clean, the stopped lane is removed" "$?:$([ -d "$L10" ] && echo kept || echo removed)" "0:removed"

# ---- X: relay hook from a linked worktree of the lane (owner fix-now FN1) -----------------------------
# A worker's worktree sits OUTSIDE the lane dir (../{repo}-{task_id}-{slug}) and holds no lane.json; the
# hook resolves the lane through the git common dir, so the question still lands in the LANE's inbox.
run lane-create "$RF" reqs/a.md 1 >/dev/null; L1="$LR/L1"
xhook() { hook_in PreToolUse "$1" "$2" | bash "${3:-$S}" relay-hook; }   # <cwd> <tool_use_id> [<script>]
xdec() { jq -r '.hookSpecificOutput.permissionDecision' <<<"$1" 2>/dev/null; }
WT="$LR/L1-42-slug"
git -C "$L1" worktree add -q -b feature/42-slug "$WT" 2>/dev/null
out="$(xhook "$WT" toolu_x1)"
check "X1 question asked from a linked worktree of the lane ⇒ defer" "$(xdec "$out")" defer
check "X2 … recorded in the LANE's inbox" "$(jq -r .id "$L1/.supervisor/inbox/questions/toolu_x1.json" 2>/dev/null)" toolu_x1
check "X3 … nothing written under the worktree" "$([ -e "$WT/.supervisor" ] && echo written || echo none)" none
out="$(xhook "$WT/reqs" toolu_x2)"
check "X4 a subdirectory of the worktree resolves to the lane too" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x2.json" ] && echo lane || echo missing)" "defer:lane"
# git < 2.31 has no --path-format: the shim echoes the flag back (as an older rev-parse does) ahead of
# the plain answer, so the hook must fall back to the toplevel-relative resolution
REAL_GIT="$(command -v git)"; mkdir -p "$T/oldgit"
cat > "$T/oldgit/git" <<EOF
#!/usr/bin/env bash
a=(); f=0
for x in "\$@"; do if [ "\$x" = --path-format=absolute ]; then f=1; else a+=("\$x"); fi; done
[ "\$f" = 1 ] && echo --path-format=absolute
exec "$REAL_GIT" "\${a[@]}"
EOF
chmod +x "$T/oldgit/git"
out="$(PATH="$T/oldgit:$PATH" xhook "$WT" toolu_x3)"
check "X5 older git (no --path-format): worktree question still reaches the lane inbox" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x3.json" ] && echo lane || echo missing)" "defer:lane"
out="$(PATH="$T/oldgit:$PATH" xhook "$L1/reqs" toolu_x4)"
check "X6 older git: a question from a lane subdirectory still reaches the lane inbox" \
  "$(xdec "$out"):$([ -s "$L1/.supervisor/inbox/questions/toolu_x4.json" ] && echo lane || echo missing)" "defer:lane"
PWT="$T/work/primary-42-slug"
git -C "$P" worktree add -q -b feature/p42 "$PWT" 2>/dev/null
check "X7 a linked worktree of a NON-lane checkout ⇒ no decision" "$(xhook "$PWT" toolu_x5)" "{}"
check "X7b … and nothing recorded anywhere" "$(ls "$PWT/.supervisor" "$P/.supervisor/inbox" 2>/dev/null | wc -l | tr -d ' ')" 0
git -C "$P" worktree remove --force "$PWT" 2>/dev/null; git -C "$P" branch -q -D feature/p42 2>/dev/null
check "X8 path-unsafe id from the worktree still ignored" "$(xhook "$WT" '../x')" "{}"
awk '/# HOOK-ROOT$/ { print "  root=\"$(git -C \"$cwd\" rev-parse --show-toplevel 2>/dev/null)\"; [ -n \"$root\" ] || root=\"$cwd\""; next } { print }' "$S" > "$MUT/automate-lanes.sh"
if ! cmp -s "$S" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  check "X9 mutation (old show-toplevel resolution) ⇒ the worktree question escapes ({})" "$(xhook "$WT" toolu_x9 "$MUT/automate-lanes.sh")" "{}"
  check "X9b … and the lane inbox never sees it" "$([ -e "$L1/.supervisor/inbox/questions/toolu_x9.json" ] && echo recorded || echo none)" none
else bad "X9 mutation control not built"; fi
git -C "$L1" worktree remove --force "$WT" 2>/dev/null; git -C "$L1" branch -q -D feature/42-slug 2>/dev/null

# ---- Y: lane-convert-ready — wave-end conversion pushes the lane run file (owner fix-now FN2) ----------
# The meta-sync stub models the real status: `synced` iff the lane's run files still hash to what the
# last push recorded, else `local_ahead 1`. current-set is the REAL automate-helpers.sh.
cat > "$T/meta-conv.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
root=""; pf=""; prev=""
for a in "$@"; do case "$prev" in --root) root="$a" ;; --paths-from) pf="$a" ;; esac; prev="$a"; done
sum() { cat "$root"/.supervisor/automate/*.md 2>/dev/null | cksum; }
case "$1" in
  push)
    echo "paths: $(tr '\n' ' ' < "$pf" 2>/dev/null)" >> "$META_LOG"
    [ -n "${STUB_PUSH_FAIL:-}" ] && { echo "meta_sync: push_failed — rejected 5 times; nothing forced, meta-base untouched" >&2; exit 1; }
    sum > "$root.pushed-sum"; echo "meta_sync: pushed abc123 (1 path(s))"; exit 0 ;;
  status) if [ "$(sum)" = "$(cat "$root.pushed-sum" 2>/dev/null)" ]; then echo "synced abc123 on test-meta"; else echo "local_ahead 1"; fi; exit 0 ;;
  pull) exit 0 ;;
esac
EOF
chmod +x "$T/meta-conv.sh"
conv_rf() { # <lane_dir> <status> <pause_reason> — a lane run file parked as given, recorded as pushed
  local id; id="$(jq -r .run_id "$1/.supervisor/lane.json")"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] reqs/b.md\n\n## Current\n- item: reqs/b.md | status: %s | pr: https://github.com/o/r/pull/12 | branch: feature/b\n- pause_reason: %s\n\n## Progress\n- 2026-10-08T00:00:00Z drain READY → %s\n' \
    "$id" "$2" "$3" "$2" > "$1/.supervisor/automate/$id.md"
  cat "$1"/.supervisor/automate/*.md | cksum > "$1.pushed-sum"
}
conv() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-conv.sh" LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "$S" lane-convert-ready "$@" 2>&1; }
rmv() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-conv.sh" bash "$S" lane-remove "$@" 2>&1; }
cur_line() { awk '/^## Current/ { c = 1; next } /^## / { c = 0 } c && /^- (item|pause_reason):/' "$1" | tr '\n' '|'; }
run lane-create "$RF" reqs/b.md 4 >/dev/null; L4="$LR/L4"; RF12="$L4/.supervisor/automate/$PARENT-L4.md"
conv_rf "$L4" escalated escalated; SUM12="$(cksum < "$RF12")"; : > "$META_LOG"
out="$(conv "$L4")"; rc=$?
check "Y1 a run file not reading ready_for_release is refused (exit 1)" "$rc" 1
has "Y1b … naming what it reads" "$out" "refused — L4 — run file reads status escalated / pause_reason escalated, not ready_for_release"
check "Y1c … nothing written, nothing pushed" "$(cksum < "$RF12"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$SUM12:0"
conv_rf "$L4" ready_for_release ready_for_release; SUM12="$(cksum < "$RF12")"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L4" --owner-command "$OWN" >/dev/null
L4P="$(tcol L4 5)"
out="$(conv "$L4")"; rc=$?
check "Y2 a live lane is refused (exit 1)" "$rc" 1
has "Y2b … naming the process" "$out" "refused — L4 — live lane process (pid $L4P)"
check "Y2c … nothing written, nothing pushed" "$(cksum < "$RF12"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$SUM12:0"
kill -TERM "$L4P" 2>/dev/null; wait_gone "$L4"
out="$(conv "$L4")"; rc=$?
check "Y3 a stopped ready_for_release lane converts (exit 0)" "$rc" 0
has "Y3b … and reports the push" "$out" "converted L4 to awaiting_merge; metadata pushed to test-meta"
check "Y3c ## Current now awaiting_merge (item, PR and branch kept)" "$(cur_line "$RF12")" \
  "- item: reqs/b.md | status: awaiting_merge | pr: https://github.com/o/r/pull/12 | branch: feature/b|- pause_reason: awaiting_merge|"
has "Y3d push passes the lane's metadata branch explicitly and its root" "$(grep ' push ' "$META_LOG")" "meta-sync push --branch test-meta --root $L4 --paths-from "
check "Y3e … and pushes exactly the lane run file" "$(grep '^paths:' "$META_LOG")" "paths: .supervisor/automate/$PARENT-L4.md "
has "Y3f ## Progress kept" "$(cat "$RF12")" "drain READY → ready_for_release"
SUM12="$(cksum < "$RF12")"
out="$(conv "$L4")"; rc=$?
check "Y4 a re-run is idempotent (exit 0, run file byte-unchanged)" "$rc:$(cksum < "$RF12")" "0:$SUM12"
has "Y4b … saying it only retries the push" "$out" "already reads awaiting_merge — retrying the metadata push"
check "Y4c no launch lock left behind" "$(ls -d "$TABLE".L4.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
out="$(rmv "$L4")"; rc=$?
check "Y5 afterwards lane-remove's metadata check passes and the lane is removed" "$rc:$([ -d "$L4" ] && echo kept || echo removed)" "0:removed"
# a failed push: loud, exit 2, the lane never looks converted-and-pushed (lane-remove refuses), re-run heals
run lane-create "$RF" reqs/b.md 5 >/dev/null; L5="$LR/L5"; RF13="$L5/.supervisor/automate/$PARENT-L5.md"
conv_rf "$L5" ready_for_release ready_for_release
out="$(STUB_PUSH_FAIL=1 conv "$L5")"; rc=$?
check "Y6 a failed push exits 2" "$rc" 2
has "Y6b … with a FAILED line naming the lane and the retry" "$out" "lane-convert-ready: FAILED — L5 — converted to awaiting_merge but the metadata push to test-meta failed (meta-sync exit 1); NOT pushed"
has "Y6c … relaying meta-sync's own reason" "$out" "meta_sync: push_failed"
has "Y6d … and naming the re-run" "$out" "re-run lane-convert-ready $L5"
check "Y6e no launch lock left behind" "$(ls -d "$TABLE".L5.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
out="$(rmv "$L5")"; rc=$?
check "Y7 after a failed push lane-remove refuses (metadata not pushed)" "$rc:$(printf '%s' "$out" | grep -c 'metadata not pushed (local_ahead 1)' | tr -d ' ')" "1:1"
out="$(conv "$L5")"; rc=$?
check "Y8 the re-run pushes (exit 0)" "$rc:$(printf '%s' "$out" | grep -c 'metadata pushed to test-meta' | tr -d ' ')" "0:1"
out="$(rmv "$L5")"; rc=$?
check "Y8b … and lane-remove then passes" "$rc:$([ -d "$L5" ] && echo kept || echo removed)" "0:removed"
# metadata mode: unknown refuses before any write; off converts with nothing to push
run lane-create "$RF" reqs/b.md 10 >/dev/null; L10="$LR/L10"; RF14="$L10/.supervisor/automate/$PARENT-L10.md"
conv_rf "$L10" ready_for_release ready_for_release; SUM14="$(cksum < "$RF14")"; : > "$META_LOG"
out="$(STUB_MODE_LINE='unknown no mode line' conv "$L10")"; rc=$?
check "Y9 metadata mode unknown ⇒ refused before any write" "$rc:$(cksum < "$RF14"):$(printf '%s' "$out" | grep -c 'metadata mode unknown' | tr -d ' ')" "1:$SUM14:1"
out="$(STUB_MODE_LINE=off conv "$L10")"; rc=$?
check "Y10 mode off ⇒ converted, nothing to push" "$rc:$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "0:0"
has "Y10b … reported as such" "$out" "converted L10 to awaiting_merge (metadata mode off — no metadata branch to push)"
out="$(conv "$LR/nope")"; check "Y11 not a lane ⇒ exit 1" "$?" 1
out="$(bash "$HERE/automate-helpers.sh" lane-convert-ready 2>&1)"; rc=$?
check "Y12 automate-helpers.sh dispatches lane-convert-ready (no lane ⇒ not-a-lane refusal)" "$rc:$(printf '%s' "$out" | grep -c 'lane-convert-ready: not a lane' | tr -d ' ')" "1:1"

# ---- Z: Validation 4/5 fixes (parallel-automate/23) ---------------------------------------------------
# Each leg fails against the pre-fix lane code at 91adff5 (identical to #426's head 8226dfe) and passes here.
# Z-F5 lane-readiness writes its report when the Validation names no repro (empty erows / vrows)
run lane-create "$RF" reqs/a.md 2 >/dev/null; LZ5="$LR/L2"; RDZ="$LZ5/.supervisor/automate/$PARENT-L2.merge-readiness.md"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$LZ5")"; rc=$?
check "Z-F5a no named repro (empty erows) ⇒ the report IS written" "$rc:$([ -f "$RDZ" ] && echo written || echo missing)" "0:written"
has "Z-F5b … with the headline-repro n/a line" "$(cat "$RDZ" 2>/dev/null)" "headline-repro: PASS — n/a (the Validation names no repro)"
hasnt "Z-F5c … and never says unwritable" "$out" "report not written"
check "Z-F5d no stray temp file left" "$(ls "$LZ5/.supervisor/automate/" | grep -c '\.tmp\.' | tr -d ' ')" 0
chmod 555 "$LZ5/.supervisor/automate"
out="$(LOOMWRIGHT_GH_BIN="$T/absent-gh" run lane-readiness "$LZ5")"; rc=$?
chmod 755 "$LZ5/.supervisor/automate"
check "Z-F5e a genuine write failure still says unwritable (exit 0, observation)" "$rc:$(printf '%s' "$out" | grep -c 'report not written (unwritable)' | tr -d ' ')" "0:1"
check "Z-F5f … leaving no temp file" "$(ls "$LZ5/.supervisor/automate/" | grep -c '\.tmp\.' | tr -d ' ')" 0

# Z-F9 a clean wave whose lanes were all removed reads `leaks: none`; salvage + stream logs are kept.
# The wave-start snapshot is taken through lanes_leaks directly (same signature before and after the
# fix) so this leg isolates F9 from F1.
PARENT4=automate-2026-10-08-090000; RF4="$P/.supervisor/automate/$PARENT4.md"; LR4="$T/work/primary-lanes/$PARENT4"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT4" > "$RF4"
( . "$S"; lanes_leaks "$P" "$PARENT4" 1 ) >/dev/null
run lane-create "$RF4" reqs/a.md 1 --parallel 2 >/dev/null; run lane-create "$RF4" reqs/b.md 2 --parallel 2 >/dev/null
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR4/L1" --owner-command "$OWN" >/dev/null; wait_gone "$LR4/L1"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$LR4/L2" --owner-command "$OWN" >/dev/null; wait_gone "$LR4/L2"
out="$(run lane-remove "$LR4/L1")$(run lane-remove "$LR4/L2")"
check "Z-F9a both lanes removed" "$([ -e "$LR4/L1" ] || [ -e "$LR4/L2" ] && echo present || echo absent)" absent
out="$(run lane-status "$RF4" --leaks)"
check "Z-F9b after a clean wave lane-status --leaks reads none" "$(printf '%s\n' "$out" | head -1 | cut -c1-11)" "leaks: none"
hasnt "Z-F9c … and lanes-dir is not changed" "$out" "lanes-dir: changed"
check "Z-F9d salvage kept at <primary>-lanes/<run_id>/salvage/" "$(ls -d "$LR4"/salvage/L1-removed-* "$LR4"/salvage/L2-removed-* 2>/dev/null | wc -l | tr -d ' ')" 2
check "Z-F9e stream logs kept at <primary>-lanes/<run_id>/L<n>.stream.log" "$([ -s "$LR4/L1.stream.log" ] && [ -s "$LR4/L2.stream.log" ] && echo kept)" kept
mkdir -p "$LR4/L3"; : > "$LR4/stray.txt"
out="$(run lane-status "$RF4" --leaks)"
has "Z-F9f a lane directory left behind is still a leak" "$out" "  + $PARENT4/L3"
has "Z-F9g … and so is any other file in the run directory (exact names only)" "$out" "  + $PARENT4/stray.txt"
rm -rf "$LR4/L3" "$LR4/stray.txt"

# Z-F1 §14 step 5 (snapshot) runs BEFORE step 6 (first lane-create): no <run_id>.lanes table yet
PARENT3=automate-2026-10-08-080000; RF3="$P/.supervisor/automate/$PARENT3.md"
SF3="$P/.supervisor/automate/$PARENT3.leaks-snapshot"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT3" > "$RF3"
check "Z-F1a fixture: no lane table yet" "$([ -e "$P/.supervisor/automate/$PARENT3.lanes" ] && echo table || echo none)" none
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
check "Z-F1b snapshot with no lane table is written (exit 0)" "$rc:$([ -s "$SF3" ] && echo written || echo missing)" "0:written"
has "Z-F1c … and says so (never a silent 'no lanes')" "$out" "leaks: snapshot written — $SF3"
hasnt "Z-F1d … no 'no lanes' line" "$out" "no lanes"
run lane-create "$RF3" reqs/a.md 1 >/dev/null
check "Z-F1e the snapshot is the baseline the end-of-wave check reads" "$(run lane-status "$RF3" --leaks | head -1 | cut -c1-6)" "leaks:"
rm -f "$SF3"; chmod 555 "$P/.supervisor/automate"
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
chmod 755 "$P/.supervisor/automate"
check "Z-F1f an unwritable snapshot exits non-zero (the one fail-SAFE exception)" "$([ "$rc" != 0 ] && echo nonzero || echo zero)" nonzero
has "Z-F1g … naming why" "$out" "leaks: snapshot not written (unwritable)"
rm -rf "$T/work/primary-lanes/$PARENT3/L1"; rm -f "$P/.supervisor/automate/$PARENT3.lanes"
chmod 555 "$P/.supervisor/automate"
out="$(run lane-status "$RF3" --leaks --snapshot)"; rc=$?
chmod 755 "$P/.supervisor/automate"
check "Z-F1h … with no lane table too" "$([ "$rc" != 0 ] && echo nonzero || echo zero):$(printf '%s' "$out" | grep -c 'snapshot not written' | tr -d ' ')" "nonzero:1"
out="$(run lane-status "$P/.supervisor/automate/absent-run.md" --leaks --snapshot)"; rc=$?
check "Z-F1i a parent run file that does not exist ⇒ non-zero, named" "$([ "$rc" != 0 ] && echo nonzero || echo zero):$(printf '%s' "$out" | grep -c 'parent run file not found' | tr -d ' ')" "nonzero:1"

# Z-F10 lane-remove --abandon writes no absolute path into the parent run file, and reports the lane's
# REAL state (lane-status's reader: a parked lane whose PR closed unmerged reads `gone`). progress-append
# is the real helper; HOME is set to the fixture root so every absolute fixture path is a $HOME path.
PARENT5=automate-2026-10-08-100000; RF5="$P/.supervisor/automate/$PARENT5.md"; LR5="$T/work/primary-lanes/$PARENT5"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT5" > "$RF5"
cat > "$T/helpers-gone.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in reconcile-item) echo gone ;; *) exec bash "$REAL_HELPERS" "$@" ;; esac
EOF
chmod +x "$T/helpers-gone.sh"; export REAL_HELPERS="$HERE/automate-helpers.sh"
run lane-create "$RF5" reqs/a.md 1 >/dev/null; L51="$LR5/L1"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L51" --owner-command "$OWN" >/dev/null; wait_gone "$L51"
printf '# Automate Run: %s-L1\n\n## Current\n- item: reqs/a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/51 | branch: f\n- pause_reason: awaiting_merge\n\n## Progress\n' "$PARENT5" > "$L51/.supervisor/automate/$PARENT5-L1.md"
check "Z-F10a fixture: lane-status reads the lane gone" \
  "$(LOOMWRIGHT_LANES_HELPERS="$T/helpers-gone.sh" bash "$S" lane-status "$RF5" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L1") | .state')" gone
out="$(HOME="$T" LOOMWRIGHT_LANES_HELPERS="$T/helpers-gone.sh" run lane-remove "$L51" --abandon)"; rc=$?
check "Z-F10b lane-remove --abandon removes the gone lane" "$rc:$([ -d "$L51" ] && echo kept || echo removed)" "0:removed"
ABL="$(grep 'lane abandoned: L1' "$RF5")"
has "Z-F10c the abandoned line reports the real state (gone, not the table's launched)" "$ABL" "— state gone;"
has "Z-F10d … and names the salvage in the <primary>-lanes/… form" "$ABL" "salvage kept at <primary>-lanes/$PARENT5/salvage/L1-removed-"
check "Z-F10e no line in the parent run file contains \$HOME" "$(grep -cF "$T" "$RF5" | tr -d ' ')" 0
check "Z-F10f no token in the parent run file starts with /" "$(grep -cE '(^|[[:space:]])/' "$RF5" | tr -d ' ')" 0

# Z-F4 a lane that died after its PICK resumes in its LAST session (its run.lock is session-id
# re-entrant), never a fresh one that waits out the dead session's lock; fresh only as the fallback
run lane-create "$RF5" reqs/b.md 2 >/dev/null; L52="$LR5/L2"
STUB_MODE=die LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "$OWN" >/dev/null; wait_gone "$L52"
printf '# Automate Run: %s-L2\n\n## Progress\n- picked reqs/b.md\n' "$PARENT5" > "$L52/.supervisor/automate/$PARENT5-L2.md"
check "Z-F4a fixture: the lane reads died with a recorded session" \
  "$(bash "$S" lane-status "$RF5" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L2") | .state + " " + .session_id')" "died sess-123"
SUM52="$(lane_sum "$L52")"; n4="$(claude_calls)"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "/automate --resume $PARENT5" --resume-run "$PARENT5-L2")"; rc=$?
wait_gone "$L52"
check "Z-F4b --resume-run launches once (exit 0)" "$rc:$(( $(claude_calls) - n4 ))" "0:1"
has "Z-F4c … resuming the lane's last session (the run lock's re-entrant path)" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume] [sess-123]"
has "Z-F4d … with the lane's own resume command" "$(grep '^STDIN' "$STUB_LOG" | tail -1)" "/loomwright:automate --resume $PARENT5-L2"
check "Z-F4e … telling the lane which path it is on (it records it in ## Progress itself)" "$(grep '^RESUMEPATH' "$STUB_LOG" | tail -1)" "RESUMEPATH session sess-123"
check "Z-F4f the coordinator wrote nothing into the lane (run file, lock)" "$(lane_sum "$L52")" "$SUM52"
n4="$(claude_calls)"
out="$(STUB_RESUME_FAIL=1 LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L52" --owner-command "/automate --resume $PARENT5" --resume-run "$PARENT5-L2")"; rc=$?
wait_gone "$L52"
check "Z-F4g an unresumable session falls back to ONE fresh session (two spawns)" "$rc:$(( $(claude_calls) - n4 ))" "0:2"
has "Z-F4h … saying so" "$out" "could not be resumed"
hasnt "Z-F4i … the fallback carries no --resume" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume]"
check "Z-F4j … and tells the lane it is on the fresh path" "$(grep '^RESUMEPATH' "$STUB_LOG" | tail -1)" "RESUMEPATH fresh session (last session sess-123 not resumable)"
has "Z-F4k a normal launch carries an empty resume path" "$(grep '^RESUMEPATH' "$STUB_LOG" | head -1)" "RESUMEPATH "

# Z-F2 a HELD answer is kept coordinator-side (validated answers + note + via, never an owner command),
# shown as answer_pending, and delivered ONLY by the delivery form under a current-session owner command
zq() { # <lane_dir> <tool_use_id> <session> — a recorded question the lane parked on (deferred)
  jq -n -c --argjson q "$Q2" --arg id "$2" '{id: $id, asked_at: "2026-10-08T00:00:00Z", questions: $q}' > "$1/.supervisor/inbox/questions/$2.json"
  jq -n -c --argjson q "$Q2" --arg id "$2" --arg s "$3" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: $s, deferred_tool_use: {id: $id, input: {questions: $q}}}' >> "$(dirname "$1")/$(basename "$1").stream.log"
}
t5set() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$P/.supervisor/automate/$PARENT5.lanes" > "$T/t5" && mv "$T/t5" "$P/.supervisor/automate/$PARENT5.lanes"; }
run lane-create "$RF5" reqs/a.md 3 >/dev/null; L53="$LR5/L3"; zq "$L53" toolu_z2 sess-z2
t5set L3 8 launched; t5set L3 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PF53="$P/.supervisor/automate/$PARENT5.L3.answer-pending.json"; AF53="$L53/.supervisor/inbox/answers/toolu_z2.json"
z2() { printf '%s' "$1" | bash "$S" lane-answer "$L53" toolu_z2 "${@:2}" 2>&1; }
n2="$(claude_calls)"
out="$(STUB_LOAD=busy z2 '{"answers":{"0":"Red","1":"A,B"},"note":"small diff"}' --owner-command "$OWN" --via test)"; rc=$?
check "Z-F2a load busy ⇒ HELD (exit 4)" "$rc:$(printf '%s\n' "$out" | head -1)" "4:lane-launch: HELD — L3 — load busy"
check "Z-F2b the validated answer is KEPT coordinator-side (answers, note, via)" \
  "$(jq -c '[.tool_use_id, .answers["0"], .answers["1"], .note, .via]' "$PF53" 2>/dev/null)" '["toolu_z2","Red","A,B","small diff","test"]'
check "Z-F2c … and the pending file holds no owner command" "$(grep -cF "$OWN" "$PF53" 2>/dev/null | tr -d ' '):$(jq -r 'keys | map(select(test("owner"))) | length' "$PF53" 2>/dev/null)" "0:0"
check "Z-F2d nothing written into the lane, nothing spawned" "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "none:0"
J="$(bash "$S" lane-status "$RF5" --json 2>/dev/null)"
check "Z-F2e lane-status shows the lane as answer_pending" "$(jq -r '.lanes[] | select(.lane == "L3") | .state' <<<"$J")" answer_pending
out="$(run lane-status "$RF5")"
has "Z-F2f … plain view names the delivery form" "$out" "L3  answer_pending"
check "Z-F2g lane-status (observation) delivered nothing, spawned nothing" "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "none:0"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L53" --deliver-pending)"; rc=$?
check "Z-F2h a pending file with NO current-session owner command is NOT delivered (BLOCKED, exit 3)" "$rc:$(printf '%s\n' "$out" | head -1)" "3:lane-launch: BLOCKED — L3 — no owner-invoked command — need the owner"
check "Z-F2i … nothing written into the lane, nothing spawned, the answer still pending" \
  "$([ -e "$AF53" ] && echo written || echo none):$(( $(claude_calls) - n2 )):$([ -s "$PF53" ] && echo kept || echo gone)" "none:0:kept"
out="$(STUB_LOAD=busy run lane-answer "$L53" --deliver-pending --owner-command "/automate --resume $PARENT5")"; rc=$?
check "Z-F2j still busy at delivery ⇒ HELD again, pending kept" "$rc:$([ -s "$PF53" ] && echo kept || echo gone):$([ -e "$AF53" ] && echo written || echo none)" "4:kept:none"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L53" --deliver-pending --owner-command "/automate --resume $PARENT5")"; rc=$?
check "Z-F2k the delivery form under the poll's owner command delivers (exit 0)" "$rc:$(( $(claude_calls) - n2 ))" "0:1"
check "Z-F2l … the answer file carries the stored labels and note" "$(jq -c '[.answers["Which color?"], .answers["Which extras?"], .note]' "$AF53" 2>/dev/null)" '["Red","A,B","small diff"]'
check "Z-F2m … the pending file is gone" "$([ -e "$PF53" ] && echo kept || echo gone)" gone
has "Z-F2n … and resumes the deferred session" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--resume] [sess-z2]"
wait_gone "$L53"
# a planted pending file (any process that can write the primary's .supervisor/automate/) is re-checked
run lane-create "$RF5" reqs/b.md 4 >/dev/null; L54="$LR5/L4"; zq "$L54" toolu_z3 sess-z3
PF54="$P/.supervisor/automate/$PARENT5.L4.answer-pending.json"; n2="$(claude_calls)"
printf '{"lane":"L4","tool_use_id":"toolu_z3","answers":{"0":"Purple","1":"A"},"note":null,"via":"x"}\n' > "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2o a stored answer that is not one of the question's labels is refused" "$rc:$(printf '%s' "$out" | grep -c 'no longer matches' | tr -d ' ')" "1:1"
check "Z-F2p … nothing written into the lane, nothing spawned, the stale file discarded" \
  "$([ -e "$L54/.supervisor/inbox/answers/toolu_z3.json" ] && echo written || echo none):$(( $(claude_calls) - n2 )):$([ -e "$PF54" ] && echo kept || echo gone)" "none:0:gone"
printf '{"lane":"L4","tool_use_id":"toolu_zz","answers":{"0":"Red","1":"A"},"note":null,"via":"x"}\n' > "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2q a stored answer for a tool_use_id the lane is not deferred on is refused" "$rc:$([ -e "$L54/.supervisor/inbox/answers/toolu_zz.json" ] && echo written || echo none):$(( $(claude_calls) - n2 ))" "1:none:0"
# Z-F2r..w (fix-now F-1/F-4) a HELD answer sets the table's state column to held_for_load; after its
# pending file is DISCARDED the lane's question is unanswered again, so lane-status must read
# awaiting_input (the question relayed), never held_for_load (which hides it and invites a fresh launch).
t5set L4 8 launched; t5set L4 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; n2="$(claude_calls)"
z4() { printf '%s' "$1" | bash "$S" lane-answer "$L54" toolu_z3 "${@:2}" 2>&1; }
out="$(STUB_LOAD=busy z4 '{"answers":{"0":"Red","1":"A"}}' --owner-command "$OWN" --via 'a b;c')"; rc=$?
check "Z-F2r fixture: HELD keeps the answer; a via that is not a short client token is stored as cli" "$rc:$(jq -r '.via' "$PF54" 2>/dev/null)" "4:cli"
out="$(STUB_LOAD=busy z4 '{"answers":{"0":"Blue","1":"B"}}' --owner-command "$OWN")"; rc=$?
check "Z-F2s a second HELD answer for the same question replaces the kept one (last write wins)" "$rc:$(jq -c '[.answers["0"], .answers["1"]]' "$PF54" 2>/dev/null)" '4:["Blue","B"]'
check "Z-F2t fixture: the table's state column reads held_for_load" "$(awk -F'\t' '$1 == "L4" { print $8 }' "$P/.supervisor/automate/$PARENT5.lanes")" held_for_load
jq -c '.answers["0"] = "Purple"' "$PF54" > "$PF54.t" && mv "$PF54.t" "$PF54"
out="$(LOOMWRIGHT_LANE_RECHECK_S=0 run lane-answer "$L54" --deliver-pending --owner-command "$OWN")"; rc=$?
check "Z-F2u fixture: the stale pending answer is discarded" "$rc:$([ -e "$PF54" ] && echo kept || echo gone):$(( $(claude_calls) - n2 ))" "1:gone:0"
J="$(bash "$S" lane-status "$RF5" --json 2>/dev/null)"
check "Z-F2v after the discard lane-status reads awaiting_input (the question shows again), not held_for_load" \
  "$(jq -r '.lanes[] | select(.lane == "L4") | .state + " " + (.questions | map(.id) | join(","))' <<<"$J")" "awaiting_input toolu_z3"
has "Z-F2w … the reason still names the last launch's hold" "$(jq -r '.lanes[] | select(.lane == "L4") | .reason' <<<"$J")" "last launch held for load: load busy"

# Z-F11 wave end with an UNMERGED done stamp: convert → PR closed unmerged → lane-remove --abandon.
# The lane is removable with no hand step, and the metadata branch (a fake remote the meta-sync stub
# keeps) never receives a done claim or a jobs/done/ brief for the unmerged work. trail-pr and its
# evidence gate are the REAL scripts (a copy whose setup-memory.sh reads branch mode on).
SC="$T/scripts-copy"; cp -R "$HERE" "$SC"
printf '#!/usr/bin/env bash\necho "on test-meta"\n' > "$SC/setup-memory.sh"
export REMOTE11="$T/remote11"; mkdir -p "$REMOTE11"
cat > "$T/meta-f11.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
root=""; pf=""; prev=""
for a in "$@"; do case "$prev" in --root) root="$a" ;; --paths-from) pf="$a" ;; esac; prev="$a"; done
managed() { (cd "$root" && find .supervisor/requirements .supervisor/jobs/done .supervisor/jobs/failed .supervisor/automate .supervisor/postmortem \
  -type f \( -name '*.md' -o -name '*.dismissed-decisions' -o -name results.jsonl \) 2>/dev/null | env LC_ALL=C sort); }
case "$1" in
  push) while IFS= read -r p; do [ -n "$p" ] || continue
          if [ -f "$root/$p" ]; then mkdir -p "$REMOTE11/$(dirname "$p")"; cp "$root/$p" "$REMOTE11/$p"; else rm -f "$REMOTE11/$p"; fi
        done < "$pf"; echo "meta_sync: pushed abc"; exit 0 ;;
  status) n=0; for p in $(managed); do cmp -s "$root/$p" "$REMOTE11/$p" || n=$((n + 1)); done
          if [ "$n" = 0 ]; then echo "synced abc on test-meta"; else echo "local_ahead $n"; fi; exit 0 ;;
  pull) exit 0 ;;
esac
EOF
cat > "$T/gh-f11" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_GH11"
case "$1 $2" in "pr view") printf '{"state":"%s","mergedAt":null}\n' "${STUB_PR_STATE:-OPEN}" ;; *) exit 1 ;; esac
EOF
chmod +x "$T/meta-f11.sh" "$T/gh-f11"; export T_GH11="$T/gh-f11.calls"
f11() { LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" LOOMWRIGHT_LANES_TRAIL="$SC/automate-helpers.sh" \
  LOOMWRIGHT_GH_BIN="$T/gh-f11" bash "$S" "$@" 2>&1; }
run lane-create "$RF5" reqs/a.md 5 >/dev/null; L55="$LR5/L5"; R11=".supervisor/requirements/t/x.md"; PR11="https://github.com/o/r/pull/55"
LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L55" --owner-command "$OWN" >/dev/null; wait_gone "$L55"
mkdir -p "$L55/.supervisor/requirements/t" "$L55/.supervisor/jobs/done"
printf '# x\n\n## Status: pending\n\n## Status: done\n<!-- loomwright:requirement-closeout -->\n- **PR:** %s\n' "$PR11" > "$L55/$R11"
printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$R11" "$PR11" > "$L55/.supervisor/jobs/done/2026-10-08-x.md"
printf '# Automate Run: %s-L5\n\n## Status: paused\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: ready_for_release | pr: %s | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- drain READY\n' \
  "$PARENT5" "$R11" "$R11" "$PR11" > "$L55/.supervisor/automate/$PARENT5-L5.md"
printf '# Merge readiness\n- score: 3/5\n' > "$L55/.supervisor/automate/$PARENT5-L5.merge-readiness.md"
out="$(STUB_PR_STATE=OPEN f11 lane-convert-ready "$L55")"; rc=$?
check "Z-F11a wave-end conversion with the PR still open exits 0" "$rc" 0
has "Z-F11b … the gated trail names the unmerged done stamp as excluded" "$out" "excluded $R11 — pr not merged"
check "Z-F11c … and nothing on the metadata branch carries it or a done/ brief" \
  "$([ -e "$REMOTE11/$R11" ] && echo req || echo noreq):$(ls "$REMOTE11/.supervisor/jobs/done" 2>/dev/null | wc -l | tr -d ' ')" "noreq:0"
check "Z-F11d … the run file and the readiness report were pushed" \
  "$([ -f "$REMOTE11/.supervisor/automate/$PARENT5-L5.md" ] && [ -f "$REMOTE11/.supervisor/automate/$PARENT5-L5.merge-readiness.md" ] && echo pushed)" pushed
out="$(STUB_PR_STATE=OPEN f11 lane-remove "$L55")"
has "Z-F11e an open PR's lane still refuses removal (its done stamp is unpushed by design)" "$out" "metadata not pushed"
out="$(STUB_PR_STATE=CLOSED f11 lane-remove "$L55" --abandon)"; rc=$?
check "Z-F11f PR closed unmerged ⇒ lane-remove --abandon removes the lane with no hand step" "$rc:$([ -d "$L55" ] && echo kept || echo removed)" "0:removed"
EMD="$(printf '\342\200\224')"
check "Z-F11g the metadata branch holds the reconcile-status ABANDONED stamp shape" \
  "$(grep -c "^## Status: done_with_escalation $EMD ABANDONED (- \[x\] $R11  # abandoned: " "$REMOTE11/$R11" 2>/dev/null | tr -d ' ')" 1
check "Z-F11h … and no other done heading (no done claim for the unmerged PR)" \
  "$(grep -E '^## Status:[[:space:]]*done' "$REMOTE11/$R11" 2>/dev/null | grep -vc "ABANDONED (- \[x\] " | tr -d ' ')" 0
check "Z-F11i … no jobs/done/ brief; the brief rides under jobs/failed/" \
  "$(ls "$REMOTE11/.supervisor/jobs/done" 2>/dev/null | wc -l | tr -d ' '):$(ls "$REMOTE11/.supervisor/jobs/failed" 2>/dev/null | tr '\n' ' ')" "0:2026-10-08-x.md "
has "Z-F11j the parent run file records the abandon with the real state" "$(cat "$RF5")" "lane abandoned: L5 ($PARENT5-L5) — state gone;"

# ---- AA: Validation 4/5 fixes B (parallel-automate/24) ------------------------------------------------
# Each leg fails against the pre-fix code at 9a65ecb and passes here.
# AA-F12 lane-feed --follow: signalling the lane-feed process ALONE leaves no tail | grep | jq behind.
AA_TAIL="tail -n \\+1 -f $(ere "$LR2/L6.stream.log")"
aa_feed() { # <signal> — prints "<seen|unseen> <none|survivor>"; kills any survivor afterwards
  local sig="$1" fp i=0 seen=unseen
  # An async child starts with SIGINT ignored, and a suite launched under `nohup` (a detached
  # ci-local / harness run) passes SIGHUP down ignored too — and bash cannot trap a signal that was
  # ignored on entry, so HUP then never reached lane-feed's trap and AA-F12b read "survivor" 50/50
  # (iq02 T07). Reset BOTH to default before exec, as a terminal would deliver them.
  python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); signal.signal(signal.SIGHUP, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash "$S" lane-feed "$L6" --follow > "$T/aa-follow.$sig" 2>&1 & fp=$!
  # Clock-bounded (wait-lib), not count-bounded: AA-F12b went red under a loaded pool (iq02 T07).
  wait_for_cmd 15 pgrep -f "$AA_TAIL" 2>/dev/null && seen=seen
  sleep 0.3; kill -"$sig" "$fp" 2>/dev/null   # fixed-sleep-ok: settle — the pipeline's traps installed before the signal (too short ⇒ a different, earlier-kill path is tested)
  wait_for_pid_gone "$fp" 10 2>/dev/null
  kill -KILL "$fp" 2>/dev/null; wait "$fp" 2>/dev/null   # bounded: a lane-feed that ignores the signal never hangs the suite
  _aa_no_tail() { ! pgrep -f "$AA_TAIL" >/dev/null 2>&1; }
  wait_for_cmd 10 _aa_no_tail 2>/dev/null
  if pgrep -f "$AA_TAIL" >/dev/null 2>&1; then echo "$seen survivor"; pkill -TERM -f "$AA_TAIL" 2>/dev/null; else echo "$seen none"; fi
}
check "AA-F12a TERM to lane-feed --follow alone ⇒ its tail pipeline is gone (and the escaped pattern did see it)" "$(aa_feed TERM)" "seen none"
check "AA-F12b HUP ⇒ the same" "$(aa_feed HUP)" "seen none"
check "AA-F12c INT ⇒ the same" "$(aa_feed INT)" "seen none"
has "AA-F12d the follow still narrates" "$(cat "$T/aa-follow.TERM")" "[spawn] loomwright:worker"
check "AA-F12e the unescaped pattern T8 used never matched a live tail (the root cause, not the path)" \
  "$(bash "$S" lane-feed "$L6" --follow >/dev/null 2>&1 & fp=$!
     # first prove the tail IS up (the escaped pattern sees it), so `unmatched` cannot pass on a slow start
     if wait_for_cmd 15 pgrep -f "$AA_TAIL" 2>/dev/null; then
       pgrep -f "tail -n +1 -f $LR2/L6.stream.log" >/dev/null 2>&1 && echo matched || echo unmatched
     else echo "tail-never-up"; fi
     kill "$fp" 2>/dev/null; wait "$fp" 2>/dev/null; pkill -TERM -f "$AA_TAIL" 2>/dev/null)" unmatched

# AA fixture: one lane (L1) of a fresh parent run, its run file at the ready_for_release park.
PARENT6=automate-2026-10-08-110000; RF6="$P/.supervisor/automate/$PARENT6.md"; LR6="$T/work/primary-lanes/$PARENT6"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT6" > "$RF6"
run lane-create "$RF6" reqs/a.md 1 --parallel 2 --max-tokens 200 >/dev/null; L61="$LR6/L1"; LRF6="$L61/.supervisor/automate/$PARENT6-L1.md"
PR6="https://github.com/o/r/pull/66"
printf '# Automate Run: %s-L1\n\n## Status: paused\n\n## Queue\n- [ ] reqs/a.md\n\n## Current\n- item: reqs/a.md | status: ready_for_release | pr: %s | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-10-08T11:00:00Z session_id sess-aa (reqs/a.md)\n' \
  "$PARENT6" "$PR6" > "$LRF6"
# AA-F8 a lane whose log holds a real (transcript-usage) ledger line reads a non-zero TOTAL, and its share parks.
mkdir -p "$T/subagents"; AAT="$T/subagents/agent-aa1.jsonl"   # the agent's OWN transcript name — the emitter sums only agent-<agent_id>.jsonl
{ for o in 8 8; do printf '{"type":"assistant","message":{"id":"msg_A","stop_reason":null,"usage":{"input_tokens":10,"output_tokens":%s,"cache_read_input_tokens":100,"cache_creation_input_tokens":50,"cache_creation":{"ephemeral_5m_input_tokens":50}}}}\n' "$o"; done
  echo '{"type":"assistant","message":{"id":"msg_A","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":263,"cache_read_input_tokens":100,"cache_creation_input_tokens":50}}}'
  echo '{"type":"assistant","message":{"id":"msg_B","stop_reason":null,"usage":{"input_tokens":7,"output_tokens":40,"cache_read_input_tokens":200,"cache_creation_input_tokens":0}}}'
} > "$AAT"
jq -n --arg a "$AAT" '{session_id: "sess-aa", agent_id: "aa1", agent_transcript_path: $a}' \
  | (cd "$L61" && env -u LOOMWRIGHT_ORIENTATION_SOURCE -u LOOMWRIGHT_SHARED_PREFIX -u LOOMWRIGHT_ADVISORY_TOTAL_BYTES bash "$HERE/emit-token-ledger.sh")
check "AA-F8a the real emitter wrote a transcript-usage line into the lane's log" \
  "$(jq -r '"\(.usage_source) \(.output_tokens)"' "$L61/.supervisor/logs/sess-aa.jsonl" 2>/dev/null)" "transcript 303"
out="$(run lane-status "$RF6" --tokens)"
check "AA-F8b lane-status --tokens: the lane's TOTAL is non-zero (the real reader)" \
  "$(printf '%s\n' "$out" | awk '$1 == "L1"' | grep -oE 'TOTAL=[0-9]+')" "TOTAL=670"
check "AA-F8c ceiling-check on the lane run file with a share below that total ⇒ PARK" \
  "$(cd "$L61" && bash "$HERE/automate-helpers.sh" ceiling-check "$LRF6" 100)" "PARK: token_ceiling total=670 max=100"


# AA-F6 lane-park-notify: desktop + automate_ready_for_release webhook, one truthful ## Progress line.
cat > "$T/aa-nd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(cat)" >> "$AA_ND_LOG"
[ -n "${STUB_ND_AUDIT:-}" ] && { mkdir -p .supervisor/logs; echo "2026-10-08T11:00:00Z notify group=loomwright-x tool_use_id=-" >> .supervisor/logs/notifications.log; }
exit 0
EOF
cat > "$T/aa-sw.sh" <<'EOF'
#!/usr/bin/env bash
echo "dry=${LOOMWRIGHT_WEBHOOK_DRY_RUN:-} $*" >> "$AA_SW_LOG"
case "${STUB_SW:-none}" in
  ignored) echo "repo_webhook_ignored slug=o/r" >&2 ;;
  configured) [ -n "${LOOMWRIGHT_WEBHOOK_DRY_RUN:-}" ] && echo '{"event_type":"gate"}' ;;
esac
exit 0
EOF
chmod +x "$T/aa-nd.sh" "$T/aa-sw.sh"; export AA_ND_LOG="$T/aa-nd.log" AA_SW_LOG="$T/aa-sw.log"
# `desktop: sent` also needs the platform notifier notify-desktop.sh dispatches to, so the host's own
# PATH must not decide these legs: pn pins the OS (AA_UNAME, default Darwin) and prepends a stub
# osascript + notify-send (never executed — only probed with `command -v`). AA_PATH replaces the
# whole PATH for the no-notifier leg (AA-F6m); AA_ND swaps the notifier stub (AA-F6r/s).
mkdir -p "$T/aa-bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/aa-bin/osascript"; cp "$T/aa-bin/osascript" "$T/aa-bin/notify-send"
chmod +x "$T/aa-bin/osascript" "$T/aa-bin/notify-send"
pn() { : > "$AA_ND_LOG"; : > "$AA_SW_LOG"; PATH="${AA_PATH:-$T/aa-bin:$PATH}" LOOMWRIGHT_LANES_UNAME="${AA_UNAME:-Darwin}" \
  LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" LOOMWRIGHT_LANES_NOTIFY_DESKTOP="${AA_ND:-$T/aa-nd.sh}" \
  LOOMWRIGHT_LANES_SEND_WEBHOOK="$T/aa-sw.sh" bash "$S" lane-park-notify "$@" 2>&1; }
pcount() { grep -c 'lane park notify: ready_for_release' "$LRF6" | tr -d ' '; }
out="$(STUB_SW=ignored STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"; rc=$?
check "AA-F6a webhook ignored ⇒ exit 0, ONE ## Progress line" "$rc:$(pcount)" "0:1"
has "AA-F6b … the line names the delivered desktop channel" "$(grep 'lane park notify' "$LRF6")" "desktop: sent;"
has "AA-F6c … and says the webhook was ignored, with the reason" "$(grep 'lane park notify' "$LRF6")" "webhook: ignored (repo_webhook_ignored slug=o/r — no user-scope egress grant)"
check "AA-F6d the desktop payload: automate_ready_for_release, the do-not-merge message" \
  "$(jq -r '"\(.hook_event_name) \(.notification_type) \(.message | test("^https://github.com/o/r/pull/66 READY — do not merge yet — wave open"))"' "$AA_ND_LOG")" \
  "Notification automate_ready_for_release true"
check "AA-F6e an ignored webhook is only probed (dry run), never posted" "$(grep -c '^dry= ' "$AA_SW_LOG" | tr -d ' ')" 0
has "AA-F6f … with gate type automate_ready_for_release" "$(cat "$AA_SW_LOG")" "--gate-type automate_ready_for_release --context https://github.com/o/r/pull/66 READY — do not merge yet — wave open"
out="$(STUB_SW=configured STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 LOOMWRIGHT_NOTIFY_DEBOUNCE=0 pn "$LRF6")"
has "AA-F6g webhook configured ⇒ posted once, reported as attempted (never 'sent': its HTTP result is unreported)" \
  "$(grep -c '^dry= --event-type gate --gate-type automate_ready_for_release' "$AA_SW_LOG" | tr -d ' '):$out" "1:lane-park-notify: lane park notify: ready_for_release ($PARENT6-L1) — desktop: sent; webhook: attempted"
out="$(STUB_SW=none LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 pn "$LRF6")"
check "AA-F6h desktop opted out ⇒ disabled, the notifier not run; no webhook ⇒ not configured" \
  "$(wc -l < "$AA_ND_LOG" | tr -d ' '):${out#*— }" "0:desktop: disabled (LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0); webhook: not configured"
out="$(STUB_SW=none LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6i the notifier wrote no audit line ⇒ suppressed, never sent" "$out" "desktop: suppressed (no audit line"
check "AA-F6j one ## Progress line per run (four runs, four lines)" "$(pcount)" 4
# AA-F6m..p `sent` is claimed only when a platform notifier exists: notify-desktop.sh writes its audit
# line on EVERY host before its platform dispatch, so the audit line alone proves no banner.
# The no-notifier PATH is a symlink farm of the host's PATH minus the three notifiers it can dispatch to.
mkdir -p "$T/aa-nonotify-bin"
_aa_ifs="$IFS"; IFS=:
for _aa_d in $PATH; do
  [ -d "$_aa_d" ] || continue
  for _aa_f in "$_aa_d"/*; do
    _aa_n="${_aa_f##*/}"
    case "$_aa_n" in osascript|terminal-notifier|notify-send) continue ;; esac
    [ -x "$_aa_f" ] && [ ! -e "$T/aa-nonotify-bin/$_aa_n" ] && ln -s "$_aa_f" "$T/aa-nonotify-bin/$_aa_n" 2>/dev/null
  done
done
IFS="$_aa_ifs"
out="$(AA_PATH="$T/aa-nonotify-bin" STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"; rc=$?
check "AA-F6m audit line written but no OS notifier on PATH (Darwin) ⇒ failed, never sent; exit 0" \
  "$rc:${out#*— }" "0:desktop: failed (no OS notifier on PATH); webhook: not configured"
has "AA-F6n … and the ## Progress line says the same" "$(grep 'lane park notify' "$LRF6" | tail -1)" "desktop: failed (no OS notifier on PATH);"
out="$(AA_PATH="$T/aa-nonotify-bin" AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6o Linux without notify-send ⇒ failed (no OS notifier on PATH)" "$out" "desktop: failed (no OS notifier on PATH);"
out="$(AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 DISPLAY= WAYLAND_DISPLAY= pn "$LRF6")"
has "AA-F6p Linux notify-send present but no display ⇒ failed (no display for notify-send) — notify-desktop.sh skips it there" \
  "$out" "desktop: failed (no display for notify-send);"
out="$(AA_UNAME=Linux STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 DISPLAY=:0 pn "$LRF6")"
has "AA-F6q Linux notify-send + DISPLAY ⇒ sent" "$out" "desktop: sent;"
# AA-F6r..t Darwin with terminal-notifier but NO osascript: notify-desktop.sh uses terminal-notifier only
# when its click action is not `none` (resolved by the notify-click-target.sh beside it), else falls
# through to the osascript branch — so terminal-notifier alone counts only with a click action.
mkdir -p "$T/aa-tn-bin" "$T/aa-ndc"; cp "$T/aa-bin/osascript" "$T/aa-tn-bin/terminal-notifier"
cp "$T/aa-nd.sh" "$T/aa-ndc/notify-desktop.sh"; ln -s "$HERE/notify-click-target.sh" "$T/aa-ndc/notify-click-target.sh"
chmod +x "$T/aa-tn-bin/terminal-notifier" "$T/aa-ndc/notify-desktop.sh"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" AA_ND="$T/aa-ndc/notify-desktop.sh" LOOMWRIGHT_NOTIFY_CLICK=off \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6r Darwin terminal-notifier only, click action none (LOOMWRIGHT_NOTIFY_CLICK=off) ⇒ failed (no OS notifier on PATH), never sent" \
  "$out" "desktop: failed (no OS notifier on PATH);"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" AA_ND="$T/aa-ndc/notify-desktop.sh" LOOMWRIGHT_NOTIFY_CLICK=activate \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6s Darwin terminal-notifier only, click action set (activate) ⇒ sent" "$out" "desktop: sent;"
out="$(AA_PATH="$T/aa-tn-bin:$T/aa-nonotify-bin" LOOMWRIGHT_NOTIFY_CLICK=activate \
  STUB_SW=none STUB_ND_AUDIT=1 LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$LRF6")"
has "AA-F6t Darwin terminal-notifier only, no notify-click-target.sh beside the notifier (action none) ⇒ failed" \
  "$out" "desktop: failed (no OS notifier on PATH);"
out="$(LOOMWRIGHT_LANES_NOTIFY_DESKTOP="$T/aa-nd.sh" LOOMWRIGHT_LANES_SEND_WEBHOOK="$T/aa-sw.sh" LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 \
  bash "$HERE/automate-helpers.sh" lane-park-notify "$LRF6" 2>&1)"; rc=$?
check "AA-F6k dispatched through automate-helpers.sh" "$rc:$(printf '%s' "$out" | grep -c '^lane-park-notify: lane park notify:' | tr -d ' ')" "0:1"
sed 's/status: ready_for_release/status: awaiting_merge/; s/pause_reason: ready_for_release/pause_reason: awaiting_merge/' "$LRF6" > "$T/aa-notpark.md"
mkdir -p "$L61/.supervisor/automate"; cp "$T/aa-notpark.md" "$L61/.supervisor/automate/aa-notpark.md"
out="$(STUB_SW=configured LOOMWRIGHT_DESKTOP_NOTIFICATIONS=1 pn "$L61/.supervisor/automate/aa-notpark.md")"; rc=$?
check "AA-F6l not at the ready_for_release park ⇒ skipped: exit 0, nothing sent, no line written" \
  "$rc:$(wc -l < "$AA_ND_LOG" | tr -d ' '):$(wc -l < "$AA_SW_LOG" | tr -d ' '):$(cmp -s "$T/aa-notpark.md" "$L61/.supervisor/automate/aa-notpark.md" && echo unchanged)" "0:0:0:unchanged"

# ---- AB: a merged lane is closed out by lane-convert-ready's re-run (automate-followups/38) ----------
# lane-convert-ready on `ready_for_release` converts with NO closeout; its `awaiting_merge` re-run runs
# `closeout <run file> <item> <## Current pr> --no-trail` inside the lane, under the launch lock and
# BEFORE the pushes (evidence-gated: an OPEN PR ⇒ nothing written); a MERGED re-run stamps the
# requirement, checks the item off, reconciles ## Current to done / awaiting_go and the wave-end push
# carries all of it; a re-run after that (`done` / `awaiting_go`) retries only the pushes. The scripts
# are the REAL copy $SC (branch mode on, Z-F11); a spy dispatcher in front of it records every call.
cat > "$T/ab-gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$T_ABGH"
st="${STUB_PR_STATE:-OPEN}"; ma=null; [ "$st" = MERGED ] && ma='"2026-10-10T00:00:00Z"'
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view") printf '{"state":"%s","mergedAt":%s,"headRefName":"feature/ab","headRefOid":"1111111111111111111111111111111111111111"}\n' "$st" "$ma" ;;
  *) exit 1 ;;
esac
EOF
cat > "$T/ab-spy.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "\$T_ABSPY"
exec bash "$SC/automate-helpers.sh" "\$@"
EOF
chmod +x "$T/ab-gh" "$T/ab-spy.sh"; export T_ABGH="$T/ab-gh.calls" T_ABSPY="$T/ab-spy.log"; mkdir -p "$T/remote-ab"
ab() { REMOTE11="$T/remote-ab" LOOMWRIGHT_LANES_META_SYNC="$T/meta-f11.sh" LOOMWRIGHT_LANES_HELPERS="$SC/automate-helpers.sh" \
  LOOMWRIGHT_LANES_TRAIL="$T/ab-spy.sh" LOOMWRIGHT_GH_BIN="$T/ab-gh" bash "$S" "$@" 2>&1; }
# ab_lane <n> <item> <pr> — a launched-then-exited lane holding <item> pending (its af/37-shaped prose
# quotes the sentinel inline) and a jobs/done/ brief pointing at it.
ab_lane() {
  run lane-create "$RF5" reqs/a.md "$1" >/dev/null; ABL="$LR5/L$1"; ABRF="$ABL/.supervisor/automate/$PARENT5-L$1.md"
  LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$ABL" --owner-command "$OWN" >/dev/null; wait_gone "$ABL"
  mkdir -p "$ABL/$(dirname "$2")" "$ABL/.supervisor/jobs/done"
  printf '# ab\n\n## Status: pending\n\n## Problem\nThe old guard matched `<!-- loomwright:requirement-closeout -->` quoted in prose.\n' > "$ABL/$2"
  printf '# brief\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$2" "$3" > "$ABL/.supervisor/jobs/done/2026-10-10-L$1.md"
}
ab_rf() { # <runfile> <lane n> <item> <pr> <status> <pause_reason>
  printf '# Automate Run: %s-L%s\n\n## Status: paused\n\n## Source\n- backlog: lane\n\n## Run Config\n- limit: 1\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: %s | branch: feature/ab\n- pause_reason: %s\n\n## Progress\n- 2026-10-10T00:00:00Z drain READY\n' \
    "$PARENT5" "$2" "$3" "$3" "$5" "$4" "$6" > "$1"
}
RAB=".supervisor/requirements/t/ab.md"; PRAB="https://github.com/o/r/pull/57"
ab_lane 7 "$RAB" "$PRAB"; L57="$ABL"; RFAB="$ABRF"
ab_rf "$RFAB" 7 "$RAB" "$PRAB" ready_for_release ready_for_release
: > "$T_ABSPY"; QAB="$(cksum < "$L57/$RAB")"
out="$(STUB_PR_STATE=OPEN ab lane-convert-ready "$L57")"; rc=$?
check "AB1 ready_for_release converts (exit 0) to awaiting_merge" "$rc:$(cur_line "$RFAB")" \
  "0:- item: $RAB | status: awaiting_merge | pr: $PRAB | branch: feature/ab|- pause_reason: awaiting_merge|"
check "AB1b … with NO closeout call (spy) and no done stamp" "$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' '):$(cksum < "$L57/$RAB")" "0:$QAB"
SAB="$(cksum < "$RFAB")"
out="$(STUB_PR_STATE=OPEN ab lane-convert-ready "$L57")"; rc=$?
check "AB2 awaiting_merge re-run, PR still OPEN: exit 0, closeout called once with --no-trail inside the lane" \
  "$rc:$(grep -cxF "closeout $RFAB $RAB $PRAB --no-trail" "$T_ABSPY" | tr -d ' ')" "0:1"
has "AB2b … its evidence gate line echoed indented" "$out" "  closeout: skipped — pr not merged (awaiting_merge)"
check "AB2c … nothing written (requirement + run file byte-unchanged)" "$(cksum < "$L57/$RAB"):$(cksum < "$RFAB")" "$QAB:$SAB"
has "AB2d … the push still names the unmerged exclusion" "$out" "/2026-10-10-L7.md — pr not merged"
has "AB2e … and the last line names the gate leftover" "$(printf '%s\n' "$out" | tail -n1)" "; closeout leftover: gate — skipped — pr not merged (awaiting_merge)"
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L57")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
check "AB3 merged re-run exits 0 and its last line reads closeout complete" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '; closeout complete$' | tr -d ' ')" "0:1"
has "AB3b … closeout stamped the lane's requirement (a quoted sentinel is not a stamp)" "$out" "  closeout: stamped — $RAB"
has "AB3c … ran with --no-trail" "$out" "  trail-pr: skipped — --no-trail"
hasnt "AB3d … and the wave-end push no longer excludes the requirement" "$out" "excluded $RAB — pr not merged"
check "AB3e the lane requirement carries ONE sentinel-led ## Status: done" \
  "$(grep -A1 -xF '<!-- loomwright:requirement-closeout -->' "$L57/$RAB" | tr '\n' '|'):$(grep -cE '^## Status:[[:space:]]*done' "$L57/$RAB" | tr -d ' ')" \
  "<!-- loomwright:requirement-closeout -->|## Status: done|:1"
check "AB3f the lane run file reads - [x] <item> and ## Current done / awaiting_go (no current-set after closeout)" \
  "$(grep -cxF -- "- [x] $RAB" "$RFAB" | tr -d ' '):$(cur_line "$RFAB")" "1:- item: $RAB | status: done | pr: $PRAB | branch: feature/ab|- pause_reason: awaiting_go|"
check "AB3g the PUSHED run file carries both" \
  "$(grep -cxF -- "- [x] $RAB" "$T/remote-ab/.supervisor/automate/$PARENT5-L7.md" 2>/dev/null | tr -d ' '):$(cur_line "$T/remote-ab/.supervisor/automate/$PARENT5-L7.md" 2>/dev/null)" \
  "1:- item: $RAB | status: done | pr: $PRAB | branch: feature/ab|- pause_reason: awaiting_go|"
check "AB3h the PUSHED requirement carries the done stamp" "$(grep -cE '^## Status:[[:space:]]*done' "$T/remote-ab/$RAB" 2>/dev/null | tr -d ' ')" 1
ab_co="$(grep -n '^closeout ' "$T_ABSPY" | tail -n1 | cut -d: -f1)"; ab_tp="$(grep -n '^trail-pr ' "$T_ABSPY" | tail -n1 | cut -d: -f1)"
check "AB3i closeout ran BEFORE the wave-end trail push (spy order)" "$([ -n "$ab_co" ] && [ -n "$ab_tp" ] && [ "$ab_co" -lt "$ab_tp" ] && echo before)" before
check "AB3j no launch lock left behind" "$(ls -d "$P/.supervisor/automate/$PARENT5.lanes".L7.launch.lock 2>/dev/null | wc -l | tr -d ' ')" 0
SAB="$(cksum < "$RFAB")"; nco="$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')"; : > "$META_LOG"
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L57")"; rc=$?
check "AB4 a re-run on a closed-out lane (done / awaiting_go) is NOT refused (exit 0)" "$rc" 0
has "AB4b … it names that state and retries only the pushes" "$out" "already closed out (## Current done / awaiting_go) — retrying the metadata push only"
check "AB4c … no second closeout, no current-set (run file byte-unchanged), the pushes ran" \
  "$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' '):$(cksum < "$RFAB"):$(grep -c ' push ' "$META_LOG" | tr -d ' ')" "$nco:$SAB:2"
out="$(ab lane-status "$RF5")"; rc=$?
check "AB5 lane-status reads the closed-out lane without error" "$rc:$(printf '%s\n' "$out" | grep -c 'L7' | tr -d ' ' | sed 's/^[1-9][0-9]*$/seen/')" "0:seen"
out="$(ab lane-park-notify "$RFAB")"; rc=$?
check "AB5b lane-park-notify keeps skipping a non-ready_for_release file" "$rc:$(printf '%s' "$out" | grep -c '^lane-park-notify: skipped — ' | tr -d ' ')" "0:1"
out="$(ab lane-remove "$L57")"; rc=$?
check "AB5c lane-remove passes after the closed-out lane's push and removes it" "$rc:$([ -d "$L57" ] && echo kept || echo removed)" "0:removed"
# AB6 a closeout leftover inside the lane (its sync refused: the lane clone is on another branch) is
# echoed and named in the last line, and never changes the exit code; the stamp still lands.
RAB8=".supervisor/requirements/t/ab8.md"; PRAB8="https://github.com/o/r/pull/58"
ab_lane 8 "$RAB8" "$PRAB8"; L58="$ABL"; RFAB8="$ABRF"
git -C "$L58" checkout -q -b scratch
ab_rf "$RFAB8" 8 "$RAB8" "$PRAB8" awaiting_merge awaiting_merge
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L58")"; rc=$?
check "AB6 a closeout sync leftover in the lane keeps exit 0" "$rc" 0
has "AB6b … the sync skip is echoed indented" "$out" "  closeout: skipped — primary checkout is on scratch (neither main nor the PR head)"
has "AB6c … and named in the last line" "$(printf '%s\n' "$out" | tail -n1)" "; closeout leftover: sync — skipped — primary checkout is on scratch (neither main nor the PR head)"
check "AB6d … the requirement is still stamped" "$(grep -cE '^## Status:[[:space:]]*done' "$L58/$RAB8" | tr -d ' ')" 1

# AB7 an awaiting_merge re-run whose ## Current carries no pr: closeout is not run, and the last line says so.
RAB9=".supervisor/requirements/t/ab9.md"
ab_lane 9 "$RAB9" "-"; L59="$ABL"; RFAB9="$ABRF"
ab_rf "$RFAB9" 9 "$RAB9" null awaiting_merge awaiting_merge
nco="$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')"
out="$(STUB_PR_STATE=MERGED ab lane-convert-ready "$L59")"; rc=$?
check "AB7 no ## Current pr ⇒ exit 0, no closeout call" "$rc:$(grep -c '^closeout ' "$T_ABSPY" | tr -d ' ')" "0:$nco"
has "AB7b … and the last line says closeout was not run" "$(printf '%s\n' "$out" | tail -n1)" "; closeout not run (## Current has no pr)"
# AB8 metadata mode off: the merged re-run still closes the lane out; the mode-off line gains only the summary.
RAB10=".supervisor/requirements/t/ab10.md"; PRAB10="https://github.com/o/r/pull/60"
ab_lane 10 "$RAB10" "$PRAB10"; L510="$ABL"; RFAB10="$ABRF"
ab_rf "$RFAB10" 10 "$RAB10" "$PRAB10" awaiting_merge awaiting_merge
out="$(STUB_MODE_LINE=off STUB_PR_STATE=MERGED ab lane-convert-ready "$L510")"; rc=$?
check "AB8 mode off: the merged re-run exits 0 with the mode-off line + the closeout summary" "$rc:$(printf '%s\n' "$out" | tail -n1)" \
  "0:lane-convert-ready: converted L10 to awaiting_merge (metadata mode off — no metadata branch to push); closeout complete"
check "AB8b … and the lane requirement is stamped" "$(grep -cE '^## Status:[[:space:]]*done' "$L510/$RAB10" | tr -d ' ')" 1

hasnt "Z1 gh never called" "$(cat "$GH_CALLS" 2>/dev/null)" "gh"
# AA-F12z (final leg): nothing this suite started may outlive it — no process whose command line names
# the suite dir $T (pgrep -f on the ERE-escaped path), after the same stop the EXIT trap performs.
for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
i=0; while pgrep -f "$(ere "$T")" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
AA_LEFT="$(for p in $(pgrep -f "$(ere "$T")" 2>/dev/null); do ps -o pid= -o command= -p "$p" 2>/dev/null; done)"
check "AA-F12z no process naming the suite dir survives the suite" "${AA_LEFT:-none}" none
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
