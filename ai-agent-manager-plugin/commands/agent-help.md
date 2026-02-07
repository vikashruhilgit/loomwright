---
description: List all available agent commands and usage examples
---

# Command: /agent-help

## Usage

```
/agent-help
```

## What This Does

Shows all available agent commands and quick usage examples.

---

# Agent Help Reference

## Quick Start

The AI Agent Manager plugin provides **8 agent roles** for your development workflow:

**Autonomous Workflow (3 agent roles):**
```
/supervisor  →  Parallel orchestrator: Task → Branch → Workers → Review → PR → Loop
  ├─ Context-Keeper  →  Externalized state management (on-demand)
  └─ Worker  →  Isolated implementation in git worktrees (background)
```

**Requirements Pipeline (1 agent):**
```
0. Discover (Product Owner)  →  User stories with acceptance criteria
```

**Constructive Pipeline (3 agents):**
```
1. Plan (Orchestrator)  →  2. Review (Code Reviewer)  →  3. Commit (Repo Steward)
```

**Independent Auditor (1 agent):**
```
4. Attack (Red Team Reviewer)  →  Finds real-world failures before production
```

**Full Manual Workflow:**
```
/product-owner → User Stories → /orchestrator → Tasks → Code → /code-reviewer → /repo-steward
```

**Full Autonomous Workflow (Parallel):**
```
/supervisor  →  INIT → ACQUIRE → PLAN → EXECUTE (parallel workers) → FINALIZE → LOOP
```

**Task Management:** Beads issue tracker (optional) or `.supervisor/` directory

---

## Command Reference

### 🤖 /supervisor — Parallel Orchestrator (v3)

**Purpose:** Autonomously manage the complete development workflow with parallel execution from task pickup to PR creation

**Usage:**
```
/supervisor                         # Auto-select next ready task
/supervisor task: BD-XX             # Work on specific task
/supervisor --max-workers 3         # Up to 3 parallel workers
/supervisor --sequential            # Force sequential (no worktrees)
/supervisor --no-beads              # Skip Beads even if initialized
/supervisor --continue              # Resume from last checkpoint
/supervisor --dry-run               # Preview workflow without executing
```

**What it does:**
- Picks up tasks (from Beads or user description — Beads optional)
- Creates feature branch (MANDATORY before any code work)
- Orchestrates parallel workers via git worktrees:
  - Context-Keeper (state management, on-demand)
  - Product Owner (if requirements unclear, blocking)
  - Orchestrator (task decomposition, blocking)
  - Workers (implementation, background in worktrees)
  - Code Reviewer (quality gates, background)
- Merges worktree branches sequentially into feature branch
- Creates Pull Request via GitHub CLI
- Closes task and moves to next

**6-Phase Workflow:**
```
┌─────────────────────────────────────────────────────────────────┐
│  0. INIT (config)  →  1. ACQUIRE (task + branch)               │
│         ↓                                                       │
│  2. PLAN (decompose + parallelism)  →  3. EXECUTE (parallel)   │
│         ↓                                                       │
│  4. FINALIZE (merge + commit + PR)  →  5. LOOP (next or exit)  │
└─────────────────────────────────────────────────────────────────┘
```

**Parallel Execution:**
```
project/                    ← main worktree (feature branch)
project-BD-15a/             ← worktree for Worker A
project-BD-15c/             ← worktree for Worker C
```

**Review Gates:**
- **PASS:** Continue; launch newly unblocked subtasks
- **FAIL:** Spawn fix worker with retry context (max 3 attempts)
- **NEEDS_HUMAN:** Checkpoint, pause, exit with resume instructions

**State Management:**
- State externalized to `.supervisor/` directory (auto-created, gitignored)
- Context-Keeper manages all state mutations
- Supervisor holds only ~800 tokens
- Cross-session resume from `.supervisor/state.md`

**Example Session:**
```
$ /supervisor

## SUPERVISOR v3: Starting Parallel Workflow
**Config:** beads=true, workers=2, mode=parallel

### Phase 1: ACQUIRE
- Task: BD-15, Branch: feature/BD-15-user-auth ← CREATED

### Phase 2: PLAN
- Subtasks: 3, Parallel: 2 launchable, 1 blocked

### Phase 3: EXECUTE
- BD-15a: PASS ✓ (parallel)
- BD-15c: PASS ✓ (parallel)
- BD-15b: PASS ✓ (unblocked after BD-15a)

### Phase 4: FINALIZE
- PR: #42 — https://github.com/org/repo/pull/42

### Phase 5: LOOP
- Continuing with BD-18...
```

**Resume from Checkpoint:**
```bash
/supervisor --continue task: BD-15
```

**When to Use:**
- Autonomous task completion with parallel execution
- End-to-end workflow automation
- Processing multiple ready tasks
- Projects with or without Beads

**When NOT to Use:**
- Manual control → Use agents individually
- Single code reviews → Use `/code-reviewer`
- Planning only → Use `/orchestrator`

**Learn More:** `/supervisor --help`

---

### 0️⃣ /product-owner — Define Requirements

**Purpose:** Translate business problems into user stories with acceptance criteria

**Usage:**
```
/product-owner feature: "staff scheduling for venue events"
/product-owner problem: "we keep double-booking shifts"
/product-owner feature: "order history" --mvp-only
```

**What it does:**
- Reads domain context from CLAUDE.md
- Runs product discovery to understand the problem
- Writes user stories (As a... I want... So that...)
- Defines acceptance criteria (Given/When/Then)
- Prioritizes scope (MVP / Phase 2 / Nice-to-have)
- Creates Beads stories (type: story)
- Provides handoff to `/orchestrator`

**Example Output:**
```
## BD-15: Staff Shift Assignment (type: story)

**As a** Staff Supervisor at a sports venue,
**I want** to assign staff members to shifts,
**so that** I have adequate coverage.

### Acceptance Criteria
- [ ] Given an event, when I open assignment, then I see available staff
- [ ] Given a conflict, when I double-book, then I see a warning

### Priority: MVP
### Handoff: /orchestrator goal: "BD-15"
```

**When to Use:**
- Starting a new feature
- When requirements are vague
- Before running /orchestrator
- When you need user stories

**Learn More:** `/product-owner --help`

---

### 1️⃣ /orchestrator — Plan Your Work

**Purpose:** Break a goal into minimal, actionable tasks

**Usage:**
```
/orchestrator goal: "add dark mode to UI"
/orchestrator goal: "fix login bug" --project /path/to/project
```

**What it does:**
- Understands your goal
- Reads project context (CLAUDE.md, Beads issue tracker state)
- Creates 3-7 Beads tasks with review gates
- Each implementation task gets a review subtask
- Identifies dependencies (review blocks next task)
- Provides clear acceptance criteria and skill references

**Example Output:**
- BD-20: Dark Mode Toggle (EPIC)
- BD-21: Implement dark mode toggle (TASK)
- BD-22: Code Review - Dark mode (SUBTASK) ← blocks BD-23
- BD-23: Add tests (TASK)
- BD-24: Commit & Link (TASK)

**When to Use:**
- Start of new work
- When goal is unclear or large
- When you need task breakdown
- When planning feature work

**Learn More:** `/orchestrator --help`

---

### 2️⃣ /code-reviewer — Review Code Changes

**Purpose:** Review code against patterns, flag issues, detect new patterns

**Usage:**
```
/code-reviewer                              # Review git changes
/code-reviewer src/components/Dark.tsx      # Review specific file
/code-reviewer src/components/              # Review folder
/code-reviewer --project /path/to/project   # Auto-detect files
```

**What it does:**
- Reads project patterns (CLAUDE.md)
- Reviews your code for:
  - Type safety issues
  - Security problems
  - Performance issues
  - Pattern violations
  - Test coverage
- Flags issues with severity (HIGH, MEDIUM, LOW)
- Detects new patterns worth documenting
- Provides specific fixes

**Example Feedback:**
- ✅ Good: 87% test coverage (above 80% threshold)
- ⚠️ HIGH: Missing type annotation on theme parameter
- 📋 PATTERN: New dark mode pattern detected, ready for CLAUDE.md

**When to Use:**
- After writing code
- Before committing
- To learn project patterns
- To catch bugs early

**Learn More:** `/code-reviewer --help`

---

### 3️⃣ /repo-steward — Create Commits

**Purpose:** Stage changes and create conventional commit messages

**Usage:**
```
/repo-steward                    # Stage and commit (no push)
/repo-steward --project /path    # Explicit project path
/repo-steward --push             # Stage, commit, and push to remote
```

**What it does:**
- Groups changes into logical commits
- Writes conventional commit messages (feat, fix, test, etc)
- Links commits to Beads tasks
- Verifies repo cleanliness (no debug code, secrets, etc)
- Optionally pushes to remote

**Example Commits:**
```
feat(theme): add dark mode toggle to Settings
test(theme): add dark mode tests (89% coverage)
security(hooks): validate localStorage input
```

**When to Use:**
- When you're done coding (after code review)
- At the end of each task
- When you want to organize commits
- Before pushing to remote

**Learn More:** `/repo-steward --help`

---

### 4️⃣ /summarizer — Summarize Work (Deprecated)

> **Note:** The Summarizer agent has been deprecated in favor of Beads issue tracker. Use `bd close` to close completed tasks and `bd comment` to add notes.

**Previous Purpose:** Update memory files, create session logs

**Current Workflow:**
- Close completed tasks: `bd close BD-XX`
- Add comments: `bd comment BD-XX "Work summary"`
- Pattern proposals: Add to Beads task comments for CLAUDE.md review

---

### 5️⃣ /red-team-reviewer — Attack Your Work (Adversarial)

**Purpose:** Break, stress-test, and ruthlessly critique work under real-world conditions

**Usage:**
```
/red-team-reviewer                              # Attack entire project
/red-team-reviewer src/auth/                    # Attack specific directory
/red-team-reviewer --focus security             # Focus on security
/red-team-reviewer src/api/ --focus cost,scale  # Focus on cost and scale
```

**What it does:**
- Identifies attack surface (entry points, trust boundaries, assumptions)
- Reality-checks claims using Context7 MCP against current docs
- Explores 6 attack vectors:
  - Core flaws & blind spots
  - Real-world operational failures
  - Security, abuse & misuse
  - Scalability & reliability
  - Human & organizational failures
  - Integration & ecosystem
- Reports findings by severity (FATAL, CRITICAL, WARNING, WEAKNESS)
- Provides: Top 3 fatal issues + what convinces hostile expert + prioritized fixes
- Asks if you want findings saved to file

**Example Output:**
- FATAL: JWT algorithm confusion — attacker bypasses auth with alg:none
- CRITICAL: No rate limiting — one user can DoS the system
- Top 3 Fatal Issues + What Would Convince Hostile Expert
- Prioritized Fixes by real-world impact

**Severity Levels:**
| Level | Meaning |
|-------|---------|
| **FATAL** | Production will fail. Showstopper. |
| **CRITICAL** | Serious pain coming. Not death, but bad. |
| **WARNING** | Future pain. Tech debt with teeth. |
| **WEAKNESS** | Exploitable attack surface exists. |

**When to Use:**
- Before production launches
- After major features
- Security reviews
- Architecture decisions
- When you need brutal honesty (not encouragement)

**When NOT to Use:**
- Regular code changes → Use `/code-reviewer` instead
- Quick pattern checks → Use `/code-reviewer` instead
- Learning codebase conventions → Use `/code-reviewer` instead
- When you want constructive feedback → Use `/code-reviewer` instead

**Key Difference from Code Reviewer:**
| Code Reviewer | Red Team Reviewer |
|---------------|-------------------|
| Constructive | Adversarial |
| Follow patterns | Attack assumptions |
| Helpful tone | Blunt, unsentimental |
| Part of workflow | Independent audit |

**Learn More:** `/red-team-reviewer --help`

---

## Daily Workflow Example

### Morning: Plan Your Work
```bash
cd /path/to/my-app
/orchestrator goal: "Add dark mode UI to settings page"
```
→ Agent creates Beads tasks with review gates

### Start Work: Claim Task
```bash
bd claim BD-21  # Claim the implementation task
```
→ Start working on the task

### During Work: Code & Review
```bash
# 1. Implement feature...

# 2. Review your code
/code-reviewer src/components/Settings.tsx
```
→ Agent flags issues and outputs PASS/FAIL/NEEDS_HUMAN

### Before Committing: Create Conventional Commits
```bash
git add src/components/Settings.tsx src/hooks/useDarkMode.ts
# Use commit skill for proper formatting
```
→ Commits linked to Beads tasks

### Complete Task: Close in Beads
```bash
bd close BD-21
```
→ Task marked complete, next task unblocked

---

## Common Scenarios

### Scenario 1: Fix a Bug
```
/orchestrator goal: "Fix login button not working on mobile"
→ Creates Beads tasks: BD-30 (fix), BD-31 (review), BD-32 (commit)
→ bd claim BD-30, implement fix
→ /code-reviewer to verify → PASS on BD-31
→ Commit and bd close BD-32
```

### Scenario 2: Add a Feature
```
/orchestrator goal: "Add dark mode to application"
→ Creates EPIC with tasks and review gates
→ BD-40: Implement → BD-41: Review (blocks) → BD-42: Tests → BD-43: Commit
→ Work through chain, reviews unlock next tasks
→ bd close each task when done
```

### Scenario 3: Refactor Code
```
/orchestrator goal: "Refactor Settings component to use hooks"
→ Creates Beads tasks with review gates
→ /code-reviewer checks pattern consistency
→ Commit with Beads linking
```

### Scenario 4: Review Someone Else's Code
```
cd /path/to/pull-request-repo
/code-reviewer src/  # Review the changes
```
→ Agent flags issues and outputs PASS/FAIL/NEEDS_HUMAN

### Scenario 5: Pre-Launch Security Review
```
/red-team-reviewer --focus security
→ Red Team attacks auth, inputs, data exposure
→ Reports FATAL issues that must be fixed
→ Provides "what would convince hostile expert"
→ Prioritized fixes before launch
```

### Scenario 6: Stress-Test Before Scale
```
/red-team-reviewer src/api/ --focus scale,cost
→ Red Team attacks scalability, cost assumptions
→ Finds N+1 queries, unbounded operations
→ Reports what breaks at 10x/100x load
→ Prioritized fixes by real-world impact
```

---

## Key Concepts

### Project Context
Each agent automatically finds your project by looking for `CLAUDE.md`:
- Starts in current directory
- Searches parent directories
- Uses `/path/to/project` if you provide it

### Task Management
Task management supports two modes:

**With Beads (optional):**
- **`bd list`** — View open/in-progress/completed tasks
- **`bd claim BD-XX`** — Start working on a task
- **`bd close BD-XX`** — Mark task complete
- **`bd comment BD-XX "note"`** — Add notes to task

**Without Beads:**
- State tracked in `.supervisor/state.md` (auto-created)
- Task descriptions provided directly to Supervisor
- **CLAUDE.md** — Codebase knowledge, patterns (still user-maintained)

### Approval Workflow
- ✅ Code Reviews: Agent outputs PASS/FAIL/NEEDS_HUMAN
- ✅ CLAUDE.md Updates: Agent proposes, you approve
- ✅ Commits: Conventional format with Beads linking
- ✅ Pushes: Only with explicit request

---

## Tips & Tricks

### Tip 1: Use Agents Flexibly
You don't have to follow strict order. For example:
- Run `/code-reviewer` first to understand patterns before coding
- Run `/code-reviewer` multiple times during development
- Use `/red-team-reviewer` for adversarial audits before launch

### Tip 2: Combine with Git
```bash
# Review changes before code-reviewer
git diff src/

# See commits after repo-steward
git log --oneline -5

# Push after repo-steward
git push
```

### Tip 3: Multi-Project Workflows
```bash
# Work on project A
cd /path/to/project-a
/orchestrator goal: "Fix bug in A"

# Switch to project B
cd /path/to/project-b
/orchestrator goal: "Add feature to B"  # Auto-detects B's context
```

### Tip 4: Review Before Committing
```bash
# Code first
/code-reviewer src/

# Fix issues
/code-reviewer src/  # Re-review

# When satisfied, commit with Beads linking
git commit -m "feat(theme): add dark mode

Closes BD-21"
```

### Tip 5: Daily Routine
```bash
# Morning: Plan
/orchestrator goal: "Today's goal"

# Claim task
bd claim BD-XX

# During: Code and review
/code-reviewer (as needed)

# Complete: Close task
bd close BD-XX
```

---

## Files & Directories

### Plugin Files
```
ai-agent-manager-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata (v3.0.0)
├── commands/                # Slash commands
│   ├── supervisor.md        # Parallel orchestrator (v3)
│   ├── orchestrator.md
│   ├── code-reviewer.md
│   ├── repo-steward.md
│   ├── red-team-reviewer.md # Adversarial auditor
│   └── agent-help.md
├── agents/                  # Agent implementations (8 roles)
│   ├── supervisor.md        # Parallel orchestrator (v3)
│   ├── context-keeper.md    # State management agent
│   ├── worker.md            # Implementation worker
│   ├── product-owner.md     # Requirements definition
│   ├── orchestrator.md
│   ├── code-reviewer.md
│   ├── repo-steward.md
│   ├── red-team-reviewer.md # Has own adversarial preamble
│   └── prompts.md           # Shared preamble
└── skills/                  # Skill files (32 skills)
    ├── async-orchestration/ # Parallel dispatch patterns
    ├── state-management/    # State file schema
    ├── workflow-management/  # Supervisor workflow patterns
    ├── context-summarization/
    ├── commit/
    ├── quality-checklist/
    ├── nestjs-*/
    ├── nextjs-*/
    └── ...
```

### Project Files
```
your-project/
├── CLAUDE.md                # Codebase knowledge, patterns
├── .supervisor/             # Supervisor state (auto-created, gitignored)
│   ├── state.md             # Current session state
│   └── history/             # Completed session summaries
└── .beads/                  # Beads issue tracker (optional)
    ├── issues/              # Issue files
    └── ...
```

---

## Getting Help

### Need Help with a Specific Agent?
```
/supervisor --help         # Help for Supervisor (autonomous workflow)
/orchestrator --help       # Help for Orchestrator
/code-reviewer --help      # Help for Code Reviewer
/repo-steward --help       # Help for Repo Steward
/red-team-reviewer --help  # Help for Red Team Reviewer
```

### Questions About the Plugin?
Check the plugin README:
```
cat /path/to/ai-agent-manager/.claude-plugin/README.md
```

### Issues or Suggestions?
Contribute to the AI Agent Manager project:
```
https://github.com/your-org/ai-agent-manager
```

---

## Keyboard Shortcuts

These are Claude Code slash commands, so you can type them directly:
- Type `/super` + Tab → Auto-completes to `/supervisor`
- Type `/orchestr` + Tab → Auto-completes to `/orchestrator`
- Type `/code-r` + Tab → Auto-completes to `/code-reviewer`
- Type `/repo-s` + Tab → Auto-completes to `/repo-steward`
- Type `/red-t` + Tab → Auto-completes to `/red-team-reviewer`

---

## Summary

### Autonomous Workflow (End-to-End Automation — 3 Roles)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Supervisor** | Parallel orchestration | Autonomous task completion | Ready tasks (Beads optional) | Completed tasks with PRs |
| **Context-Keeper** | State management | On-demand (Supervisor calls) | State operations | State file updates |
| **Worker** | Implementation | Background (parallel) | Subtask + worktree path | WORKER_RESULT block |

### Requirements Pipeline (Define What to Build)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Product Owner** | Define requirements | New feature, vague requirements | Feature/problem | User stories with acceptance criteria |

### Constructive Pipeline (Build Correctly)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Orchestrator** | Plan work | Start of task | Goal or story | Beads tasks with review gates |
| **Code Reviewer** | Review code | During development | Files/diff | PASS/FAIL/NEEDS_HUMAN + issues |
| **Repo Steward** | Create commits | When done coding | Staged changes | Conventional commits + Beads links |

### Independent Auditor (Break Safely)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Red Team Reviewer** | Attack work | Pre-launch, security review | Target scope | Fatal issues + fixes |

---

**Ready to get started?**
- Autonomous workflow: `/supervisor` (picks up tasks, runs agents, creates PRs)
- Define requirements: `/product-owner feature: "your feature here"`
- Plan work: `/orchestrator goal: "your goal here"`
- Review code: `/code-reviewer src/`
- Attack work: `/red-team-reviewer` (adversarial audit)
