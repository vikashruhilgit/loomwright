# automate-speed/07 — `next-step` driver, part 2: DRAIN and RUN bookkeeping move into the script

## Status: pending

## Problem
After item 06 the loop's tail is script-driven, but the middle of the loop is still prose the main thread executes
by hand: the `auto_review` config toggle that must wrap RUN (backup, restore finally-style, delete-if-absent,
malformed ⇒ abort), recording `session_id`, `sidecar-check`, the owned drain's start line and the verbatim
`REVIEW_HEAL_RESULT` sidecar, the drain-superseded-by-merge branch, `validation-gate`, learning-emit, and the
dismissed-findings drafts and decision step. This is the densest part of `per-item-loop.md` §6–§7 (plan doc §Why now:
62% of the read set is bookkeeping prose).

## Goal
<!-- bump: minor -->
The driver owns every deterministic step around RUN and DRAIN. The model is told only "spawn `/autonomous
--single-iteration --requirement <path>`" and "spawn the owned `/review-pr --until-mergeable` drain", and hands back
the result block; the driver does all bookkeeping and the toggle.

## Scope
- Steps: suppress/restore `auto_review` around RUN (the toggle must wrap RUN, not DRAIN — both default dispatch
  paths fire during `/autonomous`), RUN result + session-id recording, `sidecar-check`, drain start/result lines,
  `owned_drain_*` keys in `## Current`, drain superseded by merge (`reconcile-item` ⇒ `superseded_by_merge` ⇒
  closeout), `validation-gate`, learning-emit, dismissed-findings drafts, and the owner decision step (as an `ask`
  instruction with its can't-ask status).
- Delete the migrated prose; update the inventory rows' homes; golden cases pass through the driver.

## Invariants
- Single-drain ownership: exactly ONE owned drain per pass, at most one owner-requested fix-now re-drain, strictly
  sequential. The driver refuses to emit a second drain `spawn` for the same pass.
- The config toggle backup/restore contract is unchanged (byte-for-byte backup, RECONCILE restores a stranded
  backup).
- `gh pr merge --squash` executor unchanged (item 06 invariant).

## Non-goals
- PICK/RECONCILE/resume (item 08). Fresh sessions (item 09).

## Owner decisions (from _BACKLOG.md)
- D1, D5.

## Acceptance criteria
- Given each DRAIN/RUN golden case from item 05, when driven through the driver, then the run file is byte-identical.
- Given a pass that already emitted its owned drain, when the coordinator asks for another, then `next-step` refuses
  with a named status and the run file is unchanged.
- Given a malformed pre-existing `.supervisor/config.json`, then the driver aborts before RUN with the named status
  (today's behaviour).
- Given a drain that returns without a terminal block and a merged PR, then the driver writes
  `superseded_by_merge`, no review-heal sidecar, no learning-emit, and closes the item out.
- `test-loop-inventory.sh` passes; the migrated prose is gone.

## Validation (must pass before merge)
1. `test-automate-next-step.sh`, `test-automate-golden.sh`, `test-automate-helpers.sh`, `test-loop-inventory.sh`;
   report `<passed>/<total>`.
2. Mutation controls: restore the toggle after DRAIN instead of after RUN ⇒ red; allow a second drain spawn ⇒ red.
3. Running system: one real item through RUN and DRAIN on the driver path; paste the Progress lines from
   `auto_review suppressed` to `drain READY`.

## Depends on
06

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/fixtures/automate-golden/
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/automate-loop/branch-mode.md
loomwright/skills/automate-loop/command-lanes.md
loomwright/skills/automate-loop/intake.md
loomwright/skills/automate-loop/invariants.md
loomwright/skills/automate-loop/lanes.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/resume.md
loomwright/commands/automate.md
loomwright/docs/loop-inventory/automate-loop.md
changelog.d/as07-next-step-drain-and-run.md
