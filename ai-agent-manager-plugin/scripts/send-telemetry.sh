#!/usr/bin/env bash
# send-telemetry.sh — TELEMETRY WRAPPER (Subtask #2a)
#
# INVARIANT: ALWAYS exits 0. The SubagentStop hook must never see a non-zero
# exit from this script. All failure modes are absorbed and logged.
#
# Authoritative spec: ai-agent-manager-plugin/docs/TELEMETRY.md
#
# Behaviour:
#   1. Read SubagentStop JSON payload from stdin.
#   2. Extract session_id (defensive python3 try/except, empty on failure).
#   3. Resolve per-session pending-flag path under $PWD/.supervisor/logs/.
#   4. Reap stale telemetry-pending-shown-*.flag files older than 24h.
#   5. Pipe stdin to send-telemetry-core.sh (sibling script), capture rc + stderr.
#   6. Redact stderr via the privacy regex deny-list (defence in depth).
#   7. Append one structured line to telemetry.log; conditionally touch flag.
#   8. Exit 0 unconditionally.
#
# Exit-code contract honoured (codes from core, not invented here):
#   0=sent  1=generic_error  2=privacy_blocked  3=no_consent
#   4=no_repo_configured     5=filter_skipped

set -u
# Intentionally NO `set -e` — wrapper must absorb every child failure.
# pipefail is also OFF for the same reason; we capture the core's rc explicitly.

# ---- Resolve paths -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/send-telemetry-core.sh"
LOG_DIR="${PWD}/.supervisor/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/telemetry.log"

# UTC timestamp helper (date is universally available; portable -u flag)
UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# ---- Read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"

if [ -z "$INPUT" ]; then
  printf '[%s] EMPTY_PAYLOAD CORE_EXIT=- SESSION=- PENDING_FLAG_NEW=false STDERR=-\n' \
    "$UTC_TS" >> "$LOG_FILE" 2>/dev/null || true
  exit 0
fi

# ---- Detect python3 (used for session_id extraction + stderr redaction) -----
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
fi

# ---- Extract session_id ------------------------------------------------------
SESSION_ID=""
if [ -n "$PYTHON_BIN" ]; then
  SESSION_ID="$(printf '%s' "$INPUT" | "$PYTHON_BIN" -c '
import json, sys
try:
    payload = json.loads(sys.stdin.read())
    sid = payload.get("session_id", "")
    if isinstance(sid, str):
        # Sanitise to filename-safe chars only
        sid = "".join(c for c in sid if c.isalnum() or c in ("-", "_"))
        sys.stdout.write(sid)
except Exception:
    sys.stdout.write("")
' 2>/dev/null || true)"
fi

# ---- Compute pending-flag path (per-session or per-hour fallback) -----------
if [ -n "$SESSION_ID" ]; then
  FLAG="$LOG_DIR/telemetry-pending-shown-${SESSION_ID}.flag"
  REPO_UNSET_FLAG="$LOG_DIR/telemetry-repo-unset-shown-${SESSION_ID}.flag"
  SESSION_LABEL="$SESSION_ID"
else
  HOUR_BUCKET="$(date +%Y%m%d%H 2>/dev/null || echo nohour)"
  FLAG="$LOG_DIR/telemetry-pending-shown-nosession-${HOUR_BUCKET}.flag"
  REPO_UNSET_FLAG="$LOG_DIR/telemetry-repo-unset-shown-nosession-${HOUR_BUCKET}.flag"
  SESSION_LABEL="nosession"
fi

# ---- Opportunistic 24h reaper -----------------------------------------------
find "$LOG_DIR" -maxdepth 1 -name 'telemetry-pending-shown-*.flag' -mtime +1 -delete 2>/dev/null || true
find "$LOG_DIR" -maxdepth 1 -name 'telemetry-repo-unset-shown-*.flag' -mtime +1 -delete 2>/dev/null || true

# ---- Capture flag pre-existence (matters only for CORE_RC==3 / ==4) ----------
FLAG_EXISTED_BEFORE="false"
[ -e "$FLAG" ] && FLAG_EXISTED_BEFORE="true"
REPO_UNSET_FLAG_EXISTED_BEFORE="false"
[ -e "$REPO_UNSET_FLAG" ] && REPO_UNSET_FLAG_EXISTED_BEFORE="true"

# ---- Invoke core (or absorb its absence) ------------------------------------
STDERR_TMP="$(mktemp 2>/dev/null || echo "/tmp/send-telemetry-stderr-$$.tmp")"
CORE_RC=""

if [ ! -x "$CORE" ]; then
  # Core not present or not executable — log and exit 0.
  printf '[%s] CORE_NOT_EXECUTABLE CORE_EXIT=- SESSION=%s PENDING_FLAG_NEW=false STDERR=core_missing_or_not_executable\n' \
    "$UTC_TS" "$SESSION_LABEL" >> "$LOG_FILE" 2>/dev/null || true
  rm -f "$STDERR_TMP" 2>/dev/null || true
  exit 0
fi

# Pipe input to core, capture exit code, capture stderr.
printf '%s' "$INPUT" | "$CORE" 2>"$STDERR_TMP"
CORE_RC=$?

# ---- Redact stderr (defence in depth) ---------------------------------------
# Privacy regex deny-list MUST stay aligned with send-telemetry-core.sh AND
# docs/TELEMETRY.md. Subtask #2b's core re-uses the exact same (regex, label)
# tuples for body redaction.
REDACTED_STDERR=""
RAW_STDERR_HEAD="$(head -c 4096 "$STDERR_TMP" 2>/dev/null || true)"

if [ -z "$RAW_STDERR_HEAD" ]; then
  REDACTED_STDERR="-"
elif [ -n "$PYTHON_BIN" ]; then
  REDACTED_STDERR="$(printf '%s' "$RAW_STDERR_HEAD" | "$PYTHON_BIN" -c '
import re, sys
text = sys.stdin.read()
# (regex, label) tuples — keep aligned with send-telemetry-core.sh and TELEMETRY.md
patterns = [
    (re.compile(r"sk-[A-Za-z0-9]{20,}"),                                          "[REDACTED:openai-key]"),
    (re.compile(r"ghp_[A-Za-z0-9]{20,}"),                                         "[REDACTED:github-token]"),
    (re.compile(r"(?i)api[_-]?key\s*[:=]\s*\S+"),                                 "[REDACTED:api-key]"),
    (re.compile(r"Bearer\s+\S+"),                                                 "[REDACTED:bearer]"),
    (re.compile(r"(?i)password\s*[:=]\s*\S+"),                                    "[REDACTED:password]"),
    (re.compile(r"/Users/[a-zA-Z._-]+/"),                                         "/Users/[REDACTED]/"),
    (re.compile(r"/home/[a-zA-Z._-]+/"),                                          "/home/[REDACTED]/"),
    (re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"),               "[REDACTED:email]"),
]
for rx, label in patterns:
    text = rx.sub(label, text)
# Collapse to a single line for log-friendly format
text = text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
text = re.sub(r" +", " ", text).strip()
if not text:
    text = "-"
sys.stdout.write(text)
' 2>/dev/null || echo 'redaction_failed')"
else
  # python3 unavailable — drop stderr entirely rather than risk leaking a secret.
  REDACTED_STDERR="redaction_unavailable"
fi

rm -f "$STDERR_TMP" 2>/dev/null || true

# ---- Compute PENDING_FLAG_NEW -----------------------------------------------
# Surfaced once-per-session ONLY when consent has never been chosen (the core
# emits `consent_uninitialised` on stderr in that state). When the user has
# explicitly opted out (`telemetry: "no"` -> stderr `denied — skipped`), the
# decision is final and we do NOT surface a pending notice — we just log the
# `denied — skipped` line in REDACTED_STDERR for audit-trail integrity.
#
# This pairing was added in heal iter 1 of v11.2.0 to close the loophole
# where the previous wrapper treated all CORE_RC=3 the same and surfaced a
# pending notice even to users who had already chosen "no".
PENDING_FLAG_NEW="false"
if [ "$CORE_RC" = "3" ] && [ "$FLAG_EXISTED_BEFORE" = "false" ]; then
  case "$REDACTED_STDERR" in
    *consent_uninitialised*) PENDING_FLAG_NEW="true" ;;
    *"denied — skipped"*)    PENDING_FLAG_NEW="false" ;;
    *)                        PENDING_FLAG_NEW="true" ;; # fail-safe: surface notice on unknown markers
  esac
fi

# Repo-unset flag uses the same once-per-session pattern but tracked separately
# so a session that has previously surfaced a "consent pending" notice can
# still surface a distinct "repo unset" notice.
REPO_UNSET_FLAG_NEW="false"
if [ "$CORE_RC" = "4" ] && [ "$REPO_UNSET_FLAG_EXISTED_BEFORE" = "false" ]; then
  REPO_UNSET_FLAG_NEW="true"
fi

# ---- Append structured log line ---------------------------------------------
# Format (authoritative — Subtask #4 asserts on this shape):
#   [<utc-ts>] CORE_EXIT=<rc> SESSION=<sid|nosession> PENDING_FLAG_NEW=<bool> STDERR=<one-line-redacted>
{
  printf '[%s] CORE_EXIT=%s SESSION=%s PENDING_FLAG_NEW=%s STDERR=%s\n' \
    "$UTC_TS" "${CORE_RC:--}" "$SESSION_LABEL" "$PENDING_FLAG_NEW" "$REDACTED_STDERR"

  # CORE_RC == 4 surfaces a distinct user-facing notice (repo unset), also
  # rate-limited per session via its own flag.
  if [ "$REPO_UNSET_FLAG_NEW" = "true" ]; then
    printf '[%s] telemetry_repo_unset SESSION=%s message=set AI_AGENT_MANAGER_TELEMETRY_REPO or run /telemetry enable to choose target\n' \
      "$UTC_TS" "$SESSION_LABEL"
  fi
} >> "$LOG_FILE" 2>/dev/null || true

# ---- Touch flags AFTER logging (so PENDING_FLAG_NEW reflects pre-state) ----
if [ "$PENDING_FLAG_NEW" = "true" ]; then
  : > "$FLAG" 2>/dev/null || true
fi
if [ "$REPO_UNSET_FLAG_NEW" = "true" ]; then
  : > "$REPO_UNSET_FLAG" 2>/dev/null || true
fi

exit 0
