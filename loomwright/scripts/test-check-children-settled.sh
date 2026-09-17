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
#
# EXPLICIT LIMIT: this pins the script's behaviour and the WIRING (the prompts cite it where they say
# they do). It cannot prove an Execute Manager / Supervisor actually runs the Bash call at runtime.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

SCRIPT="$HERE/check-children-settled.sh"
EM="$PLUGIN_ROOT/agents/execute-manager.md"
SUP="$PLUGIN_ROOT/agents/supervisor.md"
ASYNC="$PLUGIN_ROOT/skills/async-orchestration/SKILL.md"
CMD="$PLUGIN_ROOT/commands/supervisor.md"
SCHEMAS="$PLUGIN_ROOT/docs/RESULT_SCHEMAS.md"
FAILDOC="$PLUGIN_ROOT/docs/FAILURE_ESCALATION.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$SCRIPT" "$EM" "$SUP" "$ASYNC" "$CMD" "$SCHEMAS" "$FAILDOC"; do
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
this is not json at all
{"event":"subtask_complete","agent_id":"worker-clean","result_block_present":true}
{"event":"subtask_complete","agent_id":"worker-noresult","result_block_present":false}
{"event":"token_ledger","agent_id":"reviewer-ledger"}
{"event":"agent_lifecycle","state":"failed","agent_id":"worker-failed","reason":"rate_limit"}
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
# 4) --all aggregate over the same fixture
# ---------------------------------------------------------------------------
out="$(bash "$SCRIPT" --log "$LOG" --all 2>/dev/null)"
echo "$out" | jq -e . >/dev/null 2>&1 && ok "--all output is valid JSON" || no "--all output is not valid JSON: $out"
[ "$(get "$out" .status)" = "unsettled" ] \
  && ok "--all with worker-unsettled present -> aggregate status unsettled" \
  || no "--all aggregate -> expected unsettled, got: $out"
unsettled_ids="$(get "$out" '.unsettled_agent_ids | sort | join(",")')"
[ "$unsettled_ids" = "worker-unsettled" ] \
  && ok "--all unsettled_agent_ids names exactly worker-unsettled" \
  || no "--all unsettled_agent_ids -> expected [worker-unsettled], got: $unsettled_ids"
ewr_ids="$(get "$out" '.ended_without_result_ids | sort | join(",")')"
[ "$ewr_ids" = "worker-failed,worker-noresult" ] \
  && ok "--all ended_without_result_ids names worker-failed + worker-noresult" \
  || no "--all ended_without_result_ids -> expected worker-failed,worker-noresult, got: $ewr_ids"

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
  && ok "all-settled fixture -> --all reports settled with empty arrays" \
  || no "all-settled fixture -> expected settled/[]/[], got: $out"

# ---------------------------------------------------------------------------
# 6) empty log (no lines at all) -> no_identity_rows
# ---------------------------------------------------------------------------
LOG3="$TMP/empty.jsonl"
: > "$LOG3"
out="$(bash "$SCRIPT" --log "$LOG3" --all 2>/dev/null)"
[ "$(get "$out" .status)" = "no_identity_rows" ] \
  && ok "empty (but existing) log -> no_identity_rows" \
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

grep -q "children_unsettled" "$FAILDOC" && grep -q -- "--skip-children-check" "$FAILDOC" \
  && ok "FAILURE_ESCALATION.md documents the children-unsettled gate + escape hatch" \
  || no "FAILURE_ESCALATION.md missing children_unsettled or --skip-children-check"

# ---------------------------------------------------------------------------
# 8) MUTATION CONTROL — deleting the agent_lifecycle:failed branch from a COPY
#    of the script must turn worker-failed's settled verdict into unsettled.
# ---------------------------------------------------------------------------
MUT="$TMP/mutant.sh"
sed '/agent_lifecycle" and \$l.state == "failed" and \$l.agent_id == \$id)/d' "$SCRIPT" > "$MUT"
chmod +x "$MUT"
mut_out="$(bash "$MUT" --log "$LOG" --agent-id worker-failed 2>/dev/null)"
if [ "$(get "$mut_out" .status)" != "settled" ]; then
  ok "mutation control: removing the agent_lifecycle:failed branch flips worker-failed to non-settled"
else
  no "mutation control: mutant still reports worker-failed as settled — the OR branch is vacuous"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
