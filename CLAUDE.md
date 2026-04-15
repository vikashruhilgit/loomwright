# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**AI Agent Manager** is a reusable system that provides intelligent agents for software development workflows. It integrates with Claude Code as a plugin with 12 agent roles (8 user-facing + 4 internal) that automate plan-first readiness, parallel workflow execution, requirements definition, planning, code review, commit management, adversarial security audits, and dual-agent QA automation.

The system enables agents to collaborate on any project type. The Supervisor and Launch Pad use `.supervisor/` directory exclusively for state management. Other agents (Orchestrator, Product Owner) can optionally use **Beads issue tracker** independently. `CLAUDE.md` provides codebase knowledge that persists between work sessions.

---

## Architecture & Key Concepts

### Plugin System

The repo IS the plugin — a single-plugin Claude Code repo with the manifest at `.claude-plugin/plugin.json` and plugin content directly at the repo root:

- Agent definitions: `agents/` (Markdown prompts)
- Slash commands: `commands/` (entry points)
- Skills: `skills/` (focused implementation guidance)
- Hooks: `hooks/hooks.json`
- Docs: `docs/`
- Manifest: `.claude-plugin/plugin.json`

Installation: `/plugin install ./` from a local checkout, or via the official Anthropic marketplace once submitted.

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
- **Workflow:** VALIDATE → DISCOVER → **FEASIBILITY (soft gate)** → ANALYZE → DECOMPOSE → PACKAGE → PLAN REVIEW (mandatory gate) → REFINE & SAVE
- **Feasibility (Phase 2.5):** 5 grounded checks (tech stack, dependencies, architecture, scope, hard blockers) → GO/CAUTION/NO-GO. CAUTION feeds Risk Assessment; NO-GO stops pipeline (user can override, revise max 1, or abort)
- **Plan Review:** Spawns Plan Reviewer to validate brief quality (max 3 retries on FAIL)
- **Key features:** Feasibility assessment, file impact estimation, parallelism pre-analysis, jobs folder, interactive refinement
- **Outputs:** Supervisor-Ready Brief saved to `.supervisor/jobs/pending/`

#### **Supervisor** (`/supervisor`) — v4 Parallel Orchestrator + self-heal (Phase 4.5)
- **Purpose:** Autonomously manage complete development workflow with parallel execution and post-merge self-heal
- **When to use:** Full automation of task completion
- **Command:** `/supervisor`, `/supervisor task: "description"`, `/supervisor --max-workers 3`, `/supervisor --skip-self-heal`, `/supervisor --heal-iterations N`
- **Workflow:** INIT → ACQUIRE → PLAN → EXECUTE (via Execute Manager) → FINALIZE → SELF_HEAL → LOOP
- **Key features:** Git worktrees for parallelism, externalized state, tool call budgets, mandatory branching, Phase 4.5 post-merge integration review + bounded fix loop, SUPERVISOR_RESULT machine-readable output
- **Outputs:** Completed tasks with PRs + SUPERVISOR_RESULT block

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
- **Purpose:** Translate business problems into user stories with acceptance criteria. Supports `--brainstorm` mode for multi-mind ideation. Includes grounded feasibility: **Assumption Check** (standard flow) and **Reality Check** (brainstorm flow).
- **When to use:** New feature, vague requirements, exploring multiple directions (`--brainstorm`)
- **Command:** `/product-owner feature: "your feature"`, `/product-owner problem: "issue to solve"`, `/product-owner problem: "..." --brainstorm`
- **Workflow:** reads domain context → **Assumption Check (grounded, with user gate before `bd create` if flags)** → (optional) 5-lens brainstorm with **Reality Check (Phase 3.5, caps Feasibility for NEEDS_FOUNDATION/BLOCKED ideas)** → runs discovery → writes user stories
- **Outputs:** Options Analysis (when --brainstorm, includes Reality Check) + Beads stories with acceptance criteria (Given/When/Then)

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
- **Features:** Read-only mode (permissionMode: plan), deep analysis (effort: high), pre-existing issue tagging, optional REVIEW.md support, **Beads integration is optional (auto-detected from `.beads/` presence + `bd --version`)** — when not active, CODE_REVIEW_RESULT block is the sole output channel. **Auto-expands scope to run a repo consistency audit when diff touches agents/, commands/, skills/, docs/, or plugin metadata** (mirrored prompts, version strings, counts, workflow alignment, hooks parity).
- **Outputs:** CODE_REVIEW_RESULT v3 (always emitted) with `review_mode` (diff_review | consistency_audit), `audit_focus[]`, `trigger_paths_detected[]`, `scope_expanded[]`, `files_checked[]`, `consistency_checks` + `consistency_summary` (audit mode only), issues (BLOCKING/HIGH/MEDIUM/LOW) with category (new/pre_existing/nit/drift) and `drift_kind` (for drift issues — severity caps enforced by hook), decision, CLAUDE.md proposals; Beads comment + bug issues (only when Beads is active)

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
- **Workflow:** Detect URL → infrastructure discovery → 4-phase discovery → pre-existing test triage → strategy → generate → gap analysis → dry-run → **Strategist gate audit (13 gates, independent)** → execute → coverage + bugs + audit → emit
- **Features:** Split architecture (487-line core + qa-test-patterns skill + qa-gates skill), independent Strategist gate audit (13 gates verified by separate agent), signal→pattern test generation, infrastructure discovery (Mailpit/MailHog), pre-existing test triage, auth linear chains, boundary + idempotency enforcement, blocker-first rule, email flow testing, failure classification (REAL_BUG vs DISCOVERY_GAP vs ENVIRONMENT_ISSUE), interaction-level coverage tracking
- **Outputs:** Discovery Map, discovery/infrastructure.json, Playwright tests, .qa-summary.md, QA_RESULT block, MISSING_FUNCTIONALITY_REPORT block

### Agent Design Principles

All agents follow a **shared contract** (see AGENT_GUIDELINES.md):

- **Mission:** Do the smallest correct thing that advances the objective
- **Input:** Context from CLAUDE.md + Beads state + recent git history
- **Output:** Structured Markdown with Context Read → Plan → Work → Results → Risks & Next Steps
- **Safety:** No destructive actions (db migrations, force-push) without explicit approval
- **Rules:** Never invent files/APIs/paths; ask if unsure; use Beads for task management
- **Frontmatter:** Every agent has YAML frontmatter for tool restrictions, model selection, maxTurns, color, disallowedTools, per-agent hooks, skills preloading, and persistent memory (see below)

**Self-heal pattern (v11.0.0):** After Supervisor's FINALIZE phase creates a PR, Phase 4.5 SELF_HEAL runs a holistic Code Reviewer on the integrated feature-branch diff and auto-fixes bounded BLOCKING/HIGH `new` issues (up to `--heal-iterations`, default 3). This eliminates the manual review-and-fix cycle per feature. The phase always runs (`--skip-self-heal` only short-circuits the review loop, not the phase transition); task-completion side-effects (job-file move, state marked completed) are relocated from FINALIZE into SELF_HEAL's completion tail so the record captures heal outcome. Supervisor emits a `SUPERVISOR_RESULT` block validated by the SubagentStop hook.

---

## Quick Start Commands

### Installation

```bash
# From the ai-agent-manager checkout
/plugin install ./
```

Once merged to the official Anthropic marketplace, installation is a single command without needing a local checkout.

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
ai-agent-manager/                     # The Claude Code plugin (repo IS the plugin)
├── .claude-plugin/
│   ├── plugin.json                   # Plugin manifest (v11.1.2)
│   └── README.md                     # Plugin-facing usage guide
├── agents/                           # Agent markdown prompts (12 roles)
│   ├── launch-pad.md                 # Launch Pad (Supervisor readiness)
│   ├── supervisor.md                 # Supervisor v4 (parallel orchestrator)
│   ├── execute-manager.md            # Execute Manager (Phase 3 lifecycle)
│   ├── context-keeper.md             # Context-Keeper (state management)
│   ├── worker.md                     # Worker (implementation in worktrees)
│   ├── plan-reviewer.md              # Plan Reviewer (brief validation gate)
│   ├── product-owner.md              # Product Owner (requirements)
│   ├── orchestrator.md               # Orchestrator (task planning)
│   ├── code-reviewer.md              # Code Reviewer (quality gates)
│   ├── red-team-reviewer.md          # Red Team Reviewer (adversarial)
│   ├── qa-strategist.md              # QA Strategist (risk-based test strategy)
│   └── qa-executor.md                # QA Executor (discovery + test generation)
├── commands/                         # Slash commands for Claude Code
│   ├── launch-pad.md, supervisor.md, product-owner.md, orchestrator.md
│   ├── code-reviewer.md, red-team-reviewer.md, qa-strategist.md, qa-executor.md
│   └── agent-help.md
├── hooks/
│   └── hooks.json                    # Cross-cutting quality-gate hooks
├── skills/                           # 47 skills (see SKILLS_INDEX.md)
├── docs/                             # Architecture + schemas
│   ├── QA_SYSTEM_BLUEPRINT.md, RESULT_SCHEMAS.md, FAILURE_ESCALATION.md
│   ├── ARCHITECTURE_CONTRACTS.md, ARCHITECTURE.md
├── scripts/                          # validate-version.sh, check-command-sync.sh
├── .github/                          # workflows + PR template
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
FINALIZE: Pre-merge validation → Commit in worktrees → Sequential merge → PR (exit — no task-completion side-effects yet)
    ↓
SELF_HEAL: Integration review (Code Reviewer on full diff) → bounded fix loop (max --heal-iterations, default 3) → completion tail (job → done/, state completed, SUPERVISOR_RESULT emitted). `--skip-self-heal` short-circuits the loop but phase still runs.
    ↓
LOOP: Next task or exit (consumes heal outcome for reporting)
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

Agents are Markdown files in `agents/`:

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
   - Install from the repo root: `/plugin install ./`
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
| `skills/*/SKILL.md` | Skill files for implementation guidance |

### Plugin Metadata

- **Plugin Name:** `ai-agent-manager-plugin`
- **Version:** 11.1.2
- **Description:** AI agents v11.1.2 — Close the "inline = stop orchestrating" loophole. The v11.1.1 main-thread guard correctly killed the subagent-spawn trap but accidentally licensed inline `/supervisor` runs to skip Phase 3 child agents and the Phase 4.5 `code-reviewer` integration review. v11.1.2 adds tailored execution-contract paragraphs to `/supervisor` and `/launch-pad` command files making "inline ≠ no child agents" explicit, an inline-execution critical rule in `agents/supervisor.md`, and a runtime invariant in the Phase 4.5 completion tail: if `--skip-self-heal` was not passed AND `code-reviewer` Task was not invoked, Supervisor emits `status: failed` and leaves the job in `in-progress/` instead of silently passing. Schema/hook work for `skip_self_heal_flag`, a `/supervisor --recover-self-heal` command, and symmetric `/launch-pad` plan-reviewer gate hardening are deferred to follow-up PRs. Builds on v11.1.1 `-runner` rename (preserved), v11.1 Code Reviewer system integrity review (`diff_review` / `consistency_audit` modes, repo audit baseline, CODE_REVIEW_RESULT schema v3 with `audit_focus` tags and `drift` category plus `drift_kind` severity caps enforced by the plugin hook, `scripts/check-command-sync.sh` drift guard), v11.0 self-healing Supervisor (Phase 4.5 integration review + bounded fix loop), v10.3 feasibility gates (Launch Pad Phase 2.5, Product Owner Assumption/Reality Check), QA topology auto-detection (REST/GraphQL/API-only/mobile/SSO; 13-gate audit), and v10.2 Launch Pad mandatory Plan Review. 12 agent roles, 47 reusable skills, 10 quality gate hooks, persistent agent memory, bundled MySQL MCP server.
- **Agents:** 12 roles (Launch Pad, Supervisor v4, Execute Manager, Context-Keeper, Worker, Plan Reviewer, Product Owner, Orchestrator, Code Reviewer, Red Team Reviewer, QA Strategist, QA Executor)
- **Skills:** 47 reusable skills (versioned with SKILLS_INDEX.md)
- **Hooks:** 10 quality gate hooks — centralized in hooks.json: SubagentStop (worker, execute-manager, code-reviewer, supervisor, qa-executor, plan-reviewer), Stop (code-reviewer), TaskCompleted, WorktreeCreate, StopFailure
- **Docs:** RESULT_SCHEMAS.md, FAILURE_ESCALATION.md, ARCHITECTURE_CONTRACTS.md, ARCHITECTURE.md, QA_SYSTEM_BLUEPRINT.md
- **Bundled MCP:** MySQL read-only MCP server (`vikashruhil-mysql-mcp`) — query impact analysis, schema inspection, multi-DB profiles
- **Author:** vikash ruhil
- **License:** MIT

### Installation

- Single-plugin repo with manifest at `.claude-plugin/plugin.json`
- Local install: `/plugin install ./` from a repo checkout
- Official: install via the Anthropic marketplace once submitted

---

## Important Notes

### This is a Plugin System

- Agents are distributed as a Claude Code plugin
- Users install via `/plugin install ./` from a local checkout, or via the official Anthropic marketplace
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

- **Result Schemas:** Agent result blocks follow strict schemas — CODE_REVIEW_RESULT at `schema_version: 3` (adds `review_mode`, `audit_focus`, `trigger_paths_detected`, `scope_expanded`, `files_checked`, `consistency_checks`, `consistency_summary`, and the `drift` issue category with `drift_kind` + severity caps; v2 accepted for legacy artifacts), all others at `schema_version: 1` — see `docs/RESULT_SCHEMAS.md`
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
| Launch Pad | Commonly impacted files per goal type, project patterns | `.claude/agent-memory/ai-agent-manager-plugin:launch-pad-runner/` |
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

### `/supervisor` or `/launch-pad` Aborted with "Task/Agent tool unavailable"?
- You likely hit the pre-11.1.1 name-collision trap where the slash command silently auto-delegated to a same-named registered subagent, which then couldn't spawn its own child agents ([docs](https://code.claude.com/docs/en/sub-agents): *"Subagents cannot spawn other subagents"*).
- Fix in 11.1.1: the registered agents are now `ai-agent-manager-plugin:supervisor-runner` and `ai-agent-manager-plugin:launch-pad-runner`. The slash commands are inline main-thread workflows; the `-runner` suffix is what lets `claude --agent ai-agent-manager-plugin:supervisor-runner` own a session without re-introducing auto-delegation.
- If you want an agent-owned session, use `claude --agent …-runner`. Otherwise use the slash command and stay on the main thread.

### `/supervisor` Completed But Skipped Phase 4.5 (or Phase 3 Child Agents)?
- **What this is:** Inline main-thread execution was misread as permission to stop orchestrating. "Don't delegate to `supervisor-runner`" is correct, but it does NOT mean "do the whole workflow yourself." You must still spawn first-level child agents via the Task tool — `orchestrator` in Phase 2, `execute-manager` or fast-path worker/reviewer in Phase 3, and `code-reviewer` + fix loop in Phase 4.5.
- **Fix in 11.1.2:** The Phase 4.5 completion-tail guard (`agents/supervisor.md`) refuses to emit a successful `SUPERVISOR_RESULT` when `skip_self_heal_requested=false` AND `phase45_review_invoked=false`. The run self-reports `status: failed` and the job stays in `in-progress/` for operator review. You can no longer silently skip the integration review.
- **Recovery for runs completed before 11.1.2 (operator workaround — unsupported, manual):**
  1. Generate the review scope explicitly. `/code-reviewer` does not have a first-class branch-vs-branch diff mode today — compute the changed files via `git diff --name-only origin/main...HEAD` and pass that list to `/code-reviewer`, OR pipe `git diff origin/main...HEAD` into a manual review session.
  2. If the review finds new BLOCKING/HIGH issues, fix them (manually or via a worker task loop) and push to the feature branch.
  3. Only then update `.supervisor/` state and the job file by hand. This manual state surgery is NOT supported and will become a proper `/supervisor --recover-self-heal` command in a follow-up PR — avoid it where possible.
- **Intentional skip:** If you genuinely want to bypass the integration review (emergency merge), re-run with `--skip-self-heal` explicitly. The guard accepts that flag as a recorded, deliberate choice.

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
- **Independent gate audit:** 13 quality gates verified by QA Strategist (separate agent, separate context) — not self-grading
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
- **Agent prompts:** `agents/*.md` (detailed agent definitions with YAML frontmatter)
- **Skills:** `skills/*/SKILL.md` (implementation guidance)
- **Hooks:** `hooks/hooks.json` (plugin quality gate hooks)
- **QA Blueprint:** `docs/QA_SYSTEM_BLUEPRINT.md` (14 modules, 5 maturity levels)
