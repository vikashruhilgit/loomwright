---
name: qa-strategy
description: Risk-based QA strategy framework, structured output formats, debate loop protocol, and discovery engine specification. Foundation skill for QA Strategist and QA Executor agents.
allowed-tools: [Read, Glob, Grep, Bash]
version: "1.0.0"
lastUpdated: "2026-03"
---

# QA Strategy Skill

Risk-based QA strategy framework shared by QA Strategist and QA Executor agents. Defines risk classification, coverage targets, debate protocol, discovery engine, and structured output formats.

---

## 1. Risk Classification Framework

### Risk Levels

| Risk Level | Coverage Target | Description |
|---|---|---|
| **HIGH** | 85%+ | Auth flows, payment, data mutation, core navigation |
| **MEDIUM** | 70% | CRUD operations, search, filtering, secondary features |
| **LOW** | 50% | Static pages, about/FAQ, settings with no side effects |

### Risk Score Formula

```
risk_score =
  ((HIGH_untested * 3 + MEDIUM_untested * 2 + LOW_untested * 1)
   / (HIGH_total * 3 + MEDIUM_total * 2 + LOW_total * 1))
  * 100
```

Higher score = higher risk (more untested critical areas). 0 = fully covered.
Equivalently: `risk_score = 100 - (coverage_weighted * 100)`

### Coverage Weighted Formula

```
coverage_weighted =
  (HIGH_covered * 3 + MEDIUM_covered * 2 + LOW_covered * 1)
  / (HIGH_total * 3 + MEDIUM_total * 2 + LOW_total * 1)
```

### Computation Ownership

| Metric | Computed By |
|---|---|
| discovery_confidence | Executor |
| coverage (routes/APIs) | Executor |
| coverage_weighted | Executor |
| risk_score | Executor |
| bug severity | Executor (Strategist may override) |
| coverage_target | Strategist |
| quality_score | Strategist |
| approval decision | Strategist |

---

## 2. Test Depth Matrix

> **CRITICAL:** Before evaluating or generating tests, read the Assertion Anti-Patterns and Depth Requirements below. Tests that violate these rules must be REJECTED.

### Assertion Anti-Patterns (NEVER generate these — READ FIRST)

| Anti-Pattern | Example | Why It's Bad | Correct Alternative |
|---|---|---|---|
| Status array toContain | `expect([200, 401, 500]).toContain(status)` | Accepts failures as valid | `expect(status).toBe(200)` |
| Property existence only | `expect(body).toHaveProperty('name')` | Passes even if value is wrong | `expect(body.name).toBe('Expected Name')` |
| Text length proxy | `expect(text.length).toBeGreaterThan(10)` | Passes for any non-empty text | `expect(heading).toHaveText(/dashboard/i)` |
| Accept 5xx | `expect([200, 500]).toContain(status)` | Masks server errors | `expect(status).toBe(200)` + BLOCKING bug if 500 |
| Mutation without verify | POST then assert 201 only | Doesn't prove data persisted | POST, then GET, then assert values match |
| CSS selector locator | `page.locator('input[type="email"]')` | Breaks on DOM changes | `page.getByRole('textbox', { name: /email/i })` |
| Loose error matching | `expect(body.error).toMatch(/required/i)` | Matches any "required" string, misses regression if field name changes | `expect(body.error).toMatch(/email.*required/i)` or assert specific field |

### Assertion Depth Requirements per Risk Level

| Risk Level | Status Assertions | Body Assertions | Negative Tests | State Verification | Auth State Verification | Multi-Step Flows | Boundary Tests | Pagination |
|---|---|---|---|---|---|---|---|---|
| **HIGH** | Exact (toBe) | Specific values | Empty, missing, wrong types, no-auth | Required (GET after mutation) | Signup→login, login→access, logout→deny, reset→login | 1 CRUD lifecycle + auth chain | Max length, special chars, SQL-like, zero/negative | Required if pagination params exist |
| **MEDIUM** | Exact (toBe) | Specific values | Empty, missing fields | Required (GET after mutation) | Login→access if auth-gated | Not required | Special chars only | Not required |
| **LOW** | Exact (toBe) | Type + non-empty OK | Not required | Not required | Not required | Not required | Not required | Not required |

### By Depth Mode (L1)

| Risk | smoke | functional (default) |
|---|---|---|
| **HIGH** | Navigate + verify visible | All discovered patterns + valid + invalid + error paths |
| **MEDIUM** | Navigate + verify visible | All discovered patterns + valid data only |
| **LOW** | Navigate + verify title | Navigate + verify content renders correctly |

### By Maturity Level

| Risk Level | L1 smoke | L1 functional | L2+ Tests |
|---|---|---|---|
| **HIGH** | Happy path (navigate + visible) | All interaction patterns + valid + invalid + error paths | + state combinations + journey coverage + fuzz |
| **MEDIUM** | Happy path (navigate + visible) | All interaction patterns + valid data | + state variations + journey coverage |
| **LOW** | Happy path (navigate + title) | Navigate + verify content renders | + basic error paths |

### Interaction Patterns (functional depth)

Tests are selected by matching **discovery signals** to patterns:

| Discovery Signal | Test Pattern |
|---|---|
| Form with inputs | Fill valid → submit → verify; Fill invalid → verify errors |
| API POST endpoint | Valid payload → 201 + body; Invalid → 400 |
| API PUT endpoint | Update → 200 + changed fields |
| API DELETE endpoint | Delete → 204 → re-GET → 404 |
| API GET endpoint | Call → 200 + body structure |
| Button (non-form) | Click → verify outcome |
| Modal detected | Open → interact → close → verify |
| Table/list | Verify headers, row count, data renders |
| Auth-gated route | No auth → 401/redirect |
| API POST/PUT (negative) | Empty body → 400; Missing required fields → 400 with field name; Wrong types → 400 |
| Auth endpoint (negative) | No token → 401; Invalid token → 401 |
| Data integrity probe | Concurrent creation → verify constraint; Duplicate creation → verify 409 |
| Security boundary | Cross-resource access → 403/404; Role escalation → 403; Session reuse after logout → 401 |

---

## 3. Debate Loop Protocol

### Rules

- **Max rounds:** 3 (hard cap, never negotiable)
- **L1:** 1 round only (Strategist reviews once after Executor completes)
- **L2+:** Up to 3 rounds (Executor generates -> Strategist audits -> Executor fixes gaps -> repeat)
- **Strategist verdict is final** on conflict (defaults to deeper testing)
- **Timeout handling:** If Strategist crashes/times out -> `strategist_verdict: timeout` -> `status: needs_human`

### Round Flow

```
Executor: Generate tests -> Run tests -> Compute coverage -> Write .qa-summary.md
    |
    v
Strategist (Audit Mode): Read .qa-summary.md + test results -> STRATEGIST_VERDICT
    |
    v
If approved: Executor emits QA_RESULT (status: passed)
If rejected (round < max): Executor generates additional tests for gaps -> next round
If rejected (round = max): Executor emits QA_RESULT (status: failed)
```

---

## 4. Discovery Engine Protocol (4-Phase)

### Phase A — Static Analysis (~2 tool calls)

1. Glob source files for routes, controllers, middleware, schemas
2. Grep for route definitions, API endpoints, auth decorators
3. Read OpenAPI/Swagger spec if exists
4. Output: theoretical map (routes, endpoints, roles from code)

### Phase B — Runtime Structured Crawl (~2 tool calls)

1. Generate batch crawler script (discovery/crawl.ts)
2. Run crawler with Playwright:
   - DOM structure, accessibility tree, network intercepts, JS errors
   - Interaction-based: unique button patterns, modals/drawers
   - Safe-click heuristics: skip destructive buttons (delete, remove, logout, purchase, pay)
   - SPA-aware: monitor framenavigated + history.pushState
   - Read-only: never submit forms, never persist changes
3. Auth handling (L1: 2 passes max — unauthenticated + one authenticated)
4. Bounds: max depth 3, max 30 pages, same-origin, dedup by URL
5. Output: discovery/sitemap.json + discovery/api-calls.json

### Phase C — Selective Vision (~2-4 tool calls)

1. Identify 10-20% of pages needing screenshots (complex forms, errors, modals)
2. Generate targeted screenshot script
3. Max 10 screenshots
4. DOM extraction is primary, vision is enhancement

### Phase D — Merge, Verify & Gate (~2 tool calls)

1. Compare static vs runtime routes
2. Compare runtime APIs vs OpenAPI spec
3. Tie-break: unreachable static routes = `UNVERIFIED_STATIC` (not dead code)
4. Self-verification: confirm routes render content, APIs were intercepted
5. Compute confidence score (see below)
6. Generate discovery/report.md
7. Produce final Discovery Map

### Confidence Scoring

```
confidence_score =
  0.4 * route_verification_ratio +     # verified / total routes
  0.3 * api_interception_ratio +        # intercepted / static APIs
  0.2 * crawl_coverage_ratio +          # crawled / max(static, runtime unique)
  0.1 * static_runtime_alignment        # overlap static + runtime

Fallback (no static API list):
  0.5 * route_verification + 0.3 * crawl_coverage + 0.2 * alignment
```

| Level | Score | Action |
|---|---|---|
| HIGH | >= 0.7 | Auto-proceed |
| MEDIUM | 0.4-0.7 | Auto-proceed, log note in QA_RESULT |
| LOW | < 0.4 | Halt, require human confirmation |

- Auto-cap: If crawl page limit (30) hit -> confidence capped at MEDIUM
- Override: `--strict-discovery` (always require approval), `--auto-discover` (always proceed)

**Total discovery budget: 8-10 tool calls**

---

## 5. Bug Severity Classification

| Severity | Criteria |
|---|---|
| **BLOCKING** | Auth bypass, 500 error on HIGH route, data corruption, crash |
| **HIGH** | Wrong data returned, permission violation, broken navigation |
| **MEDIUM** | Validation missing, slow response, minor logic error |
| **LOW** | UI mismatch, cosmetic issue, non-critical warning |

Executor assigns severity. Strategist may override during audit.

---

## 6. Lightweight Coverage Tracking (L1)

Track inventory-level coverage (not behavioral):

```
Routes discovered: {N}
Routes with tests: {N}
APIs discovered: {N}
APIs with tests: {N}
```

Coverage annotations in test files enable tracking:
```typescript
// @covers-route: /dashboard
// @covers-api: GET /api/dashboard/stats
// @covers-interaction: data-rendering
test('dashboard loads with stats', async ({ page }) => { ... });
```

### Interaction Coverage Annotations

Functional-depth tests include `@covers-interaction` annotations for tracking interaction depth:

```typescript
// @covers-interaction: form-submission      — test fills and submits a form
// @covers-interaction: validation-error     — test triggers and verifies validation
// @covers-interaction: api-post             — test sends POST with body validation
// @covers-interaction: api-put              — test sends PUT with field verification
// @covers-interaction: api-delete           — test deletes + verifies 404
// @covers-interaction: api-get              — test verifies response body structure
// @covers-interaction: button-click         — test clicks non-form button
// @covers-interaction: modal                — test opens/interacts/closes modal
// @covers-interaction: data-rendering       — test verifies table/list content
// @covers-interaction: auth-gate            — test verifies 401/redirect without auth
// @covers-interaction: auth-chain           — test exercises full auth lifecycle (signup→login→access→logout→deny)
// @covers-interaction: boundary-test        — test sends oversized, special chars, SQL-like, or empty string inputs
```

Compare annotations against Discovery Map to compute coverage.

---

## 7. Structured Output Formats

### QA_RESULT (emitted by QA Executor)

```markdown
## QA_RESULT
- task_id: {id}
- status: passed | failed | needs_human | skipped
- rounds_run: {N}/3
- tests_generated: {N}
- tests_generated: {N}    # total tests written to disk
- tests_run_this_session: {N}    # tests actually executed this agent session
- tests_passed: {N}
- tests_failed: {N}
- discovery_confidence: HIGH | MEDIUM | LOW
- discovery_duration_seconds: {N}
- crawl_limit_hit: true | false
- discovery_warnings: [{array of strings}]
- coverage: routes {X}/{Y}, apis {X}/{Y}
- coverage_weighted: {risk-adjusted %}
- risk_score: {0-100}
- bugs_found: {N}
- bugs_blocking: {N}
- strategist_verdict: approved | rejected | timeout
- files_created: [paths]
- error: none | {description}
- notes: {1-2 sentences}
```

### STRATEGIST_VERDICT (emitted by QA Strategist in audit mode)

```markdown
## STRATEGIST_VERDICT
- round: {N}/3
- verdict: approved | rejected
- coverage_achieved: routes {X}/{Y}, apis {X}/{Y}
- coverage_target: {pct}
- interaction_depth: {N}/{M} HIGH risk routes have deep interaction tests
- assertion_quality: {N}% strict ({X} strict / {Y} total sampled)
- assertion_flags: [lenient-status, existence-only, loose-error-match, ...]
- structural_completeness: {N}/{M} structural checks passed
- structural_flags: [no-auth-chain, no-cleanup, infrastructure-unused, ...]
- gaps: [{test_type}] {description} -- {risk}
- blocking_bugs: {N}
- missing_functionality_count: {N}
- critical_gaps: [list of CRITICAL/HIGH gaps]
- gap_recommendation: address before launch | acceptable for MVP | track as tech debt
- quality_score: {0-100}
- rationale: {1-2 sentences}
```

---

## 8. Level Gate

Each maturity level unlocks specific capabilities. Agents MUST NOT attempt higher-level work.

| Module | L1 | L2 | L3 | L4 | L5 |
|---|---|---|---|---|---|
| Static Analysis (1) | Y | Y | Y | Y | Y |
| Runtime Crawl (2) | Y | Y | Y | Y | Y |
| State Modeling (3) | - | Y | Y | Y | Y |
| Journey Generator (4) | simple linear chains only | Y | Y | Y | Y |
| Risk Strategy (5) | Y | Y | Y | Y | Y |
| UI/E2E Tests (6a) | Y | Y | Y | Y | Y |
| API Tests (6b) | Y | Y | Y | Y | Y |
| Security Tests (6c) | - | - | Y | Y | Y |
| Performance Tests (6d) | - | - | Y | Y | Y |
| Fuzz Tests (6e) | - | Y | Y | Y | Y |
| Execution (7) | Y | Y | Y | Y | Y |
| Coverage & Gap (8) | lightweight | Y | Y | Y | Y |
| Bug Reports (9) | Y | Y | Y | Y | Y |
| Visual/A11y (10) | - | - | Y | Y | Y |
| Flaky Analyzer (11) | - | - | Y | Y | Y |
| Production Feedback (12) | - | - | - | - | Y |
| Reporting (13) | lightweight (.qa-summary.md) | - | Y | Y | Y |
| Debate Loop (14) | 1 round | 3 rounds | 3 rounds | 3 rounds | 3 rounds |

---

## 9. Governance Limits

| Control | Limit |
|---|---|
| Max crawl depth | 3 levels |
| Max pages crawled | 30 |
| Max state combinations | 50 |
| Max test files generated | 30 |
| Max test execution time | 5 minutes |
| Max debate rounds | 3 |
| Max tool calls (Executor) | 60 |
| Max screenshots | 10 |

If any limit is hit: log it, proceed with what you have. Never silently fail.

---

## 10. Test Isolation Rules

Every generated test must be fully independent. Shared state causes suite-level failures even when individual tests pass.

### Mandatory isolation patterns

```typescript
test.describe('Feature', () => {
  // Set up fresh state before each test
  test.beforeEach(async ({ page, request }) => {
    // Auth: set storageState or perform login
    // Data: create required fixtures with unique IDs
    const id = `test-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  });

  // Clean up after each test
  test.afterEach(async ({ request }) => {
    // Delete created records, reset state
  });

  test('...', async ({ page }) => { ... });
});
```

### Rules
- Never rely on test execution order
- Use `Date.now()` or `crypto.randomUUID()` for unique identifiers to avoid data collisions
- For auth-gated routes: each test file must set up its own storageState or login step
- Do NOT share login cookies or auth tokens across test files implicitly
- If a test needs seed data that cannot be created programmatically: use `test.skip()` with a note

---

## 11. Seed Data Awareness

Tests that assume fixture data (slugs, org IDs, user records) fail when that data doesn't exist.

### Detection (during crawl)

Intercept GET list responses during Phase B to inventory available entities:

```json
// discovery/seed-data.json
{
  "orgs": { "count": 3, "sample_ids": ["org-abc", "org-def"] },
  "members": { "count": 12, "sample_ids": ["user-1", "user-2"] },
  "projects": { "count": 0, "sample_ids": [] }
}
```

### Generation rules

| seed count | action |
|---|---|
| > 0 | Use a discovered sample ID — do NOT hardcode |
| = 0 (LOW risk route) | Skip test with `test.skip('requires seed data: {entity}')` |
| = 0 (HIGH/MEDIUM risk route) | Generate beforeEach to create entity + afterEach to delete it |

Never hardcode slugs like `"my-org"` or IDs like `"12345"` — always read from seed-data.json or generate dynamically.

---

## 12. Quality Checklist for QA Agents

Before emitting QA_RESULT:
- [ ] Discovery Map generated with confidence score
- [ ] discovery/seed-data.json produced with entity inventory
- [ ] discovery/infrastructure.json produced (Phase 1.5)
- [ ] Pre-existing tests triaged (Phase 2.5) — or none found
- [ ] Risk classification applied to all discovered routes
- [ ] Tests follow playwright-e2e skill patterns (role-based locators, regex assertions)
- [ ] Tests have beforeEach/afterEach isolation — no shared state between tests
- [ ] Tests use unique identifiers per run (Date.now(), crypto.randomUUID())
- [ ] Data-creating tests have cleanup in afterEach/afterAll
- [ ] Seed data check done — no hardcoded slugs or IDs
- [ ] Cross-org security tests excluded from L1 generation (deferred to L3)
- [ ] Auth flow tests verify state changes (signup→login, logout→deny, reset→login)
- [ ] Auth chain test generated when auth endpoints discovered
- [ ] Boundary tests generated for HIGH risk text input endpoints
- [ ] Email-dependent flows tested if infrastructure available
- [ ] Coverage annotations present in all generated tests (including auth-chain, boundary-test)
- [ ] Phase 4.7 self-check passed: all 5 gates verified
- [ ] MISSING_FUNCTIONALITY_REPORT emitted with gaps from discovery analysis
- [ ] Dry-run gate passed before full suite execution
- [ ] Coverage tracked (routes discovered vs tested, APIs discovered vs tested)
- [ ] Bug reports include severity, reproduction steps, file:line
- [ ] Strategist audit completed (or timeout recorded)
- [ ] QA_RESULT distinguishes tests_generated from tests_run_this_session
- [ ] No hardcoded waits, no CSS selectors in generated tests
- [ ] Level boundaries respected (no L2+ work in L1)

---

## See Also

- `skills/playwright-e2e/SKILL.md` — Test authoring patterns
- `skills/quality-checklist/SKILL.md` — General quality gates
- `docs/QA_SYSTEM_BLUEPRINT.md` — Full architecture and maturity levels
