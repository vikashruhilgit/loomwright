#!/usr/bin/env bash
# send-webhook.sh — WEBHOOK NOTIFICATION WRAPPER (v14.1.0; result-extraction fix v14.2.1)
#
# INVARIANT: ALWAYS exits 0. The SubagentStop hook must never see a non-zero
# exit from this script. All failure modes (missing env var, missing curl/jq,
# malformed payload, network failure, non-2xx response) are absorbed silently.
#
# Authoritative spec: ai-agent-manager-plugin/docs/TELEMETRY.md §"Webhook Notifications"
#
# ----------------------------------------------------------------------------
# EVENT TYPES (v14.0.0 / v14.1.0)
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
#   paused                           (NEW in v14.1.0 — PreToolUse[AskUserQuestion] hook)
#     Stdin carries the hook payload; NO --event-type flag is passed. Matched on
#     hook_event_name=PreToolUse + tool_name=AskUserQuestion (requires
#     tool_input.questions). Scope-gated via AI_AGENT_MANAGER_NOTIFY_SCOPE
#     (plugin default / all). Webhook URL resolves from AI_AGENT_MANAGER_WEBHOOK_URL
#     or, if unset, the .supervisor/config.json (legacy
#     .supervisor/notify-config.json still read as a fallback) `.webhook_url` fallback.
#       ntfy.sh URLs (or AI_AGENT_MANAGER_WEBHOOK_FORMAT=ntfy) → plain-text body
#         + Title/Priority/Tags headers
#       other URLs → {event:"paused", question, timestamp}
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

# ---- Resolve webhook URL (env var, then repo-local config file) -------------
# v14.1.0 (red-team §2.1): env-var inheritance is fragile. A URL exported only in
# ~/.zshrc does NOT reach a non-interactive hook subprocess unless the shell that
# launched `claude` already had it exported — GUI/IDE launches and login shells
# that source .zprofile/.zshenv silently miss it. Fall back to a repo-local
# config file so notification config survives regardless of launch context.
# The env var wins when both are set.
WEBHOOK_URL="${AI_AGENT_MANAGER_WEBHOOK_URL:-}"
# Back-compatible config path: prefer the new .supervisor/config.json, fall back
# to the legacy .supervisor/notify-config.json (new path wins when both exist).
CONFIG_FILE=".supervisor/config.json"
[ -f "$CONFIG_FILE" ] || CONFIG_FILE=".supervisor/notify-config.json"
if [ -z "$WEBHOOK_URL" ] && [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  WEBHOOK_URL="$(jq -r '.webhook_url // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi
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

# ---- Read stdin ONCE (gate path already exited above) -----------------------
# Shared by the paused-event and supervisor_result paths below.
INPUT="$(cat 2>/dev/null || true)"

# ============================================================================
# PAUSED EVENT PATH (PreToolUse[AskUserQuestion]) — v14.1.0 (reconciled from
# release/v13.1.0). Fires automatically via the PreToolUse hook on EVERY plugin
# pause: Supervisor adjudication, /autonomous rubric gate, Plan Reviewer
# NEEDS_HUMAN, Launch Pad Phase 6, /autonomous merge-and-continue. Tells the
# operator the run is blocked on input (the OUTBOUND half of bidirectional
# autonomy; the inbound reply leg is Claude Code Remote Control).
# ============================================================================
HOOK_EVENT=""
TOOL_NAME=""
if [ -n "$JQ_BIN" ]; then
  HOOK_EVENT="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.hook_event_name // empty' 2>/dev/null || true)"
  TOOL_NAME="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.tool_name // empty' 2>/dev/null || true)"
fi

if [ "$HOOK_EVENT" = "PreToolUse" ] && [ "$TOOL_NAME" = "AskUserQuestion" ]; then
  # Defense-in-depth: require tool_input.questions to exist before treating this
  # as a plugin pause (guards against future payloads tagged AskUserQuestion).
  HAS_QUESTIONS=""
  if [ -n "$JQ_BIN" ]; then
    HAS_QUESTIONS="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.tool_input.questions // empty' 2>/dev/null || true)"
  fi
  if [ -z "$HAS_QUESTIONS" ]; then
    printf 'send-webhook: AskUserQuestion payload lacks tool_input.questions — skipping\n' >&2
    exit 0
  fi

  # Scope gate (mirrors notify-desktop.sh): default `plugin` suppresses paused
  # webhooks outside plugin context; AI_AGENT_MANAGER_NOTIFY_SCOPE=all fires on
  # every AskUserQuestion. Three independent OR'd markers.
  SCOPE="${AI_AGENT_MANAGER_NOTIFY_SCOPE:-plugin}"
  if [ "$SCOPE" = "plugin" ]; then
    TRANSCRIPT_PATH=""
    [ -n "$JQ_BIN" ] && TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.transcript_path // empty' 2>/dev/null || true)"
    PLUGIN_CONTEXT=0
    if compgen -G ".supervisor/jobs/in-progress/*.md" >/dev/null 2>&1; then PLUGIN_CONTEXT=1; fi
    if [ "$PLUGIN_CONTEXT" -eq 0 ]; then
      for sf in .supervisor/autonomous/*/state.json; do
        [ -f "$sf" ] || continue
        if [ -n "$(find "$sf" -mmin -120 2>/dev/null)" ]; then PLUGIN_CONTEXT=1; break; fi
      done
    fi
    if [ "$PLUGIN_CONTEXT" -eq 0 ] && [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
      if tail -200 "$TRANSCRIPT_PATH" 2>/dev/null | grep -qE 'ai-agent-manager-plugin:|/launch-pad|/supervisor|/autonomous|/code-reviewer|/qa-executor|/qa-strategist|/red-team-reviewer|/product-owner|/agent-help|/telemetry|/dreaming'; then
        PLUGIN_CONTEXT=1
      fi
    fi
    if [ "$PLUGIN_CONTEXT" -eq 0 ]; then exit 0; fi
  fi

  QUESTION=""
  if [ -n "$JQ_BIN" ]; then
    QUESTION="$(printf '%s' "$INPUT" | "$JQ_BIN" -r '.tool_input.questions[0].question // .tool_input.questions[0].header // empty' 2>/dev/null || true)"
  fi
  [ -z "$QUESTION" ] && QUESTION="Plugin is paused on a user question"
  if [ "${#QUESTION}" -gt 1024 ]; then QUESTION="$(printf '%s' "$QUESTION" | head -c 1021)..."; fi

  # ntfy detection (red-team NIT): match the official ntfy.sh service by URL
  # path, OR an explicit opt-in for self-hosted instances via
  # AI_AGENT_MANAGER_WEBHOOK_FORMAT=ntfy. The earlier broad `*ntfy*` glob was
  # tightened so hostnames merely containing "ntfy" (e.g. notify.example.com)
  # don't receive ntfy-shaped (and thus malformed) requests.
  NTFY=0
  case "$WEBHOOK_URL" in *ntfy.sh/*) NTFY=1 ;; esac
  [ "${AI_AGENT_MANAGER_WEBHOOK_FORMAT:-}" = "ntfy" ] && NTFY=1

  # ntfy: plain-text body + Title/Priority/Tags headers (readable phone alert).
  # Everything else (Slack/Discord/custom) gets the structured JSON payload.
  if [ "$NTFY" -eq 1 ]; then
    if [ -n "$DRY_RUN" ]; then
      printf 'NTFY paused: title=[Claude needs your input] body=[%s]\n' "$QUESTION"
      exit 0
    fi
    printf '%s' "$QUESTION" | curl -fs --max-time 5 \
      -H "Title: Claude needs your input" \
      -H "Priority: high" \
      -H "Tags: robot,question" \
      --data-binary @- "$WEBHOOK_URL" >/dev/null 2>&1 || true
  else
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
      PAYLOAD='{"event":"paused","question":"(jq not available; install jq for question text)","timestamp":"'"$TIMESTAMP"'"}'
    fi
    if [ -n "$DRY_RUN" ]; then
      printf '%s\n' "$PAYLOAD"
      exit 0
    fi
    curl -fs --max-time 5 -X POST -H "Content-Type: application/json" \
      -d "$PAYLOAD" "$WEBHOOK_URL" >/dev/null 2>&1 || true
  fi
  exit 0
fi

# ============================================================================
# SUPERVISOR_RESULT EVENT PATH (default — v13.0.1 behavior, unchanged)
# ============================================================================

# ---- stdin already read above (shared read) --------------------------------
if [ -z "$INPUT" ]; then
  printf 'send-webhook: empty stdin payload\n' >&2
  exit 0
fi

# ---- Extract SUPERVISOR_RESULT fields ---------------------------------------
# v14.2.1 correctness fix: a real Claude Code SubagentStop payload does NOT
# carry a top-level `result_block` field. Verified against a captured payload,
# the finishing subagent's final text lands in `last_assistant_message`; the
# only guaranteed fallback is the transcript JSONL (`agent_transcript_path` for
# a Task-spawned subagent — which is how supervisor-runner fires its
# SubagentStop — else the shared session `transcript_path`). Real payload keys:
#   { "session_id": "...", "agent_type": "...", "last_assistant_message": "...",
#     "agent_transcript_path": "...", "transcript_path": "...", ... }
# The SUPERVISOR_RESULT fields we want live INSIDE that text — not at top level.
# Strategy:
#   1. Resolve the result text: last_assistant_message → legacy
#      result_block/output/agent_output → last assistant message read out of
#      agent_transcript_path / transcript_path. (Mirrors
#      scripts/validate-launch-pad-result.py and send-telemetry-core.sh.)
#   2. Grep the YAML-style `key: value` lines from that text using sed.
#   3. Fall back to top-level keys (forward compat + flat-object test fixtures).
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

# extract_last_assistant <transcript_jsonl_path>  →  prints the LAST assistant
# message's concatenated text (or nothing). Used only as the v14.2.1 fallback
# when no inline result text is present on the payload. Tolerant of malformed
# lines via `fromjson?` (the transcript may interleave non-JSON or differently
# shaped entries). Pure jq — keeps this script's dependency surface at curl+jq
# (no python3, unlike send-telemetry-core.sh). Best-effort: empty on any error.
#
# The inner filter (no -r) emits each assistant message as a JSON-encoded
# string — one per line even when the text itself spans multiple lines (the
# embedded newlines stay escaped as \n) — so `tail -n 1` reliably isolates the
# LAST message before a final `jq -r` decodes it back to raw text.
extract_last_assistant() {
  local tpath="$1" encoded
  [ -n "$JQ_BIN" ] || return 0
  [ -r "$tpath" ] || return 0
  encoded="$(tail -n 800 "$tpath" 2>/dev/null | "$JQ_BIN" -R '
    fromjson?
    | (.message // .) as $m
    | select(($m.role // .role // .type) == "assistant")
    | ($m.content // .content)
    | if type == "array" then (map(select((.type // "") == "text") | .text) | join("\n"))
      elif type == "string" then .
      else empty end
  ' 2>/dev/null | tail -n 1)"
  [ -n "$encoded" ] && printf '%s' "$encoded" | "$JQ_BIN" -r '. // empty' 2>/dev/null || true
}

if [ -n "$JQ_BIN" ]; then
  # Primary: the real inline field is `last_assistant_message`. The legacy
  # `result_block` / `output` / `agent_output` names are kept in the chain so
  # any fixture or future payload that carries them still works.
  RESULT_BLOCK="$(printf '%s' "$INPUT" | "$JQ_BIN" -r \
    '.last_assistant_message // .result_block // .output // .agent_output // empty' \
    2>/dev/null || true)"

  # Fallback: read the last assistant message from the transcript JSONL. Prefer
  # the subagent-scoped `agent_transcript_path` (the finishing subagent's own
  # messages); fall back to the shared session `transcript_path`.
  if [ -z "$RESULT_BLOCK" ]; then
    for _tp_key in agent_transcript_path transcript_path; do
      _TP="$(printf '%s' "$INPUT" | "$JQ_BIN" -r --arg k "$_tp_key" '.[$k] // empty' 2>/dev/null || true)"
      if [ -n "$_TP" ] && [ -r "$_TP" ]; then
        RESULT_BLOCK="$(extract_last_assistant "$_TP")"
        [ -n "$RESULT_BLOCK" ] && break
      fi
    done
  fi

  if [ -n "$RESULT_BLOCK" ]; then
    STATUS="$(yaml_field "$RESULT_BLOCK" status)"
    PR_URL="$(yaml_field "$RESULT_BLOCK" pr_url)"
    SUMMARY="$(yaml_field "$RESULT_BLOCK" summary)"
  fi

  # Forward-compat / fixture fallback: top-level keys if the result text was
  # empty or did not carry the field.
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
