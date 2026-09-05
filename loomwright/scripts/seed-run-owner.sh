#!/usr/bin/env bash
# seed-run-owner.sh — fail-SAFE PostToolUse[Write|Edit] run-owner seed.
#
# INVARIANT: ALWAYS exits 0. Never blocks or slows the originating tool call.
# Same fail-SAFE discipline as emit-progress-event.sh / close-stranded-run.sh
# (see CLAUDE.md §"Failure-Mode Invariants"): `set -u` with NO `set -e`,
# `trap 'exit 0' EXIT`, every failure mode absorbed into a silent no-op.
# It is NOT a gate: it decides nothing, blocks nothing, and the run proceeds
# byte-identically whether or not it writes.
#
# WHY THIS EXISTS
# ----------------
# A run's owner used to become knowable only when the FIRST line of
# `.supervisor/logs/<run_id>.jsonl` was written — and that line does not exist
# until the first worker `SubagentStop`. Between Context-Keeper's `initialize`
# (Phase 0) and that first event — ACQUIRE, PRE-FLIGHT SYNC and PLAN, i.e.
# MINUTES — no owner was recorded anywhere, so nothing could tell a stranded
# run from a live one. `.supervisor/state.md` is REPO-GLOBAL, not
# session-scoped, so both available guesses were wrong:
#
#   * guess "stranded" — any ending session could stamp `status: failed` onto
#     a LIVE run (the false close-out fixed in the previous release), and
#   * guess "live"     — a genuinely stranded run stays `running` forever.
#
# For SLUG-KEYED runs the gap was GUARANTEED rather than incidental:
# `/autonomous` and `/automate` mint a synthetic `auto-{date}-{time}` id that
# is seeded into `state.md`, while a `SessionEnd` payload always carries the
# real Claude Code uuid — so the close-out's unknown-owner self-identification
# test (payload `session_id` == the run id) is structurally unsatisfiable for
# them. This script removes the guess by recording the owner AT RUN CREATION.
#
# WHY A HOOK AND NOT THE AGENT THAT CREATES THE FILE
# ---------------------------------------------------
# The obvious seed — have Context-Keeper's `initialize` write the Claude Code
# session id into `state.md` — puts a fact a HOOK must rely on into an AGENT
# PROMPT. This repo has measured what that costs: 560 hook-written
# `token_ledger` events vs 6 agent-written `phase_transition` events across
# 11+ sessions (docs/PITFALLS.md §"Schema-valid is NOT the same as true").
# An agent also cannot know its own Claude Code session id — the hook payload
# is the only place it appears. So the seed is script-owned and hook-fired,
# and no agent is instructed to remember anything.
#
# WHY THIS TRIGGER (measured, not assumed — 2026-09-05)
# ------------------------------------------------------
# Context-Keeper creates `.supervisor/state.md` with the Write tool (it has no
# Bash — see agents/context-keeper.md's `disallowedTools`), and it runs as a
# SUBAGENT. Both properties this trigger depends on were verified against a
# live headless CLI session before this script was written (docs/TELEMETRY.md
# §"Run ownership" names the exact invocation to re-run — deliberately not
# repeated here, because this file is vendor-coupling CORE):
#
#   * `PostToolUse[Write]` DOES fire for a subagent's Write (observed payload
#     carried `agent_type: general-purpose` and an `agent_id`), and
#   * its `session_id` is BYTE-IDENTICAL to the `SessionEnd` payload's
#     `session_id` for the same CLI session — which is exactly the value
#     `close-stranded-run.sh` compares against later. A subagent does not get
#     an id of its own in the payload.
#
# That makes the trigger causally exact rather than a race: the session that
# WROTE the run's state file is the run's owner by definition, so there is no
# "first observer claims it" window for an unrelated session to win. A seed
# driven by the already-firing `PostToolUse[Bash]` matcher was considered and
# REJECTED for precisely that reason — any session running any Bash command
# would have been an equally good claimant, which re-opens the false
# attribution this exists to close.
#
# WHAT IT WRITES: a SIDECAR, not a log line
# ------------------------------------------
# `.supervisor/logs/<run_id>.owner`, three `key=value` lines:
#
#     cc_session_id=<the Claude Code session that created this run>
#     session_id=<the run id state.md names>
#     started_at=<UTC ISO-8601, the projector's staleness anchor>
#
# A sidecar rather than a zero-event line prepended to the log, for three
# reasons: the log may ALREADY exist and already have a first line by the time
# `state.md` is created (`/autonomous` appends `autonomous_session_start` at
# INIT, before Supervisor runs), so there is no "first line" left to claim; the
# log is append-only and rewriting line 1 is not available; and a sidecar
# introduces no new JSONL event type for `build-insights.sh`,
# `build-loop-evidence.sh`, `build-floor.sh` or any other consumer to grow a
# case for. `.supervisor/logs/` already holds non-JSONL files (`telemetry.log`,
# `notifications.log`, `worktrees.log`, the telemetry `.flag` markers) and
# every consumer globs `*.jsonl` explicitly, so `.owner` is inert to all of
# them.
#
# WRITE-ONCE, and the ordering that follows from it
# --------------------------------------------------
# Creation is atomic via `set -C` (noclobber → O_EXCL): the first writer wins
# and an existing sidecar is NEVER overwritten, so a run's owner cannot change
# under it. Readers (`close-stranded-run.sh`, `build-state.sh`) prefer the
# sidecar OVER the log's first line when both exist, because the sidecar is
# strictly more authoritative: it is written by a hook at the moment the run
# was created and keyed to that run id, whereas the log's first line is
# whoever happened to append first — which, while the owner is unknown, the
# emitters' adopt-on-unknown rule permits a FOREIGN session to be.
#
# This script does NOT weaken that adopt-on-unknown rule and does not touch
# the emitters at all (see docs/TELEMETRY.md §"Run ownership" for the
# emitter-vs-close-out asymmetry, which is unchanged).
#
# COST: this fires after EVERY Write and Edit in EVERY session, so the no-op
# path is ONE `jq` fork (which doubles as the functional jq probe) plus a glob
# on the written path, before git, `pwd -P` or any file read is touched.
#
# No-op (exit 0) when: empty stdin, broken/absent jq, the written path is not
# the main worktree's `.supervisor/state.md`, no `state.md`, no run id in it,
# a TERMINAL run, no `session_id` in the payload, a sidecar that already
# exists, a log whose first line ALREADY records an owner (that owner stands —
# never contradict it), a clock that cannot produce a UTC ISO-8601 instant, or
# an unwritable logs directory.

set -u
# Intentionally NO `set -e` — every failure mode must absorb to exit 0.

trap 'exit 0' EXIT

# ---- Read the PostToolUse payload -------------------------------------------
# COST DISCIPLINE — this fires after EVERY Write and Edit in EVERY session, so
# the no-op path is ONE `jq` fork and then a glob, before anything heavier (git,
# `pwd -P`, any file read) is touched. All three fields come out of a single
# `@tsv` row rather than three separate `jq` invocations, and that same call
# doubles as the FUNCTIONAL jq probe this repo requires — a broken or absent jq
# produces no row, which means no seed, the same fail-safe direction every other
# consumer of this fact takes. `@tsv` escapes any tab or newline inside a value,
# so the row is always exactly one line with exactly two separators.
INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

ROW="$(printf '%s' "$INPUT" \
  | jq -r '[(.tool_input.file_path // ""), (.session_id // ""), (.cwd // "")] | @tsv' 2>/dev/null || true)"
[ -n "$ROW" ] || exit 0
# SPLIT BY PARAMETER EXPANSION, NOT `read`. `IFS=$'\t' read -r a b c` looks
# equivalent and is not: tab is IFS *WHITESPACE*, so `read` COLLAPSES runs of
# it, and a payload carrying no `session_id` (an empty middle field) shifts
# `cwd` left into the owner slot. That does not fail loudly — it records a
# FABRICATED owner built from a directory path, which is precisely the false
# attribution this whole mechanism exists to remove. Measured on a real payload
# before this line was written; case 8c in test-seed-run-owner.sh is the pin.
# `@tsv` guarantees exactly two literal separators and none inside a value, so
# these three expansions are exact and fork-free.
TARGET_PATH="${ROW%%$'\t'*}"
_rest="${ROW#*$'\t'}"
CC_SESSION_ID="${_rest%%$'\t'*}"
PAYLOAD_CWD="${_rest#*$'\t'}"
[ -n "${TARGET_PATH:-}" ] || exit 0

# CHEAP FILTER FIRST. Every write in the repo reaches this line; only a write to
# a `.supervisor/state.md` can possibly be a run creation, and that is a glob
# test with no fork at all. The authoritative check — that this is the MAIN
# worktree's state file and not some other checkout's — is below, after git.
case "$TARGET_PATH" in
  */.supervisor/state.md|.supervisor/state.md) ;;
  *) exit 0 ;;
esac

CC_SESSION_ID="$(printf '%s' "${CC_SESSION_ID:-}" | tr -cd 'A-Za-z0-9_-' || true)"
[ -n "$CC_SESSION_ID" ] || exit 0

# A relative `file_path` is not what the Write tool emits (verified: absolute),
# but resolving one against the payload's own `cwd` costs one line and removes
# the need to assume.
case "$TARGET_PATH" in
  /*) ;;
  *)
    [ -n "${PAYLOAD_CWD:-}" ] || exit 0
    TARGET_PATH="$PAYLOAD_CWD/$TARGET_PATH"
    ;;
esac

# ---- Worktree-safe anchoring (R1 — same idiom as emit-progress-event.sh) -----
# Resolve the MAIN worktree BY NAME: `git worktree list --porcelain`'s first
# entry is always the main worktree, correct from inside any linked worktree
# (including a DETACHED one). NEVER bare `$PWD`. A failed cross-check exits 0 —
# this script never guesses which checkout it is seeding.
main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
[ -n "$main_root" ] && [ -d "$main_root" ] || exit 0
top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
[ "$top" = "$main_root" ] || exit 0

# Canonicalise BOTH sides through `pwd -P` before comparing. macOS resolves
# `/tmp` through a `/private` symlink, so a raw string compare between what git
# reports and what the payload carries can differ for the same file.
main_root_p="$(cd "$main_root" 2>/dev/null && pwd -P)" || exit 0
[ -n "$main_root_p" ] || exit 0
target_dir="$(dirname "$TARGET_PATH")"
[ -d "$target_dir" ] || exit 0
target_dir_p="$(cd "$target_dir" 2>/dev/null && pwd -P)" || exit 0
[ -n "$target_dir_p" ] || exit 0

# The ONLY write this script reacts to is the run's own state file.
[ "$target_dir_p/$(basename "$TARGET_PATH")" = "$main_root_p/.supervisor/state.md" ] || exit 0

LOG_DIR="$main_root/.supervisor/logs"
STATE_MD="$main_root/.supervisor/state.md"
[ -f "$STATE_MD" ] && [ -r "$STATE_MD" ] || exit 0

# ---- Resolve the run this state.md describes --------------------------------
PLUGIN_SESSION_ID="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
PLUGIN_STATUS="$(sed -nE 's/^- status:[[:space:]]*//p' "$STATE_MD" 2>/dev/null | head -1 || true)"
PLUGIN_SESSION_ID="$(printf '%s' "$PLUGIN_SESSION_ID" | tr -cd 'A-Za-z0-9_-' || true)"
[ -n "$PLUGIN_SESSION_ID" ] || exit 0

# Only a run that is still in flight has an owner worth recording. A terminal
# (or unrecognised — never guess) status means there is nothing to close out
# later, so there is nothing for this fact to serve.
case "$PLUGIN_STATUS" in
  running|checkpoint|paused) ;;
  *) exit 0 ;;
esac

OWNER_FILE="$LOG_DIR/${PLUGIN_SESSION_ID}.owner"
# Write-once. An existing sidecar is authoritative and is never rewritten —
# `set -C` below enforces this atomically too; this is the cheap early exit
# that also skips the log read on the overwhelmingly common repeat firing
# (Context-Keeper edits `state.md` many times per run).
[ -e "$OWNER_FILE" ] && exit 0

# ---- Never contradict an owner the log ALREADY records ----------------------
# If the log's first line already carries a `cc_session_id`, that session is
# the established owner under the rule both emitters and the close-out already
# apply (docs/TELEMETRY.md §"Run ownership"). Seeding a sidecar here could
# only ever introduce a SECOND, possibly disagreeing answer — for instance on a
# `/supervisor --continue` resume under a different session, where the original
# owner is recorded and deliberately keeps the log. So: skip.
LOG_FILE="$LOG_DIR/${PLUGIN_SESSION_ID}.jsonl"
if [ -f "$LOG_FILE" ] && [ -r "$LOG_FILE" ]; then
  _first="$(head -1 "$LOG_FILE" 2>/dev/null || true)"
  if [ -n "$_first" ]; then
    _existing_owner="$(printf '%s' "$_first" | jq -r '.cc_session_id // empty' 2>/dev/null || true)"
    [ -n "$_existing_owner" ] && exit 0
  fi
fi

# ---- Timestamp (omit the whole seed when date fails) ------------------------
# `started_at` is not decoration: it is the ONLY staleness anchor a run has
# before its first event, so a sidecar without one cannot serve the backstop.
# Writing a partial record would leave a permanent write-once file that the
# projector can never act on, so refuse instead.
UTC_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
case "$UTC_TS" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
  *) exit 0 ;;
esac

# ---- Write the sidecar, atomically and exactly once -------------------------
# `set -C` (noclobber) makes the redirect an O_EXCL create: if two firings race
# (Context-Keeper's Write and a following Edit, say), exactly one creates the
# file and the other fails harmlessly. ONE `printf` so the record lands in a
# single write rather than three, and every interpolated value is already
# constrained to `[A-Za-z0-9_-]` or the ISO shape checked above — nothing here
# can need quoting or escaping in a `key=value` format.
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
( set -C; printf 'cc_session_id=%s\nsession_id=%s\nstarted_at=%s\n' \
    "$CC_SESSION_ID" "$PLUGIN_SESSION_ID" "$UTC_TS" > "$OWNER_FILE" ) 2>/dev/null || exit 0

exit 0
