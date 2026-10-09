# 08 — Shard GitHub CI's self-test suite across a job matrix, keeping the required `ci` check fail-closed

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
06

## Touches
.github/workflows/ci.yml
loomwright/scripts/run-self-tests.sh
loomwright/scripts/test-run-self-tests.sh
scripts/test-ci-local.sh
loomwright/scripts/fixtures/self-test-weights.tsv
changelog.d/throughput-08-ci-suite-shard.md

## Problem
`.github/workflows/ci.yml` has one job, `ci`. Inside it, the "Run full deterministic self-test suite (hard gate)" step calls `bash loomwright/scripts/run-self-tests.sh`, and that step dominates every push.

**Measured on PR #435's five pushes (`gh run list --workflow ci.yml`, check-runs per commit):**
- The `ci` run took 11.6–15 min per push:
  - `87f2205` 11m37s
  - `3a1cf14` 14m56s
  - `842cbe7` 11m51s
  - `77fc06b` 13m36s
  - `783b00b` 12m00s
- `claude-review` finished first on all five, so `ci` is the critical path of every push.
- On run 37809076650 (`783b00b`), step timestamps show:
  - the static gate steps (version … capability contract) done 31 s after checkout (16:28:42Z → 16:29:13Z);
  - `test-ci-local.sh` 40 s;
  - the suite step alone **10m12s** (16:29:57Z → 16:40:09Z);
  - sdk-spike 8 s.
- That suite step logged `running 134 self-tests: 131 concurrently (4 at a time), then 3 serially` and `all 134 self-tests passed (wall 612s, 4-way)`. Its per-test PASS times sum to 1846 test-seconds. That is ≈462 s of ideal 4-way work plus a 145 s serial tail: `test-ci-slot.sh` 103 s, `test-harvest-conventions.sh` 24 s, `test-build-floor.sh` 18 s. Item 06 removes that tail.
- The CI floor is the longest single test: `test-automate-trail.sh` 235 s on the runner. Next come `test-verify-walkthrough.sh` 149 s, `test-setup-ui.sh` 134 s and `test-meta-sync.sh` 121 s.

So one 4-vCPU runner is CPU-bound on ≈1846 test-seconds. Sharding the suite over N runners divides the batch part by N, down to the longest-test floor. It cannot help while a serial tail stays inside a shard, which is why this item depends on 06.

**Constraints that are easy to break:**
- **The required check.** `gh api repos/vikashruhilgit/loomwright/branches/main/protection` (read 2026-10-09) shows `required_status_checks.contexts: ["ci"]`, `checks: [{context: "ci", app_id: null}]`, `strict: true`, plus 1 required approving review.
  - Matrix jobs report as `<job> (<k>)`, so the `ci` context must still be produced by exactly one job.
  - **A job skipped because a `needs:` dependency failed reports `skipped`, and GitHub treats a skipped required check as passing.** An aggregating `ci` job with a plain `needs:` would therefore turn a red shard into a mergeable PR. It must run with `if: always()` and fail unless every needed job's `result` is `success`.
- **ci-local derives its gates from ci.yml text.** The `gates=()` block in `scripts/ci-local.sh` greps the whole file for `bash (scripts/<x>.sh( --self-test)?|loomwright/scripts/<x>.sh --check)`. Any NEW `bash scripts/<x>.sh` line, such as an aggregator script, would silently become a ci-local gate. The shard invocation (`bash loomwright/scripts/run-self-tests.sh --shard …`) does not match the pattern, which is correct.
- **Other tests read ci.yml text.**
  - `scripts/test-ci-local.sh` (W) needs `bash scripts/test-ci-local.sh` and `bash loomwright/scripts/build-capabilities.sh --check` present.
  - `loomwright/scripts/test-run-self-tests.sh` (W) needs `bash loomwright/scripts/run-self-tests.sh` and a job-level `^    timeout-minutes: [0-9]+` line.
  - `scripts/test-check-vendor-coupling.sh` case14a–f pins the vendor step's `git fetch --no-tags --depth=1 origin +refs/heads/main:refs/vendor-coupling/base`, `VENDOR_COUPLING_BASE: refs/vendor-coupling/base`, `VENDOR_COUPLING_REQUIRE_BASE: "1"`, and no `|| true`.
- **Step ordering that encodes behaviour.** The "Pull run history from the metadata branch" step sits AFTER the suite on purpose: "two of its tests change behaviour when real run history is present". In separate jobs every shard has its own fresh checkout, so the pull can no longer leak into the suite. It must still come after any test step in the job it lives in. The Playwright cache (`LOOMWRIGHT_VERIFY_TEST_CACHE`, key from `read-playwright-pin.sh`) must be restored in whichever shard runs `test-verify-walkthrough.sh`.
- **The claude-review self-skip is not triggered.** Editing `ci.yml` does not trigger claude-code-action's self-skip. Only a PR that edits the review workflow file itself is skipped (verified 2026-10-07: loomwright #412 edited only `ci.yml` and was reviewed every round). So this PR's review is real.

## Goal
The `ci` required check finishes in roughly (longest single test + per-job setup) rather than ≈10 min of suite. It stays fail-closed: every test reports, a missing or failed shard fails `ci`, and branch protection keeps reading the same `ci` context. Target: the `ci` check ≤ 6 min wall on a typical push (from 11.6–15 min). The exact target comes from 06's new longest-test floor.

## Scope
1. **Deterministic shard selection (`loomwright/scripts/run-self-tests.sh`).**
   - **`--shard K/N`** (1 ≤ K ≤ N): selects a stable subset of the canonical no-argument suite (the same two globs). Malformed `K/N` or `K>N` exits 1, named. Combining `--shard` with explicit test arguments is a usage error.
   - **`--list`:** prints the selected tests, one per line, and runs nothing. The aggregator uses it.
   - **The split:** pick one by measurement and record why in the PR body.
     - (a) name-hash or round-robin over the sorted list. No data file; balance is uneven.
     - (b) a greedy longest-first split by committed per-test weights, NEW `loomwright/scripts/fixtures/self-test-weights.tsv`, measured from a CI run's PASS times. Every test absent from the file gets a default weight, so a new test is never dropped.

     If (a) is chosen, drop the weights file from Touches before starting.
   - **Invariant, tested:** for every N, the union over K of the `--shard K/N --list` outputs equals the full list, with no duplicates.
   - Serial-marked tests (if 06 leaves any) keep their after-the-batch rule inside the shard that owns them.
   - Admission, watchdog, the hermetic layer and the fail-closed exit rules are unchanged per shard.
2. **Workflow shape (`.github/workflows/ci.yml`).**
   - **A `static` job:** checkout, every existing static gate step verbatim, `test-ci-local.sh`, then the read-only meta-sync pull, sdk-spike, fitness report and eval upload. It keeps the vendor step's env and fetch exactly, so case14 still matches.
   - **A `suite` job:** a `strategy.matrix.shard` over 1..N (choose N by measurement; start at 3–4) with `fail-fast: false`, so every shard reports even when one is red. Each shard restores the Playwright cache, runs `bash loomwright/scripts/run-self-tests.sh --shard ${{ matrix.shard }}/N`, and writes and uploads a per-shard result manifest (each test it ran plus its rc).
   - **A job named exactly `ci`:** `needs: [static, suite]`, `if: always()`. It fails unless `needs.static.result == 'success'` and `needs.suite.result == 'success'`. It downloads every shard manifest and fails closed when a manifest is missing, a test is missing or duplicated against `run-self-tests.sh --list` (the full no-shard list), or any rc is non-zero. Write it as an inline `run:` block. Do NOT add a `bash scripts/<x>.sh` line: ci-local would derive it as a gate.
   - Every job carries a job-level `timeout-minutes` (the `test-run-self-tests.sh` (W) regex). Recompute the 45-minute rationale in the comment per job.
   - No other job may be named `ci`.
3. **Keep every ci.yml-reading test green.** Extend `scripts/test-ci-local.sh` with a fixture ci.yml in the new multi-job shape. ci-local derives exactly the same gate list from it as from the single-job shape, a matrix shard line is never derived as a gate, and a fixture adding an aggregator `bash scripts/agg.sh` line shows the hazard: it IS derived, which is why the real file must not have one. Extend `test-run-self-tests.sh` with `--shard`/`--list` arms: the union invariant, malformed input, args-plus-shard refused, and a test absent from the weights file still scheduled (if (b)).
4. **Docs in the same change:** the ci.yml comments (suite step, `timeout-minutes`, the ci-local mirror note), and the `run-self-tests.sh` header usage.

## Acceptance criteria
- Branch protection is untouched. On the PR, the `ci` check exists, and it is the job that aggregates. A deliberately red shard on a throwaway commit makes `ci` **fail** (not skip), and `gh pr view --json mergeStateStatus` is not CLEAN. Revert the commit before merge and record the run URL in the PR body.
- A deliberately dropped shard manifest (or a test removed from every shard by a mutated split) makes `ci` fail and names the missing test.
- `bash scripts/ci-local.sh --list` prints the same `gate:` lines before and after the ci.yml change (diff in the PR body).
- `test-ci-local.sh`, `test-run-self-tests.sh` and `test-check-vendor-coupling.sh` are green, and the new arms fail on the base commit.
- **Measured on a real PR:** `ci` check wall time (check-run `started_at` → `completed_at`) for 3 pushes after the change, against the five PR #435 baselines above (11.6–15 min), plus each shard's wall and its longest test. Total runner minutes per push are recorded too. Public repo: no billing block is expected, but the cost is visible.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green.
2. The red-shard and dropped-manifest probes above, with their run URLs.
3. The before/after `ci` wall times from real PR runs.
4. `gh api repos/vikashruhilgit/loomwright/branches/main/protection` re-read after merge: still `contexts: ["ci"]`, and the next PR's `ci` check comes from the aggregator job.

## Non-goals
- Changing branch protection, its required contexts, or the review requirement. This is a user-only action, and nothing here needs it.
- Sharding ci-local. Locally the pool is already one machine; items 05 and 06 cover local wall time.
- Editing `.github/workflows/claude-code-review.yml`. That would self-skip the reviewer on this PR.
- Caching test results across pushes, or skipping unaffected tests in CI. Every push still runs every test (owner decision D1's spirit: shrink the run's wall time, never its coverage).
- `concurrency:` cancellation of superseded runs. It is a separate decision with its own trade-off (a cancelled run reports `cancelled`, which a required check treats as not passing).
