# Supervisor Job: meta-sync.sh — 3-way run-history sync on a metadata branch (parallel-automate/02)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean except this run's automate run file (modified), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (installed plugin 15.115.0, repo main at 15.116.0 — sessions run the installed plugin; this item adds a standalone script nothing calls yet, so no engine behaviour is affected)
- **Source requirement:** .supervisor/requirements/parallel-automate/02-meta-sync-script.md
- **Base commit:** be3924519b1e596ecda7674ff851b216b388e9b7

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe + git plumbing (`cat-file`, `ls-tree`, `update-index`, `write-tree`, `commit-tree`) beside the other `loomwright/scripts/*.sh`; same stack. |
| 2 | Dependency Availability | GO | `git`, `bash`, `jq` present; the ledger `.repo` allowlist reader already exists (`loomwright/scripts/setup-memory.sh filter-ledger` / its allowlist resolution). |
| 3 | Architecture Fit | GO | Additive standalone script in the `core` vendor class (`loomwright/scripts/*`); root resolution mirrors `run-lock.sh`'s "resolve root" block; nothing calls it (item 03 / M1 do). |
| 4 | Scope vs Supervisor Capability | CAUTION | One script + one large hermetic test + one doc section; a single worker context, but the test matrix (12 scenarios + 2 mutation controls) is sizeable. One subtask (Single-Agent Path — the only path that works under `/automate`, since `/autonomous` does not forward `--sequential`). |
| 5 | Hard Blockers | CAUTION | The new prose scrub WILL fail closed on this repo's own tracked managed set: 4 tracked files carry absolute home paths (`.supervisor/automate/automate-2026-09-01-232353.md`, `.supervisor/automate/automate-2026-09-26-115755.md`, `.supervisor/jobs/done/2026-09-28-rule-enforcement-at-review-and-merge.md`, `.supervisor/jobs/done/2026-10-01-parallel-automate-01-version-bump-script.md`) and one requirement carries the placeholder slug `github.com/<owner>/<repo>`. That is correct behaviour (exit 2, path named), but the running-system validation must account for it — see Risk Assessment. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `loomwright/scripts/meta-sync.sh` (`init` / `pull` / `push` / `status`) that syncs run-history files between the working folder and a dedicated metadata branch as a true per-file 3-way merge with deletions, over an explicit file list, scrubbed before publishing — without switching branches, touching the code branch's index, or force-pushing — plus its hermetic self-test and an `ARCHITECTURE_CONTRACTS.md` section. No caller is added (item 03 / M1 do that).

**Problem Statement:**
The maintainer (and later the `/automate` engine) needs run history off `main` — 384 tracked `.supervisor/` files at base commit, and many merges on `main` are metadata-only PRs.
A naive separate-index design was red-teamed and fails four ways: no merge base (a stale clone reverts a sibling's newer stamp on push; pull overwrites local edits), deletions never propagate, `git add -f <dir>` publishes ignored logs (7 nested `.supervisor/` trees with `telemetry.log` / `notifications.log` / `.notify-debounce` exist under `.supervisor/requirements/` at base commit — the requirement said 6; one more appeared), and a missing remote branch exiting 0 recreates silent amnesia.
Success looks like: one script whose every sync is per-file 3-way against a recorded base tree, enumerates an explicit managed set, scrubs prose before any push, and fails loudly on a missing branch, a conflict or a scrub hit.

## Acceptance Criteria
- [ ] AC1 (managed set): Given the script's ONE declared list — `.supervisor/requirements/**/*.md`, `.supervisor/jobs/done/*.md`, `.supervisor/jobs/failed/*.md`, `.supervisor/automate/*.md`, `.supervisor/postmortem/results.jsonl` — minus anything under a NESTED `.supervisor/` (`.supervisor/requirements/**/.supervisor/**`), when it enumerates files, then it uses `find`/globs and stages by explicit path only; `git add -f <directory>` never appears (the requirement's `grep -nE 'git (checkout|switch|merge)|push .*--force|add -f [^"$]*/( |$)' loomwright/scripts/meta-sync.sh` returns nothing). That grep also matches comment prose, so the header must not spell those forms (write "no branch switching, no forced push" instead), and the script needs no `merge-base` call.
- [ ] AC2 (3-way base): Given `<gitdir>/meta-base` holding the branch tree SHA of the last successful pull or push (`<gitdir>` = `git rev-parse --git-dir` of the resolved root), when any sync runs, then each managed path is decided per file from `L` (local), `R` (remote tip), `B` (base): `L == B` ⇒ take `R` (absent in `R` ⇒ delete locally); `R == B` ⇒ take `L` (absent locally ⇒ delete on the branch); `L == R` ⇒ nothing; both changed ⇒ line-union for `.supervisor/postmortem/results.jsonl` ONLY (no duplicate lines, deterministic order), and for every other path exit non-zero with `meta_sync: conflict <path>` and change NOTHING (no file written, no ref moved, `meta-base` untouched). Equality is by blob SHA (`git hash-object` vs tree entries) — no mtime comparison anywhere. **No-base rule (owner decision 2026-10-02 — history-aware base):** when `meta-base` is absent (a clone's first sync, reported `never_synced`), `B` is derived per path: for a path absent in `R`, look it up in `R`'s history (`git rev-list` / `git log --format=%H -- <path>` over `R`, reading each historical blob of that path); if `L` equals ANY historical blob, the path was deleted on the branch ⇒ treat `B = L` (pull deletes it locally, push never re-adds it); if `L` differs from every historical blob ⇒ `meta_sync: conflict <path>` (non-zero, nothing changed); if the path never existed in `R`'s history ⇒ `B` = absent (empty tree), so a genuinely new local file is pushed. For a path present in `R` with no base: `L == R` ⇒ nothing; `L` absent ⇒ take `R`; `L` equal to an OLDER blob of that path in `R`'s history ⇒ take `R` (stale copy); `.supervisor/postmortem/results.jsonl` with `L != R` ⇒ line-union (the same exemption as with a base); otherwise conflict. The history walk runs only while `meta-base` is absent. Implementation notes: read historical blobs from the old/new SHA columns of `git log --format= --raw --no-abbrev <R> -- <path>` (never `<commit>:<path>`, which fails at the deleting commit; never `--follow` — the branch is linear: an orphan root plus `commit-tree -p R` commits); bash 3.2 has no associative arrays, so keep per-path lookups in temp files + `grep -F`.

**What `meta-base` records (the merge base for the NEXT sync — deliberate deviation from the requirement's Scope 2 wording "the branch tree SHA of the last successful pull or push", named in the PR body):** `meta-base` is the per-path state that local and remote are KNOWN to agree on, written as its own tree (a second `GIT_INDEX_FILE=<gitdir>/meta-base-index` + `write-tree`; `meta-base` stores that tree SHA). After a successful **pull**, every outcome has been applied locally, so it equals `R`'s tree. After an accepted **push** (which writes nothing to the working tree), it is built per path: a "take L" path ⇒ the pushed `L` (now equal on both sides); `L == R` ⇒ `R`; a "take R" path that push did NOT apply locally ⇒ the PREVIOUS `B` entry for that path (absent stays absent; under the no-base rule, the derived `B`) — so the next pull still sees `L == B, R != B` and takes `R`, and the next push still sees `R != B` and never reverts `R` or deletes a sibling's new file. A `results.jsonl` line-union that push wrote to the branch but not locally ⇒ the local `L` (the next pull then takes the union). Any managed path the push did not consider (outside `--paths-from`) ⇒ its previous `B` entry, or, when there was no `meta-base`, its derived `B` — so after the first sync `meta-base` covers every managed path and the no-base walk never runs again. A conflict, a scrub hit or an exhausted retry leaves `meta-base` untouched. Recording `R`'s branch tree after a push is the bug this rule prevents (Plan Review attempt 2: it re-opens red-team F1 and deletion resurrection).
- [ ] AC3 (`init`): Given `meta-sync.sh init [--branch <name>]` (default branch `loomwright-meta`, owner decision P3), when the branch does not exist on `origin`, then it creates an empty orphan commit (`commit-tree` of the empty tree, no parent) and pushes it; when the branch already exists it refuses non-zero and changes nothing. `init` is the ONLY command that may create the branch.
- [ ] AC4 (`pull`): Given `meta-sync.sh pull [--branch <name>] [--root <checkout>]`, when run, then: `git fetch origin <branch>` failure ⇒ exit non-zero; branch absent on the remote ⇒ exit non-zero `meta_sync: no_remote_branch` (message names a local-path `origin` as a common cause; never treated as success); otherwise applies AC2 writing each file by per-path extraction (`git cat-file -p <blob>` / `git show <tree>:<path>`, never a multi-pathspec `git restore`), and updates `meta-base` only after every file was applied. An absent managed directory (e.g. no `jobs/failed/`) is not an error.
- [ ] AC5 (`push`): Given `meta-sync.sh push [--branch <name>] [--root <checkout>] [--paths-from <file>] [--message <m>]`, when run, then it fetches, computes the new tree from `R` plus this checkout's changes per AC2, builds it in a SEPARATE index (`GIT_INDEX_FILE=<gitdir>/meta-index`, seeded from `R`'s tree via `read-tree`) with explicit `update-index --add --cacheinfo` / `--force-remove` per path, then `write-tree` → `commit-tree -p R` → `git push origin <sha>:refs/heads/<branch>`; the code branch's own index, HEAD and working tree are untouched (`git status --porcelain` of the code branch is byte-identical before and after). `--paths-from` restricts the push to the listed managed paths (unlisted or non-managed paths are ignored, never pushed). A rejected push ⇒ re-fetch, recompute, retry, bounded to 5 attempts, then non-zero — NEVER `--force`. Nothing to push ⇒ exit 0 `meta_sync: no_changes`. `meta-base` is rewritten only after the push is accepted, as the per-path agreed-state tree defined in AC2 — NEVER as `R`'s or the new commit's branch tree.
- [ ] AC6 (scrub, fail CLOSED): Given any file being added or changed by a push, when it is scanned, then a hit exits 2, leaves the branch unchanged and names the path: (a) the existing ledger `.repo` allowlist for `results.jsonl` (reuse `setup-memory.sh`'s allowlist resolution — sibling script via the script's own directory, never a repo-local path); (b) a NEW prose scrub for e-mail addresses, absolute home paths (`/Users/<name>/`, `/home/<name>/`), token-shaped strings — ONLY these anchored, length-bounded patterns, written as portable POSIX ERE (NO `\b`, `\s`, `\w` — GNU-only; on BSD/macOS a non-matching `\b` would make this fail-CLOSED gate silently fail OPEN, cf. the "no GNU-only" note in `test-verify-provides.sh`), with `L='(^|[^A-Za-z0-9_])'` as the leading anchor and no generic "high-entropy" rule, so 40-hex commit SHAs and `sha256:` stamps never hit: `${L}gh[pousr]_[A-Za-z0-9]{36,}`, `${L}github_pat_[A-Za-z0-9_]{22,}`, `${L}sk-[A-Za-z0-9_-]{20,}`, `${L}xox[abp]-[A-Za-z0-9-]{10,}`, `${L}AKIA[0-9A-Z]{16}([^A-Za-z0-9_]|$)` (an unanchored `sk-` already matches ~38 places — `risk-`, `task-` — in 15 tracked managed files, verified by Plan Review) — and forge `owner/repo` slugs (`github.com/<o>/<r>` URLs, and `<o>/<r>` in a `repo:` / `"repo":` field) not in the allowlist. Slug detection is deliberately limited to those forge contexts — a bare `a/b` pattern would match every relative path in the corpus; the script header and the PR body state this limit. The scrub scans EVERY candidate file before deciding and names ALL hits in one run (one `meta_sync: scrub <path>: <rule>` line per hit, never stopping at the first), so a caller can build an exclusion list from the output. A project may extend the deny patterns in TRACKED config (the header names the file/key and that it is data, never executed). The header states plainly that the pre-existing `test-committed-twin-scrub.sh` is a test with placeholder deny terms, not a scrub.
- [ ] AC7 (`status`): Given `meta-sync.sh status`, when run, then it prints exactly one line — `synced <sha>` / `local_ahead <n>` / `remote_ahead` / `conflict <n>` / `no_remote_branch` / `unreachable` / `never_synced` — and always exits 0.
- [ ] AC8 (root): Given no `--root`, when the script resolves its checkout, then it takes the first `git worktree list --porcelain` entry (mirroring `run-lock.sh`'s "resolve root" block, including its `--show-toplevel` sanity check and `$PWD` fallback); `--root` overrides.
- [ ] AC9 (tests): Given `loomwright/scripts/test-meta-sync.sh` (hermetic: first executable line sources `hermetic-test-env.sh` per `scripts/check-test-hermetic.sh`; a bare origin + clones in a `mktemp -d` dir; never GitHub), when run under `/bin/bash` 3.2 (macOS) and GNU bash, then every Scope-8 scenario passes: round trip with code-branch `git status --porcelain` empty after push and after pull; stale copy (A changes+pushes X; B, holding the old untouched X, changes Y and pushes ⇒ A's X still on the branch and B's next pull gets it); local edit survives pull; deletion propagates and does not come back; rename (old gone, new present, both clones); conflict ⇒ non-zero, nothing changed; `results.jsonl` both-append ⇒ union with no duplicate line; ignored file (`*.log` and a nested `requirements/x/.supervisor/logs/y` never on the branch — `git ls-tree -r` asserts only `.md` + the ledger); scrub (e-mail / home path / foreign slug, and a separate positive case for EACH of the five token shapes ⇒ exit 2, branch tip unchanged, every offending path named in one run — run under `/bin/bash` on macOS so a BSD-regex fail-open is caught); **post-push base** (B pushes Y while A's newer X and a sibling's new file Z are on the branch and NOT applied locally ⇒ B's next pull writes A's X and Z; B's push in between neither reverts X nor deletes Z — the AC2 agreed-state rule); **scrub negative case** (clean prose containing `risk-based`, `task-ledger`, a 40-hex commit SHA, a `sha256:` stamp and an allowlisted `github.com/<allowed>/<repo>` URL ⇒ push exits 0); **fresh-clone deletion** (A deletes X and pushes; a NEW clone C with no `meta-base` that still holds the old X runs push ⇒ X is NOT re-added; C's subsequent pull deletes X and C's push after that still does not re-add it; a C-local X edited away from every historical blob ⇒ conflict; a fresh clone whose `results.jsonl` gained lines ⇒ union, not conflict); missing branch ⇒ pull non-zero, `init` creates it, second `init` refuses; absent managed path ⇒ pull succeeds; fetch failure ⇒ pull non-zero; concurrent pushes ⇒ the loser retries and lands without force. **Mutation controls run inside the test as self-checks:** (i) a variant that stages unmodified files (drops the base comparison) MUST fail the stale-copy assertion; (ii) a variant that replaces the explicit list with a directory add MUST fail the ignored-file assertion — the test asserts each control turns red. The script exposes the seam the controls need (e.g. an env var read only by the test), stated in the header and PR body.
- [ ] AC10 (docs): Given `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, when this item lands, then it carries a `## Metadata branch` section (H2, matching the file's all-H2 section convention): the mechanism, the managed patterns, the 3-way table, exit codes (`0` ok / `no_changes`, `1` conflict / no_remote_branch / fetch failure / init refusal / exhausted retries, `2` scrub hit), and the stated limit that a conflict needs a human. The section must not add a literal vendor token (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, `.claude/`); if one is genuinely needed, raise that file's allowance in `loomwright/docs/vendor-coupling-manifest.json` in the same commit and name it in the PR body. `loomwright/scripts/meta-sync.sh` and `loomwright/scripts/test-meta-sync.sh` (both core class, allowance 0) must contain none.
- [ ] AC11 (unchanged path): Given the finished branch, when checked, then `git grep -n 'meta-sync' -- loomwright/hooks loomwright/agents loomwright/commands loomwright/skills` returns nothing, and `git diff --stat origin/main` shows no edit to `.gitignore`, `loomwright/hooks/hooks.json`, `loomwright/scripts/automate-helpers.sh` or `loomwright/scripts/automate-trail.sh`.
- [ ] AC12 (bump, P7): Given this PR, when it is finalized, then its LAST commit is the output of `bash scripts/bump-version.sh` run with this item's own fragment `changelog.d/parallel-automate-02-meta-sync-script.md` (first line `<!-- bump: minor -->`), so the PR carries the new version in all three version files and no fragment remains. Never hard-code a target version.

## Validation (must pass before merge — evidence goes in the PR body)
1. **Baseline:** the full loop (every `loomwright/scripts/test-*.sh`, root `scripts/test-*.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-token-budget.sh`, `scripts/check-doc-currency.sh`) on the untouched base commit AND on the finished branch; record `<passed>/<total>` and the count of `SKIP` lines for both. No existing test may be edited.
2. **Unchanged path:** AC11's two commands, output pasted.
3. **Running system:** against scratch clones of THIS repo with a throwaway branch on a LOCAL bare remote (never GitHub): `init`, `push`, then `pull` in a second clone; paste `git status --porcelain` from both, `status`, the requirement's `git ls-tree -r --name-only <branch> | grep -vE '\.md$|results\.jsonl$'` (empty) and a `diff -r` of the managed files. Because the whole-set push is EXPECTED to exit 2 on real data (at base commit: the 4 home-path files and the `acme/widgets` placeholder — Feasibility #5; the live set may be larger), paste that exit-2 output first as evidence the scrub fires, then build the `--paths-from` exclusion list FROM THAT OUTPUT (never from the list frozen in this brief) and complete the round trip, naming the excluded paths. The PR body notes for M1 that done briefs whose `- **Project:**` line is absolute (this brief's is; most sampled ones use `~/…`) and run files carrying absolute paths will hit the home-path rule. Then repeat the stale-copy and deletion scenarios by hand and paste the branch contents.
4. **A failure this must catch:** the two AC9 mutation controls, shown failing.
5. **Rollback:** `git revert` (nothing calls the script).
6. **Premise reproduction (before designing):** reproduce the red-team failures of the naive design once in scratch (stale copy, deletion, ignored file) and paste the result — the requirement's "Verified premises" demands it.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | meta-sync.sh + hermetic test + ARCHITECTURE_CONTRACTS section + this PR's own bump | all | 4 modify (loomwright/docs/ARCHITECTURE_CONTRACTS.md, CHANGELOG.md, 2 manifests; vendor-coupling-manifest.json only if AC10 requires), 2 create (loomwright/scripts/meta-sync.sh, loomwright/scripts/test-meta-sync.sh) + 1 fragment created then folded | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/commit/SKILL.md` | LAUNCHABLE |

**Fixed in-subtask order (commit after each step):** (a) premise reproduction in scratch (Validation 6, not committed) + baseline loop on base (Validation 1); (b) `loomwright/scripts/meta-sync.sh` + `loomwright/scripts/test-meta-sync.sh` with both mutation controls → test green under `/bin/bash`; (c) `## Metadata branch` in `ARCHITECTURE_CONTRACTS.md` → full loop green on the branch; (d) running-system check (Validation 3) in scratch clones, output kept for the PR body; (e) write `changelog.d/parallel-automate-02-meta-sync-script.md` with `<!-- bump: minor -->`; (f) `bash scripts/bump-version.sh` — its result is the PR's LAST commit.

### Subtask Contracts

```yaml
# Subtask 1 — whole item, single-agent (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/meta-sync.sh"}
  - {kind: "file", path: "loomwright/scripts/test-meta-sync.sh"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "meta_sync: no_remote_branch"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "GIT_INDEX_FILE"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "meta-base"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "Metadata branch"}
requires: []
lanes:
  - "loomwright/scripts/meta-sync.sh"
  - "loomwright/scripts/test-meta-sync.sh"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "changelog.d/*.md"
  - "CHANGELOG.md"
  - ".claude-plugin/marketplace.json"
  - "loomwright/.claude-plugin/plugin.json"
external_requires:
  - "git plumbing (cat-file, ls-tree, read-tree, update-index, write-tree, commit-tree), jq, bash 3.2 (macOS) and GNU bash (CI)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The scrub fails closed on this repo's own tracked managed set — 4 home-path files + the `github.com/<owner>/<repo>` placeholder (Feasibility (Phase 2.5) #5) | HIGH | Correct behaviour, not a bug: Validation 3 shows the exit-2 output on real data FIRST, then completes the round trip with `--paths-from` excluding exactly those named paths. Cleaning them is M1's (operator) job — the PR body lists them for M1. Never weaken the scrub to make the real-data push green. |
| Slug detection over-matching: a bare `owner/repo` regex matches every relative path (`loomwright/scripts`) in the corpus | HIGH | AC6 limits slug detection to forge contexts (`github.com/<o>/<r>` URLs, `repo:` / `"repo":` fields); the header and PR body state the limit honestly. The allowlist (`vikashruhilgit/ai-agent-manager`, `vikashruhilgit/loomwright` in `.supervisor/config.json`) must make this repo's own 529 forge URLs pass. |
| Token-pattern over-matching: a loose secret rule (unanchored `sk-`, a generic entropy rule) flags `risk-`/`task-` prose, commit SHAs and `sha256:` stamps across the corpus (Plan Review, attempt 1) | MEDIUM | AC6 pins five anchored, length-bounded regexes and forbids a generic entropy rule; AC9's scrub negative case asserts clean prose with those shapes exits 0. |
| `meta-base` set to the branch tree after a push that applied nothing locally ⇒ the next sync reverts a sibling's change (F1) or resurrects a deletion (Plan Review attempt 2, HIGH) | HIGH | AC2/AC5 define `meta-base` as the per-path agreed-state tree (separate index + `write-tree`); AC9's post-push-base case asserts it; the PR body names the deliberate deviation from Scope 2's wording. |
| Scrub regexes failing OPEN on BSD/macOS via GNU-only `\b` (Plan Review attempt 2) | MEDIUM | AC6 mandates portable POSIX ERE anchors; AC9 runs a positive case per token shape under `/bin/bash` on macOS. |
| Deleted files resurrected by a clone's first sync (no `meta-base`) (Plan Review, attempt 1) | MEDIUM | AC2's history-aware no-base rule (owner decision 2026-10-02) plus AC9's fresh-clone deletion case. |
| Test matrix size in one worker context (Feasibility (Phase 2.5) #4) | MEDIUM | The fixed in-subtask order commits after each step, so a turn-limit stop resumes from a clean committed point (resume the worker via SendMessage, never respawn). |
| bash 3.2 / BSD vs GNU userland (`sed -i`, `mktemp`, `stat`, `find -printf`, empty arrays under `set -u`) | MEDIUM | No `sed -i`, no `find -printf`, no `stat`; temp file + `mv`; guard `"${arr[@]}"` under `set -u` (project memory `[ead04b14]`); run the test under `/bin/bash` on macOS and note CI (Ubuntu) parity. |
| Gitignored paths: `.supervisor/` is ignored with a `.gitignore` un-ignore block managed by `/setup memory` | MEDIUM | Plumbing (`update-index --add --cacheinfo` into the separate index) never consults `.gitignore`, so the managed set is decided ONLY by the declared list + nested-`.supervisor/` exclusion. `.gitignore` is not edited (non-goal, AC11). |
| Concurrent-push retry correctness: a retry must recompute from the NEW `R` and the unchanged `B`, never from the previous attempt's tree | MEDIUM | Each attempt re-fetches and rebuilds the separate index from scratch; the concurrent-push scenario in AC9 asserts both writers' changes land. |
| `results.jsonl` union ordering | LOW | Union keeps `R`'s lines in order and appends `L`'s new lines in local order; the test asserts no duplicate and both sides present. |
| The bump version depends on `main` at bump time (lesson `[6e0baac1]`) | LOW | The bump is the LAST commit and reads the live `plugin.json`; if `main` moves before merge, drop the bump commit (restores the fragment), rebase onto `main`, re-run `bash scripts/bump-version.sh`. |
| `ci.yml` wiring is not needed: `loomwright/scripts/test-*.sh` is auto-globbed by CI (project memory `[16474355]`) | LOW | No workflow edit (a workflow edit would also make `claude-code-action` skip its review). |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-02-parallel-automate-02-meta-sync-script.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-02T04:26:01Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/334
- **Branch:** feature/parallel-automate-02-meta-sync-script
- **Files changed:** 6
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** meta-sync.sh + hermetic test + ## Metadata branch doc + v15.117.0 bump (re-run after rebasing onto #331). Phase 4.5 ran 3 review→fix iterations; each fix verified by the next review's repros, each review found new hardening edge cases; iteration-3 fix (59ad2ad, 2 HIGH: dir-at-managed-path fake write; unscoped fail-closed find) is NOT LLM re-reviewed. Ground truth 2/2; risk high_risk=true. Default drain suppressed by /automate (auto_review=false) — the engine owns the drain.

## Not verified
- **meta-sync.sh and test-meta-sync.sh under GNU/Linux userland (CI Ubuntu)** — only run on macOS (BSD userland) under /bin/bash 3.2 and GNU bash 5.3 (subtask 1)
- **meta-sync.sh against a real forge remote (GitHub)** — by design: Validation 3 limited to local bare remotes (subtask 1)
- **iteration-3 heal fix 59ad2ad** — final heal iteration, not LLM re-reviewed (fix-3)
