---
name: supervisor-readiness
description: Pre-flight checklist, Supervisor-Ready Brief format, jobs folder convention, and failure prevention. Use before launching autonomous workflows or when diagnosing Supervisor failures.
allowed-tools: [Read, Bash]
version: "1.1.0"
lastUpdated: "2026-05-10"
---

# Supervisor Readiness Skill

Pre-flight validation, Supervisor-Ready Brief format, and jobs folder convention for autonomous workflow execution. Ensures Supervisor starts with clean context and validated inputs.

## Quick Rules

- Run pre-flight checklist before every Supervisor launch (or use Launch Pad to automate it)
- Save briefs to `.supervisor/jobs/pending/` with `{YYYY-MM-DD}-{slug}.md` naming
- Brief must include all 9 required sections (Environment, Task, Acceptance Criteria, Subtask Structure, Parallelism Analysis, Skill References, Risk Assessment, Configuration, Handoff) — Supervisor skips Phases 0-2 when consuming a brief. The `## Feasibility` section is optional (Launch Pad v10.3+)
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
| 7 | `.supervisor/` writable | `mkdir -p .supervisor/jobs/pending` | YES — Supervisor needs state directory |
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
│   └── jobs/                 # Supervisor-Ready Briefs (lifecycle folders)
│       ├── pending/          # awaiting Supervisor pickup
│       │   ├── 2026-02-07-jwt-auth.md
│       │   └── 2026-02-08-dark-mode.md
│       ├── in-progress/      # picked up by an active session
│       ├── done/             # completed successfully
│       └── failed/           # unrecoverable failures
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
mkdir -p .supervisor/jobs/pending

# Write brief
# (Launch Pad handles this automatically)
```

### Consumption

When Supervisor receives `job: .supervisor/jobs/pending/{file}.md`:
1. Read the brief file (and move it to `.supervisor/jobs/in-progress/` on pickup)
2. Skip Phase 0 (INIT) environment validation — already done by Launch Pad
3. Skip Phase 1 (ACQUIRE) requirement refinement — criteria already defined
4. Pre-populate Phase 2 (PLAN) with subtask hints and parallelism analysis
5. Begin Phase 3 (EXECUTE) with enriched context — planning phases are pre-answered by the brief

### Cleanup

After Supervisor completes successfully:
- Brief file is moved to `.supervisor/jobs/done/` (or `failed/` on unrecoverable errors) by the Supervisor's completion tail and remains there for reference
- Supervisor does NOT delete the brief
- User can manually clean up old consumed briefs:
  ```bash
  # Remove consumed briefs older than 30 days (never touch pending/)
  find .supervisor/jobs/done .supervisor/jobs/failed -name "*.md" -mtime +30 -delete 2>/dev/null
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

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | {GO/CAUTION/NO-GO} | {explanation} |
| 2 | Dependency Availability | {GO/CAUTION/NO-GO} | {explanation} |
| 3 | Architecture Fit | {GO/CAUTION/NO-GO} | {explanation} |
| 4 | Scope vs Supervisor Capability | {GO/CAUTION/NO-GO} | {explanation} |
| 5 | Hard Blockers | {GO/CAUTION/NO-GO} | {explanation} |

**Overall Verdict:** {GO | CAUTION | NO-GO (user override)}

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

## Outcomes Rubric (optional — v12.2.0+)

3-7 observable, testable assertion bullets the integrated PR diff must satisfy. Used by Supervisor Phase 4.5 (after Code Reviewer PASS) to spawn a Haiku grader that scores the PR against each item, emitting `rubric_score: N/M` in SUPERVISOR_RESULT.

**Authoring rules:**
- 3-7 bullets, no fewer no more
- Each bullet is a single, observable, testable assertion (not prose, not narrative)
- Each bullet should be evaluable from the PR diff alone (no external state, no manual steps)
- Phrase as positive assertions ("X is present", "Y references Z"), not aspirations ("X should be nice")
- The section is **optional**. Briefs without it work exactly as before — Supervisor emits `rubric_score: null`

**Positive example:**

```markdown
## Outcomes Rubric
- The new `JwtAuthGuard` class is exported from `src/auth/jwt.guard.ts` and decorated with `@Injectable()`.
- `auth.module.ts` registers `JwtAuthGuard` in its `providers` array.
- A spec file `src/auth/jwt.guard.spec.ts` exists and contains at least one `expect(...)` assertion.
- The PR description does not mention TODO, FIXME, or "deferred".
- No file outside `src/auth/` is modified.
```

## Executable Acceptance (optional — System Twin / M2b, v14.19.0+)

A list of project-declared **executable acceptance checks** the run must satisfy. Used by Supervisor Phase 4.5 (after the Code Reviewer loop) — `scripts/run-ground-truth.sh` resolves this section and runs each check, folding the result into the **advisory** `ground_truth` signal on `SUPERVISOR_RESULT`. It never changes `heal_decision` and never blocks the PR. The section is **optional**; briefs without it work exactly as before (`ground_truth.status: skipped`). Each `- ` bullet is one of:

- `corpus-task: <id>` — runs `scripts/eval-corpus/<id>/check.sh` (sandbox-constrained: `<id>` is a single path segment that cannot escape `eval-corpus/`). **The only kind a machine-authored brief may emit.** `<id>` references a **plugin-bundled** corpus task (resolved against the plugin's own `scripts/eval-corpus/`, e.g. `version-consistent`), NOT a path in the user's project — so outside this plugin's own repo a machine-authored brief will usually omit this section entirely (no matching bundled id exists).
- `qa-executor: <target>` — recognized but DEFERRED to M2b slice 1b (records `unverified`; spawns nothing).
- `cmd: <shell>` (or a bare bullet) — an arbitrary shell command run as `bash -c` with **full shell privileges**.

**Authoring rule (machine-authored-brief convention — trust boundary):**

- A **machine-authored** brief (Launch Pad, especially under `/autonomous`, where no human reviews the brief at Plan Review) **MUST NOT emit `cmd:` / bare-shell bullets.** Emit only `corpus-task:` bullets when executable acceptance can be derived at all.
- `cmd:` bullets are reserved for **human authorship**, where the person editing the requirement/brief is the trust anchor and reviews the command themselves.
- Rationale: on the unattended/`--non-interactive` path Supervisor passes `run-ground-truth.sh --no-cmd`, so a machine-authored `cmd:` bullet would be skipped (`unverified`, reason `cmd_disabled`) and never run — it is both dead-on-arrival there and a latent risk if that valve ever regressed. Plan Reviewer **Criterion 14** surfaces any `cmd:` bullet that appears in a brief (LOW/advisory today; escalates at M3).
- See `scripts/run-ground-truth.sh`, `docs/RESULT_SCHEMAS.md` §"`## Executable Acceptance`", and `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md §7`.

**Example (machine-authored — `corpus-task:` only):**

```markdown
## Executable Acceptance
- corpus-task: version-consistent
```

**Plugin-self authoring convention (v14.21.0):** a machine-authored brief generated by Launch Pad **on this plugin's own repo** whose change touches the **plugin doc surface** SHOULD declare both doc-surface invariants. That surface is defined authoritatively by `scripts/check-doc-currency.sh`'s `FILES` list **plus** the count sources (`agents/`/`commands/`/`skills/` dirs, `hooks/hooks.json`, `plugin.json`/`marketplace.json`) — **do NOT maintain a separate enumerated copy here**, since restating it is the count/cross-ref drift this convention guards against. In practice the doc surface includes, but is not limited to, `agents/`, `commands/`, `skills/`, `docs/`, the `.claude-plugin/` manifests + `README.md`, `CLAUDE.md`, `README.md`, and `AGENT_GUIDELINES.md` (each directory subsumes its index/help files, e.g. `skills/SKILLS_INDEX.md`, `commands/agent-help.md`); when in doubt, if `check-doc-currency.sh` scans it, the brief touches the doc surface. This is the **doc-currency** surface — distinct from `code-reviewer.md`'s review-trigger taxonomy (which additionally covers `.supervisor/jobs/**`). Declare:

```markdown
## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent
```

so Supervisor Phase 4.5 `ground_truth` executes the doc-currency and version-consistency invariants (advisory) instead of `skipped`. Both ids are plugin-bundled under `scripts/eval-corpus/`; outside this repo they do not resolve, so non-plugin briefs omit them. See `agents/launch-pad.md` Phase 5.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | LAUNCHABLE |
| 2 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | LAUNCHABLE |
| 3 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | BLOCKED (by #1) |

### Provides / Requires Schema (v12.0.0+)

Each subtask MUST declare a structured contract with three top-level YAML lists: `provides`, `requires`, `external_requires` — Plan Reviewer Criterion 12 FAILs the brief with a BLOCKING `dep_graph` issue when contract blocks are missing (only an explicit `legacy_brief: true` in the Environment section opts out). These are consumed by Plan Reviewer (Criterion 12) and Execute Manager's pre-spawn verification gate.

**`provides` items** — addressable outputs the subtask must produce:

- `{kind: "file", path: "<relative-path>"}` — file that must exist after the subtask completes
- `{kind: "symbol", path: "<relative-path>", name: "<identifier|heading|frontmatter-key>"}` — named identifier, heading, or frontmatter field present in that file
- `{kind: "type", path: "<relative-path>", name: "<TypeName>"}` — TypeScript / language-level type defined in that file

**`requires` items** — outputs that a sibling subtask must produce first:

- `{from: "<sibling-subtask-id>", kind: "file"|"symbol"|"type", path: "<path>", name: "<name>"}`

**`external_requires`** — top-level list of free-text strings naming things outside the brief's scope (third-party APIs, OS-level CLIs, undocumented platform features). NOT cross-referenced from `requires`.

**Status implication:** A subtask is **BLOCKED** iff its `requires` list is non-empty. Empty `requires` + no file overlap = LAUNCHABLE.

**Complete example** — two subtasks where Subtask 2 requires outputs from Subtask 1:

```yaml
# Subtask 1 — JWT guard + auth types (LAUNCHABLE)
provides:
  - {kind: "file", path: "src/auth/jwt.guard.ts"}
  - {kind: "symbol", path: "src/auth/jwt.guard.ts", name: "JwtAuthGuard"}
  - {kind: "file", path: "src/auth/types.ts"}
  - {kind: "type", path: "src/auth/types.ts", name: "AuthContext"}
requires: []
external_requires:
  - "@nestjs/passport >= 10.0"

# Subtask 2 — Auth controller wiring up the guard + types (BLOCKED by #1)
provides:
  - {kind: "file", path: "src/auth/auth.controller.ts"}
  - {kind: "symbol", path: "src/auth/auth.controller.ts", name: "AuthController"}
requires:
  - {from: "1", kind: "symbol", path: "src/auth/jwt.guard.ts", name: "JwtAuthGuard"}
  - {from: "1", kind: "type",   path: "src/auth/types.ts",     name: "AuthContext"}
external_requires: []
```

**Authoring rules:**

- Every subtask MUST declare a `provides` list (Criterion 12 BLOCKING when the contract block is absent), and it should be non-empty. Pure-deletion subtasks may use `provides: []` with a comment justifying it
- Reject vague provides like `"adds feature"` / `"updates code"` — every entry MUST be `{kind, path, name?}` addressable on disk
- `external_requires` is for things outside the brief; do NOT use it as the `from` target of any `requires` entry
- Non-empty `requires` → BLOCKED (status in Subtask Structure table MUST reflect this)

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
- **Base Branch:** main  # optional (v14.0.0+) — defaults to "main" when omitted. Autonomous-loop iter N+1 sets this to the parent iteration's feature branch for stacked PRs (e.g., `feature/v14-iter1`). Plan Reviewer Criterion 13 validates that the named branch exists locally (`main` always passes); a named-but-unresolvable branch FAILs the brief.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/{date}-{slug}.md
```
```

### Section Requirements

**9 required sections** (mandatory — Supervisor relies on them) plus **optional sections**: `Feasibility` (Launch Pad v10.3+, in the table below), `Outcomes Rubric` (v12.2.0+) and `Executable Acceptance` (v14.19.0+) — the latter two are documented in their own blocks above and omitted from the table below:

| Section | Required? | Used In Phase | Purpose |
|---------|-----------|---------------|---------|
| Environment | required | Phase 0 (skip) | Validates pre-flight was done |
| Feasibility | **optional** | Phase 0 (skip) | Records Launch Pad Phase 2.5 verdict. Absent from pre-v10.3 briefs — not required |
| Task | required | Phase 1 (skip) | Task description and problem context |
| Acceptance Criteria | required | Phase 1 (skip) | What "done" means |
| Subtask Structure | required | Phase 2 (pre-populate) | Work breakdown |
| Parallelism Analysis | required | Phase 2 (pre-populate) | Which subtasks can run concurrently |
| Skill References | required | Phase 3 (workers) | Skills to inject into each worker |
| Risk Assessment | required | Phase 3 (workers) | Known issues to watch for |
| Configuration | required | Phase 0 (skip) | Worker count, mode |
| Handoff | required | — | User-facing command to start execution |

### Base Branch field (Configuration block — v14.0.0+)

The `Base Branch:` line in `## Configuration` is **optional** and defaults to `main` when omitted. Its presence signals to Supervisor that the FINALIZE PR should target a non-default base — used by the `/autonomous` loop's multi-iteration mode (see `skills/autonomous-loop/SKILL.md`) to stack iteration N+1's PR on iteration N's feature branch.

**Validation:** Plan Reviewer's Criterion 13 (see `agents/plan-reviewer.md`) validates the field when present:

- Absent → defaults to `main`, no validation
- Value `main` → PASS (no further check)
- Value `<branch>` → check `.git/refs/heads/<branch>` and `.git/packed-refs`; FAIL with `category: missing_field` if neither resolves the branch locally

**Supervisor behavior:** Phase 0 INIT echoes `BASE_BRANCH` prominently for cross-phase recall; Phase 4 FINALIZE passes `--base "$BASE_BRANCH"` to `gh pr create` and self-verifies the created PR's `baseRefName` matches; Phase 4.5 closes the PR and emits `status: failed, error: "base_branch_mismatch:..."` on mismatch (see `agents/supervisor.md` Phase 4 + Phase 4.5).

**Pre-v14 briefs:** Briefs created before v14.0.0 do not include this field. They continue to work unchanged — Supervisor treats them as `Base Branch: main`.

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
- [ ] Brief follows the complete template (all 9 required sections present; Feasibility optional)
- [ ] If Phase 2.5 ran, Feasibility verdict recorded in the optional `## Feasibility` section

## See Also

- `skills/workflow-management/SKILL.md` — Supervisor workflow patterns
- `skills/async-orchestration/SKILL.md` — Parallel dispatch and git worktree lifecycle
- `skills/state-management/SKILL.md` — State file schema and checkpoint protocols
- `skills/context-setup/SKILL.md` — Project context loading
- `skills/claude-md-validation/SKILL.md` — CLAUDE.md freshness validation
