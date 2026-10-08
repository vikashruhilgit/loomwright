# 37 — A requirement is stamped `done` before its PR merges

## Status: pending

## Depends on
none

## Touches
loomwright/skills/self-heal-advisory/SKILL.md
loomwright/skills/automate-loop/SKILL.md
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
changelog.d/automate-followups-37-done-stamp-before-merge.md

## Problem
pa/05's Validation 4 (run `automate-2026-10-08-033739`, 2026-10-08) found finding F7. Inside each lane, the
requirement file received the closeout block (`<!-- loomwright:requirement-closeout -->` / `## Status: done` /
`Completed` / `Brief` / `PR`) during the Supervisor run, while the PR was still OPEN. L1 attributes the write to
Phase 4.5's self-review step (`skills/self-heal-advisory/SKILL.md` carries the marker). `automate-trail.sh`'s
`closeout` writes the same block, but only after `MERGED`.

Today the evidence gate in `trail-pr` keeps that early stamp off `main` / meta. But any other push path carries it.
In this run, a whole-lane `meta-sync.sh push` put a done claim for two never-merged items on `loomwright-meta`,
and it had to be corrected by hand (meta `b8697aa`). Because `is_done` matches any `## Status:` line, a clone that
holds the early stamp also reads the item as done locally. That affects folder intake, `plan-waves` and
`reconcile-status`. This behaviour predates pa/05.

## Goal
`## Status: done` on a requirement is written only by the post-merge close-out (`closeout`, evidence: the PR reads
`MERGED`). Nothing earlier in the flow makes a done claim.

## Scope
1. Find every writer of the requirement closeout block (`grep -rn 'requirement-closeout' loomwright/`), and the
   Supervisor / Phase 4.5 prose that tells an agent to stamp the requirement. Write the list into the PR.
2. Remove or defer the pre-merge writers. Phase 4.5 may record its verdict elsewhere (the brief, the run file), never
   as a `## Status:` line on the requirement.
3. A test proves a full sequential `/autonomous` + drain fixture leaves the requirement's `## Status:` unchanged until
   `closeout` runs on `MERGED`.

## Acceptance criteria
- After Supervisor and the drain, with the PR still open, the requirement carries no `## Status: done` line.
- `closeout` on `MERGED` still writes the same block, byte for byte.
- The existing trail tests pass unchanged.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` is green.
2. The new test, shown failing on the base and passing on the branch.
3. **Running system:** one real sequential `/automate` item, parked `awaiting_merge`. Paste the requirement's
   `## Status:` lines before the merge (no done), then again after the owner merges and the watcher's `closeout`
   (done).
4. Rollback: `git revert`.

## Non-goals
Lane wave-end pushes (`parallel-automate/23` F11). `reconcile-status` semantics.
