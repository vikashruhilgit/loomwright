#!/usr/bin/env bash
# build-state.sh — the progress-state PROJECTOR (Fix 3 / D5 — "One writer for
# progress state, derived state.md").
#
# INVARIANT: ALWAYS exits 0 — a projection failure must never fail the
# invoking hook (emit-progress-event.sh) or any other caller.
#
# Reads the append-only session JSONL log (`.supervisor/logs/{session_id}.
# jsonl`) and projects the canonical lowercase `## Session` block into
# `.supervisor/state.md`, replacing ONLY that block via temp-file + rename.
# `## Decisions Log`, `## Phase Flags`, `## Checkpoint`, and any other
# section are preserved byte-for-byte — this is a TARGETED in-place edit,
# not a whole-file rewrite.
#
# Usage: build-state.sh <session_id> [main_root]
#   session_id  — required; the log-file basename (join key resolved by
#                 emit-progress-event.sh / emit-token-ledger.sh).
#   main_root   — optional; when omitted, resolved via the SAME
#                 worktree-safe anchoring emit-progress-event.sh uses (see
#                 that file's header for the R1 rationale — first porcelain
#                 `git worktree list` entry + a `--show-toplevel`
#                 cross-check, never `$PWD`, never a $PWD fallback). Accepting
#                 it as an optional 2nd arg lets a caller that already
#                 resolved it (the emitter) skip re-deriving it, so both
#                 write against the identical root in the same invocation.
#
# DERIVATION IS EVIDENCE-ONLY — a projector that guesses is the same lie in
# a new place. Table (verbatim from the authoring brief, Subtask 1):
#
#   Field       | Derived from                          | Absent-evidence behavior
#   ------------|----------------------------------------|-------------------------
#   session_id  | the id passed in (AC-6: the id the      | file not written
#               | FIRST event resolved)                   |
#   branch      | LIVE `git -C main_root branch           | field omitted
#               | --show-current` at projection time      |
#               | (NOT read from the log — a property of  |
#               | the checkout, not stored per-event)      |
#   status      | >=1 `subtask_complete` event and no      | file not written
#               | `session_end` => "running"; a            |
#               | `session_end` event present => its own   |
#               | "status" field mapped into               |
#               | completed | completed_with_escalation |  |
#               | failed (unrecognized/missing status on   |
#               | a PRESENT session_end => "completed", the |
#               | closest safe closed-enum reading of      |
#               | "the run genuinely ended" — NOT a guess   |
#               | from zero evidence)                       |
#   phase       | `subtask_complete` present => "EXECUTE"; | file not written
#               | `session_end` present => "LOOP"          |
#
# `status` is NEVER omitted once the file is written — an absent `- status:`
# trips the `[ -n "$s1_status" ]` presence guard at
# hook-dispatch-on-pr-create.sh:198 and fails the until-mergeable drain
# closed (AC-5). Both `status` and `phase` MUST land inside the closed enums
# at skills/state-management/SKILL.md §"State File Schema"
# (phase: INIT|ACQUIRE|PLAN|EXECUTE|FINALIZE|SELF_HEAL|LOOP; status:
# running|paused|completed|completed_with_escalation|failed) — verified: this
# projector only ever emits EXECUTE|LOOP and running|completed|
# completed_with_escalation|failed, all members of those sets.
#
# An empty/absent log means NO `state.md` at all — start-fresh, strictly
# better than the pre-change failure mode (a stale lie left on disk).
#
# This projector writes ONLY session_id/branch/status/phase into
# `## Session` — no other field (e.g. `task_id`) is derivable from the event
# log per this subtask's scope, so any pre-existing field the OLD
# prompt-instructed writers left behind is intentionally not carried
# forward. "state.md reproducible from the log alone" is the point.
#
# Authoritative spec: this repo's 2026-07-28 brief
# (.supervisor/jobs/*/2026-07-28-one-writer-derived-state.md) Subtask 1.

set -u
trap 'exit 0' EXIT

SESSION_ID="${1:-}"
[ -n "$SESSION_ID" ] || exit 0
SESSION_ID="$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9_-')"
[ -n "$SESSION_ID" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# ---- Worktree-safe anchoring (same policy as emit-progress-event.sh) --------
MAIN_ROOT="${2:-}"
if [ -z "$MAIN_ROOT" ]; then
  MAIN_ROOT="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
fi
[ -n "$MAIN_ROOT" ] && [ -d "$MAIN_ROOT" ] || exit 0
TOP="$(git -C "$MAIN_ROOT" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
[ "$TOP" = "$MAIN_ROOT" ] || exit 0

LOG_FILE="$MAIN_ROOT/.supervisor/logs/${SESSION_ID}.jsonl"
STATE_MD="$MAIN_ROOT/.supervisor/state.md"

# Absent/empty log => no state.md at all (start-fresh).
[ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ] || exit 0

# ---- Derive status/phase from the log (evidence-only) -----------------------
# `-R` (raw input, one JSON value per line) + `fromjson?` skips any malformed
# line instead of failing the whole parse — a corrupt/partial line elsewhere
# in the JSONL must not block projection of the events that DO parse.
SESSION_END_PRESENT="$(jq -R -r 'fromjson? | select(.event? == "session_end") | "1"' "$LOG_FILE" 2>/dev/null | tail -1)"
SESSION_END_STATUS="$(jq -R -r 'fromjson? | select(.event? == "session_end") | (.status // empty)' "$LOG_FILE" 2>/dev/null | tail -1)"
SUBTASK_COMPLETE_COUNT="$(jq -R -r 'fromjson? | select(.event? == "subtask_complete") | "1"' "$LOG_FILE" 2>/dev/null | wc -l | tr -d '[:space:]')"

STATUS=""
PHASE=""
if [ "$SESSION_END_PRESENT" = "1" ]; then
  PHASE="LOOP"
  case "$SESSION_END_STATUS" in
    completed) STATUS="completed" ;;
    completed_with_escalation) STATUS="completed_with_escalation" ;;
    failed) STATUS="failed" ;;
    *) STATUS="completed" ;;   # session_end fired but status missing/unrecognized — see header note
  esac
elif [ -n "${SUBTASK_COMPLETE_COUNT:-}" ] && [ "${SUBTASK_COMPLETE_COUNT:-0}" -ge 1 ] 2>/dev/null; then
  PHASE="EXECUTE"
  STATUS="running"
else
  # No subtask_complete and no session_end => no positive evidence => do not write.
  exit 0
fi

[ -n "$STATUS" ] && [ -n "$PHASE" ] || exit 0

# `branch` is LIVE git state at the main root, not log content (see header).
BRANCH="$(git -C "$MAIN_ROOT" branch --show-current 2>/dev/null || true)"

# ---- Targeted in-place edit of ## Session only, preserving other sections --
mkdir -p "$(dirname "$STATE_MD")" 2>/dev/null || exit 0

TMP="$(mktemp "${STATE_MD}.XXXXXX" 2>/dev/null)" || exit 0
BLOCK="$(mktemp "${STATE_MD}.block.XXXXXX" 2>/dev/null)" || { rm -f "$TMP" 2>/dev/null; exit 0; }
cleanup_tmp() { rm -f "$TMP" "$BLOCK" 2>/dev/null || true; }
trap 'cleanup_tmp; exit 0' EXIT

{
  printf -- '- session_id: %s\n' "$SESSION_ID"
  if [ -n "$BRANCH" ]; then
    printf -- '- branch: %s\n' "$BRANCH"
  fi
  printf -- '- status: %s\n' "$STATUS"
  printf -- '- phase: %s\n' "$PHASE"
  printf '\n'
} > "$BLOCK" 2>/dev/null || exit 0

if [ -f "$STATE_MD" ]; then
  awk -v newblock="$BLOCK" '
    BEGIN { in_session = 0; injected = 0 }
    /^## Session[[:space:]]*$/ {
      print
      while ((getline line < newblock) > 0) print line
      close(newblock)
      in_session = 1
      injected = 1
      next
    }
    in_session && /^## / { in_session = 0 }
    in_session { next }
    { print }
    END {
      if (!injected) {
        print "## Session"
        while ((getline line < newblock) > 0) print line
      }
    }
  ' "$STATE_MD" > "$TMP" 2>/dev/null || exit 0
else
  {
    printf '# Supervisor State\n\n'
    printf '## Session\n'
    cat "$BLOCK"
  } > "$TMP" 2>/dev/null || exit 0
fi

mv -f "$TMP" "$STATE_MD" 2>/dev/null || exit 0
rm -f "$BLOCK" 2>/dev/null || true

exit 0
