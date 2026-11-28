# Every split test part is guarded against running on its own, and CI keeps it that way

## Status: pending

> GitHub issue: https://github.com/vikashruhilgit/loomwright/issues/994. Part B of 3. Parts A and A2:
> `2026-11-28-092429-test-parts-refuse-to-run-standalone-and-never-touch-the-real-checkout.md`,
> `2026-11-28-092431-automate-helpers-test-parts-refuse-to-run-standalone.md`.

## Why

Parts A and A2 guard the test parts that build or clean `.supervisor/` fixtures, the ones that deleted a live run
file on 2026-11-28. The other split parts have the same hole: run with `bash <part>`, they run with
none of their parent runner's setup. A grep on 2026-11-28 found 11 parts in `test-automate-next-step.d` and
6 in `test-setup-memory.d` with no standalone guard in their first 15 lines. Nothing stops a new part from
being added unguarded either, since the guard is a convention, not a check.

## Story

**As the** owner,
**I want** every tracked `loomwright/scripts/test-*.d/*.sh` part guarded, and CI to fail when one is not,
**so that** no split test part, today's or a future one, can run against the real checkout by mistake.

## Acceptance criteria

**Happy path**
- [ ] Given any tracked part under `loomwright/scripts/test-automate-next-step.d/` or
  `loomwright/scripts/test-setup-memory.d/`, when it is run directly with `bash <part>`, then it re-execs its
  parent runner for that one part (`--part`) or exits non-zero with one line naming the parent runner,
  before it runs any command.
- [ ] Given `test-automate-next-step.sh` and `test-setup-memory.sh`, when they run their parts as today, then
  every part still runs and the results are unchanged.

**Edge cases**
- [ ] Given a new `loomwright/scripts/test-*.d/*.sh` part with no guard, when CI runs, then a static check
  fails naming the part.
- [ ] Given a fixture step `( cd "$X" && a; b; c )` in any of these parts, when `$X` is empty or not a
  directory, then none of `a`, `b`, `c` runs.

**Error scenarios**
- [ ] Given a scratch checkout holding a sentinel `.supervisor/automate/sentinel-run.md`, when every tracked
  part (all runners) is run standalone from it, then each exits non-zero or re-execs its parent, and the
  sentinel and the checkout's tracked files are byte-unchanged afterwards; a test pins this.

## Non-goals

- The trail, meta-sync (Part A) and automate-helpers (Part A2) parts.
- Changing what any suite asserts, or how `scripts/ci-local.sh` picks suites.

## Owner decisions

- 2026-11-28 (Vikash): write this with `/loomwright:product-owner`, push only its path to the metadata
  branch, and queue it for a later run.
- 2026-11-28 (Vikash, standing rule): every defect gets a GitHub issue (#994) and a linked requirement.

## Priority: MVP

**Rationale:** without the CI check, Parts A and A2's guard decays the first time a part is added.

## Assumptions

- Defect evidence: reproduced (shared with Part A) — 2026-11-28, scratch clone at `9a6a850`: an unguarded
  part run standalone deleted a sentinel `.supervisor/automate/*.md` (issue #994).
- The static check can read the guard from each part's first lines (both accepted forms are one or two
  fixed-shape lines).

## Dependencies

- Depends on: Parts A and A2.
- Blocks: none.

## Risks

- The all-parts sentinel test runs every part once; each refuses or re-execs before any work, so it is fast,
  but a re-exec form runs the real part, which must then use its parent's scratch fixture.

## Validation (must pass before merge)

1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, including the new static guard
   check and the all-parts sentinel test.
2. **Static — the check bites:** removing the guard from one part makes the static check fail naming that
   part (shown in the PR).

## Depends on
2026-11-28-092429-test-parts-refuse-to-run-standalone-and-never-touch-the-real-checkout.md
2026-11-28-092431-automate-helpers-test-parts-refuse-to-run-standalone.md

## Touches
loomwright/scripts/test-automate-next-step.d/
loomwright/scripts/test-setup-memory.d/
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/test-setup-memory.sh
loomwright/scripts/test-split-part-guards.sh
.github/workflows/ci.yml
changelog.d
