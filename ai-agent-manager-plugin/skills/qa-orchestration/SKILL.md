---
name: qa-orchestration
description: Session management for large-app QA testing. Covers plan.json schema, coverage.json schema, scope clustering, and multi-session workflow patterns.
allowed-tools: [Read, Write, Glob, Grep, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# QA Orchestration Skill

Session management patterns for testing large applications across multiple QA Executor sessions. Enables `--plan`, `--scope`, and `--continue` workflows.

---

## 1. Quick Reference

```bash
# Survey app and create plan
/qa-executor --plan

# Test one feature area
/qa-executor --scope feature:auth

# Auto-pick next pending scope
/qa-executor --continue

# Scope with smoke depth
/qa-executor --scope feature:settings --depth smoke
```

---

## 2. Session Directory Structure

```
.qa-session/
├── plan.json          # Feature scopes with priority, status, route/API lists
├── coverage.json      # Cumulative coverage across sessions
└── results/           # Per-scope QA_RESULT files
    ├── auth.json      # Result from testing auth scope
    ├── tournaments.json
    └── ...
```

All session files are project-local. Add `.qa-session/` to `.gitignore`.

---

## 3. plan.json Schema

```json
{
  "schema_version": 1,
  "created": "2026-03-20",
  "app_url": "http://localhost:3000",
  "total_routes": 89,
  "total_apis": 230,
  "discovery_confidence": "HIGH",
  "scopes": [
    {
      "name": "auth",
      "routes": ["/auth/login", "/auth/register", "/auth/forgot-password"],
      "apis": ["POST /api/auth/login", "POST /api/auth/register", "POST /api/auth/forgot-password"],
      "risk": "HIGH",
      "priority": 1,
      "status": "pending",
      "estimated_tests": 18,
      "completed_at": null
    },
    {
      "name": "tournaments",
      "routes": ["/tournaments", "/tournaments/[id]", "/tournaments/create"],
      "apis": ["GET /api/tournaments", "POST /api/tournaments", "PUT /api/tournaments/:id", "DELETE /api/tournaments/:id"],
      "risk": "HIGH",
      "priority": 2,
      "status": "pending",
      "estimated_tests": 22,
      "completed_at": null
    }
  ]
}
```

---

## 4. coverage.json Schema

```json
{
  "schema_version": 1,
  "last_updated": "2026-03-20T11:00:00Z",
  "sessions_completed": 3,
  "routes_tested": 28,
  "routes_total": 89,
  "apis_tested": 45,
  "apis_total": 230,
  "scopes_completed": ["auth", "tournaments", "leagues"],
  "scopes_remaining": ["organizations", "browse", "courts", "members", "settings"]
}
```

**Update rules:**
- After each `--scope` or `--continue` run, merge new coverage into cumulative totals
- `routes_tested` and `apis_tested` are unique counts (deduplicated across scopes)
- `scopes_completed` moves from `scopes_remaining` when scope status becomes `completed`

---

## 5. Scope Clustering Algorithm

When `--plan` runs, routes are clustered into feature areas:

### Step 1: Group by URL prefix

```
/auth/login         → auth
/auth/register      → auth
/tournaments        → tournaments
/tournaments/[id]   → tournaments
/tournaments/create → tournaments
/settings           → settings
/about              → about
```

**Rules:**
- Use the first significant path segment (skip empty root)
- API endpoints grouped by the same prefix: `/api/auth/*` → "auth"
- Dynamic segments (`[id]`, `:id`) are ignored for grouping

### Step 2: Merge small groups

If a group has only 1 route and no APIs, merge into nearest related group or "misc".

### Step 3: Assign risk per scope

Scope risk = highest risk route within the scope.
- If any route in scope is HIGH → scope is HIGH
- Else if any is MEDIUM → scope is MEDIUM
- Else → scope is LOW

### Step 4: Assign priority

1. Sort by risk (HIGH first)
2. Within same risk, sort by route count descending (more routes = higher priority)
3. Assign sequential priority numbers starting from 1

### Step 5: Estimate test count

Per scope, estimate based on discovery data:

| Element | Estimated tests |
|---|---|
| Each route (base) | 2 |
| Each form discovered | +3 (valid, invalid, empty fields) |
| Each API POST/PUT endpoint | +2 (valid payload, auth check) |
| Each API DELETE endpoint | +2 (delete, verify gone) |
| Each API GET endpoint | +1 (response validation) |
| Each modal | +1 (open, interact, close) |
| Each table/list | +1 (data rendering check) |

---

## 6. Session Workflow Patterns

### Full plan-and-execute

```
Session 1: /qa-executor --plan
  → Creates .qa-session/plan.json (12 scopes)
  → Prints scope table
  → No tests run

Session 2: /qa-executor --scope feature:auth
  → Deep runtime crawl: launches browser, visits every scope route,
    discovers forms/buttons/tables/APIs, overrides plan's static data
  → Generates and runs tests with functional depth
  → Updates plan.json: auth status → "completed"
  → Updates coverage.json: routes 6/89, apis 6/230

Session 3: /qa-executor --continue
  → Picks tournaments (priority 2, pending)
  → Tests tournaments deeply
  → Updates plan.json: tournaments status → "completed"
  → Updates coverage.json: routes 16/89, apis 16/230

Session 4-N: /qa-executor --continue
  → Picks next pending scope each time
  → Eventually: all_scopes_completed
```

### Targeted scope testing

```
/qa-executor --plan
/qa-executor --scope feature:auth --depth functional
/qa-executor --scope feature:payments --depth functional
# Skip low-priority scopes
```

### Re-run a failed scope

If a scope fails (tests fail, budget exceeded):
1. Scope status is set to `failed` in plan.json
2. Re-run: `/qa-executor --scope feature:{name}` (will reset to in_progress)
3. Previous results in `.qa-session/results/{name}.json` are overwritten

---

## 7. Integration with QA Executor Phases

| QA Executor Phase | --plan | --scope | --continue |
|---|---|---|---|
| Phase 0 (Environment) | Yes | Yes | Yes |
| Phase 0.5 (Session) | Creates plan | Reads plan, filters | Reads plan, picks next |
| Phase 1 (Detect URL) | Yes | Yes | Yes |
| Phase 2 (Discovery) | Full (100 pages) | Reuse plan data | Reuse plan data |
| Phase 3 (Strategy) | Skip | Scoped subset | Scoped subset |
| Phase 4 (Generate) | Skip | Scoped routes | Scoped routes |
| Phase 4.5-9 | Skip | Yes | Yes |

---

## 8. Error Handling

| Error | Action |
|---|---|
| `--scope` without plan | Error: "No plan found. Run /qa-executor --plan first" |
| Unknown scope name | Error: "Scope '{name}' not found in plan" |
| `--continue` with no pending | Status: all_scopes_completed |
| Scope already completed | Re-run (overwrites previous results) |
| Budget exceeded mid-scope | Mark scope as "failed", save partial results |
| Plan file corrupted | Error: "Invalid plan.json. Re-run /qa-executor --plan" |

---

## Quality Checklist

Before creating or updating session state:
- [ ] plan.json has valid schema_version: 1
- [ ] All scopes have unique names and priorities
- [ ] coverage.json routes/apis counts are cumulative (not per-session)
- [ ] Completed scopes are moved from remaining to completed
- [ ] Per-scope results saved to .qa-session/results/{name}.json
- [ ] Plan status transitions: pending → in_progress → completed/failed

---

## See Also

- `skills/qa-strategy/SKILL.md` — Risk classification and coverage targets
- `skills/playwright-e2e/SKILL.md` — Test authoring patterns (including interaction patterns)
- `docs/RESULT_SCHEMAS.md` — QA_SESSION schema definitions
