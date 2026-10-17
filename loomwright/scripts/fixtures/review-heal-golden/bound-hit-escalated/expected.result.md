## REVIEW_HEAL_RESULT

```yaml
REVIEW_HEAL_RESULT:
  schema_version: 2
  decision: ESCALATED
  iterations: 1
  issues_fixed: 1
  remaining_issues: 1
  pr_url: "https://github.com/acme/widgets/pull/7"
  notified: true
  rounds: 1
  max_rounds: 1
  fix_cycles: 1
  churn_rounds: 1
  repeat_check_failure: false
  unresolved_bot_feedback: true
  postmortem_churn_threshold: 2
  postmortem_dispatched: true
  channels_scanned: [reviews, latestReviews, reviewThreads, issue_comments, check_outputs]
  findings_validated: 1
  findings_dismissed: 0
  checks_waited: [ci, claude-review]
  termination_reason: bound_hit
  severity_floor: HIGH
  rejected_instruction_like: 0
  rules_gate: none
  escalation_cause: other
  escalation_check: null
  escalation_run_id: null
  escalation_attempt: null
  escalation_sha: "b2c3d4e5f60718293a4b5c6d7e8f901234567890"
```
