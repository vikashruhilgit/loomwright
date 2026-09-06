#!/usr/bin/env bash
# emit-progress-event.sh — fail-SAFE SubagentStop progress-event emitter
# (Fix 3 / D5 — "One writer for progress state, derived state.md").
#
# INVARIANT: ALWAYS exits 0. Never blocks the agent run. Modelled
# LINE-FOR-LINE IN DISCIPLINE on emit-token-ledger.sh (read that file's
# header first — this script inherits its conventions exactly): `set -u`
# with NO `set -e`, `trap 'exit 0' EXIT`, stdin read that no-ops on empty,
# the same two-source session-id resolution, additive-if-present fields.
#
# WHY THIS EXISTS
# ----------------
# Progress state was previously written by prompt-instructed Context-Keeper
# operations (set_task / set_subtasks / update_phase / checkpoint) the model
# had to remember to call while doing the real work. This repo's own logs
# measure the miss rate: 785 hook-written `token_ledger` events vs 6
# agent-written `phase_transition` events across 11+ sessions — on
# 2026-07-27 all 5 subtasks were merged while `state.md` still read
# `phase: ACQUIRE` / all PENDING. This emitter is the sole hook-triggered
# replacement writer (see CLAUDE.md §Failure-Mode Invariants and
# docs/TELEMETRY.md). Do NOT "fix" a future gap here by adding another
# prompt-instructed write — that reintroduces the exact miss rate this
# mechanism exists to remove.
#
# Reads SubagentStop JSON from stdin and appends ONE additive JSONL line to
# `.supervisor/logs/{session_id}.jsonl` with `"event":"subtask_complete"`,
# then invokes the projector (build-state.sh) so `.supervisor/state.md`
# reflects the new event immediately.
#
# PAYLOAD SHAPE (verified empirically, not assumed — AC-2)
# ----------------------------------------------------------
# The real Claude Code SubagentStop payload carries: session_id,
# transcript_path, cwd, permission_mode, agent_id, agent_type, effort,
# hook_event_name, stop_hook_active, agent_transcript_path,
# last_assistant_message, background_tasks, session_crons. There is NO
# `result_block` field — this emitter reads only fields actually present.
# See the committed fixture carrying this full field set (and explicitly no
# `result_block` key) at `loomwright/scripts/progress-event-fixtures/` in
# this repo checkout — at runtime that resolves under
# `${CLAUDE_PLUGIN_ROOT}/scripts/progress-event-fixtures/`. Loaded by
# test-progress-state.sh (see that file's fixture-backed case) rather than
# only asserted via the inline `make_payload()` generator.
#
# SESSION-ID RESOLUTION (same two-source join key as emit-token-ledger.sh)
# ----------------------------------------------------------------------
#   1. Prefer the plugin session id from `.supervisor/state.md` (resolved at
#      the MAIN worktree — see anchoring below) when that file's
#      `- status:` is `running`. `checkpoint` is ALSO accepted here ONLY for
#      backward compatibility with pre-change `state.md` files — `checkpoint`
#      is NOT in the closed status enum (skills/state-management/SKILL.md
#      §"State File Schema") and this projector can never emit it; do not
#      treat it as a live status.
#   2. Else fall back to the Claude Code SubagentStop `session_id` (UUID).
#   Always record the CC uuid as additive `cc_session_id` when present, so
#   uuid-named log files do not become the sole join key.
#
# WORKTREE-SAFE ANCHORING (R1 — load-bearing, empirically verified)
# -------------------------------------------------------------------
# Never use bare `$PWD`, bare `git branch --show-current`, or `dirname` of
# the git common dir (the latter is wrong under `--separate-git-dir` and for
# submodules, and fails SILENTLY because this emitter is exit-0-by-contract).
# Verified 2026-07-28 on git 2.50.1 from inside a REAL detached linked
# worktree (this repo's own review-drain worktrees are detached-HEAD, see
# CLAUDE.md "Orphaned worktrees after crash?"): `git worktree list
# --porcelain`'s first entry correctly returned the main checkout, while
# `git branch --show-current` in that worktree returned EMPTY (exit 0, no
# output) and the worktree had no `.supervisor/` at all — i.e. the hazard is
# real. Resolution failure here (not a git repo, or a mismatched
# cross-check) exits 0 — this emitter NEVER guesses and NEVER falls back to
# `$PWD` (unlike emit-token-ledger.sh's modified anchoring, which keeps a
# `$PWD` fallback ONLY for byte-identical backward compatibility with its
# proven 785-event history — see that file's own anchoring comment).
#
# No-op (exit 0) when: empty stdin, missing python3/jq, main worktree
# unresolvable, unwritable log dir, malformed payload, unresolvable session
# id, not-a-git-repo.
#
# `checkpoint` note: emit-token-ledger.sh:128 [pins: `running|checkpoint)`] also accepts it in its
# status test for the identical backward-compat reason described above.
#
# Authoritative spec: this repo's 2026-07-28 brief
# (.supervisor/jobs/*/2026-07-28-one-writer-derived-state.md) Subtask 1.

set -u
# Intentionally NO `set -e` — every failure mode must absorb to exit 0.

trap 'exit 0' EXIT

# ---- Read stdin --------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
if [ -z "$INPUT" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  # Not used directly by THIS script's own line-append, but required by the
  # projector this script invokes — checked here too so the documented
  # "missing python3/jq" failure mode is explicit and independently testable.
  exit 0
fi

# ---- Worktree-safe anchoring (R1 fix, load-bearing) --------------------------
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] && [ -d "$main_root" ] || exit 0        # fail SAFE, never guess
top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
[ "$top" = "$main_root" ] || exit 0
session_branch="$(git -C "$main_root" branch --show-current 2>/dev/null || true)"
LOG_DIR="$main_root/.supervisor/logs"
STATE_MD="$main_root/.supervisor/state.md"

# Prefer a real UTC ISO timestamp; omit ts entirely when date fails.
UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
case "$UTC_TS" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
  *) UTC_TS="" ;;
esac

# ---- Resolve plugin session id from state.md (active run only) --------------
PLUGIN_SESSION_ID=""
PLUGIN_STATUS=""
if [ -f "$STATE_MD" ]; then
  PLUGIN_SESSION_ID="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  PLUGIN_STATUS="$(sed -nE 's/^- status:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  PLUGIN_SESSION_ID="$(printf '%s' "$PLUGIN_SESSION_ID" | tr -cd 'A-Za-z0-9_-' || true)"
  case "$PLUGIN_STATUS" in
    running|checkpoint) ;;   # checkpoint: backward-compat only, see header note
    *) PLUGIN_SESSION_ID="" ;;   # stale/absent status → do not join to a non-active run
  esac
fi

# ---- Run ownership gate ------------------------------------------------------
# Byte-parallel with emit-token-ledger.sh's gate of the same name — read that
# file's comment for the full rationale; the two are deliberately kept identical
# and must be changed together.
#
# A `running`/`checkpoint` status alone is NOT sufficient authority to join a
# run's log: a run that ended WITHOUT emitting `session_end` leaves that status
# on disk forever, so every later session's SubagentStop appends to that one
# run's log, and build-state.sh then re-derives `running` from the newest
# FOREIGN `subtask_complete` it just wrote. The stale status causes the fan-in
# and the fan-in re-asserts the stale status.
#
# The log's FIRST line records who opened it. Only that session may join it.
#
# UNKNOWN OWNER MEANS ADOPT (non-negotiable — do NOT invert this): an absent,
# empty, or unreadable log, an unparseable first line, or a first line with no
# `cc_session_id` all yield an empty owner, which ADOPTS the plugin session id
# exactly as before. Refusing on unknown owner would regress the very first
# worker completion of every fresh run.
loom_log_owner() {
  # Echo the `cc_session_id` on the FIRST line of the given log, or NOTHING
  # when no owner is recorded. Always returns 0 — "no owner" and "cannot tell"
  # are the same answer here, and both mean ADOPT.
  local _log="${1:-}" _first=""
  [ -n "$_log" ] && [ -f "$_log" ] && [ -r "$_log" ] || return 0
  _first="$(head -1 "$_log" 2>/dev/null || true)"
  [ -n "$_first" ] || return 0
  # Probe jq FUNCTIONALLY, never `command -v` alone. A broken jq yields an empty
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

export UTC_TS PLUGIN_SESSION_ID SESSION_BRANCH="$session_branch"

# ---- Build one JSONL line (or empty → no-op) ---------------------------------
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

# Log under the plugin session id when an active Supervisor run is present,
# same join-key policy as emit-token-ledger.sh.
log_session_id = plugin_session_id or cc_session_id
if not log_session_id:
    sys.exit(0)

event = {
    "event": "subtask_complete",
    "type": "subtask_complete",
    "session_id": log_session_id,
}
if cc_session_id:
    event["cc_session_id"] = cc_session_id

# `agent_type`: PAYLOAD ONLY, else the key is OMITTED ENTIRELY — never an empty
# string, never null, never invented. Byte-parallel with emit-token-ledger.sh:
# NEITHER emitter derives `agent_type` from the matcher it was registered under,
# because a matcher does not discriminate — grouping untyped events by `agent_id`
# on the live log yields a fixed 2 `token_ledger` : 1 `subtask_complete` in every
# bucket, so the single `loomwright:worker` block runs on the same untyped
# payloads as the three ledger blocks. Stamping the name of a block onto those
# payloads would INVENT an identity we do not have.
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

# ---- Invoke the projector (best-effort — never affects this emitter's own
# always-exit-0 contract; the projector has the identical contract itself) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/build-state.sh" ]; then
  bash "$SCRIPT_DIR/build-state.sh" "$SESSION_ID" "$main_root" || true
fi

exit 0
