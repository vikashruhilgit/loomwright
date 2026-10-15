# automate-speed/25 — /automate reads the lanes, resume and branch-mode files only when the run needs them

## Status: pending

## Problem
`commands/automate.md` Step 0 tells the main thread to read every automate-loop split file "each in full, in this
order", whatever the run is. On 2026-10-15 a one-item, sequential, fresh `/automate` run in vendsy/hub (PR #445, a
6-file fix) read `lanes.md` (47K chars), `command-lanes.md` (4K), `resume.md` (19K) and `branch-mode.md` (8K) in its
first 30 seconds — ~78K chars it never used — and carried them in context for the rest of the item (peak 773K; the
coordinator spent 82M context tokens against 2.8M for the worker that wrote the code). The same files were loaded on
loomwright PR #555's item. The parallel-automate/22 split was move-only, so splitting `SKILL.md` saved nothing while
this instruction reads every split back in.

## Goal
<!-- bump: patch -->
Step 0 reads only what every run needs (`SKILL.md`, `intake.md` when building a Queue, `per-item-loop.md`,
`modes-and-merge-gate.md`, `invariants.md`, `commands/autonomous.md`, `commands/review-pr.md`) and names the
condition under which each other split file is read, at the point the run reaches it.

## Scope
- Rewrite the `<!-- index-only -->` read list in `commands/automate.md` Step 0 into "always" and "only when" rows:
  - `lanes.md` and `command-lanes.md` — only when `--parallel` was given, or a helper reports a live lane
    (`pick-guard` → `live_lane`, `lane-*` subcommands).
  - `resume.md` — only when `--resume` was given or the start-up `resume-glob` finds an incomplete run to offer.
  - `branch-mode.md` — only when `setup-memory.sh mode` reports branch mode on (or a helper reports a branch-mode
    step such as `trail-unstage` / meta push).
  - `intake.md` — only when building a new Queue (not on `--resume`).
- Mirror the same rows in the `SKILL.md` index note (also an index-only block) so the two never disagree; one is the
  authority, the other points at it (house rule: a restated list is a pointer or is updated in the same change).
- Add one line to Step 0: read plugin files with the Read tool, never `cat` several of them in one Bash call (a
  too-large Bash result is saved to a file and read back, loading the same text twice — seen on PR #555's session).

## Invariants
- `test-automate-loop-split.sh` stays green: only index-only blocks change; no moved section's bytes change.
- Every split file remains reachable: each "only when" row names a trigger the run can observe.
- No rule moves or disappears: this item changes WHEN a file is read, not what it says.

## Non-goals
- Shrinking or rewriting any split file (items 13–16). Changing the driver (06–09).

## Owner decisions (from _BACKLOG.md)
- D1: no rule is dropped — conditional loading changes timing only.

## Acceptance criteria
- Given `commands/automate.md` Step 0, then its read list has an "always" group and an "only when" group, and the
  "only when" group names `lanes.md`, `command-lanes.md`, `resume.md`, `branch-mode.md` and `intake.md` with their
  triggers.
- Given the `SKILL.md` index note, then it points at Step 0 instead of restating the list.
- `test-automate-loop-split.sh` passes with no change to its pinned proofs.

## Validation (must pass before merge)
1. `test-automate-loop-split.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`; report `<passed>/<total>`.
2. Running system: start one sequential `/automate` run on a one-item backlog in a scratch repo (no `--parallel`, no
   incomplete run, branch mode off); paste the list of plugin files the session read (from its transcript) — it must
   not contain `lanes.md`, `command-lanes.md`, `resume.md` or `branch-mode.md`.

## Measurements
- Context tokens at the first PICK for that run vs PR #445's session (~400K chars of protocol read before PICK).
  Frozen commit: this PR's merge commit.

## Depends on
none

## Touches
loomwright/commands/automate.md
loomwright/skills/automate-loop/SKILL.md
changelog.d/as25-automate-load-by-mode.md
