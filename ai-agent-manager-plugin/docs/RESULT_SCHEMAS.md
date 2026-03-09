# Result Schemas

> Strict contracts for all agent result blocks. Hooks validate against these schemas.
> All schemas include `schema_version: 1` for forward compatibility.

---

## WORKER_RESULT

Produced by Worker agent on task completion.

```yaml
WORKER_RESULT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — subtask identifier (e.g., "BD-15a" or "add-auth-guard")
  status: enum [completed, failed, partial]  # required
  files_modified: string[]             # required — non-empty when status=completed
  files_created: string[]              # optional — new files created
  tests_added: string[]               # optional — test files added or modified
  tests_passed: boolean               # optional — true if all tests pass
  summary: string                      # required — max 200 tokens, what was done
  error: string                        # conditional — required when status=failed, describes what went wrong
```

**Validation rules:**
- `schema_version` must equal `1`
- `task_id` must be non-empty string
- `status` must be one of: `completed`, `failed`, `partial`
- When `status=completed`: `files_modified` must be non-empty array
- When `status=failed`: `error` must be present and non-empty
- `summary` must be present and under 200 tokens

**Example:**
```
WORKER_RESULT:
  schema_version: 1
  task_id: add-jwt-guard
  status: completed
  files_modified: [src/auth/jwt.guard.ts, src/auth/jwt.strategy.ts]
  files_created: [src/auth/jwt.guard.spec.ts]
  tests_added: [src/auth/jwt.guard.spec.ts]
  tests_passed: true
  summary: Implemented JWT guard with passport strategy. Added unit tests with 92% coverage.
```

---

## EXECUTE_RESULT

Produced by Execute Manager when all subtasks are completed.

```yaml
EXECUTE_RESULT:
  schema_version: 1                    # integer, required — always 1
  subtasks_completed: object[]         # required — non-empty array
    - task_id: string                  # subtask identifier
      status: completed                # always "completed" in this array
      branch: string                   # worktree branch name
      files_modified: string[]         # files changed by this subtask
      review_decision: string          # PASS (must be PASS to be in completed)
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
- `subtasks_completed` must be non-empty array (at least one subtask succeeded)
- `merge_order` must be non-empty array matching completed subtask branches
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
      path: /Users/name/myapp-add-jwt-guard
      branch: feature/add-jwt-guard
      status: completed
    - task_id: add-refresh-token
      path: /Users/name/myapp-add-refresh-token
      branch: feature/add-refresh-token
      status: completed
  summary: 2/2 subtasks completed. JWT guard and refresh token service implemented.
```

---

## EXECUTE_CHECKPOINT

Produced by Execute Manager when budget is exceeded or partial progress needs saving.

```yaml
EXECUTE_CHECKPOINT:
  schema_version: 1                    # integer, required — always 1
  completed_so_far: object[]           # required — subtasks already done
    - task_id: string
      status: completed
      branch: string
      files_modified: string[]
  in_progress: object[]                # optional — currently running subtasks
    - task_id: string
      status: in_progress
      worktree_path: string
      agent_id: string                 # Task agent ID for potential resume
  remaining: object[]                  # required — subtasks not yet started
    - task_id: string
      status: pending
      dependencies: string[]           # task_ids that must complete first
  resume_context: object               # required — data needed to resume
    tool_calls_used: integer
    active_worktrees: string[]         # paths that still exist
    feature_branch: string
  reason: string                       # required — why checkpointing (budget, error, etc.)
```

**Validation rules:**
- `schema_version` must equal `1`
- `completed_so_far` must be present (can be empty array if no subtasks done yet)
- `remaining` must be present and non-empty (otherwise use EXECUTE_RESULT)
- `resume_context` must be present with at least `feature_branch`
- `reason` must be non-empty string

---

## QA_RESULT

Produced by QA Executor on test completion.

```yaml
QA_RESULT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — QA run identifier
  status: enum [passed, failed, partial, skipped]  # required
  rounds_run: string                   # optional — e.g., "1/3"
  tests_generated: integer             # required — number of test files/cases generated
  tests_passed: integer                # required — number passing
  tests_failed: integer                # optional — number failing (default 0)
  discovery_confidence: enum [HIGH, MEDIUM, LOW]  # optional
  coverage_estimate: float             # optional — 0.0 to 1.0, routes/APIs tested vs discovered
  risks: object[]                      # optional — identified risk areas
    - area: string
      level: enum [HIGH, MEDIUM, LOW]
      description: string
  bugs_found: object[]                 # optional — bugs discovered during testing
    - id: string
      severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      description: string
      file: string                     # optional — file where bug manifests
      steps: string                    # optional — reproduction steps
  strategist_verdict: string           # optional — approved/rejected from Strategist
  files_created: string[]              # optional — test and discovery files created
  summary: string                      # required — max 200 tokens
  error: string                        # conditional — required when status=failed
```

**Validation rules:**
- `schema_version` must equal `1`
- `tests_generated` and `tests_passed` must be non-negative integers
- `tests_passed` must be ≤ `tests_generated`
- When `status=failed`: `error` must be present
- `summary` must be present and under 200 tokens

---

## CODE_REVIEW_RESULT

Produced by Code Reviewer agent on review completion.

```yaml
CODE_REVIEW_RESULT:
  schema_version: 1                    # integer, required — always 1
  decision: enum [PASS, FAIL, NEEDS_HUMAN]  # required
  issues: object[]                     # required (can be empty for PASS)
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      file: string                     # file path
      line: integer                    # optional — line number
      description: string              # what's wrong
      suggestion: string               # optional — how to fix
  pattern_proposals: object[]          # optional — patterns for CLAUDE.md
    - pattern: string
      file: string
      description: string
  summary: string                      # required — concise review summary
```

**Validation rules:**
- `schema_version` must equal `1`
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- When `decision=FAIL`: `issues` must contain at least one BLOCKING or HIGH severity item
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- `summary` must be present

---

## CONTEXT_KEEPER_STATE

Schema for `.supervisor/state.md` managed by Context-Keeper.

```yaml
version: integer                       # required — monotonic counter, increments on every write
current_phase: enum [INIT, ACQUIRE, PLAN, EXECUTE, FINALIZE, LOOP]  # required
session_id: string                     # required — unique session identifier
task_id: string                        # required — current task being worked on
task_title: string                     # optional — human-readable task description
branch: string                         # required after ACQUIRE — feature branch name
config:
  max_workers: integer                 # default 2
  mode: enum [parallel, sequential]    # default parallel
active_subtasks: object[]              # required during EXECUTE
  - id: string
    status: enum [pending, in_progress, completed, failed]
    worktree_path: string              # optional — only for parallel mode
    branch: string                     # optional — subtask branch
    agent_id: string                   # optional — Task agent ID
completed_subtasks: string[]           # subtask IDs that are done
failed_subtasks: string[]              # subtask IDs that failed
worktrees: object[]                    # active worktree tracking
  - task_id: string
    path: string
    branch: string
    status: enum [active, merged, cleaned, failed]
agents_running: object[]               # currently spawned agents
  - agent_type: string                 # e.g., "worker", "code-reviewer"
    task_id: string
    started_at: timestamp
last_updated: timestamp                # required — ISO 8601
```

**Validation rules:**
- `version` starts at 1 and monotonically increases on every write
- `current_phase` must be one of: `INIT`, `ACQUIRE`, `PLAN`, `EXECUTE`, `FINALIZE`, `LOOP`
- `last_updated` must be in ISO 8601 format
- `active_subtasks` required when `current_phase = EXECUTE`
- `branch` required after `ACQUIRE` phase (all subsequent phases)
- `session_id` and `task_id` must be non-empty strings

---

## Schema Versioning

All result schemas include `schema_version: 1`. This enables forward compatibility:

1. Hooks check `schema_version` before validating fields
2. If `schema_version` is unrecognized, hook warns but does not block
3. New fields can be added without breaking existing validation
4. Breaking changes require incrementing `schema_version`

## Validation Location

Schema validation occurs in the **hook execution layer**:
- Per-agent `SubagentStop` hooks (in agent frontmatter) validate Worker and Execute Manager results
- Cross-cutting `SubagentStop` hooks (in `hooks.json`) validate Code Reviewer and QA Executor results
- Validation is never duplicated in Supervisor or plugin runtime
