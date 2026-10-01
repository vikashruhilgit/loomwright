# 07 — Pilot on a real queue + documentation close-out

## Status: parked (waits on item 06 — set `## Status: pending` once 06 has merged)

## Depends on
06

## Touches
`CLAUDE.md`, `README.md`, `loomwright/skills/automate-loop/SKILL.md`, `loomwright/commands/automate.md`,
`loomwright/commands/agent-help.md`, `loomwright/docs/PITFALLS.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`,
the pilot queue's requirement files (adding `Depends on` / `Touches`)

## Problem
Items 01–06 are each tested hermetically. None of that shows a real queue running in parallel end to end, and the
standing documents still describe a sequential engine.

## Goal
One real queue is driven with `--parallel`, the result is measured against the sequential baseline, and the
standing docs describe what the plugin now does.

## Scope
1. **Pilot queue.** Use a queue whose items are genuinely independent. Candidate: `agnostic-phase1` — its overview
   says 02–05 "touch disjoint files except CHANGELOG / plugin.json version bumps", which item 01 removed. If it has
   already been run sequentially by then, pick the next pending queue and say which.
2. **Declare the queue.** Add `## Depends on` / `## Touches` to each pilot item (verify each `Touches` list against
   the item's own Scope; do not copy the overview's claim).
3. **Run** `/automate --folder <queue> --parallel 3` in safe mode. The owner merges; no `--auto-merge` in the pilot.
4. **Measure and write down** (in the parent run file's `## Progress` and a short `pilot-report.md` beside this
   file): wall-clock from first PICK to last merge versus the sum of the items' individual RUN+DRAIN times; tokens
   per lane and in total; number of PRs opened (target: one per item, zero metadata PRs); every manual
   intervention; every lane park and its cause; any merge-train conflict.
5. **Fix or file.** A defect that breaks an invariant in 00-overview is fixed before this item closes; anything
   else becomes a requirement draft under `proposed/`.
6. **Docs:**
   - `CLAUDE.md`: §"Failure-Mode Invariants" — restate single-drain ownership and the merge executor "per lane";
     add the metadata-branch and bump-at-merge invariants; keep it version-free and count-free.
   - `README.md` and `commands/agent-help.md`: the `--parallel` flag, what a lane is, how to resolve a parked lane.
   - `docs/PITFALLS.md`: retire tracked-trail pitfalls; add "a lane parked at a human gate", "metadata not synced".
   - `skills/automate-loop/SKILL.md` Quality Gates list.
   - Grep the OLD claims repo-wide ("single-open-PR", "Parallel / multi-item execution", "trail PR") and fix every
     surface in one pass, including hyphenated variants.

## Non-goals
New features. Raising the default lane count (decide from the pilot's numbers, as a separate change). Enabling
`--auto-merge` for parallel runs by default.

## Acceptance criteria
- The pilot queue's items are merged with one PR each and no metadata-only PR.
- `pilot-report.md` exists with the measurements in Scope 4, including the honest sequential comparison.
- No standing doc still describes `/automate` as sequential-only or mentions a trail PR as current behaviour.
- `scripts/check-doc-currency.sh` and the full test loop are green.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; both `<passed>/<total>` lines in the PR body.
2. **Unchanged path:** after the pilot, run ONE item sequentially (no `--parallel`) and confirm it still completes
   with one PR — the sequential path survived a real parallel run on the same checkout.
3. **Running system:** the pilot itself. `pilot-report.md` carries observed numbers only (no estimates), every lane
   park with its cause, and the leak check from item 05 (`git worktree list`, lane directory, stray processes,
   `.supervisor/config.json`) taken after the last merge.
4. **Docs match behaviour:** for each doc claim changed, name the command or run-file line that shows it; the
   old-claim grep in Scope 6 returns no current-tense hit. `scripts/check-doc-currency.sh` and
   `loomwright/scripts/test-citation-drift.sh` pass.
5. **Rollback:** docs-only PR — `git revert`. The pilot's merged feature PRs are independent of this item.

## Verified premises (re-check before starting)
- `agnostic-phase1/00-overview.md` §Order (the disjoint-files claim) — verified as TEXT on 2026-10-01; whether the
  items really touch disjoint files was not checked.
- CLAUDE.md is deliberately version-free and count-free (§"Project Overview").

## Status note
Parked until item 06 has merged.
