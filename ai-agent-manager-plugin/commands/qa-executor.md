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

## See Also

- `/qa-strategist` — Plan risk-based test strategy independently
- `/code-reviewer` — Review code changes
- `/agent-help` — List all commands
