g() { git -C "$ROOT" "$@"; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t meta-sync)" || die "cannot create a temp dir"
# Per-run scratch only: the gitdir is shared by every worktree and every concurrent invocation
# (a read-only `status` included), so no fixed-name scratch file may live there.
META_INDEX="$WORK/meta-index"
# mktemp creates 0600 files; written files get the mode a plain `>` would give them (0666 & ~umask).
FILE_MODE="$(printf '%o' $(( 0666 & ~0$(umask) )))"
META_BASE_INDEX="$WORK/meta-base-index"
RECLAIM_MARK=""   # the reclaim marker this run holds right now, if any (see reclaim_lock)
RECLAIMED=0
# cleanup — removes only this run's own state: the per-run temp dir, and the lock / a reclaim
# marker iff it still carries this run's pid (a live holder's lock is never removed by anyone else).
cleanup() {
  if [ "$LOCK_HELD" = "1" ] && [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$LOCK_DIR"
  fi
  if [ -n "$RECLAIM_MARK" ] && [ "$(cat "$RECLAIM_MARK/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$RECLAIM_MARK"
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- per-root lock (pull / push) ----
# lock_holder_alive <pid> — kill -0 first; when it fails (dead, OR alive but owned by another user:
# EPERM) let `ps -p` decide, if ps exists.
lock_holder_alive() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null && return 0
  command -v ps >/dev/null 2>&1 || return 1
  ps -p "$1" >/dev/null 2>&1
}
# lock_is_stale <dir> <token> — 0 when <dir>, carrying <token> (the pid read from <dir>/pid), is
# abandoned: the token is a dead pid, or the dir is token-less (its holder died between mkdir and
# the pid write) and over a minute old.
lock_is_stale() {
  [ -d "$1" ] || return 1
  if [ -n "$2" ]; then
    lock_holder_alive "$2" && return 1
    return 0
  fi
  [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}
# reclaim_lock <dir> <token> <depth> — remove <dir> iff it STILL carries <token> and is STILL stale.
# Exactly one process may act on a given (dir, token): the one whose mkdir of the marker
# "<dir>.reclaim.<token>" succeeds. While it holds the marker, the instance carrying <token> can
# only be removed by it (its holder is dead; every other reclaimer re-checks a DIFFERENT token or
# waits on this marker), so the re-check-then-rm below cannot hit a live lock: a lock re-acquired
# in between carries another token and is left alone. Nothing is ever renamed aside and put back,
# so a waiter can never move a live holder's lock out from under it. A marker whose own owner died
# inside this tiny section is reclaimed the same way, one level up (bounded depth).
reclaim_lock() {
  local d="$1" t="$2" depth="$3" m w
  m="$1.reclaim.${2:-nopid}"
  [ "$depth" -le 4 ] || return 0
  if mkdir "$m" 2>/dev/null; then
    RECLAIM_MARK="$m"
    if printf '%s\n' "$$" > "$m/pid" \
       && [ "$(cat "$d/pid" 2>/dev/null)" = "$t" ] && lock_is_stale "$d" "$t"; then
      rm -rf "$d" && [ "$depth" -eq 0 ] && RECLAIMED=1
    fi
    rm -rf "$m"; RECLAIM_MARK=""
    return 0
  fi
  w="$(cat "$m/pid" 2>/dev/null)"
  if lock_is_stale "$m" "$w"; then reclaim_lock "$m" "$w" $((depth + 1)); fi
  return 0
}
acquire_lock() {
  local start holder
  start="$(date +%s)"
  while :; do
    # LOCK_HELD is set BEFORE the mkdir so a signal between the mkdir and the pid write still runs
    # cleanup; cleanup removes the lock only when it carries this run's pid, so this is safe.
    LOCK_HELD=1
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      if printf '%s\n' "$$" > "$LOCK_DIR/pid"; then return 0; fi
      rm -rf "$LOCK_DIR"; LOCK_HELD=0; die "could not write the lock holder pid into $LOCK_DIR"
    fi
    LOCK_HELD=0
    holder="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if lock_is_stale "$LOCK_DIR" "$holder"; then
      RECLAIMED=0
      reclaim_lock "$LOCK_DIR" "$holder" 0
      if [ "$RECLAIMED" = "1" ]; then
        warn "reclaimed a stale lock left by pid ${holder:-unknown}"
        continue
      fi
    fi
    if [ $(( $(date +%s) - start )) -ge "$LOCK_WAIT" ]; then
      die "locked — another meta-sync (pid ${holder:-unknown}) holds $LOCK_DIR; waited ${LOCK_WAIT}s, nothing was changed"
    fi
    sleep 1
  done
}

