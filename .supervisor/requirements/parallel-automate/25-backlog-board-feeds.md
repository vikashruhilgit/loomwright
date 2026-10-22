# 25 — Backlog board feeds: the Floor surface, a generated `BACKLOG.md` at meta push, a `lane-status` pointer, and a once-a-day SessionStart nudge

## Status: pending

## Split from
`parallel-automate/18-backlog-board-and-right-size.md` Part A item A3 (feeds) plus A5's once-a-day nudge, split
2026-10-22 by the owner so `18a-backlog-board.md` fits one PR. The verbatim Part A text lives in 18a's
`## Source text` (A3 and A5); this file carries only the feeds.

## Problem
The board (18a) answers "what is pending" only when someone runs `/backlog`. The places the owner already looks — the
Floor projection, the metadata branch, `lane-status`, session start — still show nothing derived.

## Goal
Each existing surface shows the board's answer or points at it, computed by 18a's `item-state` reader, never
re-derived.

## Scope
1. Floor: a `backlog` surface in `build-floor.sh` fed by `item-state` (state totals + the items needing a decision);
   update `docs/result-schemas/floor-projection.md` and any surface-count claim `check-doc-currency.sh` names.
2. `meta-sync push`: write a generated `BACKLOG.md` (board table) into the managed set — only if the owner approves at
   Launch Pad (see Owner decisions); otherwise drop this Scope line and record it under Non-goals.
3. `lane-status` prints one pointer line to `/backlog` (`automate-lanes.d/status-read.sh`).
4. SessionStart, at most once a day: one line when any item reads `merged_unstamped` or `conflict` (`N backlog items
   need a stamp — run /backlog --verify`), in the existing `session-resume.sh` (never a new `hooks.json` leaf —
   `hooks.json` is guard-protected). Fail-SAFE: a reader error prints nothing and exits 0.

## Non-goals
Changing `item-state` semantics. Any stamp written without the owner.

## Owner decisions (from _BACKLOG.md)
- Open, for Launch Pad to ask: should the generated `BACKLOG.md` join `meta-sync`'s managed set? The
  `loomwright-meta` branch is public and world-readable (verified 2026-10-13); the board lists every requirement
  item's path and state.

## Acceptance criteria
- Given a fixture tree with one `merged_unstamped` item, the Floor `backlog` surface and the SessionStart line both
  report it; with none, the SessionStart line is absent.
- The SessionStart line prints at most once per calendar day (fixture with a stamp file from today).
- A failing `item-state` call leaves session start silent and exit 0 (fail-SAFE test).
- `bash scripts/check-version-bump.sh` passes with the `changelog.d/pa25-backlog-board-feeds.md` fragment.

## Validation (must pass before merge)
1. Targeted tests: `test-build-floor.sh`, `test-session-resume.sh`, `test-meta-sync.d/01-sync-core.sh` (if Scope 2
   stays), the lanes status tests, `check-doc-currency.sh`, `test-citation-drift.sh`. Full `ci-local` on GitHub CI.
2. Running system: one fresh session start in this repo — paste the nudge line (or its absence, with `/backlog
   --json` totals showing why).
3. Rollback: `git revert`.

## Depends on
18a-backlog-board.md

## Touches
loomwright/scripts/build-floor.sh
loomwright/scripts/test-build-floor.sh
loomwright/docs/result-schemas/floor-projection.md
loomwright/scripts/meta-sync.d/commands.sh
loomwright/scripts/test-meta-sync.d/01-sync-core.sh
loomwright/scripts/automate-lanes.d/status-read.sh
loomwright/scripts/test-automate-lanes.d/
loomwright/scripts/session-resume.sh
loomwright/scripts/test-session-resume.sh
loomwright/docs/HOOKS.md
changelog.d/pa25-backlog-board-feeds.md
