# 11 — Fewer forced conflicts: generate the skills index, split the engine's hotspot files along their seams

## Status: pending

## Depends on
10

## Touches
loomwright/skills/SKILLS_INDEX.md
scripts/check-skills-index-sync.sh
.agent/companions.json
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/automate-helpers.d/
changelog.d/parallel-automate-11-split-shared-hotspot-files.md

## Problem
Owner goal: 5–10 lanes at once. Even with complete `Touches` (item 10), items collide when they edit the same
FILE, because the planner compares paths, not hunks. Git history shows where that bites. Across the last 40
first-parent merges on `main` (2026-10-04):
- `plugin.json`, `marketplace.json`, `CHANGELOG.md`: 16 each. **Already solved** by item 01 (fragments plus one
  bump per wave), kept here only as the pattern to copy.
- `loomwright/skills/automate-loop/SKILL.md`: 10 (581 lines); `loomwright/scripts/automate-helpers.sh`: 10 (2,416
  lines, every helper in one file); `automate-trail.sh` and its test, `test-automate-helpers.sh`: 7 each.
- `loomwright/skills/SKILLS_INDEX.md`: 6. `.agent/companions.json` adds it to EVERY `skills/*/SKILL.md` edit, so any
  two items that edit any two skills conflict, even when the index row never changes.
- `loomwright/docs/RESULT_SCHEMAS.md`: 5 (3,498 lines).

## Goal
The files that collide only because they are shared registries or monoliths stop forcing separate waves: the
skills index is generated and checked, and the biggest engine file is split along its existing subcommand seams,
so two items changing different helpers touch different files. Measured first, by item 10's `--explain`.

## Scope
1. **Measure before cutting.** After item 10's backfill, run `plan-waves --explain` over the open backlog and rank
   the paths that cause the most "conflicts with" lines. Record the ranking in this item's Evidence. Only paths in
   that ranking are changed here; anything else becomes a follow-up.
2. **Skills index, generated:** `SKILLS_INDEX.md` rows are generated from each `SKILL.md`'s frontmatter (name,
   version, description) by a script, and `check-skills-index-sync.sh` (which exists) becomes "regenerate and diff"
   in CI. Then drop the `skills/*/SKILL.md ⇒ SKILLS_INDEX.md` companion rule from `.agent/companions.json`: an edit
   that changes no frontmatter no longer touches the index, and one that does is regenerated at the release bump
   (item 06 / 01 pattern) or by the PR itself without conflict-prone hand edits.
3. **`automate-helpers.sh` split along its subcommand seams:** each subcommand family (run-file writes, resume/
   reconcile, gate-eval, plan-waves, dismissed/learning helpers — read the file's own dispatch table for the real
   groups) moves to `loomwright/scripts/automate-helpers.d/<family>.sh`; `automate-helpers.sh` keeps the shared
   functions and a dispatcher that sources the family file. **The command-line interface stays byte-identical**
   (every caller, every test, the `gh pr merge --squash` single-executor invariant — `gate-eval` remains the only
   executor and the positive-form grep in CLAUDE.md must still resolve to the same five surfaces, updated to the
   new file path in the same PR).
4. **The skill and the schema doc are NOT split in this item** unless step 1 ranks them top and a split preserves
   every anchor that prose cites (`test-citation-drift.sh` pins). If ranked top, write the split as a follow-up
   with its own validation; prose engines need a state-trace review, not a mechanical cut.
5. **Tests:** the existing `test-automate-helpers.sh` passes unchanged against the split (no assertion edited); a
   new case proves every subcommand still dispatches; the index generator round-trips the current index; the
   companion change is covered by a plan-waves fixture (two items editing two different skills' bodies share a
   wave).

## Non-goals
- No behaviour change in any helper. No new subcommands. No change to the planner's rules.

## Acceptance criteria
- `plan-waves --explain` over the open backlog shows fewer "conflicts with" lines naming `SKILLS_INDEX.md` and
  `automate-helpers.sh` than before; before/after counts recorded.
- The single-merge-executor grep still resolves to exactly the documented surfaces.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts; no existing assertion edited.
2. **Unchanged path:** a real sequential `/automate` item run after the split (the engine is prose plus these
   helpers; the overview's "sequential path is protected" rule applies).
3. **Running system:** paste the before/after `--explain` ranking.
4. **A failure this must catch:** break one family file's dispatch ⇒ the dispatch test fails; hand-edit an index
   row ⇒ the sync check fails.
5. **Rollback:** `git revert` (the split is file moves plus a dispatcher).

## Verified premises (re-check before starting)
- Line counts and the 40-merge co-touch counts measured 2026-10-04 (`git log --first-parent -40 --name-only`).
- `.agent/companions.json` rule `{"when": "loomwright/skills/*/SKILL.md", "add": ["loomwright/skills/SKILLS_INDEX.md"]}`.
- `scripts/check-skills-index-sync.sh` exists.

## Evidence
To be filled by Scope 1 (the `--explain` ranking after item 10's backfill).
