#!/usr/bin/env bash
# ci-slot.sh — N shared CI slots per repository per machine, one fair queue, files + pids only.
#
# Why it exists: a per-checkout lock lets every clone of one repo run its full suite at once, each
# with every CPU — two lane clones on a 12-core machine took 2-3x longer and pushed load to 27.
# This helper keys the slots by REPOSITORY identity, so every checkout of the same repo (primary,
# linked worktrees, lane clones) shares ONE pool of N slots, ONE waiting queue and ONE state dir.
#
# usage: ci-slot.sh acquire <name> --pid <holder-pid> [--slots N] [--wait S]
#          stdout: ONLY `slot=<k> jobs=<j>` on success (safe inside `$(...)`); exit 1 on timeout or
#          when the holder pid dies while queued; exit 2 on usage (`--pid` is REQUIRED).
#        ci-slot.sh release --pid <holder-pid> | --slot <k>
#          frees that holder's slot and its queued ticket; idempotent — exit 0 when it holds nothing.
#        ci-slot.sh status [--json]   holders (slot, pid, checkout, name, started) + waiters in order
#        ci-slot.sh dir               print the repo-keyed state dir (mkdir -p only), for callers that
#                                     keep their own files next to the slots (e.g. a pass cache)
#        ci-slot.sh --help            this header
#
# HOLDER IDENTITY  the pid recorded in a slot or ticket is the caller's `--pid` (a long-lived run,
#                  e.g. ci-local.sh's own $$) — never this helper's pid or its parent's: `acquire`
#                  exits right after printing, so its own pid is dead at once and every later caller
#                  would take the slot over. A slot whose holder pid is dead (`kill -0`) is taken over.
# STATE DIR        ${XDG_STATE_HOME:-$HOME/.local/state}/loomwright/ci-slots/<repo-key>/ where
#                  <repo-key> hashes the normalised `origin` URL: lowercase host + `/` + path, with
#                  scp-style `git@host:owner/repo` mapped to `host/owner/repo`, scheme/user/port
#                  stripped, trailing `.git` and `/` removed. The host stays in, so two hosts never
#                  collide. No `origin` ⇒ a hash of the absolute git-common-dir path (per-repo only).
#                  Layout: slots/<k>/info, tickets/<n>, counter, mutex.lnk — info holds four lines:
#                  pid, checkout path, name, start epoch; a ticket adds a fifth, the waiter's N.
# ORIGIN ASSUMPTION  sharing assumes every checkout's `origin` is the same remote URL (lane-create
#                  sets it so). A clone whose `origin` is a local filesystem path keys separately and
#                  does NOT share; equality across URL forms (ssh vs https) is best-effort only.
# N SLOTS          default max(1, floor(CPUs / 6)); LOOMWRIGHT_CI_SLOTS or --slots overrides. Each
#                  slot's job share is max(2, floor(CPUs / N)). CPUs: getconf _NPROCESSORS_ONLN, else
#                  sysctl -n hw.ncpu, else 4 (LOOMWRIGHT_CI_CPUS overrides, for tests).
# CLAIM BY COUNT   a caller with N may start only while fewer than N LIVE holders exist across ALL
#                  slot dirs (whatever N they were started with); it then takes the lowest free slot
#                  index, which may be above its own N. So a caller's N caps how many suites run
#                  while it starts, and LOOMWRIGHT_CI_SLOTS=1 means "only when nothing else runs".
# FAIR QUEUE       a waiter takes a ticket from a counter guarded by the mutex (no flock). It may
#                  claim only when every LIVE ticket ahead of it is at its own cap (live holders >= that
#                  waiter's N) — with one N everywhere that is exactly "the lowest live ticket goes
#                  first", so no run starves. A ticket with no recorded N blocks everyone behind it.
#                  A queued pid that died has its ticket skipped and removed; a waiter that gives up
#                  removes its own; a waiter whose ticket vanished takes a fresh one. The claim (count
#                  + fairness check + slot `mkdir`) happens under the mutex, and a claimer re-counts
#                  after its `mkdir` and backs off if it pushed the count past its N.
# MUTEX            `ln -s <pid> mutex.lnk` — atomic and carries its holder pid from the instant it
#                  exists, so a TERM can never leave a pid-less lock; a link whose pid is dead (or
#                  not a number) is taken over at once. Lock waits honour the acquire --wait deadline.
# WAITING          stderr, first wait then every LOOMWRIGHT_CI_SLOT_PRINT_EVERY s (default 30):
#                  `waiting for a CI slot — position <p>, holders: <name> (<age>), …`. Poll period:
#                  LOOMWRIGHT_CI_SLOT_POLL s (default 2). All diagnostics go to stderr.
# NUMBERS          integer options and env values may be zero-padded; they are read as decimal
#                  (--slots 010 = 10 slots, never octal 8).
#
# Honest limits: (1) pid reuse — a recycled pid makes a dead holder look alive until it exits too
# (start time is recorded for humans, not checked). (2) `kill -0` on another user's pid fails, so a
# slot held by another user looks stale. (3) two processes taking over the same dead mutex in the
# same instant can both enter it; the post-`mkdir` re-count still keeps N, only ticket order can be
# off for that one claim. (4) mixed N trades strict order for liveness: a waiter with a SMALLER N
# than the others is passed while the live count is at its cap, and waits until the load drops below
# its N. Use one LOOMWRIGHT_CI_SLOTS value everywhere for strict first-come order. (5) a checkout on
# an earlier commit of this helper (a `mutex/` dir lock and an index scan over 1..N) does not take
# `mutex.lnk`, so during that rollout the two can interleave counter bumps and claims: the re-count
# and the fresh-ticket rule keep this side correct, but the older side can still exceed its N.
# Self-test: loomwright/scripts/test-ci-slot.sh. Portability: bash 3.2 safe, BSD + GNU userland.
set -uo pipefail
shopt -s nullglob

die()  { echo "ci-slot: $*" >&2; exit 2; }
warn() { echo "ci-slot: $*" >&2; }
# Every validated number is re-read as $((10#x)) before use: `[ -gt ]` reads "010" as decimal but
# $(( )) reads it as octal ("08" is an error), so a zero-padded value is normalised to decimal once.
is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
alive() { is_uint "${1:-}" && [ "$1" -gt 0 ] && kill -0 "$1" 2>/dev/null; }
now() { date +%s; }

cpus() {
  local c="${LOOMWRIGHT_CI_CPUS:-}"
  is_uint "$c" && [ "$c" -gt 0 ] || c="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  is_uint "$c" && [ "$c" -gt 0 ] || c="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  is_uint "$c" && [ "$c" -gt 0 ] || c=4
  echo "$((10#$c))"
}

# canon_origin URL — the canonical "host/path" form described in the header (local paths verbatim).
canon_origin() {
  local u="$1" auth host path
  u="${u%/}"; u="${u%.git}"; u="${u%/}"
  case "$u" in
    *://*)
      u="${u#*://}"; auth="${u%%/*}"
      if [ "$auth" = "$u" ]; then path=""; else path="${u#*/}"; fi
      host="${auth##*@}"; host="${host%%:*}" ;;
    /*|.*) printf 'local:%s' "$u"; return ;;
    *:*)
      auth="${u%%:*}"
      case "$auth" in */*) printf 'local:%s' "$u"; return ;; esac
      host="${auth##*@}"; path="${u#*:}" ;;
    *) printf 'local:%s' "$u"; return ;;
  esac
  path="${path#/}"
  printf '%s/%s' "$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')" "$path"
}

hash_str() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | cut -c1-16
  else printf '%s' "$1" | cksum | awk '{print $1}'; fi
}

# repo_key — hash of the canonical origin; no origin ⇒ hash of the absolute git-common-dir.
repo_key() {
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "ci-slot: not inside a git repository ($PWD)" >&2; return 1; }
  local origin common
  origin="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin" ]; then hash_str "origin:$(canon_origin "$origin")"; return; fi
  common="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)" || return 1
  hash_str "gitdir:$common"
}

state_dir() {
  local key
  key="$(repo_key)" || exit 1
  D="${XDG_STATE_HOME:-$HOME/.local/state}/loomwright/ci-slots/$key"
  mkdir -p "$D/slots" "$D/tickets" || { echo "ci-slot: cannot create $D" >&2; exit 1; }
}

# --- counter mutex: held for milliseconds by THIS process ($$ is alive for the whole hold) ---------
# A symlink, not a dir + pid file: `ln -s` creates the lock and its pid in one atomic step, so there is
# no window in which a TERM (whose trap bash runs between two commands) can strand a pid-less lock.
# mutex_lock [DEADLINE] — returns 1 once DEADLINE (epoch s) passes without the lock.
mutex_lock() {
  local p
  while ! ln -sn "$$" "$LK" 2>/dev/null; do
    p="$(readlink "$LK" 2>/dev/null || true)"
    if [ -n "$p" ] && ! alive "$p"; then
      # Rename first: only one taker can move a given link, and rm never hits a fresh mutex.
      if mv "$LK" "$D/mutex.stale.$$" 2>/dev/null; then
        warn "taking over a stale counter mutex (pid $p is gone)"
        rm -f "$D/mutex.stale.$$"
      fi
      continue
    fi
    if [ -n "${1:-}" ] && [ "$(now)" -ge "$1" ]; then return 1; fi
    sleep 0.05
  done
  return 0
}
mutex_mine() { [ "$(readlink "$LK" 2>/dev/null)" = "$$" ]; }
mutex_unlock() { mutex_mine && rm -f "$LK"; return 0; }

rec_field() { sed -n "${2}p" "$1" 2>/dev/null; }   # rec_field FILE LINE (1 pid 2 checkout 3 name 4 start)

rec() { printf '%s\n%s\n%s\n%s\n' "$PID" "$CHECKOUT" "$NAME" "$(now)"; }
write_rec() { rec > "$1"; }

# live_tickets — ticket numbers in queue order; tickets of dead pids are removed (call under mutex).
live_tickets() {
  local t n
  for t in "$D"/tickets/*; do
    n="${t##*/}"; is_uint "$n" || continue
    if alive "$(rec_field "$t" 1)"; then echo "$n"; else rm -f "$t"; fi
  done | sort -n
}

# take_ticket — under the mutex: bump the counter and create our ticket exclusively (noclobber), so
# a ticket number is never shared even with a writer that ignores this mutex.
take_ticket() {
  local n
  n="$(cat "$D/counter" 2>/dev/null || true)"; is_uint "$n" || n=0
  while :; do
    n=$((10#$n + 1))
    MY_TICKET="$n"   # set first: the TERM trap removes it only if it records our --pid
    if (set -C; { rec; echo "$SLOTS"; } > "$D/tickets/$n") 2>/dev/null; then break; fi
    # Retry only past a number already taken; an unwritable tickets dir must not spin forever.
    [ -e "$D/tickets/$n" ] || { MY_TICKET=""; return 1; }
  done
  echo "$n" > "$D/counter"
}

drop_my_ticket() {
  [ -n "$MY_TICKET" ] && [ "$(rec_field "$D/tickets/$MY_TICKET" 1)" = "$PID" ] && rm -f "$D/tickets/$MY_TICKET"
  return 0
}

# live_holders — count of LIVE holders across every slot dir; dead holders' slots are removed.
live_holders() {
  local s k p h=0
  for s in "$D"/slots/*; do
    k="${s##*/}"; is_uint "$k" || continue
    p="$(rec_field "$s/info" 1)"
    if alive "$p"; then h=$((h + 1)); else warn "taking over slot $k (holder pid ${p:-?} is gone)"; rm -rf "$s"; fi
  done
  echo "$h"
}

# try_claim — under the mutex: claim iff live holders < our N and every live ticket ahead of ours
# is at its own cap (see CLAIM BY COUNT / FAIR QUEUE). Sets GOT to the slot index. Runs in the
# acquiring shell itself (never `$(...)`), so CLAIMING is visible to the TERM trap.
try_claim() {
  local k s h t c
  h="$(live_holders)"
  [ "$h" -lt "$SLOTS" ] || return 1   # COUNT
  for t in $(live_tickets); do
    [ "$t" = "$MY_TICKET" ] && break
    c="$(rec_field "$D/tickets/$t" 5)"
    is_uint "$c" && [ "$c" -gt 0 ] && [ "$h" -ge $((10#$c)) ] || return 1   # FAIR
  done
  k=1; while [ -e "$D/slots/$k" ]; do k=$((k + 1)); done   # LOWEST
  s="$D/slots/$k"
  mkdir "$s" 2>/dev/null || return 1
  CLAIMING="$s"
  write_rec "$s/info"
  # Re-count with ours in: only a writer outside this mutex (see Honest limits) can push it past N.
  if [ "$(live_holders)" -gt "$SLOTS" ]; then rm -rf "$s"; CLAIMING=""; return 1; fi
  rm -f "$D/tickets/$MY_TICKET"
  GOT="$k"; return 0
}

fmt_age() {
  local a="$1"
  if [ "$a" -ge 3600 ]; then printf '%dh%02dm' $((a / 3600)) $((a % 3600 / 60))
  elif [ "$a" -ge 60 ]; then printf '%dm%02ds' $((a / 60)) $((a % 60))
  else printf '%ds' "$a"; fi
}

holders_line() {
  local s p st out="" t
  t="$(now)"
  for s in "$D"/slots/*; do
    p="$(rec_field "$s/info" 1)"; alive "$p" || continue
    st="$(rec_field "$s/info" 4)"; is_uint "$st" || st="$t"
    out="${out:+$out, }$(rec_field "$s/info" 3) ($(fmt_age $((t - st))))"
  done
  echo "${out:-none}"
}

json_str() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }

json_rec() {  # json_rec FILE KEY VALUE
  local p st c
  p="$(rec_field "$1" 1)"; is_uint "$p" || p=0
  st="$(rec_field "$1" 4)"; is_uint "$st" || st=0
  printf '{%s:%s,"pid":%s,"checkout":%s,"name":%s,"started":%s' "$(json_str "$2")" "$3" "$p" \
    "$(json_str "$(rec_field "$1" 2)")" "$(json_str "$(rec_field "$1" 3)")" "$st"
  # A ticket also carries the waiter's own N (0 = not recorded).
  if [ "$2" = ticket ]; then c="$(rec_field "$1" 5)"; is_uint "$c" || c=0; printf ',"slots":%s' "$((10#$c))"; fi
  printf '}'
}

cmd_status() {
  local json=0 s k sep="" t n
  [ "${1:-}" = "--json" ] && json=1
  local c; c="$(cpus)"
  if [ "$json" -eq 1 ]; then
    printf '{"dir":%s,"cpus":%s,"slots":%s,"jobs":%s,"holders":[' "$(json_str "$D")" "$c" "$SLOTS" "$JOBS"
    for s in "$D"/slots/*; do
      k="${s##*/}"; is_uint "$k" || continue
      alive "$(rec_field "$s/info" 1)" || continue
      printf '%s%s' "$sep" "$(json_rec "$s/info" slot "$k")"; sep=","
    done
    printf '],"waiters":['; sep=""
    for n in $(ls "$D/tickets" 2>/dev/null | sort -n); do
      t="$D/tickets/$n"; is_uint "$n" || continue
      alive "$(rec_field "$t" 1)" || continue
      printf '%s%s' "$sep" "$(json_rec "$t" ticket "$n")"; sep=","
    done
    printf ']}\n'
    return 0
  fi
  echo "dir: $D"
  echo "slots: $SLOTS  cpus: $c  jobs per slot: $JOBS"
  for s in "$D"/slots/*; do
    alive "$(rec_field "$s/info" 1)" || continue
    echo "holder: slot ${s##*/} pid $(rec_field "$s/info" 1) $(rec_field "$s/info" 3) $(rec_field "$s/info" 2)"
  done
  for n in $(ls "$D/tickets" 2>/dev/null | sort -n); do
    alive "$(rec_field "$D/tickets/$n" 1)" || continue
    echo "waiter: ticket $n pid $(rec_field "$D/tickets/$n" 1) $(rec_field "$D/tickets/$n" 3) $(rec_field "$D/tickets/$n" 2)"
  done
}

cmd_acquire() {
  local deadline next_print=0 every pos
  [ -n "$PID" ] || die "acquire needs --pid <holder-pid> (the long-lived caller, never this helper)"
  alive "$PID" || die "--pid $PID is not a live process"
  deadline=$(( $(now) + WAIT ))
  every="${LOOMWRIGHT_CI_SLOT_PRINT_EVERY:-30}"; is_uint "$every" || every=30; every=$((10#$every))
  while :; do
    # +1 s: a mutex held for milliseconds right at the deadline (or with --wait 0) is still waited out.
    if mutex_lock $((deadline + 1)); then
      # Our ticket vanished or was overwritten (a writer outside this mutex): take a fresh one.
      if [ -z "$MY_TICKET" ] || [ "$(rec_field "$D/tickets/$MY_TICKET" 1)" != "$PID" ]; then
        take_ticket || { mutex_unlock; warn "cannot write a ticket under $D/tickets"; return 1; }
      fi
      if try_claim; then
        CLAIMING=""
        mutex_unlock
        echo "slot=$GOT jobs=$JOBS"
        return 0
      fi
      pos="$(live_tickets | grep -nx "$MY_TICKET" | cut -d: -f1)"
      mutex_unlock
    else
      pos=""; warn "the counter mutex is held by pid $(readlink "$LK" 2>/dev/null || echo '?') past the wait deadline"
    fi
    if ! alive "$PID"; then
      drop_my_ticket; warn "holder pid $PID is gone — leaving the queue"; return 1
    fi
    if [ "$(now)" -ge "$deadline" ]; then
      drop_my_ticket
      warn "no CI slot after ${WAIT}s — giving up (holders: $(holders_line)); see: ci-slot.sh status"
      return 1
    fi
    if [ "$(now)" -ge "$next_print" ]; then
      warn "waiting for a CI slot — position ${pos:-?}, holders: $(holders_line)"
      next_print=$(( $(now) + every ))
    fi
    # Background + `wait`, not a foreground sleep: bash defers a trapped TERM until a foreground
    # child exits, so a caller stopping this waiter would block for up to one poll period.
    sleep "$POLL" >/dev/null 2>&1 &
    wait "$!"
  done
}

cmd_release() {
  local s t
  if [ -n "$SLOT" ]; then rm -rf "$D/slots/$SLOT"; return 0; fi
  [ -n "$PID" ] || die "release needs --pid <holder-pid> or --slot <k>"
  for s in "$D"/slots/*; do [ "$(rec_field "$s/info" 1)" = "$PID" ] && rm -rf "$s"; done
  for t in "$D"/tickets/*; do [ "$(rec_field "$t" 1)" = "$PID" ] && rm -f "$t"; done
  return 0
}

# --- arguments --------------------------------------------------------------------------------------
case "${1:-}" in
  -h|--help) awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
  acquire|release|status|dir) CMD="$1"; shift ;;
  '') die "missing subcommand (try --help)" ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
NAME=""; PID=""; SLOT=""; WAIT=1800; JSON=""; SLOTS="${LOOMWRIGHT_CI_SLOTS:-}"
if [ "$CMD" = acquire ] && [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then NAME="$1"; shift; fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pid)   [ "$#" -ge 2 ] && is_uint "$2" || die "--pid needs a numeric pid"; PID="$((10#$2))"; shift 2 ;;
    --slot)  [ "$#" -ge 2 ] && is_uint "$2" || die "--slot needs a number"; SLOT="$((10#$2))"; shift 2 ;;
    --slots) [ "$#" -ge 2 ] && is_uint "$2" && [ "$2" -gt 0 ] || die "--slots needs a positive integer"; SLOTS="$((10#$2))"; shift 2 ;;
    --wait)  [ "$#" -ge 2 ] && is_uint "$2" || die "--wait needs seconds (non-negative integer)"; WAIT="$((10#$2))"; shift 2 ;;
    --json)  JSON=--json; shift ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done
[ "$CMD" = acquire ] && [ -z "$NAME" ] && die "acquire needs a <name>"
CPUS="$(cpus)"
if [ -z "$SLOTS" ]; then SLOTS=$(( CPUS / 6 )); [ "$SLOTS" -ge 1 ] || SLOTS=1; fi
is_uint "$SLOTS" && [ "$SLOTS" -gt 0 ] || die "LOOMWRIGHT_CI_SLOTS must be a positive integer, got '$SLOTS'"
SLOTS=$((10#$SLOTS))
JOBS=$(( CPUS / SLOTS )); [ "$JOBS" -ge 2 ] || JOBS=2
POLL="${LOOMWRIGHT_CI_SLOT_POLL:-2}"
case "$POLL" in ''|*[!0-9.]*) POLL=2 ;; esac
CHECKOUT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MY_TICKET=""
CLAIMING=""
GOT=""
D=""
state_dir
LK="$D/mutex.lnk"

case "$CMD" in
  dir) echo "$D" ;;
  status) cmd_status "$JSON" ;;
  release) cmd_release ;;
  acquire)
    # A waiter leaving on INT/TERM removes its own ticket (and the mutex, if it was inside it).
    # A half-made claim (slot dir made, stdout not yet written) is undone too: the caller sees exit 1.
    trap 'drop_my_ticket; [ -n "$CLAIMING" ] && rm -rf "$CLAIMING"; mutex_unlock; exit 1' INT TERM
    cmd_acquire ;;
esac
