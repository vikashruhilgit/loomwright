# 06 — Wave close: one release bump per wave + split closeout (no extra PR, no merge train)

## Status: pending (S1 Q4 written 2026-10-04; still depends on 01 and 05)

## Depends on
01
05

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/test-automate-trail.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/commands/automate.md
loomwright/docs/RESULT_SCHEMAS.md

## Problem
After item 05 a wave ends with N READY PRs parked `ready_for_release`. Three things are still unsolved:
- **The version.** Lanes carry changelog fragments only (decision P7); something must fold them and bump once.
- **Closeout.** It was written for one checkout (brief repair, worktree cleanup, sync `main`, branch removal,
  stamp, check-off, trail). In N lanes it would never touch the primary or the parent queue and would leave the
  lane clones behind.
- **What NOT to build.** An earlier draft had a merge train that synced, bumped, re-drained and gated each lane,
  waiting for an owner approval. That premise is false here: the last 25 merged PRs show `REVIEW_REQUIRED` with
  zero reviews — the owner merges by admin bypass, and an author cannot approve their own PR. A bypass merge also
  does not need the branch to be up to date, so file-disjoint lane PRs need no train at all.

## Goal
A wave closes with at most ONE extra commit (the release bump on the release lane), the owner merges the PRs by
hand as today, and each merge is followed by a closeout that opens no PR and leaves no lane behind. No new merge
path, no new drain category, no push onto a PR that is waiting for a merge.

## Scope
1. **Wave close is stepwise and resumable** — each `/automate --resume` performs the next step and stops; nothing
   waits inside a session. Every step names its executor.
2. **Step A — release the ordinary lanes (bash, coordinator).** Every `ready_for_release` lane EXCEPT the last in
   planner order becomes `awaiting_merge`: park state written in the lane's run file by the lane's own resumed
   session (the coordinator does not write into a lane — it launches `lane-launch --resume` for that), merge
   watcher armed, notify "ready to merge". These PRs carry a fragment and no version-file change.
3. **Step B — the release lane (headless lane session).** The last lane in planner order stays
   `ready_for_release` until every sibling is merged, skipped, abandoned or parked `escalated` (a parked sibling is
   excluded, not waited for). Then, on the owner's `--resume`, in the lane:
   a. merge `origin/main` into the PR branch (conflict ⇒ park the lane `escalated`; the wave's fragments stay on
      `main` for the next bump);
   b. run the project's **release command** (below) — it folds every fragment now on the branch and bumps once;
   c. push; wait for required checks;
   d. park `awaiting_merge`, arm the watcher, notify.
   No extra owned drain is run for this commit: the push happens BEFORE the lane is ever `awaiting_merge`, the
   diff is a merge plus the three version files, CI and the static CI lens run on it, and the "one owned drain per
   pass" invariant stays intact. If the release command is unavailable, skip b and say so in `## Progress`.
4. **Release command = tracked project config, behind the human-stamp valve.** The shipped plugin must not call
   this repo's `scripts/bump-version.sh`. The command is read from tracked project config (same store and same
   provenance rule `rules-check.sh` applies to a rule's `check` command: executed unattended only when
   human-stamped; unstamped / absent ⇒ not run, recorded, never a failure). This repo's value is
   `bash scripts/bump-version.sh`. Read `rules-check.sh` and `skills/rules/SKILL.md` §8 before designing — do not
   invent a second valve.
5. **A wave of one item** never enters this code: the item's own PR bumps as its last commit (item 01) and parks
   `awaiting_merge` as today.
6. **Lane closeout** (inside the lane, evidence-gated on `reconcile-item` = `merged`, idempotent, fail-SAFE; run
   by the lane's merge watcher or the lane's resume, as today): brief repair → stamp the requirement → check off
   the lane run file → write `## Status: done` to it → `meta-sync.sh push --paths-from <evidence-gated list>`.
   No trail PR; no "sync main" (a lane is discarded, not reused). A failed push sets item 03's failure marker.
7. **Fleet closeout** (coordinator, primary, same evidence gate, on `--resume`): `meta-sync.sh pull` → check off
   the parent `## Queue` + append `## Progress` (one atomic write through `runfile-write` /
   `queue-checkoff`) → `git pull --ff-only` on the primary (it never left `main`) → `lane-remove` (refuses on the
   failure marker). Dismissed-finding drafts arrive via the pull and are asked at the parent's next interactive
   PICK through item 05's parent-aware `dismissed-pending`.
   **Amended 2026-10-03 (owner, from S1): teardown is part of the closeout, not left to the operator.**
   - `lane-remove` runs with item 05's full refusal set: a live watcher or `claude -p`, `awaiting_input`, unpushed
     metadata, the failure marker. A lane closeout runs inside the lane's own merge watcher, so the fleet
     closeout waits for that watcher to EXIT (a resumable step, re-checked on the next `--resume`, never an
     in-session wait) before it removes the lane.
   - When the last lane of the run is removed, remove the then-empty `<primary>-lanes/<run_id>/` directory. A
     non-empty one is refused and its contents are listed.
   - Then print `lane-status --leaks` (item 05 Validation 5) and append its one-line summary to `## Progress`.
     A non-empty leak report is a loud report, not a block: it names each leftover worktree, lane directory or
     live process and the command that clears it.
   - Finally run the plugin-wide sweep in dry-run mode (`automate-followups/22`) and report what it WOULD
     remove. The fleet closeout never removes anything outside this run's lanes.
8. **PR closed unmerged** ⇒ lane is `gone`: no stamp, lane directory kept, human decides.
9. **Next wave** becomes eligible after fleet closeout of the items it depends on and starts only on the owner's
   explicit go (P6). When the last lane of the last wave is closed out, release the primary's
   `automate-lanes:<run_id>` lock.
10. **Learning line.** Unchanged: `learning-emit` runs once at end-of-DRAIN in each lane. Step B runs no drain,
    so no second line can be emitted — pin with a test that a release lane has exactly one line for its PR.
11. **Tests:** two-lane fixture — ordinary lane goes `awaiting_merge` at step A with no version-file change in its
    diff; release lane waits; after the sibling is merged the release lane's diff after step B is exactly the
    merge + the bump, with BOTH fragments folded; a sibling parked `escalated` does not block step B; a merge
    conflict at B.a parks only that lane; unstamped release command ⇒ step b skipped and recorded; closeout opens
    no PR, pushes only evidence-gated paths, removes the lane only after its watcher exited, removes the empty
    `<run_id>` directory last and appends the leak summary; unmerged-closed PR ⇒ no stamp, lane kept; the
    single-item path never enters wave-close code. **Mutation controls:** letting step B run while a sibling is
    still `awaiting_merge` must fail a test; pushing in step B after the lane is already `awaiting_merge` must
    fail a test.

## Non-goals
Any automatic merge, `gate-eval` call, approval wait, or merge train for parallel runs (decision P1). GitHub
native auto-merge, merge queue, a CI job that merges (P5). Relaxing branch protection or the ruleset. Auto-starting
the next wave.

## Acceptance criteria
- A two-item wave merges as two PRs total — no trail PR, no release PR — with ONE version bump folding both
  fragments, landed by the release lane.
- `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same five surfaces
  listed in CLAUDE.md §"Failure-Mode Invariants"; `git diff origin/main -- loomwright/scripts/automate-helpers.sh`
  shows no change inside `gate_eval`.
- After the wave: no lane directory and no `<run_id>` parent directory, no live `claude -p` or merge watcher from
  the wave, `lane-status --leaks` empty, the primary on fresh `main`, the parent queue checked off, stamps /
  briefs / lane run files (each `## Status: done`) on `loomwright-meta`.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path:** `test-automate-trail.sh`'s closeout groups and `test-automate-helpers.sh`'s gate groups
   pass with no edit to existing assertions; then ONE real single-item `/automate` on this repo behaves as before
   (bumped by its own last commit, parked `awaiting_merge`, closeout via push).
3. **Invariant checks, pasted:** the two greps in Acceptance criteria; `git grep -nE 'gh pr merge|gate-eval'
   loomwright/scripts/automate-lanes.sh` shows no executable use.
4. **Running system:** a real two-item wave on this repo, owner merging by hand. Paste: the diff stat of the
   ordinary lane's PR (no version file), the release lane's final commit (three version files, both fragments
   gone), `gh pr list --state merged` for the wave (exactly two), `git log --oneline -3 origin/main`,
   `git ls-tree -r --name-only origin/loomwright-meta | grep <run_id>`, and the empty lane directory listing.
5. **A failure this must catch:** the two mutation controls in Scope 11, shown failing.
6. **Rollback:** `git revert` returns parallel runs to item 05's behaviour (every lane `awaiting_merge`, no bump).
   A wave mid-close is finished by hand: merge the remaining PRs, run `scripts/bump-version.sh` in a small PR,
   push metadata from each lane, remove the lanes.

## Spike findings
Filled 2026-10-04 from S1 Q4. The owner merged #372 (item 18) at 10:17:51Z by hand; the sibling #374 (item 19)
went `BEHIND` but stayed `MERGEABLE` and merged by hand two minutes later with **no branch update**. The two PRs
were a deliberately overlapping pair (separate `plan-waves` waves) sharing one file, `RESULT_SCHEMAS.md`, in
different hunks. **This item's premise holds: no sync is needed for ordinary lanes; step A stands as written.**
Lane closeout ran inside each lane on the watcher's `merged` event within ~12 s (sync `main`, remove the branch,
check off, reconcile `## Current`, watcher exits). One gap: v2-b's closeout metadata push FAILED on the push scrub
(an absolute home path in its brief), so the fleet closeout must surface a lane's `meta-push-failed` marker and
`meta-sync-followups/04` must land before 06 runs. Real `CONFLICTING` siblings are item 13's job.

## Verified premises (re-check before starting)
- `gh pr list --state merged --limit 25 --json reviewDecision,reviews` on 2026-10-01: 25 × `REVIEW_REQUIRED`,
  zero reviews.
- `gh api repos/vikashruhilgit/loomwright/branches/main/protection`: `strict: true`, required check `ci`, 1
  required review. `gh api repos/vikashruhilgit/loomwright/rulesets`: ruleset 12578391 "PRs & conventional
  commits", active, branch target. Its rule details (stale-review dismissal, last-push approval, thread
  resolution) are from the red-team report — read `gh api …/rulesets/12578391` before relying on them.
- UNVERIFIED: that an admin-bypass merge succeeds on a branch that is behind `main` under `strict: true` — S1
  question 4 is the check, and this item's design depends on it.
- `automate-merge-watch.sh` only detects a merge and runs closeout; its header says it never merges anything.
- Closeout's step order and lock (`automate-loop/SKILL.md` §6 "Post-merge close-out").

## Status note
Parked until S1 is run and item 05 has merged. Do not start from this file as written.
