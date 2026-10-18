# automate-speed/12 — Apply the next-step pattern inside the review-heal drain loop

## Status: pending

## Problem
`skills/review-heal/SKILL.md` is 133KB (plus `commands/review-pr.md` and `agents/review-pr.md`). The drain loop's
round counter, CI wait, bot-review classification, fix-cycle bookkeeping, `drain-rounds.sh bump`, the posted
comments and the terminal `REVIEW_HEAL_RESULT` are deterministic; validating a finding and writing a fix are
judgment. PR #533's single drain round took 2h11m while GitHub CI took ~7m and claude-review ~5.5m (plan doc §Why now).

## Goal
<!-- bump: minor -->
A `review-heal-next-step.sh` driver owns the drain loop's deterministic steps and hands the model one instruction at a
time (validate these findings; spawn a fix worker; done), using the instruction schema from item 06.

## Scope
- Golden fixtures for the `review-heal` inventory group's GAP rows first (method of item 05), then migrate: round
  counting, CI wait and readback, `classify-bot-review.sh` calls, fix-cycle bookkeeping, convergence/termination
  reasons, the Earned Fallback Review trigger (`no_review_lens_posted`), and the result block.
- Delete the migrated prose; update the inventory homes.

## Invariants
- `/review-pr` never merges.
- The drain stays heal-only by default; the Earned Fallback Review runs only on `no_review_lens_posted` and fails
  closed toward running.
- The `REVIEW_HEAL_RESULT` schema is unchanged (`docs/RESULT_SCHEMAS.md`).

## Non-goals
- Editing `agents/review-pr.md` (any agent-prompt edit pulls in the budget and contract companion files and would
  serialise this item against Supervisor's items).
- Waiting for items 07–08: this item runs alongside them. It builds its own driver script and shares only the
  instruction schema item 06 fixed; a schema change in 07/08 is additive.
- Changing which findings are fixed or the severity floor. The prompt diet of what remains (item 14).

## Owner decisions (from _BACKLOG.md)
- D1, D3, D5.

## Acceptance criteria
- Given each review-heal golden case, when driven through the driver, then the result block and drain-round state are
  byte-identical to the expected ones.
- Given no review lens posted, then the driver emits the Earned Fallback Review spawn exactly once.
- `test-loop-inventory.sh` passes; review-heal-group GAP count is 0. Read-set size before/after in the PR body.

## Validation (must pass before merge)
1. The new driver's test, golden tests, `test-classify-bot-review.sh`, `test-loop-inventory.sh`; report
   `<passed>/<total>`.
2. Mutation control: skip the fallback on `no_review_lens_posted` ⇒ red.
3. Running system: one real drain on the driver path; paste its round lines and result block.

## Depends on
06

## Touches
loomwright/scripts/review-heal-next-step.sh
loomwright/scripts/test-review-heal-next-step.sh
loomwright/scripts/fixtures/review-heal-golden/
loomwright/skills/review-heal/SKILL.md
loomwright/commands/review-pr.md
loomwright/docs/loop-inventory/review-heal.md
changelog.d/as12-next-step-review-heal.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-18T10:56:50Z
- **Brief:** .supervisor/jobs/done/2026-10-17-next-step-review-heal.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/600
