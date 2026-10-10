# 38 — Merged lane and `--auto-merge` items are never stamped `done` once #446 lands

## Status: pending

## Depends on
37-done-stamp-before-merge.md

## Touches
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
changelog.d/automate-followups-38-closeout-for-lane-and-auto-merge.md

## Problem
automate-followups/37 (PR #446, wave-1 run `automate-2026-10-09-174540`, lane L1) removes Phase 4.5's
pre-merge `## Status: done` stamp, so `closeout` (evidence: the PR reads `MERGED`) becomes the only engine
writer of it. #446's own Phase 4.5 escalation (`max_iterations_reached`, comment on the PR 2026-10-10T03:47Z),
corroborated by claude-review, names two paths that never reach `closeout`:

1. **`--auto-merge`.** After `gate-eval` prints `MERGE`, §6 step 5 SYNC runs only `brief-repair` and
   `git pull`. Calling `closeout` there was rejected because `closeout` always runs `trail-pr` (step 6). In
   branch mode OFF, that opens a `chore/<run_id>-trail-<n>` PR, and the next PICK's `trail-gate` parks every
   unattended `--auto-merge` run on `trail_pr_open`.
2. **`--parallel` lanes.** Verified on the installed v15.126.0 in the primary (2026-10-10):
   - A lane's READY park arms no merge watcher (lane log: `no merge watcher armed in a lane`).
   - `lane-convert-ready` never calls `closeout`; `automate-lanes.sh` names `closeout` only in a comment.
   - `closeout-others` acts only on `resume-glob` output, and `resume-glob` in the primary skips lane run
     files. The three `automate-2026-10-09-174540-L{1,2,3}.md` files were present in the primary's
     `.supervisor/automate/` after `meta-entry`, yet `resume-glob` listed neither of them.

   Today the only done stamp a lane item gets is Phase 4.5's pre-merge one: it sits in the lane and rides
   the evidence-gated `trail-pr --reason wave-end` push once the PR reads `MERGED`
   (`excluded … — pr not merged` until then). §14 "Terminal park" says the stamp "rides" after a re-run of
   `lane-convert-ready`. After #446 no writer exists behind that sentence.

Either way, a merged item stays `pending` (or `brief-shipped`), `is_done` is false, and the next `--folder` /
`--backlog` / `plan-waves` run offers the merged work again. The manual fallback, `reconcile-status --apply`,
does not recover a requirement already marked `brief-shipped` (#446 documents this as an honest limit).

**Separate `closeout` bug found on the same PR (comment 2026-10-10T03:48Z).** `closeout` step 5 decides
"already stamped" with `grep -qF '<!-- loomwright:requirement-closeout -->' "$item"`, which matches the
sentinel anywhere, including quoted in prose. `automate-followups/37-done-stamp-before-merge.md` quotes it in
its `## Problem` section, so `closeout` prints `skipped — already stamped` for that item and never stamps it.
v15.126.0's Phase 4.5 step 2.5 hit the same false match: af/37 still reads `## Status: pending`.

## Goal
Every merged item is stamped `## Status: done` by `closeout`, whatever path merged it (sequential park,
`--auto-merge`, lane), and only after its PR reads `MERGED`. No new trail PR is opened on a path where one
would park the run.

## Scope
1. **A trail-less close-out.** `closeout <runfile> <item> <pr_url> [--session-id <sid>] --no-trail` runs
   steps 1–5 and 7 exactly as today (evidence gate first; refuse unless `reconcile-item` says `merged`) and
   skips step 6 (`trail-pr`), printing `trail-pr: skipped — --no-trail`. Without the flag, output and
   behaviour are byte-unchanged. `closeout-classify` treats that line as `complete`.
2. **`--auto-merge` SYNC calls it.** §6 step 5, after `gate-eval` prints `MERGE`: run
   `closeout … --no-trail --session-id <loop sid>` instead of the bare `brief-repair` (closeout's step 2 is
   `brief-repair`). The run's trail still ships at the existing triggers (run end / skip-abandon). In branch
   mode, state whether plain `closeout` (meta push, no PR, so no `trail-gate` park) is used instead; justify
   the choice in the PR.
3. **The lane path calls it.** `lane-convert-ready` on a lane whose run file already reads `awaiting_merge`
   (the documented "re-run after the owner merges") runs `closeout <lane run file> <item> <pr> --no-trail`
   inside the lane, under the launch lock, BEFORE its pushes. On a fresh `ready_for_release` conversion, or
   any PR not reading `MERGED`, it runs nothing new. Its existing `trail-pr --reason wave-end` push then
   carries the fresh stamp through the same evidence gate. Update §14 "Terminal park" so the sentence names
   this writer.
4. **Sentinel guard.** `closeout` step 5 (and any other `requirement-closeout` reader, listed in the PR via
   `grep -rn 'requirement-closeout' loomwright/scripts`) counts a past stamp only when the sentinel is a line
   on its own, immediately followed by a `## Status: done` / `done_with_escalation` heading line. A quoted
   or inline occurrence no longer counts.

## Acceptance criteria
- `closeout --no-trail` on a `MERGED` fixture writes the same requirement block, byte for byte, as plain
  `closeout`, and never calls `trail-pr` (spy). On an `OPEN` PR it writes nothing.
- An `--auto-merge` fixture item that merged at the gate ends with `## Status: done` and no trail PR, and the
  next PICK's `trail-gate` reads `clear`.
- A lane fixture: `lane-convert-ready` on `ready_for_release` writes no stamp. After the PR reads `MERGED`, a
  re-run stamps `## Status: done` in the lane and the wave-end push carries it (`excluded` line gone).
- A requirement that quotes `<!-- loomwright:requirement-closeout -->` inline in prose is stamped by
  `closeout`. A requirement carrying a real stamp block is still `skipped — already stamped` (idempotent).
- Plain `closeout`, `closeout-others`, the merge watcher and `finalize-empty` behave and print exactly as
  before (existing tests pass unchanged).

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` is green.
2. Each new test leg shown failing on the base (#446 merged) and passing on the branch.
3. **Running system.** After merging, re-run `lane-convert-ready` on one real wave-1 lane
   (`automate-2026-10-09-174540-L1`, whose requirement is af/37 itself). Paste its requirement's
   `## Status:` lines before (`pending`, the sentinel false match) and after (`done`, PR #446).
4. Rollback: `git revert`.

## Sequencing
#446 and this item ship in ONE release: merge #446, then this, then `scripts/bump-version.sh`. Merging #446
alone to `main` is safe as long as no release is cut between them, because lanes and runs use the installed
plugin (v15.126.0, which still stamps before merge) until a release is installed.

## Non-goals
Retroactive stamps for items merged before this lands (that is `reconcile-status --apply`, run by the
owner). `reconcile-status`'s `brief-shipped` limit. Changing the trail triggers.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-10T11:00:13Z
- **Brief:** .supervisor/jobs/done/2026-10-10-closeout-for-lane-and-auto-merge.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/455
