#!/usr/bin/env bash
# test-check-children-settled.sh — static suite for check-children-settled.sh (the ONE join between
# agent_identity rows and terminal lifecycle rows) AND the seam grep-gate over its consumers
# (agents/execute-manager.md poll-loop gate, agents/supervisor.md Single-Agent step 3b + Sequential
# step, skills/async-orchestration/SKILL.md Phase 4 checklist Point 5, commands/supervisor.md
# Parameters table, docs/RESULT_SCHEMAS.md, docs/FAILURE_ESCALATION.md).
#
# Modelled on test-verify-provides.sh: ok()/no() DEFINED here, pass/fail counters, "RESULT: N passed,
# M failed" tail, exit 1 on any failure, paths from $BASH_SOURCE, fixtures in `mktemp -d`, no
# gh/network/Docker. bash 3.2 / BSD userland safe.
#
# Covers (.supervisor/requirements/orca-derived/02-completion-authority.md):
#   script  — bad_args (missing --log, neither --agent-id nor --all); missing/unreadable --log in
#             --all mode ⇒ no_identity_rows (never unverifiable, never settled); missing --log in
#             --agent-id mode ⇒ unsettled; settled via each of the three terminal-row shapes
#             (subtask_complete, token_ledger, agent_lifecycle:failed); unsettled when an
#             agent_identity row has no terminal row; ended_without_result true on
#             subtask_complete+result_block_present:false and on agent_lifecycle:failed, false on a
#             clean subtask_complete/token_ledger; --all aggregates unsettled_agent_ids +
#             ended_without_result_ids correctly across a mixed fixture; a malformed JSONL line is
#             skipped, not fatal; JSON validity via `jq -e .`.
#   seams   — EM cites check-children-settled.sh + provides_present_agent_unsettled; Supervisor
#             Single-Agent step 3b AND Sequential step cite it with --agent-id; Supervisor FINALIZE
#             gate + async-orchestration SKILL.md Point 5 cite it with --all + children_unsettled;
#             commands/supervisor.md Parameters table documents --skip-children-check;
#             RESULT_SCHEMAS.md documents the join + children_unsettled; FAILURE_ESCALATION.md
#             documents the children-unsettled FINALIZE gate.
#   (m)     — MUTATION CONTROL: deleting the agent_lifecycle:failed branch from a COPY of the script's
#             `terminal_for` jq filter must turn a failed-only fixture from settled to unsettled —
#             otherwise the three-way OR is vacuous.
#   rejected — (v15.83.0) a `subtask_complete` row with `rejected: true` is NOT terminal: a
#             rejected-then-accepted worker settles on the ACCEPTED row only (and the rejected row's
#             `result_block_present: false` never decides `ended_without_result`); a rejected-only
#             worker stays `unsettled`; `rejected_stops` / `rejected_stop_ids` count/name them; a
#             `rejected: false` or absent key is terminal exactly as before.
#   ended   — (automate-followups/33) fixtures/children-settled-ended.jsonl: a settled general-purpose
#             spawn and a turn-limit blocking return (task_return) read settled; a non-worker ended
#             reads ended_without_result false unless its reason marks a turn limit; a worker whose
#             only terminal row is `ended` reads ended_without_result true; a worker's
#             subtask_complete decides over an earlier ended row; A5 — a SubagentStop-seam ended row
#             does not settle a worker whose latest subtask_complete is rejected, a task_return row
#             does; A4 — an identity row with no stop row stays unsettled in --all.
#   (m3)    — MUTATION CONTROL: renaming the `ended` state in a COPY of `terminal_for` must turn the
#             general-purpose and turn-limit fixtures unsettled — otherwise the ended arm is vacuous.
#   (m2)    — MUTATION CONTROL: deleting the `rejected` guard from a COPY of `terminal_for` must
#             flip the rejected-only worker to settled — otherwise the guard is vacuous.
#   expect-id — (agnostic-phase1/02) `--all --expect-id`: an expected id with no log / an empty log /
#             only an agent_identity row reads unsettled; with a terminal row (and no identity row)
#             settled; identity ids are still checked (union, deduped); no flag keeps the no-log and
#             empty-log output byte-identical (`no_identity_rows`); `--expect-id` misuse ⇒ bad_args;
#             seams — supervisor.md Point 5 passes `--expect-id`, and the two skill worker-spawn
#             examples (§"Spawning a Worker", §"Worker Dispatch") use `loomwright:worker`, never
#             `general-purpose` (scoped to those sections, so the fixer spawns elsewhere never trip it).
#   (m4)    — MUTATION CONTROL: a COPY of the script that ignores `--expect-id` must turn the no-log
#             expected-id case back into no_identity_rows (mutant gated on non-empty + differs +
#             `bash -n`, else the control FAILS as inconclusive).
#
# EXPLICIT LIMIT: this pins the script's behaviour and the WIRING (the prompts cite it where they say
# they do). It cannot prove an Execute Manager / Supervisor actually runs the Bash call at runtime.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

SCRIPT="$HERE/check-children-settled.sh"
EM="$PLUGIN_ROOT/agents/execute-manager.md"
SUP="$PLUGIN_ROOT/agents/supervisor.md"
ASYNC="$PLUGIN_ROOT/skills/async-orchestration/SKILL.md"
CMD="$PLUGIN_ROOT/commands/supervisor.md"
# docs/RESULT_SCHEMAS.md is an index; the agent_lifecycle section (which documents the
# children-settled join) lives in its split file.
SCHEMAS="$PLUGIN_ROOT/docs/result-schemas/agent-lifecycle-jsonl.md"
FAILDOC="$PLUGIN_ROOT/docs/FAILURE_ESCALATION.md"
WFM="$PLUGIN_ROOT/skills/workflow-management/SKILL.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$SCRIPT" "$EM" "$SUP" "$ASYNC" "$CMD" "$SCHEMAS" "$FAILDOC" "$WFM"; do
  [ -f "$f" ] || no "MISSING surface: $f"
done
if [ "$fail" -ne 0 ]; then
  echo; echo "RESULT: $pass passed, $fail failed"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  no "jq is required to run this suite (the script itself degrades to jq_missing without it)"
  echo; echo "RESULT: $pass passed, $fail failed"; exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-children-settled.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/session.jsonl"

get() { printf '%s' "$1" | jq -r "$2"; }

# ---------------------------------------------------------------------------
# 1) bad_args
# ---------------------------------------------------------------------------
out="$(bash "$SCRIPT" --log "$LOG" 2>/dev/null)"
[ "$(get "$out" .status)" = "unverifiable" ] && [ "$(get "$out" .reason)" = "bad_args" ] \
  && ok "neither --agent-id nor --all -> unverifiable/bad_args" \
  || no "neither --agent-id nor --all -> expected unverifiable/bad_args, got: $out"

out="$(bash "$SCRIPT" --agent-id agent-x 2>/dev/null)"
[ "$(get "$out" .status)" = "unverifiable" ] && [ "$(get "$out" .reason)" = "bad_args" ] \
  && ok "missing --log -> unverifiable/bad_args" \
  || no "missing --log -> expected unverifiable/bad_args, got: $out"

# ---------------------------------------------------------------------------
# 2) missing/unreadable --log
# ---------------------------------------------------------------------------
NOLOG="$TMP/does-not-exist.jsonl"
out="$(bash "$SCRIPT" --log "$NOLOG" --all 2>/dev/null)"
[ "$(get "$out" .status)" = "no_identity_rows" ] \
  && [ "$(get "$out" '.unsettled_agent_ids | length')" = "0" ] \
  && ok "--all with missing log -> no_identity_rows, never unverifiable/settled" \
  || no "--all with missing log -> expected no_identity_rows, got: $out"

out="$(bash "$SCRIPT" --log "$NOLOG" --agent-id agent-x 2>/dev/null)"
[ "$(get "$out" .status)" = "unsettled" ] \
  && ok "--agent-id with missing log -> unsettled (no evidence of settlement)" \
  || no "--agent-id with missing log -> expected unsettled, got: $out"

# ---------------------------------------------------------------------------
# 3) fixture log — the three terminal-row shapes + an unsettled identity + a
#    malformed line + an ended-without-result pair
# ---------------------------------------------------------------------------
cat > "$LOG" <<'JSONL'
{"event":"agent_identity","session_id":"s1","cc_session_id":"s1","agent_id":"worker-clean","agent_type":"loomwright:worker"}
{"event":"agent_identity","session_id":"s1","cc_session_id":"s1","agent_id":"worker-noresult","agent_type":"loomwright:worker"}
{"event":"agent_identity","session_id":"s1","cc_session_id":"s1","agent_id":"reviewer-ledger","agent_type":"loomwright:code-reviewer"}
{"event":"agent_identity","session_id":"s1","cc_session_id":"s1","agent_id":"worker-failed","agent_type":"loomwright:worker"}
{"event":"agent_identity","session_id":"s1","cc_session_id":"s1","agent_id":"worker-unsettled","agent_type":"loomwright:worker"}
{"event":"agent_identity","session_id":"s1","cc_session_id":"s1","agent_id":"worker-rejected-then-accepted","agent_type":"loomwright:worker"}
{"event":"agent_identity","session_id":"s1","cc_session_id":"s1","agent_id":"worker-rejected-only","agent_type":"loomwright:worker"}
this is not json at all
{"event":"subtask_complete","agent_id":"worker-clean","result_block_present":true,"rejected":false}
{"event":"subtask_complete","agent_id":"worker-noresult","result_block_present":false}
{"event":"token_ledger","agent_id":"reviewer-ledger"}
{"event":"agent_lifecycle","state":"failed","agent_id":"worker-failed","reason":"rate_limit"}
{"event":"subtask_complete","agent_id":"worker-rejected-then-accepted","result_block_present":false,"rejected":true,"stop_hook_active":false}
{"event":"subtask_complete","agent_id":"worker-rejected-only","result_block_present":true,"rejected":true,"stop_hook_active":false}
{"event":"subtask_complete","agent_id":"worker-rejected-then-accepted","result_block_present":true,"rejected":false,"stop_hook_active":true}
JSONL

out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-clean 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] && [ "$(get "$out" .ended_without_result)" = "false" ] \
  && ok "subtask_complete + result_block_present:true -> settled, ended_without_result:false" \
  || no "worker-clean -> expected settled/false, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-noresult 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] && [ "$(get "$out" .ended_without_result)" = "true" ] \
  && ok "subtask_complete + result_block_present:false -> settled, ended_without_result:true" \
  || no "worker-noresult -> expected settled/true, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id reviewer-ledger 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] && [ "$(get "$out" .ended_without_result)" = "false" ] \
  && ok "token_ledger (non-worker terminal event) -> settled, ended_without_result:false" \
  || no "reviewer-ledger -> expected settled/false, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-failed 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] && [ "$(get "$out" .ended_without_result)" = "true" ] \
  && ok "agent_lifecycle:failed -> settled, ended_without_result:true" \
  || no "worker-failed -> expected settled/true, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-unsettled 2>/dev/null)"
[ "$(get "$out" .status)" = "unsettled" ] && [ "$(get "$out" .ended_without_result)" = "false" ] \
  && ok "agent_identity with no terminal row -> unsettled" \
  || no "worker-unsettled -> expected unsettled, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id no-such-agent 2>/dev/null)"
[ "$(get "$out" .status)" = "unsettled" ] \
  && ok "unknown agent_id (not even an identity row) -> unsettled, not an error" \
  || no "no-such-agent -> expected unsettled, got: $out"

# ---------------------------------------------------------------------------
# 3r) rejected stops are NOT terminal (v15.83.0) — the probe-B sequence: a first
#     stop the sibling validator blocked (`rejected: true`, `stop_hook_active:
#     false`) followed by the accepted retry (`rejected: false`, `stop_hook_active:
#     true`). The rejected row here deliberately carries `result_block_present:
#     false` so a regression that merely skips it for SETTLEDNESS but still lets
#     it decide ended_without_result would read `true` and fail.
# ---------------------------------------------------------------------------
out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-rejected-then-accepted 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] && [ "$(get "$out" .ended_without_result)" = "false" ] \
  && [ "$(get "$out" .rejected_stops)" = "1" ] \
  && ok "rejected then accepted -> settled on the ACCEPTED row, ended_without_result:false (the rejected row's result_block_present:false is ignored), rejected_stops:1" \
  || no "worker-rejected-then-accepted -> expected settled/false/rejected_stops:1, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-rejected-only 2>/dev/null)"
[ "$(get "$out" .status)" = "unsettled" ] && [ "$(get "$out" .ended_without_result)" = "false" ] \
  && [ "$(get "$out" .rejected_stops)" = "1" ] \
  && ok "rejected only (worker still running, or forced to stop at the runtime cap) -> unsettled, rejected_stops:1 — never settled" \
  || no "worker-rejected-only -> expected unsettled/rejected_stops:1, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-clean 2>/dev/null)"
[ "$(get "$out" .rejected_stops)" = "0" ] \
  && ok "an explicit rejected:false row is terminal and counts 0 rejected_stops" \
  || no "worker-clean rejected_stops -> expected 0, got: $out"

out="$(bash "$SCRIPT" --log "$LOG" --agent-id worker-noresult 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] && [ "$(get "$out" .rejected_stops)" = "0" ] \
  && ok "a pre-v15.83.0 row (no rejected key at all) is terminal exactly as before, rejected_stops:0" \
  || no "worker-noresult (no rejected key) -> expected settled/rejected_stops:0, got: $out"

# ---------------------------------------------------------------------------
# 4) --all aggregate over the same fixture
# ---------------------------------------------------------------------------
out="$(bash "$SCRIPT" --log "$LOG" --all 2>/dev/null)"
echo "$out" | jq -e . >/dev/null 2>&1 && ok "--all output is valid JSON" || no "--all output is not valid JSON: $out"
[ "$(get "$out" .status)" = "unsettled" ] \
  && ok "--all with worker-unsettled present -> aggregate status unsettled" \
  || no "--all aggregate -> expected unsettled, got: $out"
unsettled_ids="$(get "$out" '.unsettled_agent_ids | sort | join(",")')"
[ "$unsettled_ids" = "worker-rejected-only,worker-unsettled" ] \
  && ok "--all unsettled_agent_ids names exactly worker-rejected-only + worker-unsettled (the rejected-then-accepted worker is settled)" \
  || no "--all unsettled_agent_ids -> expected [worker-rejected-only,worker-unsettled], got: $unsettled_ids"
ewr_ids="$(get "$out" '.ended_without_result_ids | sort | join(",")')"
[ "$ewr_ids" = "worker-failed,worker-noresult" ] \
  && ok "--all ended_without_result_ids names worker-failed + worker-noresult (a rejected row's result_block_present:false never contributes)" \
  || no "--all ended_without_result_ids -> expected worker-failed,worker-noresult, got: $ewr_ids"
rej_ids="$(get "$out" '.rejected_stop_ids | sort | join(",")')"
[ "$rej_ids" = "worker-rejected-only,worker-rejected-then-accepted" ] \
  && ok "--all rejected_stop_ids names every identity with >=1 rejected row, settled or not (diagnostic, never the verdict)" \
  || no "--all rejected_stop_ids -> expected worker-rejected-only,worker-rejected-then-accepted, got: $rej_ids"

# ---------------------------------------------------------------------------
# 5) all-settled fixture -> --all reports settled (never no_identity_rows)
# ---------------------------------------------------------------------------
LOG2="$TMP/all-settled.jsonl"
cat > "$LOG2" <<'JSONL'
{"event":"agent_identity","session_id":"s2","cc_session_id":"s2","agent_id":"worker-only","agent_type":"loomwright:worker"}
{"event":"subtask_complete","agent_id":"worker-only","result_block_present":true}
JSONL
out="$(bash "$SCRIPT" --log "$LOG2" --all 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] \
  && [ "$(get "$out" '.unsettled_agent_ids | length')" = "0" ] \
  && [ "$(get "$out" '.ended_without_result_ids | length')" = "0" ] \
  && [ "$(get "$out" '.rejected_stop_ids | length')" = "0" ] \
  && ok "all-settled fixture -> --all reports settled with empty arrays" \
  || no "all-settled fixture -> expected settled/[]/[]/[], got: $out"

# ---------------------------------------------------------------------------
# 6) empty log (no lines at all) -> no_identity_rows
# ---------------------------------------------------------------------------
LOG3="$TMP/empty.jsonl"
: > "$LOG3"
out="$(bash "$SCRIPT" --log "$LOG3" --all 2>/dev/null)"
[ "$(get "$out" .status)" = "no_identity_rows" ] \
  && [ "$(get "$out" '.rejected_stop_ids | length')" = "0" ] \
  && ok "empty (but existing) log -> no_identity_rows (rejected_stop_ids present and empty)" \
  || no "empty log -> expected no_identity_rows, got: $out"

# ---------------------------------------------------------------------------
# 7) seam checks — the consumers cite the script + the right decision strings
# ---------------------------------------------------------------------------
grep -q "check-children-settled.sh" "$EM" && grep -q "provides_present_agent_unsettled" "$EM" \
  && ok "execute-manager.md cites check-children-settled.sh + provides_present_agent_unsettled" \
  || no "execute-manager.md missing the script cite or the decision string"

grep -q "check-children-settled.sh" "$SUP" && grep -q -- "--agent-id {worker_id}" "$SUP" \
  && ok "supervisor.md cites check-children-settled.sh --agent-id (per-subtask join)" \
  || no "supervisor.md missing the --agent-id per-subtask cite"

grep -q "check-children-settled.sh" "$SUP" && grep -q -- "--all\`" "$SUP" \
  && ok "supervisor.md cites check-children-settled.sh --all (FINALIZE aggregate)" \
  || no "supervisor.md missing the --all FINALIZE cite"

grep -q "children_unsettled" "$SUP" && grep -q -- "--skip-children-check" "$SUP" \
  && ok "supervisor.md documents children_unsettled + --skip-children-check" \
  || no "supervisor.md missing children_unsettled or --skip-children-check"

grep -q "check-children-settled.sh" "$ASYNC" && grep -q "children_unsettled" "$ASYNC" \
  && ok "async-orchestration SKILL.md Phase 4 checklist cites the script + children_unsettled" \
  || no "async-orchestration SKILL.md missing the script cite or children_unsettled"

grep -q -- "--skip-children-check" "$CMD" \
  && ok "commands/supervisor.md Parameters table documents --skip-children-check" \
  || no "commands/supervisor.md missing --skip-children-check"

grep -q "check-children-settled.sh" "$SCHEMAS" && grep -q "provides_present_agent_unsettled" "$SCHEMAS" \
  && grep -q "children_unsettled" "$SCHEMAS" \
  && ok "RESULT_SCHEMAS.md documents the script + both new decision/error strings" \
  || no "RESULT_SCHEMAS.md missing the script cite or one of the new strings"

grep -q "rejected_stops" "$SCHEMAS" && grep -q "rejected_stop_ids" "$SCHEMAS" \
  && grep -q '`rejected`' "$SCHEMAS" \
  && ok "RESULT_SCHEMAS.md documents the rejected row field + rejected_stops / rejected_stop_ids (v15.83.0)" \
  || no "RESULT_SCHEMAS.md missing rejected / rejected_stops / rejected_stop_ids"

grep -q "rejected_stops" "$EM" \
  && ok "execute-manager.md's unsettled branch names rejected_stops (a validator-rejected stop is a documented cause of unsettled)" \
  || no "execute-manager.md does not mention rejected_stops"

grep -q "rejected_stop_ids" "$ASYNC" \
  && ok "async-orchestration SKILL.md Point 5 names rejected_stop_ids" \
  || no "async-orchestration SKILL.md does not mention rejected_stop_ids"

grep -q "children_unsettled" "$FAILDOC" && grep -q -- "--skip-children-check" "$FAILDOC" \
  && ok "FAILURE_ESCALATION.md documents the children-unsettled gate + escape hatch" \
  || no "FAILURE_ESCALATION.md missing children_unsettled or --skip-children-check"

# ---------------------------------------------------------------------------
# 8) MUTATION CONTROL — deleting the agent_lifecycle:failed branch from a COPY
#    of the script must turn worker-failed's settled verdict into unsettled.
# ---------------------------------------------------------------------------
MUT="$TMP/mutant.sh"
sed 's/^\( *\)or (\$l\.event == "agent_lifecycle" and \$l\.state == "failed") then/\1then/' "$SCRIPT" > "$MUT"
chmod +x "$MUT"
mut_out="$(bash "$MUT" --log "$LOG" --agent-id worker-failed 2>/dev/null)"
if [ "$(get "$mut_out" .status)" != "settled" ]; then
  ok "mutation control: removing the agent_lifecycle:failed branch flips worker-failed to non-settled"
else
  no "mutation control: mutant still reports worker-failed as settled — the OR branch is vacuous"
fi

# ---------------------------------------------------------------------------
# 9) MUTATION CONTROL (m2) — deleting the `rejected` guard from a COPY of
#    `terminal_for` must flip worker-rejected-only from unsettled to settled;
#    otherwise the guard that keeps a rejected stop non-terminal is vacuous.
#    The sed targets the ONE line carrying the guard; the control is inconclusive
#    (and FAILS) if the copy is byte-identical to the script.
# ---------------------------------------------------------------------------
MUT2="$TMP/mutant-rejected.sh"
sed 's/ and (\$l\.rejected? == true | not))/)/' "$SCRIPT" > "$MUT2"
chmod +x "$MUT2"
if cmp -s "$MUT2" "$SCRIPT"; then
  no "mutation control (rejected): could not build the mutant — the guard line was not found, control inconclusive"
else
  mut_out="$(bash "$MUT2" --log "$LOG" --agent-id worker-rejected-only 2>/dev/null)"
  if [ "$(get "$mut_out" .status)" = "settled" ]; then
    ok "mutation control (rejected): removing the rejected guard flips worker-rejected-only to settled — the guard is load-bearing"
  else
    no "mutation control (rejected): mutant still reports worker-rejected-only as $(get "$mut_out" .status) — the guard is vacuous or the mutant missed it"
  fi
fi

# ---------------------------------------------------------------------------
# ended) automate-followups/33 — the agent_lifecycle:ended tier
# ---------------------------------------------------------------------------
EFX="$HERE/fixtures/children-settled-ended.jsonl"
agent_v() { bash "$SCRIPT" --log "${2:-$EFX}" --agent-id "$1" 2>/dev/null | jq -r '.status + "/" + (.ended_without_result|tostring)'; }
expect_agent() {
  local id="$1" want="$2" got; got="$(agent_v "$id")"
  if [ "$got" = "$want" ]; then ok "ended: $id -> $want"; else no "ended: $id expected $want, got $got"; fi
}
expect_agent gp-settled settled/false
expect_agent pr-turnlimit settled/false
expect_agent explore-maxturns settled/true
expect_agent worker-turnlimit settled/true
expect_agent worker-clean settled/false
expect_agent worker-rejected-ended unsettled/false
expect_agent worker-rejected-returned settled/true
expect_agent hung-child unsettled/false
all_out="$(bash "$SCRIPT" --log "$EFX" --all 2>/dev/null)"
if [ "$(get "$all_out" '.status')" = "unsettled" ] \
   && [ "$(get "$all_out" '.unsettled_agent_ids | sort | join(",")')" = "hung-child,worker-rejected-ended" ] \
   && [ "$(get "$all_out" '.ended_without_result_ids | sort | join(",")')" = "explore-maxturns,worker-rejected-returned,worker-turnlimit" ]; then
  ok "ended: --all keeps the hung child + the rejected-stop worker unsettled and names the ended_without_result ids"
else
  no "ended: --all aggregate wrong: $all_out"
fi
SETTLED_ONLY="$TMP/ended-settled-only.jsonl"
grep -E '"(gp-settled|pr-turnlimit)"' "$EFX" > "$SETTLED_ONLY"
if [ "$(get "$(bash "$SCRIPT" --log "$SETTLED_ONLY" --all 2>/dev/null)" .status)" = "settled" ]; then
  ok "ended: a log holding only a finished general-purpose spawn + a turn-limit return reads settled (--all)"
else
  no "ended: settled-only log did not read settled"
fi
MUT3="$TMP/mutant-ended.sh"
sed 's/\$l\.state == "ended")/$l.state == "ended-MUTANT")/' "$SCRIPT" > "$MUT3"
if cmp -s "$MUT3" "$SCRIPT"; then
  no "mutation control (ended): could not build the mutant — the ended arm was not found, control inconclusive"
else
  m3a="$(bash "$MUT3" --log "$SETTLED_ONLY" --all 2>/dev/null)"
  if [ "$(get "$m3a" .status)" = "unsettled" ] && [ "$(get "$m3a" '.unsettled_agent_ids | length')" = "2" ]; then
    ok "mutation control (ended): removing the ended arm turns both the general-purpose and turn-limit fixtures unsettled"
  else
    no "mutation control (ended): mutant still reads $(get "$m3a" .status) — the ended arm is vacuous"
  fi
fi

# ---------------------------------------------------------------------------
# expect-id) agnostic-phase1/02 — `--all --expect-id <id>`: ids the caller KNOWS it
#    spawned are checked by the same join even when no agent_identity row landed.
# ---------------------------------------------------------------------------
NIR='{"status":"no_identity_rows","unsettled_agent_ids":[],"ended_without_result_ids":[],"rejected_stop_ids":[],"source":"check-children-settled.sh"}'
out="$(bash "$SCRIPT" --log "$NOLOG" --all --expect-id a1 2>/dev/null)"; rc=$?
if [ "$rc" = 0 ] && grep -qF '"status":"unsettled"' <<<"$out" && grep -qF '"unsettled_agent_ids":["a1"]' <<<"$out"; then
  ok "expect-id: no log + --expect-id a1 -> unsettled naming a1, exit 0"
else
  no "expect-id: no log + --expect-id a1 -> expected unsettled/[a1]/exit 0, got rc=$rc: $out"
fi
out="$(bash "$SCRIPT" --log "$NOLOG" --all 2>/dev/null)"
[ "$out" = "$NIR" ] && ok "expect-id: no flag + no log -> byte-identical no_identity_rows" \
  || no "expect-id: no flag + no log -> output changed: $out"
out="$(bash "$SCRIPT" --log "$LOG3" --all 2>/dev/null)"
[ "$out" = "$NIR" ] && ok "expect-id: no flag + empty log -> byte-identical no_identity_rows" \
  || no "expect-id: no flag + empty log -> output changed: $out"
out="$(bash "$SCRIPT" --log "$LOG3" --all --expect-id a1 2>/dev/null)"
[ "$(get "$out" .status)" = "unsettled" ] && [ "$(get "$out" '.unsettled_agent_ids | join(",")')" = "a1" ] \
  && ok "expect-id: empty log + --expect-id a1 -> unsettled naming a1 (never no_identity_rows)" \
  || no "expect-id: empty log + --expect-id -> expected unsettled/[a1], got: $out"

XLOG="$TMP/expect.jsonl"
cat > "$XLOG" <<'JSONL'
{"event":"agent_identity","agent_id":"exp-identity-only","agent_type":"loomwright:worker"}
{"event":"subtask_complete","agent_id":"exp-terminal-no-identity","result_block_present":true}
{"event":"agent_identity","agent_id":"other-identity-unsettled","agent_type":"loomwright:code-reviewer"}
JSONL
out="$(bash "$SCRIPT" --log "$XLOG" --all --expect-id exp-identity-only 2>/dev/null)"
[ "$(get "$out" .status)" = "unsettled" ] \
  && [ "$(get "$out" '.unsettled_agent_ids | sort | join(",")')" = "exp-identity-only,other-identity-unsettled" ] \
  && ok "expect-id: an expected id with only an agent_identity row -> unsettled" \
  || no "expect-id: identity-only expected id -> expected unsettled, got: $out"
XLOG2="$TMP/expect-terminal-only.jsonl"
grep '"exp-terminal-no-identity"' "$XLOG" > "$XLOG2"
out="$(bash "$SCRIPT" --log "$XLOG2" --all --expect-id exp-terminal-no-identity 2>/dev/null)"
[ "$(get "$out" .status)" = "settled" ] && [ "$(get "$out" '.unsettled_agent_ids | length')" = "0" ] \
  && ok "expect-id: an expected id with a terminal row (and NO identity row) -> settled, never no_identity_rows" \
  || no "expect-id: terminal-row expected id -> expected settled, got: $out"
out="$(bash "$SCRIPT" --log "$XLOG" --all --expect-id exp-terminal-no-identity --expect-id=exp-terminal-no-identity 2>/dev/null)"
[ "$(get "$out" .status)" = "unsettled" ] \
  && [ "$(get "$out" '.unsettled_agent_ids | join(",")')" = "exp-identity-only,other-identity-unsettled" ] \
  && ok "expect-id: identity ids are still checked (union with the deduped expected ids; the settled expected id is not named)" \
  || no "expect-id: union -> expected [exp-identity-only,other-identity-unsettled], got: $out"
out="$(bash "$SCRIPT" --log "$LOG2" --all --expect-id worker-only 2>/dev/null)"
[ "$out" = "$(bash "$SCRIPT" --log "$LOG2" --all 2>/dev/null)" ] && [ "$(get "$out" .status)" = "settled" ] \
  && ok "expect-id: an expected id that also has an identity row is checked once (output identical to the flagless run)" \
  || no "expect-id: overlap with an identity id changed the verdict: $out"
for bad in "--agent-id x --expect-id a1" "--all --expect-id" "--all --expect-id="; do
  # word-splitting the argument list is the point here
  # shellcheck disable=SC2086
  out="$(bash "$SCRIPT" --log "$XLOG" $bad 2>/dev/null)"
  [ "$(get "$out" .status)" = "unverifiable" ] && [ "$(get "$out" .reason)" = "bad_args" ] \
    && ok "expect-id: [$bad] -> unverifiable/bad_args" \
    || no "expect-id: [$bad] -> expected unverifiable/bad_args, got: $out"
done
grep -q -- "--expect-id" < <(sed -n '/^# Usage:/,/^# A "terminal row"/p' "$SCRIPT") \
  && ok "expect-id: the script header's Usage / Output block documents --expect-id" \
  || no "expect-id: the script header's Usage / Output block does not document --expect-id"

# seams: FINALIZE Point 5 passes the expected ids; the two skill worker-spawn examples use the plugin worker
grep -q -- "--expect-id" < <(grep -E '^ *\*\*Point 5 — children settled' "$SUP") \
  && ok "seam: supervisor.md Point 5 passes --expect-id" \
  || no "seam: supervisor.md Point 5 does not pass --expect-id"
# section <file> <heading> — the lines from <heading> up to the next markdown heading
section() { awk -v h="$2" '$0 == h {p=1; print; next} p && /^#+ / {exit} p' "$1"; }
for spec in "$ASYNC|### Spawning a Worker" "$WFM|### Worker Dispatch"; do
  f="${spec%%|*}"; h="${spec#*|}"; body="$(section "$f" "$h")"
  if [ -n "$body" ] && grep -qF 'subagent_type: "loomwright:worker"' <<<"$body" \
     && ! grep -qF 'subagent_type: "general-purpose"' <<<"$body"; then
    ok "seam: ${f#"$PLUGIN_ROOT"/} §\"${h#\#\#\# }\" spawns loomwright:worker, not general-purpose"
  else
    no "seam: ${f#"$PLUGIN_ROOT"/} §\"${h#\#\#\# }\" missing, or its worker spawn is not loomwright:worker"
  fi
done

# (m4) MUTATION CONTROL — a COPY that ignores --expect-id must lose the no-log verdict.
MUT4="$TMP/mutant-expect.sh"
sed 's/^\( *\)\*) expect_ids="\$expect_ids\$1\$NL" ;;$/\1*) : ;;/' "$SCRIPT" > "$MUT4"
if [ ! -s "$MUT4" ] || cmp -s "$MUT4" "$SCRIPT" || ! bash -n "$MUT4" 2>/dev/null; then
  no "mutation control (expect-id): mutant empty, identical to the script, or not valid bash — control inconclusive"
else
  m4="$(bash "$MUT4" --log "$NOLOG" --all --expect-id a1 2>/dev/null)"
  if [ "$(get "$m4" .status)" != "unsettled" ]; then
    ok "mutation control (expect-id): ignoring --expect-id turns the no-log case $(get "$m4" .status) — the flag is load-bearing"
  else
    no "mutation control (expect-id): mutant still reads unsettled — the no-log assertion does not exercise --expect-id"
  fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
