# automate-speed/08 — `next-step` driver, part 3: PICK, RECONCILE and resume; retire the legacy prose path

## Status: pending

## Problem
After items 06–07 only the head of the loop is still prose: run lock + `pick-guard`, RECONCILE (+ `closeout` on a
found merge, `closeout-classify` leftovers), `trail-gate`, `trail-unstage`, and smart resume (`resume.md`: glob
incomplete runs, reconcile against `gh`/`git`/`## Status: done`, offer continue / start-new / archive). The legacy
`--legacy` prose path still ships the full ~316KB automate-loop skill.

## Goal
<!-- bump: minor -->
The whole per-item loop is driven by `automate-next-step.sh`. The coordinator prompt for `/automate` becomes a short
loop ("run next-step; do the one instruction; report the result"), and the legacy prose path is removed once every
golden case passes through the driver.

## Scope
- Part A — head of the loop: run lock, `pick-guard`, RECONCILE, `closeout-classify` (its leftover question becomes an
  `ask` instruction with the `closeout_leftover` can't-ask status), `trail-gate`, `trail-unstage`, and resume.
- Part B — retire the legacy path: delete `--legacy` and the migrated prose. What remains in `skills/automate-loop/`
  is the coordinator loop, the instruction schema, the global rules (inventory home `global`), and intake (judgment).
  Record the read-set size before and after in `docs/evidence/automate-speed-baseline.md`.

## Invariants
- Single-open-PR invariant: PICK is blocked while any PR is open, this run's trail PR included.
- `pick-guard` still parks `live_lane` while a `--parallel` wave's lane is live in this checkout.
- Smart resume semantics unchanged (golden cases).

## Non-goals
- Fresh sessions per phase (item 09). Prompt diet of what remains (item 16).

## Owner decisions (from _BACKLOG.md)
- D1, D5.

## Acceptance criteria
- Given every `automate-loop` golden case, when driven through the driver, then the run file is byte-identical.
- Given an open PR, when `next-step` is asked to pick, then it parks with today's status and picks nothing.
- `--legacy` no longer exists; `commands/automate.md` describes the driver loop.
- The automate-loop read set is at least 60% smaller than before item 06 (byte count in the evidence file).
- `test-loop-inventory.sh` passes; every `automate-loop` row's home is no longer `prose` except rows homed `global`
  or `judgment`.

## Validation (must pass before merge)
1. `test-automate-next-step.sh`, `test-automate-golden.sh`, `test-automate-helpers.sh`, `test-automate-lanes.sh`,
   `test-loop-inventory.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`; report `<passed>/<total>`.
2. Mutation control: let PICK proceed with an open PR ⇒ red.
3. Running system: `/automate --resume <run>` on a run parked `awaiting_merge` whose PR merged; paste the closeout
   and next pick lines.

## Measurements
- After merge, run the next 2 real Queue items on the driver path and compare with item 03's report: main-session
  turns and peak context per item. Frozen commit: this PR's merge commit.

## Depends on
07

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
docs/evidence/automate-speed-baseline.md
changelog.d/as08-next-step-pick-and-resume.md
