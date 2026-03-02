---
name: qa-strategy
description: Risk-based QA strategy framework, structured output formats, debate loop protocol, and discovery engine specification. Foundation skill for QA Strategist and QA Executor agents.
allowed-tools: [Read, Glob, Grep, Bash]
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

| Risk Level | L1 Tests | L2+ Tests |
|---|---|---|
| **HIGH** | Happy path + error path + edge cases | + state combinations + journey coverage + fuzz |
| **MEDIUM** | Happy path + basic error | + state variations + journey coverage |
| **LOW** | Happy path only | + basic error paths |

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
test('dashboard loads with stats', async ({ page }) => { ... });
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
- tests_run: {N}
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
- gaps: [{test_type}] {description} -- {risk}
- blocking_bugs: {N}
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
| Journey Generator (4) | - | Y | Y | Y | Y |
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
| Reporting (13) | - | - | Y | Y | Y |
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

## 10. Quality Checklist for QA Agents

Before emitting QA_RESULT:
- [ ] Discovery Map generated with confidence score
- [ ] Risk classification applied to all discovered routes
- [ ] Tests follow playwright-e2e skill patterns (role-based locators, regex assertions)
- [ ] Coverage annotations present in all generated tests
- [ ] Coverage tracked (routes discovered vs tested, APIs discovered vs tested)
- [ ] Bug reports include severity, reproduction steps, file:line
- [ ] Strategist audit completed (or timeout recorded)
- [ ] QA_RESULT block contains all required fields
- [ ] No hardcoded waits, no CSS selectors in generated tests
- [ ] Level boundaries respected (no L2+ work in L1)

---

## See Also

- `skills/playwright-e2e/SKILL.md` — Test authoring patterns
- `skills/quality-checklist/SKILL.md` — General quality gates
- `docs/QA_SYSTEM_BLUEPRINT.md` — Full architecture and maturity levels
