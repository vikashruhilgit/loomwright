# 29 — The run file's `## Current` block is set by a helper at PICK, and a stale one is caught

## Status: pending

## Problem
The run file is the contract, the dashboard and the resume state (`skills/automate-loop/SKILL.md`). Its `## Current`
block says which item is in flight, its status, PR and branch. Setting it at PICK is a prose step only.

Seen 2026-10-04 in wave w1: lane w1-10 created its run file with the correct initial `## Current: item: null |
status: null | pr: null | branch: null`, then PICKED item 10 (`## Progress`: "picked … 10-touches-backfill-lint-and-
explain.md"), ran `/autonomous` to PR #377 and started the owned drain — and **never updated `## Current`**. Its log
shows exactly one `runfile-write` call (the creation); every later update went through `progress-append`, which only
appends to `## Progress`. Lane w1-08, same engine and same session flags, set `## Current` correctly. v1's lane B had
the related "run file stale after resume".

Consequences: a RESUME after a crash would read "nothing in flight" while a PR is open mid-drain; dashboards
(`lane-status`, the lanes pane, the harness) show `null`; `gate-eval` and closeout key on the PR recorded there.

## Goal
`## Current` can only move through a helper the engine must call, and any write that implies an item is in flight
while `## Current` says otherwise is refused or flagged loudly.

## Scope
1. **`automate-helpers.sh current-set <runfile> --item <path> --status <s> [--pr <url>] [--branch <b>]
   [--pause-reason <r>]`**: rewrites only the `## Current` block through the same guarded write path `runfile-write`
   uses (refuses empty or malformed input, keeps the file intact on failure). Status values come from the
   documented enum.
2. **The skill's PICK, RUN-done, DRAIN-start, park and closeout steps call `current-set`** (prose edits name it,
   with the exact arguments), instead of hand-editing the block.
3. **Consistency guard in `progress-append`:** appending a line that starts with `picked `, `ran /autonomous`,
   `owned drain started` or `parked ` while `## Current` has `item: null` exits non-zero with
   `current_not_set` (the line is still appended, the guard is loud, not lossy). Fail-CLOSED for the engine,
   since an unset Current is resume-state corruption, not cosmetics.
4. **RECONCILE repairs:** on resume, a run whose `## Progress` shows a picked item and an open PR while `## Current` is
   null rebuilds `## Current` from the last `picked`/`ran /autonomous`/drain lines plus `gh`, and records
   `current_rebuilt`.
5. **Tests:** `current-set` writes and validates; `progress-append` "picked" with a null Current fails
   `current_not_set`; RECONCILE rebuilds from a fixture shaped like w1-10's run file; the sequential path's
   existing tests pass unedited.

## Acceptance criteria
- Replaying w1-10's run-file history through the new helpers refuses at the first "picked" line with Current null.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `test-automate-helpers.sh` / `test-automate-trail.sh` pass with no existing assertion edited.
3. Running system: one real sequential `/automate` item; paste its `## Current` after PICK, after RUN, at park.
4. A failure this must catch: skip `current-set` at PICK ⇒ the guard fires on the next progress line.
5. Rollback: `git revert`.

## Evidence
Wave w1 lane w1-10, run file `automate-2026-10-04-103627.md` (archived at teardown) and its session log.

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/automate-followups-29-current-block-set-by-helper.md
