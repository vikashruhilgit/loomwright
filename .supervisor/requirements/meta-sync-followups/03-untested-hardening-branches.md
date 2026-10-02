# 03 — meta-sync: pin the iteration-2 hardening branches with tests

## Depends on
PR #334 (parallel-automate/02, `meta-sync.sh`) MERGED to `main`, and meta-sync-followups/02 (same two files — keep the queue serial).

## Touches
loomwright/scripts/test-meta-sync.sh
loomwright/scripts/meta-sync.sh (only if a test exposes a defect)

## Problem
Four fail-closed or recovery branches added while hardening `loomwright/scripts/meta-sync.sh` on PR #334 have no test. The PR's reviewer verified two of them by scratch repro, but nothing pins any of them in CI, so a later edit can break them silently:
- **`--no-write-fetch-head` fallback:** the fetch helper retries a plain fetch when an older git (< 2.29) rejects the flag.
- **`union_into`'s "changed during the sync" re-check:** pull re-hashes the local `results.jsonl` before writing the union and refuses if it changed after the plan was computed.
- **Nested `reclaim_lock`:** a dead `<lock>.reclaim.<pid>` marker is itself reclaimed one level up (depth-limited).
- **`write_base_file`'s directory guard:** writing meta-base refuses when `<gitdir>/meta-base` is a directory.

(The find-failure refusal, `could not enumerate …`, which this finding also named, is already covered by PR #334's test leg 29. Re-check before starting; drop anything already covered.)

## Goal
Each of the four branches is pinned by a test leg that fails if the branch regresses.

## Scope
1. **Fetch fallback:** a PATH `git` shim that rejects `--no-write-fetch-head` (exit 129 with git's own error text) and passes everything else through. Assert pull/push still succeed, and that `FETCH_HEAD` behaviour matches the documented fallback.
2. **Changed during the sync:** a deterministic hook point (a PATH shim on a command the union path runs after planning, the same technique as legs 22/27) that appends a line to the local `results.jsonl` between plan and write. Assert pull refuses with "changed during the sync", writes nothing, and leaves meta-base untouched.
3. **Nested reclaim:** plant `meta-sync.lock` plus `meta-sync.lock.reclaim.<dead pid>` holding a dead pid. Assert the next run reclaims both and proceeds, with never two holders (reuse leg 27's holder log).
4. **meta-base directory guard:** make `<gitdir>/meta-base` a directory. Assert pull/push refuse with the documented message and nothing is published.
5. Each new leg must turn red under a sed-built mutant that removes the branch it covers (no env-var seam in the shipped script).

## Non-goals
Behaviour changes beyond fixing a defect a new leg exposes. Raising the reclaim depth limit (separate LOW in the summary draft).

## Acceptance criteria
- Given each of the four conditions above, when the relevant command runs, then it takes the documented branch (fallback succeeds; refusal exits non-zero with the named message and changes nothing), and a test asserts it.
- Each new leg turns red under its own mutant, shown in the PR body.
- Full loop green (`run-self-tests.sh` + root tests + `check-*.sh`); bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh` as the LAST commit.

## Provenance
Promoted 2026-10-02 by the owner from dismissed-finding draft `.supervisor/requirements/proposed/automate-2026-10-01-142337--02-meta-sync-script-b0d4ba--dismissed-5ea27966.md` (run automate-2026-10-01-142337, PR #334, Phase 4.5 code_reviewer iteration 3, MEDIUM, below_severity_floor; owner decision follow-up). Scope narrowed on promotion after verifying on PR head 566b3d3 that the find-failure refusal is already tested.

## Status: pending
