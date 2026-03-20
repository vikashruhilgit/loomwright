---
name: playwright-e2e
description: Write, run, and debug Playwright E2E tests using CLI. Covers test authoring, execution, debugging, reports, and CI integration.
allowed-tools: [Read, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
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

### Test Isolation (MANDATORY for generated tests)

Every test must be fully independent — no shared state across tests or files.

```typescript
test.describe('Members', () => {
  let createdId: string;

  test.beforeEach(async ({ request }) => {
    // Create unique fixture data for this test run
    const uniqueName = `test-member-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    const res = await request.post('/api/members', {
      data: { name: uniqueName, email: `${uniqueName}@test.example` },
      headers: { Authorization: `Bearer ${process.env.E2E_TOKEN}` },
    });
    const body = await res.json();
    createdId = body.id;
  });

  test.afterEach(async ({ request }) => {
    // Clean up to avoid data accumulation across runs
    if (createdId) {
      await request.delete(`/api/members/${createdId}`, {
        headers: { Authorization: `Bearer ${process.env.E2E_TOKEN}` },
      });
    }
  });

  test('member detail page loads', async ({ page }) => {
    await page.goto(`/members/${createdId}`);
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
test.describe('Create Tournament', () => {
  // @covers-route: /tournaments/create
  // @covers-interaction: form-submission

  test('should create tournament with valid data', async ({ page }) => {
    await page.goto('/tournaments/create');
    await page.getByLabel(/name/i).fill(`Test Tournament ${Date.now()}`);
    await page.getByLabel(/date/i).fill('2026-06-15');
    await page.getByLabel(/location/i).fill('Test Arena');
    await page.getByRole('combobox', { name: /format/i }).selectOption('round-robin');
    await page.getByRole('button', { name: /create|submit|save/i }).click();

    // Verify success feedback (toast, redirect, or new element)
    await expect(page.getByText(/created|success/i)).toBeVisible({ timeout: 10000 });
  });

  // @covers-interaction: validation-error
  test('should show validation errors for empty required fields', async ({ page }) => {
    await page.goto('/tournaments/create');
    await page.getByRole('button', { name: /create|submit|save/i }).click();

    // Verify validation messages appear
    await expect(page.getByText(/required|cannot be empty|please fill/i)).toBeVisible();
  });

  test('should reject invalid date format', async ({ page }) => {
    await page.goto('/tournaments/create');
    await page.getByLabel(/name/i).fill('Valid Name');
    await page.getByLabel(/date/i).fill('not-a-date');
    await page.getByRole('button', { name: /create|submit|save/i }).click();

    await expect(page.getByText(/invalid|format|valid date/i)).toBeVisible();
  });
});
```

### CRUD Create via UI

Create an entity through the UI form, then verify it appears in the list.

```typescript
test.describe('Member CRUD - Create', () => {
  // @covers-route: /members/new
  // @covers-interaction: form-submission
  const uniqueName = `test-member-${Date.now()}`;

  test('should create member and verify in list', async ({ page }) => {
    // Create
    await page.goto('/members/new');
    await page.getByLabel(/name/i).fill(uniqueName);
    await page.getByLabel(/email/i).fill(`${uniqueName}@test.example`);
    await page.getByRole('button', { name: /create|add|save/i }).click();
    await expect(page.getByText(/created|success/i)).toBeVisible({ timeout: 10000 });

    // Verify in list
    await page.goto('/members');
    await expect(page.getByText(uniqueName)).toBeVisible();
  });
});
```

### CRUD Update via UI

Navigate to edit form, modify fields, save, and verify changes persist.

```typescript
test.describe('Member CRUD - Update', () => {
  // @covers-route: /members/:id/edit
  // @covers-interaction: form-submission

  test('should update member name', async ({ page }) => {
    // Navigate to existing member (use seed data or create first)
    await page.goto('/members');
    await page.getByRole('link', { name: /edit/i }).first().click();

    // Modify
    const updatedName = `updated-${Date.now()}`;
    await page.getByLabel(/name/i).clear();
    await page.getByLabel(/name/i).fill(updatedName);
    await page.getByRole('button', { name: /save|update/i }).click();

    // Verify
    await expect(page.getByText(/updated|saved|success/i)).toBeVisible({ timeout: 10000 });
    await page.goto('/members');
    await expect(page.getByText(updatedName)).toBeVisible();
  });
});
```

### CRUD Delete via UI

Click delete, handle confirmation dialog, verify entity is removed.

```typescript
test.describe('Member CRUD - Delete', () => {
  // @covers-route: /members/:id
  // @covers-interaction: button-click
  // @covers-interaction: modal

  test('should delete member with confirmation', async ({ page }) => {
    await page.goto('/members');
    const memberName = await page.getByRole('row').nth(1).getByRole('cell').first().innerText();

    // Click delete
    await page.getByRole('row').nth(1).getByRole('button', { name: /delete|remove/i }).click();

    // Handle confirmation dialog
    await expect(page.getByRole('dialog')).toBeVisible();
    await page.getByRole('dialog').getByRole('button', { name: /confirm|yes|delete/i }).click();

    // Verify removed
    await expect(page.getByText(/deleted|removed/i)).toBeVisible({ timeout: 10000 });
    await expect(page.getByText(memberName)).not.toBeVisible();
  });
});
```

### Modal Interaction Pattern

Open modal via trigger, interact with contents, close, and verify state.

```typescript
test.describe('Invite Member Modal', () => {
  // @covers-route: /members
  // @covers-interaction: modal

  test('should open invite modal and submit', async ({ page }) => {
    await page.goto('/members');

    // Open modal
    await page.getByRole('button', { name: /invite|add member/i }).click();
    await expect(page.getByRole('dialog')).toBeVisible();

    // Interact with modal form
    await page.getByRole('dialog').getByLabel(/email/i).fill(`invite-${Date.now()}@test.example`);
    await page.getByRole('dialog').getByRole('button', { name: /send|invite|submit/i }).click();

    // Verify modal closes and feedback shown
    await expect(page.getByRole('dialog')).not.toBeVisible();
    await expect(page.getByText(/invited|sent/i)).toBeVisible();
  });

  test('should close modal via cancel', async ({ page }) => {
    await page.goto('/members');
    await page.getByRole('button', { name: /invite|add member/i }).click();
    await expect(page.getByRole('dialog')).toBeVisible();

    await page.getByRole('dialog').getByRole('button', { name: /cancel|close/i }).click();
    await expect(page.getByRole('dialog')).not.toBeVisible();
  });
});
```

### API CRUD Pattern

Full create-read-update-delete cycle via API with cleanup.

```typescript
test.describe('Tournaments API CRUD', () => {
  let createdId: string;
  const uniqueName = `api-tournament-${Date.now()}`;

  // @covers-api: POST /api/tournaments
  // @covers-interaction: api-post
  test('should create tournament', async ({ request }) => {
    const response = await request.post('/api/tournaments', {
      data: { name: uniqueName, format: 'round-robin', date: '2026-06-15' },
    });
    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body).toHaveProperty('id');
    expect(body.name).toBe(uniqueName);
    createdId = body.id;
  });

  // @covers-api: GET /api/tournaments/:id
  // @covers-interaction: api-get
  test('should get tournament by ID', async ({ request }) => {
    const response = await request.get(`/api/tournaments/${createdId}`);
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.name).toBe(uniqueName);
    expect(body).toHaveProperty('format');
    expect(body).toHaveProperty('date');
  });

  // @covers-api: PUT /api/tournaments/:id
  // @covers-interaction: api-put
  test('should update tournament', async ({ request }) => {
    const response = await request.put(`/api/tournaments/${createdId}`, {
      data: { name: `${uniqueName}-updated` },
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.name).toContain('updated');
  });

  // @covers-api: DELETE /api/tournaments/:id
  // @covers-interaction: api-delete
  test('should delete tournament and verify gone', async ({ request }) => {
    const del = await request.delete(`/api/tournaments/${createdId}`);
    expect([200, 204]).toContain(del.status());

    const get = await request.get(`/api/tournaments/${createdId}`);
    expect(get.status()).toBe(404);
  });

  // @covers-interaction: api-post
  test('should reject invalid tournament data', async ({ request }) => {
    const response = await request.post('/api/tournaments', {
      data: { name: '' }, // missing required fields
    });
    expect(response.status()).toBe(400);
    const body = await response.json();
    expect(body).toHaveProperty('message');
  });
});
```

### Data Rendering Verification

Verify tables/lists display correct structure and content.

```typescript
test.describe('League Standings', () => {
  // @covers-route: /leagues/:id/standings
  // @covers-interaction: data-rendering

  test('should render standings table with expected columns', async ({ page }) => {
    await page.goto('/leagues/1/standings');
    const table = page.getByRole('table');
    await expect(table).toBeVisible({ timeout: 10000 });

    // Verify column headers (from discovery data)
    await expect(page.getByRole('columnheader', { name: /team/i })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: /wins/i })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: /losses/i })).toBeVisible();

    // Verify data rows exist
    const dataRows = table.getByRole('row').filter({ hasNot: page.getByRole('columnheader') });
    expect(await dataRows.count()).toBeGreaterThan(0);
  });
});
```

### Validation Testing

Test form validation for required fields, format errors, and boundary values.

```typescript
test.describe('Registration Validation', () => {
  // @covers-route: /auth/register
  // @covers-interaction: validation-error

  test.beforeEach(async ({ page }) => {
    await page.goto('/auth/register');
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

## See Also

- `skills/quality-checklist/SKILL.md` — Review gate criteria
- `skills/commit/SKILL.md` — Conventional commit format for test changes
