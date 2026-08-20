---
name: playwright-e2e
description: Write, run, and debug Playwright E2E tests using CLI. Covers test authoring, execution, debugging, reports, and CI integration.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# Playwright E2E Testing

E2E testing patterns using Playwright with 3 test projects: setup (auth), frontend-ui (browser), and api-smoke (API).

> **CRITICAL: READ FIRST.** Before generating ANY test, understand the assertion anti-patterns below.
> Tests that use lenient patterns (status arrays, property-existence-only, text-length proxies)
> will be REJECTED by the QA Strategist. A 500 response is ALWAYS a bug, never acceptable.

---

## Assertion Anti-Patterns — NEVER Generate These

These patterns produce tests that pass regardless of application correctness. A senior QA engineer would reject any test containing these.

### Status Code Anti-Patterns

| BAD (never generate) | GOOD (always use) | Why it's bad |
|---|---|---|
| `expect([200, 401, 500]).toContain(response.status())` | `expect(response.status()).toBe(200)` | Accepts auth failures and server errors as valid |
| `expect(response.ok()).toBeTruthy()` | `expect(response.status()).toBe(200)` | `ok()` is true for any 2xx — too broad |
| `if (response.status() !== 200) return;` | `expect(response.status()).toBe(200)` | Silently skips failures — test always passes |

### Response Body Anti-Patterns

| BAD (never generate) | GOOD (always use) | Why it's bad |
|---|---|---|
| `expect(body).toHaveProperty('name')` | `expect(body.name).toBe(expectedName)` | Passes even if name is wrong value |
| `expect(body).toBeDefined()` | `expect(body.name).toBe('Test')` | Passes for any non-null response |
| `expect(Object.keys(body).length).toBeGreaterThan(0)` | `expect(body.items.length).toBeGreaterThan(0)` | Passes for any non-empty object |

### Frontend Anti-Patterns

| BAD (never generate) | GOOD (always use) | Why it's bad |
|---|---|---|
| `expect((await el.innerText()).length).toBeGreaterThan(10)` | `await expect(page.getByRole('heading')).toHaveText(/dashboard/i)` | Passes for any text, even error pages |
| `await expect(page.locator('body')).not.toBeEmpty()` | `await expect(page.getByRole('heading', { name: /welcome/i })).toBeVisible()` | Passes for any page with content |

### Locator Anti-Patterns

| BAD (never generate) | GOOD (always use) | Why it's bad |
|---|---|---|
| `page.locator('input[type="email"]')` | `page.getByRole('textbox', { name: /email/i })` | CSS selector breaks on DOM changes |
| `page.locator('.btn-primary')` | `page.getByRole('button', { name: /submit/i })` | Class names are implementation detail |
| `page.locator('#login-form')` | `page.getByRole('form')` | IDs are fragile, not user-visible |
| `page.locator('div > span.error')` | `page.getByText(/error message/i)` | DOM structure changes break this |

### State Verification Anti-Patterns

| BAD (never generate) | GOOD (always use) | Why it's bad |
|---|---|---|
| POST → assert 201 → done | POST → assert 201 → GET → assert fields match sent data | POST may return 201 but not persist |
| PUT → assert 200 → done | PUT → assert 200 → GET → assert changed fields | Response may be cached, not persisted |
| DELETE → assert 204 → done | DELETE → assert 200/204 → GET → assert 404 | Resource may not actually be deleted |

### The 5xx Rule

**A 500 response is ALWAYS a server bug, never an expected test outcome.**

If any test receives a 500:
1. The test MUST fail (not accept 500 as valid)
2. A BLOCKING bug report MUST be created
3. The bug report includes the endpoint, request payload, and 500 response body
4. Never use `expect([200, 500]).toContain(status)` — this masks real bugs

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

### Test Isolation (MANDATORY for generated tests)

Every test must be fully independent — no shared state across tests or files.

```typescript
test.describe('Items', () => {
  let createdId: string;

  test.beforeEach(async ({ request }) => {
    // Create unique fixture data for this test run
    const uniqueName = `test-item-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    const res = await request.post('/api/items', {
      data: { name: uniqueName, email: `${uniqueName}@test.example` },
      headers: { Authorization: `Bearer ${process.env.E2E_TOKEN}` },
    });
    const body = await res.json();
    createdId = body.id;
  });

  test.afterEach(async ({ request }) => {
    // Clean up to avoid data accumulation across runs
    if (createdId) {
      await request.delete(`/api/items/${createdId}`, {
        headers: { Authorization: `Bearer ${process.env.E2E_TOKEN}` },
      });
    }
  });

  test('item detail page loads', async ({ page }) => {
    await page.goto(`/items/${createdId}`);
    await expect(page.getByRole('heading')).toBeVisible();
  });
});
```

**Rules:**
- Never share `createdId`, cookies, or auth tokens across `test.describe` blocks without explicit storageState
- Use `Date.now()` or `crypto.randomUUID()` to make identifiers unique per run
- For auth-gated routes: set storageState per-file or log in inside `beforeEach`
- If test requires data that cannot be created programmatically: `test.skip('requires seed data: {entity}')`

### Fixture Data Patterns

When tests need entity data from the app:

```typescript
// GOOD — read from discovery/seed-data.json at test generation time,
//         inject as test constant (never hardcode slugs)
const ORG_SLUG = process.env.TEST_ORG_SLUG ?? 'fallback-org'; // read from env

// GOOD — create data dynamically
test.beforeEach(async ({ request }) => {
  const res = await request.post('/api/orgs', { data: { name: `org-${Date.now()}` } });
  orgSlug = (await res.json()).slug;
});

// BAD — hardcoded slug/ID that may not exist in target environment
await page.goto('/orgs/my-hardcoded-org');
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
| Hardcoded slugs/IDs: `page.goto('/orgs/my-org')` | Create data in beforeEach or read from seed-data.json |
| Shared state across tests (no beforeEach/afterEach) | Isolate each test: create + clean up in beforeEach/afterEach |
| Cross-org assertions at L1 (user A accesses org B) | L3 security tests only; at L1 only test 401 without token |

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

## 11. Interaction Test Patterns

Concrete patterns for functional-depth test generation. Used by QA Executor when `--depth functional` (default).

### Form Submission Pattern

Test forms by filling fields, submitting, and verifying feedback.

```typescript
test.describe('Create Item', () => {
  // @covers-route: /items/create
  // @covers-interaction: form-submission

  test('should create item with valid data', async ({ page }) => {
    await page.goto('/items/create');
    await page.getByLabel(/name/i).fill(`Test Item ${Date.now()}`);
    await page.getByLabel(/description/i).fill('Test description');
    await page.getByLabel(/category/i).fill('General');
    await page.getByRole('button', { name: /create|submit|save/i }).click();

    // Verify success feedback (toast, redirect, or new element)
    await expect(page.getByText(/created|success/i)).toBeVisible({ timeout: 10000 });
  });

  // @covers-interaction: validation-error
  test('should show validation errors for empty required fields', async ({ page }) => {
    await page.goto('/items/create');
    await page.getByRole('button', { name: /create|submit|save/i }).click();

    // Verify validation messages appear
    await expect(page.getByText(/required|cannot be empty|please fill/i)).toBeVisible();
  });

  test('should reject invalid input', async ({ page }) => {
    await page.goto('/items/create');
    await page.getByLabel(/name/i).fill('Valid Name');
    await page.getByLabel(/date/i).fill('not-a-date');
    await page.getByRole('button', { name: /create|submit|save/i }).click();

    await expect(page.getByText(/invalid|format|valid/i)).toBeVisible();
  });
});
```

### CRUD Create via UI

Create an entity through the UI form, then verify it appears in the list.

```typescript
test.describe('Item CRUD - Create', () => {
  // @covers-route: /items/new
  // @covers-interaction: form-submission
  const uniqueName = `test-item-${Date.now()}`;

  test('should create item and verify in list', async ({ page }) => {
    // Create
    await page.goto('/items/new');
    await page.getByLabel(/name/i).fill(uniqueName);
    await page.getByLabel(/email/i).fill(`${uniqueName}@test.example`);
    await page.getByRole('button', { name: /create|add|save/i }).click();
    await expect(page.getByText(/created|success/i)).toBeVisible({ timeout: 10000 });

    // Verify in list
    await page.goto('/items');
    await expect(page.getByText(uniqueName)).toBeVisible();
  });
});
```

### CRUD Update via UI

Navigate to edit form, modify fields, save, and verify changes persist.

```typescript
test.describe('Item CRUD - Update', () => {
  // @covers-route: /items/:id/edit
  // @covers-interaction: form-submission

  test('should update item name', async ({ page }) => {
    // Navigate to existing item (use seed data or create first)
    await page.goto('/items');
    await page.getByRole('link', { name: /edit/i }).first().click();

    // Modify
    const updatedName = `updated-${Date.now()}`;
    await page.getByLabel(/name/i).clear();
    await page.getByLabel(/name/i).fill(updatedName);
    await page.getByRole('button', { name: /save|update/i }).click();

    // Verify
    await expect(page.getByText(/updated|saved|success/i)).toBeVisible({ timeout: 10000 });
    await page.goto('/items');
    await expect(page.getByText(updatedName)).toBeVisible();
  });
});
```

### CRUD Delete via UI

Click delete, handle confirmation dialog, verify entity is removed.

```typescript
test.describe('Item CRUD - Delete', () => {
  // @covers-route: /items/:id
  // @covers-interaction: button-click
  // @covers-interaction: modal

  test('should delete item with confirmation', async ({ page }) => {
    await page.goto('/items');
    const itemName = await page.getByRole('row').nth(1).getByRole('cell').first().innerText();

    // Click delete
    await page.getByRole('row').nth(1).getByRole('button', { name: /delete|remove/i }).click();

    // Handle confirmation dialog
    await expect(page.getByRole('dialog')).toBeVisible();
    await page.getByRole('dialog').getByRole('button', { name: /confirm|yes|delete/i }).click();

    // Verify removed
    await expect(page.getByText(/deleted|removed/i)).toBeVisible({ timeout: 10000 });
    await expect(page.getByText(itemName)).not.toBeVisible();
  });
});
```

### Modal Interaction Pattern

Open modal via trigger, interact with contents, close, and verify state.

```typescript
test.describe('Invite Modal', () => {
  // @covers-route: /items
  // @covers-interaction: modal

  test('should open modal and submit', async ({ page }) => {
    await page.goto('/items');

    // Open modal
    await page.getByRole('button', { name: /invite|add|new/i }).click();
    await expect(page.getByRole('dialog')).toBeVisible();

    // Interact with modal form
    await page.getByRole('dialog').getByLabel(/email/i).fill(`test-${Date.now()}@test.example`);
    await page.getByRole('dialog').getByRole('button', { name: /send|invite|submit/i }).click();

    // Verify modal closes and feedback shown
    await expect(page.getByRole('dialog')).not.toBeVisible();
    await expect(page.getByText(/success|sent|added/i)).toBeVisible();
  });

  test('should close modal via cancel', async ({ page }) => {
    await page.goto('/items');
    await page.getByRole('button', { name: /invite|add|new/i }).click();
    await expect(page.getByRole('dialog')).toBeVisible();

    await page.getByRole('dialog').getByRole('button', { name: /cancel|close/i }).click();
    await expect(page.getByRole('dialog')).not.toBeVisible();
  });
});
```

### API CRUD Pattern

Full create-read-update-delete cycle via API with cleanup.

```typescript
test.describe('Items API CRUD', () => {
  let createdId: string;
  const uniqueName = `api-item-${Date.now()}`;

  // @covers-api: POST /api/items
  // @covers-interaction: api-post
  test('should create item', async ({ request }) => {
    const response = await request.post('/api/items', {
      data: { name: uniqueName, category: 'general', status: 'active' },
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(typeof body.id).toBe('string');
    expect(body.id.length).toBeGreaterThan(0);
    expect(body.name).toBe(uniqueName);
    createdId = body.id;
  });

  // @covers-api: GET /api/items/:id
  // @covers-interaction: api-get
  test('should get item by ID', async ({ request }) => {
    const response = await request.get(`/api/items/${createdId}`);
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.name).toBe(uniqueName);
    expect(typeof body.category).toBe('string');
    expect(typeof body.status).toBe('string');
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

    // State verification: GET to confirm update persisted
    const verify = await request.get(`/api/items/${createdId}`);
    expect(verify.status()).toBe(200);
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

  // @covers-interaction: api-post
  test('should reject invalid item data', async ({ request }) => {
    const response = await request.post('/api/items', {
      data: { name: '' }, // missing required fields
    });
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(typeof body.message).toBe('string');
    expect(body.message.length).toBeGreaterThan(0);
  });
});

test.describe('Auth Cookie Security', () => {
  // @covers-interaction: cookie-security
  test('should set secure cookie flags on login', async ({ request }) => {
    const response = await request.post('/api/auth/login', {
      data: { email: 'test@example.com', password: 'password' },
    });
    if (response.status() === 200) {
      const setCookie = response.headers()['set-cookie'] || '';
      expect(setCookie).toMatch(/httponly/i);
      expect(setCookie).toMatch(/samesite/i);
    }
  });

  // @covers-interaction: session-invalidation
  test('should invalidate session after logout', async ({ request }) => {
    // Login and save token
    const loginRes = await request.post('/api/auth/login', {
      data: { email: 'test@example.com', password: 'password' },
    });
    expect(loginRes.status()).toBe(200);
    const token = (await loginRes.json()).token;

    // Verify token works
    const protectedRes = await request.get('/api/user', {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(protectedRes.status()).toBe(200);

    // Logout
    await request.post('/api/auth/logout', {
      headers: { Authorization: `Bearer ${token}` },
    });

    // Reuse token — MUST get 401
    const reuseRes = await request.get('/api/user', {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(reuseRes.status()).toBe(401);
  });
});
```

### Data Rendering Verification

Verify tables/lists display correct structure and content.

```typescript
test.describe('Data Table Rendering', () => {
  // @covers-route: /items
  // @covers-interaction: data-rendering

  test('should render table with expected columns', async ({ page }) => {
    await page.goto('/items');
    const table = page.getByRole('table');
    await expect(table).toBeVisible({ timeout: 10000 });

    // Verify column headers (adapt to discovered column names)
    await expect(page.getByRole('columnheader', { name: /name/i })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: /status/i })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: /date|created/i })).toBeVisible();

    // Verify data rows exist
    const dataRows = table.getByRole('row').filter({ hasNot: page.getByRole('columnheader') });
    expect(await dataRows.count()).toBeGreaterThan(0);
  });
});
```

### Validation Testing

Test form validation for required fields, format errors, and boundary values.

```typescript
test.describe('Signup Validation', () => {
  // @covers-route: /signup
  // @covers-interaction: validation-error

  test.beforeEach(async ({ page }) => {
    await page.goto('/signup');
  });

  test('should require email field', async ({ page }) => {
    await page.getByLabel(/password/i).fill('ValidPass123!');
    await page.getByRole('button', { name: /register|sign up/i }).click();
    await expect(page.getByText(/email.*required|enter.*email/i)).toBeVisible();
  });

  test('should reject invalid email format', async ({ page }) => {
    await page.getByLabel(/email/i).fill('not-an-email');
    await page.getByLabel(/password/i).fill('ValidPass123!');
    await page.getByRole('button', { name: /register|sign up/i }).click();
    await expect(page.getByText(/invalid.*email|valid.*email/i)).toBeVisible();
  });

  test('should enforce password minimum length', async ({ page }) => {
    await page.getByLabel(/email/i).fill('test@example.com');
    await page.getByLabel(/password/i).fill('ab');
    await page.getByRole('button', { name: /register|sign up/i }).click();
    await expect(page.getByText(/too short|minimum|at least/i)).toBeVisible();
  });
});
```

---

## Quality Checklist

Before committing E2E tests:
- [ ] Tests pass locally (`yarn test:e2e`)
- [ ] No hardcoded credentials (use env vars)
- [ ] No hardcoded slugs or entity IDs (use dynamic creation or seed-data.json)
- [ ] Role-based locators used (no CSS selectors)
- [ ] Regex used for text assertions (i18n-friendly)
- [ ] Test file in correct directory (`tests/frontend/` or `tests/api/`)
- [ ] File named `{feature}.spec.ts` (kebab-case)
- [ ] Tests grouped with `test.describe`
- [ ] Each test has beforeEach/afterEach isolation (no shared state)
- [ ] Explicit timeouts for async assertions
- [ ] `e2e/.auth/` not committed (gitignored)
- [ ] `e2e/test-results/` not committed (gitignored)
- [ ] No status code array assertions (`expect([...]).toContain(status)`)
- [ ] No property-existence-only assertions on response bodies
- [ ] State verification present for POST/PUT/DELETE tests (follow-up GET)
- [ ] 5xx never accepted as valid test outcome
- [ ] Response body assertions check specific values, not just existence

## Email Capture Testing (Mailpit/MailHog)

When test infrastructure includes an email capture service (detected in `discovery/infrastructure.json`), use these patterns for email-dependent flows like password reset, MFA, and email verification.

### Password Reset Flow

```typescript
test.describe('Password Reset (full flow via email capture)', () => {
  const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:54324';
  const testEmail = `reset-${Date.now()}@test.example`;

  test.beforeAll(async ({ request }) => {
    // Create test user with known email (if signup API exists)
    await request.post('/api/auth/signup', {
      data: { email: testEmail, password: 'OldPass123!', name: 'Reset Test' }
    });
  });

  test.afterAll(async ({ request }) => {
    // Cleanup: delete test user if API supports it
    // Clear Mailpit messages for this email
    await request.delete(`${MAILPIT_URL}/api/v1/messages`, {
      params: { query: `to:${testEmail}` }
    });
  });

  test('should send reset email and allow password change', async ({ request }) => {
    // 1. Trigger password reset
    const triggerRes = await request.post('/api/auth/forgot-password', {
      data: { email: testEmail }
    });
    expect(triggerRes.status()).toBe(200);

    // 2. Wait for email delivery
    await new Promise(resolve => setTimeout(resolve, 2000));

    // 3. Poll email capture API
    const mailRes = await request.get(`${MAILPIT_URL}/api/v2/search`, {
      params: { query: `to:${testEmail}` }
    });
    const mail = await mailRes.json();
    expect(mail.messages.length).toBeGreaterThan(0);

    // 4. Extract reset token/link from email body
    const emailBody = mail.messages[0].Text || mail.messages[0].HTML;
    const resetMatch = emailBody.match(/https?:\/\/\S+reset\S*token=([^\s&"]+)/);
    expect(resetMatch).toBeTruthy();
    const resetToken = resetMatch![1];

    // 5. Use token to reset password
    const resetRes = await request.post('/api/auth/reset-password', {
      data: { token: resetToken, password: 'NewPass456!' }
    });
    expect(resetRes.status()).toBe(200);

    // 6. STATE VERIFICATION: login with new password
    const loginRes = await request.post('/api/auth/login', {
      data: { email: testEmail, password: 'NewPass456!' }
    });
    expect(loginRes.status()).toBe(200);
  });
});
```

### Adapting for Different Email Capture Tools

| Tool | API URL Pattern | Messages Endpoint | Search Param |
|------|----------------|-------------------|--------------|
| Mailpit | `http://localhost:8025` or `:54324` | `/api/v2/messages` | `?query=to:email` |
| MailHog | `http://localhost:1080` | `/api/v2/messages` | `?query=to:email` (different schema) |
| Inbucket | `http://localhost:9000` | `/api/v1/mailbox/{user}` | User part of email address |

Read `discovery/infrastructure.json` to determine which tool is available and its URL.

---

## See Also

- `skills/quality-checklist/SKILL.md` — Review gate criteria
- `skills/commit/SKILL.md` — Conventional commit format for test changes
