#!/usr/bin/env bash
# reproject-state-on-terminal.sh — PostToolUse[Bash] MECHANICAL re-projection
# trigger (PR #116 review Finding 1).
#
# WHY THIS EXISTS
# ----------------
# build-state.sh (the projector) only ever runs when emit-progress-event.sh
# invokes it, and THAT emitter only fires on the `loomwright:worker`
# SubagentStop matcher. Phase 4.5's completion tail appends a `session_end`
# event to the session log directly (agent-written, not via a worker
# completion), and on the Single-Agent Path no `loomwright:worker` runs
# afterward (Phase 4.5 fix tasks spawn as `general-purpose`) — so the
# projector's terminal-status branch never re-fires in production and
# `.supervisor/state.md` sits at `running`/`EXECUTE` for the rest of the run's
# on-disk life. This script is a MECHANICAL fix for that: a hook-triggered
# re-projection, not a prompt instruction telling an agent to re-run the
# projector (a prompt-instructed trigger would reintroduce the exact miss
# rate this whole one-writer mechanism exists to delete — see CLAUDE.md
# §Failure-Mode Invariants and docs/TELEMETRY.md).
#
# Registered as a SECOND `type: command` hook under the EXISTING
# `PostToolUse[Bash]` matcher in hooks.json (alongside
# hook-dispatch-on-pr-create.sh, which already fires on every Bash tool
# call) — no new hook event/matcher was introduced, only a second entry in
# the already-firing matcher's hooks array.
#
# INVARIANT: ALWAYS exits 0 — a PostToolUse[Bash] hook must never break,
# slow, or fail the originating Bash tool call. Same fail-safe contract as
# emit-progress-event.sh / build-state.sh / hook-dispatch-on-pr-create.sh:
# `set -u`, no `set -e`, `trap 'exit 0' EXIT`, every failure mode absorbs to
# a silent no-op.
#
# COST DISCIPLINE — this fires after EVERY Bash tool call in EVERY session,
# so the guard is two cheap, git-free, jq-free text checks BEFORE anything
# heavier is touched:
#   1. `.supervisor/state.md` exists and its `- status:` word is NOT already
#      terminal (one `grep` + `sed` + `awk` over a small file).
#   2. EITHER (2a) the resolved session log's TAIL (last 20 lines, not the
#      whole file) contains the literal string `"session_end"` (one `tail` +
#      `grep -F`), OR — when that log does not exist at all — (2b) the
#      run-creation seed `.supervisor/logs/<id>.owner` is older than
#      `LOOMWRIGHT_STALE_RUN_SECONDS` (one `stat` + one `date`, no jq, no git).
#      2b exists because nothing else can invoke the projector during the
#      pre-first-event window, so a run stranded there by a KILLED terminal —
#      which never reaches `SessionEnd`, so the close-out cannot fire either —
#      would otherwise read `running` on disk forever.
# Only when BOTH checks pass does this script touch git / jq / the full
# projector — i.e. only on a run that has genuinely just gone terminal.
# Measured no-op cost (the overwhelmingly common case — no session_end yet):
# see the PR description / task report for this change; check 1 short-circuits
# before any process fork beyond grep/sed/awk on a file typically under 2KB.
#
# This script does NOT duplicate build-state.sh's evidence-only derivation —
# it only decides WHETHER to invoke the projector; the projector alone owns
# what gets written (including the ordering rule from Finding 1's second
# half, and the lock/permissions/preservation fixes from Findings 2-4).

set -u
trap 'exit 0' EXIT

STATE_MD=".supervisor/state.md"
[ -f "$STATE_MD" ] || exit 0

# ---- Cheap check 1: bail if state.md is already terminal --------------------
status_word="$(grep -m1 -iE '^- (\*\*)?status:' "$STATE_MD" 2>/dev/null \
  | sed -E 's/\*\*//g' \
  | sed -E 's/^- [Ss][Tt][Aa][Tt][Uu][Ss]:[[:space:]]*//' \
  | awk '{print $1}' || true)"
case "$status_word" in
  completed|completed_with_escalation|failed) exit 0 ;;   # already terminal — nothing to do
esac

# ---- Resolve the session id state.md itself carries -------------------------
session_id="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
session_id="$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-' || true)"
[ -n "$session_id" ] || exit 0

LOG_FILE=".supervisor/logs/${session_id}.jsonl"
OWNER_FILE=".supervisor/logs/${session_id}.owner"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
  # ---- Cheap check 2a: does the log's TAIL carry a session_end event? -------
  # A tail scan (not a full-file jq parse) is sufficient for the GUARD — the
  # projector itself does the authoritative full-file evidence-only derivation
  # (including the ordering rule) once this guard passes. A string match on
  # `"session_end"` is deliberately loose about JSON key order (session_end is
  # agent-constructed JSON, not guaranteed to serialize `event` first); any
  # false-positive guard pass just costs one harmless, idempotent
  # build-state.sh invocation, never an incorrect write.
  if ! tail -20 "$LOG_FILE" 2>/dev/null | grep -qF '"session_end"'; then
    exit 0
  fi
else
  # ---- Cheap check 2b: a run stranded BEFORE its first event ----------------
  # No log means the run never got past the ACQUIRE → PRE-FLIGHT SYNC → PLAN
  # window. Nothing else ever invokes the projector there — check 2a needs a
  # log, and both emitters need a worker completion — so without this arm a run
  # whose terminal was KILLED (never reaching `SessionEnd`, so the close-out
  # cannot fire either) stays `running` on disk permanently, and every later
  # session reads that repo-global lie.
  #
  # The guard is the run-creation seed's AGE via `stat` — no jq, no git, no
  # date parsing. It is deliberately only a guard: `build-state.sh` re-decides
  # from the seed's `started_at` field and owns the verdict, exactly as check 2a
  # only decides WHETHER to invoke the projector. mtime is a sound proxy here
  # because the seed is write-once — `seed-run-owner.sh` never rewrites it.
  #
  # This arm is reached only while state.md is non-terminal AND no log exists;
  # once the projector flips the run to `failed`, check 1 short-circuits above
  # and this costs nothing again.
  [ -f "$OWNER_FILE" ] || exit 0
  stale_seconds="${LOOMWRIGHT_STALE_RUN_SECONDS:-86400}"
  case "$stale_seconds" in
    ''|*[!0-9]*) stale_seconds=86400 ;;   # non-integer override → default (same rule as the projector)
  esac
  # GNU first, then BSD — never assume a flavor. GNU `stat -f` SUCCEEDS while
  # printing a filesystem dump, so a BSD-first probe captures garbage on Linux;
  # the numeric guards below catch it either way. (Repo convention — this
  # divergence has already shipped a Linux-CI failure here.)
  seed_mtime="$(stat -c %Y "$OWNER_FILE" 2>/dev/null)"
  case "$seed_mtime" in
    ''|*[!0-9]*) seed_mtime="$(stat -f %m "$OWNER_FILE" 2>/dev/null)" ;;
  esac
  now_epoch="$(date +%s 2>/dev/null)"
  case "$seed_mtime" in ''|*[!0-9]*) exit 0 ;; esac
  case "$now_epoch"  in ''|*[!0-9]*) exit 0 ;; esac
  [ "$((now_epoch - seed_mtime))" -ge "$stale_seconds" ] || exit 0
fi

# ---- Guard passed — invoke the projector (heavier work only from here) -----
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
[ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/build-state.sh" ] || exit 0

bash "$SCRIPT_DIR/build-state.sh" "$session_id" || true

exit 0
