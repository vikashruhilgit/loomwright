#!/usr/bin/env bash
# run-lock.sh — single-run-per-repo lock for `/automate`, `/autonomous`, and
# `/supervisor`. Makes "two runs in one checkout" structurally impossible
# (rather than merely documented) — see automate-loop/SKILL.md §11.
#
# Usage:
#   run-lock.sh acquire --owner <label> [--session-id <id>] [--root <checkout>] [--force-unlock]
#   run-lock.sh release --owner <label> | --session-id <id> [--root <checkout>] [--force-unlock]
#   run-lock.sh status  [--root <checkout>]
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
#         pid, owner, session_id, ts, pid_source
#
# `pid` is the HOLDER's liveness pid — NOT this script's `$$` (which is dead
# the instant `acquire` returns, so every lock looked "dead pid" immediately
# and degraded to a bare 1800s lease). The Bash-tool shell that invokes this
# script also exits after each call, so `$PPID` is no better there; the only
# process that lives as long as the run is the session's `claude` process.
# Resolution order (recorded as `pid_source`):
#   1. `claude_pid` — `$CLAUDE_PID` when numeric and alive. Evidence: observed
#      2026-09-26 on Claude Code 2.1.281 (Desktop), `CLAUDE_PID` in a Bash-tool
#      shell = that shell's own parent = the `claude` binary. It is NOT in the
#      public env-var docs, so it is never the only line of defence:
#   2. `ancestor` — under Claude Code (`CLAUDECODE` set), the first ancestor
#      of this script that is not a shell (sh/bash/zsh/dash/ksh/fish): the
#      Bash-tool shell's parent, i.e. `claude`. Survives `CLAUDE_PID` being
#      dropped or renamed by a future release.
#   3. `ppid` — otherwise the invoking shell (an interactive terminal, a CI
#      step, a test harness). Under Claude Code this source means 1 and 2 both
#      failed — the lock is degraded to the 1800s TTL, visible in `meta`.
# Observed 2026-09-26 (automate-2026-09-26-115755): automate PICK recorded its
# own shell pid, launch-pad ran ~28 min, and Supervisor Phase 0's acquire
# (different owner) reclaimed the "dead-pid + >=1800s" lock as stale.
#
# This is a NEW lock, not a call into dispatch-pr-review.sh's acquire_lock —
# that function's meta shape carries no `session_id`/`owner` fields and its
# lock dir is scoped to a per-PR hash (a different namespace: one dispatch
# lock per PR vs. one run lock per REPO). The mkdir-atomicity + TSV-meta +
# pid-liveness + TTL-reclaim SHAPE is mirrored deliberately (see the
# `write_lock_meta`/`acquire_lock` pair in dispatch-pr-review.sh:580
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
#   Reclaim: fires ONLY when BOTH the recorded pid is dead AND
#   age >= LOCK_TTL_SECONDS (1800s) — a dead pid alone, or a young lock
#   alone, both refuse (matches dispatch-pr-review.sh's acquire_lock TTL
#   contract exactly).
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
# status: prints `LOCKED owner=<label> pid=<pid> age=<s>` or `UNLOCKED`.
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

while [ $# -gt 0 ]; do
  case "$1" in
    --owner)        OWNER="${2:-}"; shift 2 ;;
    --session-id)   SESSION_ID="${2:-}"; shift 2 ;;
    --root)         ROOT="${2:-}"; shift 2 ;;
    --force-unlock) FORCE=1; shift ;;
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

# holder_pid — prints `<pid> <pid_source>`, the liveness pid recorded in meta
# (resolution order in the header).
holder_pid() {
  case "${CLAUDE_PID:-}" in
    ''|*[!0-9]*) : ;;
    *) if kill -0 "$CLAUDE_PID" 2>/dev/null; then echo "$CLAUDE_PID claude_pid"; return; fi ;;
  esac
  if [ -n "${CLAUDECODE:-}" ]; then
    local p="$PPID" c n=0
    while [ "$n" -lt 8 ]; do
      c="$(ps -o comm= -p "$p" 2>/dev/null)"
      [ -n "$c" ] || break
      if ! is_shell_comm "$c"; then
        [ "$p" -gt 1 ] 2>/dev/null && { echo "$p ancestor"; return; }
        break
      fi
      p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
      case "$p" in ''|*[!0-9]*) break ;; esac
      n=$((n+1))
    done
  fi
  echo "$PPID ppid"
}

# write_meta [owner] — owner defaults to --owner; the re-entrant path passes
# the recorded outer owner so a nested acquire never relabels the lock.
write_meta() {
  local owner="${1:-$OWNER}" hp hsrc
  read -r hp hsrc <<EOF_HOLDER
$(holder_pid)
EOF_HOLDER
  {
    printf 'pid\t%s\n' "$hp"
    printf 'owner\t%s\n' "$owner"
    printf 'session_id\t%s\n' "$SESSION_ID"
    printf 'ts\t%s\n' "$(now_epoch)"
    printf 'pid_source\t%s\n' "$hsrc"
  } > "$LOCK_META" 2>/dev/null || true
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
    exit 0
  fi

  # Held — consider TTL reclaim. BOTH must hold: (a) recorded pid dead, AND
  # (b) lock age >= LOCK_TTL_SECONDS. A dead pid alone, or a fresh lock
  # alone, both refuse (matches dispatch-pr-review.sh's acquire_lock).
  local lk_pid age pid_alive
  lk_pid="$(meta_get pid)"
  age="$(lock_age)"
  pid_alive=0
  if [ -n "$lk_pid" ] && kill -0 "$lk_pid" 2>/dev/null; then
    pid_alive=1
  fi
  if [ "$pid_alive" -eq 0 ] && [ "$age" -ge "$LOCK_TTL_SECONDS" ] 2>/dev/null; then
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      write_meta
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
  else
    echo "UNLOCKED"
  fi
  exit 0
}

case "$CMD" in
  acquire) cmd_acquire ;;
  release) cmd_release ;;
  status)  cmd_status ;;
  *) die_usage ;;
esac
