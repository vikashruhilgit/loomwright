#!/usr/bin/env bash
# build-state.sh — the progress-state PROJECTOR (Fix 3 / D5 — "One writer for
# progress state, derived state.md").
#
# INVARIANT: ALWAYS exits 0 — a projection failure must never fail the
# invoking hook (emit-progress-event.sh, reproject-terminal-state.sh) or any
# other caller.
#
# Reads the append-only session JSONL log (`.supervisor/logs/{session_id}.
# jsonl`) and projects the canonical lowercase `## Session` block into
# `.supervisor/state.md`, replacing ONLY that block via temp-file + rename.
# `## Decisions Log`, `## Phase Flags`, `## Checkpoint`, and any other
# section are preserved byte-for-byte — this is a TARGETED in-place edit,
# not a whole-file rewrite. Any `- key:` line inside `## Session` itself
# that this projector does not derive (e.g. `task_id`, `self_heal_resume_count`)
# is ALSO preserved verbatim — see "Field ownership" below (PR #116 review
# Finding 4).
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
# a new place. Table (verbatim from the authoring brief, Subtask 1, updated
# for the PR #116 review's multi-task ordering fix):
#
#   Field       | Derived from                          | Absent-evidence behavior
#   ------------|----------------------------------------|-------------------------
#   session_id  | the id passed in (AC-6: the id the      | file not written
#               | FIRST event resolved)                   |
#   branch      | LIVE `git -C main_root branch           | field omitted
#               | --show-current` at projection time      |
#               | (NOT read from the log — a property of  |
#               | the checkout, not stored per-event)      |
#   status      | ORDERING RULE (not "any session_end      | file not written
#               | present"): the LAST of {subtask_complete,|
#               | session_end} in the log decides. If the  |
#               | last one is subtask_complete => "running"|
#               | (even when an EARLIER session_end exists |
#               | — the multi-task `/autonomous` LOOP case,|
#               | task 1's session_end must not make task  |
#               | 2 read as completed). If the last one is |
#               | session_end => its own "status" field    |
#               | mapped into completed |                  |
#               | completed_with_escalation | failed        |
#               | (unrecognized/missing status on that     |
#               | LAST session_end => "completed", the      |
#               | closest safe closed-enum reading of      |
#               | "the run genuinely ended" — NOT a guess   |
#               | from zero evidence).                      |
#   phase       | same ordering rule: last event is         | file not written
#               | subtask_complete => "EXECUTE"; last event |
#               | is session_end => "LOOP"                  |
#
# `status` is NEVER omitted once the file is written — an absent `- status:`
# trips the `[ -n "$s1_status" ]` presence guard (the `s1_status` variable in
# `hook-dispatch-on-pr-create.sh`'s Source 1 block) and fails the
# until-mergeable drain closed (AC-5). Both `status` and `phase` MUST land
# inside the closed enums at skills/state-management/SKILL.md §"State File
# Schema" (phase: INIT|ACQUIRE|PLAN|EXECUTE|FINALIZE|SELF_HEAL|LOOP; status:
# running|paused|completed|completed_with_escalation|failed) — verified: this
# projector only ever emits EXECUTE|LOOP and running|completed|
# completed_with_escalation|failed, all members of those sets.
#
# An empty/absent log means NO `state.md` at all — start-fresh, strictly
# better than the pre-change failure mode (a stale lie left on disk).
#
# FIELD OWNERSHIP (PR #116 review Finding 4 — narrowed from "owns the whole
# block"): this projector owns and re-derives EXACTLY FOUR keys —
# session_id/branch/status/phase. Any OTHER `- key: value` line already
# present in the existing `## Session` block (e.g. `task_id`,
# `self_heal_resume_count`) is read back from the pre-projection file and
# re-emitted verbatim, in its original relative order, after the four
# derived keys. This makes "state.md reproducible from the log alone" true
# for the four progress-state keys specifically, without silently deleting
# fields this scope does not own. A brand-new `## Session` block (no prior
# state.md) naturally has nothing to preserve.
#
# CONCURRENCY (PR #116 review Finding 2): this is a read-modify-write
# (read whole file -> awk -> temp file -> rename). Context-Keeper performs
# its OWN read-modify-write (via the Edit tool) against the same file for
# `## Decisions Log` / `## Worker Results` / `## Error Log` / `## Phase
# Flags`. Reproduced 6/6: an interleaved Context-Keeper write-back can
# clobber a freshly projected `## Session` block. Fix: a portable mkdir-based
# lock (flock(1) is not on stock macOS) around the read-modify-write. Under
# contention this projector SKIPS (exits 0) rather than waiting — safe
# specifically BECAUSE the log is append-only: the next event re-derives the
# identical `## Session` content, so a skipped projection is never a lost
# fact, only a delayed one. See "Lock" section below for stale-lock handling.
#
# PERMISSIONS (PR #116 review Finding 3): `mktemp` creates its temp file
# 0600, and a bare `mv -f` onto `state.md` carries that mode forward,
# silently narrowing an existing 644 file to 600 on the very first
# projection. This script reads the ORIGINAL file's mode portably (BSD
# `stat -f %Lp`, falling back to GNU `stat -c %a`; NEITHER stat flavor is
# assumed a priori, since this repo has already shipped a Linux-CI failure
# from exactly that BSD/GNU `stat -f` vs `stat -c` divergence) and re-applies
# it to the temp file before the rename. A brand-new `state.md` (no prior
# file to read a mode from) is created 644.
#
# Authoritative spec: this repo's 2026-07-28 brief
# (.supervisor/jobs/*/2026-07-28-one-writer-derived-state.md) Subtask 1;
# concurrency/permissions/ownership fixes from the PR #116 review round.

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

# ---- Derive status/phase from the log (evidence-only, ORDERING RULE) --------
# `-R` (raw input, one JSON value per line) + `fromjson?` skips any malformed
# line instead of failing the whole parse — a corrupt/partial line elsewhere
# in the JSONL must not block projection of the events that DO parse.
#
# The LAST of {subtask_complete, session_end} in the file decides — NOT "any
# session_end present anywhere" (that scanned-the-whole-file rule made task 1's
# session_end in a shared multi-task /autonomous LOOP log falsely mark task 2
# "completed" while task 2 was still running; `subtask_complete` carries no
# task id to disambiguate by, so ordering is the only evidence available).
SESSION_END_STATUS="$(jq -R -r 'fromjson? | select(.event? == "session_end") | (.status // empty)' "$LOG_FILE" 2>/dev/null | tail -1)"
LAST_RELEVANT_EVENT="$(jq -R -r 'fromjson? | select(.event? == "session_end" or .event? == "subtask_complete") | .event' "$LOG_FILE" 2>/dev/null | tail -1)"

STATUS=""
PHASE=""
case "$LAST_RELEVANT_EVENT" in
  session_end)
    PHASE="LOOP"
    case "$SESSION_END_STATUS" in
      completed) STATUS="completed" ;;
      completed_with_escalation) STATUS="completed_with_escalation" ;;
      failed) STATUS="failed" ;;
      *) STATUS="completed" ;;   # session_end fired but status missing/unrecognized — see header note
    esac
    ;;
  subtask_complete)
    PHASE="EXECUTE"
    STATUS="running"
    ;;
  *)
    # Neither event type present with valid JSON => no positive evidence => do not write.
    exit 0
    ;;
esac

[ -n "$STATUS" ] && [ -n "$PHASE" ] || exit 0

# `branch` is LIVE git state at the main root, not log content (see header).
BRANCH="$(git -C "$MAIN_ROOT" branch --show-current 2>/dev/null || true)"

# ---- Preserve non-derived `- key:` lines already in ## Session -------------
# (Finding 4 — this projector owns exactly session_id/branch/status/phase;
# everything else that was already there survives, in its original order.)
PRESERVED_SESSION_LINES=""
if [ -f "$STATE_MD" ]; then
  PRESERVED_SESSION_LINES="$(awk '
    /^## Session[[:space:]]*$/ { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^- [A-Za-z_][A-Za-z0-9_]*:/ {
      line = $0
      key = line
      sub(/^- /, "", key)
      sub(/:.*/, "", key)
      if (key !~ /^(session_id|branch|status|phase)$/) print line
    }
  ' "$STATE_MD" 2>/dev/null || true)"
fi

# ---- mkdir-based lock (Finding 2) -------------------------------------------
# flock(1) is not available on stock macOS (bash 3.2 + BSD userland), so use a
# directory-create as the portable atomic mutual-exclusion primitive: mkdir
# either creates the directory (lock acquired) or fails because it already
# exists (lock held elsewhere) — both outcomes are atomic at the filesystem
# level.
#
# Stale-lock decision (documented, not implicit): a lock dir can be
# abandoned by a hard-killed holder (SIGKILL, power loss) between mkdir and
# its own rmdir — mkdir-based locks have no OS-level "owner died" detection,
# unlike flock(1). This script ages out any lock dir older than
# STALE_LOCK_SECONDS by rmdir-ing it and retrying acquisition exactly once.
# This is safe specifically because the only thing the lock protects is a
# projection that is ALWAYS re-derivable from the same append-only log on
# the very next event — an incorrectly-stolen lock from a genuinely slow
# (not dead) holder costs, at worst, one skipped or doubled projection of
# IDENTICAL derivable content, never data loss.
LOCK_DIR="$MAIN_ROOT/.supervisor/.state.lock"
STALE_LOCK_SECONDS=60

lock_age_seconds() {
  local dir="$1" mtime now
  # GNU first: BSD `stat -c` FAILS cleanly, whereas GNU `stat -f` SUCCEEDS
  # while printing a filesystem dump. Trying BSD first would capture that
  # garbage on Linux; the numeric guard below catches it either way, but
  # GNU-first avoids relying on the guard at all (repo convention — see
  # build-handoff.sh / read-orientation.sh).
  mtime="$(stat -c %Y "$dir" 2>/dev/null)"
  case "$mtime" in
    ''|*[!0-9]*) mtime="$(stat -f %m "$dir" 2>/dev/null)" ;;
  esac
  case "$mtime" in
    ''|*[!0-9]*) return 1 ;;
  esac
  now="$(date +%s 2>/dev/null)"
  case "$now" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$((now - mtime))"
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    return 0
  fi
  # Contention. Check whether the existing lock is stale enough to steal.
  local age
  age="$(lock_age_seconds "$LOCK_DIR" 2>/dev/null || true)"
  if [ -n "${age:-}" ] && [ "$age" -ge "$STALE_LOCK_SECONDS" ] 2>/dev/null; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# Ensure the lock dir's PARENT exists before attempting to acquire it — on a
# genuinely first-ever projection (no `.supervisor/` yet) `mkdir "$LOCK_DIR"`
# would otherwise fail with ENOENT (missing parent), which `acquire_lock`
# cannot distinguish from real contention, and this script would exit 0
# without ever writing the very first state.md. This mkdir is best-effort and
# unconditional (not itself lock-protected) — creating the directory is not
# the racy part; the read-modify-write of state.md inside it is.
mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true

if ! acquire_lock; then
  # Under contention (or a live holder), skip THIS projection rather than
  # wait — the append-only log guarantees the next event re-derives the same
  # ## Session content, so nothing is lost.
  exit 0
fi

# ---- Targeted in-place edit of ## Session only, preserving other sections --
mkdir -p "$(dirname "$STATE_MD")" 2>/dev/null || { rmdir "$LOCK_DIR" 2>/dev/null || true; exit 0; }

TMP="$(mktemp "${STATE_MD}.XXXXXX" 2>/dev/null)" || { rmdir "$LOCK_DIR" 2>/dev/null || true; exit 0; }
BLOCK="$(mktemp "${STATE_MD}.block.XXXXXX" 2>/dev/null)" || { rm -f "$TMP" 2>/dev/null; rmdir "$LOCK_DIR" 2>/dev/null || true; exit 0; }
cleanup_tmp() { rm -f "$TMP" "$BLOCK" 2>/dev/null || true; rmdir "$LOCK_DIR" 2>/dev/null || true; }
# Lock is released (rmdir) on EVERY exit path from here on — normal
# completion, any `exit 0` below, or an unexpected signal — via this single
# trap (bash traps replace, not stack, so this supersedes the top-of-file
# `trap 'exit 0' EXIT`).
trap 'cleanup_tmp; exit 0' EXIT

{
  printf -- '- session_id: %s\n' "$SESSION_ID"
  if [ -n "$BRANCH" ]; then
    printf -- '- branch: %s\n' "$BRANCH"
  fi
  printf -- '- status: %s\n' "$STATUS"
  printf -- '- phase: %s\n' "$PHASE"
  if [ -n "$PRESERVED_SESSION_LINES" ]; then
    printf '%s\n' "$PRESERVED_SESSION_LINES"
  fi
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

# ---- Preserve the original file's permission mode (Finding 3) ---------------
# `mktemp` creates $TMP 0600; a bare `mv -f` would carry that onto state.md,
# silently narrowing an existing 644 file to 600 on the first projection.
# Read the ORIGINAL mode portably, GNU (`stat -c %a`) FIRST then BSD
# (`stat -f %Lp`) — never assume a flavor, and never branch on stat's exit
# code. GNU `stat -f` means "report FILE SYSTEM status": it exits 0 while
# printing a filesystem dump, so a BSD-first probe captures garbage on Linux
# that only an output guard can catch. BSD `stat -c` fails cleanly, so
# GNU-first degrades safely on both. (Repo convention — build-handoff.sh,
# read-orientation.sh. This repo has already shipped a Linux-CI failure from
# exactly this divergence, and did so again in this PR's own test code.)
ORIG_MODE=""
if [ -f "$STATE_MD" ]; then
  ORIG_MODE="$(stat -c %a "$STATE_MD" 2>/dev/null)"
  case "$ORIG_MODE" in
    ''|*[!0-7]*) ORIG_MODE="$(stat -f %Lp "$STATE_MD" 2>/dev/null)" ;;
  esac
  case "$ORIG_MODE" in
    ''|*[!0-7]*) ORIG_MODE="" ;;
  esac
fi
if [ -n "$ORIG_MODE" ]; then
  chmod "$ORIG_MODE" "$TMP" 2>/dev/null || true
else
  chmod 644 "$TMP" 2>/dev/null || true
fi

mv -f "$TMP" "$STATE_MD" 2>/dev/null || exit 0
rm -f "$BLOCK" 2>/dev/null || true

exit 0
