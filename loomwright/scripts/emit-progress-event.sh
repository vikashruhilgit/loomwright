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

for opt in ("agent_type", "agent_id"):
    val = payload.get(opt)
    if isinstance(val, str) and val:
        event[opt] = val

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
