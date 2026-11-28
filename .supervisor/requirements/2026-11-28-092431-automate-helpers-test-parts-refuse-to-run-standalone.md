# The automate-helpers test parts refuse to run on their own

## Status: pending

> GitHub issue: https://github.com/vikashruhilgit/loomwright/issues/994. Part A2 of 3. Part A:
> `2026-11-28-092429-test-parts-refuse-to-run-standalone-and-never-touch-the-real-checkout.md`; Part B:
> `2026-11-28-092430-every-split-test-part-is-guarded-and-ci-keeps-it-that-way.md`.

## Why

Part A explains the incident: a split test part run with `bash <part>` runs with none of its parent's setup,
and a failed `cd "$P"` lets the rest of a `( cd "$P" && a; b; c )` group run in the real checkout, which on
2026-11-28 deleted every `.supervisor/automate/*.md` there, a live run file included. A grep on 2026-11-28
found 16 of the 20 tracked `loomwright/scripts/test-automate-helpers.d/` parts with no standalone guard in
their first 15 lines. These parts build run-file, gate and resume fixtures, so they can reach
`.supervisor/` the same way.

## Story

**As the** owner whose `/automate` runs keep their only resume state in `.supervisor/automate/`,
**I want** every `test-automate-helpers.d` part to refuse to run without `test-automate-helpers.sh`,
**so that** none of them can touch the real checkout when run by hand or by a worker.

## Acceptance criteria

**Happy path**
- [ ] Given any tracked part under `loomwright/scripts/test-automate-helpers.d/`, when it is run directly with
  `bash <part>`, then it re-execs `test-automate-helpers.sh` for that one part (`--part`) or exits non-zero
  with one line naming it, before it runs any command.
- [ ] Given `test-automate-helpers.sh`, when it runs its parts as today, then every part still runs and the
  results are unchanged.

**Edge cases**
- [ ] Given a fixture step `( cd "$X" && a; b; c )` in any of these parts, when `$X` is empty or not a
  directory, then none of `a`, `b`, `c` runs.

**Error scenarios**
- [ ] Given a scratch checkout holding a sentinel `.supervisor/automate/sentinel-run.md`, when each
  `test-automate-helpers.d` part is run standalone from it, then each exits non-zero or re-execs its parent,
  and the sentinel is still there; a test pins this.

## Non-goals

- The trail and meta-sync parts (Part A), the other runners and the CI guard check (Part B).
- Changing what any suite asserts.

## Owner decisions

- 2026-11-28 (Vikash): write this with `/loomwright:product-owner`, push only its path to the metadata
  branch, and queue it for a later run.
- 2026-11-28 (Vikash, standing rule): every defect gets a GitHub issue (#994) and a linked requirement.

## Priority: MVP

**Rationale:** same failure mode as Part A, in the largest set of unguarded parts.

## Assumptions

- Defect evidence: reproduced (shared with Part A) — 2026-11-28, scratch clone at `9a6a850`: an unguarded
  part run standalone deleted a sentinel `.supervisor/automate/*.md` (issue #994).
- Part A's guard form is reused here, so both runners read the same way.

## Dependencies

- Depends on: Part A (its guard form).
- Blocks: Part B.

## Risks

- A part sourced by another runner needs a guard that accepts both parents.

## Validation (must pass before merge)

1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, including the new sentinel leg
   and `test-automate-helpers.sh` unchanged.

## Depends on
2026-11-28-092429-test-parts-refuse-to-run-standalone-and-never-touch-the-real-checkout.md

## Touches
loomwright/scripts/test-automate-helpers.d/
loomwright/scripts/test-automate-helpers.sh
changelog.d
