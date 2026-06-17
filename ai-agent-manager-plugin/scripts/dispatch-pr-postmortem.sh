#!/usr/bin/env bash
# dispatch-pr-postmortem.sh — CHURN-GATED AUTO-POSTMORTEM DISPATCHER (review-heal)
#
# Fired from the review-heal loop's "Postmortem Dispatch Tail" (skills/review-heal/
# SKILL.md) AFTER the loop's decision is already computed + emitted. It conditionally
# launches the EXISTING read-only `/pr-postmortem <pr-url>` as a fresh detached
# `claude` process so a meaningful-churn PR captures a learning signal — but it can
# NEVER alter REVIEW_HEAL_RESULT.decision (the decision is finalized before this runs)
# and NEVER mutates a repo file (`/pr-postmortem` only APPENDS to
# .supervisor/postmortem/results.jsonl).
#
# Canonical names are coined in skills/review-heal/SKILL.md — consumed VERBATIM here:
#   opt-out flag        : --no-auto-postmortem   (or auto_postmortem: false in config)
#   churn-threshold flag: --postmortem-churn-threshold N (or .postmortem_churn_threshold)
#   dispatch target     : the EXISTING /pr-postmortem command (already present)
#
# CONTRACT
# --------
#   INVARIANT: ALWAYS exits 0 (AC12 — the hard guarantee). Called from a LOAD-BEARING
#   completion tail; it must NEVER hard-fail the loop. Every failure mode (missing
#   claude/jq/config, malformed config, already-dispatched, disabled, gate-not-tripped)
#   is absorbed: log exactly ONE line to stderr and exit 0. Fire-and-forget. It NEVER
#   alters REVIEW_HEAL_RESULT.decision — the decision is computed and emitted by the
#   loop BEFORE this script is ever invoked (AC12).
#
#   OPT-OUT (AC13). No postmortem is dispatched, regardless of churn, when EITHER:
#     1. --no-auto-postmortem was passed, OR
#     2. .supervisor/notify-config.json has `.auto_postmortem == false`.
#   Auto-postmortem is otherwise ON-by-default within --until-mergeable — but always
#   CHURN-GATED (below); a clean PR is a silent no-op (AC9).
#
#   CHURN GATE (AC9/AC10/AC11). Even when enabled, dispatch fires ONLY when the run
#   took MEANINGFUL churn — ANY of these OR-triggers (passed in by the loop as flags):
#     * --fix-cycles N      > threshold              (default threshold 2, AC11)
#     * --decision ESCALATED                         (escalated / timed-out)
#     * --repeat-check-failure                       (same required check failed after a fix)
#     * --unresolved-bot-feedback                    (bot feedback still open after >=1 fix)
#   If NONE trip, log one line and exit 0 with NO dispatch (the clean-PR no-op, AC9).
#   The threshold is read from .supervisor/notify-config.json `.postmortem_churn_threshold`
#   via jq (NOT an env var — same repo-local-config rationale as dispatch-pr-review.sh),
#   overridable by --postmortem-churn-threshold N; default 2.
#
#   COST / RUNAWAY GUARD. A per-PR dispatch marker file under
#   .supervisor/postmortem-dispatch/ (keyed by a hash of the PR URL) ensures a given PR
#   is postmortem-dispatched AT MOST ONCE. If the marker already exists, log one line
#   and exit 0 — prevents a re-dispatch loop (e.g. a re-run of the tail on the same PR).
#
#   FRESH DETACHED PROCESS (R10). When enabled + gate-tripped + not yet dispatched,
#   launch a brand-new detached `claude /pr-postmortem <pr-url>` OS process (nohup +
#   background + full stdio redirection to a log under .supervisor/logs/). A fresh OS
#   process — NOT a nested Task spawn — is mandatory because subagents cannot spawn
#   subagents; the review-heal loop body is itself Task-spawned in the /autonomous
#   EVALUATE sense, so a nested Task(/pr-postmortem) would land one spawn-level too
#   deep. See skills/review-heal/SKILL.md "Postmortem Dispatch Tail".
#
# USAGE
#   dispatch-pr-postmortem.sh <pr-url> [gating flags...]
#   dispatch-pr-postmortem.sh --pr-url <pr-url> [gating flags...]
#     gating flags:
#       --no-auto-postmortem
#       --fix-cycles N
#       --decision PASS|ESCALATED|READY
#       --repeat-check-failure
#       --unresolved-bot-feedback
#       --postmortem-churn-threshold N
#
# ENV (test/escape hatches — all optional)
#   AI_AGENT_MANAGER_POSTMORTEM_DISPATCH_DRY_RUN=1
#     When set non-empty, the gating decision runs to completion but the real `claude`
#     process is NOT launched; instead the would-be command is printed to stdout as
#     `DRY_RUN_DISPATCH: <cmd>` and the marker is still written. Used by
#     test-dispatch-pr-postmortem.sh so the self-test never spawns claude.
#   AI_AGENT_MANAGER_CLAUDE_BIN
#     Override the claude binary name (default `claude`). Lets a test point at a stub.
#
# Style/structure mirrors dispatch-pr-review.sh (sibling fire-and-forget dispatcher).

set -u
# Intentionally NO `set -e` / pipefail — dispatcher must absorb every child failure.

log() { printf 'dispatch-pr-postmortem: %s\n' "$1" >&2; }

CONFIG_FILE=".supervisor/notify-config.json"
DISPATCH_DIR=".supervisor/postmortem-dispatch"
LOG_DIR=".supervisor/logs"
CLAUDE_BIN="${AI_AGENT_MANAGER_CLAUDE_BIN:-claude}"
DRY_RUN="${AI_AGENT_MANAGER_POSTMORTEM_DISPATCH_DRY_RUN:-}"
DEFAULT_THRESHOLD=2

# ---- Parse args -------------------------------------------------------------
# First bare (non-flag) argument is treated as the PR URL. --pr-url <url> also
# supported. The gating flags carry the loop's churn signals.
PR_URL=""
SUPPRESS=0                 # --no-auto-postmortem seen
FIX_CYCLES=0               # --fix-cycles N
DECISION=""                # --decision PASS|ESCALATED|READY
REPEAT_CHECK_FAILURE=0     # --repeat-check-failure
UNRESOLVED_BOT_FEEDBACK=0  # --unresolved-bot-feedback
THRESHOLD_OVERRIDE=""      # --postmortem-churn-threshold N

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
    --no-auto-postmortem)
      SUPPRESS=1
      shift
      ;;
    --fix-cycles)
      FIX_CYCLES="${2:-0}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --fix-cycles=*)
      FIX_CYCLES="${1#--fix-cycles=}"
      shift
      ;;
    --decision)
      DECISION="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --decision=*)
      DECISION="${1#--decision=}"
      shift
      ;;
    --repeat-check-failure)
      REPEAT_CHECK_FAILURE=1
      shift
      ;;
    --unresolved-bot-feedback)
      UNRESOLVED_BOT_FEEDBACK=1
      shift
      ;;
    --postmortem-churn-threshold)
      THRESHOLD_OVERRIDE="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --postmortem-churn-threshold=*)
      THRESHOLD_OVERRIDE="${1#--postmortem-churn-threshold=}"
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

# ---- Sanitize numeric inputs (fail-safe: garbage => safe default) -----------
case "$FIX_CYCLES" in ''|*[!0-9]*) FIX_CYCLES=0 ;; esac
case "$THRESHOLD_OVERRIDE" in *[!0-9]*) THRESHOLD_OVERRIDE="" ;; esac

# ---- Opt-out short-circuit (AC13) -------------------------------------------
# CLI --no-auto-postmortem wins outright. Config auto_postmortem:false also opts out.
if [ "$SUPPRESS" -eq 1 ]; then
  log "--no-auto-postmortem passed — auto-postmortem suppressed"
  exit 0
fi
if [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  # NB: read the raw value, NOT `.auto_postmortem // empty` — the boolean `false`
  # is falsy in jq's `//`, so `false // empty` would collapse to empty and silently
  # defeat this opt-out (the canonical `||`/falsy-coercion self-heal miss-class).
  AUTO_PM="$(jq -r 'if has("auto_postmortem") then .auto_postmortem else empty end' "$CONFIG_FILE" 2>/dev/null || true)"
  if [ "$AUTO_PM" = "false" ]; then
    log "config .auto_postmortem == false — auto-postmortem suppressed"
    exit 0
  fi
fi

# ---- Require a PR URL -------------------------------------------------------
if [ -z "$PR_URL" ]; then
  log "no PR URL supplied — nothing to dispatch"
  exit 0
fi

# ---- Resolve churn threshold ------------------------------------------------
# Precedence: --postmortem-churn-threshold N > config .postmortem_churn_threshold >
# default 2. Config is read via jq (NOT env var) — same rationale as
# dispatch-pr-review.sh's auto_review resolution.
THRESHOLD="$DEFAULT_THRESHOLD"
if [ -n "$THRESHOLD_OVERRIDE" ]; then
  THRESHOLD="$THRESHOLD_OVERRIDE"
elif [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  CFG_THRESHOLD="$(jq -r '.postmortem_churn_threshold // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  case "$CFG_THRESHOLD" in
    ''|*[!0-9]*) : ;;                 # absent or non-numeric => keep default
    *) THRESHOLD="$CFG_THRESHOLD" ;;
  esac
fi

# ---- Churn gate (AC9/AC10/AC11) ---------------------------------------------
# Dispatch fires when ANY OR-trigger is true. NONE => clean-PR no-op (AC9).
TRIGGERED=0
TRIGGER_REASON=""
if [ "$FIX_CYCLES" -gt "$THRESHOLD" ]; then
  TRIGGERED=1
  TRIGGER_REASON="fix_cycles($FIX_CYCLES) > threshold($THRESHOLD)"
elif [ "$DECISION" = "ESCALATED" ]; then
  TRIGGERED=1
  TRIGGER_REASON="decision == ESCALATED"
elif [ "$REPEAT_CHECK_FAILURE" -eq 1 ]; then
  TRIGGERED=1
  TRIGGER_REASON="repeat required-check failure after a fix"
elif [ "$UNRESOLVED_BOT_FEEDBACK" -eq 1 ]; then
  TRIGGERED=1
  TRIGGER_REASON="bot feedback unresolved after >=1 fix"
fi

if [ "$TRIGGERED" -ne 1 ]; then
  # Clean / low-churn PR — the silent no-op path (AC9).
  log "churn gate not tripped (fix_cycles=$FIX_CYCLES threshold=$THRESHOLD decision='${DECISION:-}' repeat_check=$REPEAT_CHECK_FAILURE unresolved_bot=$UNRESOLVED_BOT_FEEDBACK) — skipping postmortem"
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
  log "PR already postmortem-dispatched this run (marker exists: $MARKER) — skipping re-dispatch"
  exit 0
fi

# ---- Dry-run short-circuit (honored BEFORE requiring the claude binary) ------
# In dry-run the claude process is never launched, so its presence on PATH is
# irrelevant. Emit the would-be command + write the marker (so the marker-guard path
# is still exercised) WITHOUT requiring the binary — keeps the self-test
# (test-dispatch-pr-postmortem.sh) claude-independent on CI runners with no `claude`.
if [ -n "$DRY_RUN" ]; then
  printf 'DRY_RUN_DISPATCH: %s /pr-postmortem %s\n' "$CLAUDE_BIN" "$PR_URL"
  printf '%s\n' "$PR_URL" > "$MARKER" 2>/dev/null || true
  exit 0
fi

# ---- Require the claude binary ----------------------------------------------
if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  log "'$CLAUDE_BIN' not on PATH — cannot launch /pr-postmortem, skipping"
  exit 0
fi

# ---- Launch the fresh detached /pr-postmortem process -----------------------
mkdir -p "$LOG_DIR" 2>/dev/null || true
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
RUN_LOG="$LOG_DIR/pr-postmortem-dispatch-$TIMESTAMP-$PR_HASH.log"

# Write the marker BEFORE launching so a crash mid-launch still blocks re-dispatch
# (fail-closed against runaway). The marker records the PR URL + dispatch time.
printf '%s\t%s\n' "$TIMESTAMP" "$PR_URL" > "$MARKER" 2>/dev/null || true

# Fire-and-forget: fully detached so the loop's completion tail returns immediately.
# nohup + background subshell + all stdio redirected away from the caller's inherited
# pipes. The detached process is a fresh `claude` invocation of the EXISTING
# /pr-postmortem command (NOT a nested Task spawn — R10).
( nohup "$CLAUDE_BIN" "/pr-postmortem $PR_URL" >>"$RUN_LOG" 2>&1 </dev/null & ) >/dev/null 2>&1 || true

log "dispatched /pr-postmortem for $PR_URL ($TRIGGER_REASON; log: $RUN_LOG)"
exit 0
