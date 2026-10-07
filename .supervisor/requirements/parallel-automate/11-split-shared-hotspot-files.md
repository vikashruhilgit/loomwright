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
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/result-schemas/
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
   **Amended 2026-10-06 (owner): `loomwright/docs/RESULT_SCHEMAS.md` IS in scope now.** The 2026-10-06 S3 re-plan
   found it declared by 7 of 16 open items and the main serializer (af/31, af/34 and pa/18 wait on it and on
   `automate-helpers.sh` only — operator-run S3 §"Wave plan (re-planned 2026-10-06…)"). Step 1's ranking is still
   recorded first. The split:
   - one file per schema (or schema family) under `loomwright/docs/result-schemas/`, along the doc's existing
     per-schema sections; `RESULT_SCHEMAS.md` stays as the index that links them, so its path and every heading a
     prose citation or `[pins: …]` anchor names still resolves (`test-citation-drift.sh` green, no pin edited to
     make it pass);
   - first list every reader that PARSES the doc (as opposed to citing it in a comment) — validators, generators,
     `check-*.sh` gates, tests — and keep each working on the split, with a test per parser;
   - prose engines that cite it get the state-trace review the original sentence asks for;
   - after the merge, every open item whose `## Touches` names `RESULT_SCHEMAS.md` is re-checked and re-pointed to
     the split file it actually edits (S3 gap 7, "Touches drift after a split") before waves 3+ are re-planned.
   `automate-loop/SKILL.md` stays out of scope unless step 1 ranks it top (the original sentence above still holds
   for it).
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
- (2026-10-06) `plan-waves --explain` over the open backlog shows fewer "conflicts with" lines naming `RESULT_SCHEMAS.md`
  than before (before/after counts recorded), and every parser of the doc listed in Scope 4 passes on the split.

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
Manual backfill done 2026-10-04 (before item 10's tooling; every path checked on disk). Planner over the 31
dispatchable open items, `--max 10`: **20 waves, largest 7** (before the backfill: 24 waves, largest 2). The most-shared
declared paths, by number of open items naming them (companion expansion not counted, so the real counts are higher):
`loomwright/skills/automate-loop/SKILL.md` 11 · `vendor-coupling-manifest.json` 7 · `RESULT_SCHEMAS.md` 7 ·
`ARCHITECTURE_CONTRACTS.md` 7 · `meta-sync.sh` 6 · `test-meta-sync.sh` 6 · `automate-helpers.sh` 6 ·
`agents/supervisor.md` 6 · `test-automate-trail.sh` 5 · `test-automate-helpers.sh` 5. Scope 1 still re-ranks with
`--explain` (companions included) once item 10 lands; the automate-loop SKILL.md is the clear first target, so
Scope 4's "skill not split here" default needs revisiting.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-07T00:47:52Z
- **Brief:** .supervisor/jobs/done/2026-10-06-split-shared-hotspot-files.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/408
