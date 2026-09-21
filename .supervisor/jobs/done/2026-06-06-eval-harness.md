# Supervisor Job: System Twin M2a — the eval/benchmark harness (real fitness function)

> **The keystone.** Today's only "benchmark" is a **canary** (`run-benchmark.sh` → `selftest_pass_count`) — it proves the
> hard-signal *pipeline* works, NOT that the plugin produces *correct output*. This brief builds the **real fitness
> function**: a fixed task corpus with deterministically-checkable outcomes + a scorer, so plugin output quality becomes
> a measurable **pass-rate over releases**. This is M2 *part a* — the eval INSTRUMENT. Wiring it to auto-run the full
> agent loop in CI, and wiring ground-truth execution into Phase 4.5, are explicit **follow-ups** (M2b).
> **Sequencing:** #31/#32 merged; branch from `main` (**v14.16.0**); version → **v14.17.0**. No engine/agent/command change.
> **Run AFTER PR #33 merges** — it tracks `SYSTEM_TWIN_ROADMAP.md`, which ST3 edits; branching first avoids a duplicate-file collision.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager · **CLAUDE.md:** ✓ (v14.16.0) · **Git:** `main`; `git pull` first · **gh:** ✓ · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 0 | **legacy_brief:** false

## Task
**Goal:** Add a deterministic **eval harness** — distinct from the canary benchmark — that measures the plugin's *output quality* against a fixed corpus of tasks, each with an **executable acceptance check**. Deliver: a corpus format, a runner/scorer (`scripts/run-eval.sh`) that executes each task's check and reports a **pass-rate (N/M)**, a seed corpus (3–5 tasks dogfooded on this repo), an `EVAL_RESULT` schema so scores are trackable across releases, and self-tests. **Naming discipline:** "eval" (this) ≠ "benchmark" (the existing canary) — keep them clearly separate.

## Acceptance Criteria
- [ ] **Corpus format:** each task is a self-contained dir `scripts/eval-corpus/<task-id>/` with a `spec.md` (what the task asks) + an executable `check.sh` (exit 0 = pass, non-0 = fail) that **deterministically** verifies the outcome. Format documented (header or `eval-corpus/README.md`).
- [ ] **Runner/scorer:** `scripts/run-eval.sh` runs every task's `check.sh`, tallies pass/fail, prints a per-task line + a **pass-rate `N/M`**, and emits one machine line (`EVAL_RESULT: {...}`). Deterministic (same corpus → same result), fail-safe (missing corpus / no jq → `status: unverified`, exit 0), never `--force`/destructive.
- [ ] **Seed corpus (3–5 tasks):** small, self-contained, deterministically-checkable, dogfooded on this repo (e.g. "a deliberately-broken copy of a script must be fixed so its self-test passes"; "output must keep `check-doc-currency.sh` green"; a fixture function + its unit test). Each represents plugin-relevant work, not a trivial `true`.
- [ ] **`EVAL_RESULT` schema:** added to `docs/RESULT_SCHEMAS.md` (schema_version 1: `tasks_total`, `tasks_passed`, `pass_rate`, `per_task[]{id,status}`, `commit`, `date`) so pass-rate is trackable release-over-release — the fitness-function signal.
- [ ] **Self-tested:** `scripts/test-run-eval.sh` (mirrors `test-benchmark.sh`) covers pass/fail tallying, the deterministic-same-result invariant, and the missing-corpus fail-safe.
- [ ] **Scope honesty:** the harness is the INSTRUMENT; it does NOT auto-run the Launch Pad→Supervisor loop in CI and does NOT wire ground-truth into Phase 4.5 — both flagged as M2b follow-ups in the doc + the roadmap.
- [ ] **Anti-rebloat:** no new command/agent/hook/skill (scripts uncounted); version → v14.17.0; `check-doc-currency.sh` + `validate-version.sh` pass.

## Subtask Structure

### ST1 — eval runner + format + self-test  [blocks all]
**Files:** `scripts/run-eval.sh` (create), `scripts/test-run-eval.sh` (create), `scripts/eval-corpus/README.md` (create — the format spec).
**Work:** define the corpus format; build `run-eval.sh` (execute each `<id>/check.sh`, tally, pass-rate, `EVAL_RESULT:` line, deterministic + fail-safe exit 0); self-test with temp fixtures (mirrors `test-benchmark.sh`).
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/run-eval.sh, name: eval_runner}
  - {kind: file, path: ai-agent-manager-plugin/scripts/eval-corpus/README.md, name: corpus_format}
  - {kind: file, path: ai-agent-manager-plugin/scripts/test-run-eval.sh, name: eval_selftest}
requires: []
```

### ST2 — seed corpus  [dep ST1]
**Files:** `scripts/eval-corpus/<task-id>/{spec.md,check.sh}` ×3–5 (create).
**Work:** author 3–5 deterministic, self-contained, repo-dogfooded tasks per ST1's format; each `check.sh` exits 0/1; verify `run-eval.sh` scores them.
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/eval-corpus/, name: seed_corpus}
requires:
  - {kind: file, name: eval_runner, from: ST1}
  - {kind: file, name: corpus_format, from: ST1}
```

### ST3 — schema + docs + version  [dep ST1-2]
**Files:** `docs/RESULT_SCHEMAS.md` (modify), `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` (modify — M2 status note), `CLAUDE.md`, `CHANGELOG.md`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (modify).
**Work:** add `EVAL_RESULT` schema; note M2a shipped + M2b deferred in the roadmap; version → v14.17.0; CHANGELOG; CLAUDE banner; counts unchanged. Run both gates.
```yaml
provides:
  - {kind: file, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: file, name: eval_runner, from: ST1}
  - {kind: file, name: seed_corpus, from: ST2}
```

## Parallelism Analysis
- **Batch 1:** ST1 · **Batch 2:** ST2 · **Batch 3:** ST3 · **Mode:** sequential · **Workers:** 1 (each consumes the prior).

## Skill References
- **ST1:** `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`
- **ST3:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Mitigation |
|---|---|---|
| Eval confused with the canary benchmark | MED | Distinct naming ("eval" vs "benchmark"), separate corpus dir, README states the difference |
| Seed tasks too trivial → meaningless pass-rate | MED | AC requires repo-dogfooded, plugin-relevant tasks (fix-broken-script, keep-gate-green), not `true` |
| Scope creep into auto-running the agent loop / Phase 4.5 wiring | MED | Explicitly out of scope (M2b); this brief is the instrument only |
| Non-determinism in checks | LOW | AC: deterministic checks only; self-test asserts same-corpus→same-result |
| Anti-rebloat | LOW | No new command/agent/hook/skill; scripts uncounted |

## Configuration
- **Mode:** sequential · **Workers:** 1 · **Branch:** `feature/eval-harness` · **Cost:** default
- **References:** `scripts/run-benchmark.sh` + `scripts/test-benchmark.sh` (the canary — pattern to mirror AND stay distinct from), `docs/RESULT_SCHEMAS.md` (result-block convention), `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` (§4 M2).

## Handoff
```
git pull
/supervisor job: .supervisor/jobs/pending/2026-06-06-eval-harness.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-06T17:53:34Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/34
- **Branch:** feature/eval-harness
- **Files changed:** 21 (+627/-14)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (integration review PASSED first pass; no fix iteration needed)
- **Summary:** System Twin M2a eval harness shipped — run-eval.sh runner/scorer + eval-corpus format + 4-task seed corpus (4/4) + test-run-eval.sh self-test + EVAL_RESULT schema; version bumped to v14.17.0, counts unchanged (14/16/51/19). Both CI gates green. M2b (CI agent-loop auto-run + Phase 4.5 ground-truth wiring) deferred.
