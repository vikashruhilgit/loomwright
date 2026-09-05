#!/usr/bin/env bash
# close-stranded-run.sh — fail-SAFE SessionEnd close-out emitter.
#
# INVARIANT: ALWAYS exits 0. Never blocks session teardown. Same fail-SAFE
# discipline as emit-token-ledger.sh / emit-progress-event.sh (see CLAUDE.md
# §"Failure-Mode Invariants"): `set -u` with NO `set -e`, `trap 'exit 0' EXIT`,
# and every failure mode absorbed.
#
# WHY THIS EXISTS
# ----------------
# `.supervisor/state.md` only ever reaches a terminal status when an agent
# remembers to write a `session_end` event. This repo's own logs measure what
# that costs: a run started 2026-07-29 ended without emitting one, so its
# `status: running` stayed on disk indefinitely — and because both emitters
# adopt the plugin session id whenever the status is `running`/`checkpoint`,
# every LATER session's SubagentStop appended to that finished run's log
# (measured: 14,416 lines, 3.9 MB, 140 distinct `cc_session_id`s in one file).
# build-state.sh then re-derived `running` from the newest FOREIGN
# `subtask_complete` in that same log, so the stale status caused the fan-in and
# the fan-in re-asserted the stale status.
#
# The run-ownership gate in both emitters stops the fan-in. THIS script closes
# the other half: a session that ends without completing now says so
# MECHANICALLY, with no agent instructed to remember it.
#
# NOT a duplicate of reproject-state-on-terminal.sh (commit 8fd508f). That
# script re-projects terminal status once a `session_end` LANDS; it never fires
# in this failure mode precisely because no `session_end` ever lands. This one
# writes the missing `session_end`; the two are complementary.
#
# BEHAVIOR
# --------
# Writes exactly ONE `session_end` event (`status: failed`,
# `reason: session_ended_without_completion`) and re-projects via build-state.sh
# when ALL of the following hold:
#   0. the SessionEnd `reason` is NOT `clear` (see the deny-list guard below —
#      absent/empty/unparseable reason satisfies this), and
#   1. `.supervisor/state.md` exists at the MAIN worktree, and
#   2. its `- status:` is NON-TERMINAL (running | checkpoint | paused), and
#   3. THIS session is the recorded owner of that run's log.
# Anything else — a `clear`, a terminal status, no state.md, a non-owner
# session — writes NOTHING and exits 0.
#
# `failed` is the ONLY status this emits. `paused` is deliberately never used:
# it is classified LIVE by hook-dispatch-on-pr-create.sh and DEAD by both
# emitters, so emitting it would mean two consumers disagreeing about the same
# file (frozen decision D2). `failed` is a member of the closed status enum at
# skills/state-management/SKILL.md §"State File Schema" and reads correctly —
# the run ended without completing.
#
# OWNERSHIP is resolved from TWO sources, seed first:
#
#   1. `.supervisor/logs/<run_id>.owner` — the run-creation seed written by
#      `seed-run-owner.sh` at the moment `state.md` is created. This is what
#      makes ownership knowable during the ACQUIRE → PRE-FLIGHT SYNC → PLAN
#      window, before any log line exists.
#   2. the log's FIRST line — the same `loom_log_owner` rule the two emitters
#      use, and the only source that existed before the seed.
#
# On top of whichever answers, this writer makes ONE additional demand the
# emitters deliberately do not:
#
#   owner recorded      → only that `cc_session_id` may close the run out.
#   owner NOT recorded  → adoptable ONLY by a session whose payload
#                         `session_id` EQUALS the run id `state.md` names.
#
# The emitters ADOPT unconditionally on an unknown owner and still do; that is
# non-negotiable 2, and its protected property is their fresh-run bootstrap.
# This script is different in kind: it is the only writer that can mark a LIVE
# run dead. `.supervisor/state.md` is REPO-GLOBAL, so before a run's first
# worker completion creates its log there is no owner to compare against, and
# unconditional adoption let any unrelated ending session close out a run it
# had no connection to. Requiring self-identification closes that without
# touching the emitters. The unknown-owner rule above is what a run with NO
# seed and no log line still falls back to — pre-seed runs, and any run whose
# `state.md` was not created through the Write/Edit tool path the seed hook
# watches. It is no longer the main path for slug-keyed runs: those now have a
# seed, so they take the known-owner branch. See docs/TELEMETRY.md
# §"Honest limits" entry 9 for what remains.
#
# No-op (exit 0) when: the SessionEnd reason is `clear`, main worktree
# unresolvable, not a git repo, no state.md, terminal status, non-owner
# session, no plugin session id, broken/absent jq, unwritable log.
#
# KNOWN, DELIBERATE GAP: an owning session whose SessionEnd payload arrives
# EMPTY or UNPARSEABLE cannot be proven to be the owner, so a run with a KNOWN
# (non-empty) log owner is NOT closed out and stays stranded until the
# staleness backstop fires. Documented in docs/TELEMETRY.md §"Honest limits"
# entry 8; pinned by case 4j in test-close-stranded-run.sh.
#
# Authoritative spec: this repo's 2026-09-05 brief
# (.supervisor/jobs/*/auto-2026-09-05-121712-run-ownership-and-session-close-out.md).

set -u
# Intentionally NO `set -e` — every failure mode must absorb to exit 0.

trap 'exit 0' EXIT

# ---- Read the SessionEnd payload (may legitimately be empty) -----------------
INPUT="$(cat 2>/dev/null || true)"

# ---- Scope: `/clear` is NOT a session termination ---------------------------
# `SessionEnd` fires for `clear` as well as for real termination, and
# `cc_session_id` is STABLE across `/clear` within one CLI process. So a
# user running `/clear` mid-run — ordinary context hygiene during a long
# autonomous loop — presents a NON-TERMINAL state.md whose log owner MATCHES,
# i.e. every condition below is satisfied, and this script would stamp
# `status: failed` onto a run that is still very much alive. That corrupts
# state in the OPPOSITE direction from the fan-in this script exists to close.
#
# Defense in depth, layer 2 of 2: `hooks.json` scopes the registration to
# `"matcher": "logout|prompt_input_exit|other"` (the same scoping the earlier
# design work already chose for a different SessionEnd hook — see
# docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md §2.4). This in-script guard is the
# second layer, so a harness that ignores the matcher still cannot corrupt a
# live run.
#
# DENY-LIST, NEVER AN ALLOW-LIST. Only the exact string `clear` suppresses;
# an ABSENT, EMPTY, or UNPARSEABLE reason PROCEEDS. Requiring the reason to be
# a member of {logout,prompt_input_exit,other} would make a payload with no
# `reason` field skip — and that is the main path, not an edge case. The
# failure directions are asymmetric and settle the default: a run left
# stranded is RECOVERABLE (build-state.sh's `LOOMWRIGHT_STALE_RUN_SECONDS`
# backstop closes it, see docs/TELEMETRY.md §"Run ownership"), whereas a live
# run wrongly marked `failed` is not.
#
# Probe jq FUNCTIONALLY, never `command -v` alone — same idiom as below. A
# broken or absent jq yields no reason and therefore PROCEEDS, which is the
# safe direction by the asymmetry above.
if printf '{}' | jq -e . >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  END_REASON="$(printf '%s' "$INPUT" | jq -r '.reason // empty' 2>/dev/null || true)"
  case "${END_REASON:-}" in
    clear) exit 0 ;;
  esac
fi

# ---- Worktree-safe anchoring (R1 — same idiom as emit-progress-event.sh) -----
# Resolve the MAIN worktree BY NAME: `git worktree list --porcelain`'s first
# entry is always the main worktree, correct from inside any linked worktree
# (including a DETACHED one) and unaffected by --separate-git-dir/submodule
# layouts. NEVER bare `$PWD`, NEVER bare `git branch --show-current` (returns
# EMPTY inside a detached worktree). A failed cross-check exits 0 — this script
# never guesses which checkout it is closing out.
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] && [ -d "$main_root" ] || exit 0
top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
[ "$top" = "$main_root" ] || exit 0

LOG_DIR="$main_root/.supervisor/logs"
STATE_MD="$main_root/.supervisor/state.md"

[ -f "$STATE_MD" ] && [ -r "$STATE_MD" ] || exit 0

# ---- Resolve the run this state.md describes --------------------------------
PLUGIN_SESSION_ID="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
PLUGIN_STATUS="$(sed -nE 's/^- status:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
PLUGIN_SESSION_ID="$(printf '%s' "$PLUGIN_SESSION_ID" | tr -cd 'A-Za-z0-9_-' || true)"
[ -n "$PLUGIN_SESSION_ID" ] || exit 0

# Only a NON-TERMINAL run can be stranded. An already-terminal status (or an
# unrecognized one — never guess) writes nothing.
case "$PLUGIN_STATUS" in
  running|checkpoint|paused) ;;
  *) exit 0 ;;
esac

LOG_FILE="$LOG_DIR/${PLUGIN_SESSION_ID}.jsonl"
OWNER_FILE="$LOG_DIR/${PLUGIN_SESSION_ID}.owner"

# ---- Ownership, source 1: the run-creation seed -----------------------------
# `seed-run-owner.sh` (PostToolUse[Write|Edit]) records the owning Claude Code
# session id the moment `.supervisor/state.md` is created, which is what makes
# ownership knowable BEFORE the first worker completion writes the log's first
# line. Read that file's header for why the seed is script-owned rather than
# written by the agent that creates `state.md`.
#
# Plain `key=value`, so this reader needs no jq. That is deliberate: it means a
# jq-less host can still learn WHO owns a run. It changes nothing about what
# such a host DOES, because the ending session's own id still comes from the
# JSON payload via jq — with no jq the known-owner branch below is taken with
# an empty `CC_SESSION_ID` and this script withholds, exactly as before.
#
# KEPT BYTE-IDENTICAL to the copy in build-state.sh — change them together.
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

# ---- Ownership, source 2: the log's first line ------------------------------
# (identical rule to both emitters' loom_log_owner)
loom_log_owner() {
  # Echo the `cc_session_id` on the FIRST line of the given log, or NOTHING
  # when no owner is recorded. Always returns 0.
  local _log="${1:-}" _first=""
  [ -n "$_log" ] && [ -f "$_log" ] && [ -r "$_log" ] || return 0
  _first="$(head -1 "$_log" 2>/dev/null || true)"
  [ -n "$_first" ] || return 0
  # Probe jq FUNCTIONALLY, never `command -v` alone.
  printf '{}' | jq -e . >/dev/null 2>&1 || return 0
  printf '%s' "$_first" | jq -r '.cc_session_id // empty' 2>/dev/null || true
  return 0
}

CC_SESSION_ID=""
if printf '{}' | jq -e . >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  CC_SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  CC_SESSION_ID="$(printf '%s' "$CC_SESSION_ID" | tr -cd 'A-Za-z0-9_-' || true)"
fi

# The SEED WINS when both sources exist, and the precedence is load-bearing
# rather than arbitrary. The seed is written by a hook at the moment the run was
# created and is keyed to that run id; the log's first line is merely whoever
# appended first — and while the owner is unknown, the emitters'
# adopt-on-unknown rule explicitly permits that to be a FOREIGN session. Where
# the two disagree, the disagreement IS the foreign-append case, and the seed is
# the one that is right. `seed-run-owner.sh` never writes a seed for a run whose
# log already records an owner, so the two can only diverge that way round.
LOG_OWNER="$(loom_run_owner_seed "$OWNER_FILE" || true)"
if [ -z "$LOG_OWNER" ]; then
  LOG_OWNER="$(loom_log_owner "$LOG_FILE" || true)"
fi
LOG_OWNER="$(printf '%s' "$LOG_OWNER" | tr -cd 'A-Za-z0-9_-' || true)"

if [ -n "$LOG_OWNER" ]; then
  # An owner IS recorded. Only that session may close this run out.
  if [ "$LOG_OWNER" != "$CC_SESSION_ID" ]; then
    # A DIFFERENT session owns this run — it is still in flight from someone
    # else's point of view. Write nothing.
    exit 0
  fi
else
  # NO owner is recorded (absent/empty/unreadable log, unparseable first line,
  # or a first line with no `cc_session_id`). Adopting unconditionally here —
  # the behaviour that shipped first — let ANY ending session close out a run
  # it has no connection to, because `.supervisor/state.md` is REPO-GLOBAL, not
  # session-scoped: every session anchored to the same main worktree reads the
  # same `- session_id:` / `- status: running`. Session A starts a run; before
  # A's first worker completion creates `logs/<id>.jsonl` there is no owner to
  # compare against, so an unrelated session B merely ENDING would stamp
  # `status: failed` onto A's live run and leave a fabricated hard-signal
  # `session_end` (which build-insights.sh consumes) that nothing retracts.
  # That is the same false-attribution class this script exists to remove.
  #
  # So an unknown owner is adoptable ONLY by a session that can identify itself
  # AS this run: the payload `session_id` must equal the run id `state.md`
  # names. A session that cannot prove that writes nothing.
  #
  # This does NOT weaken non-negotiable 2, whose protected property is the
  # EMITTERS' fresh-run bootstrap — "the first worker completion of a fresh run
  # joins on the seeded plugin id" (agents/context-keeper.md). That property
  # lives in emit-progress-event.sh / emit-token-ledger.sh, which are unchanged
  # and still ADOPT on unknown owner. Only this close-out — the one writer here
  # that can mark a LIVE run dead — additionally demands self-identification.
  #
  # Failure direction is the same asymmetry the `clear` guard settles above: a
  # run left stranded is RECOVERABLE, a live run wrongly marked `failed` is not.
  if [ -z "$CC_SESSION_ID" ] || [ "$CC_SESSION_ID" != "$PLUGIN_SESSION_ID" ]; then
    exit 0
  fi
fi

# ---- Idempotency: never append a SECOND session_end -------------------------
# Cheap TAIL guard, deliberately the same shape as the one
# reproject-state-on-terminal.sh already uses (a `tail` plus a literal match —
# no jq, no full-file parse): if the log's last parsable line already carries a
# session_end, this run has been closed out and a second closing event would be
# a duplicate hard signal for build-insights.sh and a second terminal record
# for build-state.sh. Blank trailing lines are skipped so a stray newline
# cannot defeat the guard. Any read failure yields an empty LAST_LINE and falls
# through to the normal append path — fail-safe, and it can never exit non-zero.
LAST_LINE="$(tail -5 "$LOG_FILE" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1 || true)"
case "${LAST_LINE:-}" in
  *'"session_end"'*) exit 0 ;;
esac

# ---- Timestamp (omit entirely when date fails — never the literal "unknown")
UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
case "$UTC_TS" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
  *) UTC_TS="" ;;
esac

# ---- Append exactly ONE session_end event -----------------------------------
# BOTH keys are mandatory and both are valued "session_end": build-state.sh
# filters on the canonical `.event`, and build-insights.sh's hard-signal reader
# also consumes the legacy `.type` — see docs/RESULT_SCHEMAS.md §"`session_end`
# JSONL hard-signal fields". Omitting either silently breaks a live consumer.
#
# Built with printf rather than jq/python3 because every interpolated value is
# already constrained to [A-Za-z0-9_-] (the two session ids) or is a literal —
# so there is nothing here that can need JSON escaping, and the append works
# even with no interpreter available.
LINE="{\"event\":\"session_end\",\"type\":\"session_end\",\"session_id\":\"${PLUGIN_SESSION_ID}\""
if [ -n "$CC_SESSION_ID" ]; then
  LINE="${LINE},\"cc_session_id\":\"${CC_SESSION_ID}\""
fi
LINE="${LINE},\"status\":\"failed\",\"reason\":\"session_ended_without_completion\""
if [ -n "$UTC_TS" ]; then
  LINE="${LINE},\"ts\":\"${UTC_TS}\""
fi
LINE="${LINE}}"

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
printf '%s\n' "$LINE" >> "$LOG_FILE" 2>/dev/null || exit 0

# ---- Re-project so state.md reaches a terminal status immediately -----------
# Best-effort — build-state.sh carries the identical always-exit-0 contract, so
# this can never affect this script's own.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/build-state.sh" ]; then
  bash "$SCRIPT_DIR/build-state.sh" "$PLUGIN_SESSION_ID" "$main_root" || true
fi

exit 0
