#!/usr/bin/env bash
# drain-subfloor-decision.sh — the until-mergeable drain's sub-floor STOP
# decision, as a deterministic pure function. Mechanizes
# skills/review-heal/SKILL.md §U4's sub-floor block and §"Termination-only
# severity floor (`sub_floor_converged`)" — read those before changing this
# script. The semantics are UNCHANGED from that prose (reading B, fix-then-
# stop): this script changes WHO evaluates the rule, not the rule. The model
# runs the two calls below and acts ONLY on the one line each prints.
#
# WHY THIS EXISTS (implementation-quality/02, Part T01)
#   On the 2026-10-08 drain of PR #435 the model evaluated the prose rule
#   wrong: round 1 met every eligibility clause and its confirming pass would
#   have been GREEN, yet a second round ran (~33 min late), and the emitted
#   `sub_floor_fixed` listed BOTH rounds' findings. The round ceiling
#   (drain-rounds.sh) and the wait (wait-for-checks.sh) were already
#   mechanized; this was the remaining prose-evaluated decision.
#
# USAGE
#   drain-subfloor-decision.sh eligible <round.json|->
#   drain-subfloor-decision.sh decide   <round.json|-> --sha <pushed_sha> \
#       --wait-line '<the ONE line wait-for-checks.sh --required-only printed>' \
#       --rules <rules_after verdict> \
#       [--rules-failed-seen <comma-ids>] [--checks-ever-fixed <comma-names>]
#
#   round.json (or stdin with `-`) — the round's classified inputs:
#     {"required_failing": [...], "needs_human": [...],
#      "auto_fixable": [{"severity": "LOW", ...}, ...], "severity_floor": "HIGH"}
#   --rules-failed-seen   ids remembered from an earlier `fail` (empty = none).
#   --checks-ever-fixed   required-check names a prior fix cycle targeted.
#   The wait line's failing names come from its `red_names=` field (pass
#   `--names` to wait-for-checks.sh); absent ⇒ no failing names known.
#
# DECISION TABLE (severity_rank: BLOCKING 4 > HIGH 3 > MEDIUM 2 > LOW 1;
#                 "below the floor" = STRICTLY lower rank)
#   eligible:
#     required_failing == [] AND needs_human == [] AND auto_fixable != []
#       AND every auto_fixable severity ranks strictly below severity_floor
#                                                         ⇒ confirm
#     anything else — incl. missing/unreadable/malformed input, a finding
#     with an absent or unrecognised severity, an unknown floor, no jq
#                                                         ⇒ continue
#   decide (round inputs must still be eligible, else ⇒ continue):
#     wait line missing/garbage, ELAPSED, sha= ≠ --sha, no --sha, no jq
#                                                         ⇒ ESCALATED repeat_check_failure=false
#     SETTLED required=<anything but exactly green> (red, unknown, …)
#                                                         ⇒ ESCALATED repeat_check_failure=<bool>
#       (true iff required=red AND a red_names= name ∈ checks_ever_fixed — AC13)
#     SETTLED required=green AND NOT (rules == unstamped AND rules_failed_seen
#       non-empty) AND rules ∈ RULES_PASSABLE (ok|none|unstamped|cmd_disabled)
#                                                         ⇒ READY sub_floor_converged sub_floor_fixed=<auto_fixable JSON>
#     SETTLED required=green, rules clause does not hold (fail, unresolved,
#       unreadable, an unrecognised verdict, unstamped after a remembered fail)
#                                                         ⇒ continue
#   `sub_floor_fixed` is THIS round's auto_fixable only — never accumulated
#   across rounds (earlier rounds' fixes count in issues_fixed/fix_cycles).
#
# OUTPUT — exactly one line on stdout; a reason goes to stderr.
#   eligible: `confirm` | `continue`
#   decide:   `READY sub_floor_converged sub_floor_fixed=<compact JSON array>`
#           | `continue`
#           | `ESCALATED repeat_check_failure=<true|false>`
#
# EXIT CODES
#   0  a decision line was printed (fail-closed decisions included). READY is
#      only ever printed on this path.
#   2  usage error: missing or unknown subcommand — nothing on stdout.
#
# Bash 3.2 / BSD-safe; `set -u` only. jq via "${JQ:-jq}" (test seam).

set -u

JQ_BIN="${JQ:-jq}"

say()    { printf '%s\n' "$1"; exit 0; }
reason() { printf 'drain-subfloor-decision: %s\n' "$1" >&2; }

# read_round <path|-> — prints the round JSON (validated object) or nothing.
read_round() {
  local src="${1:-}" body=""
  case "$src" in
    "") return 0 ;;
    -) body="$(cat 2>/dev/null || true)" ;;
    *) [ -r "$src" ] || return 0; body="$(cat "$src" 2>/dev/null || true)" ;;
  esac
  printf '%s' "$body" | "$JQ_BIN" -ce 'select(type == "object")' 2>/dev/null || true
}

# eligible_json <round-json> — prints `confirm` or `continue:<reason>`.
eligible_json() {
  printf '%s' "$1" | "$JQ_BIN" -r '
    def rank: if type != "string" then 0 else ascii_upcase
      | if . == "BLOCKING" then 4 elif . == "HIGH" then 3
        elif . == "MEDIUM" then 2 elif . == "LOW" then 1 else 0 end end;
    (.severity_floor | rank) as $floor
    | if ($floor == 0) then "continue:unknown_severity_floor"
      elif ((.required_failing | type) != "array") or ((.needs_human | type) != "array")
           or ((.auto_fixable | type) != "array") then "continue:malformed_input"
      elif (.required_failing | length) > 0 then "continue:required_failing"
      elif (.needs_human | length) > 0 then "continue:needs_human"
      elif (.auto_fixable | length) == 0 then "continue:no_auto_fixable"
      elif ([.auto_fixable[] | (if type == "object" then .severity else null end) | rank] | any(. == 0))
        then "continue:unknown_finding_severity"
      elif ([.auto_fixable[] | .severity | rank] | all(. < $floor)) then "confirm"
      else "continue:at_or_above_floor" end
  ' 2>/dev/null || true
}

SUB="${1:-}"
[ $# -gt 0 ] && shift
case "$SUB" in
  eligible|decide) ;;
  *) reason "usage: drain-subfloor-decision.sh eligible|decide <round.json|-> [...]"; exit 2 ;;
esac

ROUND_SRC="${1:-}"
[ $# -gt 0 ] && shift

if [ "$SUB" = "eligible" ]; then
  if ! command -v "$JQ_BIN" >/dev/null 2>&1; then reason "jq not found"; say continue; fi
  round="$(read_round "$ROUND_SRC")"
  [ -n "$round" ] || { reason "round input missing or not a JSON object"; say continue; }
  verdict="$(eligible_json "$round")"
  case "$verdict" in
    confirm) say confirm ;;
    continue:*) reason "${verdict#continue:}"; say continue ;;
    *) reason "eligibility unevaluable"; say continue ;;
  esac
fi

# ---- decide ------------------------------------------------------------------
SHA=""; WAIT_LINE=""; HAVE_WAIT=0; RULES=""; RULES_SEEN=""; EVER_FIXED=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sha) SHA="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --wait-line) WAIT_LINE="${2:-}"; HAVE_WAIT=1; shift; [ $# -gt 0 ] && shift ;;
    --rules) RULES="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --rules-failed-seen) RULES_SEEN="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --checks-ever-fixed) EVER_FIXED="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    *) shift ;;
  esac
done

if ! command -v "$JQ_BIN" >/dev/null 2>&1; then
  reason "jq not found"; say "ESCALATED repeat_check_failure=false"
fi
round="$(read_round "$ROUND_SRC")"
[ -n "$round" ] || { reason "round input missing or not a JSON object"; say continue; }
verdict="$(eligible_json "$round")"
[ "$verdict" = "confirm" ] || { reason "round is not sub-floor-eligible (${verdict#continue:})"; say continue; }

# The confirming pass's one line. Anything but a well-formed SETTLED for
# exactly --sha is RED/UNREADABLE ⇒ ESCALATED (never READY on an unknown SHA).
[ "$HAVE_WAIT" -eq 1 ] && [ -n "$WAIT_LINE" ] || { reason "no wait line"; say "ESCALATED repeat_check_failure=false"; }
[ -n "$SHA" ] || { reason "no --sha"; say "ESCALATED repeat_check_failure=false"; }
set -f
# shellcheck disable=SC2086
set -- $WAIT_LINE
set +f
kind="${1:-}"
line_sha=""; required=""; red_names=""
for tok in "$@"; do
  case "$tok" in
    sha=*) line_sha="${tok#sha=}" ;;
    required=*) required="${tok#required=}" ;;
    red_names=*) red_names="${tok#red_names=}" ;;
  esac
done
[ "$kind" = "SETTLED" ] || { reason "wait line is not SETTLED (${kind:-empty})"; say "ESCALATED repeat_check_failure=false"; }
[ "$line_sha" = "$SHA" ] || { reason "sha mismatch (${line_sha:-none} != $SHA)"; say "ESCALATED repeat_check_failure=false"; }

if [ "$required" != "green" ]; then   # GREEN-REQUIRED: anything but exactly green is RED
  repeat=false
  if [ "$required" = "red" ] && [ -n "$red_names" ] && [ "$red_names" != "none" ] && [ -n "$EVER_FIXED" ]; then
    _old="$IFS"; IFS=','
    set -f
    for rn in $red_names; do
      rn="${rn%@*}"
      for ef in $EVER_FIXED; do [ -n "$rn" ] && [ "$rn" = "$ef" ] && repeat=true; done
    done
    set +f
    IFS="$_old"
  fi
  reason "confirming pass required=${required:-missing}"
  say "ESCALATED repeat_check_failure=$repeat"
fi

# GREEN: the rules clause of READY (AFFIRMATIVE — anything else is NOT READY).
if [ "$RULES" = "unstamped" ] && [ -n "$RULES_SEEN" ]; then
  reason "unstamped after a remembered fail (rules_fail_then_unstamped)"; say continue
fi
case "$RULES" in
  ok|none|unstamped|cmd_disabled) ;;
  *) reason "rules verdict '${RULES:-missing}' not in RULES_PASSABLE"; say continue ;;
esac
fixed="$(printf '%s' "$round" | "$JQ_BIN" -c '.auto_fixable' 2>/dev/null || true)"
[ -n "$fixed" ] || { reason "auto_fixable unreadable at emit"; say continue; }
say "READY sub_floor_converged sub_floor_fixed=$fixed"
