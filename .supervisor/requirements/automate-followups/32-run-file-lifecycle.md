# 32 — Run-file lifecycle: nothing left behind is skipped, `## Current` is set by a helper, a finished run is finished

## Status: pending

## Merged from (2026-10-05, owner decision before the S3 wave spike)
- Part A: `14-closeout-fail-safe.md` — 14 — Close-out fail-safe: nothing a prior item left behind is silently skipped before the next item starts
- Part B: `28-finished-runs-stop-looking-incomplete.md` — 28 — A run whose Queue is fully done stops showing up as "incomplete" to every later run
- Part C: `29-current-block-set-by-helper.md` — 29 — The run file's `## Current` block is set by a helper at PICK, and a stale one is caught

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Goal
One change set over the run file's state machine: closeout fail-safe before the next item (A), a fully done Queue ends the run instead of lingering as incomplete (B), and `## Current` moves only through a helper with a guard against a stale block (C).

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Parts

### Part A — 14 — Close-out fail-safe: nothing a prior item left behind is silently skipped before the next item starts

#### Problem
1. **A close-out that could not finish is only logged.** `closeout` (`scripts/automate-trail.sh`) refuses to remove a
   worktree whose tip differs from the merged head or that is still dirty after salvage, keeps a local branch whose tip
   differs, and skips the `main` sync when the primary checkout is dirty outside the trail paths. Each refusal is one
   `closeout: skipped — …` / `kept …` line in `## Progress`. PICK then proceeds, so the leftover is easy to miss.
2. **Close-out is per run.** RESUME (§4) reconciles and closes out only the run it continues. If an older run is
   `paused` / `awaiting_merge` and its PR has since merged, but the owner starts a new run (or resumes a different one),
   that older item is never closed out (no stamp, no check-off, no worktree/branch cleanup, no trail PR).
3. **Nothing surfaces it at session start.** `scripts/session-resume.sh` (SessionStart) does not report a
   merged-but-not-closed-out item or a live merge watcher (`<run_id>.merge-watch` marker) — the SKILL §6 honest limit.

#### Goal
Before any `/automate` PICK, every item any run left in a merged state is closed out, and anything close-out could not
safely finish is put to the owner as an explicit decision (interactive) or stops the run (non-interactive). When
everything is already closed out, this is a no-op: no question, no mutation, no extra Progress noise beyond one
"nothing to close out" line.

#### Scope (recommendation — the brief decides the details)
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

#### Acceptance criteria
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

#### Out of scope
- Auto-merging the feature PR or the trail PR (owner merges both; the trail PR still need not block the next item).
- Closing out work that was never run through `/automate` (that stays `reconcile-status --apply`, human-run).

#### Risks
- **Cross-run mutation.** Closing out run A from run B's session touches another run's file and lock — use run A's own
  lock owner and helpers; never pick or modify A's Queue beyond its in-flight item's check-off.
- **False "leftover" on an idempotent re-run.** The classifier must treat "already removed/stamped/checked" skips as
  complete, or every resume would ask (the AC2 no-op leg pins this).
- **Question fatigue.** Batch leftovers into one `AskUserQuestion` call (≤4 per call).


### Part B — 28 — A run whose Queue is fully done stops showing up as "incomplete" to every later run

#### Problem
`skills/automate-loop/SKILL.md` §"Run status" says: after a close-out the run is `paused` + `awaiting_go`, and `done`
is set only when the Queue is fully resolved by a `/automate --resume` that terminates with its `--reason done`
trail; `closeout` never writes `done`, "even when it checked off the last item". That works sequentially, where the
owner resumes. **A lane run is never resumed after its closeout**, so every finished single-item lane run stays
`paused / awaiting_go` with an empty Queue forever.

Seen on 2026-10-04: S1 v2's two lane runs (`automate-2026-10-04-072706`, `-072926`) were carried to `loomwright-meta`
after both PRs merged. The next two lanes (wave w1, items 08 and 10) each opened with a RESUME question listing
them as "incomplete runs" (plus the genuinely open `automate-2026-09-30-054439`). At 5–10 lanes per wave, every lane
of every later wave would ask about every earlier lane's finished run.

#### Goal
A paused run with no unchecked Queue item and nothing in flight is finished by the engine itself, through the same
`done` termination and trail the Queue-resolved path already uses, so RESUME lists only runs with work left.

#### Scope
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

#### Acceptance criteria
- After S1 v2's two runs are finalized, a new lane's RESUME lists only `automate-2026-09-30-054439`.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `test-automate-helpers.sh` / `test-automate-trail.sh` closeout groups pass unedited.
3. Running system: run RESUME against a copy of today's run files; paste the finalized lines and the shortened list.
4. A failure this must catch: let `closeout` write `done` ⇒ the invariant test fails.
5. Rollback: `git revert`.

#### Evidence
Wave w1 lanes' first questions (2026-10-04, this session); S1 run record.


### Part C — 29 — The run file's `## Current` block is set by a helper at PICK, and a stale one is caught

#### Problem
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

#### Goal
`## Current` can only move through a helper the engine must call, and any write that implies an item is in flight
while `## Current` says otherwise is refused or flagged loudly.

#### Scope
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

#### Acceptance criteria
- Replaying w1-10's run-file history through the new helpers refuses at the first "picked" line with Current null.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: `test-automate-helpers.sh` / `test-automate-trail.sh` pass with no existing assertion edited.
3. Running system: one real sequential `/automate` item; paste its `## Current` after PICK, after RUN, at park.
4. A failure this must catch: skip `current-set` at PICK ⇒ the guard fires on the next progress line.
5. Rollback: `git revert`.

#### Evidence
Wave w1 lane w1-10, run file `automate-2026-10-04-103627.md` (archived at teardown) and its session log.


## Depends on
none

## Touches
loomwright/commands/automate.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/test-session-resume.sh
loomwright/skills/automate-loop/SKILL.md
changelog.d/automate-followups-32-run-file-lifecycle.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-05T17:56:09Z
- **Brief:** .supervisor/jobs/done/2026-10-05-run-file-lifecycle.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/395
