#!/usr/bin/env bash
# protection-paid-plan.sh — sourced library. The ONE reading of GitHub's "branch protection needs a
# paid plan" refusal, for the drain's two protection readers (review-heal-next-step.sh `required`,
# wait-for-checks.sh).
#
# On a private repo on GitHub Free both protection endpoints exit 1 with this on stdout and stderr
# (captured 2026-11-06 from `gh api` on a private repo, for .../protection and
# .../protection/required_status_checks alike):
#   {"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.",…,"status":"403"}
#   gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
#
# Both parts must match, so a token-scope 403 and a 5xx stay unreadable and keep failing CLOSED. If
# GitHub rewords the message the drain escalates, which is the safe direction.
#
# protection_paid_plan_refusal <captured gh output> — 0 when it is that refusal, 1 otherwise. The
# caller checks gh's exit status first: this reads text only.
protection_paid_plan_refusal() {
  case "$1" in *"Upgrade to GitHub Pro"*) ;; *) return 1 ;; esac
  case "$1" in *"HTTP 403"*|*'"status":"403"'*) return 0 ;; esac
  return 1
}
