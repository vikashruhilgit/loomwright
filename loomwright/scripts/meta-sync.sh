#!/usr/bin/env bash
# meta-sync.sh — sync run-history files between this checkout's working folder and a dedicated
# metadata branch on `origin`, as a per-file 3-way merge with deletions, over an explicit file list,
# scrubbed before anything is published. No branch switching, no forced push, and the code branch's
# own index, HEAD and working tree are never touched: the branch side lives entirely in git plumbing
# (a SEPARATE index file, write-tree, commit-tree, a refspec push).
#
# Usage:
#   meta-sync.sh init   [--branch <name> [--allow-branch-mismatch]] [--root <checkout>]
#   meta-sync.sh pull   [--branch <name> [--allow-branch-mismatch]] [--root <checkout>]
#   meta-sync.sh push   [--branch <name> [--allow-branch-mismatch]] [--root <checkout>] [--paths-from <file>] [--message <m>]
#   meta-sync.sh status [--branch <name> [--allow-branch-mismatch]] [--root <checkout>] [--paths] [--learning]
#   meta-sync.sh scrub  --paths-from <file> [--root <checkout>]
#   meta-sync.sh list-managed [--tracked | --tree <tree-ish>] [--run-history] [--root <checkout>]
#   meta-sync.sh -h | --help
#
#   scrub         a DRY RUN of push's scrub over the files listed in --paths-from (read from the
#                 working tree under --root; required). One stderr line per hit (`scrub-hit`, see
#                 SCRUB below); exit 2 on any hit, 0 when clean (`meta_sync: clean (<n> file(s)
#                 scanned)` on stdout), 1 on a usage error. Writes nothing, takes no lock, fetches
#                 nothing.
#   list-managed  print every path the managed-set predicate (is_managed) accepts, one per line,
#                 LC_ALL=C-sorted, exit 0. Default: the local working folder, enumerated exactly as
#                 pull / push enumerate it (so it fails closed — exit 1 — on the same symlink /
#                 unsearchable-root / newline-name hazards). --tracked: the paths `git ls-files`
#                 lists instead (the index). --tree <tree-ish>: the managed entries of that tree
#                 (read exactly as pull / push read a branch tree — a newline name or a failed
#                 read exits 1). --run-history (with any source): RUN-HISTORY paths only — every
#                 LEARNING-STORE path (see MANAGED SET) is dropped, so a caller can tell the two
#                 classes apart without a second list. Writes nothing, takes no lock, fetches nothing.
#   scrub and list-managed need NO branch: they skip the mode / branch check below (so they work in
#   a checkout whose mode reads `unknown`), and --branch / --allow-branch-mismatch given to them is
#   a usage error (exit 1) — never silently accepted and ignored.
#
#   --branch      metadata branch on `origin`. Default: the branch the checkout's MODE LINE names,
#                 read through the sibling `setup-memory.sh --root <root> mode` (the ONE mode-line
#                 reader; this script never parses .gitignore itself): `on <Y>` => Y; `off` =>
#                 loomwright-meta; `unknown <reason>` — or ANY other reader answer (empty output, a
#                 non-zero exit, a missing sibling, a multi-line or unrecognised line) => exit 1
#                 `meta_sync: mode_unknown — <reason>; nothing was changed` (fail closed).
#                 Given explicitly, it must AGREE with the mode: `on Y` with Y != <name> => exit 1
#                 `meta_sync: branch_mismatch` naming both; `off` => <name> is used; `unknown` =>
#                 exit 1 `mode_unknown`. The check runs for init, pull, push and status (never for
#                 scrub / list-managed), right after the root is resolved and BEFORE any lock, fetch
#                 or write (nothing is changed on a refusal).
#   --allow-branch-mismatch
#                 use the given --branch even when the mode line disagrees or reads `unknown` (the
#                 mode is then not consulted). Without --branch it is a usage error (exit 1).
#   --root        checkout to sync (default: the FIRST `git worktree list --porcelain` entry, i.e. the
#                 main checkout, with a --show-toplevel sanity check and a $PWD fallback — the same
#                 "resolve root" block run-lock.sh uses)
#   --paths-from  push only the managed paths listed in <file> (one repo-relative path per line;
#                 blank and `#` lines ignored; unlisted or non-managed paths are never pushed).
#                 For scrub: the files to scan (same format; every listed path is scanned, managed
#                 or not). push and scrub ONLY: given to init / pull / status / list-managed it is a
#                 usage error (exit 1, nothing changed) — never silently accepted and ignored
#   --tracked     list-managed ONLY (a usage error elsewhere): list from `git ls-files`
#   --tree        list-managed ONLY (a usage error elsewhere, and with --tracked): list that tree
#   --run-history list-managed ONLY (a usage error elsewhere): drop the learning-store paths
#   --paths       status ONLY (a usage error elsewhere): after the status line, name the paths it
#                 counts — see STATUS below
#   --learning    status ONLY (a usage error elsewhere): add the ONE learning-store line — see
#                 STATUS below
#   --message     commit message for the metadata-branch commit
#
# MANAGED SET — the ONE declared list (is_managed below); everything else is invisible to this script:
#   .supervisor/requirements/**/*.md
#   .supervisor/jobs/done/*.md
#   .supervisor/jobs/failed/*.md
#   .supervisor/automate/*.md
#   .supervisor/automate/<name>.dismissed-decisions   (top level only; the dismissed-findings decision
#     ledger — TSV of draft names, no home paths — so a lane's decisions survive lane-remove;
#     parallel-automate/05 D9; scrubbed like every other added file)
#   .supervisor/postmortem/results.jsonl
#   LEARNING STORES (the stores agents read back to decide better; published only with the
#   user-scope consent — see CONSENT below — and never synced at all while git tracks them here —
#   see TRACKED LEARNING STORES below; every other managed path is RUN HISTORY):
#   .supervisor/twin/contracts/*.md                    (top level only) ┐ the TWIN SET — synced
#   .supervisor/twin/.provenance.jsonl                                  ┘ together (see TWIN SET)
#   .supervisor/agent-memory-proposals/*.md            (top level only)
#   .supervisor/eval/results.jsonl
#   .supervisor/eval/brain-baseline.jsonl
#   NOT managed: .supervisor/worker-summaries/ (named `{subtask_id}.md` and rewritten per run, so
#   two machines would conflict routinely — a follow-up first gives them unique names).
#   minus anything under a NESTED .supervisor/ (.supervisor/requirements/**/.supervisor/**),
#   and minus every NON-CANONICAL path (an absolute path, or one with a `.` / `..` / empty segment).
#   Branch trees are untrusted input (anyone who can push the branch can mktree any entry name);
#   a `.supervisor/requirements/../../CLAUDE.md` entry must never be joined to the root and
#   written or deleted, so it is simply not a managed path (pull ignores it; push fails closed,
#   because git's read-tree refuses such a tree).
# Local files are enumerated with `find` over the managed roots ONLY (requirements/ with nested
# .supervisor/ trees pruned; the top level of jobs/done, jobs/failed, automate, postmortem, twin,
# twin/contracts, agent-memory-proposals and eval — a root's parent is listed before it), so
# churn or an unreadable folder elsewhere under .supervisor/ (logs, worktrees) never blocks a sync;
# an unsearchable managed root or folder on the way to one, or a find error inside a root, fails
# closed. Matches are filtered through that list; each one is staged into the
# separate index by explicit path (update-index --cacheinfo). No directory is ever added, so a log or
# a nested `.supervisor/` tree that .gitignore hides can never reach the branch: the separate index
# never consults .gitignore, which is exactly why the list — not .gitignore — decides membership.
# SYMLINKS fail closed: a symlink where run history lives (`.supervisor` itself, a folder on the
# way to a managed folder, a managed file, or — under requirements/ — any symlink that resolves to
# a DIRECTORY or is DANGLING, since either could hold managed .md files) makes pull and push
# exit 1 naming it (`meta_sync: symlink <path>`), nothing changed — find does not descend it, so its
# files would read as deleted (a push would delete them from the branch) and a pull would write
# through it out of .supervisor/. A symlink under requirements/ that resolves to a regular FILE at a
# non-managed path (e.g. `requirements/q/design.png`) can neither hide managed files nor be written
# through, so it is ignored like any other non-managed file (never synced, never refused). Pull
# also re-checks every path it writes or deletes (no symlinked
# component; the parent resolves physically under <physical root>/.supervisor/). Symlinks elsewhere
# under .supervisor/ (logs, nested .supervisor/ trees) are not managed and are ignored. Every git
# read that feeds a decision or a write (ls-tree, log, hash-object, cat-file) fails closed: a read
# that fails is never treated as an empty tree, an absent file or an empty side of a union.
# A DIRECTORY (or other non-regular file) at a managed path where the branch holds a file fails
# closed the same way (`meta_sync: not_a_file <path>`, exit 1, nothing changed): it reads as locally
# absent, so a pull would rename the file into it and a push would delete the branch file.
# A NEWLINE in a name fails closed too (`meta_sync: newline_in_path <where>`, exit 1, nothing
# changed, meta-base untouched): every listing is read NUL-delimited (ls-tree -z, log -z, diff-tree
# -z, find -print0) and parsed line by line, so an embedded newline would split one entry into two
# and could fabricate a managed record (a mktree'd directory named `x<LF>100644 blob <sha><TAB>
# .supervisor` yields a fake `.supervisor/requirements/...` line). Records are NUL-separated, so ANY
# newline byte in the raw stream is inside a name: the remote tree, the meta-base tree, R's history
# (a fresh clone stays refused until the branch history is rewritten — a human decision), the
# push's tree_guard diff, and every name under a managed root locally are all refused on sight.
#
# 3-WAY RULE (per path; equality is by blob SHA — `git hash-object --no-filters` vs tree entries,
# never mtime). L = this checkout, R = the remote branch tip, B = the merge base read from
# `<gitdir>/meta-base` (a tree SHA bound to its branch — see BRANCH BINDING; `<gitdir>` =
# `git rev-parse --git-dir` of the resolved root):
#   L == R             -> nothing
#   L == B             -> take R   (R absent => delete locally)
#   R == B             -> take L   (L absent => delete on the branch)
#   both changed       -> a UNION PATH (the union-path predicate is_union in compute_plan — the
#                         postmortem ledger .supervisor/postmortem/results.jsonl, the two eval
#                         files .supervisor/eval/results.jsonl and .supervisor/eval/brain-baseline
#                         .jsonl, and every .supervisor/automate/<name>.dismissed-decisions):
#                           the three .jsonl files: line-union (R's lines unchanged, including
#                           repeats inside R, then the L lines not present in R in local order —
#                           never a global dedupe);
#                           a .dismissed-decisions ledger: an ORDERED union (ordered_merge) — every
#                           distinct line kept once; `summary-member<TAB><h8><TAB><slot>` rows are a
#                           set and come first; decision rows `<draft><TAB><decision><TAB><ts>` follow,
#                           sorted by their ISO-8601 ts (stable: ties keep R's rows first), so the
#                           reader's last-row-wins yields the time-latest decision per draft (a row
#                           whose third field is not an ISO-8601 timestamp sorts with the set rows,
#                           i.e. as the oldest);
#                         the TWIN SET (.provenance.jsonl and every contract — never a union path):
#                           the whole twin set is REFUSED (see TWIN SET), run history still syncs;
#                         any other path (every .md, the agent-memory proposals included):
#                           `meta_sync: conflict <path>`, exit 1, NOTHING changed. A conflict needs
#                           a human.
#
# NO meta-base (a clone's first sync; `status` says never_synced) — B is derived per path from R's
# history, read from the old/new blob columns of `git log --no-renames --format= --raw --no-abbrev`
# (never `<commit>:<path>`, which fails at the deleting commit; the branch is linear, an orphan root
# plus `commit-tree -p R` commits, so no rename following is needed):
#   path absent in R, existed in R's history:  L equals ANY historical blob => deleted on the branch
#                                              (B = L: pull deletes it, push never re-adds it);
#                                              otherwise conflict
#   path absent in R, never in R's history:    B absent => a genuinely new local file is pushed
#   path present in R:  L == R => nothing; L absent => take R; L equals an OLDER blob => take R
#                       (stale copy); a union path with L != R => its union (above); otherwise
#                       conflict
# The derivation always covers the WHOLE managed set (even under --paths-from) and any conflict
# anywhere aborts, because the meta-base written afterwards must cover every managed path — with
# ONE exception, the twin set: a twin conflict refuses the twin set instead of aborting, and the
# meta-base then keeps every twin path's PREVIOUS entry (absent when it had none), so no refused
# twin path is ever recorded as agreed and the next sync re-derives — and re-refuses — it (see
# TWIN SET). The history walk runs only while meta-base is absent (or to verify a legacy base,
# below).
#
# BRANCH BINDING — meta-base is two lines: the agreed-state tree SHA, then `branch <name>`, the
# branch it was recorded against (written together by one atomic rename, under the lock). A base
# is only ever used to plan a sync of ITS OWN branch:
#   - bound to another branch (a mode-line switch, or a forced --branch X --allow-branch-mismatch)
#     => pull / push exit 1 `meta_sync: base_branch_mismatch` naming both branches, up front (after
#     the lock, before any fetch); nothing written, nothing published, meta-base untouched; status
#     prints `base_branch_mismatch`. Refused, never treated as "no base": the no-base derivation
#     itself deletes (a path the target branch once held at L's blob), so it must not run silently
#     over a working folder that was synced against a different branch. Recovery is a human act:
#     sync the base's own branch with --branch, or remove meta-base by hand to make the target
#     branch a first sync.
#   - LEGACY single-line meta-base (written before the binding existed; no branch recorded) =>
#     adopted for the target branch only when EVERY (path, blob) entry it holds is one the target
#     branch's own history held (it then provably was not taken from another branch), and the
#     next write binds it; otherwise `base_branch_mismatch`, nothing changed. Honest limit: a
#     legacy base whose last push wrote a ledger union holds the LOCAL ledger blob, which the
#     branch never held, so it is refused too (remove it by hand once).
#   - unreadable, or in no recognised format (a third line, a line 2 that is not `branch <name>`)
#     => `base_branch_mismatch`, nothing changed. An empty file, or a bound / legacy base whose
#     tree object is missing, keeps the missing-object fallback below (the no-base derivation).
#
# WHAT meta-base RECORDS — the per-path state local and remote are KNOWN to agree on, written as its
# own tree (a second, per-run index file under this run's temp dir + write-tree). This deliberately
# differs from "the branch tree of the last pull or push":
#   - after a pull every path either now holds R locally or is a take-L path where R == B, so R's
#     tree is the agreed base;
#   - after an accepted push (which writes nothing to the working tree) it is built per path: a
#     pushed take-L path => the pushed L; L == R => R; a take-R path the push did NOT apply locally
#     => the PREVIOUS B entry (or the derived B), so the next pull still takes R and the next push
#     never reverts R or deletes a sibling's new file; a union (any union path) the push wrote to
#     the branch but not locally => the local L; any managed path the push did not consider
#     (outside --paths-from, a learning-store path skipped for want of consent, or a learning-store
#     path left to git because it is tracked) => its previous / derived B;
#   - after a pull or push that REFUSED the twin set it is per-path for the twin set: every twin
#     path keeps its PREVIOUS base entry (absent when it had none) while every other path is
#     recorded as above — so a pull no longer records R's tree wholesale then. Recording R for a
#     refused twin path would make it look agreed: the next push would delete the branch's
#     contracts this checkout never received and overwrite the branch's provenance chain.
#   - after a pull that LEFT a tracked learning path to git (TRACKED LEARNING STORES) the same
#     per-path rule holds for that path: it keeps its PREVIOUS base entry (absent when it had none),
#     never R's — recording R would make a later sync (once git stops tracking it) read the local
#     copy as the newer side and push it over the branch's, dropping a sibling's lines.
#   Recording R's (or the new commit's) branch tree after a push would make the next sync revert a
#   sibling's newer change or resurrect a deletion. A conflict, a scrub hit or an exhausted retry
#   leaves meta-base untouched. refs/meta-sync/base points at the same tree purely as a gc anchor
#   (the tree and its blobs are otherwise unreachable and `git gc` would prune them); if the object
#   is ever missing anyway, the script falls back to the no-base derivation with a warning.
#
# TWIN SET (.supervisor/twin/contracts/*.md + .supervisor/twin/.provenance.jsonl) — a contract is
# only valid beside its provenance chain, so the twin set syncs as a whole on the side being
# written (pull: the working folder; push: the branch) or not at all:
#   - PAIR RULE: when the sync would change the twin set on that side, its post-state is checked
#     with the SAME chain rules read-system-contract.sh applies (`GENESIS` is the first prev_hash;
#     each later prev_hash is the sha256 of the previous raw line, blank lines skipped, the walk
#     stops at the first break; a contract is valid only when the sha256 of its bytes is the
#     content_hash of a chain-valid `add`). A contract that would lack one is a pair-rule break.
#   - FORK: both sides changed .provenance.jsonl since the meta-base (or any twin path conflicts)
#     — never a line-union: two chains cannot be merged.
#   Either one REFUSES THE TWIN SET as a whole on that side — no twin path written or deleted,
#   every offending path named on stderr, one line each:
#     `meta_sync: twin_refused <path>: <reason>`   (reason: conflict | no chain-valid add
#                                                   provenance entry | no sha256 tool)
#   — while run history and the other learning stores still sync, and the exit code is the one
#   run history alone gives (meta-entry, lane pulls and migrate-branch-mode.sh treat any non-zero
#   exit as failure). meta-base keeps every twin path's previous entry (WHAT meta-base RECORDS),
#   so the next pull or push on the same divergence re-refuses; it never deletes the other side's
#   contracts nor overwrites its chain. Manual resolution: keep ONE side's chain — discard the
#   local twin set and pull, or take the branch's and re-append locally — then run
#   reprovenance-twin-contracts.sh --confirm only to re-bless contract bodies left without a chain
#   entry (it is the recovery path for bodies changed outside write-system-contract.sh, not a
#   chain merger).
#
# CONSENT (push only; pull takes learning-store paths from the branch whatever the consent — except
# a path git tracks, which neither side touches: TRACKED LEARNING STORES below) — the metadata
# branch can be PUBLIC and the learning stores hold internal reasoning the scrub only
# pattern-checks, so a push publishes them only when this repo's user-scope record says
# `granted`. The record lives in the user's scope (one JSON file — setup-memory.sh header: CONSENT names it — keyed by origin's
# owner/repo, else the literal origin URL) and is written ONLY by `setup-memory.sh consent grant |
# decline` (asked by `/setup memory`); this script only READS it, through `setup-memory.sh consent
# status` (the one reader — it never asks). Anything but an exact `granted` — no record,
# `declined`, an unreadable record, a missing reader — fails toward NOT publishing: every learning
# path the push would add, change or delete is skipped and named,
#   `meta_sync: learning_skipped <path> — no consent (run /setup memory)`
# its meta-base entry stays the previous one (a skipped path is unconsidered), run history still
# pushes, and the exit code is the one run history alone gives. (A CONFLICT is not a publish: a
# conflicting proposal .md still aborts like any .md, and a twin conflict refuses the twin set.)
# HONEST LIMIT — that abort ignores consent: an agent-memory proposal .md both sides changed (or,
# with no meta-base, one matching no branch-history blob) makes pull AND push exit 1 `conflict`,
# nothing changed — so meta-entry's pull (every /automate start or resume) is blocked by a store
# this machine may have declined to publish, and a trail-pr --paths-from push by a proposal it
# never listed. Manual resolution: make the two sides agree (`git show origin/<branch>:<path> >
# <path>`, merging any local edit in by hand), then re-run. Follow-up candidate: extend the twin
# set's hold-don't-abort rule to the other non-union learning stores.
# The record is read only when a push would publish a learning path, so a run-history-only push
# (trail-pr, lanes) never reads it.
#
# TRACKED LEARNING STORES — git owns a learning-store path this checkout's git index tracks (a repo
# that committed its eval file, twin contracts or proposals on its code branch; the migration never
# untracks one — migrate-branch-mode.sh lists it as an OWNER DECISION extra). Two owners of one
# file would fight: a pull that wrote the branch's copy into a tracked file would dirty the code
# branch's working tree on every sync (after-merge's and rollback's clean-tree preconditions then
# fail). So pull AND push leave every such path alone — never written, deleted, merged, published,
# reported as a conflict or as `learning_skipped` — and name each on stderr, one line per path:
#   `meta_sync: learning_tracked <path> — tracked by git, left to git`
# plus one summary line; its meta-base entry stays the PREVIOUS one (absent when it had none, the
# twin-set refusal's rule — WHAT meta-base RECORDS), so no later sync deletes the branch copy or
# overwrites the local file because of it. The index is read with `git ls-files -z` over the
# learning roots — with the caller's GIT_INDEX_FILE / GIT_DIR / GIT_WORK_TREE cleared, since git
# reads an inherited GIT_INDEX_FILE naming a missing file as an EMPTY index with exit 0 ("nothing
# tracked", a fail-open) — and fails closed (exit 1, nothing changed) when it cannot be read.
# RUN HISTORY is never looked up: a tracked run-history path keeps the 3-way rule above unchanged
# (run history is meant to be untracked in branch mode; that is what the migration does). The exit
# code stays the one run history alone gives. A tracked path the pair rule needs (TWIN SET) is read
# as it stands locally (pull) or on the branch (push). list-managed is unaffected (it lists, it
# never syncs).
#
# PULL — fetch, decide per path, leave every tracked learning path to git (TRACKED LEARNING
# STORES), refuse the twin set if it must be (TWIN SET), refuse on any other
# conflict / not_a_file / containment failure, then write. Every UNION (the three .jsonl union
# paths and the ordered .dismissed-decisions merge) is built and renamed into place BEFORE any
# take-R write or delete: the union re-reads the working file and fails closed when it no longer
# hashes to the planned L (`<path> changed during the sync`), and because it runs first such a
# refusal leaves every other managed file untouched and meta-base unchanged. Every file pull
# writes — .supervisor/twin/.provenance.jsonl included — gets FILE_MODE (0666 & ~umask), the mode
# a plain `>` gives it; write-system-contract.sh sets no mode either.
#
# PUSH — fetch, decide per path (a tracked learning path is left to git and never published —
# TRACKED LEARNING STORES), build the new tree in a SEPARATE index (a per-run GIT_INDEX_FILE
# under this run's temp dir — never a fixed name in the shared gitdir — seeded from R's tree via
# read-tree) with explicit per-path update-index adds/removes, write-tree -> commit-tree -p R ->
# refspec push of that commit to refs/heads/<branch>. Before commit-tree the new tree is checked
# against the plan: `git diff-tree -r` from R's tree must touch ONLY the selected take-L / union
# paths, otherwise exit 1 `tree_guard` and nothing is pushed (a lost or foreign index can never
# publish a tree that deletes paths the plan did not choose). A rejected push re-fetches,
# recomputes from the NEW R and the unchanged B, and retries — at most 5 attempts, never forced.
# Nothing to push => exit 0 `meta_sync: no_changes`.
#
# LOCK — `pull` and `push` (the only commands that write local files or meta-base) hold
# `<gitdir>/meta-sync.lock` (an atomic `mkdir` holding the holder's pid) for their whole run; every
# worktree defaults to the same --root, so they serialise there. A holder whose pid is dead (or a
# pid-less lock older than a minute) is reclaimed — by exactly ONE waiter per observed holder: the
# one whose `mkdir <lock>.reclaim.<pid>` succeeds; inside that marker it re-reads the pid and
# removes the lock only if it still carries that dead pid. A waiter never renames a lock aside, so
# it can never move a live holder's lock and let a second process in. A live holder is waited for
# up to META_SYNC_LOCK_WAIT_SECS (default 120), then exit 1 `locked`, nothing changed. A live
# lock is released only by its holder, on every exit path (EXIT trap; HUP/INT/TERM exit through
# it). Residual assumption: a pid is not recycled while its dead lock is being reclaimed.
# `status`, `init`, `scrub` and `list-managed` take no lock: status reads meta-base (always
# replaced by an atomic rename), scrub and list-managed read only the working tree / index, and
# none writes anything shared; all scratch state (index files, temp files) is per-run.
#
# SCRUB (push, fail CLOSED: exit 2, branch and meta-base unchanged; also the `scrub` dry run, below). EVERY file being added or
# changed is scanned before deciding and EVERY hit is named in one run, one line per hit:
#   `meta_sync: scrub <path>: <rule>` — so a caller can build a --paths-from exclusion list from it
#   (no other output line starts with `meta_sync: scrub `; the final summary starts `meta_sync: aborted`).
#   The `scrub` SUBCOMMAND (a dry run over --paths-from, working-tree files) runs the SAME rule table
#   through the same scan_file — the hit/no-hit decision is the same grep push runs — and names
#   each hit on stderr with a NEW prefix, so the push line above stays byte-for-byte:
#     `meta_sync: scrub-hit <path>:<line>: <rule>`
#   <line> is the first matching 1-based line for the line-based rules (email, home_path, token_*,
#   deny_pattern:<n>) and a literal `-` for the whole-file rules (forge_slug, ledger_repo,
#   ledger_unverifiable…, unreadable — a listed path that is missing or not a readable regular file
#   —, scan_error(<rule>), deny_pattern_invalid:<n>). `meta_sync: scrub-hit` does not start with
#   `meta_sync: scrub ` (a hyphen, not a space), so a parser of push's line never sees it. The
#   summary on a hit starts `meta_sync: aborted`; exit 2.
#   (a) ledger: every results.jsonl record's `.repo` must be in the repo allowlist resolved by the
#       sibling setup-memory.sh (`allowlist`); a missing/unparseable `.repo` is a hit;
#   (b) prose, portable POSIX ERE only (no GNU-only escapes — on BSD grep those would silently match
#       nothing and this fail-CLOSED gate would fail OPEN):
#         email          e-mail addresses (any letter case). ONE exemption, exact: the `git` SSH user
#                        at a forge_slug host in the scp-style remote form — `git@github.com:`,
#                        `git@gitlab.com:`, `git@bitbucket.org:`, all lowercase, trailing `:` required
#                        (git@github.com:owner/repo is a remote, not a mailbox). The whole match must
#                        be that string, so `someone@github.com`, `xgit@github.com:`, `git@example.com`,
#                        `git@github.company.com:`, a colon-less `git@github.com` and any other case
#                        still hit, and a real address on the same line still hits. The slug after
#                        the `:` is still checked by forge_slug.
#         home_path      absolute home paths: /Users/<name>/ and /home/<name>/ (any letter case —
#                        macOS paths are case-insensitive), where <name> is any run of letters, digits,
#                        `.`, `_` or `-`. ANCHORED: the `/` must start the line or follow a character
#                        that cannot end a path segment (anything but a letter, digit, `_` or `-`), so
#                        `--state-dir /Users/x/`, `HOME=/Users/x/`, `"/home/x/`, `file:///Users/x/`,
#                        `C:/Users/x/` and `../Users/x/` hit, while an API route's `/api/users/42/` (the
#                        `/users` follows the segment `api`) does not. A placeholder in angle brackets
#                        (`/Users/<name>/`) never hits: `<` is outside the name class.
#         token_github   gh[pousr]_ + 36+ chars       token_github_pat  github_pat_ + 22+ chars
#         token_sk       sk- + 20+ chars              token_slack       xox[abp]- + 10+ chars
#         token_aws      AKIA + 16 upper/digits
#       Token rules are anchored with a leading non-word boundary and length-bounded; there is NO
#       generic high-entropy rule, so 40-hex commit SHAs and `sha256:` stamps never hit. Token
#       prefixes are matched case-SENSITIVELY on purpose: issuers emit them in exactly one case.
#         forge_slug     an owner/repo NOT in the allowlist, detected ONLY in forge contexts:
#                        github.com / gitlab.com / bitbucket.org URLs (host in any letter case),
#                        and a `repo` field in any letter case with the key and the value bare or
#                        wrapped in double, single or back quotes (repo: a/b, "Repo": "a/b",
#                        'repo': 'a/b'). A bare `a/b` is deliberately NOT a slug (every relative path would
#                        match) — that is a stated limit of this scrub, not complete coverage. URL
#                        first segments that are forge-reserved words (apps, orgs, settings, …)
#                        are not owners and are skipped, as is an all-dot placeholder segment
#                        (github.com/.../pull). An EMPTY allowlist makes every slug a hit.
#   Project extension: TRACKED file `.agent/meta-sync-deny.txt` — one extra POSIX ERE per line
#   (blank and `#` lines ignored). It is DATA handed to `grep -E -e`, never executed or eval'd; an
#   invalid pattern is itself a hit (fail closed). Rule name: `deny_pattern:<line>`.
#   Note: loomwright/scripts/test-committed-twin-scrub.sh is a TEST with placeholder deny terms over
#   the committed Twin stores — it is not a scrub and does not gate this branch.
#
# STATUS prints exactly one first line and always exits 0 once the branch is resolved: `synced
# <sha> on <branch>` | `local_ahead <n>` | `remote_ahead` | `conflict <n>` | `no_remote_branch` |
# `unreachable` | `never_synced` | `base_branch_mismatch`. (A branch_mismatch / mode_unknown /
# usage refusal happens before status runs and exits 1.) The first line counts RUN-HISTORY paths
# only: every learning-store path is left out of the conflict, take-L / union and take-R counts
# alike, so a learning-only difference (a twin provenance fork included) never changes it and
# every caller that parses it (lane-remove's `local_ahead` refusal) behaves as before. With
# --paths, `local_ahead <n>` and `conflict <n>` are followed by the <n> paths they count, one per
# line, two-space indented, LC_ALL=C-sorted — local_ahead: every take-L and union path, a path
# this checkout deleted suffixed ` (deleted locally)`; conflict: every conflicting path — so a
# caller that refuses on them can name what is unpushed (lane-remove does). With --learning
# (opt-in, never part of the default output) ONE more line follows, last:
#   `learning: <state>; consent <granted|declined|none|unknown>` — <state> is `conflict <n>` |
#   `local_ahead <n>` | `remote_ahead` | `synced` over the learning-store paths alone (same
#   precedence), or the first line's own token when no plan was computed (`never_synced`, …). A
#   learning-store path git tracks (TRACKED LEARNING STORES) is not counted in <state>; when at
#   least one exists the line ends `; tracked <n>` (absent otherwise, so the line is unchanged), and
#   an unreadable index makes <state> `unreachable`.
# Without --paths / --learning status prints only the first line.
# Precedence: unreachable > no_remote_branch > never_synced > base_branch_mismatch > conflict >
# local_ahead > remote_ahead.
#
# META-BASE NOT A REGULAR FILE: pull and push refuse up front — after the lock, before any fetch,
# write or publish — when <gitdir>/meta-base exists but is not a regular file (e.g. a directory):
# exit 1 naming meta-base, nothing changed, the directory left in place (write_base_file's own
# directory guard stays as defence in depth). Without this a push would publish and only then fail.
#
# EXIT: 0 ok / no_changes; 1 conflict, no_remote_branch, fetch failure, init refusal, exhausted push
# retries, tree_guard, locked, not_a_file, newline_in_path, branch_mismatch, mode_unknown,
# base_branch_mismatch, a meta-base that is not a regular file, usage error, a list-managed
# enumeration refusal; 2 scrub hit (push and scrub). `init`
# is the ONLY command that may create the branch (an empty orphan commit); it refuses when the
# branch already exists. `twin_refused`, `learning_skipped` and `learning_tracked` are stderr-only and
# leave the exit code unchanged — they are not refusals of the command, so they are not in this
# list (an UNREADABLE git index is: exit 1, nothing changed).
#
# Callers: automate-helpers.sh `meta-entry` (pull), automate-trail.sh `trail-pr` (push
# --paths-from) and automate-lanes.sh `lane-remove` (status --paths) — each passes `--branch <the
# mode's branch>`, which the mode check accepts. meta-entry's pull takes the learning stores like
# any managed path (a tracked one excepted — TRACKED LEARNING STORES); trail-pr's (and the lanes') exact --paths-from lists never name them, so they
# are published by a whole-set push (no --paths-from) only.

# Modules (sourced in this order from meta-sync.d/):
# - lock.sh: the per-root lock (pull / push) — g, the per-run temp dir WORK (META_INDEX,
#     FILE_MODE, META_BASE_INDEX) with cleanup and its EXIT / HUP / INT / TERM traps,
#     lock_holder_alive, lock_is_stale, reclaim_lock, acquire_lock.
# - managed.sh: the ONE managed-set declaration and the reads over it — is_managed, is_twin_path,
#     is_learning_path, symlink_hazard, path_has_no_symlink, parent_inside, remote_probe,
#     no_remote_branch_msg, fetch_remote, no_newline_in, list_tree, list_local, list_history.
# - plan.sh: meta-base and the 3-way plan — load_base, compute_plan, classify_plan, hold_rows,
#     count_outcome, report_conflicts, report_not_a_file, union_into, ordered_merge,
#     refuse_bad_base, refuse_foreign_base, write_base_file.
# - scrub.sh: the scrub rules — load_allowlist, scrub_report, email_matches, first_match_line,
#     scan_file, scrub_candidates.
# - learning-twin.sh: learning stores (consent and the twin set) — read_consent, consent_skip,
#     tracked_learning_hold, twin_sha, twin_field, twin_trusted, twin_post_bytes,
#     twin_pair_check, twin_gate.
# - commands.sh: the subcommands init, pull, push, status, scrub, list-managed — build_pull_base,
#     cmd_init, fetch_or_exit, cmd_pull, build_agreed_base, cmd_push, status_paths,
#     split_learning_rows, status_done, learning_state, cmd_status, cmd_scrub, cmd_list_managed.
# This file keeps the header above, set -uo pipefail, HERE and the globals, say / warn / die /
# usage / need_val, the argument parser and its refusals, the root resolution, read_branch_mode
# and the branch choice, the lock settings, the module loader (_ms_source / _ms_bundle), the
# source lines and the final dispatch. This map sits below the header's first blank line, so
# `usage` (which prints the first comment block only) and --help are unchanged by it.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAB="$(printf '\t')"
SUBCMD=""
DEFAULT_BRANCH="loomwright-meta"   # the target when the mode reads `off` (an unmigrated repo)
BRANCH=""
BRANCH_SET=0                       # 1 iff --branch was given (never inferred from its value)
ALLOW_MISMATCH=0
ROOT=""
PATHS_FROM=""
PATHS_FROM_SET=0
TRACKED=0
TREE_SRC=""
TREE_SET=0
RUN_HISTORY=0
STATUS_PATHS=0
STATUS_LEARNING=0
MESSAGE="meta-sync: run history"
MAX_ATTEMPTS=5
LEDGER_PATH=".supervisor/postmortem/results.jsonl"
TWIN_PROV=".supervisor/twin/.provenance.jsonl"
DENY_CONFIG=".agent/meta-sync-deny.txt"
BASE_REF="refs/meta-sync/base"

say()  { printf 'meta_sync: %s\n' "$*"; }
warn() { printf 'meta_sync: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

usage() {
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
  exit 0
}

need_val() { [ "$2" -ge 2 ] || die "usage: $1 requires a value (try --help)"; }

while [ $# -gt 0 ]; do
  case "$1" in
    init|pull|push|status|scrub|list-managed)
      [ -z "$SUBCMD" ] || die "usage: more than one subcommand given"
      SUBCMD="$1"; shift ;;
    --branch)     need_val "$1" "$#"; BRANCH="$2"; BRANCH_SET=1; shift 2 ;;
    --allow-branch-mismatch) ALLOW_MISMATCH=1; shift ;;
    --root)       need_val "$1" "$#"; ROOT="$2"; shift 2 ;;
    --paths-from) need_val "$1" "$#"; PATHS_FROM="$2"; PATHS_FROM_SET=1; shift 2 ;;
    --tracked)    TRACKED=1; shift ;;
    --tree)       need_val "$1" "$#"; TREE_SRC="$2"; TREE_SET=1; shift 2 ;;
    --run-history) RUN_HISTORY=1; shift ;;
    --paths)      STATUS_PATHS=1; shift ;;
    --learning)   STATUS_LEARNING=1; shift ;;
    --message)    need_val "$1" "$#"; MESSAGE="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *) die "usage: unknown argument '$1' (try --help)" ;;
  esac
done
[ -n "$SUBCMD" ] || die "usage: a subcommand is required: init | pull | push | status | scrub | list-managed (try --help)"
# --paths-from restricts a PUSH and names what a SCRUB scans; nothing else reads it, so accepting it
# elsewhere would be a silent no-op.
[ "$PATHS_FROM_SET" = "0" ] || [ "$SUBCMD" = "push" ] || [ "$SUBCMD" = "scrub" ] \
  || die "usage: --paths-from applies to push and scrub only, not '$SUBCMD'; nothing was changed (try --help)"
[ "$SUBCMD" != "scrub" ] || [ "$PATHS_FROM_SET" = "1" ] \
  || die "usage: scrub requires --paths-from <file> (the files to scan); nothing was changed (try --help)"
[ "$TRACKED" = "0" ] || [ "$SUBCMD" = "list-managed" ] \
  || die "usage: --tracked applies to list-managed only, not '$SUBCMD'; nothing was changed (try --help)"
[ "$STATUS_PATHS" = "0" ] || [ "$SUBCMD" = "status" ] \
  || die "usage: --paths applies to status only, not '$SUBCMD'; nothing was changed (try --help)"
[ "$STATUS_LEARNING" = "0" ] || [ "$SUBCMD" = "status" ] \
  || die "usage: --learning applies to status only, not '$SUBCMD'; nothing was changed (try --help)"
{ [ "$TREE_SET" = "0" ] && [ "$RUN_HISTORY" = "0" ]; } || [ "$SUBCMD" = "list-managed" ] \
  || die "usage: --tree / --run-history apply to list-managed only, not '$SUBCMD'; nothing was changed (try --help)"
[ "$TREE_SET" = "0" ] || [ "$TRACKED" = "0" ] \
  || die "usage: --tree and --tracked are two different sources; give one; nothing was changed (try --help)"
# scrub and list-managed need no branch and skip the mode / branch check, so a --branch given to
# them could only be silently ignored.
NEEDS_BRANCH=1
case "$SUBCMD" in scrub|list-managed) NEEDS_BRANCH=0 ;; esac
[ "$NEEDS_BRANCH" = "1" ] || { [ "$BRANCH_SET" = "0" ] && [ "$ALLOW_MISMATCH" = "0" ]; } \
  || die "usage: --branch / --allow-branch-mismatch do not apply to '$SUBCMD' (it needs no branch); nothing was changed (try --help)"
# --allow-branch-mismatch only qualifies an explicit --branch; alone it would be a silent no-op.
[ "$ALLOW_MISMATCH" = "0" ] || [ "$BRANCH_SET" = "1" ] \
  || die "usage: --allow-branch-mismatch requires --branch <name>; nothing was changed (try --help)"

# ---- resolve root (mirrors run-lock.sh's "resolve root" block) ----
if [ -z "$ROOT" ]; then
  main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  if [ -n "$main_root" ] && [ -d "$main_root" ]; then
    top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
    [ "$top" = "$main_root" ] || main_root=""
  fi
  [ -n "$main_root" ] || main_root="$PWD"
  ROOT="$main_root"
fi
[ -d "$ROOT" ] || die "usage: --root '$ROOT' is not a directory"
ROOT="$(cd "$ROOT" && pwd)"
# The PHYSICAL root (every symlink in the checkout path resolved, e.g. macOS /tmp -> /private/tmp):
# the containment check compares physical paths, so a symlinked checkout path is never mistaken
# for an escape.
ROOT_P="$(cd -P "$ROOT" && pwd -P)" || die "usage: cannot resolve the physical path of '$ROOT'"
GITDIR="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null)" \
  || die "usage: '$ROOT' is not inside a git work tree"

# ---- target branch: the checkout's mode line (runs before any lock, fetch or write) ----
# read_branch_mode — asks the sibling setup-memory.sh (`mode`, the ONE mode-line reader; this
# script never parses .gitignore) and sets MODE_STATE (off|on|unknown), MODE_BRANCH, MODE_REASON.
# FAIL-CLOSED on the answer's shape: only an exact `off` or a single `on <non-empty>` line passes;
# a missing reader, a non-zero exit, empty output, a multi-line or unrecognised answer is `unknown`.
MODE_STATE=""; MODE_BRANCH=""; MODE_REASON=""
read_branch_mode() {
  local out rc=0 nl='
'
  if [ ! -f "$HERE/setup-memory.sh" ]; then
    MODE_STATE="unknown"; MODE_REASON="setup-memory.sh (the mode-line reader) is missing beside meta-sync.sh"
    return 0
  fi
  out="$(bash "$HERE/setup-memory.sh" --root "$ROOT" mode 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    MODE_STATE="unknown"; MODE_REASON="setup-memory.sh mode exited $rc"
    return 0
  fi
  case "$out" in
    *"$nl"*)      MODE_STATE="unknown"; MODE_REASON="setup-memory.sh mode returned a multi-line answer (first line '${out%%"$nl"*}')" ;;
    off)          MODE_STATE="off" ;;
    "on "?*)      MODE_STATE="on"; MODE_BRANCH="${out#on }" ;;
    "unknown "?*) MODE_STATE="unknown"; MODE_REASON="${out#unknown }" ;;
    "")           MODE_STATE="unknown"; MODE_REASON="setup-memory.sh mode printed nothing" ;;
    *)            MODE_STATE="unknown"; MODE_REASON="setup-memory.sh mode printed '$out'" ;;
  esac
}
# --branch X --allow-branch-mismatch is the explicit override: the mode is not consulted.
# scrub / list-managed (NEEDS_BRANCH=0) skip this whole block, including the ref-format check.
if [ "$NEEDS_BRANCH" = "1" ] && { [ "$BRANCH_SET" = "0" ] || [ "$ALLOW_MISMATCH" = "0" ]; }; then
  read_branch_mode
  case "$MODE_STATE" in
    on)
      if [ "$BRANCH_SET" = "1" ] && [ "$BRANCH" != "$MODE_BRANCH" ]; then
        die "branch_mismatch — --branch '$BRANCH' but this checkout's mode line names '$MODE_BRANCH'; nothing was changed. Drop --branch to target '$MODE_BRANCH', or add --allow-branch-mismatch to force '$BRANCH'."
      fi ;;
    off) : ;;
    *) die "mode_unknown — $MODE_REASON; nothing was changed (repair the mode line with setup-memory.sh apply --branch-mode <branch>|off, or pass --branch <name> --allow-branch-mismatch)" ;;
  esac
  [ "$BRANCH_SET" = "1" ] || BRANCH="$DEFAULT_BRANCH"
  [ "$BRANCH_SET" = "1" ] || [ "$MODE_STATE" != "on" ] || BRANCH="$MODE_BRANCH"
fi
# Validated AFTER the final choice, so a branch named by the mode line is checked too.
[ "$NEEDS_BRANCH" = "0" ] || git check-ref-format "refs/heads/$BRANCH" 2>/dev/null \
  || die "usage: invalid branch name '$BRANCH'"

META_BASE="$GITDIR/meta-base"
LOCK_DIR="$GITDIR/meta-sync.lock"
LOCK_HELD=0
LOCK_WAIT="${META_SYNC_LOCK_WAIT_SECS:-120}"
case "$LOCK_WAIT" in ''|*[!0-9]*) LOCK_WAIT=120 ;; esac

# >>> module loader (_ms_source / _ms_bundle) — entry-only, belongs to no module
# Everything from here to the final dispatch lives in meta-sync.d/<name>.sh (automate-speed/20, a
# move-only split; the Modules map below the header names what each holds). Each module is sourced
# by ONE `_ms_source <name>` line between `# >>> meta-sync.d/<name>.sh` and
# `# <<< meta-sync.d/<name>.sh` markers, at the position its text held when this was a single
# file, so `_ms_bundle` (this script with each such line replaced by the module's text) reproduces
# that file's line order. Listed by name, never globbed: a stray file in meta-sync.d/ is never
# sourced. The loader runs AFTER the argument parser, the root resolution and the branch choice
# above (each of which can only refuse, with nothing changed) and BEFORE the first lock, fetch or
# write: a missing, unreadable or empty module exits 1 naming it (as _ms_bundle does), with
# nothing changed. Top-level code inside a module runs as that module is sourced, before the
# later modules load (lock.sh creates
# the per-run temp dir WORK and installs its EXIT trap, so a later missing module still removes
# that temp dir on exit). The dir comes from this file's ${BASH_SOURCE[0]}; HERE is unchanged, so
# setup-memory.sh is still looked up beside this entry point.
_ms_source() {
  local _ms_f
  _ms_f="$(dirname "${BASH_SOURCE[0]}")/meta-sync.d/$1.sh"
  { [ -f "$_ms_f" ] && [ -r "$_ms_f" ] && [ -s "$_ms_f" ]; } \
    || { echo "meta-sync: missing module file: meta-sync.d/$1.sh" >&2; exit 1; }
  . "$_ms_f"
}
# _ms_bundle [<entry>] — print <entry> (default: this script) with every `_ms_source <name>` line
# replaced by meta-sync.d/<name>.sh read from beside it. Self-contained (a test evals this one
# function): a missing, unreadable or empty module prints one stderr line naming it and exits 1.
_ms_bundle() {
  local _ms_e="${1:-${BASH_SOURCE[0]}}"
  MS_MOD="$(dirname "$_ms_e")/meta-sync.d" awk '
    /^_ms_source [a-z][a-z-]*$/ {
      f = ENVIRON["MS_MOD"] "/" $2 ".sh"; n = 0
      while ((r = (getline l < f)) > 0) { print l; n++ }
      close(f)
      if (r < 0 || n == 0) { print "meta-sync: missing module file: meta-sync.d/" $2 ".sh" > "/dev/stderr"; exit 1 }
      next
    }
    { print }
  ' "$_ms_e"
}
# <<< module loader
# >>> meta-sync.d/lock.sh
_ms_source lock
# <<< meta-sync.d/lock.sh
# >>> meta-sync.d/managed.sh
_ms_source managed
# <<< meta-sync.d/managed.sh
# >>> meta-sync.d/plan.sh
_ms_source plan
# <<< meta-sync.d/plan.sh
# >>> meta-sync.d/scrub.sh
_ms_source scrub
# <<< meta-sync.d/scrub.sh
# >>> meta-sync.d/learning-twin.sh
_ms_source learning-twin
# <<< meta-sync.d/learning-twin.sh
# >>> meta-sync.d/commands.sh
_ms_source commands
# <<< meta-sync.d/commands.sh
case "$SUBCMD" in
  init)   cmd_init ;;
  pull)   acquire_lock; cmd_pull ;;
  push)   acquire_lock; cmd_push ;;
  status) cmd_status ;;
  scrub)  cmd_scrub ;;
  list-managed) cmd_list_managed ;;
esac
