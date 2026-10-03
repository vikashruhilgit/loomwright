# Supervisor Job: Prove the Loop — funnel measurement + loop-evidence dashboard + salvaged eval checks

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.12.0 — matches plugin.json)
- **Git:** clean, branch: main (base for feature branch)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Worktrees:** one expected sibling (`loomwright-pr104`, unrelated in-flight PR) — do not touch
- **Blockers:** 0 | **Warnings:** 1 (in-progress brief `2026-07-17-token-budget-ci-gate.md` exists; unrelated files, no overlap)
- **Source requirement:** .supervisor/requirements/twin-remediation/01-prove-the-loop.md

## Task
**Goal:** Build the first real measurement of whether Loomwright's advisory learning loop improves outcomes: a read-only evidence builder that computes the unattended-quality funnel (landed → clean → durable → cheap) per PR from existing on-disk data, buckets PRs by which advisory surfaces existed at run time, renders a `## Loop evidence` section in `/insights`, ports two salvaged eval-corpus regression checks, and records a per-surface written verdict. Analysis of existing artifacts only — no new emitters, no gating, nothing blocking.

**Authoritative spec:** the source requirement file above, including its 2026-07-21 amendments (funnel metric, untrusted self-graded rubric bucketing, salvaged checks, false-zero data-quality trap).

## Acceptance Criteria
- [ ] Given the repo's real `.supervisor/` data, when `build-loop-evidence.sh` runs, then it emits a per-PR funnel table (landed/clean/durable/cheap) bucketed by advisory-surface era (pre/post rules seams v15.1.0, orientation memos v15.12.0, bridge) including per-bucket root-cause class mix from postmortem results.jsonl, with real output shown in the PR description
- [ ] Given missing or partial data for any PR/stage, when the script runs, then that cell degrades to a labeled `insufficient_data` — numbers are never invented (token-ledger convention)
- [ ] Given a PR with 0 GitHub review rounds but drain-internal activity (fix_cycles / heal_iterations / drain-cycle commits), when the funnel classifies it, then it is NOT counted clean (false-zero trap, requirement §Amendment 4)
- [ ] Given a run whose rubric was auto-authored by the same run, when scores are aggregated, then it is bucketed separately from human-approved rubrics (Amendment 2)
- [ ] Given `/insights` runs, then a `## Loop evidence` section renders (suppressed-with-note when no data, dashboard still builds — matching existing section conventions)
- [ ] Given the salvaged `parity-emit-block` and `review-churn-canary` checks are ported into `loomwright/scripts/eval-corpus/`, when `run-eval.sh` runs, then both execute; parity-emit-block passes a mutation test (deleting `heal_decision` from the supervisor emit template fails it) and review-churn-canary replays its true positive on real history
- [ ] Given the analysis completes, then `loomwright/docs/SPIKES/LOOP_EVIDENCE_2026-07.md` records a SUPPORTED / NOT SUPPORTED / INSUFFICIENT DATA verdict per advisory surface with n and stated confounds
- [ ] Given the full diff, then no new advisory emitter/store/reader is introduced (freeze-compatible); the builder/reader scripts (`build-loop-evidence.sh`, insights integration) are read-only, always-exit-0 fail-safe — the ported eval-corpus `check.sh` files instead follow `run-eval.sh`'s contract (exit 0 = pass, non-zero = fail; AC6's mutation test depends on it)
- [ ] CI green: doc-currency, skills-index, command-sync, contract-parity, token-budget

## Outcomes Rubric
- [ ] Funnel table produced from real repo data (not fixtures only) and shown in PR description
- [ ] Per-surface verdict table exists with explicit n and confounds; honest nulls present where data is thin
- [ ] False-zero drain trap demonstrably handled (test case: PR with 0 GitHub rounds + ≥1 drain signal classified not-clean)
- [ ] Both salvaged checks ported, verified (mutation test + true-positive replay documented)
- [ ] Zero new write-side surfaces; all additions read-only fail-safe
- [ ] `/insights` renders with and without loop-evidence data

## Subtask Structure

| # | Title | Est. Files | Confidence | Status |
|---|-------|-----------|------------|--------|
| 1 | `build-loop-evidence.sh` + self-test (funnel + era bucketing + false-zero handling) | create 2 (`loomwright/scripts/build-loop-evidence.sh`, `loomwright/scripts/test-build-loop-evidence.sh`) | HIGH | LAUNCHABLE |
| 2 | Port + verify salvaged eval checks into eval-corpus | create 4 (`loomwright/scripts/eval-corpus/{parity-emit-block,review-churn-canary}/{check.sh,spec.md}` from `.supervisor/requirements/twin-remediation/salvage/`), possibly modify `loomwright/scripts/run-eval.sh` + `loomwright/scripts/eval-corpus/README.md` | HIGH | LAUNCHABLE |
| 3 | `## Loop evidence` section in `/insights` (build-insights.sh + commands/insights.md docs) | modify 2 (`loomwright/scripts/build-insights.sh`, `loomwright/commands/insights.md`) | MEDIUM | BLOCKED (by #1) |
| 4 | Run analysis on real data; write `LOOP_EVIDENCE_2026-07.md` verdict doc (+ funnel definition adapted from salvage `NORTH_STAR.md`, corrected for its false empty-logs premise) | create 1 (`loomwright/docs/SPIKES/LOOP_EVIDENCE_2026-07.md`) | MEDIUM | BLOCKED (by #1) |

### Subtask contracts

Subtask 1
provides:
  - {kind: file, path: loomwright/scripts/build-loop-evidence.sh}  # CLI: markdown funnel table to stdout; exit 0 always; optional --jsonl; MUST accept --state-dir <abs path> (default ./.supervisor) so callers outside the main checkout can point at real data
  - {kind: file, path: loomwright/scripts/test-build-loop-evidence.sh}  # fixture-driven; includes false-zero, insufficient_data, and --state-dir cases
requires: []
external_requires:
  - .supervisor/logs/*.jsonl, .supervisor/postmortem/results.jsonl, .supervisor/heal-signal/results.jsonl (read-only; absent ⇒ labeled degradation)

Subtask 2
provides:
  - {kind: file, path: loomwright/scripts/eval-corpus/parity-emit-block/check.sh}
  - {kind: file, path: loomwright/scripts/eval-corpus/parity-emit-block/spec.md}
  - {kind: file, path: loomwright/scripts/eval-corpus/review-churn-canary/check.sh}
  - {kind: file, path: loomwright/scripts/eval-corpus/review-churn-canary/spec.md}
requires: []
external_requires:
  - .supervisor/requirements/twin-remediation/salvage/ (source copies; review + adapt, do not blind-copy)

Subtask 3
provides:
  - {kind: symbol, path: loomwright/scripts/build-insights.sh, name: "## Loop evidence"}
  - {kind: file, path: loomwright/commands/insights.md}  # updated docs row, same commit
requires:
  - {kind: file, path: loomwright/scripts/build-loop-evidence.sh, from: 1}

Subtask 4
provides:
  - {kind: file, path: loomwright/docs/SPIKES/LOOP_EVIDENCE_2026-07.md}
requires:
  - {kind: file, path: loomwright/scripts/build-loop-evidence.sh, from: 1}

**Worktree data-visibility instruction (subtask 4, MANDATORY):** gitignored `.supervisor/` does NOT exist in worker worktrees (documented repo trap). Subtask 4's worker MUST invoke the builder with the pinned absolute main-checkout state dir: `bash loomwright/scripts/build-loop-evidence.sh --state-dir ~/Documents/work/AI/ai-agent-manager/.supervisor` (read-only access; never write there). An all-insufficient_data table caused by a missing/mistyped state dir is a FAILURE of this subtask, not an acceptable honest null — the worker must distinguish "data absent" from "data not visible from here".

## Parallelism Analysis

### Dependency Graph
- 1 → 3, 1 → 4; 2 independent

### File Overlap Matrix
- No file overlaps between subtasks (1: new scripts; 2: new eval-corpus dirs + run-eval/README touch; 3: insights pair; 4: new doc). Subtask 2's possible `run-eval.sh` edit overlaps nothing else.

### Batch Plan
- Batch 1: #1, #2 (parallel, 2 workers)
- Batch 2: #3, #4 (parallel after #1)
- Recommended workers: 2

## Skill References
- `skills/monitoring-observability` (subtasks 1,3), `skills/unit-testing` (1,2), `skills/quality-checklist` (all). Conventions: existing `read-*.sh` fail-safe reader pattern; `scripts/eval-corpus/README.md` task layout; build-insights.sh section-suppression conventions.

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| macOS-green ≠ CI-green (stat/date/sed flavors) in new bash scripts | MEDIUM | memory: stat-flavor-setu-arithmetic-trap | POSIX-portable idioms; numeric validation before arithmetic; self-test covers |
| bash 3.2 perf trap on large strings (multibyte pattern-sub O(n²)) | MEDIUM | memory: bash32-pattern-sub-wedge | avoid `${var//…}` over large log payloads; stream with jq/awk |
| insights section-enumeration drift (docs list sections; gate does NOT scan them) | MEDIUM | CLAUDE.md §doc-currency unscanned surfaces | subtask 3 updates command doc + build-insights.sh in same commit; consistency sweep |
| Era bucketing misattribution (surface ship-date vs run's plugin_version) | MEDIUM | Feasibility (Phase 2.5) | bucket by per-run `plugin_version` stamp where present, ship-date fallback labeled |
| Small n / confounded verdicts overclaimed | HIGH | requirement (honest nulls) | verdict doc must state n + confounds; INSUFFICIENT DATA is an acceptable outcome |
| Salvaged checks authored in a different worktree against v15.9-era layout | LOW | Phase 2.5 CAUTION | re-verify MANIFEST paths + mutation test in this tree before wiring |

## Configuration
- Base Branch: main
- heal_iterations: 3 (default)
- Cost profile: default (inherit)
- red_team: off (doc/analysis-only diff, low-risk)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-21-prove-the-loop.md

## Outcome
- **Status:** completed
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1
- **heal_remaining_issues:** 0 BLOCKING/HIGH (5 MEDIUM/LOW recorded non-gating: parity-emit-block fail-open args; MANIFEST reciprocal comment; era-attr non-monotonic-ts edge; canary knobs in eval mode; committed absolute path in SPIKE doc)
- **rubric_score:** 6/6 (self_graded — rubric auto-authored by this run's Launch Pad; see LOOP_EVIDENCE_2026-07.md §tautology)
- **red_team_advisory:** disabled
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/105
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260721T051148Z-93772bc65b4a8e56099edd1177dff6c6a0d90d61.log
