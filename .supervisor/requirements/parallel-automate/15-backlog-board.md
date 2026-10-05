# 15 — One backlog board: every requirement item's real state, derived, never hand-kept

## Status: pending

## Problem
Owner (2026-10-05): "this lane stuff picking stuff randomly — how can we keep track of all the tasks which are done,
pending and all, we need a good way to keep track of all those". (Lanes do not pick at random: the operator picks a wave
from `plan-waves`, and each lane gets exactly one item through its backlog file. But nothing shows that, or the rest.)

Today the state of the backlog is spread across five places, and no reader combines them:
- **Item files** under `.supervisor/requirements/<folder>/NN-*.md`: the first `## Status:` line, plus a done stamp that
  closeout APPENDS at the end (`<!-- loomwright:requirement-closeout -->` / `## Status: done`). So the first line can say
  `pending` while the item is done; on 2026-10-04 the operator counted 39 "pending" items by first line, when 26 were
  really open.
- **Run files** (`.supervisor/automate/*.md`): which item is in flight, parked or awaiting merge; one per run, and lanes
  add one per lane.
- **Lane clones** (outside the repo): which item each live lane is working on.
- **GitHub:** open PR, checks, merged commit.
- **Prose records** (S1/S2 run records, overviews): decisions, waves, why something was skipped.

A one-off board built from the files on 2026-10-05 read **97 done · 59 open · 5 in a lane · 5 parked · 1 proposed**. The
37 open items counted by explicit `pending|ready|parked` lines the day before differ from those 59 by ~22 items with **no
`## Status:` line or a non-standard one** (mostly `final-state/`, `twin-loop/`, `twin-remediation/`). Some may be done,
superseded or abandoned with no stamp. There is no single honest answer to "what is left?"

The Floor (`build-floor.sh` → `floor.json`) already projects 14 `.supervisor/` surfaces, but not requirement items.

## Goal
One command and one view answer, for every requirement item: is it done, in flight (where: lane / run / PR), parked,
blocked, open-and-ready (in which wave), or unknown (and why). All of it derived from the existing sources on every run,
never a hand-maintained list, and the counts always add up.

## Scope
1. **One canonical status reader** (`automate-helpers.sh item-state <item>` or a small `backlog-state.sh`), used by every
   consumer instead of ad-hoc greps: `done` (done or done_with_escalation stamp anywhere), `abandoned`, `parked`,
   `proposed`, `in_flight` (named by a non-done run file's `## Current`, or by a live lane's backlog), `pr_open` (a run or
   lane names a PR that `gh` reports open, with its checks), `merged_unstamped` (PR merged but no done stamp: needs
   closeout), `open` (explicit `pending`/`ready`), and **`unknown`** (no status line or a value outside the enum, reported
   with the offending line). Never guess: `unknown` is a first-class state that the board shows, not folds into `open`.
2. **`/backlog` (or `/automate --board`)**: a table grouped by folder: item, state, wave (from `plan-waves`), lane/run, PR
   and checks, merged commit, last change. `--json` for other views. `--state open|unknown|in_flight|…` filters. Totals that
   add up to the number of item files, with each state counted once.
3. **Feeds the existing views, not a new UI:** a `backlog` surface in `floor.json` (the Floor shows it), a `BACKLOG.md`
   regenerated on the metadata branch at each `meta-sync push` (readable on GitHub), and `lane-status` (item 05) pointing
   at it. The pane add-on (item 14) can render it.
4. **Hygiene, owner-gated:** `--unknown` lists every item with no or a bad status line, with a suggested fix
   (stamp done with the PR that shipped it, mark abandoned, or add `## Status: pending`). It suggests only; the owner
   applies, or `reconcile-status --apply` does where it has PR evidence.
5. **Tests:** the reader on fixtures for every state (including first-line `pending` plus an appended done stamp ⇒ `done`;
   a missing status ⇒ `unknown`; a lane backlog naming the item ⇒ `in_flight`); totals add up; `--json` round-trips;
   `gh` unavailable ⇒ PR fields `unverified`, never silently `open`.

## Non-goals
- No new state store and no manual board: every value is recomputed from the sources.
- No automatic status edits outside `reconcile-status`'s existing evidence rule.

## Acceptance criteria
- On the real backlog, `/backlog` totals equal the number of item files, and every item counted as `open` has an explicit
  `pending`/`ready` line; the ~22 status-less items appear as `unknown` with the reason.
- During a lane wave, each lane's item shows `in_flight` with its lane name, and after merge plus closeout `done` with the PR.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `reconcile-status`, `resolve-folder` and `plan-waves` outputs unchanged on existing fixtures.
3. Running system: paste `/backlog` totals and the `unknown` list over this repo's real backlog.
4. A failure this must catch: read only the first `## Status:` line ⇒ the appended-done-stamp fixture fails.
5. Rollback: `git revert`.

## Root cause found 2026-10-05 (why 21 items sat at `brief-shipped`)
`loomwright/scripts/stamp-requirement-status.sh` (runs at every SessionStart) stamps `## Status: brief-shipped` when a
brief lands in `.supervisor/jobs/done/`: by design it records only what it can prove (the work ran), never `done`. **Nothing
ever upgrades `brief-shipped` to `done`**, so every requirement that went through it stayed "open" to every reader. A
read-only validation of the 32 status-less / `brief-shipped` items on 2026-10-05 found 19 done, 2 done-with-escalation, 5
abandoned/superseded, 1 parked and only 5 still open (+1 partial); the owner approved the stamps. Scope addition:
`brief-shipped` is a first-class board state ("shipped, not verified"), and `/backlog --unknown` lists every
`brief-shipped` item with its merged PR, so the owner can verify-and-stamp in one pass instead of it rotting silently.

## Evidence
The 2026-10-05 one-off board (this session); the 39-vs-26 miscount (S1/S2 records, `parallel-automate/10` Verified premises).

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/build-floor.sh
loomwright/scripts/test-build-floor.sh
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/commands/backlog.md
loomwright/commands/agent-help.md
loomwright/skills/automate-loop/SKILL.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/parallel-automate-15-backlog-board.md
