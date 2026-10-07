## QA_RESULT

Produced by QA Executor on test completion.

```yaml
QA_RESULT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — QA run identifier
  status: enum [passed, failed, partial, skipped, needs_human, plan_created, all_scopes_completed]  # required — needs_human signals manual intervention required (e.g., app not running, dry-run failed); plan_created and all_scopes_completed are session-mode statuses (--plan wrote plan.json without running tests; --continue found no pending scopes)
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
- **Hook-enforced (in addition to schema):** when tests were actually run (i.e. `tests_generated > 0`), `coverage_estimate` must be present. The SubagentStop hook for QA Executor enforces this conditional even though the field is otherwise optional.

---

