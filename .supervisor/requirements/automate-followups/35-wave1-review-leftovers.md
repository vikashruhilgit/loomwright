# 35 — Wave-1 review leftovers: the seven open notes from the #397 review

## Status: parked (merged 2026-10-07 into `automate-followups/36-s3-engine-fixes.md` as Part A — do not run this file; work the merged item)

> **Origin (2026-10-07).** Owner decision relayed by S3 session 2216aefd: file the "Questions and smaller notes" of
> `proposed/s3w1-wave-pr-397-review.md` as ONE item (owner prefers fewer, larger items). That review's five findings
> were fixed by #400; these seven notes were not. 2216aefd verified all seven still open on `main` `f4b0732`; the S3
> operator f849e0cc re-checked the code anchors below on the same commit.

## Problem
The locally recovered review of wave PR #397 (S3 wave 1) left seven small notes. Each is small; together they are
a recurring source of owner questions, silent drift and untested refusals:
1. **A lock held by a live lane reads as a leftover.** `closeout-classify` maps `skipped — run lock held by *` to
   `leftover|lock` (`automate-helpers.d/resume.sh`, the classification table). Under `closeout-others` the lock is
   often held by a different live lane in the same checkout, so a non-interactive start parks `closeout_leftover`
   for a run that is merely busy.
2. **The SessionStart probe can stall resumes.** `session-resume.sh`'s `sr_pr_state` makes up to 5 sequential `gh`
   calls, each with a 5 s timeout, and no overall deadline: with `gh` offline or unauthenticated about 25 s is added
   to every resume, clear or compact (it still exits 0 and stays quiet).
3. **`current-rebuild` contradicts itself.** It sets `status: running` (the `current_set` call in
   `automate-helpers.d/runfile.sh`'s `current_rebuild` passes no `--pause-reason`) but keeps the stale `pause_reason`
   (often `awaiting_go`), so `## Current` disagrees with itself until the owner's ask.
4. **`finalize-empty` writes `done` before `trail-pr`** (`automate-trail.sh`), so a failed `trail-pr` is never
   retried. This matches the live Termination exit but is undocumented at the call site.
5. **Home-path examples remain in a result schema.** `docs/result-schemas/execute-result.md` (moved there from
   `RESULT_SCHEMAS.md` by pa/11) still shows `path: /Users/<name>/myapp-…` twice, so the changelog's "no home-path
   examples" is not true across the tree.
6. **An untested refusal in meta-sync.** `load_base`'s unreadable meta-base branch (`[ ! -r "$META_BASE" ]` →
   `base_branch_mismatch`, `meta-sync.sh`) has no test leg, unlike the other new refusals; it needs a root guard.
7. **A misleading test title.** `test-meta-sync.sh` test 38's title says symlinked non-managed files "sync"; per the
   code and header they are ignored (never synced, no longer refused). The released `CHANGELOG.md` headline carries
   the same wording — do NOT edit the released entry.

## Goal
Each note is fixed or explicitly documented, with a test where behaviour changes, in one change set.

## Scope
1. **Lock held by a live lane:** map `skipped — run lock held by …` to a non-leftover class (recommended:
   `run_lock_held`, retried at the next start) when the holder is live; a dead holder stays `leftover|lock`. Pick
   after reading `closeout_classify` and the `closeout_leftover` park in `automate-loop/SKILL.md`.
2. **One overall deadline for `sr_pr_state`** (or stop after the first `unverified`); the probe stays fail-SAFE
   (exit 0, quiet).
3. **`current-rebuild` clears or rewrites `pause_reason`** consistently with `status: running` (through
   `current_set`, the only writer of `## Current`).
4. **`finalize-empty` order:** reorder so a failed `trail-pr` is retried, or keep the order and add the comment
   explaining why `done` comes first. State which in the PR.
5. **Home-path examples:** replace the two `/Users/<name>/…` examples in `result-schemas/execute-result.md` with
   `~/…` or a repo-relative form.
6. **Test leg** for `load_base`'s unreadable-meta-base refusal (skip under root, as the other permission legs do).
7. **Retitle `test-meta-sync.sh` test 38** to say symlinked non-managed files are ignored. Leave `CHANGELOG.md`'s
   released entry as is.

## Non-goals
The five #397 findings (done in #400). Any new closeout behaviour beyond the lock classification. Editing released
changelog entries.

## Acceptance criteria
- A fixture where `closeout-others` meets a run lock held by a LIVE process classifies it as non-leftover and parks
  nothing; a dead holder still reads `leftover|lock`.
- `sr_pr_state` with a stubbed `gh` that hangs returns within the overall deadline.
- After `current-rebuild`, `## Current` never shows `status: running` with a pause-only `pause_reason`.
- `grep -rn '/Users/<name>' loomwright/docs/` returns nothing.

## Validation (must pass before merge)
1. Baseline full loop (`bash scripts/ci-local.sh`), `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: existing `closeout-classify`, `session-resume` and `meta-sync` assertions pass with no assertion
   edited (test 38's title is a title, not an assertion).
3. Running system: one real `/automate --resume` start with another live run holding the lock; paste the
   classification line.
4. A failure this must catch: reverting Scope 1's live-holder check makes its new test fail; removing Scope 6's
   refusal makes the new leg fail.
5. Rollback: `git revert`.

## Evidence
`proposed/s3w1-wave-pr-397-review.md` §"Questions and smaller notes" (static review of #397's merge commit
`f0b4b66`; nothing executed). Code anchors re-checked 2026-10-07 on `main` `f4b0732`: `resume.sh` maps
`leftover|lock|skipped — run lock held by *`; `runfile.sh`'s `current_rebuild` calls `current_set … --status
running` with no `--pause-reason`; `execute-result.md` carries two `/Users/<name>/myapp-…` paths; `meta-sync.sh`'s
`load_base` has the `[ ! -r "$META_BASE" ]` branch.

## Depends on
none

## Touches
loomwright/scripts/automate-helpers.d/resume.sh
loomwright/scripts/automate-helpers.d/runfile.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/session-resume.sh
loomwright/scripts/test-session-resume.sh
loomwright/scripts/test-meta-sync.sh
loomwright/docs/result-schemas/execute-result.md
loomwright/skills/automate-loop/SKILL.md
changelog.d/automate-followups-35-wave1-review-leftovers.md
