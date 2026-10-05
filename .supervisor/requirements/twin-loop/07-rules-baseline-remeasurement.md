# 07 — Append the overdue rules re-measurement row to `RULES_BASELINE.md`

## Status: pending

## Problem
twin-loop/05 (shipped PR #147) committed a baseline row in `loomwright/docs/RULES_BASELINE.md` (2026-08-14) and, in its
Scope §7, promised a comparison row once N = 20 PRs had merged after the first harvested rule batch (`3f4bb2e`,
"dreaming: 2 harvested convention rules", 2026-09-01). On 2026-10-05 about 241 merges have happened since, and
`RULES_BASELINE.md` §"Subsequent rows" still reads "None yet". Without the row nobody knows whether the committed house
rules changed review churn at all, which is the whole point of the rules loop.

## Goal
One comparison row, measured the same way as the baseline, with an honest reading of what it shows.

## Scope
1. Re-run the baseline's measurement procedure exactly as `RULES_BASELINE.md` documents it (same metrics, same
   classification), over the PRs merged after `3f4bb2e` (state the window: first and last PR, count).
2. Append the row under §"Subsequent rows" with date, window, each metric beside its baseline value, and one paragraph:
   what changed, what can and cannot be attributed to the rules (confounders: other review-lane changes in the window).
3. If the documented procedure can no longer be run as written (a script or input moved), say so in the row and record
   the substitute used; never silently change the method.

## Acceptance criteria
- `RULES_BASELINE.md` §"Subsequent rows" has one dated row with the window and per-metric values next to the baseline.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts (docs-only change: doc-currency and citation-drift green).
2. The row's numbers are reproducible from the stated window (paste the command(s) in the PR body).
3. Rollback: `git revert`.

## Evidence
twin-loop/05 §7; backlog validation 2026-10-05 (this session).

## Depends on
none

## Touches
loomwright/docs/RULES_BASELINE.md
changelog.d/twin-loop-07-rules-baseline-remeasurement.md
