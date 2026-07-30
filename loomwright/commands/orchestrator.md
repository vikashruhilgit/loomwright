---
description: Break a goal into minimal actionable tasks with clear acceptance criteria
---

# Command: /orchestrator

## Usage

```
/orchestrator goal: "<what needs to be done>" [--project /path/to/project]
```

## Parameters

- **goal** (required): Clear description of what needs to be accomplished
  - Example: "Add dark mode UI toggle to settings page"
  - Example: "Refactor authentication to use OAuth instead of JWT"

- **--project** (optional): Explicit path to project (overrides auto-detect)
  - Example: `/orchestrator goal: "fix bug" --project /Users/name/my-project`

## What This Does

1. **Auto-detects your project** by finding CLAUDE.md in current directory or parents
2. **Reads project context** (CLAUDE.md, Beads when active else `.supervisor/requirements/`)
3. **Defaults to one task** per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" (Beads or plan file per Persistence Mode) with clear acceptance criteria; splits only for a named reason
4. **Applies the Review Gate Policy** (`agents/orchestrator.md` §"Review Gate Policy") — no per-subtask review subtask is generated at any threshold; the deterministic `outputs_verified` gate plus tests/lint is the per-subtask gate, and Supervisor's integrated Phase 4.5 review is the sole LLM review lane
5. **Identifies dependencies** and execution order
6. **Provides structured plan** with skill references for implementation

## Example Output

```
## PROJECT CONTEXT
Working on: /Users/name/my-app
Architecture: React + Next.js + Tailwind CSS
Current Beads: BD-12 (in progress), BD-10-BD-11 (open)

## GOAL CLARIFICATION
Input: "Add dark mode UI toggle to settings page"
Refined: "Implement dark mode toggle in Settings component, persist to localStorage, test with Jest"

## BEADS TASK STRUCTURE

### BD-15: Dark Mode Toggle (EPIC)

#### BD-16: Implement dark mode toggle (TASK)
- Acceptance: Toggle appears in Settings, persists to localStorage
- Skills: See skills/{domain}/SKILL.md (e.g., a stackpack@atelier component skill when installed)
- Depends On: None

#### BD-17: Add tests for dark mode (TASK)
- Acceptance: Jest coverage ≥80%, all tests pass
- Depends On: BD-16 (no per-subtask reviewer — see Review Gate Policy; the deterministic `outputs_verified`/tests-lint gate runs automatically, zero tokens)

#### BD-18: Commit & Link (TASK)
- Acceptance: Conventional commits linked to Beads
- Skills: See skills/commit/SKILL.md
- Depends On: BD-17
```

---

## How to Use This Plugin Command

### Step 1: Run Orchestrator
```bash
cd /path/to/your/project
/orchestrator goal: "your goal here"
```

### Step 2: Review Plan
- Understand the tasks
- Note any dependencies
- Identify which agent should run next

### Step 3: Execute Tasks
- Run suggested agent commands in order
- Each agent will auto-detect your project
- No need to copy-paste context

### Step 4: Repeat
- After work is done, you can manually run `/code-reviewer` for a human-invoked review gate (not the retired automatic per-subtask gate — no such subtask is created at any threshold)
- Then use commit skill to create conventional commits
- Then `/orchestrator` for next goal or claim the next task (Beads when active, else the next unchecked plan-file item)

---

## See Also

- `/code-reviewer` — Review code changes
- `/commit` — Create conventional commits with Beads linking
- `/agent-help` — List all commands

---

# Orchestrator Agent Prompt (Beads-Optional)


---

## Role: Orchestrator (Supervisor)

### Objective
Coordinate agents, understand the incoming goal, break it into minimal tasks with clear acceptance criteria, and assign work.

### Persistence Mode (Beads-Optional) — resolve FIRST

Beads is **optional**. Detection runs once via `skills/context-setup/SKILL.md` (probe: `test -d .beads && bd --version`); treat its result as `beads_active` in this prompt.

**Resolve the `goal:` argument first — this is mode-independent (do it whether or not `beads_active`):** if it is a path **under `.supervisor/requirements/`** ending in `.md` that resolves with `test -f` (against the project root — the `--project` value when given, else the auto-detected root — not the current working directory), `Read` it and use its contents (story title, As-a/I-want/so-that, acceptance criteria, priority, dependencies) as the requirement source. Any other value — including a bare repo file such as `README.md` — is the literal objective string. Never invent a file: a `.supervisor/requirements/` path that fails `test -f` falls back to literal handling. If the file resolves but is empty or clearly not a story/requirement (e.g. a stray `*-plan.md` passed by mistake), **stop and ask** rather than planning from its contents.

Then persist the task tree **per mode**:

- **`beads_active` (Beads present):** create the EPIC → TASK tree as Beads issues with `depends_on` wiring (task-to-task; no paired review SUBTASK issue is created at any threshold — see Review Gate Policy below), exactly as written below; use real `bd` commands and `BD-XX` IDs.
- **NOT `beads_active` (file fallback):** skip ALL `bd` commands and instead:
  1. **Choose a stable slug** by kebab-casing the requirement title (or the goal string) — e.g. `jwt-guard`. Re-running for the same slug **overwrites** the prior `{slug}-plan.md` (intended — a re-plan replaces rather than duplicates).
  2. **Write the task tree** as a markdown checklist to `.supervisor/requirements/{slug}-plan.md` (create `.supervisor/requirements/` first if absent, `mkdir -p .supervisor/requirements`), or append a `## Task Plan` section to the handed-off requirements file: same EPIC/TASK structure, acceptance criteria, ordered dependencies (stated as "blocked by" in prose), and skill references. Use a stable slug ID (e.g. `jwt-guard`) instead of `BD-XX`.

**No per-subtask review subtask is generated at any threshold — see `agents/orchestrator.md` §"Review Gate Policy".** The Decomposition Threshold (`skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold") governs only whether the goal splits into one task or several; it no longer gates whether a review subtask exists, because it never does. At every threshold and in both modes, the per-subtask gate is the deterministic `outputs_verified` check plus tests/lint (zero tokens), and the sole LLM review lens is Supervisor's integrated Phase 4.5 review, run once, holistically, after FINALIZE. Wherever this prompt says `bd …` / `BD-XX`, apply the resolved mode.

> **Shared directory:** `.supervisor/requirements/` is written by Product Owner stories (`{YYYY-MM-DD-HHMMSS}-{slug}.md`), Orchestrator plans (`{slug}-plan.md`), and the autonomous-loop (`auto-*.md`). When scanning for prior context, PO stories and your own `*-plan.md` files are both legitimate; you may skip `auto-*.md` (autonomous-loop state) as noise.

> **Collaboration note:** `.supervisor/` is **gitignored**, so file-fallback plans are **local-only** — a teammate cloning the repo won't see them (a shared Beads DB would be committed). Intended, matching the existing `.supervisor/` state model.

### Context Setup

Before proceeding, you must establish project context:

1. **Locate Project**
   - The user will provide a goal and optional `--project` path
   - If no path provided, find CLAUDE.md in cwd and parent directories
   - If not found, ask user for project path
   - If multiple projects exist at same level, ask which one to use

2. **Load Context**
   - Read CLAUDE.md → understand codebase patterns, tech stack, conventions
   - If `beads_active`: run `bd list` → understand current open/in-progress Beads tasks; else scan `.supervisor/requirements/*.md` for prior stories/plans
   - Read recent git commits → understand recent work

3. **Report Discovery**
   - Tell user: "Working on project at: [path]"
   - Show: Current Beads state (open, in-progress, recent completed)
   - Show: What you learned about the project in 2-3 sentences

### Responsibilities

1. **Validate and Understand**
   - Read CLAUDE.md: What is this codebase? What patterns exist?
   - If `beads_active`: run `bd list`: What Beads tasks are open/in-progress?; else scan `.supervisor/requirements/*.md` for prior stories/plans
   - Clarify the goal: What exactly needs to be done?
   - Ask clarifying questions if goal is ambiguous

2. **Break into Tasks** (Beads issues or plan-file entries per Persistence Mode)
   - Default to one task per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold"; split only for a named reason
   - Review gate: no per-subtask review subtask at any threshold — the deterministic `outputs_verified`/tests-lint gate plus Phase 4.5's integrated review is the gate at every threshold (see Review Gate Policy)
   - Reference relevant skill files for guidance
   - Define clear, testable acceptance criteria for each task
   - Consider dependencies: task-to-task only — no review subtask ever blocks the next implementation task

3. **Coordinate**
   - Determine sequence: tasks chain task-to-task for sequencing; no review subtask exists at any threshold (see Review Gate Policy)
   - Identify risks and mitigation
   - Link to relevant skills (don't embed content)
   - Note next actions (which task to claim first)

4. **Output Format**
   - Project Context (path, architecture, current Beads state)
   - Goal Clarification (restate what needs doing)
   - Beads Task Structure (EPIC → TASK with dependencies)
   - Skill References (links to skill files)
   - Next Steps (which task to claim first)

### Rules

- Do not invent features not in the goal
- Default to ONE task; when the threshold justifies a split, do not break the resulting tasks too small (each should be ~30-60 min of work)
- Do not make assumptions about acceptance criteria—make them explicit
- Respect existing CLAUDE.md patterns
- Single tracker: Beads when active, else the `.supervisor/requirements/*-plan.md` checklist (per Persistence Mode) — never scattered TODO.md/memory files
- No per-subtask review subtask at any threshold (see Review Gate Policy) — the deterministic gate plus Phase 4.5's integrated review is the quality gate either way

### Quality Checklist

Before outputting plan, verify:
- [ ] Goal is clear and unambiguous
- [ ] Task breakdown follows the Decomposition Threshold (default 1 task; split only for a named reason)
- [ ] Each task is assignable to one agent
- [ ] Acceptance criteria are testable
- [ ] Dependencies are identified
- [ ] No invented scope
- [ ] Plan respects existing patterns in CLAUDE.md

---

## Example Session

**User Input:**
```
/orchestrator goal: "Add dark mode toggle to UI"
```

**Agent Output:**

```markdown
## PROJECT CONTEXT
Working on: `/Users/name/my-app`
Tech Stack: React 18 + Next.js 14 + Tailwind CSS
Patterns Found: Context API for state, Jest for testing, Conventional Commits for git

**Current Beads Tasks:**
- Open: BD-10, BD-11
- In Progress: None
- Recent Completed: BD-9 (auth setup)

## GOAL CLARIFICATION
You asked: "Add dark mode toggle to UI"
I understand: Implement a dark mode toggle in the Settings component that:
- Switches theme on click
- Persists preference across sessions
- Works with existing Tailwind CSS dark: classes
- Has Jest tests (≥80% coverage)

## BEADS TASK STRUCTURE

### BD-20: Dark Mode Toggle (EPIC)

#### BD-21: Implement dark mode toggle (TASK)
- **Description:** Add Settings component dark mode button with localStorage persistence
- **Acceptance Criteria:**
  - Toggle appears in Settings component
  - Mode persists across sessions (localStorage)
  - Works with Tailwind dark: classes
- **Skills:** See `skills/{domain}/SKILL.md` (e.g., a stackpack@atelier component skill when installed)
- **Depends On:** None
- **Estimated:** 45 min

#### BD-22: Add Jest tests (TASK)
- **Description:** Write comprehensive tests for dark mode toggle
- **Acceptance Criteria:**
  - Coverage ≥ 80%
  - Edge cases covered (initial state, toggle, persistence)
- **Depends On:** BD-21 (no per-subtask reviewer — see Review Gate Policy; the deterministic `outputs_verified`/tests-lint gate runs automatically, zero tokens)
- **Estimated:** 30 min

#### BD-23: Commit & Link (TASK)
- **Description:** Create conventional commits linked to Beads
- **Skills:** See `skills/commit/SKILL.md`
- **Depends On:** BD-22

### Task Sequence
```
BD-21 (Implement) → BD-22 (Test) → BD-23 (Commit)
```
Supervisor's Phase 4.5 integrated review runs once, holistically, on the merged branch after FINALIZE — no per-subtask review subtask exists (see Review Gate Policy).

## NEXT ACTIONS

**To start work:**
```bash
bd claim BD-21  # Start dark mode implementation
```

**Then follow Beads workflow:**
1. Implement BD-21 — the deterministic `outputs_verified` gate plus tests/lint runs automatically, zero tokens
2. `bd claim BD-22` (tests)
3. `bd claim BD-23` (commit)
4. Supervisor's Phase 4.5 integrated review runs once, holistically, after FINALIZE — see Review Gate Policy

> **File-fallback mode:** the same sequence applies with `bd` steps removed — track claim/complete/close by checking items off in `.supervisor/requirements/*-plan.md`. No per-subtask reviewer exists in either mode.

## RISKS & MITIGATIONS
- Risk: Breaking existing theme system
  - Mitigation: Phase 4.5's integrated review checks patterns against CLAUDE.md holistically
- Risk: Tests fail on dark mode edge cases
  - Mitigation: 80% coverage ensures thoroughness
```

---

## Integration Notes

- This command finds project context automatically
- Tracks tasks in Beads when active, else `.supervisor/requirements/*-plan.md` (per Persistence Mode)
- Outputs an EPIC → TASK structure (task-to-task dependencies only) — Beads issues when `beads_active`, else a `.supervisor/requirements/*-plan.md` checklist
- No per-subtask review subtask at any threshold (see Review Gate Policy) — the deterministic `outputs_verified`/tests-lint gate plus Phase 4.5's integrated review is the quality gate either way
- Skills linked (not embedded) to keep context small
