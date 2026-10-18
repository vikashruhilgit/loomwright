## REVIEW_HEAL_RESULT

```yaml
REVIEW_HEAL_RESULT:
  schema_version: 2
  decision: READY
  iterations: 2
  issues_fixed: 1
  remaining_issues: 0
  pr_url: "https://github.com/acme/widgets/pull/7"
  notified: true
  rounds: 2
  max_rounds: 5
  fix_cycles: 1
  churn_rounds: 1
  repeat_check_failure: false
  unresolved_bot_feedback: false
  postmortem_churn_threshold: 2
  postmortem_dispatched: false
  channels_scanned: [reviews, latestReviews, reviewThreads, issue_comments, check_outputs]
  findings_validated: 1
  findings_dismissed: 0
  checks_waited: [ci, claude-review]
  termination_reason: converged
  severity_floor: HIGH
  rejected_instruction_like: 0
  rules_gate: none
```
