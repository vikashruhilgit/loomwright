#!/usr/bin/env bash
# ci-run-probe.sh — MECHANIZED, fail-safe, READ-ONLY live-infra probe for a
# single RED REQUIRED check-run, wired into the `/review-pr --until-mergeable`
# drain (skills/review-heal/SKILL.md §U2.5/§U4) so it never heals a required
# check that never actually ran. See:
#   .supervisor/requirements/harness-port/07-ci-trust-probe.md
#
# ============================== CONTRACT (PIN) ================================
# WHY: a required check can be red for reasons that have nothing to do with the
# diff — the workflow job never started (account billing/spending block, a few
# seconds after dispatch), it was queued and cancelled before a runner was ever
# assigned, or a reviewer action self-skipped and exited 0. The drain treats
# check conclusions as ground truth today, so a never-ran red check gets healed
# against exactly like a real test failure. This script gives the drain a
# NARROW, evidence-based way to tell the two apart — it NEVER decides anything
# on its own; it only reports evidence for the caller (the drain loop, prose in
# skills/review-heal/SKILL.md) to act on.
#
# USAGE (single-check mode — one gh api call, one output object):
#   ci-run-probe.sh --repo <owner>/<repo> --check <name> --run-id <run_id>
#
# USAGE (batch mode — bounded, no pagination, for a whole round's red required
# checks at once; used by callers that want the --max-probes bound enforced in
# one place rather than counting invocations themselves):
#   ci-run-probe.sh --repo <owner>/<repo> --checks <json | @file> [--max-probes N]
#   <json> is a JSON array of {"name": "<check name>", "run_id": "<run id>"}.
#   `@file` reads the same shape from a file instead of an inline argument.
#   Checks beyond the Nth (default 5) are NEVER probed (no gh api call is made
#   for them) — each still gets one output line, verdict "unknown", reason
#   "max_probes_bound_reached", so the caller can distinguish "we didn't look"
#   from "we looked and could not tell".
#
# OUTPUT: one jq-built JSON object per check, on its own line (single-check
# mode prints exactly one line; batch mode prints one line per input check, in
# input order — this is JSON Lines, never a wrapping array, and NEVER
# paginated):
#   {"check": "<name>", "verdict": "ran"|"untrusted_infra"|"unknown",
#    "reason": "<short slug>", "steps_count": <int|null>,
#    "runner_assigned": <bool|null>, "annotation_match": "<pattern|null>",
#    "run_id": "<run id|null>"}
# `run_id` is additive beyond the AC's six-key shape — it is what lets a
# caller build docs/RESULT_SCHEMAS.md's `checks_untrusted[].run_id` and the
# suggested human re-run command text (see the drain's ESCALATED notification,
# skills/review-heal/SKILL.md §U4) without a second lookup.
#
# ALWAYS EXITS 0. `gh` missing, unauthenticated, rate-limited, or any other
# `gh api` failure classifies "unknown" — NEVER "untrusted_infra". An
# unreadable probe must never claim an infra fault it did not actually see
# evidence for; "unknown" still blocks READY exactly like an ordinary
# unclassified red check does today (skills/review-heal/SKILL.md §U4), it is
# simply not actionable as "re-run when infra is healthy".
#
# EVIDENCE RULES (ANY one ⇒ "untrusted_infra"; checked in this order, first
# match wins and is reported as `reason`):
#   1. zero_steps            — the run's jobs collectively report 0 steps
#                               (the job(s) never even started executing).
#   2. no_runner_assigned    — every job has BOTH `runner_name` and
#                               `started_at` null (queued, never assigned a
#                               runner — e.g. cancelled before dispatch).
#   3. annotation_match:<p>  — a job name / step name / top-level `message`
#                               field matches one of the FIXED generic
#                               GitHub-native strings below (case-insensitive,
#                               no project/account/repo names baked in):
#                               account payments | spending limit | billing |
#                               quota | rate limit exceeded |
#                               workflow validation error | not started
# A run whose jobs report >0 real steps and no pattern match is "ran" — a
# genuine failure, healed exactly as today. This is the narrowing that keeps
# `untrusted_infra` from ever masking a real test failure as an infra fault
# (see the brief's own Risk Assessment item 1).
#
# NO DATE ARITHMETIC ANYWHERE (Non-goal, this repo's own documented BSD-vs-GNU
# `date` flag-divergence trap) — every evidence rule above is evaluated from
# the `gh api .../jobs` response's own fields, never from a timestamp
# comparison, and this script calls neither `date` nor `stat` at all.
#
# No re-run command is EVER constructed or executed by this script — the
# suggestion to re-run a check is human-facing notification TEXT owned by the
# caller (skills/review-heal/SKILL.md §U4's ESCALATED branch), never
# something this probe types or invokes (an unattended re-run under an active
# billing block would burn the same exhausted quota this script exists to
# detect).
#
# TESTABILITY: the `gh` binary is invoked via "${GH:-gh}" — a test exports
# GH=/path/to/stub-gh (or puts a stub earlier on PATH) to script a
# deterministic `gh api .../jobs` response without any network call. See
# test-ci-run-probe.sh.
# ================================================================================

set -u
# Intentionally NO `set -e` / pipefail — every gh/jq read is individually
# guarded so this script can absorb any failure and still emit its one JSON
# line, exit 0 (the always-exits-0 fail-safe contract above).

GH_BIN="${GH:-gh}"
JQ_BIN="${JQ:-jq}"

# Fixed, generic GitHub-native pattern list (AC-pinned; no project/account/
# repo names baked in — see EVIDENCE RULES rule 3 above).
ANNOTATION_PATTERN='account payments|spending limit|billing|quota|rate limit exceeded|workflow validation error|not started'

REPO=""
CHECK=""
RUN_ID=""
CHECKS_ARG=""
MAX_PROBES="5"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        REPO="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --repo=*)      REPO="${1#--repo=}"; shift ;;
    --check)       CHECK="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --check=*)     CHECK="${1#--check=}"; shift ;;
    --run-id)      RUN_ID="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --run-id=*)    RUN_ID="${1#--run-id=}"; shift ;;
    --checks)      CHECKS_ARG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --checks=*)    CHECKS_ARG="${1#--checks=}"; shift ;;
    --max-probes)  MAX_PROBES="${2:-5}"; shift; [ $# -gt 0 ] && shift ;;
    --max-probes=*) MAX_PROBES="${1#--max-probes=}"; shift ;;
    *)             shift ;;
  esac
done

case "$MAX_PROBES" in
  ''|*[!0-9]*) MAX_PROBES="5" ;;   # malformed/non-numeric ⇒ fall back to the documented default, never abort
esac

# emit_line <check> <verdict> <reason> <steps_count|null> <runner_assigned|null> <annotation_match|null> <run_id|null>
# Always uses jq when available (injection-safe, --arg-only). jq missing is a
# rare fallback: values here are either internal fixed slugs or caller-
# supplied strings already stripped of quote/backslash bytes by the caller
# loop below, so direct interpolation stays JSON-safe.
emit_line() {
  local check="$1" verdict="$2" reason="$3" steps="$4" runner="$5" ann="$6" run="$7"
  if command -v "$JQ_BIN" >/dev/null 2>&1; then
    "$JQ_BIN" -cn \
      --arg check "$check" --arg verdict "$verdict" --arg reason "$reason" \
      --argjson steps "${steps:-null}" --argjson runner "${runner:-null}" \
      --arg ann "$ann" --arg run "$run" \
      '{check: $check, verdict: $verdict, reason: $reason, steps_count: $steps,
        runner_assigned: $runner,
        annotation_match: (if $ann == "" then null else $ann end),
        run_id: (if $run == "" then null else $run end)}'
  else
    local safe_check safe_reason safe_ann safe_run
    safe_check="$(printf '%s' "$check" | tr -d '"\\')"
    safe_reason="$(printf '%s' "$reason" | tr -d '"\\')"
    safe_ann="$(printf '%s' "$ann" | tr -d '"\\')"
    safe_run="$(printf '%s' "$run" | tr -d '"\\')"
    printf '{"check":"%s","verdict":"%s","reason":"%s","steps_count":%s,"runner_assigned":%s,"annotation_match":%s,"run_id":%s}\n' \
      "$safe_check" "$verdict" "$safe_reason" "${steps:-null}" "${runner:-null}" \
      "$([ -n "$safe_ann" ] && printf '"%s"' "$safe_ann" || printf 'null')" \
      "$([ -n "$safe_run" ] && printf '"%s"' "$safe_run" || printf 'null')"
  fi
}

# probe_one <check> <run_id> — makes the ONE sanctioned gh api call for this
# check/run and emits ONE JSON line. Never a non-zero exit from this function.
probe_one() {
  local check="$1" run_id="$2"

  if [ -z "$REPO" ] || [ -z "$run_id" ]; then
    emit_line "$check" "unknown" "bad_input" "null" "null" "" "$run_id"
    return 0
  fi

  if ! command -v "$GH_BIN" >/dev/null 2>&1; then
    emit_line "$check" "unknown" "gh_unavailable" "null" "null" "" "$run_id"
    return 0
  fi
  if ! command -v "$JQ_BIN" >/dev/null 2>&1; then
    emit_line "$check" "unknown" "jq_unavailable" "null" "null" "" "$run_id"
    return 0
  fi

  # The ONE sanctioned gh api call per red required check — no pagination.
  local raw rc=0
  raw="$("$GH_BIN" api "repos/$REPO/actions/runs/$run_id/jobs" 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$raw" ] || ! printf '%s' "$raw" | "$JQ_BIN" -e . >/dev/null 2>&1; then
    emit_line "$check" "unknown" "gh_api_unreadable" "null" "null" "" "$run_id"
    return 0
  fi

  # Single jq pass over the validated response: derive steps_count,
  # runner_assigned, and the annotation-pattern match, then apply the
  # evidence rules in fixed order (first match wins) and print the verdict
  # line as ONE more jq-built object — this function's own emit.
  printf '%s' "$raw" | "$JQ_BIN" -c \
    --arg check "$check" --arg run "$run_id" --arg pat "$ANNOTATION_PATTERN" '
    (.jobs // []) as $jobs
    | ([$jobs[]?.steps[]?] | length) as $steps_count
    | ( ([$jobs[]?] | length) > 0
        and ( [$jobs[]? | select(((.runner_name // null) != null) or ((.started_at // null) != null))] | length ) > 0
      ) as $runner_assigned
    | ( [ .message, ($jobs[]?.name), ($jobs[]?.steps[]?.name) ]
        | map(select(type=="string"))
        | join(" • ")
      ) as $text
    | ( $text | test($pat; "i") ) as $pat_hit
    | ( if $pat_hit then
          ( [ ($pat | split("|")[])
              | select(. as $p | $text | test($p; "i"))
            ] | first // "pattern_match" )
        else null end
      ) as $matched_pattern
    | if $steps_count == 0 then
        {verdict: "untrusted_infra", reason: "zero_steps", ann: null}
      elif ($runner_assigned | not) then
        {verdict: "untrusted_infra", reason: "no_runner_assigned", ann: null}
      elif $pat_hit then
        {verdict: "untrusted_infra", reason: ("annotation_match:" + $matched_pattern), ann: $matched_pattern}
      else
        {verdict: "ran", reason: "real_failure", ann: null}
      end
    | {check: $check, verdict: .verdict, reason: .reason, steps_count: $steps_count,
       runner_assigned: $runner_assigned, annotation_match: .ann, run_id: $run}
  ' 2>/dev/null || emit_line "$check" "unknown" "jq_eval_failed" "null" "null" "" "$run_id"
  return 0
}

# ---- dispatch: single-check vs batch mode -----------------------------------
if [ -n "$CHECKS_ARG" ]; then
  # Batch mode — read the JSON array (inline or @file), bounded to the first
  # MAX_PROBES entries; the rest are reported unknown/not-probed, NEVER
  # probed (no gh api call for them — the bound is enforced HERE, not left to
  # the caller's own loop discipline).
  RAW_LIST=""
  case "$CHECKS_ARG" in
    @*)
      _f="${CHECKS_ARG#@}"
      if [ -r "$_f" ]; then RAW_LIST="$(cat "$_f" 2>/dev/null)"; fi
      ;;
    *) RAW_LIST="$CHECKS_ARG" ;;
  esac

  if [ -z "$RAW_LIST" ] || ! command -v "$JQ_BIN" >/dev/null 2>&1 \
     || ! printf '%s' "$RAW_LIST" | "$JQ_BIN" -e 'type=="array"' >/dev/null 2>&1; then
    # Unreadable/malformed input list — fail-safe, no crash, no false claims.
    exit 0
  fi

  COUNT="$(printf '%s' "$RAW_LIST" | "$JQ_BIN" 'length' 2>/dev/null || echo 0)"
  case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

  i=0
  while [ "$i" -lt "$COUNT" ]; do
    name="$(printf '%s' "$RAW_LIST" | "$JQ_BIN" -r --argjson i "$i" '.[$i].name // ""' 2>/dev/null)"
    rid="$(printf '%s' "$RAW_LIST" | "$JQ_BIN" -r --argjson i "$i" '.[$i].run_id // "" | tostring' 2>/dev/null)"
    [ "$rid" = "null" ] && rid=""
    if [ "$i" -lt "$MAX_PROBES" ]; then
      probe_one "$name" "$rid"
    else
      emit_line "$name" "unknown" "max_probes_bound_reached" "null" "null" "" "$rid"
    fi
    i=$((i + 1))
  done
  exit 0
fi

# Single-check mode.
probe_one "$CHECK" "$RUN_ID"
exit 0
