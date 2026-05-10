# AI Agent Manager

A Claude Code plugin for AI agents to collaborate on software projects. 12 specialized agents (Launch Pad, Supervisor v4, Execute Manager, Context-Keeper, Worker, Plan Reviewer, Product Owner, Orchestrator, Code Reviewer, Red Team Reviewer, QA Strategist, QA Executor) and the `/commit` skill automate plan-first readiness, parallel workflow execution, requirements, planning, review, commits, adversarial audits, and dual-agent QA automation.

**Key Idea:** Your projects need only a `CLAUDE.md` file for codebase knowledge. The Supervisor uses `.supervisor/` for state management. Orchestrator and Product Owner can optionally use [Beads issue tracker](https://github.com/anthropics/beads). Repeatable across any project.

> **Install the plugin and run slash commands instead of manually managing agents.**
>
> **NEW in v12.2.0:** New capabilities increment — (1) **Agent Teams graduation** (3-of-6 patterns now recommended: research/exploration, competing hypotheses, cross-layer changes; the rest stay experimental), (2) an **Outcomes Rubric** scored by a Haiku grader at the end of every Supervisor run (`rubric_score` is an optional `"N/M" | null` field in `SUPERVISOR_RESULT` — null when the brief omits the section), (3) a new **`/dreaming`** slash command for read-only post-hoc reflection on completed sessions (no code or memory writes by the command itself), and (4) an **opt-in webhook SubagentStop hook** that POSTs structured agent results to a user-configured endpoint for external monitoring/dashboards (disabled by default, fail-closed on errors). 11 slash commands, 14 quality gate hooks. All v12.1.0 documentation increments preserved.
>
> **v12.1.0 (preserved):** Documentation + skills increment — Memory Tool skill (Anthropic memory-tool pattern reference), "## Structured Outputs" section in `AGENT_GUIDELINES.md` documenting both enforcement paths (`output_config.format` for direct API agents, `SubagentStop` hooks for plugin agents), and the "## Advisor Tool (SDK-only pattern)" section noting the `advisor-tool-2026-03-01` beta is reachable only via direct `client.beta.messages.create(...)` calls.
>
> **v12.0.0 (preserved):** Reliability primitives — inter-subtask `provides` / `requires` contracts, pre-spawn dependency verification gate, scope-expansion adjudication (4-option escalation), effort-tier discipline across the 10 execution-shaped agents (haiku context-keeper and discovery-only product-owner exempt), and hardened SubagentStop validation rejecting `outputs_gap` / `toolset_gap` drift. WORKER_RESULT schema bumped to v2.
>
> **v7 baseline (preserved):** Enhanced Code Reviewer (LSP diagnostics, read-only mode, issue categorization: new/pre_existing/nit), senior-grade QA (strict assertions, negative testing, CRUD lifecycle, data integrity probes, security boundary tests, missing functionality detection with `MISSING_FUNCTIONALITY_REPORT`), session-based QA (`--plan`, `--scope`, `--continue`), Strategist assertion quality audit. Plus all v6 features: structured result schemas, failure escalation, merge safety gate, session logging, per-agent hooks, architecture contracts.

---

## Quick Start

### 1. Install the Plugin

**Local development (from a checkout of this repo):**

```
/plugin marketplace add /path/to/ai-agent-manager
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

The repo is a marketplace wrapper (`/.claude-plugin/marketplace.json`) with the plugin nested at `ai-agent-manager-plugin/`. The first command registers the marketplace, the second installs the plugin from it.

Once published to the official Anthropic marketplace, installation becomes a single `/plugin install` command without needing a local checkout.

### 2. Setup Your Project

```bash
cd /path/to/your-project

# Create CLAUDE.md with your project patterns
# (See CLAUDE.md Structure section below)

# Optional: Initialize Beads issue tracker (for Orchestrator/Product Owner)
bd init
```

This creates:

```
your-project/
├── CLAUDE.md              # Codebase knowledge (you maintain)
├── .supervisor/           # Supervisor state (auto-created, gitignored)
│   ├── state.md           # Current session state
│   ├── history/           # Completed session summaries
│   ├── jobs/              # Supervisor-Ready Briefs lifecycle
│   │   ├── pending/       # Launch Pad saves briefs here
│   │   ├── in-progress/   # Supervisor moves brief here on ACQUIRE
│   │   ├── done/          # Supervisor moves here on FINALIZE
│   │   └── failed/        # Supervisor moves here on failure
│   ├── logs/              # Structured JSONL session logs
│   └── worker-summaries/  # Worker summaries (inline mode)
├── .beads/                # Beads issue tracker (optional)
│   └── issues/
└── src/ (your code)
```

### 3. (Optional) Enable MySQL MCP

The plugin bundles a read-only MySQL MCP server that gives agents direct database access — schema inspection, query execution with impact analysis, and multi-DB profile switching.

**Set your DB credentials as environment variables** (add to `~/.zshrc` or `~/.bashrc`):

```bash
export DB_HOST=localhost
export DB_USER=myuser
export DB_PASS=mypassword
export DB_NAME=mydatabase
export DB_PORT=3306        # numeric string, defaults to 3306
```

> **Note:** Running `export` in your terminal takes effect **immediately in the current session only**. When you close that terminal or open a new one, the variables are gone. To persist across sessions, add these lines to `~/.zshrc` or `~/.bashrc`:
> ```bash
> echo 'export DB_HOST=localhost' >> ~/.zshrc
> echo 'export DB_USER=myuser' >> ~/.zshrc
> echo 'export DB_PASS=mypassword' >> ~/.zshrc
> echo 'export DB_NAME=mydatabase' >> ~/.zshrc
> echo 'export DB_PORT=3306' >> ~/.zshrc
> source ~/.zshrc
> ```

The MCP server starts automatically via `uvx` when the plugin is loaded — no extra steps needed.

**Multi-DB profiles** (optional) — connect to multiple databases by setting:

```bash
export DB_PROFILES_MYSQL_PROD='{"host":"prod.example.com","user":"ro","pass":"secret","db":"myapp"}'
export DB_PROFILES_MYSQL_STAGING='{"host":"staging.example.com","user":"ro","pass":"secret","db":"myapp"}'
```

Then call `switch_database(host="prod.example.com")` at runtime to switch between them.

> **Security:** Only `SELECT` queries are permitted. All write operations (`INSERT`, `UPDATE`, `DELETE`, `DROP`, etc.) are blocked.

---

### 4. Run Your First Command

```bash
# Plan-first autonomous workflow
/launch-pad goal: "what you want to accomplish"
/supervisor job: .supervisor/jobs/pending/{date}-{slug}.md

# Or run directly
/supervisor task: "what you want to accomplish"

# Or plan manually
/orchestrator goal: "what you want to accomplish"
```

---

## The 13 Agents

### User-Facing Agents (8 + commit skill)


| Agent                 | Command                         | Purpose                                                            | When                            |
| --------------------- | ------------------------------- | ------------------------------------------------------------------ | ------------------------------- |
| **Launch Pad**        | `/launch-pad goal: "..."`       | Prepare goals for autonomous Supervisor execution with feasibility gate (Phase 2.5: GO/CAUTION/NO-GO) and mandatory Plan Review (Phase 5.5) | Before `/supervisor`, planning  |
| **Supervisor**        | `/supervisor task: "..."`       | Autonomous workflow → parallel workers → PR creation               | Full automation                 |
| **Product Owner**     | `/product-owner feature: "..."` | Define requirements → create user stories with acceptance criteria. Assumption Check (standard flow, user gate before `bd create` if flags) + Reality Check (brainstorm flow, VIABLE/NEEDS_FOUNDATION/BLOCKED with Feasibility score caps). Use `--brainstorm` for multi-mind ideation. | New feature, vague requirements, exploring directions |
| **Orchestrator**      | `/orchestrator goal: "..."`     | Plan work → create tasks with review gates                         | Starting implementation         |
| **Code Reviewer**     | `/code-reviewer src/`           | Review code → output PASS/FAIL/NEEDS_HUMAN                         | After writing code              |
| **Commit** (skill)    | `/commit`                       | Stage changes → create conventional commits                        | Ready to commit                 |
| **Red Team Reviewer** | `/red-team-reviewer`            | Adversarial audit → find production failures                       | Pre-launch, security            |
| **QA Strategist**     | `/qa-strategist src/`           | Risk-based test strategy → coverage targets → assertion quality audit | Before QA, strategy planning    |
| **QA Executor**       | `/qa-executor`                  | Discover → generate strict tests → find missing functionality → QA_RESULT | Automated QA                    |


### Internal Agents (5)


| Agent               | Spawned By                   | Purpose                                                               |
| ------------------- | ---------------------------- | --------------------------------------------------------------------- |
| **Execute Manager** | Supervisor (Phase 3)         | Own poll loop, worker/reviewer lifecycle, Context-Keeper coordination |
| **Context-Keeper**  | Supervisor / Execute Manager | Manage externalized state file (sole writer)                          |
| **Worker**          | Execute Manager / Supervisor | Implement a single subtask in an isolated git worktree                |
| **Plan Reviewer**   | Launch Pad                   | Validate Supervisor-Ready Briefs before execution                     |
| **Rubric Grader**   | Supervisor (Phase 4.5)       | Read-only Haiku scorer for the optional Outcomes Rubric (advisory)    |


### Plan-First Autonomous Workflow

```
/launch-pad goal: "add user authentication"
    ↓
Supervisor-Ready Brief saved to .supervisor/jobs/pending/
    ↓
/supervisor job: .supervisor/jobs/pending/{date}-{slug}.md   (fresh session)
    ↓
INIT → ACQUIRE → PLAN → EXECUTE (via Execute Manager) → FINALIZE → SELF_HEAL → LOOP
    ↓
PR created, next task or exit
```

### Autonomous Workflow (Supervisor v4)

```
/supervisor task: "add user authentication"
    ↓
INIT: Detect env → Ask preferences → Create .supervisor/
    ↓
ACQUIRE: Select task → Create feature branch (MANDATORY)
    ↓
PLAN: Orchestrator → Subtasks → Parallelism analysis
    ↓
EXECUTE: → Execute Manager (isolated context, 60 tool call budget)
         Worktree A ─→ Worker A ─→ Reviewer A ─→ PASS
         Worktree C ─→ Worker C ─→ Reviewer C ─→ PASS
         (unblocked) → Worktree B → Worker B → PASS
         ← EXECUTE_RESULT (merge_order, worktrees, branches)
    ↓
FINALIZE: Pre-merge validation → Commit in worktrees → Sequential merge → PR
    ↓
LOOP: Next task or exit
```

### Manual Workflow

```
Product Owner → Create user stories (requirements)
    ↓
Orchestrator → Break into tasks (EPIC → TASK → SUBTASK)
    ↓
You code
    ↓
Code Reviewer → PASS/FAIL/NEEDS_HUMAN (review gate)
    ↓
You fix issues (if needed)
    ↓
/commit → Conventional commits
    ↓
Next task
```

### QA Workflow

```
/qa-executor
    ↓
DETECT URL: playwright.config.ts → .env → ask user
    ↓
DISCOVER: Static analysis → Runtime crawl → Selective vision → Merge & gate
    ↓
STRATEGY: QA Strategist classifies routes (HIGH/MEDIUM/LOW risk)
    ↓
GENERATE: Strict tests (value assertions, negative tests, CRUD lifecycle,
          data integrity probes, security boundary tests)
    ↓
GAP ANALYSIS: Missing functionality detection → MISSING_FUNCTIONALITY_REPORT
    ↓
EXECUTE: npx playwright test --reporter=json
    ↓
COVERAGE: Routes discovered vs tested, APIs discovered vs tested
    ↓
AUDIT: QA Strategist reviews results + assertion quality + gaps → STRATEGIST_VERDICT
    ↓
QA_RESULT: passed | failed | needs_human
MISSING_FUNCTIONALITY_REPORT: gaps found in the app
```

**Requirements:**
- `playwright.config.ts` (or .js) must exist
- App must be running at the base URL
- `npx` available (Node.js installed)
- Playwright browsers installed (`npx playwright install`)

**Quick commands:**
```bash
/qa-executor                              # Full QA run (functional depth)
/qa-executor --skip-strategy              # Skip Strategist, use defaults
/qa-executor --url http://localhost:3000  # Override URL
/qa-executor --depth smoke                # Quick smoke tests only
/qa-executor --depth functional           # Deep tests (default)
/qa-strategist src/                       # Strategy only (no tests)
/qa-strategist --audit .qa-summary.md     # Audit existing QA results
```

### Session-Based QA (Large Apps)

For apps with many routes, use session-based QA to test in chunks:

```bash
# Step 1: Create a test plan (discovers all routes, groups into scopes)
/qa-executor --plan

# Step 2: Test one scope at a time
/qa-executor --scope auth            # Test auth scope
/qa-executor --scope tournaments     # Test tournaments scope
/qa-executor --scope billing         # Test billing scope

# Step 3: Continue with next unfinished scope
/qa-executor --continue              # Auto-picks next pending scope

# Step 4: Check cumulative coverage
# coverage.json tracks routes_tested/routes_total across sessions
```

**How it works:**
- `--plan` runs discovery and creates `.qa-session/plan.json` with scopes sorted by risk priority
- `--scope <name>` tests only routes in that scope, updates `.qa-session/coverage.json`
- `--continue` picks the next `pending` scope from the plan automatically
- Coverage accumulates across sessions — no retesting already-covered routes

### What the QA Agent Tests

**Assertion strictness (all modes):**
- Exact HTTP status assertions (`toBe(200)`, never `toContain([200, 500])`)
- Response body VALUE assertions (not just property existence)
- State verification after mutations (GET after POST/PUT/DELETE)
- 5xx responses are ALWAYS BLOCKING bugs — never accepted

**Negative testing (functional depth, HIGH/MEDIUM risk):**
- Empty body → expect 400
- Missing required fields → expect 400 with field name in error
- Wrong types → expect 400
- No auth / invalid auth → expect 401

**Multi-step flows (functional depth, HIGH risk):**
- CRUD lifecycle: create → read → update → verify → delete → verify gone
- Auth lifecycle: login → access protected → logout → verify session revoked

**Data integrity probes (functional depth, HIGH risk):**
- Concurrent creation race conditions (`Promise.all`)
- Duplicate creation → expect 409/400
- Cascade delete verification

**Security boundary tests (functional depth, HIGH risk):**
- Cross-resource access (IDOR) → expect 403/404
- Role escalation → expect 403
- Session invalidation after logout
- XSS/SQL injection probes (non-destructive)

**Missing functionality detection (all modes):**
- Missing CRUD operations (create exists but no edit/delete)
- Missing pagination on list endpoints
- Missing search/filter on data tables
- Missing input validation on forms
- Missing rate limiting on auth endpoints
- Missing confirmation dialogs on destructive actions
- Output: `MISSING_FUNCTIONALITY_REPORT` with severity + recommendations

---

## Telemetry (opt-in)

**New in v11.2.0 (preserved in v12.2.0)** — an optional GitHub Issues telemetry pipeline. After
qualifying agent runs (`/supervisor`, `/code-reviewer`, `/qa-executor`)
complete, the plugin can post a structured GitHub issue summarising the
result block, a derived score, agent performance breakdown, and AI
suggestions for longitudinal analysis. Telemetry is **disabled by
default** — there is no `origin`-remote fallback because the plugin runs
in arbitrary user projects.

```bash
/telemetry status     # Show consent state, target repo, last-sent timestamp
/telemetry enable     # Interactive — choose target repo, write consent file
/telemetry disable    # Mark consent denied; no further sends
/telemetry test       # Dry-run latest payload; never calls gh
```

**Privacy guarantees:** the wrapper script always exits 0 (telemetry
can never block an agent run); the core script fails closed on a regex
deny-list (tokens, API keys, bearer tokens, home-dir paths, emails,
`.env`-style assignments) and never emits matched content — only the
pattern label. To enable, run `/telemetry enable` (and pick a target
repo) or set `AI_AGENT_MANAGER_TELEMETRY_REPO=owner/repo`. See
[ai-agent-manager-plugin/docs/TELEMETRY.md](ai-agent-manager-plugin/docs/TELEMETRY.md)
for the scoring rubric, exit-code table, and wrapper-vs-core
architecture.

---

## Task Management

### Beads (Optional)

Beads is an optional issue tracker used by Orchestrator and Product Owner. The Supervisor and Launch Pad use `.supervisor/` exclusively.


| Command                   | Purpose                               |
| ------------------------- | ------------------------------------- |
| `bd list`                 | View open/in-progress/completed tasks |
| `bd create`               | Create new task                       |
| `bd claim BD-XX`          | Start working on a task               |
| `bd close BD-XX`          | Mark task complete                    |
| `bd comment BD-XX "note"` | Add notes to task                     |
| `bd dep BD-XX BD-YY`      | Set task dependencies                 |


**Task Structure:**

- **EPIC:** Large feature (contains multiple tasks)
- **TASK:** Implementation work (30-60 min)
- **SUBTASK:** Review gate (blocks next task)

**Review Gates:**

- Every implementation task has a review subtask
- Review subtask blocks next implementation task
- Review decisions: PASS (proceed), FAIL (fix and re-review), NEEDS_HUMAN (creates bug issues)

---

## Project Setup

### For New Projects

1. Create CLAUDE.md with your project structure and patterns
2. Run `/launch-pad goal: "first task"` (plan-first) or `/supervisor task: "first task"` (direct)
3. Optional: `bd init` if using Orchestrator/Product Owner with Beads

### CLAUDE.md Structure

Fill in once at the start:

```markdown
# [Your Project Name]

## Structure
- src/ — [what's here]
- test/ — [what's here]

## Tech Stack
- Node.js, Express, PostgreSQL
- Jest for testing

## Key Patterns
(Document as you discover them)

## Quick Commands
- Build: npm run build
- Test: npm test
- Lint: npm run lint
```

---

## Common Patterns & Best Practices

### Agents Follow These Rules

- **Quality First:** Thorough, well-tested solutions
- **Surgical Changes:** Only modify what's necessary
- **Pattern Consistency:** Use existing patterns
- **Type Safety:** Strict type checking
- **Security:** No secrets, validate inputs
- **Performance:** Profile and document tradeoffs

See `AGENT_GUIDELINES.md` for detailed standards per language.

### Workflow Tips

1. **Plan first:** Run `/launch-pad goal: "..."` to prepare a Supervisor-Ready Brief
2. **Use Supervisor for automation:** Run `/supervisor` for fully autonomous task completion
3. **Or start with Orchestrator:** Run `/orchestrator goal: "..."` for manual control
4. **Review iteratively:** Run `/code-reviewer` multiple times as you fix issues
5. **Review gates:** Wait for PASS before moving to next task
6. **Adversarial audit:** Run `/red-team-reviewer` before launch

### CLAUDE.md Proposal Workflow

When Code Reviewer discovers a new pattern:

1. **Flag in review output:** Pattern flagged with rationale and file:line references
2. **You review:** Check if worth documenting
3. **If approved:** You update CLAUDE.md manually
4. **Next agent learns:** Reads updated CLAUDE.md, uses the new pattern

This prevents knowledge loss and helps agents learn from discoveries.

---

## Documentation

- **This file (README.md):** Overview and quick start
- **CLAUDE.md (this repo):** Architecture and agent system
- **AGENT_GUIDELINES.md:** Development standards, quality checklist
- **.claude-plugin/marketplace.json:** Marketplace manifest (root)
- **.claude-plugin/README.md:** Detailed plugin documentation
- **ai-agent-manager-plugin/.claude-plugin/plugin.json:** Plugin manifest
- **ai-agent-manager-plugin/agents/*.md:** Individual agent prompts (13 roles)
- **ai-agent-manager-plugin/skills/*/SKILL.md:** 49 skill files for guidance
- **ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md:** Structured result contracts
- **ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md:** Agent failure paths
- **ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md:** Capability matrix, budgets, rules
- **ai-agent-manager-plugin/docs/ARCHITECTURE.md:** Visual agent topology
- **ai-agent-manager-plugin/docs/QA_SYSTEM_BLUEPRINT.md:** QA system architecture

---

## For Developers

To modify or extend agents:

1. Agents are Markdown prompts in `ai-agent-manager-plugin/agents/` (13 files)
2. Commands are in `ai-agent-manager-plugin/commands/` (11 commands)
3. Skills are in `ai-agent-manager-plugin/skills/` (49 skills, versioned with SKILLS_INDEX.md)
4. Hooks: per-agent in frontmatter (Worker, Execute Manager) + cross-cutting in `ai-agent-manager-plugin/hooks/hooks.json` (Code Reviewer, QA Executor, TaskCompleted)
5. Docs: `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`, `…/FAILURE_ESCALATION.md`, `…/ARCHITECTURE_CONTRACTS.md`, `…/ARCHITECTURE.md`
6. All agents follow standard output format (see AGENT_GUIDELINES.md)

To test locally, install via the marketplace flow shown in **Quick Start → 1. Install the Plugin**, then run agents in a test project to verify changes. After pulling new changes, use the refresh flow under **Troubleshooting → Skills / agents / hooks not showing after plugin update**.

---

## Troubleshooting

**Agent doesn't understand my project?**

- Update CLAUDE.md with clearer patterns and examples
- Add more detailed structure documentation

**Supervisor workflow interrupted?**

- State is saved to `.supervisor/state.md` automatically
- Resume with: `/supervisor --continue`
- Check `.supervisor/history/` for completed sessions

**Orphaned worktrees after crash?**

- Run `git worktree list` to see all worktrees
- Remove with: `git worktree remove ../project-{subtask_id}`

**Beads tasks not appearing?**

- Run `bd list` to check current state
- Ensure `bd init` was run in project
- Beads is only used by Orchestrator/Product Owner (not Supervisor)

**Agents suggesting wrong patterns?**

- Update CLAUDE.md with approved patterns
- Review and reject unwanted proposals

**Need help?**

- Run `/agent-help` for command reference
- Check AGENT_GUIDELINES.md for quality standards
- Check .claude-plugin/README.md for detailed command documentation
- Review agent prompts in ai-agent-manager-plugin/agents/

**Skills / agents / hooks not showing after plugin update?**

Claude Code caches plugin contents. After pulling new changes (e.g. a fresh `git pull` on main), force a full refresh:

1. **Minimal flow** — try this first:
   ```
   /plugin uninstall ai-agent-manager-plugin
   /plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
   /reload-plugins
   ```
2. **Full reset** — if the minimal flow doesn't pick up your changes, drop the marketplace cache too:
   ```
   /plugin uninstall ai-agent-manager-plugin
   /plugin marketplace remove ai-agent-manager-marketplace
   /plugin marketplace add ./
   /plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
   /reload-plugins
   ```
   Run from the repo root so `./` resolves to your local checkout.
3. Verify with `/skills` — should show all 49 skills under "Plugin skills". Use `/agent-help` to confirm all 11 user-facing commands are registered.

**Previously installed via `claude --plugin-dir` (flat layout)?** Older install instructions told you to launch Claude with `--plugin-dir` pointing at the repo root. That no longer works — the plugin is now nested under `ai-agent-manager-plugin/`. Switch to the marketplace flow shown in **Quick Start → 1. Install the Plugin**.

---

## Known Limitations

### Agent Behavior

- **LLM limitations:** Agents may occasionally reference non-existent files despite validation steps. Always verify before following plans.
- **Context7 dependency:** External library lookups depend on Context7 MCP. If unavailable, agents fall back to CLAUDE.md patterns.

### Scale

- **Token usage:** Each agent invocation loads prompts (potentially 5,000-10,000 tokens overhead). Consider this for high-frequency usage.

### Git Operations

- **Main branch protection:** The `/commit` skill refuses commits on main/master without explicit flag.
- **No rollback:** Git operations are not automatically reversible. Use `git reflog` for manual recovery.

### QA System (Level 1)

- **Requires Playwright config:** `playwright.config.ts` must exist and app must be running
- **Crawl limits:** Max 30 pages, depth 3, same-origin only
- **Single debate round:** Strategist audits once (multi-round is Level 2+)
- **No state modeling or fuzz:** L1 tests happy paths + basic errors only
- **Coverage is inventory-level:** Tracks routes/APIs discovered vs tested, not behavioral

---

## License

MIT — See LICENSE file

---

**Happy shipping!**