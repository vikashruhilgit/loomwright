# 02 — `meta-sync.sh`: pull / push / status for run history on a dedicated branch

## Depends on
none

## Touches
`loomwright/scripts/meta-sync.sh` (new), `loomwright/scripts/test-meta-sync.sh` (new),
`loomwright/docs/ARCHITECTURE_CONTRACTS.md` (one new section), `loomwright/docs/vendor-coupling-manifest.json`
(only if the new file needs an allowance)

## Problem
Run history is committed on `main`: 368 tracked files (5.4 MB) under `.supervisor/`, and 20 of the last 60
first-parent merges on `main` are metadata-only PRs that each needed CI and an owner review. Tracked metadata on
code branches has also produced a family of defects (trail files vanishing on branch switch, staged trail entries
swept into the next item's commit, `git pull` refusing over restored files). Item 03 moves run history to a
dedicated unprotected branch; this item builds the one script that does the moving, with no behaviour change yet.

## Goal
One script copies run-history files between the working folder and a metadata branch without ever switching
branches, touching the code branch's index, or force-pushing.

## Scope
1. **`meta-sync.sh pull [--branch <name>] [--root <checkout>]`**
   - `git fetch origin <branch>`; then restore the managed paths into the working folder from
     `origin/<branch>` WITHOUT touching the index (`git restore --source=… --worktree -- <paths>`).
   - **Fetch failure ⇒ exit non-zero** (fail CLOSED). A caller that starts a run must not proceed on it.
   - **Branch does not exist on the remote ⇒ exit 0** with `meta_sync: no_remote_branch` (first use).
   - Never deletes a local file that is absent from the branch; never overwrites a local file that is NEWER than
     the branch copy without recording it — print `meta_sync: kept_local <path>` and leave it for `push`.
2. **`meta-sync.sh push [--branch <name>] [--root <checkout>] [--message <m>]`**
   - Stage the managed paths into a SEPARATE index (`GIT_INDEX_FILE=<gitdir>/meta-index`, `git add -f`), seeded
     from the current `origin/<branch>` tree so files this checkout never pulled are not deleted;
     `write-tree` → `commit-tree` (parent = `origin/<branch>` tip) → `git push origin <sha>:refs/heads/<branch>`.
   - **Rejected push ⇒ re-fetch, rebuild on the new tip, retry** (bounded, e.g. 5 attempts). NEVER `--force`.
   - **Append-only files** (`.supervisor/postmortem/results.jsonl`) merge by line union, never by overwrite.
   - **Privacy scrub before push, fail CLOSED:** run the same repo-allowlist / scrub checks `/setup memory`
     applies to committed stores today; any hit aborts the push with exit 2 and names the path.
   - Nothing to push ⇒ exit 0, `meta_sync: no_changes`.
3. **`meta-sync.sh status`** — one line: `synced <sha>` / `local_ahead <n files>` / `remote_ahead` /
   `no_remote_branch` / `unreachable`. Always exit 0 (read-only reporter).
4. **Managed paths** are a single declared list in the script (the run-history set from decision P3:
   `.supervisor/requirements/`, `.supervisor/jobs/done/`, `.supervisor/jobs/failed/`, `.supervisor/automate/*.md`,
   `.supervisor/postmortem/results.jsonl`). Lessons, agent memory and `.agent/` are NOT in it.
5. **Root resolution** mirrors the existing convention (first `git worktree list --porcelain` entry unless
   `--root` is given) so a call from a linked worktree acts on the primary checkout.
6. **Tests** (`test-meta-sync.sh`, hermetic: bare origin + two clones in a temp dir): round-trip; code branch
   `git status --porcelain` empty after push and after pull; concurrent push from two clones ⇒ both sets of files
   on the branch, no force; `results.jsonl` union; fetch failure ⇒ pull exits non-zero; scrub hit ⇒ push exits 2
   and the branch is unchanged; a file present on the branch but never pulled survives another clone's push.
   **Mutation control:** removing the "seed the index from the branch tip" step must make the last test fail.
7. **Docs:** a short §"Metadata branch" in `ARCHITECTURE_CONTRACTS.md` (mechanism, managed paths, exit codes).

## Non-goals
Changing `.gitignore`, migrating any file, or calling the script from a hook or the engine (all item 03). A slash
command (item 03 decides whether one is needed beyond `/setup memory`).

## Acceptance criteria
- In a temp repo: push from clone A, pull in clone B, both clones report a clean `git status --porcelain` and the
  files are present in B.
- No code path in the script can run `git checkout`, `git switch`, `git merge`, or `git push --force`.
- `bash loomwright/scripts/test-meta-sync.sh` green under `/bin/bash` 3.2 (macOS) and in CI.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; both `<passed>/<total>` lines in the PR body.
2. **Unchanged path:** `git grep -n 'meta-sync' -- loomwright/hooks loomwright/agents loomwright/commands
   loomwright/skills` returns nothing and no existing script calls the new one — the item is additive, so no
   session behaves differently after it merges. `git diff --stat origin/main` shows no edit to `.gitignore`,
   `hooks.json`, `automate-helpers.sh` or `automate-trail.sh`.
3. **Running system:** against a scratch clone of THIS repo with a throwaway branch name (e.g.
   `loomwright-meta-test`, pushed to a local bare remote — NEVER to GitHub in this item): `push`, then `pull` in a
   second scratch clone; paste `git status --porcelain` from both (empty), `meta-sync.sh status`, and a `diff -r`
   of the managed paths between the two clones (identical). Run it once under `/bin/bash` 3.2.
4. **Rollback:** `git revert` of the PR. Nothing is lost — nothing calls the script yet.

## Verified premises (re-check before starting)
- Scratch spike 2026-10-01 (see 00-overview §Evidence): the separate-index push and the `git restore --source
  --worktree` pull both worked and left the code branch clean. The spike did NOT test concurrent pushes, the
  line-union merge, or the "seed from tip" behaviour — those are this item's to prove.
- `.gitignore`'s `.supervisor/*` block is managed by `/setup memory` between sentinels ("hand-edits inside these
  sentinels are overwritten on the next apply") — this item must not edit it.
- The scrub/allowlist logic lives in `loomwright/scripts/setup-memory.sh` (`allowlist` subcommand and the
  committed-twin scrub exercised by `test-committed-twin-scrub.sh`); read it before reusing it — do not assume its
  call shape.

## Status: pending
