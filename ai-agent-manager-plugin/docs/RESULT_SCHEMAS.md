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
  status: enum [passed, failed, partial, skipped, needs_human]  # required — needs_human signals manual intervention required (e.g., app not running, dry-run failed)
  rounds_run: string                   # optional — e.g., "1/3"
  tests_generated: integer             # required — number of test files/cases generated
  tests_run_this_session: integer      # optional — v10.3.0: tests actually executed this agent session (may differ from tests_generated if --scope/--continue)
  tests_passed: integer                # required — number passing
  tests_failed: integer                # optional — number failing (default 0)
  depth: enum [smoke, functional]      # optional — v10.3.0: test depth used
  environment: enum [local, preview, staging] # optional — v10.3.0: environment classification from Phase 3
  discovery_confidence: enum [HIGH, MEDIUM, LOW]  # optional
  discovery_warnings: string[]         # optional — v10.3.0: non-blocking warnings (e.g., "crawl_limit_hit", "infrastructure_unavailable")
  coverage_estimate: float             # optional — 0.0 to 1.0, routes/APIs tested vs discovered
  coverage: string                     # optional — v10.3.0: human-readable e.g., "routes 12/15, apis 34/40"
  coverage_weighted: float             # optional — v10.3.0: risk-adjusted coverage 0.0-1.0
  risk_score: integer                  # optional — v10.3.0: 0-100 (higher = more untested critical areas)
  interaction_coverage: string         # optional — v10.3.0: e.g., "forms 6/8, tables 3/3, modals 2/2"
  infrastructure_available: string     # optional — v7.2.0: from Phase 1.5 (e.g., "email:mailpit" or "none")
  pre_existing_tests: integer          # optional — v7.2.0: count of pre-existing tests found
  pre_existing_passing: integer        # optional — v7.2.0: count passing
  pre_existing_failing: integer        # optional — v7.2.0: count failing
  pre_existing_bugs: object[]          # optional — v7.2.0: bugs found in pre-existing test failures
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      description: string
      file: string
  pre_existing_stale: object[]         # optional — v7.2.0: stale tests needing update
    - file: string
      reason: string
  gate_audit_verdict: string           # optional — v9.0.0: from Strategist Gate Audit (e.g., "pass" or "fail")
  app_topology: object                 # optional — v10.2.0: from Phase 4 auto-detection
    ui_present: boolean                #   has browser UI
    api_style: enum [rest, graphql, mixed, none]
    client_platform: enum [web, mobile, none]
  detected_auth_method: string         # optional — v10.2.0: e.g., "oauth:auth0", "session", "api-key", "none"
  websocket_detected: boolean          # optional — v10.2.0: true if WebSocket endpoints found
  risks: object[]                      # optional — identified risk areas
    - area: string
      level: enum [HIGH, MEDIUM, LOW]
      description: string
  bugs_found: integer                  # optional — COUNT of REAL_BUG failures (>= 0)
  bugs_blocking: integer               # optional — count of BLOCKING-severity bugs
  bugs: object[]                       # optional — detailed bug list (may be omitted if bugs_found is 0)
    - id: string
      severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      description: string
      file: string                     # optional — file where bug manifests
      steps: string                    # optional — reproduction steps
  discovery_gaps: object[]             # optional — v10.3.0: DISCOVERY_GAP test failures (test was wrong, not the app)
    - description: string
      file: string
  environment_issues: object[]         # optional — v10.3.0: ENVIRONMENT_ISSUE test failures (infra/setup problem, not the app)
    - description: string
      file: string
  strategist_verdict: string           # optional — approved/rejected from Strategist
  files_created: string[]              # optional — test and discovery files created
  summary: string                      # required — max 200 tokens
  notes: string                        # optional — v10.3.0: free-form notes (e.g., "budget_exceeded", "playwright_config_auto_generated")
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
  schema_version: 2                    # integer, required — bumped from 1 for category support
  decision: enum [PASS, FAIL, NEEDS_HUMAN]  # required
  issues: object[]                     # required (can be empty for PASS)
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      category: enum [new, pre_existing, nit]  # required — new in v2
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
- `schema_version` must equal `2` (v1 still accepted for backward compatibility)
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- When `decision=FAIL`: `issues` must contain at least one `new` issue with BLOCKING or HIGH severity
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- Each issue must include `category` (one of: `new`, `pre_existing`, `nit`)
- Only `new` issues with BLOCKING/HIGH severity can trigger FAIL
- `summary` must be present

---

## PLAN_REVIEW_RESULT

Produced by Plan Reviewer agent when validating a Supervisor-Ready Brief (Launch Pad Phase 5.5).

```yaml
PLAN_REVIEW_RESULT:
  schema_version: 1                    # integer, required
  decision: enum [PASS, FAIL, NEEDS_HUMAN]  # required
  issues: object[]                     # required (can be empty for PASS)
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      section: string                  # brief section name (e.g., "Subtask Structure", "File Impact Map")
      description: string              # what's wrong
      suggestion: string               # optional — how to fix
  summary: string                      # required — concise review summary
```

**Validation rules:**
- `schema_version` must equal `1`
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- When `decision=FAIL`: `issues` must contain at least one issue with BLOCKING or HIGH severity
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- `section` must reference a valid brief section name
- `summary` must be present

**Severity mapping for plan review:**
- BLOCKING: Missing/nonexistent file paths, missing required brief sections
- HIGH: Incorrect dependencies, unsafe parallelism (false LAUNCHABLE), logic errors
- MEDIUM: Vague acceptance criteria, missing skill references, incomplete risk assessment
- LOW: Style improvements, optional enhancements

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

## QA_SESSION

Schema for `.qa-session/plan.json` and `.qa-session/coverage.json` managed by QA Executor during session-based testing.

### plan.json

```yaml
QA_SESSION_PLAN:
  schema_version: 1                    # integer, required — always 1
  created: string                      # required — ISO date (YYYY-MM-DD)
  app_url: string                      # required — base URL of the application
  total_routes: integer                # required — total routes discovered
  total_apis: integer                  # required — total API endpoints discovered
  discovery_confidence: enum [HIGH, MEDIUM, LOW]  # required
  app_topology: object                 # optional — v10.2.0: from Phase 4 auto-detection
    ui_present: boolean
    api_style: enum [rest, graphql, mixed, none]
    client_platform: enum [web, mobile, none]
  auth_method: string                  # optional — v10.2.0: e.g., "oauth:auth0", "session"
  scopes: object[]                     # required — non-empty array of feature scopes
    - name: string                     # required — scope identifier (e.g., "auth", "tournaments")
      routes: string[]                 # required — route paths in this scope
      apis: string[]                   # required — API endpoints in this scope (e.g., "POST /api/auth/login")
      risk: enum [HIGH, MEDIUM, LOW]   # required — highest risk route in scope
      priority: integer                # required — 1 = highest priority
      status: enum [pending, in_progress, completed, failed, skipped]  # required
      estimated_tests: integer         # required — estimated test count for this scope
      completed_at: string             # optional — ISO timestamp when scope was completed
```

**Validation rules:**
- `schema_version` must equal `1`
- `scopes` must be non-empty array
- Each scope must have unique `name`
- `priority` must be unique across scopes
- `status` starts as `pending` for all scopes

### coverage.json

```yaml
QA_SESSION_COVERAGE:
  schema_version: 1                    # integer, required — always 1
  last_updated: string                 # required — ISO timestamp
  sessions_completed: integer          # required — number of scope sessions run
  routes_tested: integer               # required — cumulative unique routes tested
  routes_total: integer                # required — total routes in plan
  apis_tested: integer                 # required — cumulative unique APIs tested
  apis_total: integer                  # required — total APIs in plan
  scopes_completed: string[]           # required — list of completed scope names
  scopes_remaining: string[]           # required — list of pending scope names
```

**Validation rules:**
- `routes_tested` must be ≤ `routes_total`
- `apis_tested` must be ≤ `apis_total`
- `scopes_completed` + `scopes_remaining` must equal total scope count

### QA_RESULT Session Extensions

When QA Executor runs with `--plan`, `--scope`, or `--continue`, the QA_RESULT includes additional fields:

```yaml
# Additional fields in QA_RESULT for session mode:
  depth: enum [smoke, functional]      # required — test depth used
  scope: string                        # optional — scope name (null for --plan)
  session_id: string                   # optional — unique session identifier
  cumulative_coverage: object          # optional — from coverage.json
    routes_tested: integer
    routes_total: integer
    apis_tested: integer
    apis_total: integer
    scopes_completed: integer
    scopes_total: integer
```

---

## Schema Versioning

All result schemas include a `schema_version` field. This enables forward compatibility:

1. Hooks check `schema_version` before validating fields
2. If `schema_version` is unrecognized, hook warns but does not block
3. New fields can be added without breaking existing validation
4. Breaking changes require incrementing `schema_version`

### Version History

- **CODE_REVIEW_RESULT v2** (v7.0.0): Added `category` field to issues (`new`, `pre_existing`, `nit`). FAIL decisions now require at least one `new` HIGH/BLOCKING issue. Pre-existing issues are reported but do not block.
- **MISSING_FUNCTIONALITY_REPORT v1** (v7.1.0): New schema for QA Executor gap detection output.
- **QA_RESULT + QA_SESSION_PLAN** (v10.3.0): Added optional `app_topology`, `detected_auth_method`, `websocket_detected` (QA_RESULT) and `app_topology`, `auth_method` (QA_SESSION_PLAN). Backward compatible — existing payloads without these fields still validate.
- **QA_RESULT contract fixes** (v10.3.0): `status` enum expanded to include `needs_human` (matches executor/blueprint usage). `bugs_found` reclassified as integer count (was object[]); detailed bug records now live in new optional `bugs` field. `bugs_blocking` integer added. Added missing fields to formalize executor emissions: `tests_run_this_session`, `depth`, `environment`, `discovery_warnings`, `coverage`, `coverage_weighted`, `risk_score`, `interaction_coverage`, `discovery_gaps`, `environment_issues`, `notes`. Resolves prior doc/contract drift.
- **MISSING_FUNCTIONALITY_REPORT** (v10.3.0): `gaps` may be `[]` when analysis finds nothing. Emission is always required — absent block means Phase 4.5 was skipped.
- **GRAPHQL_RISK_OVERRIDES** (v10.3.0): New output contract emitted by QA Strategist in Strategy Mode when `api_style` is `graphql` or `mixed`.
- All other schemas remain at v1.

---

## MISSING_FUNCTIONALITY_REPORT

Produced by QA Executor during Phase 4.5 gap analysis. Separate from QA_RESULT.

```yaml
MISSING_FUNCTIONALITY_REPORT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — QA run identifier
  gaps: object[]                       # required — MAY be empty. An empty array with total_gaps: 0 is valid and means "analysis ran, no gaps found"
    - category: enum [missing_crud, missing_pagination, missing_search,
                      missing_validation, missing_error_handling, missing_confirmation,
                      missing_loading_state, missing_rate_limiting,
                      data_integrity_risk, security_boundary_gap, best_practice_gap]
      severity: enum [CRITICAL, HIGH, MEDIUM, LOW]
      location: string                 # route/endpoint/component where gap found
      description: string              # what's missing and why it matters
      evidence: string                 # what discovery data led to this conclusion
      recommendation: string           # what should be built/fixed
  summary: string                      # required — concise summary of all gaps
  total_gaps: integer                  # required — total gap count
  critical_count: integer              # required — CRITICAL gaps count
```

**Validation rules:**
- **Always emit the report** — even when `gaps` is empty. Absence of the block means Phase 4.5 was skipped (Strategist will reject).
- `gaps` MAY be `[]` (empty). When empty, `total_gaps` MUST be `0` and `critical_count` MUST be `0`.
- Each gap (when present) must have `category`, `severity`, `location`, `description`
- `total_gaps` must equal `gaps.length`
- `critical_count` must equal count of gaps with `severity=CRITICAL`
- `summary` must be present (e.g., "No gaps detected." for empty report)

**Example:**
```
MISSING_FUNCTIONALITY_REPORT:
  schema_version: 1
  task_id: qa-run-2026-03-22
  gaps:
    - category: missing_crud
      severity: HIGH
      location: POST /api/tournaments
      description: Tournament entity has create endpoint but no edit (PUT) or delete (DELETE)
      evidence: Discovery found POST /api/tournaments but no PUT or DELETE for same resource
      recommendation: Add PUT /api/tournaments/:id and DELETE /api/tournaments/:id endpoints
    - category: missing_rate_limiting
      severity: HIGH
      location: POST /api/auth/login
      description: Login endpoint has no rate limiting — brute force attack vector
      evidence: 5 rapid requests all returned 200 with no 429 response
      recommendation: Add rate limiting (max 5 attempts per minute per IP)
    - category: missing_pagination
      severity: MEDIUM
      location: GET /api/tournaments
      description: List endpoint returns all items with no pagination support
      evidence: No limit/offset/page query parameters detected in API calls
      recommendation: Add pagination with limit/offset or cursor-based approach
  summary: 3 gaps found (2 HIGH, 1 MEDIUM). Missing CRUD operations and rate limiting are highest priority.
  total_gaps: 3
  critical_count: 0
```

---

## GRAPHQL_RISK_OVERRIDES

Produced by QA Strategist in Strategy Mode **only when `api_style` is `graphql` or `mixed`**.
Consumed by QA Executor in Phase 7 write-back to persist per-operation risk into `discovery/api-calls.json`.

This is a markdown-table contract (not YAML) because it appears inline in the Strategist's textual output. The Executor parses it by header row match.

### Format

```markdown
### GraphQL Risk Overrides

| Operation | Method | Risk | Reason |
|---|---|---|---|
| createUser | MUTATION | HIGH | auth + data mutation |
| getUsers | QUERY | MEDIUM | (default) |
| deleteOrg | MUTATION | HIGH | destructive, admin-only |
| healthCheck | QUERY | LOW | no side effects |
```

### Validation Rules

- Heading must contain the literal text `GraphQL Risk Overrides` (case-insensitive)
- Table columns MUST be `Operation | Method | Risk | Reason` in this order
- Match key into `api-calls.json` is `Operation` + `Method` together (a query and mutation can share the same name — method disambiguates)
- `Method` values: `QUERY` | `MUTATION` (uppercase)
- `Risk` values: `HIGH` | `MEDIUM` | `LOW`
- `Reason` is free-form human-readable text (not parsed by machines)
- Block is **omitted entirely** when `api_style` is not `graphql`/`mixed` — absence is not an error
- If block is absent for a graphql app: Phase 5B default risks stand (no write-back performed)

### Write-back Behavior (Executor)

For each row in the table:
1. Match by `Operation` + `Method` against entries in `discovery/api-calls.json`
2. If row's `Risk` differs from entry's current `risk`: update the entry's `risk` field via Edit
3. If row has no matching entry: log warning, skip (Strategist may have hallucinated an operation)
4. Operations in `api-calls.json` not listed in the override table: keep existing Phase 5B default

Executor updates `api-calls.json` in-place; no separate overrides file is persisted.

---

## Validation Location

Schema validation occurs in the **hook execution layer**:
- Per-agent `SubagentStop` hooks (in agent frontmatter) validate Worker and Execute Manager results
- Cross-cutting `SubagentStop` hooks (in `hooks.json`) validate Code Reviewer and QA Executor results
- Validation is never duplicated in Supervisor or plugin runtime
