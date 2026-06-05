#!/usr/bin/env bash
# notify-click-target.sh — PURE helper: decide the click action for a desktop
# notification banner. No side effects, no I/O beyond stdout. ALWAYS exits 0.
#
# notify-desktop.sh calls this to figure out *what should happen when the user
# clicks the banner*. Kept separate (and pure) so the riskiest logic — UUID
# validation + claude:// deep-link construction + mode resolution — is unit
# testable without installing terminal-notifier or firing a real notification.
# Mirrors the scripts/format-twin-delta.sh + test-format-twin-delta.sh pattern;
# neither this nor its self-test is counted by the doc-currency gate.
#
# Usage:
#   notify-click-target.sh <click_mode> <session_id> <entrypoint>
#
# Prints exactly two lines to stdout:
#   ACTION=<open|activate|none>
#   TARGET=<deep-link-url | bundle-id | empty>
#
# ACTION semantics (consumed by notify-desktop.sh's terminal-notifier branch):
#   open      → terminal-notifier -open  "$TARGET"   (TARGET = claude:// URL)
#   activate  → terminal-notifier -activate "$TARGET" (TARGET = bundle id)
#   none      → no clickable action; caller falls back to a plain banner
#
# click_mode (default: activate):
#   activate  → bring the Claude desktop app to the foreground. RELIABLE on
#               modern macOS: terminal-notifier's -activate click is handled
#               OS-natively. This is the default because it always works and
#               satisfies the primary goal ("open the Claude desktop app"); for
#               a single active session, focusing the app lands on that session.
#   resume    → deep-link to THIS session if session_id is a valid UUID, else
#               fall back to activate. The desktop app route
#               `claude://claude.ai/resume?session=<uuid>` is handled by its
#               deep-link router (host gh.ClaudeAI="claude.ai", path
#               lg.Resume="resume") which calls importCliSession(<uuid>).
#               CAVEAT: on macOS 26 terminal-notifier's -open click callback no
#               longer fires (it relied on the deprecated NSUserNotification
#               delegate), so a clicked banner does NOT navigate there — only a
#               direct `open <url>` does. Kept as opt-in for older macOS where
#               -open clicks still work.
#   auto      → activate when entrypoint=="claude-desktop" (the session is
#               already open in the app, so focusing it is enough); otherwise
#               behave like resume (pull a terminal/CLI session into the app).
#   off       → ACTION=none (caller uses the non-clickable fallback banner).
#
# The deep-link host/path/param were reverse-engineered from
# /Applications/Claude.app and validated against the app's own session-id regex
# (IAA = /^[0-9a-fA-F]{8}-...{12}$/i). They are an UNDOCUMENTED app surface and
# may change between Claude desktop versions — hence "resume" degrades to
# "activate" whenever the session id is missing or malformed, and the whole
# feature degrades to the plain osascript banner when terminal-notifier is
# absent. Never throws, never blocks.

set -u

CLAUDE_BUNDLE_ID="com.anthropic.claudefordesktop"
# Mirrors the desktop app's IAA session-id regex (canonical UUID, any case).
UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

MODE="${1:-activate}"
SESSION_ID="${2:-}"
ENTRYPOINT="${3:-}"

emit() {
  printf 'ACTION=%s\nTARGET=%s\n' "$1" "$2"
  exit 0
}

# Build the resume deep link only for a well-formed UUID.
deep_link_or_empty() {
  if printf '%s' "$SESSION_ID" | grep -qE "$UUID_RE"; then
    printf 'claude://claude.ai/resume?session=%s' "$SESSION_ID"
  fi
}

# NOTE: stock macOS ships bash 3.2 — no `;&` case fall-through, no `${arr[@]}`
# under `set -u`. Keep the control flow to plain if/case.
case "$MODE" in
  off)
    emit none ""
    ;;
  resume)
    LINK="$(deep_link_or_empty)"
    [ -n "$LINK" ] && emit open "$LINK"
    emit activate "$CLAUDE_BUNDLE_ID"
    ;;
  auto)
    # Already inside the desktop app → focusing it returns the user to the
    # waiting prompt; no need to re-import the session. Other entrypoints
    # (terminal/CLI) get the resume deep-link below.
    # NOTE: "claude-desktop" is the empirically-confirmed value of
    # CLAUDE_CODE_ENTRYPOINT when running inside the Claude desktop app
    # (verified live). This is a best-effort match — if the value ever changes,
    # `auto` simply behaves like `resume`, which still degrades safely.
    if [ "$ENTRYPOINT" = "claude-desktop" ]; then
      emit activate "$CLAUDE_BUNDLE_ID"
    fi
    LINK="$(deep_link_or_empty)"
    [ -n "$LINK" ] && emit open "$LINK"
    emit activate "$CLAUDE_BUNDLE_ID"
    ;;
  activate|*)
    # Default + unknown modes resolve to the always-reliable activate action.
    emit activate "$CLAUDE_BUNDLE_ID"
    ;;
esac

# Unreachable (every case emits), but keep the invariant explicit.
emit activate "$CLAUDE_BUNDLE_ID"
