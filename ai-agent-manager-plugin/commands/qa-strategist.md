---
description: Plan risk-based QA test strategy and audit QA Executor results
---

# Command: /qa-strategist

## Usage

```
/qa-strategist [target] [--audit .qa-summary.md] [--focus auth|api|ui|all]
```

## Parameters

- **target** (optional): Directory or files to analyze for risk classification
  - Example: `/qa-strategist src/`
  - Example: `/qa-strategist src/auth/ src/dashboard/`
  - If omitted, analyzes entire project from CLAUDE.md

- **--audit** (optional): Path to .qa-summary.md for audit mode
  - Example: `/qa-strategist --audit .qa-summary.md`
  - Switches to Audit Mode — reviews Executor results and emits STRATEGIST_VERDICT

- **--focus** (optional): Focus area for risk classification
  - `auth` — Prioritize authentication and authorization flows
  - `api` — Prioritize API endpoints and contracts
  - `ui` — Prioritize UI routes and user-facing flows
  - `all` — Analyze everything (default)

## What This Does

### Strategy Mode (default)

1. **Reads project context** from CLAUDE.md and source code
2. **Discovers routes and endpoints** via static analysis (Glob/Grep)
3. **Classifies risk levels** (HIGH/MEDIUM/LOW) based on:
   - Auth-gated routes (HIGH)
   - Data mutation endpoints (HIGH)
   - Payment/billing flows (HIGH)
   - CRUD operations (MEDIUM)
   - Static/informational pages (LOW)
4. **Sets coverage targets** per risk level (HIGH: 85%, MEDIUM: 70%, LOW: 50%)
5. **Produces test priority matrix** ordered by risk

### Audit Mode (--audit flag)

1. **Reads QA Executor summary** (.qa-summary.md)
2. **Evaluates coverage** against risk-based targets
3. **Checks for blocking bugs** and discovery confidence
4. **Emits STRATEGIST_VERDICT** (approved/rejected with rationale)

## Example Output (Strategy Mode)

```
## QA Strategy

### Project Context
- Tech Stack: Next.js 14 + NestJS API
- Auth Model: JWT with refresh tokens
- Routes Discovered: 15
- API Endpoints: 23

### Risk Classification

| Route/Endpoint | Risk | Reason |
|---|---|---|
| /auth/login | HIGH | Auth flow |
| /auth/register | HIGH | Auth + data mutation |
| /dashboard | HIGH | Core nav, auth-gated |
| /api/users | MEDIUM | CRUD operations |
| /about | LOW | Static page |

### Coverage Targets
- HIGH risk (5 routes): 85%+ coverage
- MEDIUM risk (7 routes): 70% coverage
- LOW risk (3 routes): 50% coverage

### Test Priority Matrix
1. /auth/login — HIGH — Auth flow
2. /auth/register — HIGH — User creation
3. /dashboard — HIGH — Core navigation
...
```

## Example Output (Audit Mode)

```
## STRATEGIST_VERDICT
- round: 1/3
- verdict: approved
- coverage_achieved: routes 12/15, apis 18/23
- coverage_target: 85%
- gaps: none
- blocking_bugs: 0
- quality_score: 82
- rationale: All HIGH risk routes covered. Coverage exceeds targets.
```

## Prerequisites

- Project with CLAUDE.md (for context)
- Source code accessible (routes, controllers)
- For audit mode: .qa-summary.md from QA Executor

## See Also

- `/qa-executor` — Discover, generate, and run Playwright tests
- `/code-reviewer` — Review code changes
- `/agent-help` — List all commands
