#!/usr/bin/env bash
# emit-token-ledger.sh — fail-SAFE SubagentStop token/proxy ledger emitter
#
# INVARIANT: ALWAYS exits 0. Never blocks the agent run.
#
# Reads SubagentStop JSON from stdin and appends ONE additive JSONL line to
# `.supervisor/logs/{session_id}.jsonl` with `"event":"token_ledger"`.
#
# Usage fields on SubagentStop are EXPECTED ABSENT (see docs/TELEMETRY.md
# §Token ledger). When absent, records a transcript-byte PROXY — never an
# invented token count, and never labelled as tokens.
#
# No-op (exit 0) when: empty stdin, missing/empty session_id, unreadable
# proxy paths, missing python3, or any parse/write failure.
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
  exit 0
fi

UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
LOG_DIR="${PWD}/.supervisor/logs"
export UTC_TS

# ---- Build one JSONL line (or empty → no-op) ---------------------------------
LINE="$(printf '%s' "$INPUT" | python3 -c '
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
    """Prefer agent_transcript_path, then transcript_path. None if unreadable."""
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

session_id = sanitise_session_id(payload.get("session_id", ""))
if not session_id:
    sys.exit(0)

event = {
    "event": "token_ledger",
    "session_id": session_id,
}
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
    sys.stdout.write(json.dumps(event, separators=(",", ":"), ensure_ascii=False))
    sys.stdout.write("\n")
except Exception:
    sys.exit(0)
' 2>/dev/null || true)"

if [ -z "$LINE" ]; then
  exit 0
fi

SESSION_ID="$(printf '%s' "$LINE" | python3 -c '
import json, sys
try:
    print(json.loads(sys.stdin.read()).get("session_id", ""))
except Exception:
    print("")
' 2>/dev/null || true)"

if [ -z "$SESSION_ID" ]; then
  exit 0
fi

mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/${SESSION_ID}.jsonl"

# Append exactly one JSONL line. `$(...)` strips a trailing newline from LINE,
# so re-add it here — swallow all write errors.
printf '%s\n' "$LINE" >> "$LOG_FILE" 2>/dev/null || true

exit 0
