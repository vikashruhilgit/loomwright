#!/usr/bin/env bash
# guard-finalize-publish.sh — FINALIZE point 5 by mechanism (automate-followups/33, Part B).
#
# Two modes, one file (so the marker format has exactly one writer and one reader):
#
#   guard-finalize-publish.sh                      PreToolUse[Bash] fail-CLOSED deny gate. Its
#                                                  hooks.json leaf carries NO `|| true` (CLAUDE.md
#                                                  §"Plugin Hooks"; the second fail-CLOSED command
#                                                  hook after guard-test-integrity.sh).
#   guard-finalize-publish.sh write-marker [--skip-children-check]
#                                                  The ONLY writer of the finalize-gate marker.
#
# WHY: FINALIZE point 5 (the children-settled check) was a numbered prose step, and a lane ran it
# AFTER pushing and opening its PR — nothing refused that. Now a Supervisor run cannot `git push` /
# `gh pr create` until this script itself has run check-children-settled.sh for the current plugin
# session and HEAD. The marker is written by a script that runs the check, never by prose and never
# by a hand `Write` (which would let the same agent forge it).
#
# MARKER: `.supervisor/logs/<plugin_session_id>.finalize-gate` — keyed by the PLUGIN session id (the
# `## Session` block's `- session_id:` in `.supervisor/state.md`), never the Claude Code UUID:
#   {"children_check":"settled"|"skipped","children_status":"<join status>","head_sha":"<sha>","ts":"<utc>"}
# write-marker removes any stale marker FIRST, then writes one ONLY when check-children-settled.sh
# --all reads `settled` or `no_identity_rows` (a session that spawned nothing has no child to wait
# on), or when `--skip-children-check` is given (recorded as `skipped`). Any other outcome
# (unsettled / unverifiable / no active session / no HEAD) writes nothing and exits 1. HEAD moving
# after the marker invalidates it: re-run write-marker before every publish (Phase 4.5 heal pushes
# included) — it re-checks the children each time.
#
# GUARD EVALUATION ORDER (cheap-first; no jq on the inert path — mirrors guard-test-integrity.sh):
#   (i)   no `.supervisor/state.md`, no `## Session` block, or its status is not running|checkpoint
#                                                         -> allow (non-Supervisor / finished run)
#   (ii)  raw payload contains neither `push` nor `pr create`     -> allow, no jq
#   (iii) jq missing / payload unparseable                         -> deny guard_unavailable
#   (iv)  no `git push` / `gh pr create` simple command in the command string (split on && || ; |
#         and newlines; leading `VAR=x` assignments and `git -C <dir>` / `-c <k=v>` tolerated)
#                                                                  -> allow
#   (v)   state.md records a `- branch:` and the checkout is on a different branch -> allow
#         (a drain fix push / human push from another branch is never this run's publish)
#   (vi)  session join (below)                                     -> deny unless the marker exists,
#         names children_check settled|skipped, and its head_sha equals the current HEAD.
#
# SESSION JOIN (B2): the plugin session id comes from `.supervisor/state.md`; its log owner is read
# by loom_log_owner (loom-log-owner.sh — the SAME rule emit-lifecycle.sh uses, sourced, never
# restated). Owner == payload `session_id` -> this session's run. Owner empty -> adopt (the shared
# rule's "unknown owner means adopt"). Owner != payload session_id -> a RESUMED run (`/supervisor
# --continue` in a new Claude Code session) of the same checkout: DECISION — still require the marker
# (fail CLOSED), because `--continue` is a documented Supervisor path that also reaches FINALIZE and a
# non-terminal `## Session` block means a run is in flight in THIS checkout. Consequence (accepted): a
# human pushing the run's feature branch from another tab while the run is non-terminal is refused
# too; the escape is `write-marker --skip-children-check`, which records the skip.
#
# DENY MECHANICS: exit 2 AND `hookSpecificOutput.permissionDecision: "deny"` JSON on stdout, one
# stderr line — exactly guard-test-integrity.sh's shape. bash 3.2 / BSD userland safe.
#
# Co-located static suite: test-guard-finalize-publish.sh.
set -u

HERE="${BASH_SOURCE[0]%/*}"
[ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE="."
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_MD="$ROOT/.supervisor/state.md"
LOG_DIR="$ROOT/.supervisor/logs"
REASON_FIRST="run FINALIZE point 5 first"

# ---- shared: the `## Session` block of state.md (no jq) ------------------------------------------
SESSION_ID=""; SESSION_STATUS=""; SESSION_BRANCH=""
read_session_block() {
  [ -f "$STATE_MD" ] || return 1
  local line in_block=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "## Session"*) in_block=1; continue ;;
      "## "*) [ "$in_block" = 1 ] && break; continue ;;
    esac
    [ "$in_block" = 1 ] || continue
    case "$line" in
      "- session_id:"*) SESSION_ID="${line#- session_id:}" ;;
      "- status:"*) SESSION_STATUS="${line#- status:}" ;;
      "- branch:"*) SESSION_BRANCH="${line#- branch:}" ;;
    esac
  done < "$STATE_MD"
  SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-')"
  SESSION_STATUS="$(printf '%s' "$SESSION_STATUS" | tr -d '[:space:]')"
  SESSION_BRANCH="$(printf '%s' "$SESSION_BRANCH" | tr -d '[:space:]')"
  [ -n "$SESSION_ID" ] || return 1
  case "$SESSION_STATUS" in
    running|checkpoint) return 0 ;;
  esac
  return 1
}

# ======================================================================================
# write-marker mode
# ======================================================================================
if [ "${1:-}" = "write-marker" ]; then
  skip=0
  [ "${2:-}" = "--skip-children-check" ] && skip=1
  refuse() { printf '{"status":"refused","reason":"%s"}\n' "$1"; exit 1; }
  command -v jq >/dev/null 2>&1 || refuse "jq_missing"
  read_session_block || refuse "no_active_session"
  MARKER="$LOG_DIR/$SESSION_ID.finalize-gate"
  rm -f "$MARKER" 2>/dev/null
  [ -e "$MARKER" ] && refuse "stale_marker_unremovable"
  head_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
  [ -n "$head_sha" ] || refuse "no_head"
  if [ "$skip" = 1 ]; then
    check="skipped"; children_status="skipped"
  else
    res="$(bash "$HERE/check-children-settled.sh" --log "$LOG_DIR/$SESSION_ID.jsonl" --all 2>/dev/null)"
    children_status="$(printf '%s' "$res" | jq -r '.status // empty' 2>/dev/null)"
    case "$children_status" in
      settled|no_identity_rows) check="settled" ;;
      *)
        printf '{"status":"refused","reason":"children_%s","children":%s}\n' \
          "${children_status:-unverifiable}" "$(printf '%s' "${res:-null}" | jq -c . 2>/dev/null || echo null)"
        exit 1 ;;
    esac
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  mkdir -p "$LOG_DIR" 2>/dev/null || refuse "log_dir_unwritable"
  body="$(jq -n -c --arg c "$check" --arg cs "$children_status" --arg h "$head_sha" --arg t "$ts" \
    '{children_check: $c, children_status: $cs, head_sha: $h, ts: $t}')"
  tmp="$MARKER.tmp.$$"
  { printf '%s\n' "$body" > "$tmp"; } 2>/dev/null && mv -f "$tmp" "$MARKER" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null; refuse "marker_write_failed"; }
  printf '%s\n' "$body"
  exit 0
fi

# ======================================================================================
# PreToolUse[Bash] guard mode
# ======================================================================================
json_escape() { local o="$1"; o="${o//\\/\\\\}"; o="${o//\"/\\\"}"; printf '%s' "$o"; }
deny() {
  local msg="finalize_publish_guard: denied — $1"
  printf '%s\n' "$msg" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$msg")"
  exit 2
}
allow() { exit 0; }

# (i) not a live Supervisor run in this checkout -> allow (no jq)
read_session_block || allow

PAYLOAD="$(cat 2>/dev/null || true)"
# (ii) cheap substring pre-filter -> allow (no jq)
case "$PAYLOAD" in
  *push*|*"pr create"*) ;;
  *) allow ;;
esac

# (iii)
command -v jq >/dev/null 2>&1 || deny "guard_unavailable: jq missing"
printf '%s' "$PAYLOAD" | jq -e 'type == "object"' >/dev/null 2>&1 || deny "guard_unavailable: payload unparseable"
CMD="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null)"

# (iv) is any simple command a publish?
is_publish_segment() {
  local seg="$1"
  local re_assign='^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+'
  while [[ "$seg" =~ $re_assign ]]; do seg="${seg#"${BASH_REMATCH[0]}"}"; done
  local re_git='^(command[[:space:]]+)?git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'
  local re_gh='^(command[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
  [[ "$seg" =~ $re_git ]] && return 0
  [[ "$seg" =~ $re_gh ]] && return 0
  return 1
}
publish=0
segs="$(printf '%s\n' "$CMD" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g')"
while IFS= read -r seg; do
  # trim leading whitespace and a subshell/group opener per segment (sed's `^` only anchors the
  # first segment once the split has put several into one pattern space)
  seg="${seg#"${seg%%[![:space:]]*}"}"
  case "$seg" in "("*|"{"*) seg="${seg#?}"; seg="${seg#"${seg%%[![:space:]]*}"}" ;; esac
  [ -n "$seg" ] || continue
  if is_publish_segment "$seg"; then publish=1; break; fi
done <<EOF
$segs
EOF
[ "$publish" = 1 ] || allow

# (v) a push from a branch other than the run's recorded feature branch is not this run's publish
if [ -n "$SESSION_BRANCH" ]; then
  cur_branch="$(git -C "$ROOT" branch --show-current 2>/dev/null)"
  [ -n "$cur_branch" ] && [ "$cur_branch" != "$SESSION_BRANCH" ] && allow
fi

# (vi) session join — reuse THE ownership rule (loom-log-owner.sh), never a restated copy
# shellcheck source=loom-log-owner.sh
. "$HERE/loom-log-owner.sh" 2>/dev/null || deny "guard_unavailable: loom-log-owner.sh missing"
owner="$(loom_log_owner "$LOG_DIR/$SESSION_ID.jsonl" | tr -cd 'A-Za-z0-9_-')"
payload_sid="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
# owner == payload_sid: this session's run. owner empty: adopt. owner != payload_sid: a resumed run
# of this checkout — the header's documented DECISION is to require the marker all the same.
# All three paths therefore converge on the marker check below; the join is computed so the deny
# reason names which case fired.
if [ -z "$owner" ] || [ "$owner" = "$payload_sid" ]; then
  join="this session"
else
  join="resumed run (log owner differs)"
fi

MARKER="$LOG_DIR/$SESSION_ID.finalize-gate"
[ -f "$MARKER" ] || deny "$REASON_FIRST (no finalize-gate marker for plugin session $SESSION_ID, $join; run: bash \${CLAUDE_PLUGIN_ROOT}/scripts/guard-finalize-publish.sh write-marker)"
m_check="$(jq -r '.children_check // empty' "$MARKER" 2>/dev/null)"
m_head="$(jq -r '.head_sha // empty' "$MARKER" 2>/dev/null)"
case "$m_check" in
  settled|skipped) ;;
  *) deny "$REASON_FIRST (finalize-gate marker unreadable or children_check='$m_check')" ;;
esac
cur_head="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
[ -n "$cur_head" ] && [ "$m_head" = "$cur_head" ] \
  || deny "$REASON_FIRST (HEAD moved since the check: marker ${m_head:-none} != HEAD ${cur_head:-unknown}; re-run write-marker)"
allow
