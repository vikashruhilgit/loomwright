# automate-speed/06 — `next-step` driver, part 1: the script owns the run file and the loop's tail (gate, park, closeout)

## Status: pending

## Problem
The `/automate` per-item loop is a state machine written in English. `skills/automate-loop/per-item-loop.md` is
106KB with no code blocks and single lines up to ~3.8K chars; the main thread re-reads it (and the rest of the ~1MB
read set) and drives each step by hand through about 45 different `automate-helpers.sh` subcommands. That is why main
sessions hold 68% of all tokens at ~380K context per turn (plan doc §Why now). Most of the logic already IS script
(`gate-eval`, `closeout`, `current-set`, `park-ask-gate`, `validation-gate`…); the prose is the glue and the
bookkeeping between them.

## Goal
<!-- bump: minor -->
A new `loomwright/scripts/automate-next-step.sh` is the single reader and writer of the run file. Called with the
run file, it runs every deterministic step it owns and prints exactly ONE JSON instruction for the model:
`{"do":"spawn",...}`, `{"do":"ask",...}`, `{"do":"park",...}`, `{"do":"done"}`. The model reports a step's result
back with `next-step --result <json>`. This item builds the driver and migrates the loop's TAIL: GATE (safe-mode park
/ `--auto-merge` → `gate-eval`), the park writes (park state, merge watcher, notify, `run-lock.sh release`), and
closeout/SYNC. Their prose is deleted from `per-item-loop.md` / `modes-and-merge-gate.md` and replaced by "run
next-step".

## Scope
- Driver skeleton: instruction JSON schema (documented in `docs/result-schemas/automate-run.md`), `--result`
  intake, idempotent re-run (calling it twice without a result returns the same instruction), and a `--legacy` flag
  in `commands/automate.md` that keeps the old prose path selectable until item 08 retires it.
- Link every golden case from item 05 into its row of `loomwright/docs/loop-inventory/automate-loop.md` (items 04
  and 05 ran in parallel, so neither could); the automate-loop group's GAP count then reaches 0.
- Migrate the tail step group. For each migrated branch: the inventory row's home becomes
  `script:automate-next-step.sh <step>`; its golden case (item 05) passes through the driver unchanged.
- The `ask` instruction carries the question, the options and the gate's named can't-ask status, so the coordinator
  never improvises a can't-ask branch.
- Repoint the tests that pin the migrated prose, in the same change that deletes it (wave-2 Plan Review FAIL×3,
  2026-10-16: the brief deleted pinned prose while keeping these tests out of scope). `test-automate-helpers.sh`
  QG3a/QG3a' read `per-item-loop.md` directly and pin the park-first order list ("**Order — sequential interactive
  READY park (park first, then ask):**") and the `### Dismissed-findings decision step (before the park)` heading;
  `test-automate-dismissed.sh`'s B legs pin the §6 step-4 GATE text. Repoint each pin to where the rule now lives
  (the `--legacy` prose or the driver's case arm), keeping every mutation control that makes the pin go red. Exempting
  that prose from deletion instead is acceptable only if the inventory row says why.

## Invariants (CLAUDE.md §Failure-Mode Invariants — must hold after this item)
- `gh pr merge --squash` keeps exactly ONE executor: `gate-eval` in `automate-helpers.sh`. The driver CALLS
  `gate-eval`; it never contains the string `gh pr merge --squash` outside a negated sentence (the positive-form grep
  in CLAUDE.md must still resolve to the same surfaces).
- `gate-eval` stays self-resolving; the driver passes it only the documented `ctx.json` keys.
- Every question gate keeps its named can't-ask branch.
- Run-file `## Progress` / `## Current` line formats are byte-identical to today's (golden tests).

## Non-goals
- Migrating DRAIN/RUN bookkeeping (item 07) or PICK/RECONCILE/resume (item 08).
- Fresh sessions per phase (item 09).
- Changing any gate condition or park semantics.

## Owner decisions (from _BACKLOG.md)
- D1: Moving prose never drops a rule — the inventory row's home is updated in the same change as the prose is
  deleted.
- D5: The old prose path stays selectable behind a flag until golden parity holds.

## Acceptance criteria
- Given each tail golden case from item 05, when driven through `automate-next-step.sh`, then the resulting run file
  is byte-identical to the expected one.
- Given the same run file, when `next-step` runs twice with no `--result`, then both calls print the same instruction
  and the run file is unchanged.
- Given a park in a non-interactive run, then the instruction carries the gate's named can't-ask status, never an
  `ask`.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same surfaces as
  before this item.
- `test-loop-inventory.sh` passes; every migrated row's home names the driver step.
- The prose for the migrated steps is gone from `skills/automate-loop/`; `wc -c` of the automate-loop read set is
  recorded before and after in the PR body.

## Validation (must pass before merge)
1. `test-automate-next-step.sh`, `test-automate-golden.sh`, `test-automate-helpers.sh`, `test-automate-dismissed.sh`, `test-loop-inventory.sh`,
   `check-doc-currency.sh`, `test-citation-drift.sh`; report `<passed>/<total>`.
2. Mutation controls: make the driver skip `gate-eval` and park directly ⇒ a golden case goes red; add an unguarded
   `gh pr merge --squash` to the driver ⇒ the invariant grep test goes red.
3. Running system: run one real Queue item end to end with the driver path in a scratch repo or a throwaway branch;
   paste the run file's tail Progress lines.

## Depends on
04
05
25

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-dismissed.sh
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
loomwright/docs/result-schemas/automate-run.md
loomwright/docs/loop-inventory/automate-loop.md
changelog.d/as06-next-step-driver-tail.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-17T03:47:33Z
- **Brief:** .supervisor/jobs/done/2026-10-16-next-step-driver-tail.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/575
