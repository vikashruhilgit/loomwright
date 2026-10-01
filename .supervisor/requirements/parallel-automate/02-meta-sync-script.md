# 02 — `meta-sync.sh`: init / pull / push / status for run history on a dedicated branch

## Depends on
none

## Touches
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/vendor-coupling-manifest.json

## Problem
Run history is committed on `main` (368 tracked files under `.supervisor/` at `fdc8a5f`) and a large share of
merges on `main` are metadata-only PRs. Item 03 moves run history to a dedicated unprotected branch; this item
builds the one script that does the moving, with no behaviour change yet.

A naive design — stage the folder into a separate index seeded from the branch tip, restore on pull — was
red-teamed and **fails in four ways** this item must close:
- **No merge base.** A clone holding a stale copy of a file re-stages it over a sibling's newer version (push
  reverts their stamp); pull then overwrites local edits with the reverted copy.
- **Deletions never propagate.** A dropped dismissed draft or a renamed requirement comes back on every pull.
- **`git add -f <dir>` publishes ignored files.** Six nested `.supervisor/` trees with `telemetry.log`,
  `notifications.log`, `.notify-debounce` exist under `.supervisor/requirements/` today, excluded only by
  gitignore rules that `-f` overrides. The repo is public and this branch has no PR and no CI.
- **A missing remote branch exiting 0** recreates the silent-amnesia path (empty folder, run proceeds).

## Goal
One script syncs run-history files between the working folder and a metadata branch as a true 3-way merge with
deletions, over an explicit file list, scrubbed before publishing — without switching branches, touching the code
branch's index, or force-pushing.

## Scope
1. **Managed set = explicit patterns, never a directory add.** One declared list in the script:
   `.supervisor/requirements/**/*.md`, `.supervisor/jobs/done/*.md`, `.supervisor/jobs/failed/*.md`,
   `.supervisor/automate/*.md`, `.supervisor/postmortem/results.jsonl` — minus anything under a NESTED
   `.supervisor/` (`.supervisor/requirements/**/.supervisor/**`). Files are enumerated with `find`/globs and
   staged by explicit path. `git add -f <directory>` is forbidden in this script.
2. **Base tree.** `<gitdir>/meta-base` records the branch tree SHA of the last successful pull or push. Every sync
   is per file, three-way against it (`L` local, `R` remote tip, `B` base):
   - `L == B` ⇒ take `R` (including "absent in `R`" ⇒ delete locally);
   - `R == B` ⇒ take `L` (including "absent locally" ⇒ delete on the branch);
   - `L == R` ⇒ nothing;
   - both changed ⇒ line-union for the declared append-only file (`results.jsonl`) ONLY; for every other file
     exit non-zero with `meta_sync: conflict <path>` and change nothing.
   No mtime comparison anywhere (a restored file's mtime is the pull time).
3. **`meta-sync.sh init [--branch <name>]`** — the ONLY command that may create the branch (empty orphan commit,
   pushed). Refuses when the branch already exists.
4. **`meta-sync.sh pull [--branch <name>] [--root <checkout>]`**
   - `git fetch origin <branch>`; **fetch failure ⇒ exit non-zero**.
   - **Branch absent on the remote ⇒ exit non-zero** `meta_sync: no_remote_branch` (item 03's callers decide what
     that means; this script never treats it as success). A clone whose `origin` is a local path is the common
     cause — say so in the message.
   - Apply the 3-way rules; write files by per-path extraction (`git cat-file`/`git show <tree>:<path>`), never a
     multi-pathspec `git restore` (one absent pathspec makes the whole command fail and restore nothing).
   - Update `meta-base` only after every file was applied.
5. **`meta-sync.sh push [--branch <name>] [--root <checkout>] [--paths-from <file>] [--message <m>]`**
   - Fetch; compute the new tree from `R` plus this checkout's changes per the 3-way rules; build it in a SEPARATE
     index (`GIT_INDEX_FILE=<gitdir>/meta-index`) from `R`'s tree with explicit `update-index` adds/removes;
     `write-tree` → `commit-tree` (parent = `R`) → `git push origin <sha>:refs/heads/<branch>`.
   - `--paths-from` restricts the push to the listed paths (engine callers pass their evidence-gated list — item
     03). Without it, the whole managed set is considered.
   - **Rejected push ⇒ re-fetch, recompute, retry** (bounded, 5 attempts). NEVER `--force`.
   - **Scrub before push, fail CLOSED (exit 2, branch unchanged, path named):** (a) the ledger `.repo` allowlist
     that exists today; (b) a NEW prose scrub over every file being added or changed — e-mail addresses, absolute
     home paths (`/Users/<name>/`, `/home/<name>/`), token-shaped strings, and `owner/repo` slugs not in the
     allowlist. A project may extend the deny patterns in tracked config. Today nothing scans prose — the existing
     "committed twin scrub" is a test with placeholder deny terms; do not present it as a scrub.
   - Nothing to push ⇒ exit 0, `meta_sync: no_changes`.
6. **`meta-sync.sh status`** — one line: `synced <sha>` / `local_ahead <n>` / `remote_ahead` / `conflict <n>` /
   `no_remote_branch` / `unreachable` / `never_synced`. Always exit 0.
7. **Root resolution** mirrors the existing convention (first `git worktree list --porcelain` entry unless
   `--root` is given).
8. **Tests** (`test-meta-sync.sh`, hermetic: bare origin + clones in a temp dir):
   - round trip; code-branch `git status --porcelain` empty after push and after pull;
   - **stale copy:** A changes a file and pushes; B (holding the old copy, untouched) changes a different file and
     pushes ⇒ A's change is still on the branch, and B's next pull gets it;
   - **local edit survives pull:** B edits a file A did not touch; pull leaves it;
   - **deletion:** A deletes a file and pushes ⇒ gone on the branch; B's pull deletes it; it does not come back;
   - **rename:** old path gone, new path present, in both clones;
   - **conflict:** both edit the same non-append file ⇒ non-zero, nothing changed;
   - **`results.jsonl`:** both append ⇒ union, no duplicate lines;
   - **ignored file:** a `*.log` and a nested `.supervisor/logs/x` under `requirements/` are never on the branch
     (`git ls-tree -r` asserts only `.md` + the ledger);
   - **scrub:** a file with an e-mail / home path / foreign slug ⇒ exit 2, branch unchanged;
   - **missing branch ⇒ pull non-zero; `init` creates it; second `init` refuses;**
   - **absent managed path** (no `jobs/failed/`) ⇒ pull succeeds;
   - fetch failure ⇒ pull non-zero; concurrent pushes ⇒ retry, no force.
   **Mutation controls:** staging unmodified files (dropping the base comparison) must fail the stale-copy test;
   replacing the explicit list with a directory add must fail the ignored-file test.
9. **Docs:** §"Metadata branch" in `ARCHITECTURE_CONTRACTS.md` — mechanism, managed patterns, the 3-way table, exit
   codes, and the stated limit that a conflict needs a human.

## Non-goals
Changing `.gitignore`, migrating any file, or calling the script from a hook or the engine (item 03 / M1). Branch
protection (M1). A slash command.

## Acceptance criteria
- Every test in Scope 8 passes under `/bin/bash` 3.2 (macOS) and in CI.
- `grep -nE 'git (checkout|switch|merge)|push .*--force|add -f [^"$]*/( |$)' loomwright/scripts/meta-sync.sh`
  returns nothing.
- After a push from a scratch clone of THIS repo, `git ls-tree -r --name-only <branch> | grep -vE '\.md$|results\.jsonl$'`
  is empty.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on the base and on the branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path:** `git grep -n 'meta-sync' -- loomwright/hooks loomwright/agents loomwright/commands
   loomwright/skills` returns nothing; `git diff --stat origin/main` shows no edit to `.gitignore`, `hooks.json`,
   `automate-helpers.sh` or `automate-trail.sh`.
3. **Running system:** against scratch clones of THIS repo with a throwaway branch on a LOCAL bare remote (never
   GitHub in this item): `init`, `push`, then `pull` in a second clone; paste `git status --porcelain` from both,
   `status`, the `ls-tree | grep -v` line above (empty), and a `diff -r` of the managed files. Then repeat the
   stale-copy and deletion scenarios by hand and paste the branch contents.
4. **A failure this must catch:** the two mutation controls in Scope 8, shown failing.
5. **Rollback:** `git revert`. Nothing calls the script yet.

## Verified premises (re-check before starting)
- `find .supervisor/requirements -type d -name .supervisor | wc -l` → 6 on 2026-10-01, containing log files.
- `.gitignore`'s `.supervisor/*` block is managed by `/setup memory` between sentinels — this item must not edit it.
- The only existing gate is the ledger `.repo` allowlist in `setup-memory.sh`; its consent text says the trail is
  prose and prose is not gated (red-team report — read the text yourself before quoting it).
- Scratch spike 2026-10-01 proved only the happy path; the red-team reproduction (stale copy, deletion, ignored
  file) is the evidence for Scope 1–2 — reproduce it once before designing.

## Status: pending
