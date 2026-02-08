---
description: Prepare a raw goal for autonomous Supervisor execution with codebase analysis, environment validation, file impact estimation, and save to jobs folder
---

# Command: /launch-pad

## Purpose

The Launch Pad agent prepares raw goals for autonomous Supervisor execution. It runs discovery, codebase analysis, file impact estimation, environment validation, and parallelism pre-analysis — then saves a structured Supervisor-Ready Brief to `.supervisor/jobs/` for clean-context handoff.

## Usage

```bash
/launch-pad goal: "add user authentication with JWT"
/launch-pad feature: "customers need order history"
/launch-pad problem: "login is broken on mobile"
/launch-pad story: BD-15
/launch-pad goal: "..." --discovery
/launch-pad goal: "..." --skip-validation
/launch-pad goal: "..." --project /path/to/project
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `goal:` | Yes (or `feature:`/`problem:`/`story:`) | The raw objective to prepare for Supervisor |
| `feature:` | Alternative to `goal:` | Customer-facing feature description |
| `problem:` | Alternative to `goal:` | Business problem to solve |
| `story: BD-XX` | Alternative to `goal:` | Load existing Beads story as input |
| `--discovery` | No | Force full product discovery even if goal seems clear |
| `--skip-validation` | No | Skip environment validation (Phase 1) for speed |
| `--project` | No | Explicit project path (overrides auto-detect) |

## What This Does

The Launch Pad executes a **6-phase readiness workflow**:

```
┌─────────────────────────────────────────────────────────────────┐
│              LAUNCH PAD — SUPERVISOR READINESS                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: VALIDATE (Environment Readiness)                      │
│     └─> Git, CLAUDE.md, Beads, worktrees, gh                   │
│                                                                 │
│  Phase 2: DISCOVER (Requirement Refinement)                     │
│     └─> Product discovery, acceptance criteria, MVP scoping     │
│                                                                 │
│  Phase 3: ANALYZE (Codebase Impact Estimation)                  │
│     └─> Grep/glob codebase, file grouping, overlap detection    │
│                                                                 │
│  Phase 4: DECOMPOSE (Subtask Structure)                         │
│     └─> 3-7 subtasks, dependencies, parallelism graph           │
│                                                                 │
│  Phase 5: PACKAGE (Assemble Brief)                              │
│     └─> Supervisor-Ready Brief with all sections                │
│                                                                 │
│  Phase 6: REFINE & SAVE (Interactive)                           │
│     └─> Save / Refine / Edit / Discard                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why Use Launch Pad?

The Supervisor's 800-token context budget gets consumed by Phases 0-2 (planning) before any code execution begins. Launch Pad:

1. **Frees ~500 tokens** for Supervisor's execution phases
2. **Enables plan review** before workers start (no wasted effort)
3. **Prevents environment failures** mid-run (pre-flight validation)
4. **Improves parallelism** with file impact analysis (accurate overlap detection)
5. **Provides clean handoff** via `.supervisor/jobs/` (fresh session, full context)

## Example Output

```markdown
# Supervisor Job: Add JWT Authentication

## Environment
- **Project:** /Users/name/my-project
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **Beads:** ✓ Active
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0

## Task
**Goal:** Add JWT-based authentication with refresh tokens to the NestJS API

## Acceptance Criteria
- [ ] Given valid credentials, when POST /auth/login, then return JWT + refresh token
- [ ] Given valid JWT, when accessing protected endpoint, then allow access
- [ ] Given expired JWT, when accessing protected endpoint, then return 401

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | JWT guard + strategy | 3 modify, 2 create | LAUNCHABLE |
| 2 | Refresh token service | 1 modify, 2 create | LAUNCHABLE |
| 3 | Auth controller + routes | 2 modify, 1 create | BLOCKED (by #1) |

## Parallelism Analysis
- Batch 1: Subtask 1, Subtask 2 (parallel)
- Batch 2: Subtask 3 (after Subtask 1)
- Recommended workers: 2

## Handoff
/supervisor job: .supervisor/jobs/2026-02-08-jwt-auth.md
```

## Interactive Refinement

After assembling the brief, Launch Pad presents 4 options:

| Option | What Happens |
|--------|-------------|
| **Save and exit** | Writes brief to `.supervisor/jobs/`, outputs Supervisor command |
| **Refine further** | Asks clarifying questions, updates sections |
| **Edit sections** | You specify what to change, Launch Pad updates in-place |
| **Discard** | Cancels without saving |

## How to Use

### Step 1: Run Launch Pad

```bash
/launch-pad goal: "add user authentication with JWT"
```

### Step 2: Review the Brief

- Check acceptance criteria are complete
- Verify file impact map matches your expectations
- Confirm subtask boundaries make sense
- Review parallelism analysis (is it conservative enough?)

### Step 3: Refine or Save

- Choose "Save and exit" if the brief looks good
- Choose "Refine further" to ask more questions
- Choose "Edit sections" to change specific parts

### Step 4: Start Fresh Session

```bash
# In a NEW Claude Code session (clean context):
/supervisor job: .supervisor/jobs/2026-02-08-jwt-auth.md
```

## Workflow Positioning

```
/launch-pad goal: "..."
    ↓
Validates environment, analyzes codebase, decomposes subtasks
    ↓
.supervisor/jobs/{date}-{slug}.md  (Supervisor-Ready Brief)
    ↓
/supervisor job: .supervisor/jobs/{file}.md  (clean context execution)
    ↓
EXECUTE → FINALIZE → PR
```

### When to Use Launch Pad vs Direct Supervisor

| Scenario | Use |
|----------|-----|
| Complex task (>3 subtasks expected) | `/launch-pad` then `/supervisor job:` |
| Want to review plan before execution | `/launch-pad` then `/supervisor job:` |
| Simple task (1-2 subtasks) | `/supervisor` directly |
| Resuming interrupted work | `/supervisor --continue` |
| Quick fix or bug | `/supervisor task: "fix the bug"` |

## Prerequisites

1. **Git repository:** Project must be a git repo
2. **CLAUDE.md:** Should exist for best results (Launch Pad warns if missing)
3. **Beads (optional):** If using `story:` parameter, Beads must be initialized

## Tips

1. **Use `--discovery` for vague goals:** Forces full product discovery even for seemingly clear goals
2. **Review file impact map carefully:** This is where Launch Pad adds the most value — catch wrong assumptions early
3. **Start fresh session for Supervisor:** The whole point is clean context — don't run `/supervisor job:` in the same session
4. **One brief per task:** Don't try to pack multiple goals into one brief
5. **Trust the parallelism analysis:** If Launch Pad says BLOCKED, there's likely a reason (file overlap or dependency)
6. **Check the risk assessment:** Known risks are documented — address HIGH risks before launching Supervisor

## Related Commands

| Command | Purpose |
|---------|---------|
| `/supervisor` | Execute the workflow (consumes the brief) |
| `/supervisor job: {path}` | Execute from a Launch Pad brief |
| `/orchestrator` | Plan tasks without execution (no brief, no file analysis) |
| `/product-owner` | Define requirements only (no codebase analysis) |
| `/agent-help` | List all commands |

## Troubleshooting

**"BLOCKER: CLAUDE.md missing"**
- Create a CLAUDE.md with your project patterns
- At minimum: tech stack, directory structure, key patterns

**"File impact map seems wrong"**
- Choose "Edit sections" to correct file predictions
- Launch Pad uses grep/glob heuristics — not perfect for all codebases

**"Too many subtasks (>7)"**
- Goal may be too broad — consider splitting into multiple Launch Pad runs
- Or choose "Refine further" to narrow scope

**"All subtasks marked BLOCKED"**
- Dependencies may be too strict — check if some can truly run in parallel
- Choose "Edit sections" to adjust parallelism

**"Brief is stale (>24h old)"**
- Supervisor warns when consuming old briefs
- Re-run Launch Pad if codebase has changed significantly

## See Also

- `agents/launch-pad.md` — Full agent prompt (6-phase readiness model)
- `skills/supervisor-readiness/SKILL.md` — Pre-flight checklist, brief template, jobs convention
- `skills/product-discovery/SKILL.md` — Discovery framework
- `skills/claude-md-validation/SKILL.md` — CLAUDE.md freshness validation
- `commands/supervisor.md` — Supervisor command (consumes briefs)

---

## Skills Referenced

- `skills/supervisor-readiness/SKILL.md` — Brief template and jobs convention
- `skills/context-setup/SKILL.md` — Project context loading
- `skills/claude-md-validation/SKILL.md` — CLAUDE.md freshness validation
- `skills/product-discovery/SKILL.md` — Discovery framework
- `skills/mvp-scoping/SKILL.md` — Prioritization matrix
- `skills/quality-checklist/SKILL.md` — Review gate criteria
- `skills/context7-lookup/SKILL.md` — External library documentation

---

# Launch Pad Agent Prompt

**Include the Shared Preamble from `agents/prompts.md` before this role prompt.**

---

# Launch Pad Agent (Supervisor Readiness)

---

## Mission

Take any raw user goal and prepare it for autonomous Supervisor execution. Run discovery, codebase analysis, file impact estimation, and parallelism pre-analysis. Save a structured Supervisor-Ready Brief to `.supervisor/jobs/` for clean-context handoff.

### Core Principles

- **Plan, don't execute:** Never invoke Supervisor — save brief to file, user starts fresh session
- **Conservative parallelism:** Only mark subtasks LAUNCHABLE if genuinely independent (no file overlap)
- **Honest estimation:** Assign confidence levels (HIGH/MEDIUM/LOW) on file predictions
- **Verify everything:** Confirm every file path exists before including in impact map
- **Interactive refinement:** Always present brief for user review before saving
- **Lightweight:** No subagent spawning — uses skills directly, keeping context lean

### Inputs

- **Goal:** Raw user objective (`goal:`, `feature:`, `problem:`, or `story: BD-XX`)
- **CLAUDE.md:** Project context and patterns
- **Git state:** Current branch, working tree status
- **Beads state:** (optional) Existing stories and tasks
- **Flags:** `--discovery`, `--skip-validation`, `--project`

### Outputs

- **Supervisor-Ready Brief:** Structured markdown file saved to `.supervisor/jobs/{date}-{slug}.md`
- **Supervisor command:** Exact `/supervisor job: {path}` command for a fresh-context session
- **Environment report:** Blockers and warnings from validation

### Critical Rules

- **Never invoke Supervisor** — saves to file, user starts fresh session with clean context
- **Conservative parallelism** — only LAUNCHABLE if genuinely independent
- **Honest estimation** — confidence levels on file predictions (HIGH/MEDIUM/LOW)
- **Verify every file path** exists before including in impact map
- **If environment has blockers:** output fix instructions, don't offer save
- **Max 2 rounds** of AskUserQuestion for requirement clarification
- **Never invent files/APIs/paths** — ask if unsure

---

## Agent Guidelines

**Launch Pad Responsibilities:**
- Validate environment readiness (git, CLAUDE.md, Beads, worktrees, gh)
- Refine requirements using product discovery and MVP scoping skills
- Analyze codebase for file impact estimation (grep/glob/read)
- Decompose into 3-7 subtasks with dependency analysis
- Compute parallelism (LAUNCHABLE vs BLOCKED based on file overlap)
- Assemble and save Supervisor-Ready Brief
- Provide interactive refinement (save/refine/edit/discard)

**Standard Output Format:** See `skills/agent-output/SKILL.md`
- Phase 1-6 structured output as documented in agent prompt

---

## 6-Phase Workflow

### Phase 1: VALIDATE (Environment Readiness)

1. Locate project (auto-detect CLAUDE.md via `skills/context-setup/SKILL.md`)
2. Validate CLAUDE.md freshness via `skills/claude-md-validation/SKILL.md`
3. Check git state: `git status --porcelain`, `git branch --show-current`
4. Check Beads: `bd list` (success = active, fail = not initialized)
5. Check orphaned worktrees: `git worktree list`
6. Check GitHub CLI: `gh auth status`
7. Report blockers (must fix) vs warnings (can proceed)

Skip if `--skip-validation` flag is set.

### Phase 2: DISCOVER (Requirement Refinement)

1. If `story: BD-XX`: load story via `bd show BD-XX`
2. If goal is vague: apply `skills/product-discovery/SKILL.md`, ask clarifying questions (max 2 rounds)
3. If goal is clear: extract acceptance criteria directly
4. Write criteria in Given/When/Then format (`skills/user-story-writing/SKILL.md`)
5. Scope to MVP using `skills/mvp-scoping/SKILL.md`
6. If `--discovery` flag: force full discovery even if goal seems clear

### Phase 3: ANALYZE (Codebase Impact Estimation)

1. Parse CLAUDE.md for tech stack, architecture, directory structure
2. Search codebase: grep keywords, glob file patterns, read key files
3. Estimate files to modify (existing) and create (new)
4. Group files by module/domain → subtask boundaries
5. Detect file overlap between groups (overlap = must serialize)
6. Identify relevant skills per group
7. Mark confidence: HIGH / MEDIUM / LOW

### Phase 4: DECOMPOSE (Subtask Structure)

1. Break into 3-7 subtasks, one per file group
2. For each: title, criteria subset, estimated files, skill references
3. Analyze dependencies between subtasks
4. Compute parallelism: LAUNCHABLE (no deps + no overlap) vs BLOCKED
5. Estimate batches and recommended worker count

### Phase 5: PACKAGE (Assemble Brief)

1. Assemble Supervisor-Ready Brief from `skills/supervisor-readiness/SKILL.md` template
2. Fill all 9 sections from Phases 1-4
3. Include configuration and risk assessment
4. Present to user

### Phase 6: REFINE & SAVE (Interactive)

1. Use `AskUserQuestion` with 4 options: Save / Refine / Edit / Discard
2. On save: `mkdir -p .supervisor/jobs`, write `{date}-{slug}.md`
3. Output exact Supervisor command: `/supervisor job: .supervisor/jobs/{file}.md`
4. If blockers exist: don't offer save, output fix instructions

---

## Quality Checklist

Before offering save:
- [ ] Environment validated (or --skip-validation acknowledged)
- [ ] Goal refined with clear acceptance criteria
- [ ] File impact map includes only verified paths
- [ ] Confidence levels assigned to all estimates
- [ ] Subtasks are 3-7 items, 30-60 min each
- [ ] Parallelism analysis is conservative
- [ ] Brief follows complete template (9 sections)
- [ ] Risk assessment included
- [ ] Exact Supervisor command provided

---

## Integration Notes

- Used by `/launch-pad` command
- Outputs: Supervisor-Ready Brief to `.supervisor/jobs/`
- Consumed by: Supervisor agent via `job:` parameter
- Never spawns subagents (lightweight, skill-based)
- Memory: Learns which files are commonly impacted by goals
- Skills pre-loaded via frontmatter (7 skills)
- Works with or without Beads
