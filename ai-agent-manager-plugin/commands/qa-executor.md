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
  subagent_type: "ai-agent-manager-plugin:ai-agent-manager-plugin:qa-executor"
)
```

**DO NOT** attempt to execute the QA Executor protocol yourself.
**DO NOT** delegate to Explore agents for discovery.
The QA Executor agent has its own tools, budget tracking, and 13-phase protocol.

---

## Usage

```
/qa-executor [--depth smoke|functional] [--url http://...] [--plan] [--scope feature:{name}] [--continue] [--skip-strategy] [--auto-discover]
```

## Parameters

- **--depth** — `smoke` (navigate + verify visible) or `functional` (default, discovery-driven)
- **--url** — Override base URL (default: from playwright.config.ts or .env)
- **--plan** — Survey app (100-page crawl), create testing plan, no tests run
- **--scope feature:{name}** — Test one feature area deeply (requires --plan first)
- **--continue** — Auto-pick next pending scope from plan
- **--skip-strategy** — Use default risk classification instead of spawning Strategist
- **--auto-discover** — Proceed even on LOW confidence discovery

## What This Does

1. Detects URL + probes for test infrastructure (Mailpit, mock servers)
2. Runs 4-phase discovery (static + runtime crawl + vision + merge)
3. Triages pre-existing tests
4. Gets risk strategy from QA Strategist
5. Generates tests using signal→pattern architecture (qa-test-patterns skill)
6. Runs 4-tier gap analysis (existence, cross-endpoint consistency, frontend↔backend, compliance)
7. Submits tests to QA Strategist for independent 12-gate audit
8. Executes tests with `--retries=1`
9. Tracks coverage (routes, APIs, interactions discovered vs tested)
10. Reports bugs with failure classification (REAL_BUG vs DISCOVERY_GAP vs ENVIRONMENT_ISSUE)
11. Emits MISSING_FUNCTIONALITY_REPORT + QA_RESULT

## Requirements

- `playwright.config.ts` must exist
- Application must be running at detected URL
- `npx` must be available

## Budget

- Default: 80 tool calls
- --scope: 90 tool calls
- --plan: 60 tool calls

## See Also

- `/qa-strategist` — Plan risk-based test strategy independently
- `/code-reviewer` — Review code changes
- `/agent-help` — List all commands
