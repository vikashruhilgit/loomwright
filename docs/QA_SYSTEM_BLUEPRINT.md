# QA System Blueprint — Dual-Agent Architecture

## Overview

The QA system adds two agents (QA Strategist + QA Executor) to the ai-agent-manager plugin. They implement autonomous QA automation through a bounded debate loop, risk-based test strategy, and 4-phase discovery.

The system ships incrementally across 5 maturity levels. Level 1 ships first.

---

## System Architecture

### 4 Macro Layers

```
Layer 1 — PERCEPTION
  Modules: 1 (Static Analysis), 2 (Runtime Crawl), 3 (State Modeling)
  Purpose: Understand WHAT exists in the application
  Phase 4 (Infrastructure Discovery) includes app topology auto-detection
  (ui_present, api_style, client_platform), auth method detection, and
  WebSocket discovery. This metadata drives conditional behavior in Layers 2-3.

Layer 2 — INTELLIGENCE
  Modules: 4 (Journey Generator), 5 (Risk Strategy), 14 (Debate Loop)
  Purpose: Decide WHAT to test and HOW deeply

Layer 3 — ACTION
  Modules: 6 (Test Generation), 7 (Execution), 8 (Coverage), 9 (Bug Reports),
           10 (Visual/A11y), 11 (Flaky Analyzer)
  Purpose: Generate, execute, analyze, and report

Layer 4 — EVOLUTION
  Modules: 12 (Production Feedback), 13 (Reporting + Quality Score)
  Purpose: Learn and improve over time
```

### 14 Modules

```
 1. Static Analysis              -> Theoretical Map
 2. Runtime Structured Crawl     -> Runtime Map (DOM + network + a11y tree)
 3. State Modeling Engine         -> State Matrix (roles x data x flags)
 4. User Journey Generator       -> Journey Graph (happy + error + cross-feature)
 5. Risk Strategy Engine          -> Risk Classification + Coverage Targets
 6. Test Generation:
    -> UI/E2E tests
    -> API + Contract tests
    -> Security tests (non-destructive validation only)
    -> Performance tests (basic Playwright + k6 config)
    -> Fuzz tests
 7. Playwright Execution
 8. Coverage & Gap Analysis
 9. Bug Report Generator
10. Visual Regression + Accessibility
11. Flaky Test Analyzer + Self-Healing
12. Production Feedback (batch import, not real-time)
13. Reporting & Quality Scoring
14. Debate Loop (Strategist <-> Executor, max 3 rounds)
```

---

## 4-Phase Discovery Engine (Modules 1+2)

### Phase A — Static Analysis (~2 tool calls)

- Glob + Grep source files for routes, controllers, middleware, schemas
- Read OpenAPI/Swagger if exists
- Output: theoretical-map.json (routes, endpoints, roles from code)

### Phase B — Runtime Structured Crawl (~2 tool calls)

- Agent generates ONE batch crawler script (discovery/crawl.ts)
- **Interaction-based crawling** (not just link-following):
  - Attempt each unique interaction pattern once per page (unique button role/text combination, not every button instance). On complex dashboards, skip repeated patterns to prevent exponential branching.
  - Detect and catalog modals/drawers (`[role="dialog"]`, `.modal`)
  - SPA-aware: monitor `page.on('framenavigated')` AND patch `window.history.pushState/replaceState`
  - **Safe-click heuristics — DO NOT CLICK:** buttons containing "delete", "remove", "logout", "sign out", "purchase", "pay", "submit payment", "confirm delete". Also skip buttons inside already-processed modals. Log ALL skipped buttons to `discovery/skipped-interactions.json`.
  - **Read-only discovery mode:** Never submit forms. Never persist changes. Reset page state after each interaction. Prefer shallow exploration over state mutation.
- Playwright extracts per page: DOM structure, accessibility tree (`page.accessibility.snapshot()`), network intercepts (`page.on('request')`), JS errors (`page.on('console')`), page metadata
- **Auth handling (L1: 2 passes max):**
  - Pass 1: Unauthenticated crawl
  - Auth escalation trigger: If static analysis shows auth-gated routes AND runtime discovers below expected count
  - Pass 2: One authenticated pass (primary user role)
  - Admin/multi-role passes deferred to Level 2
- Crawl bounds: max depth 3, max 30 pages, same-origin only, dedup by URL
- Output: discovery/sitemap.json + discovery/api-calls.json + discovery/data/*.json

### Phase C — Selective Vision (~2-4 tool calls)

- Claude reads structured data, identifies 10-20% of pages needing screenshots
- Targets: complex forms, validation errors, error states, modals, empty states
- Generates targeted screenshot script for ONLY those pages
- DOM extraction is primary, vision is enhancement

### Phase D — Merge, Verify & Gate (~2 tool calls)

- Compare static vs runtime routes
- Compare runtime APIs vs OpenAPI spec -> flag undocumented endpoints
- **Tie-break rule:** If static route exists but runtime crawl cannot reach it -> mark as `UNVERIFIED_STATIC` (NOT dead code)
- **Self-verification:** For each discovered route, verify it renders actual content. For each API endpoint, verify it was actually intercepted.
- **Confidence scoring:**
  ```
  confidence_score =
    0.4 * route_verification_ratio +
    0.3 * api_interception_ratio +
    0.2 * crawl_coverage_ratio +
    0.1 * static_runtime_alignment

  Fallback (no static API list):
    0.5 * route_verification + 0.3 * crawl_coverage + 0.2 * alignment
  ```
  - `HIGH` (>= 0.7): auto-proceed
  - `MEDIUM` (0.4-0.7): auto-proceed, log note
  - `LOW` (< 0.4): halt, require human confirmation
  - **Auto-cap:** If crawl page limit (30) was hit -> confidence capped at MEDIUM
  - Override: `--strict-discovery` (always require approval) or `--auto-discover` (always proceed)
- **Discovery Report** (always at `discovery/report.md`):
  - Route table, API endpoint count, form count, modal count
  - Roles detected, confidence level, action items
- Produce final Discovery Map

**Total discovery budget: 8-10 tool calls**

---

## Maturity Levels

### Level 1: Foundation — "Can it generate tests?"

**Modules:** 1, 2, 5, 6a, 6b, 7, 9, 14(basic) + lightweight coverage tracking

**Included (v10.2.0 — 13-phase protocol, split architecture, topology-aware):**
- App topology auto-detection (ui_present, api_style, client_platform) — replaces assumption that every app has a browser UI + REST APIs
- Auth method detection (session, oauth:{provider}, api-key, none) with `--auth-state` support for OAuth/SSO apps
- WebSocket detection (ws://, wss://, socket.io) with connection-lifecycle test generation
- GraphQL discovery with 5-step fallback chain (SDL files → resolvers → codegen → persisted queries → live introspection)
- API-only discovery with OpenAPI-first precedence (OpenAPI → route manifests → seed data → safe health/list → static fallback)
- Conditional gate logic (Gate 6 skipped for non-UI apps, Gate 10 runs only for GraphQL/mixed)
- Auto-generated minimal Playwright config for API-only apps when no config exists
- GRAPHQL_RISK_OVERRIDES contract (Strategist → Executor risk write-back to `api-calls.json`)
- Infrastructure discovery (Phase 1.5) — probes for email capture (Mailpit/MailHog), mock servers
- Static + Runtime discovery (4-phase engine)
- Pre-existing test triage (Phase 2.5) — runs existing tests, classifies failures, files bugs
- Risk Strategy (Strategist classifies HIGH/MEDIUM/LOW)
- UI/E2E test generation (happy paths + error paths + negative tests)
- API test generation (strict status assertions, value assertions, state verification)
- Negative testing for HIGH/MEDIUM risk (empty body, missing fields, wrong types, auth boundaries)
- Boundary testing for HIGH risk (oversized input, special chars, SQL-like strings, empty vs null vs missing)
- Simple linear chain tests (L1-legal: signup→login→access→logout→deny, CRUD lifecycle)
- Email flow testing (password reset, MFA via email capture when infrastructure available)
- Data integrity probes (concurrent creation, duplicate detection, cascade delete for HIGH risk)
- Security boundary testing (IDOR, role escalation, session invalidation, XSS/SQLi probes for HIGH risk)
- Independent Strategist gate audit (Phase 11) — 13 quality gates verified by separate QA Strategist agent (Gate 10 added for GraphQL coverage)
- Missing Functionality Analysis (gap detection: missing CRUD ops, pagination, search, validation, rate limiting)
- Assertion strictness enforcement (no status arrays, no existence-only, no loose error matching, 5xx = BLOCKING bug)
- Strategist assertion quality audit + structural completeness audit (6 checks)
- Playwright execution (`npx playwright test --reporter=json`)
- Bug reports (text-based, file:line, reproduction steps)
- MISSING_FUNCTIONALITY_REPORT (separate structured output for detected gaps)
- Debate loop (1 round only)
- Lightweight coverage tracking (routes/APIs discovered vs tested)

**NOT included:** State modeling, branching journey graphs, fuzz, visual regression, flaky detection, production feedback.

**Estimated QA effort eliminated: 60-70%**

### Level 2: Depth — "Does it understand behavior?"

**Adds:** 3, 4, 6e, 8, 14(full 3-round debate)

- State Modeling Engine (roles x data states x feature flags)
- User Journey Generator (happy + error + edge + cross-feature)
- Fuzz tests (adversarial inputs, boundary values, injection patterns)
- Full Coverage & Gap Analysis
- Full 3-round debate loop

**Estimated: 55-65%**

### Level 3: Security & Quality — "Can we trust it?"

**Adds:** 6c, 6d, 10, 11, 13

- Security tests (non-destructive validation: auth boundaries, role enforcement, input sanitization, token expiry)
- Basic performance tests (page load, API response, slow network via Playwright)
- k6 config generation for external load testing
- Visual regression + accessibility
- Flaky test analyzer + self-healing (guard: may ONLY modify locator/wait/retry strategy, NEVER business logic assertions)
- Reporting (quality score, risk heatmap, release readiness)

**Estimated: 75-85%**

### Level 4: Autonomous — "Does it run itself?"

**Adds:** Supervisor Phase 3.5, hooks, contract validation

- Supervisor Phase 3.5 QA Gate (post-merge, pre-PR)
- Plugin hooks (SubagentStop for qa-executor)
- Contract validation (OpenAPI schema comparison)
- `--skip-qa` flag for Supervisor

**Estimated: 85%**

### Level 5: Learning — "Does it improve itself?"

**Adds:** 12, optimization, memory growth

- Production feedback (batch import from `.qa/production-feedback/`)
- Test suite optimization
- Risk model refinement
- Agent memory growth
- **Guardrail:** Production signals refine risk weights, NEVER remove required coverage
- **Memory decay:** Max 200 entries/project. Entries older than 6 months auto-expire unless pinned.
- **Memory schema (structured):**
  ```json
  {
    "failure_pattern": "login redirect timing",
    "affected_routes": ["/auth/login", "/dashboard"],
    "resolution_pattern": "use waitForURL instead of waitForTimeout",
    "confidence_weight": 0.8,
    "created": "2026-03-01",
    "pinned": false
  }
  ```

**Estimated: 90-95%**

### Level Transition KPIs

| Transition | Ready When |
|---|---|
| L1 -> L2 | L1 tested on 2-3 real repos. Discovery accurate. Tests pass on real projects. |
| L2 -> L3 | Journey generation covers >80% of flows. Fuzz tests find real bugs. Debate terminates correctly. |
| L3 -> L4 | Security tests catch auth boundary issues. Flaky analyzer fixes >50%. Quality score trusted. |
| L4 -> L5 | QA gate runs on 10+ PRs. No false-positive blocks. Suite doesn't degrade. |

---

## Cross-Cutting Concerns

### Test Data Strategy
- Deterministic fixtures (seeded data, not random)
- Data isolation (each test creates/cleans own data)
- No production data
- Parallel-safe (unique identifiers per test)
- Cleanup via API-based teardown or `afterEach` hooks
- L1: Simple inline test data. L2+: Fixture factories matching state matrix.

### Environment Control
- URL detection order: playwright.config.ts baseURL -> .env vars -> ask user
- Environment detection: NODE_ENV / env indicators
- Safety: NEVER run destructive tests against staging/production
- Tests use `baseURL` from Playwright config, never hardcode URLs
- QA_RESULT includes `environment` field

### Observability & Artifacts
- `trace: 'on-first-retry'`, `video: 'retain-on-failure'`, `screenshot: 'only-on-failure'`
- Network HAR capture on failure
- JSON reporter always enabled (agent parses)
- HTML reporter for human review
- Artifacts in `test-results/` (gitignored)

### Governance & Safety Controls

| Control | Limit | Rationale |
|---|---|---|
| Max crawl depth | 3 levels | Prevents infinite crawl |
| Max pages crawled | 30 | Budget constraint |
| Max state combinations | 50 | Prevents combinatorial explosion |
| Max test files generated | 30 | Prevents unbounded generation |
| Max test execution time | 5 minutes | Kill-switch |
| Max debate rounds | 3 | Hard cap |
| Max tool calls (Executor) | 80 default / 110 --scope + --continue / 60 --plan | Budget zones: GREEN 0-60%, YELLOW 60-80%, ORANGE 80-92%, RED 92%+ (see agents/qa-executor.md for authoritative table) |
| Max screenshots | 10 | Selective vision |

---

## Structured Output Blocks

### QA_RESULT (QA Executor)

```
## QA_RESULT
- task_id: {id}
- status: passed | failed | partial | skipped | needs_human
- rounds_run: {N}/3
- depth: smoke | functional
- environment: local | preview | staging
- tests_generated: {N}
- tests_run_this_session: {N}
- tests_passed: {N}
- tests_failed: {N}
- discovery_confidence: HIGH | MEDIUM | LOW
- discovery_warnings: [{array of strings}]
- coverage: routes {X}/{Y}, apis {X}/{Y}
- coverage_weighted: {risk-adjusted %}
- risk_score: {0-100}
- interaction_coverage: forms {X}/{Y}, tables {X}/{Y}, modals {X}/{Y}
- app_topology: { ui_present, api_style, client_platform }
- detected_auth_method: {e.g., "oauth:auth0", "session"}
- websocket_detected: true | false
- bugs_found: {N}         # integer count of REAL_BUG failures
- bugs_blocking: {N}      # integer count of BLOCKING-severity bugs
- bugs: [...]             # optional detailed bug records (see RESULT_SCHEMAS.md)
- discovery_gaps: [...]   # DISCOVERY_GAP test failures
- environment_issues: [...] # ENVIRONMENT_ISSUE test failures
- strategist_verdict: approved | rejected | timeout
- files_created: [paths]
- error: none | {description}
- notes: {1-2 sentences}

See docs/RESULT_SCHEMAS.md for authoritative field types, optionality, and validation rules.
```

### STRATEGIST_VERDICT (QA Strategist)

```
## STRATEGIST_VERDICT
- round: {N}/3
- verdict: approved | rejected
- coverage_achieved: routes {X}/{Y}, apis {X}/{Y}
- coverage_target: {pct}
- gaps: [{test_type}] {description} -- {risk}
- blocking_bugs: {N}
- quality_score: {0-100}
- rationale: {1-2 sentences}
```

### GRAPHQL_RISK_OVERRIDES (QA Strategist, Strategy Mode only)

Emitted when `api_style` is `graphql` or `mixed`. Markdown table with columns:
`Operation | Method | Risk | Reason`. Consumed by QA Executor in Phase 7
write-back to update per-operation risk in `discovery/api-calls.json`.

```markdown
### GraphQL Risk Overrides

| Operation | Method | Risk | Reason |
|---|---|---|---|
| createUser | MUTATION | HIGH | auth + data mutation |
| getUsers | QUERY | MEDIUM | (default) |
```

See `docs/RESULT_SCHEMAS.md` for full schema, validation rules, and write-back behavior.

---

## Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Discovery approach | 4-phase: static + runtime crawl + selective vision + merge | DOM primary, vision enhancement. Budget-efficient |
| Vision usage | Selective, 10-20% of pages | Reduces cost, increases determinism |
| Primary data source | DOM structure + a11y tree + network intercepts | More reliable than screenshots |
| Auth detection | Detect-and-adapt | Best UX, handles most setups |
| Crawl bounds | Max depth 3, max 30 pages, same-origin, dedup | Prevents infinite crawl |
| L1 debate loop | 1 round only | Ship fast, validate pipeline |
| L1 coverage | Lightweight inventory | Prevents "generate and hope" |
| Security scope | Non-destructive validation only | Auth boundary + role enforcement + sanitization |
| L5 guardrail | Production data refines, never removes coverage | Prevents under-testing |
| Performance tests | Playwright basic + k6 config | Agent can't simulate 100+ users |
| Production feedback | Batch import | CLI agent can't monitor production |
