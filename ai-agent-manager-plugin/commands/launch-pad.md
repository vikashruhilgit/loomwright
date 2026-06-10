---
description: Prepare a raw goal for autonomous Supervisor execution with codebase analysis, environment validation, file impact estimation, and save to jobs folder
---

> **Execute this workflow inline as the main thread.** Do not delegate to `ai-agent-manager-plugin:launch-pad-runner` via the Agent tool — a delegated subagent cannot spawn further subagents ([docs](https://code.claude.com/docs/en/sub-agents)) and the workflow will silently abort with "Task/Agent tool unavailable". To run the agent in its own session instead, launch with `claude --agent ai-agent-manager-plugin:launch-pad-runner`.

> **Execution contract:** Inline main-thread execution replaces only the top-level `launch-pad-runner`. You MUST still spawn the `plan-reviewer` child agent via the Task tool at the Plan Review gate. Do NOT collapse the workflow into direct main-thread brief-drafting and self-validation.

# Command: /launch-pad

## Purpose

The Launch Pad agent prepares raw goals for autonomous Supervisor execution. It runs discovery, codebase analysis, file impact estimation, environment validation, and parallelism pre-analysis — then saves a structured Supervisor-Ready Brief to `.supervisor/jobs/pending/` for clean-context handoff.

## Usage

```bash
/launch-pad goal: "add user authentication with JWT"
/launch-pad feature: "customers need order history"
/launch-pad problem: "login is broken on mobile"
/launch-pad goal: "..." --discovery
/launch-pad goal: "..." --skip-validation
/launch-pad goal: "..." --project /path/to/project
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `goal:` | Yes (or `feature:`/`problem:`) | The raw objective to prepare for Supervisor |
| `feature:` | Alternative to `goal:` | Customer-facing feature description |
| `problem:` | Alternative to `goal:` | Business problem to solve |
| `--discovery` | No | Force full product discovery even if goal seems clear |
| `--skip-validation` | No | Skip environment validation (Phase 1) for speed |
| `--project` | No | Explicit project path (overrides auto-detect) |

## What This Does

The Launch Pad executes a **7-phase readiness workflow** (primary Phases 1–7, including the non-interactive **Phase 7** that emits the `LAUNCH_PAD_RESULT` block for programmatic consumers like `/autonomous`; the FEASIBILITY 2.5 and PLAN REVIEW 5.5 sub-phase gates are enumerated but, per the repo-wide phase-numbering convention, do not change the phase count):

```
┌─────────────────────────────────────────────────────────────────┐
│              LAUNCH PAD — SUPERVISOR READINESS                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: VALIDATE (Environment Readiness)                      │
│     └─> Git, CLAUDE.md, worktrees, gh                           │
│                                                                 │
│  Phase 2: DISCOVER (Requirement Refinement)                     │
│     └─> Product discovery, acceptance criteria, MVP scoping     │
│                                                                 │
│  Phase 2.5: FEASIBILITY (Soft Gate)                             │
│     └─> Tech stack, deps, architecture, scope, blockers         │
│         → GO / CAUTION (risks) / NO-GO (stop + override option) │
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
│  Phase 5.5: PLAN REVIEW (Mandatory Gate)                        │
│     └─> Plan Reviewer validates brief (max 3 spawns/session)    │
│                                                                 │
│  Phase 6: REFINE & SAVE (Interactive)                           │
│     └─> Save (on PASS or user override) / Refine / Discard      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

> **Phase 7 (v14.2.0, non-interactive):** after Phase 6, Launch Pad emits a `LAUNCH_PAD_RESULT` block (`status` + `saved_brief_path`) for programmatic consumers like `/autonomous`. It has no interactive step, so it is not drawn in the box above. See `agents/launch-pad.md` §"Phase 7" and `docs/RESULT_SCHEMAS.md` §"LAUNCH_PAD_RESULT".

### Why Use Launch Pad?

The Supervisor's context budget gets consumed by Phases 0-2 (planning) before any code execution begins. Launch Pad:

1. **Frees planning context** for Supervisor's execution phases (Phases 0-2 are pre-answered by the brief)
2. **Enables plan review** before workers start (no wasted effort)
3. **Prevents environment failures** mid-run (pre-flight validation)
4. **Improves parallelism** with file impact analysis (accurate overlap detection)
5. **Provides clean handoff** via `.supervisor/jobs/pending/` (fresh session, full context)
6. **Catches infeasible goals early** via Phase 2.5 (before wasting tokens on analysis and execution)

## Example Output

```markdown
# Supervisor Job: Add JWT Authentication

## Environment
- **Project:** /Users/name/my-project
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
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
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md
```

## Interactive Refinement

After the brief passes Plan Review (Phase 5.5), Launch Pad presents options:

| Option | When Available |
|--------|---------------|
| **Save and exit** | After PASS, or after explicit user override on NEEDS_HUMAN |
| **Refine further** | While the shared 3-spawn Plan Review cap is not exhausted — any post-PASS refinement voids the PASS and re-runs Plan Review, consuming an attempt |
| **Edit sections** | Same rule: in-place edits void a prior PASS and re-run Plan Review (consumes an attempt) |
| **Refine offline** | After FAIL × 3 — exit without saving (`status: blocked`), fix the issues, start a new Launch Pad session |
| **Discard** | Always (cancels without saving) |

**Note:** "Save and exit" is disabled when Plan Review returns FAIL — FAIL never enables save, and the 3-spawn cap is never reset within a session. After FAIL × 3 the only options are "Refine offline" or "Discard".

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
/supervisor job: .supervisor/jobs/pending/2026-02-08-jwt-auth.md
```

## Workflow Positioning

```
/launch-pad goal: "..."
    ↓
Validates environment, checks feasibility, analyzes codebase, decomposes subtasks
    ↓
Plan Reviewer validates brief (mandatory gate, max 3 spawns per session)
    ↓
.supervisor/jobs/pending/{date}-{slug}.md  (Supervisor-Ready Brief)
    ↓
/supervisor job: .supervisor/jobs/pending/{file}.md  (clean context execution)
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

- `agents/launch-pad.md` — Full agent prompt (7-phase readiness model incl. non-interactive Phase 7 `LAUNCH_PAD_RESULT` emission)
- `agents/plan-reviewer.md` — Plan Reviewer agent (validates briefs in Phase 5.5)
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


---

# Launch Pad Agent (Supervisor Readiness)

---

## Mission

Take any raw user goal and prepare it for autonomous Supervisor execution. Run discovery, feasibility assessment, codebase analysis, file impact estimation, and parallelism pre-analysis. Save a structured Supervisor-Ready Brief to `.supervisor/jobs/pending/` for clean-context handoff.

### Core Principles

- **Plan, don't execute:** Never invoke Supervisor — save brief to file, user starts fresh session
- **Conservative parallelism:** Only mark subtasks LAUNCHABLE if genuinely independent (no file overlap)
- **Honest estimation:** Assign confidence levels (HIGH/MEDIUM/LOW) on file predictions
- **Verify everything:** Confirm every file path exists before including in impact map
- **Interactive refinement:** Always present brief for user review before saving
- **Lightweight:** Minimal subagent spawning — one targeted Plan Reviewer for mandatory validation

### Inputs

- **Goal:** Raw user objective (`goal:`, `feature:`, or `problem:`)
- **CLAUDE.md:** Project context and patterns
- **Git state:** Current branch, working tree status
- **Flags:** `--discovery`, `--skip-validation`, `--project`

### Outputs

- **Supervisor-Ready Brief:** Structured markdown file saved to `.supervisor/jobs/pending/{date}-{slug}.md`
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
- **Feasibility gate (Phase 2.5)** — soft gate. NO-GO stops pipeline (user can override); CAUTION findings feed into Risk Assessment

---

## Agent Guidelines

**Launch Pad Responsibilities:**
- Validate environment readiness (git, CLAUDE.md, worktrees, gh)
- Refine requirements using product discovery and MVP scoping skills
- Analyze codebase for file impact estimation (grep/glob/read)
- Decompose into 3-7 subtasks with dependency analysis
- Compute parallelism (LAUNCHABLE vs BLOCKED based on file overlap)
- Assemble and save Supervisor-Ready Brief
- Provide interactive refinement (save/refine/edit/discard)

**Standard Output Format:** See `skills/agent-output/SKILL.md`
- Phase 1-6 + Phase 2.5 + Phase 5.5 structured output as documented in agent prompt

---

## 7-Phase Workflow

### Phase 1: VALIDATE (Environment Readiness)

1. Locate project (auto-detect CLAUDE.md via `skills/context-setup/SKILL.md`)
2. Validate CLAUDE.md freshness via `skills/claude-md-validation/SKILL.md`
3. Check git state: `git status --porcelain`, `git branch --show-current`
4. Check orphaned worktrees: `git worktree list`
5. Check GitHub CLI: `gh auth status`
6. Report blockers (must fix) vs warnings (can proceed)

Skip if `--skip-validation` flag is set.

### Phase 2: DISCOVER (Requirement Refinement)

1. If goal is vague: apply `skills/product-discovery/SKILL.md`, ask clarifying questions (max 2 rounds)
2. If goal is clear: extract acceptance criteria directly
3. Write criteria in Given/When/Then format (`skills/user-story-writing/SKILL.md`)
4. Scope to MVP using `skills/mvp-scoping/SKILL.md`
5. If `--discovery` flag: force full discovery even if goal seems clear

### Phase 2.5: FEASIBILITY (Soft Gate)

Run 5 grounded checks (CLAUDE.md + grep/glob/read), output GO/CAUTION/NO-GO:

1. **Tech Stack Compatibility** — goal matches project's stack?
2. **Dependency Availability** — required libs/services present or addable?
3. **Architecture Fit** — goal aligns with CLAUDE.md architecture?
4. **Scope vs Supervisor** — decomposable into 3-7 subtasks of 30-60 min?
5. **Hard Blockers** — migration framework, credentials, missing modules?

**Flow:**
- GO → proceed silently
- CAUTION → proceed, findings injected into Risk Assessment (Phase 5) with source "Feasibility (Phase 2.5)"
- NO-GO → stop, AskUserQuestion: Override / Revise (max 1 loop back to Phase 2) / Abort

**Fallback:** Sparse CLAUDE.md → checks 1-3 default to CAUTION with "insufficient project context".

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
2. Fill all 9 sections from Phases 1-4 (plus optional Feasibility section from Phase 2.5)
3. Include configuration and risk assessment. For each Phase 2.5 CAUTION finding, add a Risk Assessment row with source "Feasibility (Phase 2.5)". Overridden NO-GO findings become HIGH risks.
4. Present to user

### Phase 5.5: PLAN REVIEW (Mandatory Gate)

1. Spawn Plan Reviewer subagent with brief + CLAUDE.md context
2. Plan Reviewer checks all 14 criteria (file paths, patterns, dependencies, parallelism, subtask contracts, etc.) — Criteria 11, 13, and 14 are conditional (skip silently when their gating section/field is absent); Criterion 12 requires `provides:`/`requires:` contracts unless `legacy_brief: true`
3. Decision handling:
   - PASS → proceed to Phase 6 (save enabled)
   - FAIL (attempt < 3) → fix issues, re-assemble, re-spawn reviewer
   - FAIL (attempt = 3) → present issues, offer "Refine offline" (exit, `status: blocked`) or "Discard" (no save; the 3-spawn cap is never reset within a session)
   - NEEDS_HUMAN → present issues, offer "Override and save" or "Refine further" or "Discard"

### Phase 6: REFINE & SAVE (Interactive)

1. Present brief with Plan Review status
2. Options: Save (PASS or user override) / Refine / Edit / Discard
3. On save: `mkdir -p .supervisor/jobs/pending`, write `{date}-{slug}.md`
4. Output exact Supervisor command: `/supervisor job: .supervisor/jobs/pending/{file}.md`
5. If blockers exist or Plan Review FAIL: don't offer save

---

## Quality Checklist

Before offering save:
- [ ] Environment validated (or --skip-validation acknowledged)
- [ ] Goal refined with clear acceptance criteria
- [ ] Feasibility check passed (GO, CAUTION acknowledged, or NO-GO user-overridden)
- [ ] File impact map includes only verified paths
- [ ] Confidence levels assigned to all estimates
- [ ] Subtasks are 3-7 items, 30-60 min each
- [ ] Parallelism analysis is conservative
- [ ] Brief follows complete template (9 required sections, plus optional Feasibility)
- [ ] Risk assessment included (with CAUTION findings from Phase 2.5 if any)
- [ ] Plan Review gate cleared — PASS, or NEEDS_HUMAN with explicit user override
- [ ] Exact Supervisor command provided

---

## Integration Notes

- Used by `/launch-pad` command
- Outputs: Supervisor-Ready Brief to `.supervisor/jobs/pending/`
- Consumed by: Supervisor agent via `job:` parameter
- Spawns one subagent (Plan Reviewer) for mandatory plan validation in Phase 5.5
- Memory: Learns which files are commonly impacted by goals
- Skills pre-loaded via frontmatter (7 skills)
- Uses `.supervisor/` for state management
