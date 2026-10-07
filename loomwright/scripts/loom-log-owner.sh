#!/usr/bin/env bash
# loom-log-owner.sh — sourceable helper: THE run-ownership rule for a plugin session log.
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
# Sourcing has no side effects beyond defining the function. bash 3.2 safe.
loom_log_owner() {
  local _log="${1:-}" _first=""
  [ -n "$_log" ] && [ -f "$_log" ] && [ -r "$_log" ] || return 0
  _first="$(head -1 "$_log" 2>/dev/null || true)"
  [ -n "$_first" ] || return 0
  printf '{}' | jq -e . >/dev/null 2>&1 || return 0
  printf '%s' "$_first" | jq -r '.cc_session_id // empty' 2>/dev/null || true
  return 0
}
