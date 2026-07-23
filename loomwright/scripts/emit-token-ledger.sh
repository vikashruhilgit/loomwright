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
# Additive-if-present: `orientation_source` (memos|repo_map|graphify|none) read
# from the LOOMWRIGHT_ORIENTATION_SOURCE env var — any other/unset value omits
# the field entirely (fail-safe; never invented, never validated loudly).
#
# Additive-if-present: `shared_prefix: true` marker emitted only when the
# LOOMWRIGHT_SHARED_PREFIX env var is exactly "1" — any other/unset value omits
# the field entirely (fail-safe; same namespace discipline as orientation_source).
#
# Additive-if-present: `advisory_total` (+ `advisory_total_kind: "context_bytes"`) — a
# per-run TOTAL advisory-context size (bytes) spanning memos + rules + bridge +
# brain-context, read from the LOOMWRIGHT_ADVISORY_TOTAL_BYTES env var. This is a
# DIFFERENT measure from the pre-existing era-bucket `advisory_tokens` proxy emitted by
# build-loop-evidence.sh (that field is a per-era COMPUTE-SPEND proxy — real usage
# tokens or a transcript-byte stand-in for running the loop; it says nothing about how
# much advisory context was injected). `advisory_total` is a size-of-injected-context
# measure, not a spend measure — see docs/TELEMETRY.md §Token ledger and
# build-insights.sh's "Whole-stack advisory budget" subsection for the reconciliation.
# Same namespace discipline as orientation_source: the env var must be a bare
# non-negative integer string (`^[0-9]+$`); any other/unset value — including a
# negative number, a float, or empty — omits BOTH fields entirely (fail-safe; never
# invented, never validated loudly). Mirrors orientation_source's convention exactly.
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

# Known one-level container keys a future payload shape might nest usage under.
NESTED_USAGE_CONTAINERS = ("result", "message", "response")

def _nonzero_signal(val):
    """True when a usage value carries real information. All-zero usage is
    treated as ABSENT so the transcript-byte proxy (the only size signal in
    that case) is not silently skipped — placeholder zeros are not usage."""
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return val != 0
    if isinstance(val, dict):
        return any(_nonzero_signal(v) for v in val.values())
    if isinstance(val, str):
        return val != ""
    return val is not None

def usage_present(payload):
    """True when any known usage signal is present and non-zero."""
    if not isinstance(payload, dict):
        return False
    for key in USAGE_TOP_KEYS:
        if key not in payload:
            continue
        if _nonzero_signal(payload[key]):
            return True
    # Nested usage object one level deep (forward-compat) — scoped to known
    # container keys only, so an arbitrary dict field carrying an unrelated
    # "usage" sub-object cannot flip the proxy decision.
    for key in NESTED_USAGE_CONTAINERS:
        val = payload.get(key)
        if isinstance(val, dict) and isinstance(val.get("usage"), dict) and _nonzero_signal(val["usage"]):
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
        for key in NESTED_USAGE_CONTAINERS:
            val = payload.get(key)
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

# Additive-if-present: orientation_source from the LOOMWRIGHT_ORIENTATION_SOURCE
# env var (inherited from the hook invocation environment). Only the four known
# values are emitted; anything else — including unset/empty — omits the field
# entirely (fail-safe: never a guess, never an error).
orientation_source = os.environ.get("LOOMWRIGHT_ORIENTATION_SOURCE", "")
if orientation_source in ("memos", "repo_map", "graphify", "none"):
    event["orientation_source"] = orientation_source

# Additive-if-present: shared_prefix marker from the LOOMWRIGHT_SHARED_PREFIX
# env var (inherited from the hook invocation environment — same namespace
# discipline as orientation_source above). Only the exact value "1" emits
# `"shared_prefix": true`; anything else — including unset/empty — omits the
# field entirely (fail-safe: never a guess, never an error).
if os.environ.get("LOOMWRIGHT_SHARED_PREFIX", "") == "1":
    event["shared_prefix"] = True

# Additive-if-present: advisory_total (+ advisory_total_kind) from the
# LOOMWRIGHT_ADVISORY_TOTAL_BYTES env var — a per-run TOTAL advisory-context size
# (bytes) across memos + rules + bridge + brain-context. Only a bare non-negative
# integer string is accepted (str.isdigit() rejects "", signs, floats, and any
# non-digit character); anything else — including unset — omits BOTH fields
# entirely (fail-safe: never a guess, never an error). This is DISTINCT from the
# pre-existing era-bucket `advisory_tokens` proxy (build-loop-evidence.sh) — that
# is a per-era compute-SPEND proxy, not a context-size measure; see the header
# comment above for the reconciliation.
advisory_total_raw = os.environ.get("LOOMWRIGHT_ADVISORY_TOTAL_BYTES", "")
if advisory_total_raw.isdigit():
    event["advisory_total"] = int(advisory_total_raw)
    event["advisory_total_kind"] = "context_bytes"

# RESERVED (do not emit): graph_context_used — reserved for future job 04.
# (orientation_source is emitted above since v15.12.0, shared_prefix since
# v15.13.0, and advisory_total since v15.14.0 — none of these are reserved keys.)

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
