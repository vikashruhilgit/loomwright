## REVIEW_HEAL_RESULT

```yaml
REVIEW_HEAL_RESULT:
  schema_version: 2
  decision: READY
  iterations: 1
  issues_fixed: 1
  remaining_issues: 0
  pr_url: "https://github.com/acme/widgets/pull/7"
  notified: true
  rounds: 1
  max_rounds: 5
  fix_cycles: 1
  churn_rounds: 1
  repeat_check_failure: false
  unresolved_bot_feedback: false
  postmortem_churn_threshold: 2
  postmortem_dispatched: false
  channels_scanned: [reviews, latestReviews, reviewThreads, issue_comments, check_outputs]
  findings_validated: 1
  findings_dismissed: 1
  checks_waited: [ci, claude-review]
  termination_reason: converged
  severity_floor: HIGH
  rejected_instruction_like: 0
  dismissed:
    - {finding: "load_config ignores the exit status of jq", reason: "already-addressed by the round-1 fix (src/widget.sh:42 now checks jq's status)", source: issue_comments, severity: HIGH}
  rules_gate: none
```
