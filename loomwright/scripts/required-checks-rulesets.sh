#!/usr/bin/env bash
# required-checks-rulesets.sh — sourced library. The ONE reading of a branch's
# repository-RULESET protection, for the three readers that otherwise see only
# classic branch protection: drain-gh-read.sh `required-checks` (the drain's
# required-check list), wait-for-checks.sh (the scoped wait's required set) and
# automate-helpers.sh `gate-eval` condition 4/5 (the --auto-merge gate).
#
# WHY: classic branch protection (`repos/<o>/<r>/branches/<b>/protection`) and
# rulesets are separate GitHub stores. A base branch protected ONLY by a ruleset
# answers the classic endpoint with 404 "Branch not protected", so a classic-only
# reader escalates every drain `required_checks_unavailable`, reads the scoped
# wait's required set as verified-empty, and reads the merge gate's base as
# unprotected (issue #874). `repos/<o>/<r>/rules/branches/<b>` returns the
# EFFECTIVE rules for the branch — every active ruleset that applies, merged.
#
# rulesets_required_read <gh_bin> <jq_bin> <owner> <repo> <branch>
#   Always returns 0. Sets:
#     RSR_STATE     list       — at least one active required_status_checks rule names a context
#                   none       — read verified: no rule names a required check (an empty rule list,
#                                rules without required checks, a 404 for the rules endpoint, or
#                                GitHub's paid-plan refusal: such a repo cannot have rulesets)
#                   unreadable — any other failure, or a body that is not a rule array. Callers
#                                FAIL CLOSED on this: a ruleset they could not read may require
#                                checks they would otherwise skip.
#     RSR_CONTEXTS  JSON array (unique) of the required contexts; "[]" unless list
#     RSR_REVIEWS   the highest required_approving_review_count over active pull_request rules (0)
#     RSR_ERR       gh's error output when unreadable
#   A rules read that succeeds with no required_status_checks rule is "no required list", never
#   "every check required" (issue #874 acceptance 4).
#
# gh_http_status <captured gh output> — the status from the LAST line ending in gh's
#   `(HTTP NNN)` token, never a bare `404` elsewhere in the text; empty when there is none.

_RSR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v protection_paid_plan_refusal >/dev/null 2>&1; then
  # A missing library reads the paid-plan refusal as unreadable: fail CLOSED.
  . "$_RSR_DIR/protection-paid-plan.sh" 2>/dev/null || protection_paid_plan_refusal() { return 1; }
fi

gh_http_status() {
  printf '%s\n' "$1" | sed -n -E 's/.*\(HTTP ([0-9]{3})\)[[:space:]]*$/\1/p' | tail -n 1
}

rulesets_required_read() {
  local gh="$1" jqb="$2" owner="$3" repo="$4" branch="$5" out err_f err rc=0 parsed
  RSR_STATE=unreadable; RSR_CONTEXTS='[]'; RSR_REVIEWS=0; RSR_ERR=''
  err_f="$(mktemp 2>/dev/null)" || { RSR_ERR="mktemp failed"; return 0; }
  out="$("$gh" api --method GET "repos/$owner/$repo/rules/branches/$branch?per_page=100" --paginate 2>"$err_f" </dev/null)" || rc=$?
  err="$(cat "$err_f" 2>/dev/null)"; rm -f "$err_f"
  if [ "$rc" -ne 0 ]; then
    RSR_ERR="$out $err"
    if [ "$(gh_http_status "$err")" = 404 ] || protection_paid_plan_refusal "$out $err"; then
      RSR_STATE=none
    fi
    return 0
  fi
  # --paginate concatenates one JSON array per page; slurp and add them. Anything that is not
  # an array of rule objects is unreadable, never "no rules".
  parsed="$(printf '%s' "$out" | "$jqb" -cs '
    if length > 0 and all(.[]; type == "array") then
      (add // []) as $rules
      | if all($rules[]; type == "object") then
          { contexts: ([ $rules[] | select(.type == "required_status_checks")
                         | (.parameters.required_status_checks // [])[] | .context ]
                       | map(select(type == "string" and length > 0)) | unique),
            reviews:  ([ $rules[] | select(.type == "pull_request")
                         | (.parameters.required_approving_review_count // 0)
                         | select(type == "number") ] | max // 0) }
        else error("rule is not an object") end
    else error("not a rule array") end' 2>/dev/null)" || parsed=""
  if [ -z "$parsed" ]; then
    RSR_ERR="rules/branches/$branch returned a body that is not a rule array"
    return 0
  fi
  RSR_CONTEXTS="$(printf '%s' "$parsed" | "$jqb" -c '.contexts')"
  RSR_REVIEWS="$(printf '%s' "$parsed" | "$jqb" -r '.reviews')"
  if [ "$RSR_CONTEXTS" = "[]" ]; then RSR_STATE=none; else RSR_STATE=list; fi
  return 0
}
