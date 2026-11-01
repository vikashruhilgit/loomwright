#!/usr/bin/env bash
# propose-scorecard.sh - the SCORECARD basis of `/propose` (`/propose --from-scorecard`): turns every
# feature the feature scorecard flags with a `review:` verdict into ONE candidate requirement file
# under `.supervisor/requirements/proposed/`, carrying the scorecard's numbers, the record paths they
# were read from, and two options - ENHANCE (what the numbers suggest) and RETIRE (the surfaces that
# name the feature) - for a human to promote or delete.
#
# THE CONTRACT (identical to every other basis, restated in every emitted proposal too):
#   `.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;
#   promotion is a human moving a file out of it. IT PROPOSES; IT NEVER QUEUES. Nothing here
#   enqueues, dispatches, ranks or merges, and nothing here edits, disables or retires a feature -
#   the scorecard's verdict is a suggestion and so is every draft built from it.
#
# READS EXACTLY ONE SURFACE: the `--json` object of the sibling `build-feature-scorecard.sh` (its
# `--state-dir` / `--registry` / `--since` flags are passed through unchanged, which is how the
# self-test points it at a fixture). The verdict vocabulary lives in that builder alone; this
# script only prefix-matches `review:` and never restates the set. A `critical: true` feature never
# reaches a `review:` verdict there (it is held at the builder's critical keep), and is also skipped
# here, so no retire draft is ever written for one.
#
# WRITES ONLY under the output directory, through the shared guarded write in `propose-common.sh`
# (sourced, never copied inline - the same file every basis sources; see its header for how a
# caller's mutation control stays live against a guard that lives outside the caller's text). The
# output directory is created only once at least one draft is due, so an error / empty / all-clear
# scorecard leaves the tree exactly as it was.
#
# ONE DRAFT PER FLAGGED FEATURE, named `scorecard--<slug of the feature id>.md`. The name is a pure
# function of the id, so a re-run against unchanged records rewrites the identical bytes (no run
# timestamps anywhere), never a duplicate. Two ids that slugify alike: the first wins and the second
# is named and skipped, never silently overwritten.
#
# RETIRE SURFACES are `git grep -lF -e <feature id>` over the checkout the run starts in (tracked
# files only, sorted, capped), so `.supervisor/` and any other ignored path are never listed.
#
# FAIL-SAFE. `set -uo pipefail`, no `set -e`, a `jq` guard that skips rather than fails, `exit 0`
# ALWAYS - an advisory producer must never break its caller.
#
# Usage:  propose-scorecard.sh [--state-dir <dir>] [--registry <file>] [--since <date|sha>]
#   env PROPOSE_SCORECARD_OUT_DIR=<path>   where candidates are written
#                                          (default .supervisor/requirements/proposed)
# Exit:   0 always.

set -uo pipefail

SELF="propose-scorecard"
say() { echo "$SELF: $1" >&2; }

command -v jq >/dev/null 2>&1 || {
  say "jq required - skipping, nothing proposed"
  exit 0
}

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
BUILDER="$SCRIPT_DIR/build-feature-scorecard.sh"
# PROPOSE_COMMON_SH overrides the sibling path - the test-only knob every basis honours (see
# propose-common.sh's header). Unset in every real run.
COMMON="${PROPOSE_COMMON_SH:-$SCRIPT_DIR/propose-common.sh}"
if [ ! -f "$BUILDER" ]; then
  say "sibling build-feature-scorecard.sh not found at $BUILDER - skipping, nothing proposed"
  exit 0
fi
if [ ! -f "$COMMON" ]; then
  say "sibling propose-common.sh not found at $COMMON - skipping, nothing proposed"
  exit 0
fi
# shellcheck disable=SC1090
. "$COMMON"

# Pass-through flags: only the three the builder defines, each with a value that is not itself a
# flag. Anything else is named and ignored (fail-safe), never forwarded.
PASS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir|--registry|--since)
      case "${2:-}" in
        ''|--*) say "$1 given without a value - ignored" ;;
        *) PASS[${#PASS[@]}]="$1"; PASS[${#PASS[@]}]="$2"; shift ;;
      esac
      ;;
    *) say "unknown argument '$1' ignored" ;;
  esac
  shift
done

SC_JSON="$(bash "$BUILDER" --json ${PASS[@]+"${PASS[@]}"})"
SC_STATUS="$(printf '%s' "$SC_JSON" | jq -r 'if type == "object" then (.status // "" | tostring) else "" end' 2>/dev/null)"
case "$SC_STATUS" in
  ok) : ;;
  error)
    SC_ERR="$(printf '%s' "$SC_JSON" | jq -r '.error // "unspecified" | tostring' 2>/dev/null)"
    say "the scorecard reported an error (${SC_ERR:-unspecified}) - nothing proposed"
    exit 0 ;;
  *)
    say "the scorecard's --json output is unreadable - nothing proposed"
    exit 0 ;;
esac

N_FEATURES="$(printf '%s' "$SC_JSON" | jq -r '(.features // []) | length' 2>/dev/null)"
case "$N_FEATURES" in ''|*[!0-9]*) N_FEATURES=0 ;; esac
if [ "$N_FEATURES" -eq 0 ]; then
  say "the scorecard lists no features - nothing proposed"
  exit 0
fi

SINCE="$(printf '%s' "$SC_JSON" | jq -r '.since // "" | tostring' 2>/dev/null)"
CANDS="$(printf '%s' "$SC_JSON" | jq -c '
  .features[]
  | select(type == "object" and (.id | type) == "string" and (.verdict | type) == "string")
  | select((.verdict | startswith("review:")) and .critical != true)' 2>/dev/null)"

if [ -z "$CANDS" ]; then
  say "no non-critical feature carries a review: verdict ($N_FEATURES feature(s) read) - nothing proposed"
  exit 0
fi

OUT_DIR="${PROPOSE_SCORECARD_OUT_DIR:-.supervisor/requirements/proposed}"
mkdir -p "$OUT_DIR" 2>/dev/null || {
  say "cannot create $OUT_DIR - skipping, nothing proposed"
  exit 0
}
OUT_DIR_ABS="$(cd "$OUT_DIR" 2>/dev/null && pwd)"
[ -n "$OUT_DIR_ABS" ] || { say "cannot resolve $OUT_DIR - skipping, nothing proposed"; exit 0; }

SURF_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
SURF_CAP=40
# surfaces_of <feature id> - tracked files that name the id, sorted (C collation), one per line.
surfaces_of() {
  [ -n "$SURF_ROOT" ] || return 0
  git -C "$SURF_ROOT" grep -lF -e "$1" 2>/dev/null | env LC_ALL=C sort
}

# num <json> <key> - a scalar field as text; null/absent prints `none` (never a fabricated 0).
num() { printf '%s' "$1" | jq -r --arg k "$2" '.[$k] | if . == null then "none" else tostring end' 2>/dev/null; }

emitted=0
USED=""
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  id="$(printf '%s' "$rec" | jq -r '.id')"
  verdict="$(num "$rec" verdict)"
  runs="$(num "$rec" runs_available)"
  ran="$(num "$rec" ran)"
  caught="$(num "$rec" caught)"
  rate="$(num "$rec" catch_rate)"
  cost="$(num "$rec" cost_total)"
  per="$(num "$rec" cost_per_catch)"
  last="$(num "$rec" last_fired)"
  paths="$(printf '%s' "$rec" | jq -r '(.record_paths // [])[] | tostring' 2>/dev/null)"
  slug="$(pc_slugify "$id")"
  fname="scorecard--${slug}.md"

  prior="$(printf '%s\n' "$USED" | awk -F'\t' -v n="$fname" '$1 == n { print $2; exit }')"
  if [ -n "$prior" ]; then
    say "skipping $id - its draft name $fname is already taken by $prior in this run"
    continue
  fi
  USED="$(printf '%s\n%s\t%s' "$USED" "$fname" "$id")"

  if [ "$ran" = "0" ]; then
    enhance="It had $runs run opportunit(ies) in the window and ran in none of them. Find why it never fires - an opt-in flag nobody sets, a routing condition that never holds, or a record that never notes a run - and fix the trigger or the record."
  elif [ "$caught" = "0" ]; then
    enhance="It ran $ran of $runs time(s) and caught nothing (cost total: $cost). Narrow it to the runs where a catch is plausible, cut its cost, or - if it does catch but the record never says so - make the record attribute its catches."
  else
    enhance="The scorecard flags it ($verdict). Address what that verdict names, using the numbers above."
  fi
  surf="$(surfaces_of "$id")"
  n_surf="$(printf '%s' "$surf" | awk 'END { print NR + 0 }')"

  {
    printf '# Proposed: enhance or retire `%s` (feature scorecard)\n\n' "$id"
    printf 'scorecard-feature: %s - %s\n\n' "$id" "$verdict"
    printf '## Depends on\n\nnone\n\n## Touches\n\nunknown\n\n'
    printf '## Problem\n\n'
    printf 'The feature scorecard (`scripts/build-feature-scorecard.sh --json`) suggests `%s` for `%s`. ' "$verdict" "$id"
    printf 'The verdict is a suggestion: pick one option below, or delete this draft. Nothing has been changed.\n\n'
    printf '## Evidence\n\n'
    printf -- '- verdict: %s\n' "$verdict"
    printf -- '- window: since %s\n' "${SINCE:-the oldest retained record}"
    printf -- '- runs available: %s\n- ran: %s\n- caught: %s\n- catch rate: %s\n' "$runs" "$ran" "$caught" "$rate"
    printf -- '- cost total: %s\n- cost per catch: %s\n- last fired: %s\n' "$cost" "$per" "$last"
    if [ -n "$paths" ]; then
      printf '%s\n' "$paths" | while IFS= read -r p; do [ -n "$p" ] && printf -- '- record: %s\n' "$p"; done
    else
      printf -- '- record: none listed\n'
    fi
    printf '\n## Options\n\n### Enhance\n\n%s\n\n' "$enhance"
    printf '### Retire\n\n'
    printf 'Remove or disable `%s` and drop its entry from `docs/feature-scorecard.json`. ' "$id"
    if [ "$n_surf" -gt 0 ]; then
      printf 'Tracked files naming it (`git grep -lF %s`):\n\n' "$id"
      printf '%s\n' "$surf" | head -n "$SURF_CAP" | while IFS= read -r s; do [ -n "$s" ] && printf -- '- %s\n' "$s"; done
      [ "$n_surf" -gt "$SURF_CAP" ] && printf -- '- (%s more not listed)\n' "$((n_surf - SURF_CAP))"
    else
      printf 'No tracked file in this checkout names it (`git grep -lF %s` found nothing).\n' "$id"
    fi
    printf '\n## Suggested acceptance\n\n'
    printf -- '- [ ] One option is chosen and the choice cites the numbers above\n'
    printf -- '- [ ] `docs/feature-scorecard.json` reflects the choice in the same change (entry updated, or removed on retire)\n'
    printf '\n## Status: proposed\n'
  } | pc_guarded_write "$OUT_DIR_ABS" "$SELF" "$fname" \
    && { emitted=$((emitted + 1)); say "proposed $id -> $OUT_DIR/$fname"; }
done <<EOF
$CANDS
EOF

say "$emitted candidate(s) written to $OUT_DIR - nothing was queued, and nothing will be until a human moves a file out of it"
exit 0
