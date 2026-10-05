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
   armed at `escalated` parks under item 06's amendment, also polls the named check on the recorded head sha. When
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
../parallel-automate/06-wave-close-and-closeout.md

## Touches
loomwright/scripts/automate-merge-watch.sh
loomwright/scripts/wait-for-checks.sh
loomwright/scripts/test-wait-for-checks.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/skills/review-heal/SKILL.md
loomwright/skills/automate-loop/SKILL.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/automate-followups-31-transient-escalation-recheck.md
