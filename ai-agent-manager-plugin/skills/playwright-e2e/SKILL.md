---
name: playwright-e2e
description: Write, run, and debug Playwright E2E tests using CLI. Covers test authoring, execution, debugging, reports, and CI integration.
allowed-tools: [Read, Bash]
---

# Playwright E2E Testing

E2E testing patterns using Playwright with 3 test projects: setup (auth), frontend-ui (browser), and api-smoke (API).

---

## 1. Quick Reference

```bash
# Run all tests
yarn test:e2e

# Run by project
yarn test:e2e:ui              # frontend-ui only
yarn test:e2e:api             # api-smoke only

# Debug & inspect
yarn test:e2e:headed          # frontend-ui with visible browser
yarn test:e2e:debug           # frontend-ui with Playwright Inspector
yarn test:e2e:report          # open HTML report

# Target specific tests
npx playwright test --grep "test name"       # by test name
npx playwright test path/to/file.spec.ts     # by file

# Setup
npx playwright install                       # install browsers
```

### Environment Overrides

```bash
# Run against staging
FRONTEND_URL=https://staging.example.com yarn test:e2e:ui
GATEWAY_URL=https://staging.example.com/api yarn test:e2e:api
```

---

## 2. Project Structure

```
e2e/
├── playwright.config.ts       # 3 projects: setup, frontend-ui, api-smoke
├── global-setup.ts            # Auth via POST /api/auth/login -> saves storageState
├── fixtures/index.ts          # Custom fixtures (extends base test, exports test + expect)
├── .auth/                     # Generated auth state (GITIGNORED)
│   └── user.json              # storageState saved by global-setup
├── test-results/              # Traces, screenshots, videos, JUnit XML (GITIGNORED)
├── tests/frontend/            # Browser UI tests (Desktop Chrome, depends on setup)
│   ├── login.spec.ts          # Unauthenticated login page tests
│   └── smoke.spec.ts          # Authenticated dashboard smoke tests
└── tests/api/                 # API-only tests (no browser, hits gateway directly)
    ├── health.spec.ts         # GET /health, GET /health/live
    └── gateway-smoke.spec.ts  # Auth rejection, CORS headers
```

### 3 Projects in playwright.config.ts

| Project | Test Dir | Browser | Auth | baseURL |
|---------|----------|---------|------|---------|
| **setup** | — | — | POST /api/auth/login -> `.auth/user.json` | — |
| **frontend-ui** | `tests/frontend/` | Desktop Chrome | storageState from setup | `FRONTEND_URL` or `http://localhost:3000` |
| **api-smoke** | `tests/api/` | None (API only) | Manual headers | `GATEWAY_URL` or `http://localhost:3001` |

### Config Settings

| Setting | Local | CI |
|---------|-------|----|
| retries | 0 | 2 |
| workers | auto | 1 |
| timeout | 30000 | 30000 |
| expect timeout | 5000 | 5000 |
| trace | on-first-retry | on-first-retry |
| screenshot | only-on-failure | only-on-failure |
| video | retain-on-failure | retain-on-failure |
| reporter | HTML | HTML + JUnit (`./test-results/junit.xml`) |

---

## 3. Writing Tests

### Frontend UI Test (Authenticated)

Authenticated tests get auth automatically via the setup project dependency — no extra setup needed.

```typescript
import { test, expect } from '@playwright/test';

test.describe('Dashboard', () => {
  test('should display welcome message', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', { name: /welcome/i })).toBeVisible({ timeout: 10000 });
  });

  test('should navigate to sites page', async ({ page }) => {
    await page.goto('/dashboard');
    await page.getByRole('link', { name: /sites/i }).click();
    await expect(page).toHaveURL(/\/(en|ar)\/(dashboard|sites)?/);
  });
});
```

### Frontend UI Test (Unauthenticated)

Override storageState to clear auth:

```typescript
import { test, expect } from '@playwright/test';

test.describe('Login Page', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test('should show login form', async ({ page }) => {
    await page.goto('/login');
    await expect(page.getByRole('textbox', { name: /email/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /sign in|log in/i })).toBeVisible();
  });

  test('should show error for invalid credentials', async ({ page }) => {
    await page.goto('/login');
    await page.getByRole('textbox', { name: /email/i }).fill('wrong@example.com');
    await page.getByLabel(/password/i).fill('wrongpassword');
    await page.getByRole('button', { name: /sign in|log in/i }).click();
    await expect(page.getByText(/invalid|error|incorrect/i)).toBeVisible();
  });
});
```

### API Test

API tests use the `request` fixture directly — no browser, no `page`:

```typescript
import { test, expect } from '@playwright/test';

test.describe('Health Checks', () => {
  test('GET /health returns 200', async ({ request }) => {
    const response = await request.get('/health');
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.status).toBe('ok');
  });
});

test.describe('Auth Rejection', () => {
  test('rejects unauthenticated requests', async ({ request }) => {
    const response = await request.get('/api/protected', {
      headers: { Authorization: '' },
    });
    expect(response.status()).toBe(401);
  });
});
```

---

## 4. Adding New Tests

| Test Type | Directory | Example Path |
|-----------|-----------|-------------|
| Frontend UI | `e2e/tests/frontend/` | `e2e/tests/frontend/user-profile.spec.ts` |
| API | `e2e/tests/api/` | `e2e/tests/api/users-crud.spec.ts` |

**Naming convention:** `{feature}.spec.ts` — use kebab-case for multi-word names (`user-profile.spec.ts`).

- Frontend tests automatically get auth via setup project dependency — no extra setup needed
- API tests must manually set auth headers if the endpoint requires authentication
- Always group related tests with `test.describe('Feature Name', () => { ... })`

---

## 5. Test Authoring Rules

### Locators: Role-Based First

```typescript
// GOOD - role-based, accessible, resilient
page.getByRole('button', { name: /submit/i })
page.getByRole('textbox', { name: /email/i })
page.getByRole('link', { name: /dashboard/i })
page.getByLabel(/password/i)
page.getByText(/welcome/i)

// BAD - CSS selectors, brittle
page.locator('.btn-primary')
page.locator('#email-input')
page.locator('div > form > button:first-child')
```

### Assertions: Use Regex for i18n

```typescript
// GOOD - works across locales
await expect(page.getByText(/invalid|error|incorrect/i)).toBeVisible();
await expect(page).toHaveURL(/\/(en|ar)\/(dashboard|sites)?/);

// BAD - breaks if locale changes
await expect(page.getByText('Invalid credentials')).toBeVisible();
```

### Timeouts: Set for Async Operations

```typescript
// Navigation or data loading - use explicit timeout
await expect(page.getByRole('heading')).toBeVisible({ timeout: 10000 });

// Default expect timeout (5000ms) is fine for static elements
await expect(page.getByRole('button')).toBeEnabled();
```

### Grouping and Structure

```typescript
test.describe('Feature Name', () => {
  // Shared setup for this group
  test.beforeEach(async ({ page }) => {
    await page.goto('/feature');
  });

  test('should do X', async ({ page }) => { /* ... */ });
  test('should handle Y', async ({ page }) => { /* ... */ });
});
```

### Imports: Fixtures vs @playwright/test

```typescript
// Use @playwright/test for tests that don't need custom fixtures
import { test, expect } from '@playwright/test';

// Use fixtures/index.ts when you need project-specific fixtures
import { test, expect } from '../fixtures/index';
```

When adding a new fixture, extend the existing `fixtures/index.ts` — don't create a separate fixtures file.

---

## 6. Debugging Failures

### Step 1: Read CLI Output

The terminal shows the failing assertion, expected vs actual values, and the file:line number.

### Step 2: Run the Failing Test Alone

```bash
# By file
npx playwright test e2e/tests/frontend/smoke.spec.ts

# By name
npx playwright test --grep "should display welcome"
```

### Step 3: Use Playwright Inspector

```bash
yarn test:e2e:debug
```

Opens a browser with step-by-step execution, locator highlighting, and a console for trying locators.

### Step 4: Check HTML Report

```bash
yarn test:e2e:report
```

Opens a detailed report with:
- Test timeline with screenshots at each step
- Traces (network, console, DOM snapshots) on first retry
- Screenshot on failure
- Video on failure

### Step 5: Inspect Traces

Traces are saved on first retry (configured via `trace: 'on-first-retry'`). Open them:

```bash
npx playwright show-trace e2e/test-results/<test-folder>/trace.zip
```

Shows network requests, DOM snapshots, console logs, and action timeline.

### Step 6: Check Screenshots and Videos

- Screenshots: `e2e/test-results/<test-folder>/<test-name>.png` (on failure)
- Videos: `e2e/test-results/<test-folder>/video.webm` (on failure)

---

## 7. Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `FRONTEND_URL` | `http://localhost:3000` | Base URL for frontend-ui project |
| `GATEWAY_URL` | `http://localhost:3001` | Base URL for api-smoke project |
| `E2E_USER_EMAIL` | *(set per-project)* | Auth credentials for global-setup |
| `E2E_USER_PASSWORD` | *(set per-project)* | Auth credentials for global-setup |
| `CI` | — | Enables retries (2), single worker, JUnit reporter |

---

## 8. CI Integration

- **Docker image:** `mcr.microsoft.com/playwright:v1.50.0-noble`
- **Tests in CI:** API smoke tests only (`yarn test:e2e:api`)
- **Frontend tests:** Require running frontend stack (local only for now)
- **JUnit output:** `e2e/test-results/junit.xml`
- **CI behavior:** 2 retries, 1 worker, HTML + JUnit reporters

---

## 9. Anti-Patterns

| Don't | Do Instead |
|-------|-----------|
| `await page.waitForTimeout(3000)` | `await expect(locator).toBeVisible({ timeout: 10000 })` |
| Hardcoded credentials in test files | Use `E2E_USER_EMAIL` / `E2E_USER_PASSWORD` env vars |
| CSS selectors: `page.locator('.btn')` | Role locators: `page.getByRole('button', { name: /submit/i })` |
| Skip setup dependency for frontend tests | Keep `dependencies: ['setup']` in config |
| Commit `e2e/.auth/` directory | Add to `.gitignore` (contains auth tokens) |
| Commit `e2e/test-results/` directory | Add to `.gitignore` (generated artifacts) |
| Create separate fixtures files | Extend existing `fixtures/index.ts` |
| Hardcoded URLs: `page.goto('http://localhost:3000')` | Use `baseURL` from config: `page.goto('/dashboard')` |

---

## 10. Auth Pattern Reference

### How Auth Works

```
global-setup.ts
  ├── POST /api/auth/login { email, password }
  ├── Save storageState → e2e/.auth/user.json
  └── frontend-ui project loads storageState automatically
```

### Authenticated Test (Default)

No action needed — auth is inherited from setup project.

### Unauthenticated Test

```typescript
test.use({ storageState: { cookies: [], origins: [] } });
```

---

## Quality Checklist

Before committing E2E tests:
- [ ] Tests pass locally (`yarn test:e2e`)
- [ ] No hardcoded credentials (use env vars)
- [ ] Role-based locators used (no CSS selectors)
- [ ] Regex used for text assertions (i18n-friendly)
- [ ] Test file in correct directory (`tests/frontend/` or `tests/api/`)
- [ ] File named `{feature}.spec.ts` (kebab-case)
- [ ] Tests grouped with `test.describe`
- [ ] Explicit timeouts for async assertions
- [ ] `e2e/.auth/` not committed (gitignored)
- [ ] `e2e/test-results/` not committed (gitignored)

## See Also

- `skills/quality-checklist/SKILL.md` — Review gate criteria
- `skills/commit/SKILL.md` — Conventional commit format for test changes
