#!/usr/bin/env bash
# reconcile-resume-state.sh — ground-truth reconciliation for `/supervisor --continue`.
#
# WHY THIS EXISTS
#   The v15.3.0 resume validation gate (skills/state-management/SKILL.md §"Resume validation gate")
#   checks that `.supervisor/state.md` is SCHEMA-VALID. It cannot tell whether the state is TRUE.
#   Observed 2026-07-27 (session sup-2026-07-27-tree-and-find): all 5 subtasks implemented,
#   reviewed, and merged, while state.md still read `phase: ACQUIRE` with every subtask `PENDING`.
#   That file passes every schema check. Resuming from it would silently re-execute the whole job.
#
#   Root cause is NOT a Context-Keeper bug — it is that prompt-instructed bookkeeping is unreliable
#   under load. Measured across this repo's session logs: 560 hook-written `token_ledger` events vs
#   6 agent-written `phase_transition` events across 11+ sessions. The agent does the work and skips
#   the recording. So this reconciler deliberately keys ONLY on artifacts produced as a BYPRODUCT of
#   doing the work — subtask commits reachable from the feature branch. A worker cannot deliver a
#   subtask without committing it, so unlike a log line the signal is not skippable.
#
#   Commit convention is mandated, not guessed: skills/async-orchestration/SKILL.md:576 specifies
#   `subtask: {subtask_id} — {title}`. Merge commits observed in the wild add a `merge: ` prefix.
#
# CONTRACT
#   Usage: reconcile-resume-state.sh <state_file> [repo_root]
#   Prints `VERDICT: CLEAN|STALE|UNKNOWN` plus detail lines on stdout.
#   Exit 0 = CLEAN (state does not under-report reality; safe to consume)
#   Exit 3 = STALE (state under-reports completed work; caller MUST refuse the resume)
#   Exit 4 = UNKNOWN (ground truth unreadable; caller MUST fail CLOSED per the bimodal invariant)
#
#   This is a CORRECTNESS gate, not a telemetry emitter — it fails CLOSED and must never be
#   given a `|| true`. See CLAUDE.md §Failure-Mode Invariants.
#
# macOS/bash 3.2 safe: no associative arrays, no mapfile, no GNU-only flags.

set -u

STATE_FILE="${1:-}"
REPO_ROOT="${2:-.}"

die_unknown() { printf 'VERDICT: UNKNOWN\nreason: %s\n' "$1"; exit 4; }

[ -n "$STATE_FILE" ] || die_unknown "no state file argument"

# A MISSING state file is not this gate's business — "no state → start fresh" is existing
# documented behaviour (Resume Priority item 3). Report CLEAN and let the caller proceed.
if [ ! -f "$STATE_FILE" ]; then
  printf 'VERDICT: CLEAN\nreason: no state file — start-fresh path, nothing to contradict\n'
  exit 0
fi

command -v git >/dev/null 2>&1 || die_unknown "git not available"
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die_unknown "not a git repository: $REPO_ROOT"

# --- Parse the branch out of the ## Session block -----------------------------------------------
# Untrusted input (the gate's own premise): validate as a ref name before passing to git.
BRANCH=$(sed -n 's/^[[:space:]]*-[[:space:]]*branch:[[:space:]]*//p' "$STATE_FILE" | head -1 \
         | sed 's/[[:space:]]*$//')

if [ -z "$BRANCH" ]; then
  printf 'VERDICT: CLEAN\nreason: no branch asserted in ## Session — no git ground truth to compare\n'
  exit 0
fi

git -C "$REPO_ROOT" check-ref-format --branch "$BRANCH" >/dev/null 2>&1 \
  || die_unknown "branch value fails ref-format: $BRANCH"
git -C "$REPO_ROOT" rev-parse --verify "$BRANCH" >/dev/null 2>&1 \
  || die_unknown "branch not resolvable locally: $BRANCH"

# --- Collect subtask ids that git proves are done -----------------------------------------------
# Matches `subtask: 3 — title` and `merge: subtask 3 — title`; id is the first token after the
# colon. Anchored so a mention inside prose cannot masquerade as a completion record.
SUBJECTS=$(git -C "$REPO_ROOT" log --format='%s' "$BRANCH" 2>/dev/null) \
  || die_unknown "git log failed for branch: $BRANCH"

DONE_IDS=$(printf '%s\n' "$SUBJECTS" \
  | sed -n 's/^\(merge: \)\{0,1\}subtask:[[:space:]]*\([A-Za-z0-9_.-]\{1,\}\).*/\2/p' \
  | sort -u)

# --- Parse the ## Subtasks table ----------------------------------------------------------------
# Rows look like: | 1 | Shared $I30 walker | PENDING |
# Absent section or zero rows ⇒ nothing can be under-reported ⇒ CLEAN.
ROWS=$(awk '
  /^##[[:space:]]+Subtasks/ { in_s=1; next }
  in_s && /^##[[:space:]]/  { in_s=0 }
  in_s && /^\|/             { print }
' "$STATE_FILE")

if [ -z "$ROWS" ]; then
  printf 'VERDICT: CLEAN\nreason: no ## Subtasks rows in state — nothing to contradict\n'
  exit 0
fi

STALE_LINES=""
STALE_COUNT=0
CHECKED=0

# Statuses that already acknowledge the subtask is finished or deliberately closed. Anything else
# (PENDING, IN_PROGRESS, BLOCKED, REVIEW, empty, …) is a claim that work remains.
#
# Match on the FIRST TOKEN only. Real state files annotate the status rather than emitting a bare
# keyword — `DONE (review PASS)` is what Supervisor actually writes (observed 2026-07-27), and
# `COMPLETED WITH ESCALATION` appears in the status enum. An exact-match check false-positived every
# completed subtask as under-reported, which would have refused every legitimate resume: a
# fail-closed gate that never opens is as broken as one that never closes.
is_terminal_status() {
  _first=$(printf '%s' "$1" | awk '{print $1}')
  case "$_first" in
    DONE|DONE:|COMPLETE|COMPLETED|MERGED|FAILED|SKIPPED|ABANDONED) return 0 ;;
    *) return 1 ;;
  esac
}

OLD_IFS="$IFS"
IFS='
'
for row in $ROWS; do
  # Skip the header row and the |---|---| separator.
  case "$row" in
    *---*) continue ;;
  esac

  id=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
  status=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print toupper($4)}')

  # Header row has a non-numeric-ish id like "#" and a status like "STATUS".
  [ -n "$id" ] || continue
  case "$id" in
    '#'|'ID'|'Id') continue ;;
  esac
  [ "$status" = "STATUS" ] && continue

  CHECKED=$((CHECKED + 1))
  is_terminal_status "$status" && continue

  # State says this subtask is NOT finished. Does git disagree?
  if printf '%s\n' "$DONE_IDS" | grep -qx "$id"; then
    STALE_COUNT=$((STALE_COUNT + 1))
    STALE_LINES="${STALE_LINES}stale_subtask: id=${id} state_says=${status:-<empty>} git_says=COMMITTED
"
  fi
done
IFS="$OLD_IFS"

if [ "$CHECKED" -eq 0 ]; then
  printf 'VERDICT: CLEAN\nreason: no parseable subtask rows — nothing to contradict\n'
  exit 0
fi

if [ "$STALE_COUNT" -gt 0 ]; then
  printf 'VERDICT: STALE\n'
  printf 'branch: %s\n' "$BRANCH"
  printf 'rows_checked: %s\n' "$CHECKED"
  printf 'under_reported: %s\n' "$STALE_COUNT"
  printf '%s' "$STALE_LINES"
  printf 'consequence: resuming would re-execute work that is already committed on %s\n' "$BRANCH"
  exit 3
fi

printf 'VERDICT: CLEAN\nbranch: %s\nrows_checked: %s\nunder_reported: 0\n' "$BRANCH" "$CHECKED"
exit 0
