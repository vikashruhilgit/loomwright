# 08 — meta-sync hardening: symlinked files, untested hardening branches, branch from the mode line

## Status: pending

## Merged from (2026-10-05, owner decision before the S3 wave spike)
- Part A: `02-symlinked-file-under-requirements.md` — 02 — meta-sync: a symlinked non-managed FILE under requirements/ must not refuse the whole sync
- Part B: `03-untested-hardening-branches.md` — 03 — meta-sync: pin the iteration-2 hardening branches with tests
- Part C: `06-default-branch-from-mode-line.md` — 06 — `meta-sync.sh` takes its default branch from the checkout's mode line, never silently from a constant

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Goal
One meta-sync.sh change set: a symlinked non-managed file never refuses the whole sync (A), the iteration-2 hardening branches are pinned by tests (B), and the default branch comes from the checkout's mode line (C).

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Parts

### Part A — 02 — meta-sync: a symlinked non-managed FILE under requirements/ must not refuse the whole sync

#### Notes on the touched files (conditions moved out of the machine-read section)
- `ARCHITECTURE_CONTRACTS.md` §"Metadata branch" changes only if the stated rule changes.
- "PR #334 MERGED" dropped from Depends (merged).

#### Problem
`symlink_hazard` in `loomwright/scripts/meta-sync.sh` treats a local symlink as hazardous when `is_managed "$1" || is_managed "$1/x.md"`. The second arm is meant to catch a symlinked DIRECTORY under `.supervisor/requirements/` (which could hide managed `.md` files or redirect writes), but it matches every path under `requirements/`, including a symlinked regular FILE such as `requirements/q/design.png`. Such a file can neither hide managed files nor be written through (pull's `path_has_no_symlink` already guards every write, and a managed `.md` symlink is caught by the first arm), yet it makes `pull` and `push` refuse with `meta_sync: symlink <path>` until someone removes it. The script header and `ARCHITECTURE_CONTRACTS.md` describe the rule as "any **folder** under requirements/", so the code is stricter than its documented contract.

Reproduced by the PR #334 Phase 4.5 reviewer (iteration 3): rc=1, `meta_sync: symlink .supervisor/requirements/q/design.png`.

#### Goal
Only symlinks that can actually hide or redirect managed run history refuse the sync; a symlinked non-managed file under `requirements/` is ignored, matching the documented rule.

#### Scope
1. Apply the `"$1/x.md"` arm only when the symlink points at a directory or is dangling (`[ -d "$ROOT/$1" ] || [ ! -e "$ROOT/$1" ]`), or an equivalent precise rule. Keep the first arm (`is_managed "$1"`, a symlinked managed `.md`) and every ancestor-directory check unchanged.
2. Tests:
   - a symlinked non-`.md` FILE under `requirements/` ⇒ `pull` and `push` succeed and the file is not published;
   - a symlinked DIRECTORY under `requirements/` ⇒ still refused, nothing written, nothing deleted from the branch;
   - a DANGLING symlink under `requirements/` ⇒ still refused (it could become a directory);
   - a symlinked managed `.md` file ⇒ still refused.
3. A sed-built mutant that restores the old over-broad arm must turn the first test red.

#### Non-goals
Any other symlink rule; the containment checks on pull writes (`path_has_no_symlink`, `parent_inside`).

#### Acceptance criteria
- Given `.supervisor/requirements/q/design.png` is a symlink to a regular file, when `pull`/`push` run, then both succeed and the branch carries no `design.png`.
- Given a symlinked directory, a dangling symlink, or a symlinked managed `.md` under `requirements/`, when `pull`/`push` run, then each still refuses with `meta_sync: symlink <path>`, exit 1, nothing changed.
- The doc and script header state the rule exactly as implemented.
- Full loop green (`run-self-tests.sh` + root tests + `check-*.sh`); bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh` as the LAST commit.

#### Provenance
Promoted 2026-10-02 by the owner from dismissed-finding draft `.supervisor/requirements/proposed/automate-2026-10-01-142337--02-meta-sync-script-b0d4ba--dismissed-9bd82e20.md` (run automate-2026-10-01-142337, PR #334, Phase 4.5 code_reviewer iteration 3, MEDIUM, below_severity_floor; owner decision follow-up). Verified still present on PR head 566b3d3.


### Part B — 03 — meta-sync: pin the iteration-2 hardening branches with tests

#### Notes on the touched files (conditions moved out of the machine-read section)
- `loomwright/scripts/meta-sync.sh` is edited only if a test exposes a defect.
- "PR #334 MERGED" dropped from Depends (merged).

#### Problem
Four fail-closed or recovery branches added while hardening `loomwright/scripts/meta-sync.sh` on PR #334 have no test. The PR's reviewer verified two of them by scratch repro, but nothing pins any of them in CI, so a later edit can break them silently:
- **`--no-write-fetch-head` fallback:** the fetch helper retries a plain fetch when an older git (< 2.29) rejects the flag.
- **`union_into`'s "changed during the sync" re-check:** pull re-hashes the local `results.jsonl` before writing the union and refuses if it changed after the plan was computed.
- **Nested `reclaim_lock`:** a dead `<lock>.reclaim.<pid>` marker is itself reclaimed one level up (depth-limited).
- **`write_base_file`'s directory guard:** writing meta-base refuses when `<gitdir>/meta-base` is a directory.

(The find-failure refusal, `could not enumerate …`, which this finding also named, is already covered by PR #334's test leg 29. Re-check before starting; drop anything already covered.)

#### Goal
Each of the four branches is pinned by a test leg that fails if the branch regresses.

#### Scope
1. **Fetch fallback:** a PATH `git` shim that rejects `--no-write-fetch-head` (exit 129 with git's own error text) and passes everything else through. Assert pull/push still succeed, and that `FETCH_HEAD` behaviour matches the documented fallback.
2. **Changed during the sync:** a deterministic hook point (a PATH shim on a command the union path runs after planning, the same technique as legs 22/27) that appends a line to the local `results.jsonl` between plan and write. Assert pull refuses with "changed during the sync", writes nothing, and leaves meta-base untouched.
3. **Nested reclaim:** plant `meta-sync.lock` plus `meta-sync.lock.reclaim.<dead pid>` holding a dead pid. Assert the next run reclaims both and proceeds, with never two holders (reuse leg 27's holder log).
4. **meta-base directory guard:** make `<gitdir>/meta-base` a directory. Assert pull/push refuse with the documented message and nothing is published.
5. Each new leg must turn red under a sed-built mutant that removes the branch it covers (no env-var seam in the shipped script).

#### Non-goals
Behaviour changes beyond fixing a defect a new leg exposes. Raising the reclaim depth limit (separate LOW in the summary draft).

#### Acceptance criteria
- Given each of the four conditions above, when the relevant command runs, then it takes the documented branch (fallback succeeds; refusal exits non-zero with the named message and changes nothing), and a test asserts it.
- Each new leg turns red under its own mutant, shown in the PR body.
- Full loop green (`run-self-tests.sh` + root tests + `check-*.sh`); bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh` as the LAST commit.

#### Provenance
Promoted 2026-10-02 by the owner from dismissed-finding draft `.supervisor/requirements/proposed/automate-2026-10-01-142337--02-meta-sync-script-b0d4ba--dismissed-5ea27966.md` (run automate-2026-10-01-142337, PR #334, Phase 4.5 code_reviewer iteration 3, MEDIUM, below_severity_floor; owner decision follow-up). Scope narrowed on promotion after verifying on PR head 566b3d3 that the find-failure refusal is already tested.


### Part C — 06 — `meta-sync.sh` takes its default branch from the checkout's mode line, never silently from a constant

#### Problem
`loomwright/scripts/meta-sync.sh` sets `BRANCH="loomwright-meta"` and changes it only with `--branch`. It never
reads the checkout's own mode line (`# loomwright-meta-branch: <name>` in `.gitignore`), which `setup-memory.sh mode`
does read. The engine passes `--branch` itself, so engine pushes go to the right place, but **any plain
`meta-sync.sh pull|push` in a checkout whose mode line names another branch targets the REAL `loomwright-meta`.**

Seen 2026-10-04 in S1 v2's wrap-up: in lane clones whose mode line said `loomwright-meta-s1v2`, an operator `push`
without `--branch` aimed at the real branch (saved only because it reported `no_changes`), and a `pull` dragged the
real branch into a lane clone. Lanes (item 05) put several checkouts on non-default branches at once, so this trap
multiplies.

#### Goal
With no `--branch`, `meta-sync.sh` uses the branch the checkout's mode line names; an explicit `--branch` that
disagrees with the mode line is refused unless forced, so no command reaches a branch the checkout is not set up for.

#### Scope
1. Default branch = the mode line's branch when the mode line is present and well-formed; the constant
   `loomwright-meta` only when there is no mode line (today's behaviour for unmigrated repos).
2. `--branch X` when the mode line names `Y` ≠ `X` ⇒ exit 1 `branch_mismatch` with both names; `--branch X
   --allow-branch-mismatch` proceeds (for deliberate operator moves such as carrying records between branches).
3. `status` prints the branch it compared against (`synced <sha> on <branch>`), so an operator sees the target.
4. Tests: a clone with a throwaway mode line pulls and pushes the throwaway branch with no flag; a mismatched
   `--branch` is refused; the override works; no mode line ⇒ `loomwright-meta`; `status` names the branch.

#### Acceptance criteria
- In a lane clone set up the S1 way, `meta-sync.sh push` with no flags pushes to the lane's throwaway branch.

#### Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: the primary (mode line = `loomwright-meta`) behaves exactly as today.
3. Running system: a throwaway clone with an edited mode line; paste `status` / `push` output naming the branch.
4. A failure this must catch: ignore the mode line again ⇒ the throwaway-clone test fails.
5. Rollback: `git revert`.

#### Evidence
S1 run record, "v2 wrap-up" (operator slip + trap); `parallel-automate/05` Spike findings (Q5).


## Depends on
01-untested-push-and-base-fallbacks.md

## Touches
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
changelog.d/meta-sync-followups-08-meta-sync-hardening.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-05T17:15:24Z
- **Brief:** .supervisor/jobs/done/2026-10-05-meta-sync-hardening.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/394
