# 28 — A run whose Queue is fully done stops showing up as "incomplete" to every later run

## Status: pending

## Problem
`skills/automate-loop/SKILL.md` §"Run status" says: after a close-out the run is `paused` + `awaiting_go`, and `done`
is set only when the Queue is fully resolved by a `/automate --resume` that terminates with its `--reason done`
trail; `closeout` never writes `done`, "even when it checked off the last item". That works sequentially, where the
owner resumes. **A lane run is never resumed after its closeout**, so every finished single-item lane run stays
`paused / awaiting_go` with an empty Queue forever.

Seen on 2026-10-04: S1 v2's two lane runs (`automate-2026-10-04-072706`, `-072926`) were carried to `loomwright-meta`
after both PRs merged. The next two lanes (wave w1, items 08 and 10) each opened with a RESUME question listing
them as "incomplete runs" (plus the genuinely open `automate-2026-09-30-054439`). At 5–10 lanes per wave, every lane
of every later wave would ask about every earlier lane's finished run.

## Goal
A paused run with no unchecked Queue item and nothing in flight is finished by the engine itself, through the same
`done` termination and trail the Queue-resolved path already uses, so RESUME lists only runs with work left.

## Scope
1. **RESUME auto-finalizes the empty ones:** when the resume glob finds a run with `## Status: paused`,
   `pause_reason: awaiting_go`, `remaining` = 0 (`automate-helpers.sh remaining`) and `## Current` status `done`, it
   terminates that run exactly as the Queue-resolved path does (`--reason done` trail, `## Status: done`) WITHOUT
   asking, records one `## Progress` line ("auto-finalized: queue empty after closeout"), and does not list it.
   `closeout` keeps never writing `done` (the invariant stands; the terminal write stays in the termination path).
2. **Lane mode:** item 05's coordinator runs the same finalization on a lane's run at fleet closeout, so a wave
   leaves no paused-empty runs behind.
3. **Anything else still asks:** a run with an unchecked item, an in-flight `## Current`, or any other pause reason is
   listed as today.
4. **Tests:** a paused/awaiting_go/remaining-0 run is finalized and not listed; one unchecked item ⇒ listed; a
   different pause reason ⇒ listed; the trail line matches the Queue-resolved termination byte-for-byte apart from the
   reason text; `closeout` alone still never writes `done`.

## Acceptance criteria
- After S1 v2's two runs are finalized, a new lane's RESUME lists only `automate-2026-09-30-054439`.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `test-automate-helpers.sh` / `test-automate-trail.sh` closeout groups pass unedited.
3. Running system: run RESUME against a copy of today's run files; paste the finalized lines and the shortened list.
4. A failure this must catch: let `closeout` write `done` ⇒ the invariant test fails.
5. Rollback: `git revert`.

## Evidence
Wave w1 lanes' first questions (2026-10-04, this session); S1 run record.

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/skills/automate-loop/SKILL.md
changelog.d/automate-followups-28-finished-runs-stop-looking-incomplete.md
