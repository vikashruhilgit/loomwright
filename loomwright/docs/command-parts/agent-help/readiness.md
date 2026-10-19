### 🚀 /launch-pad — Supervisor Readiness

**Purpose:** Prepare raw goals for autonomous Supervisor execution with codebase analysis, environment validation, file impact estimation, and interactive refinement

**Usage:**
```
/launch-pad goal: "add user authentication with JWT"
/launch-pad feature: "customers need order history"
/launch-pad problem: "login is broken on mobile"
/launch-pad goal: "..." --discovery
/launch-pad goal: "..." --skip-validation
```

**What it does:**
- Validates environment readiness (git, CLAUDE.md, worktrees, gh)
- Refines requirements using product discovery and MVP scoping
- **Checks feasibility (Phase 2.5 soft gate)** — tech stack, dependencies, architecture, scope, hard blockers. GO/CAUTION/NO-GO verdict. NO-GO stops pipeline (user can override); CAUTION feeds into Risk Assessment
- Analyzes codebase for file impact estimation (grep/glob/read)
- Decomposes per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" (default ONE subtask; split only for a named reason) with dependency analysis
- Computes parallelism (LAUNCHABLE vs BLOCKED based on file overlap)
- Validates brief via Plan Reviewer (mandatory gate — PASS enables save; NEEDS_HUMAN enables save only with explicit user override; FAIL never enables save)
- Saves Supervisor-Ready Brief to `.supervisor/jobs/pending/`
- Provides interactive refinement (save/refine/edit/discard)

**7-Phase Workflow:**
```
┌─────────────────────────────────────────────────────────────────┐
│  1. VALIDATE (env)  →  2. DISCOVER (requirements)              │
│         ↓                                                       │
│  2.5. FEASIBILITY (soft gate: GO/CAUTION/NO-GO)                 │
│         ↓                                                       │
│  3. ANALYZE (codebase)  →  4. DECOMPOSE (subtasks)             │
│         ↓                                                       │
│  5. PACKAGE (brief)  →  5.5. PLAN REVIEW (mandatory gate)      │
│         ↓                                                       │
│  6. REFINE & SAVE (save on PASS or user-overridden NEEDS_HUMAN)│
│         ↓                                                       │
│  7. EMIT LAUNCH_PAD_RESULT (non-interactive, always runs)       │
└─────────────────────────────────────────────────────────────────┘
```

**Example Session:**
```
$ /launch-pad goal: "add JWT authentication"

## Phase 1: VALIDATE
- CLAUDE.md: ✓ Found (fresh)
- Git: clean, branch: main

## Phase 2.5: FEASIBILITY
- Verdict: GO (5/5 checks passed)

## Phase 5: PACKAGE
# Supervisor Job: Add JWT Authentication
- Subtasks: 4 (2 LAUNCHABLE, 2 BLOCKED)
- Recommended workers: 2

## Phase 5.5: PLAN REVIEW
- Reviewer decision: PASS
- Issues found: 0
- Attempts: 1/3

## Phase 6: SAVE
Brief saved: .supervisor/jobs/pending/2026-02-08-jwt-auth.md

To execute: /supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md
```

**When to Use:**
- Complex tasks (>3 expected subtasks)
- Want to review plan before workers start
- Need accurate file impact analysis
- Working on unfamiliar codebase

**When NOT to Use:**
- Simple tasks (1-2 subtasks) → Use `/supervisor` directly
- Resuming work → Use `/supervisor --continue`
- Planning without execution → Use `/orchestrator`

**Learn More:** `/launch-pad --help`

---

### 🤖 /supervisor — Parallel Orchestrator (v4)

**Purpose:** Autonomously manage the complete development workflow with parallel execution from task pickup to PR creation

**Usage:**
```
/supervisor                         # Interactive task description
/supervisor task: "add user auth"   # Work on specific task
/supervisor --max-workers 3         # Up to 3 parallel workers
/supervisor --sequential            # Force sequential (no worktrees)
/supervisor --continue              # Resume from last checkpoint
/supervisor --dry-run               # Preview workflow without executing
/supervisor job: .supervisor/jobs/pending/{file}.md  # Execute from Launch Pad brief
```

**What it does:**
- Picks up tasks (user description or `.supervisor/state.md`)
- Creates feature branch (MANDATORY before any code work)
- Delegates Phase 3 execution to Execute Manager:
  - Execute Manager (Phase 3 poll loop, worker lifecycle, blocking)
  - Context-Keeper (state management, on-demand)
  - Product Owner (if requirements unclear, blocking)
  - Orchestrator (task decomposition, blocking)
  - Workers (implementation, background in worktrees)
  - Code Reviewer (quality gates, background)
- Validates worktrees and commits worker changes before merging
- Merges worktree branches sequentially into feature branch
- Creates Pull Request via GitHub CLI
- Moves to next task

**7-Phase Workflow:**
```
┌─────────────────────────────────────────────────────────────────┐
│  0. INIT (config)  →  1. ACQUIRE (task + branch)                │
│         ↓                                                       │
│  1.5 PRE-FLIGHT SYNC (remote-state reconciliation)              │
│         ↓                                                       │
│  2. PLAN (decompose + parallelism)  →  3. EXECUTE (Exec Mgr)    │
│         ↓                                                       │
│  4. FINALIZE (merge + commit + PR)                              │
│         ↓                                                       │
│  4.5 SELF_HEAL (integration review + bounded fix loop)          │
│         ↓                                                       │
│  5. LOOP (next or exit)                                         │
└─────────────────────────────────────────────────────────────────┘
```

**Parallel Execution:**
```
project/                    ← main worktree (feature branch)
project-BD-15a/             ← worktree for Worker A
project-BD-15c/             ← worktree for Worker C
```

**Gates:**
- Per-subtask: deterministic `outputs_verified` + tests/lint gate — **PASS:** continue, launch newly unblocked subtasks (no per-subtask LLM reviewer at any threshold)
- Phase 4.5 holistic Code Reviewer (sole LLM review, once after FINALIZE) — **PASS:** mark completed. **FAIL:** spawn fix worker with retry context (max 3 attempts). **NEEDS_HUMAN:** checkpoint, pause, exit with resume instructions

**State Management:**
- State externalized to `.supervisor/` directory (auto-created, gitignored)
- Context-Keeper manages `## Decisions Log` / `## Worker Results` / `## Error Log` / `## Phase Flags`; the `## Session` block (phase/status) is derived from the session's event log by `scripts/build-state.sh`
- Supervisor budget: 50 tool calls (including Phase 4.5); Execute Manager budget: 60 tool calls
- Cross-session resume from `.supervisor/state.md`

**Example Session:**
```
$ /supervisor

## SUPERVISOR v4: Starting Parallel Workflow
**Config:** workers=2, mode=parallel

### Phase 1: ACQUIRE
- Task: BD-15, Branch: feature/BD-15-user-auth ← CREATED

### Phase 2: PLAN
- Subtasks: 3, Parallel: 2 launchable, 1 blocked

### Phase 3: EXECUTE
- BD-15a: outputs_verified + tests/lint PASS ✓ (parallel)
- BD-15c: outputs_verified + tests/lint PASS ✓ (parallel)
- BD-15b: outputs_verified + tests/lint PASS ✓ (unblocked after BD-15a)

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
- Processing multiple tasks sequentially

**When NOT to Use:**
- Manual control → Use agents individually
- Single code reviews → Use `/code-reviewer`
- Planning only → Use `/orchestrator`

**Learn More:** `/supervisor --help`

---

