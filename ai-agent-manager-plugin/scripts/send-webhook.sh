#!/usr/bin/env bash
# send-webhook.sh — WEBHOOK NOTIFICATION WRAPPER (v12.2.0, Subtask S4)
#
# INVARIANT: ALWAYS exits 0. The SubagentStop hook must never see a non-zero
# exit from this script. All failure modes (missing env var, missing curl/jq,
# malformed payload, network failure, non-2xx response) are absorbed silently.
#
# Authoritative spec: ai-agent-manager-plugin/docs/TELEMETRY.md §"Webhook Notifications"
#
# Behaviour:
#   1. If AI_AGENT_MANAGER_WEBHOOK_URL is unset/empty → exit 0 (silent no-op).
#   2. Read SubagentStop JSON payload from stdin.
#   3. Use `jq -r // empty` to defensively extract SUPERVISOR_RESULT fields
#      (status, pr_url, summary). On parse failure → log to stderr, exit 0.
#   4. If `curl` not on PATH → log to stderr, exit 0.
#   5. POST a small JSON body {agent, status, pr_url, summary, timestamp} to
#      the webhook URL with a hard 5s timeout.
#   6. ALWAYS exit 0 regardless of curl outcome (fire-and-forget).
#
# Why a `type: command` wrapper instead of `type: http` hook:
#   Claude Code env-var interpolation only substitutes ${VAR} inside HTTP
#   `headers`, not inside `url`. To gate on AI_AGENT_MANAGER_WEBHOOK_URL the URL
#   must resolve at hook-fire time inside a script, not in the hook config.
#
# Style/structure mirrors send-telemetry.sh (sibling wrapper).

set -u
# Intentionally NO `set -e` — wrapper must absorb every child failure.
# pipefail is also OFF for the same reason.

# ---- Gate on env var --------------------------------------------------------
WEBHOOK_URL="${AI_AGENT_MANAGER_WEBHOOK_URL:-}"
if [ -z "$WEBHOOK_URL" ]; then
  exit 0
fi

# ---- Read stdin -------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  printf 'send-webhook: empty stdin payload\n' >&2
  exit 0
fi

# ---- Tool availability ------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  printf 'send-webhook: curl not on PATH — skipping\n' >&2
  exit 0
fi

JQ_BIN=""
if command -v jq >/dev/null 2>&1; then
  JQ_BIN="jq"
fi

# ---- Event-type branch ------------------------------------------------------
# This script is wired to two distinct hook events:
#   - SubagentStop (supervisor-runner): post final SUPERVISOR_RESULT.
#   - PreToolUse (AskUserQuestion):     post a "paused" event so the user
#                                       knows the plugin is blocked on input.
# Branch early so the SUPERVISOR_RESULT YAML-parsing path stays untouched.
HOOK_EVENT=""
TOOL_NAME=""
if [ -n "$JQ_BIN" ]; then
  HOOK_EVENT="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.hook_event_name // empty' 2>/dev/null || true)"
  TOOL_NAME="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.tool_name // empty' 2>/dev/null || true)"
fi

if [ "$HOOK_EVENT" = "PreToolUse" ] && [ "$TOOL_NAME" = "AskUserQuestion" ]; then
  # ---- Paused-event path (AskUserQuestion) ----------------------------------
  # The plugin is about to block on user input — Supervisor adjudication,
  # rubric gate, Plan Reviewer NEEDS_HUMAN, Launch Pad Phase 6, /autonomous
  # merge-and-continue, etc. Send a minimal payload so an external service
  # (Slack incoming-webhook, etc.) can ping the operator.

  # Defense-in-depth: also require the tool_input.questions field to exist
  # before treating this as a plugin pause event. Guards against future
  # SubagentStop payload schemas that happen to carry tool_name="AskUserQuestion".
  HAS_QUESTIONS=""
  if [ -n "$JQ_BIN" ]; then
    HAS_QUESTIONS="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.tool_input.questions // empty' 2>/dev/null || true)"
  fi
  if [ -z "$HAS_QUESTIONS" ]; then
    printf 'send-webhook: AskUserQuestion-tagged payload lacks tool_input.questions — skipping\n' >&2
    exit 0
  fi

  # Scope gate: AI_AGENT_MANAGER_NOTIFY_SCOPE=plugin (default) suppresses
  # paused-event webhook fires when no plugin context is detected. Operators
  # who want host-wide AskUserQuestion notifications set this to `all`.
  # Detection identical to notify-desktop.sh §"Scope gate" — three independent
  # markers (active Supervisor job, recent autonomous state, transcript marker).
  SCOPE="${AI_AGENT_MANAGER_NOTIFY_SCOPE:-plugin}"
  if [ "$SCOPE" = "plugin" ]; then
    TRANSCRIPT_PATH=""
    if [ -n "$JQ_BIN" ]; then
      TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.transcript_path // empty' 2>/dev/null || true)"
    fi
    PLUGIN_CONTEXT=0
    if compgen -G ".supervisor/jobs/in-progress/*.md" > /dev/null 2>&1; then
      PLUGIN_CONTEXT=1
    fi
    if [ "$PLUGIN_CONTEXT" -eq 0 ]; then
      for state_file in .supervisor/autonomous/*/state.json; do
        [ -f "$state_file" ] || continue
        if [ -n "$(find "$state_file" -mmin -120 2>/dev/null)" ]; then
          PLUGIN_CONTEXT=1
          break
        fi
      done
    fi
    if [ "$PLUGIN_CONTEXT" -eq 0 ] && [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
      if tail -200 "$TRANSCRIPT_PATH" 2>/dev/null | grep -qE 'ai-agent-manager-plugin:|/launch-pad|/supervisor|/autonomous|/code-reviewer|/qa-executor|/qa-strategist|/red-team-reviewer|/product-owner|/agent-help|/telemetry|/dreaming'; then
        PLUGIN_CONTEXT=1
      fi
    fi
    if [ "$PLUGIN_CONTEXT" -eq 0 ]; then
      exit 0
    fi
  fi

  QUESTION=""
  if [ -n "$JQ_BIN" ]; then
    QUESTION="$(printf '%s' "$INPUT" \
      | "$JQ_BIN" -r '.tool_input.questions[0].question // .tool_input.questions[0].header // empty' \
      2>/dev/null || true)"
  fi
  if [ -z "$QUESTION" ]; then
    QUESTION="Plugin is paused on a user question"
  fi
  # Truncate to keep Slack-class webhook bodies small.
  if [ "${#QUESTION}" -gt 1024 ]; then
    QUESTION="$(printf '%s' "$QUESTION" | head -c 1021)..."
  fi
  TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  PAYLOAD=""
  if [ -n "$JQ_BIN" ]; then
    PAYLOAD="$("$JQ_BIN" -nc \
      --arg event     "paused" \
      --arg question  "$QUESTION" \
      --arg timestamp "$TIMESTAMP" \
      '{event: $event, question: $question, timestamp: $timestamp}' \
      2>/dev/null || true)"
  fi
  if [ -z "$PAYLOAD" ]; then
    # Fallback minimal payload without jq. $TIMESTAMP is safe to inline (digits,
    # dashes, colons, T, Z only). $QUESTION is NOT JSON-safe — without jq we
    # cannot guarantee escaping, so fall back to a static body that signals the
    # pause without leaking unescaped content.
    PAYLOAD='{"event":"paused","question":"(jq not available; install jq for question text)","timestamp":"'"$TIMESTAMP"'"}'
  fi
  curl -fs --max-time 5 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$WEBHOOK_URL" >/dev/null 2>&1 || true
  exit 0
fi

# ---- Extract SUPERVISOR_RESULT fields ---------------------------------------
# Claude Code SubagentStop payload shape (matches send-telemetry-core.sh):
#   { "session_id": "...", "agent_type": "...", "result_block": "SUPERVISOR_RESULT:\n  schema_version: 1\n  status: completed\n  pr_url: https://...\n  summary: ..." }
# The fields we want live INSIDE the `result_block` text — not at the top level.
# Strategy:
#   1. Use jq to lift `result_block` out of the JSON envelope (string).
#   2. Grep the YAML-style `key: value` lines from that text using sed.
#   3. Fall back to top-level keys if `result_block` is absent (forward compat
#      and unit-test fixtures that pass a flat object).
STATUS=""
PR_URL=""
SUMMARY=""

# yaml_field <text> <key>  →  prints the value of `  key: value` (case-sensitive
# match against lowercase keys; SUPERVISOR_RESULT schema in docs/RESULT_SCHEMAS.md
# always emits keys in lowercase). Tolerates leading dash for bullet-style blocks.
# Strips surrounding double-quotes and whitespace. Returns empty when not found.
#
# Portability: BSD sed (macOS) historically lacks the `/I` case-insensitive flag,
# so we match only lowercase keys. Stick to the documented schema casing — do
# not add `/I` here, it breaks on older BSD sed.
#
# Value-shape assumption: SUPERVISOR_RESULT emits single-line values per the
# schema convention in agents/supervisor.md §"Result Block" (status, pr_url,
# summary are all one-liners; summary is also truncated to 2KB earlier in this
# script). The `[^"]*` capture stops at the first embedded double-quote, which
# would silently truncate a summary that contains a literal `"` mid-string.
# That is acceptable today because the schema does not produce such values; if
# the schema ever permits embedded quotes in single-line fields, switch to a
# tighter quoted-string parser or extract via jq from the JSON envelope only.
yaml_field() {
  printf '%s' "$1" | sed -nE \
    "s/^[[:space:]]*-?[[:space:]]*$2[[:space:]]*:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/p" \
    | head -n1
}

if [ -n "$JQ_BIN" ]; then
  RESULT_BLOCK="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.result_block // empty' 2>/dev/null || true)"

  if [ -n "$RESULT_BLOCK" ]; then
    STATUS="$(yaml_field "$RESULT_BLOCK" status)"
    PR_URL="$(yaml_field "$RESULT_BLOCK" pr_url)"
    SUMMARY="$(yaml_field "$RESULT_BLOCK" summary)"
  fi

  # Forward-compat / fixture fallback: top-level keys if result_block was empty
  # or did not carry the field.
  if [ -z "$STATUS" ]; then
    STATUS="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.status // .result.status // empty' 2>/dev/null || true)"
  fi
  if [ -z "$PR_URL" ]; then
    PR_URL="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.pr_url // .result.pr_url // empty' 2>/dev/null || true)"
  fi
  if [ -z "$SUMMARY" ]; then
    SUMMARY="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.summary // .result.summary // empty' 2>/dev/null || true)"
  fi
else
  printf 'send-webhook: jq not on PATH — fields will be empty\n' >&2
fi

# ---- Payload validity guard -------------------------------------------------
# If status is empty after all extraction attempts, supervisor did not produce
# a valid SUPERVISOR_RESULT block (failed/aborted run, or jq absent).
# Skip the POST — sending an all-empty payload provides no signal and produces
# spam notifications.
if [ -z "$STATUS" ]; then
  printf 'send-webhook: no status in result block — skipping POST\n' >&2
  exit 0
fi

# Truncate summary defensively. Slack incoming-webhooks reject bodies > 40 KB;
# other endpoints may be stricter. Keep summaries small even if the result block
# is unbounded.
if [ "${#SUMMARY}" -gt 2048 ]; then
  SUMMARY="$(printf '%s' "$SUMMARY" | head -c 2045)..."
fi

# ---- Compose payload --------------------------------------------------------
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# Build JSON safely. Prefer jq if available (handles escaping); otherwise emit
# a minimal object (status/pr_url/summary may be empty strings).
PAYLOAD=""
if [ -n "$JQ_BIN" ]; then
  PAYLOAD="$("$JQ_BIN" -nc \
    --arg agent     "supervisor" \
    --arg status    "$STATUS" \
    --arg pr_url    "$PR_URL" \
    --arg summary   "$SUMMARY" \
    --arg timestamp "$TIMESTAMP" \
    '{agent: $agent, status: $status, pr_url: $pr_url, summary: $summary, timestamp: $timestamp}' \
    2>/dev/null || true)"
fi

if [ -z "$PAYLOAD" ]; then
  # Fallback minimal payload — fields are deliberately empty when jq is absent.
  # $TIMESTAMP is safe to inline into the JSON string here: `date -u
  # +%Y-%m-%dT%H:%M:%SZ` only ever produces digits, dashes, colons, T, and Z
  # (no double-quotes, backslashes, or control chars), so no JSON-escape
  # hazard. The `|| echo unknown` fallback above produces the literal token
  # "unknown" which is also JSON-safe.
  PAYLOAD='{"agent":"supervisor","status":"","pr_url":"","summary":"","timestamp":"'"$TIMESTAMP"'"}'
fi

# ---- Fire webhook (fire-and-forget) -----------------------------------------
# -f : fail (exit non-zero) on HTTP error so `|| true` swallows it
# -s : silent (no progress meter)
# --max-time 5 : hard 5s ceiling so a slow endpoint never blocks Supervisor
curl -fs --max-time 5 \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$WEBHOOK_URL" >/dev/null 2>&1 || true

exit 0
