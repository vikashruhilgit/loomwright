---
name: qa-gates
description: Quality gates, gap analysis tiers, and enforcement checklist for QA Executor. Contains Phase 4.5 (4-tier gap analysis), Phase 4.6 (dry-run), Phase 4.7 (12 quality gates with PASS CRITERIA), and quality checklist.
allowed-tools: [Read, Glob, Grep, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# QA Gates Skill

Quality gates, gap analysis tiers, dry-run enforcement, and post-generation self-check for QA test suites.

---

## Phase 4.5: MISSING FUNCTIONALITY ANALYSIS (MANDATORY -- DO NOT SKIP)

This phase is NOT optional. It costs 3-5 tool calls.
DO NOT skip for budget reasons. DO NOT substitute test failures for gap analysis.
Test failures are BUGS. Gap analysis finds MISSING FEATURES. They are different things.
You MUST read actual route handler source code, not just check endpoint existence.

Run ALL 4 tiers below. After each rule, record: "CHECKED -- {found/not-found}."

### TIER 1 -- EXISTENCE CHECKS (read discovery data)

Read api-calls.json, sitemap.json, seed-data.json. Check each rule:

**Rule 1 -- Missing CRUD operations:**
For each entity with a POST endpoint:
- Is there a PUT? If NO -> flag "Entity has create but no edit" (HIGH)
- Is there a DELETE? If NO -> flag "Entity has create but no delete" (HIGH)
- CHECKED -- {found/not-found}

**Rule 2 -- Missing pagination:**
For each GET endpoint that returns an array:
- Does it accept limit/offset/page/cursor params? If NO -> flag (MEDIUM)
- CHECKED -- {found/not-found}

**Rule 3 -- Missing search/filter:**
For each page with table/list showing > 5 items:
- Is there a search input? If NO -> flag (MEDIUM)
- CHECKED -- {found/not-found}

**Rule 4 -- Missing error pages:**
- Was a 404 page discovered? If NO -> flag (LOW)
- CHECKED -- {found/not-found}

**Rule 5 -- Missing confirmation dialogs:**
- Do DELETE endpoints exist without confirmation modals? If YES -> flag (HIGH)
- CHECKED -- {found/not-found}

**Rule 6 -- Missing loading states:**
- Do forms exist without loading/spinner states? If YES -> flag (LOW)
- CHECKED -- {found/not-found}

**Rule 7 -- Missing input validation:**
- Do forms have text inputs without client-side validation? If YES -> flag (HIGH)
- CHECKED -- {found/not-found}

**Rule 8 -- Missing or inconsistent rate limiting:**
For ANY endpoint that returns rate limit headers (X-RateLimit-*, Retry-After):
- Record limit value for test generation (rate-limit-verify pattern).
For ANY endpoint cluster where SOME endpoints have rate limiting but others don't:
- Flag inconsistency: "Endpoint B is missing rate limiting that sibling A has" (HIGH)
For HIGH risk endpoints (auth, payment, data mutation) with no rate limit headers:
- Flag: "HIGH risk endpoint without rate limiting" (HIGH)
- CHECKED -- {found/not-found}, limit_values: {recorded per endpoint}

### TIER 2 -- CROSS-ENDPOINT CONSISTENCY (read source code)

This tier requires reading actual route handler source files.
This is where MOST real gaps are found.

For each API cluster in scope (e.g., all /api/auth/* endpoints):
1. Glob for route handler files in the cluster
2. Read EVERY route handler file (not just check existence)
3. For each handler, check for these safeguards:
   - Input validation (email format, required fields, type checking)
   - JSON parse safety (.catch() or try/catch around body parsing)
   - Rate limiting (middleware, decorator, or explicit check)
   - Auth check (session/token validation)
   - Error handling (proper error responses vs unhandled crashes)
4. Build a safeguard matrix: endpoint x safeguard
5. Flag inconsistencies across sibling endpoints:
   - "Endpoint A validates email format but endpoint B doesn't" (MEDIUM)
   - "Endpoint A handles malformed JSON but endpoint B crashes" (HIGH)
   - "Endpoint A has rate limiting but endpoint B doesn't" (HIGH)
   - "Endpoint A accepts {field} in body but never reads/validates it" (HIGH)
     (false sense of security -- e.g., password field sent but ignored)
6. Field-name heuristic: for each handler, check if it reads/validates ALL fields
   it accepts in the request body. If a field is in the request body schema but
   the handler never references it -> flag as "accepted but ignored field" (HIGH)
7. Each inconsistency = one gap in MISSING_FUNCTIONALITY_REPORT

### TIER 3 -- FRONTEND-BACKEND CONTRACT (read both sides)

For each frontend page that sends data to scoped APIs:
1. Read the frontend form/component that calls each API endpoint
2. Compare what frontend sends vs what backend reads:
   - Frontend sends fields backend ignores -> security gap (HIGH)
   - Backend exposes endpoints with no frontend UI -> missing feature (MEDIUM)
   - Frontend has stub handlers (buttons that show messages instead
     of calling APIs) -> missing implementation (MEDIUM)
   - Destructive actions (delete, disable) without confirmation
     dialog -> UX safety gap (HIGH)

### TIER 4 -- COMPLIANCE CHECKLIST (auth scopes only at L1)

For auth-related scopes only (expand to other scopes in L2+):
- Can users delete their account? If not -> flag (MEDIUM, GDPR)
- Can users export their data? If not -> flag (MEDIUM, GDPR)
- Can users revoke all sessions? If not -> flag (MEDIUM)
- MFA disable: requires password confirmation? If not -> flag (HIGH)

### COMPLETION

Record gap_findings list with all findings from all 4 tiers.
If gap_findings is non-empty: queue for MISSING_FUNCTIONALITY_REPORT in Phase 9.
If gap_findings is empty after all 4 tiers:
  Record "0 gaps found (all 4 tiers checked)" in notes to prove execution.

Output MISSING_FUNCTIONALITY_REPORT block (see docs/RESULT_SCHEMAS.md for schema).
This is a SEPARATE output from QA_RESULT -- both MUST be emitted.

Budget: 3-5 tool calls. DO NOT skip this phase for budget reasons.

---

## Phase 4.6: DRY-RUN GATE

Before executing the full suite:

1. Pick up to 3 test files (1 HIGH risk, 1 MEDIUM, 1 LOW if available)
2. Run: `npx playwright test {file1} {file2} {file3} --reporter=json --timeout=60000`
3. Parse results:
   - If >= 2/3 pass -> proceed to full suite (Phase 5)
   - For each test that returns 5xx in the dry-run:
     a) File BLOCKING bug immediately with endpoint path and status code
     b) Add endpoint path to BLOCKED_ENDPOINTS list (track in memory)
     c) If MORE test files remain to be generated (Phase 4 not complete):
        Re-enter Phase 4 generation but SKIP endpoints in BLOCKED_ENDPOINTS.
        For skipped endpoints: "Skipped {N} tests for {path} (500 on happy path)"
     d) If all test files already generated:
        Edit existing files to wrap BLOCKED endpoint tests in test.fixme():
        `test.fixme('Endpoint returns 500 -- fix server first', async () => { ... });`
        This keeps tests visible in reports but prevents them from running.
   - If < 2/3 pass -> HALT. Do not run full suite.
     Inspect failures:
       - "Cannot find module" / "module not found" -> dependency issue (re-run Phase 0)
       - Locator not found / element missing -> discovery/locator mismatch
       - Auth redirect / 401 -> need storageState for gated routes
     status: needs_human, error: "Dry-run failed: {failure summary}"
     Attach dry-run failures to QA_RESULT notes field
     Emit QA_RESULT with partial data and exit

---

## Phase 4.7: POST-GENERATION SELF-CHECK

Before running the full suite, read ALL generated test files and verify 12 quality gates.
This is the primary enforcement mechanism -- passive rules in Phase 4 may be missed during
generation. Phase 4.7 catches violations BEFORE execution, not after.

### GATE 0 -- DISCOVERY VERIFICATION

Check for Phase B artifacts specifically (NOT Phase D merged output):
- discovery/sitemap.json MUST exist (Phase B output, not discovery-map.json)
- discovery/api-calls.json MUST exist (Phase B output)
- discovery/crawl.ts MUST exist (Phase B crawler script)

If ANY is missing: Phase 2B was skipped.
HALT. Do NOT proceed. Output: "GATE 0 FAILED: Phase 2B artifacts missing.
sitemap.json: {exists/missing}, api-calls.json: {exists/missing},
crawl.ts: {exists/missing}. Go back and run Phase 2B (runtime crawl) now."

Provenance check (for --scope/--continue runs):
- Read sitemap.json, check for _meta field
- If _meta.source !== "playwright_crawl": HALT (generated from static analysis)
- If _meta.timestamp is older than session start: HALT (stale from prior run)

discovery-map.json (Phase D) is NOT sufficient to pass this gate.
discovery-map.json without sitemap.json means only static analysis ran.

### GATE 0.5 -- TEST DIRECTORY VERIFICATION

Verify all generated test files are in {testDir}/frontend/ or {testDir}/api/.
No test files should be in the root test directory.
If any test file is in the wrong location: move it via Edit before proceeding.

### GATE 1 -- ASSERTION QUALITY

Read each generated test file. For each test, verify:
- No `expect([...]).toContain(status)` patterns (use toBe)
- No `expect(body).toHaveProperty('x')` without subsequent value assertion
- No `expect(text.length).toBeGreaterThan(N)` as content proxy
- No `expect([..., 500, ...]).toContain` patterns (accepts-5xx)
- Error assertions use specific field names, not just `/required/i`:
  - BAD: `expect(body.error).toMatch(/required/i)`
  - GOOD: `expect(body.error).toMatch(/email.*required/i)`
  - GOOD: `expect(body.errors.email).toBeDefined()`

If ANY violation found: Edit the file to fix it before proceeding.

### GATE 1.5 -- LOCATOR VERIFICATION

Grep all generated frontend test files for ANY of these banned patterns:
- `page.locator('input` (CSS type selector)
- `page.locator('#` (CSS ID selector)
- `page.locator('.` (CSS class selector)
- `page.locator('[` (CSS attribute selector)
- `.or(page.locator(` (fallback pattern -- STILL a CSS selector)
- `page.$(` (Puppeteer-style)
- `page.$$(` (Puppeteer-style)

The `.or(page.locator())` fallback is NOT acceptable. If the primary
role-based locator doesn't match, fix the locator -- don't fall back to CSS.

If ANY match found: Edit to replace with semantic locator:
- Use `page.getByRole()`, `page.getByLabel()`, `page.getByText()`, `page.getByPlaceholder()`
- Last resort: `page.getByTestId()` -- NEVER `page.locator()`

If ANY CSS selector or `.or()` fallback remains after fix: FAIL gate.

### GATE 2 -- STATE VERIFICATION (annotation-driven)

For every test with `@covers-interaction: auth-chain`:
- Verify it includes: create session -> access resource -> end session ->
  reuse old credential -> expect 401. All steps must be present.

For every test with `@covers-interaction: credential-change-verify`:
- Verify it includes a step that reuses the OLD credential/session and expects 401.

For every test with `@covers-interaction: api-post, api-put, api-delete`:
- Verify it includes a follow-up GET to confirm the state change persisted.

For every test that creates a session (login, token generation, API key creation):
- Verify the test accesses a protected resource to prove the session works.

For scopes with tenant-scoped endpoints (URL contains [slug], [orgId], [tenantId]):
- Verify at least ONE cross-tenant access test exists with
  `@covers-interaction: cross-tenant-access`.
- If zero: flag in notes as "no cross-tenant test" (MEDIUM, not blocking).

A test that only checks the response code without verifying state change is INCOMPLETE.
If ANY state verification is missing: add the missing steps via Edit.

### GATE 3 -- CLEANUP HOOKS (real cleanup, not comments)

For every `test.describe` block that creates data (POST, signup, register):
- Verify afterEach or afterAll contains ACTUAL cleanup logic:
  - If DELETE/cleanup API exists for the entity: MUST call it in afterAll
  - If admin API is available (e.g., /api/admin/*): use admin API for cleanup
  - If NO cleanup mechanism exists:
    a) afterAll MUST log: `console.warn('No cleanup API for {entity}')`
    b) Add gap to MISSING_FUNCTIONALITY_REPORT: "No delete API for {entity}" (MEDIUM)
    c) Test data MUST use identifiable prefix: `qa-test-{timestamp}` for manual cleanup
- For tests creating users/accounts:
  - afterAll MUST delete created test users via discovered API
  - If no user delete API: log warning + add to MISSING_FUNCTIONALITY_REPORT
- REJECT any cleanup hook that is only a comment (e.g., `// TODO: cleanup`).
  A comment is NOT cleanup. Either call a real API or log + document the gap.

If ANY data-creating describe block lacks real cleanup: fix it via Edit.

### GATE 4 -- BOUNDARY + IDEMPOTENCY TESTS

**BOUNDARY:** For every HIGH risk endpoint accepting user text input:
- Verify at least one boundary test exists with `@covers-interaction: boundary-test`:
  - Oversized input (1000+ chars)
  - Special characters or SQL-like strings (`"' OR 1=1 --"`)
  - Empty string (distinct from missing field)
- If NO boundary tests exist for a HIGH risk input endpoint: generate them.

**IDEMPOTENCY:** For every HIGH risk POST endpoint that returns 201:
- Verify at least one test exists with `@covers-interaction: idempotency-check`.
  (Send same payload twice, verify second is 409/400/200, never 500.)
- If NO idempotency test exists: generate one.

### GATE 5 -- PHASE 4.5 EXECUTION VERIFICATION

Verify Phase 4.5 was EXECUTED, not skipped:
- Were route handler source files read? (Tier 2 requires Read tool calls)
- Is there a gap_findings record (even if 0 gaps)?
- Did the agent check all 4 tiers?

If Phase 4.5 was NOT executed:
HALT. Go back and run Phase 4.5 NOW before proceeding to Phase 5.
Do NOT proceed. Do NOT substitute test failures for gap analysis.

If Phase 4.5 was executed and found 0 gaps: PASS.
If Phase 4.5 found gaps: verify they are queued for Phase 9 emission. PASS.

### GATE 6 -- UI PATTERN COVERAGE (counted per FORM, not per route)

Read discovery/sitemap.json. Count forms per HIGH risk route.
For EACH form on EACH HIGH risk route:
- Count UI tests that `@covers-route` this route AND cover this form's fields.
- MINIMUM: 3 tests per form:
  - `@covers-interaction: form-submission` MUST exist (valid submit)
  - `@covers-interaction: loading-state` MUST exist (submit button discovered)
  - `@covers-interaction: keyboard-nav` OR `error-recovery` MUST exist (at least one)
- Example: /signup has 1 form -> minimum 3 UI tests.
- Example: /admin/settings has 2 forms (profile + password) -> minimum 6 UI tests.

**COUNTING:**
- forms_in_scope = sum of forms across all HIGH risk routes in sitemap.json
- ui_tests_required = forms_in_scope * 3
- ui_tests_actual = count of tests in {testDir}/frontend/ with @covers-route matching
- If ui_tests_actual < ui_tests_required: FAIL gate.
- Output: "Gate 6: {ui_tests_actual}/{ui_tests_required} UI tests
  ({forms_in_scope} forms x 3 minimum)"

If Gate 6 FAILS and API test files exist but UI tests are insufficient:
The generation order was NOT interleaved. Generate missing UI tests NOW.
UI tests for HIGH risk forms have HIGHER priority than API tests for MEDIUM routes.

### GATE 7 -- INFRASTRUCTURE UTILIZATION (email flow enforcement)

If discovery/infrastructure.json has email.tool !== null:
- Scan api-calls.json for endpoints whose path contains ANY of:
  forgot, reset, invite, verify, confirm, activation, welcome
- OR whose request body contains fields: email, recipient, to
- If ANY such endpoint found AND zero tests have @covers-interaction
  containing "email" or use the email tool URL (Mailpit/MailHog):
  FAIL gate. Generate email flow test.

The email flow test MUST have all 5 steps:
1. Trigger the email-sending endpoint
2. Poll {email_tool_url}/api/v2/messages (or /api/v1/mailbox)
3. Extract token/link from email body
4. Use the token/link in a follow-up request
5. Verify the action succeeded

### GATE 8 -- OVERLAP CHECK

For each generated test file:
- Glob for pre-existing test files covering same feature/routes.
- If overlap found:
  - Count endpoints tested in BOTH new and existing files.
  - If overlap > 30%: FAIL gate.
    Either: merge coverage annotations into existing file (if quality high)
    Or: add `// Supplements {existing_file}` header and remove duplicate tests.
  - If overlap <= 30%: PASS (minor overlap acceptable for different test depths).
- Output: "Gate 8: {N} endpoints overlap between {new_file} and {existing_file}"

### GATE 9 -- SHARED HELPERS

If 2+ generated test files contain the same function body (login helper,
cookie parser, API wrapper):
- FAIL gate. Extract to {testDir}/helpers/{name}.ts and import.

Detection: Grep all generated spec files for:
- `async function login` or `function getSessionCookie` or `function authGet`
  appearing in more than one file
- Same function name defined in 2+ files

If ANY duplicate utility function found: Extract to helpers/ and update imports.

### PASS CRITERIA

All 12 gates must pass before proceeding to Phase 5:

| Gate | Name | Description |
|------|------|-------------|
| Gate 0 | Discovery verification | Crawl artifacts + provenance |
| Gate 0.5 | Test directory verification | Files in correct subdirectories |
| Gate 1 | Assertion quality | No lenient patterns |
| Gate 1.5 | Locator verification | No CSS selectors, no .or() fallback |
| Gate 2 | State verification | Annotation-driven |
| Gate 3 | Cleanup hooks | Real cleanup, not comments |
| Gate 4 | Boundary + idempotency tests | HIGH risk endpoints |
| Gate 5 | Phase 4.5 execution verification | Gap analysis was run |
| Gate 6 | UI pattern coverage | 3 per form, counted by form not route |
| Gate 7 | Infrastructure utilization | Email flow if available |
| Gate 8 | Overlap check | < 30% duplicate with existing tests |
| Gate 9 | Shared helpers | No duplicate utility functions across files |

This list is EXHAUSTIVE -- if a gate number is listed, it runs.
If ANY gate fails: fix via Edit, then re-verify that gate.
Do NOT skip gates. Do NOT pass a gate with a workaround.

Budget: 2-4 tool calls (Read generated files + potential Edits).
Phase 4.7 runs in ALL budget zones including ORANGE.
ONLY RED (55+) skips Phase 4.7 -- and RED must still emit a partial
QA_RESULT noting "self-check skipped due to RED budget zone."

---

## Quality Checklist

Before emitting QA_RESULT:

- [ ] Phase 0: Dependencies installed, Playwright version confirmed
- [ ] Playwright config found and base URL detected
- [ ] App reachability verified
- [ ] Phase 1.5: Infrastructure probed -- discovery/infrastructure.json written
- [ ] Phase 2: 4-phase discovery completed with confidence score
- [ ] discovery/seed-data.json produced with entity counts
- [ ] Phase 2.5: Pre-existing tests triaged (or none found)
- [ ] Strategist risk classification received (or --skip-strategy used)
- [ ] Tests follow playwright-e2e skill patterns
- [ ] Tests have beforeEach/afterEach isolation -- no shared state
- [ ] No multi-tenant cross-organization security tests in generated suite (deferred to L3)
- [ ] Coverage annotations present in all tests (@covers-route, @covers-api, @covers-interaction)
- [ ] Functional depth: forms have fill+submit tests, APIs have CRUD tests, buttons have click tests
- [ ] Phase 4.7 Gate 0: Discovery files (sitemap.json, api-calls.json) exist and are fresh
- [ ] Phase 4.7 Gate 0.5: All test files in correct directories ({testDir}/frontend/ or /api/)
- [ ] Phase 4.7 Gate 1: Assertion strictness verified -- no anti-patterns in generated tests
- [ ] Phase 4.7 Gate 1.5: No CSS selectors (page.locator) -- all role-based locators
- [ ] Phase 4.7 Gate 2: State verification -- annotation-driven (auth-chain, credential-change, CRUD)
- [ ] Phase 4.7 Gate 3: Cleanup hooks -- ACTUAL cleanup (not comments), identifiable test data prefixes
- [ ] Phase 4.7 Gate 4: Boundary tests exist for HIGH risk text input endpoints
- [ ] Phase 4.7 Gate 5: Phase 4.5 was EXECUTED (route handlers read, all 4 tiers checked)
- [ ] 5xx responses treated as BLOCKING bugs (never accepted as valid outcomes)
- [ ] State verification: POST/PUT/DELETE AND auth mutation tests include follow-up verification
- [ ] Negative tests: HIGH risk API endpoints have empty-body and missing-field tests
- [ ] Multi-step flows: auth linear chain + CRUD lifecycle for HIGH risk groups
- [ ] Data integrity probes: concurrent creation/duplicate tests for HIGH risk entities
- [ ] Security boundary tests: IDOR, role escalation, session invalidation for HIGH risk endpoints
- [ ] Signal-driven patterns: cookie-security, credential-change-verify, rate-limit-verify, response-leak-check, error-leak-check generated where discovery signals match
- [ ] UI patterns: loading-state (HIGH/MEDIUM forms), keyboard-nav (HIGH forms), error-recovery (HIGH forms)
- [ ] Interaction coverage tracked: forms/tables/modals discovered vs tested
- [ ] Failure classification: REAL_BUG vs DISCOVERY_GAP vs ENVIRONMENT_ISSUE
- [ ] MISSING_FUNCTIONALITY_REPORT emitted with gaps found during analysis
- [ ] Email-dependent flows tested if infrastructure available (Phase 1.5)
- [ ] Pre-existing test failures triaged with severity (Phase 2.5)
- [ ] Dry-run gate passed (>= 2/3 sample tests passing) before full suite
- [ ] Tests executed with JSON reporter
- [ ] Coverage tracked (routes + APIs discovered vs tested)
- [ ] Bug reports generated for failures with severity
- [ ] Strategist audit completed (1 round for L1)
- [ ] .qa-summary.md written (max 200 tokens)
- [ ] QA_RESULT block contains ALL required fields (tests_generated vs tests_run_this_session)
- [ ] Level 1 boundaries respected
- [ ] Tool call budget tracked
