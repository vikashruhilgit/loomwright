# 05 — ci-local early gates: a full run fails in seconds when a cheap gate is red, not after the whole pool

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
none

## Touches
scripts/ci-local.sh
scripts/test-ci-local.sh
loomwright/scripts/run-self-tests.sh
loomwright/scripts/test-run-self-tests.sh
loomwright/scripts/test-automate-helpers-dispatch.sh
loomwright/scripts/test-citation-drift.sh
AGENT_GUIDELINES.md
changelog.d/throughput-05-ci-local-early-gates.md

## Problem
**Owner decision D1 (2026-10-09, binding — `00-overview.md` §"Owner decisions"):** the pre-push rule stays. One FULL `bash scripts/ci-local.sh` before every push, drain pushes included, with no "GitHub CI is the full run" exemption. So the only way to make a red push-gate cheaper is to make the full run **fail early**, never to skip it.

Today a full run puts every gate into one pool and reports only at the end:

- `scripts/ci-local.sh` (the `--- plan:` block and the `--- run ---` block) turns every ci.yml gate into a wrapper and appends every root and loomwright self-test, then makes ONE `bash "$runner" "${plan[@]}"` call. The 20 ci.yml gates and the 135 self-tests share a single pool (`ci-local: 20 ci.yml gates + 135 self-tests, one pool` in every PR #435 log).
- `loomwright/scripts/run-self-tests.sh` prints failures only after the whole pool has finished. Its header says so: "a red test does not hide the ones after it: every test runs, then each failure's full log is printed at the end". The verdict-collection loop prints `FAIL` banners only after both `schedule` calls return. The one thing it streams as it happens is a TIMEOUT (the watchdog's `.hang` report).

**Measured (ci-slot run logs `~/.local/state/loomwright/ci-slots/dd8a9612cd818d9a/runs/`, 2026-10-08, attributed by tree key):** PR #435's item made 9 full runs, 639–836 s each (6114 s ≈ 102 min in total). 4 failed. 3 of those 4 were caught only by static gates or by fast, deterministic self-tests, yet each took the full wall time to say so:

| Run (tree key, start) | Wall | What failed | Cheapest thing that catches it |
|---|---|---|---|
| `b8f9698…` 12:54Z | 646 s | `check-vendor-coupling.sh` + `test-check-vendor-coupling.sh` (case15 "live repo passes its own ratchet") + `test-automate-helpers-dispatch.sh` (`--help`/`-h`/no-arg output differs from `automate-helpers-help.golden`) + `test-citation-drift.sh` ("2 pinned citation(s) have DRIFTED") | `check-vendor-coupling.sh` (7 s) + dispatch test (11–12 s) + citation-drift (6 s) |
| `3e7bc89…` 14:29Z | 836 s | vendor-coupling pair + gate `19-build-capabilities.sh` (`build-capabilities.sh --check`, stale `capabilities.json`) + `test-build-capabilities.sh` | `check-vendor-coupling.sh` + `build-capabilities.sh --check` (1–2 s) |
| `e615441…` 14:45Z | 658 s | `test-automate-lanes.sh` S6 (`--keep-awake`; the same tree passed on the immediate rerun at 14:56Z) | not catchable early: a race, item 07 |
| `96b9fcf…` 15:31Z | 639 s | vendor-coupling pair | `check-vendor-coupling.sh` (7 s) |

Per-entry times are from the passing logs of the same item (`1095661…`, `2503f9…`, `d0dd0c…`, `e615441…-1139`). They were measured inside the 6-way pool, so they are upper bounds. The pure static gates (every ci.yml gate that is not a `scripts/test-*.sh` — 13 of the 20) total ≈16–17 s of test time. All 20 gate wrappers, self-tests included, total ≈126 s (`test-ci-local.sh` 45 s, `test-check-vendor-coupling.sh` 31–32 s and `test-check-doc-currency.sh` 26–28 s are the heavy ones). The whole pool totals ≈2808 test-seconds at 6 jobs: ≈470 s ideal against ≈650 s wall.

`--affected` has the matching gap. Its cheap-gate filter (the `case "$s" in scripts/check-*.sh|scripts/validate-version.sh)` arm in the `--- --affected:` block) matches only those two name shapes, so it never schedules `loomwright/scripts/build-capabilities.sh --check`. That is the gate that went red in run `3e7bc89…`. A dismissed Phase 4.5 follow-up already records this: `.supervisor/requirements/proposed/automate-2026-10-07-055816--01-published-capability-contract-fbc9f7--dismissed-summary.md` Entry 1, key `ae6f354e` (PR #412, LOW, "ci-local.sh --affected skips the capabilities --check gate on agent/command/skill/hooks.json edits"). **This item folds it in and closes it.**

CI parity is not at risk. GitHub CI already fails early in effect: ci.yml runs each static gate as its own step before the "Run full deterministic self-test suite" step, and a failing step stops the job. On run 37809076650 (`783b00b`) the static gate steps were done 31 s after checkout. Only the local mirror flattens everything into one end-of-run report.

## Goal
A full `ci-local` run whose tree breaks a cheap gate or an `early`-marked self-test exits 1 within ≈1–2 minutes (slot acquire + early phase), not after ~650–840 s. A green tree still runs every gate and every test exactly once and stamps as today. Expected saving on PR #435: the 3 catchable red runs (646 + 836 + 639 s ≈ 35 min) become ~1–2 min each.

## Scope
1. **Early set, derived, never hand-listed (`scripts/ci-local.sh`).** The early set is:
   - (a) every ci.yml gate the existing `gates=()` derivation finds whose script basename is not `test-*.sh`. That is every `scripts/check-*.sh` / `scripts/validate-version.sh` line with its argument (`--self-test` forms included) **and** every `loomwright/scripts/<x>.sh --check` line (today `build-capabilities.sh --check`). A new gate of either shape joins the early phase automatically.
   - (b) every planned self-test (root or loomwright) that carries the exact line `# run-self-tests: early`.

   The rule is structural (by gate shape and marker), not a list of file names.
2. **One marker parser (`loomwright/scripts/run-self-tests.sh`).** Add the `# run-self-tests: early` marker next to `serial`, with the same `grep -qx` exact-line rule, documented in the header's `marker:` paragraph. Do not re-implement the grep in ci-local. Expose it from the runner instead (e.g. `run-self-tests.sh --select-marked early <tests…>` prints the marked subset in input order), so the two markers keep one parser. In the runner's own default run (what CI's suite step calls), an `early` marker changes nothing: the test stays in the concurrent batch. A test carrying both `early` and `serial` is a usage error (exit 1, named), because the two phases conflict.
3. **Mark the measured-fast candidates, after measuring each alone.** Run each with `time bash <test>` on an idle machine, record the number in the PR body, and mark only those that are deterministic and ≲15 s alone:
   - `loomwright/scripts/test-automate-helpers-dispatch.sh` (help golden; 11–12 s in the pool)
   - `loomwright/scripts/test-citation-drift.sh` (6 s in the pool)

   `scripts/test-check-vendor-coupling.sh` is a ci.yml gate already. It is a `test-*.sh` wrapper, so it is not in (a). At 31–32 s it is not "fast", and its case15 failure was always accompanied by `check-vendor-coupling.sh` (7 s) failing on the same live tree in all three vendor-coupling runs above. So `check-vendor-coupling.sh` in (a) already catches that class. Do not move it early unless the measurement contradicts this, and say so either way.
4. **Early phase in a full run.** After the slot acquire and the post-slot cache re-check, and before the pool:
   - Run the early set through the same runner (`bash "$runner" <early…>`), so the watchdog, the hermetic layer and the fail-closed rules are identical. The nested call folds into ci-local's slot (ci-slot.sh NESTED, as today).
   - **Early red:** print every early failure, not just the first. The runner already runs all of its arguments and prints each failing log; run `b8f9698…` had three distinct early-catchable failures. Then `rm -f "$stamp"` as the pool-failure path does, set a verdict that starts with `ci-local: FAIL` (e.g. `ci-local: FAIL after <n>s — early gates failed; pool skipped (nothing cached)`) so `--last` and `--wait` parse it unchanged, write no PASS stamp, and exit 1 without starting the pool.
   - **Early green:** run the pool with the remaining entries only. Every full-plan entry runs exactly once across the two phases.
   - The tree-moved check and the stamp at the end are unchanged.
5. **Stream FAIL lines as they happen (`run-self-tests.sh`).** When a test finishes non-zero, print one line at once, e.g. `run-self-tests: FAIL (exit <rc>, <secs>s): <test>`, in addition to (not instead of) the full banner and log at the end. Mirror how the TIMEOUT path already reports from the worker. This applies to the pool and the early phase alike, so a reader of a running log, or of `--wait` output, sees a red test within seconds. The end-of-run report and its order (passes, slowest tests, failures last, the `N of M self-tests FAILED` summary) are unchanged.
6. **`--affected` uses the same early set.** Replace the `scripts/check-*.sh|scripts/validate-version.sh` filter with the early-set predicate from step 1. `build-capabilities.sh --check` and the `early`-marked tests then always run under `--affected`, which closes `ae6f354e`. Rename the "cheap gates" wording in its messages and counts to the early-set term. Keep the `refusing to report green on an empty plan` refusal, and keep the "never reads, writes or removes a pass stamp" rule.
7. **`--list` shows the phases.** A full `--list` marks which planned entries are early (e.g. an `early:` prefix, or a separate block). `--affected --list` shows the same early set. Keep the "no temp wrapper paths" rule of arm (LS).
8. **Docs in the same change.** Update the ci-local header (`SAME GATES AS CI`, `--affected`, a new early-phase paragraph), the run-self-tests header (`marker:`), and `AGENT_GUIDELINES.md` §"Pre-push: one command" (the `--affected` bullet's "cheap `check-*`/`validate-version` gates" wording).
9. **Sequencing with pending work (not a dependency).** `automate-followups/34` Part B and `automate-followups/36` Part C also edit `scripts/ci-local.sh` (and 36 edits `scripts/test-ci-local.sh` and `AGENT_GUIDELINES.md`). Run them sequentially with this item, never in one parallel wave. The shared `## Touches` lines already keep the wave planner from co-scheduling them. PR #438's `--wait` is merged. Build on it: the early-red verdict must be what `--wait` returns.

## Acceptance criteria
- A full run on a tree with a red early gate exits 1 with a `ci-local: FAIL …` verdict as the log's last content line. It names every red early entry (fixture: two early gates both red ⇒ both printed), starts no pool entry (a pool sentinel test did not run), leaves no PASS stamp (an existing stamp for the key is removed), and `--last` reports `FAIL <log>`.
- A green tree runs every full-plan entry exactly once across the two phases (fixture: each entry appends to a ledger; no duplicates, none missing) and stamps as today. Arms (P), (C), (U), (F), (O), (M), (X), (Q), (QC), (LG), (LA1–3), (UV) and (PR) still pass.
- The early set is derived. A fixture ci.yml with a new `scripts/check-new.sh` line and a `loomwright/scripts/gen.sh --check` line puts both in the early phase with no edit to ci-local. A `scripts/test-*.sh` gate stays in the pool. A fixture test carrying `# run-self-tests: early` runs early; the same test with the marker removed runs in the pool (mutation control).
- A copy of ci-local that skips the early-red exit is caught by the early-red arm (mutation control).
- `run-self-tests.sh` streams a `FAIL` line for a red test before the end-of-run report (fixture: a fast red test plus a slow green test; the FAIL line precedes the slow test's PASS line in the output). The end report is unchanged. `test-run-self-tests.sh` arms (F), (C) and (S) still pass. A test marked both `early` and `serial` exits 1, named.
- `--affected` runs `build-capabilities.sh --check`-shaped gates and `early`-marked tests: an (AF1)-style fixture with a `--check` gate shows it ran. (AF5) "empty changed set ⇒ early set only" holds, and the empty-plan refusal still fires when the early set and the mapped set are both empty.
- On the real repo, `ci-local --list` shows the early set: the 13 non-`test-*` ci.yml gates today plus the marked tests (the exact count goes in the PR body as evidence, never restated in docs).
- The real-repo early phase is measured: wall time of a forced early-red run (e.g. a deliberately stale `capabilities.json` in a scratch worktree) from `ci-local` start to verdict, recorded in the PR body. Target ≤ 120 s including slot acquire on an idle machine.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the full run, early phase included), with its log path in the PR body.
2. New `test-ci-local.sh` / `test-run-self-tests.sh` arms fail on the base commit and pass on the branch.
3. The forced early-red measurement above, plus one green full run's wall time before vs after on the same machine. Expected roughly unchanged: the early set is a few seconds and leaves the pool.
4. Operator follow-up after merge (the file is gitignored, so it is not in the worktree): remove Entry 1 (key `ae6f354e`) from `.supervisor/requirements/proposed/automate-2026-10-07-055816--01-published-capability-contract-fbc9f7--dismissed-summary.md`, citing this item's PR.

## Non-goals
- Skipping or caching any part of the full run beyond today's whole-tree PASS stamp (D1). The early phase reorders the run. It never shortens a green one.
- Changing CI's suite step behaviour. ci.yml's own steps already stop at the first failure. The `early` marker is inert in a default `run-self-tests.sh` run.
- Stopping at the first early failure. Every early entry runs, so one fix round sees all of them.
- Making `test-check-vendor-coupling.sh`, `test-check-doc-currency.sh` or `test-ci-local.sh` early. They are 26–45 s, and their live-repo arms duplicate gates already in (a).
- Fixing the S6 race (item 07) or the serial tail (item 06).
