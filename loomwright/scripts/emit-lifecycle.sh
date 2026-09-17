#!/usr/bin/env bash
# emit-lifecycle.sh — fail-SAFE agent-lifecycle JSONL emitter
# (`agent_lifecycle` waiting / heartbeat("working") / failed states).
#
# INVARIANT: ALWAYS exits 0. Never blocks the agent run. Modelled LINE-FOR-LINE
# IN DISCIPLINE on emit-progress-event.sh and emit-agent-identity.sh (read
# those headers first — this file inherits their conventions exactly): `set -u`
# with NO `set -e`, `trap 'exit 0' EXIT`, a stdin read that no-ops on empty,
# the same two-source session-id resolution + run-ownership gate, the same
# worktree-safe anchoring (`git worktree list --porcelain` first entry, refuse
# if not toplevel — never bare `$PWD`), and additive-if-present fields only
# (never invent a field the payload doesn't carry).
#
# WHY THIS EXISTS
# ----------------
# The plugin records what an agent PRODUCED (`agent_identity` on spawn,
# `subtask_complete`/`token_ledger` on stop) but never what state it is IN.
# Three real incidents share this root cause (see the source requirement,
# `.supervisor/requirements/orca-derived/01-agent-lifecycle-ledger.md`): a
# worker that dies before `WORKER_RESULT`, an until-mergeable drain marker
# that means dispatched-not-completed, and a spawned agent that hits its turn
# limit before ever emitting a result. This emitter adds the missing rows so a
# reader can answer "is it waiting on a human, has it gone quiet, or did it
# end without a result" from the session JSONL alone — `stalled` and
# `ended_without_result` are DERIVED by a future reader (build-floor.sh /
# build-state.sh), never written here (see docs/RESULT_SCHEMAS.md
# `## agent_lifecycle`).
#
# SUBCOMMANDS (dispatch on argv[1] — anything else is a silent no-op)
# --------------------------------------------------------------------
#   waiting [reason]   — PreToolUse[AskUserQuestion] passes the literal
#                        "ask_user" as $2; the Notification matcher passes no
#                        $2 and this script reads the notification subtype
#                        from the payload defensively (tries a couple of
#                        candidate field names, falls back to "unknown" —
#                        never crashes, never invents a value it didn't read).
#   heartbeat          — PostToolUse[Bash|Write|Edit|Task]. Debounced PER
#                        DERIVED AGENT ID (never per matcher block) via a
#                        single shared marker file under `.supervisor/logs/`,
#                        so an agent whose tool calls hit any mix of the three
#                        registered matchers still yields at most one
#                        `working` line per debounce window. Window is
#                        `LOOMWRIGHT_LIFECYCLE_HEARTBEAT_DEBOUNCE` seconds
#                        (default 60; same override-env-var convention as
#                        `LOOMWRIGHT_STALE_RUN_SECONDS` in build-state.sh) —
#                        non-integer overrides fall back to the default
#                        rather than tripping `set -u` arithmetic.
#   failed             — StopFailure. `reason` is the payload's own top-level
#                        `error` string, copied VERBATIM (never parsed/derived
#                        from message text) — `unknown` when that key is
#                        absent. `agent_scope` is `subagent` when the payload
#                        carries `agent_id` (empirically confirmed present on
#                        17 of 37 real captures in this repo's own
#                        `.supervisor/logs/failures.log` — see the source
#                        requirement's `## §0 Probe Results`), else `main`.
#                        This is the ONE subcommand that falls back to an
#                        explicit `agent_scope: main` — `waiting` and
#                        `heartbeat` OMIT `agent_scope` instead when
#                        `agent_id` is absent, because there is no comparable
#                        grounded evidence for a main-thread fallback on
#                        those two seams (never guess).
#
# This is an ADDITIONAL emitter wired as a SECOND (or later) `command` hook
# alongside the existing ones on each matcher — `notify-desktop.sh`,
# `send-webhook.sh`, and the raw `failures.log` append all keep receiving
# byte-identical stdin via the `payload=$(cat); printf '%s' "$payload" | ...`
# re-fan pattern already used elsewhere in hooks.json. See CLAUDE.md
# §"Failure-Mode Invariants" and docs/HOOKS.md for the wiring.
#
# No-op (exit 0, writes nothing) when: empty stdin, malformed JSON, unknown/
# missing subcommand, missing python3/jq, main worktree unresolvable, a
# mismatched worktree cross-check, unwritable log dir, unresolvable session
# id, or the resolved main worktree lacking a pre-existing `.supervisor/`
# (the `plugin_present()` gate — see worktree-audit.sh for the shared
# convention: never CREATE `.supervisor/`, only write into it once it already
# exists) — the identical failure-mode contract as emit-progress-event.sh,
# plus this last one which is unique to emit-lifecycle.sh's generic-matcher
# wiring.

set -u
# Intentionally NO `set -e` — every failure mode must absorb to exit 0.

trap 'exit 0' EXIT

# ---- Subcommand dispatch ------------------------------------------------------
LIFECYCLE_SUBCOMMAND="${1:-}"
case "$LIFECYCLE_SUBCOMMAND" in
  waiting|heartbeat|failed) ;;
  *) exit 0 ;;
esac
LIFECYCLE_EXTRA_ARG="${2:-}"

# ---- Read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# ---- Worktree-safe anchoring (identical to emit-progress-event.sh) -----------
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] && [ -d "$main_root" ] || exit 0        # fail SAFE, never guess
top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
[ "$top" = "$main_root" ] || exit 0
session_branch="$(git -C "$main_root" branch --show-current 2>/dev/null || true)"
LOG_DIR="$main_root/.supervisor/logs"
STATE_MD="$main_root/.supervisor/state.md"

# plugin_present <root> — the population gate: the plugin has run in this repo
# iff `<root>/.supervisor/` already exists. Byte-parallel with
# worktree-audit.sh's identically-named gate (same file family, same
# convention) — checked BEFORE any `mkdir -p "$LOG_DIR"` call site (the
# heartbeat debounce marker below, and the shared write path at the bottom)
# and before the debounce marker file is touched, so a repo where
# Loomwright/Supervisor has never run is left completely untouched by all
# three subcommands (waiting/heartbeat/failed) on all six hook wirings.
plugin_present() { [ -d "$1/.supervisor" ]; }
plugin_present "$main_root" || exit 0

# Prefer a real UTC ISO timestamp; omit ts entirely when date fails.
UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
case "$UTC_TS" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
  *) UTC_TS="" ;;
esac

# ---- heartbeat debounce (per DERIVED agent id, never per matcher block) ------
# Checked BEFORE session-id resolution: a debounced call should cost nothing
# beyond the jq probe below, and the bound must hold even when the run cannot
# be resolved at all.
if [ "$LIFECYCLE_SUBCOMMAND" = "heartbeat" ]; then
  # This ONE code path serves three different PostToolUse matchers
  # (Bash|Write|Edit fire inside a subagent's OWN tool call and carry the
  # correct id at top-level `.agent_id`; Task fires on the SPAWN action
  # completing and carries the newly-spawned child's id only at nested
  # `.tool_response.agentId` — see emit-agent-identity.sh, registered on the
  # same Task matcher, for the identical precedent). Try the Task shape
  # first, then fall back to the top-level field, so all three matchers
  # derive the correct debounce key through one shared jq call.
  #
  # AGENT_ID_RAW is ALSO the value exported below for the python event
  # builder to source `agent_id` from on this subcommand (see the export
  # line and the python block's `PAYLOAD ONLY` comment) — it is read once
  # here and never re-derived, so the debounce key and the emitted row's
  # agent_id cannot drift apart. It is exported RAW (pre-sanitisation,
  # pre-"main"-default) so the emitted value matches emit-agent-identity.sh's
  # own un-sanitised `AGENT_ID` byte-for-byte; the tr -cd sanitisation below
  # and the "main" default are debounce-FILENAME concerns only and must not
  # leak into the emitted row (never invent an agent_id — see header note).
  AGENT_ID_RAW="$(printf '%s' "$INPUT" | jq -r 'if (.tool_response.agentId | type) == "string" then .tool_response.agentId elif (.agent_id | type) == "string" then .agent_id else empty end' 2>/dev/null || true)"
  AGENT_ID_KEY="$(printf '%s' "$AGENT_ID_RAW" | tr -cd 'A-Za-z0-9_-' || true)"
  [ -n "$AGENT_ID_KEY" ] || AGENT_ID_KEY="main"

  HEARTBEAT_DEBOUNCE="${LOOMWRIGHT_LIFECYCLE_HEARTBEAT_DEBOUNCE:-60}"
  case "$HEARTBEAT_DEBOUNCE" in
    ''|*[!0-9]*) HEARTBEAT_DEBOUNCE=60 ;;   # non-integer override -> default, never `set -u` arithmetic on it
  esac

  mkdir -p "$LOG_DIR" 2>/dev/null || true
  DEBOUNCE_FILE="$LOG_DIR/.lifecycle-heartbeat-debounce-$AGENT_ID_KEY"
  NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
  if [ "$NOW_EPOCH" != "0" ] && [ -f "$DEBOUNCE_FILE" ]; then
    LAST_EPOCH="$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)"
    case "$LAST_EPOCH" in *[!0-9]*|"") LAST_EPOCH=0 ;; esac
    if [ "$LAST_EPOCH" -gt 0 ] && [ "$((NOW_EPOCH - LAST_EPOCH))" -lt "$HEARTBEAT_DEBOUNCE" ]; then
      exit 0
    fi
  fi
  # Update the marker BEFORE the event is built so a downstream failure
  # (unresolvable session id, unwritable log dir, ...) still counts against
  # the debounce window rather than retrying every call.
  [ "$NOW_EPOCH" != "0" ] && printf '%s' "$NOW_EPOCH" > "$DEBOUNCE_FILE" 2>/dev/null || true
fi

# ---- Resolve plugin session id from state.md (active run only) --------------
PLUGIN_SESSION_ID=""
PLUGIN_STATUS=""
if [ -f "$STATE_MD" ]; then
  PLUGIN_SESSION_ID="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  PLUGIN_STATUS="$(sed -nE 's/^- status:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  PLUGIN_SESSION_ID="$(printf '%s' "$PLUGIN_SESSION_ID" | tr -cd 'A-Za-z0-9_-' || true)"
  case "$PLUGIN_STATUS" in
    running|checkpoint) ;;   # checkpoint: backward-compat only, see emit-progress-event.sh header note
    *) PLUGIN_SESSION_ID="" ;;   # stale/absent status -> do not join to a non-active run
  esac
fi

# ---- Run ownership gate -------------------------------------------------------
# Byte-parallel with emit-progress-event.sh's/emit-token-ledger.sh's gate of the
# same name — see that file's comment for the full rationale. UNKNOWN OWNER
# MEANS ADOPT (non-negotiable): an absent, empty, or unreadable log, an
# unparseable first line, or a first line with no `cc_session_id` all yield an
# empty owner, which ADOPTS the plugin session id exactly as before.
loom_log_owner() {
  local _log="${1:-}" _first=""
  [ -n "$_log" ] && [ -f "$_log" ] && [ -r "$_log" ] || return 0
  _first="$(head -1 "$_log" 2>/dev/null || true)"
  [ -n "$_first" ] || return 0
  printf '{}' | jq -e . >/dev/null 2>&1 || return 0
  printf '%s' "$_first" | jq -r '.cc_session_id // empty' 2>/dev/null || true
  return 0
}

if [ -n "$PLUGIN_SESSION_ID" ]; then
  _log_owner="$(loom_log_owner "${LOG_DIR}/${PLUGIN_SESSION_ID}.jsonl" || true)"
  _log_owner="$(printf '%s' "$_log_owner" | tr -cd 'A-Za-z0-9_-' || true)"
  if [ -n "$_log_owner" ]; then
    _payload_session_id=""
    if printf '{}' | jq -e . >/dev/null 2>&1; then
      _payload_session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
      _payload_session_id="$(printf '%s' "$_payload_session_id" | tr -cd 'A-Za-z0-9_-' || true)"
    fi
    if [ "$_log_owner" != "$_payload_session_id" ]; then
      PLUGIN_SESSION_ID=""
    fi
  fi
fi

export UTC_TS PLUGIN_SESSION_ID SESSION_BRANCH="$session_branch" LIFECYCLE_SUBCOMMAND LIFECYCLE_EXTRA_ARG AGENT_ID_RAW="${AGENT_ID_RAW:-}"

# ---- Build one JSONL line (or empty -> no-op) --------------------------------
OUT="$(printf '%s' "$INPUT" | python3 -c '
import json, os, sys

def sanitise_session_id(raw):
    if not isinstance(raw, str):
        return ""
    return "".join(c for c in raw if c.isalnum() or c in ("-", "_"))

try:
    payload = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

if not isinstance(payload, dict):
    sys.exit(0)

cc_session_id = sanitise_session_id(payload.get("session_id", ""))
plugin_session_id = sanitise_session_id(os.environ.get("PLUGIN_SESSION_ID", ""))
log_session_id = plugin_session_id or cc_session_id
if not log_session_id:
    sys.exit(0)

subcommand = os.environ.get("LIFECYCLE_SUBCOMMAND", "")
extra_arg = os.environ.get("LIFECYCLE_EXTRA_ARG", "")

STATE_BY_SUBCOMMAND = {"waiting": "waiting", "heartbeat": "working", "failed": "failed"}
state = STATE_BY_SUBCOMMAND.get(subcommand)
if not state:
    sys.exit(0)

event = {
    "event": "agent_lifecycle",
    "state": state,
    "session_id": log_session_id,
}
if cc_session_id:
    event["cc_session_id"] = cc_session_id

# `agent_id`/`agent_type`: PAYLOAD ONLY, else OMITTED ENTIRELY — never
# invented, byte-parallel with emit-progress-event.sh / emit-agent-identity.sh.
#
# EXCEPTION: `heartbeat` sources agent_id from the bash-derived AGENT_ID_RAW
# env var instead of payload.get("agent_id") directly. That subcommand fires
# on THREE PostToolUse matchers (Bash|Write|Edit|Task) and the Task shape
# carries the id only at nested `.tool_response.agentId` — bash already
# resolved the Task-vs-top-level fallback once (the same jq call that keys
# the heartbeat debounce marker; see that comment) and this reuses it
# verbatim rather than re-deriving it here, which would risk the debounce
# key and the emitted row disagreeing on which agent this is. `waiting`/
# `failed` never fire on the Task matcher, so they keep reading the
# top-level payload field directly.
if subcommand == "heartbeat":
    agent_id = os.environ.get("AGENT_ID_RAW", "")
else:
    agent_id = payload.get("agent_id")
has_agent_id = isinstance(agent_id, str) and bool(agent_id)
if has_agent_id:
    event["agent_id"] = agent_id
    event["agent_scope"] = "subagent"

agent_type = payload.get("agent_type")
if isinstance(agent_type, str) and agent_type:
    event["agent_type"] = agent_type

if subcommand == "waiting":
    reason = None
    if extra_arg:
        # PreToolUse[AskUserQuestion] hardcodes the literal "ask_user" as $2.
        reason = extra_arg
    else:
        # Notification seam: read the subtype defensively (UNVERIFIED whether
        # agent_id is ever present here for a subagent — see the source
        # requirement'\''s Probe Results). Try candidate field names in order;
        # never crash, never invent a value not actually read.
        for key in ("notification_type", "type"):
            value = payload.get(key)
            if isinstance(value, str) and value:
                reason = value
                break
        if not reason:
            reason = "unknown"
    event["reason"] = reason
elif subcommand == "failed":
    error_value = payload.get("error")
    event["reason"] = error_value if (isinstance(error_value, str) and error_value) else "unknown"
    # The ONE subcommand with a grounded main-thread fallback (17/37 real
    # captures carry agent_id; the rest are main-thread) — see header note.
    if not has_agent_id:
        event["agent_scope"] = "main"
# heartbeat carries no additional fields beyond state/session/agent identity.

branch = os.environ.get("SESSION_BRANCH", "")
if branch:
    event["branch"] = branch

utc = os.environ.get("UTC_TS", "")
if isinstance(utc, str) and utc:
    event["ts"] = utc

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

if [ -z "$SESSION_ID" ] || [ "$LINE" = "$OUT" ]; then
  exit 0
fi
case "$LINE" in
  "{"*) ;;
  *) exit 0 ;;
esac

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
LOG_FILE="$LOG_DIR/${SESSION_ID}.jsonl"

printf '%s\n' "$LINE" >> "$LOG_FILE" 2>/dev/null || exit 0

exit 0
