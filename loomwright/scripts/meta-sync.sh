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
#   meta-sync.sh status [--branch <name> [--allow-branch-mismatch]] [--root <checkout>]
#   meta-sync.sh -h | --help
#
#   --branch      metadata branch on `origin`. Default: the branch the checkout's MODE LINE names,
#                 read through the sibling `setup-memory.sh --root <root> mode` (the ONE mode-line
#                 reader; this script never parses .gitignore itself): `on <Y>` => Y; `off` =>
#                 loomwright-meta; `unknown <reason>` — or ANY other reader answer (empty output, a
#                 non-zero exit, a missing sibling, a multi-line or unrecognised line) => exit 1
#                 `meta_sync: mode_unknown — <reason>; nothing was changed` (fail closed).
#                 Given explicitly, it must AGREE with the mode: `on Y` with Y != <name> => exit 1
#                 `meta_sync: branch_mismatch` naming both; `off` => <name> is used; `unknown` =>
#                 exit 1 `mode_unknown`. The check runs for every subcommand, right after the root
#                 is resolved and BEFORE any lock, fetch or write (nothing is changed on a refusal).
#   --allow-branch-mismatch
#                 use the given --branch even when the mode line disagrees or reads `unknown` (the
#                 mode is then not consulted). Without --branch it is a usage error (exit 1).
#   --root        checkout to sync (default: the FIRST `git worktree list --porcelain` entry, i.e. the
#                 main checkout, with a --show-toplevel sanity check and a $PWD fallback — the same
#                 "resolve root" block run-lock.sh uses)
#   --paths-from  push only the managed paths listed in <file> (one repo-relative path per line;
#                 blank and `#` lines ignored; unlisted or non-managed paths are never pushed).
#                 push ONLY: given to init / pull / status it is a usage error (exit 1, nothing
#                 changed) — never silently accepted and ignored
#   --message     commit message for the metadata-branch commit
#
# MANAGED SET — the ONE declared list (is_managed below); everything else is invisible to this script:
#   .supervisor/requirements/**/*.md
#   .supervisor/jobs/done/*.md
#   .supervisor/jobs/failed/*.md
#   .supervisor/automate/*.md
#   .supervisor/postmortem/results.jsonl
#   minus anything under a NESTED .supervisor/ (.supervisor/requirements/**/.supervisor/**),
#   and minus every NON-CANONICAL path (an absolute path, or one with a `.` / `..` / empty segment).
#   Branch trees are untrusted input (anyone who can push the branch can mktree any entry name);
#   a `.supervisor/requirements/../../CLAUDE.md` entry must never be joined to the root and
#   written or deleted, so it is simply not a managed path (pull ignores it; push fails closed,
#   because git's read-tree refuses such a tree).
# Local files are enumerated with `find` over the managed roots ONLY (requirements/ with nested
# .supervisor/ trees pruned; the top level of jobs/done, jobs/failed, automate and postmortem), so
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
#   both changed       -> .supervisor/postmortem/results.jsonl: line-union (R's lines unchanged,
#                         including repeats inside R, then the L lines not present in R in local
#                         order — never a global dedupe); any other path: `meta_sync: conflict
#                         <path>`, exit 1, NOTHING changed. A conflict needs a human.
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
#                       (stale copy); results.jsonl with L != R => line-union; otherwise conflict
# The derivation always covers the WHOLE managed set (even under --paths-from) and any conflict
# anywhere aborts, because the meta-base written afterwards must cover every managed path. The
# history walk runs only while meta-base is absent (or to verify a legacy base, below).
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
#     never reverts R or deletes a sibling's new file; a results.jsonl union the push wrote to the
#     branch but not locally => the local L; any managed path the push did not consider (outside
#     --paths-from) => its previous / derived B.
#   Recording R's (or the new commit's) branch tree after a push would make the next sync revert a
#   sibling's newer change or resurrect a deletion. A conflict, a scrub hit or an exhausted retry
#   leaves meta-base untouched. refs/meta-sync/base points at the same tree purely as a gc anchor
#   (the tree and its blobs are otherwise unreachable and `git gc` would prune them); if the object
#   is ever missing anyway, the script falls back to the no-base derivation with a warning.
#
# PULL — fetch, decide per path, refuse on any conflict / not_a_file / containment failure, then
# write. The ledger UNION is built and renamed into place BEFORE any take-R write or delete: the
# union re-reads the working ledger and fails closed when it no longer hashes to the planned L
# (`<path> changed during the sync`), and because it runs first such a refusal leaves every other
# managed file untouched and meta-base unchanged.
#
# PUSH — fetch, decide per path, build the new tree in a SEPARATE index (a per-run GIT_INDEX_FILE
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
# `status` and `init` take no lock: status reads meta-base (always replaced by an atomic rename)
# and writes nothing shared; all scratch state (index files, temp files) is per-run.
#
# SCRUB (push only, fail CLOSED: exit 2, branch and meta-base unchanged). EVERY file being added or
# changed is scanned before deciding and EVERY hit is named in one run, one line per hit:
#   `meta_sync: scrub <path>: <rule>` — so a caller can build a --paths-from exclusion list from it
#   (no other output line starts with `meta_sync: scrub `; the final summary starts `meta_sync: aborted`).
#   (a) ledger: every results.jsonl record's `.repo` must be in the repo allowlist resolved by the
#       sibling setup-memory.sh (`allowlist`); a missing/unparseable `.repo` is a hit;
#   (b) prose, portable POSIX ERE only (no GNU-only escapes — on BSD grep those would silently match
#       nothing and this fail-CLOSED gate would fail OPEN):
#         email          e-mail addresses
#         home_path      absolute home paths: /Users/<name>/ and /home/<name>/ (any letter case —
#                        macOS paths are case-insensitive)
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
# STATUS prints exactly one line and always exits 0 once the branch is resolved: `synced <sha> on
# <branch>` | `local_ahead <n>` | `remote_ahead` | `conflict <n>` | `no_remote_branch` |
# `unreachable` | `never_synced` | `base_branch_mismatch`. (A branch_mismatch / mode_unknown /
# usage refusal happens before status runs and exits 1.)
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
# base_branch_mismatch, a meta-base that is not a regular file, usage error; 2 scrub hit. `init`
# is the ONLY command that may create the branch (an empty orphan commit); it refuses when the
# branch already exists.
#
# Callers: automate-helpers.sh `meta-entry` (pull) and automate-trail.sh `trail-pr` (push
# --paths-from) — both pass `--branch <the mode's branch>`, which the mode check accepts.

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
MESSAGE="meta-sync: run history"
MAX_ATTEMPTS=5
LEDGER_PATH=".supervisor/postmortem/results.jsonl"
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
    init|pull|push|status)
      [ -z "$SUBCMD" ] || die "usage: more than one subcommand given"
      SUBCMD="$1"; shift ;;
    --branch)     need_val "$1" "$#"; BRANCH="$2"; BRANCH_SET=1; shift 2 ;;
    --allow-branch-mismatch) ALLOW_MISMATCH=1; shift ;;
    --root)       need_val "$1" "$#"; ROOT="$2"; shift 2 ;;
    --paths-from) need_val "$1" "$#"; PATHS_FROM="$2"; PATHS_FROM_SET=1; shift 2 ;;
    --message)    need_val "$1" "$#"; MESSAGE="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *) die "usage: unknown argument '$1' (try --help)" ;;
  esac
done
[ -n "$SUBCMD" ] || die "usage: a subcommand is required: init | pull | push | status (try --help)"
# --paths-from restricts a PUSH; pull never reads it, so accepting it elsewhere would be a silent no-op.
[ "$PATHS_FROM_SET" = "0" ] || [ "$SUBCMD" = "push" ] \
  || die "usage: --paths-from applies to push only, not '$SUBCMD'; nothing was changed (try --help)"
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
if [ "$BRANCH_SET" = "0" ] || [ "$ALLOW_MISMATCH" = "0" ]; then
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
git check-ref-format "refs/heads/$BRANCH" 2>/dev/null || die "usage: invalid branch name '$BRANCH'"

META_BASE="$GITDIR/meta-base"
LOCK_DIR="$GITDIR/meta-sync.lock"
LOCK_HELD=0
LOCK_WAIT="${META_SYNC_LOCK_WAIT_SECS:-120}"
case "$LOCK_WAIT" in ''|*[!0-9]*) LOCK_WAIT=120 ;; esac

g() { git -C "$ROOT" "$@"; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t meta-sync)" || die "cannot create a temp dir"
# Per-run scratch only: the gitdir is shared by every worktree and every concurrent invocation
# (a read-only `status` included), so no fixed-name scratch file may live there.
META_INDEX="$WORK/meta-index"
# mktemp creates 0600 files; written files get the mode a plain `>` would give them (0666 & ~umask).
FILE_MODE="$(printf '%o' $(( 0666 & ~0$(umask) )))"
META_BASE_INDEX="$WORK/meta-base-index"
RECLAIM_MARK=""   # the reclaim marker this run holds right now, if any (see reclaim_lock)
RECLAIMED=0
# cleanup — removes only this run's own state: the per-run temp dir, and the lock / a reclaim
# marker iff it still carries this run's pid (a live holder's lock is never removed by anyone else).
cleanup() {
  if [ "$LOCK_HELD" = "1" ] && [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$LOCK_DIR"
  fi
  if [ -n "$RECLAIM_MARK" ] && [ "$(cat "$RECLAIM_MARK/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$RECLAIM_MARK"
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- per-root lock (pull / push) ----
# lock_holder_alive <pid> — kill -0 first; when it fails (dead, OR alive but owned by another user:
# EPERM) let `ps -p` decide, if ps exists.
lock_holder_alive() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null && return 0
  command -v ps >/dev/null 2>&1 || return 1
  ps -p "$1" >/dev/null 2>&1
}
# lock_is_stale <dir> <token> — 0 when <dir>, carrying <token> (the pid read from <dir>/pid), is
# abandoned: the token is a dead pid, or the dir is token-less (its holder died between mkdir and
# the pid write) and over a minute old.
lock_is_stale() {
  [ -d "$1" ] || return 1
  if [ -n "$2" ]; then
    lock_holder_alive "$2" && return 1
    return 0
  fi
  [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}
# reclaim_lock <dir> <token> <depth> — remove <dir> iff it STILL carries <token> and is STILL stale.
# Exactly one process may act on a given (dir, token): the one whose mkdir of the marker
# "<dir>.reclaim.<token>" succeeds. While it holds the marker, the instance carrying <token> can
# only be removed by it (its holder is dead; every other reclaimer re-checks a DIFFERENT token or
# waits on this marker), so the re-check-then-rm below cannot hit a live lock: a lock re-acquired
# in between carries another token and is left alone. Nothing is ever renamed aside and put back,
# so a waiter can never move a live holder's lock out from under it. A marker whose own owner died
# inside this tiny section is reclaimed the same way, one level up (bounded depth).
reclaim_lock() {
  local d="$1" t="$2" depth="$3" m w
  m="$1.reclaim.${2:-nopid}"
  [ "$depth" -le 4 ] || return 0
  if mkdir "$m" 2>/dev/null; then
    RECLAIM_MARK="$m"
    if printf '%s\n' "$$" > "$m/pid" \
       && [ "$(cat "$d/pid" 2>/dev/null)" = "$t" ] && lock_is_stale "$d" "$t"; then
      rm -rf "$d" && [ "$depth" -eq 0 ] && RECLAIMED=1
    fi
    rm -rf "$m"; RECLAIM_MARK=""
    return 0
  fi
  w="$(cat "$m/pid" 2>/dev/null)"
  if lock_is_stale "$m" "$w"; then reclaim_lock "$m" "$w" $((depth + 1)); fi
  return 0
}
acquire_lock() {
  local start holder
  start="$(date +%s)"
  while :; do
    # LOCK_HELD is set BEFORE the mkdir so a signal between the mkdir and the pid write still runs
    # cleanup; cleanup removes the lock only when it carries this run's pid, so this is safe.
    LOCK_HELD=1
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      if printf '%s\n' "$$" > "$LOCK_DIR/pid"; then return 0; fi
      rm -rf "$LOCK_DIR"; LOCK_HELD=0; die "could not write the lock holder pid into $LOCK_DIR"
    fi
    LOCK_HELD=0
    holder="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if lock_is_stale "$LOCK_DIR" "$holder"; then
      RECLAIMED=0
      reclaim_lock "$LOCK_DIR" "$holder" 0
      if [ "$RECLAIMED" = "1" ]; then
        warn "reclaimed a stale lock left by pid ${holder:-unknown}"
        continue
      fi
    fi
    if [ $(( $(date +%s) - start )) -ge "$LOCK_WAIT" ]; then
      die "locked — another meta-sync (pid ${holder:-unknown}) holds $LOCK_DIR; waited ${LOCK_WAIT}s, nothing was changed"
    fi
    sleep 1
  done
}

# ---- the ONE managed-set declaration ----
is_managed() {
  case "$1" in
    *"$TAB"*) return 1 ;;
    # Non-canonical paths are never managed (paths from a branch tree are untrusted; `*` in a case
    # pattern also matches `/`, so a dot segment would otherwise pass the globs below and climb out
    # of .supervisor/ when joined to the root).
    /*|./*|../*|*/./*|*/../*|*//*|*/.|*/..|*/) return 1 ;;
    .supervisor/requirements/*.md)
      case "$1" in
        .supervisor/requirements/.supervisor/*|.supervisor/requirements/*/.supervisor/*) return 1 ;;
      esac
      return 0 ;;
    .supervisor/jobs/done/*/*|.supervisor/jobs/failed/*/*|.supervisor/automate/*/*) return 1 ;;
    .supervisor/jobs/done/*.md|.supervisor/jobs/failed/*.md|.supervisor/automate/*.md) return 0 ;;
    .supervisor/postmortem/results.jsonl) return 0 ;;
  esac
  return 1
}

# ---- symlink containment (a symlink can redirect a write out of .supervisor/ or hide a file) ----
# symlink_hazard <repo-relative path of a local symlink> — 0 when a symlink there could redirect
# or hide managed run history: a managed path itself, a directory on the way to a managed folder,
# or a symlink under .supervisor/requirements/ that could hold managed .md files — one that
# resolves to a DIRECTORY, or a DANGLING one (its target may become a directory; it cannot be ruled
# out). A symlink resolving to a regular file at a non-managed path (requirements/q/design.png) can
# neither hide managed files nor be written through: it is not a hazard (and never synced).
symlink_hazard() {
  case "$1" in
    .supervisor|.supervisor/requirements|.supervisor/jobs|.supervisor/jobs/done|.supervisor/jobs/failed|.supervisor/automate|.supervisor/postmortem) return 0 ;;
  esac
  is_managed "$1" && return 0
  if [ -d "$ROOT/$1" ] || [ ! -e "$ROOT/$1" ]; then is_managed "$1/x.md"; else return 1; fi
}
# path_has_no_symlink <managed path> — 0 when no EXISTING component of the path, from .supervisor
# down to the leaf, is a symlink.
path_has_no_symlink() {
  local rest="$1" acc="" comp
  while :; do
    comp="${rest%%/*}"
    acc="${acc:+$acc/}$comp"
    [ -L "$ROOT/$acc" ] && return 1
    [ "$rest" = "$comp" ] && return 0
    rest="${rest#*/}"
  done
}
# parent_inside <managed path> — 0 when the path's (existing) parent directory resolves PHYSICALLY
# under <physical root>/.supervisor/.
parent_inside() {
  local phys
  phys="$(cd -P "$(dirname "$ROOT/$1")" 2>/dev/null && pwd -P)" || return 1
  case "$phys/" in "$ROOT_P/.supervisor/"*) return 0 ;; esac
  return 1
}

# ---- remote probing ----
# remote_probe — sets REMOTE_STATE (present|absent|unreachable) and REMOTE_SHA.
REMOTE_STATE=""; REMOTE_SHA=""
remote_probe() {
  local out rc
  out="$(g ls-remote --exit-code origin "refs/heads/$BRANCH" 2>/dev/null)"; rc=$?
  REMOTE_SHA=""
  case "$rc" in
    0) REMOTE_STATE="present"; REMOTE_SHA="$(printf '%s\n' "$out" | awk -v r="refs/heads/$BRANCH" '$2==r{print $1; exit}')"
       [ -n "$REMOTE_SHA" ] || REMOTE_STATE="unreachable" ;;
    2) REMOTE_STATE="absent" ;;
    *) REMOTE_STATE="unreachable" ;;
  esac
}

no_remote_branch_msg() {
  printf '%s\n' "meta_sync: no_remote_branch — '$BRANCH' does not exist on origin. Run 'meta-sync.sh init' once to create it. A common cause is a clone whose origin is a LOCAL PATH (another checkout) rather than the forge: that remote never carries the metadata branch. This is never treated as success." >&2
}

# fetch_remote — probe + fetch; sets R (commit) and RT (tree). Returns 0 ok, 1 fetch failure,
# 3 branch absent.
R=""; RT=""
fetch_remote() {
  remote_probe
  case "$REMOTE_STATE" in
    absent) return 3 ;;
    unreachable) return 1 ;;
  esac
  # --no-write-fetch-head: the gitdir (and its FETCH_HEAD) is shared with the user's own fetches
  # and every worktree; git < 2.29 rejects the flag, so fall back to a plain fetch there.
  if ! g fetch -q --no-tags --no-write-fetch-head origin "refs/heads/$BRANCH" >/dev/null 2>"$WORK/fetch.err"; then
    grep -q 'no-write-fetch-head' "$WORK/fetch.err" 2>/dev/null || return 1
    g fetch -q --no-tags origin "refs/heads/$BRANCH" >/dev/null 2>"$WORK/fetch.err" || return 1
  fi
  g cat-file -e "$REMOTE_SHA^{commit}" 2>/dev/null || return 1
  R="$REMOTE_SHA"
  RT="$(g rev-parse "$R^{tree}")" || return 1
  return 0
}

# ---- tables (path<TAB>sha, sorted) ----
# Every producer below FAILS CLOSED (non-zero) when its git read fails: an empty table is a
# decision input (an R or B table that silently came out empty turns every path into a deletion
# or a re-add), so a failed read must never look like an empty tree. The filter loops use
# `if`, not `&&`, so a non-managed LAST entry does not make the loop — and the pipeline — fail.
# no_newline_in <NUL-delimited raw listing> <what> — 0 when the listing holds no newline byte.
# Records are NUL-terminated and these -z listings emit no other newline, so any newline is INSIDE
# a name; the line-oriented parsing below would split it into fabricated records. Refuse on sight.
no_newline_in() {
  local n
  n="$(wc -l < "$1" | tr -d ' ')" || return 1
  [ "$n" = "0" ] && return 0
  warn "newline_in_path $2"
  warn "refusing — $2 holds a name containing a newline (it cannot be parsed safely); nothing was changed, meta-base untouched"
  return 1
}

# list_tree <tree-ish> <out> — managed blob entries of a tree.
list_tree() {
  g ls-tree -r -z --full-tree "$1" > "$WORK/lt.raw" 2>/dev/null || return 1
  no_newline_in "$WORK/lt.raw" "tree $1" || return 1
  tr '\0' '\n' < "$WORK/lt.raw" \
    | awk -F'\t' '{ split($1, a, " "); if (a[2] == "blob" && index($2, ".supervisor/") == 1) print $2 "\t" a[3] }' \
    | while IFS="$TAB" read -r p s; do if is_managed "$p"; then printf '%s\t%s\n' "$p" "$s"; fi; done \
    | env LC_ALL=C sort > "$2"
}

# list_local <out> <write:0|1> — managed files in the working folder, hashed as stored bytes.
# Enumerates ONLY the managed roots (requirements/ minus nested .supervisor/ trees; the top level
# of jobs/done, jobs/failed, automate and postmortem), so churn or unreadable entries elsewhere
# under .supervisor/ (logs, worktrees) can never block a sync. Fails closed when a managed root or
# a folder on the way to one cannot be searched or fully enumerated, or when a symlink sits where
# managed run history lives (find does not descend a symlinked directory, so its files would read
# as locally ABSENT — a push would delete them from the branch — and a pull would write through it).
list_local() {
  local p d hz="$WORK/local.symlinks" present=" " roots=""
  : > "$WORK/local.paths" || return 1
  : > "$WORK/local.found" || return 1
  : > "$hz" || return 1
  if [ -L "$ROOT/.supervisor" ]; then
    warn "symlink .supervisor"
    warn "refusing — .supervisor is a symlink; run history must live inside the checkout (nothing was changed)"
    return 1
  fi
  # Parents first: a child is only looked at when its parent is a searchable real directory, so an
  # absent child is truly absent (never an EACCES on the parent read as "no such folder").
  for d in .supervisor .supervisor/requirements .supervisor/jobs .supervisor/jobs/done \
           .supervisor/jobs/failed .supervisor/automate .supervisor/postmortem; do
    case "$d" in
      .supervisor) : ;;
      *) case "$present" in *" ${d%/*} "*) : ;; *) continue ;; esac ;;
    esac
    if [ -L "$ROOT/$d" ]; then printf '%s\n' "$d" >> "$hz"; continue; fi
    [ -d "$ROOT/$d" ] || continue
    [ -x "$ROOT/$d" ] || { warn "cannot search $d/ (permission denied); nothing was changed"; return 1; }
    present="$present$d "
    case "$d" in .supervisor|.supervisor/jobs) : ;; *) roots="$roots $d" ;; esac
  done
  : > "$WORK/local.found.z" || return 1
  for d in $roots; do
    if [ "$d" = ".supervisor/requirements" ]; then
      (cd "$ROOT" && find "$d" -type d -name .supervisor -prune -o \( -type f -o -type l \) -print0) >> "$WORK/local.found.z"
    else
      (cd "$ROOT" && find "$d" -maxdepth 1 \( -type f -o -type l \) -print0) >> "$WORK/local.found.z"
    fi || { warn "could not enumerate every file under $d/ (find failed); nothing was changed"; return 1; }
  done
  no_newline_in "$WORK/local.found.z" "the local files under the managed roots" || return 1
  tr '\0' '\n' < "$WORK/local.found.z" > "$WORK/local.found" || return 1
  while IFS= read -r p; do
    p="${p#./}"
    if [ -L "$ROOT/$p" ]; then
      if symlink_hazard "$p"; then printf '%s\n' "$p" >> "$hz"; fi
    elif is_managed "$p"; then
      printf '%s\n' "$p"
    fi
  done < "$WORK/local.found" | env LC_ALL=C sort > "$WORK/local.paths" || return 1
  if [ -s "$hz" ]; then
    sed 's/^/meta_sync: symlink /' "$hz" >&2
    warn "refusing — the symlink(s) above sit where managed run history lives (a write could leave .supervisor/, and files behind them read as deleted); replace them with real directories/files. Nothing was changed."
    return 1
  fi
  : > "$1"
  [ -s "$WORK/local.paths" ] || return 0
  local wflag=""
  [ "$2" = "1" ] && wflag="-w"
  (cd "$ROOT" && git hash-object $wflag --no-filters --stdin-paths < "$WORK/local.paths") > "$WORK/local.shas" \
    || return 1
  [ "$(wc -l < "$WORK/local.paths")" -eq "$(wc -l < "$WORK/local.shas")" ] || return 1
  paste "$WORK/local.paths" "$WORK/local.shas" > "$1"
}

# list_history <commit> <out> — every (path, blob) a managed path ever held in R's history.
list_history() {
  g log --no-renames --format= --raw --no-abbrev -z "$1" -- .supervisor > "$WORK/lh.raw" 2>/dev/null || return 1
  no_newline_in "$WORK/lh.raw" "the history of $1" || return 1
  tr '\0' '\n' < "$WORK/lh.raw" \
    | awk '
        /^:/ { split($0, f, " "); old = f[3]; new = f[4]; getline p
               if (old != "" && old !~ /^0+$/) print p "\t" old
               if (new != "" && new !~ /^0+$/) print p "\t" new }' \
    | while IFS="$TAB" read -r p s; do if is_managed "$p"; then printf '%s\t%s\n' "$p" "$s"; fi; done \
    | env LC_ALL=C sort -u > "$2"
}

# ---- base ----
# load_base — reads <gitdir>/meta-base: line 1 the agreed-state tree, line 2 `branch <name>` (the
# branch it was recorded against; see the header's BRANCH BINDING). Sets HAVE_BASE / BASE_TREE /
# BASE_LEGACY, and BASE_REFUSAL (non-empty = refuse the sync, nothing changed) when the base is
# bound to ANOTHER branch, is unreadable, or is in no recognised format. The branch check runs
# BEFORE the object check, so a mismatched base never degrades to the no-base derivation.
HAVE_BASE=0; BASE_TREE=""; BASE_LEGACY=0; BASE_REFUSAL=""
load_base() {
  local l1="" l2="" l3="" nl bb=""
  HAVE_BASE=0; BASE_TREE=""; BASE_LEGACY=0; BASE_REFUSAL=""
  [ -f "$META_BASE" ] || return 0
  if [ ! -r "$META_BASE" ]; then
    BASE_REFUSAL="base_branch_mismatch — meta-base $META_BASE is unreadable, so the branch it was recorded against is unknown; nothing was changed (no file written, no ref moved, meta-base untouched). Fix its permissions by hand."
    return 0
  fi
  { IFS= read -r l1; IFS= read -r l2; IFS= read -r l3; } < "$META_BASE"
  nl="$(awk 'END { print NR }' "$META_BASE")"
  BASE_TREE="$(printf '%s' "$l1" | tr -d ' \t\r')"
  l2="${l2%$'\r'}"
  case "$l2" in
    "") BASE_LEGACY=1 ;;
    "branch "?*) bb="${l2#branch }" ;;
    *) nl=99 ;;
  esac
  if [ "$nl" -gt 2 ] || [ -n "$l3" ] || { [ -z "$BASE_TREE" ] && [ -n "$bb" ]; }; then
    BASE_REFUSAL="base_branch_mismatch — meta-base $META_BASE is not in a recognised format (line 1 a tree, line 2 'branch <name>'), so the branch it was recorded against is unknown; nothing was changed (no file written, no ref moved, meta-base untouched). Repair or remove it by hand."
    BASE_TREE=""; BASE_LEGACY=0
    return 0
  fi
  if [ -n "$bb" ] && [ "$bb" != "$BRANCH" ]; then
    BASE_REFUSAL="base_branch_mismatch — meta-base was recorded against branch '$bb' but this sync targets '$BRANCH'; nothing was changed (no file written, no ref moved, meta-base untouched). Planning '$BRANCH' against another branch's base would delete local or branch files '$BRANCH' never removed. Sync '$bb' with --branch '$bb' (plus --allow-branch-mismatch when the mode line names another branch), or remove $META_BASE by hand to treat '$BRANCH' as never synced (the history-aware first-sync derivation)."
    BASE_TREE=""; return 0
  fi
  if [ -n "$BASE_TREE" ] && g cat-file -e "$BASE_TREE^{tree}" 2>/dev/null; then
    HAVE_BASE=1
  else
    warn "meta-base '$BASE_TREE' is missing from the object store — falling back to the no-base (history-aware) derivation"
    BASE_LEGACY=0
    BASE_TREE=""
  fi
}

# ---- plan ----
# compute_plan <write-local-objects:0|1> — writes $WORK/plan: outcome<TAB>path<TAB>L<TAB>R<TAB>newbase<TAB>sel
# ("-" = absent). Outcomes: SAME TAKE_R TAKE_L UNION CONFLICT. newbase = the agreed-state entry a
# PUSH records for the path (pull records R's tree instead).
compute_plan() {
  local L="$WORK/L.tsv" Rf="$WORK/R.tsv" Bf="$WORK/B.tsv" Hf="$WORK/H.tsv" Sf="$WORK/S.lst" hs=0
  list_local "$L" "$1" || { warn "could not hash the local managed files"; return 1; }
  list_tree "$R" "$Rf" || { warn "could not list the remote tree $R"; return 1; }
  : > "$Bf" && : > "$Hf" && : > "$Sf" || return 1
  load_base
  [ -z "$BASE_REFUSAL" ] || return 2
  if [ "$HAVE_BASE" = "1" ]; then
    list_tree "$BASE_TREE" "$Bf" || { warn "could not list the meta-base tree $BASE_TREE"; return 1; }
    if [ "$BASE_LEGACY" = "1" ]; then
      # A legacy base (no branch line) is adopted for $BRANCH only when EVERY entry it holds is a
      # (path, blob) $BRANCH's own history held — i.e. it provably was not taken from another branch.
      local stray
      list_history "$R" "$Hf" || { warn "could not read the history of $R"; return 1; }
      stray="$(awk -F'\t' -v HF="$Hf" 'FILENAME == HF { h[$0] = 1; next } !($0 in h) { n++ } END { print n + 0 }' "$Hf" "$Bf")" \
        || { warn "could not check the legacy meta-base against the history of $R"; return 1; }
      if [ "$stray" != "0" ]; then
        BASE_REFUSAL="base_branch_mismatch — the legacy meta-base $META_BASE records no branch and holds $stray entr(y/ies) '$BRANCH''s history never held, so it may have been taken from another branch; nothing was changed (no file written, no ref moved, meta-base untouched). Sync the branch it came from with --branch <that branch>, or remove $META_BASE by hand to treat '$BRANCH' as never synced (the history-aware first-sync derivation)."
        return 2
      fi
      : > "$Hf" || return 1
    fi
  else
    list_history "$R" "$Hf" || { warn "could not read the history of $R"; return 1; }
  fi
  if [ -n "$PATHS_FROM" ]; then
    hs=1
    sed -e 's/\r$//' -e 's|^\./||' "$PATHS_FROM" | awk 'NF && $0 !~ /^#/' > "$Sf" \
      || { warn "could not read --paths-from '$PATHS_FROM'"; return 1; }
  fi
  awk -F'\t' -v OFS='\t' -v hb="$HAVE_BASE" -v hs="$hs" -v ledger="$LEDGER_PATH" \
      -v LF="$L" -v RF="$Rf" -v BF="$Bf" -v HF="$Hf" -v SF="$Sf" '
    FILENAME == LF { Lb[$1] = $2; U[$1] = 1; next }
    FILENAME == RF { Rb[$1] = $2; U[$1] = 1; next }
    FILENAME == BF { Bb[$1] = $2; U[$1] = 1; next }
    FILENAME == HF { H[$1 SUBSEP $2] = 1; HP[$1] = 1; next }
    FILENAME == SF { S[$0] = 1; next }
    END {
      for (p in U) {
        l = (p in Lb) ? Lb[p] : "-"
        r = (p in Rb) ? Rb[p] : "-"
        sel = (hs == 0 || (p in S)) ? 1 : 0
        if (hb == 1) {
          b = (p in Bb) ? Bb[p] : "-"
          if (l == r) { o = "SAME"; nb = r }
          else if (l == b) { o = "TAKE_R"; nb = b }
          else if (r == b) { o = "TAKE_L"; nb = (sel ? l : b) }
          else if (p == ledger) { o = "UNION"; nb = (sel ? l : b) }
          else { o = "CONFLICT"; nb = b }
        } else if (r != "-") {
          if (l == r) { o = "SAME"; nb = r }
          else if (l == "-") { o = "TAKE_R"; nb = "-" }
          else if ((p SUBSEP l) in H) { o = "TAKE_R"; nb = l }
          else if (p == ledger) { o = "UNION"; nb = (sel ? l : "-") }
          else { o = "CONFLICT"; nb = "-" }
        } else if (p in HP) {
          if ((p SUBSEP l) in H) { o = "TAKE_R"; nb = l }
          else { o = "CONFLICT"; nb = "-" }
        } else {
          o = "TAKE_L"; nb = (sel ? l : "-")
        }
        print o, p, l, r, nb, sel
      }
    }' "$L" "$Rf" "$Bf" "$Hf" "$Sf" | env LC_ALL=C sort -t "$TAB" -k2,2 > "$WORK/plan" \
    || { warn "could not compute the sync plan"; return 1; }
}

# count_outcome <outcome> [selected-only:0|1]
count_outcome() {
  awk -F'\t' -v o="$1" -v so="${2:-0}" '$1 == o && (so == 0 || $6 == 1) { n++ } END { print n + 0 }' "$WORK/plan"
}

# report_conflicts <selected-only:0|1> — prints one line per conflict; returns 0 when there are none.
report_conflicts() {
  local n
  n="$(count_outcome CONFLICT "$1")"
  [ "$n" -eq 0 ] && return 0
  awk -F'\t' -v so="$1" '$1 == "CONFLICT" && (so == 0 || $6 == 1) { print "meta_sync: conflict " $2 }' "$WORK/plan" >&2
  warn "aborted — $n conflict(s); nothing was changed (no file written, no ref moved, meta-base untouched). A conflict needs a human."
  return 1
}

# report_not_a_file <selected-only:0|1> — 0 unless a path the branch holds a FILE at is, locally,
# a directory or another non-regular file. find lists regular files only, so such a path reads as
# locally ABSENT: a pull would rename the branch file INTO the directory (and record it as synced)
# and a push would delete the branch file. Paths the branch does not hold are never refused.
report_not_a_file() {
  local o p l r nb sel n=0
  while IFS="$TAB" read -r o p l r nb sel; do
    [ "$r" != "-" ] || continue
    [ "$1" = "0" ] || [ "$sel" = "1" ] || continue
    if [ -e "$ROOT/$p" ] && [ ! -f "$ROOT/$p" ]; then
      warn "not_a_file $p"; n=$((n + 1))
    fi
  done < "$WORK/plan"
  [ "$n" -eq 0 ] && return 0
  warn "refusing — $n managed path(s) above exist locally as a directory or another non-regular file while the branch holds a file there; nothing was changed (no file written, no ref moved, meta-base untouched)"
  return 1
}

# union_into <R-blob|-> <L-blob|-> <out> [<L-file>] — R's lines unchanged, then L's lines not
# present in R. With <L-file> (pull) L is read from the working file — a pull hashes local files
# WITHOUT -w, so L's blob is not in the object store — and must still hash to <L-blob> (a file
# changed mid-sync fails closed). Every read fails closed: a side that cannot be read is NEVER
# treated as empty (that silently drops the clone's unpushed ledger lines). "-" = absent side.
union_into() {
  { : > "$WORK/u.r" && : > "$WORK/u.l"; } || return 1
  if [ "$1" != "-" ]; then g cat-file blob "$1" > "$WORK/u.r" 2>/dev/null || return 1; fi
  if [ "$2" != "-" ]; then
    if [ -n "${4:-}" ]; then
      cat "$4" > "$WORK/u.l" 2>/dev/null || return 1
      [ "$(g hash-object --no-filters -- "$WORK/u.l" 2>/dev/null)" = "$2" ] \
        || { warn "$4 changed during the sync"; return 1; }
    else
      g cat-file blob "$2" > "$WORK/u.l" 2>/dev/null || return 1
    fi
  fi
  awk 'FNR == NR { inR[$0] = 1; print; next } !($0 in inR) && !seen[$0]++ { print }' "$WORK/u.r" "$WORK/u.l" > "$3"
}

# refuse_bad_base — pull / push refuse UP FRONT (after the lock, before any fetch, write or
# publish) when <gitdir>/meta-base exists but is not a regular file. load_base reads such a path as
# "no base", so without this a push would publish and only then fail to record meta-base, and a
# pull would write local files first. The path is left exactly as found (nothing moved into it).
refuse_bad_base() {
  local kind=""
  { [ -e "$META_BASE" ] || [ -L "$META_BASE" ]; } || return 0
  [ -f "$META_BASE" ] && return 0
  [ -d "$META_BASE" ] && kind=" (it is a directory)"
  die "refusing — meta-base $META_BASE is not a regular file$kind; remove or replace it by hand. Nothing was changed (no fetch, no file written, nothing published)."
}

# refuse_foreign_base — pull / push refuse UP FRONT (after the lock, before any fetch) when
# meta-base is bound to another branch, unreadable or malformed (load_base's BASE_REFUSAL). A
# LEGACY base is checked later, in compute_plan, because that check needs the fetched R.
refuse_foreign_base() {
  load_base 2>/dev/null
  [ -z "$BASE_REFUSAL" ] || die "$BASE_REFUSAL"
}

# write_base_file <tree> — atomic replace via a mktemp'd (O_EXCL, never a pre-existing symlink)
# sibling + rename; a meta-base that is a directory (mv would move INTO it) fails closed. Writes
# both lines in ONE file (tree, then `branch $BRANCH`), so the binding can never be torn from the
# tree; the lock (pull / push) means the branch checked by load_base is the branch written here.
write_base_file() {
  local tmp
  [ -d "$META_BASE" ] && { warn "$META_BASE is a directory"; return 1; }
  tmp="$(mktemp "$META_BASE.tmp.XXXXXX" 2>/dev/null)" || return 1
  chmod "$FILE_MODE" "$tmp" && printf '%s\nbranch %s\n' "$1" "$BRANCH" > "$tmp" && mv -f "$tmp" "$META_BASE" || { rm -f "$tmp"; return 1; }
  g update-ref "$BASE_REF" "$1" >/dev/null 2>&1 || warn "could not update the gc anchor $BASE_REF (meta-base itself was written)"
  return 0
}

# ---- scrub ----
ALLOW_FILE=""
load_allowlist() {
  ALLOW_FILE="$WORK/allow.lst"
  bash "$HERE/setup-memory.sh" --root "$ROOT" allowlist 2>/dev/null \
    | tr 'A-Z' 'a-z' | awk 'NF && $0 !~ /^#/' > "$ALLOW_FILE" || : > "$ALLOW_FILE"
}

RESERVED_OWNERS=' about apps blog collections contact enterprise events explore features issues login logout marketplace new notifications organizations orgs pricing pulls readme search security settings site sponsors topics trending users '

# scan_file <file> <path> — prints `meta_sync: scrub <path>: <rule>` per hit; returns 1 when any hit.
scan_file() {
  local f="$1" p="$2" hits=0 L='(^|[^A-Za-z0-9_])' rule re rc icase
  # rule<TAB>case(i = any letter case, s = exact)<TAB>ERE
  while IFS="$TAB" read -r rule icase re; do
    if [ "$icase" = "i" ]; then
      env LC_ALL=C grep -i -E -q -e "$re" "$f" 2>/dev/null; rc=$?
    else
      env LC_ALL=C grep -E -q -e "$re" "$f" 2>/dev/null; rc=$?
    fi
    if [ "$rc" -eq 0 ]; then echo "meta_sync: scrub $p: $rule"; hits=1
    elif [ "$rc" -gt 1 ]; then echo "meta_sync: scrub $p: scan_error($rule)"; hits=1
    fi
  done <<EOF
email${TAB}i${TAB}[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}
home_path${TAB}i${TAB}/(Users|home)/[A-Za-z0-9._-]+/
token_github${TAB}s${TAB}${L}gh[pousr]_[A-Za-z0-9]{36,}
token_github_pat${TAB}s${TAB}${L}github_pat_[A-Za-z0-9_]{22,}
token_sk${TAB}s${TAB}${L}sk-[A-Za-z0-9_-]{20,}
token_slack${TAB}s${TAB}${L}xox[abp]-[A-Za-z0-9-]{10,}
token_aws${TAB}s${TAB}${L}AKIA[0-9A-Z]{16}([^A-Za-z0-9_]|\$)
EOF
  # forge slugs — URL contexts and repo fields only (see header: a bare a/b is not a slug). Both
  # extractions are case-INSENSITIVE (a host or key in any case is the same context) and the output
  # is lowercased BEFORE the sed strip, so the strip patterns only ever see lowercase. The repo key
  # and its value may be bare or wrapped in double, single or back quotes.
  local slugs="$WORK/slugs" s owner bad=0 q="[\"'\`]?"
  {
    env LC_ALL=C grep -ioE '(github\.com|gitlab\.com|bitbucket\.org)[/:](repos/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$f" 2>/dev/null \
      | tr 'A-Z' 'a-z' | sed -E 's#^[^/:]+[/:]##; s#^repos/##'
    env LC_ALL=C grep -ioE "${L}${q}repo${q}[[:space:]]*:[[:space:]]*${q}[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+" "$f" 2>/dev/null \
      | tr 'A-Z' 'a-z' | sed -E "s#^.*repo${q}[[:space:]]*:[[:space:]]*${q}##"
  } | sed -E 's#\.+$##; s#\.git$##' | tr 'A-Z' 'a-z' | env LC_ALL=C sort -u > "$slugs"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    owner="${s%%/*}"
    case "$RESERVED_OWNERS" in *" $owner "*) continue ;; esac
    # an all-dot segment is a placeholder ellipsis (github.com/.../pull), never an owner or repo
    case "$owner" in *[!.]*) : ;; *) continue ;; esac
    case "${s#*/}" in *[!.]*) : ;; *) continue ;; esac
    grep -F -x -q -e "$s" "$ALLOW_FILE" 2>/dev/null || { bad=1; break; }
  done < "$slugs"
  [ "$bad" -eq 1 ] && { echo "meta_sync: scrub $p: forge_slug"; hits=1; }
  # project deny patterns — tracked DATA, handed to grep -E, never executed.
  if [ -f "$ROOT/$DENY_CONFIG" ]; then
    local n=0 pat
    while IFS= read -r pat || [ -n "$pat" ]; do
      n=$((n + 1))
      pat="${pat%$'\r'}"
      case "$pat" in ''|'#'*) continue ;; esac
      env LC_ALL=C grep -E -q -e "$pat" "$f" 2>/dev/null; rc=$?
      if [ "$rc" -eq 0 ]; then echo "meta_sync: scrub $p: deny_pattern:$n"; hits=1
      elif [ "$rc" -gt 1 ]; then echo "meta_sync: scrub $p: deny_pattern_invalid:$n"; hits=1
      fi
    done < "$ROOT/$DENY_CONFIG"
  fi
  # ledger: every record's .repo must be allowlisted.
  if [ "$p" = "$LEDGER_PATH" ]; then
    local out
    if ! command -v jq >/dev/null 2>&1; then
      echo "meta_sync: scrub $p: ledger_unverifiable(jq missing)"; hits=1
    else
      out="$(jq -R -r --arg allow "$(cat "$ALLOW_FILE")" '
              ($allow | split("\n") | map(select(length > 0))) as $a
              | select(test("^\\s*$") | not)
              | (try fromjson catch null) as $o
              | if ($o | type) == "object" and ($o.repo | type) == "string"
                   and (($o.repo | ascii_downcase) as $r | $a | any(.[]; . == $r))
                then empty else "hit" end' "$f" 2>/dev/null)"; rc=$?
      if [ "$rc" -ne 0 ]; then echo "meta_sync: scrub $p: ledger_unverifiable"; hits=1
      elif [ -n "$out" ]; then echo "meta_sync: scrub $p: ledger_repo"; hits=1
      fi
    fi
  fi
  [ "$hits" -eq 0 ]
}

# scrub_candidates <list: path<TAB>blob> — scans every candidate, prints every hit; 0 = clean.
scrub_candidates() {
  local p s any=0
  load_allowlist
  while IFS="$TAB" read -r p s; do
    [ -n "$p" ] || continue
    g cat-file blob "$s" > "$WORK/scan.blob" 2>/dev/null || { echo "meta_sync: scrub $p: unreadable"; any=1; continue; }
    scan_file "$WORK/scan.blob" "$p" || any=1
  done < "$1"
  [ "$any" -eq 0 ]
}

# ---- subcommands ----
cmd_init() {
  remote_probe
  case "$REMOTE_STATE" in
    present) die "init_refused — '$BRANCH' already exists on origin ($REMOTE_SHA); nothing was changed" ;;
    unreachable) die "fetch_failed — origin is unreachable; nothing was created" ;;
  esac
  local empty c
  empty="$(g mktree < /dev/null)" || die "could not write the empty tree"
  c="$(printf '%s\n' "meta-sync: initialise $BRANCH" | g commit-tree "$empty")" || die "commit-tree failed (is user.name / user.email configured?)"
  g push -q origin "$c:refs/heads/$BRANCH" || die "init push failed — '$BRANCH' was not created"
  say "initialised $BRANCH at $c"
}

fetch_or_exit() {
  local rc
  fetch_remote; rc=$?
  case "$rc" in
    0) return 0 ;;
    3) no_remote_branch_msg; exit 1 ;;
    *) warn "fetch_failed — could not fetch '$BRANCH' from origin"; [ -s "$WORK/fetch.err" ] && sed 's/^/  /' "$WORK/fetch.err" >&2; exit 1 ;;
  esac
}

cmd_pull() {
  local rc
  refuse_bad_base
  refuse_foreign_base
  fetch_or_exit
  compute_plan 0; rc=$?
  [ "$rc" -eq 2 ] && die "$BASE_REFUSAL"
  [ "$rc" -eq 0 ] || exit 1
  report_conflicts 0 || exit 1
  report_not_a_file 0 || exit 1
  local o p l r nb sel written=0 deleted=0 dst tmp phase
  # Containment pre-pass: nothing is written or deleted unless EVERY path the plan touches is a
  # canonical managed path with no symlinked component (list_local already refused symlinks where
  # run history lives; this re-checks the exact plan paths before the first write).
  while IFS="$TAB" read -r o p l r nb sel; do
    case "$o" in
      TAKE_R|UNION)
        is_managed "$p" || die "refusing non-managed path in the plan: $p (nothing was changed)"
        path_has_no_symlink "$p" || die "refusing — a component of $p is a symlink (nothing was changed)" ;;
    esac
  done < "$WORK/plan"
  # UNION rows first, then TAKE_R: the union re-reads the working ledger and refuses when it no
  # longer hashes to the planned L (`changed during the sync`). Run first, that refusal happens
  # before any other managed file is written or deleted — so it really changes nothing.
  for phase in UNION TAKE_R; do
    while IFS="$TAB" read -r o p l r nb sel; do
      [ "$o" = "$phase" ] || continue
      dst="$ROOT/$p"
      # Defence in depth (a symlink planted after the pre-pass): re-check right before the act, and
      # after any mkdir -p confirm the parent resolves physically under .supervisor/.
      path_has_no_symlink "$p" || die "refusing — a component of $p is a symlink (meta-base untouched)"
      if [ -e "$dst" ] && [ ! -f "$dst" ]; then
        die "refusing — $p exists locally but is not a regular file (meta-base untouched)"
      fi
      if [ "$o" = "TAKE_R" ] && [ "$r" = "-" ]; then
        parent_inside "$p" || die "refusing — $p does not resolve under .supervisor/ (meta-base untouched)"
        rm -f "$dst" || die "could not delete $p (meta-base untouched)"
        deleted=$((deleted + 1))
        continue
      fi
      mkdir -p "$(dirname "$dst")" || die "could not create the folder for $p (meta-base untouched)"
      parent_inside "$p" || die "refusing — $p does not resolve under .supervisor/ (meta-base untouched)"
      tmp="$(mktemp "$dst.meta-sync.tmp.XXXXXX" 2>/dev/null)" || die "could not create a temp file for $p (meta-base untouched)"
      chmod "$FILE_MODE" "$tmp" || { rm -f "$tmp"; die "could not set the mode of a temp file for $p (meta-base untouched)"; }
      if [ "$o" = "TAKE_R" ]; then
        g cat-file blob "$r" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dst" \
          || { rm -f "$tmp"; die "could not write $p (meta-base untouched)"; }
      else
        union_into "$r" "$l" "$tmp" "$dst" && mv -f "$tmp" "$dst" \
          || { rm -f "$tmp"; die "could not write the union of $p (it runs first: nothing was changed, meta-base untouched)"; }
      fi
      written=$((written + 1))
    done < "$WORK/plan"
  done
  write_base_file "$RT" || die "could not write meta-base"
  say "pulled $R ($written written, $deleted deleted)"
}

# build_agreed_base — the per-path agreed-state tree for a push (see header); prints its SHA.
build_agreed_base() {
  rm -f "$META_BASE_INDEX"
  GIT_INDEX_FILE="$META_BASE_INDEX" g read-tree --empty || return 1
  awk -F'\t' '$5 != "-" { print "100644 " $5 "\t" $2 }' "$WORK/plan" \
    | GIT_INDEX_FILE="$META_BASE_INDEX" g update-index --index-info || return 1
  GIT_INDEX_FILE="$META_BASE_INDEX" g write-tree
}

cmd_push() {
  [ -z "$PATHS_FROM" ] || [ -f "$PATHS_FROM" ] || die "usage: --paths-from '$PATHS_FROM' is not a file"
  local attempt=1 o p l r nb sel s newtree commit changed abort_sel rc
  refuse_bad_base
  refuse_foreign_base
  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    fetch_or_exit
    compute_plan 1; rc=$?
    [ "$rc" -eq 2 ] && die "$BASE_REFUSAL"
    [ "$rc" -eq 0 ] || exit 1
    # With a base, an unlisted path is ignored entirely; without one the derivation covers the
    # whole managed set and any conflict anywhere aborts (meta-base must cover every path).
    abort_sel=1
    [ "$HAVE_BASE" = "1" ] || abort_sel=0
    report_conflicts "$abort_sel" || exit 1
    report_not_a_file "$abort_sel" || exit 1
    rm -f "$META_INDEX"
    GIT_INDEX_FILE="$META_INDEX" g read-tree "$RT" || die "read-tree into the separate index failed"
    : > "$WORK/candidates"
    : > "$WORK/planned"
    changed=0
    while IFS="$TAB" read -r o p l r nb sel; do
      [ "$sel" = "1" ] || continue
      case "$o" in TAKE_L|UNION) printf '%s\n' "$p" >> "$WORK/planned" ;; esac
      case "$o" in
        TAKE_L)
          if [ "$l" = "-" ]; then
            GIT_INDEX_FILE="$META_INDEX" g update-index --force-remove -- "$p" || die "update-index failed for $p"
          else
            GIT_INDEX_FILE="$META_INDEX" g update-index --add --cacheinfo 100644 "$l" "$p" || die "update-index failed for $p"
            printf '%s\t%s\n' "$p" "$l" >> "$WORK/candidates"
          fi
          changed=$((changed + 1)) ;;
        UNION)
          union_into "$r" "$l" "$WORK/union.out" || die "could not build the union of $p"
          s="$(g hash-object -w --no-filters --stdin < "$WORK/union.out")" || die "hash-object failed for $p"
          GIT_INDEX_FILE="$META_INDEX" g update-index --add --cacheinfo 100644 "$s" "$p" || die "update-index failed for $p"
          printf '%s\t%s\n' "$p" "$s" >> "$WORK/candidates"
          changed=$((changed + 1)) ;;
      esac
    done < "$WORK/plan"
    newtree="$(GIT_INDEX_FILE="$META_INDEX" g write-tree)" || die "write-tree failed"
    if [ "$changed" -eq 0 ] || [ "$newtree" = "$RT" ]; then
      nb="$(build_agreed_base)" || die "could not build the agreed-state base tree"
      write_base_file "$nb" || die "could not write meta-base"
      say "no_changes"
      exit 0
    fi
    # tree_guard — the new tree may differ from R's ONLY at the selected take-L / union paths.
    g diff-tree -r -z --no-renames --name-only "$RT" "$newtree" > "$WORK/touched.z" \
      || die "tree_guard — could not diff the new tree against $RT; nothing was pushed"
    no_newline_in "$WORK/touched.z" "the new tree" || die "tree_guard — the new tree holds a newline name; nothing was pushed, meta-base untouched"
    tr '\0' '\n' < "$WORK/touched.z" | awk -v PF="$WORK/planned" 'FILENAME == PF { ok[$0] = 1; next } NF && !($0 in ok)' "$WORK/planned" - > "$WORK/unplanned" \
      || die "tree_guard — could not compare the new tree with the plan; nothing was pushed"
    if [ -s "$WORK/unplanned" ]; then
      sed 's/^/  unplanned: /' "$WORK/unplanned" >&2
      die "tree_guard — the new tree changes $(wc -l < "$WORK/unplanned" | tr -d ' ') path(s) the plan did not select; nothing was pushed, meta-base untouched"
    fi
    if ! scrub_candidates "$WORK/candidates" >&2; then
      warn "aborted — scrub hit(s) above; nothing was pushed, the branch and meta-base are unchanged (exclude or clean the named paths)"
      exit 2
    fi
    commit="$(printf '%s\n' "$MESSAGE" | g commit-tree "$newtree" -p "$R")" \
      || die "commit-tree failed (is user.name / user.email configured?)"
    if g push -q origin "$commit:refs/heads/$BRANCH" 2>"$WORK/push.err"; then
      nb="$(build_agreed_base)" || die "pushed $commit but could not build the agreed-state base tree; meta-base untouched"
      write_base_file "$nb" || die "pushed $commit but could not write meta-base"
      say "pushed $commit ($changed path(s))"
      exit 0
    fi
    warn "rejected (attempt $attempt/$MAX_ATTEMPTS) — re-fetching and recomputing"
    attempt=$((attempt + 1))
    [ "$attempt" -le "$MAX_ATTEMPTS" ] && sleep 1
  done
  sed 's/^/  /' "$WORK/push.err" >&2 2>/dev/null
  die "push_failed — rejected $MAX_ATTEMPTS times; nothing forced, meta-base untouched"
}

cmd_status() {
  local rc n
  fetch_remote; rc=$?
  case "$rc" in
    0) : ;;
    3) echo "no_remote_branch"; exit 0 ;;
    *) echo "unreachable"; exit 0 ;;
  esac
  [ -f "$META_BASE" ] || { echo "never_synced"; exit 0; }
  compute_plan 0 >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && { echo "base_branch_mismatch"; exit 0; }
  [ "$rc" -eq 0 ] || { echo "unreachable"; exit 0; }
  [ "$HAVE_BASE" = "1" ] || { echo "never_synced"; exit 0; }
  n="$(count_outcome CONFLICT)"
  [ "$n" -gt 0 ] && { echo "conflict $n"; exit 0; }
  n=$(( $(count_outcome TAKE_L) + $(count_outcome UNION) ))
  [ "$n" -gt 0 ] && { echo "local_ahead $n"; exit 0; }
  [ "$(count_outcome TAKE_R)" -gt 0 ] && { echo "remote_ahead"; exit 0; }
  echo "synced $R on $BRANCH"
  exit 0
}

case "$SUBCMD" in
  init)   cmd_init ;;
  pull)   acquire_lock; cmd_pull ;;
  push)   acquire_lock; cmd_push ;;
  status) cmd_status ;;
esac
