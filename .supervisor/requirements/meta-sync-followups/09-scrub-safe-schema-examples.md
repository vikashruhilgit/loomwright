# 09 — Scrub-safe worktree paths in the result-schema examples and fixtures

## Status: parked (merged 2026-10-06 into `meta-sync-followups/11-scrub-precision.md` as Part B — do not run this file; work the merged item)

## Depends on
none

## Touches
loomwright/docs/RESULT_SCHEMAS.md
loomwright/scripts/result-validator-fixtures/execute-checkpoint-valid.md
loomwright/scripts/result-validator-fixtures/execute-result-valid.md
changelog.d/meta-sync-followups-09-scrub-safe-schema-examples.md

## Problem
Filed 2026-10-05 by the owner at PR #391's park (one of its "Not verified" items; out of `04`'s scope because
`RESULT_SCHEMAS.md` is in `automate-followups/32`'s Touches, which runs in the same wave).
The worktree-path examples read `/Users/<literal "name">/myapp-...` (`RESULT_SCHEMAS.md` the two `path:` lines of the
EXECUTE_RESULT example; `execute-checkpoint-valid.md` `active_worktrees`; `execute-result-valid.md` two `path:` lines).
`name` is inside the `meta-sync.sh` `home_path` class `[A-Za-z0-9._-]+`, so any record that copies an example
verbatim is refused by the scrub (exit 2), blocking the lane's whole trail push. `04` set the convention:
placeholders in angle brackets (`/Users/<name>/`), which fall outside the class.

## Scope
1. Rewrite the five example paths to the `04` placeholder form (`/Users/<name>/myapp-add-jwt-guard`), keeping
   every fixture valid for `result-validator.sh` (the validator must still accept the fixtures).
2. Check, and record in this file, whether a REAL EXECUTE_RESULT / checkpoint written into a managed sidecar
   (`.supervisor/automate/*.md`) carries an absolute worktree path that trips the scrub on a lane's trail push (S2's
   handover names `reconcile-status` paths in run files as one cause of blocked pushes). If it does, that is a
   separate item — file it, do not widen this one.

## Non-goals
Changing the scrub regex (`10`). Changing what the schemas require.

## Acceptance criteria
- `grep -nE '/(Users|home)/[A-Za-z0-9._-]+/' loomwright/docs/RESULT_SCHEMAS.md loomwright/scripts/result-validator-fixtures/`
  returns nothing.
- The result-validator self-test passes with the rewritten fixtures.
- `bash scripts/ci-local.sh` green; a `changelog.d/` fragment.

## Validation (must pass before merge)
- The grep above, and the validator test, on the PR head.
