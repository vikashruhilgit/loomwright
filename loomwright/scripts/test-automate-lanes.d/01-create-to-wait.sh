# af/39e: every lane / phase launch registers in proc-registry.sh — the suite's own registry under $T (sourced at
# top level, so it holds for every later part), never the real home
export LOOMWRIGHT_PROC_REGISTRY_DIR="$T/procs"

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
check "E3 --parallel 1 --auto-merge refused (a single lane never runs the merge gate)" "$(run init-check --parallel 1 --auto-merge)" "refuse: auto_merge_with_parallel"
check "E4 --parallel 11 out of range" "$(run init-check --parallel 11)" "refuse: parallel_out_of_range"
check "E5 --parallel 0 out of range" "$(run init-check --parallel 0)" "refuse: parallel_out_of_range"
check "E6 --parallel 10 ok" "$(run init-check --parallel 10)" ok
# E7-E9 single-lane mode (twin-remediation/08b): N = 1 needs branch mode ON (setup-memory.sh mode through the
# SETUP_MEMORY seam); anything but `on <branch>` refuses (fail CLOSED); N > 1 never reads the mode.
out="$(STUB_MODE_LINE=off run init-check --parallel 1)"; rc=$?
check "E7 --parallel 1 with branch mode off ⇒ refuse: single_lane_requires_branch_mode (exit 1)" "$rc:$out" "1:refuse: single_lane_requires_branch_mode"
check "E7b … mode unknown ⇒ refused" "$(STUB_MODE_LINE='unknown no line' run init-check --parallel 1)" "refuse: single_lane_requires_branch_mode"
printf '#!/usr/bin/env bash\necho "mode-read $*" >> "$E_MODE_LOG"; exit 1\n' > "$T/mode-fail.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/mode-empty.sh"
chmod +x "$T/mode-fail.sh" "$T/mode-empty.sh"; export E_MODE_LOG="$T/mode-read.log"; : > "$E_MODE_LOG"
check "E7c … a failing reader / an empty answer ⇒ refused" \
  "$(LOOMWRIGHT_LANES_SETUP_MEMORY="$T/mode-fail.sh" run init-check --parallel 1):$(LOOMWRIGHT_LANES_SETUP_MEMORY="$T/mode-empty.sh" run init-check --parallel 1)" \
  "refuse: single_lane_requires_branch_mode:refuse: single_lane_requires_branch_mode"
check "E7d … the reader got --root = this checkout's top level" "$(head -1 "$E_MODE_LOG")" "mode-read --root $(git rev-parse --show-toplevel 2>/dev/null || pwd) mode"
out="$(run init-check --parallel 1)"; rc=$?
check "E8 --parallel 1 with branch mode on <branch> ⇒ ok" "$rc:$out" "0:ok"
: > "$E_MODE_LOG"
check "E9 N > 1 makes NO mode read: outputs byte-identical to base, the loud stub never called" \
  "$(for a in '--parallel 2' '--parallel 10' '--parallel 2 --auto-merge' '--parallel 11'; do
       # shellcheck disable=SC2086
       LOOMWRIGHT_LANES_SETUP_MEMORY="$T/mode-fail.sh" run init-check $a; done | tr '\n' '|'):$(wc -l < "$E_MODE_LOG" | tr -d ' ')" \
  "ok|ok|refuse: auto_merge_with_parallel|refuse: parallel_out_of_range|:0"

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
out="$(LOOMWRIGHT_MACHINE_LOAD_CMD="$T/absent-load.sh" CLAUDECODE=1 CLAUDE_PID=4242 LOOMWRIGHT_HOLDER_PID=4242 run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
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
# H1b-H1e: the background-work rules L8 broke on 2026-10-16 (see LANE_SYS's comment), each pinned in the spawned prompt.
has "H1b the lane is told a turn end waits on background tasks (never that it stops them)" "$first" "this process does not exit until every background task has finished, and a finished background task starts another turn"
has "H1c … that a timed-out Bash call is moved to the background, so wait loops carry a deadline" "$first" "every wait loop needs its own deadline, shorter than the call's timeout"
has "H1d … never to poll a subagent's transcript" "$first" "Never poll a subagent's transcript or output files"
has "H1e … to stop background tasks before asking the owner" "$first" "Before you ask the owner, stop every background task still running"
hasnt "H1f the false claim that ending the turn stops background tasks is gone" "$first" "stops any background task"
has "H2 disallow carries the merge command" "$first" "Bash(gh pr merge:*)"
has "H3 disallow carries force push" "$first" "Bash(git push --force:*)"
has "H4 disallow carries a push to the base branch" "$first" "Bash(git push origin main:*)"
has "H4b disallow carries the REST merge endpoint via gh api" "$first" "Bash(gh api *pulls/*/merge*)"
has "H4c disallow carries the GraphQL merge mutation via gh api" "$first" "Bash(gh api *mergePullRequest*)"
has "H4d disallow carries the GraphQL auto-merge mutation via gh api" "$first" "Bash(gh api *enablePullRequestAutoMerge*)"
hasnt "H4e gh api graphql itself is not blanket-denied" "$first" "Bash(gh api graphql"
hasnt "H5 no non-interactive fallback flag" "$first" "non-interactive"
has "H6 env: ceiling 0, CLAUDECODE and CLAUDE_PID unset" "$(grep '^ENV' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "CEIL=0 CC=unset PID=unset"
check "H6b env: the coordinator's LOOMWRIGHT_HOLDER_PID (set on the launch) is unset for the lane" "$(grep '^HOLDERENV' "$STUB_LOG" | sed -n "$((n0 + 1))p")" "HOLDERENV unset"
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
# H15 — the vendor-neutral root arm (twin-remediation/11): with the harness variable unset (the suite
# unsets it above), a pre-set LOOMWRIGHT_ROOT is the plugin dir the lane is pinned to. H1 covers the
# other side: nothing pre-set ⇒ the location-derived root.
out="$(LOOMWRIGHT_ROOT="$T/neutral-root" LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L1" --owner-command "$OWN")"
has "H15 pre-set LOOMWRIGHT_ROOT pins --plugin-dir" "$(grep '^ARGS' "$STUB_LOG" | tail -1)" "[--plugin-dir] [$T/neutral-root]"
wait_gone "$L1"

# ---- I: coordinator never writes into a launched lane (checksum) + mutation control ------------------
check "I1 lane checksum unchanged across launches" "$(lane_sum "$L1")" "$SUM_L1_BEFORE"
MUT="$T/mut"; mkdir -p "$MUT"
awk '{ print } /# >>> spawn/ { print "  touch \"$LN_DIR/.coordinator-write\"" }' "$SB" > "$MUT/automate-lanes.sh"
LOOMWRIGHT_LANE_RECHECK_S=0 bash "$MUT/automate-lanes.sh" lane-launch "$L1" --owner-command "$OWN" >/dev/null 2>&1
wait_gone "$L1"
if [ "$(lane_sum "$L1")" != "$SUM_L1_BEFORE" ]; then ok "I2 mutation (coordinator write after launch) fails the checksum"; else bad "I2 mutation control did not trip"; fi
rm -f "$L1/.coordinator-write"

# ---- I3–I8 (af/39e AC14/AC16): lane-launch registers ONE `lane` entry for the _lane-run wrapper ---------------
# A sleeping stub keeps the wrapper alive past the registration; each launch is TERMed afterwards (the wrapper
# then records a .died for the session it lost — removed below, it is this leg's artifact, not L1's history).
# Every registry here is the leg's own dir under $T; the suite-wide one (above) is never read.
lane_entries() { { cat "$1"/*.json 2>/dev/null || true; } | jq -c -s '[.[] | select(.kind == "lane")]' 2>/dev/null; }
lane_reg_stop() { kill -TERM "$(tcol L1 5)" 2>/dev/null; wait_gone "$L1"; rm -f "$LR/L1.died"; }
PRG="$T/procs-lane"
out="$(STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 LOOMWRIGHT_PROC_REGISTRY_DIR="$PRG" run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
LPID="$(tcol L1 5)"
LCLS="$(LOOMWRIGHT_PROC_REGISTRY_DIR="$PRG" bash "$HERE/proc-registry.sh" list | awk -F'\t' '$2 == "lane" { print $5 }')"
lane_reg_stop
check "I3 lane-launch registers ONE lane entry: pid = the _lane-run wrapper, lane = the lane dir, run id, the 24h default cap" \
  "$rc|$(lane_entries "$PRG" | jq -r '[length, (.[0].pid | tostring), .[0].lane, .[0].run_id, (.[0].max_lifetime_s | tostring), ((.[0].stop_hint // "") | test("^kill -TERM [0-9]+ ")) | tostring] | join("|")')" \
  "0|1|$LPID|$L1|$PARENT-L1|86400|true"
check "I4 … hashed after the exec: the live wrapper classified running" "$LCLS" running
LOUT_OK="$(printf '%s\n' "$out" | sed 's/pid [0-9][0-9]*/pid N/')"
: > "$T/procs-not-a-dir"
out="$(STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 LOOMWRIGHT_PROC_REGISTRY_DIR="$T/procs-not-a-dir" run lane-launch "$L1" --owner-command "$OWN")"; rc=$?
lane_reg_stop
check "I5 an unwritable registry still launches: exit and output unchanged" "$rc|$(printf '%s\n' "$out" | sed 's/pid [0-9][0-9]*/pid N/')" "0|$LOUT_OK"
# I6/I7 mutation control (AC16): a bundle copy WITH proc-registry.sh beside it registers (the positive control from
# that location); the same copy minus launch.sh's ONE registration line registers nothing
lm_count="$(grep -c 'proc-registry.sh" register --pid "$pid" --kind lane' "$SB" | tr -d ' ')"
mkdir -p "$T/lreg-ok" "$T/lreg-mut"; ln -sf "$HERE/proc-registry.sh" "$T/lreg-ok/proc-registry.sh"; ln -sf "$HERE/proc-registry.sh" "$T/lreg-mut/proc-registry.sh"
cp "$SB" "$T/lreg-ok/automate-lanes.sh"
grep -v 'proc-registry.sh" register --pid "$pid" --kind lane' "$SB" > "$T/lreg-mut/automate-lanes.sh"
if [ "$lm_count" = 1 ] && [ -s "$T/lreg-mut/automate-lanes.sh" ] && ! cmp -s "$SB" "$T/lreg-mut/automate-lanes.sh" && bash -n "$T/lreg-mut/automate-lanes.sh"; then
  STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 LOOMWRIGHT_PROC_REGISTRY_DIR="$T/procs-lane-ok" bash "$T/lreg-ok/automate-lanes.sh" lane-launch "$L1" --owner-command "$OWN" >/dev/null 2>&1
  lane_reg_stop
  STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 LOOMWRIGHT_PROC_REGISTRY_DIR="$T/procs-lane-mut" bash "$T/lreg-mut/automate-lanes.sh" lane-launch "$L1" --owner-command "$OWN" >/dev/null 2>&1
  lane_reg_stop
  check "I6 mutation control: the unmutated bundle copy registers one lane entry, the copy minus the registration line none" \
    "$(lane_entries "$T/procs-lane-ok" | jq length):$(lane_entries "$T/procs-lane-mut" | jq length)" "1:0"
else
  bad "I6 lane-registration mutant not built (registration lines in the bundle: $lm_count)"
fi
check "I7 I1 still holds: the registry writes nothing into the lane (checksum unchanged)" "$(lane_sum "$L1")" "$SUM_L1_BEFORE"

# ---- J: relay hook (AC6) ----------------------------------------------------------------------------
Q2='[{"question":"Which color?","header":"Color","multiSelect":false,"options":[{"label":"Red","description":"r"},{"label":"Blue","description":"b"}]},{"question":"Which extras?","header":"Extras","multiSelect":true,"options":[{"label":"A","description":"a"},{"label":"B","description":"b"},{"label":"C","description":"c"}]}]'
hook_in() { jq -n -c --arg ev "$1" --arg cwd "$2" --arg id "$3" --argjson q "${4:-$Q2}" '{hook_event_name: $ev, cwd: $cwd, tool_use_id: $id, tool_name: "AskUserQuestion", tool_input: {questions: $q}}'; }
out="$(hook_in PermissionRequest "$L2" toolu_q1 | bash "$S" relay-hook)"
check "J1 bundled call denied" "$(jq -r '.hookSpecificOutput.decision.behavior' <<<"$out")" deny
out="$(hook_in PreToolUse "$L2" toolu_q1 | bash "$S" relay-hook)"
check "J2 unanswered question ⇒ defer" "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out")" defer
J2_DEFER="$out"   # the pre-policy defer, byte for byte (AD5–AD9b compare against it)
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
awk '/# >>> awaiting-input check/ { skip = 1 } !skip { print } /# <<< awaiting-input check/ { skip = 0 }' "$SB" > "$MUT/automate-lanes.sh"
out="$(bash "$MUT/automate-lanes.sh" lane-remove "$L2" 2>&1)"
hasnt "N2 mutation (awaiting_input check deleted) no longer refuses" "$out" "awaiting_input"
rm -rf "$L2"
# live-process mutation on a fresh lane
run lane-create "$RF" reqs/a.md 3 >/dev/null; L3="$LR/L3"
STUB_MODE=sleep LOOMWRIGHT_LANE_RECHECK_S=0 run lane-launch "$L3" --owner-command "$OWN" >/dev/null
L3P="$(tcol L3 5)"
awk '/# >>> live-process check/ { skip = 1 } !skip { print } /# <<< live-process check/ { skip = 0 }' "$SB" > "$MUT/automate-lanes.sh"
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
# N6c-N6f the `status --paths` naming cap (_lanes_status_named): at most five paths, then `+<k> more`;
# exactly five reads no `more`; a control with the cap removed lists all seven (N6c's line fails).
N6P7="$(printf 'local_ahead 7\n  a.md\n  b.md\n  c.md\n  d.md\n  e.md\n  f.md\n  g.md')"
out="$(STUB_META_STATUS="$N6P7" run lane-remove "$L4")"
check "N6c seven unpushed paths: five named, then +2 more" "$(printf '%s\n' "$out" | grep 'metadata not pushed' | sed 's/^.* — metadata/metadata/')" \
  "metadata not pushed (local_ahead 7) — paths: a.md, b.md, c.md, d.md, e.md, +2 more"
out="$(STUB_META_STATUS="$(printf 'local_ahead 5\n  a.md\n  b.md\n  c.md\n  d.md\n  e.md')" run lane-remove "$L4")"
check "N6d exactly five paths: all named, no +k more" "$(printf '%s\n' "$out" | grep 'metadata not pushed' | sed 's/^.* — metadata/metadata/')" \
  "metadata not pushed (local_ahead 5) — paths: a.md, b.md, c.md, d.md, e.md"
sed "s/sed 's\/^  \/\/' | head -5 /sed 's\/^  \/\/' /" "$SB" > "$MUT/automate-lanes.sh"
check "N6e mutation removed the five-path cap" "$(grep -c "sed 's/^  //' | head -5 " "$MUT/automate-lanes.sh" | tr -d ' ')" 0
out="$(STUB_META_STATUS="$N6P7" bash "$MUT/automate-lanes.sh" lane-remove "$L4" 2>&1)"
has "N6f mutation: without the cap all seven are listed (N6c's expected line would fail)" "$out" "paths: a.md, b.md, c.md, d.md, e.md, f.md, g.md, +2 more"
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
tcol2() { awk -F'\t' -v l="$1" -v c="$2" '$1 == l { print $c }' "$TABLE2"; }
cat > "$T/pgrep-stub" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *caffeinate*) [ -n "${STUB_CAFF_HELD:-}" ] && { echo 777; exit 0; }; exit 1 ;;
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
export LOOMWRIGHT_LANES_PGREP="$T/pgrep-stub" LOOMWRIGHT_LANES_CI_SLOT="$T/ci-stub.sh"
export LOOMWRIGHT_LANES_CAFFEINATE="$T/caff-stub" CAFF_LOG="$T/caff.log" LOOMWRIGHT_LANES_BOOT_EPOCH=1000000000
export LOOMWRIGHT_LANES_UNAME=Darwin LOOMWRIGHT_LANES_COORDINATOR_PID=4242
# pmset stub: prints $PMSET_OUT's content (none by default), so the real Mac's power assertions — the
# Claude desktop app holds one while it works — never leak into keep_awake.
printf '%s\n' '#!/usr/bin/env bash' '[ "$*" = "-g assertions" ] && [ -s "${PMSET_OUT:-}" ] && cat "$PMSET_OUT"; exit 0' > "$T/pmset-stub"
chmod +x "$T/pmset-stub"; export LOOMWRIGHT_LANES_PMSET="$T/pmset-stub" PMSET_OUT="$T/pmset.out"
: > "$CAFF_LOG"; : > "$PMSET_OUT"
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
# Q3c–Q3h: the answer-relaunch gap (wave 7, run automate-2026-10-15-163325 — lane-wait printed `state L21
# stalled`, L23, L24, each running seconds later). lane-answer writes the answer file, then spawns the
# resume: between the two the lane has no live process, no pending question and no park. L3's last result
# is a deferred question; its answer file's `at` decides the gap (LOOMWRIGHT_LANES_RESUME_GRACE_S).
QIB="$LR2/L3/.supervisor/inbox"; mkdir -p "$QIB/questions" "$QIB/answers"
jq -n -c --argjson q "$Q2" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-q3", deferred_tool_use: {id: "toolu_s1", input: {questions: $q}}}' > "$LR2/L3.stream.log"
jq -n -c --argjson q "$Q2" '{questions: $q, asked_at: "2026-10-15T00:00:00Z"}' > "$QIB/questions/toolu_s1.json"
J="$(sj)"; check "Q3c deferred, unanswered ⇒ awaiting_input (unchanged)" "$(lf L3 .state)" awaiting_input
jq -n -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{answers: {"Which color?": "Red"}, note: null, source: "human", via: "test", at: $at}' > "$QIB/answers/toolu_s1.json"
J="$(sj)"
check "Q3d answered seconds ago, resume not yet visible ⇒ running, not stalled" "$(lf L3 .state)" running
has "Q3e … its reason names the answer it resumes after" "$(lf L3 .reason)" "resuming after answer toolu_s1 (written "
out="$(run lane-wait "$RF2" --interval 1 --timeout 3)"   # L4's blocked_launch is an event: one poll, then exit
has "Q3f lane-wait polled (reports the other lanes' events) …" "$out" "lane-wait: state L4 blocked_launch"
hasnt "Q3f-b … and reports no stalled event for the resuming lane" "$out" "state L3 "
check "Q3f-c the Stop hook's quick classifier reads it running too" \
  "$( ( . "$S"; _lanes_quick_state "$LR2/L3" "$(tcol2 L3 5)" "$(tcol2 L3 6)" "$(tcol2 L3 8)" "" ) 2>/dev/null)" running
rm -f "$P/.supervisor/automate/$PARENT2.lane-wait-seen"
J="$(LOOMWRIGHT_LANES_RESUME_GRACE_S=0 sj)"
check "Q3g past the grace with no resumed process ⇒ stalled, naming the answer" "$(lf L3 '.state + "|" + .reason')" \
  "stalled|process gone after answer toolu_s1 (written $(jq -r .at "$QIB/answers/toolu_s1.json")), no resumed process — resume once with lane-launch --continue"
# Q3h mutation control: the in-flight branch dropped reproduces wave 7's false stalled
awk '/elif rs="\$\(_lanes_resume_in_flight / { skip = 2 } skip > 0 { skip--; next } { print }' "$SB" > "$MUT/lanes-q3h.sh"
check "Q3h-a mutation removed the in-flight branch" "$(grep -c 'resuming after answer' "$MUT/lanes-q3h.sh" | tr -d ' ')" 0
check "Q3h mutation: the answered lane reads stalled (the wave 7 incident)" \
  "$(bash "$MUT/lanes-q3h.sh" lane-status "$RF2" --json 2>/dev/null | jq -r '.lanes[] | select(.lane == "L3") | .state')" stalled
rm -rf "$QIB" "$LR2/L3.stream.log"
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
out="$(run lane-status "$RF2")"; rc=$?
has "Q10 plain view: one line per lane with state and item" "$out" "L4  blocked_launch (auto-mode classifier denied the spawn)  item=reqs/a.md"
# Q10c–Q10f (automate-speed/24): the DEFAULT plain view is terse — the header line plus each lane's first
# line, nothing else; `--verbose` is the full _lanes_render view, and its header + lane lines are exactly
# the default's (one shared jq def each, _LANES_RENDER_HEAD).
vout="$(run lane-status "$RF2" --verbose)"
check "Q10c default plain view = header + one line per lane (7 lanes), exit 0" \
  "$rc:$(printf '%s\n' "$out" | wc -l | tr -d ' '):$(printf '%s\n' "$out" | sed 1d | grep -vc '^L[0-9][0-9]*  ' | tr -d ' '):$(printf '%s\n' "$out" | head -1 | grep -c "^lane-status: $PARENT2 — 7 lane(s) — ")" "0:8:0:1"
check "Q10d the default's lane lines are the --verbose view's lane lines" "$(printf '%s\n' "$out" | sed 1d)" "$(printf '%s\n' "$vout" | grep '^L[0-9][0-9]*  ')"
has "Q10b --verbose shows held for load" "$vout" "held for load: load overloaded"
hasnt "Q10e the default drops the indented detail lines (held for load)" "$out" "    held for load:"
hasnt "Q10f the default drops the machine line" "$out" "machine: state="
# Q10g / Q10h: exact bytes — the committed fixture status document (fixtures/terse-output/lane-status/
# status.json) rendered by the module's _lanes_render equals verbose.golden, captured from the PRE-change
# (base ee3d7ea) _lanes_render on the same document; _lanes_render_terse equals default.golden.
TG="$HERE/fixtures/terse-output/lane-status"
tg_v="$( . "$HERE/automate-lanes.d/status-read.sh" && _lanes_render "$(cat "$TG/status.json")"; echo x)"
tg_d="$( . "$HERE/automate-lanes.d/status-read.sh" && _lanes_render_terse "$(cat "$TG/status.json")"; echo x)"
check "Q10g --verbose renderer is byte-identical to the pre-change plain view (verbose.golden)" "$tg_v" "$(cat "$TG/verbose.golden"; echo x)"
check "Q10h terse renderer = header + each lane's first line (default.golden)" "$tg_d" "$(cat "$TG/default.golden"; echo x)"
check "Q10i default.golden is verbose.golden's header + lane lines" "$(cat "$TG/default.golden")" "$(sed -n '1p; /^L[0-9][0-9]*  /p' "$TG/verbose.golden")"
# Q10j: unreadable status (every jq call fails ⇒ no status document) ⇒ the ONE fail-safe line, exit 0.
mkdir -p "$T/nojq"; printf '#!/usr/bin/env bash\nexit 1\n' > "$T/nojq/jq"; chmod +x "$T/nojq/jq"
out="$(PATH="$T/nojq:$PATH" run lane-status "$RF2")"; rc=$?
check "Q10j unreadable status ⇒ one 'lane-status: unknown — status unreadable' line, exit 0" "$rc:$out" "0:lane-status: unknown — status unreadable"
check "Q11 liveness is not redefined (one lanes_proc_alive)" "$(grep -c '^lanes_proc_alive()' "$SB")" 1
out="$(run lane-status "$P/.supervisor/automate/none.md" --json)"; rc=$?
check "Q12 no lane table ⇒ empty lanes, exit 0" "$rc:$(jq -r '.lanes | length' <<<"$out")" "0:0"

# ---- R: lane-status --json fields (AC8: machine, asked_at / waiting_s, last_message, CI slot) -----------
L6="$LR2/L6"; t2set L6 8 launched; t2set L6 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"id":"toolu_r1","asked_at":"2026-10-07T00:00:00Z","questions":[{"question":"Which path?","header":"Path","options":[{"label":"A","description":"the first"},{"description":"no label: dropped"}]},{"question":"Which checks?","multiSelect":true,"options":[{"label":"x, y"},{"label":"z"}]}]}\n' > "$L6/.supervisor/inbox/questions/toolu_r1.json"
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
# items (parallel-automate/14): every question of the call, in answer-key order, with exactly the labels
# lane-answer accepts — what a client draws its option buttons from without reading the lane's files.
check "R13 items: one per question, in order" "$(lf L6 '.questions[0].items | map(.question) | join("|")')" "Which path?|Which checks?"
check "R14 items carry header, multiSelect and descriptions" \
  "$(lf L6 '.questions[0].items | map("\(.header)/\(.multiSelect)/\(.options | map(.label + "=" + (.description // "-")) | join(","))") | join(" ; ")')" \
  "Path/false/A=the first ; null/true/x, y=-,z=-"
check "R15 question (first text) kept beside items" "$(lf L6 '.questions[0].question')" "Which path?"
check "R16 no ## Current branch ⇒ branch null" "$(lf L6 '.branch')" null

# ---- S: keep-awake (suggest, never silently start) --------------------------------------------------
out="$(run lane-status "$RF2" --verbose)"
has "S1 macOS: one-line caffeinate suggestion with the coordinator pid" "$out" "caffeinate -i -w 4242"
has "S2 keep-awake: not held" "$out" "keep-awake: not held"
check "S3 no keep-awake process started without --keep-awake" "$(wc -l < "$CAFF_LOG" | tr -d ' ')" 0
hasnt "S4 other OS: no suggestion" "$(LOOMWRIGHT_LANES_UNAME=Linux run lane-status "$RF2" --verbose)" "caffeinate -i -w"
out="$(STUB_CAFF_HELD=1 run lane-status "$RF2" --verbose)"
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
# S7-S11: keep-awake is read from macOS power assertions, not only a `caffeinate` process. The desktop
# app's "Keep computer awake while Claude works" hold is a NoIdleSleepAssertion owned by `Claude` — the
# machine IS held, but only while a Code session works (headless lanes are not Code sessions), so the
# caffeinate suggestion stays and --keep-awake still starts one.
pm_line() { printf '   pid %s(%s): [0x0006137400018c52] 01:11:43 %s named: "%s"  \n' "$@"; }
{ echo 'Listed by owning process:'; pm_line 39844 Claude NoIdleSleepAssertion Electron
  pm_line 341 powerd PreventUserIdleSystemSleep 'Powerd - Prevent sleep while display is on'; } > "$PMSET_OUT"
J="$(sj)"
check "S7 Claude app assertion ⇒ held, not lasting, one claude-app holder (powerd's own hold ignored)" \
  "$(jq -r '.machine | "\(.keep_awake)|\(.keep_awake_lasting)|\([.keep_awake_holders[] | .process + ":" + .kind] | join(","))"' <<<"$J")" \
  "held|false|Claude:claude-app"
out="$(run lane-status "$RF2" --verbose)"
has "S8 plain view names the app hold and its limit" "$out" "keep-awake: held (Claude app — only while a Code session works)"
has "S8b the app hold alone keeps the caffeinate suggestion" "$out" "keep-awake suggestion (run it yourself, or lane-status --keep-awake): caffeinate -i -w 4242"
: > "$CAFF_LOG"; out="$(run lane-status "$RF2" --keep-awake)"
wait_for_file_content "$CAFF_LOG" "caffeinate -i -w 4242" 15 || bad "S9 wait" "no caffeinate start with only the app hold"
has "S9 --keep-awake still starts caffeinate when only the app holds" "$(cat "$CAFF_LOG")" "caffeinate -i -w 4242"
pm_line 777 caffeinate PreventUserIdleSystemSleep 'caffeinate command-line tool' >> "$PMSET_OUT"
J="$(sj)"; out="$(run lane-status "$RF2" --verbose)"
check "S10 a caffeinate assertion ⇒ lasting, no suggestion" \
  "$(jq -r .machine.keep_awake_lasting <<<"$J"):$(printf '%s' "$out" | grep -c 'suggestion')" "true:0"
: > "$CAFF_LOG"; out="$(run lane-status "$RF2" --keep-awake)"
check "S10b --keep-awake with a caffeinate already holding starts none" "$(wc -l < "$CAFF_LOG" | tr -d ' '):$(printf '%s' "$out" | grep -c 'already held')" "0:1"
{ echo 'Listed by owning process:'; pm_line 639 sharingd PreventUserIdleSystemSleep Handoff; } > "$PMSET_OUT"
J="$(sj)"
check "S11 a transient daemon assertion is listed but never makes it held" \
  "$(jq -r '.machine | "\(.keep_awake)|\(.keep_awake_holders | length)|\(.keep_awake_holders[0].kind)"' <<<"$J")" "not held|1|other"
: > "$PMSET_OUT"; : > "$CAFF_LOG"

# ---- T: --watch, lane-feed ----------------------------------------------------------------------------
out="$(LOOMWRIGHT_LANES_WATCH_ITERATIONS=1 run lane-status "$RF2" --watch)"; rc=$?
check "T1 --watch one iteration exits 0" "$rc" 0
has "T1b frame header" "$out" "lane-status --watch"
has "T1c frame carries the fleet" "$out" "L6  awaiting_input"
# T1d / T1e (automate-speed/24): --watch keeps the FULL view (_lanes_watch passes --verbose on both
# branches), with a runfile and without one (the newest lane table under the cwd's checkout).
has "T1d --watch <runfile> shows the full view (machine line)" "$out" "machine: state="
out="$(cd "$P" && LOOMWRIGHT_LANES_WATCH_ITERATIONS=1 bash "$S" lane-status --watch 2>&1)"; rc=$?
check "T1e --watch with no runfile shows the full view (machine line), exit 0" "$rc:$(printf '%s\n' "$out" | grep -c '^machine: state=' | tr -d ' ')" "0:1"
out="$(LOOMWRIGHT_LANES_WATCH_ITERATIONS=2 LOOMWRIGHT_LANES_WATCH_INTERVAL_S=0 run lane-status "$RF2" --watch)"
check "T2 --watch refreshes" "$(printf '%s\n' "$out" | grep -c '^lane-status --watch')" 2

# ---- AH: lane-wait — the coordinator's lane watcher (a question no longer sits unseen) ---------------------
# Fleet at this point: L1 died · L2 running · L3 stalled · L4 blocked_launch · L5 held_for_load ·
# L6 awaiting_input (toolu_r1) · L7 created.
LWS="$P/.supervisor/automate/$PARENT2.lane-wait-seen"; rm -f "$LWS"
out="$(run lane-wait "$RF2" --interval 1 --timeout 5)"; rc=$?
check "AH1 a pending question ⇒ exits 0 at once" "$rc" 0
has "AH1b the question is named with lane, id and text" "$out" "lane-wait: question L6 toolu_r1 asked 2026-10-07T00:00:00Z — Which path?"
has "AH1c a died lane is an event" "$out" "lane-wait: state L1 died — pr -"
has "AH1d a stalled lane is an event" "$out" "lane-wait: state L3 stalled"
has "AH1e a blocked launch is an event" "$out" "lane-wait: state L4 blocked_launch"
hasnt "AH1f awaiting_input with its question is reported once, as the question" "$out" "state L6 awaiting_input"
hasnt "AH1g running / held / created lanes are not events" "$out" "state L2"
has "AH1h ends with the relay hint" "$(printf '%s\n' "$out" | tail -1)" "lane-wait: relay — show each question to the owner verbatim"
has "AH1i a mixed batch also carries the state act hint" "$out" "lane-wait: act — handle each state line"
check "AH2 the seen ledger records every printed key" "$(sort "$LWS" | tr '\n' ',')" "question L6 toolu_r1,state L1 died,state L3 stalled,state L4 blocked_launch,"
# AH16 the Stop hook's classifier (_lanes_quick_state: no gh, no ci-slot, a stream-log tail at most) names the same
# state as lane-status for every live / attention state; the states past awaiting_input read `other`.
ah16_full="$(bash "$S" lane-status "$RF2" --json 2>/dev/null | jq -r '.lanes[] | "\(.lane) \(.state)"' \
  | awk '{ s = $2; if (s !~ /^(answer_pending|blocked_launch|held_for_load|created|missing|running|awaiting_input)$/) s = "other"; print $1, s }')"
ah16_quick="$( ( . "$S"; while IFS="$(printf '\t')" read -r l p _ _ pid st _ ts _; do
  case "$l" in L[0-9]|L[0-9][0-9]) ;; *) continue ;; esac
  printf '%s %s\n' "$l" "$(_lanes_quick_state "$p" "$pid" "$st" "$ts" "$P/.supervisor/automate/$PARENT2.$l.answer-pending.json")"
done < "$TABLE2" ) )"
check "AH16 fixture: the fleet spans live, attention and other states" \
  "$(printf '%s\n' "$ah16_full" | awk '{ print $2 }' | sort -u | tr '\n' ' ')" "awaiting_input blocked_launch created held_for_load other running "
check "AH16a _lanes_quick_state agrees with lane-status lane by lane" "$ah16_quick" "$ah16_full"
echo "state L2 died" >> "$LWS"
out="$(run lane-wait "$RF2" --interval 1 --timeout 1)"; rc=$?
check "AH3 nothing new ⇒ waits, then times out (exit 0)" "$rc:$out" "0:lane-wait: timeout after 1s — nothing new"
check "AH3b a state key no longer true is pruned (re-entry reports again); questions are kept" \
  "$(grep -c '^state L2 died$' "$LWS"):$(grep -c '^question L6 toolu_r1$' "$LWS")" "0:1"
printf '{"id":"toolu_r2","asked_at":"2026-10-07T00:05:00Z","questions":[{"question":"Second ask?","options":[{"label":"A"}]}]}\n' > "$L6/.supervisor/inbox/questions/toolu_r2.json"
out="$(run lane-wait "$RF2" --interval 1 --timeout 5)"
check "AH4 a new question only ⇒ exactly that one event + the hint" "$(printf '%s\n' "$out" | grep -c '^lane-wait: ')" 2
has "AH4b … and it is the new id" "$out" "lane-wait: question L6 toolu_r2 asked 2026-10-07T00:05:00Z — Second ask?"
hasnt "AH4c a question-only batch carries no state act hint" "$out" "lane-wait: act"
rm -f "$L6/.supervisor/inbox/questions/toolu_r2.json"
out="$(run lane-wait)"; rc=$?
check "AH5 no run file ⇒ usage, exit 2" "$rc" 2
out="$(run lane-wait "$RF2" --interval 0)"; rc=$?
check "AH5b a zero interval is refused (never a busy loop)" "$rc" 2
out="$(run lane-wait "$P/.supervisor/automate/none.md")"; rc=$?
check "AH6 no lane table ⇒ idle, exit 0" "$rc" 0
has "AH6b … and says idle" "$out" "lane-wait: idle — no lane table"
out="$(bash "$HERE/automate-helpers.sh" lane-wait "$P/.supervisor/automate/none.md" 2>&1)"; rc=$?
check "AH6c dispatched through automate-helpers.sh" "$rc:$out" "0:lane-wait: idle — no lane table for $P/.supervisor/automate/none.md (nothing to watch)"
check "AH7 --help lists lane-wait" "$(bash "$S" --help | grep -c '^#   lane-wait <parent_runfile>' | tr -d ' ')" 1
# AH8 idle: a fleet with no live lane and nothing new must exit, never poll parked lanes forever.
PARENT3=automate-2026-10-07-140000; RF3="$P/.supervisor/automate/$PARENT3.md"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT3" > "$RF3"
run lane-create "$RF3" reqs/a.md 1 --parallel 2 >/dev/null
# AH10 the ledger's ONLY key is a state no longer true (L1 is `created`: live, not an event). With nothing
# new and nothing kept, the poll must still prune it — else the re-entered state is never reported again.
LWS3="$P/.supervisor/automate/$PARENT3.lane-wait-seen"; echo "state L1 blocked_launch" > "$LWS3"
out="$(run lane-wait "$RF3" --interval 1 --timeout 1)"; rc=$?
check "AH10 a lone stale key, one live lane, nothing new ⇒ times out" "$rc:$out" "0:lane-wait: timeout after 1s — nothing new"
check "AH10b … and that lone stale state key is pruned (ledger removed)" "$([ -e "$LWS3" ] && cat "$LWS3" || echo absent)" absent
run lane-launch "$T/work/primary-lanes/$PARENT3/L1" --host-denied 'denied' >/dev/null
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"
has "AH8a first call reports the blocked lane (AH10c: the re-entered state reports again)" "$out" "lane-wait: state L1 blocked_launch"
# AH11 the hint follows the events: a state-only batch says act-on-the-lane, never the question relay.
has "AH11a a state-only batch ends with the act hint" "$(printf '%s\n' "$out" | tail -1)" "lane-wait: act — handle each state line per the automate-loop skill §14"
hasnt "AH11b … and carries no question relay hint" "$out" "lane-wait: relay"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"; rc=$?
check "AH8b nothing live, nothing new ⇒ idle at once, exit 0" "$rc:$out" "0:lane-wait: idle — no lane is running; nothing changes until the owner acts"
# AH9 read-only toward lanes: a full lane-wait pass writes nothing but its own ledger.
before="$(find "$LR2" -type f -newer "$LWS" 2>/dev/null | wc -l | tr -d ' ')"
run lane-wait "$RF2" --interval 1 --timeout 1 >/dev/null
check "AH9 lane-wait writes nothing into any lane" "$(find "$LR2" -type f -newer "$LWS" 2>/dev/null | wc -l | tr -d ' ')" "$before"
# AH13 events are every state that is neither live nor quiet (a deny-list): `_lanes_parked` reports ANY
# run-file pause_reason as the lane's state, so a park the old allow-list never named (token_ceiling) must
# wake the coordinator, while a coordinator-driven park (awaiting_merge) must not. L1 (blocked_launch) was
# already reported above and stays in the ledger.
for n in 2 3; do run lane-create "$RF3" reqs/a.md "$n" --parallel 4 >/dev/null; done
TABLE3="$P/.supervisor/automate/$PARENT3.lanes"
t3set() { awk -F'\t' -v OFS='\t' -v l="$1" -v c="$2" -v v="$3" '$1 == l { $c = v } { print }' "$TABLE3" > "$TABLE3.t" && mv "$TABLE3.t" "$TABLE3"; }
ah_park() { # <lane> <status> <pause_reason> — a launched-then-exited lane whose run file is parked as given
  local d r; d="$(awk -F'\t' -v l="$1" '$1 == l { print $2 }' "$TABLE3")"; r="$(awk -F'\t' -v l="$1" '$1 == l { print $4 }' "$TABLE3")"
  t3set "$1" 8 launched; t3set "$1" 5 99999998; t3set "$1" 6 "Mon Jan  1 00:00:00 2001"; t3set "$1" 9 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$d/.supervisor/automate"
  printf '# Automate Run: %s\n\n## Status: paused\n\n## Current\n- item: reqs/a.md | status: %s | pr: null | branch: f\n- pause_reason: %s\n\n## Progress\n' "$r" "$2" "$3" > "$d/.supervisor/automate/$r.md"
}
ah_park L2 running token_ceiling; ah_park L3 awaiting_merge awaiting_merge
J="$(bash "$S" lane-status "$RF3" --json 2>/dev/null)"
check "AH13 fixture: L2 reads token_ceiling, L3 awaiting_merge" "$(lf L2 .state):$(lf L3 .state)" "token_ceiling:awaiting_merge"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"; rc=$?
check "AH13a an unlisted run-file park (token_ceiling) is an event, alone" "$rc:$(printf '%s\n' "$out" | grep '^lane-wait: state')" "0:lane-wait: state L2 token_ceiling — pr -"
hasnt "AH13b a coordinator-driven park (awaiting_merge) is not an event" "$out" "state L3"
has "AH13c … and the act hint names the owner's decision for any other state" "$out" "a run-file park such as token_ceiling — the owner decides"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"; rc=$?
check "AH13d a parked-but-quiet fleet with every event reported ⇒ idle at once (no loop, no re-report)" "$rc:$out" "0:lane-wait: idle — no lane is running; nothing changes until the owner acts"
# AH14 a long question is clipped by _lanes_clip on a whitespace boundary and marked ` …` (never a raw cut).
L32="$(awk -F'\t' '$1 == "L2" { print $2 }' "$TABLE3")"; mkdir -p "$L32/.supervisor/inbox/questions"
ahq="$(for i in $(seq 1 40); do printf 'word%02d ' "$i"; done)"
jq -n -c --arg q "$ahq" '{id: "toolu_long", asked_at: "2026-10-07T00:09:00Z", questions: [{question: $q, options: [{label: "A"}]}]}' > "$L32/.supervisor/inbox/questions/toolu_long.json"
out="$(run lane-wait "$RF3" --interval 1 --timeout 5)"
check "AH14 the question text is clipped by _lanes_clip 160" "$(printf '%s\n' "$out" | grep '^lane-wait: question')" \
  "lane-wait: question L2 toolu_long asked 2026-10-07T00:09:00Z — $(for i in $(seq 1 22); do printf 'word%02d ' "$i"; done)…"
# AH12 static: every _LANES_WAIT_QUIET / _LANES_WAIT_LIVE token is a state lane-status can report — a literal
# `state=<tok>` assignment in _lanes_lane_json, a table state it passes through (`removed|abandoned) state="$ts"`),
# a run-file park status `_lanes_parked` passes through, or a SKILL §3 `pause_reason` enum value (any non-empty
# pause_reason becomes the state). A renamed state would otherwise drift the array silently (a quiet token that
# matches nothing stops silencing; a live token that matches nothing lets idle fire past a working lane).
# Mutation control: a fake token must be named.
ah_reportable="$( { grep -v '^_LANES_WAIT_' "$SB" | grep -oE '(^|[^_a-zA-Z])state=[a-z_]+' | sed 's/.*state=//'
  grep -A3 '^_lanes_parked() {' "$SB" | grep -F 'case "${1:-}" in' | sed -E 's/.* in ([a-z_|]+)\).*/\1/' | tr '|' '\n'
  grep -E '^[[:space:]]+[a-z_|]+\) state="\$ts"' "$SB" | sed -E 's/^[[:space:]]+([a-z_|]+)\).*/\1/' | tr '|' '\n'
  grep -m1 '^- pause_reason: ' "$HERE/../skills/automate-loop/run-file.md" | sed 's/^- pause_reason: //' | tr '|' '\n'; } | sort -u)"
ah_drift() { jq -r '.[]' <<<"$1" 2>/dev/null | while IFS= read -r tok; do grep -qxF -- "$tok" <<<"$ah_reportable" || printf '%s ' "$tok"; done; }
ah_quiet="$(sed -n "s/^_LANES_WAIT_QUIET='\(.*\)'\$/\1/p" "$SB")"; ah_live="$(sed -n "s/^_LANES_WAIT_LIVE='\(.*\)'\$/\1/p" "$SB")"
check "AH12 both arrays read, and the reportable set holds a parked, a derived, a table and an enum-only state" \
  "$(jq 'length > 0' <<<"$ah_quiet"):$(jq 'length > 0' <<<"$ah_live"):$(grep -cxE 'failed|running|removed|awaiting_go' <<<"$ah_reportable")" "true:true:4"
check "AH12a every _LANES_WAIT_QUIET token is a reportable state" "$(ah_drift "$ah_quiet")" ""
check "AH12b every _LANES_WAIT_LIVE token is a reportable state" "$(ah_drift "$ah_live")" ""
check "AH12c mutation: a fake token appended to a copy of the array is named" "$(ah_drift "$(jq -c '. + ["stalld"]' <<<"$ah_quiet")")" "stalld "
check "AH12d no token is both live and quiet (an event state would be silenced twice)" "$(jq -rn --argjson a "$ah_quiet" --argjson b "$ah_live" '$a - ($a - $b) | join(",")')" ""
# AH15 the liveness marker: written naming the watcher's pid; a second watcher takes it over; the first
# one's exit leaves it (it names the second); the owner's exit removes it; the idle paths write none.
LWM="$P/.supervisor/automate/$PARENT2.lane-wait.pid"; rm -f "$LWM"
ah15_wait() { local i=0; while [ "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" != "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }
bash "$S" lane-wait "$RF2" --interval 1 --timeout 60 >/dev/null 2>&1 & LWA=$!; BG_PIDS="$BG_PIDS $LWA"
ah15_wait "$LWA"
check "AH15a lane-wait writes <pid> <start epoch>" "$(awk '{ print ($1 == '"$LWA"') ":" ($2 ~ /^[0-9]+$/) }' "$LWM" 2>/dev/null)" "1:1"
bash "$S" lane-wait "$RF2" --interval 1 --timeout 60 >/dev/null 2>&1 & LWB=$!; BG_PIDS="$BG_PIDS $LWB"
ah15_wait "$LWB"
check "AH15b a second watcher takes the marker over" "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" "$LWB"
kill -TERM "$LWA" 2>/dev/null; wait "$LWA" 2>/dev/null
check "AH15c the first watcher's exit leaves the marker it no longer owns" "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" "$LWB"
kill -TERM "$LWB" 2>/dev/null; wait "$LWB" 2>/dev/null
check "AH15d the owner's exit (TERM) removes it" "$([ -e "$LWM" ] && echo present || echo absent)" absent
out="$(run lane-wait "$RF2" --interval 1 --timeout 1)"
check "AH15e a lane-wait that times out removes its marker" "$([ -e "$LWM" ] && echo present || echo absent)" absent
run lane-wait "$P/.supervisor/automate/none.md" >/dev/null
bash "$S" lane-wait "$TABLE2" --interval 1 --timeout 60 >/dev/null 2>&1 & LWC=$!; BG_PIDS="$BG_PIDS $LWC"
ah15_wait "$LWC"
check "AH15g given the .lanes table path, the marker still lands at <parent_run_id>.lane-wait.pid" "$(awk '{ print $1 }' "$LWM" 2>/dev/null)" "$LWC"
kill -TERM "$LWC" 2>/dev/null; wait "$LWC" 2>/dev/null
check "AH15f the no-lane-table idle path writes no marker" "$(ls "$P/.supervisor/automate/" | grep -c 'none.lane-wait.pid' | tr -d ' ')" 0
# Clean up the second wave: lane-feed L<n> (T7) resolves the NEWEST lane table in the primary.
rm -rf "$LWS" "$P/.supervisor/automate/$PARENT3".* "$T/work/primary-lanes/$PARENT3"
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

