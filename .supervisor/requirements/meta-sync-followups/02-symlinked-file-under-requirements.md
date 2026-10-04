# 02 — meta-sync: a symlinked non-managed FILE under requirements/ must not refuse the whole sync

## Depends on
01

## Touches
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/meta-sync-followups-02-symlinked-file-under-requirements.md

## Notes on the touched files (conditions moved out of the machine-read section)
- `ARCHITECTURE_CONTRACTS.md` §"Metadata branch" changes only if the stated rule changes.
- "PR #334 MERGED" dropped from Depends (merged).

## Problem
`symlink_hazard` in `loomwright/scripts/meta-sync.sh` treats a local symlink as hazardous when `is_managed "$1" || is_managed "$1/x.md"`. The second arm is meant to catch a symlinked DIRECTORY under `.supervisor/requirements/` (which could hide managed `.md` files or redirect writes), but it matches every path under `requirements/`, including a symlinked regular FILE such as `requirements/q/design.png`. Such a file can neither hide managed files nor be written through (pull's `path_has_no_symlink` already guards every write, and a managed `.md` symlink is caught by the first arm), yet it makes `pull` and `push` refuse with `meta_sync: symlink <path>` until someone removes it. The script header and `ARCHITECTURE_CONTRACTS.md` describe the rule as "any **folder** under requirements/", so the code is stricter than its documented contract.

Reproduced by the PR #334 Phase 4.5 reviewer (iteration 3): rc=1, `meta_sync: symlink .supervisor/requirements/q/design.png`.

## Goal
Only symlinks that can actually hide or redirect managed run history refuse the sync; a symlinked non-managed file under `requirements/` is ignored, matching the documented rule.

## Scope
1. Apply the `"$1/x.md"` arm only when the symlink points at a directory or is dangling (`[ -d "$ROOT/$1" ] || [ ! -e "$ROOT/$1" ]`), or an equivalent precise rule. Keep the first arm (`is_managed "$1"`, a symlinked managed `.md`) and every ancestor-directory check unchanged.
2. Tests:
   - a symlinked non-`.md` FILE under `requirements/` ⇒ `pull` and `push` succeed and the file is not published;
   - a symlinked DIRECTORY under `requirements/` ⇒ still refused, nothing written, nothing deleted from the branch;
   - a DANGLING symlink under `requirements/` ⇒ still refused (it could become a directory);
   - a symlinked managed `.md` file ⇒ still refused.
3. A sed-built mutant that restores the old over-broad arm must turn the first test red.

## Non-goals
Any other symlink rule; the containment checks on pull writes (`path_has_no_symlink`, `parent_inside`).

## Acceptance criteria
- Given `.supervisor/requirements/q/design.png` is a symlink to a regular file, when `pull`/`push` run, then both succeed and the branch carries no `design.png`.
- Given a symlinked directory, a dangling symlink, or a symlinked managed `.md` under `requirements/`, when `pull`/`push` run, then each still refuses with `meta_sync: symlink <path>`, exit 1, nothing changed.
- The doc and script header state the rule exactly as implemented.
- Full loop green (`run-self-tests.sh` + root tests + `check-*.sh`); bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh` as the LAST commit.

## Provenance
Promoted 2026-10-02 by the owner from dismissed-finding draft `.supervisor/requirements/proposed/automate-2026-10-01-142337--02-meta-sync-script-b0d4ba--dismissed-9bd82e20.md` (run automate-2026-10-01-142337, PR #334, Phase 4.5 code_reviewer iteration 3, MEDIUM, below_severity_floor; owner decision follow-up). Verified still present on PR head 566b3d3.

## Status: pending
