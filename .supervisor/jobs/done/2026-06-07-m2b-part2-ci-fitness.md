# Supervisor Job: System Twin M2b part-2 (slice 2a) — wire fitness + self-test signals into CI

> **Why:** Pillar 2 ("provable-done") has the instruments (eval `pass_rate`, ground-truth, benchmark) but they
> only run **locally/manually**. CI (`.github/workflows/ci.yml`) runs version/doc gates + **just 1 of the 14
> deterministic self-tests** (`test-run-eval.sh`), and **never runs the fitness instruments themselves**. So
> `pass_rate` is not a continuous signal and 13 self-tests can silently rot. This slice makes both **continuous in
> CI** — the self-test suite as **hard gates** (deterministic, no API cost) and the fitness signal as an
> **advisory, non-gating** report. It is the dogfoodable first slice of M2b part-2.
>
> **Advisory-first (non-negotiable):** CI **surfaces** fitness (pass_rate / ground-truth / benchmark) but NEVER
> fails the build on a low pass_rate — hard-gating on fitness is **M3**, explicitly out of scope. Self-tests DO
> gate (they test the *instruments*, not the *fitness*).
>
> **Sequencing:** branch from `main` (v14.19.0); version → **v14.20.0**. No engine/agent/command change.
>
> **Deferred (named so reviewers don't expect them):**
> - **M2b part-2b** — drive `claude` **headless** in CI to actually *produce* solutions for *generative* corpus
>   tasks. Needs an `ANTHROPIC_API_KEY` secret, a per-run token budget, a circuit-breaker, and a *generative* task
>   shape (today's corpus is mostly verify-repo-state shaped). Real cost + real guardrails — its own slice.
> - **M3** — flipping any fitness signal from advisory → gating. NOT in scope.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager · **CLAUDE.md:** ✓ (v14.19.0, fresh)
- **Git:** `main`, clean (only `.claude/` untracked) · **gh:** ✓ authenticated · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 0 | **legacy_brief:** false

## Task
**Goal:** Extend `.github/workflows/ci.yml` so that on every push/PR to `main` it (1) runs the **full deterministic
self-test suite** as hard gates, and (2) runs the **fitness instruments** and reports their results **advisorily**
(GitHub Step Summary + uploaded artifact), without ever failing the build on fitness. Do not disturb the existing
`claude-code-review.yml` / `claude.yml` workflows.

**Verified facts to build on:**
- 14 self-tests under `ai-agent-manager-plugin/scripts/test-*.sh`; all CI-safe (no network / no `ANTHROPIC_API_KEY` / no interactive read; `test-telemetry.sh`'s only `gh` mention is an assertion that `--dry-run` does NOT call `gh`). CI currently runs only `test-run-eval.sh`.
- Fitness runners are fail-safe / **always exit 0**: `run-eval.sh` (emits `EVAL_RESULT`, supports `--no-record` + `EVAL_RESULTS_FILE`), `run-ground-truth.sh` (emits `GROUND_TRUTH_JSON`, supports `--check 'corpus-task:<id>'`), `run-benchmark.sh` (emits `BENCHMARK_JSON`). All emit one machine-readable jq-built line; on failure they emit `status:"unverified"`/`"skipped"`.
- `ubuntu-latest` ships `jq` preinstalled (the runners' only hard dep).

## Acceptance Criteria
- [ ] **Self-test suite gated (HARD):** `ci.yml` runs **all** `ai-agent-manager-plugin/scripts/test-*.sh` (not just `test-run-eval.sh`) as a hard gate — a **loop over `test-*.sh`** so future self-tests are auto-included (anti-drift), failing the job if any self-test exits non-zero. The existing single `test-run-eval.sh` step is subsumed by the loop (no double-run).
- [ ] **Existing gates preserved:** `validate-version.sh`, `check-command-sync.sh`, `check-doc-currency.sh` still run and still hard-gate.
- [ ] **Advisory fitness report (NON-gating):** a CI step/job runs `run-eval.sh`, `run-ground-truth.sh --check 'corpus-task: version-consistent'`, and `run-benchmark.sh`, parses each one-line result with `jq`, and writes a readable summary (eval `pass_rate` + `status`, ground-truth `status` + `checks_passed/checks_total`, benchmark `metric` + `value`) to `$GITHUB_STEP_SUMMARY`. This step **MUST NOT fail the build** regardless of pass_rate or `status:"unverified"`/`"skipped"` (guard with the runners' exit-0 contract + tolerant parsing).
- [ ] **Fitness history artifact:** the eval results history (`.supervisor/eval/results.jsonl`, produced by `run-eval.sh`) is uploaded as a workflow artifact (best-effort; absence does not fail the job).
- [ ] **No build-break on advisory path:** demonstrably, a low/`unverified` fitness result leaves the job green (only self-tests + version/doc gates can red the build).
- [ ] **Workflows isolated:** `claude-code-review.yml` and `claude.yml` are untouched; no new secrets required for this slice (part-2b's `ANTHROPIC_API_KEY` is NOT introduced here).
- [ ] **Deferral documented:** the corpus `README.md` "Out of scope (M2b follow-ups)" note and `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` are updated to reflect "part-2a shipped (fitness + self-tests in CI, advisory); part-2b (headless agent generation) deferred".
- [ ] **Anti-rebloat + currency:** NO new command/agent/hook/skill (counts stay 14/16/51/19); at most one tiny uncounted helper script if a loop-in-YAML is unwieldy; version → v14.20.0; `check-doc-currency.sh` + `validate-version.sh` pass.

## Subtask Structure

### ST1 — CI: gate the full self-test suite + advisory fitness report  [blocks ST2]
**Files:** `.github/workflows/ci.yml` (modify). Optionally `ai-agent-manager-plugin/scripts/ci-fitness-report.sh` (create, uncounted) if the summary-building logic is too long for inline YAML.
**Work:** (a) replace the single `test-run-eval.sh` step with a loop over `ai-agent-manager-plugin/scripts/test-*.sh` (hard gate, fails on any non-zero); keep the three existing version/doc gates. (b) add a final **advisory** step/job that runs `run-eval.sh` + `run-ground-truth.sh --check 'corpus-task: version-consistent'` + `run-benchmark.sh`, parses each result line with `jq`, writes a summary to `$GITHUB_STEP_SUMMARY`, and is wrapped so it can never fail the build. (c) upload `.supervisor/eval/results.jsonl` via `actions/upload-artifact` (best-effort).
```yaml
provides:
  - {kind: file, path: .github/workflows/ci.yml, name: ci_fitness_workflow}
requires: []
```

### ST2 — docs: corpus README + roadmap deferral note  [dep ST1]
**Files:** `ai-agent-manager-plugin/scripts/eval-corpus/README.md` (modify), `ai-agent-manager-plugin/docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` (modify).
**Work:** update the corpus "Out of scope (M2b follow-ups)" bullets — CI auto-run of the fitness instruments is now done (advisory); only the *headless agent generation loop* (part-2b) remains out of scope. Update the roadmap M2 row + §2 pillar-2 cell + §6 item 3 to reflect part-2a shipped / part-2b deferred.
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/docs/SPIKES/SYSTEM_TWIN_ROADMAP.md, name: roadmap_update}
requires:
  - {kind: file, name: ci_fitness_workflow, from: ST1}
```

### ST3 — version + currency  [dep ST1-2]
**Files:** `CLAUDE.md`, `CHANGELOG.md`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (modify).
**Work:** version → v14.20.0; CHANGELOG entry; CLAUDE.md banner (counts unchanged 14/16/51/19); run `check-doc-currency.sh` + `validate-version.sh`.
```yaml
provides:
  - {kind: file, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: file, name: roadmap_update, from: ST2}
```

## Parallelism Analysis
- **Batch 1:** ST1 · **Batch 2:** ST2 · **Batch 3:** ST3 · **Mode:** sequential · **Workers:** 1 (ST2 doc-updates describe ST1's workflow; ST3 version-bumps after the surface is final). ST1 is the only code subtask.

## Outcomes Rubric
- `.github/workflows/ci.yml` runs all `ai-agent-manager-plugin/scripts/test-*.sh` (loop, not a single test) as a hard gate, and still runs `validate-version.sh` + `check-command-sync.sh` + `check-doc-currency.sh`.
- `ci.yml` runs `run-eval.sh`, `run-ground-truth.sh`, and `run-benchmark.sh` and writes their pass_rate/status/value to `$GITHUB_STEP_SUMMARY`.
- The fitness step cannot fail the build: it is wrapped so a low pass_rate or `status:"unverified"`/`"skipped"` leaves the job green.
- `claude-code-review.yml` and `claude.yml` are unchanged; no `ANTHROPIC_API_KEY` secret is added by this change.
- The corpus `README.md` and `SYSTEM_TWIN_ROADMAP.md` state part-2a shipped (advisory CI fitness + self-tests) and part-2b (headless agent generation) deferred.
- `plugin.json` version is `14.20.0`; agent/command/skill/hook counts unchanged (14/16/51/19); `check-doc-currency.sh` and `validate-version.sh` pass.

## Skill References
- **ST1:** `skills/ci-cd/SKILL.md`, `skills/quality-checklist/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`
- **ST3:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Mitigation |
|---|---|---|
| Advisory fitness step accidentally fails the build (becomes a gate = M3 creep) | HIGH | Hard AC + rubric: wrap so it can never fail; rely on runners' always-exit-0; tolerant `jq` parse; assert a low/unverified result stays green |
| A self-test is not actually CI-safe (network/API/flaky) | MED | Pre-verified: all 14 are CI-safe (scan found none); loop runs them in the checked-out repo where the maintainer-side checks resolve; if one proves flaky, exclude it explicitly with a comment |
| Loop hides which self-test failed | LOW | Echo `== <test> ==` before each; fail fast on first non-zero with the test name in the log |
| Disturbing the existing claude workflows | MED | Scope strictly to `ci.yml`; AC + rubric assert the other two are untouched |
| Maintainer-side corpus tasks fail in CI (path assumptions) | LOW | CI checks out the repo so `git rev-parse --show-toplevel` resolves; fitness is advisory anyway — a fail is reported, not gated |

## Configuration
- **Mode:** sequential · **Workers:** 1 · **Branch:** `feature/m2b-part2-ci-fitness` · **Base Branch:** `main` · **Cost:** default
- **References:** `.github/workflows/ci.yml` (current: validate-version, check-command-sync, check-doc-currency, test-run-eval), `ai-agent-manager-plugin/scripts/run-eval.sh` (`EVAL_RESULT`, `--no-record`, `EVAL_RESULTS_FILE`), `run-ground-truth.sh` (`GROUND_TRUTH_JSON`, `--check 'corpus-task:<id>'`), `run-benchmark.sh` (`BENCHMARK_JSON`), `scripts/eval-corpus/README.md` ("Out of scope (M2b follow-ups)" note to update), `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` (M2 row §75 / §2 pillar table §54 / §6 item 3 §107).

## Handoff
```
git checkout main && git pull origin main
/supervisor job: .supervisor/jobs/pending/2026-06-07-m2b-part2-ci-fitness.md --base-branch main
```

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/39 (base: main)
- **Branch:** feature/m2b-part2-ci-fitness · **Commit:** 2b9cdb0
- **heal_loop_ran:** true · **heal_decision:** PASS · **heal_iterations:** 0 · **heal_remaining_issues:** 0
- **rubric_score:** 6/6
- **Code Reviewer:** PASS (consistency_audit) — 1 LOW nit (intentional `continue-on-error` + `|| true` redundancy), 0 new BLOCKING/HIGH
- **Gates:** validate-version + check-command-sync + check-doc-currency green at v14.20.0; all 14 self-tests pass; ground_truth: skipped (brief has no `## Executable Acceptance` section — advisory, non-gating)
- **Completed:** 2026-06-08
