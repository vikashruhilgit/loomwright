#!/usr/bin/env bash
# notify-desktop.sh — OS-native notification helper for plugin pause events.
#
# INVARIANT: ALWAYS exits 0. The hook must never see a non-zero exit. All
# failure modes (missing jq, missing osascript/notify-send, malformed payload,
# unknown event) are absorbed silently.
#
# Triggers (wired in hooks/hooks.json):
#   - PreToolUse[AskUserQuestion]: plugin is about to block on a user question
#     (Supervisor adjudication, rubric gate, Plan Reviewer NEEDS_HUMAN,
#     Launch Pad Phase 6, /autonomous merge-and-continue, etc.).
#   - Notification: Claude Code itself signals attention (permission_prompt,
#     idle_prompt, elicitation_*).
#
# Behaviour:
#   1. If AI_AGENT_MANAGER_DESKTOP_NOTIFICATIONS=0 → silent no-op (opt-out).
#   2. Read JSON payload from stdin.
#   3. Build a (title, body) pair per event type. Unknown events → exit 0.
#   4. Fire OS-native notification (best-effort, never blocking):
#        macOS  → osascript display notification
#        Linux  → notify-send
#   5. ALWAYS exit 0.
#
# Why a `type: command` wrapper instead of `type: http` or `type: prompt`:
#   - Need access to local OS notification facilities (osascript/notify-send).
#   - Hook must never block the agent loop.
#
# Style/structure mirrors send-webhook.sh and send-telemetry.sh (sibling
# fire-and-forget wrappers).

set -u
# Intentionally NO `set -e` / pipefail — wrapper must absorb every child failure.

# ---- Opt-out gate -----------------------------------------------------------
if [ "${AI_AGENT_MANAGER_DESKTOP_NOTIFICATIONS:-1}" = "0" ]; then
  exit 0
fi

# ---- Read stdin -------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  exit 0
fi

# ---- jq availability --------------------------------------------------------
# jq is required to safely parse Claude Code hook payloads. Without it we
# cannot reliably distinguish event types, so we silent-exit rather than guess.
if ! command -v jq >/dev/null 2>&1; then
  printf 'notify-desktop: jq not on PATH — skipping\n' >&2
  exit 0
fi

# ---- Field extraction -------------------------------------------------------
HOOK_EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

# ---- Scope gate -------------------------------------------------------------
# AI_AGENT_MANAGER_NOTIFY_SCOPE controls whether non-plugin AskUserQuestion
# events fire notifications. Default `plugin` suppresses noise from unrelated
# Claude Code work; set to `all` to fire on every AskUserQuestion regardless of
# origin (the v13.1.0 initial-release behavior, retained as an opt-in for
# operators who genuinely want host-wide notification coverage).
#
# Plugin-context detection is intentionally permissive — false negatives only
# cost a missed notification (the AskUserQuestion still fires in-conversation).
# A false positive costs at most one spurious banner. The three markers are
# independent ORs:
#   (1) .supervisor/jobs/in-progress/*.md exists — Supervisor is active
#   (2) .supervisor/autonomous/*/state.json mtime within last 2h — autonomous loop active
#   (3) transcript_path readable AND contains a plugin marker in the last 200 lines
# Notification hook events (permission_prompt, idle_prompt, elicitation_*) are
# exempt from the scope gate — those events ARE inherently Claude-Code-wide and
# the user expects them.
is_plugin_context() {
  local transcript_path="${1:-}"

  # Marker 1: active Supervisor job. compgen returns 0 when at least one match;
  # nullglob would be cleaner but pulls in shopt side effects.
  if compgen -G ".supervisor/jobs/in-progress/*.md" > /dev/null 2>&1; then
    return 0
  fi

  # Marker 2: recent autonomous-loop state file. -mmin -120 is "modified in
  # the last 120 minutes" — 2h is wide enough to span Phase 4.5 self-heal +
  # rubric-grader latency but short enough to expire stale runs.
  local state_file
  for state_file in .supervisor/autonomous/*/state.json; do
    [ -f "$state_file" ] || continue
    if [ -n "$(find "$state_file" -mmin -120 2>/dev/null)" ]; then
      return 0
    fi
  done

  # Marker 3: transcript scan. The transcript_path field is documented in
  # Claude Code hook payloads. Grep for canonical plugin agent / command
  # references in the last 200 lines (cheap; bounded). Patterns:
  #   - ai-agent-manager-plugin:<agent>  — Task-spawn references
  #   - /launch-pad, /supervisor, /autonomous, /code-reviewer, /qa-executor,
  #     /qa-strategist, /red-team-reviewer, /product-owner, /agent-help,
  #     /telemetry, /dreaming — the 12 plugin slash commands
  if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
    if tail -200 "$transcript_path" 2>/dev/null | grep -qE 'ai-agent-manager-plugin:|/launch-pad|/supervisor|/autonomous|/code-reviewer|/qa-executor|/qa-strategist|/red-team-reviewer|/product-owner|/agent-help|/telemetry|/dreaming'; then
      return 0
    fi
  fi

  return 1
}

SCOPE="${AI_AGENT_MANAGER_NOTIFY_SCOPE:-plugin}"
# Notification hook event is exempt: it represents Claude Code itself signalling
# the user (permission prompts, idle, elicitation) — always relevant regardless
# of plugin origin. Only PreToolUse[AskUserQuestion] gets the scope gate.
if [ "$SCOPE" = "plugin" ] && [ "$HOOK_EVENT" = "PreToolUse" ]; then
  if ! is_plugin_context "$TRANSCRIPT_PATH"; then
    exit 0
  fi
fi

TITLE=""
BODY=""

case "$HOOK_EVENT" in
  PreToolUse)
    TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
    if [ "$TOOL_NAME" != "AskUserQuestion" ]; then
      # Only fire for AskUserQuestion. Other PreToolUse events are noise.
      exit 0
    fi
    TITLE="Claude needs your input"
    # AskUserQuestion schema: tool_input.questions[].question / .header.
    # Prefer the first question text; fall back to header; else generic.
    BODY="$(printf '%s' "$INPUT" \
      | jq -r '.tool_input.questions[0].question // .tool_input.questions[0].header // "Plugin is paused on a user question"' \
      2>/dev/null || true)"
    ;;
  Notification)
    NOTIF_TYPE="$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null || true)"
    MSG="$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null || true)"
    case "$NOTIF_TYPE" in
      permission_prompt)
        TITLE="Claude wants permission"
        ;;
      idle_prompt)
        TITLE="Claude is waiting on you"
        ;;
      elicitation_*)
        TITLE="MCP server needs input"
        ;;
      *)
        TITLE="Claude Code"
        ;;
    esac
    BODY="${MSG:-Claude Code event}"
    ;;
  *)
    # Unknown / not-wired-here event. Stay silent.
    exit 0
    ;;
esac

# ---- Defensive bounds -------------------------------------------------------
# macOS Notification Center silently truncates very long bodies; cap explicitly
# so the displayed message stays readable.
MAX_BODY=200
MAX_TITLE=60

if [ "${#BODY}" -gt "$MAX_BODY" ]; then
  BODY="$(printf '%s' "$BODY" | head -c "$((MAX_BODY - 3))")..."
fi
if [ "${#TITLE}" -gt "$MAX_TITLE" ]; then
  TITLE="$(printf '%s' "$TITLE" | head -c "$((MAX_TITLE - 3))")..."
fi

if [ -z "$BODY" ]; then BODY="Claude Code event"; fi
if [ -z "$TITLE" ]; then TITLE="Claude Code"; fi

# ---- Dispatch ---------------------------------------------------------------
# Per-platform native notification. Each branch is best-effort and never
# allowed to bubble a non-zero exit.

# osascript_escape: escape backslashes and double-quotes for embedding inside
# a double-quoted AppleScript string literal. Order matters: backslash first.
osascript_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

mkdir -p .supervisor/logs 2>/dev/null || true
NOTIFY_LOG=".supervisor/logs/notifications.log"

# Portable timeout guard (v14.1.0 hardening — red-team W4). A wedged notification
# daemon or a first-run permission interaction must never block the agent loop.
# GNU `timeout` is not on stock macOS; `gtimeout` ships with coreutils. If neither
# is present we run the notifier directly — identical to pre-v14.1.0 behavior, so
# this is purely additive protection with zero regression risk.
TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT="timeout 3"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT="gtimeout 3"
fi

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)
    if command -v osascript >/dev/null 2>&1; then
      ESC_TITLE="$(osascript_escape "$TITLE")"
      ESC_BODY="$(osascript_escape "$BODY")"
      # Glass is a system-supplied sound; safe on every macOS install.
      # stderr captured to .supervisor/logs/notifications.log so the user has a
      # signal when notifications silently stop working (Finding #11 in the
      # v13.1.0 red-team audit). The `|| true` keeps the script exit code at 0.
      $TIMEOUT osascript -e "display notification \"$ESC_BODY\" with title \"$ESC_TITLE\" sound name \"Glass\"" \
        >/dev/null 2>>"$NOTIFY_LOG" || true
    fi
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      $TIMEOUT notify-send -a "Claude Code" "$TITLE" "$BODY" >/dev/null 2>>"$NOTIFY_LOG" || true
    fi
    ;;
  *)
    # Windows / unknown — no built-in notifier we can rely on. Skip silently.
    :
    ;;
esac

exit 0
