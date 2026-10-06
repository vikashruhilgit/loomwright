## FIX_RESULT

Produced by the ad-hoc fix task that Supervisor spawns during Phase 4.5 self-heal iterations. Introduced in v11.0.0.

```yaml
FIX_RESULT:
  schema_version: 1                    # integer, required — always 1
  issues_addressed: integer            # required — count of issues the fix task resolved this iteration
  files_modified: string[]             # required — non-empty when issues_addressed > 0
  commit_sha: string                   # required — SHA of the fix commit on the feature branch
  summary: string                      # required — concise description of what was fixed
  deviations: string[]                 # optional — additive, no schema_version bump (stays 1); same shape/bound as WORKER_RESULT.deviations (at most 12 entries, each at most 200 characters, plan:/edge:/open:/test: convention, unprefixed reads as other:, never rejected for lacking a prefix). REPORT-ONLY — read by skills/self-heal-advisory/SKILL.md step 1g via the review-and-fix loop's per-run `fixer_deviations` list (Context-Keeper is not in this path — FIX_RESULT is returned in-context to the Supervisor, not through record_worker_result). Conditional-mandatory: a FIX_RESULT whose diff edits a test assertion and carries no `test:` entry is incomplete — no validator hook exists for FIX_RESULT (no FIX_RESULT validator hook as of this writing), so this is a prompt-contract-only rule.
```

**Validation rules:**
- `schema_version` must equal `1`
- `issues_addressed` must be a non-negative integer
- When `issues_addressed > 0`: `files_modified` must be non-empty
- `commit_sha` must match `^[0-9a-f]{7,40}$`
- `summary` must be present
- `deviations`, when present, must be an array of at most 12 non-empty strings, each at most 200 characters — same bound as `WORKER_RESULT.deviations`; no validator hook enforces this for FIX_RESULT (prompt-contract only)

**Example:**
```
FIX_RESULT:
  schema_version: 1
  issues_addressed: 3
  files_modified: [src/auth/jwt.guard.ts, src/auth/jwt.guard.spec.ts, src/auth/types.ts]
  commit_sha: a1b2c3d
  summary: Addressed 3 HIGH-severity findings — tightened JWT validation, fixed type exports, added missing unit tests.
  deviations: ["test: jwt.guard.spec.ts expiry case — assertion wrong: asserted pre-fix error message"]
```

---

