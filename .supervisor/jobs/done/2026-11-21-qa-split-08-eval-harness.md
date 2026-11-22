# Supervisor Job: Selvedge eval harness — held-out false-PASS / false-FAIL / abstention rates with Clopper-Pearson intervals, and the Phase 3 gate

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/` — unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (unrelated untracked dirs; 6 extra worktrees listed by `git worktree list`)
- **Source requirement:** .supervisor/requirements/qa-split/08-eval-harness-and-the-phase-3-gate.md
- **Base commit:** cce7bb642ab5d3858e8c3216c9364bad49b849bf

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Selvedge is Node >= 18 standard-library-only ES modules plus bash 3.2 tests (`selvedge/lib/verdict.mjs` header: "Node >= 18, standard library only."); the harness fits that stack. |
| 2 | Dependency Availability | GO | No new dependency: Clopper-Pearson is computed in stdlib JS; the planner is the existing `claude -p` default (`selvedge/lib/plan-planner.mjs`, `DEFAULT_PLANNER_MODEL = 'sonnet'`). |
| 3 | Architecture Fit | GO | `selvedge/eval/` is the owner-only measurement folder; `eval-set.mjs` already exports `loadSet`, `manifestCheck`, `readAnswers`, `heldOutDir` for reuse. Selvedge imports nothing from `loomwright/`. |
| 4 | Scope vs Supervisor Capability | CAUTION | About 11 files, under the split threshold: one subtask. The real held-out run (Validation 2) is long, though: it revives every held-out sports-management commit with local Supabase and spends 3 planner passes over the held-out set, so it is the subtask's last step, after the static gate is green. |
| 5 | Hard Blockers | CAUTION | The real run needs the outside folder (`~/.claude/selvedge-eval/held-out/`, present with `answers.json`), Docker + supabase CLI + npm for commit revival, Playwright, and `claude` for the planner. Planted held-out variants do not exist yet (item 07 left them open), so the first real run covers real-bug and non-defect cases only. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add a harness under `selvedge/eval/` that runs the normal Selvedge path (plan → freeze → model-free run → verdict) on every held-out (or tuning) known-answer case, scores the verdicts against the manifest-checked answers, writes a per-engine-version report (false-PASS, false-FAIL, abstention rates with Clopper-Pearson 95% intervals, `model-judged` apart, per-defect and per-app groups, planner and runner repeatability apart) to a committed results file, prints the Phase 3 gate verdict, and keeps a README results block generated from that file — then run it once for real on the held-out set.

**Problem Statement:**
The owner, deciding whether Selvedge goes into Loomwright (Phase 3), needs one re-runnable command that reports Selvedge's held-out false-PASS, false-FAIL and abstention rates with their intervals, because the Phase 3 gate (false-PASS ≤ 5% point estimate and abstention ≤ 20% on the held-out set) must be a number anyone can re-run, not a claim.
Currently, item 07 delivered the known-answer set (`selvedge/eval/eval-set.mjs`, `held-out/cases.json`, the outside `answers.json` behind `held-out/manifest.sha256`) but nothing runs Selvedge on it or scores it. Without an abstention cap, answering NOT_VERIFIABLE to everything scores 0% false-PASS; without intervals, a small set's 5% means nothing.
Success looks like a committed results file holding the current engine version's held-out report and gate verdict, and a README block that a selvedge test proves matches it.

## Design decisions
- decision: where the harness and the rate/interval math live
  chosen: two new modules — `selvedge/eval/stats.mjs` (pure: rates, Clopper-Pearson, gate, revision rule; no I/O) and `selvedge/eval/harness.mjs` (CLI: run, score, write results, sync README) — importing the set loading and manifest check that `selvedge/eval/eval-set.mjs` already exports
  rejected: append to `selvedge/eval/eval-set.mjs` — blast radius `no`: the file is 678 lines (past the §"Module layout" threshold) and `test-eval-set.sh` pins each of its reason tokens to exactly one code line, so new tokens there widen that pin
  rejected: re-implement set loading / manifest check inside the harness — reversibility `no`: a second copy of the manifest rule drifts from `eval-set.mjs`'s
  evidence: `grep -n '^export function' selvedge/eval/eval-set.mjs` → `loadSet`, `checkSet`, `readManifest`, `manifestCheck`, `readAnswers`, `heldOutDir`, `sideOf` are exported; `wc -l selvedge/eval/eval-set.mjs` → 678
  revisit when: a second consumer of the stats outside `selvedge/eval/` appears (then `stats.mjs` may move under `selvedge/lib/`)
  status: confirmed
- decision: how the Clopper-Pearson 95% interval is computed
  chosen: exact Clopper-Pearson in standard-library JS (bisection on the binomial tail sums, or the regularized incomplete beta), with the closed-form edges: lower = 0 when k = 0, upper = 1 when k = n
  rejected: an npm stats package (e.g. jStat) — already in lockfile `no`: selvedge has no `package.json` and every lib header says "Node >= 18, standard library only."
  rejected: Wilson or normal-approximation interval — fits stack `yes` but it is not the interval the plan and the owner decision name (Q7: "Clopper-Pearson 95% interval"), and the normal form collapses at the 0-miss edge
  evidence: `ls selvedge/package.json` → absent; requirement AC1 "Clopper-Pearson 95% interval … 3 misses in 60 gives an upper bound of 13.9%"
  revisit when: never for the gate; only if the plan's interval definition changes
  status: confirmed
- decision: how a case's target (a sports-management commit, or a planted variant) is brought up on localhost for each run
  chosen: a driver script `selvedge/eval/target-driver.sh` with `up <target-json> <workdir>` (prints `origin=<url>` and `root=<dir>` lines) and `down <workdir>`, called by the harness and overridable by `SELVEDGE_EVAL_TARGET_DRIVER`. For a `commit` target the driver implements item 07's revival recipe AS CODE, using each `selvedge/eval/real-bugs.json` entry's `setup` lines (prose) as its specification: a scratch clone outside this repo checked out at the sha; `supabase/config.toml` copied READ-ONLY from the owner's local sports-management checkout (path from `SELVEDGE_EVAL_SM_CHECKOUT`; the driver never writes there) and patched to project id `selvedge-eval-sm` and ports 553xx; `npm ci`; `supabase db reset --local`; `.env.local` from `supabase status -o env` plus the recorded local secrets/dummy keys; the `NEXT_FONT_GOOGLE_MOCKED_RESPONSES` fetch; `rm -rf .next; next dev -p 3471`. A step that no longer matches the commit (a missing file, a failed command) makes `up` exit non-zero with the step named, and the harness stops with `target_unavailable` — never a guessed workaround. A `variant` target is served with `node`
  rejected: a new selvedge.json hook (e.g. `start`) — blast radius `no`: `HOOK_KEYS` in `selvedge/lib/env-config.mjs` is the closed set `['seed', 'reset', 'auth_setup']`; adding one changes the CLI, outside this item
  rejected: bring targets up by hand before each run — reversibility `yes` but test cost `no` and it defeats "a number anyone can re-run"
  evidence: `grep -n HOOK_KEYS selvedge/lib/env-config.mjs` → `export const HOOK_KEYS = Object.freeze(['seed', 'reset', 'auth_setup']);`; `real-bugs.json` entries carry `setup.parent` / `setup.fix` step lists (item 07 recorded them for item 08's reuse)
  revisit when: Selvedge grows a first-class app-start hook
  status: confirmed

## Acceptance Criteria
- [ ] AC1 — Given a results fixture with known counts, when the harness computes the rates, then each rate and its Clopper-Pearson 95% interval match a reference table in `selvedge/tests/test-eval-harness.sh` to 4 decimal places, including the 0-miss edge (lower bound 0.0000) and the all-miss edge (upper bound 1.0000), and 3 misses in 60 gives an upper bound of 0.1392 (the plan's 13.9%).
- [ ] AC2 — Given a held-out folder whose manifest check fails (one byte of `answers.json` changed, a listed file missing, or an extra file), when the harness runs, then it exits non-zero with the `manifest_*` reason and the changed file named on stderr, runs no target, and writes no results (the results file and README are byte-identical before and after).
- [ ] AC3 — Given a run where every criterion is NOT_VERIFIABLE, when the gate is evaluated, then it reports `not met` on abstention (100% > 20%) even though false-PASS is 0%.
- [ ] AC3b — Given a held-out report whose known-FAIL denominator is below `FLOORS.held_out_fail` (imported from `selvedge/eval/eval-set.mjs`, never restated), when the gate is evaluated, then it reports `not met` with the reason that the known-FAIL denominator is below the floor — even when false-PASS ≤ 5% and abstention ≤ 20% (owner decision 2026-11-12: the gate is a point estimate ≤ 5% on ≥ 60 held-out known-FAIL criteria).
- [ ] AC4 — Given a criterion whose evidence class is `model-judged` (the `evidence_class` field of its entry in `verdict.json`'s `criteria`), when the report is written, then it is counted in the report's own `model_judged` section and not in the main rates' numerators or denominators. (The web runner reads `structured-read`, so in a real run this section is normally empty; the test covers it with a fixture verdict.)
- [ ] AC5 — Given 3 replays of one frozen plan set (runner) and 3 fresh plans (planner), when repeatability is reported, then runner flips and planner flips are separate numbers with their flipped case ids listed on their own, and the main rates' denominators equal the held-out case counts — unchanged by the repeats.
- [ ] AC6 — Given the results file, when the README results block differs from what the harness would render from it, then a selvedge test (`selvedge/tests/test-eval-harness.sh`) fails; the harness's `readme` command rewrites the block from the file, never by hand.
- [ ] AC7 — Given the latest engine version, when the harness has run on the held-out set, then the committed results file holds that version's held-out report (rates with numerators, denominators and intervals; false-FAIL; `model_judged`; per-defect and per-app groups; both repeatability numbers; tokens and duration per run; gate verdict), `selvedge/README.md` shows its gate verdict and intervals, and a committed evidence file `docs/evidence/qa-split-08-eval-harness.md` contains the commands run, the harness's printed report and gate line, and the declared line `Verdict: PASS for Validation 2`, and the PR body links to it.
- [ ] AC8 — Given two engine revisions whose held-out reports (each with a known-FAIL denominator at or above the floor) both miss the gate, when the second report is written, then the harness prints that the owner should stop and run the §8 review early, and its output offers no option to raise the abstention cap or loosen the gate.
- [ ] AC9 — Given the report schema, when a report is computed, then it holds false-FAIL = FAIL on known-PASS ÷ all known-PASS with its interval, numerator and denominator; results grouped per defect (`group_id`) and per app (the target repo, or `sample-app` for a variant); and tokens and duration per run.
- [ ] AC10 — Given `--set tuning`, when the harness runs, then it uses the same path and writes a report marked `set: tuning`, and the gate verdict and the two-revision rule read held-out reports only.
- [ ] AC11 — Given the committed results file, when `node selvedge/eval/eval-set.mjs check-leak` runs, then it passes: the results file carries no object with an `answer` key for a held-out case and no map of held-out case ids to PASS/FAIL (flip lists are arrays of `{case_id, verdicts: [...]}`), and no run folder is committed under `selvedge/eval/`.
- [ ] AC12 — Given the finished change, when `bash selvedge/tests/run.sh` runs, then it passes (including the interval table, manifest-refusal, all-abstain, model-judged, repeatability, two-revision and README-sync arms), and `bash scripts/ci-local.sh --affected` is green.

## Scope widening
- docs/evidence/qa-split-08-eval-harness.md
- selvedge/tests/fixtures/eval-harness/**
- accepted: LP-SCOPE 2026-11-21

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `cce7bb642ab5d3858e8c3216c9364bad49b849bf`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/eval/README.md`** — keep: the reason-token table; every token `eval-set.mjs` names stays listed in backticks, because `selvedge/tests/test-eval-set.sh` greps it (`r="$(grep -cF "\`$t\`" "$PLUGIN_DIR/eval/README.md")"`); the harness's own tokens go in a separate harness table, not mixed into `eval-set.mjs`'s; keep the line "The set's sizes are never written here" true (no counts or rates restated in this README — the results live in the results file and the generated `selvedge/README.md` block only). pinned by: `selvedge/tests/test-eval-set.sh` (`TOKENS="split_unreadable`).
- **`selvedge/eval/eval-set.mjs`** (NOT modified — consumed) — mirror: the harness must reuse `manifestCheck` and `readAnswers` (`export function manifestCheck(repo, ctx, outside = heldOutDir())`, `export function readAnswers(heldOut, ctx, outside = heldOutDir())`) with a ctx of the same shape as its private `newCtx` (`return { problems: [], leaks: new Set(), invalid: [], answerGaps: [] };`); mirror the leak rule the results file must survive (`maps held-out case ids to answers`, `carries an answer`) — `check-leak` reads every tracked file under `selvedge/eval/` by content.
- **`selvedge/.claude-plugin/plugin.json`, `selvedge/CHANGELOG.md`, `.claude-plugin/marketplace.json`** — keep: release lockstep; `selvedge/tests/check-release.sh` fails unless the first CHANGELOG heading equals plugin.json's version (`changelog_version_mismatch: plugin.json version`), with heading form `## <X.Y.Z> — <YYYY-MM-DD>`; `scripts/validate-version.sh` fails on marketplace/plugin drift (`Version mismatch detected!`); never a `changelog.d/` fragment for selvedge (`never through the repository's \`changelog.d/\` fragments`). The harness reads the engine version from `selvedge/.claude-plugin/plugin.json` at run time, so the bump comes BEFORE the real run.
- **`selvedge/README.md`** — keep: the `## Measuring Selvedge: the known-answer set` section's pointer style; its sentence that the set's sizes "are not written here" becomes false once the block carries denominators, so reword it to say the sizes appear only in the generated results block below, derived from `selvedge/eval/results.json` and held equal by the AC6 sync test; the results block is the one sanctioned second copy, between fixed begin/end markers, generated by the harness. pinned by: `selvedge/tests/test-plan.sh` (`export README="$PLUGIN_DIR/README.md"`) and other `test-*.sh` that read it — run the full selvedge gate after editing.

## Closed enumerations touched

> Sibling grep at base `cce7bb642ab5d3858e8c3216c9364bad49b849bf`: `grep -rnF 'manifest_extra_file' --exclude=CHANGELOG.md . | grep -v '^./.claude/worktrees\|^./.supervisor'` → 8 hits in 3 files.

- **New harness reason tokens** (e.g. `results_invalid`, `readme_results_out_of_sync`, `target_unavailable`; the worker fixes the final names) (sibling: `manifest_extra_file`) — must be named in:
  - `selvedge/eval/README.md` — the reason-token table (`| \`manifest_extra_file\` | the outside folder holds a file the manifest does not list |`) — extend with a separate harness table.
  - `selvedge/eval/harness.mjs` (create) — its header comment lists every token it emits, each on exactly one code line (same convention as `eval-set.mjs`).
  - `selvedge/tests/test-eval-harness.sh` (create) — a TOKENS loop like `test-eval-set.sh`'s.
  - `selvedge/eval/eval-set.mjs` — no change: its tokens are its own; the harness re-emits `manifest_*` lines from `manifestCheck`'s ctx rather than defining them.
  - `selvedge/tests/test-eval-set.sh` — no change: its TOKENS list covers `eval-set.mjs` only.
- **Gate verdict values** `met` / `not met` — new; named only in `harness.mjs`, `stats.mjs`, the results-file schema text in `selvedge/eval/README.md` and the test.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-eval-harness.sh` — AC3 all-abstain reports `not met` on abstention | flip `abstention_max: 0.2` → `abstention_max: 1` in `selvedge/eval/stats.mjs` |
| `test-eval-harness.sh` — gate `not met` when false-PASS is above 5% | flip `false_pass_max: 0.05` → `false_pass_max: 1` in `selvedge/eval/stats.mjs` |
| `test-eval-harness.sh` — AC1 interval reference table (0-miss, all-miss, 3/60 → 0.1392) | the reviewer replaces the Clopper-Pearson function's return with the normal-approximation interval in a scratch copy of `selvedge/eval/stats.mjs`; the table must go red |
| `test-eval-harness.sh` — AC4 model-judged excluded from main rates | the reviewer deletes the line in `selvedge/eval/stats.mjs` that routes `model-judged` verdicts to the separate section; the main-rates arm must go red |
| `test-eval-harness.sh` — AC2 manifest refusal writes nothing | the reviewer deletes the harness's early return after a non-empty `manifestCheck` ctx in `selvedge/eval/harness.mjs`; the "no results written" arm must go red |
| `test-eval-harness.sh` — AC6 README-sync | the reviewer makes `check-readme`'s comparison in `selvedge/eval/harness.mjs` always report equal (a scratch copy); the sync arm must go red |
| `test-eval-harness.sh` — AC3b known-FAIL floor | the reviewer deletes the floor condition (`FLOORS.held_out_fail`) from the gate function in `selvedge/eval/stats.mjs`; the below-floor arm must go red |
| `test-eval-harness.sh` — AC5 repeats never enter the main denominators | the reviewer adds the replay/extra-plan verdicts to the main tallies in `selvedge/eval/stats.mjs`; the denominators-unchanged arm must go red |
| `test-eval-harness.sh` — AC9 false-FAIL rate and per-group schema | the reviewer deletes the false-FAIL entry from the report built in `selvedge/eval/stats.mjs`; the report-schema arm must go red |
| `test-eval-harness.sh` — AC10 tuning never feeds the gate | the reviewer drops the `set === 'held-out'` filter from the gate / two-revision reader in `selvedge/eval/stats.mjs`; the tuning arm must go red |
| `test-eval-harness.sh` — AC11 results file survives check-leak | the reviewer writes the flip list as an `{case_id: verdict}` map in `selvedge/eval/harness.mjs`; the fixture `check-leak` arm must go red |
| `test-eval-harness.sh` — token-budget stripped from every selvedge child | the reviewer removes the env stripping for the `run` child in `selvedge/eval/harness.mjs`; the no-`budget_exceeded` arm must go red |
| `test-eval-harness.sh` — harness TOKENS loop (each token on one code line, in the header, in eval/README.md) | the reviewer deletes one token's row from the harness table in `selvedge/eval/README.md`; the TOKENS loop must go red |
| `test-eval-harness.sh` — AC8 two-revision stop | flip `revisions_before_review: 2` → `revisions_before_review: 3` in `selvedge/eval/stats.mjs` |

The `stats.mjs` gate constants are named so the three flip rows above apply by script: `GATE = Object.freeze({ false_pass_max: 0.05, abstention_max: 0.2, revisions_before_review: 2 })` (exact literals).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Eval harness, stats, target driver, tests, release 0.9.0 and the real held-out run | AC1–AC12 (incl. AC3b) | 5 modify, 6 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/eval/stats.mjs"}
  - {kind: "symbol", path: "selvedge/eval/stats.mjs", name: "clopperPearson"}
  - {kind: "symbol", path: "selvedge/eval/stats.mjs", name: "GATE"}
  - {kind: "file", path: "selvedge/eval/harness.mjs"}
  - {kind: "file", path: "selvedge/eval/target-driver.sh"}
  - {kind: "file", path: "selvedge/tests/test-eval-harness.sh"}
  - {kind: "file", path: "selvedge/eval/results.json"}
  - {kind: "file", path: "docs/evidence/qa-split-08-eval-harness.md"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.9.0"}
requires: []
lanes:
  - "selvedge/eval/stats.mjs"
  - "selvedge/eval/harness.mjs"
  - "selvedge/eval/target-driver.sh"
  - "selvedge/eval/README.md"
  - "selvedge/eval/results.json"
  - "selvedge/tests/test-eval-harness.sh"
  - "selvedge/tests/fixtures/eval-harness/**"
  - "selvedge/README.md"
  - "selvedge/CHANGELOG.md"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "docs/evidence/qa-split-08-eval-harness.md"
external_requires:
  - "node >= 18 and git on PATH (the test fails, never skips, without them)"
  - "for the real run only: the outside held-out folder (~/.claude/selvedge-eval/held-out/ or $SELVEDGE_EVAL_HELD_OUT) passing `node selvedge/eval/eval-set.mjs manifest check`"
  - "for the real run only: Docker + supabase CLI + npm to revive sports-management commits (item 07's recorded setup), Playwright for `selvedge run`, and `claude` for the default planner"
```

### Notes for the workers

- **Step order (one worker):** (a) build stats, harness, driver, tests and eval docs until `bash selvedge/tests/run.sh` is green, commit; (b) the release + real run below.
- **What the harness does.** `node selvedge/eval/harness.mjs run --set held-out|tuning` : (1) `validate` the set and, for held-out, `manifestCheck` + `readAnswers` (stop on any problem before anything runs; write nothing); (2) per target (cases grouped by target, so each commit is brought up once), `target-driver.sh up`, write criteria for that target's cases and a `selvedge.json` allowing only the driver's origin into the target's workspace (never into this repo), run `selvedge plan`, `selvedge run`, read `verdict.json`, `target-driver.sh down`; (3) score each criterion's verdict against its known answer; (4) append the report for engine `{selvedge_version from plugin.json, planner_model from SELVEDGE_PLANNER_MODEL or the planner default}` to `selvedge/eval/results.json`; (5) print the rates and the gate line. Repeatability: `--planner-repeats 3` (run 1 is the main run; plans 2–3 only feed the planner-flip number) and `--runner-repeats 3` (`selvedge run --replay` of run 1's frozen plans). A target the driver cannot bring up stops the run with its reason (never silently scored). `node selvedge/eval/harness.mjs readme` rewrites the `selvedge/README.md` block from the results file; `node selvedge/eval/harness.mjs check-readme` fails when they differ (the test calls it). Run folders, clones and logs live under a work dir outside the repo (default under `${TMPDIR}`), never under `selvedge/eval/`.
- **Scoring.** Abstention = (BLOCKED + NOT_VERIFIABLE) ÷ all criteria scored (model-judged excluded). False-PASS = PASS on known-FAIL ÷ known-FAIL. False-FAIL = FAIL on known-PASS ÷ known-PASS. Each with Clopper-Pearson 95% (two-sided, α = 0.05) and its numerator/denominator. Gate: `met` iff the held-out known-FAIL denominator ≥ `FLOORS.held_out_fail` (imported from `eval-set.mjs`) AND false-PASS point estimate ≤ `GATE.false_pass_max` AND abstention ≤ `GATE.abstention_max`, on a held-out report only; a `not met` line names every condition that failed. Two-revision rule: when the results file holds held-out reports for `GATE.revisions_before_review` or more distinct engine versions and all miss the gate, print the stop-and-review line.
- **Tests stay hermetic** (`test-eval-set.sh`'s pattern): temp HOME, `SELVEDGE_EVAL_HELD_OUT` in a temp dir, fixture sets in temp git repos, a stub planner (`SELVEDGE_PLANNER`, see `selvedge/tests/fixtures/stub-planner.sh`) or pre-baked verdict fixtures, and a stub target driver; no network, no Docker, no real `claude`. The real-tree arm: when `selvedge/eval/results.json` is tracked, `check-readme` must pass on the real README; when it is not, the README must carry no block.
- **Release + real run order (step b):** bump the release first (plugin.json + marketplace.json + `## 0.9.0 — <today>` CHANGELOG heading), then run the harness on the held-out set with both repeat counts, then `harness.mjs readme`, then `eval-set.mjs check-leak` and `bash selvedge/tests/run.sh`. If the engine misses the gate, that is a valid result: commit the report as it is (the plan says stop and review, never loosen). If the run cannot complete (a commit will not revive), record the reason in the evidence file and stop — do not lower the bar or score a partial set as the gate.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single subtask)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | none (single subtask) | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| harness (step a) | `selvedge/eval/README.md` (152 — appending the harness commands, its reason tokens and the results-file schema: it is the eval folder's single doc) | `selvedge/eval/stats.mjs` (rates, Clopper-Pearson, gate, revision rule), `selvedge/eval/harness.mjs` (run / score / results / readme / check-readme), `selvedge/eval/target-driver.sh` (target bring-up), `selvedge/tests/test-eval-harness.sh` (+ fixtures under `selvedge/tests/fixtures/eval-harness/`) | HIGH (files) / MEDIUM (commit revival in the driver) |
| release + real run (step b) | `selvedge/README.md` (1030 — the generated results block goes inside the existing `## Measuring Selvedge: the known-answer set` section: it is the plugin's single user doc and the requirement names it), `selvedge/CHANGELOG.md` (269), `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (137) | `selvedge/eval/results.json`, `docs/evidence/qa-split-08-eval-harness.md` | HIGH (files) / LOW (whether every held-out commit revives in one session) |

Module layout: every new responsibility has its own CREATE module (stats vs. orchestration vs. bring-up vs. test). No helper is copied: the harness imports `manifestCheck` / `readAnswers` / `loadSet` / `heldOutDir` from `eval-set.mjs` and invokes `selvedge/bin/selvedge` as a child process (the normal path). The test reuses `test-eval-set.sh`'s `ok`/`ko`/`finish` and temp-HOME idiom by its own copy, as each selvedge test does (there is no shared test lib for these beyond `selvedge/tests/lib/run-helpers.sh`, which the worker may source if it fits).

### Blast-Radius / Impact Prediction

> **Advisory** — System Twin contracts + the `twin-graph.sh` graph, subordinate to `CLAUDE.md`; does not gate decomposition.

| Touched Subsystem | Depends On (`DEPENDS_ON`) | Depended-on-by — derived dependents (`DEPENDED_ON_BY`) | Source Contract | Incident History |
|-------------------|---------------------------|-------------------------------------------------------|-----------------|------------------|
| `.claude-plugin/marketplace.json` | — | `loomwright/docs/qa-removal-manifest.md` | none | none |

**Predicted ripple beyond directly-touched files:** `loomwright/docs/qa-removal-manifest.md` (reads marketplace.json; a version-only change to the selvedge entry should not affect it).

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

How the brief honors them: the results file is the one authority for the rates; the `selvedge/README.md` block is the single second copy the requirement asks for (the owner's consumer), generated by `harness.mjs readme` and held equal by a sync test (AC6) — the rule's "last resort" case. `selvedge/eval/README.md` restates no rate or count.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): reviving every held-out sports-management commit (Supabase migrations, `npm ci`, env) may not finish in one session | HIGH | The real run is the subtask's last step, after the static gate is green and committed, so the code survives a long run; the driver reuses item 07's recorded `setup` steps, one scratch clone and its own Supabase project id/ports (553xx, never the owner's 543xx); a commit that will not revive stops the run with its reason in the evidence file — never a partial set scored as the gate |
| Feasibility (Phase 2.5): planted held-out variants do not exist yet, so the first held-out report covers real-bug + non-defect cases only, and the held-out known-FAIL count is below Q7's 60 floor | MEDIUM | By AC3b the first real run's gate is `not met` (known-FAIL below the floor) whatever its rates — the honest outcome; the report still publishes the rates and intervals; the results file holds one report per engine version, so a re-run after the planted set lands is just another run. A below-floor `not met` is not an engine revision missing on accuracy, so it does not count toward the two-revision §8 rule (AC8 counts reports with a full denominator only) |
| Feasibility (Phase 2.5): planner token cost — 3 planner passes over the held-out set | MEDIUM | Nothing caps the cost; it is made visible: tokens and duration per run are recorded in the report (from `.selvedge/runs.jsonl` `planner_tokens` / `duration_ms`). The harness does NOT set `SELVEDGE_PLANNER_TOKEN_BUDGET` for a gate run (a plan over budget is BLOCKED `budget_exceeded` after its tokens are spent, which would inflate abstention); the harness strips it from the environment of EVERY selvedge child process it starts (`plan`, `run` and `run --replay` — `selvedge/lib/runner/run.mjs` reads it at run time and BLOCKs a plan over budget), with a hermetic test arm proving a fixture run reports no `budget_exceeded` while the variable is set in the parent env; any `budget_exceeded` BLOCKED it still sees is reported on its own line, never silently folded into abstention |
| Once planted held-out variants land, per-group counts plus the flip lists (`{case_id, verdicts}`) could let a reader work out planted held-out answers even though `check-leak` passes (no `answer` key, no id→PASS/FAIL map) | LOW | Today every held-out answer is already derivable from committed data (`selvedge/eval/README.md` §"What the outside folder does not hide"); `selvedge/eval/README.md` gains a note that, when the planted set lands, per-group counts and flip lists for planted groups must be re-checked for answer exposure before they are committed |
| The committed results file trips `check-leak` (`held_out_answer_committed`) by listing per-case answers or an id→PASS/FAIL map for held-out cases | HIGH | AC11: flips are arrays of `{case_id, verdicts: [...]}`, groups carry counts only; the test runs `check-leak` on a fixture repo with a results file, and step (b) runs it on the real tree |
| A Selvedge workspace or `selvedge.json` written into this repo, or the owner's own sports-management checkout or Supabase stack, is touched | HIGH | Workspaces live under a work dir outside the repo; the driver clones into scratch and never writes to the owner's checkout; it checks `supabase status` and uses its own project id |
| Engine misses the gate | LOW | A valid outcome: commit the report; two misses print the §8 stop line; never loosen the gate or raise abstention (non-goal) |
| Planner nondeterminism makes one run unrepresentative | MEDIUM | The planner-variance number (3 fresh plans) makes it visible, reported apart from runner variance |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-21-qa-split-08-eval-harness.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/973
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/qa-split/08-eval-harness-and-the-phase-3-gate.md (https://github.com/vikashruhilgit/loomwright/pull/973) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
