# automate-speed/04 — Inventory every branch and rule in the loop prose, with a test that keeps it honest

## Status: pending

## Problem
One `/automate` item reads ~1.04MB (proxy ~260K tokens) of protocol prose inline: automate-loop 316KB,
self-heal-advisory 176KB, review-heal 133KB, `agents/supervisor.md` 111KB, autonomous-loop 102KB,
`agents/launch-pad.md` 94KB, plus the commands (plan doc §Why now). By heuristic sentence classification it is about
62% step-by-step bookkeeping and control flow written as prose, 19% rules and invariants, 11% history and stories,
8% "call script X". Later items in this set move the control flow into scripts and move stories out. The risk is
an edge case or a rule that exists ONLY in prose: delete the paragraph and the behaviour silently goes. Nothing today
lists those branches, so nobody can say what is safe to move.

## Goal
<!-- bump: minor -->
A committed inventory lists every branch and rule in the loop prose, one row each, and a test fails whenever the
prose and the inventory disagree. Every later item in this set updates the inventory in the same change as it moves
or deletes prose, so "moving prose never drops a rule" becomes mechanical.

## Scope
- Four inventory files under `loomwright/docs/loop-inventory/`, one per file group (so later items in different
  groups never edit the same file): `automate-loop.md` (all `skills/automate-loop/*` + `commands/automate.md`),
  `supervisor.md` (`agents/supervisor.md`, `commands/supervisor.md`, `skills/self-heal-advisory/`,
  `skills/async-orchestration/`), `review-heal.md` (`skills/review-heal/`, `commands/review-pr.md`,
  `agents/review-pr.md`), `launch-pad-autonomous.md` (`agents/launch-pad.md`, `commands/launch-pad.md`,
  `skills/autonomous-loop/`, `commands/autonomous.md`).
- One table row per branch or rule: stable id (`AL-001`, `SV-001`, `RH-001`, `LP-001`), anchor (a heading or a
  pinned quote — never a bare line number), condition, action, kind (`deterministic` / `judgment` / `rule` /
  `story`), home (`prose` today; later `script:<file> <subcommand>`, `hook:<leaf>`, `step-scoped`, `global`,
  `rationale:<doc>#<anchor>`), the script that already implements it (if any), the test that covers it (or `GAP`).
- `loomwright/scripts/test-loop-inventory.sh` (auto-discovered by CI's `loomwright/scripts/test-*.sh` glob):
  fails when a row's anchor no longer exists in its file while its home is still `prose`; fails when a row's
  `script:` home names a subcommand the script does not have; fails on a duplicate id. It prints a GAP count per
  group (informational, not a failure).
- A gap list per group at the end of each file: every row with test `GAP`, ordered by risk.

## Non-goals
- Changing any prose, script or behaviour.
- Writing the missing tests (that is item 05).
- Classifying the plugin's other skills and commands.

## Owner decisions (from _BACKLOG.md)
- D1: Moving prose never drops a rule — every rule gets a home recorded in this inventory before its prose is deleted.
- D5: Phase 0 lands before any Phase 1 prose is deleted.

## Acceptance criteria
- Given the four groups, then every `###`/`####` step heading and every numbered or bulleted branch in the listed
  files maps to at least one row (the test checks heading coverage; bullet coverage is the reviewer's check).
- Given a row whose anchor is deleted from the prose while its home is `prose`, when `test-loop-inventory.sh`
  runs, then it fails naming the row id.
- Given a row homed `script:automate-helpers.sh gate-eval`, then the test passes; renamed to a subcommand that does
  not exist, it fails.
- Each group file ends with its gap list and a per-kind count.
- House rule (advisory): the inventory restates the prose's branch list, so it is kept in sync by the test, never by
  hand — the restated copy cannot drift silently.

## Validation (must pass before merge)
1. `test-loop-inventory.sh`, `test-citation-drift.sh`, `check-doc-currency.sh`; report `<passed>/<total>`.
2. Mutation control: delete one anchored heading from a scratch copy of `per-item-loop.md` ⇒ the test goes red
   naming the row.
3. Paste the per-group counts (rows, per kind, GAP) into the PR body.

## Depends on
none

## Touches
loomwright/docs/loop-inventory/automate-loop.md
loomwright/docs/loop-inventory/supervisor.md
loomwright/docs/loop-inventory/review-heal.md
loomwright/docs/loop-inventory/launch-pad-autonomous.md
loomwright/scripts/test-loop-inventory.sh
changelog.d/as04-loop-inventory.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-16T01:41:03Z
- **Brief:** .supervisor/jobs/done/2026-10-15-as04-loop-inventory.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/559
