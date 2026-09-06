#!/usr/bin/env bash
# emit-agent-identity.sh — fail-SAFE PostToolUse[Task] agent-identity emitter.
#
# INVARIANT: ALWAYS exits 0. Never blocks the agent run. Modelled LINE-FOR-LINE
# IN DISCIPLINE on emit-token-ledger.sh and emit-progress-event.sh (read those
# headers first — this file inherits their conventions exactly): `set -u` with
# NO `set -e`, `trap 'exit 0' EXIT`, a stdin read that no-ops on empty, and the
# main-checkout log-directory resolution that refuses to guess.
#
# WHY THIS EXISTS
# ----------------
# The Floor rendered `identity unknown` on almost every lane, and the standing
# explanation — "the SubagentStop payload does not carry an agent_type" — was
# true and led to the wrong conclusion. Measured across one real project's whole
# history: 1,040 distinct agent ids, 64 carrying a type and 976 not. Two
# candidate repairs were tested and BOTH fail:
#
#   * the `agent-<id>.meta.json` sidecar Claude Code writes beside a subagent
#     transcript DOES carry `agentType` — but it intersects the typed set 64/64
#     and the untyped set 0/976. An agent has a sidecar exactly when its type is
#     already known, so the lookup re-derives what is known and resolves nothing.
#   * nothing else on disk records what those agents were, so no back-fill of
#     existing lanes is possible in any form.
#
# The identity is on a THIRD hook nobody registered. A single `PostToolUse[Task]`
# payload carries both halves at once — `tool_input.subagent_type` (the role) and
# `tool_response.agentId` (an id in the SAME namespace as `SubagentStop.agent_id`)
# — so no join across events, no correlation store and no third hook are needed.
# The evidence is committed: scripts/progress-event-fixtures/spawn-probe-2026-09-02/
# holds six real captures from one run, and docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md
# records the measurement. That spike closed NO-GO against a DIFFERENT requirement
# (a live spawn-time `agent_spawn` event joinable at spawn), which is why this
# reading of the same evidence was never taken.
#
# THE MATCHER IS `Task` AND THE PAYLOAD SAYS `tool_name: "Agent"`. Both hold at
# once — recorded in that spike as finding 1, and the reason this script does NOT
# filter on the payload's `tool_name`: a consumer that did would never fire.
#
# WHY IT WRITES A LOG LINE RATHER THAN RESOLVING THE TYPE IN PLACE. PostToolUse
# [Task] and SubagentStop both fire when a subagent finishes and their order is
# NOT guaranteed, so an emitter that tried to enrich the stop line would race.
# Writing an independent line and letting the PROJECTOR join by `agent_id` at read
# time is race-free by construction — and build-floor.sh already takes `agent_type`
# from ANY line of an agent, so the join needed no new projector code, only an
# exclusion so this line is not counted as one of that agent's events.

set -u
# Intentionally NO `set -e` — every failure mode must absorb to exit 0.

# ---- Always-exit-0 trap ------------------------------------------------------
trap 'exit 0' EXIT

# ---- Read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
case "$INPUT" in "{"*) ;; *) exit 0 ;; esac

command -v jq >/dev/null 2>&1 || exit 0

# ---- The two fields, and BOTH must be present --------------------------------
# A line carrying one without the other is not an identity: an agent_id with no
# type says nothing this projector did not already know, and a type with no id
# cannot be attached to a lane. Fail SAFE — write nothing rather than a row that
# would have to be interpreted.
AGENT_ID="$(printf '%s' "$INPUT" | jq -r 'if (.tool_response.agentId | type) == "string" then .tool_response.agentId else empty end' 2>/dev/null || true)"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r 'if (.tool_input.subagent_type | type) == "string" then .tool_input.subagent_type else empty end' 2>/dev/null || true)"
[ -n "$AGENT_ID" ] && [ -n "$AGENT_TYPE" ] || exit 0
# Shape-filter the id the same way the rest of this plugin filters slugs: it
# becomes a grouping key in a projection, never a path, but a control character
# in a JSONL field is a corrupt line for every downstream reader.
case "$AGENT_ID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

# ---- Where the log lives — the main checkout, never a guess ------------------
# Identical to emit-progress-event.sh: a worktree's `.supervisor/` is not the
# project's, so resolve the FIRST entry of `git worktree list` (the main
# checkout) and refuse when that is not a toplevel.
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] && [ -d "$main_root" ] || exit 0
top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
[ "$top" = "$main_root" ] || exit 0
LOG_DIR="$main_root/.supervisor/logs"

CC_SESSION_ID="$(printf '%s' "$INPUT" | jq -r 'if (.session_id | type) == "string" then .session_id else empty end' 2>/dev/null || true)"
[ -n "$CC_SESSION_ID" ] || exit 0
case "$CC_SESSION_ID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

LINE="$(jq -nc \
  --arg id "$AGENT_ID" --arg t "$AGENT_TYPE" --arg s "$CC_SESSION_ID" --arg ts "$TS" '
  {event: "agent_identity", session_id: $s, cc_session_id: $s, agent_id: $id, agent_type: $t}
  + (if $ts == "" then {} else {recorded_at: $ts} end)' 2>/dev/null || true)"
[ -n "$LINE" ] || exit 0

# NO `ts` FIELD, DELIBERATELY, and this is the one field decision worth stating.
# `ts` is what the projector uses to pick the newest session and to span a lane's
# first/last event. This line is not an event of the agent — it is a fact ABOUT
# it — so a `ts` here would let a lane's "last event" age report the moment its
# identity was recorded, and could make an otherwise-idle session look newest.
# The time is kept under `recorded_at` so the line is still auditable.

mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/${CC_SESSION_ID}.jsonl"

# One identity per agent is enough, and PostToolUse can fire again for a retried
# tool call. The scan is bounded to the tail because an identity is written near
# the agent's own lines; a miss costs a duplicate row that the projector's `first`
# already collapses.
#
# IT COMPARES THE IDENTITY, NOT THE LINE, and that distinction is the whole guard.
# The first version of this was `grep -qxF "$LINE"` — byte-identity — which is
# defeated by the line's own `recorded_at`: two firings a second apart produce two
# different lines describing the SAME agent, and both were written. It passed on
# macOS because three firings landed inside one second, and CI (Linux) failed it at
# `expected 1, actual 2`. The identity of this row is (cc_session_id, agent_id,
# agent_type); the timestamp is metadata about when it was noticed.
#
# Parsed per line rather than grepped for a substring, so field order and any future
# additive field cannot silently break the match, and `fromjson? // empty` skips a
# malformed neighbouring line instead of aborting the scan. Every failure here falls
# through to the append: a duplicate identity row is harmless (the projector takes
# the FIRST type it sees), a missing one is not.
if [ -f "$LOG_FILE" ]; then
  _dup="$(tail -200 "$LOG_FILE" 2>/dev/null | jq -R -r \
    --arg id "$AGENT_ID" --arg t "$AGENT_TYPE" --arg s "$CC_SESSION_ID" '
      (fromjson? // empty)
      | select((.event? == "agent_identity") and (.agent_id? == $id)
               and (.agent_type? == $t) and (.cc_session_id? == $s))
      | "dup"' 2>/dev/null || true)"
  case "$_dup" in *dup*) exit 0 ;; esac
fi

printf '%s\n' "$LINE" >> "$LOG_FILE" 2>/dev/null || true
exit 0
