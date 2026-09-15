#!/usr/bin/env bash
# propose-common.sh - the shared blast-radius guard for every `/propose` basis. MEANT TO BE
# SOURCED, never executed directly (it defines functions and returns; it has no main).
#
# WHY THIS FILE EXISTS. `propose-work.sh` (the ledger basis) and `propose-domain.sh` (the domain
# basis) each shipped their OWN inline `guarded_write()`, and by the time a third basis
# (`propose-from-verify.sh`) needed the same guard, the two originals had already drifted:
# `propose-domain.sh`'s copy additionally refused a pre-existing symlink or non-regular-file
# occupant and staged the write through a temp file + `mv -f` (closing a hostile-hardlink and a
# check-then-write TOCTOU window that `propose-work.sh`'s plain `cat >` copy did not). This file
# is the RECONCILED, canonical version - the hardened one - so a THIRD caller never has to choose
# which drifted copy to trust or write a fourth one of its own.
#
# guarded_write() BELOW IS THAT CANONICAL VERSION, and `propose-from-verify.sh` sources this file
# and calls it directly - "never copied a third time" for any NEW basis from here on.
#
# `propose-work.sh` and `propose-domain.sh` themselves are DELIBERATELY NOT switched to source
# this file. Each one's own self-test (`test-propose-work.sh` AC8, `test-propose-domain.sh` AC10)
# proves its blast-radius guard is load-bearing with a MUTATION CONTROL that `sed`-deletes the
# marked `>>> WRITE-PATH GUARD ... <<< END WRITE-PATH GUARD` block DIRECTLY OUT OF THAT SCRIPT'S
# OWN FILE TEXT and asserts the guard's absence actually lets a hostile write escape. If either
# script sourced this file instead of defining the function inline, that guard block would no
# longer exist in the script's own text - the mutation control's `sed` would delete nothing, the
# "mutant" would be byte-identical to the original, and the control would report "could not build
# a valid mutant" instead of proving the guard is load-bearing. Sourcing would not soften the
# guard - the guard would still run, unchanged, from this file - but it would SILENTLY DISABLE the
# test that proves it, turning a real safety net into an unfalsifiable green. That is the exact
# "claim no check backs" defect class this repo keeps meeting, so this file deliberately keeps
# `propose-work.sh` and `propose-domain.sh`'s own inline copies in place, RECONCILED to be
# byte-for-byte the same guard behaviour as this canonical version (both now carry the hardened
# symlink / non-regular-file / staged-write checks propose-domain.sh originated), rather than
# deleting them. The two inline copies and this file are meant to be changed together; a future
# edit to guarded_write's behaviour must land in all three, and a manual diff (or a future
# test-propose-common.sh) is how that lockstep gets checked - there is no automated byte-diff gate
# today, which is the one honest gap in "never copied a third time" as applied to the two
# PRE-EXISTING copies (only the third-and-later caller is structurally prevented from drifting, by
# sourcing this file instead of writing its own).
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
