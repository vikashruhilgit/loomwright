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

The Loomwright plugin provides **14 agent roles** (9 user-facing + 5 internal) for your development workflow:

**Which command?** (condensed — full table in `README.md` / `.claude-plugin/README.md`)

| I want to… | Run | Does NOT do |
|---|---|---|
| New task/goal | `/launch-pad` then `/supervisor` (or `/autonomous`) | Never merges |
| Multi-iteration on ONE goal, stacked PRs | `/autonomous` | Never merges (stack merges bottom-up, by a human) |
| Queue of independent goals (folder/backlog) | `/automate` | Never merges by default; only opt-in `--auto-merge` (default OFF) can |
| Existing PR to review-and-heal | `/review-pr <pr-url>` | Never merges (pushes fixes, PR stays open) |
| Review-only of my diff, no fixes | `/code-reviewer` | Read-only — no fixes, no commits, never merges |

**Readiness Pipeline (2 agent roles):**
```
/launch-pad  →  Env validation + codebase analysis + brief → Plan Review (gate) → .supervisor/jobs/pending/
  └─ Plan Reviewer  →  Validates brief quality, patterns, file paths (mandatory gate)
```

**Autonomous Workflow (5 agent roles):**
```
/supervisor  →  Parallel orchestrator: Task → Branch → Execute Manager → PR → Loop
  ├─ Execute Manager  →  Phase 3 poll loop, worker/reviewer lifecycle (blocking)
  ├─ Context-Keeper   →  Externalized state management (on-demand)
  ├─ Worker           →  Isolated implementation in git worktrees (background)
  └─ Rubric Grader    →  Phase 4.5 read-only Haiku scorer for the optional Outcomes Rubric (advisory only)
```

**Requirements Pipeline (1 agent):**
```
0. Discover (Product Owner)  →  User stories with acceptance criteria
```

**Constructive Pipeline (2 agents + /commit skill):**
```
1. Plan (Orchestrator)  →  2. Review (Code Reviewer)  →  3. Commit (/commit skill)
```

**Independent Auditor (1 agent):**
```
4. Attack (Red Team Reviewer)  →  Finds real-world failures before production
```

**QA Pipeline (2 agents):**
```
5. Strategy (QA Strategist)  →  Risk classification + coverage targets
6. Execute (QA Executor)     →  Discovery → Tests → Debate → QA_RESULT
```

**Full Manual Workflow:**
```
/product-owner → User Stories → /orchestrator → Tasks → Code → /code-reviewer → /commit
```

**Full Autonomous Workflow (Parallel):**
```
/supervisor  →  INIT → ACQUIRE → PRE-FLIGHT SYNC → PLAN → EXECUTE (Execute Manager) → FINALIZE → SELF_HEAL → LOOP
```

**Plan-First Autonomous Workflow:**
```
/launch-pad → .supervisor/jobs/pending/{brief} → /supervisor job: {brief} → clean execution
```

**Continuous Autonomous Loop (v14):**
```
/autonomous "<requirement>"                                 → multi-iteration loop (default, cap 3), stacked PRs, re-plan on rubric N<M / Option-C
/autonomous "<requirement>" --single-iteration              → run once (v13-compat command chaining)
```

**Task Management:** `.supervisor/` directory for Supervisor/Launch Pad; Beads available for Orchestrator/Product Owner

---

## Command Reference

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
- Decomposes into 3-7 subtasks with dependency analysis
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
  - Execute Manager (Phase 3 poll loop, worker/reviewer lifecycle, blocking)
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

**Review Gates:**
- **PASS:** Continue; launch newly unblocked subtasks
- **FAIL:** Spawn fix worker with retry context (max 3 attempts)
- **NEEDS_HUMAN:** Checkpoint, pause, exit with resume instructions

**State Management:**
- State externalized to `.supervisor/` directory (auto-created, gitignored)
- Context-Keeper manages all state mutations
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
- Processing multiple tasks sequentially

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
/product-owner problem: "low retention" --brainstorm
/product-owner feature: "new pricing model" --brainstorm deep
```

**What it does:**
- Reads domain context from CLAUDE.md
- **Runs Assumption Check (standard flow)** — grounded feasibility against codebase (domain entities, architecture alignment, prerequisites). If flags exist, asks user confirmation before `bd create` (Proceed/Refine/Abort)
- Runs multi-mind brainstorm (5 expert lenses) when `--brainstorm` flag is used — generates options, debates, scores, and recommends a winner before writing stories
- **Runs Reality Check (brainstorm flow)** — for top 2-3 scored ideas, grounded codebase validation with VIABLE/NEEDS_FOUNDATION/BLOCKED verdicts. Caps Feasibility scores (NEEDS_FOUNDATION ≤ 5, BLOCKED ≤ 2), re-ranks before recommendation
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
- When exploring multiple directions (`--brainstorm`) before committing to one

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

### 3️⃣ /commit — Create Commits

**Purpose:** Stage changes and create conventional commit messages with Beads linking

**Usage:**
```
/commit                          # Stage and commit with Beads linking
```

**What it does:**
- Groups changes into logical commits
- Writes conventional commit messages (feat, fix, test, etc)
- Links commits to Beads tasks (`Closes BD-XX`)
- Verifies repo cleanliness (no debug code, secrets, etc)

**Example Commits:**
```
feat(theme): add dark mode toggle to Settings

Closes BD-46

test(theme): add dark mode tests (89% coverage)
security(hooks): validate localStorage input
```

**When to Use:**
- When you're done coding (after code review)
- At the end of each task
- When you want to organize commits

---

### 4️⃣ /red-team-reviewer — Attack Your Work (Adversarial)

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

### 5️⃣ /qa-strategist — Risk-Based QA Strategy

**Purpose:** Plan risk-based test strategy and audit QA Executor results

**Usage:**
```
/qa-strategist src/                              # Analyze source for risk
/qa-strategist --audit .qa-summary.md            # Audit Executor results
/qa-strategist src/auth/ --focus auth             # Focus on auth flows
```

**What it does:**
- **Strategy Mode:** Discovers routes/endpoints, classifies risk (HIGH/MEDIUM/LOW), sets coverage targets, produces test priority matrix
- **Audit Mode:** Reviews QA Executor summary, evaluates coverage against targets, emits STRATEGIST_VERDICT (approved/rejected)

**Risk Classification:**
- **HIGH:** Auth flows, data mutation, payment/billing (target: 85%)
- **MEDIUM:** CRUD operations, standard API endpoints (target: 70%)
- **LOW:** Static pages, informational content (target: 50%)

**Key Constraints:**
- Read-only — never writes files, never runs tests
- Verdict is final on conflict (defaults to deeper testing)
- Level-aware — only demands current maturity level capabilities

**When to Use:**
- Before QA execution to define test priorities
- After QA execution to audit coverage and quality
- When you need risk-based testing decisions

**Learn More:** `/qa-strategist --help`

---

### 6️⃣ /qa-executor — Automated QA Testing

**Purpose:** Discover app structure, generate and run Playwright tests, orchestrate debate loop

**Usage:**
```
/qa-executor                                      # Auto-detect URL + topology, full run
/qa-executor --url http://localhost:3000            # Explicit URL
/qa-executor --auth-state ./auth.json              # Pre-authenticated (OAuth/SSO apps)
/qa-executor --skip-strategy                       # Quick run, skip Strategist
/qa-executor --coverage 90                         # Override coverage target (risk-based default)
/qa-executor --strict-discovery                    # Require human approval of discovery
# Note: --rounds only meaningful at L2+. L1 runs 1 round (hard cap).
```

**What it does:**
1. Auto-detects app topology (UI, API style, platform) + probes test infrastructure
2. Runs 4-phase discovery engine (static analysis → runtime crawl → selective vision → merge & gate)
3. Gets risk strategy from QA Strategist (or uses defaults)
4. Generates Playwright tests appropriate to detected topology (UI/API/GraphQL/WebSocket)
5. Executes tests, tracks coverage, reports bugs
6. Runs Strategist audit (debate loop)
7. Emits QA_RESULT

**Discovery Engine:**
```
Static Analysis → Routes from source code (Glob/Grep)
Runtime Crawl   → Playwright DOM/network/a11y extraction (max 30 pages, depth 3)
Selective Vision → Screenshots for complex pages only
Merge & Gate    → Confidence scoring (HIGH/MEDIUM/LOW)
```

**Level 1 Boundaries:**
- Happy paths + basic errors + negative tests (no state modeling / fuzz → L2)
- No performance tests (→ L3)
- No adversarial/penetration security tests (→ L3)
- L1 INCLUDES non-destructive security boundary probes: IDOR, role escalation,
  session invalidation, XSS/SQLi input-rejection checks, cookie security flags
- Single debate round
- Inventory-level coverage tracking
- Auto-detects: REST, GraphQL, mixed APIs, web UI, mobile backends
- Generates tests appropriate to detected topology (skips UI tests for API-only apps)

**Requirements:**
- Application must be running at base URL
- Playwright browsers installed
- `playwright.config.ts`: required for UI apps; auto-generated for API-only apps if missing
- For OAuth/SSO apps: `--auth-state ./auth.json` recommended

**When to Use:**
- Automated QA after feature implementation
- Regression testing before release
- Quick smoke tests (with --skip-strategy)

**Learn More:** `/qa-executor --help`

---

### 💤 /dreaming — Reflect on Past Sessions (Read-Only)

**Purpose:** Run target agents in reflection mode over recent session logs to **propose** memory and `CLAUDE.md` updates. Strictly read-only on code AND agent memory until per-item user approval.

**Usage:**
```
/dreaming                                      # All agents, last 5 sessions
/dreaming --agent code-reviewer                # Reflect with Code Reviewer only
/dreaming --agent red-team --sessions 10       # Red Team, last 10 sessions
/dreaming --agent qa-executor --sessions 3     # QA Executor, last 3 sessions
/dreaming --agent all --sessions 20            # All agents, deeper history
/dreaming --full-model                         # Reflection spawns inherit the session model (skip sonnet default)
```

**Parameters:**
- `--agent all|code-reviewer|red-team|qa-executor` (default `all`)
- `--sessions N` (default `5`)
- `--full-model` (default off — reflection spawns default to `model: "sonnet"` per `docs/ARCHITECTURE_CONTRACTS.md` §Cost Profiles → "Async analysis surfaces"; flag restores `inherit`)

**What it does:**
- Reads the N most recent `.supervisor/logs/{session_id}.jsonl` files (read-only)
- Spawns target agent(s) in reflection mode with read-only access to their own `.claude/agent-memory/{agent-id}/`
- Aggregates per-agent output into a single reflection report with four mandatory sections:
  - Recurring Patterns
  - Distilled Insights
  - Proposed Memory Updates
  - Proposed CLAUDE.md Updates
- Presents each proposed update for **per-item user approval** (Accept / Reject / Edit)

**Read-only contract:**
- `/dreaming` does not modify code, agent memory, or `CLAUDE.md`
- Every proposed update is labeled **PENDING USER APPROVAL**
- Persistence happens **only after** the user explicitly approves each item: on per-item Accept, `/dreaming` writes project-memory facts + LESSONS via the repo-root sole writers and promotes orientation proposals via `add-orientation.sh --confirm` (literal argv); CLAUDE.md and legacy agent-memory proposals stay paste-to-apply

**When to Use:**
- After a streak of completed `/supervisor` sessions, to surface recurring issues
- Before updating `CLAUDE.md` by hand, to discover what the logs say should change
- As a recurring retrospective cadence (weekly / per milestone)

**When NOT to Use:**
- During active execution → `/dreaming` reflects on *past* sessions
- When you need code changes → `/dreaming` is read-only; use `/supervisor` or `/code-reviewer`
- For agents without persistent memory → only Code Reviewer, Red Team Reviewer, and QA Executor are valid targets

**Learn More:** see `loomwright/commands/dreaming.md` for full parameter table, reflection-mode task prompt template, the read-only contract, and example output

---

### 🔭 /capability-check — Scan for New Platform Capabilities (Read-Only)

**Purpose:** On-demand, bounded (≤5 fetches) scan that diffs the live Claude Code changelog/docs plus dependency info against the tracked `loomwright/docs/CAPABILITY_BASELINE.json` and reports **CANDIDATE** adoptions — new platform capabilities the plugin could adopt. Never self-applies; suppresses output when nothing new is found. `--update-baseline` is an explicit maintainer action that refreshes the tracked baseline. With **`--strategy`** it instead runs a grounded product-evolution pass that proposes scored, deduped, differentiated **product directions** (distinct from adoption candidates, reusing the brainstorming skill) — same propose-only / bounded / human-gated discipline.

**Learn More:** see `loomwright/commands/capability-check.md` for the scan protocol, fetch budget, the `--strategy` product-direction mode, and the maintainer `--update-baseline` flow

---

### 📊 /insights — Local Insights Dashboard (Read-Only, Obsidian-friendly)

**Purpose:** Generate a local markdown insights dashboard (`.supervisor/insights/dashboard.md` + per-run notes with Dataview-compatible frontmatter) from `.supervisor/logs/*.jsonl`, covering work / quality / session-performance (completion rate, self-heal outcomes, rubric scores, subtask counts, files touched). Deterministic `jq` aggregation via `scripts/build-insights.sh`. **Cost (tokens/$) is intentionally NOT captured** — it lives in Claude Code's own transcripts; the dashboard points to `npx ccusage`.

**Learn More:** see `loomwright/commands/insights.md` for the dashboard layout, the Dataview frontmatter schema, and the `ccusage` cost note

---

### 🔮 /obsidian — Local Obsidian Vault Projection (Read-Only, Linked)

**Purpose:** Project this repo's accumulated knowledge — session logs, System Twin contracts (with `[[dependency]]` wikilinks so the graph view = blast radius), and Lessons / Project Memory — into a fully-**linked** external Obsidian vault you configure. Read-only one-way projection (no source-of-truth file touched, no agent reads it back, no data leaves your machine) via `scripts/build-vault.sh`. **Opt-in:** destination via `LOOMWRIGHT_OBSIDIAN_VAULT` env or `.supervisor/obsidian-config.json`; **no-op (exits 0, prints how to opt in) when unset.** Content-hash idempotent and sparse-tolerant.

**Learn More:** see `loomwright/commands/obsidian.md` for the configuration (env var / config file / slug), the vault layout, and the idempotency / sparse-tolerance guarantees

---

### 🤝 /handoff — Catch-Up / Hand-Off Digest (Read-Only)

**Purpose:** Assemble ONE recency-focused, per-work-item catch-up digest so a second person can pick up where you left off in ~2 minutes. Interleaves work items across Supervisor jobs, autonomous runs, and automate runs into a single newest-first list, surfacing the five facets where derivable — decision · why · tried/rejected · current state · provenance — plus an honest freshness/basis line (mtime vs recorded commit-SHA, never conflated). Reuses the sanctioned `read-project-memory.sh` / `read-lessons.sh` readers, silently skips absent surfaces, and writes a derived digest to `.supervisor/handoff/digest.md` (gitignored) via `scripts/build-handoff.sh`. Read-only on your work; always exits 0. Distinct from `/insights` (run trends/aggregates) and `/obsidian` (external vault projection).

**Usage:** `/handoff`

**Learn More:** see `loomwright/commands/handoff.md` for the facet-derivation rules, the freshness-basis contract, and the surfaces it reads

---

### 📜 /rules — House Rules Substrate (Committed `.agent/rules/`)

**Purpose:** Maintain the plugin's first **committed-convention** surface — `.agent/rules/*.json`, a version-controlled source of truth for project conventions so an implementer can read them on the DO side, not only get caught on review. Four subcommands: `list` (show all valid rules via the fail-safe `read-rules.sh` reader), `suggest` (scan the repo → PROPOSE rules for human review, never auto-writes), `add` (append-only, confirm-only write to a path-contained `.agent/rules/<category-slug>.json`), and `check` (HUMAN-invoked: display + run `must` rules' checks only after explicit confirmation). **Trust boundary:** the reader emits each `check` as DATA and never executes it; `/rules check` requires explicit confirmation (mechanized in `rules-check.sh`, with a default-off `--no-cmd` unattended valve that wins over `--confirm`). **Advisory enforcement is wired (never-gating)** at the worker / Phase 4.5 self-heal / SessionStart-nudge seams (the reader is consumed as review/DO-side context, never a gate); `/rules add` is mechanized into the sole-writer `add-rule.sh`. Subordinate to CLAUDE.md (on conflict, CLAUDE.md wins).

**Usage:** `/rules list` · `/rules suggest` · `/rules add` · `/rules check`

**Learn More:** see `loomwright/commands/rules.md` and the `rules` skill (`skills/rules/SKILL.md`, the protocol authority) for the schema, the fail-safe read contract, the path-contained atomic-append write discipline, and the `check`-is-arbitrary-shell trust boundary

---

### 🩺 /pr-postmortem — PR Review-Churn Root-Cause Analysis (Read-Only)

**Purpose:** On-demand, read-only diagnostic that analyzes a merged or open PR's review-and-fix churn to find the **root cause** of repeated review rounds. Gathers PR metadata, review threads, and diff stats via `scripts/pr-postmortem-gather.sh`, then buckets each review round into one of six root-cause classes (plan gap, missing context, convention mismatch, execution bug, quality gap, scope too large), flags rounds self-heal should have caught (`self_heal_miss`), and maps where in the agent flow (`launch_pad` / `worker` / `self_heal` / `unknowable`) each should have been caught. Never writes code, never gates, never blocks the PR — it appends one advisory `POSTMORTEM_RESULT` record to `.supervisor/postmortem/results.jsonl`, the seed corpus for a future synthetic eval harness.

**Learn More:** see `loomwright/commands/pr-postmortem.md` and the `pr-postmortem` skill for the gather protocol, the miss-class taxonomy, and the `POSTMORTEM_RESULT` schema

---

### 🔁 /autonomous — Continuous Autonomous Loop (v14, stacked PRs)

**Purpose:** Chain `/launch-pad → /supervisor` to drive a requirement to completion. Default mode is **multi-iteration** (cap 10, default 3) with **stacked PRs** — iteration N+1 branches from `iterations[N].branch` — and re-plans on two specific `SUPERVISOR_RESULT` signals. Pass `--single-iteration` (or `--max-iterations 1`) for v13's run-once behavior; `--no-stacked-branches` for the v13 branch-from-`main` cadence.

> **Foreground-assisted automation, not fire-and-forget.** The loop pauses at every existing interactive boundary (Launch Pad Phase 6 save, NO-GO override, Plan Review FAIL × 3, Supervisor adjudication 4-option, and the loop's own rubric gate). You must be at the terminal to answer them — unless you pass `--non-interactive-fallback` (CI / non-TTY: gates fail closed). `--notify` posts a gate-event webhook (resolved from `LOOMWRIGHT_WEBHOOK_URL` or `.supervisor/config.json`; legacy `.supervisor/notify-config.json` is still read as a fallback, new path wins) so an out-of-band notifier can ping you.

**Usage:**
```bash
/autonomous "<requirement string>"                                       # multi-iteration (default, cap 3), stacked PRs
/autonomous --requirement <path/to/file.md>                              # file-supplied requirement
/autonomous "<...>" --max-iterations N                                   # cap iterations at N (max 10)
/autonomous "<...>" --single-iteration                                   # v13 run-once (no loop)
/autonomous "<...>" --no-stacked-branches                                # each iteration branches from main (v13 cadence)
/autonomous "<...>" --non-interactive-fallback --notify                  # CI: gates fail closed + webhook pings
```

**Parameters:**
- `"<requirement>"` or `--requirement <path>` (required, choose one)
- `--max-iterations N` — cap for multi-iteration mode (default 3, max 10)
- `--single-iteration` — disable the loop; run Launch Pad → Supervisor once (v13-compat)
- `--no-stacked-branches` — each iteration branches from `main` instead of the prior iteration's branch
- `--non-interactive-fallback` — permit multi-iter in CI / non-TTY; gates fail closed instead of prompting
- `--notify` — POST gate-event webhooks (fails loud at INIT if no URL resolvable). `--allow-multi-iteration` is **deprecated** (multi-iter is the default now; accepted as a silent no-op)

**Multi-iteration re-plan signals (read from `SUPERVISOR_RESULT` plus iteration-scoped job artifacts):**

| Signal | Action |
|---|---|
| `completed` + `rubric_score N/M` with N<M | Pause for the rubric-gate AskUserQuestion. In the **default stacked-branch mode** the options are continue-to-next-iteration / stop-here / force-continue with **no merge required** (iter N+1 branches from iter N). With `--no-stacked-branches` the gate is merge-and-continue / stop / force and verifies the PR is merged via `gh pr view` (or `git merge-base --is-ancestor` fallback) before re-planning. |
| `failed` + Option-C detected on this iteration's brief | Anchored by `.supervisor/jobs/failed/{basename(current_brief_path)}` existence; `inter_subtask_gap` confirmed by grepping the failed brief contents, `SUPERVISOR_RESULT.error`, or `SUPERVISOR_RESULT.summary` (state.md intentionally not consulted). Re-plan immediately — no merge prompt, no PR was created. |
| anything else | Terminate the loop (done / paused_max_iterations / failed / aborted). |

**When to Use:**
- Multi-step requirements where Launch Pad → Supervisor is the natural chain
- Requirements with `## Outcomes Rubric` you want to iteratively satisfy (the default loop)
- After Phase 4.5 self-heal is not enough to address residual rubric gaps

**When NOT to Use:**
- Single small change with no rubric → `--single-iteration`, or just run `/supervisor` directly
- Crash recovery → no `--continue` yet; clean up manually and restart (the `SessionStart` hook injects recovery context on resume/clear/compact)
- Parallel `/autonomous` runs on the same repo → brief-save detection's primary signal is `LAUNCH_PAD_RESULT.saved_brief_path` (validated by `scripts/validate-launch-pad-result.py`); the `ls`-diff is a pre-v14.2.0 fallback only. Still run one autonomous / launch-pad invocation at a time per repo.

**Learn More:** see `loomwright/commands/autonomous.md` for the full flow diagram, signal-extraction algorithm, refined-requirement templates, and troubleshooting. The protocol skill is `loomwright/skills/autonomous-loop/SKILL.md`.

---

### 🤖 /automate — Generic Automation Engine (v14.41.0)

**Purpose:** Walk arbitrary work from any starting point. Converts any source — a prompt (via `/product-owner`), a requirements folder, or a backlog/plan doc — into a full Queue inside a **single run file** `.supervisor/automate/<run_id>.md` (the contract, dashboard, and resume state), then drives each Queue item through the per-item loop: `/autonomous --single-iteration` → **one owned inline `/review-pr --until-mergeable` drain** → trusted-merge-or-park → sync `main` → check the item off. Smart resume globs `.supervisor/automate/*.md` for incomplete runs and reconciles against ground truth before trusting a checkbox.

**Usage:**
```bash
/automate "<what you want to automate>"          # prompt source (via /product-owner) → Queue
/automate                                         # bare → resume an incomplete run, else ASK
/automate --folder <dir>                          # folder source — each *.md becomes a Queue item
/automate --backlog <_BACKLOG.md>                 # backlog-doc source — dependency-ordered Queue
/automate --limit N                               # cap PROCESSED items this run (default 5; full Queue still stored)
/automate --resume [<run_id>]                     # reconcile + continue a prior incomplete run
/automate ... --auto-merge                        # opt-in, default-OFF, 5-condition fail-closed merge gate
```

**Parameters:**
- `"<what>"` / `--folder <dir>` / `--backlog <doc>` — the source (choose one); bare `/automate` resumes, else asks
- `--limit N` — cap PROCESSED items this run (default 5); the FULL resolved Queue is still materialized in the run file
- `--resume [<run_id>]` — reconcile + continue a prior incomplete run (most-recent incomplete if id omitted)
- `--auto-merge` — opt-in (default OFF) trusted auto-merge behind a 5-condition fail-closed gate; the **only** place in the plugin that executes `gh pr merge --squash`
- `--notify` / `--non-interactive-fallback` — passthrough to the inner `/autonomous`

**When to Use:**
- A whole folder of requirements, a backlog doc, or a prompt that fans out into many items
- You want one item driven to a mergeable PR at a time (single-open-PR invariant), with smart crash resume

**When NOT to Use:**
- A single requirement → `/autonomous` directly
- Two concurrent `/automate` runs in one repo (they collide on the repo-global `.auto_review` toggle)

**Learn More:** see `loomwright/commands/automate.md`; the protocol authority is `loomwright/skills/automate-loop/SKILL.md`, and the run-file layout is documented as `AUTOMATE_RUN` in `loomwright/docs/RESULT_SCHEMAS.md`.

---

### 🧩 /setup — Optional-Capability Dashboard & Guided Configuration

**Purpose:** Single entry point for checking and configuring every optional plugin capability across 7 modules — **observability** (local Langfuse v3 + bundled OTel collector; `init | status | remove`), **telemetry** (delegates to `/telemetry`), **notifications**, **webhook**, **Beads**, **MySQL MCP**, and **twin** (cold-start bootstrap: Twin-readiness status + guided graph / bridge / starter CLAUDE.md build). No-arg invocation prints a status dashboard (one real check per module) then offers configuration via multi-select. Every module follows the same contract: check → report → offer → apply → verify — idempotent, never blind-overwrite (settings.json changes are jq-deep-merged with a timestamped backup, aborting on parse failure).

**Usage:**
```
/setup                      # status dashboard + multi-select configuration
/setup observability        # observability module directly: init | status | remove
/setup twin                 # Twin cold-start bootstrap: graph + bridge + starter CLAUDE.md
/setup telemetry            # delegates to /telemetry
```

**Learn More:** see `loomwright/commands/setup.md` and the `setup` skill (the module-contract authority); the observability architecture reference is `loomwright/docs/OBSERVABILITY.md`

---

### 🩺 /review-pr — Standalone PR Review-and-Heal

**Purpose:** Run the bounded review→fix→re-review loop against an *existing* PR URL — decoupled from a full Supervisor run, so any open PR (human- or agent-authored) can be reviewed and auto-healed in place. Resolves the PR's head branch (`gh pr view --json headRefName`), checks it out, then orchestrates a `code-reviewer` pass + a `general-purpose` fix worker (default 3 iterations) until the diff is clean (`PASS`) or escalates (`ESCALATED`). Pushes fixes (never `--force`); **never auto-merges** — the PR is always left open for a human, and `NEEDS_HUMAN` stops + notifies + posts findings to the PR.

> **Inline main-thread command.** `/review-pr` runs inline; the `loomwright:review-pr-runner` agent is for `claude --agent` agent-owned sessions and is NEVER `Task`-spawned (it spawns its own `code-reviewer` + fix-worker children — subagents cannot spawn subagents). Plain `/supervisor` can optionally auto-dispatch it from the completion tail (`--auto-review` / `--no-auto-review`, off by default); `/autonomous` chains it as a Task step in EVALUATE.

**Usage:**
```bash
/review-pr <pr-url>                                                       # review-and-heal an existing PR
```

**Learn More:** see `loomwright/commands/review-pr.md` for the workflow and the `REVIEW_HEAL_RESULT` output; the loop contract lives in `loomwright/skills/review-heal/SKILL.md`.

---

### QA Workflow Diagram

```
/qa-strategist src/ → Risk Classification + Coverage Targets
    ↓
/qa-executor → Discovery → Tests → Execute → Coverage → Bugs
    ↓
/qa-strategist --audit .qa-summary.md → STRATEGIST_VERDICT
    ↓
approved: QA complete | rejected: re-run with gaps addressed
```

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

### Agent Frontmatter (Native Configuration)

Every agent has YAML frontmatter that configures its behavior automatically:

| Setting | What It Does | Example |
|---------|-------------|---------|
| `name` | Agent identifier | `loomwright:supervisor-runner` |
| `tools` | Restricts available tools | Workers can't spawn subagents (no Task tool) |
| `model` | Sets model for the agent | Context-Keeper uses haiku (fast, cheap) |
| `maxTurns` | Limits API round-trips | Context-Keeper: 3 turns max |
| `memory: project` | Persistent memory across sessions | Code Reviewer remembers past patterns |
| `skills` | Pre-loads skill content | Supervisor gets workflow-management pre-injected |

**Agent Model Assignments:**
| Agent | Model | Why |
|-------|-------|-----|
| Supervisor | inherit | Respects user's model choice (Sonnet+ recommended) |
| Context-Keeper | haiku | Simple state read/write |
| Worker | inherit | Matches user's choice |
| Code Reviewer | inherit | Matches user's choice + memory |
| Red Team Reviewer | inherit | Matches user's choice + memory |

Use `/supervisor --cheap` to override the execution-shaped roles (orchestrator, execute-manager, worker, code-reviewer, Phase 4.5 fix tasks, and — when `--multi-voter-heal` is ON — the multi-voter verification voters/refute spawn) to Sonnet at spawn time. See `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" for the full profile table and Haiku-session caveat. Since v15.2.0, `/autonomous` and `/automate` also forward `--cheap` down the chain to every inlined `/supervisor` run.

**Agents with Persistent Memory:**
- Code Reviewer — remembers past review patterns, recurring issues
- Red Team Reviewer — remembers past vulnerabilities, attack patterns
- Product Owner — remembers domain context, terminology, stakeholder preferences

### Plugin Hooks (Quality Gates)

The plugin centralizes **22 hooks** in `hooks/hooks.json` that automatically enforce quality and surface notifications (the authoritative table lives in the root `CLAUDE.md`):

| Hook | When It Fires | What It Checks / Does |
|------|---------------|----------------|
| **SubagentStop** (worker, execute-manager, code-reviewer, supervisor-runner, qa-executor, plan-reviewer, launch-pad-runner) | The matching agent completes | Validates its result block (WORKER_RESULT, EXECUTE_*, CODE_REVIEW_RESULT v3, SUPERVISOR_RESULT, QA_RESULT, PLAN_REVIEW_RESULT, LAUNCH_PAD_RESULT) + 3 telemetry + 1 webhook `type: command` hooks |
| **PreToolUse (AskUserQuestion)** | Plugin about to block on a user question | Desktop banner (`notify-desktop.sh`) + paused-event webhook (v14.1.0) |
| **Notification** | Claude Code signals attention (permission / idle / elicitation) | Desktop banner (v14.1.0) |
| **PostToolUse (Bash)** | A Bash tool call completes (e.g. `gh pr create`) | Backstops the until-mergeable review drain on PR creation (`hook-dispatch-on-pr-create.sh`); session-scope gated, fail-safe (v14.34.0) |
| **SessionStart** | Session resume / clear / compact | Injects bounded recovery context (`session-resume.sh`, v14.2.0); also maintains per-project OpenTelemetry resource attributes (`set-otel-resource-attrs.sh`, telemetry-gated, fail-safe, v14.47.0) |
| **Stop / TaskCompleted / WorktreeCreate / WorktreeRemove / StopFailure** | Various | Completeness gate, task-done check, worktree create/remove + failure logging (`WorktreeRemove` added v15.5.0) |

These hooks run automatically — no configuration needed. They use fast prompt-based validation (haiku model, 30s timeout).

### Agent Teams (Experimental)

For research or exploration tasks, Claude Code Agent Teams provides native multi-agent coordination:

```bash
# Enable Agent Teams
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

**Best for:** Research across multiple areas, competing hypotheses, cross-layer changes.
**Not for:** Sequential tasks, same-file edits (use Supervisor v4 with git worktrees instead).

See `skills/agent-teams/SKILL.md` for full patterns and decision matrix.

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

# See commits after /commit
git log --oneline -5

# Push after /commit
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
.claude-plugin/
├── marketplace.json                  # Marketplace manifest (root)
└── README.md                         # Plugin-facing usage guide

loomwright/              # Nested plugin root
├── .claude-plugin/
│   └── plugin.json                   # Plugin metadata (v15.13.0)
├── commands/                         # Slash commands (21)
│   ├── launch-pad.md                 # Supervisor readiness
│   ├── supervisor.md                 # Parallel orchestrator (v4)
│   ├── autonomous.md                 # Continuous autonomous loop, stacked PRs (v14)
│   ├── automate.md                   # Generic automation engine — source → Queue → per-item loop (v14.41.0)
│   ├── product-owner.md              # Requirements definition
│   ├── orchestrator.md
│   ├── code-reviewer.md
│   ├── red-team-reviewer.md          # Adversarial auditor
│   ├── review-pr.md                  # Standalone PR review-and-heal loop (never auto-merges)
│   ├── qa-strategist.md              # Risk-based QA strategy
│   ├── qa-executor.md                # Automated QA testing
│   ├── dreaming.md                   # Read-only reflection over session logs (proposes memory + CLAUDE.md updates)
│   ├── capability-check.md           # Read-only scan for new Claude Code capabilities vs tracked baseline
│   ├── insights.md                   # Local Obsidian-friendly insights dashboard from session logs
│   ├── obsidian.md                   # Read-only linked Obsidian vault projection (logs + Twin contracts + memory)
│   ├── pr-postmortem.md              # Read-only on-demand PR review-churn root-cause analyzer
│   ├── telemetry.md                  # Opt-in GitHub Issues telemetry (status/enable/disable/test)
│   ├── setup.md                      # Optional-capability dashboard + guided configuration (incl. observability)
│   └── agent-help.md
├── agents/                           # Agent implementations (14 roles)
│   ├── launch-pad.md                 # Supervisor readiness agent
│   ├── supervisor.md                 # Parallel orchestrator (v4)
│   ├── execute-manager.md            # Phase 3 execution manager
│   ├── context-keeper.md             # State management agent
│   ├── worker.md                     # Implementation worker
│   ├── plan-reviewer.md              # Brief validation gate
│   ├── rubric-grader.md              # Phase 4.5 read-only Haiku scorer (v12.2.0)
│   ├── product-owner.md              # Requirements definition
│   ├── orchestrator.md
│   ├── code-reviewer.md
│   ├── red-team-reviewer.md
│   ├── review-pr.md                  # Standalone PR review-and-heal runner
│   ├── qa-strategist.md
│   └── qa-executor.md
├── hooks/                            # Plugin quality gate hooks
│   └── hooks.json                    # SubagentStop + TaskCompleted validation
├── docs/                             # Architecture + schemas
│   ├── RESULT_SCHEMAS.md
│   ├── FAILURE_ESCALATION.md
│   ├── ARCHITECTURE_CONTRACTS.md
│   ├── ARCHITECTURE.md
│   ├── QA_SYSTEM_BLUEPRINT.md
│   └── SPIKES/                       # Capability spike investigations + deferral records
└── skills/                           # Skill files (41 skills; 18 tech-stack skills moved to stackpack@atelier)
    ├── SKILLS_INDEX.md               # Skill catalog with agent mapping
    ├── supervisor-readiness/         # Pre-flight checklist & brief template
    ├── agent-teams/                  # Agent Teams patterns (experimental)
    ├── async-orchestration/          # Parallel dispatch patterns
    ├── state-management/             # State file schema
    ├── workflow-management/          # Supervisor workflow patterns
    ├── context-summarization/
    ├── commit/
    ├── quality-checklist/
    ├── error-handling/
    ├── unit-testing/
    └── ...                           # (tech-stack skills: stackpack@atelier)
```

### Project Files
```
your-project/
├── CLAUDE.md                # Codebase knowledge, patterns
├── .supervisor/             # Supervisor state (auto-created, gitignored)
│   ├── state.md             # Current session state
│   ├── history/             # Completed session summaries
│   └── jobs/                # Supervisor-Ready Briefs from Launch Pad
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
/red-team-reviewer --help  # Help for Red Team Reviewer
```

### Questions About the Plugin?
Check the plugin README:
```
cat /path/to/loomwright/.claude-plugin/README.md
```

### Issues or Suggestions?
Contribute to the Loomwright project:
```
https://github.com/your-org/loomwright
```

---

## Keyboard Shortcuts

These are Claude Code slash commands, so you can type them directly:
- Type `/launch` + Tab → Auto-completes to `/launch-pad`
- Type `/super` + Tab → Auto-completes to `/supervisor`
- Type `/orchestr` + Tab → Auto-completes to `/orchestrator`
- Type `/code-r` + Tab → Auto-completes to `/code-reviewer`
- Type `/red-t` + Tab → Auto-completes to `/red-team-reviewer`
- Type `/comm` + Tab → Auto-completes to `/commit`

---

## Summary

### Readiness Pipeline (Prepare for Autonomous Execution)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Launch Pad** | Supervisor readiness | Complex tasks, plan review | Raw goal + codebase | Supervisor-Ready Brief in `.supervisor/jobs/pending/` |

### Autonomous Workflow (End-to-End Automation — 4 Roles)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Supervisor** | Parallel orchestration | Autonomous task completion | Task description or Launch Pad brief | Completed tasks with PRs |
| **Execute Manager** | Phase 3 execution | Delegated by Supervisor | Brief pointer + subtask index + config | EXECUTE_RESULT / EXECUTE_CHECKPOINT |
| **Context-Keeper** | State management | On-demand (Supervisor/EM calls) | State operations | State file updates |
| **Worker** | Implementation | Background (parallel) | Subtask + worktree path | WORKER_RESULT + .worker-summary.md |

### Requirements Pipeline (Define What to Build)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Product Owner** | Define requirements | New feature, vague requirements | Feature/problem | User stories with acceptance criteria |

### Constructive Pipeline (Build Correctly)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Orchestrator** | Plan work | Start of task | Goal or story | Beads tasks with review gates |
| **Code Reviewer** | Review code | During development | Files/diff | PASS/FAIL/NEEDS_HUMAN + issues |
| **/commit** (skill) | Create commits | When done coding | Staged changes | Conventional commits + Beads links |

### Independent Auditor (Break Safely)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Red Team Reviewer** | Attack work | Pre-launch, security review | Target scope | Fatal issues + fixes |

### QA Pipeline (Test Automatically)

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **QA Strategist** | Plan test strategy | Before QA, or audit after | Source code or .qa-summary.md | Risk classification + STRATEGIST_VERDICT |
| **QA Executor** | Run automated QA | After implementation | Running app + Playwright config | QA_RESULT + test files |

---

**Ready to get started?**
- Prepare for execution: `/launch-pad goal: "your goal here"` (codebase analysis, brief, clean handoff)
- Autonomous workflow: `/supervisor` (picks up tasks, runs agents, creates PRs)
- Plan-first workflow: `/launch-pad` → `/supervisor job: .supervisor/jobs/pending/{brief}.md`
- Define requirements: `/product-owner feature: "your feature here"`
- Plan work: `/orchestrator goal: "your goal here"`
- Review code: `/code-reviewer src/`
- Attack work: `/red-team-reviewer` (adversarial audit)
