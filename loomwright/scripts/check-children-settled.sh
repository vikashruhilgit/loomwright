#!/usr/bin/env bash
# check-children-settled.sh — the ONE join between agent_identity/spawn rows and the terminal
# lifecycle events (subtask_complete | token_ledger | agent_lifecycle:failed) that "settle" an
# agent_id in a session's JSONL log (.supervisor/logs/{session_id}.jsonl).
#
# WHY THIS EXISTS (.supervisor/requirements/orca-derived/02-completion-authority.md): completion of a
# subtask is decided by TWO independent facts — the `provides` artefacts on disk (verify-provides.sh,
# unchanged by this script) AND a terminal lifecycle row for the producing worker's `agent_id` — never
# by the worker's own self-report alone. `provides` present on disk from a partial/interrupted run, a
# stale artifact, or a still-running worker that happens to write its files early would otherwise be
# marked complete regardless. This script is the SECOND, independent condition.
#
# WHY A SCRIPT, NOT RESTATED jq (the verify-provides.sh precedent): the 3-way OR across event shapes
# (`subtask_complete.agent_id` | `token_ledger.agent_id` | `agent_lifecycle{state:failed}.agent_id`)
# is consumed at FOUR call sites — agents/execute-manager.md's v12 outputs_verified gate (per-subtask),
# agents/supervisor.md's Single-Agent Path step 3 AND Sequential Path step (per-subtask, same join),
# and agents/supervisor.md's Phase 4 FINALIZE pre-merge safety gate (per-session aggregate, `--all`).
# Restating the OR condition in four places is exactly the drift class verify-provides.sh's own header
# names ("a restated copy drifts silently") — one implementation, cited by every consumer.
#
# Failure-mode split (CLAUDE.md §"Failure-Mode Invariants"): this script is a fail-SAFE EMITTER — it
# always exits 0, never writes, never mutates the log, never invents a value it did not read. Its
# CONSUMERS fail CLOSED: an `unsettled` verdict (or an `unverifiable` result the consumer cannot
# route) blocks completion / merge, exactly as verify-provides.sh's `missing` / `unverifiable` does.
#
# Usage:
#   check-children-settled.sh --log <path> --agent-id <id>   # single-agent join (per-subtask gate)
#   check-children-settled.sh --log <path> --all             # per-session aggregate (FINALIZE gate)
#
# Output (ONE JSON object on stdout, always exit 0):
#   single-agent: {"agent_id":"<id>","status":"settled"|"unsettled","ended_without_result":true|false,"source":"check-children-settled.sh"}
#   --all:        {"status":"settled"|"unsettled"|"no_identity_rows","unsettled_agent_ids":[...],"ended_without_result_ids":[...],"source":"check-children-settled.sh"}
#   A missing/unreadable `--log` in `--all` mode is the documented `no_identity_rows` case (a session
#   that never wrote a log trivially has zero `agent_identity` rows) — never `unverifiable`, never a
#   false `settled`. The SAME condition in single-agent mode is `unsettled` (no evidence of settlement
#   is not evidence of absence of the agent — fail closed toward "not done yet", never toward "done").
#   Malformed invocation (missing `--log`, or neither `--agent-id` nor `--all`) or a missing `jq` ⇒
#   `{"status":"unverifiable","reason":"bad_args"|"jq_missing","source":"check-children-settled.sh"}` —
#   routed by the consumer the same way verify-provides.sh's `unverifiable` is (never a silent pass).
#
# A "terminal row" for an agent_id is exactly one of:
#   - {"event":"subtask_complete", "agent_id":"<id>", ...}   (worker role terminal event)
#   - {"event":"token_ledger", "agent_id":"<id>", ...}       (non-worker roles' terminal event; this
#     event carries no `result_block_present` field yet — see docs/RESULT_SCHEMAS.md §agent_lifecycle
#     "forward-reference" note — so presence alone settles it)
#   - {"event":"agent_lifecycle", "state":"failed", "agent_id":"<id>", ...}
#
# `ended_without_result` (docs/RESULT_SCHEMAS.md §agent_lifecycle "Reader-derived states") is `true`
# when the FIRST terminal row found for that agent_id is EITHER a `subtask_complete` with
# `result_block_present: false` OR an `agent_lifecycle:failed` row — surfaced so an operator can
# SendMessage the `agent_id` to resume (memory `subagents-hit-turn-limit-resume-via-sendmessage`)
# instead of re-running the subtask cold. This script does not implement the resume — it only
# surfaces the id (via `ended_without_result` / `ended_without_result_ids`).
#
# HONEST LIMITS: a malformed JSONL line is skipped (`fromjson? // empty`), never aborts the scan. Only
# the FIRST matching terminal row (file order) decides `ended_without_result` for a given agent_id — a
# worker settles once. `--agent-id` performs no allowlist validation beyond what `jq --arg` already
# escapes safely; an id with no matching row is simply reported `unsettled`, never an error. Pure
# jq/POSIX-sh — no GNU/BSD-grep dependency (unlike verify-provides.sh, this join is JSONL filtering,
# not a file-content grep), bash 3.2 / BSD userland safe.
#
# Co-located static suite: test-check-children-settled.sh.

set -uo pipefail
SELF="check-children-settled.sh"

log=""
agent_id=""
mode=""   # "agent" | "all"
bad_args=""

while [ $# -gt 0 ]; do
  case "$1" in
    --log)
      if [ $# -lt 2 ]; then bad_args="--log needs a path argument"; break; fi
      log="$2"; shift 2 ;;
    --log=*) log="${1#--log=}"; shift ;;
    --agent-id)
      if [ $# -lt 2 ]; then bad_args="--agent-id needs a value argument"; break; fi
      agent_id="$2"; mode="agent"; shift 2 ;;
    --agent-id=*) agent_id="${1#--agent-id=}"; mode="agent"; shift ;;
    --all) mode="all"; shift ;;
    -h|--help)
      printf 'usage: %s --log <path> (--agent-id <id> | --all)\n' "$SELF" >&2
      exit 0 ;;
    *)
      printf '%s: unexpected argument %s (ignored)\n' "$SELF" "$1" >&2
      shift ;;
  esac
done

[ -z "$bad_args" ] && [ -z "$mode" ] && bad_args="one of --agent-id <id> or --all is required"
[ -z "$bad_args" ] && [ "$mode" = "agent" ] && [ -z "$agent_id" ] && bad_args="--agent-id needs a non-empty value"
[ -z "$bad_args" ] && [ -z "$log" ] && bad_args="--log is required"

if [ -n "$bad_args" ]; then
  printf '%s: unverifiable — bad_args (%s)\n' "$SELF" "$bad_args" >&2
  printf '{"status":"unverifiable","reason":"bad_args","source":"%s"}\n' "$SELF"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '%s: unverifiable — jq_missing (jq is required to run the log join)\n' "$SELF" >&2
  printf '{"status":"unverifiable","reason":"jq_missing","source":"%s"}\n' "$SELF"
  exit 0
fi

if [ ! -f "$log" ] || [ ! -r "$log" ]; then
  if [ "$mode" = "all" ]; then
    # No log at all ⇒ trivially zero agent_identity rows — this IS the documented no_identity_rows
    # case (a session that never wrote a log has nothing to check), never `unverifiable`, never a
    # false `settled`.
    jq -n -c --arg s "$SELF" \
      '{status: "no_identity_rows", unsettled_agent_ids: [], ended_without_result_ids: [], source: $s}'
    exit 0
  fi
  # Single-agent mode: no log ⇒ no evidence of settlement ⇒ unsettled (fail closed toward "not done").
  jq -n -c --arg id "$agent_id" --arg s "$SELF" \
    '{agent_id: $id, status: "unsettled", ended_without_result: false, source: $s}'
  exit 0
fi

# terminal_for <agent_id> — prints "0" or "1" (ended_without_result) for the FIRST terminal row
# matching <agent_id>, or nothing when no terminal row exists for it. `head -1` on a jq pipe under
# `pipefail` can raise SIGPIPE(141) in $?, which is harmless here: this script has no `set -e`, and
# every caller inspects the CAPTURED VALUE (`[ -n "$ewr" ]`), never the exit code of the substitution.
terminal_for() {
  jq -R -r --arg id "$1" '
    (fromjson? // empty) as $l
    | select(
        ($l.event == "subtask_complete" and $l.agent_id == $id) or
        ($l.event == "token_ledger" and $l.agent_id == $id) or
        ($l.event == "agent_lifecycle" and $l.state == "failed" and $l.agent_id == $id)
      )
    | ( if ($l.event == "subtask_complete" and ($l.result_block_present? == false))
          or ($l.event == "agent_lifecycle" and $l.state == "failed")
        then "1" else "0" end )
  ' "$log" 2>/dev/null | head -1
}

if [ "$mode" = "agent" ]; then
  ewr="$(terminal_for "$agent_id")"
  if [ -n "$ewr" ]; then
    if [ "$ewr" = "1" ]; then ewr_bool=true; else ewr_bool=false; fi
    jq -n -c --arg id "$agent_id" --argjson ewr "$ewr_bool" --arg s "$SELF" \
      '{agent_id: $id, status: "settled", ended_without_result: $ewr, source: $s}'
  else
    jq -n -c --arg id "$agent_id" --arg s "$SELF" \
      '{agent_id: $id, status: "unsettled", ended_without_result: false, source: $s}'
  fi
  exit 0
fi

# --all: every distinct agent_id that ever appeared on an agent_identity row.
ids="$(jq -R -r '(fromjson? // empty) | select(.event == "agent_identity" and (.agent_id? // "") != "") | .agent_id' "$log" 2>/dev/null | sort -u)"

if [ -z "$ids" ]; then
  jq -n -c --arg s "$SELF" \
    '{status: "no_identity_rows", unsettled_agent_ids: [], ended_without_result_ids: [], source: $s}'
  exit 0
fi

unsettled='[]'
ewr_ids='[]'
while IFS= read -r id; do
  [ -n "$id" ] || continue
  ewr="$(terminal_for "$id")"
  if [ -z "$ewr" ]; then
    unsettled="$(jq -c --arg id "$id" '. + [$id]' <<<"$unsettled")"
  elif [ "$ewr" = "1" ]; then
    ewr_ids="$(jq -c --arg id "$id" '. + [$id]' <<<"$ewr_ids")"
  fi
done <<EOF
$ids
EOF

if [ "$unsettled" = "[]" ]; then status="settled"; else status="unsettled"; fi

jq -n -c --argjson u "$unsettled" --argjson e "$ewr_ids" --arg st "$status" --arg s "$SELF" \
  '{status: $st, unsettled_agent_ids: $u, ended_without_result_ids: $e, source: $s}'
exit 0
