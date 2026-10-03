# Supervisor Job: Make `/insights` the unified System-Twin scoreboard (eval fitness + Twin growth)

> **Why:** `/insights` already shows work/quality + the Twin hard signal — but it does NOT surface the **eval
> fitness function** (M2a, `EVAL_RESULT` pass-rate) we just shipped, nor **Twin contract growth**. This wires both in,
> so `/insights` becomes the single scoreboard for predict · prove · compound · **fitness**. Read-only on your work;
> deterministic; advisory. **Distinct from** Claude Code's builtin "Insights" (whole-usage coaching) and `ccusage` (cost).
> **Sequencing:** #34 merged; branch from `main` (**v14.17.0**); version → **v14.18.0**. No engine/agent/command change.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager · **CLAUDE.md:** ✓ (v14.17.0) · **Git:** `main`; `git pull` first · **gh:** ✓ · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 0 | **legacy_brief:** false

## Task
**Goal:** (1) make `scripts/run-eval.sh` **persist** each `EVAL_RESULT` to a small history file so a trend exists; (2) extend `scripts/build-insights.sh` (the `/insights` aggregator) with two new dashboard sections — **Eval fitness function** (latest pass-rate + trend) and **System Twin growth** (contract count over time) — reading the eval history + the Twin store. Deterministic, fail-safe, gitignored output. No cost (still defers to `ccusage`).

## Acceptance Criteria
- [ ] **Eval history persisted:** `run-eval.sh` appends each run's result (the `EVAL_RESULT` fields + timestamp) to `.supervisor/eval/results.jsonl` (under `.supervisor/`, gitignored), one line per run; a `--no-record` flag suppresses it (used by the self-test). Append is atomic/fail-safe; `run-eval.sh` still always exits 0.
- [ ] **`/insights` — Eval fitness section:** `build-insights.sh` adds an **"Eval fitness function"** section showing the **latest pass-rate** and a **trend** across the recorded results (e.g. `4/4 → 5/6 → 6/6`, newest last), read deterministically (jq) from `.supervisor/eval/results.jsonl`.
- [ ] **`/insights` — Twin growth section:** adds a **"System Twin growth"** section showing the current **contract count** (`.supervisor/twin/contracts/*.md`) and growth (count of `add` actions over time from `.supervisor/twin/.provenance.jsonl`), e.g. "7 contracts (4 → 7)".
- [ ] **Sparse-tolerant:** with no `.supervisor/eval/results.jsonl` and/or no `.supervisor/twin/`, both new sections render a benign "no data yet" line and `/insights` never errors (exit 0) — matching the existing dashboard's fail-safe style.
- [ ] **Distinct-from-CC note:** `commands/insights.md` gains a one-line pointer: this is the plugin's deterministic run scoreboard; for whole-usage coaching see **Claude Code Insights**, for cost see **`ccusage`**.
- [ ] **Self-tested:** `scripts/test-insights.sh` extended to assert both new sections render from fixture data AND degrade gracefully when sources are absent; `scripts/test-run-eval.sh` extended to assert the `results.jsonl` append (+ `--no-record` suppression). Both green.
- [ ] **Anti-rebloat + currency:** no new command/agent/hook/skill (scripts uncounted); version → v14.18.0; `check-doc-currency.sh` + `validate-version.sh` pass.

## Subtask Structure

### ST1 — `run-eval.sh` result persistence  [blocks all]
**Files:** `scripts/run-eval.sh` (modify), `scripts/test-run-eval.sh` (modify).
**Work:** append each `EVAL_RESULT` (with a UTC timestamp) as one line to `.supervisor/eval/results.jsonl` (mkdir -p; atomic; fail-safe; always exit 0); add `--no-record`. Extend the self-test to assert the append happens by default and is suppressed by `--no-record` (use a temp `.supervisor/eval/` so it doesn't pollute real history).
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/run-eval.sh, name: eval_history}
requires: []
```

### ST2 — `build-insights.sh` two new sections + doc  [dep ST1]
**Files:** `scripts/build-insights.sh` (modify), `commands/insights.md` (modify), `scripts/test-insights.sh` (modify).
**Work:** add the **Eval fitness function** section (latest + trend from `.supervisor/eval/results.jsonl`) and the **System Twin growth** section (contract count from `.supervisor/twin/contracts/`, growth from `.provenance.jsonl`); both sparse-tolerant. Document the two sections + the distinct-from-CC/ccusage pointer in `commands/insights.md`. Extend `test-insights.sh` to cover both (present + absent).
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/build-insights.sh, name: scoreboard_sections}
  - {kind: capability, path: ai-agent-manager-plugin/commands/insights.md, name: insights_doc}
requires:
  - {kind: file, name: eval_history, from: ST1}
```

### ST3 — docs, version, currency  [dep ST1-2]
**Files:** `CLAUDE.md`, `CHANGELOG.md`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (modify).
**Work:** version → v14.18.0; CHANGELOG; CLAUDE banner; counts unchanged. Run both gates.
```yaml
provides:
  - {kind: file, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: file, name: scoreboard_sections, from: ST2}
```

## Parallelism Analysis
- **Batch 1:** ST1 · **Batch 2:** ST2 · **Batch 3:** ST3 · **Mode:** sequential · **Workers:** 1 (each consumes the prior).

## Skill References
- **ST1:** `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`
- **ST3:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Mitigation |
|---|---|---|
| run-eval.sh persistence breaks its always-exit-0 contract | MED | Append is best-effort/fail-safe; `--no-record` for tests; self-test asserts exit 0 |
| `/insights` errors when eval/twin data absent | MED | Hard AC: sparse-tolerant, both sections render "no data yet", exit 0; test covers absent case |
| Confusion with Claude Code's builtin "Insights" | LOW | Distinct-from-CC pointer added to commands/insights.md |
| Anti-rebloat | LOW | No new command/agent/hook/skill; scripts uncounted; deterministic jq |

## Configuration
- **Mode:** sequential · **Workers:** 1 · **Branch:** `feature/insights-scoreboard` · **Cost:** default
- **References:** `scripts/build-insights.sh` (the aggregator), `scripts/run-eval.sh` (`EVAL_RESULT` shape: `tasks_total/tasks_passed/pass_rate/per_task[]/commit/date/status`), `.supervisor/twin/{contracts/,.provenance.jsonl}` (Twin growth source), `commands/insights.md` (doc).

## Handoff
```
git pull
/supervisor job: .supervisor/jobs/pending/2026-06-07-insights-twin-scoreboard.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-07T08:13:16Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/35
- **Branch:** feature/insights-scoreboard
- **Files changed:** 11
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Contract conformance:** advisory_violations (1 advisory — run-eval.sh read-only invariant superseded by new persistence)
- **Benchmark:** pass (selftest_pass_count=4)
- **Summary:** ST1 eval-history persistence + ST2 two new /insights sections (Eval fitness, Twin growth) + ST3 v14.18.0/CHANGELOG/currency. 3/3 subtasks PASS; integration review PASS first pass (0 fix iterations). Tests 9/0 + 39/0; both CI gates green.
