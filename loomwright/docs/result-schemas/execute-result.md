## EXECUTE_RESULT

Produced by Execute Manager when all subtasks are completed.

> **`out_of_lane` is NOT an `EXECUTE_RESULT` field.** A worker's lane report reaches
> durable state through Context-Keeper's `record_worker_result` (whose parameter
> contract in `agents/context-keeper.md` declares it), landing in `state.md`'s
> `## Worker Results`. `EXECUTE_RESULT` stays at `schema_version: 1`, unchanged.
> This is deliberate: lane reporting is report-only and per-worker, so it belongs
> in the per-worker record, not in the aggregate execute summary.
>
> **`not_verified` is likewise NOT an `EXECUTE_RESULT` field (harness-port/04).** It
> reaches durable state the SAME way `out_of_lane` does — through Context-Keeper's
> `record_worker_result` parameter contract, landing in `state.md`'s `## Worker
> Results` — and from there is aggregated into the FINALIZE PR body's optional
> `## Not verified` section (`skills/async-orchestration/SKILL.md` Part 2) and the
> done brief's own `## Not verified` section (`skills/self-heal-advisory/SKILL.md`
> step 2), which `verify-run.sh acs` parses back for `/verify`. `EXECUTE_RESULT`
> stays at `schema_version: 1`, unchanged.

```yaml
EXECUTE_RESULT:
  schema_version: 1                    # integer, required — always 1
  subtasks_completed: object[]         # required — may be empty ONLY when subtasks_failed is non-empty (all-failed escalation)
    - task_id: string                  # subtask identifier
      status: completed                # always "completed" in this array
      branch: string                   # worktree branch name
      files_modified: string[]         # files changed by this subtask
      review_decision: string          # PASS (must be PASS to be in completed) — REQUIRED, unchanged shape, but reinterpreted (Fix 7): above the Decomposition Threshold (and on the Sequential Path) no per-subtask LLM reviewer runs any more, so this field reports the DETERMINISTIC `outputs_verified` gate's outcome (plus tests/lint) for that subtask, NOT an LLM reviewer's decision — `agents/execute-manager.md` sets it to `PASS` once that gate passes, never from a `CODE_REVIEW_RESULT`. Below the threshold (Single-Agent Path) this field was already unused (no `EXECUTE_RESULT` is emitted there). See `agents/orchestrator.md` §"Review Gate Policy".
  subtasks_failed: object[]            # optional — subtasks that failed after retries
    - task_id: string
      status: failed
      error: string
      retry_count: integer
  merge_order: string[]                # required — ordered list of branches to merge
  worktrees: object[]                  # required — worktree details for cleanup
    - task_id: string
      path: string                     # absolute path to worktree
      branch: string                   # branch name in worktree
      status: enum [completed, failed, cleaned]
  branches: string[]                   # optional — all branches created
  summary: string                      # required — execution summary
```

**Validation rules:**
- `schema_version` must equal `1`
- **Discriminator (no top-level `status:` field):** consumers (Supervisor Phase 3) branch on `subtasks_failed` — non-empty ⇔ escalation; additionally `subtasks_completed` empty ⇔ all-failed escalation (nothing to merge). A partial escalation (both arrays non-empty) merges the completed subset per `merge_order`, then reports the failures.
- `subtasks_completed` must be present; it may be an empty array ONLY when `subtasks_failed` is non-empty and `summary` records the escalation (all-failed case)
- `merge_order` must match completed subtask branches (empty when `subtasks_completed` is empty), minus any subtask whose `WORKER_RESULT` declared `no_changes: true` — that branch has nothing to commit or merge (see `WORKER_RESULT.no_changes` above)
- `worktrees` must be non-empty array with valid paths
- `summary` must be present

**Example:**
```
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: add-jwt-guard
      status: completed
      branch: feature/add-jwt-guard
      files_modified: [src/auth/jwt.guard.ts]
      review_decision: PASS
    - task_id: add-refresh-token
      status: completed
      branch: feature/add-refresh-token
      files_modified: [src/auth/refresh.service.ts]
      review_decision: PASS
  merge_order: [feature/add-jwt-guard, feature/add-refresh-token]
  worktrees:
    - task_id: add-jwt-guard
      path: /Users/<name>/myapp-add-jwt-guard
      branch: feature/add-jwt-guard
      status: completed
    - task_id: add-refresh-token
      path: /Users/<name>/myapp-add-refresh-token
      branch: feature/add-refresh-token
      status: completed
  summary: 2/2 subtasks completed. JWT guard and refresh token service implemented.
```

---

