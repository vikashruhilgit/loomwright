# 07 — Parallel pilot report from the 2026-10-15 run + documentation close-out

## Status: pending

## Re-scoped 2026-10-22 (owner, /product-owner session; re-verified read-only against main 7b7cb08 / v17.14.1)
The owner decided the 2026-10-15 run `automate-2026-10-15-163325` — the automate-speed backlog, 24 items, safe mode,
`--parallel 4`, 8 waves (wave PRs #567, #596, #606, #631, #641, #651), `## Status: done` — **is the pilot**. It went
further than the planned 2-lane pilot. So this item no longer waits on anything: it writes the report from that
run's record and closes out the docs. The pre-2026-10-22 text is kept below, demoted, under `## Original text`;
where it and this header differ, this header wins.

## Problem
No report exists for the parallel run, and the standing docs still partly describe a sequential engine:
- `CLAUDE.md` §"Failure-Mode Invariants" never mentions lanes in the single-drain ownership invariant.
- `README.md`'s `/automate` block has no `--parallel` flag, and "Single drain, single open PR … will not pick a
  new item" describes only the sequential mode.
- `docs/PITFALLS.md` has "metadata not pulled" (pa/03) but not "a lane parked at a human gate" or "meta-push failed".
Already correct, leave alone: `commands/agent-help.md` covers the flag; the lanes pane is in the README; the remaining
"trail PR" / "single-open-PR" hits describe the sequential non-branch-mode path, which still works that way.

## Goal
A committed pilot report with the measurements the run's record supports, and standing docs that describe what
`/automate --parallel` does.

## Scope
1. **Report** — `docs/evidence/pa07-parallel-pilot-report.md` (committed; never the PR body alone), built from the
   run's parent file and lane files on the metadata branch
   (`git show origin/loomwright-meta:.supervisor/automate/automate-2026-10-15-163325.md`, plus the `-L<n>.md` lane
   files): wall-clock from first PICK to last merge per wave and overall; PRs opened (one per item plus one wave PR
   per wave); every lane park and its cause; every "owner-approved hand step"; conflicts or stops at wave close
   (e.g. wave 1's token-budget stop); leak checks at fleet close-out; whether a rate limit or the weekly cap hit.
   **Not measurable from the record — say so, never estimate:** tokens per lane, and an honest sequential baseline.
   Name what a future run would need to log to measure them.
2. **Docs** (Original Scope 7, re-verified):
   - `CLAUDE.md` §"Failure-Mode Invariants": single-drain ownership holds **per lane**; the merge executor is
     unchanged and never used by parallel runs; how the metadata branch and the version bump fold work in a wave
     (one wave PR carries the bump). Version-free and count-free.
   - `README.md`: the `--parallel N` flag in the `/automate` block, what a lane and a wave are, and the
     single-open-PR sentence scoped to sequential mode.
   - `docs/PITFALLS.md`: add "a lane parked at a human gate" and "meta-push failed"; there is no tracked-trail
     pitfall left to retire.
   - Grep the old claims repo-wide in one pass (including hyphenated variants and agent↔command mirrors), and fix
     only the ones that are false for a parallel run.
3. **Fix or file:** a defect the report finds that breaks an invariant is named in the report and filed as a draft
   under `.supervisor/requirements/proposed/`, never fixed in this docs PR.

## Non-goals
A new pilot run. Changing the default lane count (stays unset; a separate one-line change if the owner wants it).
New features. Enabling `--auto-merge` for parallel runs.

## Owner decisions (from _BACKLOG.md)
- 2026-10-22: the 2026-10-15 `--parallel 4` run counts as the pilot; no fresh pilot; this item drops its
  dependencies on pa/18, 39c, 39d and the rest.

## Acceptance criteria
- `docs/evidence/pa07-parallel-pilot-report.md` exists; every number in it cites the run-file line it came from;
  tokens per lane and the sequential baseline are listed as "not measurable from the record" with what to log next.
- No standing doc describes `/automate` as sequential-only, and none describes a trail PR as current behaviour for
  a branch-mode repo.
- The original acceptance "no release PR" is replaced by the shipped behaviour: one PR per item plus one wave PR per
  wave carrying the version bump.
- `bash scripts/check-version-bump.sh` passes with the `changelog.d/pa07-pilot-report-and-docs.md` fragment.

## Validation (must pass before merge)
1. `check-doc-currency.sh`, `test-citation-drift.sh`, and any test that pins `CLAUDE.md` / `README.md` text. Full
   `ci-local` on GitHub CI (owner rule 2026-10-12).
2. A failure this must catch: each changed doc claim names the command or run-file line that shows it; a claim with
   no such pointer is removed, not kept.
3. Rollback: docs-only PR — `git revert`.

## Depends on
none

## Touches
CLAUDE.md
README.md
loomwright/docs/PITFALLS.md
docs/evidence/pa07-parallel-pilot-report.md
changelog.d/pa07-pilot-report-and-docs.md

## Original text (pre-2026-10-22, demoted — superseded where the header above differs)

### 07 — Pilot on a real queue + documentation close-out

#### Status: parked (runs LAST — waits on every item in `## Depends on`: 21 fleet operations (06 is parked inside it as Part A), 14, automate-followups/34, automate-followups/36, 18; set `## Status: pending` once all have merged)

#### Depends on
21-fleet-operations.md
14-lanes-pane-addon.md
../automate-followups/34-sweep-and-janitor.md
../automate-followups/36-s3-engine-fixes.md
18-backlog-board-and-right-size.md

#### Touches
CLAUDE.md
README.md
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/commands/automate.md
loomwright/commands/agent-help.md
loomwright/docs/PITFALLS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md

#### Problem
Items 01–06 are each tested hermetically. None of that shows a real queue running in parallel end to end, and the
standing documents still describe a sequential engine.

#### Goal
One real queue is driven with `--parallel`, measured against the sequential baseline, and the standing docs
describe what the plugin now does.

#### Scope
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

#### Non-goals
New features. Enabling `--auto-merge` for parallel runs.

#### Acceptance criteria
- The pilot queue's items are merged with one PR each, no metadata-only PR and no release PR.
- `pilot-report.md` exists with the measurements in Scope 4, including the honest sequential comparison.
- No standing doc still describes `/automate` as sequential-only or a trail PR as current behaviour for a
  branch-mode repo.
- `scripts/check-doc-currency.sh` and the full test loop are green.

#### Validation (must pass before merge)
1. **Baseline:** full loop on base and branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path:** after the pilot, run ONE item sequentially (no `--parallel`) and confirm it completes with
   one PR — the sequential path survived a real parallel run on the same checkout.
3. **Running system:** the pilot itself. `pilot-report.md` carries observed numbers only, every lane park with its
   cause, and item 05's leak check taken after the last merge.
4. **A failure this must catch:** each changed doc claim names the command or run-file line that shows it; a claim
   with no such pointer is removed, not kept.
5. **Rollback:** docs-only PR — `git revert`.

#### Verified premises (re-check before starting)
- `agnostic-phase1/00-overview.md` §Order — the full sentence quoted in Scope 1.
- CLAUDE.md is deliberately version-free and count-free (§"Project Overview").

#### Status note
Parked until item 06 has merged.

#### Depends re-pointed 2026-10-07 (S3 operator f849e0cc)
- `06` → `21-fleet-operations.md`: item 06 was merged into 21 (Part A) with item 12 (Part B), owner decision relayed by S3
  session 2216aefd. Nothing else in this file changed.
- **Amended 2026-10-07 (owner, relayed by S3 session 2216aefd): pa/07 really runs last.** Milestone B is "pa/07 last, so the
  pilot exercises pa/12–14 and the docs cover them", but `## Depends on` named only 21, so the planner could have
  placed it before 14 / af/34 / af/36 / 18. All four added; the status line re-pointed (06 is parked inside 21).

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-24T03:30:14Z
- **Brief:** .supervisor/jobs/done/2026-10-22-pa07-pilot-report-and-docs.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/673
