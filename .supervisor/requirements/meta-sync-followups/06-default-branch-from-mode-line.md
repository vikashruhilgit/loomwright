# 06 — `meta-sync.sh` takes its default branch from the checkout's mode line, never silently from a constant

## Status: pending

## Problem
`loomwright/scripts/meta-sync.sh` sets `BRANCH="loomwright-meta"` and changes it only with `--branch`. It never
reads the checkout's own mode line (`# loomwright-meta-branch: <name>` in `.gitignore`), which `setup-memory.sh mode`
does read. The engine passes `--branch` itself, so engine pushes go to the right place, but **any plain
`meta-sync.sh pull|push` in a checkout whose mode line names another branch targets the REAL `loomwright-meta`.**

Seen 2026-10-04 in S1 v2's wrap-up: in lane clones whose mode line said `loomwright-meta-s1v2`, an operator `push`
without `--branch` aimed at the real branch (saved only because it reported `no_changes`), and a `pull` dragged the
real branch into a lane clone. Lanes (item 05) put several checkouts on non-default branches at once, so this trap
multiplies.

## Goal
With no `--branch`, `meta-sync.sh` uses the branch the checkout's mode line names; an explicit `--branch` that
disagrees with the mode line is refused unless forced, so no command reaches a branch the checkout is not set up for.

## Scope
1. Default branch = the mode line's branch when the mode line is present and well-formed; the constant
   `loomwright-meta` only when there is no mode line (today's behaviour for unmigrated repos).
2. `--branch X` when the mode line names `Y` ≠ `X` ⇒ exit 1 `branch_mismatch` with both names; `--branch X
   --allow-branch-mismatch` proceeds (for deliberate operator moves such as carrying records between branches).
3. `status` prints the branch it compared against (`synced <sha> on <branch>`), so an operator sees the target.
4. Tests: a clone with a throwaway mode line pulls and pushes the throwaway branch with no flag; a mismatched
   `--branch` is refused; the override works; no mode line ⇒ `loomwright-meta`; `status` names the branch.

## Acceptance criteria
- In a lane clone set up the S1 way, `meta-sync.sh push` with no flags pushes to the lane's throwaway branch.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: the primary (mode line = `loomwright-meta`) behaves exactly as today.
3. Running system: a throwaway clone with an edited mode line; paste `status` / `push` output naming the branch.
4. A failure this must catch: ignore the mode line again ⇒ the throwaway-clone test fails.
5. Rollback: `git revert`.

## Evidence
S1 run record, "v2 wrap-up" (operator slip + trap); `parallel-automate/05` Spike findings (Q5).

## Depends on
none

## Touches
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
changelog.d/meta-sync-followups-06-default-branch-from-mode-line.md
