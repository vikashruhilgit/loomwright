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

## Risk Classification Rules

The Strategist classifies every discovered route and endpoint into one of three risk levels using evidence from source code analysis. Classification is never guesswork — it requires code-level evidence.

### HIGH Risk Indicators

Routes are HIGH risk when they involve authentication, authorization, data mutation on critical entities, payment flows, or core navigation.

**Auth decorators and guards:**
```
@UseGuards(AuthGuard)           # NestJS
requireAuth()                   # Express middleware
middleware: [auth]              # Next.js
withAuth(Component)             # React HOC
```

**Data mutation on critical entities:**
```
@Post('users')                  # User creation
@Delete('organizations/:id')   # Org deletion
router.put('/permissions')      # Permission changes
app.post('/api/orders')         # Order creation
```

**Payment and billing flows:**
```
/checkout, /payment, /billing   # URL patterns
stripe, paypal, braintree       # Payment provider imports
processPayment(), createCharge  # Function names
```

**Core navigation (auth-gated):**
```
/dashboard                      # Main app entry
/admin                          # Admin panel
/settings/security              # Security settings
```

### MEDIUM Risk Indicators

Routes are MEDIUM risk when they involve CRUD on non-critical entities, search/filter operations, or secondary features.

**CRUD on non-critical entities:**
```
@Get('products')                # Product listing
router.post('/comments')        # Comment creation
/api/tags                       # Tag management
```

**Search and filtering:**
```
/search, /filter, /browse       # URL patterns
?q=, ?page=, ?sort=             # Query parameters
```

**Secondary features:**
```
/settings/preferences           # Non-security settings
/notifications                  # Notification center
/profile/avatar                 # Profile customization
```

### LOW Risk Indicators

Routes are LOW risk when they are static, informational, or public with no side effects.

**Static and informational pages:**
```
/about, /faq, /help             # Info pages
/terms, /privacy                # Legal pages
/docs, /changelog               # Documentation
```

**Public marketing pages:**
```
/pricing                        # Pricing page (no transaction)
/features                       # Feature showcase
/blog/:slug                     # Blog posts (read-only)
```

### Classification Precedence

When a route matches multiple levels, the highest risk wins. For example, `/settings/billing` matches both "settings" (MEDIUM) and "billing" (HIGH) — it is classified HIGH.

---

## Audit Mode Details

When invoked with `--audit .qa-summary.md`, the Strategist switches to Audit Mode. This is how it works step by step.

### Step 1: Read Results

The Strategist reads three data sources:
- `.qa-summary.md` — compact summary from QA Executor (max 200 tokens)
- `discovery/discovery-map.json` — merged discovery map with route details and confidence
- Test result files in `e2e/test-results/` (if available)

### Step 2: Evaluate Coverage

For each risk level, the Strategist compares actual coverage against targets:
- Count routes tested vs routes discovered per risk level
- Check that every HIGH risk route has at least one test
- Verify no BLOCKING severity bugs exist

### Step 3: Compute Quality Score

```
quality_score = (coverage_weighted * 0.6) + (pass_rate * 0.3) + (discovery_confidence_numeric * 0.1)

Where:
  coverage_weighted = sum of (routes_tested / routes_discovered * weight) per risk level
  pass_rate = tests_passed / tests_run
  discovery_confidence_numeric: HIGH = 1.0, MEDIUM = 0.6, LOW = 0.3
```

### Step 4: Decide Verdict

**APPROVE if all of these are true:**
- Coverage meets or exceeds targets for HIGH risk routes (85%)
- Every HIGH risk route has at least one test
- No BLOCKING severity bugs
- Discovery confidence is not LOW (unless `--auto-discover` was used)

**REJECT if any of these are true:**
- Coverage below 85% target for HIGH risk routes
- Any HIGH risk route has zero tests
- A BLOCKING severity bug exists
- Discovery confidence is LOW (without `--auto-discover`)

### Step 5: Emit STRATEGIST_VERDICT

The verdict block contains these fields:

| Field | Description |
|-------|-------------|
| `round` | Current round / max rounds (e.g., 1/3) |
| `verdict` | `approved` or `rejected` |
| `coverage_achieved` | Routes and APIs tested vs discovered |
| `coverage_target` | The target percentage that was applied |
| `gaps` | Specific routes or endpoints missing coverage (or "none") |
| `blocking_bugs` | Count of BLOCKING severity bugs |
| `quality_score` | Computed score (0-100) |
| `rationale` | Human-readable explanation of the decision |

---

## Coverage Target Explanation

Coverage targets are risk-weighted, not flat percentages. This means HIGH risk areas must be tested more thoroughly than LOW risk areas.

### Targets Per Risk Level

| Risk Level | Coverage Target | Rationale |
|------------|----------------|-----------|
| HIGH | 85% | Auth, payment, and critical mutation flows must be well-covered |
| MEDIUM | 70% | Standard CRUD and secondary features need reasonable coverage |
| LOW | 50% | Static pages need basic smoke tests only |

### Weighted Coverage Score

The overall `coverage_weighted` score accounts for the importance of each risk level:

```
coverage_weighted =
  (high_routes_tested / high_routes_total * 0.5) +
  (medium_routes_tested / medium_routes_total * 0.3) +
  (low_routes_tested / low_routes_total * 0.2)
```

HIGH risk routes contribute 50% of the weighted score, MEDIUM contributes 30%, and LOW contributes 20%. This means missing a HIGH risk route has a much larger impact on the overall score than missing a LOW risk route.

### Example Calculation

Given: 4 HIGH routes (3 tested), 6 MEDIUM routes (5 tested), 5 LOW routes (3 tested):

```
coverage_weighted = (3/4 * 0.5) + (5/6 * 0.3) + (3/5 * 0.2)
                  = 0.375 + 0.25 + 0.12
                  = 0.745 (74.5%)
```

The Strategist would note that HIGH risk coverage is 75% (below the 85% target) and flag the gap.

---

## Examples

### Strategy Mode with Focus

```
/qa-strategist src/auth/ src/api/ --focus auth
```

Focuses analysis on authentication flows. The Strategist will:
1. Prioritize routes with auth decorators, guards, and middleware
2. Classify auth-adjacent routes (login, register, password reset, token refresh) as HIGH
3. Produce a strategy where auth-related routes appear first in the priority matrix

### Audit Mode — Rejected Verdict

```
/qa-strategist --audit .qa-summary.md
```

Example rejected output:

```
## STRATEGIST_VERDICT
- round: 1/3
- verdict: rejected
- coverage_achieved: routes 8/15, apis 12/23
- coverage_target: 85%
- gaps:
  - /auth/reset-password — HIGH risk, no tests generated
  - /api/users/:id/permissions — HIGH risk, no tests generated
  - /dashboard/settings — HIGH risk, tested but only happy path
- blocking_bugs: 1
- quality_score: 54
- rationale: Two HIGH risk routes have zero test coverage. One BLOCKING
  bug found (500 error on /auth/reset-password). HIGH risk coverage is
  60%, well below the 85% target. Executor must add tests for the missing
  HIGH risk routes and fix the blocking bug before resubmission.
```

### Multi-Focus Analysis

```
/qa-strategist src/ --focus api
```

When focused on API, the Strategist:
1. Scans for controller decorators, route handlers, and OpenAPI specs
2. Classifies API endpoints by HTTP method and entity criticality
3. Weights POST/PUT/DELETE endpoints higher than GET-only endpoints
4. Produces API-specific coverage targets and test priority matrix

---

## Integration with QA Executor

The QA Strategist and QA Executor work together through a debate loop protocol.

### The Debate Loop

```
QA Executor                          QA Strategist
    |                                      |
    |--- Phase 2: Discovery ------------->|
    |                                      |
    |--- Phase 3: Request Strategy ------>|
    |    (spawn as blocking subagent)      |
    |<-- Risk classification + targets ---|
    |                                      |
    |--- Phase 4-7: Generate + Execute -->|
    |                                      |
    |--- Phase 8: Request Audit --------->|
    |    (spawn as blocking subagent)      |
    |<-- STRATEGIST_VERDICT --------------|
    |                                      |
    |--- If rejected: fix gaps + re-audit |
    |    (L2+ only, L1 = 1 round)         |
```

### Key Integration Points

1. **Strategy Phase:** Executor spawns Strategist as a blocking Task subagent. Strategist reads discovery data and returns risk classification. Executor parses this to drive test generation priorities.

2. **Audit Phase:** After test execution, Executor writes `.qa-summary.md` and spawns Strategist again in Audit Mode. Strategist reads the summary, evaluates coverage against targets, and emits STRATEGIST_VERDICT.

3. **Verdict Handling:** If the Strategist approves, the Executor sets `status: passed`. If rejected, the Executor sets `status: failed` (at L1, only 1 round is allowed, so no retry).

4. **Strategist Authority:** On conflict, the Strategist verdict wins. If the Strategist says coverage is insufficient, the Executor cannot override this.

---

## Troubleshooting

### "No routes discovered"

**Cause:** The Strategist could not find route definitions in the source code.

**Solutions:**
- Ensure CLAUDE.md documents the routing framework (Next.js App Router, React Router, NestJS controllers, Express routes)
- Provide a `target` directory that contains route files: `/qa-strategist src/app/` or `/qa-strategist src/controllers/`
- Check that route files follow standard patterns the Strategist greps for (page.tsx, @Controller, app.get, etc.)
- If using a non-standard routing framework, document the pattern in CLAUDE.md

### "Low confidence classification"

**Cause:** Source code is ambiguous — routes exist but risk signals are unclear.

**Solutions:**
- Add auth decorators/guards explicitly to route handlers instead of relying on global middleware
- Use descriptive route names that indicate purpose (/admin/users vs /page-7)
- Ensure CLAUDE.md documents the auth model and critical entities
- Run with `--focus` to narrow the analysis scope

### "Verdict rejected — what to do next"

**At Level 1 (single round):**
1. Read the `gaps` field in STRATEGIST_VERDICT to see which routes need tests
2. Read the `blocking_bugs` count to see critical failures
3. Address gaps manually or re-run `/qa-executor` after fixing underlying issues
4. Run `/qa-strategist --audit .qa-summary.md` again to re-evaluate

**Common rejection reasons and fixes:**
- **HIGH risk route with no tests:** The Executor failed to generate tests for a critical route. Check if the route requires authentication that was not available during discovery.
- **Coverage below target:** Not enough tests for HIGH risk area. Add more test scenarios or ensure discovery found all routes.
- **Blocking bug exists:** A test failure indicates a serious issue (500 error, auth bypass). Fix the application bug first, then re-run QA.

### "Strategist crashes or times out"

**Cause:** The Strategist subagent exceeded its turn limit or encountered an error.

**Solutions:**
- Check that `.qa-summary.md` exists and is under 200 tokens
- Verify `discovery/discovery-map.json` is valid JSON
- Re-run `/qa-executor` which will re-spawn the Strategist
- As a workaround, use `/qa-executor --skip-strategy` to bypass the Strategist entirely

---

## See Also

- `/qa-executor` — Discover, generate, and run Playwright tests
- `/code-reviewer` — Review code changes
- `/agent-help` — List all commands
