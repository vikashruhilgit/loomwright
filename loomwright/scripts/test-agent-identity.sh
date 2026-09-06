#!/usr/bin/env bash
# test-agent-identity.sh — self-tests for emit-agent-identity.sh.
#
# The SUT reads a `PostToolUse[Task]` payload and writes ONE `agent_identity` line
# joining `tool_response.agentId` to `tool_input.subagent_type`. Every positive case
# below is driven by the SIX REAL CAPTURES committed at
# progress-event-fixtures/spawn-probe-2026-09-02/ rather than by a hand-written
# payload, because the whole reason this emitter exists is that hand-reasoning about
# this payload has been wrong three times: the sidecar theory (0/976), the
# meta-lookup theory, and `tool_name` (the matcher is `Task`, the payload says
# `Agent`). A fixture nobody invented cannot inherit an invented assumption.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/emit-agent-identity.sh"
FIX="$HERE/progress-event-fixtures/spawn-probe-2026-09-02"
PASS=0; FAIL=0
ok() { echo "  ok: $1"; PASS=$((PASS+1)); }
no() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1  expected='$2' actual='$3'"; fi; }

[ -f "$SUT" ] || { echo "FATAL: $SUT missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required"; exit 1; }

SB="$(mktemp -d)" || exit 1
trap 'rm -rf "$SB" 2>/dev/null || true' EXIT INT TERM

new_repo() { d="$(mktemp -d "$SB/repo.XXXXXX")"; ( cd "$d" && git init -q . ) >/dev/null 2>&1; printf '%s' "$d"; }
run() { # run <repo> <payload-file>  -> rc
  ( cd "$1" && bash "$SUT" < "$2" >/dev/null 2>&1 ); printf '%s' "$?"; }
logline() { cat "$1"/.supervisor/logs/*.jsonl 2>/dev/null; }

echo "== 1. the real captures: both halves are read out of ONE payload =="
# PREMISE, asserted rather than assumed: the fixture must actually contain the two
# fields this emitter joins, or every assertion below passes for the wrong reason.
P1="$FIX/posttooluse-task-1.json"
[ -f "$P1" ] || { echo "FATAL: committed capture missing: $P1"; exit 1; }
prem_id="$(jq -r '.tool_response.agentId // empty' "$P1")"
prem_ty="$(jq -r '.tool_input.subagent_type // empty' "$P1")"
prem_tn="$(jq -r '.tool_name // empty' "$P1")"
if [ -n "$prem_id" ] && [ -n "$prem_ty" ]; then
  ok "PREMISE: the committed capture carries agentId='$prem_id' AND subagent_type='$prem_ty' in one payload"
else
  no "PREMISE: the committed capture no longer carries both fields (id='$prem_id' type='$prem_ty') — every case below is vacuous"
fi
eq "PREMISE: and its tool_name is 'Agent' though the matcher is 'Task' — the finding this emitter must not trip over" "Agent" "$prem_tn"

R1="$(new_repo)"
eq "exits 0" "0" "$(run "$R1" "$P1")"
L1="$(logline "$R1")"
eq "writes agent_id from tool_response.agentId" "$prem_id" "$(printf '%s' "$L1" | jq -r '.agent_id')"
eq "writes agent_type from tool_input.subagent_type" "$prem_ty" "$(printf '%s' "$L1" | jq -r '.agent_type')"
eq "the line is tagged event=agent_identity" "agent_identity" "$(printf '%s' "$L1" | jq -r '.event')"

echo "== 2. no 'ts' field — the omission is deliberate and load-bearing =="
# `ts` is what build-floor.sh uses to pick the NEWEST session and to span a lane's
# first/last event. This line is a fact ABOUT an agent, not an event OF one: a `ts`
# here would let a lane's "last event" age report when its identity was recorded,
# and could make an idle session look newest. The time is kept under `recorded_at`.
eq "carries no ts" "false" "$(printf '%s' "$L1" | jq -r 'has("ts")')"
eq "but is still auditable via recorded_at" "true" "$(printf '%s' "$L1" | jq -r 'has("recorded_at")')"

echo "== 3. BOTH halves are required — one without the other is not an identity =="
jq 'del(.tool_response.agentId)' "$P1" > "$SB/no-id.json"
jq 'del(.tool_input.subagent_type)' "$P1" > "$SB/no-type.json"
for f in no-id no-type; do
  R="$(new_repo)"
  eq "$f: exits 0" "0" "$(run "$R" "$SB/$f.json")"
  eq "$f: writes NOTHING (a half-identity is not written as a row to be interpreted)" "" "$(logline "$R")"
done

echo "== 4. idempotent across a retried tool call =="
R4="$(new_repo)"
run "$R4" "$P1" >/dev/null; run "$R4" "$P1" >/dev/null; run "$R4" "$P1" >/dev/null
eq "three firings of one payload leave ONE line" "1" "$(logline "$R4" | awk 'NF{n++} END{print n+0}')"

echo "== 5. two different agents in one session are two different rows =="
R5="$(new_repo)"
run "$R5" "$FIX/posttooluse-task-1.json" >/dev/null
run "$R5" "$FIX/posttooluse-task-2.json" >/dev/null
eq "two agents ⇒ two lines" "2" "$(logline "$R5" | awk 'NF{n++} END{print n+0}')"
eq "and two distinct agent_ids" "2" "$(logline "$R5" | jq -r '.agent_id' | sort -u | awk 'NF{n++} END{print n+0}')"

echo "== 6. the ids it writes are the ones SubagentStop uses — the whole point =="
# Recomputed from the committed stop captures, never from this emitter's output.
join_bad=""
for f in "$FIX"/subagentstop-*.json; do
  [ -f "$f" ] || continue
  sid="$(jq -r '.agent_id // empty' "$f")"
  [ -n "$sid" ] || continue
  logline "$R5" | jq -e --arg a "$sid" 'select(.agent_id == $a)' >/dev/null 2>&1 || join_bad="$join_bad $sid"
done
[ -z "$join_bad" ] \
  && ok "every agent_id in the committed SubagentStop captures is matched by a row this emitter wrote — the join needs no correlation store" \
  || no "SubagentStop agent_id(s) with no identity row:$join_bad"

echo "== 7. fail-safe inputs all exit 0 and write nothing =="
R7="$(new_repo)"
( cd "$R7" && bash "$SUT" </dev/null >/dev/null 2>&1 ); eq "empty stdin exits 0" "0" "$?"
printf 'not json at all' > "$SB/junk.txt"
eq "non-JSON stdin exits 0" "0" "$(run "$R7" "$SB/junk.txt")"
printf '{"tool_input":{"subagent_type":"x"},"tool_response":{"agentId":"a1"}}' > "$SB/no-session.json"
eq "a payload with no session_id exits 0" "0" "$(run "$R7" "$SB/no-session.json")"
eq "and none of the three wrote anything" "" "$(logline "$R7")"

echo "== 8. a hostile agent_id is refused, not sanitised =="
# It becomes a grouping key in a projection rather than a path, but a control
# character or a separator in a JSONL field is a corrupt line for every reader.
R8="$(new_repo)"
jq '.tool_response.agentId = "../../etc/passwd"' "$P1" > "$SB/evil.json"
eq "traversal-shaped id: exits 0" "0" "$(run "$R8" "$SB/evil.json")"
eq "traversal-shaped id: writes nothing" "" "$(logline "$R8")"

echo ""
echo "RESULT  pass=$PASS  fail=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
