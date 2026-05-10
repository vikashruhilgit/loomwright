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
#   1. If AGENT_MANAGER_WEBHOOK_URL is unset/empty → exit 0 (silent no-op).
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
#   `headers`, not inside `url`. To gate on AGENT_MANAGER_WEBHOOK_URL the URL
#   must resolve at hook-fire time inside a script, not in the hook config.
#
# Style/structure mirrors send-telemetry.sh (sibling wrapper).

set -u
# Intentionally NO `set -e` — wrapper must absorb every child failure.
# pipefail is also OFF for the same reason.

# ---- Gate on env var --------------------------------------------------------
WEBHOOK_URL="${AGENT_MANAGER_WEBHOOK_URL:-}"
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

# yaml_field <text> <key>  →  prints the value of `  key: value` (case-insensitive,
# tolerates leading dash for bullet-style blocks). Strips surrounding quotes and
# whitespace. Returns empty when not found.
yaml_field() {
  printf '%s' "$1" | sed -nE \
    "s/^[[:space:]]*-?[[:space:]]*$2[[:space:]]*:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/Ip" \
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
