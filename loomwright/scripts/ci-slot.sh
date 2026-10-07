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
#          when the holder pid dies while queued; exit 2 on usage (`--pid` is REQUIRED). A caller
#          nested in a live holder of this pool gets that holder's slot back at once (NESTED).
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
# NESTED           a caller whose --pid descends from a LIVE holder of THIS repo's pool (ci-local.sh
#                  runs run-self-tests.sh as its pool, and the runner asks for admission too) FOLDS
#                  into that holder before any count, queue or machine check: it gets
#                  `slot=<that holder's slot>` and nothing is recorded (no ticket, no slot, no machine
#                  record), so its `release --pid` frees nothing. Checked first because the outer run
#                  cannot end while its own child waits: counting the child (N=1) or queueing it
#                  behind a waiter that waits on the outer run would hold it until --wait. A slot
#                  record started before this boot is never folded into (same rule as the machine
#                  list below).
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
# MACHINE GATE     the per-repo pool above caps one repository; this gate caps the MACHINE. Before a
#                  claim is granted (under the repo mutex, after the count and fairness checks, so a
#                  held caller keeps its ticket and its place), the caller reads machine-load.sh:
#                  `overloaded` ⇒ held (nothing machine-wide is granted); `busy` ⇒ granted only while
#                  no other machine-wide holder is live. At EVERY state a caller also waits while the
#                  jobs its live machine holders run plus its own exceed the CPUs (COMMITTED WORK — a
#                  sole caller is always admitted): load1 lags a suite's ramp by about a minute, so
#                  load alone admits a burst of close starts (12 CPUs, 6 jobs a slot ⇒ at most two
#                  suites machine-wide). A holder record's 6th line is its jobs; a record without
#                  one counts as the caller's. Otherwise `ok` and `unknown` ⇒ granted (fail-SAFE: a
#                  reader that exits non-zero, prints garbage or is missing reads as `unknown`, so a
#                  broken reader never stalls a lane). A reader still running after 5 s is not broken
#                  but slow — what deep overload looks like — so it is never read as `unknown`: until
#                  it answers, the last answered reading stands in when it is ok/busy/overloaded and
#                  under 60 s old, else `busy`. It is never signalled, no second reader starts while
#                  it runs, and its answer is used on the next poll after it ends. The reading is
#                  refreshed every LOOMWRIGHT_MACHINE_LOAD_RECHECK s (default 15); the holder count is
#                  re-read every poll. Holders are listed in ONE machine state dir shared by every
#                  repo key and every XDG_STATE_HOME: LOOMWRIGHT_MACHINE_STATE_DIR, default
#                  $HOME/.local/state/loomwright/machine/ (holders/<pid>, mutex.lnk, load = the last
#                  reading). So a clone with a local-path origin keeps its own repo pool but joins the
#                  machine count. A caller whose --pid descends from a live machine holder (an outer
#                  ci-local.sh running the self-tests that call acquire again) FOLDS into it: granted
#                  at any machine state, no second holder recorded. A holder record whose start epoch
#                  predates this boot (kern.boottime / /proc/stat btime; LOOMWRIGHT_MACHINE_BOOT_TIME
#                  overrides it, for tests) is dropped before it is counted or folded into: records
#                  survive the hard reboot a freeze forces, and their pids then name unrelated
#                  processes. Unreadable boot time ⇒ nothing dropped. A self-test that sets
#                  LOOMWRIGHT_MACHINE_STATE_DIR to a sandbox is isolated from the real list by design;
#                  one that sets neither is an ordinary caller and counts once. LOOMWRIGHT_MACHINE_
#                  LOAD_CMD names another reader script (tests). `status` shows a held waiter as
#                  `held for load: <state> load1=<n>`; a held caller still times out at --wait.
#                  The gate never signals any process; `status`, `dir` and `release` never take its
#                  mutex or run its reader. Lock order is always repo mutex, then machine mutex.
#
# Honest limits: (1) pid reuse — a recycled pid makes a dead holder look alive until it exits too
# (a slot's start time is recorded for humans, not checked). The machine list and the nested-holder
# fold check a record's start only against boot time, so a record written THIS boot whose pid was
# recycled still counts as a holder, and still folds a caller that descends from the new owner; a
# wall-clock step shortly after boot can also move boot time past a record written just before it.
# (2) `kill -0` on another user's pid fails, so a slot held by another user looks stale. (3) two
# processes taking over the same dead mutex in the same instant can both enter it; the post-`mkdir`
# re-count still keeps N, only ticket order can be off for that one claim. (4) mixed N trades strict order for liveness: a waiter with a SMALLER N
# than the others is passed while the live count is at its cap, and waits until the load drops below
# its N. Use one LOOMWRIGHT_CI_SLOTS value everywhere for strict first-come order. (5) a checkout on
# an earlier commit of this helper (a `mutex/` dir lock and an index scan over 1..N) does not take
# `mutex.lnk`, so during that rollout the two can interleave counter bumps and claims: the re-count
# and the fresh-ticket rule keep this side correct, but the older side can still exceed its N.
# (6) a checkout on a commit before the MACHINE GATE neither reads the load nor joins the machine
# list: its runs are invisible to `busy` until it updates. (7) the machine gate has no cross-repo
# ticket queue: when the load falls, held callers of different repos race for the first grant (order
# inside each repo is kept). (8) nesting (NESTED, and the machine gate's fold) is detected by
# --pid ancestry: a holder whose child was re-parented (setsid / nohup to launchd) is not recognised,
# and that child counts as a new caller. (9) only callers that ask are gated: ci-local.sh and
# run-self-tests.sh (every full-suite entry point) take a slot, but a single test-*.sh run directly
# — or any other heavy command — never asks the gate at all, so it is neither counted nor held.
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
# clock_ms — wall-clock milliseconds into CLOCK_MS, without a fork: bash >= 5's EPOCHREALTIME
# (microseconds; `.` or `,` by locale), else SECONDS (bash 3.2: whole seconds, so a 5 s bound ends
# after just over 4 s to 5 s). Either way a polling caller can overshoot by one poll step (one
# `sleep` plus its process start). Only differences of two readings are meaningful.
clock_ms() {
  local e="${EPOCHREALTIME:-}"
  case "$e" in
    *[.,]*) e="${e/[.,]/}"; CLOCK_MS=$(( 10#$e / 1000 )) ;;
    *) CLOCK_MS=$(( SECONDS * 1000 )) ;;
  esac
}

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
mutex_lock() { link_lock "$LK" "counter" "${1:-}"; }
# link_lock LINK WHAT [DEADLINE] — the one lock routine, for the repo mutex and the machine mutex.
link_lock() {
  local p
  while ! ln -sn "$$" "$1" 2>/dev/null; do
    p="$(readlink "$1" 2>/dev/null || true)"
    if [ -n "$p" ] && ! alive "$p"; then
      # Rename first: only one taker can move a given link, and rm never hits a fresh mutex.
      if mv "$1" "$1.stale.$$" 2>/dev/null; then
        warn "taking over a stale $2 mutex (pid $p is gone)"
        rm -f "$1.stale.$$"
      fi
      continue
    fi
    if [ -n "${3:-}" ] && [ "$(now)" -ge "$3" ]; then return 1; fi
    sleep 0.05
  done
  return 0
}
mutex_mine() { [ "$(readlink "$LK" 2>/dev/null)" = "$$" ]; }
mutex_unlock() { mutex_mine && rm -f "$LK"; return 0; }
link_unlock() { [ "$(readlink "$1" 2>/dev/null)" = "$$" ] && rm -f "$1"; return 0; }

# --- MACHINE GATE ------------------------------------------------------------------------------------
# read_load — refresh LOAD_STATE / LOAD1 when the cached reading is older than RECHECK. Never under a
# mutex. The reader runs in the background and is waited for at most 5 s. One still running then is
# left alone (never signalled) and NOT read as unknown: a slow reader is what deep overload looks like.
# load_timed_out stands in for it, no second reader starts while it runs, and its answer is taken on
# the first call after it ends. Only an answered reading is written to $MD/load (a rename, so a reader
# outside the mutex never sees a half line); a stand-in never refreshes the cache's age.
read_load() {
  local t i rc out st l
  t="$(now)"
  if [ -n "$RP" ]; then
    if alive "$RP"; then load_timed_out "$t"; return 0; fi
    wait "$RP"; rc=$?
  else
    [ -n "$LOAD_AT" ] && [ $((t - LOAD_AT)) -lt "$RECHECK" ] && return 0
    RF="$MD/.reading.$$"
    [ -d "$MD" ] || RF="${TMPDIR:-/tmp}/ci-slot-reading.$$"
    LOOMWRIGHT_CI_CPUS="$CPUS" bash "$LOAD_CMD" > "$RF" 2>/dev/null &
    RP=$!; clock_ms; i="$CLOCK_MS"
    # bounded by the CLOCK, not by a loop count: each `sleep` is a process start, which costs ~8 ms
    # extra on macOS, so 100 x `sleep 0.05` took 5.85 s idle (more under load) and a reader that
    # answered at 6 s was taken as answered instead of still running (test-ci-slot G10, G13). The
    # wait now ends at 5 s plus at most one poll step (bash 3.2: just over 4 s to 5 s, plus that step).
    while alive "$RP"; do clock_ms; [ $((CLOCK_MS - i)) -ge 5000 ] && break; sleep 0.05; done
    if alive "$RP"; then load_timed_out "$t"; return 0; fi   # SLOW
    wait "$RP"; rc=$?
  fi
  out="$(cat "$RF" 2>/dev/null)"; rm -f "$RF"; RP=""; RF=""
  st="$(printf '%s\n' "$out" | sed -n 's/^state=//p' | head -n 1)"
  l="$(printf '%s\n' "$out" | sed -n 's/^load1=//p' | head -n 1)"
  case "$st" in ok|busy|overloaded|unknown) ;; *) st=unknown ;; esac
  [ "$rc" -eq 0 ] || st=unknown
  case "$l" in ''|*[!0-9.]*) l=unknown ;; esac
  LOAD_STATE="$st"; LOAD1="$l"; LOAD_AT="$t"
  [ -d "$MD" ] && printf '%s %s %s\n' "$t" "$st" "$l" > "$MD/load.$$" 2>/dev/null && mv "$MD/load.$$" "$MD/load"
  rm -f "$MD/load.$$"
  return 0
}

# load_timed_out T — the reading while a reader is still running: the last answered machine-wide
# reading when it is ok/busy/overloaded and under LOAD_STALE s old, else busy (one holder at most).
load_timed_out() {
  set -- "$1" $(cat "$MD/load" 2>/dev/null)
  if is_uint "${2:-}" && [ "$1" -ge "$2" ] && [ $(( $1 - $2 )) -lt "$LOAD_STALE" ]; then
    case "${3:-}" in ok|busy|overloaded) LOAD_STATE="$3"; LOAD1="${4:-unknown}"; return 0 ;; esac
  fi
  LOAD_STATE=busy; LOAD1="unknown (reader still running after 5s)"
}
# drop_reading — at exit: unlink a timed-out reader's output file (the reader itself is left running)
# and a cache write cut short by a signal.
drop_reading() { [ -n "$RF" ] && rm -f "$RF"; rm -f "$MD/load.$$"; return 0; }

# ancestry PID — " PID ppid ppid… " up to init: a live machine holder in it means we are nested.
# ONE `ps` for the whole walk (a per-level `ps` cost seconds on a loaded machine, past a short --wait).
ancestry() {
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '{ pp[$1] = $2 }
    END { out = " "; i = 0; while (p > 1 && i < 64) { out = out p " "; p = pp[p]; i++ }; print out }'
}
# need_ancestry — walk once, and only when a machine holder exists (none ⇒ nothing to nest in).
need_ancestry() {
  [ -n "$ANCESTRY" ] && return 0
  local r; for r in "$MD"/holders/*; do ANCESTRY="$(ancestry "$PID")"; return 0; done
  return 0
}

# boot_epoch — the kernel's boot time (epoch s) into BOOT, read once; empty when unreadable.
# LOOMWRIGHT_MACHINE_BOOT_TIME, when set, replaces the OS reading (tests; a non-number = unreadable).
boot_epoch() {
  local b
  [ "$BOOT_READ" -eq 1 ] && return 0
  BOOT_READ=1
  if [ -n "${LOOMWRIGHT_MACHINE_BOOT_TIME+x}" ]; then b="$LOOMWRIGHT_MACHINE_BOOT_TIME"
  elif [ -r /proc/stat ]; then b="$(awk '$1 == "btime" { print $2; exit }' /proc/stat 2>/dev/null)"
  else b="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ *sec *= *\([0-9][0-9]*\).*/\1/p')"; fi
  is_uint "$b" && BOOT="$((10#$b))"
  return 0
}

# machine_holders — under the machine mutex: MH = count of LIVE holders (dead records removed);
# NESTED_IN = the holder pid our --pid descends from, if any. Runs in this shell, never `$(...)`.
# A record whose start epoch predates this boot is dropped before its pid is even looked at: that
# pid belongs to a process of this boot that never wrote it (a holder from before a hard reboot),
# and trusting it would make a phantom holder or a false fold. Unreadable boot time ⇒ no pruning.
# Records are written only under this mutex, so the read-then-remove cannot drop a fresh rewrite.
machine_holders() {
  local r p s j h=0 mj=0
  NESTED_IN=""
  boot_epoch
  for r in "$MD"/holders/*; do
    p="$(rec_field "$r" 1)"
    if [ -n "$BOOT" ]; then
      s="$(rec_field "$r" 4)"
      if is_uint "$s" && [ "$((10#$s))" -lt "$BOOT" ]; then rm -f "$r"; continue; fi   # BOOT
    fi
    if ! alive "$p"; then rm -f "$r"; continue; fi
    h=$((h + 1))
    j="$(rec_field "$r" 6)"; is_uint "$j" && [ "$((10#$j))" -gt 0 ] || j="$JOBS"   # no 6th line: an older record
    mj=$((mj + 10#$j))
    case "$ANCESTRY" in *" $p "*) NESTED_IN="$p" ;; esac
  done
  MJ="$mj"
  MH="$h"
}

# repo_fold — NESTED (see the header): FOLDED = the slot of a live holder of this repo's pool that
# our --pid descends from (0 = folded, 1 = not nested). Read-only, outside every mutex; runs in this
# shell, never `$(...)`. Skips a slot record started before this boot, like machine_holders.
repo_fold() {
  local s k p st
  FOLDED=""
  boot_epoch
  for s in "$D"/slots/*; do
    k="${s##*/}"; is_uint "$k" || continue
    p="$(rec_field "$s/info" 1)"; alive "$p" || continue
    if [ -n "$BOOT" ]; then
      st="$(rec_field "$s/info" 4)"
      if is_uint "$st" && [ "$((10#$st))" -lt "$BOOT" ]; then continue; fi   # REPOBOOT
    fi
    [ -n "$ANCESTRY" ] || ANCESTRY="$(ancestry "$PID")"
    case "$ANCESTRY" in *" $p "*) FOLDED="$k"; return 0 ;; esac
  done
  return 1
}

# machine_admit — under the repo mutex: 0 = admitted (MACHINE_REC = our record, empty when folded or
# the gate is off), 1 = held (HELD says why). Records are written under the machine mutex, so two
# repos never both pass `busy`.
machine_admit() {
  local h
  HELD=""; MACHINE_REC=""
  [ "$MACHINE_OK" -eq 1 ] || return 0
  if ! link_lock "$MLK" machine $(( $(now) + 2 )); then HELD="machine mutex busy"; return 1; fi
  machine_holders; h="$MH"
  if [ -n "$NESTED_IN" ]; then link_unlock "$MLK"; return 0; fi   # FOLD: the same real holder
  case "$LOAD_STATE" in
    overloaded) HELD="held for load: overloaded load1=$LOAD1"; link_unlock "$MLK"; return 1 ;;
    busy) if [ "$h" -ge 1 ]; then HELD="held for load: busy load1=$LOAD1 ($h machine-wide holder(s))"; link_unlock "$MLK"; return 1; fi ;;
  esac
  # COMMITTED WORK, at every load state: load1 lags a suite's ramp by about a minute, so suites that
  # start close together all read `ok` (S3 wave 2: three started 30 s apart, all granted below load1
  # 14, peak 63.6). A suite starts only while the jobs live holders already run plus its own fit the
  # CPUs; a sole caller is always admitted, so one suite never waits on this.
  if [ "$h" -ge 1 ] && [ $(( MJ + JOBS )) -gt "$CPUS" ]; then HELD="held for load: committed $MJ+$JOBS jobs > $CPUS CPUs ($h machine-wide holder(s))"; link_unlock "$MLK"; return 1; fi   # COMMIT
  MACHINE_REC="$MD/holders/$PID"
  { rec; echo "$D"; echo "$JOBS"; } > "$MACHINE_REC" 2>/dev/null || MACHINE_REC=""
  link_unlock "$MLK"
  return 0
}

# set_held — under the repo mutex: keep our ticket's 6th line in step with why we wait (status reads
# it). Lines 1-5 are kept byte for byte; the swap is a rename, so a reader never sees a half file.
set_held() {
  local t="$D/tickets/$MY_TICKET" cur
  [ -n "$MY_TICKET" ] && [ -f "$t" ] || return 0
  cur="$(rec_field "$t" 6)"
  [ "$cur" = "$1" ] && return 0
  { sed -n '1,5p' "$t"; [ -n "$1" ] && echo "$1"; } > "$t.tmp.$$" 2>/dev/null && mv "$t.tmp.$$" "$t"
  rm -f "$t.tmp.$$"
}

rec_field() { sed -n "${2}p" "$1" 2>/dev/null; }   # rec_field FILE LINE (1 pid 2 checkout 3 name 4 start; machine records: 5 repo dir 6 jobs)

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
  machine_admit || return 1   # MACHINE
  k=1; while [ -e "$D/slots/$k" ]; do k=$((k + 1)); done   # LOWEST
  s="$D/slots/$k"
  mkdir "$s" 2>/dev/null || { drop_machine_rec; return 1; }
  CLAIMING="$s"
  write_rec "$s/info"
  # Re-count with ours in: only a writer outside this mutex (see Honest limits) can push it past N.
  if [ "$(live_holders)" -gt "$SLOTS" ]; then rm -rf "$s"; CLAIMING=""; drop_machine_rec; return 1; fi
  rm -f "$D/tickets/$MY_TICKET"
  GOT="$k"; return 0
}

drop_machine_rec() { [ -n "$MACHINE_REC" ] && rm -f "$MACHINE_REC"; MACHINE_REC=""; return 0; }

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
  if [ "$2" = ticket ]; then
    c="$(rec_field "$1" 5)"; is_uint "$c" || c=0; printf ',"slots":%s' "$((10#$c))"
    c="$(rec_field "$1" 6)"; if [ -n "$c" ]; then printf ',"held":%s' "$(json_str "$c")"; else printf ',"held":null'; fi
  fi
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
    printf '],"machine":{"dir":%s,"holders":[' "$(json_str "$MD")"; sep=""
    for s in "$MD"/holders/*; do
      alive "$(rec_field "$s" 1)" || continue
      printf '%s%s' "$sep" "$(json_rec "$s" holder "$(rec_field "$s" 1)")"; sep=","
    done
    set -- $(cat "$MD/load" 2>/dev/null)
    if is_uint "${1:-}"; then printf '],"last_reading":{"at":%s,"state":%s,"load1":%s}}}\n' "$1" "$(json_str "${2:-unknown}")" "$(json_str "${3:-unknown}")"
    else printf '],"last_reading":null}}\n'; fi
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
    t="$(rec_field "$D/tickets/$n" 6)"
    echo "waiter: ticket $n pid $(rec_field "$D/tickets/$n" 1) $(rec_field "$D/tickets/$n" 3) $(rec_field "$D/tickets/$n" 2)${t:+ — $t}"
  done
  # Machine-wide view: read-only (no machine mutex, no reader run), so status never waits on the gate.
  n=0; for s in "$MD"/holders/*; do alive "$(rec_field "$s" 1)" && n=$((n + 1)); done
  set -- $(cat "$MD/load" 2>/dev/null)
  if is_uint "${1:-}"; then t="last reading: ${2:-unknown} load1=${3:-unknown} ($(fmt_age $(( $(now) - $1 ))) ago)"; else t="last reading: none"; fi
  echo "machine: $MD  holders: $n  $t"
  for s in "$MD"/holders/*; do
    alive "$(rec_field "$s" 1)" || continue
    echo "machine holder: pid $(rec_field "$s" 1) $(rec_field "$s" 3) $(rec_field "$s" 2)"
  done
}

cmd_acquire() {
  local deadline next_print=0 every pos
  [ -n "$PID" ] || die "acquire needs --pid <holder-pid> (the long-lived caller, never this helper)"
  alive "$PID" || die "--pid $PID is not a live process"
  if repo_fold; then echo "slot=$FOLDED jobs=$JOBS"; return 0; fi   # REPOFOLD
  deadline=$(( $(now) + WAIT ))
  every="${LOOMWRIGHT_CI_SLOT_PRINT_EVERY:-30}"; is_uint "$every" || every=30; every=$((10#$every))
  while :; do
    # +1 s: a mutex held for milliseconds right at the deadline (or with --wait 0) is still waited out.
    read_load; need_ancestry; boot_epoch   # outside every mutex: a slow reader never holds anyone else up
    if mutex_lock $((deadline + 1)); then
      # Our ticket vanished or was overwritten (a writer outside this mutex): take a fresh one.
      if [ -z "$MY_TICKET" ] || [ "$(rec_field "$D/tickets/$MY_TICKET" 1)" != "$PID" ]; then
        take_ticket || { mutex_unlock; warn "cannot write a ticket under $D/tickets"; return 1; }
      fi
      if try_claim; then
        CLAIMING=""; MACHINE_REC=""
        mutex_unlock
        echo "slot=$GOT jobs=$JOBS"
        return 0
      fi
      set_held "$HELD"
      pos="$(live_tickets | grep -nx "$MY_TICKET" | cut -d: -f1)"
      mutex_unlock
    else
      pos=""; warn "the counter mutex is held by pid $(readlink "$LK" 2>/dev/null || echo '?') past the wait deadline"
    fi
    if ! alive "$PID"; then
      drop_my_ticket; warn "holder pid $PID is gone — leaving the queue"; return 1
    fi
    # The first waiting line comes before any give-up, so even a --wait shorter than one round says why.
    if [ "$next_print" -eq 0 ]; then
      warn "waiting for a CI slot — position ${pos:-?}, ${HELD:+$HELD, }holders: $(holders_line)"
      next_print=$(( $(now) + every ))
    fi
    if [ "$(now)" -ge "$deadline" ]; then
      drop_my_ticket
      warn "no CI slot after ${WAIT}s — giving up (${HELD:+$HELD, }holders: $(holders_line)); see: ci-slot.sh status"
      return 1
    fi
    if [ "$(now)" -ge "$next_print" ]; then
      warn "waiting for a CI slot — position ${pos:-?}, ${HELD:+$HELD, }holders: $(holders_line)"
      next_print=$(( $(now) + every ))
    fi
    # Background + `wait`, not a foreground sleep: bash defers a trapped TERM until a foreground
    # child exits, so a caller stopping this waiter would block for up to one poll period.
    sleep "$POLL" >/dev/null 2>&1 &
    wait "$!"
  done
}

# release_machine PID — drop PID's machine-wide record (no mutex: a remove never waits on the gate).
release_machine() {
  is_uint "${1:-}" || return 0
  [ "$(rec_field "$MD/holders/$1" 1)" = "$1" ] && rm -f "$MD/holders/$1"
  return 0
}

cmd_release() {
  local s t
  if [ -n "$SLOT" ]; then
    release_machine "$(rec_field "$D/slots/$SLOT/info" 1)"; rm -rf "$D/slots/$SLOT"; return 0
  fi
  [ -n "$PID" ] || die "release needs --pid <holder-pid> or --slot <k>"
  release_machine "$PID"
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
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MD="${LOOMWRIGHT_MACHINE_STATE_DIR:-$HOME/.local/state/loomwright/machine}"
MLK="$MD/mutex.lnk"
LOAD_CMD="${LOOMWRIGHT_MACHINE_LOAD_CMD:-$HERE/machine-load.sh}"
RECHECK="${LOOMWRIGHT_MACHINE_LOAD_RECHECK:-15}"; is_uint "$RECHECK" || RECHECK=15; RECHECK=$((10#$RECHECK))
LOAD_STATE=unknown; LOAD1=unknown; LOAD_AT=""; HELD=""; MACHINE_REC=""; NESTED_IN=""; MH=0; MJ=0; ANCESTRY=""
RP=""; RF=""; LOAD_STALE=60; BOOT=""; BOOT_READ=0; FOLDED=""
MACHINE_OK=0
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
    trap 'drop_my_ticket; [ -n "$CLAIMING" ] && rm -rf "$CLAIMING"; drop_machine_rec; link_unlock "$MLK"; mutex_unlock; exit 1' INT TERM
    trap 'drop_reading' EXIT
    # Only acquire creates the machine dir; a dir that cannot be made turns the gate off (fail-SAFE).
    if mkdir -p "$MD/holders" 2>/dev/null; then MACHINE_OK=1; else warn "machine gate off: cannot create $MD"; fi
    cmd_acquire ;;
esac
