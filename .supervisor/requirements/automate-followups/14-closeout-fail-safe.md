# 14 — Close-out fail-safe: nothing a prior item left behind is silently skipped before the next item starts

## Status: pending

> **Origin (2026-10-01).** After item 12 merged and its close-out ran from the merge watcher, the owner asked whether
> a forgotten close-out (cleanup + merge) is always taken care of before the next job starts. Within one run it is
> (§6 step 1 runs `closeout` before PICK, and the single-open-PR invariant blocks PICK on an open PR), but three gaps
> remain. The owner wants the close-out to be a fail-safe: either it completed, or the run stops and asks.

## Problem
1. **A close-out that could not finish is only logged.** `closeout` (`scripts/automate-trail.sh`) refuses to remove a
   worktree whose tip differs from the merged head or that is still dirty after salvage, keeps a local branch whose tip
   differs, and skips the `main` sync when the primary checkout is dirty outside the trail paths. Each refusal is one
   `closeout: skipped — …` / `kept …` line in `## Progress`. PICK then proceeds, so the leftover is easy to miss.
2. **Close-out is per run.** RESUME (§4) reconciles and closes out only the run it continues. If an older run is
   `paused` / `awaiting_merge` and its PR has since merged, but the owner starts a new run (or resumes a different one),
   that older item is never closed out (no stamp, no check-off, no worktree/branch cleanup, no trail PR).
3. **Nothing surfaces it at session start.** `scripts/session-resume.sh` (SessionStart) does not report a
   merged-but-not-closed-out item or a live merge watcher (`<run_id>.merge-watch` marker) — the SKILL §6 honest limit.

## Goal
Before any `/automate` PICK, every item any run left in a merged state is closed out, and anything close-out could not
safely finish is put to the owner as an explicit decision (interactive) or stops the run (non-interactive). When
everything is already closed out, this is a no-op: no question, no mutation, no extra Progress noise beyond one
"nothing to close out" line.

## Scope (recommendation — the brief decides the details)
- **(a) Close-out completion gate at PICK.** After RECONCILE's `closeout`, classify its output: `removed|synced|stamped|
  checked` and `skipped — already …` lines are complete; any `kept …`, `refused`, or a `skipped — <reason>` that is not
  an "already done" idempotent skip is a **leftover**. Interactive: `AskUserQuestion` per leftover (clean up now / keep
  and continue / stop). "Clean up now" re-runs the specific safe step after salvage (never `--force`, never a reset,
  never deleting unmerged work). Under `--non-interactive-fallback`: park with a `pause_reason` (reuse an existing value
  or add one to the §3 vocabulary + RESULT_SCHEMAS — decide in the brief), never proceed silently.
- **(b) Cross-run close-out at start/resume.** At every `/automate` start or resume (before the run's own RECONCILE),
  glob every run file (`resume-glob`), and for each other run's in-flight `## Current` item whose PR reads `merged`
  (`reconcile-item`), run `closeout` for THAT run file (its own run lock owner, its own trail). Read-only for runs whose
  PR is open/closed/gone. One `## Progress` line in the CURRENT run naming each cross-run close-out performed.
- **(c) SessionStart surfacing.** `session-resume.sh` prints one advisory line per merged-but-not-closed-out item and
  per live merge watcher (pid + PR), read-only, fail-SAFE (always exit 0), bounded (no `gh` calls if offline —
  degrade to "unverified").
- **(d) Idempotency is the invariant.** Every new step must be a pure no-op when the work is already done (the common
  case: the watcher already closed the item out during the last job). Prove it with tests that run each step twice and
  against an already-closed-out fixture.

## Acceptance criteria
- [ ] Given a close-out that kept a worktree (tip ≠ merged head) and a branch, the next PICK does not proceed silently:
      interactive asks one decision per leftover; non-interactive parks with a named `pause_reason` (fixture test +
      SKILL-text leg).
- [ ] Given an already fully closed-out item (watcher ran), the next PICK asks nothing, mutates nothing, and appends at
      most one "nothing to close out" line (fixture test).
- [ ] Given two run files where run A is paused `awaiting_merge` on a now-merged PR and the owner starts/resumes run B,
      run A's item is closed out (stamp, check-off, cleanup, trail) before B picks, and run B's file records it; run A's
      file shows the close-out lines (fixture test with stubbed `gh`).
- [ ] An open / closed-unmerged / gone PR in another run is never touched (fixture test).
- [ ] `session-resume.sh` prints the merged-not-closed-out and live-watcher lines, prints nothing extra when there is
      nothing to report, and always exits 0 (test).
- [ ] "Clean up now" never removes a worktree or branch whose tip is not the merged head, never discards uncommitted
      work without `worktree-salvage.sh`, never force-pushes or resets (negative legs).
- [ ] `gh pr merge --squash` positive grep unchanged; `gate-eval` unchanged; SKILL §4/§6/§8 + RESULT_SCHEMAS
      §AUTOMATE_RUN + `commands/automate.md` (surface only) updated; full test loop green under bash and `/bin/bash` 3.2.

## Out of scope
- Auto-merging the feature PR or the trail PR (owner merges both; the trail PR still need not block the next item).
- Closing out work that was never run through `/automate` (that stays `reconcile-status --apply`, human-run).

## Risks
- **Cross-run mutation.** Closing out run A from run B's session touches another run's file and lock — use run A's own
  lock owner and helpers; never pick or modify A's Queue beyond its in-flight item's check-off.
- **False "leftover" on an idempotent re-run.** The classifier must treat "already removed/stamped/checked" skips as
  complete, or every resume would ask (the AC2 no-op leg pins this).
- **Question fatigue.** Batch leftovers into one `AskUserQuestion` call (≤4 per call).

## Depends on
none

## Touches
loomwright/scripts/automate-trail.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-session-resume.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/commands/automate.md
changelog.d/automate-followups-14-closeout-fail-safe.md
