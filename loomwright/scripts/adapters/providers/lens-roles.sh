#!/usr/bin/env bash
# lens-roles.sh — role registry for lens-run.sh. SOURCED, never executed: it only
# defines functions and one constant, so sourcing has no side effect.
#
# A "role" is the --role value lens-run.sh is called with. Two kinds:
#   issues  the provider answers with the review-shaped {"issues":[...]} object
#           that lens-run.sh normalizes (the generic `review` role, plus seats
#           whose resolve-routing.sh marker column is `-`).
#   text    the provider answers in plain text; lens-run.sh returns it as
#           `result_text` and reports `lens_status: "ok"` only when that text
#           contains the role's marker (the seat's own output-contract token).
#
# WHERE THE SEAT LIST LIVES: scripts/resolve-routing.sh `seats` is the one home of
# the seat ids and of each seat's marker (`<id> <home-file> <marker> <validator>`).
# This file never restates either: a role is REGISTERED when it is `review` or a
# seat id printed by `resolve-routing.sh seats`, AND it has an output-contract arm
# in lens_role_shape below. The arms are role-specific prose (the content this
# file owns); test-lens-roles.sh fails when a seat has no arm, so a seat added to
# `seats` cannot silently stay unroutable or drift.
#
# FUNCTIONS
#   lens_role_lookup <role>    returns 0 when registered, else 1. Sets
#                              LENS_ROLE_KIND (issues|text) and LENS_ROLE_MARKER
#                              (the marker; empty for an issues role).
#   lens_role_contract <role>  prints the body of the prompt's OUTPUT CONTRACT
#                              section (call lens_role_lookup first for text roles:
#                              it names the marker).
#
# CONSTANT
#   LENS_RESULT_TEXT_MAX  byte bound on result_text. Over the bound the run is
#                         lens_unparseable (never silently truncated: a cut-off
#                         answer must not pass its marker check). Kept below one
#                         argv string limit of the platforms jq is run on.
#
# bash 3.2 safe: no associative arrays, no ${var,,}, no mapfile.

LENS_ROLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LENS_ROLES_ROUTING="$LENS_ROLES_DIR/../../resolve-routing.sh"
LENS_RESULT_TEXT_MAX=200000

LENS_ROLE_KIND=""
LENS_ROLE_MARKER=""

# lens_role_shape <role> — prints the role-specific "what the answer looks like"
# sentence for a text role; prints nothing for an issues role. Returns 1 when the
# role has no arm (an unregistered role). One arm per role; the marker token itself
# is appended by lens_role_contract from the seats table, never written here.
lens_role_shape() {
  case "$1" in
    review|heal_voter|refute) return 0 ;;
    plan_reviewer)
      printf '%s\n' 'Reply with the PLAN_REVIEW_RESULT block exactly as your instructions above define it (decision PASS, FAIL or NEEDS_HUMAN, the issues list, and a summary).' ;;
    orchestrator)
      printf '%s\n' 'Reply with the decomposition in the Context Read, Plan, Work/Results, Risks layout your instructions above define.' ;;
    drain_reviewer|fallback_reviewer|evaluate_reviewer|code_reviewer)
      printf '%s\n' 'Reply with your review, ending in the CODE_REVIEW_RESULT block exactly as your instructions above define it.' ;;
    rubric_grader)
      printf '%s\n' 'Reply with one "ITEM N: PASS" or "ITEM N: FAIL" line (with a one-line reason) per rubric bullet, then a final "rubric_score: <passed>/<total>" line.' ;;
    postmortem_classifier)
      printf '%s\n' 'Reply with the classification as the JSON object your instructions above define, including its categories array.' ;;
    dreaming_analysis)
      printf '%s\n' 'Reply with the analysis in the numbered sections your instructions above define, including the Recurring Patterns section.' ;;
    capability_check)
      printf '%s\n' 'Reply with the CAPABILITY_REPORT your instructions above define (one entry per candidate, or the no-candidates statement).' ;;
    red_team)
      printf '%s\n' 'Reply with the adversarial report, ending in the RED_TEAM_RESULT block exactly as your instructions above define it.' ;;
    product_owner)
      printf '%s\n' 'Reply with the requirements and stories your instructions above define, ending in the HANDOFF section.' ;;
    qa_strategist)
      printf '%s\n' 'Reply with the risk-based test strategy your instructions above define, including the risk Classification of each route or endpoint.' ;;
    *) return 1 ;;
  esac
  return 0
}

# lens_role_lookup <role> — see the header. Fails closed: a missing or failing
# resolve-routing.sh means no seat role is registered (only `review` is).
lens_role_lookup() {
  local role="${1:-}" id home marker validator found=0
  LENS_ROLE_KIND=""
  LENS_ROLE_MARKER=""
  case "$role" in
    ""|*[!a-z0-9_]*) return 1 ;;
  esac
  if [ "$role" = "review" ]; then
    LENS_ROLE_KIND=issues
    return 0
  fi
  [ -r "$LENS_ROLES_ROUTING" ] || return 1
  lens_role_shape "$role" >/dev/null || return 1
  while read -r id home marker validator; do
    [ "$id" = "$role" ] || continue
    found=1
    break
  done <<EOF
$(bash "$LENS_ROLES_ROUTING" seats 2>/dev/null)
EOF
  [ "$found" = "1" ] || return 1
  [ -n "$marker" ] || return 1
  if [ "$marker" = "-" ]; then
    LENS_ROLE_KIND=issues
  else
    LENS_ROLE_KIND=text
    LENS_ROLE_MARKER="$marker"
  fi
  return 0
}

# lens_role_contract <role> — prints the OUTPUT CONTRACT body. For an issues role
# this is byte-for-byte the instruction lens-run.sh always sent; for a text role it
# is the role's shape sentence plus the marker the answer must contain.
lens_role_contract() {
  local role="${1:-}"
  lens_role_lookup "$role" || return 1
  if [ "$LENS_ROLE_KIND" = "issues" ]; then
    printf 'Respond with ONLY a single JSON object, no prose outside it, matching exactly:\n'
    printf '{"issues": [{"severity": "BLOCKING|HIGH|MEDIUM|LOW", "category": "new|pre_existing|nit", "file": "<path>", "line": <integer or null>, "description": "<string>", "suggestion": "<string or null>"}]}\n'
    return 0
  fi
  printf 'Respond in plain text only. Do not modify any file.\n'
  lens_role_shape "$role"
  printf 'Your answer MUST contain this exact token, verbatim: %s\n' "$LENS_ROLE_MARKER"
  return 0
}
