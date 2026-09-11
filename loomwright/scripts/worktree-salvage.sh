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
#   worktree-salvage.sh <abs-or-rel worktree path> [--dest <dir>] [--reason <text>]
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
#                     a submodule entry is a directory and is skipped here, it
#                     appears in the patch as a `Subproject commit` line)
#   untracked/<rel>   every `??` entry, verbatim, relative path preserved
#   README.md         worktree, branch, BASE_SHA, removed ts, reason, status,
#                     recovery steps (modified/ first; the patch is against
#                     BASE_SHA — that worktree's own HEAD — and will NOT apply to
#                     current main), and what is deliberately not captured.
#   If a step fails the salvage continues and the README's `status:` reads
#   `partial (<step> failed)` instead of `complete`.
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
  printf 'worktree-salvage: %s\n' "$1" >&2
  exit 0
}

WT=""
DEST=""
REASON="unspecified"
while [ $# -gt 0 ]; do
  case "$1" in
    --dest)
      [ $# -ge 2 ] || fail "--dest needs a value"
      DEST="$2"; shift 2 ;;
    --reason)
      [ $# -ge 2 ] || fail "--reason needs a value"
      REASON="$2"; shift 2 ;;
    --dest=*)   DEST="${1#--dest=}"; shift ;;
    --reason=*) REASON="${1#--reason=}"; shift ;;
    -h|--help)
      printf 'usage: worktree-salvage.sh <worktree path> [--dest <dir>] [--reason <text>]\n'
      exit 0 ;;
    *)
      if [ -z "$WT" ]; then WT="$1"; shift
      else fail "unexpected argument: $1"
      fi ;;
  esac
done
# SALVAGE_MUTANT_ANCHOR — argument parsing ends here; detection and capture follow.
# (test-worktree-salvage.sh derives its mutant by inserting `exit 0` after this line.)

[ -n "$WT" ] || fail "usage: worktree-salvage.sh <worktree path> [--dest <dir>] [--reason <text>]"
command -v git >/dev/null 2>&1 || fail "git not found"
[ -d "$WT" ] || fail "not a directory: $WT"
WT_TOP="$(cd "$WT" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" \
  || fail "not a git worktree: $WT"
[ -n "$WT_TOP" ] || fail "not a git worktree: $WT"

# ---- detection ---------------------------------------------------------------
TMP="$(mktemp 2>/dev/null)" || fail "cannot create a temp file"
[ -n "$TMP" ] || fail "cannot create a temp file"
trap 'rm -f "$TMP"' EXIT
if ! git -C "$WT_TOP" status --porcelain=v1 -z --untracked-files=all > "$TMP" 2>/dev/null; then
  fail "git status failed in $WT_TOP"
fi
# Clean worktree ⇒ nothing to keep ⇒ silent, no directory, exit 0.
[ -s "$TMP" ] || exit 0

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
while IFS= read -r -d '' ENTRY; do
  X="${ENTRY:0:1}"
  Y="${ENTRY:1:1}"
  REL="${ENTRY:3}"
  # A rename/copy entry carries one extra NUL-terminated field: the ORIGIN path
  # (with -z the order is `XY new\0old\0`). Consume it; REL is already the NEW path.
  case "$X$Y" in
    R?|C?|?R|?C) IFS= read -r -d '' _ORIGIN || true ;;
  esac
  [ -n "$REL" ] || continue
  SRC="$WT_TOP/$REL"
  if [ "$X$Y" = "??" ]; then
    SUB="untracked"
  else
    SUB="modified"
  fi
  if [ -d "$SRC" ] && [ ! -L "$SRC" ]; then
    # A submodule (or an untracked dir git listed as one) — nothing to copy verbatim.
    [ "$SUB" = "modified" ] && SUBMODULE_SKIPPED=1
    continue
  fi
  [ -e "$SRC" ] || [ -L "$SRC" ] || continue   # deleted — the patch carries it
  DST="$SALVAGE_DIR/$SUB/$REL"
  if mkdir -p "$(dirname "$DST")" 2>/dev/null && cp -pR "$SRC" "$DST" 2>/dev/null; then
    :
  else
    step_fail "$SUB/$REL"
  fi
done < "$TMP"

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
  if [ "$SUBMODULE_SKIPPED" -eq 1 ]; then
    printf '5. A modified submodule is a directory and is not copied into `modified/`; it\n'
    printf '   appears in the patch as a `Subproject commit` line.\n'
  fi
  printf '\n## Not captured\n\n'
  printf 'Gitignored runtime state (`.supervisor/` logs, drain rounds, scratch) is per-checkout\n'
  printf 'by design and is not uncommitted work — it is never listed by `git status` without\n'
  printf '`--ignored`, so the salvage holds work, not noise.\n'
}
if ! write_readme > "$SALVAGE_DIR/README.md" 2>/dev/null; then
  printf 'worktree-salvage: README.md write failed in %s\n' "$SALVAGE_DIR" >&2
fi

printf '%s\n' "$SALVAGE_DIR"
exit 0
