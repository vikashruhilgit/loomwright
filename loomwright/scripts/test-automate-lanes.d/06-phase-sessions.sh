declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ] && [ -d "$T" ] || { echo "${BASH_SOURCE[0]##*/}: run via test-automate-lanes.sh, never standalone (its kills need the suite's \$T)" >&2; exit 2; }
# ---- AN: phase sessions (automate-speed/09 — fresh session per phase) -----------------------------------
# A coordinator running INSIDE a lane clone (the hardest case for D2: the clone's own settings carry the
# lane relay hook, and a phase question must still never reach the lane inbox). The phase run file is the
# lane's own run file; the phase dir sits beside it.
PARENT9=automate-2026-10-19-090000; RF9="$P/.supervisor/automate/$PARENT9.md"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT9" > "$RF9"
for n in 1 2; do run lane-create "$RF9" reqs/a.md "$n" --parallel 2 >/dev/null; done
L91="$T/work/primary-lanes/$PARENT9/L1"; L92="$T/work/primary-lanes/$PARENT9/L2"
check "AN0 fixture: two lanes of a fresh parent run" "$([ -s "$L91/.supervisor/lane.json" ] && [ -s "$L92/.supervisor/lane.json" ] && echo ok)" ok
RFL="$L91/.supervisor/automate/$PARENT9-L1.md"; mkdir -p "$(dirname "$RFL")"
printf '# Automate Run: %s-L1 — reqs/a.md\n\n## Progress\n' "$PARENT9" > "$RFL"
PHS="$L91/.supervisor/automate/$PARENT9-L1.phase/supervisor"
PHOWN='/automate --resume'
an_launch() { run phase-launch "$RFL" "$@"; }

# AN1-AN2: phase-check (AC3, the lane-machinery leg)
out="$(run phase-check)"; rc=$?
check "AN1 phase-check with a pinnable regime ⇒ ok, exit 0" "$rc:$out" "0:phase-check: ok"
out="$(STUB_NO_REGIME=1 run phase-check)"; rc=$?
check "AN2 phase-check, claude without --permission-prompt-tool ⇒ unavailable (exit 0)" \
  "$rc:$out" "0:phase-check: unavailable — CLI advertises no pinnable permission regime (--permission-prompt-tool, --allowedTools, --disallowedTools)"
sed '/phase-check: unavailable — CLI advertises no pinnable/d' "$SB" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  check "AN2b mutation (phase-check skips _lanes_regime_ok) ⇒ the no-regime stub reads ok" \
    "$(STUB_NO_REGIME=1 bash "$MUT/automate-lanes.sh" phase-check 2>&1)" "phase-check: ok"
else bad "AN2b mutant not built"; fi
if [ -z "$(PATH=/usr/bin:/bin command -v claude)" ] && command -v jq >/dev/null 2>&1; then
  mkdir -p "$T/anbin"; ln -sf "$(command -v jq)" "$T/anbin/jq"
  check "AN2c no claude on PATH ⇒ unavailable" "$(PATH="$T/anbin:/usr/bin:/bin" bash "$S" phase-check 2>&1)" "phase-check: unavailable — no claude on PATH"
else ok "AN2c SKIP — a claude in /usr/bin or /bin (or no jq) leaves no PATH without one"; fi

# AN3-AN4: launch authority (AC5) + usage refusals
n0="$(claude_calls)"
out="$(an_launch supervisor --coordinator-session sess-coord -- '/loomwright:supervisor job: x')"; rc=$?
check "AN3 phase-launch without --owner-command ⇒ BLOCKED, exit 3" "$rc:$out" "3:phase-launch: BLOCKED — supervisor — no owner command — need the owner"
check "AN3b … no process started, no phase dir written" "$(claude_calls):$([ -e "$PHS" ] && echo dir || echo none)" "$n0:none"
sed '/phase-launch: BLOCKED — \$PH_PHASE — no owner command/d' "$SB" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  out="$(bash "$MUT/automate-lanes.sh" phase-launch "$RFL" drain --coordinator-session sess-coord -- '/loomwright:review-pr x' 2>&1)"
  wait_gone "$L91"
  check "AN3c mutation (owner-command check deleted) ⇒ the stub sees a spawn and no BLOCKED line" \
    "$(claude_calls):$(printf '%s' "$out" | grep -c 'BLOCKED' | tr -d ' ')" "$((n0 + 1)):0"
else bad "AN3c mutant not built"; fi
out="$(an_launch reviewer --owner-command "$PHOWN" --coordinator-session sess-coord -- x)"; rc=$?
check "AN4 an unknown phase is refused (exit 1)" "$rc:$out" "1:automate-lanes: phase-launch: unknown phase 'reviewer' (launch-pad | supervisor | drain)"
out="$(an_launch supervisor --owner-command "$PHOWN" -- x)"; check "AN4b no --coordinator-session refused (exit 1)" "$?" 1
out="$(run phase-launch "$P/reqs/a.md" supervisor --owner-command "$PHOWN" --coordinator-session sess-coord -- x)"
check "AN4c a file outside .supervisor/automate/ is no run file" "$?" 1

# AN5-AN12: launch + a question (AC4)
QP='[{"question":"Proceed with the plan?","header":"SV-GO","multiSelect":false,"options":[{"label":"Proceed","description":"p"},{"label":"Stop","description":"s"}]}]'
HIN="$(hook_in PreToolUse "$L91" toolu_p1 "$QP")"
DLP="$(jq -n -c --argjson q "$QP" '{type: "result", subtype: "success", stop_reason: "tool_deferred", session_id: "sess-123", deferred_tool_use: {id: "toolu_p1", name: "AskUserQuestion", input: {questions: $q}}}')"
n0="$(claude_calls)"
PHSC="$L91/.supervisor/automate/$PARENT9-L1.supervisor-result.md"
printf 'SUPERVISOR_RESULT:\n  task_id: a-previous-item\n' > "$PHSC"   # a previous item's sidecar, left beside the run file
out="$(STUB_MODE=defer STUB_DEFER_LINE="$DLP" STUB_HOOK_INPUT="$HIN" LOOMWRIGHT_HOLDER_PID=4242 CLAUDECODE=1 CLAUDE_PID=4242 \
  an_launch supervisor --owner-command "$PHOWN" --coordinator-session sess-coord -- '/loomwright:supervisor job: .supervisor/jobs/pending/x.md')"; rc=$?
check "AN5 phase-launch launched (exit 0)" "$rc:$(printf '%s' "$out" | grep -c '^phase-launch: launched supervisor (pid [0-9]*, session sess-123) (launch)' | tr -d ' ')" "0:1"
wait_gone "$L91"
check "AN5b one process started" "$(claude_calls)" "$((n0 + 1))"
check "AN5s a fresh launch removed the previous item's result sidecar" "$([ -e "$PHSC" ] && echo stale || echo none)" none
pa="$(grep '^ARGS' "$STUB_LOG" | tail -1)"
for f in "[-p]" "[--permission-prompt-tool] [stdio]" "[--permission-mode] [acceptEdits]" \
         "[--allowedTools] [Bash,Read,Edit,Write,Glob,Grep,Task,Agent,AskUserQuestion]" "Bash(gh pr merge:*)" \
         "Bash(git push --force:*)" "Bash(git push origin main:*)" "[--append-system-prompt] [You are running as a HEADLESS lane"; do
  has "AN6 phase flag $f (the lane's own list)" "$pa" "$f"
done
has "AN6b --settings carries the relay hook" "$pa" "[--settings] [{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"AskUserQuestion\",\"hooks\":[{\"type\":\"command\",\"command\":\"bash \\\"$S\\\" relay-hook\"}]}]"
hasnt "AN6c a fresh launch carries no --resume" "$pa" "[--resume]"
check "AN6d nothing written into the checkout's settings files (only the lane's own relay entry)" \
  "$(jq -c '[(.hooks.PreToolUse | length), (.hooks.PermissionRequest | length)]' "$L91/.claude/settings.local.json" 2>/dev/null):$(ls "$L91/.claude" | tr '\n' ' ')" "[1,1]:settings.local.json "
check "AN7 cwd = the run's checkout" "$(grep '^CWD' "$STUB_LOG" | tail -1)" "CWD $L91"
check "AN8 env: phase dir + the coordinator's run-lock session set" "$(grep '^PHASEENV' "$STUB_LOG" | tail -1)" "PHASEENV dir=$PHS lock=sess-coord"
has "AN8b env: ceiling 0, the runtime-identity vars unset" "$(grep '^ENV' "$STUB_LOG" | tail -1)" "CEIL=0 CC=unset PID=unset"
check "AN8c env: the coordinator's holder pin unset" "$(grep '^HOLDERENV' "$STUB_LOG" | tail -1)" "HOLDERENV unset"
has "AN9 the phase prompt is the session's first message" "$(grep '^STDIN' "$STUB_LOG" | tail -1)" "/loomwright:supervisor job: .supervisor/jobs/pending/x.md"
check "AN10 the hook (fired from --settings, in the phase env) defers" "$(grep '^HOOKOUT' "$STUB_LOG" | tail -1)" 'HOOKOUT {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}'
check "AN11 the question is recorded under the phase dir" \
  "$(jq -r '[.id, (.questions | length)] | map(tostring) | join(",")' "$PHS/inbox/questions/toolu_p1.json" 2>/dev/null)" "toolu_p1,1"
check "AN11b … and never in the lane inbox" "$(ls "$L91/.supervisor/inbox/questions" 2>/dev/null | tr '\n' ' ')" ""
check "AN11c phase dir files" "$(cd "$PHS" && for f in stream.log stdin.json session pid offset coordinator; do [ -s "$f" ] || printf 'missing:%s ' "$f"; done; cat session coordinator | tr '\n' ' ')" "sess-123 sess-coord "
out="$(run phase-wait "$RFL" supervisor --timeout 10)"; rc=$?
check "AN12 phase-wait ⇒ question (exit 5)" "$rc:$out" "5:phase-wait: question — toolu_p1 $PHS/inbox/questions/toolu_p1.json"

# AN13: the relay hook's phase branch, direct (a non-lane checkout: the primary)
PPD="$P/.supervisor/automate/$PARENT9.phase/drain"; mkdir -p "$PPD"
out="$(hook_in PreToolUse "$P" toolu_h1 "$QP" | LOOMWRIGHT_PHASE_DIR="$PPD" bash "$S" relay-hook)"
check "AN13 hook with a phase dir in a non-lane checkout ⇒ defer + question file" \
  "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"):$([ -s "$PPD/inbox/questions/toolu_h1.json" ] && echo file)" "defer:file"
awk '/# >>> phase-dir routing/ { skip = 1 } !skip { print } /# <<< phase-dir routing/ { skip = 0 }' "$SB" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
  out="$(hook_in PreToolUse "$P" toolu_h2 "$QP" | LOOMWRIGHT_PHASE_DIR="$PPD" bash "$MUT/automate-lanes.sh" relay-hook)"
  check "AN13b mutation (LOOMWRIGHT_PHASE_DIR branch deleted) ⇒ {} and no question file" \
    "$out:$([ -e "$PPD/inbox/questions/toolu_h2.json" ] && echo file || echo none)" "{}:none"
else bad "AN13b mutant not built"; fi
out="$(hook_in PreToolUse "$L91" toolu_h3 "$QP" | LOOMWRIGHT_PHASE_DIR="$T/not-a-phase-dir" bash "$S" relay-hook)"
check "AN13c a phase variable naming no phase dir ⇒ {}, nothing in the lane inbox" \
  "$out:$(ls "$L91/.supervisor/inbox/questions" 2>/dev/null | tr '\n' ' ')" "{}:"
out="$(hook_in PermissionRequest "$L91" toolu_h4 "$QP" | LOOMWRIGHT_PHASE_DIR="$PPD" bash "$S" relay-hook)"
check "AN13d a bundled call is still denied with a re-ask" "$(jq -r '.hookSpecificOutput.decision.behavior' <<<"$out")" deny

# AN14-AN17: phase-answer → the SAME session resumes → done
pans() { printf '%s' "$1" | bash "$S" phase-answer "$RFL" supervisor toolu_p1 "${@:2}" 2>&1; }
AFP="$PHS/inbox/answers/toolu_p1.json"
out="$(pans '{"answers":{"0":"Maybe"}}' --owner-command "$PHOWN")"; rc=$?
check "AN14 an unknown label is refused" "$rc:$(printf '%s' "$out" | grep -c '"Maybe" is not one of its options' | tr -d ' ')" "1:1"
out="$(pans '{"note":"your call"}' --owner-command "$PHOWN")"; check "AN14b a note alone is refused" "$?" 1
n1="$(claude_calls)"
out="$(pans '{"answers":{"0":"Proceed"}}')"; rc=$?
check "AN14c no --owner-command ⇒ BLOCKED exit 3, nothing written, no resume" \
  "$rc:$out:$([ -e "$AFP" ] && echo written || echo none):$(claude_calls)" "3:phase-answer: BLOCKED — supervisor — no owner command — need the owner:none:$n1"
HIN2="$(hook_in PreToolUse "$L91" toolu_p1 "$QP")"
out="$(printf '%s' '{"answers":{"0":"Proceed"},"note":"keep it small"}' | STUB_HOOK_INPUT="$HIN2" bash "$S" phase-answer "$RFL" supervisor toolu_p1 --owner-command "$PHOWN" 2>&1)"; rc=$?
wait_gone "$L91"
check "AN15 a valid answer is accepted and resumes (exit 0)" "$rc:$(printf '%s' "$out" | grep -c '^phase-answer: resumed supervisor (pid [0-9]*, session sess-123) (after answer toolu_p1)' | tr -d ' ')" "0:1"
check "AN15b answer file (human, via phase-answer, note kept)" "$(jq -c '[.answers["Proceed with the plan?"], .note, .source, .via]' "$AFP")" '["Proceed","keep it small","human","phase-answer"]'
pa="$(grep '^ARGS' "$STUB_LOG" | tail -1)"
has "AN15c the resume carries --resume <the SAME session>" "$pa" "[--resume] [sess-123]"
has "AN15d … and the relay hook settings again" "$pa" "[--settings]"
check "AN15e … in the phase env, the coordinator session read back from the phase dir" "$(grep '^PHASEENV' "$STUB_LOG" | tail -1)" "PHASEENV dir=$PHS lock=sess-coord"
check "AN15f the re-fired hook answers with the owner's label + note" \
  "$(grep '^HOOKOUT' "$STUB_LOG" | tail -1 | sed 's/^HOOKOUT //' | jq -r '.hookSpecificOutput as $h | [$h.permissionDecision, $h.updatedInput.answers["Proceed with the plan?"], $h.updatedInput.annotations["Proceed with the plan?"].notes, $h.permissionDecisionReason] | join("|")')" \
  "allow|Proceed|keep it small|answered by the owner via automate-lanes.sh phase-answer"
out="$(run phase-wait "$RFL" supervisor --timeout 10)"; rc=$?
check "AN16a a result line but no result sidecar ⇒ died (exit 6), never done" "$rc:$out" \
  "6:phase-wait: died — the session ended without writing its result sidecar ($PHSC)"
printf 'SUPERVISOR_RESULT:\n  task_id: this-item\n' > "$PHSC"   # the phase session's own result block
out="$(run phase-wait "$RFL" supervisor --timeout 10)"; rc=$?
check "AN16 phase-wait ⇒ done, naming the session and the sidecar (exit 0)" "$rc:$out" \
  "0:phase-wait: done — session sess-123 result $L91/.supervisor/automate/$PARENT9-L1.supervisor-result.md"
out="$(pans '{"answers":{"0":"Stop"}}' --owner-command "$PHOWN")"; check "AN16b a second answer is refused" "$?" 1
check "AN17 the lane inbox stayed empty across the whole phase" "$(find "$L91/.supervisor/inbox" -type f 2>/dev/null | wc -l | tr -d ' ')" 0

# AN18-AN19: running (3) / already running / died (6)
STUB_MODE=sleep an_launch drain --owner-command "$PHOWN" --coordinator-session sess-coord -- '/loomwright:review-pr x' >/dev/null
out="$(run phase-wait "$RFL" drain --timeout 0)"; rc=$?
check "AN18 phase-wait on a live session ⇒ running (exit 3)" "$rc:$out" "3:phase-wait: running — session sess-123"
out="$(an_launch drain --owner-command "$PHOWN" --coordinator-session sess-coord -- x)"; rc=$?
check "AN18b a second launch of a running phase is refused" "$rc:$(printf '%s' "$out" | grep -c '^phase-launch: refused — drain — already running' | tr -d ' ')" "1:1"
kill -TERM "$(cut -f1 "$L91/.supervisor/automate/$PARENT9-L1.phase/drain/pid")" 2>/dev/null; wait_gone "$L91"
out="$(run phase-wait "$RFL" drain --timeout 5)"; rc=$?
check "AN18c a killed session ⇒ died (exit 6)" "$rc:$(printf '%s' "$out" | grep -c '^phase-wait: died — the session exited with no result line (died_at ' | tr -d ' ')" "6:1"
STUB_MODE=die an_launch launch-pad --owner-command "$PHOWN" --coordinator-session sess-coord -- x >/dev/null; wait_gone "$L91"
out="$(run phase-wait "$RFL" launch-pad --timeout 5)"; check "AN19 an exit with no result line ⇒ died (exit 6)" "$?" 6
out="$(run phase-wait "$RFL" launch-pad --timeout x)"; check "AN19b a non-numeric --timeout is a usage error" "$?" 1

# AN20: a lane spawn strips both phase variables (AC6) + one mutation each
n2="$(claude_calls)"
LOOMWRIGHT_RUN_LOCK_SESSION_ID=sess-coord LOOMWRIGHT_PHASE_DIR="$PHS" LOOMWRIGHT_LANE_RECHECK_S=0 \
  run lane-launch "$L92" --owner-command "$OWN" >/dev/null; wait_gone "$L92"
check "AN20 lane env: neither phase variable reaches a lane" "$(claude_calls):$(grep '^PHASEENV' "$STUB_LOG" | tail -1)" "$((n2 + 1)):PHASEENV dir=unset lock=unset"
for v in LOOMWRIGHT_RUN_LOCK_SESSION_ID LOOMWRIGHT_PHASE_DIR; do
  sed "s/-u $v\\([ )]\\)/\\1/" "$SB" > "$MUT/automate-lanes.sh"
  if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh"; then
    LOOMWRIGHT_RUN_LOCK_SESSION_ID=sess-coord LOOMWRIGHT_PHASE_DIR="$PHS" LOOMWRIGHT_LANE_RECHECK_S=0 \
      bash "$MUT/automate-lanes.sh" lane-launch "$L92" --owner-command "$OWN" >/dev/null 2>&1; wait_gone "$L92"
    case "$v" in LOOMWRIGHT_RUN_LOCK_SESSION_ID) want="lock=sess-coord" ;; *) want="dir=$PHS" ;; esac
    has "AN20b mutation (-u $v dropped from envu) ⇒ the stub's env shows it" "$(grep '^PHASEENV' "$STUB_LOG" | tail -1)" "$want"
  else bad "AN20b mutant for $v not built"; fi
done

# AN21: a finished session whose result line is followed by more output than a pipe holds is NOT died (wave 7, lane
# L22: the wrapper's `tail | grep -q` under pipefail exited 141 when grep's early exit SIGPIPEd tail — a false .died,
# phase-wait exit 6 on a Supervisor phase that had opened its PR). The mutant restores that line and must write .died
PHD="$L91/.supervisor/automate/$PARENT9-L1.phase/launch-pad"; PHDS="$L91/.supervisor/automate/$PARENT9-L1.launch-pad-result.md"
STUB_MODE=flood an_launch launch-pad --owner-command "$PHOWN" --coordinator-session sess-coord -- x >/dev/null; wait_gone "$L91"
check "AN21 fixture: the result line is early in a stream larger than a pipe" \
  "$([ "$(grep -n '"type":"result"' "$PHD/stream.log" | tail -1 | cut -d: -f1)" -lt 5 ] && [ "$(wc -c < "$PHD/stream.log")" -gt 1000000 ] && echo ok)" ok
check "AN21b no .died marker for a session that wrote its result line" "$([ -e "$PHD/.died" ] && echo died || echo none)" none
printf 'LAUNCH_PAD_RESULT:\n  status: saved\n' > "$PHDS"
out="$(run phase-wait "$RFL" launch-pad --timeout 5)"; rc=$?
check "AN21c … and phase-wait reads it done (exit 0)" "$rc:$out" "0:phase-wait: done — session sess-123 result $PHDS"
# the old line is assembled from pieces (the pipe character in p) so this file never holds a literal pipe into
# grep -q itself — test-no-pipefail-grep-q.sh gates exactly that shape
awk -v q="'" -v p='|' '
  index($0, p " grep -c " q "\"type\": *\"result\"" q) { print "  if ! tail -c +\"$((off + 1))\" \"$log\" 2>/dev/null " p " grep -q " q "\"type\": *\"result\"" q "; then printf " q "died_at\\t%s\\nexit\\t%s\\n" q " \"$(now_utc)\" \"$rc\" > \"$died\"; fi"; skip = 1; next }
  skip && index($0, "case \"$n\" in") { skip = 0; next }
  { print }' "$SB" > "$MUT/automate-lanes.sh"
if [ -s "$MUT/automate-lanes.sh" ] && ! cmp -s "$SB" "$MUT/automate-lanes.sh" && bash -n "$MUT/automate-lanes.sh" \
   && grep -qF 'if ! tail -c +"$((off + 1))" "$log"' "$MUT/automate-lanes.sh"; then
  STUB_MODE=flood bash "$MUT/automate-lanes.sh" phase-launch "$RFL" launch-pad --owner-command "$PHOWN" --coordinator-session sess-coord -- x >/dev/null 2>&1; wait_gone "$L91"
  check "AN21d mutation (the old tail-into-grep -q pipe under pipefail) ⇒ the same stream writes a false .died (exit 0)" \
    "$(sed -n 's/^exit\t//p' "$PHD/.died" 2>/dev/null)" 0
else bad "AN21d mutant not built"; fi

# AN-z: nothing this part started outlives it (AA-F12z closed part 05, before these launches)
for p in $(tal_pgrep "$T" "_lane-run "); do kill -TERM "$p" 2>/dev/null; done
i=0; while tal_pgrep "$T" "_lane-run " >/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
check "AN-z no phase or lane wrapper of the suite survives" "$(tal_pgrep "$T" "_lane-run " | wc -l | tr -d ' ')" 0
