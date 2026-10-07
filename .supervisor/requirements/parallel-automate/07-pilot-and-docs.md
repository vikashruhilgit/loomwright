# 07 — Pilot on a real queue + documentation close-out

## Status: parked (runs LAST — waits on every item in `## Depends on`: 21 fleet operations (06 is parked inside it as Part A), 14, automate-followups/34, automate-followups/36, 18; set `## Status: pending` once all have merged)

## Depends on
21-fleet-operations.md
14-lanes-pane-addon.md
../automate-followups/34-sweep-and-janitor.md
../automate-followups/36-s3-engine-fixes.md
18-backlog-board-and-right-size.md

## Touches
CLAUDE.md
README.md
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/commands/automate.md
loomwright/commands/agent-help.md
loomwright/docs/PITFALLS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md

## Problem
Items 01–06 are each tested hermetically. None of that shows a real queue running in parallel end to end, and the
standing documents still describe a sequential engine.

## Goal
One real queue is driven with `--parallel`, measured against the sequential baseline, and the standing docs
describe what the plugin now does.

## Scope
1. **Pilot queue.** Choose a pending queue whose items are genuinely independent, and VERIFY it: build each item's
   `Touches` from its own Scope, then let `plan-waves` decide. Do not take an overview's word — e.g.
   `agnostic-phase1/00-overview.md` says its items "touch disjoint files except CHANGELOG / plugin.json version
   bumps; run sequentially, never in parallel": half of that sentence is the reason item 01 exists, the other half
   is an instruction this pilot would be overriding, so that queue qualifies only if the owner says so and the
   declared sets really are disjoint after companion expansion.
2. **Declare the queue.** Add `## Depends on` / `## Touches` (strict grammar, item 04) to each pilot item.
3. **Run** `/automate --folder <queue> --parallel 2` in safe mode. The owner merges by hand.
4. **Measure and write down** (parent `## Progress` and `pilot-report.md` beside this file): wall-clock from first
   PICK to last merge versus the sum of the items' individual RUN+DRAIN times; tokens per lane and in total;
   self-test wall-clock inside a lane versus alone; PRs opened (target: one per item, zero metadata PRs, zero
   release PRs); every manual intervention; every lane park and its cause; any conflict at wave close; whether the
   weekly cap or a rate limit was hit.
5. **Decide the default lane count** (P2) from the numbers — as a separate one-line change, not here.
6. **Fix or file.** A defect that breaks an invariant in 00-overview is fixed before this item closes; anything
   else becomes a requirement draft under `proposed/`.
7. **Docs:**
   - `CLAUDE.md` §"Failure-Mode Invariants": single-drain ownership "per lane"; the merge executor unchanged and
     never used by parallel runs; metadata-branch and bump rules. Version-free and count-free.
   - `README.md`, `commands/agent-help.md`: the flag, what a lane is, how to resolve a parked lane, how a wave
     closes.
   - `docs/PITFALLS.md`: retire tracked-trail pitfalls; add "a lane parked at a human gate", "metadata not
     pulled", "meta-push failed".
   - Grep the OLD claims repo-wide ("single-open-PR", "Parallel / multi-item execution", "trail PR") and fix every
     surface in one pass, including hyphenated variants and agent↔command mirrors.

## Non-goals
New features. Enabling `--auto-merge` for parallel runs.

## Acceptance criteria
- The pilot queue's items are merged with one PR each, no metadata-only PR and no release PR.
- `pilot-report.md` exists with the measurements in Scope 4, including the honest sequential comparison.
- No standing doc still describes `/automate` as sequential-only or a trail PR as current behaviour for a
  branch-mode repo.
- `scripts/check-doc-currency.sh` and the full test loop are green.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path:** after the pilot, run ONE item sequentially (no `--parallel`) and confirm it completes with
   one PR — the sequential path survived a real parallel run on the same checkout.
3. **Running system:** the pilot itself. `pilot-report.md` carries observed numbers only, every lane park with its
   cause, and item 05's leak check taken after the last merge.
4. **A failure this must catch:** each changed doc claim names the command or run-file line that shows it; a claim
   with no such pointer is removed, not kept.
5. **Rollback:** docs-only PR — `git revert`.

## Verified premises (re-check before starting)
- `agnostic-phase1/00-overview.md` §Order — the full sentence quoted in Scope 1.
- CLAUDE.md is deliberately version-free and count-free (§"Project Overview").

## Status note
Parked until item 06 has merged.

## Depends re-pointed 2026-10-07 (S3 operator f849e0cc)
- `06` → `21-fleet-operations.md`: item 06 was merged into 21 (Part A) with item 12 (Part B), owner decision relayed by S3
  session 2216aefd. Nothing else in this file changed.
- **Amended 2026-10-07 (owner, relayed by S3 session 2216aefd): pa/07 really runs last.** Milestone B is "pa/07 last, so the
  pilot exercises pa/12–14 and the docs cover them", but `## Depends on` named only 21, so the planner could have
  placed it before 14 / af/34 / af/36 / 18. All four added; the status line re-pointed (06 is parked inside 21).
