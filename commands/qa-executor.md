---
description: Discover app structure, generate and run Playwright tests with risk-based strategy
---

# Command: /qa-executor

## Subagent Enforcement

**When `/qa-executor` is invoked, you MUST spawn the QA Executor agent via Task tool:**

```
Task(
  description: "QA Executor: {flags and context}",
  prompt: "{user flags, project context, and any --scope/--continue/--plan details}",
  subagent_type: "ai-agent-manager-plugin:qa-executor"
)
```

**DO NOT** attempt to execute the QA Executor protocol yourself.
**DO NOT** delegate to Explore agents for discovery.
The QA Executor agent has its own tools, budget tracking, and 13-phase protocol.

---

## Usage

```
/qa-executor [--depth smoke|functional] [--url http://...] [--plan] [--scope feature:{name}] [--continue] [--skip-strategy] [--strict-discovery] [--auto-discover] [--rounds N] [--coverage PCT] [--auth-state ./auth.json]
```

## Parameters

- **--depth** — `smoke` (navigate + verify visible) or `functional` (default, discovery-driven)
- **--url** — Override base URL (default: from playwright.config.ts or .env)
- **--plan** — Survey app (100-page crawl), create testing plan, no tests run
- **--scope feature:{name}** — Test one feature area deeply (requires --plan first)
- **--continue** — Auto-pick next pending scope from plan
- **--skip-strategy** — Use default risk classification instead of spawning Strategist
- **--strict-discovery** — Require human approval of LOW-confidence discovery (default: halt)
- **--auto-discover** — Proceed even on LOW confidence discovery
- **--rounds** — Max debate rounds (default: 1 at L1, cap: 3). Higher values only meaningful at L2+
- **--coverage** — Target coverage percentage (default: risk-based — HIGH 85%, MEDIUM 70%, LOW 50%)
- **--auth-state** — Path to pre-authenticated Playwright storageState file (for OAuth/SSO apps)

## What This Does

1. Detects URL + auto-detects app topology (UI present? REST/GraphQL/mixed? Web/mobile?) + probes test infrastructure (Mailpit, mock servers)
2. Runs 4-phase discovery (static + runtime crawl + vision + merge)
3. Triages pre-existing tests
4. Gets risk strategy from QA Strategist
5. Generates tests using signal→pattern architecture (qa-test-patterns skill)
6. Runs 4-tier gap analysis (existence, cross-endpoint consistency, frontend↔backend, compliance)
7. Submits tests to QA Strategist for independent 13-gate audit
8. Executes tests with `--retries=1`
9. Tracks coverage (routes, APIs, interactions discovered vs tested)
10. Reports bugs with failure classification (REAL_BUG vs DISCOVERY_GAP vs ENVIRONMENT_ISSUE)
11. Emits MISSING_FUNCTIONALITY_REPORT + QA_RESULT

## Requirements

- Application must be running at detected URL
- `npx` must be available
- `playwright.config.ts`:
  - If exists: use as-is (baseURL, projects, timeouts)
  - If missing AND app has a browser UI (`ui_present: true`): status=skipped with "No Playwright config found. Required for UI testing."
  - If missing AND app is API-only (`ui_present: false`): auto-generate a minimal request-only config at project root with `testDir: './e2e/tests'` and a single `api` project
- For OAuth/SSO apps: `--auth-state ./auth.json` recommended for authenticated discovery

## Budget

- Default: 80 tool calls
- --scope / --continue: 110 tool calls
- --plan: 60 tool calls

Budget zones: GREEN 0-60%, YELLOW 60-80%, ORANGE 80-92%, RED 92%+

## See Also

- `/qa-strategist` — Plan risk-based test strategy independently
- `/code-reviewer` — Review code changes
- `/agent-help` — List all commands
