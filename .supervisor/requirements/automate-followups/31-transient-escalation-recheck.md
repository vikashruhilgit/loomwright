# 31 — A temporary escalation is named as such and re-checked once it settles

## Status: pending

## Problem
A drain ends ESCALATED, and the item parks `escalated`, whenever a required check on the final commit is red or has
not settled within the bound. The drain does not distinguish a real failure from a temporary one. In wave S2
(2026-10-05) two of five lanes escalated for temporary reasons:
- **s2-c, PR #381:** the drain's confirming pass found `ci` red on `a7f9953`, a comment-only commit whose parent was
  green. The cause was `scripts/test-ci-local.sh` case (L): `ci-slot: no CI slot after 1s — giving up`, a 1-second
  timeout under runner load in a file the PR does not touch. `gh run rerun 37254186674 --failed` was green.
- **s2-d, PR #386:** `ci` was green on `1e35336`, but `claude-review` run 37259136927 was still in progress at the
  drain's 1200 s bound, so the drain failed closed. The review completed green with "no new findings" 2 min later.

Both PRs were then mergeable without any change, but the park recorded only `escalated`. The owner had to diagnose
each one, and neither lane had a merge watcher (`parallel-automate/06` Scope 7, 2026-10-05 amendment). The same wave
saw three other CI flakes on unrelated files (`test-ci-slot.sh` (P) `mutex.lnk: File exists`,
`test-session-resume.sh` (x-b'), and `sort: Broken pipe` on PR #385's first run).

## Goal
An escalation whose only cause is a required check that is still pending, or red in a file the PR does not touch, is
recorded with that cause, re-checked once the check settles, and reported to the owner as "now mergeable" or "still
failing". No merge path changes, and no new automatic rerun unless the owner decides it (question below).

## Scope
1. **Name the cause.** The drain's ESCALATED result and the park's `## Current` carry
   `escalation_cause: check_pending | check_red_unrelated | check_red | findings | other`, plus the check name, run
   id and head sha. `check_red_unrelated` means every failing test file named in the log is outside the PR's
   `files`. If that can't be read, the cause is `check_red` (fail closed).
2. **Re-check after it settles.** For `check_pending` and `check_red_unrelated` parks, the merge watcher, which is
   armed at `escalated` parks by this item's Part "Escalated parks arm the merge watcher", also polls the named check on the recorded head sha. When
   it settles, it appends one `## Progress` line and notifies once: `now mergeable: <check> green on <sha>` or
   `still failing: <check> <conclusion>`. It never merges, pushes, approves or reruns anything.
3. **Owner decision needed before design:** `harness-port/07` forbids the drain to rerun CI ("`gh run rerun` is
   suggested to the human, never executed"). Options: (a) keep that, and the rerun stays human (the owner gets the
   exact command); (b) allow at most ONE `gh run rerun <id> --failed` for `check_red_unrelated` only, recorded in
   `## Progress`. Do not build (b) without a recorded decision.
4. **Report.** `/automate` status and `lane-status` show the cause and the re-check verdict for an escalated
   item.
5. **Tests:** fixtures for each cause; a pending check that settles green produces exactly one `now mergeable`
   line; a red check in a file the PR touches is never `check_red_unrelated`; an unreadable log is `check_red`.
   **Mutation control:** classifying by test name without the `files` comparison must fail a test.

## Non-goals
Merging, approving, or changing the drain's fail-closed verdict. A check that never ran (billing, no runner) stays
`harness-port/07`'s `ci_untrusted`. Fixing the individual flaky tests (file those separately).

## Acceptance criteria
- Replaying s2-c's and s2-d's drains through the classifier gives `check_red_unrelated` and `check_pending`, and
  the watcher reports `now mergeable` for both without any push.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: a drain that ends READY and a drain escalated on findings behave as before, with no existing
   assertion edited.
3. Running system: one real escalated park on a pending `claude-review`; paste the park's `## Current` and the
   watcher's `now mergeable` line.
4. A failure this must catch: the mutation control in Scope 5.
5. Rollback: `git revert`.

## Evidence
S2 run record `parallel-automate/operator-run/S2-five-lane-spike.md`; lane archives
`~/Documents/work/AI/ai-agent-manager-lanes-v2/archive/s2-c/`, `archive/s2-d/`; s2-c's run file
`automate-2026-10-05-002749.md` and s2-d's `automate-2026-10-05-002748.md` on `loomwright-meta`.

## Depends on
none

## Touches
loomwright/scripts/automate-merge-watch.sh
loomwright/scripts/test-automate-trail.sh
loomwright/commands/automate.md
loomwright/scripts/wait-for-checks.sh
loomwright/scripts/test-wait-for-checks.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-helpers.d/runfile.sh
loomwright/scripts/fixtures/automate-helpers-help.golden
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/review-heal/SKILL.md
loomwright/skills/automate-loop/SKILL.md
loomwright/docs/result-schemas/review-heal-result.md
loomwright/docs/result-schemas/automate-run.md
changelog.d/automate-followups-31-transient-escalation-recheck.md

## Touches re-pointed 2026-10-07 (S3 operator f849e0cc, after pa/11's split — #408, v15.124.0)
- `RESULT_SCHEMAS.md` → `result-schemas/review-heal-result.md` (Scope 1: the drain's ESCALATED result carries
  `escalation_cause`) + `result-schemas/automate-run.md` (Scope 1: the park's `## Current` fields).
- `automate-helpers.sh` kept (its usage header documents `current-set`'s flags) + `automate-helpers.d/runfile.sh`
  (`current_set`, "the ONLY writer of `## Current`", enum-validated, gains the new fields) +
  `fixtures/automate-helpers-help.golden` (the dispatcher's `--help` golden; any usage-header change regenerates it,
  `test-automate-helpers-dispatch.sh` check 5).

## Amended 2026-10-07 — arm the merge watcher idempotently (owner, relayed by S3 session 2216aefd)
- **Evidence (S3 wave 2, lane s3-g, agnostic/04 #403):** s3-g armed TWO merge watchers for the same PR — one at its
  first park and one at the re-park after the owner-requested fix-now re-drain. Both exited cleanly at the merge and
  only one closeout ran, but nothing prevents a double closeout. (S3 record §"Wave 2 result", new gap 6.)
- **Change:** arming is idempotent. Before arming, the park tail reads the run's `<run_id>.merge-watch` marker; a
  live watcher for the same `pr_url` (checked the way `automate-merge-watch.sh` already checks liveness: `ps -ww`
  shows that script carrying the marker's `pr_url`, so a recycled pid is never trusted) is kept and no second one
  starts; a dead or different-PR marker is replaced as today. Applies to every park that arms (`awaiting_merge` and,
  with this item's Part above, `escalated`).
- **Test:** two parks of the same item in one run (park → fix-now re-drain → re-park) leave exactly one live watcher
  and produce exactly one closeout. **Mutation control:** removing the liveness check before arming must fail it.
- Placement note (operator): this is a watcher-arming change, not a transient-escalation one; it sits here because
  this item already owns the park-tail arming change (Part above) and `automate-merge-watch.sh`.

## Part — Escalated parks arm the merge watcher (moved 2026-10-06 from `parallel-automate/06` Scope 7, verbatim)
Owner decision 2026-10-06: this engine change does not need the coordinator, so it lives here and this item no
longer depends on `parallel-automate/06`. It also fixes the sequential case: a merged escalated item is
closed out without a manual `--resume`. Watcher tests live in `test-automate-trail.sh`; the park tail is
documented in `automate-loop/SKILL.md` §6/§9 and `commands/automate.md` ("an `awaiting_merge` park arms").

### Context (pa/06 Scope 7, 2026-10-05 amendment intro — also kept there)
   **Amended 2026-10-05 (owner, from S2): an `escalated` lane is closed out too.** Today the merge watcher is
   armed only at an `awaiting_merge` park ("an `escalated` park arms none", `automate-loop/SKILL.md` §6
   "Post-merge close-out"), and an escalated item is closed out only by `/automate --resume` RECONCILE. A lane
   exits after it parks and nothing resumes it, so after the owner merges an escalated lane's PR, Scope 6 never
   runs and Scope 7 waits on it forever.

### The change (verbatim)
   - **Arm the merge watcher at an `escalated` park as well** (the §9 park tail). This is an engine change and it
     also applies to sequential runs: a sequential `escalated` park gets a watcher too. It is safe because the
     watcher runs `closeout` only after it reads `MERGED`. A `CLOSED` PR gets one `gone` line, and past the 72 h
     cap `--resume` still closes the item out. It merges nothing.

### Its test (from pa/06 Scope 11, verbatim)
- an `escalated` park arms the watcher and a merge of its PR closes the lane out;

### Its validation note (from pa/06 Validation step 2, verbatim)
- Deliberate change, stated in the PR: a sequential `escalated` park now arms a merge watcher (Scope 7, 2026-10-05 amendment).

## Owner decisions 2026-10-07 (relayed from lane s3-i, S3 wave 3)
- **Scope 3: option (a), keep human-only.** The engine never reruns CI; the park and the watcher name the cause and
  print the exact `gh run rerun <id> --failed` for the owner. `harness-port/07`'s rule stands.
- **Scope 4: run file only.** The cause and re-check verdict go into the run file's `## Current` / `## Progress`
  (read by `/automate` status); `lane-status` (not built yet — `parallel-automate/05`) picks them up when it exists.
- **Correction to the 2026-10-07 watcher amendment above (same day, operator-verified):** the s3-g evidence was a
  process-count artifact. One watcher launch only (one tool call; one `merge-watch: started pid=86028` in its log).
  `automate-merge-watch.sh` already refuses a second watcher for the same PR (`already running`). So the change is the
  test, not new arming code: two parks of the same item leave one live watcher and one closeout, asserted on the
  `already running` line, the first pid still alive, and the marker pid unchanged.

<!-- loomwright:requirement-closeout -->
## Status: done_with_escalation
- **Completed:** 2026-10-07T11:13:04Z
- **Brief:** .supervisor/jobs/done/2026-10-07-automate-followups-31-transient-escalation-recheck.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/415
- **Heal:** max_iterations_reached — 2 remaining
