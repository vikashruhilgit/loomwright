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
# STALENESS BACKSTOP (LOOMWRIGHT_STALE_RUN_SECONDS, default 86400): a derived
# `running` whose newest OWNER-ORIGINATED event is older than the threshold is
# reported as `failed` instead. Age is measured over OWNER lines ONLY — lines
# whose `cc_session_id` equals the one on the log's FIRST line. Measuring over
# ALL lines is precisely what made the original failure circular: foreign
# sessions kept appending fresh `subtask_complete` events to a finished run's
# log, so the log always LOOKED fresh and `running` was re-asserted forever.
# When ownership cannot be established or a timestamp cannot be parsed, the
# backstop SKIPS — it never guesses a run dead.
#
# OWNER AND AGE BOTH ALSO COME FROM THE RUN-CREATION SEED
# (`.supervisor/logs/<run_id>.owner`, written by `seed-run-owner.sh` when
# `state.md` is created). The seed is consulted FIRST for the owner, and its
# `started_at` counts as owner-originated evidence — it is the last thing we
# know the owner did when the owner has emitted no events of its own. That is
# what lets the backstop reach the ACQUIRE → PRE-FLIGHT SYNC → PLAN window at
# all: before, this script returned on its log-exists guard below, and in that
# window the log does not exist. A log with no seed behaves exactly as before.
#
# The status vocabulary this projector emits is UNCHANGED by the backstop:
# `failed` is already in the set below. `paused` is NEVER emitted (frozen
# decision D2 — it is classified live by hook-dispatch-on-pr-create.sh and dead
# by both emitters, so emitting it would put two consumers in disagreement).
#
# `status` is NEVER omitted once the file is written — an absent `- status:`
# trips the `[ -n "$s1_status" ]` presence guard (the `s1_status` variable in
# `hook-dispatch-on-pr-create.sh`'s Source 1 block) and fails the
# until-mergeable drain closed (AC-5). Both `status` and `phase` MUST land
# inside the closed enums at skills/state-management/SKILL.md §"State File
# Schema" (phase: INIT|ACQUIRE|PLAN|EXECUTE|FINALIZE|SELF_HEAL|LOOP; status:
# running|paused|completed|completed_with_escalation|failed) — verified: this
# projector only ever emits EXECUTE|LOOP and running|completed|
# completed_with_escalation|failed, all members of those sets. The staleness
# backstop introduces NO new status word — it can only turn a derived `running`
# into `failed`, both already in that list.
#
# An empty/absent log still means NO `state.md` is ever CREATED — start-fresh,
# strictly better than the pre-change failure mode (a stale lie left on disk).
# The one thing an empty/absent log can now do is close out an ALREADY-EXISTING
# non-terminal `state.md` for this same run, and only when the seed's
# `started_at` is older than the staleness threshold: `failed`/`LOOP`, the same
# pair a `session_end` produces. It can never write `running` from this branch.
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
OWNER_FILE="$MAIN_ROOT/.supervisor/logs/${SESSION_ID}.owner"
STATE_MD="$MAIN_ROOT/.supervisor/state.md"

# ---- The run-creation seed (`<run_id>.owner`) -------------------------------
# Written by `seed-run-owner.sh` at the moment `state.md` is created, so both
# WHO owns a run and WHEN it began are knowable before the log's first line
# exists. Plain `key=value`; no jq needed to read it.
#
# `loom_run_owner_seed` is KEPT BYTE-IDENTICAL to the copy in
# close-stranded-run.sh — change them together;
# `scripts/test-seed-run-owner.sh` asserts the two bodies match.
loom_run_owner_seed() {
  # Echo the `cc_session_id` recorded at run creation, or NOTHING when no seed
  # exists / it carries no owner. Always returns 0 — "no seed" and "cannot
  # tell" are the same answer, and both mean "fall back to the log".
  local _seed="${1:-}"
  [ -n "$_seed" ] && [ -f "$_seed" ] && [ -r "$_seed" ] || return 0
  sed -nE 's/^cc_session_id=//p' "$_seed" 2>/dev/null | head -1 || true
  return 0
}

loom_run_started_at() {
  # Echo the seed's `started_at` when it is a strict UTC ISO-8601 instant, or
  # NOTHING. Always returns 0 — a malformed value is treated as absent, never
  # allowed to reach the age arithmetic.
  local _seed="${1:-}" _ts=""
  [ -n "$_seed" ] && [ -f "$_seed" ] && [ -r "$_seed" ] || return 0
  _ts="$(sed -nE 's/^started_at=//p' "$_seed" 2>/dev/null | head -1 || true)"
  case "${_ts:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) printf '%s\n' "$_ts" ;;
  esac
  return 0
}

# ---- Log present, or the pre-first-event window? ----------------------------
# An absent/empty log used to exit here unconditionally, which is why the
# staleness backstop could never reach a run stranded between `initialize` and
# its first worker completion: the projector returned on this guard before any
# derivation ran, and in that window the log does not exist at all.
#
# It still exits when there is nothing to derive from. What it no longer does is
# exit when the run-creation seed carries evidence — specifically a
# `started_at`, which is the last thing we know the owner did and therefore a
# legitimate staleness anchor. The branch below is DELIBERATELY narrow: the ONLY
# outcome it can produce is the staleness verdict `failed` (see the
# PRE_EVENT_RUN gate after the backstop). It can never project `running` over a
# live run's block, and it can never bring a `state.md` into existence — an
# absent state file still means start-fresh, exactly as before.
LOG_PRESENT=0
if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
  LOG_PRESENT=1
fi

PRE_EVENT_RUN=0
if [ "$LOG_PRESENT" -eq 0 ]; then
  [ -f "$STATE_MD" ] && [ -r "$STATE_MD" ] || exit 0
  _sm_session="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  _sm_session="$(printf '%s' "$_sm_session" | tr -cd 'A-Za-z0-9_-' || true)"
  # Only act on the run `state.md` currently describes. A caller passing some
  # OTHER run's id must not repaint this file with that run's verdict.
  [ "$_sm_session" = "$SESSION_ID" ] || exit 0
  _sm_status="$(sed -nE 's/^- status:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
  case "$_sm_status" in
    running|checkpoint|paused) ;;
    *) exit 0 ;;   # already terminal, or unrecognised — never guess
  esac
  # No seed ⇒ no owner and no start instant ⇒ nothing to measure. Exit exactly
  # as this guard did before, rather than guessing the run dead.
  [ -n "$(loom_run_owner_seed "$OWNER_FILE" || true)" ] || exit 0
  [ -n "$(loom_run_started_at "$OWNER_FILE" || true)" ] || exit 0
  PRE_EVENT_RUN=1
fi

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
STATUS=""
PHASE=""
if [ "$LOG_PRESENT" -eq 1 ]; then
  SESSION_END_STATUS="$(jq -R -r 'fromjson? | select(.event? == "session_end") | (.status // empty)' "$LOG_FILE" 2>/dev/null | tail -1)"
  LAST_RELEVANT_EVENT="$(jq -R -r 'fromjson? | select(.event? == "session_end" or .event? == "subtask_complete") | .event' "$LOG_FILE" 2>/dev/null | tail -1)"

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
else
  # PRE-FIRST-EVENT WINDOW. The seed is evidence that a run BEGAN and nothing
  # more, so `running` is the only honest starting point — and it is never
  # written as such: the gate after the backstop drops this branch unless the
  # backstop turned it into `failed`. `LOOP` is set here because it is the
  # phase word this projector already pairs with EVERY terminal status (the
  # `session_end` arm above), so a run closed by the backstop reads exactly
  # like one closed by an event. No new phase word is introduced.
  STATUS="running"
  PHASE="LOOP"
fi

# ---- Staleness backstop -----------------------------------------------------
# A run whose OWNER stopped emitting long ago is not running, whatever the last
# event in the log says. Without this, a run that ends without a `session_end`
# leaves `running` on disk permanently, which is exactly what let a finished run
# capture 140 later sessions' events.
#
# MEASURED OVER OWNER LINES ONLY. The owner is the `cc_session_id` on the log's
# FIRST line. Measuring over every line would re-create the original circularity:
# foreign appends kept the log looking fresh forever.
LOOMWRIGHT_STALE_RUN_SECONDS="${LOOMWRIGHT_STALE_RUN_SECONDS:-86400}"
case "$LOOMWRIGHT_STALE_RUN_SECONDS" in
  ''|*[!0-9]*) LOOMWRIGHT_STALE_RUN_SECONDS=86400 ;;   # non-integer override → default, never `set -u` arithmetic on it
esac

iso_to_epoch() {
  # Convert a strict UTC ISO-8601 `YYYY-MM-DDTHH:MM:SSZ` string to epoch
  # seconds. Returns non-zero (and prints nothing) when it cannot.
  local _iso="${1:-}" _e=""
  case "$_iso" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) return 1 ;;
  esac
  # GNU first, then BSD — the same never-assume-a-flavor convention this file
  # already applies to `stat` (see the permission-mode block below). Both
  # flavors reject the other's flag cleanly here, and the numeric guard below
  # catches anything that slips through, so neither platform can produce
  # garbage that reaches arithmetic.
  _e="$(date -u -d "$_iso" +%s 2>/dev/null)"
  case "$_e" in
    ''|*[!0-9]*) _e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_iso" +%s 2>/dev/null)" ;;
  esac
  case "$_e" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$_e"
}

if [ "$STATUS" = "running" ]; then
  # SEED FIRST, log first line second — the same precedence close-stranded-run.sh
  # applies, for the same reason: the seed is recorded at run creation and keyed
  # to the run id, whereas the log's first line is whoever appended first, which
  # the emitters' adopt-on-unknown rule allows to be a FOREIGN session. Where the
  # two disagree, the disagreement IS that foreign append.
  LOG_OWNER="$(loom_run_owner_seed "$OWNER_FILE" || true)"
  if [ -z "$LOG_OWNER" ] && [ "$LOG_PRESENT" -eq 1 ]; then
    LOG_OWNER="$(head -1 "$LOG_FILE" 2>/dev/null | jq -r '.cc_session_id // empty' 2>/dev/null || true)"
  fi
  LOG_OWNER="$(printf '%s' "$LOG_OWNER" | tr -cd 'A-Za-z0-9_-' || true)"
  if [ -n "$LOG_OWNER" ]; then
    # UTC ISO-8601 sorts lexicographically in chronological order, so `sort |
    # tail -1` is the newest owner-originated timestamp without any date math.
    # SANITISE BOTH SIDES IDENTICALLY. $owner has already been through
    # `tr -cd 'A-Za-z0-9_-'` above, so comparing it against a RAW
    # `.cc_session_id` would make every owner id containing a stripped
    # character match NOTHING — the backstop would silently find no owner
    # lines and skip. The gsub below applies the same character class to the
    # log side, so the two are compared in the same normalised space.
    NEWEST_OWNER_TS=""
    if [ "$LOG_PRESENT" -eq 1 ]; then
      NEWEST_OWNER_TS="$(jq -R -r --arg owner "$LOG_OWNER" \
        'fromjson? | select(((.cc_session_id // "") | gsub("[^A-Za-z0-9_-]";"")) == $owner) | (.ts // empty)' \
        "$LOG_FILE" 2>/dev/null | sort | tail -1)"
    fi
    # The run's START is owner-originated evidence too — it is the last thing we
    # know the owner did when it has emitted no events of its own, which is the
    # entire pre-first-event window. Without this the backstop had NOTHING to
    # measure there and skipped, so a run stranded before its first worker stayed
    # `running` forever. Taking the LATER of the two also keeps a log that DOES
    # carry owner lines authoritative over the (necessarily older) start instant.
    # Strict UTC ISO-8601 sorts lexicographically in chronological order, so the
    # string comparison is the chronological one — the same property the `sort |
    # tail -1` above already relies on.
    RUN_STARTED_AT="$(loom_run_started_at "$OWNER_FILE" || true)"
    if [ -n "${RUN_STARTED_AT:-}" ] && [ "$RUN_STARTED_AT" \> "${NEWEST_OWNER_TS:-}" ]; then
      NEWEST_OWNER_TS="$RUN_STARTED_AT"
    fi
    if [ -n "${NEWEST_OWNER_TS:-}" ]; then
      _now="$(date -u +%s 2>/dev/null)"
      # Command substitution discards the callee's exit status, so validate the
      # VALUE — an empty string reaching `$(( ))` under `set -u` is a silent trap.
      _then="$(iso_to_epoch "$NEWEST_OWNER_TS" 2>/dev/null || true)"
      case "$_now" in ''|*[!0-9]*) _now="" ;; esac
      case "${_then:-}" in ''|*[!0-9]*) _then="" ;; esac
      if [ -n "$_now" ] && [ -n "$_then" ] && [ "$((_now - _then))" -ge "$LOOMWRIGHT_STALE_RUN_SECONDS" ]; then
        STATUS="failed"
      fi
    fi
  fi
fi

[ -n "$STATUS" ] && [ -n "$PHASE" ] || exit 0

# ---- The pre-first-event branch may write ONLY the staleness verdict --------
# A run with no log has no evidence of PROGRESS — only of having begun. If the
# backstop did not turn that into `failed`, there is nothing to project, and
# writing `running`/`LOOP` would actively destroy information: it would stamp
# the projector's terminal phase word onto a live run and overwrite whatever
# phase Context-Keeper's seed put there. So this branch either closes the run
# out or writes nothing at all.
if [ "$PRE_EVENT_RUN" -eq 1 ] && [ "$STATUS" != "failed" ]; then
  exit 0
fi

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
