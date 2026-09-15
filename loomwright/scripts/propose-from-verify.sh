#!/usr/bin/env bash
# propose-from-verify.sh - the VERIFY basis of `/propose`: turns the FAIL / issue lines a `/verify`
# run recorded into CANDIDATE requirement files under `.supervisor/requirements/proposed/`, each
# citing the evidence line(s) it rests on, for a human to promote or delete.
#
# WHY THIS EXISTS. A real QA lane found 25 blocking bugs on a live app and one (`BUG-NC-001`)
# stayed unfixed five months later because the finding had no consumer (memory
# `qa-l1-validated-on-sports-management`). `/verify` already records every fact validated to
# `.supervisor/verify/<run_id>/evidence.jsonl` (schema `VERIFY_EVIDENCE`, `docs/RESULT_SCHEMAS.md`),
# but nothing consumed a FAIL. This is the third `/propose` basis (alongside the ledger basis
# `propose-work.sh` and the domain basis `propose-domain.sh`) and the missing consumer.
#
# THE CONTRACT (identical to the other two bases, restated in every emitted proposal too):
#   `.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;
#   promotion is a human moving a file out of it. IT PROPOSES; IT NEVER QUEUES. Nothing here
#   enqueues, dispatches, ranks, scores or merges.
#
# READS EXACTLY ONE SURFACE: `<run_dir>/evidence.jsonl`. Not `summary.md` (a derived, lossier
# view), not `acs.json`, not the ticket file itself. WRITES ONLY under the output directory,
# through the shared `pc_guarded_write()` in `propose-common.sh` (sourced, never copied inline -
# `propose-work.sh` and `propose-domain.sh` source the same file; see propose-common.sh's own
# header for how each caller's mutation control stays live against a guard that no longer lives
# in its own file text).
#
# ONE DRAFT PER QUALIFYING LINE:
#   * a `FAIL` `ac` line whose `classification` is `REAL_BUG` - taking the LATEST line per `ac_id`
#     (the VERIFY_EVIDENCE schema's own "latest-per-ac_id" rule: a re-verified AC that ended PASS
#     must not still be drafted from an earlier, superseded FAIL). `DISCOVERY_GAP` /
#     `ENVIRONMENT_ISSUE` are the RUN's problem, not the app's, and are never drafted - they stay
#     in the summary only.
#   * every `issue` line, unconditionally (an `issue` line carries no `classification` at all).
#   BLOCKED and NOT_VERIFIABLE never produce a draft, at any classification.
#
# IDEMPOTENT ON (run_id, ac_id) / (run_id, issue ordinal). The filename is DERIVED, not counted:
# `verify-<run_id>-<ac_id>-<slug>.md` for an AC, `verify-<run_id>-issue-<n>-<slug>.md` for an issue
# (`<n>` is the issue's 1-based ordinal among issue lines, in file order). Because the filename is
# a pure function of (run_id, ac_id | issue ordinal, text-derived slug) and `evidence.jsonl` is
# append-only, re-running this script against an UNCHANGED store recomputes the identical filename
# with identical content and `pc_guarded_write` simply overwrites it byte-for-byte through the SAME
# guard every write already goes through - "no duplicates, no second write attempt beyond the
# guard" (AC3). A re-verified AC (a later `ac` line for the same `ac_id`, resume-after-pause or a
# retry) changes what gets drafted at all - which is the intended effect of the latest-per-ac_id
# rule, not a duplicate.
#
# BLAST RADIUS. This script never calls `verify-helpers.sh summary-build` and never touches
# anything under `<run_dir>/`. The evidence-driven "## Proposals" section of `summary.md` (added to
# `verify-helpers.sh summary_build` as part of this same change) is computed PURELY from
# `evidence.jsonl` content - which `FAIL`/`issue` lines qualify - so it already states the correct
# "N draft(s) expected" / "no draft is expected" fact on every append, with no dependency on this
# script having run and no need for this script to trigger a rebuild. That keeps this script's own
# write footprint to EXACTLY the output directory, which is what the self-test's find-diff (AC10)
# checks.
#
# FAIL-SAFE. `set -uo pipefail`, no `set -e`, a `jq` guard that skips rather than fails, `exit 0`
# ALWAYS - an advisory producer must never break its caller (`/propose --from-verify`).
#
# Usage:  propose-from-verify.sh <run_dir>
#   env PROPOSE_FROM_VERIFY_OUT_DIR=<path>   where candidates are written
#                                            (default .supervisor/requirements/proposed)
# Exit:   0 always.

set -uo pipefail

SELF="propose-from-verify"
say() { echo "$SELF: $1" >&2; }

command -v jq >/dev/null 2>&1 || {
  say "jq required - skipping, nothing proposed"
  exit 0
}

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  say "usage: propose-from-verify.sh <run_dir> - skipping, nothing proposed"
  exit 0
fi
if [ ! -d "$RUN_DIR" ]; then
  say "no such run dir '$RUN_DIR' - skipping, nothing proposed"
  exit 0
fi
RUN_DIR_ABS="$(cd "$RUN_DIR" 2>/dev/null && pwd)"
[ -n "$RUN_DIR_ABS" ] || { say "cannot resolve '$RUN_DIR' - skipping, nothing proposed"; exit 0; }

EVIDENCE="$RUN_DIR_ABS/evidence.jsonl"
if [ ! -f "$EVIDENCE" ]; then
  say "no evidence.jsonl under $RUN_DIR_ABS - skipping, nothing proposed"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
# PROPOSE_COMMON_SH overrides the sibling path - a test-only knob (see propose-common.sh's own
# header) that lets a mutation control point this script's sourcing at a mutated COPY of
# propose-common.sh without touching this script's own text. Unset in every real run.
COMMON="${PROPOSE_COMMON_SH:-$SCRIPT_DIR/propose-common.sh}"
if [ ! -f "$COMMON" ]; then
  say "sibling propose-common.sh not found at $COMMON - skipping, nothing proposed"
  exit 0
fi
# shellcheck disable=SC1090
. "$COMMON"

OUT_DIR="${PROPOSE_FROM_VERIFY_OUT_DIR:-.supervisor/requirements/proposed}"
mkdir -p "$OUT_DIR" 2>/dev/null || {
  say "cannot create $OUT_DIR - skipping, nothing proposed"
  exit 0
}
OUT_DIR_ABS="$(cd "$OUT_DIR" 2>/dev/null && pwd)"
[ -n "$OUT_DIR_ABS" ] || { say "cannot resolve $OUT_DIR - skipping, nothing proposed"; exit 0; }

RUN_ID="$(basename "$RUN_DIR_ABS")"

# run_start fields - ticket, branch, head_sha. Absent run_start ⇒ empty strings, never fabricated.
RS_JSON="$(jq -c 'select(.event == "run_start")' "$EVIDENCE" 2>/dev/null | head -1)"
TICKET_PATH="$(printf '%s' "$RS_JSON" | jq -r '.ticket_path // ""' 2>/dev/null)"
BRANCH="$(printf '%s' "$RS_JSON" | jq -r '.branch // ""' 2>/dev/null)"
HEAD_SHA="$(printf '%s' "$RS_JSON" | jq -r '.head_sha // ""' 2>/dev/null)"

# One compact JSON record per qualifying line, each carrying its own 1-based PHYSICAL line number
# in evidence.jsonl (jq's `to_entries` index + 1 - the file is one JSON object per line, guaranteed
# by evidence-append's canonicalisation, so this is the same number a human would count with `nl`).
#
# Latest-per-ac_id (the VERIFY_EVIDENCE schema's own rule): group ac lines by ac_id, keep the one
# with the greatest physical index, THEN filter to FAIL/REAL_BUG. issue lines carry no dedup rule -
# every one is drafted, numbered by its 1-based ordinal among issue lines in file order.
RECORDS="$(jq -cs '
    def latest_by(f): group_by(f) | map(max_by(._i)) | sort_by(._i);
    (to_entries | map(.value + {_i: .key})) as $L
    | ([$L[] | select(.event == "ac")] | latest_by(.ac_id)) as $acs
    | ([$L[] | select(.event == "issue")] | sort_by(._i) | to_entries | map(.value + {_n: (.key + 1)})) as $issues
    | ([ $acs[] | select(.verdict == "FAIL" and .classification == "REAL_BUG")
         | {kind: "ac", ac_id: .ac_id, line: (._i + 1), text: .text, reason: (.reason // ""),
            artifacts: (.artifacts // [])} ]
       + [ $issues[] | {kind: "issue", n: ._n, line: (._i + 1), text: .text,
            severity: (.severity // ""), route: (.route // ""), artifacts: (.artifacts // [])} ])
    | .[]
  ' "$EVIDENCE" 2>/dev/null)"

if [ -z "$RECORDS" ]; then
  say "no REAL_BUG FAIL and no issue line in $EVIDENCE - nothing to propose (BLOCKED / NOT_VERIFIABLE / DISCOVERY_GAP / ENVIRONMENT_ISSUE are the run's problem, not the app's)"
  exit 0
fi

emitted=0
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  kind="$(printf '%s' "$rec" | jq -r '.kind')"
  line_no="$(printf '%s' "$rec" | jq -r '.line')"
  text="$(printf '%s' "$rec" | jq -r '.text')"
  arts="$(printf '%s' "$rec" | jq -r '.artifacts[]?' 2>/dev/null)"
  slug="$(pc_slugify "$text")"

  if [ "$kind" = "ac" ]; then
    ac_id="$(printf '%s' "$rec" | jq -r '.ac_id')"
    reason="$(printf '%s' "$rec" | jq -r '.reason')"
    fname="verify-${RUN_ID}-${ac_id}-${slug}.md"
    {
      printf '# Proposed: verify FAIL %s (%s)\n\n' "$ac_id" "$RUN_ID"
      printf 'evidence-set: %s/%s@L%s\n\n' "$RUN_ID" "$ac_id" "$line_no"
      printf '## Problem\n\n'
      printf '%s\n\n' "$text"
      printf 'Observed verdict: FAIL (classification: REAL_BUG)\n'
      [ -n "$reason" ] && printf 'Reason: %s\n' "$reason"
      printf '\n## Evidence\n\n'
      printf -- '- evidence.jsonl line %s (event: ac, ac_id: %s)\n' "$line_no" "$ac_id"
      if [ -n "$arts" ]; then
        printf '%s\n' "$arts" | while IFS= read -r a; do [ -n "$a" ] && printf -- '- artifact: %s\n' "$a"; done
      fi
      [ -n "$TICKET_PATH" ] && printf -- '- ticket: %s\n' "$TICKET_PATH"
      [ -n "$BRANCH" ] && printf -- '- branch: %s @ head_sha %s\n' "$BRANCH" "${HEAD_SHA:-unknown}"
      printf -- '- classification: REAL_BUG\n'
      printf '\n## Suggested acceptance\n\n'
      printf -- '- [ ] %s\n' "$text"
      printf '\n## Status: proposed\n'
    } | pc_guarded_write "$OUT_DIR_ABS" "$SELF" "$fname" \
      && { emitted=$((emitted + 1)); say "proposed $ac_id -> $OUT_DIR/$fname"; }
  else
    n="$(printf '%s' "$rec" | jq -r '.n')"
    severity="$(printf '%s' "$rec" | jq -r '.severity')"
    route="$(printf '%s' "$rec" | jq -r '.route')"
    fname="verify-${RUN_ID}-issue-${n}-${slug}.md"
    {
      printf '# Proposed: verify issue #%s (%s)\n\n' "$n" "$RUN_ID"
      printf 'evidence-set: %s/issue-%s@L%s\n\n' "$RUN_ID" "$n" "$line_no"
      printf '## Problem\n\n'
      printf '%s\n\n' "$text"
      [ -n "$severity" ] && printf 'Severity: %s\n' "$severity"
      [ -n "$route" ] && printf 'Route: %s\n' "$route"
      printf '\n## Evidence\n\n'
      printf -- '- evidence.jsonl line %s (event: issue)\n' "$line_no"
      if [ -n "$arts" ]; then
        printf '%s\n' "$arts" | while IFS= read -r a; do [ -n "$a" ] && printf -- '- artifact: %s\n' "$a"; done
      fi
      [ -n "$TICKET_PATH" ] && printf -- '- ticket: %s\n' "$TICKET_PATH"
      [ -n "$BRANCH" ] && printf -- '- branch: %s @ head_sha %s\n' "$BRANCH" "${HEAD_SHA:-unknown}"
      printf -- '- classification: n/a (issue lines carry no classification)\n'
      printf '\n## Suggested acceptance\n\n'
      printf -- '- [ ] Address: %s\n' "$text"
      printf '\n## Status: proposed\n'
    } | pc_guarded_write "$OUT_DIR_ABS" "$SELF" "$fname" \
      && { emitted=$((emitted + 1)); say "proposed issue #$n -> $OUT_DIR/$fname"; }
  fi
done <<EOF
$RECORDS
EOF

say "$emitted candidate(s) written to $OUT_DIR - nothing was queued, and nothing will be until a human moves a file out of it"
exit 0
