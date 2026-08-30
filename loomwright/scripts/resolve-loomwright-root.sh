#!/usr/bin/env bash
# resolve-loomwright-root.sh — the ONE place the plugin is allowed to name its host harness.
#
# WHY: the plugin's runtime scripts locate their own installed root through a
# harness-specific environment variable. Every script that reads that variable
# directly is a hard-coded dependency on one vendor, and there are hundreds of
# them. This resolver exists so there can eventually be exactly ONE: it reads the
# harness variable here, publishes the vendor-NEUTRAL `LOOMWRIGHT_ROOT`, and lets
# every other script depend on the neutral name. Porting to another harness then
# means adding one arm to this file, not editing hundreds of call sites.
#
# THIS FILE IS DELIBERATELY ADAPTER-CLASSIFIED in
# loomwright/docs/vendor-coupling-manifest.json and is therefore exempt from the
# vendor-coupling ratchet (scripts/check-vendor-coupling.sh). That is load-bearing,
# not an oversight: a gate that flagged this file would be flagging the seam that
# exists to remove the coupling everywhere else.
#
# CONTRACT
#   Publishes (exports) LOOMWRIGHT_ROOT, resolved by this precedence:
#     1. The Claude Code harness variable CLAUDE_PLUGIN_ROOT, if set and non-empty
#        -> LOOMWRIGHT_ROOT is EXACTLY that value, byte for byte. It is NOT
#           normalized, symlink-resolved, or existence-checked: the harness owns
#           that path and is authoritative about it.
#     2. An explicitly pre-set, non-empty LOOMWRIGHT_ROOT (a non-Claude adapter
#        setting the neutral name directly). Ranked BELOW the harness variable
#        because arm 1 is a stated contract; in practice the two never both apply
#        — a non-Claude harness does not set CLAUDE_PLUGIN_ROOT.
#     3. Dev-checkout fallback: the parent directory of this script's own
#        location (loomwright/scripts/.. == loomwright/). Location-derived, never
#        hard-coded, so a relocated or copied plugin tree still resolves.
#
# USAGE
#   Sourced (the intended form — sets LOOMWRIGHT_ROOT in the caller):
#       . "$(dirname "$0")/resolve-loomwright-root.sh"
#   Executed (prints the resolved root on stdout):
#       LOOMWRIGHT_ROOT="$(bash loomwright/scripts/resolve-loomwright-root.sh)"
#
# EXIT CODES (executed form)
#   0 = resolved; the path is printed on stdout.
#   1 = could not resolve (no harness variable, no pre-set value, and the
#       script's own location could not be determined). Fails CLOSED — it never
#       prints a guessed or empty root.
#       NOTE: this branch is UNTESTED — see the header of
#       test-resolve-loomwright-root.sh for why no honest fixture can reach
#       it. Treat it as reasoned-correct, not as execution-verified like
#       every other behaviour of this script.
#
# NOT IN SCOPE: migrating existing call sites onto LOOMWRIGHT_ROOT. This file
# creates the seam; the migration is separate, tracked work.
#
# Portability: bash 3.2 / BSD userland safe. No GNU-only stat/sed/date flags, no
# `realpath`/`readlink -f` (neither is portable to macOS), no subshell-unsafe
# constructs. Resolution is pure `cd`+`pwd`, which is POSIX.

# NOTE: no `set -e`/`set -u` here — this file is meant to be SOURCED, and those
# options would leak into (and can abort) the caller's shell.

__lw_resolve_root() {
  local src dir

  # Arm 1 — harness-provided root wins, verbatim.
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    printf '%s' "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi

  # Arm 2 — an adapter that already published the neutral name.
  if [ -n "${LOOMWRIGHT_ROOT:-}" ]; then
    printf '%s' "$LOOMWRIGHT_ROOT"
    return 0
  fi

  # Arm 3 — dev checkout: derive from this file's own location.
  # BASH_SOURCE is correct when sourced; $0 is the fallback when executed by a
  # shell that does not populate it.
  src="${BASH_SOURCE[0]:-$0}"
  [ -n "$src" ] || return 1
  dir="$(cd "$(dirname "$src")/.." 2>/dev/null && pwd)" || return 1
  [ -n "$dir" ] || return 1
  printf '%s' "$dir"
  return 0
}

# Sourced or executed? Decides whether the failure path must `return` or `exit`,
# and whether the resolved root is printed.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then __lw_executed=1; else __lw_executed=0; fi

__lw_root="$(__lw_resolve_root)"
if [ -z "$__lw_root" ]; then
  echo "resolve-loomwright-root: could not resolve LOOMWRIGHT_ROOT" >&2
  unset __lw_root __lw_resolve_root 2>/dev/null
  unset -f __lw_resolve_root 2>/dev/null
  if [ "$__lw_executed" -eq 1 ]; then unset __lw_executed; exit 1; fi
  unset __lw_executed
  return 1
fi

LOOMWRIGHT_ROOT="$__lw_root"
export LOOMWRIGHT_ROOT
unset __lw_root
unset -f __lw_resolve_root 2>/dev/null

# When EXECUTED (not sourced), print the resolved root so callers can capture it.
if [ "$__lw_executed" -eq 1 ]; then
  printf '%s\n' "$LOOMWRIGHT_ROOT"
fi
unset __lw_executed
