#!/usr/bin/env bash
# emit-token-ledger.sh — fail-SAFE SubagentStop token/proxy ledger emitter
#
# INVARIANT: ALWAYS exits 0. Never blocks the agent run.
#
# Reads SubagentStop JSON from stdin and appends ONE additive JSONL line to
# `.supervisor/logs/{session_id}.jsonl` with `"event":"token_ledger"`.
#
# Session-id resolution (join key for /insights + job 04):
#   1. Prefer the plugin session id from `.supervisor/state.md` when that
#      file's `- status:` is `running` or `checkpoint` (same id Supervisor
#      writes `session_end` under).
#   2. Else fall back to the Claude Code SubagentStop `session_id` (UUID).
#   Always record the CC uuid as additive `cc_session_id` when present, so
#   uuid-named files do not become the sole join key.
#
# Usage fields on SubagentStop are EXPECTED ABSENT (see docs/TELEMETRY.md
# §Token ledger). When absent, records a transcript-byte PROXY — never an
# invented token count, and never labelled as tokens.
#
# No-op (exit 0) when: empty stdin, missing/empty session_id (both sources),
# unreadable proxy paths, missing python3, or any parse/write failure.
#
# RESERVED (do not emit): graph_context_used — reserved for future job 04.
#
# Authoritative spec: loomwright/docs/TELEMETRY.md §Token ledger

set -u
# Intentionally NO `set -e` — every failure mode must absorb to exit 0.

# ---- Always-exit-0 trap ------------------------------------------------------
trap 'exit 0' EXIT

# ---- Read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  # One-time (per logs dir) stderr note — otherwise silent forever with no signal.
  _flag="${PWD}/.supervisor/logs/token-ledger-python3-missing.flag"
  if [ ! -f "$_flag" ]; then
    mkdir -p "${PWD}/.supervisor/logs" 2>/dev/null || true
    echo "emit-token-ledger: python3 not found — token_ledger will not be written (one-time note)" >&2
    : > "$_flag" 2>/dev/null || true
  fi
  exit 0
fi

# Prefer a real UTC ISO timestamp; omit ts entirely when date fails (do NOT
# emit the literal string "unknown" — that violates the omit-when-absent contract).
UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
case "$UTC_TS" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
  *) UTC_TS="" ;;
esac
LOG_DIR="${PWD}/.supervisor/logs"
export UTC_TS

# ---- Resolve plugin session id from state.md (active run only) --------------
# Match build-handoff.sh / Supervisor Session block: `- session_id: …`
PLUGIN_SESSION_ID=""
PLUGIN_STATUS=""
STATE_MD="${PWD}/.supervisor/state.md"
if [ -f "$STATE_MD" ]; then
  PLUGIN_SESSION_ID="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  PLUGIN_STATUS="$(sed -nE 's/^- status:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  # Sanitize to the same charset as the emitter (alnum / - / _).
  PLUGIN_SESSION_ID="$(printf '%s' "$PLUGIN_SESSION_ID" | tr -cd 'A-Za-z0-9_-' || true)"
  case "$PLUGIN_STATUS" in
    running|checkpoint) ;;
    *) PLUGIN_SESSION_ID="" ;;   # stale completed/failed → do not join to finished run
  esac
fi
export PLUGIN_SESSION_ID

# ---- Build one JSONL line (or empty → no-op) ---------------------------------
# Single python3 invocation emits TWO lines: the resolved session id, then the
# JSONL event — avoids a second interpreter spawn just to re-parse session_id.
OUT="$(printf '%s' "$INPUT" | python3 -c '
import json, os, sys

USAGE_TOP_KEYS = (
    "usage",
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
)

def usage_present(payload):
    """True when any known usage signal is present and non-null."""
    if not isinstance(payload, dict):
        return False
    for key in USAGE_TOP_KEYS:
        if key not in payload:
            continue
        val = payload[key]
        if val is None:
            continue
        if key == "usage":
            if isinstance(val, dict) and len(val) > 0:
                return True
            if not isinstance(val, dict) and val not in ("", 0, False):
                return True
        else:
            return True
    # Nested usage object one level deep (forward-compat).
    for val in payload.values():
        if isinstance(val, dict) and isinstance(val.get("usage"), dict) and val["usage"]:
            return True
    return False

def sanitise_session_id(raw):
    if not isinstance(raw, str):
        return ""
    return "".join(c for c in raw if c.isalnum() or c in ("-", "_"))

def transcript_bytes(payload):
    """Prefer agent_transcript_path, then transcript_path. None if unreadable.
    Size via os.path.getsize only (no wc/stat fallback)."""
    for key in ("agent_transcript_path", "transcript_path"):
        path = payload.get(key)
        if not isinstance(path, str) or not path:
            continue
        try:
            if os.path.isfile(path):
                return os.path.getsize(path)
        except OSError:
            continue
    return None

try:
    payload = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

if not isinstance(payload, dict):
    sys.exit(0)

cc_session_id = sanitise_session_id(payload.get("session_id", ""))
plugin_session_id = sanitise_session_id(os.environ.get("PLUGIN_SESSION_ID", ""))

# Log under the plugin session id when an active Supervisor run is present so
# token_ledger lines join the same JSONL as session_end (job 04 /insights).
log_session_id = plugin_session_id or cc_session_id
if not log_session_id:
    sys.exit(0)

event = {
    "event": "token_ledger",
    "session_id": log_session_id,
}
# Always retain the Claude Code uuid when present (additive join / debug key).
if cc_session_id:
    event["cc_session_id"] = cc_session_id

for opt in ("agent_type", "agent_id"):
    val = payload.get(opt)
    if isinstance(val, str) and val:
        event[opt] = val

utc = os.environ.get("UTC_TS", "")
if isinstance(utc, str) and utc:
    event["ts"] = utc

if usage_present(payload):
    event["proxy"] = False
    # Record real usage fields only — copy what is present, invent nothing.
    for key in USAGE_TOP_KEYS:
        if key in payload and payload[key] is not None:
            event[key] = payload[key]
    if "usage" not in event:
        for val in payload.values():
            if isinstance(val, dict) and isinstance(val.get("usage"), dict) and val["usage"]:
                event["usage"] = val["usage"]
                break
else:
    nbytes = transcript_bytes(payload)
    if nbytes is None:
        # Unreadable / missing proxy paths → silent no-op.
        sys.exit(0)
    event["proxy"] = True
    event["token_proxy_kind"] = "transcript_bytes"
    event["token_proxy_transcript_bytes"] = int(nbytes)

# RESERVED (do not emit): graph_context_used — reserved for future job 04.

try:
    line = json.dumps(event, separators=(",", ":"), ensure_ascii=False)
except Exception:
    sys.exit(0)
# Line 1: session id (shell log-file key). Line 2: the JSONL event.
sys.stdout.write(log_session_id + "\n")
sys.stdout.write(line + "\n")
' 2>/dev/null || true)"

if [ -z "$OUT" ]; then
  exit 0
fi

SESSION_ID="${OUT%%
*}"
LINE="${OUT#*
}"

# Guard: need both lines, and the event line must be a JSON object.
if [ -z "$SESSION_ID" ] || [ "$LINE" = "$OUT" ]; then
  exit 0
fi
case "$LINE" in
  "{"*) ;;
  *) exit 0 ;;
esac

mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/${SESSION_ID}.jsonl"

# Append exactly one JSONL line. `$(...)` strips a trailing newline from LINE,
# so re-add it here — swallow all write errors.
printf '%s\n' "$LINE" >> "$LOG_FILE" 2>/dev/null || true

exit 0
