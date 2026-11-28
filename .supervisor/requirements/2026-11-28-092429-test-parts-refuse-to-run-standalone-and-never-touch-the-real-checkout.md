# Split test parts that touch run state refuse to run on their own and never touch the real checkout

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/1004

> GitHub issue: https://github.com/vikashruhilgit/loomwright/issues/994. Part A of 3. Part A2:
> `2026-11-28-092431-automate-helpers-test-parts-refuse-to-run-standalone.md`; Part B:
> `2026-11-28-092430-every-split-test-part-is-guarded-and-ci-keeps-it-that-way.md`.

## Why

On 2026-11-28 a Supervisor worker (run automate-2026-11-27-162041, item qa-split/09) ran split test parts
directly, one `bash <part>` per file, from the live checkout:
`loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` among them. A part expects its
parent runner (`test-automate-trail.sh`) to set `$P`, `$TOP` and the helper functions first. Run alone,
`$P` was empty, every `cd "$P"` failed (`cd: null directory`), and line 171

```
( cd "$P" && git checkout -q -- README; rm -f stray.txt; rm -f "$AUTD"/*.md )
```

ran its `rm` in the live checkout, because `;` does not stop after a failed `cd`. It deleted every
`.supervisor/automate/*.md` there: the live run file (the only copy of the run's resume state, rebuilt by hand
with the owner's approval) and 449 run-history files. The same file has 3 such `cd "$P" && …; …` lines.

The lanes parts already refuse to run alone (`test-automate-lanes.d/03-fixes-to-finalize.sh`:
`declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ] && [ -d "$T" ] || { echo "…: run via
test-automate-lanes.sh, never standalone …"; exit …; }`), and some parts re-exec their parent with `--part`
(`test-automate-next-step.d/15-source-requirement.sh`). This part covers the runners whose parts build or
clean `.supervisor/` fixtures: `test-automate-trail.d` (7 parts) and `test-meta-sync.d` (4), counted by a grep on 2026-11-28 for parts with
neither guard form in their first 15 lines. `test-automate-helpers.d` (16 unguarded) is Part A2.

## Story

**As the** owner whose `/automate` runs keep their only resume state in `.supervisor/automate/`,
**I want** the trail and meta-sync test parts to refuse to run without their parent runner, and
their fixture `cd` groups to stop when the `cd` fails,
**so that** no test, run by a worker, a reviewer or me, can delete or rewrite files in the real checkout.

## Acceptance criteria

**Happy path**
- [ ] Given any tracked part under `loomwright/scripts/test-automate-trail.d/` or
  `loomwright/scripts/test-meta-sync.d/`, when it is run
  directly with `bash <part>` from a checkout, then it either re-execs its parent runner for that one part
  (the `--part` form) or exits non-zero with one line naming the parent runner, before it runs any command.
- [ ] Given `test-automate-trail.sh` and `test-meta-sync.sh`, when they run their
  parts as today, then every part still runs and each suite's results are unchanged.

**Edge cases**
- [ ] Given a fixture step of the form `( cd "$X" && a; b; c )` in any part of those two runners, when `$X`
  is empty or not a directory, then none of `a`, `b`, `c` runs (the whole group is guarded, e.g.
  `cd "$X" || exit`), not only line 171 of `05-finalize-closeout-others.sh`.

**Error scenarios**
- [ ] Given a scratch checkout holding a sentinel `.supervisor/automate/sentinel-run.md`, when
  `bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` is run from it, then it
  exits non-zero naming `test-automate-trail.sh` (or re-execs it), and the sentinel is still there; a test
  pins this.

## Non-goals

- The `test-automate-helpers.d` parts (Part A2); the other runners' parts and the CI check that keeps every
  part guarded (Part B).
- Changing what any suite asserts, or how `scripts/ci-local.sh` picks suites.
- Instructions to workers about how to run tests (the guard makes the wrong way harmless; this story does
  not depend on prompts being followed).
- Restoring the deleted run-history files (they are on `loomwright-meta`; a manual
  `git show origin/loomwright-meta:<path> > <path>` restores one).

## Owner decisions

- 2026-11-28 (Vikash): write this with `/loomwright:product-owner`, push only its path to the metadata
  branch, and queue it for a later run (not automate-2026-11-27-162041).
- 2026-11-28 (Vikash, standing rule): every defect gets a GitHub issue (#994), a requirement linked to it,
  and a scratch-copy reproduction recorded in both.

## Priority: MVP

**Rationale:** a worker running tests the obvious way destroyed a live run's only resume state; any run in a
checkout where tests run can lose it the same way.

## Assumptions

- Defect evidence: reproduced — 2026-11-28, in a scratch clone at `9a6a850` (never a real `.supervisor/`),
  with `.supervisor/automate/sentinel-run.md` and `sentinel.next-step.json` present,
  `bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` exited 127, printed
  `line 25: cd: null directory`, and left only `sentinel.next-step.json`. The incident itself was observed at
  2026-11-28T03:38Z (`.supervisor/automate/` went from 530 entries to 85, no `.md` left).
- The lanes guard (`declare -F <parent function>` plus a parent-set directory) and the `--part` re-exec are
  both acceptable forms; the implementer picks one per runner and uses it for all of that runner's parts.

## Dependencies

- Depends on: none.
- Blocks: Part B (its CI check would fail on these parts until they are guarded).

## Risks

- A part that is also sourced by another runner needs a guard that accepts both parents.
- A whole-set `meta-sync.sh push` from a checkout where this defect already struck would publish its
  deletions to `loomwright-meta` (issue #994); this story prevents new losses, it does not undo old ones.

## Validation (must pass before merge)

1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, including the new sentinel
   leg and the two runners' suites unchanged.
2. **Running system — the incident replayed:** in a scratch clone holding a sentinel
   `.supervisor/automate/sentinel-run.md`, `bash loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh`
   exits non-zero naming `test-automate-trail.sh`, and the sentinel is still there; the command and output
   are pasted in the PR.

## Depends on
none

## Touches
loomwright/scripts/test-automate-trail.d/
loomwright/scripts/test-meta-sync.d/
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/test-meta-sync.sh
changelog.d

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-28T12:02:52Z
- **Brief:** .supervisor/jobs/done/2026-11-28-test-parts-refuse-standalone-trail-meta.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/1004
