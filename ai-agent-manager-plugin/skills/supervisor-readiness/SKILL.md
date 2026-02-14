---
name: supervisor-readiness
description: Pre-flight checklist, Supervisor-Ready Brief format, jobs folder convention, and failure prevention. Use before launching autonomous workflows or when diagnosing Supervisor failures.
allowed-tools: [Read, Bash]
---

# Supervisor Readiness Skill

Pre-flight validation, Supervisor-Ready Brief format, and jobs folder convention for autonomous workflow execution. Ensures Supervisor starts with clean context and validated inputs.

## Quick Rules

- Run pre-flight checklist before every Supervisor launch (or use Launch Pad to automate it)
- Save briefs to `.supervisor/jobs/` with `{YYYY-MM-DD}-{slug}.md` naming
- Brief must include all 8 sections — Supervisor skips Phases 0-2 when consuming a brief
- Conservative parallelism: only mark LAUNCHABLE if zero file overlap AND zero dependencies
- Clean up consumed briefs after successful Supervisor completion

## When to Use This Skill

- Before launching `/supervisor` for complex tasks
- When Launch Pad prepares a Supervisor-Ready Brief
- When Supervisor fails and you need to diagnose why
- When resuming a failed Supervisor session
- When manually creating a brief without Launch Pad

## Pre-Flight Checklist

Run these 8 checks before launching Supervisor:

| # | Check | How to Verify | Blocker? |
|---|-------|---------------|----------|
| 1 | CLAUDE.md exists | `ls CLAUDE.md` | YES — Supervisor needs project context |
| 2 | CLAUDE.md is fresh | Compare patterns vs actual code (see `skills/claude-md-validation/SKILL.md`) | WARNING — stale patterns cause wrong decisions |
| 3 | Git state is clean | `git status --porcelain` (empty = clean) | WARNING — dirty state risks lost work |
| 4 | On expected branch | `git branch --show-current` | WARNING — wrong branch = wrong base |
| 5 | No orphaned worktrees | `git worktree list` (only main entry) | WARNING — orphans block new worktrees |
| 6 | GitHub CLI authenticated | `gh auth status` | WARNING — PR creation will fail |
| 7 | `.supervisor/` writable | `mkdir -p .supervisor/jobs` | YES — Supervisor needs state directory |
| 8 | Disk space adequate | `df -h .` (>1GB free) | YES — worktrees need space |

**Decision:**
- 0 blockers + 0 warnings → Ready to launch
- 0 blockers + N warnings → Ready with caveats (list them)
- Any blockers → NOT ready (provide fix instructions)

## Jobs Folder Convention

### Location

```
{project}/
├── .supervisor/
│   ├── state.md              # Active session state
│   ├── history/              # Completed session summaries
│   └── jobs/                 # Supervisor-Ready Briefs
│       ├── 2026-02-07-jwt-auth.md
│       ├── 2026-02-08-dark-mode.md
│       └── ...
```

### Naming Convention

```
{YYYY-MM-DD}-{slug}.md
```

- **Date:** ISO format, date the brief was created
- **Slug:** Lowercase, hyphens, max 40 characters, derived from goal
- **Examples:**
  - `2026-02-08-jwt-auth.md`
  - `2026-02-08-fix-mobile-login.md`
  - `2026-02-08-add-order-history.md`

### Creation

```bash
# Create jobs directory (idempotent)
mkdir -p .supervisor/jobs

# Write brief
# (Launch Pad handles this automatically)
```

### Consumption

When Supervisor receives `job: .supervisor/jobs/{file}.md`:
1. Read the brief file
2. Skip Phase 0 (INIT) environment validation — already done by Launch Pad
3. Skip Phase 1 (ACQUIRE) requirement refinement — criteria already defined
4. Pre-populate Phase 2 (PLAN) with subtask hints and parallelism analysis
5. Begin Phase 3 (EXECUTE) with enriched context (~200 tokens instead of ~700)
6. Context savings: ~500 tokens freed for execution phases

### Cleanup

After Supervisor completes successfully:
- Brief file remains in `.supervisor/jobs/` for reference
- Supervisor does NOT delete the brief
- User can manually clean up old briefs:
  ```bash
  # Remove briefs older than 30 days
  find .supervisor/jobs -name "*.md" -mtime +30 -delete
  ```

### Gitignore

The `.supervisor/` directory should be gitignored (Supervisor auto-adds this):
```
# .gitignore
.supervisor/
```

## Supervisor-Ready Brief Template

```markdown
# Supervisor Job: {goal}

## Environment
- **Project:** {absolute path}
- **CLAUDE.md:** ✓ Found ({fresh|stale})
- **Git:** {clean|dirty} ({N} files), branch: {branch}
- **GitHub CLI:** ✓ Authenticated | ⚠ Not authenticated
- **Blockers:** {count} | **Warnings:** {count}

## Task
**Goal:** {refined goal statement — one clear sentence}

**Problem Statement:**
{who} needs {what} because {why}.
Currently, {current state}. This causes {pain/cost}.
Success looks like {measurable outcome}.

## Acceptance Criteria
- [ ] Given {precondition}, when {action}, then {outcome}
- [ ] Given {precondition}, when {action}, then {outcome}
- [ ] ...

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | LAUNCHABLE |
| 2 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | LAUNCHABLE |
| 3 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | BLOCKED (by #1) |

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 2 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | `src/auth/module.ts` | YES |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel)
- **Batch 2:** Subtask 3 (after Subtask 1)
- **Recommended workers:** {N}
- **Estimated batches:** {N}

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/{name}/SKILL.md` |
| 2 | `skills/{name}/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| {risk description} | HIGH/MEDIUM/LOW | {how to mitigate} |

## Configuration
- **Workers:** {recommended count}
- **Mode:** parallel | sequential
- **Estimated batches:** {N}

## Handoff
```
/supervisor job: .supervisor/jobs/{date}-{slug}.md
```
```

### Section Requirements

Every section is **mandatory**. Supervisor relies on:

| Section | Used In Phase | Purpose |
|---------|---------------|---------|
| Environment | Phase 0 (skip) | Validates pre-flight was done |
| Task | Phase 1 (skip) | Task description and problem context |
| Acceptance Criteria | Phase 1 (skip) | What "done" means |
| Subtask Structure | Phase 2 (pre-populate) | Work breakdown |
| Parallelism Analysis | Phase 2 (pre-populate) | Which subtasks can run concurrently |
| Skill References | Phase 3 (workers) | Skills to inject into each worker |
| Risk Assessment | Phase 3 (workers) | Known issues to watch for |
| Configuration | Phase 0 (skip) | Worker count, mode |
| Handoff | — | User-facing command to start execution |

## Common Failure Modes

| Failure | Cause | Prevention |
|---------|-------|------------|
| Supervisor re-does Phases 0-2 | Brief not loaded (wrong path or missing `job:` flag) | Verify path exists before handing off |
| Workers modify same files | File overlap not detected in brief | Check overlap matrix carefully, mark overlapping subtasks as BLOCKED |
| Subtask criteria too vague | Acceptance criteria not broken down per subtask | Map each criterion to exactly one subtask |
| Worker confused by scope | Subtask has too many files or mixed concerns | Keep subtasks focused: one module/domain per subtask |
| Parallelism overestimated | Dependencies missed or file overlap ignored | Conservative: when in doubt, mark as BLOCKED |
| Environment changed between brief and execution | Time gap between Launch Pad and Supervisor | Re-validate environment in Supervisor Phase 0 (quick check) |
| Brief is stale | Created days ago, codebase changed | Include creation timestamp, Supervisor warns if >24h old |
| Disk space exhausted | Too many parallel worktrees | Recommend max 3 workers; check disk in pre-flight |

## Parallelism Optimization Tips

1. **One module per subtask:** Group files by domain/module, not by file type
2. **Tests with their code:** Include test files in the same subtask as the code they test
3. **Shared files serialize:** If two subtasks touch the same file, they MUST serialize
4. **Config files are tricky:** `package.json`, `tsconfig.json`, `.env` modifications often overlap — serialize subtasks that modify these
5. **Database migrations:** Always sequential — never parallelize migration creation
6. **Interface-first:** If subtask B uses types from subtask A, B is BLOCKED by A
7. **Max 3 workers:** Diminishing returns beyond 3; context overhead increases

## Quality Checklist

Before saving a brief:
- [ ] All 8 pre-flight checks passed (or warnings acknowledged)
- [ ] Goal is a single clear sentence
- [ ] Acceptance criteria are testable (Given/When/Then)
- [ ] Every file path in impact map has been verified to exist (or marked as "create")
- [ ] Subtasks are 3-7 items, each 30-60 min scope
- [ ] Parallelism analysis is conservative (no false LAUNCHABLE)
- [ ] Brief follows the complete template (all 8 sections present)

## See Also

- `skills/workflow-management/SKILL.md` — Supervisor workflow patterns
- `skills/async-orchestration/SKILL.md` — Parallel dispatch and git worktree lifecycle
- `skills/state-management/SKILL.md` — State file schema and checkpoint protocols
- `skills/context-setup/SKILL.md` — Project context loading
- `skills/claude-md-validation/SKILL.md` — CLAUDE.md freshness validation
