# Supervisor Job: System Twin M2b (slice 1a) — advisory ground-truth execution in Phase 4.5

> **Why:** Pillar 2 ("provable-done") is still soft. Phase 4.5 today re-verifies via the static Code Reviewer
> + an advisory contract-conformance check + a canary benchmark — none of which **runs the software** and
> produces a hard pass/fail on real behavior. This slice adds an **advisory ground-truth execution** step to
> Phase 4.5: it runs a project-declared executable acceptance check against the integrated PR diff and records
> a hard PASS/FAIL into `SUPERVISOR_RESULT` + the `session_end` JSONL — **advisory only, never gates**. It is
> the M2b "the gate can *run the software*" muscle, demonstrated end-to-end on a single eval-corpus task.
>
> **Sequencing:** this is **M2b slice 1a**. Branch from `main` **AFTER v14.18.0 (insights-scoreboard) merges**;
> version → **v14.19.0**. Mirrors the `contract_conformance` / `benchmark_result` advisory precedent exactly.
>
> **Deferred (out of scope — named here so reviewers don't expect them):**
> - **M2b slice 1b** — auto-dispatch the **QA Executor** (`--depth smoke`, Playwright/app-execution) from
>   Phase 4.5 for *web-app* repos. Needs an opt-in flag + per-run budget guardrail (the QA Executor is a
>   120-maxTurn agent; auto-spawning it inside every supervisor run is a cost/scale decision of its own).
>   This slice WIRES the generic executable-acceptance path and **documents** the QA-Executor branch as the
>   resolver for `kind: qa-executor` checks; it does not yet Task-dispatch the agent.
> - **M2b part 2** — auto-run the full Launch Pad→Supervisor agent loop in CI against the eval corpus.
> - **M3** — flipping any of this from advisory → gating. Explicitly NOT in scope.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager · **CLAUDE.md:** ✓ (v14.17.0, fresh)
- **Git:** repo currently on `feature/insights-scoreboard` (maintainer WIP). **This brief MUST be run from a fresh `main`-based branch via `/supervisor --base-branch main` AFTER v14.18.0 merges** — do not branch off `feature/insights-scoreboard`.
- **gh:** ✓ authenticated (vikashruhilgit) · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 1 (sequencing — see below) | **legacy_brief:** false

## Task
**Goal:** Add an **advisory ground-truth execution** step to Supervisor Phase 4.5 SELF_HEAL that runs a
project-declared executable acceptance check against the integrated feature-branch diff and records a hard
PASS/FAIL, following the exact advisory-first discipline of the existing contract-conformance + benchmark
checks. Prove it end-to-end by running a single eval-corpus task's `check.sh` as the ground-truth check.

**Mechanism (the smallest correct thing):**
1. A new deterministic, fail-safe runner `scripts/run-ground-truth.sh` (sibling of `run-eval.sh` /
   `run-benchmark.sh`) that resolves a set of executable acceptance checks, runs each (exit 0 = pass), and
   emits one `GROUND_TRUTH_JSON: {...}` line. **Always exits 0**; on any failure it emits `status:"unverified"`.
2. A Phase 4.5 step in `agents/supervisor.md` that invokes the runner after the Code Reviewer loop (alongside
   the conformance + benchmark checks), folds the result into a new additive `ground_truth` object on
   `SUPERVISOR_RESULT`, and writes the matching FLAT `session_end` JSONL fields. **Advisory only** — NEVER
   changes `heal_decision`, NEVER triggers a fix, NEVER blocks the PR.

**Check resolution (deterministic, advisory, fail-safe):**
- **Primary:** the in-progress brief's optional `## Executable Acceptance` section — a list of `- ` bullets,
  each either a shell command or `<kind>: <target>` (`kind ∈ {cmd, corpus-task, qa-executor}`).
- **Fallback:** `.supervisor/twin/ground-truth.json` (gitignored) if present.
- **No source → graceful no-op:** `status:"skipped"`, `checks_total:0` (mirrors conformance-with-no-contracts).
- `kind: qa-executor` is **recognized but deferred** in this slice → recorded as `status:"unverified"` per-check
  with reason `"qa_executor_dispatch_deferred_m2b_1b"` (documents the seam without spawning the agent).

## Acceptance Criteria
- [ ] **Runner exists & is fail-safe:** `scripts/run-ground-truth.sh` runs each resolved check (exit 0 = pass),
      emits exactly one `GROUND_TRUTH_JSON: {ran, status, checks_total, checks_passed, pass_rate, per_check[], commit, date}`
      line, and **always exits 0** (missing `jq`/no source/check crash → `status:"unverified"` or `"skipped"`, never non-zero).
- [ ] **Dogfood proof (single eval-corpus task end-to-end):** invoking the runner with a `corpus-task: version-consistent`
      check executes `scripts/eval-corpus/version-consistent/check.sh` and reports a hard `checks_passed`/`checks_total`
      reflecting that task's real exit code.
- [ ] **Phase 4.5 wiring (advisory):** `agents/supervisor.md` Phase 4.5 invokes `run-ground-truth.sh` after the
      Code Reviewer loop, parses `GROUND_TRUTH_JSON`, and records it. The step **explicitly states** it NEVER changes
      `heal_decision`, NEVER triggers a fix iteration, and NEVER blocks the PR — identical wording-discipline to the
      contract-conformance block. Runs on EVERY Phase 4.5 (PASS or ESCALATED), read-only, dispatches no fixes.
- [ ] **SUPERVISOR_RESULT additive field:** `docs/RESULT_SCHEMAS.md` gains a `ground_truth` object on SUPERVISOR_RESULT
      (`checked`, `status ∈ [pass, advisory_failures, unverified, skipped]`, `checks_total`, `checks_passed`, `findings[]`),
      **schema_version stays 1**, documented as optional/additive/advisory following the `contract_conformance` /
      `benchmark_result` precedent (Supervisor SubagentStop hook does NOT enumerate it; pre-existing blocks stay valid).
- [ ] **Flat `session_end` fields:** `docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields" documents the
      matching FLAT scalars (`ground_truth_status`, `ground_truth_checks_total`, `ground_truth_checks_passed`,
      `ground_truth_pass_rate`) as the same data in two shapes, additive, readers treat absent as `skipped`.
- [ ] **GROUND_TRUTH_JSON schema:** `docs/RESULT_SCHEMAS.md` gains a short `GROUND_TRUTH_JSON` (schema_version 1) entry
      next to `BENCHMARK_JSON` / `EVAL_RESULT`, documenting the emitted shape.
- [ ] **`## Executable Acceptance` brief convention:** documented in `docs/RESULT_SCHEMAS.md` (or the supervisor-readiness
      skill reference within the brief), including the `cmd` / `corpus-task` / `qa-executor`(deferred) kinds.
- [ ] **Self-tested:** `scripts/test-run-ground-truth.sh` asserts (a) a passing check → `status:"pass"`, correct tallies;
      (b) a failing check → `status:"advisory_failures"`, runner still exits 0; (c) no source → `status:"skipped"`;
      (d) missing-`jq` simulation → `status:"unverified"`, exit 0; (e) `qa-executor` kind → per-check `"unverified"`
      with the deferred reason. Uses a temp dir; does not pollute real `.supervisor/`.
- [ ] **Roadmap updated:** `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` M2 row + §2 pillar table reflect "M2b slice 1a shipped"
      (the ground-truth execution muscle is wired, advisory; 1b QA-Executor dispatch + part-2 CI loop still deferred).
- [ ] **Anti-rebloat + currency:** NO new command/agent/hook/skill (scripts uncounted: 14/16/51/19 unchanged);
      version → v14.19.0; `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` pass.
- [ ] **No dedup collision:** the change set touches **none of** `scripts/run-eval.sh`, `scripts/build-insights.sh`,
      `commands/insights.md` (owned by the in-flight v14.18.0 insights-scoreboard brief).

## Subtask Structure

### ST1 — `run-ground-truth.sh` runner + self-test  [blocks all]
**Files:** `ai-agent-manager-plugin/scripts/run-ground-truth.sh` (create), `ai-agent-manager-plugin/scripts/test-run-ground-truth.sh` (create).
**Work:** deterministic, fail-safe runner that resolves checks (`## Executable Acceptance` section passed via arg/stdin, or `.supervisor/twin/ground-truth.json`, or none→skipped), runs each (`cmd`, `corpus-task`; `qa-executor`→deferred-unverified), and emits one `GROUND_TRUTH_JSON` line. mkdir-safe, no writes outside given paths, **always exit 0**. Self-test covers the 5 cases in the AC (temp dir).
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/run-ground-truth.sh, name: ground_truth_runner}
requires: []
```

### ST2 — Phase 4.5 wiring + schemas  [dep ST1]
**Files:** `ai-agent-manager-plugin/agents/supervisor.md` (modify — Phase 4.5 SELF_HEAL), `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` (modify).
**Work:** add the Phase 4.5 ground-truth step (after Code Reviewer loop; advisory-only wording mirroring the contract-conformance block; runs on PASS or ESCALATED; writes the `ground_truth` SUPERVISOR_RESULT object + flat `session_end` fields in the completion record). Add to RESULT_SCHEMAS.md: the `ground_truth` SUPERVISOR_RESULT object (schema_version 1, additive precedent text), the flat `session_end` fields, the `GROUND_TRUTH_JSON` entry, and the `## Executable Acceptance` brief convention.
```yaml
provides:
  - {kind: capability, path: ai-agent-manager-plugin/agents/supervisor.md, name: phase45_ground_truth}
  - {kind: file, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md, name: ground_truth_schema}
requires:
  - {kind: file, name: ground_truth_runner, from: ST1}
```

### ST3 — roadmap, version, currency  [dep ST1-2]
**Files:** `ai-agent-manager-plugin/docs/SPIKES/SYSTEM_TWIN_ROADMAP.md`, `CLAUDE.md`, `CHANGELOG.md`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (modify).
**Work:** roadmap M2/§2 rows → "M2b slice 1a shipped"; version → v14.19.0; CHANGELOG entry; CLAUDE.md banner (counts unchanged 14/16/51/19); run `check-doc-currency.sh` + `validate-version.sh`.
```yaml
provides:
  - {kind: file, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: capability, name: phase45_ground_truth, from: ST2}
```

## Parallelism Analysis
- **Batch 1:** ST1 · **Batch 2:** ST2 · **Batch 3:** ST3 · **Mode:** sequential · **Workers:** 1 (each consumes the prior; ST2 hard-depends on ST1's `GROUND_TRUTH_JSON` contract, ST3 on the version/doc surface from ST1-2).

## Outcomes Rubric
- `scripts/run-ground-truth.sh` exists and exits 0 on every path (passing check, failing check, no source, missing jq).
- Running the runner against `corpus-task: version-consistent` produces a `GROUND_TRUTH_JSON` line whose `checks_passed`/`checks_total` reflect that task's real exit code.
- `agents/supervisor.md` Phase 4.5 invokes the runner after the Code Reviewer loop and states it is advisory-only (never changes `heal_decision`, never blocks the PR).
- `docs/RESULT_SCHEMAS.md` documents the `ground_truth` SUPERVISOR_RESULT object at schema_version 1 (additive) plus the flat `session_end` fields and a `GROUND_TRUTH_JSON` entry.
- `scripts/test-run-ground-truth.sh` exists and passes, covering pass / fail / skipped / unverified / qa-executor-deferred.
- The diff touches none of `scripts/run-eval.sh`, `scripts/build-insights.sh`, `commands/insights.md`.
- `plugin.json` version is `14.19.0`; agent/command/skill/hook counts unchanged (14/16/51/19); `check-doc-currency.sh` and `validate-version.sh` pass.

## Skill References
- **ST1:** `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`, `skills/state-management/SKILL.md`
- **ST3:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Mitigation |
|---|---|---|
| QA Executor (Playwright) is not dogfoodable on this repo (no web app) — roadmap M2 language implies it | MED (Feasibility 2.5) | Scope to a **generic executable-acceptance** runner; dogfood via a corpus-task `check.sh`; `qa-executor` kind recognized but **deferred to slice 1b** with an explicit per-check reason |
| Ground-truth step accidentally gates / blocks a PR | HIGH | Hard AC + rubric: advisory-only, identical wording to the contract-conformance block; runner output never feeds `heal_decision`; runs read-only after the loop |
| Auto-spawning QA Executor inside every run = cost/scale leak | MED | Slice 1a does NOT Task-dispatch the agent; 1b gated behind opt-in flag + budget (deferred, documented) |
| Version/doc-currency conflict with the in-flight v14.18.0 brief | MED | Branch from `main` **after** v14.18.0 merges; target v14.19.0; brief touches no insights-owned files |
| Runner breaks its always-exit-0 contract | MED | Fail-safe by construction; self-test asserts exit 0 on every path incl. missing-jq and check-crash |

## Configuration
- **Mode:** sequential · **Workers:** 1 · **Branch:** `feature/m2b-ground-truth` · **Base Branch:** `main` · **Cost:** default
- **References:** `agents/supervisor.md` (Phase 4.5 SELF_HEAL — advisory contract-conformance + benchmark blocks are the pattern to mirror, ~lines 796–855), `docs/RESULT_SCHEMAS.md` (SUPERVISOR_RESULT additive-field precedent ~lines 234–284; `session_end` flat fields ~lines 718–753; `EVAL_RESULT` / `BENCHMARK_JSON` entries), `scripts/run-eval.sh` + `scripts/run-benchmark.sh` (read-only — the fail-safe runner idiom to copy, NOT modify), `scripts/eval-corpus/version-consistent/check.sh` (dogfood target).

## Handoff
```
# AFTER v14.18.0 (insights-scoreboard) merges to main:
git checkout main && git pull origin main
/supervisor job: .supervisor/jobs/pending/2026-06-07-m2b-ground-truth.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-07T10:35:14Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/37
- **Branch:** feature/m2b-ground-truth
- **Files changed:** 11 (2 new scripts + 9 modified)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Rubric score:** null (grader output failed to parse twice; all 7 outcomes independently verified — see SUPERVISOR_RESULT)
- **Twin signal:** Twin: conformance PASS (0 violations) · benchmark system-twin-selftest 4
- **Ground-truth (this run):** skipped (brief declared no `## Executable Acceptance` heading; graceful no-op). Dogfood pass demonstrated separately via `--check 'corpus-task: version-consistent'`.
- **Summary:** System Twin M2b slice 1a shipped — advisory ground-truth execution wired into Supervisor Phase 4.5 (v14.19.0). Code review PASS (consistency audit), both CI gates green, no dedup collision.
