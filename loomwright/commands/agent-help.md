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

<!-- index-only:begin -->

**Read rule (split parts, move-only).** A bare `/agent-help` answers from this file alone — `## Quick Start` and the `## Command Reference` index below, whose entries name every command — and reads no part. Only for detail on one command, or on a section of the guide that follows the reference, `Read` the ONE part below that holds it, from `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/agent-help/`, one Read call per file, and read no other part:

- `readiness.md` — `/launch-pad`, `/supervisor`.
- `build.md` — `/product-owner`, `/orchestrator`, `/code-reviewer`, `/commit`, `/red-team-reviewer`.
- `qa.md` — `/qa-strategist`, `/qa-executor`, `/verify`.
- `knowledge.md` — `/dreaming`, `/capability-check`, `/insights`, `/obsidian`, `/handoff`, `/propose`.
- `ops.md` — `/telemetry`, `/rules`, `/pr-postmortem`, `/autonomous`, `/backlog`, `/janitor`.
- `more.md` — `/setup`, `/review-pr`, the QA Workflow Diagram.
- `guide.md` — Daily Workflow Example, Common Scenarios, Key Concepts, Tips & Tricks, Files & Directories, Getting Help, Keyboard Shortcuts, Summary.

`/automate` is in this file in full; it has no part.

<!-- index-only:end -->
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
  ├─ Execute Manager  →  Phase 3 poll loop, worker lifecycle (blocking)
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

<!-- split:begin ../docs/command-parts/agent-help/readiness.md -->
### 🚀 /launch-pad — Supervisor Readiness

See [../docs/command-parts/agent-help/readiness.md](../docs/command-parts/agent-help/readiness.md).

### 🤖 /supervisor — Parallel Orchestrator (v4)

See [../docs/command-parts/agent-help/readiness.md](../docs/command-parts/agent-help/readiness.md).
<!-- split:end ../docs/command-parts/agent-help/readiness.md -->
<!-- split:begin ../docs/command-parts/agent-help/build.md -->
### 0️⃣ /product-owner — Define Requirements

See [../docs/command-parts/agent-help/build.md](../docs/command-parts/agent-help/build.md).

### 1️⃣ /orchestrator — Plan Your Work

See [../docs/command-parts/agent-help/build.md](../docs/command-parts/agent-help/build.md).

### 2️⃣ /code-reviewer — Review Code Changes

See [../docs/command-parts/agent-help/build.md](../docs/command-parts/agent-help/build.md).

### 3️⃣ /commit — Create Commits

See [../docs/command-parts/agent-help/build.md](../docs/command-parts/agent-help/build.md).

### 4️⃣ /red-team-reviewer — Attack Your Work (Adversarial)

See [../docs/command-parts/agent-help/build.md](../docs/command-parts/agent-help/build.md).
<!-- split:end ../docs/command-parts/agent-help/build.md -->
<!-- split:begin ../docs/command-parts/agent-help/qa.md -->
### 5️⃣ /qa-strategist — Risk-Based QA Strategy

See [../docs/command-parts/agent-help/qa.md](../docs/command-parts/agent-help/qa.md).

### 6️⃣ /qa-executor — Automated QA Testing

See [../docs/command-parts/agent-help/qa.md](../docs/command-parts/agent-help/qa.md).

### 🔎 /verify — Walk a ticket through the running app

See [../docs/command-parts/agent-help/qa.md](../docs/command-parts/agent-help/qa.md).
<!-- split:end ../docs/command-parts/agent-help/qa.md -->
<!-- split:begin ../docs/command-parts/agent-help/knowledge.md -->
### 💤 /dreaming — Reflect on Past Sessions (Read-Only Until You Accept)

See [../docs/command-parts/agent-help/knowledge.md](../docs/command-parts/agent-help/knowledge.md).

### 🔭 /capability-check — Scan for New Platform Capabilities (Read-Only)

See [../docs/command-parts/agent-help/knowledge.md](../docs/command-parts/agent-help/knowledge.md).

### 📊 /insights — Local Insights Dashboard (Read-Only, Obsidian-friendly)

See [../docs/command-parts/agent-help/knowledge.md](../docs/command-parts/agent-help/knowledge.md).

### 🔮 /obsidian — Local Obsidian Vault Projection (Read-Only, Linked)

See [../docs/command-parts/agent-help/knowledge.md](../docs/command-parts/agent-help/knowledge.md).

### 🤝 /handoff — Catch-Up / Hand-Off Digest (Read-Only)

See [../docs/command-parts/agent-help/knowledge.md](../docs/command-parts/agent-help/knowledge.md).

### 🌱 /propose — Candidate Work Items from the Churn Ledger, a /verify Run, the Feature Scorecard, and the Domain (Read-Only, Propose-Only)

See [../docs/command-parts/agent-help/knowledge.md](../docs/command-parts/agent-help/knowledge.md).
<!-- split:end ../docs/command-parts/agent-help/knowledge.md -->
<!-- split:begin ../docs/command-parts/agent-help/ops.md -->
### 📡 /telemetry — Opt-In GitHub Issues Telemetry

See [../docs/command-parts/agent-help/ops.md](../docs/command-parts/agent-help/ops.md).

### 📜 /rules — House Rules Substrate (Committed `.agent/rules/`)

See [../docs/command-parts/agent-help/ops.md](../docs/command-parts/agent-help/ops.md).

### 🩺 /pr-postmortem — PR Review-Churn Root-Cause Analysis (Read-Only)

See [../docs/command-parts/agent-help/ops.md](../docs/command-parts/agent-help/ops.md).

### 🔁 /autonomous — Continuous Autonomous Loop (v14, stacked PRs)

See [../docs/command-parts/agent-help/ops.md](../docs/command-parts/agent-help/ops.md).

### 📋 /backlog — Requirement Backlog Board (Read-Only, Owner-Gated Stamps)

See [../docs/command-parts/agent-help/ops.md](../docs/command-parts/agent-help/ops.md).

### 🧹 /janitor — Leftover Processes, Locks, Lanes and Worktrees (Read-Only, Owner-Picked Actions)

See [../docs/command-parts/agent-help/ops.md](../docs/command-parts/agent-help/ops.md).
<!-- split:end ../docs/command-parts/agent-help/ops.md -->
### 🤖 /automate — Generic Automation Engine (v14.41.0)

**Purpose:** Walk arbitrary work from any starting point. Converts any source — a prompt (via `/product-owner`), a requirements folder, or a backlog/plan doc — into a full Queue inside a **single run file** `.supervisor/automate/<run_id>.md` (the contract, dashboard, and resume state), then drives each Queue item through the per-item loop: by default each phase is a fresh headless session (Launch Pad → Supervisor → **one owned `/review-pr --until-mergeable` drain**; `--inline-phases`: `/autonomous --single-iteration` + an inline drain) → trusted-merge-or-park → sync `main` → check the item off. Smart resume globs `.supervisor/automate/*.md` for incomplete runs and reconciles against ground truth before trusting a checkbox.

**Usage:**
```bash
/automate "<what you want to automate>"          # prompt source (via /product-owner) → Queue
/automate                                         # bare → resume an incomplete run, else ASK
/automate --folder <dir>                          # folder source — each *.md becomes a Queue item
/automate --backlog <_BACKLOG.md>                 # backlog-doc source — dependency-ordered Queue
/automate --limit N                               # cap PROCESSED items this run (default 5; full Queue still stored)
/automate --resume [<run_id>]                     # reconcile + continue a prior incomplete run
/automate --sweep [--apply]                       # run ONLY the sweep of leftover plugin worktrees/branches; dry run unless --apply
/automate ... --auto-merge                        # opt-in, default-OFF, fail-closed merge gate (conditions: skills/automate-loop/SKILL.md §10)
/automate ... --trust-unprotected                 # with --auto-merge: allow merge onto an unprotected branch (condition 4 ONLY — never overrides condition 6, the high-risk park)
/automate ... --inline-phases                     # run each item's phases inline here (default: each its own fresh session)
/automate ... --parallel N                        # opt-in lanes: up to N independent items at once, each in its own local clone; N = 1 = single-lane mode (refused with --auto-merge)
```

**Parameters:**
- `"<what>"` / `--folder <dir>` / `--backlog <doc>` — the source (choose one); bare `/automate` resumes, else asks
- `--limit N` — cap PROCESSED items this run (default 5); the FULL resolved Queue is still materialized in the run file
- `--resume [<run_id>]` — reconcile + continue a prior incomplete run (most-recent incomplete if id omitted)
- `--sweep [--apply]` — run ONLY the sweep (no RESUME, no PICK, no run file): lists leftover plugin-made worktrees and local branches with a reason; `--apply` (the owner's typed flag — no question gate) removes only those proven merged under `closeout`'s squash-safe rule, salvaging gitignored runtime content first; refused with a source or `--resume`
- `--auto-merge` — opt-in (default OFF) trusted auto-merge behind the fail-closed trusted-merge gate (conditions enumerated in `skills/automate-loop/SKILL.md` §10); the **only** place in the plugin that executes `gh pr merge --squash`. Condition 6 re-classifies the PR head with `scripts/classify-risk.sh` and parks any high-risk or unclassifiable diff — nothing overrides it
- `--parallel N` — opt-in lanes: N > 1 runs up to N independent items at once, each in its own local clone; a READY lane of an N > 1 run parks `ready_for_release` (do not merge yet — wave open); N = 1 is single-lane mode — each item runs in ONE fresh lane that parks `awaiting_merge` like a sequential item (no wave PR; needs branch mode); a lane launches only on a command the owner typed in this session; absent ⇒ unchanged (`skills/automate-loop/lanes.md`)
- `--trust-unprotected` — with `--auto-merge`: allow merge onto a branch without enforceable protection. Scoped to condition 4 ONLY; it does not override condition 6, and no flag, config key, or project file does
- `--inline-phases` — run each item's phases inline in this session (`/autonomous --single-iteration`, then the inline drain) instead of as fresh headless sessions (the default); kept for the current item only (no off form, not in `## Run Config`) — re-pass on every `--resume` / `/loop` tick
- `--notify` / `--non-interactive-fallback` — passthrough to the inner `/autonomous`

**When to Use:**
- A whole folder of requirements, a backlog doc, or a prompt that fans out into many items
- You want one item driven to a mergeable PR at a time (single-open-PR invariant), with smart crash resume

**When NOT to Use:**
- A single requirement → `/autonomous` directly
- Two concurrent `/automate` runs in one checkout (they collide on the repo-global `.auto_review` toggle) — use `--parallel N` (N = 1: single-lane mode), which runs each item in its own lane clone

**Learn More:** see `loomwright/commands/automate.md`; the protocol authority is `loomwright/skills/automate-loop/SKILL.md`, and the run-file layout is documented as `AUTOMATE_RUN` in `loomwright/docs/RESULT_SCHEMAS.md`.

---

<!-- split:begin ../docs/command-parts/agent-help/more.md -->
### 🧩 /setup — Optional-Capability Dashboard & Guided Configuration

See [../docs/command-parts/agent-help/more.md](../docs/command-parts/agent-help/more.md).

### 🩺 /review-pr — Standalone PR Review-and-Heal

See [../docs/command-parts/agent-help/more.md](../docs/command-parts/agent-help/more.md).

### QA Workflow Diagram

See [../docs/command-parts/agent-help/more.md](../docs/command-parts/agent-help/more.md).
<!-- split:end ../docs/command-parts/agent-help/more.md -->
<!-- split:begin ../docs/command-parts/agent-help/guide.md -->
## Daily Workflow Example

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Morning: Plan Your Work

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Start Work: Claim Task

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### During Work: Code & Review

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Before Committing: Create Conventional Commits

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Complete Task: Close in Beads

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

## Common Scenarios

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Scenario 1: Fix a Bug

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Scenario 2: Add a Feature

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Scenario 3: Refactor Code

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Scenario 4: Review Someone Else's Code

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Scenario 5: Pre-Launch Security Review

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Scenario 6: Stress-Test Before Scale

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

## Key Concepts

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Agent Frontmatter (Native Configuration)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Plugin Hooks (Quality Gates)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Agent Teams (Experimental)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Project Context

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Task Management

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Approval Workflow

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

## Tips & Tricks

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Tip 1: Use Agents Flexibly

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Tip 2: Combine with Git

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Tip 3: Multi-Project Workflows

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Tip 4: Review Before Committing

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Tip 5: Daily Routine

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

## Files & Directories

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Plugin Files

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Project Files

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

## Getting Help

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Need Help with a Specific Agent?

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Questions About the Plugin?

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Issues or Suggestions?

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

## Keyboard Shortcuts

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

## Summary

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Readiness Pipeline (Prepare for Autonomous Execution)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Autonomous Workflow (End-to-End Automation — 4 Roles)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Requirements Pipeline (Define What to Build)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Constructive Pipeline (Build Correctly)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### Independent Auditor (Break Safely)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).

### QA Pipeline (Test Automatically)

See [../docs/command-parts/agent-help/guide.md](../docs/command-parts/agent-help/guide.md).
<!-- split:end ../docs/command-parts/agent-help/guide.md -->
