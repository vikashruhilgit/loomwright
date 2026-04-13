# AI Agent Manager Plugin for Claude Code

A Claude Code plugin with 12 agent roles (8 user-facing + 4 internal), 47 focused skills, and optional Beads issue tracker integration. Automates plan-first readiness, parallel workflow execution, requirements definition, code review, adversarial audits, and dual-agent QA testing.

## Overview

The AI Agent Manager Plugin v11.1.0 includes:

- **Code Reviewer as system integrity reviewer** — `diff_review` / `consistency_audit` modes, trigger-based auto-expand, always-included audit baseline (plugin.json + CLAUDE.md + README.md), repo consistency audit (mirrored prompts, version strings, counts, workflow alignment, hooks parity), `CODE_REVIEW_RESULT` schema v3 with `audit_focus` + `drift` category + `drift_kind` severity caps enforced by the plugin hook, CI-wired sync guard (`scripts/check-command-sync.sh`)

Plus all prior v11.0/v10.3/v10.2 capabilities:

- **Phase 4.5 self-heal** — Supervisor runs a holistic Code Reviewer pass on the integrated feature branch and auto-fixes bounded BLOCKING/HIGH `new` issues (up to `--heal-iterations`, default 3), eliminating the manual review-and-fix cycle per feature
- **Beads-optional Code Reviewer** — auto-detects `.beads/` + `bd` CLI; when absent, `CODE_REVIEW_RESULT` is the sole decision channel

### User-Facing Agents (8)

- **Launch Pad** (`/launch-pad`) — Prepare goals for autonomous Supervisor execution
- **Supervisor** (`/supervisor`) — Autonomous parallel workflow orchestrator with git worktrees
- **Product Owner** (`/product-owner`) — Translate business problems into user stories. Supports `--brainstorm` for multi-mind ideation
- **Orchestrator** (`/orchestrator`) — Break goals into tasks with review gates
- **Code Reviewer** (`/code-reviewer`) — Review code with PASS/FAIL/NEEDS_HUMAN decisions (LSP diagnostics, read-only)
- **Red Team Reviewer** (`/red-team-reviewer`) — Adversarial audits to break assumptions
- **QA Strategist** (`/qa-strategist`) — Risk-based test strategy and QA audit
- **QA Executor** (`/qa-executor`) — Discover app, generate Playwright tests, find gaps

### Internal Agents (4)

- **Execute Manager** — Owns Phase 3 worker/reviewer lifecycle (spawned by Supervisor)
- **Context-Keeper** — Sole writer of externalized state file (spawned on-demand)
- **Worker** — Implements a single subtask in an isolated git worktree (spawned by Execute Manager)
- **Plan Reviewer** — Validates Supervisor-Ready Briefs before execution (spawned by Launch Pad)

### 47 Skills

Skills are loaded on-demand to keep context small:

- **Core:** Commits, Context7 lookups, Quality checklist, Pattern detection, Claude.md validation
- **Workflow:** Supervisor readiness, Async orchestration, State management, Context summarization, Workflow management, Agent teams
- **Product:** Brainstorming, Product discovery, MVP scoping, User story writing, Domain knowledge
- **QA:** QA strategy, QA orchestration, QA test patterns, QA gates, Playwright E2E, Unit testing
- **NestJS:** Guards, Controllers, Services, Drizzle ORM, TypeORM
- **Next.js:** Routing, Components, API routes, Data fetching, Authentication
- **Gateway:** Proxy patterns, Auth middleware, Rate limiting, Correlation ID
- **DevOps:** CI/CD, Docker, Monitoring/Observability, Error handling
- **Data:** MySQL, PostgreSQL, Redis caching
- **UI:** Frontend UI (design system, accessibility, responsive)

---

## Quick Start

### 1. Installation

```bash
# From the ai-agent-manager checkout
cd /path/to/ai-agent-manager
/plugin install ./
```

Once published to the official Anthropic marketplace, installation becomes a single command without needing a local checkout.

### 2. Setup Your Project

Your project needs only a `CLAUDE.md` file for agents to work:

```bash
cd /path/to/your/project

# Option A: With Beads (full task management)
bd init

# Option B: Without Beads (Supervisor creates .supervisor/ automatically)
# Just create CLAUDE.md with your project patterns
```

This creates:
```
your-project/
├── CLAUDE.md              # Codebase knowledge (required)
├── .supervisor/           # Supervisor state (auto-created, gitignored)
│   ├── state.md           # Current session state
│   ├── history/           # Completed session summaries
│   └── jobs/              # Supervisor-Ready Briefs from Launch Pad
├── .beads/                # Beads issue tracker (optional)
└── src/                   # Your code
```

### 3. Run Your First Command

```bash
# Plan-first autonomous workflow
/launch-pad goal: "add user authentication"
/supervisor job: .supervisor/jobs/pending/2026-02-08-user-auth.md

# Or run directly
/supervisor task: "add user authentication"

# Or plan manually
/orchestrator goal: "add dark mode to UI"
```

---

## Commands

### /launch-pad goal: "\<goal\>"

Prepare a goal for autonomous Supervisor execution. Analyzes codebase, estimates file impact, validates environment.

```bash
/launch-pad goal: "add user authentication"
/launch-pad goal: "refactor payment module" --discovery
```

**Output:** Supervisor-Ready Brief saved to `.supervisor/jobs/pending/`

---

### /supervisor [task: "\<description\>"] [job: \<path\>]

Autonomous workflow orchestrator. Creates feature branch, plans work, spawns parallel workers in git worktrees, reviews, merges, and creates PR.

```bash
/supervisor                                    # Pick up next Beads task
/supervisor task: "add dark mode"              # Direct task
/supervisor job: .supervisor/jobs/pending/...   # From Launch Pad brief
/supervisor --max-workers 3                    # Parallel workers
```

**Output:** Completed implementation with PR

---

### /product-owner feature: "\<what\>" | problem: "\<issue\>"

Translate business problems into user stories with acceptance criteria.

```bash
/product-owner feature: "staff scheduling for venue events"
/product-owner problem: "we keep double-booking shifts"
/product-owner feature: "order history" --mvp-only
/product-owner problem: "low retention" --brainstorm
/product-owner feature: "new pricing model" --brainstorm deep
```

**Flags:**
- `--mvp-only` — Focus only on MVP scope
- `--discovery` — Run full discovery before writing stories
- `--brainstorm` — 5-lens multi-mind ideation (Creative, PM, Engineer, Business, Critic) with debate, scoring, and recommendation before writing stories
- `--brainstorm deep` — Deep ideation with 2 debate rounds and market research

**Output:** User stories with Given/When/Then acceptance criteria, scope analysis, handoff to Orchestrator

---

### /orchestrator goal: "\<what to do\>"

Break a goal into tasks with mandatory code review subtasks.

```bash
/orchestrator goal: "add dark mode to UI"
/orchestrator goal: "fix login bug" --project /path/to/project
```

**Output:** Beads task structure (EPIC -> TASK -> SUBTASK) with review gates

---

### /code-reviewer [files] [--project /path]

Review code against quality standards. Read-only (never modifies files).

```bash
/code-reviewer src/components/        # Review specific files
/code-reviewer                        # Review recent git changes
```

**Checks:** Type safety (LSP diagnostics), security, performance, pattern consistency, test coverage

**Output:** Issues by severity with category tags (`new`/`pre_existing`/`nit`) + PASS/FAIL/NEEDS_HUMAN decision

---

### /red-team-reviewer [target] [--focus security|scale|cost|ops]

Adversarial audit — find what breaks in production.

```bash
/red-team-reviewer                    # Full audit
/red-team-reviewer src/auth/          # Target specific area
/red-team-reviewer --focus security   # Focus on security vectors
```

**Output:** Findings by severity (FATAL/CRITICAL/WARNING/WEAKNESS) with prioritized fixes

---

### /qa-strategist [target] [--audit .qa-summary.md]

Plan risk-based test strategy or audit QA Executor results.

```bash
/qa-strategist src/                           # Strategy mode
/qa-strategist --audit .qa-summary.md         # Audit mode
/qa-strategist --focus auth                   # Focus area
```

**Output:** Risk classification, coverage targets, STRATEGIST_VERDICT

---

### /qa-executor [--url http://...] [--rounds 1|2|3]

Discover app structure, generate Playwright tests, find gaps, execute.

```bash
/qa-executor                                          # Auto-detect
/qa-executor --url http://localhost:3000               # Explicit URL
/qa-executor --url http://localhost:3000 --skip-strategy
```

**Requires:** `playwright.config.ts` and running application

**Output:** Playwright tests, .qa-summary.md, QA_RESULT block, MISSING_FUNCTIONALITY_REPORT

---

### /commit

Create conventional commits with Beads linking.

```bash
/commit
```

---

### /agent-help

Show all commands and quick reference.

```bash
/agent-help
```

---

## Workflows

### Plan-First Autonomous (Recommended)

```
/launch-pad goal: "..."
    |
.supervisor/jobs/pending/{date}-{slug}.md  (Supervisor-Ready Brief)
    |
/supervisor job: .supervisor/jobs/pending/{file}.md  (clean context)
    |
INIT -> ACQUIRE -> PLAN -> EXECUTE (parallel workers) -> FINALIZE -> PR
```

### Manual

```
/orchestrator goal: "..."     # Plan tasks
    |
bd claim BD-XX                # Start task
    |
(implement code)
    |
/code-reviewer src/           # Review -> PASS/FAIL
    |
/commit                       # Conventional commits
    |
bd close BD-XX                # Complete, next unblocks
```

### QA Automation

```
/qa-strategist src/                    # Risk-based strategy
    |
/qa-executor --url http://localhost:3000  # Generate + run tests
    |
/qa-strategist --audit .qa-summary.md    # Audit results
```

---

## Project Structure

### Plugin Files

```
ai-agent-manager/                        (plugin root — this IS the plugin)
├── .claude-plugin/
│   ├── plugin.json                      # Plugin manifest (v11.1.0)
│   └── README.md                        # This file
├── agents/                              # Agent prompts (12 roles)
│   ├── launch-pad.md, supervisor.md, execute-manager.md, context-keeper.md
│   ├── worker.md, plan-reviewer.md, product-owner.md, orchestrator.md
│   ├── code-reviewer.md, red-team-reviewer.md, qa-strategist.md, qa-executor.md
├── commands/                            # Slash commands (9)
│   ├── launch-pad.md, supervisor.md, product-owner.md, orchestrator.md
│   ├── code-reviewer.md, red-team-reviewer.md, qa-strategist.md, qa-executor.md
│   └── agent-help.md
├── hooks/
│   └── hooks.json                       # 10 quality gate hooks (centralized)
├── skills/                              # 47 focused skill modules
│   ├── SKILLS_INDEX.md                  # Skill catalog with agent mapping
│   └── [skill-name]/SKILL.md            # Individual skills
└── docs/
    ├── RESULT_SCHEMAS.md                # Structured result contracts
    ├── FAILURE_ESCALATION.md            # Retry limits and escalation paths
    ├── ARCHITECTURE_CONTRACTS.md        # Capability matrix, budgets, rules
    ├── ARCHITECTURE.md                  # Visual agent topology
    └── QA_SYSTEM_BLUEPRINT.md           # QA system architecture
```

---

## Key Concepts

### Project Auto-Detection

Agents automatically find your project:

1. Search current directory for CLAUDE.md
2. Search parent directories up to root
3. Use first CLAUDE.md found (nearest wins)
4. Accept `--project /path` override

### Approval Workflow

- **Code Issues:** Agent flags, you fix
- **File Updates:** Agent suggests, you review
- **CLAUDE.md Changes:** Agent proposes, you approve
- **Commits:** Agent creates, you review
- **Pushes:** Only with explicit instruction

### Beads Issue Tracking (Optional)

Agents can read and update Beads:

| Command | Purpose |
|---------|---------|
| `bd list` | View all tasks |
| `bd create` | Create new task |
| `bd claim BD-XX` | Start task |
| `bd close BD-XX` | Mark complete |
| `bd comment BD-XX "note"` | Add notes |
| `bd dep BD-XX BD-YY` | Set dependencies |

### Persistent Agent Memory

Agents with `memory: project` build knowledge across sessions:

| Agent | What It Remembers |
|-------|-------------------|
| Launch Pad | Commonly impacted files, project patterns |
| Code Reviewer | Review patterns, recurring issues, conventions |
| Red Team Reviewer | Past vulnerabilities, attack patterns |
| Product Owner | Domain context, terminology, preferences |
| QA Strategist | Risk patterns, which routes break |
| QA Executor | Flaky patterns, common failures |

### Quality Gate Hooks

10 hooks centralized in `hooks.json` validate agent output:
- **SubagentStop:** Worker, Execute Manager, Code Reviewer, Supervisor, QA Executor, Plan Reviewer
- **Stop:** Code Reviewer (completeness gate)
- **TaskCompleted:** Verify task genuinely done
- **WorktreeCreate / StopFailure:** Logging

---

## Marketplace Setup

### Local Install (Testing)

```bash
cd /path/to/ai-agent-manager
/plugin install ./
```

### Official Marketplace (Distribution)

Once the plugin is accepted into the official Anthropic marketplace, users install with a single command — no local checkout required. See `.claude-plugin/plugin.json` for the plugin manifest.

---

## Troubleshooting

### "Error: No project context found"

Agent couldn't find CLAUDE.md. Create one in your project root or use `--project /path`.

### "No files to review" (Code Reviewer)

No git changes detected. Specify files: `/code-reviewer src/components/MyFile.tsx`

### Supervisor Workflow Interrupted

State is saved to `.supervisor/state.md` automatically. Resume with `/supervisor --continue task: BD-XX`.

### Orphaned Worktrees After Crash

```bash
git worktree list              # See all worktrees
git worktree remove ../path    # Clean up
```

---

## FAQ

### Do agents make changes automatically?

No. Agents suggest changes. You decide whether to apply them. Exception: Supervisor workers write code in isolated worktrees, but merging requires validation.

### Can I use agents on different languages?

Yes. The plugin works on any language (JavaScript, TypeScript, Python, Go, Rust, Java, etc). Customize patterns in CLAUDE.md.

### Do I need all 8 user-facing agents?

No. Use what helps:
- **Just need to plan?** `/orchestrator`
- **Just need code review?** `/code-reviewer`
- **Need full automation?** `/launch-pad` then `/supervisor`
- **Need requirements?** `/product-owner`
- **Need security audit?** `/red-team-reviewer`
- **Need QA tests?** `/qa-executor`

### Do agents need internet?

No. Everything runs locally. `WebSearch`/`WebFetch` are used only by Red Team Reviewer and Product Owner (for `--brainstorm deep` market research).

### Can agents work on private projects?

Yes. Your code stays local. Agent memory is stored in `.claude/agent-memory/` on your machine.

---

## License

MIT License

---

## Support

```bash
/agent-help          # Quick reference
```

Open an issue in the ai-agent-manager repository for bugs or feature requests.
