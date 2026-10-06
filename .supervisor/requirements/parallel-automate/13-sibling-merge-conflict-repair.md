# 13 — After each merge, keep the other parked PRs mergeable (conflict repair, not a merge train)

## Status: parked (merged 2026-10-06 into `06-wave-close-and-closeout.md` as Part S, rewritten for wave-branch integration — do not run this file; work the merged item)

## Depends on
05

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-merge-watch.sh
loomwright/scripts/test-automate-merge-watch.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/parallel-automate-13-sibling-merge-conflict-repair.md

## Problem
Owner goal: 5–10 lanes at once, so 5–10 PRs parked `awaiting_merge` at the same time. Decisions P1/P5 and item 06
already settle that **no merge train is built**: the owner merges by admin bypass, a bypass merge does not need an
up-to-date branch, and file-disjoint PRs need nothing. (A train was proposed in this session's first draft and
withdrawn for that reason.) What is NOT covered:
- **Textual conflicts.** Wave items are file-disjoint by `Touches`, but a `Touches` list can be incomplete, and
  shared files still exist until item 11 lands. After one merge, a sibling can turn `CONFLICTING`, and a bypass
  merge cannot merge a conflicting PR. Nothing today notices this until the owner tries.
- **A red `main`.** Several bypass merges in a row, each green on its own stale base, can leave `main` red. Nothing
  stops the next merge or tells the owner which merge broke it.
- **The invariant that makes repair delicate:** no push onto a PR that is `awaiting_merge` with a watcher armed
  (overview invariants; skill §6). Repair must first take the PR out of that state.

## Goal
After every merge in a wave, the coordinator checks the other parked PRs and `main`. A PR that became conflicting
is repaired through a proper handshake (watcher stopped, lane resumed, conflict merged or escalated, CI, re-parked);
a red `main` pauses the wave with the suspect merge named. No new merge path, no push onto an armed PR.

## Scope
1. **Post-merge sweep** (coordinator, on the merge watcher's `merged` event or the owner's `--resume`): for each
   other lane parked `awaiting_merge`, read GitHub's `mergeable` / `mergeStateStatus`; for `main`, read the latest
   `ci` run on the merge commit.
2. **`CONFLICTING` ⇒ repair handshake:**
   a. stop that lane's merge watcher and record `watch_stopped: sibling_conflict` (the PR is no longer
      `awaiting_merge`; its park state becomes `repairing`);
   b. resume the lane (`lane-launch --resume`) with a single task: merge `origin/main` into the branch;
   c. a conflict confined to the conflict markers and resolved without changing either side's intent ⇒ commit,
      `ci-local` (item 08 slot), push, wait for required checks, re-park `awaiting_merge`, re-arm the watcher,
      notify; anything larger (a semantic clash, a test now failing) ⇒ park `escalated` with the diff, never guess;
   d. the "one owned drain per pass" invariant holds: a pure merge-from-main commit gets CI and the static CI lens,
      not a new drain (item 06 Step B's precedent); a resolution that edits code beyond the markers is escalated.
3. **`BEHIND` but clean ⇒ nothing** (bypass merges do not need it; P1).
4. **`main` red after a merge ⇒ wave pause:** write `wave_paused: main_red after <PR>` to the coordinator run file,
   notify, and mark every parked PR "hold — main is red" in `lane-status` and the pane until `main` is green again.
   No automatic revert.
5. **Tests:** a fixture where merging lane 1 makes lane 2 conflicting ⇒ watcher stopped, lane resumed, clean
   resolution re-parks with a re-armed watcher; a semantic conflict ⇒ `escalated`; `BEHIND`-only ⇒ untouched; a red
   `main` ⇒ wave paused; and a guard test that no push ever happens while a watcher marker for that PR is live.

## Non-goals
- No merge train, no merge queue, no auto-merge, no CI job with merge authority (P1, P5).
- No automatic revert of a merge that turned `main` red.

## Acceptance criteria
- In S2, every PR that turned conflicting after a sibling merge is either re-parked green or escalated with its
  diff, and no push was made onto a PR with a live watcher marker.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. **Unchanged path:** a wave whose PRs stay mergeable produces no repair activity (item 06's tests unchanged).
3. **Running system:** two lanes with a deliberate one-line overlap; merge one; paste the sweep, the handshake
   lines and the re-parked PR's checks.
4. **A failure this must catch:** skip step 2a (push while the watcher is armed) ⇒ the guard test fails.
5. **Rollback:** `git revert`; parked PRs keep working as in item 06.

## Spike findings
(S1 Q4: record #374's `mergeable` / `mergeStateStatus` and what its lane and watcher did after #372 merged.
Items 18 and 19 are in different waves by `plan-waves`, so they are the overlap case on purpose.)

## Verified premises (re-check before starting)
- `main` protection: 1 approving review, required check `ci`, `strict: true`; repo owner type `User`, so GitHub's
  merge queue is unavailable (`mergeQueue: null`), checked 2026-10-04. P5 rules it out anyway.
- Item 06 §Problem: "A bypass merge also does not need the branch to be up to date, so file-disjoint lane PRs need
  no train at all."

## Evidence
This session's scale-up analysis (2026-10-04) and S1 Q4 once recorded.
