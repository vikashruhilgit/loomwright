Tool-call budget exhausted at 58/60. Checkpointing with an adjudication request.

```yaml
EXECUTE_CHECKPOINT:
  schema_version: 1
  completed_so_far:
    - task_id: add-jwt-guard
      status: completed
      branch: feature/add-jwt-guard
      files_modified: [src/auth/jwt.guard.ts]
  in_progress: []
  remaining:
    - task_id: add-refresh-token
      status: pending
      dependencies: [add-jwt-guard]
  resume_context:
    tool_calls_used: 58
    active_worktrees: [/Users/name/myapp-add-refresh-token]
    feature_branch: feature/auth-hardening
  reason: "Tool-call budget exhausted at 58/60 with one subtask still pending."
  adjudication_required: true
  missing_outputs:
    - item: src/auth/refresh.service.ts
      producing_subtask: add-refresh-token
      check_run: "ls"
  adjudication_options: ["A: re-queue producer", "B: insert remediation subtask", "C: exit to Launch Pad", "D: update consumer brief"]
```
