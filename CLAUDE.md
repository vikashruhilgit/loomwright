# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**AI Agent Manager** is a reusable system that provides intelligent agents for software development workflows. It integrates with Claude Code as a plugin with 12 agent roles (8 user-facing + 4 internal) that automate plan-first readiness, parallel workflow execution, requirements definition, planning, code review, commit management, adversarial security audits, and dual-agent QA automation.

The system enables agents to collaborate on any project type. The Supervisor and Launch Pad use `.supervisor/` directory exclusively for state management. Other agents (Orchestrator, Product Owner) can optionally use **Beads issue tracker** independently. `CLAUDE.md` provides codebase knowledge that persists between work sessions.

---

## Architecture & Key Concepts

### Plugin System

The project is structured as a **Claude Code plugin marketplace**:

1. **Plugin Package** (`ai-agent-manager-plugin/`)
   - Agent definitions: `agents/` (Markdown prompts)
   - Slash commands: `commands/` (entry points)
   - Skills: `skills/` (focused implementation guidance)

2. **Marketplace** (`.claude-plugin/`)
   - Plugin metadata and distribution
   - Installation via `/plugin install` command
   - Supports local and remote marketplaces

### Beads Task Management

**Beads replaces TODO.md and memory files:**

| Command | Purpose |
|---------|---------|
| `bd list` | View open/in-progress/completed tasks |
| `bd create` | Create new task |
| `bd claim BD-XX` | Start working on a task |
| `bd close BD-XX` | Mark task complete |
| `bd comment BD-XX "note"` | Add notes to task |
| `bd dep BD-XX BD-YY` | Set task dependencies |

**Task Structure:**
- **EPIC:** Large feature (contains multiple tasks)
- **TASK:** Implementation work (30-60 min)
- **SUBTASK:** Review gate (blocks next task)

**Review Gates:**
- Every implementation task has a review subtask
- Review subtask blocks next implementation task
- Review decisions: PASS (proceed), FAIL (fix and re-review), NEEDS_HUMAN (creates bug issues)

### The 12 Agent Roles

Each agent is a Markdown prompt file (`agents/[name].md`):

#### **Launch Pad** (`/launch-pad`) — Supervisor Readiness
- **Purpose:** Prepare raw goals for autonomous Supervisor execution
- **When to use:** Before `/supervisor` for complex tasks, when starting new work, when you want to review the plan
- **Command:** `/launch-pad goal: "..."`, `/launch-pad goal: "..." --discovery`
- **Workflow:** VALIDATE → DISCOVER → ANALYZE → DECOMPOSE → PACKAGE → PLAN REVIEW (mandatory gate) → REFINE & SAVE
- **Plan Review:** Spawns Plan Reviewer to validate brief quality (max 3 retries on FAIL)
- **Key features:** File impact estimation, parallelism pre-analysis, jobs folder, interactive refinement
- **Outputs:** Supervisor-Ready Brief saved to `.supervisor/jobs/pending/`

#### **Supervisor** (`/supervisor`) — v4 Parallel Orchestrator
- **Purpose:** Autonomously manage complete development workflow with parallel execution
- **When to use:** Full automation of task completion
- **Command:** `/supervisor`, `/supervisor task: "description"`, `/supervisor --max-workers 3`
- **Workflow:** INIT → ACQUIRE → PLAN → EXECUTE (via Execute Manager) → FINALIZE → LOOP
- **Key features:** Git worktrees for parallelism, externalized state, tool call budgets, mandatory branching
- **Outputs:** Completed tasks with PRs

#### **Execute Manager** (internal, spawned by Supervisor)
- **Purpose:** Own Phase 3 EXECUTE loop — worker/reviewer lifecycle, poll loop, Context-Keeper coordination
- **When to use:** Automatically spawned for multi-subtask workflows (not used for fast-path single subtask)
- **Budget:** 60 tool calls, isolated context from Supervisor
- **Outputs:** EXECUTE_RESULT or EXECUTE_CHECKPOINT block

#### **Context-Keeper** (internal, spawned by Supervisor/Execute Manager)
- **Purpose:** Manage Supervisor's externalized state file
- **When to use:** On-demand, called at each phase transition and for batch updates
- **Sole writer:** Only agent allowed to mutate the state file
- **Outputs:** < 50 token confirmations of state operations

#### **Worker** (internal, spawned by Execute Manager or Supervisor)
- **Purpose:** Implement a single subtask in an isolated git worktree
- **When to use:** Background execution during EXECUTE phase
- **Isolation:** Works only within assigned worktree path, no git operations
- **Outputs:** Structured WORKER_RESULT block + `.worker-summary.md` file

#### **Plan Reviewer** (internal, spawned by Launch Pad)
- **Purpose:** Validate Supervisor-Ready Briefs for gaps, missing pieces, pattern alignment, and correctness
- **When to use:** Automatically spawned during Launch Pad Phase 5.5 (not user-facing)
- **Checks:** 10 review criteria (file paths, patterns, acceptance criteria, dependencies, parallelism, skills, risks, completeness, configuration)
- **Outputs:** PLAN_REVIEW_RESULT with decision (PASS/FAIL/NEEDS_HUMAN) and issues array
- **Gate rule:** PASS enables save; NEEDS_HUMAN enables save only with explicit user override; FAIL never enables save

#### **Product Owner** (`/product-owner`)
- **Purpose:** Translate business problems into user stories with acceptance criteria. Supports `--brainstorm` mode for multi-mind ideation.
- **When to use:** New feature, vague requirements, exploring multiple directions (`--brainstorm`)
- **Command:** `/product-owner feature: "your feature"`, `/product-owner problem: "issue to solve"`, `/product-owner problem: "..." --brainstorm`
- **Workflow:** (Optional) 5-lens brainstorm → reads domain context → runs discovery → writes user stories
- **Outputs:** Options Analysis (when --brainstorm) + Beads stories with acceptance criteria (Given/When/Then)

#### **Orchestrator** (`/orchestrator`)
- **Purpose:** Break goals into Beads tasks with review gates
- **When to use:** Starting new work or need a plan
- **Command:** `/orchestrator goal: "what you want to accomplish"`
- **Workflow:** Reads CLAUDE.md + Beads state → creates task structure
- **Outputs:** EPIC → TASK → SUBTASK structure with skill references

#### **Code Reviewer** (`/code-reviewer`)
- **Purpose:** Provide precise feedback; output PASS/FAIL/NEEDS_HUMAN decision
- **When to use:** After writing code, need review
- **Command:** `/code-reviewer src/` (specify files/dirs to review)
- **Checks:** Type safety (via LSP), security, performance, pattern alignment, test coverage
- **Features:** Read-only mode (permissionMode: plan), deep analysis (effort: high), pre-existing issue tagging, optional REVIEW.md support
- **Outputs:** Issues (BLOCKING/HIGH/MEDIUM/LOW) with category (new/pre_existing/nit) + decision + CLAUDE.md proposals

#### **Red Team Reviewer** (`/red-team-reviewer`)
- **Purpose:** Adversarial audit — find what breaks in production
- **When to use:** Pre-launch, security reviews, architecture decisions
- **Command:** `/red-team-reviewer [target] [--focus security|scale|cost|ops]`
- **Workflow:** Attacks assumptions → verifies claims against docs → explores 6 attack vectors
- **Outputs:** Findings by severity (FATAL/CRITICAL/WARNING/WEAKNESS), prioritized fixes

#### **QA Strategist** (`/qa-strategist`)
- **Purpose:** Plan risk-based test strategy and audit QA Executor results
- **When to use:** Before QA execution for strategy, or during debate loop for audit
- **Command:** `/qa-strategist [target] [--audit .qa-summary.md] [--focus auth|api|ui|all]`
- **Dual mode:** Strategy Mode (standalone risk classification) + Audit Mode (review Executor results)
- **Outputs:** Risk classification, coverage targets, STRATEGIST_VERDICT block

#### **QA Executor** (`/qa-executor`)
- **Purpose:** Discover app, generate senior-grade Playwright tests, find missing functionality, orchestrate debate loop
- **When to use:** Automated QA — test generation, execution, gap detection, and coverage tracking
- **Command:** `/qa-executor [--url http://...] [--rounds 1|2|3] [--skip-strategy]`
- **Workflow:** Detect URL → infrastructure discovery → 4-phase discovery → pre-existing test triage → strategy → generate → gap analysis → dry-run → **Strategist gate audit (12 gates, independent)** → execute → coverage + bugs + audit → emit
- **Features:** Split architecture (487-line core + qa-test-patterns skill + qa-gates skill), independent Strategist gate audit (12 gates verified by separate agent), signal→pattern test generation, infrastructure discovery (Mailpit/MailHog), pre-existing test triage, auth linear chains, boundary + idempotency enforcement, blocker-first rule, email flow testing, failure classification (REAL_BUG vs DISCOVERY_GAP vs ENVIRONMENT_ISSUE), interaction-level coverage tracking
- **Outputs:** Discovery Map, discovery/infrastructure.json, Playwright tests, .qa-summary.md, QA_RESULT block, MISSING_FUNCTIONALITY_REPORT block

### Agent Design Principles

All agents follow a **shared contract** (see AGENT_GUIDELINES.md):

- **Mission:** Do the smallest correct thing that advances the objective
- **Input:** Context from CLAUDE.md + Beads state + recent git history
- **Output:** Structured Markdown with Context Read → Plan → Work → Results → Risks & Next Steps
- **Safety:** No destructive actions (db migrations, force-push) without explicit approval
- **Rules:** Never invent files/APIs/paths; ask if unsure; use Beads for task management
- **Frontmatter:** Every agent has YAML frontmatter for tool restrictions, model selection, maxTurns, color, disallowedTools, per-agent hooks, skills preloading, and persistent memory (see below)

---

## Quick Start Commands

### Installation

```bash
# Add the marketplace (from ai-agent-manager directory)
/plugin marketplace add ./

# Install the plugin
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Or manually copy to Claude Code plugins directory:
- **macOS/Linux:** `cp -r ai-agent-manager-plugin ~/.claude/plugins/ai-agent-manager-plugin`
- **Windows:** Copy `ai-agent-manager-plugin` to `%APPDATA%\Claude\plugins\`

### Setup a Project

```bash
# Initialize project
cd /path/to/your-project

# Option A: With Beads (full task management)
bd init

# Option B: Without Beads (Supervisor creates .supervisor/ automatically)
# Just create CLAUDE.md with your project patterns
```

This creates:
```
your-project/
├── CLAUDE.md              # Your codebase knowledge
├── .supervisor/           # Supervisor state (auto-created, gitignored)
│   ├── state.md           # Current session state
│   ├── history/           # Completed session summaries
│   └── jobs/              # Supervisor-Ready Briefs from Launch Pad
├── .beads/                # Beads issue tracker (optional)
│   └── issues/
└── src/                   # Your code
```

### Run Agents

```bash
# Prepare for autonomous execution (plan-first)
/launch-pad goal: "add user authentication"

# Execute from Launch Pad brief (in fresh session)
/supervisor job: .supervisor/jobs/pending/2026-02-08-user-auth.md

# Or run Supervisor directly
/supervisor task: "add user authentication"

# Plan work
/orchestrator goal: "add user authentication"

# Review code
/code-reviewer src/components/

# Commit changes
/commit

# Adversarial audit (pre-launch)
/red-team-reviewer --focus security

# QA automation (requires Playwright config + running app)
/qa-executor
/qa-executor --url http://localhost:3000 --skip-strategy
/qa-strategist src/
```

---

## High-Level Architecture

### Directory Structure

```
ai-agent-manager/
├── ai-agent-manager-plugin/          # The Claude Code plugin
│   ├── agents/                       # Agent markdown prompts (12 roles)
│   │   ├── launch-pad.md             # Launch Pad (Supervisor readiness)
│   │   ├── supervisor.md             # Supervisor v4 (parallel orchestrator)
│   │   ├── execute-manager.md        # Execute Manager (Phase 3 lifecycle)
│   │   ├── context-keeper.md         # Context-Keeper (state management)
│   │   ├── worker.md                 # Worker (implementation in worktrees)
│   │   ├── plan-reviewer.md          # Plan Reviewer (brief validation gate)
│   │   ├── product-owner.md          # Product Owner (requirements)
│   │   ├── orchestrator.md           # Orchestrator (task planning)
│   │   ├── code-reviewer.md          # Code Reviewer (quality gates)
│   │   ├── red-team-reviewer.md      # Red Team Reviewer (adversarial)
│   │   ├── qa-strategist.md          # QA Strategist (risk-based test strategy)
│   │   └── qa-executor.md            # QA Executor (discovery + test generation)
│   ├── commands/                     # Slash commands for Claude Code
│   │   ├── launch-pad.md             # /launch-pad command
│   │   ├── supervisor.md             # /supervisor command (v4)
│   │   ├── product-owner.md          # /product-owner command
│   │   ├── orchestrator.md           # /orchestrator command
│   │   ├── code-reviewer.md          # /code-reviewer command
│   │   ├── red-team-reviewer.md      # /red-team-reviewer command
│   │   ├── qa-strategist.md          # /qa-strategist command
│   │   ├── qa-executor.md            # /qa-executor command
│   │   └── agent-help.md             # /agent-help command
│   ├── hooks/                        # Plugin quality gate hooks
│   │   └── hooks.json                # Cross-cutting hooks (Code Reviewer, QA Executor, TaskCompleted)
│   ├── skills/                       # Skill files for guidance (43 skills)
│   │   ├── supervisor-readiness/     # Pre-flight checklist & Supervisor-Ready Brief template
│   │   ├── agent-teams/              # Agent Teams patterns (experimental)
│   │   ├── async-orchestration/      # Parallel dispatch & git worktree patterns
│   │   ├── state-management/         # State file schema & checkpoint protocols
│   │   ├── workflow-management/      # 6-phase workflow patterns
│   │   ├── context-summarization/    # Output compression for context
│   │   ├── commit/                   # Conventional commits
│   │   ├── quality-checklist/        # Review gate criteria
│   │   ├── pattern-detector/         # CLAUDE.md proposals
│   │   ├── nestjs-*/                 # NestJS patterns (6 skills)
│   │   ├── nextjs-*/                 # Next.js patterns (5 skills)
│   │   ├── gateway-*/                # API Gateway patterns (4 skills)
│   │   ├── nestjs-typeorm/           # TypeORM integration
│   │   ├── mysql/                    # MySQL patterns
│   │   ├── playwright-e2e/           # Playwright E2E testing patterns
│   │   ├── qa-strategy/             # QA risk framework & debate protocol
│   │   ├── qa-orchestration/        # Session management for large-app QA
│   │   ├── unit-testing/            # Jest/Vitest patterns
│   │   ├── error-handling/          # Error hierarchy & boundaries
│   │   ├── ci-cd/                   # GitHub Actions patterns
│   │   ├── docker/                  # Dockerfile & compose patterns
│   │   ├── monitoring-observability/ # Logging, tracing, metrics
│   │   ├── redis-caching/           # Cache patterns & invalidation
│   │   ├── postgresql/              # Schema, migrations, optimization
│   │   ├── SKILL_TEMPLATE.md        # Standard skill template
│   │   └── SKILLS_INDEX.md          # Skill catalog with agent mapping
│   ├── docs/                        # Architecture documentation
│   │   ├── QA_SYSTEM_BLUEPRINT.md   # QA system architecture (14 modules, 5 levels)
│   │   ├── RESULT_SCHEMAS.md        # Structured result contracts for all agents
│   │   ├── FAILURE_ESCALATION.md    # Agent failure paths and retry rules
│   │   ├── ARCHITECTURE_CONTRACTS.md # Capability matrix, budgets, rules
│   │   └── ARCHITECTURE.md          # Visual agent topology diagram
│   └── .claude-plugin/
│       └── plugin.json               # Plugin metadata (v10.3.0)
│
├── .claude-plugin/
│   ├── marketplace.json              # Marketplace definition
│   └── README.md                     # Plugin usage documentation
│
├── README.md                         # User-facing documentation
├── AGENT_GUIDELINES.md               # Development standards & agent contract
└── CLAUDE.md                         # This file
```

### How Agents Work Together

**Manual Workflow:**
```
User Goal
    ↓
/orchestrator → Beads tasks (EPIC → TASK → SUBTASK)
    ↓
bd claim BD-XX → Start task
    ↓
You code
    ↓
/code-reviewer → PASS/FAIL/NEEDS_HUMAN
    ↓
Fix issues (if FAIL)
    ↓
/commit → Conventional commits + Beads linking
    ↓
bd close BD-XX → Task complete, next unblocked
    ↓
Next agent reads updated CLAUDE.md (knowledge grows)
```

**Plan-First Autonomous Workflow:**
```
/launch-pad goal: "..."
    ↓
.supervisor/jobs/pending/{date}-{slug}.md  (Supervisor-Ready Brief)
    ↓
/supervisor job: .supervisor/jobs/pending/{file}.md  (clean context, ~500 tokens freed)
    ↓
EXECUTE → FINALIZE → PR
```

**Autonomous Workflow (Supervisor v4):**
```
/supervisor
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

### Task Management Workflow (Beads Optional)

```
Session Start:
  1. Agent reads CLAUDE.md (codebase knowledge)
  2. With Beads: bd list (current task state)
     Without Beads: read .supervisor/state.md
  3. Agent reads git history (recent work)

During Work:
  4. Agent creates/updates tasks (Beads or .supervisor/)
  5. Agent outputs review decisions (PASS/FAIL/NEEDS_HUMAN)
  6. Agent flags new patterns for CLAUDE.md

Task Complete:
  7. With Beads: bd close BD-XX (marks complete, unblocks next)
     Without Beads: update .supervisor/state.md
  8. You review pattern proposals
  9. You update CLAUDE.md (approve/reject proposals)
  10. Knowledge accumulates; agents learn from discoveries
```

---

## Development Workflow

### Daily Pattern

**Morning:**
1. Run `/orchestrator goal: "today's objective"` to create Beads tasks
2. Review task structure and acceptance criteria

**During Work:**
1. `bd claim BD-XX` to start task
2. Implement code
3. Run `/code-reviewer` to check for issues
4. Fix identified problems, re-review until PASS

**Afternoon:**
1. Run `/commit` to create conventional commits
2. `bd close BD-XX` to complete task

**Pre-Launch:**
1. Run `/red-team-reviewer` for adversarial audit
2. Address FATAL and CRITICAL findings

### Adding or Modifying Agents

Agents are Markdown files in `ai-agent-manager-plugin/agents/`:

1. **Create new agent:**
   - Write `.md` file in `agents/` directory
   - Follow structured output format (Context Read → Plan → Work → Results → Risks)

2. **Create slash command:**
   - Write `.md` file in `commands/` directory
   - Reference the agent prompt
   - Define command syntax and examples

3. **Create skill:**
   - Write `SKILL.md` in `skills/[skill-name]/` directory
   - Include quick rules, examples, and quality gates

4. **Test locally:**
   - Copy plugin to `~/.claude/plugins/` (or use `/plugin marketplace add ./`)
   - Run `/agent-help` to verify command is available
   - Test in a sample project

5. **Core principles:**
   - Do smallest correct thing that advances goal
   - Output structured Markdown
   - Never invent files/APIs/paths; ask if unsure
   - Use Beads for task management
   - Cite exact file:line numbers when referencing code

---

## Core Principles (From AGENT_GUIDELINES.md)

All agents follow these standards:

1. **Quality First** - Thorough, well-tested, correct solutions; proven approaches
2. **Surgical Changes** - Only modify what's necessary; fix one thing at a time
3. **Pattern Consistency** - Use existing patterns; learn codebase before implementing
4. **Type Safety** - Strictest checking; no implicit `any`; equivalent rigor per language
5. **Security** - No secrets/PII in code/logs; validate inputs; clear decisions
6. **Performance** - Profile before/after; document tradeoffs; optimize bottlenecks

### Quality Checklist

Before an agent completes work:
- Tests pass; no linting/type errors
- Code follows patterns; changes minimal and focused
- Coverage ≥ 80%; no regressions
- No secrets, debug code, console.logs
- Docs/comments updated
- Input validation in place

---

## Project Structure

### Key Files

| File | Purpose |
|------|---------|
| `README.md` | User-facing guide (installation, quick start, workflow) |
| `AGENT_GUIDELINES.md` | Development standards, agent contract, quality checklist |
| `.claude-plugin/README.md` | Detailed plugin documentation |
| `ai-agent-manager-plugin/skills/*/SKILL.md` | Skill files for implementation guidance |

### Plugin Metadata

- **Plugin Name:** `ai-agent-manager-plugin`
- **Version:** 10.3.0
- **Description:** AI agents v10.3 — QA topology auto-detection: QA Executor detects app_topology (ui_present, api_style, client_platform), auth method, and WebSocket presence. Supports REST, GraphQL (5-step fallback), API-only backends, mobile-backend apps, and SSO/OAuth (--auth-state flag). New Gate 10 for GraphQL coverage with budget-aware tiers. 13-gate Strategist audit. Plus v10.2 Launch Pad mandatory Plan Review gate. 12 agent roles, 47 reusable skills, 10 quality gate hooks, persistent agent memory, bundled MySQL MCP server
- **Agents:** 12 roles (Launch Pad, Supervisor v4, Execute Manager, Context-Keeper, Worker, Plan Reviewer, Product Owner, Orchestrator, Code Reviewer, Red Team Reviewer, QA Strategist, QA Executor)
- **Skills:** 47 reusable skills (versioned with SKILLS_INDEX.md)
- **Hooks:** 10 quality gate hooks — centralized in hooks.json: SubagentStop (worker, execute-manager, code-reviewer, supervisor, qa-executor, plan-reviewer), Stop (code-reviewer), TaskCompleted, WorktreeCreate, StopFailure
- **Docs:** RESULT_SCHEMAS.md, FAILURE_ESCALATION.md, ARCHITECTURE_CONTRACTS.md, ARCHITECTURE.md, QA_SYSTEM_BLUEPRINT.md
- **Bundled MCP:** MySQL read-only MCP server (`vikashruhil-mysql-mcp`) — query impact analysis, schema inspection, multi-DB profiles
- **Author:** vikash ruhil
- **License:** MIT

### Marketplace Configuration

- Defined in `.claude-plugin/marketplace.json`
- Supports local marketplace (`/plugin marketplace add ./`)
- Supports remote GitHub marketplaces for team distribution

---

## Important Notes

### This is a Plugin System

- Agents are distributed as a Claude Code plugin
- Users install via `/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace`
- Agents run within Claude Code (not standalone)

### Language-Agnostic

- Agents work with any programming language
- Follow language-specific standards per AGENT_GUIDELINES.md (TypeScript, Python, Go, Rust, Java, etc.)

### Human-in-Loop Design

- Agents suggest changes; humans approve
- Agents flag pattern proposals in Beads task comments
- Only humans update CLAUDE.md (after review)
- Agents never make destructive changes without explicit instruction
- Merge conflicts always escalate to human

### Task Management

- **Supervisor and Launch Pad:** Use `.supervisor/` exclusively for state management (no Beads dependency)
- **Orchestrator and Product Owner:** Can optionally use Beads for task/story creation independently
- Projects need only CLAUDE.md to get started (`.supervisor/` is auto-created, `.beads/` is optional)
- Same agents work across different projects

### Structured Contracts (v9.0.0)

- **Result Schemas:** Agent result blocks follow strict schemas — CODE_REVIEW_RESULT at `schema_version: 2` (with issue categories), all others at `schema_version: 1` — see `docs/RESULT_SCHEMAS.md`
- **Failure Escalation:** Defined retry limits and escalation paths for all agents — see `docs/FAILURE_ESCALATION.md`
- **Architecture Contracts:** Capability matrix, context budgets, timeout rules, worktree naming — see `docs/ARCHITECTURE_CONTRACTS.md`
- **Job Lifecycle:** Briefs tracked through `pending/` → `in-progress/` → `done/`/`failed/` in `.supervisor/jobs/`
- **Session Logging:** Structured JSONL logs in `.supervisor/logs/` for post-mortem analysis
- **Merge Safety Gate:** Pre-merge checklist in FINALIZE prevents corrupted partial merges

### Parallel Execution Model

- Supervisor v4 delegates Phase 3 to Execute Manager for multi-subtask workflows
- Execute Manager owns the poll loop, worker/reviewer lifecycle, and Context-Keeper coordination
- Each worker operates in its own git worktree (no file conflicts)
- Workers write `.worker-summary.md` files for lightweight result extraction
- Context-Keeper externalizes state; Supervisor uses tool call budgets (30 calls) instead of percentage thresholds
- Execute Manager has its own tool call budget (60 calls) in isolated context
- Subtask branches merge sequentially into feature branch with pre-merge validation
- Fast-path: single subtask skips worktrees and Execute Manager entirely

### Plugin Hooks (Quality Gates)

All validation hooks are centralized in `hooks.json` since v10.0.0. Claude Code silently ignores `hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter — only hooks.json hooks fire for plugin-distributed agents. Per-agent frontmatter hooks are kept for `~/.claude/agents/` compatibility.

| Hook | Trigger | Location | Validation |
|------|---------|----------|------------|
| **SubagentStop** (worker) | Worker completes | hooks.json + frontmatter | WORKER_RESULT with schema_version, task_id, status, files_modified |
| **SubagentStop** (execute-manager) | Execute Manager completes | hooks.json + frontmatter | EXECUTE_RESULT/EXECUTE_CHECKPOINT with required fields |
| **SubagentStop** (code-reviewer) | Code Reviewer completes | hooks.json | CODE_REVIEW_RESULT v2 with decision, issue categories (new/pre_existing/nit) |
| **SubagentStop** (supervisor) | Supervisor completes | hooks.json | Session outcome, subtask statuses, PR URL if created |
| **SubagentStop** (qa-executor) | QA Executor completes | hooks.json | QA_RESULT with tests_generated, tests_passed, summary |
| **SubagentStop** (plan-reviewer) | Plan Reviewer completes | hooks.json | PLAN_REVIEW_RESULT with schema_version, decision, issues, summary |
| **Stop** (code-reviewer) | Code Reviewer finishing | hooks.json + frontmatter | CODE_REVIEW_RESULT block present with required fields |
| **TaskCompleted** | Any task marked complete | hooks.json | Task genuinely done, not abandoned or skipped |
| **WorktreeCreate** | Worktree created | hooks.json | Logs to `.supervisor/logs/worktrees.log` (type: command) |
| **StopFailure** | Agent API error | hooks.json | Logs to `.supervisor/logs/failures.log` (type: command) |

Hooks validate against schemas defined in `docs/RESULT_SCHEMAS.md`. Prompt-based validation (fast haiku model, 30s timeout). WorktreeCreate and StopFailure use `type: "command"` for zero-latency logging.

### Persistent Memory

Agents with `memory: project` in their frontmatter build knowledge across sessions:

| Agent | What It Remembers | Storage |
|-------|-------------------|---------|
| Launch Pad | Commonly impacted files per goal type, project patterns | `.claude/agent-memory/ai-agent-manager-plugin:launch-pad/` |
| Code Reviewer | Review patterns, recurring issues, codebase conventions | `.claude/agent-memory/ai-agent-manager-plugin:code-reviewer/` |
| Red Team Reviewer | Past vulnerabilities, attack patterns, audit history | `.claude/agent-memory/ai-agent-manager-plugin:red-team-reviewer/` |
| Product Owner | Domain context, terminology, stakeholder preferences | `.claude/agent-memory/ai-agent-manager-plugin:product-owner/` |
| QA Strategist | Per-project risk patterns, which routes tend to break | `.claude/agent-memory/ai-agent-manager-plugin:qa-strategist/` |
| QA Executor | Flaky patterns, common failures, successful test templates | `.claude/agent-memory/ai-agent-manager-plugin:qa-executor/` |

Memory accumulates automatically — agents get smarter about project-specific patterns over time.

### Skills Preloading

Agents with `skills` in their frontmatter receive skill content pre-injected at spawn time:

| Agent | Pre-loaded Skills | Why |
|-------|-------------------|-----|
| Launch Pad | supervisor-readiness, context-setup, claude-md-validation, product-discovery, mvp-scoping, quality-checklist, context7-lookup | All discovery/validation/readiness knowledge needed |
| Supervisor | workflow-management, async-orchestration, state-management, context-summarization, supervisor-readiness | Referenced in every run |
| Orchestrator | quality-checklist | Defines review gate criteria for subtask creation |
| Code Reviewer | quality-checklist, context7-lookup, unit-testing, error-handling, monitoring-observability | Always needs quality criteria, library doc lookup, and coverage/error/observability patterns |
| Red Team Reviewer | context7-lookup | Mandatory for reality-checking library usage |
| QA Strategist | qa-strategy, quality-checklist | Risk framework and quality gates always needed |
| QA Executor | qa-strategy, playwright-e2e, quality-checklist | Discovery, test generation patterns, and gates |
| Product Owner | brainstorming, product-discovery, mvp-scoping | Multi-mind ideation, problem understanding, prioritization |

This eliminates file-read latency during execution — skills are in context from the start.

### Agent Teams (Experimental Alternative)

Claude Code Agent Teams is an experimental feature providing native multi-agent coordination:
- Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable
- Best for research, competing hypotheses, cross-layer changes
- Not for sequential tasks or same-file edits (use Supervisor with git worktrees)
- See `skills/agent-teams/SKILL.md` for patterns and decision matrix
- Does not replace Supervisor v4 — complementary for exploration tasks

---

## Common Pitfalls

### Agents Don't Understand Project Structure?
- Update the project's CLAUDE.md with more detailed patterns
- Include concrete examples and file references
- Agents re-read CLAUDE.md at the start of each session

### Beads Tasks Not Appearing?
- Run `bd list` to check current state
- Ensure `bd init` was run in project


### Supervisor Workflow Interrupted?
- State is saved to `.supervisor/state.md` automatically
- Resume with: `/supervisor --continue task: BD-XX`
- Check `.supervisor/history/` for completed sessions

### Orphaned Worktrees After Crash?
- Run `git worktree list` to see all worktrees
- Remove with: `git worktree remove ../project-BD-XXa`
- Clean up branches: `git branch -d feature/BD-XXa`

### New Pattern But Unsure If Important?
- Agent flags it in Beads task comment as a proposal
- Review code at specified file:line numbers
- Decide whether to add to CLAUDE.md
- Approval gates prevent noise

---

## Known Limitations

### Agent Behavior
- **File verification:** Agents verify file existence before referencing, but LLM hallucination is possible
- **Observability:** All agents output structured summary (status, files read/modified, errors)

### Scale Considerations
- **Token overhead:** ~5,000-10,000 tokens per invocation for prompts
- **Context7 dependency:** External library lookups require MCP; fallback to CLAUDE.md if unavailable

### QA System (Level 1 — v9.0.0)
- **Requires Playwright:** `playwright.config.ts` must exist and app must be running
- **Crawl limits:** Max 30 pages, depth 3, same-origin only
- **Split architecture:** 487-line core agent + qa-test-patterns skill + qa-gates skill (was 1,911 lines)
- **13 sequential phases** (1-13, no sub-numbering)
- **Independent gate audit:** 12 quality gates verified by QA Strategist (separate agent, separate context) — not self-grading
- **Budget: 80/90** — matches protocol reality (was 60)
- **Infrastructure-aware:** Discovers email capture (Mailpit/MailHog) and generates email flow tests when available
- **Simple linear chains (L1-legal):** Auth lifecycle tests (signup→login→access→logout→deny). NOT L2 journey graphs
- **Strategist spawned twice:** Phase 11 (gate audit) + Phase 13 (results audit)
- **Security boundary tests (non-destructive):** L1 includes IDOR, role escalation, session invalidation, XSS/SQLi probes for HIGH risk endpoints. Full adversarial security testing is Level 3.
- **No performance tests:** Performance testing is Level 3.
- **Coverage is inventory-level:** Tracks routes/APIs discovered vs tested, not behavioral coverage

---

## Future Enhancements

Potential improvements:
- Additional specialized agents (e.g., Documentation Agent, Performance Analyzer)
- Deeper GitHub/GitLab integration
- Agent composition (multi-agent workflows)
- Metrics and analytics

---

## References

- **Main docs:** `README.md` (user guide, examples, troubleshooting)
- **Plugin docs:** `.claude-plugin/README.md` (installation, commands, project setup)
- **Development standards:** `AGENT_GUIDELINES.md` (quality checklist, agent contract, standards per language)
- **Agent prompts:** `ai-agent-manager-plugin/agents/*.md` (detailed agent definitions with YAML frontmatter)
- **Skills:** `ai-agent-manager-plugin/skills/*/SKILL.md` (implementation guidance)
- **Hooks:** `ai-agent-manager-plugin/hooks/hooks.json` (plugin quality gate hooks)
- **QA Blueprint:** `ai-agent-manager-plugin/docs/QA_SYSTEM_BLUEPRINT.md` (14 modules, 5 maturity levels)
