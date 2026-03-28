---
description: Discover app structure, generate and run Playwright tests with risk-based strategy
---

# Command: /qa-executor

## Subagent Enforcement

**When `/qa-executor` is invoked, you MUST spawn the QA Executor agent via Task tool:**

```
Task(
  description: "QA Executor: {flags and context}",
  prompt: "{user flags, project context, and any --scope/--continue/--plan details}",
  subagent_type: "ai-agent-manager-plugin:ai-agent-manager-plugin:qa-executor"
)
```

**DO NOT** attempt to execute the QA Executor protocol yourself.
**DO NOT** delegate discovery to Explore agents.
**DO NOT** cherry-pick phases from the protocol.

The QA Executor agent has its own tools, budget tracking, phase protocol, and Playwright access.
Only the QA Executor subagent can run browsers for discovery, generate tests, and emit QA_RESULT.

---

## Usage

```
/qa-executor [--depth smoke|functional] [--url http://...] [--rounds 1|2|3] [--coverage 80] [--skip-strategy] [--strict-discovery] [--auto-discover] [--plan] [--scope feature:{name}] [--continue]
```

## Parameters

- **--depth** (optional): Test generation depth (default: `functional`)
  - `smoke` — Navigate + verify visible (original L1 behavior). Quick CI sanity check.
  - `functional` — Discovery-driven test generation. Fills forms, tests CRUD, clicks buttons, verifies data rendering. Uses the Test Pattern Library to match discovered interactions to test patterns.

- **--url** (optional): Override base URL for the application
  - Example: `/qa-executor --url http://localhost:3000`
  - If omitted, detects from playwright.config.ts or .env

- **--rounds** (optional): Max debate rounds with QA Strategist (default: 1 for L1)
  - `1` — Single audit round (Level 1 default)
  - `2` or `3` — Multiple rounds (Level 2+)

- **--coverage** (optional): Override coverage target percentage (default: risk-based)
  - Example: `/qa-executor --coverage 90`
  - Overrides the risk-based targets (HIGH: 85%, MEDIUM: 70%, LOW: 50%)

- **--skip-strategy** (optional): Skip QA Strategist, use default risk classification
  - All routes classified as MEDIUM, 70% target
  - Useful for quick runs or when Strategist is not needed

- **--strict-discovery** (optional): Always require human approval of discovery results
  - Even HIGH confidence maps require approval before test generation

- **--auto-discover** (optional): Proceed even on LOW confidence discovery
  - Skips the halt-and-confirm gate for low confidence

- **--plan** (optional): Survey app and create testing plan without running tests
  - Runs discovery (100-page crawl limit), clusters routes into feature scopes
  - Writes `.qa-session/plan.json` with scopes, priorities, and estimated test counts
  - Prints human-readable scope summary table

- **--scope feature:{name}** (optional): Test one feature area deeply
  - Reads `.qa-session/plan.json` (run `--plan` first)
  - Filters to only that scope's routes/APIs
  - Runs functional-depth tests for the scoped subset
  - Updates cumulative coverage in `.qa-session/coverage.json`
  - Example: `/qa-executor --scope feature:auth`

- **--continue** (optional): Auto-pick next pending scope from plan
  - Reads `.qa-session/plan.json`, finds first pending scope by priority
  - Equivalent to `--scope feature:{next-pending-scope}`

**Note:** `--plan`, `--scope`, and `--continue` are mutually exclusive. They can be combined with `--depth`.

## What This Does

1. **Detects target URL** from Playwright config, .env, or --url flag
2. **Probes for test infrastructure** (Phase 1.5) — email capture (Mailpit/MailHog), mock servers
3. **Runs 4-phase discovery** (enhanced with interaction data):
   - Static analysis (routes from source code)
   - Runtime crawl (DOM + network + a11y + **forms, buttons, tables, modals, API body fields**)
   - Selective vision (screenshots for complex pages only)
   - Merge & gate (confidence scoring, discovery report)
4. **Triages pre-existing tests** (Phase 2.5) — runs existing tests, classifies failures as real bugs vs stale tests
5. **Gets risk strategy** from QA Strategist (or uses defaults with --skip-strategy)
6. **Generates Playwright tests** using discovery-driven Test Pattern Library:
   - **Functional depth (default):** Form submissions, CRUD operations, button clicks, modal interactions, data rendering, API body validation, **auth linear chains**, **boundary tests**, **email flow tests** (if infrastructure available)
   - **Smoke depth:** Navigate + verify visible (quick CI sanity)
   - All tests use role-based locators and regex assertions
7. **Self-checks generated tests** (Phase 4.7) — validates assertion quality, auth state verification, cleanup hooks, boundary tests, gap report readiness
8. **Executes tests** via `npx playwright test --reporter=json`
9. **Tracks coverage** (routes, APIs, and **interactions** discovered vs tested)
10. **Reports bugs** for failures (severity: BLOCKING/HIGH/MEDIUM/LOW)
11. **Runs Strategist audit** (1 round for L1) -> approved/rejected with structural completeness checks
12. **Emits QA_RESULT** with complete status including infrastructure, pre-existing test triage, and self-check results

## Requirements

- **playwright.config.ts** (or .js) must exist in project
- **Application must be running** at the detected base URL
- **npx** must be available (Node.js installed)
- **Playwright browsers** installed (`npx playwright install`)

## Example Output

### Default run (functional depth)

```
## QA_RESULT
- task_id: qa-run-001
- status: passed
- depth: functional
- rounds_run: 1/1
- tests_generated: 42
- tests_run_this_session: 42
- tests_passed: 39
- tests_failed: 3
- discovery_confidence: HIGH
- discovery_duration_seconds: 15
- crawl_limit_hit: false
- discovery_warnings: []
- coverage: routes 12/15, apis 18/23
- coverage_weighted: 82%
- risk_score: 18
- bugs_found: 3
- bugs_blocking: 0
- strategist_verdict: approved
- files_created: [discovery/*, e2e/tests/frontend/*.spec.ts, e2e/tests/api/*.spec.ts]
- error: none
- notes: Functional tests include 8 form submissions, 4 API CRUD flows, 3 data rendering checks. 3 MEDIUM bugs.
```

### Plan mode output

```
## QA_RESULT
- task_id: qa-plan-001
- status: plan_created
- depth: functional
- tests_generated: 0
- scope: null
- notes: Plan created with 12 scopes. Next: /qa-executor --scope feature:auth

QA Plan for Sports Management Platform
=======================================
12 scopes | 89 routes | 230 APIs

Priority  Scope           Risk    Routes  APIs  Est. Tests  Status
────────  ──────────────  ──────  ──────  ────  ──────────  ───────
1         auth            HIGH    3       3     18          pending
2         orders     HIGH    4       4     22          pending
3         reports         HIGH    3       3     15          pending
4         organizations   MEDIUM  8       12    20          pending
5         browse          MEDIUM  3       3     8           pending
...

Next: /qa-executor --scope feature:auth
Auto: /qa-executor --continue
```

### Scoped run output

```
## QA_RESULT
- task_id: qa-scope-auth-001
- status: passed
- depth: functional
- tests_generated: 18
- tests_run_this_session: 18
- tests_passed: 17
- tests_failed: 1
- scope: auth
- session_id: qa-session-2026-03-20
- cumulative_coverage: routes 6/89, apis 6/230, scopes 1/12
- strategist_verdict: approved
```

## Generated Files

```
discovery/
  crawl.ts                  # Playwright crawler script
  static-map.json           # Routes from static analysis
  sitemap.json              # Routes from runtime crawl (enriched: forms, buttons, tables, modals)
  api-calls.json            # Intercepted API calls (enriched: request/response body fields)
  seed-data.json            # Entity counts and sample IDs
  infrastructure.json       # Test infrastructure (email capture, mock servers) from Phase 1.5
  discovery-map.json        # Merged discovery map
  report.md                 # Human-readable discovery report

e2e/tests/frontend/
  {feature}.spec.ts         # UI/E2E tests per feature (5-10 tests per file in functional mode)

e2e/tests/api/
  {feature}.spec.ts         # API tests per feature (CRUD patterns in functional mode)

.qa-summary.md              # Summary for Strategist audit

# Session files (only with --plan/--scope/--continue):
.qa-session/
  plan.json                 # Feature scopes with priority and status
  coverage.json             # Cumulative coverage across sessions
  results/{scope}.json      # Per-scope QA_RESULT files
```

## Common Workflows

### Default run (functional depth)
```
/qa-executor
```
Generates tests that fill forms, test CRUD via API, click buttons, verify data rendering. This is the default.

### Quick smoke run (CI sanity)
```
/qa-executor --depth smoke
```
Generates navigate-and-verify tests only. Fast, shallow.

### Quick QA run (skip strategy)
```
/qa-executor --skip-strategy
```

### Full QA with strict discovery
```
/qa-executor --strict-discovery
```

### QA against preview deployment
```
/qa-executor --url https://my-app-preview.vercel.app
```

### QA with higher coverage target
```
/qa-executor --coverage 90
```

### Large app: plan, then test by scope
```
/qa-executor --plan                        # Survey app, create plan (no tests)
/qa-executor --scope feature:auth          # Test auth deeply
/qa-executor --scope feature:orders   # Test orders deeply
/qa-executor --continue                    # Auto-pick next pending scope
/qa-executor --continue                    # ...and the next
```

### Scope with smoke depth
```
/qa-executor --scope feature:settings --depth smoke
```

## Discovery Engine Details

The QA Executor uses a 4-phase discovery engine to understand the application before generating any tests. Each phase builds on the previous one.

### Phase A: Static Analysis

Scans source code for route definitions without running the application.

**What it greps for:**
- **Next.js App Router:** `app/**/page.{ts,tsx}` — each page file is a route
- **Next.js Pages Router:** `pages/**/*.{ts,tsx}` — file-based routing
- **React Router:** `<Route path=`, `createBrowserRouter`, `createRoutesFromElements`
- **NestJS:** `@Controller`, `@Get`, `@Post`, `@Put`, `@Delete`, `@Patch` decorators
- **Express:** `app.get(`, `app.post(`, `router.get(`, `router.post(`
- **OpenAPI/Swagger:** `openapi.json`, `swagger.json` — full API inventory
- **Auth patterns:** `@UseGuards`, `requireAuth`, `middleware: [auth]`, `withAuth`

**Output:** `discovery/static-map.json` containing route paths, HTTP methods, and auth indicators.

### Phase B: Runtime Crawl

Launches a Playwright browser and crawls the running application.

**What Playwright extracts per page:**
- **DOM:** Links (`<a href>`), forms (`<form action>`), buttons, inputs
- **Network:** All XHR/fetch requests intercepted via `page.on('request')` — captures API endpoints the frontend actually calls
- **Accessibility tree:** `page.accessibility.snapshot()` for semantic page structure
- **Console errors:** `page.on('console')` captures runtime warnings and errors
- **Modals:** Detects `[role="dialog"]`, `.modal`, `[aria-modal="true"]`
- **SPA navigation:** Monitors `framenavigated` events and `pushState`/`replaceState` for client-side routing

**Crawl behavior:**
- Starts from baseURL, follows links breadth-first
- Two passes: Pass 1 unauthenticated, Pass 2 authenticated (if auth-gated routes detected)
- Safe-click policy: skips delete, remove, logout, purchase, and pay buttons
- Records entity counts from GET list responses for seed data inventory

**Output:** `discovery/sitemap.json` (runtime routes), `discovery/api-calls.json` (intercepted APIs), `discovery/seed-data.json` (entity counts and sample IDs).

### Phase C: Selective Vision

Takes screenshots of complex pages that need visual inspection. Targets 10-20% of pages (max 10).

**When screenshots trigger:**
- Pages with more than 5 form inputs
- Pages where modals were detected during crawl
- Pages with console errors
- Pages with complex interactive elements (tables, charts, drag-and-drop)

If all pages are simple (few inputs, no errors, no modals), this phase is skipped entirely. Under budget pressure (YELLOW zone, 36+ tool calls), this phase is always skipped.

### Phase D: Merge and Gate

Combines static analysis and runtime crawl results, then computes confidence.

**Confidence scoring algorithm:**
```
overlap = routes found in BOTH static and runtime
static_only = routes in static but NOT runtime (UNVERIFIED_STATIC)
runtime_only = routes in runtime but NOT static (UNDOCUMENTED)

confidence_score = overlap / (overlap + static_only + runtime_only)

Thresholds:
  >= 0.7 → HIGH confidence (proceed automatically)
  0.4 - 0.7 → MEDIUM confidence (proceed, log note)
  < 0.4 → LOW confidence (halt unless --auto-discover)
```

**Flags generated:**
- `UNVERIFIED_STATIC` — route found in code but not during crawl (may be behind feature flag or auth)
- `UNDOCUMENTED_API` — API intercepted at runtime but not in OpenAPI spec
- `SEED_DATA_MISSING` — entity count is 0 for a route that requires data

**Output:** `discovery/discovery-map.json` (final merged map), `discovery/report.md` (human-readable summary).

---

## Test Generation Patterns

Tests are generated based on **depth mode** and **risk level**. All tests follow the playwright-e2e skill patterns.

### Smoke Depth (`--depth smoke`)

Smoke tests verify pages load and key elements are visible. Same as original L1 behavior.

```typescript
test.describe('Login', () => {
  // @covers-route: /auth/login
  test('should display login form', async ({ page }) => {
    await page.goto('/auth/login');
    await expect(page.getByRole('heading', { name: /log in|sign in/i })).toBeVisible();
  });
});
```

### Functional Depth (default)

Functional tests exercise **discovered interactions** — forms, CRUD, buttons, modals, data rendering.

#### HIGH Risk Route with Form (functional)

```typescript
test.describe('Login', () => {
  // @covers-route: /auth/login
  // @covers-interaction: form-submission

  test('should submit login form with valid credentials', async ({ page }) => {
    await page.goto('/auth/login');
    await page.getByLabel(/email/i).fill('user@example.com');
    await page.getByLabel(/password/i).fill('ValidPass123!');
    await page.getByRole('button', { name: /log in|sign in/i }).click();
    await expect(page).toHaveURL(/dashboard/);
  });

  // @covers-interaction: validation-error
  test('should show validation error for invalid email', async ({ page }) => {
    await page.goto('/auth/login');
    await page.getByLabel(/email/i).fill('not-an-email');
    await page.getByLabel(/password/i).fill('password');
    await page.getByRole('button', { name: /log in|sign in/i }).click();
    await expect(page.getByText(/invalid|error|incorrect/i)).toBeVisible();
  });

  test('should show error for empty required fields', async ({ page }) => {
    await page.goto('/auth/login');
    await page.getByRole('button', { name: /log in|sign in/i }).click();
    await expect(page.getByText(/required|cannot be empty/i)).toBeVisible();
  });
});
```

#### API CRUD Tests (functional)

```typescript
test.describe('Items API', () => {
  const uniqueName = `test-item-${Date.now()}`;
  let createdId: string;

  // @covers-api: POST /api/items
  // @covers-interaction: api-post
  test('should create item with valid data', async ({ request }) => {
    const response = await request.post('/api/items', {
      data: { name: uniqueName, price: 29.99, category: 'test' },
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(typeof body.id).toBe('string');
    expect(body.id.length).toBeGreaterThan(0);
    expect(body.name).toBe(uniqueName);
    expect(body.price).toBe(29.99);
    createdId = body.id;
  });

  // @covers-api: GET /api/items/:id
  // @covers-interaction: api-get
  test('should get item by ID', async ({ request }) => {
    const response = await request.get(`/api/items/${createdId}`);
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.name).toBe(uniqueName);
    expect(body.price).toBe(29.99);
  });

  // @covers-api: PUT /api/items/:id
  // @covers-interaction: api-put
  test('should update item', async ({ request }) => {
    const response = await request.put(`/api/items/${createdId}`, {
      data: { name: `${uniqueName}-updated` },
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.name).toBe(`${uniqueName}-updated`);

    // State verification: confirm update persisted
    const verify = await request.get(`/api/items/${createdId}`);
    expect((await verify.json()).name).toBe(`${uniqueName}-updated`);
  });

  // @covers-api: DELETE /api/items/:id
  // @covers-interaction: api-delete
  test('should delete item and verify gone', async ({ request }) => {
    const del = await request.delete(`/api/items/${createdId}`);
    const delStatus = del.status();
    expect(delStatus === 200 || delStatus === 204).toBe(true);
    const get = await request.get(`/api/items/${createdId}`);
    expect(get.status()).toBe(404);
  });

  // @covers-interaction: negative-test
  test('should reject empty body', async ({ request }) => {
    const response = await request.post('/api/items', { data: {} });
    expect(response.status()).toBe(400); // NOT 500
  });

  // @covers-interaction: negative-test
  test('should reject missing required field', async ({ request }) => {
    const response = await request.post('/api/items', {
      data: { price: 10 }, // missing 'name'
    });
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(JSON.stringify(body)).toMatch(/name/i);
  });
});
```

#### Data Rendering Test (functional)

```typescript
test.describe('Item List', () => {
  // @covers-route: /orders
  // @covers-interaction: data-rendering
  test('should render data table with data', async ({ page }) => {
    await page.goto('/orders');
    const table = page.getByRole('table');
    await expect(table).toBeVisible();
    // Verify column headers from discovery
    await expect(page.getByRole('columnheader', { name: /name/i })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: /date/i })).toBeVisible();
    // Verify at least one row of data renders
    const rows = table.getByRole('row');
    await expect(rows).toHaveCount(/.+/); // at least header + 1 data row
  });
});
```

### Locator Patterns

All generated tests use role-based locators (never CSS selectors):

| Pattern | Example |
|---------|---------|
| `getByRole` | `page.getByRole('button', { name: /submit/i })` |
| `getByLabel` | `page.getByLabel(/email/i)` |
| `getByText` | `page.getByText(/welcome/i)` |
| `getByPlaceholder` | `page.getByPlaceholder(/search/i)` |

### Assertion Patterns

Assertions use regex for resilience against minor text changes:

| Pattern | Example |
|---------|---------|
| Text matching | `expect(el).toHaveText(/welcome/i)` |
| Visibility | `expect(el).toBeVisible()` |
| URL navigation | `expect(page).toHaveURL(/dashboard/)` |
| Response status | `expect(response.status()).toBe(200)` |

---

## Crawl Limits

The runtime crawl operates within strict bounds to prevent runaway execution.

| Limit | Value | What Happens When Hit |
|-------|-------|----------------------|
| Max pages | 30 (default/scope), 100 (plan mode) | Stops crawling, processes what was found |
| Max depth | 3 | Does not follow links beyond 3 levels from baseURL |
| Same-origin | Enforced | External links are recorded but not followed |
| Auth passes | 2 max | Pass 1 unauthenticated, Pass 2 authenticated |

**When crawl limits are hit:**
- `crawl_limit_hit` is set to `true` in the QA_RESULT
- Discovery confidence is capped at MEDIUM (even if score would be HIGH)
- A warning is added to `discovery_warnings`: "Crawl limit reached at 30 pages"
- Routes beyond the limit appear only in static analysis (flagged UNVERIFIED_STATIC)

**Implications:** For large applications with more than 30 routes, use `--plan` to survey with a 100-page crawl limit, then `--scope` to test each feature area deeply. Static analysis helps fill the gap for unverified routes, which are verified when their scope runs via `--scope`.

---

## Budget Tracking

The QA Executor has a strict 60 tool call budget. Every tool invocation (Read, Write, Edit, Glob, Grep, Bash, Task) increments the counter by 1.

### Budget Thresholds

| Tool Calls | Zone | What Happens |
|------------|------|-------------|
| 0-36 | GREEN (60%) | Normal operation — all phases run fully |
| 36-48 | YELLOW (80%) | Selective vision (Phase C) is skipped. Output compression applied — shorter discovery reports, minimal comments in generated tests |
| 48-55 | ORANGE (92%) | Remaining test generation is skipped. Jumps directly to executing whatever tests exist, then coverage tracking and emit |
| 55+ | RED | Immediately writes .qa-summary.md and emits QA_RESULT with whatever partial data is available. No further phases run |

### Budget Tips

- **Simple projects** (under 10 routes, no auth): typically finish in 25-35 tool calls
- **Medium projects** (10-20 routes, auth flows): typically use 40-50 tool calls
- **Large projects** (20+ routes, complex auth, many APIs): may hit ORANGE/RED zone
- Use `--skip-strategy` to save the tool calls spent spawning the Strategist (approximately 2-4 calls)
- Use `--auto-discover` to avoid halting on LOW confidence (saves the back-and-forth)

---

## Debug Guide

### Test Failures

When tests fail after execution:

1. **Read the report:** Check `discovery/report.md` for discovery accuracy. If routes were misidentified, tests may target wrong URLs.
2. **Check screenshots:** If selective vision ran, check `discovery/screenshots/` for visual clues about page structure.
3. **Inspect test output:** The JSON reporter output shows exact error messages and stack traces per test.
4. **Common failure patterns:**
   - `Locator not found` — page structure differs from what discovery predicted. Re-run discovery or adjust locators.
   - `Navigation timeout` — page takes too long to load. Check if the app is running and responsive.
   - `401 Unauthorized` — auth-gated route tested without credentials. Ensure storageState is configured for authenticated tests.
   - `Element not visible` — element exists but is hidden. May need scroll or interaction to reveal it.

### Discovery Issues

When discovery produces unexpected results:

1. **Too few routes found:** Check that the `target` framework patterns match your project. If using a custom framework, document routing patterns in CLAUDE.md.
2. **Confidence is LOW:** Static and runtime results disagree significantly. Common causes: routes behind feature flags, routes requiring specific auth roles, routes only accessible via form submission.
3. **Use `--strict-discovery`:** Forces human approval of discovery results even at HIGH confidence. Useful when you want to verify before test generation.
4. **UNVERIFIED_STATIC routes:** Routes found in code but not during crawl. These may be behind auth, feature flags, or unused code.

### Playwright Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `browserType.launch: Executable doesn't exist` | Browsers not installed | Run `npx playwright install --with-deps` |
| `No playwright.config found` | Missing config file | Create `playwright.config.ts` in project root |
| `Target page, context or browser has been closed` | App crashed during test | Check app logs, restart app, re-run |
| `net::ERR_CONNECTION_REFUSED` | App not running | Start the app at the expected URL |
| `Timeout 30000ms exceeded` | Slow app or wrong URL | Verify URL, check app performance |

### Low Coverage

When coverage is below expectations:

1. **Check discovery completeness:** Are all routes in `discovery/discovery-map.json`? Missing routes mean missing tests.
2. **Check test generation:** Were tests generated for all HIGH risk routes? Check `e2e/tests/` directory.
3. **Check auth coverage:** Auth-gated routes may have been skipped if credentials were not available during test generation.
4. **Budget exhaustion:** If the Executor hit ORANGE or RED zone, test generation was cut short. Re-run with fewer routes or use `--skip-strategy` to save budget.

---

## Level 1 Boundaries

Understanding what Level 1 does and does not do is important for setting expectations.

### What L1 Does

- Discovers routes and APIs via 4-phase engine (static + runtime + vision + merge)
- **Infrastructure discovery:** Probes for email capture (Mailpit/MailHog), mock servers (Phase 1.5)
- **Pre-existing test triage:** Runs existing tests, classifies failures, files bugs (Phase 2.5)
- **Enhanced discovery:** Captures form details, button actions, table structure, modal triggers, API request/response body fields
- Gets risk classification from QA Strategist
- **Smoke depth:** Generates navigate-and-verify tests (original L1 behavior)
- **Functional depth (default):** Generates interaction tests — form submissions, CRUD operations, button clicks, modal interactions, data rendering verification
- Generates API tests (GET response validation, POST/PUT/DELETE CRUD flows, auth validation)
- **Simple linear chains:** Generates auth lifecycle tests (signup→login→access→logout→deny) for HIGH risk auth flows
- **Boundary tests:** Tests oversized input, special chars, SQL-like strings for HIGH risk endpoints
- **Email flow tests:** Tests password reset, MFA via email capture (if infrastructure available)
- **Post-generation self-check:** Validates assertion quality, state verification, cleanup, boundaries (Phase 4.7)
- **Session management:** `--plan` surveys app into testable scopes, `--scope` tests one area deeply, `--continue` auto-picks next scope
- Runs tests and parses JSON results
- Tracks route/API/interaction coverage (inventory-level: discovered vs tested)
- Reports bugs with severity classification
- Runs 1 round of Strategist audit (with structural completeness checks)

### What L1 Does NOT Do

| Capability | Level | Why Not at L1 |
|------------|-------|---------------|
| State modeling (login -> add to cart -> checkout) | L2 | Requires journey graph generation |
| Fuzz testing (random/adversarial inputs) | L2 | Requires input generation engine |
| Multi-round debate (fix gaps and re-audit) | L2 | L1 gets 1 audit round only |
| Branching journey graphs (multi-path user flows) | L2 | Requires state transition modeling (L1 has simple linear chains) |
| Security tests (XSS, CSRF, injection) | L3 | Requires adversarial test patterns |
| Cross-org access tests | L3 | Requires multi-tenant security modeling |
| Performance tests (load, stress) | L3 | Requires performance benchmarking tools |
| Visual regression comparison | L3 | Requires baseline screenshots + diffing |
| Flaky test detection | L3 | Requires multiple runs + statistical analysis |
| Production feedback integration | L5 | Requires observability pipeline |

### Coverage Is Inventory-Level

At L1, "coverage" means routes/APIs discovered vs routes/APIs that have at least one test. It does NOT mean:
- Code coverage (line/branch/statement)
- Behavioral coverage (all state transitions tested)
- Edge case coverage (boundary values, error combinations)

This is a known limitation. L2+ adds behavioral coverage tracking.

---

## Detailed Example Session

A full QA Executor run on a Next.js application with authentication produces output similar to the following.

### Phase 0-1: Setup and URL Detection

```
Dependencies installed. Playwright version: 1.42.0
Detected baseURL: http://localhost:3000 (from playwright.config.ts)
Environment: local
App reachability: OK (HTTP 200)
```

### Phase 2: Discovery

```
## Discovery Report

### Static Analysis (Phase A)
Routes found: 12
  /              (page.tsx)
  /auth/login    (page.tsx)
  /auth/register (page.tsx)
  /dashboard     (page.tsx, layout with auth middleware)
  /dashboard/settings (page.tsx)
  /items      (page.tsx)
  /items/[id] (page.tsx)
  /api/auth/login     (POST)
  /api/auth/register  (POST)
  /api/users          (GET)
  /api/items       (GET, POST)
  /api/items/:id   (GET, PUT, DELETE)

### Runtime Crawl (Phase B)
Pages crawled: 8 (depth 2)
API calls intercepted: 6
Seed data: items(24), users(3)
Console errors: 0

### Selective Vision (Phase C)
Screenshots taken: 2 (register form with 6 inputs, dashboard with table)

### Merge & Gate (Phase D)
Overlap: 8 routes
Static-only: 4 (auth-gated routes not reached in Pass 1)
Runtime-only: 0
Confidence: 0.67 (MEDIUM)
Note: 4 routes require authentication for runtime verification
```

### Phase 3: Strategy (from QA Strategist)

```
Risk Classification:
  HIGH: /auth/login, /auth/register, /dashboard, /api/auth/*, /api/items (POST/PUT/DELETE)
  MEDIUM: /items, /items/[id], /dashboard/settings, /api/users, /api/items (GET)
  LOW: /

Coverage Targets: HIGH 85%, MEDIUM 70%, LOW 50%
```

### Phase 4: Test Generation (functional depth)

```
Generated 8 test files (5-10 tests each, functional depth):
  e2e/tests/frontend/auth.spec.ts            (8 tests, HIGH — login form valid/invalid, register form valid/invalid/empty)
  e2e/tests/frontend/dashboard.spec.ts       (4 tests, HIGH — data rendering, auth gate)
  e2e/tests/frontend/items.spec.ts        (5 tests, MEDIUM — list rendering, detail page, create form)
  e2e/tests/frontend/settings.spec.ts        (2 tests, MEDIUM — form submission)
  e2e/tests/frontend/home.spec.ts            (1 test, LOW — content renders)
  e2e/tests/api/auth.spec.ts                 (6 tests, HIGH — POST valid/invalid, 401 without token)
  e2e/tests/api/users.spec.ts                (3 tests, MEDIUM — GET body validation, auth)
  e2e/tests/api/items.spec.ts             (7 tests, MEDIUM — full CRUD: POST/GET/PUT/DELETE + validation)
Total: 36 tests across 8 files
```

### Phase 4.5: Dry-Run Gate

```
Dry-run: 3 files selected (auth-login, items, home)
Results: 3/3 passed
Gate: PASSED — proceeding to full suite
```

### Phase 5: Execution

```
Running full suite: npx playwright test e2e/tests/ --reporter=json
Duration: 58s
Total: 36 tests
Passed: 33
Failed: 3
Skipped: 0
```

### Phase 6-7: Coverage and Bugs

```
Coverage:
  Routes: 10/12 tested (83%)
  APIs: 5/6 tested (83%)
  Interactions: 14 form-submissions, 4 CRUD flows, 3 data-rendering checks
  Weighted: 82%

Bugs found: 3
  MEDIUM - Register form accepts empty email field
    Route: /auth/register (HIGH risk)
    Expected: validation error on empty email
    Actual: form submits with empty email
    @covers-interaction: validation-error
  MEDIUM - PUT /api/items/:id returns 200 but doesn't update name
    API: PUT /api/items/:id (MEDIUM risk)
    Expected: updated item name in response
    Actual: response shows original name
    @covers-interaction: api-put
  LOW - Detail page missing alt text on images
    Route: /items/[id] (MEDIUM risk)
    Expected: img elements have alt attributes
    Actual: alt="" on detail images
```

### Phase 8: Strategist Audit

```
## STRATEGIST_VERDICT
- round: 1/1
- verdict: approved
- coverage_achieved: routes 10/12, apis 5/6
- coverage_target: 85%
- interaction_depth: 5/5 HIGH risk routes have deep interaction tests
- gaps: /dashboard/settings (MEDIUM, no error path test)
- blocking_bugs: 0
- quality_score: 79
- rationale: All HIGH risk routes covered with form submission, validation,
  and CRUD tests. Interaction depth is full for HIGH risk routes. Coverage
  weighted at 82%. Three non-blocking bugs found (2 MEDIUM, 1 LOW).
  Approved.
```

### Phase 9: Final QA_RESULT

```
## QA_RESULT
- task_id: qa-run-001
- status: passed
- depth: functional
- rounds_run: 1/1
- tests_generated: 36
- tests_run_this_session: 36
- tests_passed: 33
- tests_failed: 3
- discovery_confidence: MEDIUM
- discovery_duration_seconds: 18
- crawl_limit_hit: false
- discovery_warnings: ["4 auth-gated routes not verified at runtime"]
- coverage: routes 10/12, apis 5/6
- coverage_weighted: 82%
- risk_score: 18
- bugs_found: 3
- bugs_blocking: 0
- strategist_verdict: approved
- files_created: [discovery/*, e2e/tests/frontend/*.spec.ts, e2e/tests/api/*.spec.ts, .qa-summary.md]
- error: none
- notes: Functional tests with 14 form submissions, 4 CRUD flows. 3 non-blocking bugs. Cross-org security tests deferred to L3.
```

---

## See Also

- `/qa-strategist` — Plan risk-based test strategy independently
- `/code-reviewer` — Review code changes
- `/agent-help` — List all commands
