#!/usr/bin/env bash
# dispatch-pr-review.sh — POST-/supervisor AUTO-REVIEW DISPATCHER (review-heal)
#
# Canonical names are coined in skills/review-heal/SKILL.md — consumed VERBATIM here:
#   enable signal : auto_review: true   in .supervisor/notify-config.json (or --auto-review)
#   opt-out flag  : --no-auto-review
#   runner agent  : ai-agent-manager-plugin:review-pr-runner
#
# CONTRACT
# --------
#   INVARIANT: ALWAYS exits 0. Called from Supervisor Phase 4.5's completion tail
#   (a LOAD-BEARING path) — it must NEVER hard-fail the tail. Every failure mode
#   (missing claude/jq/config, malformed config, already-dispatched, disabled) is
#   absorbed: log exactly ONE line to stderr and exit 0. Fire-and-forget.
#
#   GATING (config-file-driven, NOT env-var inheritance — AC5). Auto-review is OFF
#   by default. It is enabled ONLY when BOTH hold:
#     1. NOT suppressed: --no-auto-review was not passed.
#     2. Enabled: --auto-review was passed, OR
#        .supervisor/notify-config.json has `.auto_review == true`.
#   Reading config from a repo-local JSON file (via jq) — rather than an exported
#   env var — sidesteps the known ~/.zshrc env-propagation failure class where a
#   var exported only in an interactive rc never reaches a non-interactive
#   subprocess (same rationale as send-webhook.sh's webhook_url resolution).
#
#   COST / RUNAWAY GUARD. A per-PR dispatch marker file under
#   .supervisor/review-dispatch/ (keyed by a hash of the PR URL) ensures a given
#   PR is dispatched AT MOST ONCE. If the marker already exists, log one line and
#   exit 0 — this prevents a re-dispatch loop (e.g. a Supervisor --continue that
#   re-runs the completion tail on the same PR). Combined with the fact that
#   /review-pr NEVER creates a PR, there is no review->review recursion.
#
#   FRESH DETACHED PROCESS. When enabled + not yet dispatched, launch a brand-new
#   detached `claude --agent ai-agent-manager-plugin:review-pr-runner <pr-url>`
#   OS process (nohup + background + full stdio redirection to a log under
#   .supervisor/logs/). A fresh OS process means the runner is the MAIN agent of
#   its own session and can therefore spawn its own child agents (code-reviewer /
#   fix worker) — see skills/review-heal/SKILL.md "Two entry senses of fresh" (a).
#
# USAGE
#   dispatch-pr-review.sh <pr-url> [--no-auto-review|--auto-review]
#   dispatch-pr-review.sh --pr-url <pr-url> [--no-auto-review|--auto-review]
#
# ENV (test/escape hatches — all optional)
#   AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN=1
#     When set non-empty, the gating decision runs to completion but the real
#     `claude` process is NOT launched; instead the would-be command is printed
#     to stdout as `DRY_RUN_DISPATCH: <cmd>` and the marker is still written.
#     Used by test-dispatch-pr-review.sh so the self-test never spawns claude.
#   AI_AGENT_MANAGER_CLAUDE_BIN
#     Override the claude binary name (default `claude`). Lets a test point at a
#     stub on PATH if it ever wants to exercise the launch path.
#
# Style/structure mirrors send-webhook.sh (sibling fire-and-forget wrapper).

set -u
# Intentionally NO `set -e` / pipefail — wrapper must absorb every child failure.

log() { printf 'dispatch-pr-review: %s\n' "$1" >&2; }

CONFIG_FILE=".supervisor/notify-config.json"
DISPATCH_DIR=".supervisor/review-dispatch"
LOG_DIR=".supervisor/logs"
CLAUDE_BIN="${AI_AGENT_MANAGER_CLAUDE_BIN:-claude}"
RUNNER="ai-agent-manager-plugin:review-pr-runner"
DRY_RUN="${AI_AGENT_MANAGER_REVIEW_DISPATCH_DRY_RUN:-}"

# ---- Parse args -------------------------------------------------------------
# First bare (non-flag) argument is treated as the PR URL. --pr-url <url> also
# supported. --no-auto-review / --auto-review set the suppress/force signals.
PR_URL=""
SUPPRESS=0   # --no-auto-review seen
FORCE=0      # --auto-review seen

while [ $# -gt 0 ]; do
  case "$1" in
    --pr-url)
      PR_URL="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --pr-url=*)
      PR_URL="${1#--pr-url=}"
      shift
      ;;
    --no-auto-review)
      SUPPRESS=1
      shift
      ;;
    --auto-review)
      FORCE=1
      shift
      ;;
    --*)
      # Unknown flag — ignore (forward compat).
      shift
      ;;
    *)
      # First bare argument is the PR URL; later bare args ignored.
      [ -z "$PR_URL" ] && PR_URL="$1"
      shift
      ;;
  esac
done

# ---- Opt-out short-circuit --------------------------------------------------
if [ "$SUPPRESS" -eq 1 ]; then
  log "--no-auto-review passed — auto-review suppressed"
  exit 0
fi

# ---- Require a PR URL -------------------------------------------------------
if [ -z "$PR_URL" ]; then
  log "no PR URL supplied — nothing to dispatch"
  exit 0
fi

# ---- Resolve enable signal --------------------------------------------------
# Enabled when --auto-review was passed OR notify-config.json has auto_review:true.
# Config is read via jq (NOT env var) — see header AC5 rationale.
ENABLED=0
if [ "$FORCE" -eq 1 ]; then
  ENABLED=1
elif [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  AUTO_REVIEW="$(jq -r '.auto_review // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  if [ "$AUTO_REVIEW" = "true" ]; then
    ENABLED=1
  fi
fi

if [ "$ENABLED" -ne 1 ]; then
  # OFF by default — the common, silent-ish no-op path.
  log "auto-review disabled (no --auto-review and config .auto_review != true) — skipping"
  exit 0
fi

# ---- Per-PR dispatch marker (cost / runaway guard) --------------------------
# Key the marker by a hash of the PR URL so a given PR dispatches at most once.
mkdir -p "$DISPATCH_DIR" 2>/dev/null || true
PR_HASH=""
if command -v shasum >/dev/null 2>&1; then
  PR_HASH="$(printf '%s' "$PR_URL" | shasum 2>/dev/null | cut -d' ' -f1 || true)"
elif command -v sha1sum >/dev/null 2>&1; then
  PR_HASH="$(printf '%s' "$PR_URL" | sha1sum 2>/dev/null | cut -d' ' -f1 || true)"
fi
# Fallback to a sanitized URL if no hashing tool is present (still unique per PR).
if [ -z "$PR_HASH" ]; then
  PR_HASH="$(printf '%s' "$PR_URL" | tr -c 'A-Za-z0-9' '-' )"
fi
MARKER="$DISPATCH_DIR/$PR_HASH"

if [ -e "$MARKER" ]; then
  log "PR already dispatched this run (marker exists: $MARKER) — skipping re-dispatch"
  exit 0
fi

# ---- Dry-run short-circuit (honored BEFORE requiring the claude binary) ------
# In dry-run the claude process is never launched, so its presence on PATH is
# irrelevant. Emit the would-be command + write the marker (so the marker-guard
# path is still exercised) WITHOUT requiring the binary. This keeps the self-test
# (test-dispatch-pr-review.sh) claude-independent on CI runners that have no
# `claude` on PATH — previously the claude check below short-circuited first,
# making the dry-run a no-op on CI.
if [ -n "$DRY_RUN" ]; then
  printf 'DRY_RUN_DISPATCH: %s --agent %s %s\n' "$CLAUDE_BIN" "$RUNNER" "$PR_URL"
  printf '%s\n' "$PR_URL" > "$MARKER" 2>/dev/null || true
  exit 0
fi

# ---- Require the claude binary ----------------------------------------------
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  log "'$CLAUDE_BIN' not on PATH — cannot launch review-pr-runner, skipping"
  exit 0
fi

# ---- Launch the fresh detached review-pr-runner process ---------------------
mkdir -p "$LOG_DIR" 2>/dev/null || true
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
RUN_LOG="$LOG_DIR/review-pr-dispatch-$TIMESTAMP-$PR_HASH.log"

# Write the marker BEFORE launching so a crash mid-launch still blocks re-dispatch
# (fail-closed against runaway). The marker records the PR URL + dispatch time.
printf '%s\t%s\n' "$TIMESTAMP" "$PR_URL" > "$MARKER" 2>/dev/null || true

# Fire-and-forget: fully detached so the Supervisor completion tail returns
# immediately. nohup + background subshell + all stdio redirected away from the
# caller's inherited pipes (a backgrounded child still holding the tail's stdout
# would keep the tail "running" until it exits).
( nohup "$CLAUDE_BIN" --agent "$RUNNER" "$PR_URL" >>"$RUN_LOG" 2>&1 </dev/null & ) >/dev/null 2>&1 || true

log "dispatched review-pr-runner for $PR_URL (log: $RUN_LOG)"
exit 0
