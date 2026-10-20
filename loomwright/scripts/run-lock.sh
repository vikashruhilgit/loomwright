#!/usr/bin/env bash
# run-lock.sh — single-run-per-repo lock for `/automate`, `/autonomous`, and
# `/supervisor`. Makes "two runs in one checkout" structurally impossible
# (rather than merely documented) — see automate-loop/SKILL.md §11.
#
# Usage:
#   run-lock.sh acquire --owner <label> [--session-id <id>] [--root <checkout>] [--force-unlock]
#   run-lock.sh release --owner <label> | --session-id <id> [--root <checkout>] [--force-unlock]
#   run-lock.sh status  [--root <checkout>]
#   run-lock.sh liveness [--pid <pid>] [--root <checkout>]
#
# Lock: <root>/.supervisor/run.lock          (a directory — `mkdir` is atomic
#                                              on every POSIX filesystem, the
#                                              same primitive dispatch-pr-review.sh's
#                                              acquire_lock already uses; no
#                                              flock on stock macOS)
# Meta: <root>/.supervisor/run.lock/meta     (TSV `key<TAB>value` lines —
#                                              NOT JSON, matching
#                                              dispatch-pr-review.sh's
#                                              write_lock_meta convention):
#         pid, owner, session_id, ts, pid_source[, pid_start]
#       The first five keys keep their names and this order (session-resume.sh
#       reads `pid` with its own awk); `pid_start` is appended after them.
#
# `pid` is the HOLDER's liveness pid — NOT this script's `$$` (which is dead
# the instant `acquire` returns, so every lock looked "dead pid" immediately
# and degraded to a bare 1800s lease). The Bash-tool shell that invokes this
# script also exits after each call, so `$PPID` is no better there; the
# process that lives as long as the run is the harness's own process (the
# session's `claude` under Claude Code). No tier ever records a pid that
# `kill -0` may never report dead (is_holder_pid): 0 (`kill -0 0` signals the
# caller's own process group, so it always "lives"), a leading zero, or 1
# (init — alive forever wherever the caller may signal it, e.g. as root in a
# CI container; EPERM elsewhere) — such a lock could never be reclaimed.
# Resolution order (recorded as `pid_source`):
#   1. `holder_env` — `$LOOMWRIGHT_HOLDER_PID` when numeric and alive. The
#      vendor-neutral way for ANY harness (a CI job, a script, a close-out
#      that must hold the lock itself) to name the process the lock lives as
#      long as. A dead or non-numeric value, 0, a leading zero, or 1 is
#      ignored (falls through).
#   2. `claude_pid` — `$CLAUDE_PID` when numeric and alive; 0, a leading zero
#      or 1 is ignored the same way (none is a real `claude`). Evidence: observed
#      2026-09-26 on Claude Code 2.1.281 (Desktop), `CLAUDE_PID` in a Bash-tool
#      shell = that shell's own parent = the `claude` binary. It is NOT in the
#      public env-var docs, so it is never the only line of defence:
#   3. `ancestor` — under ANY harness (the walk has no harness gate), the first
#      ancestor of this script that is neither a shell (sh/bash/zsh/dash/ksh/
#      fish) nor a WRAPPER (is_wrapper_comm: a process that only runs the
#      command below it), walking up from `$PPID` for at most 8 steps. Under
#      Claude Code that is `claude`; survives `CLAUDE_PID` being dropped or
#      renamed by a future release. The walk STOPS (falls to 4) at a SESSION
#      HOST (is_session_host_comm: a terminal multiplexer, login or terminal
#      app that outlives any one run), at pid 1, or when `ps` yields nothing —
#      a host is never recorded, so a run that crashed under one stays
#      TTL-reclaimable.
#   4. `ppid` — otherwise the invoking shell. The lock is then DEGRADED to the
#      1800s TTL: `acquire` (and `status` on such a lock) prints one STDERR
#      line `run_lock_degraded: pid_source=ppid ttl_only=1800s`; stdout and
#      the exit code are unchanged. Set LOOMWRIGHT_HOLDER_PID to avoid it.
#      When `$PPID` itself is no holder pid — 1 (the script was orphaned to
#      init before bash read its parent, a double fork) or 0 (a parent outside
#      the pid namespace, e.g. `docker exec`) — `pid` is recorded EMPTY, with
#      no `pid_start`: no holder, so `holder_alive` reads dead and reclaim
#      needs only age >= 1800s; `status` prints `pid=` and `liveness` prints
#      `unknown`. Never `$$` instead: it is dead the instant `acquire` returns,
#      which an empty pid states honestly rather than through a fake pid.
# Honest limits of the walk: a long-lived non-shell that is not the run (a CI
# runner agent, an IDE) IS recorded — name the right process with
# LOOMWRIGHT_HOLDER_PID; names are matched exactly after the basename +
# leading-`-` strip, so a host whose `comm` differs from the closed list is
# recorded as `ancestor`.
#
# `pid_start` fingerprints the holder: `env TZ=UTC0 LC_ALL=C ps -o lstart=
# -p <pid>`, surrounding whitespace trimmed, written only when non-empty.
# `ps` prints `lstart` in the caller's local time, so both TZ and the locale
# are pinned — a writer and a comparer in sessions with different TZ (or
# LC_*) settings read the same string. The recorded pid is alive only when
# `kill -0` succeeds AND (meta has no `pid_start`, OR the pid's current
# `lstart` equals it) — so a pid the OS reused for an unrelated process reads
# dead. That ONE rule is `holder_alive`; reclaim reads it, and `liveness`
# prints it for every other reader that judges the holder (session-resume.sh's
# stale-lock line, automate-trail.sh's closeout refusal). No script outside
# this file probes a run.lock meta pid with its own `kill -0` — readers that
# only read `owner`/`session_id` (guard-lane-wait-armed.sh, `status` callers)
# make no liveness call and are not copies of the rule.
# Honest limits: a live pid whose `lstart` cannot be read now, while meta
# holds a `pid_start`, compares unequal and reads dead. On Linux, procps
# derives `lstart` from the boot time plus the process's start ticks, and the
# boot time follows the wall clock, so a wall-clock STEP (an NTP step, a VM
# resume) can shift a running holder's `lstart`: it then reads dead too. In
# both cases reclaim still also needs age >= 1800s, and a re-entrant acquire
# re-stamps `pid_start`.
#
# Observed 2026-09-26 (automate-2026-09-26-115755): automate PICK recorded its
# own shell pid, launch-pad ran ~28 min, and Supervisor Phase 0's acquire
# (different owner) reclaimed the "dead-pid + >=1800s" lock as stale.
#
# This is a NEW lock, not a call into dispatch-pr-review.sh's acquire_lock —
# that function's meta shape carries no `session_id`/`owner` fields and its
# lock dir is scoped to a per-PR hash (a different namespace: one dispatch
# lock per PR vs. one run lock per REPO). The mkdir-atomicity + TSV-meta +
# pid-liveness + TTL-reclaim SHAPE is mirrored deliberately (see the
# `write_lock_meta`/`acquire_lock` pair in dispatch-pr-review.sh:630
# [pins: `write_lock_meta`]) so both locks fail exactly the same way
# under a crashed holder.
#
# acquire:
#   Success: exits 0, prints nothing (fresh acquire or reclaim), or one
#     `run_lock_reentrant ...` line (re-entrant, below).
#   Held (and not reclaimable): prints
#     `run_lock_held owner=<label> pid=<pid> age=<s>`
#   to stdout and exits 1 — NEVER proceeds silently (fail CLOSED). The
#   caller (automate PICK / Supervisor Phase 0 INIT / /autonomous INIT) must
#   park on this, not retry into a spin.
#   Re-entrant: when the lock is held and `--session-id` equals the recorded
#     `session_id`, acquire SUCCEEDS without changing the recorded `owner`
#     and prints `run_lock_reentrant owner=<outer> session_id=<id>`. This is
#     the nested-entry case — /automate RUN inlines /autonomous, which inlines
#     /supervisor, all in ONE session — made explicit instead of relying on an
#     accidental stale-reclaim. Keeping the OUTER owner means the inner run's
#     own `release --owner <inner>` is a no-op, so the lock is held until the
#     outermost run releases it. The refresh re-stamps `pid`/`ts` (a nested
#     acquire doubles as a liveness heartbeat). An empty `--session-id` never
#     re-enters. Cooperative, like the rest of this lock: a caller that lies
#     about its session id can re-enter, exactly as it could `--force-unlock`.
#   Cross-session re-entrant (fresh session per phase): when the lock is held
#     and LOOMWRIGHT_RUN_LOCK_SESSION_ID is non-empty and equals the recorded
#     `session_id`, acquire SUCCEEDS with the same `run_lock_reentrant
#     owner=<outer> session_id=<recorded id>` line and writes NOTHING (owner,
#     session_id and holder pid stay the coordinator's). automate-lanes.sh
#     `phase-launch` sets it to the coordinator's session id for a phase
#     session; a lane spawn strips it. `release` never reads it, so a phase
#     session's own release (its owner / its session id) is a no-op and only
#     the coordinator frees the lock.
#   Reclaim: fires ONLY when BOTH the recorded pid is dead (a `pid_start`
#   mismatch counts as dead — see `pid_start` above) AND
#   age >= LOCK_TTL_SECONDS (1800s) — a dead pid alone, or a young lock
#   alone, both refuse (matches dispatch-pr-review.sh's acquire_lock TTL
#   contract exactly).
#   Degraded: any successful acquire (fresh, reclaim, re-entrant refresh)
#   that recorded `pid_source ppid` also prints `run_lock_degraded: …` to
#   STDERR (never stdout).
#
# release:
#   Idempotent no-op success (exit 0) when the lock is already absent, or
#   when neither --owner nor --session-id matches the lock's recorded
#   owner/session_id (never silently steals a lock you don't hold).
#   Releases when --owner matches the recorded `owner`, OR --session-id
#   matches the recorded `session_id` — the latter is what lets
#   close-stranded-run.sh release-by-ending-session without knowing the
#   owner label the acquirer used.
#
# --force-unlock (human-only escape hatch): breaks the lock unconditionally
#   (whether or not it is reclaimable) and prints what it broke, before
#   acquiring/releasing. This script does not gate WHO may pass the flag —
#   that authorization belongs to the caller (never invoked by an agent
#   without an explicit human instruction — see docs/PITFALLS.md).
#
# status: prints `LOCKED owner=<label> pid=<pid> age=<s>` or `UNLOCKED`; a
#   held lock whose meta reads `pid_source ppid` also gets the
#   `run_lock_degraded: …` line on STDERR.
#
# liveness: prints exactly one of `alive`, `dead` (the `holder_alive` verdict
#   on the recorded pid + pid_start) or `unknown` (no lock, or no recorded
#   pid); always exits 0. Read-only — never acquires, refreshes or reclaims.
#   `--pid <pid>` binds the verdict to ONE holder: when the lock now records a
#   different pid (the holder a caller saw refused it has since released, and
#   another took the lock), it prints `dead`, never the newcomer's `alive` —
#   a caller judging a refusal fails toward "not running". A non-numeric
#   `--pid` is a usage error.
#
# Honest limit: this lock protects only entry points that actually RUN this
# script (automate PICK, Supervisor Phase 0 INIT, /autonomous INIT). It does
# NOT protect against an IDE-hosted agent, or any other process, that edits
# the checkout without going through one of those entry points — see
# docs/PITFALLS.md "Run lock does not see an IDE-hosted agent".

set -u
LOCK_TTL_SECONDS=1800

die_usage() {
  {
    echo "usage: run-lock.sh acquire --owner <label> [--session-id <id>] [--root <dir>] [--force-unlock]"
    echo "       run-lock.sh release --owner <label> | --session-id <id> [--root <dir>] [--force-unlock]"
    echo "       run-lock.sh status  [--root <dir>]"
    echo "       run-lock.sh liveness [--pid <pid>] [--root <dir>]"
  } >&2
  exit 1
}

CMD="${1:-}"
[ -n "$CMD" ] || die_usage
shift || true

OWNER=""
SESSION_ID=""
ROOT=""
FORCE=0
EXPECT_PID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)        OWNER="${2:-}"; shift 2 ;;
    --session-id)   SESSION_ID="${2:-}"; shift 2 ;;
    --root)         ROOT="${2:-}"; shift 2 ;;
    --force-unlock) FORCE=1; shift ;;
    --pid)          EXPECT_PID="${2:-}"; shift 2 ;;
    -h|--help)      die_usage ;;
    *)              die_usage ;;
  esac
done

# ---- resolve root (mirrors emit-token-ledger.sh / read-token-ledger.sh) ----
if [ -z "$ROOT" ]; then
  main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  if [ -n "$main_root" ] && [ -d "$main_root" ]; then
    top="$(git -C "$main_root" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
    [ "$top" = "$main_root" ] || main_root=""
  fi
  [ -n "$main_root" ] || main_root="$PWD"
  ROOT="$main_root"
fi

LOCK_DIR="${ROOT}/.supervisor/run.lock"
LOCK_META="${LOCK_DIR}/meta"

meta_get() {
  local key="$1"
  [ -f "$LOCK_META" ] || return 0
  awk -F'\t' -v k="$key" '$1==k{print $2; exit}' "$LOCK_META" 2>/dev/null
}

now_epoch() { date +%s 2>/dev/null || echo 0; }

lock_age() {
  local lk_ts now
  lk_ts="$(meta_get ts)"
  now="$(now_epoch)"
  if [ -n "$lk_ts" ] && [ "$lk_ts" -ge 0 ] 2>/dev/null; then
    echo $((now - lk_ts))
  else
    echo -1
  fi
}

is_shell_comm() {
  local c="${1##*/}"
  c="${c#-}"   # login shells show as -zsh / -bash
  case "$c" in sh|bash|zsh|dash|ksh|fish) return 0 ;; esac
  return 1
}

# is_wrapper_comm — a process that only runs the command below it; the walk
# steps past it like a shell. Closed list, owned here (docs point to it).
is_wrapper_comm() {
  local c="${1##*/}"
  c="${c#-}"
  case "$c" in env|timeout|xargs|sudo) return 0 ;; esac
  return 1
}

# is_session_host_comm — a process that outlives any one run (a terminal
# multiplexer, a login, a terminal app); the walk STOPS at it and never
# records it. Closed list, owned here (docs point to it).
is_session_host_comm() {
  local c="${1##*/}"
  c="${c#-}"
  case "$c" in tmux|screen|sshd|login|Terminal|iTerm2) return 0 ;; esac
  return 1
}

# proc_lstart <pid> — the pid's start time (`lstart`, pinned to UTC and the C
# locale via `env`, never a bare prefix — check-locale-prefix.sh), surrounding
# whitespace trimmed; empty when `ps` yields nothing. The `pid_start` value.
proc_lstart() {
  env TZ=UTC0 LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -n 1
}

# holder_alive <pid> <pid_start> — THE liveness rule (header, `pid_start`):
# `kill -0` succeeds AND (no recorded pid_start, OR the pid's current lstart
# equals it). Read by acquire's reclaim and by `liveness`.
holder_alive() {
  local pid="${1:-}" start="${2:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  if [ -n "$start" ] && [ "$(proc_lstart "$pid")" != "$start" ]; then
    return 1   # pid_start mismatch: the pid was reused
  fi
  return 0
}

# is_holder_pid <v> — true when <v> may be recorded as a holder: decimal, no
# leading zero, > 1. 0 (kill -0 0 signals our own process group, so it always
# "lives"), a leading zero, and 1 (init; alive to `kill -0` as root) never
# are — one rule for every tier.
is_holder_pid() {
  case "${1:-}" in ''|*[!0-9]*|0*|1) return 1 ;; esac
  return 0
}

# holder_pid — prints `<pid> <pid_source>`, the liveness pid recorded in meta
# (resolution order in the header); `-` in place of the pid means "no holder"
# (an empty `pid`, header tier 4).
holder_pid() {
  if is_holder_pid "${LOOMWRIGHT_HOLDER_PID:-}" && kill -0 "$LOOMWRIGHT_HOLDER_PID" 2>/dev/null; then
    echo "$LOOMWRIGHT_HOLDER_PID holder_env"; return
  fi
  if is_holder_pid "${CLAUDE_PID:-}" && kill -0 "$CLAUDE_PID" 2>/dev/null; then
    echo "$CLAUDE_PID claude_pid"; return
  fi
  # The ancestor walk — unconditional (no harness gate).
  local p="$PPID" c n=0
  while [ "$n" -lt 8 ]; do
    c="$(ps -o comm= -p "$p" 2>/dev/null)"
    [ -n "$c" ] || break
    is_session_host_comm "$c" && break
    if ! is_shell_comm "$c" && ! is_wrapper_comm "$c"; then
      is_holder_pid "$p" && { echo "$p ancestor"; return; }
      break
    fi
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$p" in ''|*[!0-9]*) break ;; esac
    n=$((n+1))
  done   # end of the ancestor walk
  if is_holder_pid "$PPID"; then echo "$PPID ppid"; else echo "- ppid"; fi
}

# write_meta [owner] — owner defaults to --owner; the re-entrant path passes
# the recorded outer owner so a nested acquire never relabels the lock. Sets
# WROTE_SRC to the recorded pid_source (read by note_degraded).
WROTE_SRC=""
write_meta() {
  local owner="${1:-$OWNER}" hp hsrc hstart
  read -r hp hsrc <<EOF_HOLDER
$(holder_pid)
EOF_HOLDER
  [ "$hp" != - ] || hp=""
  hstart=""
  [ -z "$hp" ] || hstart="$(proc_lstart "$hp")"
  {
    printf 'pid\t%s\n' "$hp"
    printf 'owner\t%s\n' "$owner"
    printf 'session_id\t%s\n' "$SESSION_ID"
    printf 'ts\t%s\n' "$(now_epoch)"
    printf 'pid_source\t%s\n' "$hsrc"
    [ -z "$hstart" ] || printf 'pid_start\t%s\n' "$hstart"
  } > "$LOCK_META" 2>/dev/null || true
  WROTE_SRC="$hsrc"
}

# note_degraded <pid_source> — the one STDERR line for a TTL-only lock. Never
# stdout: every stdout line here is parsed by a caller.
note_degraded() {
  [ "${1:-}" = ppid ] || return 0
  echo "run_lock_degraded: pid_source=ppid ttl_only=${LOCK_TTL_SECONDS}s" >&2
}

print_held() {
  local o p a
  o="$(meta_get owner)"
  p="$(meta_get pid)"
  a="$(lock_age)"
  echo "run_lock_held owner=${o} pid=${p} age=${a}"
}

break_lock() {
  echo "force-unlock: broke $(print_held)"
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}

cmd_acquire() {
  [ -n "$OWNER" ] || die_usage
  mkdir -p "$ROOT/.supervisor" 2>/dev/null || true

  if [ "$FORCE" -eq 1 ] && [ -d "$LOCK_DIR" ]; then
    break_lock
  fi

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    write_meta
    note_degraded "$WROTE_SRC"
    exit 0
  fi

  # Held by THIS session (nested /automate → /autonomous → /supervisor entry)
  # — re-entrant: keep the outer owner, refresh pid/ts, succeed.
  local lk_session lk_owner
  lk_session="$(meta_get session_id)"
  if [ -n "$SESSION_ID" ] && [ "$lk_session" = "$SESSION_ID" ]; then
    lk_owner="$(meta_get owner)"
    write_meta "$lk_owner"
    echo "run_lock_reentrant owner=${lk_owner} session_id=${SESSION_ID}"
    note_degraded "$WROTE_SRC"
    exit 0
  fi
  # Held by the COORDINATOR session that spawned this one (a fresh phase session, automate-lanes.sh
  # phase-launch) — re-entrant across sessions: same line, and the meta is left exactly as the outer
  # holder wrote it (its owner, session_id and holder pid: a phase session is shorter-lived than its
  # coordinator, so recording it would hand the lock to a pid that dies first). Acquire-only: release
  # never reads LOOMWRIGHT_RUN_LOCK_SESSION_ID, so the phase's own release stays a no-op.
  if [ -n "${LOOMWRIGHT_RUN_LOCK_SESSION_ID:-}" ] && [ "$lk_session" = "$LOOMWRIGHT_RUN_LOCK_SESSION_ID" ]; then
    echo "run_lock_reentrant owner=$(meta_get owner) session_id=${lk_session}"
    exit 0
  fi

  # Held — consider TTL reclaim. BOTH must hold: (a) recorded pid dead, AND
  # (b) lock age >= LOCK_TTL_SECONDS. A dead pid alone, or a fresh lock
  # alone, both refuse (matches dispatch-pr-review.sh's acquire_lock).
  # "Alive" is holder_alive — a reused pid reads dead (header, `pid_start`).
  local age pid_alive
  age="$(lock_age)"
  pid_alive=0
  if holder_alive "$(meta_get pid)" "$(meta_get pid_start)"; then
    pid_alive=1
  fi
  if [ "$pid_alive" -eq 0 ] && [ "$age" -ge "$LOCK_TTL_SECONDS" ] 2>/dev/null; then
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      write_meta
      note_degraded "$WROTE_SRC"
      exit 0
    fi
    # Lost the reclaim race to a concurrent acquirer — fall through and
    # report whatever is there now as held.
  fi

  print_held
  exit 1
}

cmd_release() {
  [ -n "$OWNER" ] || [ -n "$SESSION_ID" ] || die_usage
  if [ ! -d "$LOCK_DIR" ]; then
    exit 0   # already released / never held — idempotent no-op
  fi
  if [ "$FORCE" -eq 1 ]; then
    break_lock
    exit 0
  fi
  local lk_owner lk_session
  lk_owner="$(meta_get owner)"
  lk_session="$(meta_get session_id)"
  if { [ -n "$OWNER" ] && [ "$lk_owner" = "$OWNER" ]; } \
     || { [ -n "$SESSION_ID" ] && [ -n "$lk_session" ] && [ "$lk_session" = "$SESSION_ID" ]; }; then
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    exit 0
  fi
  # Not our lock — idempotent no-op success, never silently steal it.
  exit 0
}

cmd_status() {
  if [ -d "$LOCK_DIR" ]; then
    print_held | sed 's/^run_lock_held/LOCKED/'
    note_degraded "$(meta_get pid_source)"
  else
    echo "UNLOCKED"
  fi
  exit 0
}

cmd_liveness() {
  local lk_pid
  case "$EXPECT_PID" in *[!0-9]*) die_usage ;; esac
  lk_pid="$(meta_get pid)"
  if [ ! -d "$LOCK_DIR" ] || [ -z "$lk_pid" ]; then
    echo "unknown"
  elif [ -n "$EXPECT_PID" ] && [ "$lk_pid" != "$EXPECT_PID" ]; then
    echo "dead"   # --pid: the lock now names another holder (header, `liveness`)
  elif holder_alive "$lk_pid" "$(meta_get pid_start)"; then
    echo "alive"
  else
    echo "dead"
  fi
  exit 0
}

case "$CMD" in
  acquire)  cmd_acquire ;;
  release)  cmd_release ;;
  status)   cmd_status ;;
  liveness) cmd_liveness ;;
  *) die_usage ;;
esac
