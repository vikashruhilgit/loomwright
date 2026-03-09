---
description: Discover app structure, generate and run Playwright tests with risk-based strategy
---

# Command: /qa-executor

## Usage

```
/qa-executor [--url http://...] [--rounds 1|2|3] [--coverage 80] [--skip-strategy] [--strict-discovery] [--auto-discover]
```

## Parameters

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

## What This Does

1. **Detects target URL** from Playwright config, .env, or --url flag
2. **Runs 4-phase discovery:**
   - Static analysis (routes from source code)
   - Runtime crawl (Playwright-based DOM + network + a11y extraction)
   - Selective vision (screenshots for complex pages only)
   - Merge & gate (confidence scoring, discovery report)
3. **Gets risk strategy** from QA Strategist (or uses defaults with --skip-strategy)
4. **Generates Playwright tests:**
   - UI/E2E tests for routes (happy + error paths for HIGH risk)
   - API tests for endpoints (status codes, auth validation)
   - All tests use role-based locators and regex assertions
5. **Executes tests** via `npx playwright test --reporter=json`
6. **Tracks coverage** (routes and APIs discovered vs tested)
7. **Reports bugs** for failures (severity: BLOCKING/HIGH/MEDIUM/LOW)
8. **Runs Strategist audit** (1 round for L1) -> approved/rejected
9. **Emits QA_RESULT** with complete status

## Requirements

- **playwright.config.ts** (or .js) must exist in project
- **Application must be running** at the detected base URL
- **npx** must be available (Node.js installed)
- **Playwright browsers** installed (`npx playwright install`)

## Example Output

```
## QA_RESULT
- task_id: qa-run-001
- status: passed
- rounds_run: 1/3
- tests_generated: 18
- tests_run: 18
- tests_passed: 16
- tests_failed: 2
- discovery_confidence: HIGH
- discovery_duration_seconds: 12
- crawl_limit_hit: false
- discovery_warnings: []
- coverage: routes 12/15, apis 18/23
- coverage_weighted: 78%
- risk_score: 22
- bugs_found: 2
- bugs_blocking: 0
- strategist_verdict: approved
- files_created: [discovery/*, e2e/tests/frontend/*.spec.ts, e2e/tests/api/*.spec.ts]
- error: none
- notes: 2 LOW severity bugs found (cosmetic). All HIGH risk routes covered.
```

## Generated Files

```
discovery/
  crawl.ts                  # Playwright crawler script
  static-map.json           # Routes from static analysis
  sitemap.json              # Routes from runtime crawl
  api-calls.json            # Intercepted API calls
  discovery-map.json        # Merged discovery map
  report.md                 # Human-readable discovery report

e2e/tests/frontend/
  {feature}.spec.ts         # UI/E2E tests per feature

e2e/tests/api/
  {feature}.spec.ts         # API tests per feature

.qa-summary.md              # Summary for Strategist audit
```

## Common Workflows

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

Tests are generated differently based on risk level. All tests follow the playwright-e2e skill patterns.

### HIGH Risk Routes

Each HIGH risk route gets both happy path and error path tests:

```typescript
test.describe('Login', () => {
  // @covers-route: /auth/login

  test('should display login form', async ({ page }) => {
    await page.goto('/auth/login');
    await expect(page.getByRole('heading', { name: /log in|sign in/i })).toBeVisible();
    await expect(page.getByLabel(/email/i)).toBeVisible();
    await expect(page.getByLabel(/password/i)).toBeVisible();
  });

  test('should reject invalid credentials', async ({ page }) => {
    await page.goto('/auth/login');
    await page.getByLabel(/email/i).fill('invalid@example.com');
    await page.getByLabel(/password/i).fill('wrongpassword');
    await page.getByRole('button', { name: /log in|sign in/i }).click();
    await expect(page.getByText(/invalid|incorrect|error/i)).toBeVisible();
  });
});
```

### MEDIUM Risk Routes

MEDIUM risk routes get happy path tests only:

```typescript
test.describe('Product List', () => {
  // @covers-route: /products

  test('should display product listing', async ({ page }) => {
    await page.goto('/products');
    await expect(page.getByRole('heading', { name: /products/i })).toBeVisible();
  });
});
```

### LOW Risk Routes

LOW risk routes get a single smoke test:

```typescript
test.describe('About Page', () => {
  // @covers-route: /about

  test('should load about page', async ({ page }) => {
    await page.goto('/about');
    await expect(page).toHaveTitle(/about/i);
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
| Max pages | 30 | Stops crawling, processes what was found |
| Max depth | 3 | Does not follow links beyond 3 levels from baseURL |
| Same-origin | Enforced | External links are recorded but not followed |
| Auth passes | 2 max | Pass 1 unauthenticated, Pass 2 authenticated |

**When crawl limits are hit:**
- `crawl_limit_hit` is set to `true` in the QA_RESULT
- Discovery confidence is capped at MEDIUM (even if score would be HIGH)
- A warning is added to `discovery_warnings`: "Crawl limit reached at 30 pages"
- Routes beyond the limit appear only in static analysis (flagged UNVERIFIED_STATIC)

**Implications:** For large applications with more than 30 routes, the Executor will not discover all pages via crawling. Static analysis helps fill the gap, but confidence is reduced. Consider running targeted analysis on specific directories if coverage of a particular area is important.

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
- Gets risk classification from QA Strategist
- Generates UI/E2E tests for happy paths on all risk levels
- Generates error path tests for HIGH risk routes
- Generates API tests (status codes, auth validation for 401)
- Runs tests and parses JSON results
- Tracks route/API coverage (inventory-level: discovered vs tested)
- Reports bugs with severity classification
- Runs 1 round of Strategist audit

### What L1 Does NOT Do

| Capability | Level | Why Not at L1 |
|------------|-------|---------------|
| State modeling (login -> add to cart -> checkout) | L2 | Requires journey graph generation |
| Fuzz testing (random/boundary inputs) | L2 | Requires input generation engine |
| Multi-round debate (fix gaps and re-audit) | L2 | L1 gets 1 audit round only |
| Journey depth tests (multi-step user flows) | L2 | Requires state transition modeling |
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
  /products      (page.tsx)
  /products/[id] (page.tsx)
  /api/auth/login     (POST)
  /api/auth/register  (POST)
  /api/users          (GET)
  /api/products       (GET, POST)
  /api/products/:id   (GET, PUT, DELETE)

### Runtime Crawl (Phase B)
Pages crawled: 8 (depth 2)
API calls intercepted: 6
Seed data: products(24), users(3)
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
  HIGH: /auth/login, /auth/register, /dashboard, /api/auth/*, /api/products (POST/PUT/DELETE)
  MEDIUM: /products, /products/[id], /dashboard/settings, /api/users, /api/products (GET)
  LOW: /

Coverage Targets: HIGH 85%, MEDIUM 70%, LOW 50%
```

### Phase 4: Test Generation

```
Generated 14 test files:
  e2e/tests/frontend/auth-login.spec.ts      (3 tests, HIGH)
  e2e/tests/frontend/auth-register.spec.ts   (3 tests, HIGH)
  e2e/tests/frontend/dashboard.spec.ts       (2 tests, HIGH)
  e2e/tests/frontend/products.spec.ts        (1 test, MEDIUM)
  e2e/tests/frontend/product-detail.spec.ts  (1 test, MEDIUM)
  e2e/tests/frontend/settings.spec.ts        (1 test, MEDIUM)
  e2e/tests/frontend/home.spec.ts            (1 test, LOW)
  e2e/tests/api/auth.spec.ts                 (4 tests, HIGH)
  e2e/tests/api/users.spec.ts                (2 tests, MEDIUM)
  e2e/tests/api/products.spec.ts             (3 tests, MEDIUM)
```

### Phase 4.5: Dry-Run Gate

```
Dry-run: 3 files selected (auth-login, products, home)
Results: 3/3 passed
Gate: PASSED — proceeding to full suite
```

### Phase 5: Execution

```
Running full suite: npx playwright test e2e/tests/ --reporter=json
Duration: 42s
Total: 21 tests
Passed: 19
Failed: 2
Skipped: 0
```

### Phase 6-7: Coverage and Bugs

```
Coverage:
  Routes: 10/12 tested (83%)
  APIs: 5/6 tested (83%)
  Weighted: 79%

Bugs found: 2
  MEDIUM - Register form accepts empty email field
    Route: /auth/register (HIGH risk)
    Expected: validation error on empty email
    Actual: form submits with empty email
  LOW - Product page missing alt text on images
    Route: /products/[id] (MEDIUM risk)
    Expected: img elements have alt attributes
    Actual: alt="" on product images
```

### Phase 8: Strategist Audit

```
## STRATEGIST_VERDICT
- round: 1/1
- verdict: approved
- coverage_achieved: routes 10/12, apis 5/6
- coverage_target: 85%
- gaps: /dashboard/settings (MEDIUM, no error path test)
- blocking_bugs: 0
- quality_score: 76
- rationale: All HIGH risk routes covered with both happy and error paths.
  Coverage weighted at 79%. Two non-blocking bugs found. The 2 untested
  routes are auth-gated and were not reached during crawl — acceptable
  for L1. Approved.
```

### Phase 9: Final QA_RESULT

```
## QA_RESULT
- task_id: qa-run-001
- status: passed
- rounds_run: 1/1
- tests_generated: 21
- tests_run_this_session: 21
- tests_passed: 19
- tests_failed: 2
- discovery_confidence: MEDIUM
- discovery_duration_seconds: 18
- crawl_limit_hit: false
- discovery_warnings: ["4 auth-gated routes not verified at runtime"]
- coverage: routes 10/12, apis 5/6
- coverage_weighted: 79%
- risk_score: 21
- bugs_found: 2
- bugs_blocking: 0
- strategist_verdict: approved
- files_created: [discovery/*, e2e/tests/frontend/*.spec.ts, e2e/tests/api/*.spec.ts, .qa-summary.md]
- error: none
- notes: 2 non-blocking bugs (1 MEDIUM, 1 LOW). Cross-org security tests deferred to L3.
```

---

## See Also

- `/qa-strategist` — Plan risk-based test strategy independently
- `/code-reviewer` — Review code changes
- `/agent-help` — List all commands
