# automate-speed/05 — Golden run-file tests pin today's /automate behaviour before anything moves

## Status: pending

## Problem
The `/automate` run file (`.supervisor/automate/<run_id>.md`) is the loop's state and its contract: other scripts
parse its pinned `## Progress` and `## Current` line formats (for example `lane-drain-check` counts the
`owned drain started` lines). Items 06–09 move the loop's control flow from prose into a `next-step` script. The
inventory (item 04) lists every branch whose only test is `GAP`. Without tests that pin today's run-file output for
those branches, a migration that changes a line format or skips a branch passes every existing suite.

## Goal
<!-- bump: patch -->
Every branch of the `/automate` per-item loop (`skills/automate-loop/` §6–§10 and `resume.md`) is covered by a test
that pins today's behaviour, using golden run files built from real past runs, so items 06–09 can prove they produce
the same run file. Runs in parallel with item 04: it works from the prose's own step headings, and item 06 records each
golden case in the inventory row it covers.

## Scope
- `loomwright/scripts/fixtures/automate-golden/`: input/expected run-file pairs for each covered branch. Build them
  from real runs in `.supervisor/automate/` (e.g. `automate-2026-10-13-181331`: drain superseded, escalated park,
  dismissed-findings decisions, closeout, resume), scrubbed: no home paths, no non-plugin project content.
- `loomwright/scripts/test-automate-golden.sh`: drives the existing `automate-helpers.sh` subcommands the prose
  calls, in the prose's order, over each fixture, and diffs the resulting run file against the expected one
  byte-for-byte (timestamps normalised).
- Name each golden case after the prose step heading it covers (e.g. `drain-superseded-by-merge`), so item 06 can map
  it to the inventory row mechanically.
- A branch that cannot be driven by script calls alone (it needs a judgment step) gets a row note `judgment —
  covered at the step boundary` and a fixture for the boundary (what the step receives and what it must write).

## Non-goals
- Supervisor, review-heal and Launch Pad gaps (their groups are covered when items 11, 12 and 13 run).
- Writing to the loop inventory (item 04 owns it; item 06 links the cases).
- Changing any behaviour. A test that would need a behaviour change to pass is a finding: record it in the PR body
  and the inventory, do not fix it here.

## Owner decisions (from _BACKLOG.md)
- D1, D5 (see plan doc).

## Acceptance criteria
- Given every `###`/`####` step heading and numbered branch in `skills/automate-loop/per-item-loop.md`,
  `modes-and-merge-gate.md` and `resume.md`, then each has a golden case or a `judgment — covered at the step
  boundary` case; the test prints the heading→case map and fails on an unmapped heading.
- Given a fixture whose expected run file has a `## Progress` line, when one character of that line's pinned prefix
  changes in the code under test, then `test-automate-golden.sh` fails naming the case.
- Fixtures contain no `/Users/` or `/home/` path (the test asserts it).

## Validation (must pass before merge)
1. `test-automate-golden.sh`, `test-automate-helpers.sh`; report `<passed>/<total>`.
2. Mutation control: change the `owned drain started` prefix in a scratch copy of `automate-helpers.sh` ⇒ the
   golden test goes red.

## Depends on
none

## Touches
loomwright/scripts/fixtures/automate-golden/
loomwright/scripts/test-automate-golden.sh
changelog.d/as05-golden-run-tests.md
