#!/usr/bin/env bash
# check-children-settled.sh — the ONE join between agent_identity/spawn rows and the terminal
# lifecycle events (subtask_complete | token_ledger | agent_lifecycle:failed | agent_lifecycle:ended)
# that "settle" an
# agent_id in a session's JSONL log (.supervisor/logs/{session_id}.jsonl).
#
# WHY THIS EXISTS (.supervisor/requirements/orca-derived/02-completion-authority.md): completion of a
# subtask is decided by TWO independent facts — the `provides` artefacts on disk (verify-provides.sh,
# unchanged by this script) AND a terminal lifecycle row for the producing worker's `agent_id` — never
# by the worker's own self-report alone. `provides` present on disk from a partial/interrupted run, a
# stale artifact, or a still-running worker that happens to write its files early would otherwise be
# marked complete regardless. This script is the SECOND, independent condition.
#
# WHY A SCRIPT, NOT RESTATED jq (the verify-provides.sh precedent): the 4-way OR across event shapes
# (`subtask_complete.agent_id` | `token_ledger.agent_id` | `agent_lifecycle{state:failed}.agent_id`
# | `agent_lifecycle{state:ended}.agent_id`)
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
#   check-children-settled.sh --log <path> --all --expect-id <id> [--expect-id <id> ...]
#                                                            # aggregate + ids the caller KNOWS it spawned
#
# Output (ONE JSON object on stdout, always exit 0):
#   single-agent: {"agent_id":"<id>","status":"settled"|"unsettled","ended_without_result":true|false,"rejected_stops":N,"source":"check-children-settled.sh"}
#   --all:        {"status":"settled"|"unsettled"|"no_identity_rows","unsettled_agent_ids":[...],"ended_without_result_ids":[...],"rejected_stop_ids":[...],"source":"check-children-settled.sh"}
#   `--expect-id <id>` (repeatable, `--all` only; agnostic-phase1/02): every expected id is checked by
#   the SAME `terminal_for` join as the `agent_identity` ids — the checked set is their union, deduped —
#   whether or not any identity row landed. An expected id with no terminal row (an identity row alone,
#   no row at all, an empty log, or NO LOG) is `unsettled` and named in `unsettled_agent_ids`. WHY: an
#   identity row is written by a PostToolUse[Task] hook; when that hook never fired (log dir
#   unresolvable, non-Claude host) a run that DID spawn workers read `no_identity_rows` — the same answer
#   as a run that spawned nothing — while the per-subtask `--agent-id` gates failed closed on the same
#   absence. With at least one `--expect-id`, `no_identity_rows` is unreachable. Without the flag the
#   `--all` output is byte-identical to before. Callers: FINALIZE Point 5 and
#   guard-finalize-publish.sh write-marker, both passing the ids recorded under state.md's
#   `## Worker Results` (headings / `agent_id:` keys; write-marker refuses a non-empty section with
#   none as `worker_results_unparsed` before calling this script). `--expect-id` with `--agent-id`, a missing value, an empty value or a
#   value carrying a newline ⇒ `bad_args`.
#   `rejected_stops` / `rejected_stop_ids` (additive, v15.83.0) are DIAGNOSTIC ONLY — the count of
#   `subtask_complete` rows carrying `rejected: true` for that agent_id / the identity-row ids with at
#   least one such row — so an `unsettled` verdict caused by a validator-rejected stop is readable
#   from the join output instead of only from the subagent transcript. Consumers decide on `status`
#   alone; these never change the verdict.
#   A missing/unreadable `--log` in `--all` mode with NO `--expect-id` is the documented
#   `no_identity_rows` case (a session that never wrote a log trivially has zero `agent_identity`
#   rows) — never `unverifiable`, never a false `settled`; WITH `--expect-id` it is `unsettled` naming
#   every expected id. The SAME condition in single-agent mode is `unsettled` (no evidence of settlement
#   is not evidence of absence of the agent — fail closed toward "not done yet", never toward "done").
#   Malformed invocation (missing `--log`, or neither `--agent-id` nor `--all`) or a missing `jq` ⇒
#   `{"status":"unverifiable","reason":"bad_args"|"jq_missing","source":"check-children-settled.sh"}` —
#   routed by the consumer the same way verify-provides.sh's `unverifiable` is (never a silent pass).
#
# A "terminal row" for an agent_id is exactly one of:
#   - {"event":"subtask_complete", "agent_id":"<id>", ...}   (worker role terminal event) — EXCEPT a
#     row carrying `rejected: true` (v15.83.0): that firing's WORKER_RESULT was rejected by the
#     sibling `validate-worker-result.py` (`decision: block`), so the runtime made the worker
#     CONTINUE — it is still running and will stop again. Such a row is skipped entirely (it neither
#     settles the agent nor decides `ended_without_result`); an absent or `false` `rejected` key is
#     terminal, exactly as every pre-v15.83.0 row was (see emit-progress-event.sh's header).
#   - {"event":"token_ledger", "agent_id":"<id>", ...}       (non-worker roles' terminal event; this
#     event carries no `result_block_present` field yet — see docs/RESULT_SCHEMAS.md §agent_lifecycle
#     "forward-reference" note — so presence alone settles it)
#   - {"event":"agent_lifecycle", "state":"failed", "agent_id":"<id>", ...}
#   - {"event":"agent_lifecycle", "state":"ended", "agent_id":"<id>", ...} (automate-followups/33,
#     emit-lifecycle.sh `ended`: written for EVERY child stop — the SubagentStop catch-all leaf and the
#     blocking PostToolUse[Task] return — so a non-plugin spawn and a turn-limit-stopped blocking child
#     settle). Lower tier: it decides `ended_without_result` only when none of the three rows above
#     exists for the id. EXCEPTION (A5): a SubagentStop-seam `ended` row (`seam` "subagent_stop" or
#     absent) does not settle an id whose LATEST `subtask_complete` is `rejected: true` — it came from
#     the same validator-blocked firing and the worker is still running. A `task_return` row does.
#     A hung or still-running child has NO stop row and stays `unsettled` — silence is never settled;
#     a BACKGROUND child stopped at its turn limit fires neither seam (fixtures/subagentstop-maxturns-
#     probe.json) and so also stays `unsettled` (honest limit).
#
# `ended_without_result` (docs/RESULT_SCHEMAS.md §agent_lifecycle "Reader-derived states") is `true`
# when the deciding terminal row for that agent_id is a `subtask_complete` with
# `result_block_present: false`, an `agent_lifecycle:failed` row, or — only when neither those nor a
# `token_ledger` row exists — an `agent_lifecycle:ended` row whose `reason` marks a turn limit
# (`max_turns` / `maxTurns` / `turn_limit`, case-insensitive) OR whose agent is a worker (any row for
# the id carries an `agent_type` ending in `worker`: a worker that left no `subtask_complete` ended
# without a result by definition). A plain `ended` for a non-worker reads `false`. Note: on Claude Code
# 2.1.286 neither seam carries a turn-limit marker, so in practice the worker rule is what fires — surfaced so an operator can
# SendMessage the `agent_id` to resume (memory `subagents-hit-turn-limit-resume-via-sendmessage`)
# instead of re-running the subtask cold. This script does not implement the resume — it only
# surfaces the id (via `ended_without_result` / `ended_without_result_ids`).
#
# HONEST LIMITS: a malformed JSONL line is skipped (`fromjson? // empty`), never aborts the scan. Only
# the FIRST matching NON-REJECTED terminal row (file order) decides `ended_without_result` for a given
# agent_id — a worker settles once. A worker whose every stop was rejected (the runtime forces the stop
# at its consecutive-continuation cap — 8 on Claude Code v2.1.278) leaves ONLY rejected rows and stays
# `unsettled`: fail CLOSED toward "not done" (its result IS malformed), surfaced via `rejected_stops`,
# and bounded by each consumer's own existing re-poll / bounded-retry-then-pause / `--skip-children-
# check` path — this script cannot tell "rejected, retrying" from "rejected at the cap" and does not
# guess. `--agent-id` performs no allowlist validation beyond what `jq --arg` already
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
expect_ids=""   # newline-separated --expect-id values (order of arrival; deduped at use)
NL='
'

# add_expect <value> — record one --expect-id value, or set bad_args for an empty / multi-line one.
add_expect() {
  case "$1" in
    '') bad_args="--expect-id needs a non-empty value" ;;
    *"$NL"*) bad_args="--expect-id value must not contain a newline" ;;
    *) expect_ids="$expect_ids$1$NL" ;;
  esac
}

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
    --expect-id)
      if [ $# -lt 2 ]; then bad_args="--expect-id needs a value argument"; break; fi
      add_expect "$2"; shift 2 ;;
    --expect-id=*) add_expect "${1#--expect-id=}"; shift ;;
    -h|--help)
      printf 'usage: %s --log <path> (--agent-id <id> | --all [--expect-id <id>]...)\n' "$SELF" >&2
      exit 0 ;;
    *)
      printf '%s: unexpected argument %s (ignored)\n' "$SELF" "$1" >&2
      shift ;;
  esac
done

[ -z "$bad_args" ] && [ -z "$mode" ] && bad_args="one of --agent-id <id> or --all is required"
[ -z "$bad_args" ] && [ "$mode" = "agent" ] && [ -z "$agent_id" ] && bad_args="--agent-id needs a non-empty value"
[ -z "$bad_args" ] && [ -z "$log" ] && bad_args="--log is required"
[ -z "$bad_args" ] && [ "$mode" = "agent" ] && [ -n "$expect_ids" ] && bad_args="--expect-id is only valid with --all"

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
  if [ "$mode" = "all" ] && [ -z "$expect_ids" ]; then
    # No log at all ⇒ trivially zero agent_identity rows — this IS the documented no_identity_rows
    # case (a session that never wrote a log has nothing to check), never `unverifiable`, never a
    # false `settled`. With --expect-id there IS something to check: fall through to the join below,
    # whose every jq read of the absent log yields nothing, so each expected id reads `unsettled`.
    jq -n -c --arg s "$SELF" \
      '{status: "no_identity_rows", unsettled_agent_ids: [], ended_without_result_ids: [], rejected_stop_ids: [], source: $s}'
    exit 0
  fi
  if [ "$mode" = "agent" ]; then
    # Single-agent mode: no log ⇒ no evidence of settlement ⇒ unsettled (fail closed toward "not done").
    jq -n -c --arg id "$agent_id" --arg s "$SELF" \
      '{agent_id: $id, status: "unsettled", ended_without_result: false, source: $s}'
    exit 0
  fi
fi

# terminal_for <agent_id> — prints "0" or "1" (ended_without_result) for the deciding terminal row of
# <agent_id>, or nothing when no terminal row exists for it. Two tiers (automate-followups/33):
#   tier P — the three result-bearing rows (subtask_complete non-rejected | token_ledger |
#            agent_lifecycle:failed); the FIRST one in file order decides, exactly as before.
#   tier E — agent_lifecycle:ended rows; consulted ONLY when tier P is empty, so a worker's
#            `subtask_complete` always decides its `ended_without_result` even when the `ended` row
#            (a sibling hook leaf, order not guaranteed) landed first.
# A `subtask_complete` with `rejected == true` is NOT terminal (header: "REJECTED STOPS ARE NOT
# TERMINAL"), and — A5 — an `ended` row from the SubagentStop seam (`seam` "subagent_stop" or absent)
# does NOT settle an id whose LATEST `subtask_complete` is rejected: that ended row came from the same
# validator-blocked firing, and the worker is still running. A `task_return` ended row DOES settle it:
# the blocking Task has returned, so the child is finished whatever its last stop looked like.
# `head -1` on a jq pipe under `pipefail` can raise SIGPIPE(141) in $?, which is harmless here: this
# script has no `set -e`, and every caller inspects the CAPTURED VALUE (`[ -n "$ewr" ]`), never the
# exit code of the substitution.
terminal_for() {
  local latest_rej is_worker rows
  latest_rej="$(jq -R -r --arg id "$1" '
    (fromjson? // empty) as $l
    | select($l.event == "subtask_complete" and $l.agent_id == $id)
    | if $l.rejected? == true then "1" else "0" end
  ' "$log" 2>/dev/null | tail -1)"
  [ "$latest_rej" = "1" ] || latest_rej=0
  is_worker="$(jq -R -r --arg id "$1" '
    (fromjson? // empty) as $l
    | select($l.agent_id == $id and (($l.agent_type? // "") | type) == "string"
             and (($l.agent_type? // "") | test("(^|:)worker$")))
    | "1"
  ' "$log" 2>/dev/null | head -1)"
  [ "$is_worker" = "1" ] || is_worker=0
  rows="$(jq -R -r --arg id "$1" --argjson rej "$latest_rej" --argjson wk "$is_worker" '
    (fromjson? // empty) as $l
    | select($l.agent_id == $id)
    | if ($l.event == "subtask_complete" and ($l.rejected? == true | not))
         or ($l.event == "token_ledger")
         or ($l.event == "agent_lifecycle" and $l.state == "failed") then
        "P" + ( if ($l.event == "subtask_complete" and ($l.result_block_present? == false))
                     or ($l.event == "agent_lifecycle" and $l.state == "failed")
                then "1" else "0" end )
      elif ($l.event == "agent_lifecycle" and $l.state == "ended")
           and (($rej == 1 and (($l.seam? // "subagent_stop") == "subagent_stop")) | not) then
        "E" + ( if $wk == 1
                     or ((($l.reason? // "") | tostring | ascii_downcase) | test("max_?turns|turn_?limit"))
                then "1" else "0" end )
      else empty end
  ' "$log" 2>/dev/null)"
  local first
  first="$(printf '%s\n' "$rows" | grep '^P' | head -1)"
  [ -n "$first" ] || first="$(printf '%s\n' "$rows" | grep '^E' | head -1)"
  [ -n "$first" ] && printf '%s' "${first#?}"
  return 0
}

# rejected_stops_for <agent_id> — prints the count of `subtask_complete` rows with `rejected: true`
# for <agent_id> (diagnostic only — see the header). Always prints a number; a log with no such row
# prints 0.
rejected_stops_for() {
  local n
  n="$(jq -R -r --arg id "$1" '
    (fromjson? // empty) as $l
    | select($l.event == "subtask_complete" and $l.agent_id == $id and $l.rejected? == true)
    | 1
  ' "$log" 2>/dev/null | wc -l | tr -d '[:space:]')"
  case "$n" in
    ''|*[!0-9]*) n=0 ;;
  esac
  printf '%s' "$n"
}

if [ "$mode" = "agent" ]; then
  ewr="$(terminal_for "$agent_id")"
  rej="$(rejected_stops_for "$agent_id")"
  if [ -n "$ewr" ]; then
    if [ "$ewr" = "1" ]; then ewr_bool=true; else ewr_bool=false; fi
    jq -n -c --arg id "$agent_id" --argjson ewr "$ewr_bool" --argjson rej "$rej" --arg s "$SELF" \
      '{agent_id: $id, status: "settled", ended_without_result: $ewr, rejected_stops: $rej, source: $s}'
  else
    jq -n -c --arg id "$agent_id" --argjson rej "$rej" --arg s "$SELF" \
      '{agent_id: $id, status: "unsettled", ended_without_result: false, rejected_stops: $rej, source: $s}'
  fi
  exit 0
fi

# --all: every distinct agent_id that ever appeared on an agent_identity row, UNION every --expect-id
# (deduped). An expected id goes through the SAME terminal_for join below — never a second copy.
ids="$( { jq -R -r '(fromjson? // empty) | select(.event == "agent_identity" and (.agent_id? // "") != "") | .agent_id' "$log" 2>/dev/null; printf '%s' "$expect_ids"; } | sort -u)"

if [ -z "$ids" ]; then
  jq -n -c --arg s "$SELF" \
    '{status: "no_identity_rows", unsettled_agent_ids: [], ended_without_result_ids: [], rejected_stop_ids: [], source: $s}'
  exit 0
fi

unsettled='[]'
ewr_ids='[]'
rej_ids='[]'
while IFS= read -r id; do
  [ -n "$id" ] || continue
  ewr="$(terminal_for "$id")"
  if [ -z "$ewr" ]; then
    unsettled="$(jq -c --arg id "$id" '. + [$id]' <<<"$unsettled")"
  elif [ "$ewr" = "1" ]; then
    ewr_ids="$(jq -c --arg id "$id" '. + [$id]' <<<"$ewr_ids")"
  fi
  if [ "$(rejected_stops_for "$id")" != "0" ]; then
    rej_ids="$(jq -c --arg id "$id" '. + [$id]' <<<"$rej_ids")"
  fi
done <<EOF
$ids
EOF

if [ "$unsettled" = "[]" ]; then status="settled"; else status="unsettled"; fi

jq -n -c --argjson u "$unsettled" --argjson e "$ewr_ids" --argjson r "$rej_ids" --arg st "$status" --arg s "$SELF" \
  '{status: $st, unsettled_agent_ids: $u, ended_without_result_ids: $e, rejected_stop_ids: $r, source: $s}'
exit 0
