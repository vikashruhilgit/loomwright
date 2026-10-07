#!/usr/bin/env bash
# loom-log-owner.sh — sourceable helper: THE run-ownership rule for a plugin session log, and THE
# main-worktree anchoring rule for `.supervisor/`.
#
# Extracted from emit-lifecycle.sh (automate-followups/33) so guard-finalize-publish.sh can join a
# hook payload's Claude Code session id to the plugin session id by the SAME rule, never a restated
# copy. emit-progress-event.sh / emit-token-ledger.sh still carry byte-parallel inline copies (see
# their comments); converging them on this file is a separate change.
#
# loom_log_owner <log> — prints the `cc_session_id` on the log's FIRST line, or nothing. UNKNOWN
# OWNER MEANS ADOPT (non-negotiable, see emit-progress-event.sh): an absent, empty, or unreadable
# log, an unparseable first line, a first line with no `cc_session_id`, or a missing jq all print
# nothing and return 0 — the caller treats empty as "adopt".
#
# loom_main_root [dir] — prints the MAIN worktree of the repo containing <dir> (default: the cwd):
# the first entry of `git worktree list --porcelain`, accepted only when its own `--show-toplevel`
# equals it. That is where build-state.sh and the emitters (emit-lifecycle.sh, emit-agent-identity.sh,
# emit-token-ledger.sh) keep `.supervisor/`, correct from inside any linked worktree (detached
# included). Prints nothing and returns 1 when it cannot be resolved — the CALLER picks the failure
# direction (emitters exit 0; guard-finalize-publish.sh falls back to the project dir).
#
# Sourcing has no side effects beyond defining the functions. bash 3.2 safe.
loom_log_owner() {
  local _log="${1:-}" _first=""
  [ -n "$_log" ] && [ -f "$_log" ] && [ -r "$_log" ] || return 0
  _first="$(head -1 "$_log" 2>/dev/null || true)"
  [ -n "$_first" ] || return 0
  printf '{}' | jq -e . >/dev/null 2>&1 || return 0
  printf '%s' "$_first" | jq -r '.cc_session_id // empty' 2>/dev/null || true
  return 0
}

loom_main_root() {
  local _dir="${1:-.}" _m="" _top=""
  _m="$(git -C "$_dir" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [ -n "$_m" ] && [ -d "$_m" ] || return 1
  _top="$(git -C "$_m" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
  [ "$_top" = "$_m" ] || return 1
  printf '%s' "$_m"
}
