#!/usr/bin/env bash
# contained-path-lib.sh — physical-path containment for repo-relative config writers. SOURCE it,
# never execute it; it has no top-level side effects (no `set`, no output, no traps), so a writer
# can load it lazily, immediately before the one write it guards:
#
#   . "$(dirname "$0")/contained-path-lib.sh" 2>/dev/null || <refuse in the writer's own convention>
#   cpl_check_write <label> "$CFG" "$REPO" [<symlink-reason>] || <refuse; CPL_REASON says why>
#
# WHY: a repo can commit a symlinked parent directory (`.supervisor -> /somewhere/else`). A writer
# that only tests its leaf (`[ -L "$CFG" ]`) then rewrites — and leaves a backup beside — a file
# elsewhere on the machine. cpl_check_write resolves the target PHYSICALLY and refuses
# `path_outside_repo` when it is not under the repo's physical root. An inside-pointing symlink
# and a repo reached through a symlinked ancestor (macOS /tmp -> /private/tmp) both still pass.
#
# Only repo-relative files belong here. User-scope files (settings.json, egress.json,
# meta-sync-consent.json, rules-check-stamp.json) are exempt on purpose: they live outside any repo
# and some are meant to be symlinks into a dotfiles checkout.
#
# bash 3.2 + BSD/GNU userland: plain `readlink` (no -f), `cd -P`/`pwd -P`, `-ef`; no realpath.
#
# API:
#   cpl_phys <abs-path>               print the physical path (symlinks and directory aliases
#                                     resolved); a missing target resolves its nearest existing
#                                     ancestor and re-appends the missing tail. Non-absolute,
#                                     dangling, over-long chain, or a `.`/`..` tail ⇒ return 1.
#   cpl_inside <physical-path> <root> return 0 iff the path's directory is <root> or lies beneath
#                                     it (device+inode ancestor walk). A walk that exhausts its
#                                     cap returns 1 — fail CLOSED.
#   cpl_check_write <label> <target> <repo-root> [<symlink-reason>]
#                                     return 0, silent, when the write is allowed. Otherwise set
#                                     CPL_REASON, print ONE headline
#                                     `<label>: ABORTED (<reason>) — <why>. Nothing was written.`
#                                     to stdout and return 1. Reasons: <symlink-reason> (default
#                                     `symlink`, when the leaf is a symlink) or `path_outside_repo`
#                                     (target or root unresolvable, or target outside the root).
#
# cpl_phys and cpl_inside are COPIES of automate-helpers.sh `gate_eval`'s `_ge_phys` / `_ge_inside`
# (the merge executor stays byte-identical on purpose), with two deliberate differences: cpl_phys
# also resolves a not-yet-existing target, and cpl_inside's exhausted cap means "outside".

CPL_REASON=""

# cpl_phys <abs-path> — see the header. Follows a symlinked final component with a bounded hop
# count (the kernel's ELOOP), then resolves the directory part with `cd -P`.
cpl_phys() {
  local p="$1" n=0 t d b cur tail="" comp parent
  case "$p" in /*) ;; *) return 1 ;; esac
  while [ -L "$p" ]; do
    n=$((n + 1)); [ "$n" -le 40 ] || return 1
    t="$(readlink "$p" 2>/dev/null)" || return 1
    [ -n "$t" ] || return 1
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
  done
  d="$(dirname "$p")"; b="$(basename "$p")"
  case "$b" in ""|.|..|/) return 1 ;; esac
  # Walk up to the nearest EXISTING directory; the components skipped on the way are the missing
  # tail. A symlink met on the walk that is not a usable directory (dangling, or pointing at a
  # file) fails: it must never fall through to "an ancestor exists, so inside".
  cur="$d"
  while :; do
    if [ -d "$cur" ]; then
      d="$(CDPATH='' cd -P -- "$cur" 2>/dev/null && pwd -P)" || return 1
      break
    fi
    { [ -L "$cur" ] || [ -e "$cur" ]; } && return 1
    comp="$(basename "$cur")"
    case "$comp" in ""|.|..|/) return 1 ;; esac
    tail="/$comp$tail"
    parent="$(dirname "$cur")"
    [ "$parent" != "$cur" ] || return 1
    cur="$parent"
  done
  case "$d" in /*) ;; *) return 1 ;; esac
  [ "$d" = "/" ] && d=""
  printf '%s%s/%s' "$d" "$tail" "$b"
}

# cpl_inside <physical-path> <root> — 0 iff the path's directory IS <root> or lies beneath it.
# Ancestors are compared with `-ef` (device + inode), so a case-variant, firmlink or bind-mount
# spelling of the root is still the root. The one inversion from `_ge_inside`: an exhausted cap
# returns 1 (outside ⇒ refuse), because here "inside" means "allowed".
cpl_inside() {
  local d n=0; d="$(dirname "$1")"
  while :; do
    [ "$d" -ef "$2" ] && return 0
    case "$d" in /|"") return 1 ;; esac
    d="$(dirname "$d")"; n=$((n + 1)); [ "$n" -le 256 ] || return 1
  done
}

# cpl_check_write <label> <target> <repo-root> [<symlink-reason>] — see the header. A relative
# <target> or <repo-root> is made absolute against $PWD first (callers pass relative paths today).
cpl_check_write() {
  local _cpl_label="$1" _cpl_t="$2" _cpl_r="$3" _cpl_tp _cpl_rp
  CPL_REASON=""
  if [ -z "$_cpl_t" ] || [ -z "$_cpl_r" ]; then
    CPL_REASON=path_outside_repo
    printf '%s: ABORTED (path_outside_repo) — an empty target or repo root cannot be checked. Nothing was written.\n' "$_cpl_label"
    return 1
  fi
  case "$_cpl_t" in /*) ;; *) _cpl_t="$PWD/$_cpl_t" ;; esac
  case "$_cpl_r" in /*) ;; *) _cpl_r="$PWD/$_cpl_r" ;; esac
  set -- "$_cpl_label" "$_cpl_t" "$_cpl_r" "${4:-symlink}"
  if [ -L "$2" ]; then
    CPL_REASON="$4"
    printf '%s: ABORTED (%s) — %s is a symlink; refusing to write through it. Nothing was written.\n' "$1" "$4" "$2"
    return 1
  fi
  # The root is a directory: resolve it with `cd -P` (so a `.` or trailing-slash spelling works).
  if ! _cpl_rp="$(CDPATH='' cd -P -- "$3" 2>/dev/null && pwd -P)" || ! _cpl_tp="$(cpl_phys "$2")"; then
    CPL_REASON=path_outside_repo
    printf '%s: ABORTED (path_outside_repo) — the physical location of %s (repo %s) cannot be resolved. Nothing was written.\n' "$1" "$2" "$3"
    return 1
  fi
  if ! cpl_inside "$_cpl_tp" "$_cpl_rp"; then
    CPL_REASON=path_outside_repo
    printf '%s: ABORTED (path_outside_repo) — %s resolves to %s, outside the repo %s. Nothing was written.\n' "$1" "$2" "$_cpl_tp" "$_cpl_rp"
    return 1
  fi
  return 0
}
