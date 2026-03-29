---
name: qa-test-patterns
description: Test Pattern Library, assertion rules, and generation rules for QA Executor. Contains all test generation patterns including signal-driven security, UI interaction, and API test patterns.
allowed-tools: [Read, Write, Edit, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# QA Test Patterns

Test Pattern Library, assertion rules, and generation rules for QA Executor test generation.

---

## ASSERTION RULES

These rules are MANDATORY for ALL tests in ALL depth modes. Every test you generate MUST follow these rules. Tests that violate them will be REJECTED by the QA Strategist.

```
HTTP STATUS RULES:
  - ALWAYS assert exact expected status: expect(response.status()).toBe(200)
  - NEVER use toContain with status arrays:
      BAD:  expect([200, 401, 500]).toContain(response.status())
      GOOD: expect(response.status()).toBe(200)
  - Only acceptable multi-status: DELETE may return 200 or 204:
      const delStatus = response.status();
      expect(delStatus === 200 || delStatus === 204).toBe(true);
  - 5xx is ALWAYS a bug. If any endpoint returns 500:
      1. Fail the test: expect(response.status()).toBeLessThan(500)
      2. Create a BLOCKING bug report with endpoint, payload, and response body
      3. NEVER treat 500 as an acceptable alternate outcome
  - NEVER silently skip on non-200: no `if (response.status() !== 200) return;`

RESPONSE BODY RULES:
  - Assert specific VALUES, not just property existence:
      BAD:  expect(body).toHaveProperty('name')
      GOOD: expect(body.name).toBe(expectedName)
  - For dynamic values (IDs, timestamps), assert type + constraints:
      expect(typeof body.id).toBe('string');
      expect(body.id.length).toBeGreaterThan(0);
  - For created/updated resources, verify input values echoed back:
      const payload = { name: 'Test Item', price: 29.99 };
      expect(body.name).toBe(payload.name);
      expect(body.price).toBe(payload.price);
  - For arrays/lists, assert length AND first item structure:
      expect(body.items.length).toBeGreaterThan(0);
      expect(typeof body.items[0].id).toBe('string');

FRONTEND RULES:
  - NEVER assert just text length as proxy for content:
      BAD:  expect((await el.innerText()).length).toBeGreaterThan(10)
      GOOD: await expect(page.getByRole('heading', { name: /dashboard/i })).toBeVisible()
  - Assert specific visible elements: headings, form labels, button text, data values
  - For forms: fill EVERY required field, submit, verify success/error BY SPECIFIC TEXT
  - For tables: verify column headers BY NAME, row count > 0, at least one cell value

LOCATOR RULES (MANDATORY for all frontend tests):
  - NEVER use CSS selectors:
      BAD:  page.locator('input[type="email"]')
      BAD:  page.locator('.login-form button')
      BAD:  page.locator('#submit-btn')
      BAD:  page.locator('div > span.error')
  - ALWAYS use role-based or semantic locators:
      GOOD: page.getByRole('textbox', { name: /email/i })
      GOOD: page.getByLabel(/email/i)
      GOOD: page.getByPlaceholder(/email/i)
      GOOD: page.getByRole('button', { name: /sign in|log in|submit/i })
  - For forms: use getByLabel() matching the visible label text
  - For buttons: use getByRole('button', { name: /text/i })
  - For links: use getByRole('link', { name: /text/i })
  - For headings: use getByRole('heading', { name: /text/i })
  - For text content: use getByText(/text/i)

STATE VERIFICATION RULES (MANDATORY for ALL mutation tests -- CRUD and auth):
  - After POST (create): GET the created resource, verify fields match what was sent
  - After PUT (update): GET the updated resource, verify changed fields persisted
  - After DELETE: GET the deleted resource, verify 404 response
  - Never assume a mutation succeeded without a follow-up read verification

  AUTH STATE VERIFICATION (MANDATORY -- not just CRUD):
  - Signup test -> MUST verify login works with the new credentials
  - Login test -> MUST verify access to a protected resource succeeds
  - Logout test -> MUST verify session is dead (reuse token -> expect 401)
  - Password reset test -> MUST verify login works with the new password
  - Password change test -> MUST verify old password no longer works
  - A test that only checks the response code of an auth endpoint without
    verifying the state change is INCOMPLETE. Strategist gate audit will catch this.

SESSION INVALIDATION RULE (MANDATORY for any auth flow test):
  - Logout tests MUST verify the session is actually invalidated:
      1. Login -> save auth token/cookie
      2. Access protected endpoint -> verify 200
      3. Logout -> verify 200
      4. Reuse saved auth token/cookie -> access same protected endpoint
      5. MUST get 401 (not 200) -- if 200, create BLOCKING bug
  - A logout that returns 200 but doesn't invalidate the session is a security vulnerability

SECURITY ASSERTION RULES:
  - XSS test MUST verify the payload is escaped in the response, not just that the server didn't crash:
      BAD:  expect(response.status()).toBeLessThan(500)  // only checks "didn't crash"
      GOOD: const body = await response.json();
            expect(body.name).not.toContain('<script>');  // verifies escaping
            // OR: expect(response.status()).toBe(400);   // input rejected
  - SQL injection test MUST verify no 500 AND input is rejected:
      const res = await request.post('/api/entities', {
        data: { name: "'; DROP TABLE entities; --" }
      });
      expect(res.status()).not.toBe(500);  // 500 = likely vulnerable
      expect(res.status()).toBe(400);       // should reject the input
  - Cookie security: for any endpoint that sets cookies (detected via Set-Cookie header), verify:
      const setCookie = response.headers()['set-cookie'] || '';
      expect(setCookie).toMatch(/httponly/i);     // prevents JS access
      expect(setCookie).toMatch(/samesite/i);     // CSRF protection
      // Secure flag: only enforce on non-localhost (HTTPS required)
      if (!baseURL.includes('localhost') && !baseURL.includes('127.0.0.1')) {
        expect(setCookie).toMatch(/secure/i);    // cookie only sent over HTTPS
      }
      // If any flag missing, create HIGH severity bug

THE 5xx RULE:
  A 500 response is ALWAYS a server bug, never an expected test outcome.
  If any test receives a 500:
    1. The test MUST fail
    2. A BLOCKING bug report MUST be created
    3. Never use expect([200, 500]).toContain(status) -- this masks real bugs
```

---

## TEST DIRECTORY RULES

These rules are MANDATORY before generating any test file.

```
1. Read playwright.config.ts -> extract testDir value (e.g., './tests', './e2e/tests')
2. Write ALL test files ONLY to {testDir}/frontend/ and {testDir}/api/
3. NEVER write tests to a second directory -- no duplicates
4. If playwright.config has no separate frontend/api projects:
   - Create frontend-ui project (browser tests, testMatch: 'frontend/**/*.spec.ts')
   - Create api-smoke project (API tests, testMatch: 'api/**/*.spec.ts')
5. If {testDir}/frontend/ or {testDir}/api/ doesn't exist, create it
6. NEVER use hardcoded 'e2e/tests/' -- always use the testDir from config
```

---

## Depth Mode: smoke

L1 original behavior.

```
For each route in priority order (HIGH first, then MEDIUM, then LOW):

  UI/E2E tests -> {testDir}/frontend/{feature}.spec.ts
    - Happy path: navigate, verify key elements visible
    - Error path (HIGH risk only): invalid input, verify error message
    - Coverage annotations: // @covers-route: {route}

  ALL tests MUST follow ASSERTION RULES above. Even smoke tests use strict assertions.

  API tests -> {testDir}/api/{feature}.spec.ts
    - GET: assert status toBe(200) + response body field types (not just property existence)
    - POST/PUT/DELETE: assert status toBe(401) without token
    - ALL: if any endpoint returns 5xx, create BLOCKING bug and fail the test
    - Coverage annotations: // @covers-api: {METHOD} {path}
```

---

## Depth Mode: functional (DEFAULT)

Discovery-driven pattern selection. ALL tests MUST follow the ASSERTION RULES section above. No toContain with status arrays. No toHaveProperty without values. 5xx = BLOCKING bug. Mutations need follow-up GET verification.

Instead of risk-level-only generation, use **discovery data to select test patterns**. Match discovered interactions to the Test Pattern Library below.

### Test Pattern Library -- pattern selection by discovery signal

| Discovery Signal | Test Pattern | Coverage Annotation | Assertion Depth |
|---|---|---|---|
| Form with inputs | Fill valid data -> submit -> verify success BY SPECIFIC TEXT; Fill invalid/empty -> verify PER-FIELD error messages | `@covers-interaction: form-submission` | Exact text match on success/error messages |
| API POST endpoint | Valid payload -> verify 201 + body VALUES match sent payload; Invalid -> 400 + error names the invalid field; Empty body -> 400 | `@covers-interaction: api-post` | Field-level value matching via toBe/toEqual |
| API PUT endpoint | Update -> verify 200 + GET to confirm changes PERSISTED | `@covers-interaction: api-put` | State verification via follow-up GET |
| API DELETE endpoint | Delete -> verify exactly 200 or 204 -> GET -> verify exactly 404 | `@covers-interaction: api-delete` | Exact status + follow-up 404 verification |
| API GET endpoint | Call -> verify 200 + field VALUES and types from discovery (not just property names) | `@covers-interaction: api-get` | Type + value assertions on response fields |
| Button (non-form) | Click -> verify expected outcome (navigation change, modal open, state change) | `@covers-interaction: button-click` | Specific URL/element/state assertion |
| Modal detected | Open modal via trigger -> interact with contents -> close -> verify state | `@covers-interaction: modal` | Content assertions inside modal |
| Table/list rendering | Verify column headers BY NAME, row count > 0, at least one cell value matches data | `@covers-interaction: data-rendering` | Column header names + cell value assertions |
| Auth-gated route | Access without auth -> verify 401/redirect to login | `@covers-interaction: auth-gate` | Exact 401 status or login URL assertion |
| API POST/PUT (negative) | Empty body -> 400; Missing required fields -> 400 with field name; Wrong types -> 400 | `@covers-interaction: negative-test` | Exact 400 status + error field identification |
| Auth endpoint (negative) | No token -> 401; Invalid token -> 401 | `@covers-interaction: auth-negative` | Exact 401 status |
| Form with submit button (HIGH/MEDIUM) | Submit -> verify loading indicator (spinner, disabled button, or aria-busy) appears -> disappears after response | `@covers-interaction: loading-state` | Loading element visible during submission |
| Form with multiple inputs (HIGH) | Tab through all fields -> verify focus reaches each -> Enter on last field -> verify submission | `@covers-interaction: keyboard-nav` | Focus moves to each field in DOM order |
| Form with validation rules (HIGH) | Submit invalid -> see errors -> fix each errored field -> resubmit -> verify success | `@covers-interaction: error-recovery` | Success after correcting invalid inputs |
| Endpoint returns rate limit headers | Send N+1 requests -> verify (N+1)th returns 429 + Retry-After header. Skip if N > 20 | `@covers-interaction: rate-limit-verify` | Exact 429 status + header present |
| Endpoint sets cookies (Set-Cookie) | Verify HttpOnly, SameSite flags. Verify Secure flag (skip for localhost) | `@covers-interaction: cookie-security` | All security flags present |
| Endpoint changes credentials (modifies_secret_material) | Use old session after credential change -> expect 401. Old credential must be denied | `@covers-interaction: credential-change-verify` | 401 on old credential reuse |
| Endpoint returns setup data with secret/code | Test wrong value -> expect 400/403; Test expired value; Test reused value (replay protection) | `@covers-interaction: secret-verify` | Exact rejection status codes |
| API response has sensitive_fields_exposed | Verify password, hash, secret, token, stackTrace fields are NOT in response (or redacted) | `@covers-interaction: response-leak-check` | Sensitive fields absent |
| API error response (4xx/5xx) | Verify no stack traces, file paths, or SQL queries in error body | `@covers-interaction: error-leak-check` | No implementation details leaked |
| Prior scope found HIGH/BLOCKING bug affecting current scope | Generate regression test verifying bug impact on this scope's endpoints | `@covers-interaction: cross-scope-regression` | Exact status/behavior check |
| POST endpoint returns 201 (HIGH risk) | Send same payload twice sequentially -> verify second is 409/400/200 (not 500). Document if non-idempotent | `@covers-interaction: idempotency-check` | No 500 on duplicate |
| Endpoint has slow_endpoint: true (>3s in crawl) | Add expect(responseTime).toBeLessThan(5000) assertion | `@covers-interaction: response-time-check` | Response under 5s threshold |
| Endpoint URL contains tenant scope ([slug], [orgId], [tenantId]) + requires auth | Authenticate as user from tenant A, access tenant B's endpoint -> expect 403 or 404 | `@covers-interaction: cross-tenant-access` | Exact 403/404, never 200 |

### Risk level controls depth within each pattern

| Risk | smoke | functional |
|---|---|---|
| HIGH | Navigate + verify visible | All matched patterns + valid + invalid + error paths |
| MEDIUM | Navigate + verify visible | All matched patterns + valid data only |
| LOW | Navigate + verify title | Navigate + verify content renders correctly |

### Test file grouping (budget optimization)

- Group 5-10 tests per spec file by feature area (not 1 test per file)
- Example: `auth.spec.ts` contains login form, register form, forgot-password tests
- Same number of Write tool calls, much deeper test coverage

---

## UI/E2E Generation Patterns

```
OVERLAP CHECK (before generating each test file):
  Before writing tests for a feature, glob for existing test files covering same routes:
    Glob: {testDir}/**/*{feature}*.spec.ts, tests/**/*{feature}*.spec.ts
  If existing spec covers the same endpoint:
    - Read it. Check assertion quality against current rules.
    - If HIGH quality (strict assertions, state verification, coverage annotations):
      SKIP generating new tests for those endpoints.
      Record in coverage: "covered by existing {file}" with @covers-api annotations.
    - If LOW quality (lenient assertions, no state verification):
      Generate new tests. Add header comment: "// Supplements existing {file} with stricter assertions"
  NEVER generate a file that fully duplicates existing coverage.
  Pre-existing coverage counts toward route/API coverage in Phase 6.

For each route in priority order (HIGH first, then MEDIUM, then LOW):
  Generate BOTH the API test file AND the UI test file for this feature
  before moving to the next feature.
  Per feature area (e.g., "auth", "organizations"):
    1. Write {testDir}/api/{feature}.spec.ts (all API tests for this feature)
    2. Write {testDir}/frontend/{feature}.spec.ts (all UI tests for this feature)
    3. Then move to next feature
  This ensures budget exhaustion cuts evenly across UI and API layers,
  not all API files first then all UI files last.
  Note: test file grouping (5-10 tests per spec file by feature) is unchanged --
  this only changes the ORDER files are written, not how tests are grouped.

  BUDGET PRIORITY: If budget reaches YELLOW zone (60%) and UI tests for the
  current feature have NOT been generated yet: generate them BEFORE moving to
  the next feature. UI tests for HIGH risk forms have HIGHER priority than
  API tests for MEDIUM risk routes.

  For each route/feature:

  1. Read route's discovery data from sitemap.json + api-calls.json
  2. Match discovery signals to Test Pattern Library (table above)
  3. Generate tests for ALL matched patterns (not just "navigate + verify visible")

  UI/E2E tests -> {testDir}/frontend/{feature}.spec.ts
    For each discovered form on the route:
      - Test: fill all required fields with valid data -> submit -> verify success (toast, redirect, or new element)
      - Test (HIGH risk): fill invalid data per field -> submit -> verify validation error messages
      - Test (HIGH risk): submit empty required fields -> verify required-field errors
      - Coverage: // @covers-route: {route}  // @covers-interaction: form-submission

    For each discovered form with a submit button (HIGH/MEDIUM risk):
      - Test: fill form -> submit -> verify loading indicator (spinner, disabled button,
        or aria-busy) appears during submission -> verify it disappears after response
      - Coverage: // @covers-interaction: loading-state

    For each discovered form with multiple inputs (HIGH risk):
      - Test: Tab through all required fields -> verify focus reaches each field
        -> press Enter -> verify form submits
      - Coverage: // @covers-interaction: keyboard-nav

    For each discovered form with validation rules (HIGH risk):
      - Test: submit with invalid data -> verify errors -> fix each errored field
        -> resubmit -> verify success
      - Coverage: // @covers-interaction: error-recovery

    For each discovered button (non-form, non-destructive):
      - Test: click -> verify outcome (URL change, modal open, content update)
      - Coverage: // @covers-interaction: button-click

    For each discovered modal:
      - Test: trigger modal -> verify modal content -> interact -> close
      - Coverage: // @covers-interaction: modal

    For each discovered table/list:
      - Test: verify headers present, row count > 0, sample data renders
      - Coverage: // @covers-interaction: data-rendering

    For auth-gated routes:
      - Test: access without auth -> verify redirect to login or 401
      - Coverage: // @covers-interaction: auth-gate
```

---

## API Generation Patterns

```
  API tests -> {testDir}/api/{feature}.spec.ts
    For each intercepted GET endpoint:
      - Test: call -> assert status toBe(200) -> assert response body field VALUES match expected types and constraints (not just property existence)
      - For arrays: assert length > 0 AND first item has expected fields with correct types
      - Coverage: // @covers-api: GET {path}  // @covers-interaction: api-get

    For each GET list endpoint that supports pagination (detected from query params like limit, offset, page, cursor):
      - Test: call with default params -> verify response has pagination metadata (total, page, limit, or next cursor)
      - Test: call with page=1&limit=5 -> verify response has <= 5 items
      - Test: call with page=2 -> verify different items than page 1
      - Test: call with page=0 or page=-1 -> verify 400 (not 500)
      - Test: call with limit=0 -> verify 400 (not 500)
      - Coverage: // @covers-api: GET {path}  // @covers-interaction: pagination

    For each intercepted POST endpoint:
      - Test: send valid payload (field names from request_body_fields) -> assert status toBe(201) -> assert response body VALUES MATCH sent payload fields
      - Test (HIGH risk): send invalid payload -> assert status toBe(400) -> assert error message names the invalid field
      - Test (HIGH risk): send empty body {} -> assert status toBe(400) (NOT 500 -- if 500, create BLOCKING bug)
      - Test: send without auth -> assert status toBe(401)
      - State verification: after successful POST, GET the created resource and verify fields match
      - Coverage: // @covers-api: POST {path}  // @covers-interaction: api-post

    For each intercepted PUT endpoint:
      - Test: send update (fields from request_body_fields) -> assert status toBe(200)
      - State verification: GET the updated resource -> assert changed fields PERSISTED (not just in response)
      - Test: send without auth -> assert status toBe(401)
      - Coverage: // @covers-api: PUT {path}  // @covers-interaction: api-put

    For each intercepted DELETE endpoint:
      - Test: delete entity -> assert status is exactly 200 or 204 (NOT array toContain) -> GET deleted resource -> assert status toBe(404)
      - Test: send without auth -> assert status toBe(401)
      - Coverage: // @covers-api: DELETE {path}  // @covers-interaction: api-delete
```

---

## Common Rules (Both Modes)

```
Test isolation requirements (MANDATORY):
  - Every test must be fully independent -- no shared state
  - Use test.beforeEach to set up required data/auth state
  - Use test.afterEach to clean up any created data
  - Never rely on test execution order
  - Use unique identifiers per test run (Date.now(), crypto.randomUUID())
    to avoid collisions with existing data
  - For auth-gated routes: include storageState setup or login step in beforeEach
  - Do NOT use shared login state across test files without explicit storageState

SHARED HELPERS RULE:
  If 2+ test files need the same utility (auth login, API helpers, data factories):
    1. Check if {testDir}/helpers/ directory exists
    2. If not: create it
    3. Generate shared helper file (e.g., {testDir}/helpers/auth.ts):
         export async function loginAs(request: APIRequestContext, email: string, password: string) {
           const res = await request.post('/api/auth/login', { data: { email, password } });
           return res.headers()['set-cookie'] || '';
         }
    4. All spec files import from helpers/ -- NEVER copy/paste utility functions
    5. NEVER inline complex type annotations for request parameters
  This applies to: auth login helpers, API request wrappers, test data factories.

TEST DATA SETUP (MANDATORY):
  Detect API dependencies from URL patterns:
    - If API has /api/{parent}/{id}/{child} -> creating a child requires a parent first
    - Nested URL = parent resource must exist before child can be tested

  Setup strategy:
    1. Identify parent resources from URL nesting
    2. In test.beforeAll: create parent resources via API (POST /api/{parent})
    3. Store created IDs for use in child tests
    4. In test.afterAll: clean up created resources (DELETE, reverse creation order)
    5. Use unique names per test run to avoid collisions (Date.now() suffix)

  Cross-scope setup:
    - If this scope's APIs need resources from another scope,
      create minimal parent resources in beforeAll -- don't depend on other scope's tests
    - Each scope must be independently runnable

  SEED DATA USAGE RULES:
    - READ-only tests (GET, list, verify existence): MAY use seed-data.json IDs
    - MUTATION tests (POST, PUT, DELETE, create, update): MUST create own data
      in beforeAll/beforeEach with unique identifiers (Date.now())
    - Never mutate seed data -- it breaks other tests and future runs
    - For scope-dependent entities (e.g., org-scoped resources): create a test
      parent entity in beforeAll rather than depending on seed data slugs

Locator and assertion rules:
  - Role-based locators: getByRole, getByLabel, getByText
  - Regex assertions for text matching
  - No hardcoded waits, no CSS selectors
  - Group with test.describe('{Feature Name}', ...)
```

---

## BLOCKER-FIRST RULE

```
BLOCKER-FIRST RULE (before generating negative/boundary tests):
  For each endpoint, the happy-path test MUST be generated FIRST.
  During Phase 4.6 (dry-run gate), if a happy-path test returns 5xx:
    - File BLOCKING bug immediately for that endpoint
    - SKIP all negative, boundary, idempotency, and security tests for it
    - Add to discovery_warnings: "Endpoint {path} returns 500 on happy path -- skipped {N} secondary tests"
  Do NOT spend budget testing error handling on an endpoint that can't handle success.
  This saves 4-8 tool calls per broken endpoint.
```

---

## NEGATIVE TESTING PATTERNS

Functional depth, HIGH/MEDIUM risk.

```
For every API POST/PUT endpoint (HIGH risk):
  - Empty body test:
      const response = await request.post('/api/endpoint', { data: {} });
      expect(response.status()).toBe(400); // NOT 500 -- if 500, create BLOCKING bug
  - Missing required field test (one per required field from discovery):
      const response = await request.post('/api/endpoint', {
        data: { /* omit 'name' */ price: 10 }
      });
      expect(response.status()).toBe(400);
      const body = await response.json();
      expect(JSON.stringify(body)).toMatch(/name/i); // error should name the field
  - Wrong type test:
      const response = await request.post('/api/endpoint', {
        data: { name: 12345, price: 'not-a-number' }
      });
      expect(response.status()).toBe(400);
  - Coverage: // @covers-interaction: negative-test

For every authenticated endpoint (HIGH risk):
  - No auth header test:
      const response = await request.get('/api/protected');
      expect(response.status()).toBe(401);
  - Invalid token test:
      const response = await request.get('/api/protected', {
        headers: { Authorization: 'Bearer invalid-token-xyz' }
      });
      expect(response.status()).toBe(401);
  - Coverage: // @covers-interaction: auth-negative

For every form (HIGH risk):
  - Submit empty test: click submit without filling -> verify per-field validation errors appear
  - Submit invalid values: fill known-invalid data -> verify specific error message per field

Boundary value tests (MANDATORY for functional depth, HIGH risk -- Phase 4.7 enforces this):
  For each text field accepting user input (from discovery):
    - Oversized input: 1000+ character string -> expect 400 (or truncation, not 500)
    - Special characters: quotes, slashes, unicode, emojis -> expect 200 or 400 (not 500)
    - SQL-like strings: "' OR 1=1 --" -> expect 400 (not 500)
    - Empty string (distinct from missing field) -> expect 400 or valid handling
    - Missing field vs null vs empty string (3 different cases)
  For each numeric field:
    - Zero -> expect 200 or 400 (depends on business rule)
    - Negative number -> expect 400 (for quantities, prices, counts)
    - Very large number (Number.MAX_SAFE_INTEGER) -> expect 400 or valid handling
  For each date field:
    - Date in far past (1900-01-01) -> expect 400 or valid handling
    - Date in far future (2099-12-31) -> expect 400 or valid handling
    - Invalid date format ("not-a-date") -> expect 400
  Coverage: // @covers-interaction: boundary-test
  NOTE: If no boundary tests are generated for a HIGH risk endpoint with text input,
        Phase 4.7 Gate 4 will catch this and generate them.

Error message quality (functional depth, HIGH risk):
  When a 400 response is returned, verify the error message is descriptive:
    BAD:  expect(response.status()).toBe(400); // only checks status
    GOOD: expect(response.status()).toBe(400);
          const body = await response.json();
          expect(body.message || body.error).toBeDefined();
          expect((body.message || body.error).length).toBeGreaterThan(5);
  If error body is empty or just "Bad Request" -> create MEDIUM bug (unhelpful error message)

For MEDIUM risk: include empty-body, missing-required-field, and error message quality tests.
For LOW risk: skip negative tests.
```

---

## MULTI-STEP FLOW TESTING

Functional depth, HIGH risk.

```
For every entity with CRUD API endpoints, generate a CRUD lifecycle test:
  test('CRUD lifecycle: [entity]', async ({ request }) => {
    // 1. CREATE
    const createRes = await request.post('/api/entities', { data: payload });
    expect(createRes.status()).toBe(201);
    const created = await createRes.json();
    const id = created.id;
    // 2. READ and verify
    const readRes = await request.get(`/api/entities/${id}`);
    expect(readRes.status()).toBe(200);
    expect((await readRes.json()).name).toBe(payload.name);
    // 3. UPDATE
    const updateRes = await request.put(`/api/entities/${id}`, { data: { name: 'Updated' } });
    expect(updateRes.status()).toBe(200);
    // 4. VERIFY update persisted
    const verifyRes = await request.get(`/api/entities/${id}`);
    expect((await verifyRes.json()).name).toBe('Updated');
    // 5. DELETE
    const delRes = await request.delete(`/api/entities/${id}`);
    const delStatus = delRes.status();
    expect(delStatus === 200 || delStatus === 204).toBe(true);
    // 6. VERIFY gone
    const goneRes = await request.get(`/api/entities/${id}`);
    expect(goneRes.status()).toBe(404);
  });

AUTH LINEAR CHAINS (MANDATORY for HIGH risk auth flows -- L1-legal):
If login AND signup/register endpoints are both discovered, generate:

  test('auth chain: signup -> login -> access protected -> logout -> verify denied', async ({ request }) => {
    const email = `chain-${Date.now()}@test.example`;
    const password = 'ValidPass123!';

    // 1. SIGNUP
    const signup = await request.post('/api/auth/signup', { data: { email, password, name: 'Chain Test' } });
    expect(signup.status()).toBe(201);

    // 2. LOGIN with new credentials (STATE VERIFICATION of signup)
    const login = await request.post('/api/auth/login', { data: { email, password } });
    expect(login.status()).toBe(200);
    const { token } = await login.json();
    expect(token).toBeTruthy();

    // 3. ACCESS protected resource (STATE VERIFICATION of login)
    const protectedRes = await request.get('/api/user', {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(protectedRes.status()).toBe(200);

    // 4. LOGOUT
    const logout = await request.post('/api/auth/logout', {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(logout.status()).toBe(200);

    // 5. VERIFY DENIED -- reuse old token (STATE VERIFICATION of logout)
    const denied = await request.get('/api/user', {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(denied.status()).toBe(401);

    // 6. CLEANUP -- delete the test user if API supports it
    // If admin delete exists: await adminRequest.delete(`/api/users/${userId}`);
  });

  Coverage: // @covers-interaction: auth-chain  // @covers-interaction: credential-change-verify

If only login and logout are discovered (no signup), generate:
  Login -> access protected -> logout -> reuse same auth -> verify 401

These chains are L1-legal because they are:
  - Single test function, 3-5 ordered steps, single path, no branching
  - NOT L2 journey graphs (no state combinations, no branching paths, no journey coverage tracking)

For business workflows detected from route clusters:
  Connect 2-3 related HIGH risk routes into a single flow test
```

---

## DATA INTEGRITY PROBES

Functional depth, HIGH risk.

```
For EVERY HIGH risk POST endpoint that returns 201 (resource creation):
  - Concurrent creation race condition:
      const [res1, res2] = await Promise.all([
        request.post('/api/entities', { data: payload1 }),
        request.post('/api/entities', { data: payload2 }),
      ]);
      // At least one should succeed, verify constraint is enforced
      const statuses = [res1.status(), res2.status()].sort();
      // If both return 201 when only one should, create BLOCKING bug

  - Duplicate creation:
      const first = await request.post('/api/entities', { data: samePayload });
      expect(first.status()).toBe(201);
      const second = await request.post('/api/entities', { data: samePayload });
      // Should get 409 (conflict) or 400, NOT another 201
      const secondStatus = second.status();
      expect(secondStatus === 400 || secondStatus === 409 || secondStatus === 422).toBe(true);

  - Cascade delete verification:
      // Create parent -> create child linked to parent -> delete parent -> verify child state
      // Child should be deleted (cascade) or return orphan-safe response

  - Idempotency test:
      // Submit same valid payload twice SEQUENTIALLY (not concurrently)
      const first = await request.post('/api/entities', { data: payload });
      expect(first.status()).toBe(201);
      const second = await request.post('/api/entities', { data: payload });
      // Second should be 409 (conflict), 200 (idempotent), or 201 (non-idempotent)
      // But NEVER 500 -- if 500, create BLOCKING bug
      expect(second.status()).not.toBe(500);
      // Document actual behavior in test comments

Coverage: // @covers-interaction: data-integrity
```

---

## SECURITY BOUNDARY TESTING

Functional depth, HIGH risk.

```
For every authenticated endpoint with resource-specific access:
  - Cross-resource access (IDOR):
      // User A creates a resource, User B tries to access it
      const created = await userARequest.post('/api/entities', { data: payload });
      const id = (await created.json()).id;
      const cross = await userBRequest.get(`/api/entities/${id}`);
      const crossStatus = cross.status();
      expect(crossStatus === 403 || crossStatus === 404).toBe(true); // NOT 200

  - Role escalation:
      // Regular user tries to assign admin role
      const res = await regularUserRequest.post('/api/users/roles', {
        data: { role: 'admin' }
      });
      expect(res.status()).toBe(403);

  - Session invalidation after logout:
      // Login -> save auth -> logout -> reuse saved auth -> expect 401
      const loginRes = await request.post('/api/auth/login', { data: creds });
      const token = (await loginRes.json()).token;
      await request.post('/api/auth/logout', { headers: { Authorization: `Bearer ${token}` } });
      const reuse = await request.get('/api/protected', {
        headers: { Authorization: `Bearer ${token}` }
      });
      expect(reuse.status()).toBe(401);

For every endpoint accepting user text input:
  - XSS probe:
      const res = await request.post('/api/entities', {
        data: { name: '<script>alert(1)</script>' }
      });
      if (res.status() === 201) {
        const body = await res.json();
        expect(body.name).not.toContain('<script>'); // should be escaped
      }
  - SQL injection probe:
      const res = await request.post('/api/entities', {
        data: { name: "'; DROP TABLE entities; --" }
      });
      expect(res.status()).not.toBe(500); // 500 = likely SQL injection vulnerability

Coverage: // @covers-interaction: security-boundary
```

### Signal-Driven Security Patterns (from Phase 2B discovery data)

```
For every endpoint that sets cookies (Set-Cookie header detected in response_headers):
  - Cookie attribute completeness:
      const setCookie = response.headers()['set-cookie'] || '';
      expect(setCookie).toMatch(/httponly/i);
      expect(setCookie).toMatch(/samesite/i);
      if (!baseURL.includes('localhost') && !baseURL.includes('127.0.0.1')) {
        expect(setCookie).toMatch(/secure/i);
      }
      // If any flag missing, create HIGH severity bug
  Coverage: // @covers-interaction: cookie-security

For every endpoint with modifies_secret_material: true (from Phase 2B):
  - Credential change session invalidation:
      // Login -> get session -> change credential -> reuse OLD session -> expect 401
      const loginRes = await request.post(loginEndpoint, { data: creds });
      const token = (await loginRes.json()).token;
      // Verify old session works
      const before = await request.get(protectedEndpoint, {
        headers: { Authorization: `Bearer ${token}` }
      });
      expect(before.status()).toBe(200);
      // Change credential via the modifies_secret_material endpoint
      await request.post(credentialChangeEndpoint, {
        headers: { Authorization: `Bearer ${token}` },
        data: newCredentialPayload
      });
      // Old session MUST be invalidated
      const after = await request.get(protectedEndpoint, {
        headers: { Authorization: `Bearer ${token}` }
      });
      expect(after.status()).toBe(401); // if 200, create BLOCKING bug
  Coverage: // @covers-interaction: credential-change-verify

For every endpoint with rate limit headers (from response_headers in api-calls.json):
  - Rate limit enforcement:
      const limit = parseInt(response.headers()['x-ratelimit-limit'] || '0');
      if (limit > 0 && limit <= 20) {
        // Send limit+1 requests rapidly
        for (let i = 0; i <= limit; i++) {
          const res = await request.post(endpoint, { data: probePayload });
          if (i === limit) {
            expect(res.status()).toBe(429);
            const retryAfter = res.headers()['retry-after']
              || res.headers()['x-ratelimit-reset'];
            expect(retryAfter).toBeTruthy();
          }
        }
      }
      // If limit > 20: skip active test, log in discovery_warnings
  Coverage: // @covers-interaction: rate-limit-verify

For every endpoint returning setup data with secret/code
(e.g., TOTP secret, verification code, API key -- detected from response body field names):
  - Secret verification error paths:
      const wrongCode = await request.post(verifyEndpoint, { data: { code: '000000' } });
      expect(wrongCode.status()).toBe(400); // or 403
      const reusedCode = await request.post(verifyEndpoint, { data: { code: validCode } });
      // Submit same code twice -> second should fail (replay protection)
      const replay = await request.post(verifyEndpoint, { data: { code: validCode } });
      expect(replay.status()).toBe(400); // or 403
  - Happy path (conditional): if generation library available in project
      (grep package.json for: otpauth, speakeasy, totp-generator)
      Generate valid code -> submit -> verify success
      If no library: add to discovery_warnings and MISSING_FUNCTIONALITY_REPORT (MEDIUM)
  Coverage: // @covers-interaction: secret-verify

For every endpoint with sensitive_fields_exposed (from Phase 2B):
  - Response leak check:
      const body = await response.json();
      const sensitiveFields = ['password', 'hash', 'secret', 'ssn',
        'creditCard', 'stackTrace', 'internalId'];
      for (const field of sensitiveFields) {
        expect(body).not.toHaveProperty(field);
      }
  Coverage: // @covers-interaction: response-leak-check

For every error response (4xx/5xx):
  - Error leak check:
      const body = await response.text();
      expect(body).not.toMatch(/at\s+\w+\s+\(/);     // no stack traces
      expect(body).not.toMatch(/\/[\w/]+\.\w+:\d+/);  // no file paths
      expect(body).not.toMatch(/SELECT|INSERT|UPDATE|DELETE.*FROM/i); // no SQL
  Coverage: // @covers-interaction: error-leak-check

Note: All patterns are non-destructive probes. No actual exploitation.
```

---

## Governance Limits

```
- Max 30 test files
- If cap hit: prioritize HIGH risk routes first
- Log skipped routes in discovery_warnings
```
