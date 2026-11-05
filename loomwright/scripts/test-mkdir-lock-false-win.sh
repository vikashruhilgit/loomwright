#!/usr/bin/env bash
# test-mkdir-lock-false-win.sh — every lock that used to test the `mkdir` command holds under a mkdir
# that lets every racer win.
#
# uutils mkdir, the ubuntu-latest default, exits 0 when mkdir(2) returned EEXIST and the path is a
# directory, even without -p. On a real uutils that only shows when two racers interleave, and BSD and
# GNU never do it, so the shim below exits 0 every time the directory exists: the worst case of the
# same behaviour, on every platform, with no race to wait for (test-token-ledger.sh case 25d).
#
# Each lock's take is the script's OWN function, extracted from the file, never a copy. Each site then
# runs:
#   hold     a live holder has it, a contender under the shim is refused
#   CONTROL  the same contender against that function with the `mkdir` command put back as the test
#            wins, which proves the case can fail and the shim bites
#   legacy   an older build's directory reads as held, or is taken when it has no holder to wait for
#
# Not here: ci-slot.sh's slot claim. It runs under the repo mutex, so a false win needs a writer outside
# that mutex; check-mkdir-lock.sh pins its form and test-ci-slot.sh its behaviour.
#
# Portability: bash 3.2 safe (macOS) + Linux CI. No sed -i, no mapfile, offline.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
HOLDERS=""
cleanup() { for p in $HOLDERS; do kill "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  PASS: $1"; }
no() { fail=$((fail + 1)); echo "  FAIL: $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — expected '$2', got '$3'"; fi; }

SHIM="$T/false-win-bin"; mkdir -p "$SHIM"
printf '#!/bin/sh\n"%s" "$@" 2>/dev/null && exit 0\nfor a in "$@"; do l="$a"; done\n[ -d "$l" ] && exit 0\nexit 1\n' "$(command -v mkdir)" > "$SHIM/mkdir"
chmod +x "$SHIM/mkdir"

echo "== the shim is what it claims"
d="$T/shimcheck"; mkdir "$d"
if PATH="$SHIM:$PATH" mkdir "$d" 2>/dev/null; then ok "the shim exits 0 on an existing directory"; else no "the shim does not bite"; fi

# fn <file> <name> — one function's text from a script. Ends at the closing brace in column 0, or on
# its own line for a one-line function.
fn() {
  awk -v n="$2" '
    index($0, n "() {") == 1 { on = 1; print; if ($0 ~ /; *}[ \t]*$/) on = 0; next }
    on { print; if ($0 ~ /^}/) on = 0 }' "$1"
}

# snippet <out> <script> <sed expr or ""> <prelude> <fn>... — a sourceable file with the script's own
# functions after <sed expr> (the control's mutation, or a test-only change to both forms). <take>
# is then called with $L set. Fails when a function is missing, so a rename cannot make a site vacuous.
snippet() {
  local out="$1" src="$2" expr="$3" pre="$4" f text; shift 4
  local tmp="$out.src"
  if [ -n "$expr" ]; then sed -e "$expr" "$src" > "$tmp"; else cp "$src" "$tmp"; fi
  printf '%s\n' "$pre" > "$out"
  for f in "$@"; do
    text="$(fn "$tmp" "$f")"
    [ -n "$text" ] || { no "$src has no function $f — this site proves nothing"; return 1; }
    printf '%s\n' "$text" >> "$out"
  done
  bash -n "$out" 2>/dev/null || { no "$out does not parse"; return 1; }
}

# hold <snippet> <take> <lock> — a live holder takes it; prints what a contender under the shim got
# (0 = it won too). The holder execs sleep so the pid it stamped stays alive for the whole check.
hold_then_contend() {
  local s="$1" take="$2" L="$3" ready="$3.ready.$$" h i=0 rc
  L="$L" bash -c '. "$0"; '"$take"' || exit 1; : > "$1"; exec sleep 60' "$s" "$ready" >/dev/null 2>&1 &
  h=$!; HOLDERS="$HOLDERS $h"
  while [ ! -e "$ready" ] && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
  if [ ! -e "$ready" ]; then kill "$h" 2>/dev/null; echo "holder-failed"; return; fi
  PATH="$SHIM:$PATH" L="$L" bash -c '. "$0"; '"$take" "$s" >/dev/null 2>&1; rc=$?
  kill "$h" 2>/dev/null; wait "$h" 2>/dev/null
  rm -rf "$L" "$ready"
  echo "$rc"
}

# site <label> <script> <take> <sed: back to mkdir> <prelude> <pre-sed or ""> <fn>...
site() {
  local label="$1" src="$2" take="$3" back="$4" pre="$5" both="$6" real="$T/$1.real.sh" mut="$T/$1.mut.sh" res; shift 6
  snippet "$real" "$src" "$both" "$pre" "$@" || return 0
  snippet "$mut" "$src" "${both:+$both;}$back" "$pre" "$@" || return 0
  if cmp -s "$real" "$mut"; then no "$label: the control's sed did not change the function — it would prove nothing"; return 0; fi
  res="$(hold_then_contend "$real" "$take" "$T/$label.lk")"
  case "$res" in 0|holder-failed) no "$label: a contender under a false-win mkdir got '$res' (expected refused)" ;; *) ok "$label: a live holder excludes a contender under a false-win mkdir" ;; esac
  res="$(hold_then_contend "$mut" "$take" "$T/$label.lk")"
  is "$label CONTROL: with the mkdir command as the test, the contender wins too" 0 "$res"
}

# legacy <label> <snippet> <take> <stamp or ""> <want rc: 0 or nonzero> — an older build's directory.
legacy() {
  local L="$T/$1.legacy" rc
  mkdir "$L"; [ -z "$4" ] || printf 'x\n' > "$L/$4"
  PATH="$SHIM:$PATH" L="$L" bash -c '. "$0"; '"$3" "$2" >/dev/null 2>&1; rc=$?
  if [ "$5" = 0 ]; then is "$1: legacy: a directory with no holder stamp is taken" 0 "$rc"
  elif [ "$rc" -ne 0 ]; then ok "$1: legacy: a lock directory${4:+ with its $4 stamp} reads as held"
  else no "$1: legacy: the older build's directory was taken"; fi
  rm -rf "$L"
}

# A control's first step: drop the mkdir whose status the real form ignores, so the put-back mkdir is
# the one that creates the directory.
CLAIM='s/^\( *\)mkdir "\$[A-Z_a-z0-9]*" 2>\/dev\/null || :.*$/\1:/'

echo "== locks that keep a directory: the O_EXCL stamp decides"
CLAIM1='s/^\( *\)mkdir "\$1" 2>\/dev\/null || :.*$/\1:/'
P='LOCK_DIR="$L"; LOCK_META="$L/meta"'
site run-lock "$HERE/run-lock.sh" take_lock \
  "$CLAIM;"'s/( set -C; : > "$LOCK_META" ) 2>\/dev\/null \&\& return 0/mkdir "$LOCK_DIR" 2>\/dev\/null \&\& return 0/' "$P" "" take_lock
legacy run-lock "$T/run-lock.real.sh" take_lock meta nonzero
legacy run-lock "$T/run-lock.real.sh" take_lock "" 0

site dispatch-pr-review "$HERE/dispatch-pr-review.sh" take_lock \
  "$CLAIM;"'s/( set -C; : > "$LOCK_META" ) 2>\/dev\/null \&\& return 0/mkdir "$LOCK_DIR" 2>\/dev\/null \&\& return 0/' "$P" "" take_lock
legacy dispatch-pr-review "$T/dispatch-pr-review.real.sh" take_lock meta nonzero

P='LOCK_DIR="$L"; LOCK_WAIT=1; LOCK_HELD=0; RECLAIM_MARK=""; RECLAIMED=0; die() { exit 1; }; warn() { :; }'
site meta-sync "$HERE/meta-sync.d/lock.sh" acquire_lock \
  "$CLAIM;"'s/if ( set -C; : > "$LOCK_DIR\/pid" ) 2>\/dev\/null; then/if mkdir "$LOCK_DIR" 2>\/dev\/null; then/' "$P" "" \
  lock_holder_alive lock_is_stale reclaim_lock acquire_lock
L="$T/ms-legacy"; mkdir "$L"; sleep 60 & lp=$!; HOLDERS="$HOLDERS $lp"; printf '%s\n' "$lp" > "$L/pid"
PATH="$SHIM:$PATH" L="$L" bash -c '. "$0"; acquire_lock' "$T/meta-sync.real.sh" >/dev/null 2>&1; rc=$?
kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
if [ "$rc" -ne 0 ] && [ "$(cat "$L/pid")" = "$lp" ]; then ok "meta-sync: legacy: a directory naming a live pid reads as held and stays"; else no "meta-sync: legacy: rc=$rc pid=$(cat "$L/pid" 2>/dev/null)"; fi
PATH="$SHIM:$PATH" L="$L" bash -c '. "$0"; acquire_lock' "$T/meta-sync.real.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(cat "$L/pid")" != "$lp" ]; then ok "meta-sync: legacy: the same directory is reclaimed once that pid is dead"; else no "meta-sync: legacy: not reclaimed, rc=$rc"; fi
rm -rf "$L"
# the reclaim marker: of two reclaimers, one (the marker's pid file is held by a live process).
M="$T/ms-marker"; mkdir "$M" "$M.reclaim.1234"; sleep 60 & lp=$!; HOLDERS="$HOLDERS $lp"; printf '%s\n' "$lp" > "$M.reclaim.1234/pid"; printf '1234\n' > "$M/pid"
PATH="$SHIM:$PATH" L="$M" bash -c '. "$0"; reclaim_lock "$L" 1234 0; [ "$RECLAIMED" = 1 ]' "$T/meta-sync.real.sh" >/dev/null 2>&1; rc=$?
kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
if [ "$rc" -ne 0 ] && [ -e "$M/pid" ]; then ok "meta-sync: a reclaim marker held by a live process keeps a second reclaimer out"; else no "meta-sync: the second reclaimer acted, rc=$rc"; fi

P='PROG=test; INDEX_LOCK_WAIT_SECS=0; index_lock=""; index_lock_token=""; index_lock_seq=0; index_breaker=""'
site write-agent-memory "$HERE/write-agent-memory.sh" '_take_index_lock "$L"' \
  "$CLAIM;"'s/( set -C; : > "$lock\/owner" ) 2>\/dev\/null || return 1/mkdir "$lock" 2>\/dev\/null || return 1/' "$P" "" _take_index_lock
snippet "$T/wam.plain.sh" "$HERE/write-agent-memory.sh" "" "$P" _take_index_lock
legacy write-agent-memory "$T/wam.plain.sh" '_take_index_lock "$L"' owner nonzero
legacy write-agent-memory "$T/wam.plain.sh" '_take_index_lock "$L"' "" 0

P='NS_CM_LOCK=""; NS_CM_LOCK_TOKEN=""; NS_CM_BREAKER=""'
site automate-next-step "$HERE/automate-next-step.sh" 'ns_cm_take "$L"' \
  "$CLAIM1;"'s/( set -C; : > "$1\/owner" ) 2>\/dev\/null || return 1/mkdir "$1" 2>\/dev\/null || return 1/' "$P" "" ns_cm_take
snippet "$T/ns.plain.sh" "$HERE/automate-next-step.sh" "" "$P" ns_cm_take
legacy automate-next-step "$T/ns.plain.sh" 'ns_cm_take "$L"' owner nonzero

P='_LT_ME=""'
site lane-table "$HERE/automate-lanes.d/common.sh" '_lt_take "$L"' \
  "$CLAIM1;"'s/( set -C; printf .%s\\n. "$(_lt_me)" > "$1\/holder" ) 2>\/dev\/null/mkdir "$1" 2>\/dev\/null/' "$P" "" _trim_ws _lt_me _lt_take
snippet "$T/lt.plain.sh" "$HERE/automate-lanes.d/common.sh" "" "$P" _trim_ws _lt_me _lt_take
legacy lane-table "$T/lt.plain.sh" '_lt_take "$L"' holder nonzero
# the lane-table's reclaim guard: with the guard held, a reclaim waits and removes nothing yet.
snippet "$T/lt.reclaim.sh" "$HERE/automate-lanes.d/common.sh" 's/sleep 0\.1/return 7/' "$P" _lt_holder _lt_reclaim
L="$T/lt-guard"; mkdir "$L"; printf 'dead\n' > "$L/holder"; : > "$L.reclaim"
PATH="$SHIM:$PATH" L="$L" bash -c '. "$0"; _lt_reclaim "$L" dead' "$T/lt.reclaim.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" = 7 ] && [ -e "$L/holder" ]; then ok "lane-table: the reclaim guard keeps a second reclaimer out"; else no "lane-table: the reclaim guard did not hold, rc=$rc"; fi

echo "== locks with no stamp: an O_EXCL file at the lock path"
P='LOCK_FILE="$L"; STALE_LOCK_SECONDS=60'
site build-state "$HERE/build-state.sh" acquire_lock \
  's/( set -C; : > "$LOCK_FILE" ) 2>\/dev\/null/mkdir "$LOCK_FILE" 2>\/dev\/null/' "$P" "" lock_age_seconds acquire_lock
legacy build-state "$T/build-state.real.sh" acquire_lock "" nonzero
L="$T/bs-aged"; mkdir "$L"; touch -t 200001010000 "$L"
PATH="$SHIM:$PATH" L="$L" bash -c '. "$0"; acquire_lock' "$T/build-state.real.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ -f "$L" ]; then ok "build-state: legacy: an aged directory is broken and replaced by the lock file"; else no "build-state: legacy: aged dir rc=$rc"; fi

# reg_lock breaks a lock after ~5 s by design, so both forms make one attempt: `sleep 0.1` returns.
P='REG_DIR="$L"; '
site write-run "$HERE/adapters/providers/write-run.sh" 'reg_lock' \
  's/until ( set -C; : > "$REG_DIR\/lock" ) 2>\/dev\/null; do/until mkdir "$REG_DIR\/lock" 2>\/dev\/null; do/' "$P" 's/^    sleep 0\.1$/    return 1/' reg_lock
L="$T/wr-legacy"; mkdir -p "$L/lock"
snippet "$T/wr.plain.sh" "$HERE/adapters/providers/write-run.sh" "" "$P" reg_lock reg_unlock
PATH="$SHIM:$PATH" L="$L" bash -c '. "$0"; reg_lock' "$T/wr.plain.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ -f "$L/lock" ]; then ok "write-run: legacy: a stranded directory is broken after the wait and replaced by the lock file"; else no "write-run: legacy rc=$rc"; fi

echo "== real entry points"
RL="$HERE/run-lock.sh"
R="$T/rl"; mkdir -p "$R/.supervisor"
rl() { PATH="$SHIM:$PATH" LOOMWRIGHT_HOLDER_PID=$$ bash "$RL" acquire --root "$R" "$@" 2>/dev/null; }
out="$(rl --owner a --session-id s1)"; is "run-lock.sh: the first acquire holds it" 0 "$?"
out="$(rl --owner b --session-id s2)"; rc=$?
is "run-lock.sh: a second session is refused under a false-win mkdir" 1 "$rc"
case "$out" in run_lock_held\ owner=a*) ok "run-lock.sh: the refusal names the holder" ;; *) no "run-lock.sh: refusal said '$out'" ;; esac
bash "$RL" release --root "$R" --session-id s1 >/dev/null 2>&1
if [ ! -e "$R/.supervisor/run.lock" ]; then ok "run-lock.sh: release removes it"; else no "run-lock.sh: release left the lock"; fi
# A dead pid and an old ts in an older build's directory: reclaimed, same as ever.
mkdir "$R/.supervisor/run.lock"; printf 'pid\t999999\nowner\told\nsession_id\tolds\nts\t1000\n' > "$R/.supervisor/run.lock/meta"
out="$(rl --owner c --session-id s3)"; is "run-lock.sh: legacy: a dead older-build holder past the TTL is reclaimed" 0 "$?"
bash "$RL" release --root "$R" --session-id s3 >/dev/null 2>&1

# Eight racers, repeated: the real script, a real race, the false-win mkdir. Exactly one holds.
over=0; none=0; n=0
while [ "$n" -lt 6 ]; do
  n=$((n + 1)); W="$T/race.$n"; mkdir -p "$W"; i=0
  while [ "$i" -lt 8 ]; do
    i=$((i + 1))
    ( PATH="$SHIM:$PATH" LOOMWRIGHT_HOLDER_PID=$$ bash "$RL" acquire --root "$R" --owner "r$i" --session-id "race-$n-$i" >/dev/null 2>&1 && : > "$W/won.$i" ) &
  done
  wait
  c="$(ls "$W" | wc -l | tr -d ' ')"
  [ "$c" -le 1 ] || over=$((over + 1))
  [ "$c" -ge 1 ] || none=$((none + 1))
  rm -rf "$R/.supervisor/run.lock"
done
is "run-lock.sh: 6 rounds of 8 real racers under a false-win mkdir never had two holders" 0 "$over"
is "run-lock.sh: and every round had a holder" 0 "$none"

SR="$HERE/stamp-requirement-status.sh"
S="$T/stamp"; mkdir -p "$S/.supervisor/jobs/done"
LK="$S/.supervisor/.stamp-requirement-status.lock"
mkdir "$LK"
out="$(PATH="$SHIM:$PATH" bash "$SR" --project-root "$S" 2>&1)"
case "$out" in *"holds the lock"*) ok "stamp-requirement-status.sh: legacy: a fresh older-build directory reads as held" ;; *) no "stamp-requirement-status.sh: legacy: said '$out'" ;; esac
[ -d "$LK" ] && ok "stamp-requirement-status.sh: and it is left alone" || no "stamp-requirement-status.sh: the live directory was removed"
touch -t 200001010000 "$LK"
out="$(PATH="$SHIM:$PATH" bash "$SR" --project-root "$S" 2>&1)"
case "$out" in *"reclaiming stale lock"*) ok "stamp-requirement-status.sh: legacy: an aged directory is reclaimed" ;; *) no "stamp-requirement-status.sh: legacy: aged said '$out'" ;; esac
[ ! -e "$LK" ] && ok "stamp-requirement-status.sh: and released on exit" || no "stamp-requirement-status.sh: the lock survived the run"
SM="$T/stamp-mut"; mkdir -p "$SM"; cp "$HERE/brief-pointer.sh" "$HERE/host-mode.sh" "$SM/"
sed 's/^if ( set -C; : > "$LOCK" ) 2>\/dev\/null; then/if mkdir "$LOCK" 2>\/dev\/null; then/' "$SR" > "$SM/stamp-requirement-status.sh"
if cmp -s "$SR" "$SM/stamp-requirement-status.sh"; then no "stamp-requirement-status.sh CONTROL did not stage"
else
  mkdir "$LK"
  out="$(PATH="$SHIM:$PATH" bash "$SM/stamp-requirement-status.sh" --project-root "$S" 2>&1)"
  case "$out" in
    *"holds the lock"*) no "stamp-requirement-status.sh CONTROL: the mkdir form was still refused, so the case proves nothing" ;;
    *"cannot"*|*"not found"*|*"No such file"*) no "stamp-requirement-status.sh CONTROL: the mutant did not run: $out" ;;
    *) ok "stamp-requirement-status.sh CONTROL: with the mkdir command as the test, a live directory is walked through" ;;
  esac
  rm -rf "$LK"
fi

echo
echo "mkdir-lock false-win test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
