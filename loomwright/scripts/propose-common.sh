#!/usr/bin/env bash
# propose-common.sh - the shared blast-radius guard for every `/propose` basis. MEANT TO BE
# SOURCED, never executed directly (it defines functions and returns; it has no main).
#
# WHY THIS FILE EXISTS. `propose-work.sh` (the ledger basis) and `propose-domain.sh` (the domain
# basis) each ORIGINALLY shipped their OWN inline `guarded_write()`, and by the time a third basis
# (`propose-from-verify.sh`) needed the same guard, the two originals had already drifted:
# `propose-domain.sh`'s copy additionally refused a pre-existing symlink or non-regular-file
# occupant and staged the write through a temp file + `mv -f` (closing a hostile-hardlink and a
# check-then-write TOCTOU window that `propose-work.sh`'s plain `cat >` copy did not).
#
# pc_guarded_write() BELOW IS THE RECONCILED, CANONICAL VERSION - the hardened one - and ALL
# THREE bases (`propose-work.sh`, `propose-domain.sh`, `propose-from-verify.sh`) now SOURCE this
# file and call it directly. There is exactly ONE copy of this guard in the whole repo; "never
# copied a third time" holds for every caller, including the two pre-existing ones, not only for
# a new one.
#
# HOW THE MUTATION CONTROL STAYS LIVE ACROSS A SOURCED GUARD. Each caller's own self-test
# (`test-propose-work.sh` AC8, `test-propose-domain.sh` AC10, `test-propose-common.sh`) proves the
# guard is load-bearing with a MUTATION CONTROL - but the guard block no longer lives in the
# caller's own file text, so a `sed` against the CALLER would delete nothing and build a
# byte-identical, uncontrolled "mutant". Every mutation control therefore mutates a COPY of THIS
# FILE instead: it `sed`-deletes the guard function's marked comment-delimited block (see that
# block's own opening and closing comment lines, just below, for the exact marker text a `sed`
# range targets - not spelled out again here so this prose paragraph itself can never become a
# second, false match for that same `sed` range) out of a copy of `propose-common.sh`, and points
# the UNMODIFIED caller script's sourcing at that mutant copy through `PROPOSE_COMMON_SH` - each
# of the three callers resolves its sibling as
# `"${PROPOSE_COMMON_SH:-$SCRIPT_DIR/propose-common.sh}"`, so the env var overrides the
# `SCRIPT_DIR`-relative default without touching the caller's own file text at all. That override
# is a TEST-ONLY knob, always unset in a real run, and is the "or an overridable source path"
# half of the same technique `test-propose-from-verify.sh`'s own AC12 evidence-section mutant
# already used (there, a scratch-dir copy) before this guard was extracted into this file.
#
# CONTRACT (identical to every basis that uses it, restated in every emitted proposal file too):
#   the output directory (normally `.supervisor/requirements/proposed/`) is deliberately NOT an
#   `/automate --folder` target; promotion is a human moving a file out of it. IT PROPOSES; IT
#   NEVER QUEUES. Nothing here enqueues, dispatches, ranks, scores or merges.
#
# Usage (sourced, not executed):
#   . "$(dirname "$0")/propose-common.sh"
#   pc_guarded_write "$OUT_DIR_ABS" "<self-name-for-temp-file>" "<plain-file-name>"   # content on stdin
#
# `$OUT_DIR_ABS` MUST already be the fully-resolved (`cd ... && pwd`) absolute path of the output
# directory - this file never resolves it and never creates it (`mkdir -p` is the caller's job,
# same as every existing basis). `<self-name-for-temp-file>` is a short, filesystem-safe token
# (e.g. `propose-from-verify`) folded into the staged temp file's name only, for readability in an
# `ls` of a half-finished write; it is never validated as an identity and carries no security
# meaning.
#
# PORTABILITY / DISCIPLINE - mirrors propose-work.sh and propose-domain.sh:
#   * `set -uo pipefail`, no `set -e` - this file is sourced into an advisory producer that must
#     never be broken by a guard failure; every guard failure is a `return 1` from the function,
#     never an `exit`.
#   * No `stat`, no `timeout`, no GNU-only / BSD-only date flags anywhere in this file.

set -uo pipefail

# pc_guarded_write <out_dir_abs> <self_name> <plain-file-name> - the SINGLE enforcement point for
# every basis that sources this file. Content arrives on stdin. Returns 0 on a successful write,
# 1 (with the reason named on stderr) on any refusal.
#
# Deliberately the ONLY sanitisation a caller needs: a second, redundant check at the call site
# would make THIS guard's own mutation control (in whichever self-test exercises it) vacuous - a
# test could delete this function's guard block and nothing would escape, because the caller's own
# redundant check would still catch it, and the test would stay green with the mechanism it is
# supposed to be proving deleted.
pc_guarded_write() {
  pc_out_dir_abs="$1"
  pc_self="$2"
  pc_name="$3"
  # >>> WRITE-PATH GUARD (a mutation control deletes this marked block)
  case "$pc_name" in
    ''|.|..|.*|*/*|*'\'*)
      echo "$pc_self: refusing to write '$pc_name' - not a plain file name under $pc_out_dir_abs" >&2
      cat >/dev/null; return 1 ;;
  esac
  # Unreachable defence-in-depth: the case above already rejects any name containing "/", so
  # dirname is always $pc_out_dir_abs and this cannot fire. Kept so the guard still holds if that
  # case is ever narrowed. Not load-bearing - the case above is the traversal defence.
  pc_guard_parent="$(cd "$(dirname "$pc_out_dir_abs/$pc_name")" 2>/dev/null && pwd)"
  if [ "$pc_guard_parent" != "$pc_out_dir_abs" ]; then
    echo "$pc_self: refusing to write '$pc_name' - resolves outside $pc_out_dir_abs" >&2
    cat >/dev/null; return 1
  fi
  # A legal plain name can still be a pre-existing SYMLINK planted in the output directory, and
  # `cat >` FOLLOWS a symlink - which walks the write outside the directory the name guard just
  # proved it was inside. Refuse rather than unlink: this basis never removes a file it did not
  # write, and a symlink here is hostile input, not a stale artefact to tidy.
  if [ -L "$pc_out_dir_abs/$pc_name" ]; then
    echo "$pc_self: refusing to write '$pc_name' - it is a symlink, and writing through it would leave $pc_out_dir_abs" >&2
    cat >/dev/null; return 1
  fi
  # A pre-existing entry that is not a REGULAR file. This matters specifically because the write
  # below is `mv -f`: mv into a DIRECTORY succeeds, moving the temp entry inside it and returning
  # 0, so the run counts a candidate it never wrote and abandons a PID-named temp in a tree this
  # basis promises to leave nothing extra in.
  if [ -e "$pc_out_dir_abs/$pc_name" ] && [ ! -f "$pc_out_dir_abs/$pc_name" ]; then
    echo "$pc_self: refusing to write '$pc_name' - something that is not a regular file already occupies that name" >&2
    cat >/dev/null; return 1
  fi
  # <<< END WRITE-PATH GUARD
  # Write to a temp entry inside the output dir and `mv -f` it into place. `mv` REPLACES the
  # directory entry rather than writing through whatever occupies it, which closes three things
  # the `-L` test above cannot: a HARDLINK at a legal name (`[ -L ]` is false for one, and `cat >`
  # truncates the shared inode), the check-then-write TOCTOU race on the symlink path, and any
  # future link type. The `-L` refusal is kept above because naming a planted symlink is more
  # useful to a human than silently replacing it.
  pc_tmp="$pc_out_dir_abs/.tmp.$pc_self.$$"
  { cat > "$pc_tmp"; } 2>/dev/null || {
    rm -f "$pc_tmp" 2>/dev/null
    echo "$pc_self: cannot write $pc_out_dir_abs/$pc_name - skipping this candidate" >&2
    return 1
  }
  mv -f "$pc_tmp" "$pc_out_dir_abs/$pc_name" 2>/dev/null && [ -f "$pc_out_dir_abs/$pc_name" ] || {
    rm -f "$pc_tmp" 2>/dev/null
    echo "$pc_self: cannot move the staged candidate into place at $pc_out_dir_abs/$pc_name - skipping this candidate" >&2
    return 1
  }
  return 0
}

# pc_slugify <text> - lower-cased, non-alnum runs collapsed to one `-`, edge dashes trimmed,
# truncated to 60 chars so a long AC/issue text cannot produce an unwieldy filename. Empty input
# (or input that slugifies to nothing, e.g. all punctuation) yields the literal string `item` -
# never an empty component, which would collide two distinct filenames onto the same directory
# entry through guarded_write's `mv -f`.
pc_slugify() {
  pc_slug="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-60)"
  [ -n "$pc_slug" ] || pc_slug="item"
  printf '%s' "$pc_slug"
}
