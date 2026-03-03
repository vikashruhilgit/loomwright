# AI Agent Manager

A Claude Code plugin for AI agents to collaborate on software projects. 11 specialized agents (Launch Pad, Supervisor v4, Execute Manager, Context-Keeper, Worker, Product Owner, Orchestrator, Code Reviewer, Red Team Reviewer, QA Strategist, QA Executor) and the `/commit` skill automate plan-first readiness, parallel workflow execution, requirements, planning, review, commits, adversarial audits, and dual-agent QA automation.

**Key Idea:** Your projects need only a `CLAUDE.md` file for codebase knowledge. The Supervisor uses `.supervisor/` for state management. Orchestrator and Product Owner can optionally use [Beads issue tracker](https://github.com/anthropics/beads). Repeatable across any project.

> **Install the plugin and run slash commands instead of manually managing agents.**
>
> **NEW in v5:** Dual-agent QA system — `/qa-executor` discovers your app, generates risk-based Playwright tests, and `/qa-strategist` audits the results. Plus all v4 features: `/launch-pad` for goal preparation and `/supervisor` for fully autonomous parallel workflows.

---

## Quick Start

### 1. Install the Plugin

```bash
# Add marketplace
/plugin marketplace add ./

# Install plugin
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Or manually: `cp -r ai-agent-manager-plugin ~/.claude/plugins/`

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
│   └── jobs/              # Supervisor-Ready Briefs from Launch Pad
├── .beads/                # Beads issue tracker (optional, for Orchestrator/Product Owner)
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
/supervisor job: .supervisor/jobs/{date}-{slug}.md

# Or run directly
/supervisor task: "what you want to accomplish"

# Or plan manually
/orchestrator goal: "what you want to accomplish"
```

---

## The 11 Agents

### User-Facing Agents (8 + commit skill)


| Agent                 | Command                         | Purpose                                                            | When                            |
| --------------------- | ------------------------------- | ------------------------------------------------------------------ | ------------------------------- |
| **Launch Pad**        | `/launch-pad goal: "..."`       | Prepare goals for autonomous Supervisor execution                  | Before `/supervisor`, planning  |
| **Supervisor**        | `/supervisor task: "..."`       | Autonomous workflow → parallel workers → PR creation               | Full automation                 |
| **Product Owner**     | `/product-owner feature: "..."` | Define requirements → create user stories with acceptance criteria | New feature, vague requirements |
| **Orchestrator**      | `/orchestrator goal: "..."`     | Plan work → create tasks with review gates                         | Starting implementation         |
| **Code Reviewer**     | `/code-reviewer src/`           | Review code → output PASS/FAIL/NEEDS_HUMAN                         | After writing code              |
| **Commit** (skill)    | `/commit`                       | Stage changes → create conventional commits                        | Ready to commit                 |
| **Red Team Reviewer** | `/red-team-reviewer`            | Adversarial audit → find production failures                       | Pre-launch, security            |
| **QA Strategist**     | `/qa-strategist src/`           | Risk-based test strategy → coverage targets                        | Before QA, strategy planning    |
| **QA Executor**       | `/qa-executor`                  | Discover app → generate + run Playwright tests → QA_RESULT         | Automated QA                    |


### Internal Agents (3)


| Agent               | Spawned By                   | Purpose                                                               |
| ------------------- | ---------------------------- | --------------------------------------------------------------------- |
| **Execute Manager** | Supervisor (Phase 3)         | Own poll loop, worker/reviewer lifecycle, Context-Keeper coordination |
| **Context-Keeper**  | Supervisor / Execute Manager | Manage externalized state file (sole writer)                          |
| **Worker**          | Execute Manager / Supervisor | Implement a single subtask in an isolated git worktree                |


### Plan-First Autonomous Workflow

```
/launch-pad goal: "add user authentication"
    ↓
Supervisor-Ready Brief saved to .supervisor/jobs/
    ↓
/supervisor job: .supervisor/jobs/{date}-{slug}.md   (fresh session)
    ↓
INIT → ACQUIRE → PLAN → EXECUTE (via Execute Manager) → FINALIZE → LOOP
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
GENERATE: Playwright tests (UI/E2E + API, role-based locators)
    ↓
EXECUTE: npx playwright test --reporter=json
    ↓
COVERAGE: Routes discovered vs tested, APIs discovered vs tested
    ↓
AUDIT: QA Strategist reviews results → STRATEGIST_VERDICT
    ↓
QA_RESULT: passed | failed | needs_human
```

**Requirements:**
- `playwright.config.ts` (or .js) must exist
- App must be running at the base URL
- `npx` available (Node.js installed)
- Playwright browsers installed (`npx playwright install`)

**Quick commands:**
```bash
/qa-executor                              # Full QA run
/qa-executor --skip-strategy              # Skip Strategist, use defaults
/qa-executor --url http://localhost:3000  # Override URL
/qa-strategist src/                       # Strategy only (no tests)
```

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
- **.claude-plugin/README.md:** Detailed plugin documentation
- **ai-agent-manager-plugin/agents/*.md:** Individual agent prompts (11 roles)
- **ai-agent-manager-plugin/skills/*/SKILL.md:** 36 skill files for guidance
- **ai-agent-manager-plugin/docs/QA_SYSTEM_BLUEPRINT.md:** QA system architecture

---

## For Developers

To modify or extend agents:

1. Agents are Markdown prompts in `ai-agent-manager-plugin/agents/` (11 files)
2. Commands are in `ai-agent-manager-plugin/commands/` (9 commands)
3. Skills are in `ai-agent-manager-plugin/skills/` (36 skills)
4. Hooks are in `ai-agent-manager-plugin/hooks/hooks.json` (SubagentStop + TaskCompleted)
5. All agents follow standard output format (see AGENT_GUIDELINES.md)

To test locally:

```bash
/plugin marketplace add ./
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Then run agents in a test project to verify changes.

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

**Skills not showing after plugin update?**

Claude Code caches plugin contents. After restructuring skills, force a refresh:

1. Remove plugin and marketplace:
  ```
   /plugin marketplace remove ai-agent-manager-marketplace
   /plugin uninstall ai-agent-manager-plugin
  ```
2. Re-add marketplace:
  ```
   /plugin marketplace add /path/to/ai-agent-manager
  ```
3. Reinstall plugin:
  ```
   /plugin install ai-agent-manager-plugin
  ```
4. Restart Claude Code (close and reopen entirely)
5. Verify with `/skills` — should show all 36 skills under "Plugin skills"

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