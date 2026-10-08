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
#   (X)  mixed N, claim by count: an N=2 holder in slot 1, an N=1 waiter, then an N=2 waiter ⇒ the
#        N=2 waiter gets slot 2 promptly while the N=1 waiter keeps waiting (status --json shows its
#        "slots":1); with the only live holder in slot 2 the N=1 waiter still cannot claim slot 1;
#        once nothing runs it gets slot 1.
#        MUTATION CONTROL: revert to head-ticket-only + index scan over 1..N ⇒ the (X) check fails.
#   (D)  a slot whose holder pid is dead is taken over
#   (M)  a counter mutex (mutex.lnk) left by a dead pid is taken over at once
#   (P)  no stranded mutex: a pre-planted garbage-target mutex.lnk plus a pid-less legacy mutex/ dir
#        do not stall an acquire --wait 2 (done within 3 s); TERM to a waiter while its `ln` of the
#        mutex is in flight (an `ln` shim on PATH delays it 1 s) leaves no mutex.lnk behind, and the
#        next acquire --wait 2 claims within 3 s
#   (L)  deadline: a mutex.lnk held by a LIVE unrelated pid makes acquire --wait 2 exit 1 within 6 s
#        (W + 1 s mutex grace + one poll + 1 s clock granularity), ticket-less — never an unbounded wait on the mutex
#   (I)  TERM to a queued waiter ⇒ exit 1 at once (not after its poll period), its ticket removed
#   (R)  release is idempotent (nothing held ⇒ exit 0); --slot frees one slot
#   (U)  usage: acquire without --pid ⇒ exit 2; unknown subcommand ⇒ exit 2; non-numeric --pid,
#        --slot, --wait, --slots 0 and --slots abc ⇒ exit 2 with that option's own message and no
#        ticket/slot/counter change; --help = the header. Zero-padded numbers are decimal:
#        --slots 010 = 10, --slots 08 / LOOMWRIGHT_CI_SLOTS=09 / LOOMWRIGHT_CI_CPUS=040 / --wait 08 /
#        --pid 0<pid> / --slot 01 / PRINT_EVERY=08 neither crash nor read as octal.
#        MUTATION CONTROL: drop the --slots -gt 0 check ⇒ the --slots 0 check fails.
#        MUTATION CONTROL: drop the --slots normalisation ⇒ the --slots 010 check fails.
#   (G)  machine gate — every arm uses a sandboxed LOOMWRIGHT_MACHINE_STATE_DIR and a fixture reader
#        (LOOMWRIGHT_MACHINE_LOAD_CMD, never the real machine-load.sh), so a loaded dev machine cannot
#        hold this suite and the real machine list is never touched:
#        (G1) busy: a second machine-wide holder waits ("held for load: busy"), from a clone with a
#             local-path origin and its own XDG_STATE_HOME; under ok both are listed in ONE machine
#             holders list, seen from either repo's status (AC3)
#        (G2) overloaded: two queued callers keep their tickets in order, status shows
#             `held for load: overloaded load1=<n>`; flipped to ok ⇒ the first is granted within one
#             re-check, then the second. MUTATION CONTROL: drop the admission call ⇒ (G2) fails.
#        (G3) a held caller still times out at --wait, ticket gone
#        (G4) fail-SAFE: a reader answering unknown, exiting non-zero, printing garbage or missing
#             grants exactly as ok (with a live holder present, so busy would have held)
#        (G5) nested: an acquire whose --pid descends from a live machine holder folds into it —
#             granted at once under busy AND overloaded, no second machine record (bypass (a))
#        (G6) a caller whose machine-state-dir override points at another sandbox is isolated from
#             this list (bypass (b)); (G7) a bare caller adds exactly one record, release (--pid and
#             --slot) removes it (bypass (c))
#        (G8) status, status --json, dir and release never wait on the gate: a held machine mutex
#             and a hanging reader do not slow them
#        (G9) no signal: code lines of ci-slot.sh and machine-load.sh send none (`kill -0` liveness
#             probes only, no pkill / killall). MUTATION CONTROL: an injected `kill` is caught.
#        (G10) a SLOW reader is not a broken one: one that answers overloaded after 6 s (past the 5 s
#             wait) holds a caller while a live holder exists (read as busy meanwhile, then its own
#             overloaded answer is taken: one reader run, the cached reading never 'unknown'); a
#             hanging reader with an answered overloaded reading under 60 s old holds even with no
#             holder; with that reading older than 60 s it reads busy and grants a sole caller.
#             MUTATION CONTROL: a timed-out reader read as unknown ⇒ the slow-reader check fails.
#        (G13) the reader wait is bounded by the clock, not by a count of `sleep` calls: with a PATH
#             `sleep` that adds 0.1 s per call, G10's slow-reader check still holds busy. MUTATION
#             CONTROL: the old 100 x `sleep 0.05` loop restored ⇒ the check fails under that sleep.
#             The same check also passes on a copy forced onto clock_ms's SECONDS fallback.
#        (G11) boot time: a holder record started before boot (fixture LOOMWRIGHT_MACHINE_BOOT_TIME)
#             whose pid is now an ANCESTOR of the caller is dropped, not folded into (held under
#             overloaded); one whose pid is an unrelated live process is dropped, not a phantom
#             holder (granted under busy); an unreadable boot time keeps both (fail-SAFE, today's
#             behaviour). MUTATION CONTROL: drop the boot-time prune ⇒ the fold check fails.
#        (G12) committed work: at load ok, 12 CPUs / 2 slots (6 jobs a suite), three callers from
#             three repo keys ⇒ two granted, the third held ("held for load: committed 12+6 jobs >
#             12 CPUs") and granted once a holder releases. MUTATION CONTROL: drop the cap ⇒ fails.
#        (G14) NESTED (repo-pool fold): with N=1 and its holder alive, a caller whose --pid descends
#             from that holder — from a linked worktree of the same origin, at load overloaded — is
#             granted at once with the holder's slot, records no ticket, slot or machine record, and
#             its release leaves the holder's slot in place; a sibling (not nested) caller still
#             waits and times out. This is the shape of ci-local.sh running run-self-tests.sh, which
#             asks for admission too. MUTATION CONTROL: drop the fold ⇒ the nested caller waits.
#        (G15) NESTED + boot time (the repo-pool twin of G11): a repo slot record started before
#             boot (fixture LOOMWRIGHT_MACHINE_BOOT_TIME) whose pid is now an ANCESTOR of the caller
#             is never folded into — the caller is counted and waits (N=1) — while an unreadable
#             boot time keeps today's fold. MUTATION CONTROL: drop repo_fold's boot-time skip ⇒ the
#             caller folds into the pre-boot record and (G15) fails.
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
# Machine gate: a sandboxed holders list and a fixture reader (machine-load.sh is never run here);
# load.state picks its answer, default ok.
MDIR="$tmp/machine"
export LOOMWRIGHT_MACHINE_STATE_DIR="$MDIR" LOOMWRIGHT_MACHINE_LOAD_CMD="$tmp/load.sh" LOOMWRIGHT_MACHINE_LOAD_RECHECK=1
cat > "$tmp/load.sh" <<'EOF'
m="$(cat "$(dirname "$0")/load.state" 2>/dev/null || echo ok)"
case "$m" in
  fail) echo "state=busy"; exit 3 ;;
  garbage) echo "%%% nonsense" ;;
  hang) sleep 8; echo "state=overloaded" ;;
  slow) sleep 6; echo "load1=40.00"; echo "state=overloaded" ;;
  *) echo "load1=40.00"; echo "state=$m" ;;
esac
EOF

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
# MUTATION CONTROL — drop the ticket-order (fairness) check.
mut="$tmp/mut-fair.sh"
grep -v '# FAIR$' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if fair_blocks "$mut"; then no "(F) MUTATION CONTROL: without ticket order the newcomer was still kept out — (F) proves nothing"
  else ok "(F) MUTATION CONTROL: without ticket order the newcomer jumps the queue"; fi
else no "(F) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi
kill "$FQ" 2>/dev/null; wait "$FQ" 2>/dev/null; rm -f "$d1/tickets/0"
at "$tmp/c1" -- release --pid "$h3"

# --- (X) mixed N: claim by live count ---------------------------------------------------------------
# Runs in solo2 (its own repo key), so the c1 pool above is untouched. Every wait is bounded.
# Holders left live by the sections above stay in the machine list; clear it so the committed-work
# cap (G12) does not count them against this repo-pool test.
rm -rf "$MDIR/holders/"*
ds="$(at "$tmp/solo2" -- dir)"
nwait() {   # nwait N — poll (max 10 s) until status --json lists N waiters
  local i=0
  while [ "$(at "$tmp/solo2" -- status --json | jq '.waiters | length')" != "$1" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
}
xwait() {   # xwait FILE — poll (max 3 s) until FILE is non-empty
  local i=0
  while [ ! -s "$1" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
}
mixed_ok() {   # mixed_ok SUT — exit 0 iff every (X) property holds; XWHY says which failed
  local s="$1" ha hb hn w1 w2 rc=0
  XWHY=""; rm -f "$tmp"/x.*
  live; ha=$LIVE; live; hb=$LIVE; live; hn=$LIVE
  at "$tmp/solo2" "$s" -- acquire xa --pid "$ha" --slots 2 >/dev/null 2>&1
  (cd "$tmp/solo2" && exec bash "$s" acquire xn --pid "$hn" --slots 1 --wait 30 >"$tmp/x.n" 2>/dev/null) &
  w1=$!; pids="$pids $w1"
  nwait 1
  (cd "$tmp/solo2" && exec bash "$s" acquire xb --pid "$hb" --slots 2 --wait 10 >"$tmp/x.b" 2>/dev/null) &
  w2=$!; pids="$pids $w2"
  xwait "$tmp/x.b"
  if [ "$(cat "$tmp/x.b" 2>/dev/null)" != "slot=2 jobs=6" ]; then rc=1; XWHY="N=2 waiter did not get slot 2 within 3 s (got '$(cat "$tmp/x.b" 2>/dev/null)')"
  elif [ -s "$tmp/x.n" ] || [ "$(at "$tmp/solo2" -- status --json | jq -c '[.waiters[] | [.pid, .slots]]')" != "[[$hn,1]]" ]; then
    rc=1; XWHY="N=1 waiter claimed past 1 live holder (out '$(cat "$tmp/x.n")')"
  else
    at "$tmp/solo2" -- release --pid "$ha"   # the only live holder is now in slot 2
    sleep 0.6
    if [ -s "$tmp/x.n" ]; then rc=1; XWHY="N=1 waiter took a slot while 1 holder (slot 2) was live: '$(cat "$tmp/x.n")'"
    else
      at "$tmp/solo2" -- release --pid "$hb"
      xwait "$tmp/x.n"
      [ "$(cat "$tmp/x.n")" = "slot=1 jobs=12" ] || { rc=1; XWHY="N=1 waiter did not get slot 1 once idle: '$(cat "$tmp/x.n")'"; }
    fi
  fi
  # Reap BOTH waiters before returning — `exec` above makes each $! the acquire
  # process itself, so the TERM reaches it (killing a plain `( … )` subshell
  # orphans its child). Against the mutant the N=2 waiter never gets its slot and
  # used to keep polling (and taking the counter mutex) for the rest of its
  # --wait 10, into the next leg: (P) then found a live mutex.lnk where it plants
  # its garbage one (CI run 37252976836, "ln: ... File exists").
  kill "$w1" "$w2" 2>/dev/null; wait "$w1" 2>/dev/null; wait "$w2" 2>/dev/null
  for p in $ha $hb $hn; do at "$tmp/solo2" -- release --pid "$p"; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  return "$rc"
}
if mixed_ok "$SUT"; then ok "(X) mixed N: the N=2 waiter gets slot 2 past a capped N=1 waiter; N=1 never claims while 1 holder is live"
else no "(X) $XWHY"; fi
# MUTATION CONTROL — revert claim-by-count to the old rule: head ticket only, index scan over 1..N.
mut="$tmp/mut-count.sh"
sed -e '/# COUNT$/d' \
    -e 's/^    is_uint "\$c" .*# FAIR$/    return 1/' \
    -e 's/^  k=1; while \[ -e "\$D\/slots\/\$k" \]; do k=\$((k + 1)); done   # LOWEST$/  k=1; while [ -e "$D\/slots\/$k" ]; do k=$((k + 1)); done; [ "$k" -le "$SLOTS" ] || return 1/' \
    "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut" && ! grep -q '# COUNT$\|# FAIR$\|# LOWEST$' "$mut"; then
  if mixed_ok "$mut"; then no "(X) MUTATION CONTROL: the index-scan rule still passed (X) — (X) proves nothing"
  else ok "(X) MUTATION CONTROL: with the index-scan rule (X) fails ($XWHY)"; fi
else no "(X) MUTATION CONTROL: mutant not built (empty, unchanged, invalid or a tagged line left)"; fi
rm -rf "$ds/tickets/"* "$ds/slots/"*

# --- (P) no stranded mutex ----------------------------------------------------------------------------
live; hp=$LIVE
# The plant must land: a pre-existing mutex.lnk (a process from an earlier leg
# still running) would make this leg measure something else entirely.
if [ -e "$ds/mutex.lnk" ] || [ -L "$ds/mutex.lnk" ]; then no "(P) precondition: a mutex.lnk already exists before the plant ($(readlink "$ds/mutex.lnk"))"; fi
ln -s garbage "$ds/mutex.lnk"; mkdir "$ds/mutex"
t0=$(date +%s)
got="$(at "$tmp/solo2" -- acquire hp --pid "$hp" --wait 2 2>"$tmp/p.err")"; rc=$?
el=$(( $(date +%s) - t0 ))
if [ "$rc" = 0 ] && [ "$got" = "slot=1 jobs=6" ] && [ "$el" -le 3 ] && [ ! -L "$ds/mutex.lnk" ]; then
  ok "(P) a garbage-target mutex.lnk and a pid-less legacy mutex/ dir do not stall acquire --wait 2 (${el}s)"
else no "(P) planted: rc=$rc got=$got ${el}s err=$(cat "$tmp/p.err")"; fi
rmdir "$ds/mutex" 2>/dev/null
# TERM while the waiter's `ln` of the mutex is in flight: bash defers the trap until `ln` returns.
realln="$(command -v ln)"; mkdir -p "$tmp/shim"
printf '#!/bin/sh\ncase "$*" in *mutex.lnk*) echo x >> "%s"; sleep 1 ;; esac\nexec "%s" "$@"\n' "$tmp/p.inln" "$realln" > "$tmp/shim/ln"
chmod +x "$tmp/shim/ln"; rm -f "$tmp/p.inln"
nlines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
live; hq=$LIVE; live; hp2=$LIVE
at "$tmp/solo2" -- acquire hp2 --pid "$hp2" >/dev/null   # both slots held: hq must queue and poll
(cd "$tmp/solo2" && PATH="$tmp/shim:$PATH" exec bash "$SUT" acquire hq --pid "$hq" --wait 60 >/dev/null 2>&1) &
qpid=$!; pids="$pids $qpid"
i=0
while [ "$(nlines "$tmp/p.inln")" -lt 2 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
kill -TERM "$qpid" 2>/dev/null
i=0
while kill -0 "$qpid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
kill -KILL "$qpid" 2>/dev/null; wait "$qpid" 2>/dev/null
at "$tmp/solo2" -- release --pid "$hp"; at "$tmp/solo2" -- release --pid "$hp2"
live; hr=$LIVE
t0=$(date +%s)
got="$(at "$tmp/solo2" -- acquire hr --pid "$hr" --wait 2 2>"$tmp/p.err")"; rc=$?
el=$(( $(date +%s) - t0 ))
if [ "$(nlines "$tmp/p.inln")" -ge 2 ] && [ "$rc" = 0 ] && [ -n "$got" ] && [ "$el" -le 3 ] \
   && ! grep -q 'stale counter mutex' "$tmp/p.err" && [ -z "$(ls "$ds/tickets")" ]; then
  ok "(P) TERM during the waiter's mutex ln leaves no lock or ticket behind; the next acquire --wait 2 claims in ${el}s"
else no "(P) interrupted: ln-calls=$(nlines "$tmp/p.inln") rc=$rc got=$got ${el}s tickets=[$(ls "$ds/tickets")] lnk=$(readlink "$ds/mutex.lnk") err=$(cat "$tmp/p.err")"; fi
at "$tmp/solo2" -- release --pid "$hr"

# --- (L) the acquire deadline holds even with a stuck mutex --------------------------------------------
live; hl=$LIVE; live; hs=$LIVE
ln -s "$hs" "$ds/mutex.lnk"
t0=$(date +%s)
got="$(at "$tmp/solo2" -- acquire hl --pid "$hl" --wait 2 2>"$tmp/l.err")"; rc=$?
el=$(( $(date +%s) - t0 ))
if [ "$rc" = 1 ] && [ -z "$got" ] && [ "$el" -le 6 ] && [ -z "$(ls "$ds/tickets")" ] && [ "$(readlink "$ds/mutex.lnk")" = "$hs" ] \
   && grep -q "held by pid $hs past the wait deadline" "$tmp/l.err"; then
  ok "(L) a mutex held by a live pid: acquire --wait 2 exits 1 in ${el}s, no ticket, the live lock untouched"
else no "(L) rc=$rc got=$got ${el}s tickets=[$(ls "$ds/tickets")] err=$(cat "$tmp/l.err")"; fi
rm -f "$ds/mutex.lnk"; kill "$hs" "$hl" 2>/dev/null

# --- (D) dead holder -------------------------------------------------------------------------------
kill "$h1" 2>/dev/null; wait "$h1" 2>/dev/null
live; h4=$LIVE
got="$(at "$tmp/c2" -- acquire h4 --pid "$h4" --wait 1 2>"$tmp/d.err")"
if [ "$got" = "slot=1 jobs=6" ] && grep -q "taking over slot 1 (holder pid $h1 is gone)" "$tmp/d.err"; then
  ok "(D) a slot whose holder pid is dead is taken over"
else no "(D) got=$got err=$(cat "$tmp/d.err")"; fi
at "$tmp/c2" -- release --pid "$h4"

# --- (M) stale counter mutex -------------------------------------------------------------------------
dead; ln -s "$DEAD" "$d1/mutex.lnk"
live; h5=$LIVE
got="$(at "$tmp/c1" -- acquire h5 --pid "$h5" --wait 1 2>"$tmp/m.err")"
if [ -n "$got" ] && grep -q "stale counter mutex (pid $DEAD is gone)" "$tmp/m.err" && [ ! -L "$d1/mutex.lnk" ]; then
  ok "(M) a mutex left by a dead pid is taken over at once"
else no "(M) got=$got err=$(cat "$tmp/m.err")"; fi

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

# --- (G) machine gate ------------------------------------------------------------------------------
setload() { echo "$1" > "$tmp/load.state"; }
mrecs() { ls "$MDIR/holders" 2>/dev/null | wc -l | tr -d ' '; }
git clone -q "$tmp/base" "$tmp/lp"   # origin = a local path ⇒ a repo key of its own
lpat() { (cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" bash "$SUT" "$@"); }
rm -rf "$MDIR/holders/"* "$d1/slots/"* "$d1/tickets/"*
unset LOOMWRIGHT_CI_SLOTS
export LOOMWRIGHT_CI_SLOTS=2
# (G1) busy + AC3
setload busy
live; gx=$LIVE; live; gy=$LIVE
gxo="$(at "$tmp/c1" -- acquire gx --pid "$gx" 2>/dev/null)"
gyo="$(lpat acquire gy --pid "$gy" --wait 1 2>"$tmp/g1.err")"; rc=$?
if [ -n "$gxo" ] && [ "$rc" = 1 ] && [ -z "$gyo" ] && [ "$(lpat dir)" != "$d1" ] \
   && grep -q "held for load: busy load1=40.00 (1 machine-wide holder(s))" "$tmp/g1.err"; then
  ok "(G1) busy: the first machine-wide holder is granted, a second (local-path origin, own XDG_STATE_HOME) waits"
else no "(G1) busy: gx=[$gxo] gy rc=$rc out=[$gyo] err=$(cat "$tmp/g1.err")"; fi
setload ok
gyo="$(lpat acquire gy --pid "$gy" --wait 5 2>/dev/null)"
if [ -n "$gyo" ] && [ "$(mrecs)" = 2 ] \
   && [ "$(at "$tmp/c1" -- status --json | jq -c '[.machine.holders[].pid] | sort')" = "$(printf '[%s]' "$(printf '%s\n' "$gx" "$gy" | sort -n | paste -sd, -)")" ] \
   && [ "$(lpat status --json | jq '.machine.holders | length')" = 2 ] \
   && [ "$(at "$tmp/c1" -- status --json | jq -r .machine.dir)" = "$MDIR" ]; then
  ok "(G1) two repo keys (one a local-path origin) and two XDG_STATE_HOMEs share ONE machine holders list (AC3)"
else no "(G1) shared list: gy=[$gyo] recs=$(mrecs) status=$(at "$tmp/c1" -- status --json | jq -c .machine)"; fi
at "$tmp/c1" -- release --pid "$gx"; lpat release --pid "$gy"
[ "$(mrecs)" = 0 ] && ok "(G1) release --pid drops the machine record" || no "(G1) release left $(mrecs) machine records"

# (G2) overloaded: held in order, released within one re-check
held_ok() {   # held_ok SUT — exit 0 iff every (G2) property holds; GWHY says which failed
  local s="$1" ga gb wa wb i t0 el st
  GWHY=""; rm -f "$tmp"/g2.*
  setload overloaded
  live; ga=$LIVE; live; gb=$LIVE
  (cd "$tmp/c1" && exec bash "$s" acquire ga --pid "$ga" --wait 30 >"$tmp/g2.a" 2>"$tmp/g2.aerr") & wa=$!; pids="$pids $wa"
  i=0; while [ "$(at "$tmp/c1" -- status --json | jq '.waiters | length')" != 1 ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  (cd "$tmp/c1" && exec bash "$s" acquire gb --pid "$gb" --wait 30 >"$tmp/g2.b" 2>/dev/null) & wb=$!; pids="$pids $wb"
  i=0; while [ "$(at "$tmp/c1" -- status --json | jq '.waiters | length')" != 2 ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 1.5   # past one re-check: still held
  st="$(at "$tmp/c1" -- status --json)"
  if [ -s "$tmp/g2.a" ] || [ -s "$tmp/g2.b" ]; then GWHY="granted while overloaded (a=[$(cat "$tmp/g2.a")] b=[$(cat "$tmp/g2.b")])"
  elif [ "$(jq -c '[.waiters[].pid]' <<<"$st")" != "[$ga,$gb]" ]; then GWHY="tickets not kept in order: $st"
  elif [ "$(jq -r '.waiters[0].held' <<<"$st")" != "held for load: overloaded load1=40.00" ]; then GWHY="status --json waiter not marked held: $st"
  elif ! grep -q "waiter: ticket .* pid $ga .* — held for load: overloaded load1=40.00$" <<<"$(at "$tmp/c1" -- status)"; then GWHY="status text lacks 'held for load': $(at "$tmp/c1" -- status)"
  elif ! grep -q "held for load: overloaded load1=40.00" "$tmp/g2.aerr"; then GWHY="waiting line lacks the hold reason: $(cat "$tmp/g2.aerr")"
  else
    setload ok; t0=$(date +%s)
    i=0; while [ ! -s "$tmp/g2.b" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i + 1)); done
    el=$(( $(date +%s) - t0 ))
    if [ "$(cat "$tmp/g2.a")" != "slot=1 jobs=6" ] || [ "$(cat "$tmp/g2.b")" != "slot=2 jobs=6" ] || [ "$el" -gt 3 ]; then
      GWHY="after ok: a=[$(cat "$tmp/g2.a")] b=[$(cat "$tmp/g2.b")] in ${el}s (want slot 1 then 2, within one 1 s re-check + poll)"
    fi
  fi
  kill "$wa" "$wb" 2>/dev/null; wait "$wa" 2>/dev/null; wait "$wb" 2>/dev/null
  for p in $ga $gb; do at "$tmp/c1" -- release --pid "$p"; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -f "$d1/tickets/"*
  [ -z "$GWHY" ]
}
if held_ok "$SUT"; then ok "(G2) overloaded: both held with tickets in order and 'held for load: overloaded load1=40.00'; ok ⇒ slot 1 then slot 2 within one re-check"
else no "(G2) $GWHY"; fi
mut="$tmp/mut-machine.sh"
grep -v '# MACHINE$' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if held_ok "$mut"; then no "(G2) MUTATION CONTROL: without the admission call the callers were still held — (G2) proves nothing"
  else ok "(G2) MUTATION CONTROL: without the admission call (G2) fails ($GWHY)"; fi
else no "(G2) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# (G3) a held caller still times out at --wait
setload overloaded; live; gt=$LIVE
t0=$(date +%s)
out="$(at "$tmp/c1" -- acquire gt --pid "$gt" --wait 2 2>"$tmp/g3.err")"; rc=$?
el=$(( $(date +%s) - t0 ))
if [ "$rc" = 1 ] && [ -z "$out" ] && [ "$el" -le 5 ] && [ -z "$(ls "$d1/tickets")" ] \
   && grep -q "giving up (held for load: overloaded load1=40.00, holders:" "$tmp/g3.err"; then
  ok "(G3) a caller held for load times out at --wait 2 (${el}s), its ticket removed"
else no "(G3) rc=$rc out=[$out] ${el}s tickets=[$(ls "$d1/tickets")] err=$(cat "$tmp/g3.err")"; fi

# (G4) fail-SAFE reader: a live holder is present, so a reader read as busy would hold the caller
setload ok; at "$tmp/c1" -- acquire gx --pid "$gx" >/dev/null 2>&1
fok=1
for m in unknown fail garbage missing; do
  live; gz=$LIVE; setload "$m"; cmd="$tmp/load.sh"; [ "$m" = missing ] && cmd="$tmp/no-such-reader.sh"
  t0=$(date +%s)
  out="$(cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" LOOMWRIGHT_MACHINE_LOAD_CMD="$cmd" bash "$SUT" acquire gz --pid "$gz" --wait 10 2>/dev/null)"
  el=$(( $(date +%s) - t0 ))
  if [ -z "$out" ] || [ "$el" -gt 7 ]; then fok=0; no "(G4) reader '$m' was not read as ok: out=[$out] ${el}s"; fi
  lpat release --pid "$gz"
done
[ "$fok" -eq 1 ] && ok "(G4) a reader answering unknown / exiting 3 / printing garbage / missing grants as ok"
at "$tmp/c1" -- release --pid "$gx"

# (G5) nested inside a live machine holder: folds, under busy and overloaded
cat > "$tmp/outer.sh" <<'EOF'
cd "$1/c1" && bash "$2" acquire outer --pid $$ >/dev/null 2>&1 || { echo "outer-not-granted"; exit 1; }
sleep 60 & c=$!
for m in busy overloaded; do
  echo "$m" > "$1/load.state"
  t0=$(date +%s)
  o="$(cd "$1/lp" && XDG_STATE_HOME="$1/state3" bash "$2" acquire inner --pid "$c" --wait 10 2>/dev/null)"
  echo "$m:$o:$(( $(date +%s) - t0 )):$(ls "$1/machine/holders" | wc -l | tr -d ' ')"
  (cd "$1/lp" && XDG_STATE_HOME="$1/state3" bash "$2" release --pid "$c")
done
kill "$c" 2>/dev/null
cd "$1/c1" && bash "$2" release --pid $$
EOF
setload ok; live; gx=$LIVE; at "$tmp/c1" -- acquire gx --pid "$gx" >/dev/null 2>&1   # a second live holder: busy would hold anyone new
out="$(bash "$tmp/outer.sh" "$tmp" "$SUT")"
if [ "$(printf '%s\n' "$out" | grep -cE '^(busy|overloaded):slot=1 jobs=6:[01]:2$')" = 2 ]; then
  ok "(G5) an acquire nested in a live machine holder is granted at once under busy and overloaded, no record added"
else no "(G5) nested: $out"; fi

# (G6) another machine-state-dir sandbox is isolated; (G7) a bare caller counts once
setload busy; live; gi=$LIVE
out="$(cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" LOOMWRIGHT_MACHINE_STATE_DIR="$tmp/machine-sb" bash "$SUT" acquire gi --pid "$gi" --wait 2 2>/dev/null)"
if [ -n "$out" ] && [ "$(mrecs)" = 1 ] && [ -f "$tmp/machine-sb/holders/$gi" ]; then
  ok "(G6) a caller whose LOOMWRIGHT_MACHINE_STATE_DIR is another sandbox is isolated: granted under busy, this list untouched"
else no "(G6) out=[$out] recs=$(mrecs) sb=[$(ls "$tmp/machine-sb/holders" 2>/dev/null)]"; fi
lpat release --pid "$gi"
rm -rf "$MDIR/holders/"*   # earlier live holders: two bare callers must fit the committed-work cap (G12)
setload ok; live; gc=$LIVE; live; gc2=$LIVE
n0="$(mrecs)"; at "$tmp/solo2" -- acquire gc --pid "$gc" >/dev/null 2>&1
n1="$(mrecs)"; k="$(at "$tmp/solo2" -- acquire gc2 --pid "$gc2" 2>/dev/null)"; k="${k#slot=}"; k="${k%% *}"
n2="$(mrecs)"; at "$tmp/solo2" -- release --slot "$k"; n3="$(mrecs)"; at "$tmp/solo2" -- release --pid "$gc"
if [ "$n1" = $((n0 + 1)) ] && [ "$(sed -n 1p "$MDIR/holders/$gc" 2>/dev/null || echo "$gc")" = "$gc" ] && [ "$n2" = $((n0 + 2)) ] \
   && [ "$n3" = $((n0 + 1)) ] && [ "$(mrecs)" = "$n0" ]; then
  ok "(G7) a bare caller adds exactly one machine record; release --slot and --pid remove it"
else no "(G7) records: before=$n0 +gc=$n1 +gc2=$n2 after --slot=$n3 after --pid=$(mrecs)"; fi
at "$tmp/c1" -- release --pid "$gx"

# (G8) read-only commands never wait on the gate
live; gm=$LIVE; ln -s "$gm" "$MDIR/mutex.lnk"; setload hang
t0=$(date +%s)
at "$tmp/c1" -- status >/dev/null; at "$tmp/c1" -- status --json >/dev/null; at "$tmp/c1" -- dir >/dev/null
at "$tmp/c1" -- release --pid 999999; rc=$?
el=$(( $(date +%s) - t0 ))
if [ "$el" -le 2 ] && [ "$rc" = 0 ] && [ "$(readlink "$MDIR/mutex.lnk")" = "$gm" ]; then
  ok "(G8) status, status --json, dir and release return in ${el}s with the machine mutex held and a hanging reader"
else no "(G8) read-only commands took ${el}s (rc=$rc)"; fi
rm -f "$MDIR/mutex.lnk"; setload ok

# (G9) no code path sends a signal (AC4): code lines only, `kill -0` allowed
signals() {   # signals FILE… — print each code line that could signal another process
  awk '/^[[:space:]]*#/ { next }
       { l = $0; gsub(/kill -0/, "", l)
         if (l ~ /(^|[^[:alnum:]_-])(pkill|killall|kill)([^[:alnum:]_-]|$)/) print FILENAME ":" FNR ": " $0 }' "$@"
}
hits="$(signals "$SUT" "$HERE/machine-load.sh")"
if [ -z "$hits" ]; then ok "(G9) ci-slot.sh and machine-load.sh send no signal (kill -0 probes only)"
else no "(G9) signal-sending code: $hits"; fi
mut="$tmp/mut-kill.sh"
sed 's/^  MH="\$h"$/  MH="$h"; kill "$NESTED_IN" 2>\/dev\/null/' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if [ -n "$(signals "$mut")" ]; then ok "(G9) MUTATION CONTROL: an injected kill is caught"
  else no "(G9) MUTATION CONTROL: an injected kill was not caught — (G9) proves nothing"; fi
else no "(G9) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# (G10) a slow reader is not read as unknown
slow_held() {   # slow_held SUT — exit 0 iff a 6 s overloaded reader holds a caller beside a live holder
  local s="$1" h c rc out n
  GWHY=""
  cat > "$tmp/load-slow.sh" <<'EOS'
echo start >> "$(dirname "$0")/g10.n"; sleep 6; echo end >> "$(dirname "$0")/g10.n"; echo "load1=40.00"; echo "state=overloaded"
EOS
  rm -rf "$MDIR/holders/"*   # exactly ONE machine holder (h): earlier live holders would trip the committed-work cap (G12)
  setload ok; live; h=$LIVE; at "$tmp/c1" -- acquire g10h --pid "$h" >/dev/null 2>&1
  rm -f "$MDIR/load" "$tmp/g10.n"   # no answered reading to stand in: the slow reader alone decides
  live; c=$LIVE
  # RECHECK 30: after the slow answer is taken no fresh reader starts inside this --wait.
  out="$(cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" LOOMWRIGHT_MACHINE_LOAD_CMD="$tmp/load-slow.sh" \
    LOOMWRIGHT_MACHINE_LOAD_RECHECK=30 bash "$s" acquire g10c --pid "$c" --wait 9 2>"$tmp/g10.err")"; rc=$?
  n="$(paste -sd' ' "$tmp/g10.n" 2>/dev/null)"
  if [ "$rc" != 1 ] || [ -n "$out" ]; then GWHY="granted: rc=$rc out=[$out]"
  elif ! grep -q "held for load: busy load1=unknown (reader still running after 5s) (1 machine-wide holder(s))" "$tmp/g10.err"; then GWHY="not held as busy while the reader ran: $(cat "$tmp/g10.err")"
  elif ! grep -q "held for load: overloaded load1=40.00" "$tmp/g10.err"; then GWHY="the slow reader's own answer was never taken: $(cat "$tmp/g10.err")"
  elif [ "$n" != "start end" ]; then GWHY="want one reader run start to end, got [$n]"
  elif [ "$(cut -d' ' -f2- "$MDIR/load" 2>/dev/null)" != "overloaded 40.00" ]; then GWHY="cached reading [$(cat "$MDIR/load" 2>/dev/null)], want 'overloaded 40.00'"
  fi
  at "$tmp/c1" -- release --pid "$h"; lpat release --pid "$c"
  [ -z "$GWHY" ]
}
if slow_held "$SUT"; then ok "(G10) a reader answering overloaded after 6 s holds the caller (busy meanwhile, then its own answer; one reader run)"
else no "(G10) $GWHY"; fi
mut="$tmp/mut-slow.sh"
sed 's/then load_timed_out "\$t"; return 0; fi   # SLOW$/then LOAD_STATE=unknown; LOAD1=unknown; LOAD_AT="$t"; RP=""; return 0; fi/' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if slow_held "$mut"; then no "(G10) MUTATION CONTROL: with a timed-out reader read as unknown the caller was still held — (G10) proves nothing"
  else ok "(G10) MUTATION CONTROL: a timed-out reader read as unknown fails (G10) ($GWHY)"; fi
else no "(G10) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi
# A hanging reader: a fresh answered reading stands in; a stale one does not (busy, sole caller granted).
setload hang; live; c=$LIVE
echo "$(date +%s) overloaded 40.00" > "$MDIR/load"
out="$(lpat acquire g10f --pid "$c" --wait 2 2>"$tmp/g10.err")"; rc=$?
if [ "$rc" = 1 ] && [ -z "$out" ] && grep -q "held for load: overloaded load1=40.00" "$tmp/g10.err"; then
  ok "(G10) a hanging reader with an answered overloaded reading under 60 s old holds a caller with no other holder"
else no "(G10) fresh stand-in: rc=$rc out=[$out] err=$(cat "$tmp/g10.err")"; fi
echo "$(( $(date +%s) - 61 )) overloaded 40.00" > "$MDIR/load"
out="$(lpat acquire g10f --pid "$c" --wait 2 2>/dev/null)"
if [ -n "$out" ] && [ "$(cut -d' ' -f2- "$MDIR/load")" = "overloaded 40.00" ]; then
  ok "(G10) with that reading 61 s old a hanging reader reads busy: a sole caller is granted, the cache untouched"
else no "(G10) stale stand-in: out=[$out] cache=[$(cat "$MDIR/load")]"; fi
# (G13) the 5 s reader wait is bounded by the CLOCK, not by a count of `sleep` calls: with a `sleep` on
# PATH that costs 0.1 s extra per call (process start cost, exaggerated), the old 100 x `sleep 0.05`
# loop ran ~15 s, so G10's 6 s reader answered first and the interim busy line never showed.
mkdir -p "$tmp/slowsleep"
printf '#!/bin/sh\n/bin/sleep 0.1\nexec /bin/sleep "$@"\n' > "$tmp/slowsleep/sleep"; chmod +x "$tmp/slowsleep/sleep"
if PATH="$tmp/slowsleep:$PATH" slow_held "$SUT"; then ok "(G13) a slow \`sleep\` does not stretch the 5 s reader wait (busy shown while the 6 s reader runs)"
else no "(G13) slow sleep: $GWHY"; fi
mut="$tmp/mut-count.sh"
sed 's/^    while alive "\$RP"; do clock_ms; \[ \$((CLOCK_MS - i)) -ge 5000 \] \&\& break; sleep 0\.05; done$/    i=0; while alive "$RP" \&\& [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done/' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if PATH="$tmp/slowsleep:$PATH" slow_held "$mut"; then no "(G13) MUTATION CONTROL: the iteration-bounded wait still passed under a slow sleep — (G13) proves nothing"
  else ok "(G13) MUTATION CONTROL: the iteration-bounded wait fails (G13) under a slow sleep ($GWHY)"; fi
else no "(G13) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi
# clock_ms's SECONDS fallback (bash 3.2's branch) never runs in CI (bash 5 populates EPOCHREALTIME):
# force it on any bash with a copy whose clock_ms never sees EPOCHREALTIME, and run the same check.
sec="$tmp/sut-seconds.sh"
sed 's/^  local e="\${EPOCHREALTIME:-}"$/  local e=""/' "$SUT" > "$sec"
if [ -s "$sec" ] && ! cmp -s "$sec" "$SUT" && bash -n "$sec"; then
  if PATH="$tmp/slowsleep:$PATH" slow_held "$sec"; then ok "(G13) the SECONDS fallback (bash 3.2's branch, forced) also bounds the reader wait by the clock"
  else no "(G13) SECONDS fallback: $GWHY"; fi
else no "(G13) SECONDS fallback: forced copy not built (empty, unchanged or invalid)"; fi
lpat release --pid "$c"; setload ok

# (G11) records from before this boot are dropped, never counted or folded into
boot_ok() {   # boot_ok SUT — exit 0 iff every (G11) property holds; GWHY says which failed
  local s="$1" c u out rc
  GWHY=""; rm -f "$MDIR/holders/"*
  live; c=$LIVE; live; u=$LIVE
  # The test shell ($$) is the parent of --pid $c: a record naming it is an ancestor record.
  printf '%s\n%s\n%s\n%s\n%s\n' "$$" "$tmp/c1" old-outer 1700000000 "$d1" > "$MDIR/holders/$$"
  setload overloaded
  out="$(cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" LOOMWRIGHT_MACHINE_BOOT_TIME=1700000100 bash "$s" acquire g11 --pid "$c" --wait 2 2>/dev/null)"; rc=$?
  if [ "$rc" != 1 ] || [ -n "$out" ]; then GWHY="folded into a pre-boot ancestor record: rc=$rc out=[$out]"
  elif [ -e "$MDIR/holders/$$" ]; then GWHY="the pre-boot ancestor record was kept"
  fi
  lpat release --pid "$c"; rm -f "$MDIR/holders/"*
  if [ -z "$GWHY" ]; then
    printf '%s\n%s\n%s\n%s\n%s\n' "$u" "$tmp/c1" old-other 1700000000 "$d1" > "$MDIR/holders/$u"
    setload busy
    out="$(cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" LOOMWRIGHT_MACHINE_BOOT_TIME=1700000100 bash "$s" acquire g11 --pid "$c" --wait 2 2>/dev/null)"
    if [ -z "$out" ] || [ -e "$MDIR/holders/$u" ]; then GWHY="a pre-boot record with a live unrelated pid held the caller under busy: out=[$out]"; fi
    lpat release --pid "$c"; rm -f "$MDIR/holders/"*
  fi
  if [ -z "$GWHY" ]; then
    printf '%s\n%s\n%s\n%s\n%s\n' "$u" "$tmp/c1" old-other 1700000000 "$d1" > "$MDIR/holders/$u"
    out="$(cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" LOOMWRIGHT_MACHINE_BOOT_TIME=garbage bash "$s" acquire g11 --pid "$c" --wait 1 2>/dev/null)"; rc=$?
    if [ "$rc" != 1 ] || [ ! -e "$MDIR/holders/$u" ]; then GWHY="unreadable boot time did not keep the record: rc=$rc out=[$out]"; fi
    lpat release --pid "$c"; rm -f "$MDIR/holders/"*
  fi
  for p in $c $u; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  setload ok
  [ -z "$GWHY" ]
}
if boot_ok "$SUT"; then ok "(G11) pre-boot holder records are dropped (no false fold under overloaded, no phantom under busy); unreadable boot time keeps them"
else no "(G11) $GWHY"; fi
mut="$tmp/mut-boot.sh"
grep -v '# BOOT$' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if boot_ok "$mut"; then no "(G11) MUTATION CONTROL: without the boot-time prune (G11) still passed — it proves nothing"
  else ok "(G11) MUTATION CONTROL: without the boot-time prune (G11) fails ($GWHY)"; fi
else no "(G11) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# (G12) committed work at load ok: 12 CPUs and 2 slots ⇒ 6 jobs a suite ⇒ two suites machine-wide.
# Three callers from three repo keys (so no repo pool holds anyone): the third waits although the
# reader says ok, and is granted once a holder releases. This is the S3 wave-2 burst (three suites
# 30 s apart all read ok on a lagging load1 and drove it to 63.6).
commit_ok() {   # commit_ok SUT — exit 0 iff (G12) holds; GWHY says which failed
  local s="$1" a b c ao bo co rc
  GWHY=""; setload ok; rm -rf "$MDIR/holders/"*
  live; a=$LIVE; live; b=$LIVE; live; c=$LIVE
  ao="$(cd "$tmp/c1" && LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 bash "$s" acquire ca --pid "$a" 2>/dev/null)"
  bo="$(cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 bash "$s" acquire cb --pid "$b" 2>/dev/null)"
  co="$(cd "$tmp/c3" && LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 bash "$s" acquire cc --pid "$c" --wait 1 2>"$tmp/g12.err")"; rc=$?
  if [ -z "$ao" ] || [ -z "$bo" ]; then GWHY="first two not granted: a=[$ao] b=[$bo]"
  elif [ "$rc" != 1 ] || [ -n "$co" ]; then GWHY="third granted at load ok: rc=$rc out=[$co]"
  elif ! grep -q "held for load: committed 12+6 jobs > 12 CPUs (2 machine-wide holder(s))" "$tmp/g12.err"; then GWHY="no committed-work hold line: $(tr '\n' ' ' < "$tmp/g12.err")"
  fi
  (cd "$tmp/c1" && bash "$s" release --pid "$a") >/dev/null 2>&1
  if [ -z "$GWHY" ]; then
    co="$(cd "$tmp/c3" && LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 bash "$s" acquire cc --pid "$c" --wait 5 2>/dev/null)"
    [ -n "$co" ] || GWHY="third not granted after a holder released"
  fi
  (cd "$tmp/lp" && XDG_STATE_HOME="$tmp/state2" bash "$s" release --pid "$b") >/dev/null 2>&1
  (cd "$tmp/c3" && bash "$s" release --pid "$c") >/dev/null 2>&1
  [ -z "$GWHY" ]
}
if commit_ok "$SUT"; then ok "(G12) committed work: at load ok a third suite (3 repo keys, 12 CPUs, 6 jobs each) waits, and starts when a holder releases"
else no "(G12) $GWHY"; fi
mut="$tmp/mut-commit.sh"
grep -v '# COMMIT$' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if commit_ok "$mut"; then no "(G12) MUTATION CONTROL: without the committed-work cap (G12) still passed — it proves nothing"
  else ok "(G12) MUTATION CONTROL: without the committed-work cap (G12) fails ($GWHY)"; fi
else no "(G12) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# (G14) NESTED: a caller nested in a live holder of THIS repo's pool folds into it before the count
# (N=1 here: without the fold the child would wait on its own parent until --wait).
repofold_ok() {   # repofold_ok SUT — exit 0 iff (G14) holds; GWHY says which failed
  local s="$1" out
  GWHY=""; setload ok; rm -rf "$MDIR/holders/"*
  cat > "$tmp/g14.sh" <<'EOF'
export LOOMWRIGHT_CI_SLOTS=1 LOOMWRIGHT_CI_CPUS=12
o="$(cd "$1/c1" && bash "$2" acquire g14outer --pid $$ 2>/dev/null)" || { echo "outer-not-granted"; exit 1; }
ok_slot="${o#slot=}"; ok_slot="${ok_slot%% *}"
echo overloaded > "$1/load.state"
sleep 60 & c=$!
sib="$3"   # a live pid of the test shell's: NOT a descendant of this holder
d="$(cd "$1/c1" && bash "$2" dir)"
t0=$(date +%s)
in="$(cd "$1/wt1" && bash "$2" acquire g14inner --pid "$c" --wait 2 2>/dev/null)"; irc=$?
el=$(( $(date +%s) - t0 ))
nt="$(ls "$d/tickets" | wc -l | tr -d ' ')"; ns="$(ls "$d/slots" | wc -l | tr -d ' ')"
nm="$(ls "$1/machine/holders" | wc -l | tr -d ' ')"
(cd "$1/wt1" && bash "$2" release --pid "$c")
kept="$( [ -d "$d/slots/$ok_slot" ] && echo kept || echo gone )"
echo ok > "$1/load.state"
sout="$(cd "$1/wt1" && bash "$2" acquire g14sib --pid "$sib" --wait 1 2>/dev/null)"; src=$?
kill "$c" 2>/dev/null
cd "$1/c1" && bash "$2" release --pid $$
if [ "$in" = "slot=$ok_slot jobs=12" ]; then same=holder-slot; else same="other-slot[$in]"; fi
echo "inner=$irc $same ${el}s tickets=$nt slots=$ns mrecs=$nm $kept sibling=$src:$sout"
EOF
  live
  out="$(bash "$tmp/g14.sh" "$tmp" "$s" "$LIVE")"
  (cd "$tmp/wt1" && bash "$s" release --pid "$LIVE") >/dev/null 2>&1; kill "$LIVE" 2>/dev/null
  case "$out" in
    "inner=0 holder-slot "[01]"s tickets=0 slots=1 mrecs=1 kept sibling=1:") ;;
    *) GWHY="nested caller not folded at once into its holder's slot (or the fold left a record / passed a sibling): $out" ;;
  esac
  setload ok
  [ -z "$GWHY" ]
}
if repofold_ok "$SUT"; then ok "(G14) a caller nested in a live holder of this repo's pool (N=1, overloaded) gets the holder's slot at once, records nothing; a sibling still waits"
else no "(G14) $GWHY"; fi
mut="$tmp/mut-repofold.sh"
grep -v '# REPOFOLD$' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if repofold_ok "$mut"; then no "(G14) MUTATION CONTROL: without the repo-pool fold (G14) still passed — it proves nothing"
  else ok "(G14) MUTATION CONTROL: without the repo-pool fold (G14) fails ($GWHY)"; fi
else no "(G14) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# (G15) repo_fold skips a slot record started before this boot, like machine_holders (G11): its pid
# belongs to a process of this boot that never wrote it, so folding into it would hand the caller a
# slot nobody holds. The test shell ($$) is the parent of --pid $c, so a record naming it is an
# ancestor record; with N=1 a caller that is NOT folded is counted against it and times out.
repoboot_ok() {   # repoboot_ok SUT — exit 0 iff (G15) holds; GWHY says which failed
  local s="$1" c out rc
  GWHY=""; setload ok; rm -rf "$MDIR/holders/"* "$d1/slots/"* "$d1/tickets/"*
  live; c=$LIVE
  mkdir -p "$d1/slots/1"; printf '%s\n%s\n%s\n%s\n' "$$" "$tmp/c1" old-outer 1700000000 > "$d1/slots/1/info"
  out="$(cd "$tmp/c1" && LOOMWRIGHT_CI_SLOTS=1 LOOMWRIGHT_MACHINE_BOOT_TIME=1700000100 bash "$s" acquire g15 --pid "$c" --wait 1 2>/dev/null)"; rc=$?
  if [ "$rc" != 1 ] || [ -n "$out" ]; then GWHY="folded into a pre-boot ancestor slot record: rc=$rc out=[$out]"; fi
  (cd "$tmp/c1" && bash "$s" release --pid "$c") >/dev/null 2>&1
  if [ -z "$GWHY" ]; then
    mkdir -p "$d1/slots/1"; printf '%s\n%s\n%s\n%s\n' "$$" "$tmp/c1" old-outer 1700000000 > "$d1/slots/1/info"
    out="$(cd "$tmp/c1" && LOOMWRIGHT_CI_SLOTS=1 LOOMWRIGHT_MACHINE_BOOT_TIME=garbage bash "$s" acquire g15 --pid "$c" --wait 1 2>/dev/null)"; rc=$?
    case "$rc:$out" in "0:slot=1 "*) ;; *) GWHY="unreadable boot time did not keep the fold: rc=$rc out=[$out]" ;; esac
    (cd "$tmp/c1" && bash "$s" release --pid "$c") >/dev/null 2>&1
  fi
  rm -rf "$d1/slots/"* "$d1/tickets/"* "$MDIR/holders/"*
  kill "$c" 2>/dev/null; wait "$c" 2>/dev/null
  [ -z "$GWHY" ]
}
if repoboot_ok "$SUT"; then ok "(G15) a pre-boot repo slot record naming an ancestor is never folded into (counted, the caller waits); unreadable boot time keeps the fold"
else no "(G15) $GWHY"; fi
mut="$tmp/mut-repoboot.sh"
grep -v '# REPOBOOT$' "$SUT" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$SUT" && bash -n "$mut"; then
  if repoboot_ok "$mut"; then no "(G15) MUTATION CONTROL: without repo_fold's boot-time skip (G15) still passed — it proves nothing"
  else ok "(G15) MUTATION CONTROL: without repo_fold's boot-time skip (G15) fails ($GWHY)"; fi
else no "(G15) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

echo
echo "test-ci-slot: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
