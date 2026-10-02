# 01 — meta-sync: test the push-retry exhaustion and missing-meta-base-object fallback

## Depends on
PR #334 (parallel-automate/02, `meta-sync.sh`) MERGED to `main` — this item tests code that exists only there.

## Touches
loomwright/scripts/test-meta-sync.sh
loomwright/scripts/meta-sync.sh (only if a test exposes a defect)

## Problem
Two fail-closed branches of `loomwright/scripts/meta-sync.sh` have no test, so a regression in either would ship silently:
- **Exhausted push retries.** `cmd_push` retries a rejected push and, after `MAX_ATTEMPTS`, dies with `push_failed — rejected <n> times; nothing forced, meta-base untouched`. No test drives a remote that rejects every push.
- **Missing meta-base object.** `load_base` (the `<gitdir>/meta-base` reader, anchored by `refs/meta-sync/base`) falls back to the no-base history derivation when the recorded tree object is missing. No test deletes that object.

(The other branches this finding originally named — the tracked deny file `.agent/meta-sync-deny.txt` and `ledger_unverifiable` when jq is missing — were covered on PR #334 in drain round 1, test legs 32–33. Re-check before starting; drop anything already covered.)

## Goal
Each of the two branches is pinned by a test leg that fails if the branch's fail-closed behaviour regresses.

## Scope
1. **push_failed leg:** a bare origin with a `pre-receive` (or `update`) hook that rejects every push. Assert: `push` exits 1 with `push_failed`, the branch tip on origin is unchanged, `<gitdir>/meta-base` is unchanged, no `--force` was attempted, and the attempt count equals the documented bound.
2. **Missing-object leg:** sync once (meta-base recorded), then make the recorded tree object unreachable/absent (delete `refs/meta-sync/base` and prune, or point meta-base at a non-existent sha). Assert: the documented warning is printed, behaviour equals the no-base derivation (a file the branch deleted is not resurrected; a genuinely new local file is pushed), and nothing is published before the derivation completes.
3. Each new leg must be shown to FAIL against a mutant that removes the branch it covers (sed-built mutant in the test's temp dir, the `test-run-lock.sh` convention — no env-var seam in the shipped script).

## Non-goals
Any behaviour change to `meta-sync.sh` beyond fixing a defect a new leg exposes. Calling the script from the engine (item parallel-automate/03).

## Acceptance criteria
- Given a remote that rejects every push, when `meta-sync.sh push` runs, then it exits 1 with `push_failed`, origin's branch tip and the local meta-base are unchanged, and the test asserts each.
- Given a recorded meta-base whose tree object is missing, when `pull` or `push` runs, then it warns and follows the no-base derivation (no resurrection of a branch-deleted file), and the test asserts it.
- Each new leg turns red under its own mutant, shown in the PR body.
- `bash loomwright/scripts/run-self-tests.sh` + root `scripts/test-*.sh` + `scripts/check-*.sh` green; bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh` as the LAST commit.

## Provenance
Promoted 2026-10-02 by the owner from dismissed-finding draft `.supervisor/requirements/proposed/automate-2026-10-01-142337--02-meta-sync-script-b0d4ba--dismissed-6159f242.md` (run automate-2026-10-01-142337, PR #334, Phase 4.5 code_reviewer, MEDIUM, below_severity_floor; owner decision follow-up). Scope narrowed on promotion after verifying on PR head 566b3d3 that the deny-file and jq-missing branches are already tested.

## Status: pending
