## REVIEW_HEAL_RESULT

```yaml
REVIEW_HEAL_RESULT:
  schema_version: 2
  decision: ESCALATED
  iterations: 1
  issues_fixed: 0
  remaining_issues: 1
  pr_url: "https://github.com/acme/widgets/pull/7"
  notified: true
  rounds: 1
  max_rounds: 5
  fix_cycles: 0
  churn_rounds: 0
  repeat_check_failure: false
  unresolved_bot_feedback: false
  postmortem_churn_threshold: 2
  postmortem_dispatched: true
  channels_scanned: [reviews, latestReviews, reviewThreads, issue_comments, check_outputs]
  findings_validated: 0
  findings_dismissed: 0
  checks_waited: [ci, claude-review]
  termination_reason: ci_untrusted
  severity_floor: HIGH
  rejected_instruction_like: 0
  rules_gate: none
  escalation_cause: other
  escalation_check: null
  escalation_run_id: null
  escalation_attempt: null
  escalation_sha: null
  checks_untrusted:
    - {check: "ci", reason: zero_steps, run_id: "1001"}
```
