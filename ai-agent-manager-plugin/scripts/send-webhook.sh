#!/usr/bin/env bash
# send-webhook.sh — WEBHOOK NOTIFICATION WRAPPER (v14.0.0, Subtask S2)
#
# INVARIANT: ALWAYS exits 0. The SubagentStop hook must never see a non-zero
# exit from this script. All failure modes (missing env var, missing curl/jq,
# malformed payload, network failure, non-2xx response) are absorbed silently.
#
# Authoritative spec: ai-agent-manager-plugin/docs/TELEMETRY.md §"Webhook Notifications"
#
# ----------------------------------------------------------------------------
# EVENT TYPES (v14.0.0)
# ----------------------------------------------------------------------------
#
#   --event-type supervisor_result   (default when flag absent — v13.0.1 path)
#     SubagentStop hook payload arrives on stdin; extracts SUPERVISOR_RESULT
#     fields (status, pr_url, summary) and POSTs:
#       {agent, status, pr_url, summary, timestamp}
#
#   --event-type gate                (NEW in v14.0.0 — autonomous-loop gates)
#     Stdin is NOT read. Fields are taken from CLI flags:
#       --gate-type <phase6_save|rubric|no_rubric|adjudication>   (required)
#       --iteration <N>                                            (optional)
#       --session-id <id>                                          (optional)
#       --context <freeform string>                                (optional)
#     Posts:
#       {event_type:"gate", gate_type, iteration, session_id, context, timestamp}
#     All payload fields are constructed via `jq --arg` — no shell-templated
#     JSON. The injection-safety contract: --context may contain single quotes,
#     double quotes, backslashes, embedded newlines, and unicode; the receiver
#     sees the exact round-tripped string with no parse error.
#
# ----------------------------------------------------------------------------
# DRY-RUN MODE
# ----------------------------------------------------------------------------
#
#   AI_AGENT_MANAGER_WEBHOOK_DRY_RUN=1
#     When set to a non-empty value, the constructed JSON payload is printed
#     to stdout INSTEAD of POSTing. The env-var gate on
#     AI_AGENT_MANAGER_WEBHOOK_URL still applies (must be set, but any
#     non-empty value works — e.g. AI_AGENT_MANAGER_WEBHOOK_URL=test).
#     Used for injection-safety self-tests:
#       AI_AGENT_MANAGER_WEBHOOK_URL=test \
#         AI_AGENT_MANAGER_WEBHOOK_DRY_RUN=1 \
#         bash send-webhook.sh --event-type gate \
#           --gate-type rubric --iteration 2 --session-id s \
#           --context "fix user's \"auth\" bug" \
#       | jq -e .
#
# ----------------------------------------------------------------------------
# Behaviour (supervisor_result path — unchanged from v13.0.1):
#   1. If AI_AGENT_MANAGER_WEBHOOK_URL is unset/empty → exit 0 (silent no-op).
#   2. Read SubagentStop JSON payload from stdin.
#   3. Use `jq -r // empty` to defensively extract SUPERVISOR_RESULT fields
#      (status, pr_url, summary). On parse failure → log to stderr, exit 0.
#   4. If `curl` not on PATH → log to stderr, exit 0.
#   5. POST a small JSON body {agent, status, pr_url, summary, timestamp} to
#      the webhook URL with a hard 5s timeout.
#   6. ALWAYS exit 0 regardless of curl outcome (fire-and-forget).
#
# Behaviour (gate path — new in v14.0.0):
#   1. If AI_AGENT_MANAGER_WEBHOOK_URL is unset/empty → exit 0 (silent no-op).
#   2. Parse remaining CLI flags. Missing --gate-type is treated as a no-op
#      (log to stderr, exit 0).
#   3. If jq not on PATH → log to stderr, exit 0 (jq is required for safe
#      payload construction; no shell-template fallback for the gate path).
#   4. Build the JSON payload via `jq --arg` exclusively.
#   5. POST (or dry-run print) and exit 0.
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

DRY_RUN="${AI_AGENT_MANAGER_WEBHOOK_DRY_RUN:-}"

# ---- Parse CLI flags --------------------------------------------------------
# Supported flags:
#   --event-type <supervisor_result|gate>
#   --gate-type  <phase6_save|rubric|no_rubric|adjudication>   (gate only)
#   --iteration  <N>                                            (gate only)
#   --session-id <id>                                           (gate only)
#   --context    <freeform string>                              (gate only)
#
# Unknown flags are ignored (forward-compat). All values come from "$@",
# never from stdin (stdin is only used for the supervisor_result event).
EVENT_TYPE="supervisor_result"
GATE_TYPE=""
ITERATION=""
SESSION_ID=""
CONTEXT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --event-type)
      EVENT_TYPE="${2:-supervisor_result}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --event-type=*)
      EVENT_TYPE="${1#--event-type=}"
      shift
      ;;
    --gate-type)
      GATE_TYPE="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --gate-type=*)
      GATE_TYPE="${1#--gate-type=}"
      shift
      ;;
    --iteration)
      ITERATION="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --iteration=*)
      ITERATION="${1#--iteration=}"
      shift
      ;;
    --session-id)
      SESSION_ID="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --session-id=*)
      SESSION_ID="${1#--session-id=}"
      shift
      ;;
    --context)
      CONTEXT="${2:-}"
      shift; [ $# -gt 0 ] && shift
      ;;
    --context=*)
      CONTEXT="${1#--context=}"
      shift
      ;;
    *)
      # Ignore unknown flags (forward compat).
      shift
      ;;
  esac
done

# ---- Tool availability ------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  printf 'send-webhook: curl not on PATH — skipping\n' >&2
  exit 0
fi

JQ_BIN=""
if command -v jq >/dev/null 2>&1; then
  JQ_BIN="jq"
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# ============================================================================
# GATE EVENT PATH (v14.0.0)
# ============================================================================
if [ "$EVENT_TYPE" = "gate" ]; then
  # Gate path REQUIRES jq — no shell-template fallback. The injection-safety
  # contract is non-negotiable for this event type.
  if [ -z "$JQ_BIN" ]; then
    printf 'send-webhook: jq not on PATH — gate event requires jq, skipping\n' >&2
    exit 0
  fi

  if [ -z "$GATE_TYPE" ]; then
    printf 'send-webhook: --gate-type is required for --event-type gate — skipping\n' >&2
    exit 0
  fi

  # Build payload via jq --arg exclusively. Every interpolation is an --arg
  # binding; the jq filter body contains zero shell variables. This is the
  # injection-safety guarantee: $CONTEXT may contain any byte sequence
  # (quotes, backslashes, newlines, unicode) and jq will produce a valid JSON
  # string literal.
  #
  # `iteration` is emitted as a string field for schema simplicity (the
  # receiver can `parseInt` if needed). Using --arg (not --argjson) ensures
  # we never crash on non-numeric input — an empty or malformed --iteration
  # value produces an empty string, not a jq compile error.
  PAYLOAD="$("$JQ_BIN" -nc \
    --arg event_type "gate" \
    --arg gate_type  "$GATE_TYPE" \
    --arg iteration  "$ITERATION" \
    --arg session_id "$SESSION_ID" \
    --arg context    "$CONTEXT" \
    --arg timestamp  "$TIMESTAMP" \
    '{event_type: $event_type, gate_type: $gate_type, iteration: $iteration, session_id: $session_id, context: $context, timestamp: $timestamp}' \
    2>/dev/null || true)"

  if [ -z "$PAYLOAD" ]; then
    printf 'send-webhook: gate payload construction failed — skipping\n' >&2
    exit 0
  fi

  if [ -n "$DRY_RUN" ]; then
    # Dry-run: print payload to stdout, do not POST.
    printf '%s\n' "$PAYLOAD"
    exit 0
  fi

  # Fire-and-forget POST. --data-binary @- preserves the payload byte-for-byte
  # (no curl-level interpretation of @ or other metachars).
  printf '%s' "$PAYLOAD" | curl -fs --max-time 5 \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "$WEBHOOK_URL" >/dev/null 2>&1 || true

  exit 0
fi

# ============================================================================
# SUPERVISOR_RESULT EVENT PATH (default — v13.0.1 behavior, unchanged)
# ============================================================================

# ---- Read stdin -------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  printf 'send-webhook: empty stdin payload\n' >&2
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

if [ -n "$DRY_RUN" ]; then
  # Dry-run: print payload to stdout, do not POST.
  printf '%s\n' "$PAYLOAD"
  exit 0
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
