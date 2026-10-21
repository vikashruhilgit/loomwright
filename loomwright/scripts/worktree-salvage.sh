#!/usr/bin/env bash
# worktree-salvage.sh — preserve a worktree's UNCOMMITTED content before a
# plugin-owned `git worktree remove` discards it.
#
# WHY THIS EXISTS. The plugin removes worktrees it created at four places: the
# review drain's dispatcher (`dispatch-pr-review.sh`) force-removes its
# `../{project}-review-{hash}` sibling at three sites — a defensive pre-add
# cleanup of a prior dispatch's stale dir, a header-write-failure teardown, and
# the detached wrapper's EXIT trap that fires on the runner's crash/SIGTERM
# mid-fix — and the Supervisor's FINALIZE step 4 removes each
# `../{project}-{subtask_id}` sibling. `--force` discards without asking. The
# same rescue had already been done BY HAND twice (a `BASE_SHA` + `tracked.patch`
# + `modified/` + `untracked/` + README layout under `.supervisor/salvage/`);
# this script executes that convention, in that shape, before every plugin-owned
# removal.
#
# USAGE
#   worktree-salvage.sh <abs-or-rel worktree path> [--dest <dir>] [--reason <text>] [--ignored [--allow-unsalvaged]]
#   worktree-salvage.sh <abs-or-rel worktree path> --check-ignored
#
#   --dest    destination directory. Default: `<primary>/.supervisor/salvage/`
#             where <primary> is the parent of `git rev-parse --git-common-dir`
#             — the PRIMARY checkout, never the worktree itself (it is about to
#             be deleted). The dispatcher passes it explicitly — ITS OWN checkout's
#             `.supervisor/salvage`, beside the per-PR marker, which is the
#             dispatching checkout and not necessarily the primary — so the EXIT
#             trap never depends on git resolution from a possibly-broken worktree.
#   --reason  free text recorded in the README (the caller names its site:
#             `dispatch pre-add cleanup`, `dispatch header-write teardown`,
#             `review-drain teardown`, `FINALIZE step 4`).
#   --ignored OPT-IN gitignored-runtime salvage (af/39a — the 2026-10-12 hand
#             cleanup lost a worktree's session logs and postmortem ledger, because
#             DETECTION below skips ignored content by design and `git worktree
#             remove` deletes it). Each PRESENT entry of the fixed SALVAGE LIST
#             (ign_salvage_list below — the runtime records a drained worktree holds,
#             and the host's local settings file, IGN_HOST_SETTINGS) is copied to
#             `<salvage>/ignored/<rel>` and verified byte-identical (`diff -r`),
#             stopping at the first failure. The VERDICT is the LAST stdout line,
#             always printed in this mode: `ignored: ok <n>` (n = entries copied;
#             `ignored: ok 0` with no salvage directory when the tree is clean and no
#             entry is present) or `ignored: failed <rel> — <reason>` (a script-level
#             failure before any entry is known names `-`). FAIL CLOSED on what the
#             list does not cover: when the worktree holds gitignored content that is
#             neither on the salvage list (or inside one of its entries) nor
#             REGENERABLE (ign_regenerable below: build/cache output beside its manifest), the
#             verdict is `ignored: failed <entry>[, <entry>…] — unsalvaged ignored content`,
#             naming EVERY such entry — a `.env`, `.supervisor/state.md`,
#             `.supervisor/jobs/` or `graphify-out/` would otherwise be deleted with no
#             copy. An EMPTY directory (no file at any depth — ign_empty_dir below) holds
#             nothing a removal could lose and is never named. `--allow-unsalvaged` drops ONLY
#             that coverage verdict (closeout step 3a's documented limit: its own
#             merged PR worktree keeps its prior contract and is removed even with such
#             content — `automate-trail.sh` sweep never passes it). Exit stays 0. A caller removes
#             the worktree ONLY on an `ignored: ok` line — anything else, including no
#             line at all, keeps it (`automate-trail.sh` sweep and closeout step 3a).
#             Without the flag every output below is byte-unchanged.
#   --check-ignored  READ-ONLY (writes nothing, creates no directory): the same
#             coverage check alone, so a dry run can report what `--ignored` would
#             refuse. ONE stdout line: `ignored-check: ok` | `ignored-check:
#             unsalvaged <entry>[, <entry>…]` (every gitignored entry neither salvaged,
#             regenerable nor empty, as `git ls-files --others --ignored --exclude-standard
#             --directory` names it — a directory ends in `/`) | `ignored-check:
#             failed — <reason>` (unreadable ⇒ the caller keeps the worktree). Exit 0.
#
# OUTPUT
#   stdout: the created salvage directory `<dest>/<basename(wt)>-<UTC ts>[-N]`
#           when something was saved; NOTHING (stdout or stderr) when the
#           worktree is clean.
#   exit:   ALWAYS 0 — a runtime side-effect emitter (CLAUDE.md §"Failure-Mode
#           Invariants"). A missing argument, an unreadable path, git absent, a
#           non-worktree path, an unwritable destination ⇒ ONE stderr line naming
#           the cause, nothing captured, exit 0. A salvage failure never prevents
#           the removal that was going to happen. Sub-tools' stderr (git, mkdir,
#           cp, date) is redirected to /dev/null so the one line is this
#           script's own and the clean case is silent.
#
# DETECTION = `git status --porcelain=v1 -z --untracked-files=all`, WITHOUT
#   `--ignored`. Empty output ⇒ clean ⇒ return before any directory is created.
#   Gitignored content is never listed by that command, so per-checkout runtime
#   state under `.supervisor/` (logs, drain rounds, scratch) is excluded
#   STRUCTURALLY — by git's own ignore rules, not by a path denylist. Tracked
#   files under `.supervisor/` that are modified DO show up and ARE captured: they
#   are uncommitted work in git's own terms.
#
# CAPTURE, in this order, best-effort per step, README LAST:
#   BASE_SHA          `git rev-parse HEAD` + newline — written ONLY when the
#                     output is a hex SHA (an unborn HEAD makes git print the
#                     literal `HEAD` with rc 128; that is `partial (BASE_SHA
#                     failed)`, not a base)
#   tracked.patch     `git diff --binary HEAD` (staged additions and binary edits
#                     round-trip; an empty diff is an empty file — an
#                     untracked-only salvage is legal)
#   modified/<rel>    every non-`??` entry whose path still exists, VERBATIM
#                     (deletions have nothing to copy — the patch carries them;
#                     a modified or newly added SUBMODULE is a directory with
#                     nothing to copy verbatim and is the ONE directory entry
#                     skipped here — it appears in the patch as a `Subproject
#                     commit` line and the README says so in its own item)
#   untracked/<rel>   every `??` entry, verbatim, relative path preserved. An
#                     untracked DIRECTORY reaches the stream under
#                     `--untracked-files=all` only as a NESTED REPOSITORY (git
#                     never descends into one — a stray clone / `git init` a
#                     worker left behind, listed as `?? nested/`); it is
#                     uncommitted content and is copied verbatim, its own `.git`
#                     included, and the README names it under "Nested
#                     repositories". It is never silently dropped.
#   README.md         worktree, branch, BASE_SHA, removed ts, reason, status,
#                     recovery steps (modified/ first; the patch is against
#                     BASE_SHA — that worktree's own HEAD — and will NOT apply to
#                     current main), and what is deliberately not captured.
#   If a step fails (a `cp` of one entry included — `partial (untracked/<rel>
#   failed)`) the salvage continues and the README's `status:` reads
#   `partial (<step> failed)` instead of `complete`.
#
#   THE `-z` STREAM: a rename/copy entry (`R`/`C` in either column) carries ONE
#   extra NUL-terminated field, the origin path, AFTER the new path. The parser
#   consumes it exactly once per such entry; every later entry is still read in
#   register (a parser that skipped it would read the origin path as a record of
#   its own).
#
# DIRECTORY NAME  `<basename(wt)>-<YYYYMMDDTHHMMSSZ>`; on collision `-2`, `-3`,
#   … up to a HARD CAP of 999 (this runs inside an EXIT trap — nothing here may
#   spin); exhaustion ⇒ one stderr line, nothing captured, exit 0.
#   `mkdir -p` of the destination happens ONLY after detection found content.
#
# TEST SEAM (not a feature): `LOOMWRIGHT_SALVAGE_TS=<YYYYMMDDTHHMMSSZ>` overrides
#   the `date -u` timestamp so the collision arm is deterministic. It becomes a
#   path component, so it is honored ONLY when it matches that exact shape;
#   anything else is silently ignored and `date -u` is used.
#
# POPULATION GATE — deliberately the INVERSE of the worktree audit log's.
#   `worktree-audit.sh` refuses to create `.supervisor/` in a repo the plugin
#   never touched because a log line is nobody's business. A salvage is someone's
#   uncommitted work, and losing it is worse than a stray directory: this script
#   creates `.supervisor/salvage/` under its destination (the primary checkout by
#   default; the dispatching checkout when the drain passes `--dest`) even where
#   `.supervisor/` did not exist.
#
# HONEST LIMITS (limits, not claims):
#   (a) SIGKILL / power-loss skips the salvage exactly as it skips the trap that
#       calls it — the window narrows, it does not close.
#   (b) A worktree whose `git status` cannot be read (broken `.git` file, git
#       absent) is not captured — one stderr line, exit 0.
#   (c) Retention / pruning of `.supervisor/salvage/` is NOT this script's job
#       (reconciler-repair item 06).
#   (d) The salvage directory is created under the destination — the primary
#       checkout by default, the dispatching checkout for the drain — even where
#       `.supervisor/` did not exist (the inverse of the audit log's population
#       gate, above).
#   (e) A `git worktree remove --force` typed by a human or an agent through the
#       Bash tool is NOT a plugin-owned path — nothing intercepts it. Scope is
#       the moment before a plugin-owned removal, nothing else.
#
# PORTABILITY: bash 3.2 + BSD userland. The `-z` stream is parsed with
#   `read -r -d ''` from a temp FILE (a `cmd | while read` loop runs in a subshell
#   and loses its flags); fixed-string comparisons only; no `${var//…}` on the
#   stream (macOS bash 3.2 O(n²) trap); `set -u` but no `set -e` / `pipefail` —
#   every failure is absorbed explicitly.

set -u

fail() {
  # ONE stderr line, nothing captured, exit 0 — the always-exit-0 contract.
  # --ignored: the verdict line still comes last on stdout, naming the first
  # pending entry (or `-` before the entry list is known). --check-ignored: its
  # one `ignored-check: failed — …` line.
  printf 'worktree-salvage: %s\n' "$1" >&2
  [ "$CHECK_ONLY" -eq 1 ] && printf 'ignored-check: failed — %s\n' "$1"
  [ "$IGNORED" -eq 1 ] && printf 'ignored: failed %s — %s\n' "${IGN_FIRST:--}" "$1"
  exit 0
}

WT=""
DEST=""
REASON="unspecified"
IGNORED=0
CHECK_ONLY=0
ALLOW_UNSALV=0
IGN_FIRST=""

# The host's local settings file — named ONCE here (vendor-coupling ratchet: a
# harness-specific path, the one this script cannot avoid naming).
IGN_HOST_SETTINGS=".claude/settings.local.json"
# ign_salvage_list — the fixed --ignored SALVAGE LIST, one relative path per line
# (never a word-split variable). Session logs, the postmortem ledger, a review drain's
# round ledger (drain-rounds.sh) and its REVIEW_HEAL_RESULT sidecars
# (review-heal-next-step.sh) — the records a drained PR worktree holds — and the host's
# local settings file.
ign_salvage_list() {
  printf '%s\n' .supervisor/logs .supervisor/postmortem .supervisor/drain-rounds .supervisor/review-heal "$IGN_HOST_SETTINGS"
}
# ign_empty_dir <entry> — returns 0 when <entry> (relative to $WT_TOP) is a real,
# non-symlink directory holding no file, symlink or other non-directory at ANY depth:
# a removal deletes nothing in it, so it is never unsalvaged content (a drain's
# `.supervisor/check-wait/` once its deadline file is gone). A tree `find` cannot read
# in full is NOT empty — the caller then names it (fail closed).
ign_empty_dir() {
  local p hit
  p="${1%/}"
  [ -d "$WT_TOP/$p" ] && [ ! -L "$WT_TOP/$p" ] || return 1
  hit="$(find "$WT_TOP/$p" ! -type d -print -quit 2>/dev/null)" || return 1
  [ -z "$hit" ]
}
# ign_regenerable <entry> — THE REGENERABLE RULE, stated only here: returns 0 when a
# gitignored <entry> (relative to $WT_TOP, as `git ls-files --directory` names it — a
# directory ends in `/`) is build/cache output a removal may delete with no copy.
# Anything neither regenerable nor on the salvage list keeps the worktree
# (--ignored / --check-ignored fail closed on it). The rule is ANCHORED, never a bare
# name match: a name alone (`build`, `dist`, `target`) is also what a person calls a
# hand-written folder, so `src/build/notes.md` must never read as regenerable.
#   - DIRECTORIES ONLY (a real, non-symlink directory; the entry ends in `/`) beside
#     the manifest of the tool that regenerates them, in the SAME parent directory
#     (the worktree top for a top-level entry):
#       node_modules/ .next/          beside package.json
#       dist/ build/                  beside package.json, pyproject.toml, setup.py
#                                     or requirements*.txt
#       target/                       beside Cargo.toml
#       .venv/                        beside pyproject.toml, setup.py or requirements*.txt
#   - ANY DEPTH, two exceptions, because neither is ever hand-authored work: a
#     `__pycache__/` directory (CPython writes one beside every imported module, at
#     whatever depth the module sits, and rebuilds it on the next import) and a
#     `.DS_Store` FILE (Finder's per-folder view metadata).
ign_regenerable() {
  local p name dir m f
  case "$1" in
    .DS_Store|*/.DS_Store) return 0 ;;
    */) ;;
    *) return 1 ;;
  esac
  p="${1%/}"
  [ -d "$WT_TOP/$p" ] && [ ! -L "$WT_TOP/$p" ] || return 1
  name="${p##*/}"
  case "$p" in */*) dir="$WT_TOP/${p%/*}" ;; *) dir="$WT_TOP" ;; esac
  case "$name" in
    __pycache__) return 0 ;;
    node_modules|.next) set -- package.json ;;
    dist|build) set -- package.json pyproject.toml setup.py 'requirements*.txt' ;;
    target) set -- Cargo.toml ;;
    .venv) set -- pyproject.toml setup.py 'requirements*.txt' ;;
    *) return 1 ;;
  esac
  for m in "$@"; do
    # $m unquoted on purpose: `requirements*.txt` is a glob; an unmatched glob stays
    # literal and fails -f.
    for f in "$dir"/$m; do [ -f "$f" ] && return 0; done
  done
  return 1
}

# ign_unsalvaged — prints, on ONE line joined by `, `, EVERY gitignored entry of
# $WT_TOP that is neither a salvage-list entry (or inside one), regenerable nor an
# empty directory; prints nothing when every entry is covered. Every entry, never only
# the first: a verdict that names one entry hides the others behind it, and an operator
# who judges that one harmless removes the rest with no copy. A directory that is a
# proper ANCESTOR of a salvage-list entry (`.supervisor/` collapsed by --directory) is
# descended one level at a time (children sorted), so its other children (`state.md`,
# `jobs/`) are judged on their own; an entry reached twice is named once. `-z`
# throughout, so a non-ASCII or newline-bearing name is never C-quoted. Returns 1 when
# git cannot list the entries (the caller fails closed).
ign_unsalvaged() {
  local q nq e p s cover anc c out seen
  out=""; seen="
"
  q="$(mktemp "${TMPDIR:-/tmp}/wt-salvage-ign.XXXXXX" 2>/dev/null)" || return 1
  nq="$(mktemp "${TMPDIR:-/tmp}/wt-salvage-ign.XXXXXX" 2>/dev/null)" || { rm -f "$q"; return 1; }
  if ! git -C "$WT_TOP" ls-files -z --others --ignored --exclude-standard --directory > "$q" 2>/dev/null; then
    rm -f "$q" "$nq"; return 1
  fi
  while [ -s "$q" ]; do
    : > "$nq"
    while IFS= read -r -d '' e; do
      [ -n "$e" ] || continue
      p="${e%/}"; cover=0; anc=0
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        case "$p" in "$s"|"$s"/*) cover=1 ;; esac
        case "$s" in "$p"/*) anc=1 ;; esac
      done <<SALV
$(ign_salvage_list)
SALV
      ign_regenerable "$e" && cover=1
      [ "$cover" -eq 1 ] && continue
      if [ "$anc" -eq 1 ] && [ -d "$WT_TOP/$p" ] && [ ! -L "$WT_TOP/$p" ]; then
        while IFS= read -r -d '' c; do
          c="${c#"$WT_TOP/"}"
          if [ -d "$WT_TOP/$c" ] && [ ! -L "$WT_TOP/$c" ]; then printf '%s/\0' "$c"; else printf '%s\0' "$c"; fi
        done < <(find "$WT_TOP/$p" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z) >> "$nq"
        continue
      fi
      ign_empty_dir "$e" && continue
      case "$seen" in *"
$e
"*) continue ;; esac
      seen="$seen$e
"
      out="${out:+$out, }$e"
    done < "$q"
    mv -f "$nq" "$q" 2>/dev/null || { rm -f "$q" "$nq"; return 1; }
    nq="$(mktemp "${TMPDIR:-/tmp}/wt-salvage-ign.XXXXXX" 2>/dev/null)" || { rm -f "$q"; return 1; }
  done
  rm -f "$q" "$nq"
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}
while [ $# -gt 0 ]; do
  case "$1" in
    --dest)
      [ $# -ge 2 ] || fail "--dest needs a value"
      DEST="$2"; shift 2 ;;
    --reason)
      [ $# -ge 2 ] || fail "--reason needs a value"
      REASON="$2"; shift 2 ;;
    --ignored) IGNORED=1; shift ;;
    --check-ignored) CHECK_ONLY=1; shift ;;
    --allow-unsalvaged) ALLOW_UNSALV=1; shift ;;
    --dest=*)   DEST="${1#--dest=}"; shift ;;
    --reason=*) REASON="${1#--reason=}"; shift ;;
    -h|--help)
      printf 'usage: worktree-salvage.sh <worktree path> [--dest <dir>] [--reason <text>] [--ignored [--allow-unsalvaged]]\n       worktree-salvage.sh <worktree path> --check-ignored\n'
      exit 0 ;;
    *)
      if [ -z "$WT" ]; then WT="$1"; shift
      else fail "unexpected argument: $1"
      fi ;;
  esac
done
# SALVAGE_MUTANT_ANCHOR — argument parsing ends here; detection and capture follow.
# (test-worktree-salvage.sh derives its mutant by inserting `exit 0` after this line.)

[ -n "$WT" ] || fail "usage: worktree-salvage.sh <worktree path> [--dest <dir>] [--reason <text>] [--ignored]"
command -v git >/dev/null 2>&1 || fail "git not found"
[ -d "$WT" ] || fail "not a directory: $WT"
WT_TOP="$(cd "$WT" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" \
  || fail "not a git worktree: $WT"
[ -n "$WT_TOP" ] || fail "not a git worktree: $WT"

# ---- --check-ignored / --ignored: the coverage check (read-only) --------------
# Every gitignored entry neither salvaged, regenerable nor empty (empty = all covered).
# Unlistable ⇒ fail (the verdict is `failed`, so the caller keeps the worktree).
IGN_UNSALV=""
if [ "$CHECK_ONLY" -eq 1 ] || { [ "$IGNORED" -eq 1 ] && [ "$ALLOW_UNSALV" -eq 0 ]; }; then
  IGN_UNSALV="$(ign_unsalvaged)" || fail "cannot list the gitignored entries of $WT_TOP"
fi
if [ "$CHECK_ONLY" -eq 1 ]; then
  if [ -n "$IGN_UNSALV" ]; then printf 'ignored-check: unsalvaged %s\n' "$IGN_UNSALV"; else printf 'ignored-check: ok\n'; fi
  exit 0
fi

# ---- detection ---------------------------------------------------------------
TMP="$(mktemp 2>/dev/null)" || fail "cannot create a temp file"
[ -n "$TMP" ] || fail "cannot create a temp file"
trap 'rm -f "$TMP"' EXIT
if ! git -C "$WT_TOP" status --porcelain=v1 -z --untracked-files=all > "$TMP" 2>/dev/null; then
  fail "git status failed in $WT_TOP"
fi
# --ignored: the PRESENT entries of the fixed salvage list (ign_salvage_list —
# never a word-split variable). Read before the clean-tree exit so a tree that is
# clean in git's terms but holds runtime logs is still salvaged.
IGN_LIST=""
IGN_N=0
if [ "$IGNORED" -eq 1 ]; then
  while IFS= read -r IGN_REL; do
    [ -n "$IGN_REL" ] || continue
    if [ -e "$WT_TOP/$IGN_REL" ] || [ -L "$WT_TOP/$IGN_REL" ]; then
      IGN_LIST="$IGN_LIST$IGN_REL
"
      IGN_N=$((IGN_N + 1))
      [ -n "$IGN_FIRST" ] || IGN_FIRST="$IGN_REL"
    fi
  done <<IGNSALV
$(ign_salvage_list)
IGNSALV
fi
# Clean worktree ⇒ nothing to keep ⇒ silent, no directory, exit 0 (--ignored with
# no entry present: the verdict alone, still no directory — `ignored: ok 0`, or
# the unsalvaged-content failure when the coverage check named an entry).
if [ ! -s "$TMP" ]; then
  [ "$IGNORED" -eq 1 ] || exit 0
  if [ "$IGN_N" -eq 0 ]; then
    if [ -n "$IGN_UNSALV" ]; then printf 'ignored: failed %s — unsalvaged ignored content\n' "$IGN_UNSALV"
    else printf 'ignored: ok 0\n'; fi
    exit 0
  fi
fi

# ---- destination + name (only now — detection found content) -----------------
if [ -z "$DEST" ]; then
  COMMON="$(cd "$WT_TOP" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)"
  [ -n "$COMMON" ] || fail "cannot resolve the primary checkout for $WT_TOP"
  PRIMARY="$(cd "$WT_TOP" 2>/dev/null && cd "$COMMON/.." 2>/dev/null && pwd -P)"
  [ -n "$PRIMARY" ] || fail "cannot resolve the primary checkout for $WT_TOP"
  DEST="$PRIMARY/.supervisor/salvage"
fi
NAME="$(basename "$WT_TOP")"
TS=""
case "${LOOMWRIGHT_SALVAGE_TS:-}" in
  [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) TS="$LOOMWRIGHT_SALVAGE_TS" ;;
esac
[ -n "$TS" ] || TS="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)"
[ -n "$TS" ] || fail "cannot read the clock"

mkdir -p "$DEST" 2>/dev/null || fail "cannot create destination $DEST"
[ -d "$DEST" ] && [ -w "$DEST" ] || fail "destination not writable: $DEST"
SALVAGE_DIR="$DEST/$NAME-$TS"
N=1
while [ -e "$SALVAGE_DIR" ]; do
  N=$((N + 1))
  [ "$N" -le 999 ] || fail "no free salvage name under $DEST for $NAME-$TS (cap 999)"
  SALVAGE_DIR="$DEST/$NAME-$TS-$N"
done
mkdir "$SALVAGE_DIR" 2>/dev/null || fail "cannot create $SALVAGE_DIR"

# ---- capture (best-effort per step, README last) -----------------------------
STATUS="complete"
step_fail() { [ "$STATUS" = "complete" ] && STATUS="partial ($1 failed)"; }

# On an unborn HEAD `git rev-parse HEAD` prints the literal `HEAD` (rc 128) — a
# non-empty string, so emptiness alone would record `BASE_SHA: HEAD` as complete.
# The value must be a full hex SHA; anything else (empty, `HEAD`, an error echo)
# is `unknown` and the README's status reads `partial (BASE_SHA failed)`.
BASE="$(git -C "$WT_TOP" rev-parse HEAD 2>/dev/null)" || BASE=""
case "$BASE" in
  ''|*[!0-9a-f]*) BASE="" ;;
esac
if [ -n "$BASE" ] && printf '%s\n' "$BASE" > "$SALVAGE_DIR/BASE_SHA" 2>/dev/null; then
  :
else
  BASE="unknown"; step_fail "BASE_SHA"
fi
git -C "$WT_TOP" diff --binary HEAD > "$SALVAGE_DIR/tracked.patch" 2>/dev/null || step_fail "tracked.patch"

SUBMODULE_SKIPPED=0
NESTED_REPO_COPIED=0
while IFS= read -r -d '' ENTRY; do
  X="${ENTRY:0:1}"
  Y="${ENTRY:1:1}"
  REL="${ENTRY:3}"
  # A rename/copy entry carries one extra NUL-terminated field: the ORIGIN path
  # (with -z the order is `XY new\0old\0`). Consume it EXACTLY ONCE; REL is already
  # the NEW path. Skipping this read would feed the origin path into the next
  # iteration as a record of its own (a desynced stream).
  case "$X$Y" in
    R?|C?|?R|?C) IFS= read -r -d '' _ORIGIN || true ;;
  esac
  # git lists an untracked DIRECTORY with a trailing `/` (`?? nested/`); strip it so
  # the copy lands at `untracked/nested`, not at a path cp may interpret as
  # "contents of". A single suffix strip — not the O(n²) `${var//…}` form.
  REL="${REL%/}"
  [ -n "$REL" ] || continue
  SRC="$WT_TOP/$REL"
  if [ "$X$Y" = "??" ]; then
    SUB="untracked"
  else
    SUB="modified"
  fi
  IS_NESTED_REPO=0
  if [ -d "$SRC" ] && [ ! -L "$SRC" ]; then
    if [ "$SUB" = "modified" ]; then
      # A modified (or newly added) SUBMODULE — a directory with nothing to copy
      # verbatim; the patch carries it as a `Subproject commit` line and the README
      # says so. This is the ONLY skip of a directory entry.
      SUBMODULE_SKIPPED=1
      continue
    fi
    # An UNTRACKED directory reaches the stream under --untracked-files=all only
    # when git refused to descend into it: a NESTED REPOSITORY (a stray clone or
    # `git init` a worker left behind). It IS uncommitted content, so it is copied
    # verbatim below like any other `??` entry — its own `.git` travels with it —
    # and the README names it. Before this branch existed the entry was silently
    # `continue`d past and the salvage still reported `status: complete`.
    IS_NESTED_REPO=1
  fi
  [ -e "$SRC" ] || [ -L "$SRC" ] || continue   # deleted — the patch carries it
  DST="$SALVAGE_DIR/$SUB/$REL"
  if mkdir -p "$(dirname "$DST")" 2>/dev/null && cp -pR "$SRC" "$DST" 2>/dev/null; then
    [ "$IS_NESTED_REPO" -eq 1 ] && NESTED_REPO_COPIED=1
  else
    step_fail "$SUB/$REL"
  fi
done < "$TMP"

# ---- --ignored: copy + verify each present gitignored runtime entry ------------
# Stops at the first failure; the verdict names that entry. `diff -r` is the
# byte-identity check (content, recursively — a partial `cp` or a source that
# changed mid-copy reads as a failure).
IGN_VERDICT=""
IGN_DONE=0
if [ "$IGNORED" -eq 1 ]; then
  while IFS= read -r IGN_REL; do
    [ -n "$IGN_REL" ] || continue
    IGN_DST="$SALVAGE_DIR/ignored/$IGN_REL"
    # IGNORED_COPY_ANCHOR — test-worktree-salvage.sh's pin mutation deletes this copy.
    if ! mkdir -p "$(dirname "$IGN_DST")" 2>/dev/null || ! cp -pR "$WT_TOP/$IGN_REL" "$IGN_DST" 2>/dev/null; then
      IGN_VERDICT="ignored: failed $IGN_REL — copy failed"; break
    fi
    if ! diff -r "$WT_TOP/$IGN_REL" "$IGN_DST" >/dev/null 2>&1; then
      IGN_VERDICT="ignored: failed $IGN_REL — copy is not byte-identical"; break
    fi
    IGN_DONE=$((IGN_DONE + 1))
  done <<IGNLIST
$IGN_LIST
IGNLIST
  # FAIL CLOSED on coverage: every listed entry copied, but gitignored content the
  # list does not cover (and that is not regenerable) would still be deleted.
  if [ -z "$IGN_VERDICT" ] && [ -n "$IGN_UNSALV" ]; then
    IGN_VERDICT="ignored: failed $IGN_UNSALV — unsalvaged ignored content"
  fi
  [ -n "$IGN_VERDICT" ] || IGN_VERDICT="ignored: ok $IGN_DONE"
fi

BRANCH="$(git -C "$WT_TOP" rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -n "$BRANCH" ] || BRANCH="HEAD"

# ---- README (every caller-controlled field goes through printf '%s') ----------
write_readme() {
  printf '# Worktree salvage — '; printf '%s' "$NAME"; printf '\n\n'
  printf 'worktree: '; printf '%s' "$WT_TOP"; printf '\n'
  printf 'branch: ';   printf '%s' "$BRANCH"; printf '\n'
  printf 'BASE_SHA: '; printf '%s' "$BASE";   printf '\n'
  printf 'removed: ';  printf '%s' "$TS";     printf '\n'
  printf 'reason: ';   printf '%s' "$REASON"; printf '\n'
  printf 'status: ';   printf '%s' "$STATUS"; printf '\n\n'
  printf 'Uncommitted content captured by scripts/worktree-salvage.sh immediately before a\n'
  printf 'plugin-owned `git worktree remove` of this worktree.\n\n'
  printf '## Recovering\n\n'
  printf '1. `modified/` holds each changed tracked file VERBATIM as it stood in the\n'
  printf '   worktree — use these first; they need no patch application.\n'
  printf '2. `tracked.patch` is a diff against `BASE_SHA` — that worktree'"'"'s own HEAD — not\n'
  printf '   against current `main`, so it will NOT apply to current `main` directly. To use it:\n\n'
  printf '       git checkout -b salvage-'; printf '%s' "$NAME"; printf ' $(cat BASE_SHA)\n'
  printf '       git apply tracked.patch\n\n'
  printf '3. `untracked/` holds files that were never added to git, copied verbatim with\n'
  printf '   their relative paths.\n'
  printf '4. Deleted tracked files have nothing to copy — they appear only in the patch.\n'
  ITEM=5
  if [ "$SUBMODULE_SKIPPED" -eq 1 ]; then
    printf '%s. A modified (or newly added) submodule is a directory and is not copied into\n' "$ITEM"
    printf '   `modified/`; it appears in the patch as a `Subproject commit` line.\n'
    ITEM=$((ITEM + 1))
  fi
  if [ "$NESTED_REPO_COPIED" -eq 1 ]; then
    printf '%s. Nested repositories: an untracked directory that is itself a git repository\n' "$ITEM"
    printf '   (a stray clone or `git init`) is copied verbatim under `untracked/`, its own\n'
    printf '   `.git` included — nothing inside it was ever committed to this repository.\n'
  fi
  printf '\n## Not captured\n\n'
  printf 'Gitignored runtime state (`.supervisor/` logs, drain rounds, scratch) is per-checkout\n'
  printf 'by design and is not uncommitted work — it is never listed by `git status` without\n'
  printf '`--ignored`, so the salvage holds work, not noise.\n'
  if [ "$IGNORED" -eq 1 ]; then
    printf '\n## Gitignored runtime content (--ignored)\n\n'
    printf 'This salvage was asked for it: `ignored/` holds each present entry of the\n'
    printf 'salvage list, verified byte-identical:\n\n'
    # The list is read from ign_salvage_list, never restated here.
    ign_salvage_list | while IFS= read -r IGN_REL; do printf -- '- `%s`\n' "$IGN_REL"; done
    printf '\nVerdict: '; printf '%s' "$IGN_VERDICT"; printf '\n'
  fi
}
if ! write_readme > "$SALVAGE_DIR/README.md" 2>/dev/null; then
  printf 'worktree-salvage: README.md write failed in %s\n' "$SALVAGE_DIR" >&2
fi

printf '%s\n' "$SALVAGE_DIR"
[ "$IGNORED" -eq 1 ] && printf '%s\n' "$IGN_VERDICT"
exit 0
