#!/usr/bin/env bash
# session-resume.sh — SessionStart hook helper for crash/compact recovery.
#
# Fires on SessionStart events. When `source` is `resume`, `clear`, or `compact`,
# emits a bounded (~8 KB; MAX_CHARS=8000) structured summary as `additionalContext` so the
# agent re-entering the session has immediate visibility into:
#   - in-progress Supervisor jobs (.supervisor/jobs/in-progress/)
#   - recent failed jobs (.supervisor/jobs/failed/)
#   - last 5 lines of .supervisor/state.md
#   - last 3 entries from the most recent .supervisor/logs/*.jsonl
# Stays under SessionStart's documented 10,000-char additionalContext cap.
#
# When `source` is `startup` (fresh session) → silent no-op. Startup context
# injection would create noise on every Claude Code launch even when no plugin
# work is in flight.
#
# INVARIANT: ALWAYS exits 0. Hook output is JSON via stdout. Silent-pass
# on any failure (no .supervisor/, no state, missing tools) so the session
# starts normally without diagnostic noise.

set -u
# Intentionally NO `set -e` / pipefail.

# ---- Read stdin -------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  exit 0
fi

# ---- Extract source field via jq (required) --------------------------------
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi
SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)"

# Only fire on resume / clear / compact. Startup is a fresh session — no
# need to inject prior-state context.
case "$SOURCE" in
  resume|clear|compact) ;;
  *) exit 0 ;;
esac

# ---- Bail if no plugin state at all ----------------------------------------
if [ ! -d ".supervisor" ]; then
  exit 0
fi

# ---- Build the summary -----------------------------------------------------
# Compose into a temporary buffer. Hard cap at 8000 chars (well under
# Claude Code's 10K SessionStart additionalContext limit).
SUMMARY=""

append() {
  SUMMARY="$SUMMARY$1"
}

append "## AI Agent Manager — prior-session context ($SOURCE)"$'\n\n'

# Section 1: in-progress Supervisor jobs ----
if compgen -G ".supervisor/jobs/in-progress/*.md" > /dev/null 2>&1; then
  append "### In-progress briefs (Supervisor was mid-run)"$'\n'
  for f in .supervisor/jobs/in-progress/*.md; do
    [ -f "$f" ] || continue
    append "- $f"$'\n'
  done
  append $'\n'
fi

# Section 2: recent failed jobs (last 5 by mtime) ----
if compgen -G ".supervisor/jobs/failed/*.md" > /dev/null 2>&1; then
  append "### Recent failed briefs (last 5)"$'\n'
  # ls -t sorts newest first; head -5 caps the count
  for f in $(ls -t .supervisor/jobs/failed/*.md 2>/dev/null | head -5); do
    append "- $f"$'\n'
  done
  append $'\n'
fi

# Section 3: tail of state.md ----
if [ -f ".supervisor/state.md" ]; then
  append "### Last 5 lines of .supervisor/state.md"$'\n'
  append '```'$'\n'
  TAIL_OUT="$(tail -5 .supervisor/state.md 2>/dev/null || true)"
  if [ -n "$TAIL_OUT" ]; then
    append "$TAIL_OUT"$'\n'
  else
    append "(state.md exists but is empty)"$'\n'
  fi
  append '```'$'\n\n'
fi

# Section 4: last 3 entries from the most recent session log ----
if compgen -G ".supervisor/logs/*.jsonl" > /dev/null 2>&1; then
  # Pick the most-recently-modified log file. The shared session-log
  # convention is .supervisor/logs/{session_id}.jsonl per CLAUDE.md.
  LATEST_LOG="$(ls -t .supervisor/logs/*.jsonl 2>/dev/null | head -1)"
  if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
    append "### Last 3 entries from $LATEST_LOG"$'\n'
    append '```'$'\n'
    LOG_TAIL="$(tail -3 "$LATEST_LOG" 2>/dev/null || true)"
    if [ -n "$LOG_TAIL" ]; then
      append "$LOG_TAIL"$'\n'
    else
      append "(log file is empty)"$'\n'
    fi
    append '```'$'\n\n'
  fi
fi

# Section 5: autonomous loop state (if any recent runs) ----
if compgen -G ".supervisor/autonomous/*/state.json" > /dev/null 2>&1; then
  RECENT_AUTO=""
  for f in .supervisor/autonomous/*/state.json; do
    [ -f "$f" ] || continue
    # Within last 24h?
    if [ -n "$(find "$f" -mmin -1440 2>/dev/null)" ]; then
      RECENT_AUTO="$RECENT_AUTO- $f"$'\n'
    fi
  done
  if [ -n "$RECENT_AUTO" ]; then
    append "### Active /autonomous sessions (state.json modified within 24h)"$'\n'
    append "$RECENT_AUTO"$'\n'
  fi
fi

# Section 6: recovery hints ----
append "### Recovery hints"$'\n'
append "- Read \`.supervisor/state.md\` for full context."$'\n'
append "- Check \`git status\` and \`git worktree list\` for in-flight changes."$'\n'
append "- Resume in-progress Supervisor work: \`/supervisor --continue task: <task_id>\`."$'\n'
append "- Resume an aborted /autonomous run: re-launch with the same requirement; the loop is single-iteration-safe to re-run."$'\n'

# ---- Hard-cap and emit -----------------------------------------------------
# Defensive ceiling well below the documented 10K additionalContext cap.
MAX_CHARS=8000
if [ "${#SUMMARY}" -gt "$MAX_CHARS" ]; then
  SUMMARY="$(printf '%s' "$SUMMARY" | head -c "$((MAX_CHARS - 32))")"
  SUMMARY="$SUMMARY"$'\n'"... [truncated — see .supervisor/ directly]"
fi

# Emit the documented SessionStart context envelope. Claude Code injects
# `hookSpecificOutput.additionalContext` — a bare top-level `additionalContext`
# is NOT recognized (it would be dropped / shown as raw JSON). jq handles safe
# JSON string escaping. Scrub to valid UTF-8 first: the byte-wise `head -c`
# truncation above can split a multibyte char, which would make jq fail and
# drop ALL context; `iconv -c` strips any invalid sequence (|| cat if iconv is
# absent).
printf '%s' "$SUMMARY" \
  | { iconv -c -f UTF-8 -t UTF-8 2>/dev/null || cat; } \
  | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' 2>/dev/null \
  || true

exit 0
