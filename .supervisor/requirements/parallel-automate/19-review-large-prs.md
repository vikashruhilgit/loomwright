# 19 — The CI reviewer reviews large PRs (wave PRs, hotspot splits) instead of ending with no comment

## Status: done (2026-10-06, PR #398 merged `7bd43ce`, done directly — not a lane; first live check: the next non-workflow PR)

## Depends on
none

## Touches
.github/workflows/claude-code-review.yml
changelog.d/parallel-automate-19-review-large-prs.md

## Problem
Filed 2026-10-06 (owner "ok" to the operator's recommendation, S3 wave 1 closeout). The wave-1 PR #397 (34 files,
~3,100 lines: four lane PRs merged on `wave/s3w1` + the release bump) got NO review, twice:
- run 37407425806: 45 turns, $1.86, `permission_denials_count` 8, result `success`, no comment posted, so the
  workflow's "Assert a review was actually posted" step failed the check. The re-run (same run id, 2026-10-06) failed
  the same way. The action hides its full output, so which commands were denied is not known.
- `.github/workflows/claude-code-review.yml` passes `--allowed-tools` with a fixed list (`Read, Grep, Glob, Task,
  TodoWrite` + named `git`/`gh`/text `Bash(...)` forms). `--allowed-tools` REPLACES the action's defaults, so
  anything else (e.g. `sed`, `awk`, `find`, `xargs`, `nl`) is denied and each denial burns a turn — the assert's own
  hint names this as the most common cause.
Coming next: `parallel-automate/11` (wave 2) moves several thousand lines (`automate-helpers.sh`, `RESULT_SCHEMAS.md`,
the skills index) and every later wave PR is a multi-lane diff. The per-lane reviews were all green in wave 1, but a
wave PR or a hotspot split with no review is a gap the owner merges blind.

## Goal
A large PR gets a posted review (findings or an explicit "reviewed N of M files, these not") within its budget, and
a move-only change can be shown to be move-only without the reviewer reading every moved line.

## Scope
1. **Find the denials first.** Reproduce locally as the workflow comment says (`claude --debug --allowed-tools
   "<the list>"` on #397's diff, or a scratch copy of it) and record which commands were denied and how many turns
   were left when the reviewer stopped. Change the list only for what is actually denied.
2. **A budget that fits the diff.** State the turn budget the reviewer gets and make the prompt's existing
   "if low on turns, post what you have" path fire before the budget runs out (the result was `success` with nothing
   posted). For a diff over a size threshold, review per changed file group and post one comment that lists any
   file not reviewed.
3. **Move-only evidence for splits.** For a PR whose description says "move-only", the reviewer (or a deterministic
   step before it) checks that removed and added lines match as multisets per moved block, and reviews only the
   residue. Decide in the brief whether this is a workflow step or a script under `scripts/`.
4. **Self-test caveat:** a PR that edits a workflow file is skipped by `claude-code-action` (green, no comment) —
   this PR cannot review itself. Validate on the next non-workflow PR after it merges (CLAUDE.md global note).

## Non-goals
Changing who merges, the required checks, or the per-lane drain's review.

## Acceptance criteria
- Re-running the reviewer on #397's diff (scratch PR or local reproduction) posts a review, with a "not reviewed"
  list if anything was skipped.
- The first wave PR after this merges gets a posted review.

## Validation (must pass before merge)
1. The local reproduction's denial list, before and after.
2. Running system: one large non-workflow PR after the merge (a wave PR or pa/11's) shows a posted review.
3. Rollback: `git revert`.

## Evidence
#397 checks and run 37407425806 (first run and re-run); S3 record §"Wave 1 result".
