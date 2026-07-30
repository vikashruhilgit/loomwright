Brief reviewed against all criteria. One BLOCKING path issue found.

```markdown
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: FAIL
  issues:
    - severity: BLOCKING
      section: "File Impact Map"
      category: "missing_field"
      description: "Path src/auth/jwt.guard.ts does not exist in codebase. Glob found no matches."
      suggestion: "Verify correct path. Possible: src/guards/jwt.guard.ts (found via Glob)."
    - severity: MEDIUM
      section: "Parallelism Analysis"
      description: "Subtask 2 file overlap is understated but already serialized."
      suggestion: "Note the overlap in the matrix."
  summary: "Brief has 1 BLOCKING issue. File path verification failed for jwt.guard.ts."
```
