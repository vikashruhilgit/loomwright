# automate-speed/21 — Split test-automate-helpers.sh to mirror automate-helpers.d/ (move-only)

## Status: pending

## Problem
`automate-helpers.sh` is already split: a 1,122-line dispatcher plus nine modules in `loomwright/scripts/automate-helpers.d/`
(the largest, `runfile.sh`, is 694 lines). Its test was not: `test-automate-helpers.sh` is 6,137 lines, the largest test
file in the repo. Every helper change edits it, so parallel lanes collide on it and a reviewer reads far more than
the change (owner, 2026-10-15: smaller files make changes and maintenance easier).

## Goal
<!-- bump: patch -->
`test-automate-helpers.sh` becomes a thin runner that sources one test module per helper module from
`loomwright/scripts/test-automate-helpers.d/`, with every assertion kept.

## Scope
- One test module per `automate-helpers.d/` module (config, escalation, intake, learning, meta, plan-waves,
  reconcile-status, resume, runfile) plus one for the dispatcher's own subcommands (gate-eval, closeout, park…).
- The runner keeps today's entry point, exit code and `<passed>/<total>` summary; a single module can be run alone.
- Start only after `feature/af39a-sweep` (live on 2026-10-15 with uncommitted edits to `automate-helpers.sh`) has
  merged; rebase onto that main.

## Invariants
- `gate-eval` and its `gh pr merge --squash` line stay in `automate-helpers.sh`; the CLAUDE.md positive-form grep
  resolves to the same files before and after (the test file is one of its five surfaces — keep that line in the runner
  or update the enumeration in CLAUDE.md and `skills/automate-loop/` §11 in the same change).
- CI's `loomwright/scripts/test-*.sh` glob must not pick up the modules as separate suites (they live in a `.d/` dir).

## Non-goals
- Any change to `automate-helpers.sh` or its modules. Terse output (item 24).

## Owner decisions (from _BACKLOG.md)
- D6: Splits are move-only — no behaviour, subcommand or output change.

## Acceptance criteria
- The runner's `<passed>/<total>` is identical before and after.
- No test module exceeds ~800 lines.
- The invariant grep's output is identical before and after (pasted in the PR body).

## Validation (must pass before merge)
1. `test-automate-helpers.sh` before and after; `check-test-hermetic.sh`; report both `<passed>/<total>`.
2. Mutation control: delete one assertion from a module ⇒ the total drops by one.

## Depends on
none

## Touches
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-helpers.d/
changelog.d/as21-split-automate-helpers-tests.md
