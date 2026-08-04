---
name: supervisor-readiness
description: Pre-flight checklist, Supervisor-Ready Brief format, jobs folder convention, and failure prevention. Use before launching autonomous workflows or when diagnosing Supervisor failures.
allowed-tools: [Read, Bash]
version: "1.4.0"
lastUpdated: "2026-08-04"
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
- **Source requirement:** {repo-root-relative path to the `.supervisor/requirements/*.md` this brief was planned from — OPTIONAL; emitted only when Launch Pad resolved a requirement file at Phase 2 step 0, omitted entirely otherwise}

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

### Auto-Authoring (multi-iteration)

This is the rubric's **producer** path. When `/autonomous` runs in **multi-iteration mode** AND the requirement file has **no `## Outcomes Rubric`**, the inlined Launch Pad auto-authors one (guarded step — see `agents/launch-pad.md` Phase 5).

- Authored bullets **derive from the brief's Acceptance Criteria plus the Phase 3 codebase analysis** (file impact map), and MUST obey the **Authoring rules** above (3-7 bullets, observable, **diff-checkable from the PR diff alone**, positive assertions). *(At plan-review time no diff exists yet, so Plan Reviewer applies "diff-checkable" as a phrasing/observability heuristic — see `agents/plan-reviewer.md` Criterion 3.)*
- **Human-gated:** the authored rubric appears in the assembled brief and is surfaced for approve/edit at Launch Pad Phase 6 — never blind-written. Plan Reviewer (Phase 5.5) validates the auto-authored *draft* against these rules. Per Launch Pad's standard Phase 6 mutation rule (`agents/launch-pad.md` Phase 6), if the human edits the rubric (or any section) the prior PASS is voided and Plan Review re-runs before save (consuming an attempt from the shared 3-spawn cap) — so human edits re-enter validation rather than bypassing it; only an unedited approve-as-is skips a re-review.
- **Partly non-diff-checkable outcomes:** if some outcomes are non-diff-checkable (e.g. visual) but **3 or more diff-checkable bullets** remain, author the rubric from that diff-checkable subset and document the excluded outcomes as a prose note — do NOT pad the rubric with non-checkable bullets.
- **Degenerate-rubric fallback:** if **fewer than 3** diff-checkable bullets can be derived at all, do NOT emit a rubric — fall back to the autonomous loop's existing no-rubric gate rather than emitting a weak/degenerate rubric.
- **Freeze:** once approved, the rubric is persisted back into the requirement body by the autonomous loop (see `skills/autonomous-loop/SKILL.md`) so every later iteration scores against the same yardstick.

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

**Plugin-self authoring convention (v14.21.0):** a machine-authored brief generated by Launch Pad **on this plugin's own repo** whose change touches the **plugin doc surface** SHOULD declare both doc-surface invariants. That surface is defined authoritatively by `scripts/check-doc-currency.sh`'s `FILES` list **plus** the count sources (`agents/`/`commands/`/`skills/` dirs, `hooks/hooks.json`, `plugin.json`/`marketplace.json`) — **do NOT maintain a separate enumerated copy here**, since restating it is exactly the count/version/restated-list and cross-reference precision drift this convention guards against. In practice the doc surface includes, but is not limited to, `agents/`, `commands/`, `skills/`, `docs/`, the `.claude-plugin/` manifests + `README.md`, `CLAUDE.md`, `README.md`, and `AGENT_GUIDELINES.md` (each directory subsumes its index/help files, e.g. `skills/SKILLS_INDEX.md`, `commands/agent-help.md`); when in doubt, if `check-doc-currency.sh` scans it, the brief touches the doc surface. This is the **doc-currency** surface — distinct from `code-reviewer.md`'s review-trigger taxonomy (which additionally covers `.supervisor/jobs/**`). Declare:

```markdown
## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent
```

so Supervisor Phase 4.5 `ground_truth` executes the doc-currency and version-consistency invariants (advisory) instead of `skipped`. Both ids are plugin-bundled under `scripts/eval-corpus/`; outside this repo they do not resolve, so non-plugin briefs omit them. See `agents/launch-pad.md` Phase 5.

## Subtask Structure

**Subtask id scheme (RULE, not merely illustration):** subtask ids are **plain numeric, 1-based, sequential** (`1, 2, 3, …`) — never alpha-suffixed (`1a`/`1b`) and never any other prefixed form. Every id used in the `#` column of the table below, and every `from:` reference in the Subtask Contracts YAML, MUST use this scheme. Downstream, `loomwright/sdk-spike/src/runner.ts`'s parser tolerates legacy alpha-suffixed ids from older briefs (`normalizeSubtaskIds` maps them onto this same scheme so no `from:` edge dangles) — that tolerance is a compatibility shim for *archived* briefs, not license to author new ones with alpha suffixes.

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | LAUNCHABLE |
| 2 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | LAUNCHABLE |
| 3 | {title} | {criteria IDs} | {M} modify, {C} create | {skill refs} | BLOCKED (by #1) |

### Provides / Requires Schema (v12.0.0+)

Each subtask MUST declare a structured contract with four top-level YAML lists: `provides`, `requires`, `external_requires`, `lanes` — Plan Reviewer Criterion 12 FAILs the brief with a BLOCKING `dep_graph` issue when contract blocks are missing (only an explicit `legacy_brief: true` in the Environment section opts out). These are consumed by Plan Reviewer (Criterion 12) and Execute Manager's pre-spawn verification gate. `lanes` is documented separately below (§"Lane Declaration Schema", v15.20.0+) — it is validated by a dedicated Plan Reviewer criterion (Criterion 16), not Criterion 12.

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
lanes:
  - "src/auth/jwt.guard.ts"
  - "src/auth/types.ts"
external_requires:
  - "@nestjs/passport >= 10.0"

# Subtask 2 — Auth controller wiring up the guard + types (BLOCKED by #1)
provides:
  - {kind: "file", path: "src/auth/auth.controller.ts"}
  - {kind: "symbol", path: "src/auth/auth.controller.ts", name: "AuthController"}
requires:
  - {from: "1", kind: "symbol", path: "src/auth/jwt.guard.ts", name: "JwtAuthGuard"}
  - {from: "1", kind: "type",   path: "src/auth/types.ts",     name: "AuthContext"}
lanes:
  - "src/auth/auth.controller.ts"
external_requires: []
```

**Authoring rules:**

- Every subtask MUST declare a `provides` list (Criterion 12 BLOCKING when the contract block is absent), and it should be non-empty. Pure-deletion subtasks may use `provides: []` with a comment justifying it
- Reject vague provides like `"adds feature"` / `"updates code"` — every entry MUST be `{kind, path, name?}` addressable on disk
- `external_requires` is for things outside the brief; do NOT use it as the `from` target of any `requires` entry
- Non-empty `requires` → BLOCKED (status in Subtask Structure table MUST reflect this)

### Lane Declaration Schema (v15.20.0+)

Alongside `provides` / `requires` / `external_requires`, every subtask contract also declares a `lanes:` top-level YAML list — a flat list of repo-relative path globs the subtask **owns**:

```yaml
lanes:
  - "src/auth/jwt.guard.ts"
  - "src/auth/types.ts"
```

A subtask's declared `lanes` is the set of paths it is expected to modify/create. When a worker writes to a path matching no glob in its OWN subtask's `lanes`, that path is recorded in a new `out_of_lane` field on `WORKER_RESULT` (see `docs/RESULT_SCHEMAS.md` §"WORKER_RESULT"). The `out_of_lane` field itself, and the worker/async-orchestration seam that populates it, belong to that schema and to `agents/worker.md` — this section defines the CONTRACT the gate consumes (what a lane IS, and when a violation is a real cross-subtask collision), not the gate's own mechanics.

**The lane-collision test — reachability, not edges.** Two subtasks A and B may legally **collide** (i.e. an out-of-lane write into a sibling's lane is a flaggable divergent-interface hazard) **iff neither is reachable from the other in the `requires` DAG (transitive closure)** — i.e. the two are unordered relative to each other, so nothing guarantees one finishes before the other starts. (Do NOT restate this as "the scheduler puts them in the same wave" — see the terminology paragraph directly below for why wave membership is not a valid proxy.) **This is NOT "no direct `requires` edge between A and B."** That phrasing reads as *direct adjacency* and would falsely flag every transitively-ordered pair: two subtasks two or more waves apart via an intermediate dependency (e.g. A → B → C, so A and C share no direct edge) are still correctly ordered — C is reachable from A — and MUST NOT be flagged, even though no `requires` entry names them directly. If either subtask **is** reachable from the other, they are sequentially ordered: a shared file between them is **legal** and must not be flagged as a collision.

**Terminology — "same-wave" is a SHORTHAND for exactly this reachability condition, nothing more.** The phrase appears in Plan Reviewer Criterion 16, the seam tests, and the CHANGELOG; everywhere it appears it MEANS "mutually unreachable in the `requires` DAG." It is NOT a claim that the runtime assigns wave numbers you could compute and compare: Execute Manager's poll loop is event-driven, launching each subtask as its dependencies clear and a slot frees, so two mutually-unreachable subtasks at different chain depths can overlap in wall-clock time without ever sharing a wave index. Read "same-wave" as "unordered relative to each other"; never implement it by comparing wave numbers.

**The edge set is an assertion, not trusted input.** The `requires` graph this reachability test runs over is exactly the graph Plan Reviewer **Criterion 5** ("Dependency Correctness") validates — cycle detection, and that blocked subtasks genuinely depend on their blockers. The lane-collision check consumes that already-validated graph; it is never a guarantee independent of it. A spurious `requires` edge silences the collision check for that pair by construction — authoring a `requires` entry that isn't real is a way to defeat the check, not just a correctness bug.

**Sequential sharing grants VISIBILITY, not PRESERVATION.** A downstream subtask that legally shares (edits) a file carrying an upstream subtask's `provides` symbol is only guaranteed to be able to SEE that symbol when it starts — sequential ordering makes the file exist by the time it runs. Nothing in the existing gate re-verifies the symbol still resolves after the downstream subtask's own edit: the deterministic `outputs_verified` gate (`agents/worker.md`, `scripts/validate-worker-result.py`) checks a producer's OWN `provides` at producer time only, never that a later consumer preserved them. A subtask editing a file that carries a sibling's `provides` symbol MUST re-verify that symbol still resolves after its own edit — this is a manual authoring/review discipline, not something any existing gate automates.

**Authoring rules:**
- Every subtask with a contract block MUST declare `lanes:` (mirrors the `provides` mandate above — non-empty except for a subtask that genuinely touches nothing addressable, same `provides: []`-with-justification precedent)
- Every lane path SHOULD resolve to an existing file, OR have an existing parent directory (a legitimate create target) — validated by Plan Reviewer's dedicated lane criterion (Criterion 16)
- `lanes` entries share the SAME path space as `provides`/`requires` `path` fields — repo-relative, no leading `./`
- A same-wave lane overlap (per the reachability test above) between two MUTUALLY-UNREACHABLE subtasks is a genuine authoring defect at brief time, distinct from a worker later writing out of its own lane at runtime. (Phrased as reachability, not as "LAUNCHABLE in the same batch" — the terminology note above is explicit that batch/wave membership is not a valid proxy for this test, and this bullet must not reintroduce the framing it warns against.)

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
- **Mode:** parallel | sequential | single-agent
- **Estimated batches:** {N}
- **Base Branch:** main  # optional (v14.0.0+) — defaults to "main" when omitted. Autonomous-loop iter N+1 sets this to the parent iteration's feature branch for stacked PRs (e.g., `feature/v14-iter1`). Plan Reviewer Criterion 13 validates that the named branch exists locally (`main` always passes); a named-but-unresolvable branch FAILs the brief.
- **Split reason:** <file-conflict|context-bound|genuine-parallelism>  # optional — see `## Decomposition Threshold`; required when the brief has more than 1 subtask, omitted for a single-subtask brief

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

## Decomposition Threshold

The default is **ONE subtask**. Acceptance criteria are a **checklist for one worker to satisfy**, not a template for generating subtasks — do not decompose unless a split is justified by one of exactly three named reasons below. When a split fires, record the triggering reason verbatim in the brief's `## Configuration` block on a `- **Split reason:** <reason>` line (omitted entirely for a single-subtask brief).

**The three legal split reasons — no other reason justifies a split:**
1. `file-conflict` — two coherent work groups would edit the same file (they must serialize anyway; splitting makes the ordering explicit).
2. `context-bound` — the estimated change exceeds one worker's context: **> 12 files changed OR > 800 changed lines**.
3. `genuine-parallelism` — **≥ 2 groups with zero file overlap AND each group ≥ 3 files** (below that, the cold start costs more than the parallelism saves).

**Calibration honesty:** the numeric bounds in (2) and (3) are an **initial calibration, not a measured optimum** — set so the measured `tree-and-find` corpus entry (5 criteria, 6 files) lands single-agent. They are explicitly tunable as more data accumulates; do not present them as derived.

**Single-subtask form (below-threshold default):** `## Subtask Structure` and `## Parallelism Analysis` remain **required** sections (Plan Reviewer Criterion 9 treats their absence as BLOCKING) even when there is only one subtask — they take this reduced legal form instead of being omitted:

```markdown
## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | {title} | all | {M} modify, {C} create | {skill refs} | LAUNCHABLE |

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
```

**Single home:** this section is the sole **authority** for the threshold — tune the numbers here first. Orchestrator does not preload this skill and cites this section by path (`skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold") rather than restating the numbers.

**Derived mirror (must be updated in the SAME change when you retune a bound — nothing in CI couples them):**

| Mirror | Why it restates the numbers |
|---|---|
| `agents/plan-reviewer.md` Criterion 4 ("Cross-check the reason's PREDICATE") | Plan Reviewer does not preload this skill, and its predicate check is worthless without the concrete bounds |

These are the ONLY sanctioned **live** restatements — every other surface cites this section by path. **Release banners are exempt:** the `v15.15.0` notes in `CLAUDE.md`, `CHANGELOG.md`, and the `README.md` banner are historical snapshots of what shipped in that release and are deliberately NOT retuned (same convention as CHANGELOG entries and frozen example values). Verify after a retune with `grep -rnE "800 changed|12 files|[≥>]=? ?3 files|[≥>]=? ?2 .*group" loomwright/ README.md CLAUDE.md` — the pattern must cover **both** predicates, since `genuine-parallelism`'s bounds (≥ 2 groups, ≥ 3 files) are restated in the sanctioned mirror and in `agents/launch-pad.md`'s worked example, not just `context-bound`'s. Update only the live mirror in the table above (worked examples are illustrative and re-checked by Criterion 4, but keep them internally consistent).

## Common Failure Modes

| Failure | Cause | Prevention |
|---------|-------|------------|
| Supervisor re-does Phases 0-2 | Brief not loaded (wrong path or missing `job:` flag) | Verify path exists before handing off |
| Workers modify same files | File overlap not detected in brief | Check overlap matrix carefully, mark overlapping subtasks as BLOCKED |
| Subtask criteria too vague | Acceptance criteria not broken down per subtask | Acceptance criteria are a checklist for one worker, not a subtask generator — see `## Decomposition Threshold` |
| Work fanned out with no stated reason | Split decided without checking `## Decomposition Threshold` | Default to one subtask; split only for one of the three named reasons, recorded as `Split reason:` in `## Configuration` |
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
- [ ] Subtask count follows `## Decomposition Threshold` (default 1; split only for a named reason, recorded as `Split reason:`)
- [ ] Parallelism analysis is conservative (no false LAUNCHABLE)
- [ ] Brief follows the complete template (all 9 required sections present; Feasibility optional)
- [ ] If Phase 2.5 ran, Feasibility verdict recorded in the optional `## Feasibility` section

## See Also

- `skills/workflow-management/SKILL.md` — Supervisor workflow patterns
- `skills/async-orchestration/SKILL.md` — Parallel dispatch and git worktree lifecycle
- `skills/state-management/SKILL.md` — State file schema and checkpoint protocols
- `skills/context-setup/SKILL.md` — Project context loading
- `skills/claude-md-validation/SKILL.md` — CLAUDE.md freshness validation
