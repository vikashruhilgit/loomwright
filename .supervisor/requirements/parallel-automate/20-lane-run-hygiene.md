# 20 — Lane-run hygiene: an unrun running-system check blocks READY, run files carry no home paths, ci-local fits a lane's command limit

## Status: pending

> **Origin (2026-10-07).** Owner decision relayed by S3 session 2216aefd, from S3 waves 1 and 2 (operator-run
> `S3-stabilization-wave-spike.md` §"Wave 1 result", §"Wave 2 result"). Three parts in one item (owner prefers
> fewer, larger items). Part A is an OWNER POLICY, not a suggestion.

## Problem
- **A. An unrun "Running system" check passes as READY.** Wave 2's #402 (pa/16) listed its own three-clone
  `ci-local` check under "Not verified". The lane parked READY. The operator ran it and it FAILED: load1 63.6 (fixed
  on the PR in `cd5f400`). In wave 1 every PR's "Not verified" list hid something the operator then found. Nothing in
  the engine stops a lane from parking READY with a must-pass Validation step not run.
- **B. Lane metadata pushes fail the home-path scrub on the engine's own lines.** `reconcile-status` writes absolute
  home paths into run files, so a lane's metadata push fails the `home_path` scrub: s3-c and s3-d in wave 1, s3-f in
  wave 2 (its records were carried to `loomwright-meta` by hand, `f7709f0`). The scrub is right; the writer is wrong.
- **C. A lane's full `ci-local` exceeds its single-command limit.** A full `ci-local` takes ~620 s in a lane; the
  lane's Bash tool caps a foreground command at 600 s. s3-e was cut off and re-ran it (wave 2, gap 4).

## Goal
A lane cannot park READY with a must-pass running-system check it did not run; the engine's own run-file lines
pass the scrub; and the pre-push suite can be run by a lane without hitting the command limit.

## Scope
### Part A — an unrun must-pass running-system step blocks READY (owner policy)
1. Before the READY / `awaiting_merge` park, the engine compares the item's `## Validation (must pass before merge)`
   "Running system" step(s) with the PR body's evidence. A step listed as "Not verified" / not run, or with no pasted
   output, BLOCKS READY: the item parks `escalated` with a named cause (recommended: `automate-followups/31`'s
   `escalation_cause`, new value `validation_unrun`), naming the step.
2. It stays parked until the step is run (evidence pasted, re-checked) or the owner explicitly waives it; the waiver
   is recorded in `## Progress` with the step and the owner's words. No silent default.
3. Can't-ask branch (CLAUDE.md §"Failure-Mode Invariants": every question gate has a named can't-ask branch):
   non-interactive ⇒ stays parked `escalated`, never waived.
4. Relation to `parallel-automate/05` Scope 15a: that report shows NOT-RUN advisorily; this part makes the same
   condition blocking for the park itself. Keep one reader for both.
5. **Tests:** a fixture PR body listing a running-system step under "Not verified" ⇒ `escalated`
   `validation_unrun`; pasted evidence ⇒ READY as today; a recorded waiver ⇒ READY with the waiver line; an item with
   no running-system step ⇒ unchanged. **Mutation control:** skipping the check must fail the first leg.

### Part B — `reconcile-status` writes no absolute home paths
1. Trace which `reconcile-status` output reaches a run file with an absolute path (the `plan` / `stamped` rows and
   their justification, appended through `progress-append` per `automate-loop/SKILL.md` RESUME step 7) and fix the
   WRITER: repo-relative paths, or `~/` where a home path is unavoidable. Do not weaken the scrub.
2. **Tests:** a fixture run under a home-like root ⇒ no `/Users/` or `/home/` path in any appended line; the
   existing scrub test still refuses a planted absolute path.

### Part C — `ci-local` fits a lane's 600 s command limit
1. Either `ci-local` supports a detached run plus a poll (e.g. a background mode that writes the verdict where
   `--last` reads it), or the engine / project guidance says to run it backgrounded and poll its log. Pick one; the
   brief records why. The pass cache, slot and machine gate behave as today.
2. Update the pre-push guidance that names `bash scripts/ci-local.sh` (`AGENT_GUIDELINES.md` §"Pre-push: one
   command", `CLAUDE.md` §"Pre-push test run?") in the same change.
3. **Tests:** a stubbed slow suite completes through the new path with the verdict readable afterwards; a foreground
   run is unchanged.

## Non-goals
Running any validation step automatically. Changing the home-path scrub. Making `ci-local` faster.

## Acceptance criteria
- Replaying #402's park (its PR body's "Not verified" three-clone step) gives `escalated` `validation_unrun`, not
  READY.
- A lane metadata push after `reconcile-status` passes the scrub with no hand edit.
- A lane runs the full `ci-local` to a verdict without a timeout cut-off.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: a READY drain whose PR body pastes every running-system step parks `awaiting_merge` as before; a
   foreground `ci-local` behaves as before.
3. Running system: one real lane run (or sequential `/automate` item) that parks on an unrun step, then READY after
   the step is run; paste both `## Current`s. One real lane metadata push after `reconcile-status`; paste its line.
4. A failure this must catch: the Part A mutation control.
5. Rollback: `git revert`.

## Evidence
S3 record §"Wave 2 result" (pa/16 failed its own running-system Validation; records carried by hand: home paths;
new gap 4) and §"Wave 1 result" / §"Lessons from wave 1" (merge checks found real gaps the PR bodies left open; s3-c,
s3-d meta-push scrub failures).

## Depends on
../automate-followups/31-transient-escalation-recheck.md

## Touches
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-helpers.d/runfile.sh
loomwright/scripts/automate-helpers.d/reconcile-status.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/review-heal/SKILL.md
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
scripts/ci-local.sh
scripts/test-ci-local.sh
AGENT_GUIDELINES.md
CLAUDE.md
changelog.d/parallel-automate-20-lane-run-hygiene.md
