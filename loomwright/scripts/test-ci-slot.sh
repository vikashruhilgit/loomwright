#!/usr/bin/env bash
# test-ci-slot.sh — offline self-test for ci-slot.sh. Every arm runs against fixture git repos in a
# mktemp dir with XDG_STATE_HOME sandboxed there too, so the real shared slot pool (which an outer
# ci-local.sh run may be holding) is never read, queued on or written.
#
# Arms:
#   (K)  repo key: two clones + a linked worktree of one origin → one state dir; another origin →
#        another dir; no origin → keyed by git-common-dir (a worktree shares, a separate clone not);
#        URL forms (scheme, user, port, case of host, .git, trailing /) canonicalise to one key.
#        MUTATION CONTROL: key by git dir ⇒ the two-clone check fails.
#   (N)  job share max(2, floor(CPUs / N)) for N in {1,2,4}; default N = max(1, floor(CPUs / 6));
#        LOOMWRIGHT_CI_SLOTS overrides it
#   (A)  N=2, three acquirers: two hold — recorded under the caller's --pid, whose acquire already
#        exited, so it is NOT taken over — the third (--wait 1) exits 1 with its ticket gone
#   (W)  a queued waiter: stderr carries the position line, stdout ONLY `slot=<k> jobs=<j>`;
#        status --json lists holders + the waiter; a release hands it the slot
#   (F)  fairness: a free slot goes only to the lowest LIVE ticket; a dead queued pid is skipped.
#        MUTATION CONTROL: drop the ticket-order check ⇒ the fairness check fails.
#   (D)  a slot whose holder pid is dead is taken over
#   (M)  a counter mutex left by a dead pid (or pid-less and old) is taken over, not waited on
#   (I)  TERM to a queued waiter ⇒ exit 1 at once (not after its poll period), its ticket removed
#   (R)  release is idempotent (nothing held ⇒ exit 0); --slot frees one slot
#   (U)  usage: acquire without --pid ⇒ exit 2; unknown subcommand ⇒ exit 2; non-numeric --pid,
#        --slot, --wait, --slots 0 and --slots abc ⇒ exit 2 with that option's own message and no
#        ticket/slot/counter change; --help = the header. Zero-padded numbers are decimal:
#        --slots 010 = 10, --slots 08 / LOOMWRIGHT_CI_SLOTS=09 / LOOMWRIGHT_CI_CPUS=040 / --wait 08 /
#        --pid 0<pid> / --slot 01 / PRINT_EVERY=08 neither crash nor read as octal.
#        MUTATION CONTROL: drop the --slots -gt 0 check ⇒ the --slots 0 check fails.
#        MUTATION CONTROL: drop the --slots normalisation ⇒ the --slots 010 check fails.
# run-self-tests: serial
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/ci-slot.sh"
[ -f "$SUT" ] || { echo "test-ci-slot: $SUT not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "test-ci-slot: FATAL: jq required" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ci-slot-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
pids=""
trap 'for p in $pids; do kill "$p" 2>/dev/null; done; rm -rf "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"
unset LOOMWRIGHT_CI_SLOTS LOOMWRIGHT_CI_CPUS
export LOOMWRIGHT_CI_SLOT_POLL=0.1 LOOMWRIGHT_CI_SLOT_PRINT_EVERY=1

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }

# live — a long-lived holder process (its pid outlives every acquire call); dead — a reaped pid.
live() { sleep 120 & LIVE=$!; pids="$pids $LIVE"; }
dead() { sleep 0 & DEAD=$!; wait "$DEAD" 2>/dev/null; }
# at DIR [SUT] -- ARGS: run the helper with DIR as the checkout.
at() { local d="$1" s="$SUT"; shift; if [ "$1" != "--" ]; then s="$1"; shift; fi; shift; (cd "$d" && bash "$s" "$@"); }

URL="https://example.invalid/team/proj.git"
mkrepo() { git init -q "$1" && (cd "$1" && git config user.email t@t && git config user.name t \
  && echo x > f && git add f && git commit -qm init) ; }
mkrepo "$tmp/base"
git clone -q "$tmp/base" "$tmp/c1"; git clone -q "$tmp/base" "$tmp/c2"; git clone -q "$tmp/base" "$tmp/c3"
(cd "$tmp/c1" && git remote set-url origin "$URL" && git worktree add -q "$tmp/wt1" -b wt1 2>/dev/null)
(cd "$tmp/c2" && git remote set-url origin "$URL")
(cd "$tmp/c3" && git remote set-url origin "https://example.invalid/team/other.git")
mkrepo "$tmp/solo"; (cd "$tmp/solo" && git worktree add -q "$tmp/solo-wt" -b swt 2>/dev/null)
mkrepo "$tmp/solo2"

# --- (K) -------------------------------------------------------------------------------------------
shares() { [ "$(at "$tmp/c1" "$1" -- dir)" = "$(at "$tmp/c2" "$1" -- dir)" ]; }
d1="$(at "$tmp/c1" -- dir)"
case "$d1" in "$tmp/state/loomwright/ci-slots/"?*) ok "(K) state dir is <XDG_STATE_HOME>/loomwright/ci-slots/<repo-key>" ;;
  *) no "(K) unexpected state dir: $d1"; exit 1 ;; esac
if shares "$SUT" && [ "$d1" = "$(at "$tmp/wt1" -- dir)" ]; then ok "(K) two clones + a linked worktree of one origin share one dir"
else no "(K) same origin did not share: c1=$d1 c2=$(at "$tmp/c2" -- dir) wt1=$(at "$tmp/wt1" -- dir)"; fi
if [ "$d1" != "$(at "$tmp/c3" -- dir)" ]; then ok "(K) a different origin gets a different dir"; else no "(K) two origins collided"; fi
s1="$(at "$tmp/solo" -- dir)"
if [ "$s1" = "$(at "$tmp/solo-wt" -- dir)" ] && [ "$s1" != "$(at "$tmp/solo2" -- dir)" ] && [ "$s1" != "$d1" ]; then
  ok "(K) no origin: keyed by git-common-dir (its worktree shares, another repo does not)"
else no "(K) no-origin keying wrong: solo=$s1 solo-wt=$(at "$tmp/solo-wt" -- dir) solo2=$(at "$tmp/solo2" -- dir)"; fi
keyof() { (cd "$tmp/solo2" && git remote remove origin 2>/dev/null; git remote add origin "$1" && bash "$SUT" dir); }
k1="$(keyof "https://Example.invalid/team/proj.git/")"
same=1
for u in "https://example.invalid/team/proj" "ssh://git@example.invalid:2222/team/proj.git" \
         "git@example.invalid:team/proj.git" "https://user@EXAMPLE.invalid/team/proj/"; do
  [ "$(keyof "$u")" = "$k1" ] || { same=0; no "(K) URL form did not canonicalise: $u"; }
done
[ "$same" -eq 1 ] && ok "(K) scheme/user/port/host-case/.git/trailing-/ forms share one key"
if [ "$(keyof "https://other.invalid/team/proj.git")" != "$k1" ]; then ok "(K) same owner/repo on another host keys apart"
else no "(K) two hosts collided"; fi
(cd "$tmp/solo2" && git remote remove origin)
# MUTATION CONTROL — key by git dir instead of origin.
mut="$tmp/mut-key.sh"
sed 's/^  origin="\$(git remote get-url origin 2>\/dev\/null || true)"$/  origin=""/' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if shares "$mut"; then no "(K) MUTATION CONTROL: keying by git dir still shared across clones — (K) proves nothing"
  else ok "(K) MUTATION CONTROL: keying by git dir breaks two-clone sharing"; fi
else no "(K) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# --- (N) -------------------------------------------------------------------------------------------
share() { at "$tmp/solo2" -- status --json | jq -r '"\(.slots) \(.jobs)"'; }
nok=1
for c in 12 4 3 24 1; do
  for n in 1 2 4; do
    want=$(( c / n )); [ "$want" -ge 2 ] || want=2
    got="$(LOOMWRIGHT_CI_CPUS=$c LOOMWRIGHT_CI_SLOTS=$n share)"
    [ "$got" = "$n $want" ] || { nok=0; no "(N) cpus=$c N=$n: got '$got', want '$n $want'"; }
  done
  dn=$(( c / 6 )); [ "$dn" -ge 1 ] || dn=1
  dj=$(( c / dn )); [ "$dj" -ge 2 ] || dj=2
  got="$(LOOMWRIGHT_CI_CPUS=$c share)"
  [ "$got" = "$dn $dj" ] || { nok=0; no "(N) cpus=$c default: got '$got', want '$dn $dj'"; }
done
[ "$nok" -eq 1 ] && ok "(N) jobs = max(2, floor(CPUs/N)) for N in {1,2,4}; default N = max(1, floor(CPUs/6))"
if [ "$(LOOMWRIGHT_CI_CPUS=12 at "$tmp/solo2" -- status --json --slots 3 | jq -r .slots)" = 3 ]; then ok "(N) --slots overrides"
else no "(N) --slots ignored"; fi

# --- (A) N=2, three acquirers ------------------------------------------------------------------------
export LOOMWRIGHT_CI_SLOTS=2 LOOMWRIGHT_CI_CPUS=12
live; h1=$LIVE; live; h2=$LIVE; live; h3=$LIVE
a1="$(at "$tmp/c1" -- acquire h1 --pid "$h1")"; a2="$(at "$tmp/c2" -- acquire h2 --pid "$h2")"
st="$(at "$tmp/c1" -- status --json)"
if [ "$a1" = "slot=1 jobs=6" ] && [ "$a2" = "slot=2 jobs=6" ] \
   && [ "$(jq -c '[.holders[] | [.slot, .pid]]' <<<"$st")" = "[[1,$h1],[2,$h2]]" ]; then
  ok "(A) two acquirers hold slots 1 and 2, recorded under their callers' --pid"
else no "(A) a1=$a1 a2=$a2 status=$st"; fi
a3="$(at "$tmp/wt1" -- acquire h3 --pid "$h3" --wait 1 2>"$tmp/a3.err")"; rc=$?
st="$(at "$tmp/c1" -- status --json)"
if [ "$rc" -ne 0 ] && [ -z "$a3" ] && [ "$(jq '.waiters | length' <<<"$st")" = 0 ] && [ -z "$(ls "$d1/tickets")" ] \
   && [ "$(jq -c '[.holders[].pid]' <<<"$st")" = "[$h1,$h2]" ]; then
  ok "(A) third acquirer: live holders (acquire long gone) NOT taken over; --wait 1 exits $rc, ticket gone"
else no "(A) third: rc=$rc out=$a3 tickets=[$(ls "$d1/tickets")] status=$st err=$(cat "$tmp/a3.err")"; fi

# --- (W) a queued waiter ---------------------------------------------------------------------------
(cd "$tmp/wt1" && bash "$SUT" acquire h3 --pid "$h3" --wait 30 >"$tmp/w.out" 2>"$tmp/w.err"; echo "$?" >"$tmp/w.rc") &
wpid=$!
i=0
while [ "$(at "$tmp/c1" -- status --json | jq '.waiters | length')" != 1 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
st="$(at "$tmp/c1" -- status --json)"
if [ "$(jq -c '[.waiters[] | [.pid, .name, .checkout]]' <<<"$st")" = "[[$h3,\"h3\",\"$tmp/wt1\"]]" ] \
   && [ "$(jq -c '[.holders[] | [.name, .checkout, (.started > 0)]]' <<<"$st")" = "[[\"h1\",\"$tmp/c1\",true],[\"h2\",\"$tmp/c2\",true]]" ]; then
  ok "(W) status --json: holders (pid, checkout, name, started) and the queued waiter"
else no "(W) status=$st"; fi
sleep 1.2   # at least one more progress period
at "$tmp/c2" -- release --pid "$h2"
wait "$wpid"
if [ "$(cat "$tmp/w.rc")" = 0 ] && [ "$(cat "$tmp/w.out")" = "slot=2 jobs=6" ] \
   && grep -q "waiting for a CI slot — position 1, holders: h1 (" "$tmp/w.err" \
   && ! grep -q "slot=" "$tmp/w.err"; then
  ok "(W) waiter got the released slot; stdout ONLY 'slot=2 jobs=6', progress on stderr"
else no "(W) rc=$(cat "$tmp/w.rc") out=[$(cat "$tmp/w.out")] err=[$(cat "$tmp/w.err")]"; fi
[ "$(grep -c 'waiting for a CI slot' "$tmp/w.err")" -ge 2 ] && ok "(W) the position line repeats while waiting" \
  || no "(W) position line printed once only: $(cat "$tmp/w.err")"

# --- (F) fairness ----------------------------------------------------------------------------------
# One free slot; a LIVE pid holds an earlier ticket (planted at 0, below any the counter issues).
fair_blocks() {   # fair_blocks SUT — exit 0 iff a newcomer is kept out by the earlier live ticket
  local s="$1" q n
  live; q=$LIVE; live; n=$LIVE
  printf '%s\n%s\n%s\n%s\n' "$q" "$tmp/c1" early "$(date +%s)" > "$d1/tickets/0"
  at "$tmp/wt1" -- release --pid "$h3" >/dev/null
  if at "$tmp/c2" "$s" -- acquire late --pid "$n" --wait 1 >/dev/null 2>&1; then
    at "$tmp/c2" "$s" -- release --pid "$n"; FQ=$q; return 1
  fi
  FQ=$q; FN=$n; return 0
}
if fair_blocks "$SUT"; then ok "(F) a free slot is NOT given past an earlier live ticket"
else no "(F) a newcomer jumped the queue"; fi
kill "$FQ" 2>/dev/null; wait "$FQ" 2>/dev/null
got="$(at "$tmp/c2" -- acquire late --pid "$FN" --wait 5 2>/dev/null)"
if [ "$got" = "slot=2 jobs=6" ] && [ ! -e "$d1/tickets/0" ]; then ok "(F) the dead queued pid's ticket is skipped and removed; next live ticket gets the slot"
else no "(F) dead-ticket skip: got=$got tickets=[$(ls "$d1/tickets")]"; fi
h3=$FN
# MUTATION CONTROL — drop the lowest-live-ticket check.
mut="$tmp/mut-fair.sh"
grep -v '\[ "$(live_tickets | head -n 1)" = "$MY_TICKET" \] || return 1' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if fair_blocks "$mut"; then no "(F) MUTATION CONTROL: without ticket order the newcomer was still kept out — (F) proves nothing"
  else ok "(F) MUTATION CONTROL: without ticket order the newcomer jumps the queue"; fi
else no "(F) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi
kill "$FQ" 2>/dev/null; wait "$FQ" 2>/dev/null; rm -f "$d1/tickets/0"
at "$tmp/c1" -- release --pid "$h3"

# --- (D) dead holder -------------------------------------------------------------------------------
kill "$h1" 2>/dev/null; wait "$h1" 2>/dev/null
live; h4=$LIVE
got="$(at "$tmp/c2" -- acquire h4 --pid "$h4" --wait 1 2>"$tmp/d.err")"
if [ "$got" = "slot=1 jobs=6" ] && grep -q "taking over slot 1 (holder pid $h1 is gone)" "$tmp/d.err"; then
  ok "(D) a slot whose holder pid is dead is taken over"
else no "(D) got=$got err=$(cat "$tmp/d.err")"; fi
at "$tmp/c2" -- release --pid "$h4"

# --- (M) stale counter mutex -------------------------------------------------------------------------
dead; mkdir "$d1/mutex"; echo "$DEAD" > "$d1/mutex/pid"
live; h5=$LIVE
got="$(at "$tmp/c1" -- acquire h5 --pid "$h5" --wait 1 2>"$tmp/m.err")"
if [ -n "$got" ] && grep -q "stale counter mutex (pid $DEAD is gone)" "$tmp/m.err" && [ ! -d "$d1/mutex" ]; then
  ok "(M) a mutex left by a dead pid is taken over at once"
else no "(M) got=$got err=$(cat "$tmp/m.err")"; fi
at "$tmp/c1" -- release --pid "$h5"
mkdir "$d1/mutex"; touch -t 202001010000 "$d1/mutex"
got="$(at "$tmp/c1" -- acquire h5 --pid "$h5" --wait 1 2>"$tmp/m.err")"
if [ -n "$got" ] && grep -q "no pid file for 30s+" "$tmp/m.err"; then ok "(M) a pid-less mutex older than 30 s is taken over"
else no "(M) pid-less: got=$got err=$(cat "$tmp/m.err")"; fi

# --- (I) TERM to a queued waiter ---------------------------------------------------------------------
# Both slots held; a waiter with a 30 s poll period. Its TERM trap must run at once, not after the poll.
live; h6=$LIVE; live; h7=$LIVE
at "$tmp/c2" -- acquire h6 --pid "$h6" >/dev/null
(cd "$tmp/c1" && LOOMWRIGHT_CI_SLOT_POLL=30 exec bash "$SUT" acquire h7 --pid "$h7" --wait 120 >/dev/null 2>&1) &
ipid=$!
i=0
while [ "$(at "$tmp/c1" -- status --json | jq '.waiters | length')" != 1 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
sleep 0.3   # past the claim attempt, into the poll wait
kill -TERM "$ipid" 2>/dev/null
i=0
while kill -0 "$ipid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
if kill -0 "$ipid" 2>/dev/null; then irc="still-running"; kill -KILL "$ipid" 2>/dev/null; wait "$ipid" 2>/dev/null
else wait "$ipid"; irc=$?; fi
if [ "$irc" = 1 ] && [ -z "$(ls "$d1/tickets")" ]; then ok "(I) TERM to a queued waiter: exits 1 within 3s (not after its 30 s poll), ticket gone"
else no "(I) rc=$irc tickets=[$(ls "$d1/tickets")]"; fi
# On failure the waiter was SIGKILLed with its ticket in place: drop h7 so that ticket is dead and
# the later arms are not queued behind it.
at "$tmp/c2" -- release --pid "$h6"; at "$tmp/c1" -- release --pid "$h7"
kill "$h7" 2>/dev/null; wait "$h7" 2>/dev/null

# --- (R) release -----------------------------------------------------------------------------------
at "$tmp/c1" -- release --pid "$h5"; r1=$?
at "$tmp/c1" -- release --pid "$h5"; r2=$?
if [ "$r1" = 0 ] && [ "$r2" = 0 ] && [ "$(at "$tmp/c1" -- status --json | jq '.holders | length')" = 0 ]; then
  ok "(R) release frees the slot; a second release (nothing held) exits 0"
else no "(R) r1=$r1 r2=$r2"; fi
at "$tmp/c1" -- acquire h5 --pid "$h5" >/dev/null
at "$tmp/c1" -- release --slot 1
if [ ! -d "$d1/slots/1" ]; then ok "(R) release --slot frees that slot"; else no "(R) --slot left slot 1"; fi

# --- (U) usage -------------------------------------------------------------------------------------
at "$tmp/c1" -- acquire nopid >/dev/null 2>&1; r1=$?
at "$tmp/c1" -- bogus >/dev/null 2>&1; r2=$?
if [ "$r1" = 2 ] && [ "$r2" = 2 ]; then ok "(U) acquire without --pid and an unknown subcommand exit 2"; else no "(U) r1=$r1 r2=$r2"; fi
# Malformed option values: each must exit 2 with ITS OWN parser message (the later LOOMWRIGHT_CI_SLOTS
# guard also exits 2 on a zero slot count, so exit code alone cannot pin the --slots guard) and leave
# no ticket, slot or counter bump behind. Every call names a live --pid so only the bad value is wrong.
live; hu=$LIVE
refuses() {   # refuses SUT MSG -- ARGS: exit 2, stderr names MSG, state untouched
  local s="$1" m="$2" c0 rc; shift 3
  c0="$(cat "$d1/counter" 2>/dev/null)"
  at "$tmp/c1" "$s" -- "$@" >"$tmp/u.out" 2>"$tmp/u.err"; rc=$?
  [ "$rc" = 2 ] && [ ! -s "$tmp/u.out" ] && grep -qF -- "ci-slot: $m" "$tmp/u.err" \
    && [ -z "$(ls "$d1/tickets")" ] && [ -z "$(ls "$d1/slots")" ] \
    && [ "$(cat "$d1/counter" 2>/dev/null)" = "$c0" ]
}
uok=1
for spec in "--pid needs a numeric pid|acquire u --pid abc" \
            "--slot needs a number|release --slot abc" \
            "--slots needs a positive integer|acquire u --pid $hu --wait 0 --slots 0" \
            "--slots needs a positive integer|acquire u --pid $hu --wait 0 --slots abc" \
            "--wait needs seconds|acquire u --pid $hu --wait abc"; do
  # shellcheck disable=SC2086  # the arg list is word-split on purpose
  refuses "$SUT" "${spec%%|*}" -- ${spec#*|} || { uok=0; no "(U) not refused cleanly: ${spec#*|} — rc/err=[$(cat "$tmp/u.err")] tickets=[$(ls "$d1/tickets")] slots=[$(ls "$d1/slots")]"; }
done
[ "$uok" -eq 1 ] && ok "(U) non-numeric --pid/--slot/--wait, --slots 0 and --slots abc each exit 2 with their own message, no ticket/slot left"
# MUTATION CONTROL — drop the --slots -gt 0 check (the later env guard still exits 2, so only the
# parser message tells them apart).
mut="$tmp/mut-slots.sh"
sed 's/is_uint "\$2" && \[ "\$2" -gt 0 \] || die "--slots/is_uint "$2" || die "--slots/' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if refuses "$mut" "--slots needs a positive integer" -- acquire u --pid "$hu" --wait 0 --slots 0; then
    no "(U) MUTATION CONTROL: without the -gt 0 guard --slots 0 was still refused by the parser — (U) proves nothing"
  else ok "(U) MUTATION CONTROL: without the -gt 0 guard --slots 0 is no longer refused by the parser"; fi
else no "(U) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi
# Zero-padded numbers are decimal: with 40 CPUs, 10 slots ⇒ 4 jobs, octal 8 slots ⇒ 5 jobs.
padded() { LOOMWRIGHT_CI_CPUS=40 at "$tmp/c1" "$1" -- status --slots 010 2>&1 | grep '^slots:'; }
want10="slots: 10  cpus: 40  jobs per slot: 4"
if [ "$(padded "$SUT")" = "$want10" ]; then ok "(U) --slots 010 is 10 slots (jobs 4 of 40 CPUs), not octal 8"
else no "(U) --slots 010: got '$(padded "$SUT")', want '$want10'"; fi
got="$(LOOMWRIGHT_CI_CPUS=40 at "$tmp/c1" -- status --slots 08 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qx "slots: 8  cpus: 40  jobs per slot: 5" <<<"$got"; then ok "(U) --slots 08 is 8 slots, no 'value too great for base' crash"
else no "(U) --slots 08: rc=$rc out=[$got]"; fi
got="$(LOOMWRIGHT_CI_SLOTS=09 LOOMWRIGHT_CI_CPUS=040 at "$tmp/c1" -- status 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -qx "slots: 9  cpus: 40  jobs per slot: 4" <<<"$got"; then ok "(U) LOOMWRIGHT_CI_SLOTS=09 / LOOMWRIGHT_CI_CPUS=040 read as decimal 9 / 40"
else no "(U) padded env: rc=$rc out=[$got]"; fi
got="$(LOOMWRIGHT_CI_SLOT_PRINT_EVERY=08 LOOMWRIGHT_CI_CPUS=40 at "$tmp/c1" -- acquire u --pid "0$hu" --wait 08 --slots 08 2>"$tmp/u.err")"; rc=$?
if [ "$rc" = 0 ] && [ "$got" = "slot=1 jobs=5" ] && [ "$(jq -c '[.holders[].pid]' <<<"$(at "$tmp/c1" -- status --json)")" = "[$hu]" ]; then
  ok "(U) acquire --wait 08 --slots 08 --pid 0<pid> (PRINT_EVERY=08): claims slot 1, recorded under the decimal pid"
else no "(U) padded acquire: rc=$rc out=[$got] err=[$(cat "$tmp/u.err")]"; fi
had="$(ls "$d1/slots")"; at "$tmp/c1" -- release --slot 01
if [ "$had" = 1 ] && [ -z "$(ls "$d1/slots")" ]; then ok "(U) release --slot 01 frees slot 1"; else no "(U) --slot 01 left [$(ls "$d1/slots")]"; fi
# MUTATION CONTROL — drop the --slots normalisation ⇒ 010 is read as octal 8 by the job share.
mut="$tmp/mut-pad.sh"
sed 's/SLOTS="\$((10#\$2))"/SLOTS="$2"/; s/^SLOTS=\$((10#\$SLOTS))$//' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if [ "$(padded "$mut")" = "$want10" ]; then no "(U) MUTATION CONTROL: without normalisation --slots 010 still gave 10 slots — (U) proves nothing"
  else ok "(U) MUTATION CONTROL: without normalisation --slots 010 is no longer 10 slots ($(padded "$mut"))"; fi
else no "(U) MUTATION CONTROL: padded mutant not built (empty, unchanged or invalid)"; fi
kill "$hu" 2>/dev/null; wait "$hu" 2>/dev/null
out="$(bash "$SUT" --help)"
if grep -q '^ci-slot.sh — ' <<<"$out" && grep -q '^Self-test: loomwright/scripts/test-ci-slot.sh' <<<"$out" \
   && ! grep -q 'set -uo' <<<"$out"; then ok "(U) --help prints the de-commented header"
else no "(U) --help: $out"; fi

echo
echo "test-ci-slot: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
