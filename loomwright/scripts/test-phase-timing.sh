#!/usr/bin/env bash
# test-phase-timing.sh — phase-timing.sh (iq02 Part T04): the 2026-10-08 replay
# (committed trimmed fixtures), owner-wait exact / fallback / null / 0, missing
# endpoints ⇒ null, ci-local attribution by tree key only, fail-SAFE input (incl. a
# value-less flag never swallowing the next --flag), and six mutation controls run
# against COPIES (gated non-empty + differs + bash -n).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PT="$HERE/phase-timing.sh"
FX="$HERE/fixtures/phase-timing/replay-2026-10-08"
RUNF="$FX/automate/automate-2026-10-08-121222.md"
# session logs live in session-logs/, not logs/: the root .gitignore ignores every logs/ dir
pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$HERE/wait-lib.sh"   # bounded condition waits (iq02 T07)
# near <actual> <expected> — within 60 s (and never null)
near() { [ -n "$1" ] && [ "$1" != "null" ] && [ $(( $1 > $2 ? $1 - $2 : $2 - $1 )) -le 60 ]; }
q() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }

echo "== R. replay of automate-2026-10-08-121222 (PR #435) — each known span within 60 s =="
OUT="$(bash "$PT" --run "$RUNF" --logs-dir "$FX/session-logs" 2>/dev/null)"
near "$(q '.item.pick_to_first_ready.seconds')" 7480 && ok "pick → drain READY ≈ 2 h 04 m 40 s ($(q '.item.pick_to_first_ready.seconds') s)" || no "pick → READY: $(q '.item.pick_to_first_ready.seconds')"
near "$(q '.item.post_ready.seconds')" 11245 && ok "post-READY ≈ 3 h 07 m 25 s" || no "post-READY: $(q '.item.post_ready.seconds')"
[ "$(q '[.item.owned_drains[]|select(.fix_now)][0]|"\(.start) \(.end)"')" = "2026-10-08T15:08:30Z 2026-10-08T16:41:29Z" ] && ok "fix-now re-drain 15:08:30 → 16:41:29" || no "re-drain: $(q '.item.owned_drains')"
near "$(q '.item.pick_to_autonomous_start.seconds')" 1147 && ok "pick → autonomous_start ≈ 19 m 07 s" || no "pick → start: $(q '.item.pick_to_autonomous_start.seconds')"
near "$(q '.item.pick_to_autonomous_start.plan_review.seconds')" 480 && ok "  … plan review ≈ 8 m (cc-log join)" || no "plan review: $(q '.item.pick_to_autonomous_start.plan_review')"
near "$(q '.item.pick_to_autonomous_start.owner_seconds')" 600 && [ "$(q '.item.pick_to_autonomous_start.owner_waits[0].exact')" = "false" ] && ok "  … owner ≈ 10 m, exact: false" || no "pre-start owner: $(q '.item.pick_to_autonomous_start.owner_waits')"
[ "$(q '[.supervisor.phase45_iterations[]|"\(.start)-\(.end)"]|join(" ")')" = "2026-10-08T13:23:02Z-2026-10-08T13:31:07Z 2026-10-08T14:01:15Z-2026-10-08T14:07:54Z 2026-10-08T14:10:09Z-2026-10-08T14:13:23Z" ] && ok "three Phase 4.5 reviewer spans exactly as the hand derivation" || no "reviewer spans: $(q '.supervisor.phase45_iterations')"
near "$(q '.item.post_ready.owner_waits[0].seconds')" 120 && near "$(q '.item.post_ready.owner_waits[1].seconds')" 2580 && [ "$(q '[.item.post_ready.owner_waits[].exact]|unique|join(",")')" = "false" ] && ok "two post-READY owner waits ≈ 2 m and ≈ 43 m, exact: false" || no "post-READY waits: $(q '.item.post_ready.owner_waits')"
# the second post-READY wait's fallback working row lands 1 s AFTER the park (17:24:51 vs 17:24:50):
# it is clamped to the window end exactly — the 60 s tolerance above cannot see a 1 s overflow.
[ "$(q '.item.post_ready.owner_waits[1]|"\(.end) \(.seconds)"')" = "2026-10-08T17:24:50Z 2589" ] && ok "post-READY owner wait clamped to the park (ends 17:24:50, 2589 s)" || no "post-READY clamp: $(q '.item.post_ready.owner_waits[1]')"
[ "$(q '[.item.pick_to_park, .item.pick_to_autonomous_start, .item.post_ready] | map(. as $w | $w.owner_seconds <= $w.seconds and $w.machine_seconds >= 0 and ($w.owner_seconds + $w.machine_seconds) == $w.seconds and ([$w.owner_waits[].end] | all(. <= $w.end))) | all')" = "true" ] && ok "every split window: owner ≤ wall, machine ≥ 0, no owner wait ends past the window" || no "window bound: $(q '[.item.pick_to_park, .item.post_ready]|map({seconds,owner_seconds,machine_seconds,owner_waits})')"
[ "$(q '.supervisor.finalize.seconds')" = "null" ] && [ "$(q '.supervisor.pr_created')" = "null" ] && ok "no pr_created row in a pre-3c log ⇒ finalize null, not 0" || no "finalize: $(q '.supervisor.finalize')"
[ "$(q '.supervisor.order|join(",")')" = "plan,execute,finalize,phase45_1,phase45_2,phase45_3,completion" ] || [ "$(q '.supervisor.order|index("execute") < index("phase45_1")')" = "true" ] && ok "phases ordered by timestamp" || no "order: $(q '.supervisor.order')"
REPLAY="$OUT"

echo "== O. owner-wait: exact pair / fallback / no ask =="
mkrun() {  # mkrun <dir> <cc rows...> — picked 10:00:00, parked 11:00:00
  local d="$1"; shift; mkdir -p "$d/automate" "$d/logs"
  printf '## Progress\n- 2026-10-01T09:59:00Z run created (session cc-o)\n- 2026-10-01T10:00:00Z picked x.md\n- 2026-10-01T11:00:00Z parked awaiting_merge\n' > "$d/automate/r.md"
  printf '%s\n' "$@" > "$d/logs/cc-o.jsonl"
}
L='{"event":"agent_lifecycle","ts":"2026-10-01T09:58:00Z","state":"working"}'
E='{"event":"agent_lifecycle","ts":"2026-10-01T11:01:00Z","state":"working"}'
mkrun "$T/o1" "$L" '{"event":"agent_lifecycle","ts":"2026-10-01T10:10:00Z","state":"waiting","reason":"ask_user","tool_use_id":"tu1"}' \
  '{"event":"agent_lifecycle","ts":"2026-10-01T10:12:00Z","state":"working","reason":"answered","tool_use_id":"tu1"}' \
  '{"event":"agent_lifecycle","ts":"2026-10-01T10:30:00Z","state":"working"}' "$E"
OUT="$(bash "$PT" --run "$T/o1/automate/r.md" 2>/dev/null)"
[ "$(q '.item.owner_seconds')" = "120" ] && [ "$(q '.item.pick_to_park.owner_waits[0].exact')" = "true" ] && [ "$(q '.item.owner_exact_share == 1')" = "true" ] && ok "waiting + answered (same tool_use_id) ⇒ exact 120 s, exact: true" || no "exact pair: $(q '.item.pick_to_park')"
mkrun "$T/o2" "$L" '{"event":"agent_lifecycle","ts":"2026-10-01T10:10:00Z","state":"waiting","reason":"ask_user"}' \
  '{"event":"agent_lifecycle","ts":"2026-10-01T10:30:00Z","state":"working"}' "$E"
OUT="$(bash "$PT" --run "$T/o2/automate/r.md" 2>/dev/null)"
[ "$(q '.item.owner_seconds')" = "1200" ] && [ "$(q '.item.pick_to_park.owner_waits[0].exact')" = "false" ] && ok "no answered row ⇒ next working row, exact: false" || no "fallback: $(q '.item.pick_to_park')"
mkrun "$T/o3" "$L" '{"event":"agent_lifecycle","ts":"2026-10-01T10:30:00Z","state":"working"}' "$E"
OUT="$(bash "$PT" --run "$T/o3/automate/r.md" 2>/dev/null)"
[ "$(q '.item.owner_seconds')" = "0" ] && [ "$(q '.item.machine_seconds')" = "3600" ] && ok "no ask and the log spans the item ⇒ owner 0, machine 3600" || no "no-ask spanning: $(q '.item.owner_seconds')"
mkrun "$T/o4" '{"event":"agent_lifecycle","ts":"2026-10-01T10:30:00Z","state":"working"}'
OUT="$(bash "$PT" --run "$T/o4/automate/r.md" 2>/dev/null)"
[ "$(q '.item.owner_seconds')" = "null" ] && [ "$(q '.item.machine_seconds')" = "null" ] && ok "no ask but the log does NOT span the item ⇒ owner null (never 0)" || no "no-ask non-spanning: $(q '.item.owner_seconds')"

mkrun "$T/o5" "$L" '{"event":"agent_lifecycle","ts":"2026-10-01T10:50:00Z","state":"waiting","reason":"ask_user","tool_use_id":"tu5"}' \
  '{"event":"agent_lifecycle","ts":"2026-10-01T11:10:00Z","state":"working","reason":"answered","tool_use_id":"tu5"}' "$E"
OUT="$(bash "$PT" --run "$T/o5/automate/r.md" 2>/dev/null)"
[ "$(q '.item.owner_seconds')" = "600" ] && [ "$(q '.item.machine_seconds')" = "3000" ] && [ "$(q '.item.pick_to_park.owner_waits[0]|"\(.end) \(.exact)"')" = "2026-10-01T11:00:00Z true" ] && ok "answer 10 m after the park ⇒ clamped to the window: owner 600, machine 3000, exact kept" || no "clamp exact: $(q '.item.pick_to_park')"
mkrun "$T/o6" "$L" '{"event":"agent_lifecycle","ts":"2026-10-01T10:50:00Z","state":"waiting","reason":"ask_user"}' "$E"
OUT="$(bash "$PT" --run "$T/o6/automate/r.md" 2>/dev/null)"
[ "$(q '.item.owner_seconds')" = "600" ] && [ "$(q '.item.machine_seconds')" = "3000" ] && [ "$(q '.item.pick_to_park.owner_waits[0].exact')" = "false" ] && ok "fallback working row after the park ⇒ clamped too: owner 600, machine 3000" || no "clamp fallback: $(q '.item.pick_to_park')"
O5="$T/o5/automate/r.md"
# a permission_prompt ask has no `answered` row (only emit-lifecycle.sh answered writes one, on the owner-question hook):
# it must take the fallback (exact: false), never steal the NEXT ask_user question's answer.
mkrun "$T/o7" "$L" '{"event":"agent_lifecycle","ts":"2026-10-01T10:05:00Z","state":"waiting","reason":"permission_prompt"}' \
  '{"event":"agent_lifecycle","ts":"2026-10-01T10:06:00Z","state":"working"}' \
  '{"event":"agent_lifecycle","ts":"2026-10-01T10:20:00Z","state":"waiting","reason":"ask_user"}' \
  '{"event":"agent_lifecycle","ts":"2026-10-01T10:30:00Z","state":"working","reason":"answered"}' "$E"
O7="$T/o7/automate/r.md"
OUT="$(bash "$PT" --run "$O7" 2>/dev/null)"
[ "$(q '[.item.pick_to_park.owner_waits[]|"\(.seconds):\(.exact)"]|join(",")')" = "60:false,600:true" ] && [ "$(q '.item.owner_seconds')" = "660" ] \
  && ok "id-less permission_prompt ⇒ fallback 60 s exact: false; the later ask_user keeps its own answer (600 s exact)" || no "permission_prompt pairing: $(q '.item.pick_to_park.owner_waits')"

echo "== I. item scope: a multi-item run file reports ONE item's segment =="
mkdir -p "$T/i/automate" "$T/i/logs"
printf '%s\n' '## Progress' '- 2026-10-01T09:00:00Z picked a.md' '- 2026-10-01T09:30:00Z session_id s-a (a.md)' \
  '- 2026-10-01T09:32:00Z owned drain started' '- 2026-10-01T09:40:00Z drain READY → awaiting_merge' '- 2026-10-01T09:50:00Z parked awaiting_merge' \
  '- 2026-10-01T11:00:00Z picked b.md' '- 2026-10-01T11:30:00Z session_id s-b (b.md)' '- 2026-10-01T11:32:00Z owned drain started' \
  '- 2026-10-01T11:50:00Z drain READY → awaiting_merge' '- 2026-10-01T12:00:00Z parked awaiting_merge' > "$T/i/automate/r.md"
I2="$T/i/automate/r.md"
pt_item() { q '"\(.session_id) \(.item.pick) \(.item.park) \(.item.pick_to_park.seconds) \([.item.owned_drains[].start]|join(","))"'; }
B_WANT="s-b 2026-10-01T11:00:00Z 2026-10-01T12:00:00Z 3600 2026-10-01T11:32:00Z"
OUT="$(bash "$PT" --run "$I2" --item b.md 2>/dev/null)"
[ "$(pt_item)" = "$B_WANT" ] && ok "--item b.md ⇒ item 2's pick/park/session/drain only (not item 1's)" || no "item 2 scope: $(pt_item)"
OUT="$(bash "$PT" --run "$I2" --item ./a.md 2>/dev/null)"
[ "$(pt_item)" = "s-a 2026-10-01T09:00:00Z 2026-10-01T09:50:00Z 3000 2026-10-01T09:32:00Z" ] && ok "--item ./a.md ⇒ item 1's segment (leading ./ ignored)" || no "item 1 scope: $(pt_item)"
OUT="$(bash "$PT" --run "$I2" 2>/dev/null)"
[ "$(pt_item)" = "$B_WANT" ] && ok "no --item ⇒ the LAST picked item's segment" || no "default scope: $(pt_item)"
OUT="$(bash "$PT" --run "$I2" --item c.md 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ "$(q '.item.pick_to_park.seconds')" = "null" ] && [ "$(q '.item.owned_drains|length')" = "0" ] && ok "--item never picked ⇒ null item spans, exit 0" || no "absent item: rc=$rc $(pt_item)"
mkdir -p "$T/i0/automate" "$T/i0/logs"; printf '%s\n' '## Progress' '- 2026-10-01T10:05:00Z session_id s-i0' > "$T/i0/automate/r.md"
OUT="$(bash "$PT" --run "$T/i0/automate/r.md" 2>/dev/null)"
[ "$(q '.session_id')" = "s-i0" ] && ok "a run file with no picked line at all is read whole (session_id kept)" || no "no-pick file lost its session: $(q '.session_id')"
printf '%s\n' '- 2026-10-01T12:30:00Z picked b.md (resume)' '- 2026-10-01T12:40:00Z session_id s-b2 (b.md)' > "$T/i/automate/r2.tail"
cat "$I2" "$T/i/automate/r2.tail" > "$T/i/automate/r2.md"
OUT="$(bash "$PT" --run "$T/i/automate/r2.md" --item b.md 2>/dev/null)"
[ "$(pt_item)" = "s-b2 2026-10-01T11:00:00Z 2026-10-01T12:00:00Z 3600 2026-10-01T11:32:00Z" ] && ok "a resume re-pick of the same item stays in its segment (first pick kept, latest session_id)" || no "re-pick scope: $(pt_item)"
echo "== N. missing endpoint ⇒ null, never 0; stranded close-out ⇒ null completion =="
mkdir -p "$T/n/automate" "$T/n/logs"
printf '## Progress\n- 2026-10-01T10:00:00Z picked x.md\n- 2026-10-01T10:05:00Z session_id s-n\n' > "$T/n/automate/r.md"
printf '%s\n' '{"event":"agent_lifecycle","ts":"2026-10-01T10:06:00Z","state":"ended","agent_id":"r1","agent_type":"loomwright:code-reviewer"}' \
  '{"event":"session_end","ts":"2026-10-01T12:00:00Z","reason":"session_ended_without_completion"}' > "$T/n/logs/s-n.jsonl"
OUT="$(bash "$PT" --run "$T/n/automate/r.md" 2>/dev/null)"
[ "$(q '.item.pick_to_park.seconds')" = "null" ] && [ "$(q '.item.pick_to_park.end')" = "null" ] && ok "no parked line ⇒ pick_to_park null" || no "missing park: $(q '.item.pick_to_park')"
[ "$(q '.supervisor.completion.seconds')" = "null" ] && ok "session_ended_without_completion ⇒ completion null" || no "stranded: $(q '.supervisor.completion')"
MISSING="$OUT"

echo "== C. ci-local runs: tree key / HEAD only, never time window =="
CI="$T/ci"; mkdir -p "$CI"
printf 'ci-local: log x\nci-local: PASS after 600s\n' > "$CI/aaaatree-base-Darwin-20261008T133000Z-1.log"
printf 'ci-local: log x\nci-local: PASS after 500s\n' > "$CI/5bdf5a4other-base-Darwin-20261008T142600Z-2.log"
printf 'ci-local: log x\nci-local: head bbbbsha feature/pa24\nci-local: FAIL after 30s\n' > "$CI/3e7bc89dirty-base-Darwin-20261008T142900Z-3.log"
printf 'aaaatree\nbbbbsha\n' > "$T/trees"
OUT="$(bash "$PT" --run "$RUNF" --logs-dir "$FX/session-logs" --ci-runs "$CI" --trees "$T/trees" 2>/dev/null)"
[ "$(q '[.ci_runs[].log]|map(.[0:8])|join(",")')" = "3e7bc89d,aaaatree" ] && [ "$(q '.ci_unattributed')" = "1" ] && ok "tree + HEAD attributed; the #438-tree run inside the window is unattributed" || no "ci attribution: $(q '.ci_runs') unattributed=$(q '.ci_unattributed')"
[ "$(q '[.ci_runs[]|select(.log|startswith("aaaa"))][0]|"\(.start) \(.wall_seconds) \(.verdict)"')" = "2026-10-08T13:30:00Z 600 PASS" ] && ok "a run carries start, wall seconds, verdict" || no "run fields: $(q '.ci_runs')"
OUT="$(bash "$PT" --run "$RUNF" --logs-dir "$FX/session-logs" --ci-runs "$CI" 2>/dev/null)"
[ "$(q '.ci_runs')" = "null" ] && ok "no tree list ⇒ ci_runs null (incomplete), not []" || no "no trees: $(q '.ci_runs')"
CIOUT_ARGS="--ci-runs $CI --trees $T/trees"
CI2="$T/ci2"; mkdir -p "$CI2"
printf 'ci-local: log x\nci-local: head bbbbsha feature/pa24\nci-local --affected: PASS after 351s — 25 of 157\naffected-only — not a pre-push gate\n' > "$CI2/cccctree-base-Darwin-20261009T101047Z-4-affected.log"
OUT="$(bash "$PT" --run "$RUNF" --logs-dir "$FX/session-logs" --ci-runs "$CI2" --trees "$T/trees" 2>/dev/null)"
[ "$(q '.ci_runs[0]|"\(.wall_seconds) \(.verdict)"')" = "351 PASS" ] && ok "an --affected log (advisory line after the verdict) reads PASS 351 s, attributed by its HEAD line" || no "affected log: $(q '.ci_runs')"

echo "== F. fail-SAFE =="
OUT="$(bash "$PT" --run "$T/does-not-exist.md" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [ "$(q '.item.pick_to_park.seconds')" = "null" ] && ok "unreadable run file ⇒ exit 0, null fields" || no "fail-safe rc=$rc out=$OUT"
OUT="$(bash "$PT" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && ok "no arguments ⇒ exit 0, valid JSON" || no "no-arg rc=$rc"
# last_flag_exits <script> <flag> <timeout_s> — run <script> with <flag> as the LAST argument in the
# background; 0 when it exits 0 within the bounded wait. A hung run is killed and returns 1. (The old
# unguarded `shift 2` never shifted with one argument left, so `while [ $# -gt 0 ]` spun forever.)
last_flag_exits() {
  local pid rc
  bash "$1" "$2" >/dev/null 2>&1 & pid=$!
  if wait_for_pid_gone "$pid" "$3" 2>/dev/null; then wait "$pid"; rc=$?; [ "$rc" = 0 ]; return; fi
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 1
}
for flag in --run --item --session --logs-dir --ci-runs --trees --git-range --branch; do
  last_flag_exits "$PT" "$flag" 10 && ok "$flag as the last argument ⇒ exit 0 within a bounded wait" || no "$flag as the last argument hung or exited non-zero"
done
# (fix-now C class) a value-less flag never swallows the next `--flag`: `--logs-dir --run <file>`
# keeps --run (an item record), where the old parser took `--run` as the logs dir and lost the run.
OUT="$(bash "$PT" --logs-dir --run "$RUNF" 2>"$T/swallow.err")"; rc=$?
[ "$rc" = 0 ] && [ "$(q '.kind')" = "item" ] && [ "$(q '.session_id')" = "auto-2026-10-08-123152" ] \
  && ok "--logs-dir before --run: --run is not swallowed (kind item, session from the run file)" || no "--logs-dir swallowed --run: rc=$rc $(q '{kind,session_id}')"
grep -qF -- "--logs-dir has no value (next arg '--run' is a flag)" "$T/swallow.err" && ok "the refused value is named on stderr" || no "no stderr reason: $(cat "$T/swallow.err")"

echo "== M. mutation controls (copies; each must turn a leg red) =="
mutant() {  # mutant <name> <python-old> <python-new>
  local m="$T/mut-$1.sh"
  python3 - "$PT" "$m" "$2" "$3" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4], 1))
PYEOF
  if [ -s "$m" ] && ! cmp -s "$PT" "$m" && bash -n "$m"; then printf '%s' "$m"; fi
}
M1="$(mutant nojoin 'cc_rows = read_jsonl(os.path.join(logs, cc_id + ".jsonl")) if cc_id else None' 'cc_rows = None')"
if [ -n "$M1" ]; then
  OUT="$(bash "$M1" --run "$RUNF" --logs-dir "$FX/session-logs" 2>/dev/null)"
  if near "$(q '.item.pick_to_autonomous_start.plan_review.seconds')" 480 && near "$(q '.item.pick_to_autonomous_start.owner_seconds')" 600; then no "M1 dropping the cc_session_id join left the 19-minute split green"; else ok "M1 drop the cc_session_id join ⇒ the 19-minute split goes red"; fi
else no "M1 mutant not built (empty / identical / bash -n)"; fi
M2="$(mutant zero 'secs = (eb - ea) if (ea is not None and eb is not None and eb >= ea) else None' 'secs = (eb - ea) if (ea is not None and eb is not None and eb >= ea) else 0')"
if [ -n "$M2" ]; then
  OUT="$(bash "$M2" --run "$T/n/automate/r.md" 2>/dev/null)"
  [ "$(q '.item.pick_to_park.seconds')" = "null" ] && no "M2 missing endpoint ⇒ 0 stayed green" || ok "M2 missing endpoint ⇒ 0 turns the null leg red ($(q '.item.pick_to_park.seconds'))"
else no "M2 mutant not built"; fi
M3="$(mutant window 'if tree in keys or (head and head in keys) or (branch and hb == branch):' 'if start and "2026-10-08T12:12:45Z" <= start <= "2026-10-08T17:24:50Z":')"
if [ -n "$M3" ]; then
  # shellcheck disable=SC2086
  OUT="$(bash "$M3" --run "$RUNF" --logs-dir "$FX/session-logs" $CIOUT_ARGS 2>/dev/null)"
  if q '[.ci_runs[].log]|join(",")' | grep -q '^.*5bdf5a4'; then ok "M3 time-window attribution ⇒ the 5bdf5a4 (#438) run appears — red"; else no "M3 time-window attribution stayed green"; fi
else no "M3 mutant not built"; fi
M4="$(mutant shift2 '  VAL=""; NSHIFT=1' '  VAL=""; NSHIFT=2')"
if [ -n "$M4" ]; then
  if last_flag_exits "$M4" --run 3; then no "M4 unguarded \`shift 2\` with --run last stayed green"; else ok "M4 unguarded \`shift 2\` ⇒ --run as the last argument hangs — red"; fi
else no "M4 mutant not built"; fi
M6="$(mutant swallow '    --*) echo "phase-timing: $1 has no value' '    --NEVER*) echo "phase-timing: $1 has no value')"
if [ -n "$M6" ]; then
  OUT="$(bash "$M6" --logs-dir --run "$RUNF" 2>/dev/null)"
  [ "$(q '.kind')" = "item" ] && no "M6 dropping the --… value refusal stayed green" || ok "M6 drop the --… value refusal ⇒ --logs-dir swallows --run (kind $(q '.kind')) — red"
else no "M6 mutant not built"; fi

M7="$(mutant noscope '        progress = progress[lo_i:end_i]' '        pass')"
if [ -n "$M7" ]; then
  OUT="$(bash "$M7" --run "$I2" --item b.md 2>/dev/null)"
  [ "$(pt_item)" = "$B_WANT" ] && no "M7 dropping the item-segment scope stayed green" || ok "M7 drop the item-segment scope ⇒ item 2 reads item 1's spans ($(pt_item)) — red"
else no "M7 mutant not built"; fi
M8="$(mutant pairany 'for i, r in enumerate(answered if a.get("reason") == "ask_user" else []):' 'for i, r in enumerate(answered):')"
if [ -n "$M8" ]; then
  OUT="$(bash "$M8" --run "$O7" 2>/dev/null)"
  [ "$(q '.item.owner_seconds')" = "660" ] && no "M8 pairing a permission_prompt with an answered row stayed green" || ok "M8 pair permission_prompt by order ⇒ it steals the ask_user answer (owner $(q '.item.owner_seconds')) — red"
else no "M8 mutant not built"; fi

M5="$(mutant noclamp '            end = hi' '            end = ans')"
if [ -n "$M5" ]; then
  OUT="$(bash "$M5" --run "$O5" 2>/dev/null)"
  [ "$(q '.item.machine_seconds')" = "3000" ] && no "M5 unclamped owner interval stayed green" || ok "M5 drop the window clamp ⇒ owner overflows the park, machine $(q '.item.machine_seconds') — red"
else no "M5 mutant not built"; fi
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
