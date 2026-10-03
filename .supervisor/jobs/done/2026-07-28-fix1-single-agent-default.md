# Supervisor Job: Fix 1 — Single-agent default + fan-out threshold (D3)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — v15.14.0 banner matches plugin.json)
- **Git:** clean, branch: main @ 7dbca4b
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/final-state/01-fix1-single-agent-default.md
- **Created:** 2026-07-28

## Feasibility
**Verdict: CAUTION** (Phase 2.5 — proceeded; findings carried into Risk Assessment)
1. Tech stack — markdown prompt surfaces + bash CI validators. Native. GO.
2. Dependencies — none added. GO.
3. Architecture fit — this IS the plugin's execution-model surface; `FINAL_STATE_GOAL.md:34` D3 is the standing owner decision. GO.
4. Scope vs Supervisor — decomposable into 6 subtasks of 30–60 min. CAUTION: ~60 edit sites across ~25 files.
5. Hard blockers — none. CAUTION ×3 recorded as risks R1/R2/R3 below.

## Task
**Goal:** Invert the plugin's decomposition default so ONE subtask is the default and fan-out is the stated exception above a written threshold, and add a true single-agent execution path (one worker does all criteria in one context, then ONE integrated review).

**Problem (verified, every citation read at plan time):** three rules combine to guarantee fan-out with nothing opposing them —
- `skills/supervisor-readiness/SKILL.md:359` *"Map each criterion to exactly one subtask"* — acceptance criteria **manufacture** subtasks.
- `agents/orchestrator.md:45,54,81,91,155,156,157,187,195,207,208,398` — mandatory paired code-review subtask, restated **12×** — **doubles** whatever the above produced. (The cited authority `EVAL_FINDINGS_AND_FIXES.md:56` says "stated 5×"; re-counted at plan time by anchor-phrase grep, the true figure is 12. See Subtask 2 for the phrase list and the grep that finds them.)
- `agents/supervisor.md:216,253` — the fast path fires only `If ≤ 1 subtask OR --sequential`, so it is **unreachable** for any multi-criterion requirement.

Measured cost: **6.4× the dollar cost and ~4× wall clock vs bare Claude for the same 0-defect outcome** (`FABLE_PARITY_EVAL.md` arm 1 $9.70 / arm 2 $61.76, both `post_merge_defects: 0`). No phase anywhere asks "could one agent do this?" — verified absent by grep (`EVAL_FINDINGS_AND_FIXES.md:65-69`).

**`--sequential` does NOT fix it** — the fast-path body still spawns one worker + one reviewer per subtask (`agents/supervisor.md:253-259`); it skips worktrees and the Execute Manager, not the cold starts. **There is currently no mode in the plugin that reads the codebase once and completes the job in one context** — confirmed at plan time; the closest existing construct is Phase 4.5, which is a post-merge integrated review, not an execution path.

**Authority:** `docs/SPIKES/FINAL_STATE_GOAL.md:34` (D3) and `docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md:45-103` (Fix 1 (a)(b)(c)). Where this brief and the goal file disagree, the goal file wins.

## Acceptance Criteria
- [ ] Given a multi-criterion requirement with no stated split reason, when Launch Pad or Orchestrator decomposes it, then the result is **exactly 1 subtask** end-to-end (and Plan Reviewer PASSes that brief).
- [ ] Given a brief with 1 subtask, when Supervisor runs Phase 3, then **one worker executes all acceptance criteria in one context and NO per-subtask Code Reviewer is spawned** — the Phase 4.5 holistic review is the single review of the integrated result.
- [ ] Given a decomposition decision, when the threshold's inputs are consulted, then they are **written in exactly one place** and both Launch Pad and Orchestrator **cite that place by path**.
- [ ] Given a brief that splits into >1 subtask, when Plan Reviewer validates it, then a brief with **no recorded split reason FAILs**, and a brief with one **PASSes**.
- [ ] Given the above-threshold path, when the existing multi-subtask flow runs, then behavior is **unchanged** (worktrees, Execute Manager, per-subtask review, `outputs_verified` gate all intact) and all CI gates stay green.
- [ ] Given the change lands, when every restating surface is checked, then agent prompts, command mirrors, skills, and root docs all state the new default consistently (no surface still asserting "3-7 subtasks" as the default or "every task gets a review subtask" unconditionally).

## Outcomes Rubric
- Decomposition default inverted with stated-reason rule
- True single-agent path exists and is the default below threshold
- Threshold documented + cited by both deciding agents
- All restating surfaces synced in the same PR

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Pinned design decisions (load-bearing — do NOT re-litigate; a worker that disagrees must escalate, not improvise)

**D-a. The threshold's single home is `skills/supervisor-readiness/SKILL.md`, in a NEW top-level section `## Decomposition Threshold`.** Chosen over `docs/ARCHITECTURE_CONTRACTS.md` because supervisor-readiness (i) already owns the brief template and the exact failure-mode row being replaced, and (ii) is preloaded by Launch Pad **and** Supervisor via frontmatter, so the rule is in-context at the moment of the decision. Orchestrator does NOT preload it and therefore **cites it by path**. ARCHITECTURE_CONTRACTS gets **no mirror copy** of the threshold — a second copy is exactly the drift this repo keeps paying for.

**D-b. The default is ONE subtask. A split requires a stated reason recorded in the brief.** Exactly three legal reasons; the brief records the triggering one verbatim on a new `- **Split reason:** <reason>` line in `## Configuration` (omitted when the brief is single-subtask):
1. `file-conflict` — two coherent work groups would edit the same file (they must serialize anyway; splitting makes the ordering explicit and is the isolation insurance Fix 1(c) preserves).
2. `context-bound` — the estimated change exceeds one worker's context: **> 12 files changed OR > 800 changed lines**.
3. `genuine-parallelism` — **≥ 2 groups with zero file overlap AND each group ≥ 3 files** (below that, the cold start costs more than the parallelism saves).

**Calibration honesty (state this in the section, do not hide it):** the numeric bounds in (2) and (3) are an **initial calibration**, not a measured optimum — they are set so the measured `tree-and-find` corpus entry (5 criteria, 6 files) lands single-agent, and are explicitly tunable. Record them as such; do not present them as derived.

**D-c. Below the threshold, the per-subtask Code Reviewer spawn is DROPPED — not the Phase 4.5 review.** The single-agent path is: one worker (all criteria, one context) → deterministic gate (`outputs_verified`, `agents/execute-manager.md:222`, plus tests/lint/LSP on the branch — all zero-token) → Phase 4 FINALIZE → **Phase 4.5 holistic Code Reviewer = the one review**. This is the whole of the review change permitted here. **Explicit scope boundary:** do NOT touch the CI-review lens, the until-mergeable drain, `--multi-voter-heal`, or the Phase 4.5 loop's own structure — that is final-state item 04 (Fix 7 / D4). A worker tempted to "also fix the drain" must stop.

**D-d. Above the threshold NOTHING changes.** Worktrees, Execute Manager, per-subtask workers and reviewers, the parallelism graph, `--max-workers`, `--sequential` all keep byte-identical behavior. This is a threshold, not a removal (Fix 1(c)).

**D-e. `--sequential` keeps its current meaning** (no worktrees, serial execution) and is NOT redefined as the single-agent path. The single-agent path is selected by subtask count, not by that flag.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Threshold authority + brief template | AC-3 | 1 modify, 0 create | `skills/supervisor-readiness/SKILL.md` | LAUNCHABLE |
| 2 | Deciding agents (Launch Pad + Orchestrator) | AC-1 | 2 modify, 0 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |
| 3 | Single-agent execution path (Supervisor) | AC-2, AC-5 | 3 modify, 0 create | `skills/async-orchestration/SKILL.md` | BLOCKED (by #1) |
| 4 | Plan Reviewer criteria | AC-4 | 1 modify, 0 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |
| 5 | Command mirrors + root docs | AC-6 | 7 modify, 0 create | — | BLOCKED (by #2,#3,#4) |
| 6 | Token budgets + version + stale spike notes | AC-5, AC-6 | 10 modify, 0 create | — | BLOCKED (by #5) |

### Subtask 1 — Threshold authority + brief template (LAUNCHABLE)

Scope: `loomwright/skills/supervisor-readiness/SKILL.md` ONLY.
- Add top-level `## Decomposition Threshold` per D-b (default one, three named reasons, the calibration-honesty note, and the `Split reason:` recording rule).
- Replace the `:359` failure-mode row Prevention cell *"Map each criterion to exactly one subtask"* with the inverted rule (acceptance criteria are a **checklist for one worker**, not a subtask generator) and add a row for the new failure mode (*"Work fanned out with no stated reason"*).
- Update the `:383` quality-checklist line `- [ ] Subtasks are 3-7 items, each 30-60 min scope` to the threshold form.
- `## Configuration` template (`:310-314`): add the optional `- **Split reason:** <file-conflict|context-bound|genuine-parallelism>` line and a `single-agent` value for `- **Mode:**`.
- `## Subtask Structure` (`:220`) and `## Parallelism Analysis` (`:276`) stay **required sections** (Plan Reviewer Criterion 9 treats absence as BLOCKING — do not remove them); document the legal single-subtask form: a one-row table, and a Parallelism Analysis reading `single-agent (no fan-out)` with `Recommended workers: 1`.

```yaml
provides:
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Decomposition Threshold"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "Split reason:"}
requires: []
external_requires: []
```

### Subtask 2 — Deciding agents (BLOCKED by #1)

Scope: `loomwright/agents/launch-pad.md`, `loomwright/agents/orchestrator.md` ONLY.
- launch-pad `:197,198` (Phase 2.5 scope check), `:356-368` (Phase 4 DECOMPOSE, incl. the `:362` *"one per file group"* manufacturing line), `:849` quality checklist, and the `:760-773` worked example: invert to the threshold, **citing `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" by path**.
- orchestrator: invert the 3 sizing lines (`:154,189,204` — *"Create 3-7 focused implementation tasks"*, *"Minimal tasks: … 3-7 tasks typical"*, *"Task breakdown is minimal (3-7 tasks…)"*) and reduce the **12** paired-review restatements to the threshold-conditional form — mandatory review **above** the threshold; below it, the Phase 4.5 integrated review is the gate. Cite the threshold by path.

  **Find them by anchor phrase, not by line number** (this repo's recurring `absolute-line-ref drift` defect: an edit that inserts a line above invalidates every later pointer, including your own). `grep -n "review subtask\|Review subtask\|mandatory code review\|Review gates are mandatory\|Code Review (SUBTASK"` returns all 12. Line numbers below are a **hint at authoring time (2026-07-28), not an anchor**:
  `:45` *"Review gates are mandatory in BOTH modes"* · `:54` *"Built-in quality gates: Every task includes mandatory code review subtask"* · `:81` *"Review is mandatory: Every implementation has a review subtask"* · `:91` *"Each implementation task automatically has a review subtask that blocks the next task"* · `:155` *"REQUIRED: Each task gets a review subtask"* · `:156` *"Each subtask: Code Review (SUBTASK type, blocks next task)"* · `:157` *"Review subtask uses `skills/quality-checklist/SKILL.md` criteria"* · `:187` *"Review is mandatory: Every implementation task must have a review subtask"* · `:195` *"Block on review: Review subtask blocks next task"* · `:207` *"Every implementation task has a review subtask (depends_on)"* · `:208` *"Review subtask uses the quality-checklist skill criteria"* · `:398` *"Review subtasks block next tasks (quality gates)"`.

  **Two corrections to the cited authority, verified at plan time — do not propagate the old numbers:** (i) `EVAL_FINDINGS_AND_FIXES.md:56` says the rule is *"stated 5×"* at `:54,81,155,156,187` — the true count is **12**; (ii) an earlier draft of this brief cited `:196`, which is *"Blockers explicit: Flag any external blockers upfront"* and is **unrelated to review** — the real restatement is `:195`. `:157` and `:398` were missed by both.
- **Net-reductive requirement:** orchestrator.md has only **299 proxy tokens** of budget headroom (~1.2 KB). Collapsing 10 restatements into 1–2 lines must leave the file **no larger than today**. Verify with `bash scripts/check-token-budget.sh` before finishing; if it still breaches, STOP and report — do not raise the budget from this subtask (that is #6's file).

```yaml
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "Decomposition Threshold"}
  - {kind: "symbol", path: "loomwright/agents/orchestrator.md", name: "Decomposition Threshold"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Decomposition Threshold"}
external_requires: []
```

### Subtask 3 — Single-agent execution path (BLOCKED by #1)

Scope: `loomwright/agents/supervisor.md`, `loomwright/skills/async-orchestration/SKILL.md`, `loomwright/skills/workflow-management/SKILL.md` ONLY.
- `agents/supervisor.md:216` and `:251-260`: today `If ≤ 1 subtask OR --sequential` runs a per-subtask worker→reviewer loop. Split this into **two** named paths: **Single-Agent Path** (1 subtask — one worker executes ALL acceptance criteria in one context; **no per-subtask Code Reviewer spawn**; deterministic gate only) and **Sequential Path** (`--sequential` with >1 subtask — unchanged, keeps its per-subtask reviewer). Per D-e, `--sequential` is NOT the single-agent path.
- Update the mode strings (`:229`, `:324`) to carry `single-agent`, and the spawn-table rows (`:623-624`, `:638-639`) to say the fast-path Code Reviewer runs on the Sequential path only.
- `async-orchestration/SKILL.md:68-72` (Fast-Path), `:520` checklist, and the verbatim spawn contracts at `:723` (Worker) / `:754` (Code Reviewer): add the single-agent Worker contract — the worker receives ALL acceptance criteria, not one subtask's row — and scope the fast-path Reviewer contract to the Sequential path.
- `workflow-management/SKILL.md:61-62`: update the phase-transition guidance.
- **Preserve every pinned field name** — `check-contract-parity.sh` greps `agents/*.md` for hook-required result-block field names (`subtasks_completed`, `merge_order`, `worktrees`, …) and fails closed if the last mention disappears. Do not introduce a new bare `status: <token>` literal in `supervisor.md` outside the allowlist.
- **`skills/async-orchestration/SKILL.md` is preloaded by Supervisor** — growth charges the `supervisor` budget (2857 headroom, comfortable, but check).

```yaml
provides:
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "Single-Agent Path"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "Single-Agent Path"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Decomposition Threshold"}
external_requires: []
```

### Subtask 4 — Plan Reviewer criteria (BLOCKED by #1)

Scope: `loomwright/agents/plan-reviewer.md` ONLY. **This subtask is what makes the new default reviewable at all** — today Criterion 4 mechanically FAILs any brief with fewer than 3 subtasks, so without it every single-agent brief is rejected.
- Criterion 4 (`:101-110`): replace `Count subtasks (reject < 3 or > 7)` with the inverted check — **1 subtask is valid and expected**; a brief with >1 subtask and **no `Split reason:`** in `## Configuration` FAILs; severity HIGH. Keep the >7 upper bound.
- Criterion 6 Parallelism Safety (`:123-128`): make the LAUNCHABLE-pair overlap check **vacuously PASS** on a single-subtask brief instead of erroring on an empty pair set.
- Criterion 9 Completeness (`:157-173`): Subtask Structure + Parallelism Analysis remain required; accept the documented single-subtask form from #1.
- Criterion 10 Configuration (`:176-183`): accept `Mode: single-agent`; `Workers: 1`. **Reword the worker-count rule** from *"Workers should not exceed the number of LAUNCHABLE subtasks in the first batch"* to *"…should not exceed the width of the LARGEST parallel batch"*. Rationale (found by Plan Review on this very brief): a staged plan whose Batch 1 is a single authority subtask legitimately declares peak workers from a later batch — under the old wording every such brief, including any future single-agent-plus-staged-fan-out brief, trips a false nit. This brief is the worked example: Batch 1 = 1 subtask, peak = 3.
- Criterion 12 (`:202-218`): a single-subtask brief has no siblings — `requires: []` is correct and the contract block is still BLOCKING-if-absent. Make that explicit.
- Update the affected examples (`:338,354-356,368,383`).

```yaml
provides:
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "Split reason"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Decomposition Threshold"}
external_requires: []
```

### Subtask 5 — Command mirrors + root docs (BLOCKED by #2,#3,#4)

Scope: `loomwright/commands/launch-pad.md`, `loomwright/commands/orchestrator.md`, `loomwright/commands/supervisor.md`, `loomwright/commands/agent-help.md`, `README.md`, `AGENT_GUIDELINES.md`, `CLAUDE.md`.
**`check-command-sync.sh` gates ONLY `commands/code-reviewer.md`** — these four mirrors are unprotected by CI, so drift here passes every gate and is caught only by a consistency audit. Sync them by hand against the FINAL wording landed in #2/#3/#4 (read those files; do not work from this brief's paraphrase).
- commands/launch-pad.md `:61,317,356,378,419` + the `:108-121` example brief.
- commands/orchestrator.md `:27,125,160,161,167,186,192,301,302`.
- commands/supervisor.md `:331-333` (Fast-Path section → Single-Agent + Sequential), `:319-322`.
- commands/agent-help.md `:116,117,355,356,357`.
- README.md `:200,322-328,340,554`; AGENT_GUIDELINES.md `:502,556,648`; CLAUDE.md `:73,115` (and the Worker/Orchestrator table rows that assert the old default).

```yaml
provides:
  - {kind: "symbol", path: "loomwright/commands/orchestrator.md", name: "Decomposition Threshold"}
  - {kind: "symbol", path: "loomwright/commands/supervisor.md", name: "Single-Agent"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/agents/orchestrator.md", name: "Decomposition Threshold"}
  - {from: "3", kind: "symbol", path: "loomwright/agents/supervisor.md", name: "Single-Agent Path"}
  - {from: "4", kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "Split reason"}
external_requires: []
```

### Subtask 6 — Budgets + version + stale spike notes (BLOCKED by #5)

Scope (**10 files**): `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.claude-plugin/README.md`, `loomwright/commands/agent-help.md`, `CLAUDE.md`, `README.md` (banner line only), `CHANGELOG.md`, `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md`.
- Run `bash scripts/check-token-budget.sh`. Only if a **real** breach remains after #2's net-reductive edit, raise the specific budget in `prompt-token-budgets.json` **and** the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" in the same commit (the gate checks both and fails closed on drift), and add the raise-log entry.
- Version bump to **v15.15.0**. `scripts/check-doc-currency.sh` is **GREEN today (verified at plan time)** and fails closed on any stale annotation, so the bump and **all five** live annotation sites MUST land in this one commit. Verified present at plan time — re-locate by phrase, not by line:
  1. `loomwright/.claude-plugin/plugin.json:4` — `"Loomwright v15.14.0 — …"` (headline, inside `description`)
  2. `.claude-plugin/marketplace.json:10` — `"Loomwright v15.14.0 — …"` (headline, inside `description`)
  3. `.claude-plugin/README.md:430` — `# Plugin manifest (v15.14.0)`
  4. `loomwright/commands/agent-help.md:1084` — `# Plugin metadata (v15.14.0)`
  5. `CLAUDE.md:28` — ``Plugin manifest: `loomwright/.claude-plugin/plugin.json` (v15.14.0)``

  Confirm with `bash scripts/check-doc-currency.sh` **and** `bash scripts/validate-version.sh` before finishing. Update each `description` **in place** — do NOT append a version clause (CLAUDE.md anti-rebloat rule). Counts are UNCHANGED (14 agents / 21 commands / 41 skills / 22 hooks) — do not touch count claims.
- CHANGELOG.md entry; CLAUDE.md banner (keep only the two most recent releases). Also prepend the matching `> **NEW in v15.15.0 — …**` banner line to `README.md:9`, mirroring the existing `NEW in v15.14.0` line — this is a **repo convention, NOT a gated one** (verified at plan time: the `NEW in vX.Y.Z` phrasing matches none of `check-doc-currency.sh`'s five `check_version` patterns), so it must be done by hand or it silently rots. Add `README.md` to this subtask's file set for that one line; the prose rows in it belong to #5, which runs first.
- **CLAUDE.md is shared with #5 and #6 runs strictly after it** — #5 owns the *prose rows* (the fast-path / review-gate assertions), #6 owns the *version banner + the `(v15.14.0)` manifest line*. Re-read the file before editing; do not revert #5's rows.
- Mark `EVAL_FINDINGS_AND_FIXES.md` Fix 1 with a `**STATUS 2026-07-28:** SHIPPED …` note in the same shape as the existing Fix 2 status note (`:109-113`) so the spike file does not go stale.
- **Do NOT "fix" illustrative example version strings** in RESULT_SCHEMAS.md / agent prompts — they are deliberately frozen (CLAUDE.md).

```yaml
provides:
  - {kind: "symbol", path: "CHANGELOG.md", name: "15.15.0"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.15.0"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "15.15.0"}
  - {kind: "symbol", path: ".claude-plugin/README.md", name: "Plugin manifest (v15.15.0)"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "Plugin metadata (v15.15.0)"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md", name: "STATUS 2026-07-28"}
requires:
  - {from: "5", kind: "symbol", path: "loomwright/commands/supervisor.md", name: "Single-Agent"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┬──→ Subtask 2 ──┐
            ├──→ Subtask 3 ──┼──→ Subtask 5 ──→ Subtask 6
            └──→ Subtask 4 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 4 | none | NO |
| Subtask 3 | Subtask 4 | none | NO |
| Subtask 1 | Subtask 6 | none (`ARCHITECTURE_CONTRACTS.md` touched only by #6 — the threshold has no mirror there, per D-a) | NO |
| Subtask 5 | Subtask 6 | **`CLAUDE.md`** (#5: prose rows · #6: version banner + manifest annotation) **`loomwright/commands/agent-help.md`** (#5: the 3-7 / review-subtask help copy · #6: the `Plugin metadata (v15.14.0)` annotation) and **`README.md`** (#5: prose rows · #6: the `NEW in vX.Y.Z` banner line) | **YES** — #6 is batched last and re-reads both files before editing |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3, Subtask 4 (parallel)
- **Batch 3:** Subtask 5
- **Batch 4:** Subtask 6
- **Recommended workers:** 3
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |
| 3 | `skills/async-orchestration/SKILL.md`, `skills/workflow-management/SKILL.md` |
| 4 | `skills/quality-checklist/SKILL.md` |
| 5 | — (mirror sync; read the #2/#3/#4 files directly) |
| 6 | — |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **R1** — Command mirrors drift: `check-command-sync.sh` gates only `commands/code-reviewer.md`, so stale prose in the other four passes all CI (repo's recurring `agent↔command mirror drift` failure). | HIGH | Subtask 5 exists solely for this and reads the FINAL agent wording, not this brief's paraphrase. Phase 4.5 will auto-expand to a consistency audit (diff touches `agents/`,`commands/`,`skills/`,`docs/`). |
| **R2** — `orchestrator.md` has only **299** proxy tokens of budget headroom (~1.2 KB) and bucket-B alone touches 12 lines. **Measured live at plan time**, not read from the JSON: `bash scripts/check-token-budget.sh` → orchestrator 8366/8665 (299), worker 4703/5045 (342), execute-manager 25597/25941 (344), supervisor 48364/51221 (2857). The `measured` field inside `prompt-token-budgets.json` is decorative and never re-derived — do not trust it. | MEDIUM | #2 is explicitly **net-reductive** (12 restatements → 1–2 lines) and must re-run `check-token-budget.sh` itself; a budget raise is #6's file only, keeping the gate's raise-rule (JSON + mirror in one commit) intact. |
| **R3** — Self-reference: Plan Reviewer Criterion 4 rejects `< 3` subtasks today, so the new default is unreviewable until #4 lands. | HIGH | #4 is a first-class subtask in Batch 2, not an afterthought. Note this brief itself is 6 subtasks under the OLD rule — the change cannot bootstrap itself, which is expected, not a defect. |
| **R4** — Scope creep into review-lens work (item 04 / Fix 7 / D4). | MEDIUM | D-c pins the boundary: the ONLY review change permitted is dropping the per-subtask reviewer on the single-agent path. Workers must escalate rather than "also fix" the drain or Phase 4.5. |
| **R5** — Losing per-subtask isolation below the threshold lets one worker's mistake contaminate all criteria. | MEDIUM | Accepted and named in Fix 1(c): the zero-token deterministic gate (`outputs_verified` at `agents/execute-manager.md:222`, plus tests/lint/LSP on the branch) plus the Phase 4.5 integrated review remain. Above the threshold, isolation is unchanged (D-d). |
| **R6** — `check-contract-parity.sh` fails closed if the last mention of a pinned field name is deleted while trimming `supervisor.md`/`orchestrator.md` prose. | MEDIUM | Called out inline in #3; run `bash scripts/check-contract-parity.sh` before finishing. |
| **R8** — A version bump silently breaks `check-doc-currency.sh`: the gate is GREEN today and fails closed on any of five live `v15.14.0` annotations left stale, three of which sit in files that would otherwise be out of #6's scope. Caught by Plan Review attempt 1 as a state-trace failure — AC-5 and the brief's own `corpus-task: doc-currency-green` could not both have held as originally scoped. | HIGH | #6's scope now names all 9 files and enumerates all five annotation sites, and must run `check-doc-currency.sh` + `validate-version.sh` before finishing. |
| **R7** — Per-subtask work volume: 4 of 4 workers hit the turn limit on the last comparable multi-surface job in this repo (twin-remediation, 2026-07-23). | MEDIUM | Subtasks here are file-scoped and small (1–3 files each except the mirror sweep). If a worker nears its limit it must emit `WORKER_RESULT` with partial status rather than dying silently. |

## Configuration
- **Workers:** 3 (peak concurrency, reached in Batch 2; Batch 1 runs 1). Declared against the largest parallel batch — see Subtask 4's Criterion 10 rewording, which this brief is the worked example for.
- **Mode:** parallel
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound (~60 edit sites across ~25 files — exceeds one worker's context; recorded per D-b even though the threshold rule this brief introduces is not yet in force)

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-07-28-fix1-single-agent-default.md
```

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/115
- **Branch:** feature/single-agent-default
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (no `new` BLOCKING/HIGH; 4 MEDIUM advisory findings fixed post-PASS)
- **Heal remaining issues:** 0 new BLOCKING/HIGH; 2 pre_existing LOW wording items left (execute-manager "fast-path" term, 91 proxy-token headroom)
- **Rubric score:** 4/4
- **Subtasks:** 6/6 completed
- **CI gates:** 7/7 green locally
- **Until-mergeable dispatched:** false (suppressed by /automate; the engine owns exactly one inline drain)
