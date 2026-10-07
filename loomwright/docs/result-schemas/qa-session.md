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

