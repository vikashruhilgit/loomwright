# 06 — Merge train + split closeout (serial merge of a wave, no extra PR)

## Status: parked (waits on S1 and item 05 — write the spike's answer to question 4 under "Spike findings", then set `## Status: pending`)

## Depends on
01, 05

## Touches
`loomwright/scripts/automate-lanes.sh`, `loomwright/scripts/automate-trail.sh` (closeout),
`loomwright/scripts/automate-merge-watch.sh`, `loomwright/scripts/test-automate-lanes.sh`,
`loomwright/scripts/test-automate-trail.sh`, `loomwright/skills/automate-loop/SKILL.md`,
`loomwright/commands/automate.md`

## Problem
After item 05 a wave ends with N READY PRs, but:
- `main` is protected with `strict: true` — once the first PR merges, the others are behind and must be updated;
  updating moves the head SHA, and `gate-eval` parks on `head_sha_moved` without a fresh READY.
- each PR still needs its version bump, which must happen after the sync so no two PRs claim one number;
- closeout was written for one checkout: brief repair, worktree cleanup, sync `main`, branch removal, stamp,
  check-off, trail. Run as-is in N lanes it would never touch the primary checkout or the parent queue and would
  leave the lane clones behind.

## Goal
A wave's PRs merge one at a time, in planner order, through the existing gate; each merge is followed by a closeout
that needs no additional PR and leaves no lane behind.

## Scope
1. **Train order** = the wave order `plan-waves` printed. One lane at a time; the train holds the primary's run
   lock for its whole length so two trains can never interleave.
2. **Per lane, inside that lane's clone:**
   a. merge `origin/main` into the PR branch (a conflict here ⇒ park that lane `escalated`, continue the train
      with the next lane);
   b. `scripts/bump-version.sh` (item 01) — the only place the version files change;
   c. push; wait for required checks on the new head;
   d. ONE owned drain pass (`/review-pr --until-mergeable --no-auto-postmortem`) to obtain a READY verdict for the
      new head — the same single-drain contract as §7, counted in the lane's `## Current`;
   e. `gate-eval`, unchanged, all seven conditions, executed in the lane. The train never merges by any other path.
3. **Approval wait (decision P1).** In this repo `gate-eval` returns `PARK: review_decision_blocking` until the
   owner approves. In safe mode the train stops at step (d) and parks the lane `awaiting_merge` with the merge
   watcher armed, exactly as today. With `--auto-merge`, the train re-runs `gate-eval` when the watcher sees the
   review decision change, and merges only on `MERGE`. It never bypasses the review requirement and never uses
   `--admin`.
4. **`--auto-merge --parallel N>1` is now allowed** (lifts item 05's refusal) — only through this train.
5. **Lane closeout** (inside the lane, evidence-gated on `reconcile-item` = `merged`, idempotent, fail-SAFE):
   brief repair → stamp the requirement → check off the lane's own run file → `meta-sync.sh push`. No trail PR,
   no "sync main" (a lane is discarded, not reused).
6. **Fleet closeout** (coordinator, primary checkout, same evidence gate): `meta-sync.sh pull` → check off the
   parent `## Queue` + append `## Progress` (one atomic write) → `git pull --ff-only` on the primary (it never left
   `main`) → `lane-remove`. Dismissed-finding drafts arrive via the pull and are asked at the parent's next
   interactive PICK (Follow-up / Drop), as today.
7. **Next wave** becomes eligible after fleet closeout of the items it depends on, and starts only on the owner's
   explicit go (decision P6).
8. **Learning line.** The engine-native `learning-emit` runs at end-of-DRAIN in the lane as today; the train's
   extra drain pass in 2d must not emit a second line for the same PR — extend the existing line or suppress, and
   pin the choice in a test.
9. **Tests:** two-lane fixture — after lane A merges, lane B is synced, bumped to the NEXT version, re-drained and
   gated; a sync conflict parks only that lane; closeout opens no PR and removes the lane; the positive-form
   `gh pr merge --squash` grep still resolves to the same five surfaces; `--parallel 1` closeout path unchanged.
   **Mutation control:** skipping step 2d must make `gate-eval` park `head_sha_moved` in a test.

## Non-goals
GitHub native auto-merge, merge queue, or a CI job that merges (decision P5). Relaxing branch protection. Merging
lanes out of planner order. Auto-starting the next wave.

## Acceptance criteria
- A three-item wave merges as three PRs total — no trail PR, no manual renumbering — with versions assigned in
  train order.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same five surfaces
  listed in CLAUDE.md §"Failure-Mode Invariants".
- After the wave: no lane directory remains, the primary is on fresh `main`, the parent queue is checked off, and
  the stamps / briefs / run files are on `loomwright-meta`.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; both `<passed>/<total>` lines in the PR body.
2. **Unchanged path:** the sequential closeout and gate are untouched for `--parallel 1` —
   `test-automate-trail.sh`'s closeout groups and `test-automate-helpers.sh`'s gate groups pass with no edit to
   their existing assertions; `git diff origin/main -- loomwright/scripts/automate-helpers.sh` shows NO change
   inside `gate_eval` (the train calls it, it does not modify it).
3. **Merge-executor invariant, pasted:** `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`
   resolves to the same five surfaces; `git grep -nE 'gh pr merge|--admin|--auto' loomwright/scripts/automate-lanes.sh`
   returns nothing.
4. **Gate cannot be skipped:** a test (and one manual run, output pasted) where the train reaches a lane whose
   review is not approved shows `PARK: review_decision_blocking` and NO merge; another where step 2d is skipped
   shows `PARK: head_sha_moved`.
5. **Running system:** a real two-item wave on this repo in safe mode, owner approving. Paste: the two version
   numbers in train order, `gh pr list --state merged` showing exactly two PRs for the wave and no metadata PR,
   `git log --oneline -3 origin/main`, `git ls-tree -r --name-only origin/loomwright-meta | grep <run_id>`, and the
   empty `ls <primary>-lanes/<run_id>/`.
6. **No evidence, no stamp:** closing one lane's PR unmerged leaves its requirement unstamped on the metadata
   branch and its lane directory in place (`gone`, needs a human) — pasted.
7. **Rollback:** `git revert` of the PR returns parallel runs to item 05's safe-mode-only behaviour. A train in
   flight is stopped by releasing the primary's run lock after the current lane's step completes; remaining lanes
   stay `awaiting_merge` and can be merged by hand.

## Spike findings
_(fill in from S1 question 4 before un-parking: the state of a sibling PR after the first merge, and `gate-eval`'s
answer before and after the branch update)_

## Verified premises (re-check before starting)
- `gh api repos/vikashruhilgit/loomwright/branches/main/protection` on 2026-10-01: `strict: true`, required check
  `ci`, 1 required approving review. `gh api repos/vikashruhilgit/loomwright`: `allow_auto_merge: false`,
  `allow_update_branch: false`, owner type `User`.
- `gate-eval`'s park reasons include `head_sha_moved`, `checks_not_green`, `review_decision_blocking`
  (`automate-helpers.sh`); the skill's §10 lists the seven conditions and the gate-owned `ctx.json` keys.
- Closeout's step order and its lock (`automate-loop/SKILL.md` §6 "Post-merge close-out"); the merge watcher is
  armed only at the safe-mode `awaiting_merge` park.
- Merge queue being unavailable for user-owned repositories was NOT verified against current GitHub docs; it does
  not matter for this design (P5) — do not cite it as fact.

## Status note
Parked until S1 is run and item 05 has merged. Do not start from this file as written.
