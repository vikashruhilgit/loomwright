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
# §Token ledger). Real usage is then read from the agent's own transcript (see
# transcript_usage() below); only when none is readable, a transcript-byte PROXY.

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
# per-run TOTAL advisory-context size (bytes) spanning memos + rules +
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

# ---- Worktree-safe anchoring (R1 fix, v15.16.0) ------------------------------
# Resolve the MAIN worktree by name — `git worktree list --porcelain`'s first
# entry is always the main worktree, correct from inside any linked worktree
# (including a DETACHED one — this repo's own review-drain worktrees are
# detached-HEAD, see CLAUDE.md "Orphaned worktrees after crash?") and
# unaffected by --separate-git-dir/submodule layouts. NEVER bare `$PWD`,
# NEVER bare `git branch --show-current` (empirically returns EMPTY inside a
# detached worktree, verified 2026-07-28 on git 2.50.1 — see
# emit-progress-event.sh's header for the full R1 writeup this anchoring
# mirrors). UNLIKE that new emitter, this proven emitter (785 real events)
# falls back to `$PWD` when git resolution is unavailable — preserving
# BYTE-IDENTICAL pre-change behaviour ONLY when cwd is exactly the git
# TOPLEVEL of the main checkout (`$PWD` == `git rev-parse --show-toplevel`),
# NOT an arbitrary subdirectory of it — from a subdirectory the fallback
# resolves LOG_DIR relative to that subdirectory's own `$PWD`, a
# pre-existing (unchanged) property of the `$PWD` fallback, not something
# this fix introduces. This fix changes ONLY the worktree case.
#
# Resolved BEFORE the python3 check below (deliberately reordered) so the
# one-time python3-missing flag file also anchors to `$main_root` instead of
# a bare `$PWD` — the flag write is not part of this emitter's 785-event
# proven write path (that path requires python3 to even reach the JSONL
# append), so reordering here does not touch byte-identical behaviour on the
# proven path; it only fixes where the flag itself lands.
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
if [ -n "$main_root" ] && [ -d "$main_root" ]; then
  top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
  [ "$top" = "$main_root" ] || main_root=""
fi
[ -n "$main_root" ] || main_root="${PWD}"

if ! command -v python3 >/dev/null 2>&1; then
  # One-time (per logs dir) stderr note — otherwise silent forever with no signal.
  # Anchored to $main_root (see anchoring block above), not a bare $PWD, so the
  # flag lands in the same logs dir the rest of this emitter would have used.
  _flag="${main_root}/.supervisor/logs/token-ledger-python3-missing.flag"
  if [ ! -f "$_flag" ]; then
    mkdir -p "${main_root}/.supervisor/logs" 2>/dev/null || true
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

LOG_DIR="${main_root}/.supervisor/logs"
export UTC_TS LOG_DIR

# ---- Resolve plugin session id from state.md (active run only) --------------
# Match build-handoff.sh / Supervisor Session block: `- session_id: …`
PLUGIN_SESSION_ID=""
PLUGIN_STATUS=""
STATE_MD="${main_root}/.supervisor/state.md"
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

# ---- Run ownership gate ------------------------------------------------------
# A `running`/`checkpoint` status alone is NOT sufficient authority to join a
# run's log: a run that ended WITHOUT emitting `session_end` leaves that status
# on disk forever, and every later session's SubagentStop then appends to that
# one run's log (measured: 14,416 lines / 140 distinct `cc_session_id`s in a
# single file). The stale status caused the fan-in and the fan-in re-asserted
# the stale status, because build-state.sh derives `running` from the newest
# foreign `subtask_complete` in that same log.
#
# The log's FIRST line records who opened it. Only that session may join it.
#
# UNKNOWN OWNER MEANS ADOPT (non-negotiable — do NOT invert this): an absent,
# empty, or unreadable log, an unparseable first line, or a first line with no
# `cc_session_id` all yield an empty owner, which ADOPTS the plugin session id
# exactly as before. Refusing on unknown owner would regress the very first
# worker completion of every fresh run — the log does not exist yet at that
# point, so there is nothing to be the owner of.
#
# Defined AFTER the status block above (not before it) deliberately: the
# `running|checkpoint)` case line is a CI-pinned citation target in root
# CLAUDE.md and in emit-progress-event.sh's header, and inserting above it
# would silently drift both pins.
loom_log_owner() {
  # Echo the `cc_session_id` on the FIRST line of the given log, or NOTHING
  # when no owner is recorded. Always returns 0 — "no owner" and "cannot tell"
  # are the same answer here, and both mean ADOPT.
  local _log="${1:-}" _first=""
  [ -n "$_log" ] && [ -f "$_log" ] && [ -r "$_log" ] || return 0
  _first="$(head -1 "$_log" 2>/dev/null || true)"
  [ -n "$_first" ] || return 0
  # Probe jq FUNCTIONALLY, never `command -v` alone — a jq on PATH that cannot
  # execute would otherwise take the refuse branch. A broken jq yields an empty
  # owner, i.e. ADOPT, which is the fail-safe direction.
  printf '{}' | jq -e . >/dev/null 2>&1 || return 0
  printf '%s' "$_first" | jq -r '.cc_session_id // empty' 2>/dev/null || true
  return 0
}

if [ -n "$PLUGIN_SESSION_ID" ]; then
  _log_owner="$(loom_log_owner "${LOG_DIR}/${PLUGIN_SESSION_ID}.jsonl" || true)"
  _log_owner="$(printf '%s' "$_log_owner" | tr -cd 'A-Za-z0-9_-' || true)"
  if [ -n "$_log_owner" ]; then
    # An owner IS recorded — this firing may join only if it is that session.
    _payload_session_id=""
    if printf '{}' | jq -e . >/dev/null 2>&1; then
      _payload_session_id="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
      _payload_session_id="$(printf '%s' "$_payload_session_id" | tr -cd 'A-Za-z0-9_-' || true)"
    fi
    if [ "$_log_owner" != "$_payload_session_id" ]; then
      # Foreign session → fall back to the CC uuid so this line lands in
      # `<cc_uuid>.jsonl` and the owned log stops growing.
      PLUGIN_SESSION_ID=""
    fi
  fi
fi
export PLUGIN_SESSION_ID

# ---- Build one JSONL line (or empty → no-op) ---------------------------------
# Single python3 invocation emits TWO lines: the resolved session id, then the
# JSONL event — avoids a second interpreter spawn just to re-parse session_id.
OUT="$(printf '%s' "$INPUT" | python3 -c '
import atexit, json, os, sys, time

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

USAGE_INT_FIELDS = (
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
)
# A transcript larger than this is not parsed (the proxy line is written
# instead) — the read is streaming, but a hook must stay bounded.
TRANSCRIPT_MAX_BYTES = 256 * 1024 * 1024

def _usage_int(val):
    """A usage count is a non-negative int (never a bool, a float, a string or
    one of the sub-objects real transcript usage also carries) — else 0."""
    if isinstance(val, bool) or not isinstance(val, int) or val < 0:
        return 0
    return val

def _line_mark(raw, agent_id):
    """The watermark ONE log line records for agent_id, as (usage_last_message_id
    or None, usage_anon_after), or None when the line is not a positioned
    transcript-sourced token_ledger line of agent_id. A line written by a build
    without usage_anon_after that also lacks the id carries no position and is
    None, as that build skipped it; a malformed line is None. A cheap substring
    test rejects every line that cannot be one before any JSON parse."""
    if agent_id not in raw or "\"usage_source\"" not in raw:
        return None
    try:
        obj = json.loads(raw)
    except Exception:
        return None
    if not (isinstance(obj, dict) and obj.get("event") == "token_ledger"
            and obj.get("usage_source") == "transcript"
            and obj.get("agent_id") == agent_id):
        return None
    mid = obj.get("usage_last_message_id")
    mid = mid if isinstance(mid, str) and mid else None
    after = _usage_int(obj.get("usage_anon_after"))
    if mid is not None or after > 0:
        return (mid, after)
    return None

# The log is read BACKWARDS in chunks of this many bytes: the watermark is the
# LAST positioned line of the agent, which sits near EOF, so a long session log
# costs a few chunks rather than a full scan — inside the lock, where every
# millisecond is a sibling firing waiting.
MARK_CHUNK_BYTES = 64 * 1024

def _text_lines(seg, terminated):
    """The lines a text-mode read (utf-8, errors=replace, universal newlines)
    yields for one \\n-delimited byte segment, LAST first, each with the "\\n"
    that read gives it (none on an unterminated final line). Universal newlines
    also end a line at a lone \\r and fold \\r\\n into one \\n, so the segment is
    split on \\r too and a trailing \\r is the end of the last line, not an
    empty line of its own."""
    pieces = seg.decode("utf-8", "replace").split("\r")
    if len(pieces) > 1 and pieces[-1] == "":
        pieces.pop()
        terminated = True
    out = [p + "\n" for p in pieces[:-1]]
    if pieces[-1] or terminated:
        out.append(pieces[-1] + ("\n" if terminated else ""))
    return reversed(out)

def _lines_backward(fh, needles=()):
    """Every line of the binary file fh, LAST first, exactly as a forward
    text-mode read yields it — never more than one chunk plus one line in
    memory. A line straddling a chunk boundary is carried until its start is
    read; the first line of the file is yielded last. needles are byte strings
    EVERY line the caller can use contains: a span of complete lines lacking
    one is skipped without splitting or decoding it, so a log in which the
    agent never appears (its first stop) costs one substring search per chunk.
    The chunk size is read at call time, so a test can shrink it to make every
    line straddle one. A read that comes back short (the log shrank under it)
    is an OSError, the same "cannot tell" every other read failure is."""
    chunk = MARK_CHUNK_BYTES
    fh.seek(0, os.SEEK_END)
    pos = fh.tell()
    carry, carry_terminated = b"", False
    while pos > 0:
        step = min(chunk, pos)
        pos -= step
        fh.seek(pos)
        data = fh.read(step)
        if len(data) != step:
            raise OSError("log changed size under the backward read")
        buf = data + carry
        if not all(n in buf for n in needles):
            # No complete line in buf can be a match; keep only the (possibly
            # partial) first line, whose start may still be in an earlier chunk.
            nl = buf.find(b"\n")
            if nl >= 0:
                carry, carry_terminated = buf[:nl], True
            else:
                carry = buf
            continue
        parts = buf.split(b"\n")
        for i in range(len(parts) - 1, 0, -1):
            seg = parts[i]
            if not all(n in seg for n in needles):
                continue
            for line in _text_lines(seg, True if i < len(parts) - 1 else carry_terminated):
                yield line
        if len(parts) > 1:
            carry_terminated = True
        carry = parts[0]
    if all(n in carry for n in needles):
        for line in _text_lines(carry, carry_terminated):
            yield line

def last_counted_mark(log_path, agent_id):
    """The resume WATERMARK of agent_id: the position its LAST transcript-sourced
    token_ledger line in log_path counted up to (_line_mark above), or None when
    there is no such line. Reads from EOF backwards and stops at the first match,
    which is the last one in the file — the same answer a forward scan to EOF
    gives, without one."""
    if not agent_id or not log_path:
        return None
    try:
        # Byte needles that are EXACT prefilters for _line_mark: its literal
        # "usage_source" substring is ASCII, which decoding with errors=replace
        # never alters; the agent id is one too only when it is ASCII with no
        # line break (else a decoded line could hold it where the bytes do not).
        needles = [b"\"usage_source\""]
        if agent_id.isascii() and "\r" not in agent_id and "\n" not in agent_id:
            needles.append(agent_id.encode("ascii"))
        with open(log_path, "rb") as fh:
            for raw in _lines_backward(fh, needles):
                mark = _line_mark(raw, agent_id)
                if mark is not None:
                    return mark
    except OSError:
        return None
    return None

def read_transcript(path):
    """Per-message usage from the OWN transcript of a subagent (parallel-automate/24
    F8), or None when there is none to read. Its assistant lines carry
    message.usage repeated once per streamed content block, and the repeats
    are NOT identical: output_tokens is a stream-start placeholder until the
    final line, the one with a non-null message.stop_reason. Per distinct
    message.id: that final line (the last such) when one exists, else the
    per-field max over the lines of that id, never the first line. A line with
    no message.id stands alone as its own entry. Returns (order, per): the
    entries in first-seen order and their usage. Reads no shared state, so it
    runs OUTSIDE the log lock — a large transcript never holds up a sibling."""
    if not isinstance(path, str) or not path:
        return None
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > TRANSCRIPT_MAX_BYTES:
            return None
        order, per, anon = [], {}, 0
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if "\"usage\"" not in raw or "\"assistant\"" not in raw:
                    continue
                try:
                    obj = json.loads(raw)
                except Exception:
                    continue
                if not isinstance(obj, dict) or obj.get("type") != "assistant":
                    continue
                msg = obj.get("message")
                if not isinstance(msg, dict) or not isinstance(msg.get("usage"), dict):
                    continue
                vals = {k: _usage_int(msg["usage"].get(k)) for k in USAGE_INT_FIELDS}
                mid = msg.get("id")
                if not isinstance(mid, str) or not mid:
                    anon += 1               # no id to dedupe on: the line stands alone
                    mid = "\0anon-%d" % anon
                rec = per.get(mid)
                if rec is None:
                    rec = per[mid] = {"final": None, "max": dict.fromkeys(USAGE_INT_FIELDS, 0)}
                    order.append(mid)
                for k in USAGE_INT_FIELDS:
                    if vals[k] > rec["max"][k]:
                        rec["max"][k] = vals[k]
                if msg.get("stop_reason") is not None:
                    rec["final"] = vals
    except (OSError, ValueError):
        return None
    if not order:
        return None
    return order, per

def count_after(order, per, mark):
    """Sum the entries AFTER the watermark mark (last_counted_mark above) — a
    resumed agent counts only what its previous line did not. The watermark is a
    POSITION, not just an id: the last entry WITH a message.id plus the number
    of id-less entries counted after it (usage_anon_after), because the newest
    entry may have no id to record, and an id-less entry counted once must not
    be counted again on the next stop. The transcript is append-only, so those
    entries are the same ones. Returns (totals, n_counted, last_id, anon_after)
    — last_id None when no entry has an id, anon_after then counting from the
    start."""
    start = 0
    if mark is not None:
        mid, skip = mark
        if mid is not None:
            if mid in per:
                start = order.index(mid) + 1
            else:
                skip = 0                    # an id this transcript lacks: count it all
        while skip > 0 and start < len(order) and order[start].startswith("\0"):
            start += 1
            skip -= 1
    counted = order[start:]
    totals = dict.fromkeys(USAGE_INT_FIELDS, 0)
    for m in counted:
        src = per[m]["final"] if per[m]["final"] is not None else per[m]["max"]
        for k in USAGE_INT_FIELDS:
            totals[k] += src[k]
    last_pos = next((i for i in range(len(order) - 1, -1, -1)
                     if not order[i].startswith("\0")), None)
    last_id = order[last_pos] if last_pos is not None else None
    anon_after = len(order) - (last_pos + 1 if last_pos is not None else 0)
    return totals, len(counted), last_id, anon_after

# THE WATERMARK READ, THE COUNT AND THE APPEND ARE ONE CRITICAL SECTION. Claude
# Code runs the hooks matched to one completion CONCURRENTLY (the fan-out the
# shell lock below documents), so a watermark read before the lock lets every
# sibling read "nothing counted yet" and append the full total — and when their
# ts differ by a second the byte-identity guard cannot catch it. So this path
# takes the SAME per-log mkdir lock the shell takes, AFTER the transcript read
# (which touches no shared state) and BEFORE the watermark read, and HANDS IT
# OVER to the shell, which keeps it through its tail-compare and append and
# releases it there (line 2 of the output says so). Every failure direction is
# the shell one: a lock not taken within the bound proceeds unguarded, a lock
# older than a minute is broken, and every exit of this interpreter before the
# hand-over releases it (atexit).
LOCK_WAIT_TRIES = 40        # 40 x 50ms: this section also spans an interpreter exit
LOCK_WAIT_S = 0.05
LOCK_STALE_S = 60
_LOCK = {"path": None, "handed_off": False}

def take_log_lock(lock_path):
    """Returns "held" or "timeout" (never raises)."""
    try:
        os.makedirs(os.path.dirname(lock_path) or ".", exist_ok=True)
    except OSError:
        pass
    for _ in range(LOCK_WAIT_TRIES):
        try:
            os.mkdir(lock_path)
            _LOCK["path"] = lock_path
            return "held"
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(lock_path) > LOCK_STALE_S:
                    os.rmdir(lock_path)
            except OSError:
                pass
        except OSError:
            return "timeout"                # cannot be created at all: unguarded
        time.sleep(LOCK_WAIT_S)
    return "timeout"

def _release_unless_handed_off():
    if _LOCK["path"] and not _LOCK["handed_off"]:
        try:
            os.rmdir(_LOCK["path"])
        except OSError:
            pass

atexit.register(_release_unless_handed_off)
LOCK_STATE = "none"         # "none": this interpreter did not try; the shell takes the lock

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

# `agent_type`: PAYLOAD ONLY, else the key is OMITTED ENTIRELY — never an empty
# string, never null, never invented. Same additive-if-present discipline as
# orientation_source below. There is deliberately NO env fallback that would
# inject the name of a matcher — byte-parallel with emit-progress-event.sh, which
# omits one for the same reason: this emitter is registered under ONE SubagentStop
# matcher PER AGENT this plugin ships — hooks.json is the authority for how many, and this
# comment deliberately does not restate the number, because the last one sat here asserting
# THREE for the release that made it thirteen. Those matchers only discriminate when the payload ALREADY carries
# an `agent_type`, and the single `loomwright:worker` matcher of the other
# emitter does not discriminate either (grouping untyped events by `agent_id` on the live
# log gives a fixed 2 ledger : 1 subtask_complete in every bucket, so all four
# blocks see the same untyped payloads). Measured on the live log, 94/94 typed
# firings emitted 1 line and 4,376/4,376 untyped emitted 2 — i.e. more than one
# block runs for an untyped payload. Adopting an identity from whichever matcher happened to run
# would be a GUESS in exactly the population where we have no identity, and it
# would also defeat the byte-identity dedupe guard below (two lines differing
# only in a fabricated `agent_type` can never compare equal).
agent_type = payload.get("agent_type")
if isinstance(agent_type, str) and agent_type:
    event["agent_type"] = agent_type

agent_id = payload.get("agent_id")
if isinstance(agent_id, str) and agent_id:
    event["agent_id"] = agent_id

# `agent_scope`: WHICH THREAD this payload describes - derived from the transcript
# path the payload itself carries, never from the matcher and never from the mere
# absence of `agent_type`. Claude Code writes a spawned subagent transcript to
# `<session>/subagents/agent-<agent_id>.jsonl` and the transcript of the session
# itself to `<cc_session_id>.jsonl`, so each basename is a POSITIVE
# identification rather than an inference from what is missing. Measured on the
# live log: every typed line reported a proxy byte count equal to a
# `subagents/agent-<id>.jsonl` file on disk, while every untyped line of the
# newest session reported the size of the session transcript itself - a session
# for which no `subagents/` directory exists at all, so those lines were never
# spawned agents.
#
# Recorded ONLY when a basename actually matches. A path matching neither
# pattern, or no path at all, leaves the key OMITTED - the same refusal
# `agent_type` above makes, for the same reason. UNTYPED and NOT-A-SUBAGENT are
# different facts, and it is the second one that stops a reader calling the main
# thread an unidentified agent.
_apath = payload.get("agent_transcript_path")
_tpath = payload.get("transcript_path")
_scope = None
if isinstance(_apath, str) and _apath:
    if (isinstance(agent_id, str) and agent_id
            and os.path.basename(_apath) == "agent-" + agent_id + ".jsonl"):
        _scope = "subagent"
elif (isinstance(_tpath, str) and _tpath and cc_session_id
        and os.path.basename(_tpath) == cc_session_id + ".jsonl"):
    _scope = "main"
if _scope:
    event["agent_scope"] = _scope

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
    # The payload carries no usage (the expected case): read the real usage
    # from the OWN transcript of the subagent (_apath, above) only; the session
    # transcript (`transcript_path`) belongs to the main thread and is never
    # summed here. "Own" is the SAME positive identification `agent_scope` uses:
    # the basename is `agent-<agent_id>.jsonl` for the agent_id of THIS payload
    # (_scope == "subagent"). A payload with no agent_id has no watermark key
    # (repeat stops would re-sum the whole transcript), and a path naming the
    # transcript of another agent would book its tokens to this one - both take
    # the proxy line instead. Any read/parse failure falls through to it too.
    # (No apostrophes in this program: it is a single-quoted python3 -c string.)
    _log_path = os.path.join(os.environ.get("LOG_DIR", ""), log_session_id + ".jsonl")
    _parsed = None
    if _scope == "subagent":
        try:
            _parsed = read_transcript(_apath)
        except Exception:
            _parsed = None
    _tu = None
    if _parsed is not None:
        # The critical section starts HERE (see take_log_lock above): the
        # watermark is read under the lock, never before it.
        LOCK_STATE = take_log_lock(_log_path + ".lock")
        try:
            _tu = count_after(_parsed[0], _parsed[1], last_counted_mark(
                _log_path, agent_id if isinstance(agent_id, str) else ""))
        except Exception:
            _tu = None
    if _tu is not None:
        _totals, _n_ids, _last_id, _anon_after = _tu
        if _n_ids == 0:
            # Everything in the transcript is already counted by an earlier line
            # of this agent — a sibling firing of this same completion that took
            # the lock first, or a repeat stop. A second line would add nothing
            # but an event, so none is written (atexit releases the lock).
            sys.exit(0)
        event["proxy"] = False
        event["usage_source"] = "transcript"
        for key in USAGE_INT_FIELDS:
            event[key] = int(_totals[key])
        event["usage_messages"] = int(_n_ids)
        if _last_id:
            event["usage_last_message_id"] = _last_id
        if _anon_after:
            event["usage_anon_after"] = int(_anon_after)
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
# (bytes) across memos + rules + brain-context. Only a bare non-negative
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
# Line 1: session id (shell log-file key). Line 2: the lock state (held: this
# interpreter took the log lock and hands it to the shell; timeout: it waited
# out the bound; none: it did not try). Line 3: the JSONL event. The lock is
# handed over only once the output is flushed — a failed write releases it.
sys.stdout.write(log_session_id + "\n" + LOCK_STATE + "\n" + line + "\n")
sys.stdout.flush()
_LOCK["handed_off"] = True
' 2>/dev/null || true)"

if [ -z "$OUT" ]; then
  exit 0
fi

SESSION_ID="${OUT%%
*}"
_rest="${OUT#*
}"
PY_LOCK="${_rest%%
*}"
LINE="${_rest#*
}"
LOG_FILE="$LOG_DIR/${SESSION_ID}.jsonl"
_lock="${LOG_FILE}.lock"
_have_lock=""
# A lock the python step handed over is adopted BEFORE any guard below can exit,
# so no exit path strands it (the chained trap is explained at the shell lock).
if [ "$PY_LOCK" = held ] && [ -n "$SESSION_ID" ]; then
  _have_lock=1
  trap 'rmdir "$_lock" 2>/dev/null || true; exit 0' EXIT
fi

# Guard: need all three lines, and the event line must be a JSON object.
if [ -z "$SESSION_ID" ] || [ "$_rest" = "$OUT" ] || [ "$LINE" = "$_rest" ]; then
  exit 0
fi
case "$LINE" in
  "{"*) ;;
  *) exit 0 ;;
esac

mkdir -p "$LOG_DIR" 2>/dev/null || true

# ---- Per-firing idempotency guard (confirmed duplicate mechanism) ------------
# CONFIRMED, not assumed. hooks.json registers emit-token-ledger.sh under one SubagentStop
# matcher per agent this plugin ships (that file is the authority for the count; a number
# restated here is the copy that went stale last time). THE MEASUREMENTS BELOW
# WERE TAKEN WHEN THERE WERE THREE (code-reviewer, qa-executor, supervisor-runner), before
# v15.60.0, and are kept because they are what established the mechanism; the ratios they
# report do NOT describe the current topology and must not be read as though they do. What
# carries forward unchanged is the mechanism, not the arithmetic. They are
# NOT mutually exclusive in practice: they only discriminate when the payload
# actually carries an `agent_type`; when it does not, more than one matcher block
# runs for a single subagent completion. Measured on the live 14,539-line log:
#   token_ledger lines WITH agent_type    → 94 firings, 94/94 emitted exactly 1
#   token_ledger lines WITHOUT agent_type → 4,376 firings emitted exactly 2
# i.e. the duplication is perfectly correlated with the absence of `agent_type`,
# and real typed loomwright agents were never duplicated.
#
# At three blocks, exactly TWO lines were measured per untyped firing; why one block
# emitted nothing was an OPEN QUESTION, recorded rather than guessed in
# docs/TELEMETRY.md §"Adjacent-duplicate guard". THAT QUESTION IS NOW ABOUT A SYSTEM THAT
# NO LONGER EXISTS — it was keyed to a three-matcher topology and there are fourteen. It is
# left recorded rather than deleted because the investigation it holds is still the best
# account of how these blocks interact, and it is NOT re-answered here because nobody has
# re-measured at fourteen. The guard never depended on the answer: it keys on byte-identity,
# not on a duplicate count, which is why raising the fan-out needed no change to it —
# asserted at the new fan-out by test-token-ledger.sh case 23 rather than assumed.
#
# The guard is minimal and consecutive-only: skip the append when the line is
# byte-identical to the CURRENT last line of the log. Duplicate blocks fire
# back-to-back within one firing, so they are always adjacent. Byte-identity
# includes ts, agent_id, and transcript byte count together — vanishingly
# unlikely to collide, NOT impossible: ts is second-granularity, agent_id is
# omitted for exactly the untyped population this targets, and parallel worker
# completion is a designed feature. A collision therefore needs the same second,
# an identical transcript byte count, and an absent agent_id on both. The failure
# direction is one-way and benign: one ADVISORY ledger line is silently lost;
# nothing reads it for state or gating. Reading only the last line keeps this
# O(1) on a large log, and every failure absorbs to the normal append path.
# THE GUARD ABOVE WAS CHECK-THEN-ACT, AND THAT IS WHY IT DID NOT WORK. Measured in
# the field on a log written by a build that HAD it: an /automate run produced 13
# subagent completions, 26 token_ledger lines, and 13 adjacent byte-identical pairs
# — the guard caught 0 of 13. On a lightly loaded session the same build produced 9
# completions and 11 lines, catching most. That spread is the signature of a RACE,
# not of a rule that is simply wrong: Claude Code runs the hooks matched to one
# event CONCURRENTLY, so two firings both `tail -1` before either has appended,
# both see no match, and both append. Under load they always overlap; when idle
# they sometimes serialise by luck. A read-then-write guard cannot close that, so
# the read and the write are made ONE critical section instead.
#
# `mkdir` is the primitive, for the reason the ui registry lock already documents:
# `flock` is not on stock macOS, and `mkdir` is atomic on every POSIX filesystem —
# exactly one of N racing callers creates it and the rest get EEXIST.
#
# EVERY FAILURE DIRECTION IS TOWARD THE APPEND, never toward silence or a hang.
# This is an ALWAYS-EXIT-0 advisory emitter (see the header): losing a ledger line
# is a worse outcome than writing a duplicate one, and blocking a hook is worse
# than both. So a lock that cannot be taken within the bounded wait is abandoned
# and the append proceeds unguarded, and a lock older than a minute — far longer
# than a healthy holder of this section can need — is broken rather than waited on.
# PER LOG FILE, not per logs DIRECTORY. The duplication this serialises is two
# firings of ONE completion, which by construction target the same file; a
# directory-wide lock would additionally serialise unrelated sessions against each
# other for no correctness gain. The name cannot be mistaken for a log: every
# consumer globs `logs/*.jsonl` on the exact extension, and this ends `.lock`.
# The lock may already be held: the transcript-usage path takes it in the python
# step, BEFORE its watermark read, and hands it over (PY_LOCK=held, adopted above).
# PY_LOCK=timeout means that step already spent the bounded wait — the append
# proceeds unguarded rather than waiting a second time. Otherwise the shell takes it.
_tries=0
if [ -n "$_have_lock" ] || [ "$PY_LOCK" = timeout ]; then _tries=20; fi
while [ "$_tries" -lt 20 ]; do
  if mkdir "$_lock" 2>/dev/null; then
    _have_lock=1
    break
  fi
  # A holder that died leaves the directory behind. WHOLE MINUTES, not a fraction:
  # BSD find (macOS) and GNU find agree on `-mmin +1` and do not agree on `+0.16`,
  # and a portability trap inside a fail-safe emitter is how a guard stops firing on
  # one platform without anyone noticing. A critical section this short is never a
  # live holder after a minute, and a stranded lock costs at most that minute of
  # unguarded appends — today's behaviour, not worse.
  if [ -n "$(find "$_lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    rmdir "$_lock" 2>/dev/null || true
  fi
  _tries=$((_tries + 1))
  sleep 0.05 2>/dev/null || true
done
# THE CLEANUP IS CHAINED ONTO THE ALWAYS-EXIT-0 TRAP, NEVER SUBSTITUTED FOR IT.
# `trap` REPLACES the handler for a signal rather than composing with it, so a bare
# cleanup trap here silently discards the `trap 'exit 0' EXIT` installed at the top
# of this file — the mechanism that makes this script's stated invariant true.
#
# WHAT THAT COSTS, measured rather than argued, because the intuitive answer is
# wrong in both directions. A SIGTERM is NOT the failure mode: bash re-raises the
# signal after running the EXIT trap, so an interrupted run exits 143 with the
# original trap, with a cleanup-only trap, and with no trap at all — all three
# measured identical. The failure mode is the ORDINARY one this file's header names
# as the reason the trap exists at all: `set -u` is on and `set -e` is off, so an
# unbound variable anywhere below is a fatal non-zero exit. Measured on that path:
# original trap 0, cleanup-only trap 1, chained trap 0. The `|| true` inside the
# cleanup is not a substitute — it makes the trap BODY succeed, and the shell then
# exits with the fatal status regardless.
#
# In production a non-zero here is currently invisible, because every hooks.json
# registration appends `|| true`. That is the caller's accident, not this script's
# contract, and a contract that holds only because of an external wrapper is exactly
# the fail-safe inversion CLAUDE.md's Failure-Mode Invariants section forbids.
[ -n "$_have_lock" ] && trap 'rmdir "$_lock" 2>/dev/null || true; exit 0' EXIT

# Adjacent byte-identity, unchanged in meaning — only now the read and the append
# cannot be interleaved by a sibling firing. Byte-identity includes ts, agent_id
# and the transcript byte count together; the collision case and its one-way,
# benign failure direction are as described above.
if [ -f "$LOG_FILE" ]; then
  _last_line="$(tail -1 "$LOG_FILE" 2>/dev/null || true)"
  if [ -n "$_last_line" ] && [ "$_last_line" = "$LINE" ]; then
    exit 0
  fi
fi

# Append exactly one JSONL line. `$(...)` strips a trailing newline from LINE,
# so re-add it here — swallow all write errors.
printf '%s\n' "$LINE" >> "$LOG_FILE" 2>/dev/null || true

exit 0
