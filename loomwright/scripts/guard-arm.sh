#!/usr/bin/env bash
# guard-arm.sh — marker-file arming/disarming for the test-integrity guard
# (six-phase-loop-gaps/02). Companion to guard-test-integrity.sh, which reads
# the markers this script writes.
#
# DESIGN — ONE MARKER FILE PER SESSION (Rev 4 of the source requirement,
# `.supervisor/requirements/six-phase-loop-gaps/02-test-integrity-guard.md`).
# Rev 3's single-slot-per-checkout design had two disarm bypasses, both
# closed here:
#   (a) `arm` read the session id ONLY from `$CLAUDE_CODE_SESSION_ID`, never
#       from any other source, and NEVER overwrites an existing file for a
#       DIFFERENT session id — `CLAUDE_CODE_SESSION_ID=dead bash guard-arm.sh
#       arm x` creates only `dead.json`, which no real payload's session_id
#       will ever match. Harmless by construction.
#   (b) a second session arming on the same checkout gets its OWN file — it
#       can never disarm a sibling session's marker, because `arm` only ever
#       creates/touches the file named after its own id.
# There is no `disarm` reachable from a Bash tool call at all — see
# `disarm-session` below, invoked ONLY from the `SessionEnd` hook leaf.
#
# SUBCOMMANDS
#   arm <by> [--session-id <uuid>]
#       Writes `.supervisor/guard/<id>.json` where <id> is the explicit
#       --session-id value (ONLY the dispatcher pre-arm caller is meant to
#       pass this — see dispatch-pr-review.sh) or, when --session-id is
#       omitted, `$CLAUDE_CODE_SESSION_ID`. Idempotent: own file already
#       present -> exit 0 no-op. Empty/unset id -> exit 3, stderr
#       "guard_arm_failed: no session id", writes nothing. Also prunes marker
#       files whose mtime is older than 7 days (dead sessions) — the ONLY
#       deletion this subcommand performs, and never the caller's own or any
#       newer file.
#   arm-from-payload
#       Reads a PreToolUse[Agent|Task] hook payload from stdin. Arms with the
#       PAYLOAD's own `session_id` field (not the env — hook processes are
#       not guaranteed to inherit the spawning session's Bash-tool env)
#       ONLY when `tool_input.subagent_type` ends in
#       `:(worker|execute-manager|supervisor-runner|review-pr-runner)` — the
#       namespace colon is REQUIRED so a bare `*worker` agent from another
#       plugin, or a human's own `~/.claude/agents/` agent, never arms a
#       session it has no business arming. `subagent_type` is checked BEFORE
#       any file I/O (this leaf forks on every single Task/Agent spawn in
#       every project using the plugin). Always exits 0 (this leaf is
#       `|| true` in hooks.json; a hook backstop that failed loudly would be
#       worse than a silently-skipped arm — see
#       skills/self-heal-advisory/SKILL.md "Hook backstop" note).
#   disarm-session
#       Reads a SessionEnd hook payload from stdin, removes ONLY the file
#       named by the payload's own `session_id`. The single disarm point in
#       the whole design — never reachable from a tool call. Always exits 0.
#
# `.supervisor/guard/` is created here, in whichever directory
# `$CLAUDE_PROJECT_DIR` (or, absent that, the hook process's own cwd — Claude
# Code launches hook commands with cwd already set to the project dir)
# resolves to — i.e. the SAME worktree the arming session is actually running
# in. This is intentionally worktree-scoped, not main-checkout-anchored: it is
# the runner's own action to create it, distinct from the plugin's usual
# "observer" convention of gating on an EXISTING `.supervisor/` and never
# creating one (that convention governs read-only progress/lifecycle
# emitters; this script is the one place in the plugin that legitimately
# creates `.supervisor/guard/` as part of arming a session's own run).
#
# Crash/kill honesty: a session that dies without ever reaching SessionEnd
# leaves its marker behind. That marker matches no LIVE payload's
# session_id (a dead session's id is never reused), so it is inert — and
# gets pruned by any later `arm` call once it crosses the 7-day mark.
set -u

GUARD_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.supervisor/guard"
PRUNE_AGE_SECONDS=604800 # 7 days

# ---- shared helpers ---------------------------------------------------

# valid_session_id <id> — rejects empty ids and anything that could escape
# GUARD_DIR (a defense-in-depth check beyond the literal spec: a forged
# CLAUDE_CODE_SESSION_ID containing "/" must never be treated as a filename
# component).
valid_session_id() {
  case "$1" in
    "") return 1 ;;
    */*) return 1 ;;
    .|..) return 1 ;;
    *) return 0 ;;
  esac
}

# prune — removes marker files older than PRUNE_AGE_SECONDS (by mtime, which
# is set once at write time and never touched again, so it is equivalent to
# the JSON `armed_at` field without needing to date-parse an ISO8601 string
# portably across BSD/GNU `date`). Never touches a file younger than the
# threshold — a live session's own marker, or a sibling session's live
# marker, is always safe.
prune() {
  [ -d "$GUARD_DIR" ] || return 0
  local now cutoff f mtime
  now="$(date -u +%s 2>/dev/null)" || return 0
  case "$now" in ''|*[!0-9]*) return 0 ;; esac
  cutoff=$(( now - PRUNE_AGE_SECONDS ))
  for f in "$GUARD_DIR"/*.json; do
    [ -e "$f" ] || continue
    # GNU `-c %Y` tried FIRST, not BSD `-f %m`: on Linux, `stat -f %m`
    # does NOT cleanly fail (which is what a `||` fallback needs) — it
    # succeeds with garbage, because `-f` switches GNU stat into
    # filesystem-status mode where `%m` is not a valid directive for
    # file mtime. That garbage previously always passed straight through
    # to the numeric-validation guard below as a non-numeric value,
    # silently skipping every file's prune check on Linux (never
    # pruning, never crashing) — confirmed by CI failing "arm prunes an
    # 8-day-old marker" on every run while passing locally on macOS,
    # where BSD stat has no `-c` and `-f %m` is the correct, only form.
    # Trying `-c %Y` first means it wins cleanly on Linux and correctly
    # fails (nonzero exit, clean fallback) on macOS. (PR #258.)
    mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || true)"
    case "$mtime" in ''|*[!0-9]*) continue ;; esac
    if [ "$mtime" -lt "$cutoff" ]; then
      rm -f "$f" 2>/dev/null || true
    fi
  done
}

# write_marker <sid> <by> — atomic same-dir temp + mv, idempotent (own file
# present -> no-op, never rewritten). Mirrors dispatch-pr-review.sh's
# acquire_lock SHAPE (atomic mkdir/temp+mv discipline) but is a one-file-
# per-session design, not a shared lock slot.
write_marker() {
  local sid="$1" by="$2" marker tmp armed_at
  marker="$GUARD_DIR/$sid.json"
  if [ -e "$marker" ]; then
    return 0
  fi
  mkdir -p "$GUARD_DIR" 2>/dev/null || { printf 'guard_arm_failed: cannot create guard dir\n' >&2; return 1; }
  armed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  tmp="$GUARD_DIR/.tmp.$$.${sid}.json"
  {
    printf '{\n'
    printf '  "session_id": "%s",\n' "$sid"
    printf '  "armed_at": "%s",\n' "$armed_at"
    printf '  "by": "%s"\n' "$by"
    printf '}\n'
  } > "$tmp" 2>/dev/null
  if [ -s "$tmp" ]; then
    mv -f "$tmp" "$marker" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; printf 'guard_arm_failed: could not write marker\n' >&2; return 1; }
  else
    rm -f "$tmp" 2>/dev/null || true
    printf 'guard_arm_failed: could not write marker\n' >&2
    return 1
  fi
  return 0
}

# ---- subcommands --------------------------------------------------------

cmd_arm() {
  local by="" sid="" saw_flag=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --session-id)
        saw_flag=1
        sid="${2:-}"
        # A trailing `--session-id` with no value leaves only 1 arg —
        # `shift 2` would fail, and since this script runs under only
        # `set -u` (not `set -e`), that failure is silently swallowed,
        # $1 is never consumed, and the while loop spins forever on the
        # same token (PR #258 round-11 review finding, live-reproduced
        # as an unbounded hang). Not attacker-reachable — the Bash
        # matcher denies any tool-issued `guard-arm.sh arm ...
        # --session-id` outright, and the one real direct caller always
        # supplies a generated UUID — but a malformed direct invocation
        # should fail fast, not hang. sid stays empty either way, which
        # valid_session_id already rejects below.
        if [ "$#" -ge 2 ]; then shift 2; else shift; fi
        ;;
      *)
        [ -n "$by" ] || by="$1"
        shift
        ;;
    esac
  done
  [ -n "$by" ] || by="unknown"
  if [ "$saw_flag" -eq 0 ]; then
    sid="${CLAUDE_CODE_SESSION_ID:-}"
  fi
  if ! valid_session_id "$sid"; then
    printf 'guard_arm_failed: no session id\n' >&2
    exit 3
  fi
  if ! write_marker "$sid" "$by"; then
    exit 1
  fi
  prune
  exit 0
}

cmd_arm_from_payload() {
  local payload subagent_type sid
  payload="$(cat 2>/dev/null || true)"
  command -v jq >/dev/null 2>&1 || exit 0
  subagent_type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
  case "$subagent_type" in
    *:worker|*:execute-manager|*:supervisor-runner|*:review-pr-runner) ;;
    *) exit 0 ;;
  esac
  sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
  valid_session_id "$sid" || exit 0
  write_marker "$sid" "hook-backstop" || true
  exit 0
}

cmd_disarm_session() {
  local payload sid
  payload="$(cat 2>/dev/null || true)"
  command -v jq >/dev/null 2>&1 || exit 0
  sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
  valid_session_id "$sid" || exit 0
  rm -f "$GUARD_DIR/$sid.json" 2>/dev/null || true
  exit 0
}

case "${1:-}" in
  arm)
    shift
    cmd_arm "$@"
    ;;
  arm-from-payload)
    cmd_arm_from_payload
    ;;
  disarm-session)
    cmd_disarm_session
    ;;
  *)
    printf 'guard-arm.sh: unknown subcommand %s\n' "${1:-<none>}" >&2
    exit 64
    ;;
esac
