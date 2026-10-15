# automate-speed/23 — Measure whether v17.2.0 ended the 3/3 heal rounds, and what Plan Review attempts cost

## Status: pending

## Problem
Since 2026-10-12 every `/automate` item used all 3 Phase 4.5 rounds; on PR #533 Phase 4.5 took 85m and ended
ESCALATED. automate-speed/02 (v17.2.0, PR #538) changed Phase 4.5 to read CI once and run pin mutations once, and
predicted fewer rounds, but nothing has measured it yet. Plan Review also used 3 of 3 attempts on #533 (13m for
Launch Pad). Both are quality gates: they must not be capped on a guess (plan doc §Why now).

## Goal
<!-- bump: patch -->
A committed evidence file reports, for every item merged on v17.2.0 or later: Phase 4.5 rounds and duration,
termination reason, Plan Review attempts and Launch Pad duration, compared with the items before v17.2.0. If heal is
still 3/3 on most items, a propose-only draft explains why each round found new HIGH findings.

## Scope
- Use item 03's per-item report and `.supervisor/postmortem/results.jsonl` (`self_heal_rounds`); no new tool.
- `docs/evidence/review-gate-rounds.md`: the commands, a table per item, and the before/after comparison.
- If ≥ half of the post-v17.2.0 items still hit 3/3: read their iteration findings and classify each new HIGH as
  (a) present before round 1 and missed, (b) introduced by a fix, (c) found by a check that earlier rounds did not run.
  Write the result as a propose-only draft in `.supervisor/requirements/proposed/` (not in this PR's diff).

## Non-goals
- Changing Phase 4.5, Plan Review or any cap.

## Acceptance criteria
- `docs/evidence/review-gate-rounds.md` lists every `/automate` item merged on ≥ v17.2.0 (at least 3; if fewer exist,
  the file says so and the item parks) with rounds, duration, termination reason, Plan Review attempts.
- The PR body links to the evidence file.

## Validation (must pass before merge)
1. `check-doc-currency.sh`; the commands in the evidence file re-run and print the same table.

## Measurements
- Re-run the same report after this set's Phase 1 lands; append the result. Frozen commit: this PR's merge commit.

## Depends on
03

## Touches
docs/evidence/review-gate-rounds.md
changelog.d/as23-measure-review-gates.md
