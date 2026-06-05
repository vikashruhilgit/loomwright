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

# ---- Debounce (v14.2.2) -----------------------------------------------------
# Coalesce rapid notification bursts (several gates in quick succession, or
# parallel hook fires) into a single banner: if one fired within the last
# DEBOUNCE_WINDOW seconds, suppress this one. State is a single epoch timestamp
# in a gitignored file under .supervisor/. Best-effort — any failure → no
# debounce (we'd rather over-notify than drop a real pause). Set
# AI_AGENT_MANAGER_NOTIFY_DEBOUNCE=0 to disable.
DEBOUNCE_WINDOW="${AI_AGENT_MANAGER_NOTIFY_DEBOUNCE:-5}"
case "$DEBOUNCE_WINDOW" in *[!0-9]*|"") DEBOUNCE_WINDOW=5 ;; esac
DEBOUNCE_FILE=".supervisor/logs/.notify-debounce"
mkdir -p .supervisor/logs 2>/dev/null || true
NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
if [ "$DEBOUNCE_WINDOW" -gt 0 ] && [ "$NOW_EPOCH" != "0" ] && [ -f "$DEBOUNCE_FILE" ]; then
  LAST_EPOCH="$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)"
  case "$LAST_EPOCH" in *[!0-9]*|"") LAST_EPOCH=0 ;; esac
  if [ "$LAST_EPOCH" -gt 0 ] && [ "$((NOW_EPOCH - LAST_EPOCH))" -lt "$DEBOUNCE_WINDOW" ]; then
    exit 0
  fi
fi
[ "$NOW_EPOCH" != "0" ] && printf '%s' "$NOW_EPOCH" > "$DEBOUNCE_FILE" 2>/dev/null || true

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
# so the displayed message stays readable. NOTE: `head -c` truncates by BYTES
# (BSD), so a multi-byte UTF-8 code point at the boundary may be split — cosmetic
# only at these small caps (a possibly-garbled trailing char before the ellipsis).
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

# ---- Click target (clickable banner) ---------------------------------------
# Decide what clicking the banner should do. The pure decision logic lives in
# the sibling notify-click-target.sh (self-tested by test-notify-click-target.sh)
# so the UUID validation + claude:// deep-link construction can be unit-tested
# without installing terminal-notifier or firing a real notification.
#
# This only has an EFFECT when terminal-notifier is installed (see the Darwin
# branch below). macOS's built-in `osascript display notification` cannot carry
# a click action at all, so without terminal-notifier the banner is the same
# non-clickable banner as before — zero regression.
#
#   AI_AGENT_MANAGER_NOTIFY_CLICK = activate (default) | resume | auto | off
#     activate → click brings the Claude desktop app to the foreground.
#                RELIABLE on modern macOS (incl. macOS 26) — this is the default.
#                For a single active session, focusing the app lands on it.
#     resume   → click opens claude://claude.ai/resume?session=<uuid> to jump
#                back to THIS exact session. Works only where terminal-notifier's
#                -open click still fires (older macOS); on macOS 26 the click
#                callback is dead, so the banner won't navigate. Opt-in.
#     auto     → activate when already inside the desktop app; else resume.
#     off      → no click action; plain banner only.
#
# Session id: the hook payload's .session_id is authoritative (same field
# send-telemetry.sh reads); fall back to the CLAUDE_CODE_SESSION_ID env var.
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
CLICK_MODE="${AI_AGENT_MANAGER_NOTIFY_CLICK:-activate}"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -z "$SESSION_ID" ] && SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
CLICK_ACTION="none"
CLICK_TARGET=""
if [ "$CLICK_MODE" != "off" ] && [ -r "$SCRIPT_DIR/notify-click-target.sh" ]; then
  CLICK_OUT="$(bash "$SCRIPT_DIR/notify-click-target.sh" "$CLICK_MODE" "$SESSION_ID" "${CLAUDE_CODE_ENTRYPOINT:-}" 2>/dev/null || true)"
  CLICK_ACTION="$(printf '%s\n' "$CLICK_OUT" | sed -n 's/^ACTION=//p' | head -1)"
  CLICK_TARGET="$(printf '%s\n' "$CLICK_OUT" | sed -n 's/^TARGET=//p' | head -1)"
  [ -z "$CLICK_ACTION" ] && CLICK_ACTION="none"
fi

# ---- Dispatch ---------------------------------------------------------------
# Per-platform native notification. Each branch is best-effort and never
# allowed to bubble a non-zero exit. (A terminal-bell tier was evaluated and
# intentionally omitted in v14.2.2: a bell from a non-TTY hook subprocess goes
# nowhere useful and would emit a raw 0x07 into a log; the webhook is the
# headless channel instead — see docs/TELEMETRY.md §"Webhook Notifications".)

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
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi
# run_bounded <cmd...> — run with a 3s ceiling if a timeout binary exists, else
# run directly. A function (not a `$TIMEOUT` string) avoids SC2086 word-splitting
# AND the bash-3.2 `"${arr[@]}"`-under-`set -u` pitfall on stock macOS.
run_bounded() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" 3 "$@"
  else
    "$@"
  fi
}

# fire_detached <cmd...> — run a notifier FULLY DETACHED so this hook returns
# immediately. terminal-notifier does NOT exit while a clickable notification
# (-sender / -open) is on screen — it lingers to service the click — which would
# otherwise BLOCK the agent loop (and `run_bounded` can't help on stock macOS,
# which ships neither `timeout` nor `gtimeout`). Backgrounding in a subshell
# with ALL stdio redirected away from the hook's inherited pipes is what lets
# the hook finish: a backgrounded child still holding the hook's stdout pipe
# would keep the hook "running" until that child exits. The orphaned notifier is
# harmless and is reaped when the user clicks/clears it (or when the next
# notification in the same -group replaces it).
fire_detached() {
  ( "$@" >>"$NOTIFY_LOG" 2>&1 </dev/null & ) >/dev/null 2>&1
}

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)
    # Preferred path: terminal-notifier produces a CLICKABLE banner.
    #   -open <claude:// url> runs the resume deep link on click (jump back to
    #     THIS session); -activate <bundle id> just focuses the desktop app.
    #
    # IMPORTANT — do NOT use -sender here. Impersonating another app's bundle id
    # (e.g. com.anthropic.claudefordesktop, to borrow its icon) is silently
    # REJECTED by the macOS 26 notification service: the banner never appears.
    # Verified empirically — a bare terminal-notifier delivers fine, the same
    # call with -sender delivers nothing. Omitting -sender also means
    # terminal-notifier owns the notification, so the -open click callback fires
    # reliably instead of being hijacked into a plain sender-activate. The only
    # cost is cosmetic: the banner shows terminal-notifier's icon, not Claude's.
    #
    # Built-in `osascript display notification` (the fallback when
    # terminal-notifier is absent) cannot carry any click action — that is the
    # whole reason terminal-notifier is preferred here. Install it with
    # `brew install terminal-notifier` to enable clickable banners.
    CLAUDE_BUNDLE_ID="com.anthropic.claudefordesktop"
    # -group coalesces banners (a new one replaces the prior in the group, which
    # also reaps the prior lingering terminal-notifier process — bounding pileup).
    TN_GROUP="ai-agent-manager"
    if command -v terminal-notifier >/dev/null 2>&1 && [ "$CLICK_ACTION" != "none" ]; then
      if [ "$CLICK_ACTION" = "open" ] && [ -n "$CLICK_TARGET" ]; then
        fire_detached terminal-notifier \
          -title "$TITLE" -message "$BODY" -sound Glass \
          -group "$TN_GROUP" \
          -open "$CLICK_TARGET"
      else
        # activate (CLICK_TARGET is the bundle id; default to Claude's).
        fire_detached terminal-notifier \
          -title "$TITLE" -message "$BODY" -sound Glass \
          -group "$TN_GROUP" \
          -activate "${CLICK_TARGET:-$CLAUDE_BUNDLE_ID}"
      fi
    elif command -v osascript >/dev/null 2>&1; then
      ESC_TITLE="$(osascript_escape "$TITLE")"
      ESC_BODY="$(osascript_escape "$BODY")"
      # Glass is a system-supplied sound; safe on every macOS install.
      # stderr captured to .supervisor/logs/notifications.log so the user has a
      # signal when notifications silently stop working (Finding #11 in the
      # v13.1.0 red-team audit). The `|| true` keeps the script exit code at 0.
      run_bounded osascript -e "display notification \"$ESC_BODY\" with title \"$ESC_TITLE\" sound name \"Glass\"" \
        >/dev/null 2>>"$NOTIFY_LOG" || true
    fi
    ;;
  Linux)
    # Channel-detect (v14.2.2): only attempt notify-send when a display server is
    # present (DISPLAY or WAYLAND_DISPLAY). On a headless Linux box notify-send
    # errors with no notification daemon — there's no banner to show, so skip
    # cleanly (the webhook covers headless). run_bounded still caps any hang.
    if command -v notify-send >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      run_bounded notify-send -a "Claude Code" "$TITLE" "$BODY" >/dev/null 2>>"$NOTIFY_LOG" || true
    fi
    ;;
  *)
    # Windows / unknown — no built-in notifier we can rely on. Skip silently.
    :
    ;;
esac

exit 0
