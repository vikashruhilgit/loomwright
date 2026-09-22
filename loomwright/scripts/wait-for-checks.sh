#!/usr/bin/env bash
# wait-for-checks.sh — foreground, BLOCKING, bounded wait for a PR's scoped CI
# checks to settle for a SPECIFIC sha. Mechanizes skills/review-heal/SKILL.md
# §U2 (required-check discovery, fail-closed) + §U2.5 (scoped wait, bounded) —
# read those sections before changing this script; do not re-derive the loop
# logic, this script exists so the prose can point at it instead of restating
# it as `sleep(poll_interval)` pseudocode.
#
# WHY THIS EXISTS (red-team-hardening item 04)
# ---------------------------------------------------------------------------
# Before this script, the wait was pseudocode the MODEL executed directly.
# Under `claude -p` (a headless, non-interactive session) the model's habit
# was to start a background poll and end its turn — but under `-p`, turn-end
# IS process exit. The drain process died mid-wait, and the dispatcher's
# cleanup trap salvaged + removed the worktree/lock as if the run had
# completed normally, leaving no record that no result was ever produced.
# A single foreground, blocking script call the model cannot background (and
# cannot "wait for a notification" on, because there is no other turn left to
# receive one) closes that hole. See the call sites in
# skills/review-heal/SKILL.md and agents/review-pr.md, each marked with:
#   "Never run this wait in the background and never end the turn while
#    waiting — under `claude -p` ending the turn ends the process and the
#    drain dies with no result."
#
# USAGE
#   wait-for-checks.sh <pr_url> --sha <sha> --bound <seconds> \
#       [--interval <s>] [--required-only | --review-check-pattern <glob>]
#
#   <pr_url>       the PR being waited on (any bare positional argument).
#   --sha <sha>    the commit the caller is waiting for. A rollup reported
#                  for a DIFFERENT sha is NEVER treated as settled — this was
#                  implicit in the prior pseudocode (see §"Termination-only
#                  severity floor"'s `headRefOid` guard) and is now explicit
#                  and load-bearing for BOTH call-site shapes (§U2.5's scoped
#                  wait and the confirming required-check pass).
#   --bound <s>    hard wall-clock ceiling on the wait, in seconds.
#   --interval <s> poll interval, in seconds (default 15, matching
#                  review-heal/SKILL.md's documented poll_interval).
#   --required-only
#                  scope = required checks ONLY (used by the confirming
#                  required-check pass — it never waits on review-producing
#                  checks, per §"Termination-only severity floor").
#   --review-check-pattern <glob>[,<glob>...]
#                  scope = required checks (always) UNION checks whose name
#                  matches any of these comma-separated globs (used by
#                  §U2.5's scoped wait). Default when NEITHER flag is passed:
#                  `*review*,claude*` (skills/review-heal/SKILL.md's own
#                  documented default).
#
# CONTRACT
#   - Foreground and BLOCKING. This script NEVER backgrounds itself — that is
#     the entire point (see "WHY THIS EXISTS" above).
#   - Bash 3.2 / BSD-safe: NO `timeout` binary dependency (per this repo's
#     documented macOS/BSD portability convention — `timeout` may be absent).
#     The bound is tracked via the bash builtin `$SECONDS` (reset to 0 at
#     script start), never a `date`-diff or a subprocess timer.
#   - ALWAYS exits 0 — mirrors dispatch-pr-review.sh / send-webhook.sh's
#     fire-and-forget convention. A malformed invocation or an unreadable `gh`
#     read degrades to an ELAPSED-shaped line, never a non-zero exit the
#     caller would have to special-case.
#   - Prints EXACTLY ONE final line to stdout:
#       SETTLED sha=<sha> required=<green|red> review_producing=<settled|elapsed>
#       ELAPSED sha=<sha> required=<green|red|pending> review_producing=<settled|elapsed> pending=<comma-list|none>
#     The caller (the model, per the skill prose) is responsible for turning
#     this line into a READY/ESCALATED decision — this script only reports
#     scoped-settlement fact, it never decides drain readiness itself.
#
# GH STUB SEAM (tests)
#   The `gh` binary is invoked via "${GH:-gh}" throughout — a test exports
#   GH=/path/to/stub-gh to script a deterministic sequence of rollup
#   responses across polls without any network call. See
#   test-wait-for-checks.sh.

set -u
# Intentionally NO `set -e` / pipefail — every gh/jq read is individually
# guarded so a single unreadable poll degrades gracefully instead of
# aborting the whole bounded wait.

log() { printf 'wait-for-checks: %s\n' "$1" >&2; }

GH_BIN="${GH:-gh}"
JQ_BIN="${JQ:-jq}"

# ---- Parse args --------------------------------------------------------------
PR_URL=""
SHA=""
BOUND=""
INTERVAL="15"
REQUIRED_ONLY=0
REVIEW_PATTERN=""
HAVE_PATTERN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --sha)
      SHA="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --sha=*)
      SHA="${1#--sha=}"; shift ;;
    --bound)
      BOUND="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --bound=*)
      BOUND="${1#--bound=}"; shift ;;
    --interval)
      INTERVAL="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --interval=*)
      INTERVAL="${1#--interval=}"; shift ;;
    --required-only)
      REQUIRED_ONLY=1; shift ;;
    --review-check-pattern)
      REVIEW_PATTERN="${2:-}"; HAVE_PATTERN=1; shift; [ $# -gt 0 ] && shift ;;
    --review-check-pattern=*)
      REVIEW_PATTERN="${1#--review-check-pattern=}"; HAVE_PATTERN=1; shift ;;
    --*)
      # Unknown flag — ignore (forward compat, mirrors dispatch-pr-review.sh).
      shift ;;
    *)
      [ -z "$PR_URL" ] && PR_URL="$1"
      shift ;;
  esac
done

# Default scope (§U2.5): required ∪ *review*/claude* when neither
# --required-only nor --review-check-pattern was passed.
if [ "$REQUIRED_ONLY" -eq 0 ] && [ "$HAVE_PATTERN" -eq 0 ]; then
  REVIEW_PATTERN='*review*,claude*'
  HAVE_PATTERN=1
fi

if [ -z "$PR_URL" ] || [ -z "$SHA" ] || [ -z "$BOUND" ]; then
  log "usage: wait-for-checks.sh <pr_url> --sha <sha> --bound <seconds> [--interval <s>] [--required-only | --review-check-pattern <glob>]"
  printf 'ELAPSED sha=%s required=pending review_producing=elapsed pending=bad_usage\n' "${SHA:-unknown}"
  exit 0
fi

if ! command -v "$JQ_BIN" >/dev/null 2>&1; then
  log "jq not found — cannot parse gh output"
  printf 'ELAPSED sha=%s required=pending review_producing=elapsed pending=no_jq\n' "$SHA"
  exit 0
fi

# ---- owner/repo from the PR URL ----------------------------------------------
OWNER=""
REPO=""
case "$PR_URL" in
  *github.com/*/*/pull/*)
    _rest="${PR_URL#*github.com/}"
    _ownerrepo="${_rest%%/pull/*}"
    OWNER="${_ownerrepo%%/*}"
    REPO="${_ownerrepo#*/}"
    ;;
esac

# review_pattern_match <name> <comma-separated-globs> — bash-native glob
# matching (no jq/regex glob-translation reinvented). Returns 0 on any match.
#
# `set -f` (noglob) is LOAD-BEARING around the `set --` word-split below: an
# unquoted `set -- $patterns` is ALSO subject to pathname expansion, so a
# pattern like `*review*` would silently glob-expand against whatever the
# CURRENT WORKING DIRECTORY happens to contain (e.g. run from
# loomwright/scripts/ itself, `*review*` matches real files like
# `dispatch-pr-review.sh`) INSTEAD of staying the literal glob string this
# function means to match check NAMES against. Without `set -f` this breaks
# silently and non-deterministically depending on the caller's cwd — caught
# by a full-suite run where the caller `cd`'d into loomwright/scripts/ first.
review_pattern_match() {
  local name="$1" patterns="$2" p oldIFS
  [ -n "$patterns" ] || return 1
  oldIFS="$IFS"
  IFS=','
  set -f
  set -- $patterns
  set +f
  IFS="$oldIFS"
  for p in "$@"; do
    case "$name" in
      $p) return 0 ;;
    esac
  done
  return 1
}

# ---- Required-check discovery (§U2, fail-closed spirit — an unreadable read
# here degrades required_contexts_json to [], which makes `required=green`
# vacuously true; the caller (the SKILL prose's fail-CLOSED rule) is what
# turns an unverifiable required set into ESCALATED, not this script) --------
required_contexts_json="[]"
if [ -n "$OWNER" ] && [ -n "$REPO" ]; then
  _base="$("$GH_BIN" pr view "$PR_URL" --json baseRefName 2>/dev/null || true)"
  BASE_REF="$(printf '%s' "$_base" | "$JQ_BIN" -r '.baseRefName // empty' 2>/dev/null || true)"
  [ -n "$BASE_REF" ] || BASE_REF="main"
  _prot="$("$GH_BIN" api "repos/$OWNER/$REPO/branches/$BASE_REF/protection" 2>/dev/null || true)"
  if [ -n "$_prot" ] && printf '%s' "$_prot" | "$JQ_BIN" -e . >/dev/null 2>&1; then
    required_contexts_json="$(printf '%s' "$_prot" | "$JQ_BIN" -c '
      ((.required_status_checks.contexts // []) + ((.required_status_checks.checks // []) | map(.context))) | unique
    ' 2>/dev/null || echo '[]')"
    [ -n "$required_contexts_json" ] || required_contexts_json="[]"
  fi
fi

# ---- Bounded, foreground poll loop (§U2.5 + confirming-pass, mechanized) ----
SECONDS=0   # bash builtin wall-clock counter — reset here so $SECONDS is the
            # elapsed time since THIS script started, never a `date`-diff
            # (bash 3.2 / BSD safe; no `timeout` binary dependency).

while :; do
  _view="$("$GH_BIN" pr view "$PR_URL" --json headRefOid,statusCheckRollup 2>/dev/null || true)"
  live_sha=""
  rollup='[]'
  if [ -n "$_view" ] && printf '%s' "$_view" | "$JQ_BIN" -e . >/dev/null 2>&1; then
    live_sha="$(printf '%s' "$_view" | "$JQ_BIN" -r '.headRefOid // empty' 2>/dev/null || true)"
    rollup="$(printf '%s' "$_view" | "$JQ_BIN" -c '.statusCheckRollup // []' 2>/dev/null || echo '[]')"
  fi

  required_settled=0
  required_green=1
  rp_settled=1        # vacuously settled when not tracked (--required-only)
  pending_names=""

  if [ "$live_sha" = "$SHA" ]; then
    # Required-check stats: total/materialized/in-flight/not-green, computed
    # in ONE jq pass. Materialization is checked SEPARATELY from in-flight —
    # a required context absent from the rollup entirely (not yet created for
    # this sha) is NOT-settled, never silently read as the prior commit's
    # green (the exact race skills/review-heal/SKILL.md's confirming pass
    # names: "an absent entry is indistinguishable from 'not yet queued'").
    _req_stats="$(printf '%s' "$rollup" | "$JQ_BIN" -r --argjson req "$required_contexts_json" '
      ($req | length) as $total
      | [ .[] | select( (( .name // .context // "" ) as $n | ($req | index($n))) != null ) ] as $rows
      | ($rows | length) as $materialized
      | ( [ $rows[] | select(
            (((.status // "") | ascii_upcase) as $st | ($st=="QUEUED" or $st=="IN_PROGRESS"))
            or (((.state // "") | ascii_upcase) == "PENDING")
          ) ] | length ) as $inflight
      | ( [ $rows[] | select(
            ( ((.conclusion // "") | ascii_upcase) as $c | ((.state // "") | ascii_upcase) as $s
              | ($c=="SUCCESS" or $c=="NEUTRAL" or $s=="SUCCESS") | not )
          ) ] | length ) as $notgreen
      | "\($total)\t\($materialized)\t\($inflight)\t\($notgreen)"
    ' 2>/dev/null || printf '0\t0\t0\t0')"
    IFS=$'\t' read -r _req_total _req_materialized _req_inflight _req_notgreen <<EOF_STATS
$_req_stats
EOF_STATS
    _req_total="${_req_total:-0}"; _req_materialized="${_req_materialized:-0}"
    _req_inflight="${_req_inflight:-0}"; _req_notgreen="${_req_notgreen:-0}"

    if [ "$_req_materialized" -ge "$_req_total" ] 2>/dev/null && [ "$_req_inflight" -eq 0 ] 2>/dev/null; then
      required_settled=1
    fi
    if [ "$_req_notgreen" -gt 0 ] 2>/dev/null; then
      required_green=0
    fi

    # Review-producing scope (§U2.5) — bash-native glob match over the FULL
    # rollup (union with required is harmless: a required check that also
    # matches the pattern is already covered by the required stats above).
    if [ "$REQUIRED_ONLY" -eq 0 ]; then
      rp_settled=1
      _rows_tsv="$(printf '%s' "$rollup" | "$JQ_BIN" -r '
        .[] | [ (.name // .context // ""), (.status // ""), (.state // "") ] | @tsv
      ' 2>/dev/null || true)"
      while IFS=$'\t' read -r _c_name _c_status _c_state; do
        [ -n "$_c_name" ] || continue
        review_pattern_match "$_c_name" "$REVIEW_PATTERN" || continue
        _up_status="$(printf '%s' "$_c_status" | tr '[:lower:]' '[:upper:]')"
        _up_state="$(printf '%s' "$_c_state" | tr '[:lower:]' '[:upper:]')"
        if [ "$_up_status" = "QUEUED" ] || [ "$_up_status" = "IN_PROGRESS" ] || [ "$_up_state" = "PENDING" ]; then
          rp_settled=0
          pending_names="${pending_names:+$pending_names,}$_c_name"
        fi
      done <<EOF_ROWS
$_rows_tsv
EOF_ROWS
    fi
  else
    # Unknown/mismatched sha — never settled. Surface it plainly.
    pending_names="sha_mismatch"
  fi

  if [ "$required_settled" -eq 1 ] && [ "$rp_settled" -eq 1 ]; then
    _req_field="red"
    [ "$required_green" -eq 1 ] && _req_field="green"
    printf 'SETTLED sha=%s required=%s review_producing=settled\n' "$SHA" "$_req_field"
    exit 0
  fi

  if [ "$SECONDS" -ge "$BOUND" ] 2>/dev/null; then
    _req_field="pending"
    if [ "$required_settled" -eq 1 ]; then
      _req_field="red"
      [ "$required_green" -eq 1 ] && _req_field="green"
    fi
    _rp_field="elapsed"
    [ "$rp_settled" -eq 1 ] && _rp_field="settled"
    [ -n "$pending_names" ] || pending_names="none"
    printf 'ELAPSED sha=%s required=%s review_producing=%s pending=%s\n' "$SHA" "$_req_field" "$_rp_field" "$pending_names"
    exit 0
  fi

  sleep "$INTERVAL" 2>/dev/null || sleep 1
done
