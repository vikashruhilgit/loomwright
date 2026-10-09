#!/usr/bin/env bash
# test-ci-local.sh — offline self-test for scripts/ci-local.sh. Every arm drives a COPY of the
# script inside a fixture git repo in a mktemp dir (fixture ci.yml, fixture gates, the real
# run-self-tests.sh + hermetic-test-env.sh); the real repo and its suite are never run.
#
# Arms:
#   (P)  green fixture                → exit 0, every ci.yml gate (with its argument), the extra root
#                                       test and the loomwright test ran; "stamped"
#   (C)  same tree again              → exit 0 "PASS (cached)", NOTHING ran
#   (U)  an UNTRACKED file appears    → cache miss, re-runs; the vendor-coupling gate sees the file
#                                       via the temp index; the REAL index is left untouched;
#        MUTATION CONTROL: the same gate run against the real index → exit 1 (it can tell)
#   (F)  a gate fails under --force   → exit 1, and the old PASS stamp is removed: the next plain
#                                       run re-runs instead of reporting cached
#   (O)  origin/main moves            → cache miss (check-doc-currency reads the merge-base)
#   (M)  the tree changes mid-run     → PASS reported but "NOT cached"; the next run re-runs
#   (X)  another CLONE, same origin   → "PASS (cached)" from the shared repo-keyed pass dir, nothing
#                                       ran; the same clone re-pointed at another origin re-runs
#   (L)  every CI slot held by a live pid → waits (progress line), exit 1 after CI_LOCAL_LOCK_WAIT,
#                                       nothing ran; held by a dead pid → taken over ("is gone"), run
#                                       proceeds, slot released after
#   (J)  job share                    → SELF_TEST_JOBS = the slot's share; an explicit SELF_TEST_JOBS
#                                       is passed through unchanged
#   (Q)  waiter queued behind a holder that stamps the same tree → "PASS (cached)", nothing ran
#   (T)  TERM to a run queued for a slot → exit 143 within seconds (not after CI_LOCAL_LOCK_WAIT),
#                                       no ticket and no slot left under its pid, nothing ran
#   (B)  broken slot helper (stub)    → `dir` exits non-zero or prints nothing: exit 1 with the
#                                       dir-failure message, no acquire, nothing ran; a malformed
#                                       acquire answer: exit 1 "unexpected answer from", nothing ran,
#                                       the EXIT trap still calls `release --pid`; real helper restored
#   (LS) --list                       → key + cache status, exactly the ci.yml gates (with args) and the
#                                       plain tests in order, no temp wrapper paths, nothing ran;
#                                       a changed tree lists "cache: miss"
#   (H)  --help                       → the whole header de-commented, no code; still correct when the
#                                       first code line after the header changes
#   (Z)  ci.yml names no gates        → exit 1 (no green on zero gates)
#   (A)  unknown argument             → exit 2
#   (W)  wiring: ci-local.sh's loomwright glob line is the one run-self-tests.sh uses, and the real
#        ci.yml runs this self-test
# Run logs, --last, --affected:
#   (LG) a run's first and last output line name its log (PASS, FAIL, TERM while queued); the log
#        ends with its verdict line; a FAIL log holds the runner's FAIL banner (stderr captured)
#   (LA1) after a full run, --last prints that log + "PASS <log>", exit 0
#   (LA2) the tree changed → --last says stale-key, exit 1, and writes no git object, log or ticket
#   (LA3) a newer --affected log on the same tree is never what --last prints
#   (IN) a log cut off without a verdict (the TERMed queued run of (T)) → --last INCOMPLETE, exit 1
#   (QC) the (Q) waiter's post-slot cache hit leaves a log --last reports as PASS
#   (AF1) a changed loomwright/scripts/<x>.sh → --affected runs test-<x>.sh + the cheap gates
#        (check-* and validate-version, with arguments) and NOT the other tests nor test-check-*
#   (AF2) an unmapped change and a deleted test are listed under "not covered by --affected:"
#   (AF3) --affected never creates or removes a pass stamp (PASS and FAIL); MUTATION CONTROL: a copy
#        that stamps on PASS is caught by the same check
#   (AF4) a changed scripts/check-<x>.sh → its ci.yml-named test-check-<x>.sh runs
#   (E*) iq02 T05 early phase: (EL) the early set is DERIVED — non-test-*.sh ci.yml gates (a new
#        check-new.sh and a loomwright gen.sh --check join with no ci-local edit) + `# run-self-tests:
#        early` tests; a test-*.sh gate stays in the pool; (EM) MUTATION CONTROL: the marker removed ⇒
#        that test is in the pool; (ER) two early gates red ⇒ exit 1, every red early entry named, no
#        pool entry ran, the existing stamp removed, verdict `ci-local: FAIL … early gates failed`
#        last, --last says FAIL; (EG) green ⇒ every entry ran exactly once, early before pool,
#        stamped; (EX) MUTATION CONTROL: a copy that skips the early-red exit is caught; (AFC)
#        --affected runs the --check gate and the early-marked test; (AF8) early set and mapped set
#        both empty ⇒ the empty-plan refusal
#   (AF5) empty changed set → says so, still runs the cheap gates; (AF7) no origin/main → says so,
#        diffs against HEAD; (AF6) --affected --list: the plan, nothing ran, no log;
#        (AX) conflicting flags → exit 2
#   (UV) the (M) run's tree restored (its touched file removed) → --last reads that run's "NOT
#        cached" verdict as UNVERIFIED, exit 1 — never PASS
#   (PR) 25 seeded logs + one run → 20 remain, the run's own log survives, the oldest are gone;
#        no logs at all → --last says so, exit 1
#   (PA) 25 newer finished --affected logs never push the one full-run log out; --last still finds it
#   (PI) an in-flight log (no verdict, live owner pid) older than 20+ finished logs survives a run's
#        prune and the total is still 20 (one more finished log goes instead); a verdict-less log
#        with a dead owner is pruned
#   (PG) the run's own log removed mid-run → no verdict-only stub recreated, the removal is reported
#   (LM) --last never waits on the machine gate: a held machine mutex and a hanging load reader do
#        not slow it (still PASS, within 2 s)
#   (WT) --wait: nothing in flight → --last's answer at once; this tree's newest log in flight (live
#        owner pid, no verdict) → STILL-RUNNING exit 3 at CI_LOCAL_WAIT_MAX; the verdict lands while
#        it waits → that PASS, exit 0; the owner dies with no verdict → INCOMPLETE exit 1, no hang;
#        a bad CI_LOCAL_WAIT_MAX → exit 2; ci-local.sh never waits by process name (no pgrep/pkill)
# Slot state lives under a sandboxed XDG_STATE_HOME: an inner fixture run must never queue on the
# real shared pool that an outer ci-local.sh run is holding (that would deadlock it). The machine
# gate is sandboxed the same way (LOOMWRIGHT_MACHINE_STATE_DIR) and its reader pinned to a fixture
# that answers ok (LOOMWRIGHT_MACHINE_LOAD_CMD), so a loaded dev machine never holds these fixture
# runs and they never touch the real machine-wide holders list.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SUT="$HERE/ci-local.sh"
[ -f "$SUT" ] || { echo "test-ci-local: $SUT not found" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ci-local-test.XXXXXX")"
sleeper=""
trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"
# The outer run exports its own job share / slot knobs; every arm here starts from a clean slate.
unset SELF_TEST_JOBS LOOMWRIGHT_CI_SLOTS LOOMWRIGHT_CI_CPUS LOOMWRIGHT_CI_SLOT_PRINT_EVERY CI_LOCAL_LOCK_WAIT \
  CI_LOCAL_WAIT_MAX CI_LOCAL_WAIT_POLL
export LOOMWRIGHT_CI_SLOT_POLL=0.2
export LOOMWRIGHT_MACHINE_STATE_DIR="$tmp/machine" LOOMWRIGHT_MACHINE_LOAD_CMD="$tmp/load.sh"
printf '%s\n' 'if [ -f "$(dirname "$0")/load.hang" ]; then sleep 8; fi' 'echo load1=1.00' 'echo state=ok' > "$tmp/load.sh"
ORIGIN_URL="https://example.invalid/fixture/repo.git"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }

R="$tmp/repo"
export FIXTURE_LOG="$tmp/ran.log"

# build_fixture — a minimal repo shaped like this one.
build_fixture() {
  rm -rf "$R"; mkdir -p "$R/.github/workflows" "$R/scripts" "$R/loomwright/scripts"
  cp "$SUT" "$R/scripts/ci-local.sh"
  cp "$REPO_ROOT/loomwright/scripts/run-self-tests.sh" "$REPO_ROOT/loomwright/scripts/hermetic-test-env.sh" \
     "$REPO_ROOT/loomwright/scripts/ci-slot.sh" "$REPO_ROOT/loomwright/scripts/machine-load.sh" "$R/loomwright/scripts/"
  cat > "$R/.github/workflows/ci.yml" <<'YML'
jobs:
  ci:
    steps:
      - run: |
          bash scripts/check-a.sh --self-test
          bash scripts/check-a.sh
      - run: bash scripts/check-vendor-coupling.sh
YML
  cat > "$R/scripts/check-a.sh" <<'SH'
echo "check-a ${1:-plain}" >> "$FIXTURE_LOG"
exit "${FIXTURE_FAIL_A:-0}"
SH
  # Mirrors the real gate's blind spot: it only sees what `git ls-files` lists.
  cat > "$R/scripts/check-vendor-coupling.sh" <<'SH'
echo "vendor" >> "$FIXTURE_LOG"
[ ! -f scripts/new-untracked.txt ] || grep -qx scripts/new-untracked.txt < <(git ls-files)
SH
  echo 'echo "extra" >> "$FIXTURE_LOG"' > "$R/scripts/test-extra.sh"
  cat > "$R/loomwright/scripts/test-one.sh" <<'SH'
echo "one" >> "$FIXTURE_LOG"
[ -z "${FIXTURE_TOUCH:-}" ] || echo "changed $$" > "$(dirname "$0")/../../touched.txt"
[ -z "${FIXTURE_RMLOGS:-}" ] || rm -f "$FIXTURE_RMLOGS"/*.log
exit 0
SH
  ( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm fixture && git update-ref refs/remotes/origin/main HEAD \
      && git remote add origin "$ORIGIN_URL" )
}

run() { : > "$FIXTURE_LOG"; out="$(cd "$R" && bash scripts/ci-local.sh "$@" 2>&1)"; rc=$?; }
ran() { grep -qx "$1" "$FIXTURE_LOG"; }
slot() { (cd "$R" && bash loomwright/scripts/ci-slot.sh "$@"); }
# has PAT — `grep -q` on a here-string, never a pipe (test-no-pipefail-grep-q.sh).
has() { grep -q "$1" <<<"$out"; }
hasf() { grep -qF -- "$1" <<<"$out"; }
# Run-log helpers: the log path a run named on its first line; its first/last output lines; the
# log's own last content line (its verdict).
first_line() { sed -n '1p' <<<"$out"; }
last_line() { sed -n '$p' <<<"$out"; }
logpath() { first_line | sed -n 's/^ci-local: log //p'; }
names_log() { local p; p="$(logpath)"; [ -n "$p" ] && [ -f "$p" ] && [ "$(last_line)" = "ci-local: log $p" ]; }
log_verdict() { awk 'NF { l = $0 } END { print l }' "$1"; }
nlogs() { ls "$state/runs" 2>/dev/null | wc -l | tr -d ' '; }

build_fixture
state="$(slot dir)"
case "$state" in "$tmp/state/"*) ok "(S) slot state is inside the sandboxed XDG_STATE_HOME" ;;
  *) no "(S) slot state escaped the sandbox: $state"; exit 1 ;; esac

# (P)
run
if [ "$rc" -eq 0 ] && ran "check-a --self-test" && ran "check-a plain" && ran vendor && ran extra && ran one \
   && has "stamped"; then ok "(P) green: every gate + test ran, stamped"
else no "(P) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
if [ -z "$(sort "$FIXTURE_LOG" | uniq -d)" ] && [ "$(wc -l < "$FIXTURE_LOG" | tr -d ' ')" = 5 ]; then
  ok "(P) every full-plan entry ran exactly once across the early phase and the pool"
else no "(P) duplicate or missing entries: [$(tr '\n' ' ' < "$FIXTURE_LOG")]"; fi

# (LG) — the (P) run named its log first and last; the log ends with the verdict line.
plog="$(logpath)"
case "$plog" in "$state/runs/"*-[0-9]*T[0-9]*Z-[0-9]*.log) pname_ok=1 ;; *) pname_ok=0 ;; esac
if names_log && [ "$pname_ok" -eq 1 ] && [ "$(log_verdict "$plog")" = "$(grep '^ci-local: PASS after' <<<"$out")" ] \
   && grep -q '^ci-local: PASS after .* stamped' "$plog"; then
  ok "(LG) PASS run: first + last line name <state>/runs/<key>-<ts>-<pid>.log; it ends with the verdict"
else no "(LG) pass: log=[$plog] verdict=[$( [ -f "$plog" ] && log_verdict "$plog")] out=$out"; fi
# (3D) iq02 T04 3d: the run log's line 2 names HEAD sha + branch; stdout never carries it
_hsha="$(cd "$R" && git rev-parse HEAD 2>/dev/null)"; _hbr="$(cd "$R" && git symbolic-ref --short -q HEAD 2>/dev/null || echo detached)"
if [ "$(sed -n '2p' "$plog" 2>/dev/null)" = "ci-local: head $_hsha $_hbr" ] && ! has '^ci-local: head '; then
  ok "(3D) run log line 2 = 'ci-local: head <HEAD sha> <branch>'; not on stdout"
else no "(3D) head line: [$(sed -n '2p' "$plog" 2>/dev/null)] want [ci-local: head $_hsha $_hbr]"; fi

# (LA1) — --last reads that log back, runs nothing.
run --last
if [ "$rc" -eq 0 ] && [ "$(last_line)" = "ci-local --last: PASS $plog" ] && hasf "stamped; re-running" && [ ! -s "$FIXTURE_LOG" ]; then
  ok "(LA1) --last after a full run: that log + 'PASS <log>', exit 0, nothing ran"
else no "(LA1) rc=$rc plog=$plog out=$out"; fi

# (LM) — --last never waits on the machine gate.
sleep 60 & lm_holder=$!
mkdir -p "$tmp/machine"; ln -s "$lm_holder" "$tmp/machine/mutex.lnk"; touch "$tmp/load.hang"
t0=$(date +%s); run --last; el=$(( $(date +%s) - t0 ))
if [ "$rc" -eq 0 ] && [ "$el" -le 2 ] && [ "$(last_line)" = "ci-local --last: PASS $plog" ]; then
  ok "(LM) --last with the machine mutex held and a hanging reader: PASS in ${el}s"
else no "(LM) rc=$rc ${el}s out=$out"; fi
rm -f "$tmp/machine/mutex.lnk" "$tmp/load.hang"; kill "$lm_holder" 2>/dev/null; wait "$lm_holder" 2>/dev/null

# (WT) --wait. A seeded log for the (P) tree's key, newer than every real log, plays a run still in
# flight: its owner pid is a live sleeper and it has no verdict line yet.
b="${plog##*/}"; b="${b%.log}"; b="${b%-*}"; pkey="${b%-*}"
t0=$(date +%s); run --wait; el=$(( $(date +%s) - t0 ))
if [ "$rc" -eq 0 ] && [ "$el" -le 2 ] && [ "$(last_line)" = "ci-local --last: PASS $plog" ] && ! has "waiting" \
   && [ ! -s "$FIXTURE_LOG" ]; then ok "(WT) --wait with nothing in flight: --last's PASS at once, nothing ran"
else no "(WT) idle: rc=$rc ${el}s out=$out"; fi
sleep 60 & sleeper=$!
wlog="$state/runs/$pkey-29990101T000000Z-$sleeper.log"
echo "ci-local: log $wlog" > "$wlog"
t0=$(date +%s); CI_LOCAL_WAIT_MAX=1 CI_LOCAL_WAIT_POLL=0.2 run --wait; el=$(( $(date +%s) - t0 ))
if [ "$rc" -eq 3 ] && [ "$el" -le 4 ] && [ "$(last_line)" = "ci-local --wait: STILL-RUNNING after 1s — call --wait again $wlog" ]; then
  ok "(WT) --wait on an in-flight run: STILL-RUNNING, exit 3 at the deadline (${el}s)"
else no "(WT) deadline: rc=$rc ${el}s out=$out"; fi
( sleep 1; echo "ci-local: PASS after 1s — stamped; re-running on this exact tree is instant" >> "$wlog" ) &
wt_writer=$!
CI_LOCAL_WAIT_MAX=20 CI_LOCAL_WAIT_POLL=0.2 run --wait
wait "$wt_writer" 2>/dev/null
if [ "$rc" -eq 0 ] && has "^ci-local --wait: waiting" && [ "$(last_line)" = "ci-local --last: PASS $wlog" ]; then
  ok "(WT) --wait while the verdict lands: waits, then that run's PASS, exit 0"
else no "(WT) lands: rc=$rc out=$out"; fi
echo "ci-local: log $wlog" > "$wlog"
( sleep 1; kill "$sleeper" ) &
wt_killer=$!
t0=$(date +%s); CI_LOCAL_WAIT_MAX=20 CI_LOCAL_WAIT_POLL=0.2 run --wait; el=$(( $(date +%s) - t0 ))
wait "$wt_killer" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""
if [ "$rc" -eq 1 ] && [ "$el" -le 6 ] && [ "$(last_line)" = "ci-local --last: INCOMPLETE $wlog" ]; then
  ok "(WT) --wait when the owner dies with no verdict: INCOMPLETE, exit 1, no hang (${el}s)"
else no "(WT) owner died: rc=$rc ${el}s out=$out"; fi
rm -f "$wlog"
CI_LOCAL_WAIT_MAX=soon run --wait
if [ "$rc" -eq 2 ] && has "CI_LOCAL_WAIT_MAX must be"; then ok "(WT) a non-integer CI_LOCAL_WAIT_MAX: exit 2"
else no "(WT) bad deadline: rc=$rc out=$out"; fi
# Code lines only: the header names the `pgrep -f` trap it avoids.
if ! grep -qE 'pgrep|pkill' <<<"$(grep -v '^[[:space:]]*#' "$SUT")"; then ok "(WT) ci-local.sh never waits on a process name (no pgrep/pkill in code)"
else no "(WT) ci-local.sh uses pgrep/pkill — a name match can match its own waiter"; fi

# (LA2) — the tree changed: stale-key, and --last writes no git object (its key hashing goes to a
# temp object dir), no log and no slot ticket.
echo stale > "$R/stale-probe.txt"
objs_before="$(find "$R/.git/objects" -type f | wc -l | tr -d ' ')"; logs_before="$(nlogs)"
run --last
objs_after="$(find "$R/.git/objects" -type f | wc -l | tr -d ' ')"
if [ "$rc" -eq 1 ] && grep -q "^ci-local --last: stale-key (log key [^ ]*, current key [^ ]*) $plog\$" <<<"$(last_line)" \
   && [ ! -s "$FIXTURE_LOG" ]; then ok "(LA2) changed tree: --last says stale-key, exit 1, nothing ran"
else no "(LA2) rc=$rc out=$out"; fi
if [ "$objs_before" = "$objs_after" ] && [ "$logs_before" = "$(nlogs)" ] && [ -z "$(ls "$state/tickets")" ]; then
  ok "(LA2) --last wrote no git object, no log, no ticket"
else no "(LA2) writes: objects $objs_before→$objs_after logs $logs_before→$(nlogs) tickets=[$(ls "$state/tickets")]"; fi
rm -f "$R/stale-probe.txt"

# (C)
run
if [ "$rc" -eq 0 ] && has "PASS (cached)" && [ ! -s "$FIXTURE_LOG" ]; then ok "(C) unchanged tree: cached, nothing ran"
else no "(C) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
if [ "$(nlogs)" = 1 ] && ! has "^ci-local: log "; then ok "(LG) a cached PASS found before the slot writes no log"
else no "(LG) cached run: logs=$(nlogs) out=$out"; fi

# (X) — a second clone of the same origin on the identical tree shares the pass stamp.
R2="$tmp/clone"
git clone -q "$R" "$R2" && ( cd "$R2" && git remote set-url origin "$ORIGIN_URL" \
  && git update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse refs/remotes/origin/main)" )
: > "$FIXTURE_LOG"; out="$(cd "$R2" && bash scripts/ci-local.sh 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && has "PASS (cached)" && [ ! -s "$FIXTURE_LOG" ]; then ok "(X) another clone, same origin: PASS (cached), nothing ran"
else no "(X) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
( cd "$R2" && git remote set-url origin "https://example.invalid/other/repo.git" )
: > "$FIXTURE_LOG"; out="$(cd "$R2" && bash scripts/ci-local.sh 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ran one && ! has "cached"; then ok "(X) same clone, different origin: own cache, re-ran"
else no "(X) other origin: rc=$rc out=$out"; fi
rm -rf "$R2"

# (U)
echo new > "$R/scripts/new-untracked.txt"
run
if [ "$rc" -eq 0 ] && ran vendor && ! has "cached"; then ok "(U) untracked file: cache miss, vendor gate saw it via the temp index"
else no "(U) rc=$rc out=$out"; fi
if ( cd "$R" && git diff --cached --quiet && ! git ls-files --error-unmatch scripts/new-untracked.txt >/dev/null 2>&1 ); then
  ok "(U) real index untouched (file still untracked, nothing staged)"
else no "(U) the real index was modified"; fi
if ( cd "$R" && bash scripts/check-vendor-coupling.sh ) >/dev/null 2>&1; then
  no "(U) MUTATION CONTROL: fixture gate passed against the real index — (U) proves nothing"
else ok "(U) MUTATION CONTROL: same gate against the real index fails"; fi

# (F)
FIXTURE_FAIL_A=1 run --force
if [ "$rc" -eq 1 ] && has "FAIL"; then ok "(F) failing gate under --force: exit 1"
else no "(F) rc=$rc out=$out"; fi
flog="$(logpath)"
if names_log && grep -q '^ci-local: FAIL after' <<<"$(log_verdict "$flog")" \
   && grep -q '^================ FAIL (exit 1): .*check-a' "$flog"; then
  ok "(LG) FAIL run: first + last line name the log; it holds the runner's FAIL banner and ends with the FAIL verdict"
else no "(LG) fail: log=[$flog] out=$out"; fi
run
if [ "$rc" -eq 0 ] && ran "check-a plain" && ! has "cached"; then ok "(F) the failure removed the old PASS stamp: next run re-ran"
else no "(F) next run: rc=$rc out=$out"; fi

# (O)
( cd "$R" && git add -A && git commit -qm more && git update-ref refs/remotes/origin/main HEAD )
run; run
if [ "$rc" -eq 0 ] && has "PASS (cached)"; then :; else no "(O) setup: second run not cached: $out"; fi
# A never-seen base (not HEAD~1: an earlier arm already stamped that tree against it).
( cd "$R" && git update-ref refs/remotes/origin/main "$(git commit-tree 'HEAD^{tree}' -p HEAD -m side)" )
run
if [ "$rc" -eq 0 ] && ran one && ! has "cached"; then ok "(O) origin/main moved: cache miss, re-ran"
else no "(O) rc=$rc out=$out"; fi

# (M)
FIXTURE_TOUCH=1 run --force
if [ "$rc" -eq 0 ] && has "NOT cached"; then ok "(M) tree changed mid-run: PASS not cached"
else no "(M) rc=$rc out=$out"; fi
mlog="$(logpath)"
run
if [ "$rc" -eq 0 ] && ran one && ! has "PASS (cached)"; then ok "(M) next run re-ran"
else no "(M) next run: rc=$rc out=$out"; fi
# (UV) — back on the (M) run's starting tree (the next run above logged the touched tree, so the (M)
# log is the newest for this key): its "NOT cached" verdict is not a PASS --last may report.
rm -f "$R/touched.txt"
run --last
if [ "$rc" -eq 1 ] && [ "$(last_line)" = "ci-local --last: UNVERIFIED (tree changed during the run — result not cached) $mlog" ] \
   && ! has "last: PASS" && [ ! -s "$FIXTURE_LOG" ]; then ok "(UV) --last on a tree-moved run's log: UNVERIFIED, exit 1"
else no "(UV) rc=$rc mlog=$mlog out=$out"; fi

# (L) — one slot, held by a live process whose own acquire call has already exited.
sleep 30 & sleeper=$!
LOOMWRIGHT_CI_SLOTS=1 slot acquire holder --pid "$sleeper" >/dev/null
LOOMWRIGHT_CI_SLOTS=1 CI_LOCAL_LOCK_WAIT=1 run --force
if [ "$rc" -eq 1 ] && has "giving up" && has "waiting for a CI slot — position 1, holders: holder (" \
   && [ ! -s "$FIXTURE_LOG" ]; then ok "(L) live holder: waited with a progress line, then exit 1, nothing ran"
else no "(L) live: rc=$rc out=$out"; fi
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""
LOOMWRIGHT_CI_SLOTS=1 run --force
held="$(ls "$state/slots")"
if [ "$rc" -eq 0 ] && has "is gone" && ran one && [ -z "$held" ]; then ok "(L) dead holder: slot taken over, run passed, slot released"
else no "(L) dead: rc=$rc slots_left=[$held] out=$out"; fi
if [ ! -e "$R/.git/loomwright-ci-local" ]; then ok "(L) no per-clone loomwright-ci-local dir is created"
else no "(L) the per-clone loomwright-ci-local dir still exists"; fi

# (LS) — the (L) run above stamped the current tree.
ls_logs="$(nlogs)"
run --list
if [ "$rc" -eq 0 ] && has "^key: " && has "^cache: PASS stamped" && [ ! -s "$FIXTURE_LOG" ]; then ok "(LS) --list: key + cached status, nothing ran"
else no "(LS) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
want_gates=$'gate: scripts/check-a.sh --self-test\ngate: scripts/check-a.sh\ngate: scripts/check-vendor-coupling.sh'
want_tests=$'test: scripts/test-extra.sh\ntest: loomwright/scripts/test-one.sh'
if [ "$(grep '^gate: ' <<<"$out")" = "$want_gates" ] && [ "$(grep '^test: ' <<<"$out")" = "$want_tests" ]; then
  ok "(LS) --list: exactly the ci.yml gates (with arguments) and the plain tests, in order"
else no "(LS) plan lines: $out"; fi
if has "/gates/"; then no "(LS) --list leaked a temp gate-wrapper path: $out"; else ok "(LS) --list hides the temp gate wrappers"; fi
if [ "$(nlogs)" = "$ls_logs" ] && ! has "^ci-local: log "; then ok "(LS) --list writes no run log"
else no "(LS) --list wrote a log: $ls_logs→$(nlogs)"; fi
echo x > "$R/list-probe.txt"
run --list
if [ "$rc" -eq 0 ] && has "^cache: miss" && [ ! -s "$FIXTURE_LOG" ]; then ok "(LS) --list on a changed tree: cache miss, nothing ran"
else no "(LS) changed tree: rc=$rc out=$out"; fi
rm -f "$R/list-probe.txt"

# (J)
LOOMWRIGHT_CI_SLOTS=2 LOOMWRIGHT_CI_CPUS=12 run --force
if [ "$rc" -eq 0 ] && has "CI slot 1, 6 jobs" && has "(6 at a time)"; then ok "(J) SELF_TEST_JOBS = the slot's share (12 CPUs / 2 slots = 6)"
else no "(J) share: rc=$rc out=$out"; fi
SELF_TEST_JOBS=3 LOOMWRIGHT_CI_SLOTS=2 LOOMWRIGHT_CI_CPUS=12 run --force
if [ "$rc" -eq 0 ] && has "(3 at a time)" && ! has "(6 at a time)"; then ok "(J) an explicit SELF_TEST_JOBS is passed through unchanged"
else no "(J) explicit: rc=$rc out=$out"; fi

# (Q) — a waiter whose holder stamps the very tree it is waiting to verify.
echo q > "$R/q-probe.txt"
qkey="$(cd "$R" && bash scripts/ci-local.sh --list 2>/dev/null | sed -n 's/^key: //p')"
sleep 30 & sleeper=$!
LOOMWRIGHT_CI_SLOTS=1 slot acquire holder --pid "$sleeper" >/dev/null
: > "$FIXTURE_LOG"
( cd "$R" && LOOMWRIGHT_CI_SLOTS=1 CI_LOCAL_LOCK_WAIT=30 bash scripts/ci-local.sh > "$tmp/q.out" 2>&1; echo "$?" > "$tmp/q.rc" ) &
qpid=$!
i=0
while ! grep -q '"waiters":\[{' <<<"$(slot status --json)" && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
[ -n "$qkey" ] && date '+%Y-%m-%dT%H:%M:%S%z' > "$state/pass/$qkey"
slot release --pid "$sleeper"
wait "$qpid"
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""
out="$(cat "$tmp/q.out")"
if [ -n "$qkey" ] && [ "$(cat "$tmp/q.rc")" = 0 ] && has "waiting for a CI slot" && has "PASS (cached)" && [ ! -s "$FIXTURE_LOG" ]; then
  ok "(Q) waiter behind a holder that stamped the same tree: PASS (cached), nothing ran"
else no "(Q) key=$qkey rc=$(cat "$tmp/q.rc") log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
# (QC) — that waiter's log ends with the cached verdict, which --last reports as PASS.
qlog="$(logpath)"
if names_log && grep -q '^ci-local: PASS (cached)' <<<"$(log_verdict "$qlog")"; then
  run --last
  if [ "$rc" -eq 0 ] && [ "$(last_line)" = "ci-local --last: PASS $qlog" ]; then
    ok "(QC) post-slot cache hit: log ends 'PASS (cached)', --last reports PASS"
  else no "(QC) --last: rc=$rc out=$out"; fi
else no "(QC) waiter log=[$qlog] out=$out"; fi
rm -f "$R/q-probe.txt"

# (T) — TERM to a run queued for a slot exits at once (not after CI_LOCAL_LOCK_WAIT), leaves no ticket.
echo t > "$R/t-probe.txt"
sleep 60 & sleeper=$!
LOOMWRIGHT_CI_SLOTS=1 slot acquire holder --pid "$sleeper" >/dev/null
: > "$FIXTURE_LOG"
( cd "$R" && LOOMWRIGHT_CI_SLOTS=1 CI_LOCAL_LOCK_WAIT=60 exec bash scripts/ci-local.sh > "$tmp/t.out" 2>&1 ) &
tpid=$!
i=0
while ! grep -q "\"waiters\":\[{\"ticket\":[0-9]*,\"pid\":$tpid," <<<"$(slot status --json)" && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
queued=$i
kill -TERM "$tpid" 2>/dev/null
i=0
while kill -0 "$tpid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
if kill -0 "$tpid" 2>/dev/null; then trc="still-running"; kill -KILL "$tpid" 2>/dev/null; wait "$tpid" 2>/dev/null
else wait "$tpid"; trc=$?; fi
tickets="$(ls "$state/tickets")"
tslots="$(grep -lx "$tpid" "$state"/slots/*/info 2>/dev/null || true)"
slot release --pid "$sleeper"
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""
if [ "$queued" -lt 150 ] && [ "$trc" = 143 ] && [ -z "$tickets" ] && [ -z "$tslots" ] && [ ! -s "$FIXTURE_LOG" ]; then
  ok "(T) TERM to a queued run: exit 143 within 5s, no ticket or slot left, nothing ran"
else no "(T) queued_polls=$queued rc=$trc tickets=[$tickets] slots=[$tslots] out=$(cat "$tmp/t.out")"; fi
# (LG)/(IN) — the TERMed run still named its log first and last; that log has no verdict line, so
# --last (same tree) reports it INCOMPLETE, never PASS.
out="$(cat "$tmp/t.out")"
tlog="$(logpath)"
if names_log && ! grep -qE '^ci-local: (PASS|FAIL)' "$tlog"; then ok "(LG) TERM while queued: first + last line name the log; no verdict in it"
else no "(LG) term: log=[$tlog] out=$out"; fi
run --last
if [ "$rc" -eq 1 ] && [ "$(last_line)" = "ci-local --last: INCOMPLETE $tlog" ] && ! has "last: PASS"; then
  ok "(IN) a log cut off without a verdict: --last INCOMPLETE, exit 1"
else no "(IN) rc=$rc tlog=$tlog out=$out"; fi
rm -f "$R/t-probe.txt"

# (B) — a broken slot helper: the fixture's ci-slot.sh is swapped for a stub that logs every call.
stub_log="$tmp/stub.log"
cat > "$R/loomwright/scripts/ci-slot.sh" <<'SH'
echo "$*" >> "$STUB_LOG"
case "$1:$STUB_MODE" in
  dir:dir-fail)  exit 3 ;;
  dir:dir-empty) exit 0 ;;
  dir:*)         echo "$STUB_STATE" ;;
  acquire:*)     echo "slot=1 jobs=abc"; exit 0 ;;
esac
exit 0
SH
for mode in dir-fail dir-empty; do
  : > "$stub_log"
  STUB_LOG="$stub_log" STUB_MODE="$mode" run --force
  if [ "$rc" -eq 1 ] && has "ci-slot.sh dir failed" && [ ! -s "$FIXTURE_LOG" ] && ! grep -q '^acquire' "$stub_log"; then
    ok "(B) slot helper 'dir' $mode: exit 1, dir-failure message, nothing ran, no acquire"
  else no "(B) $mode: rc=$rc calls=[$(tr '\n' ' ' < "$stub_log")] out=$out"; fi
done
: > "$stub_log"
STUB_LOG="$stub_log" STUB_MODE=bad-acquire STUB_STATE="$tmp/stub-state" run --force
if [ "$rc" -eq 1 ] && has "unexpected answer from loomwright/scripts/ci-slot.sh: 'slot=1 jobs=abc'" \
   && [ ! -s "$FIXTURE_LOG" ] && grep -qE '^release --pid [0-9]+$' "$stub_log"; then
  ok "(B) malformed acquire answer: exit 1 'unexpected answer from', nothing ran, EXIT trap released"
else no "(B) bad-acquire: rc=$rc calls=[$(tr '\n' ' ' < "$stub_log")] out=$out"; fi
cp "$REPO_ROOT/loomwright/scripts/ci-slot.sh" "$R/loomwright/scripts/ci-slot.sh"
rm -rf "$tmp/stub-state" "$stub_log"
if ( cd "$R" && git diff --quiet -- loomwright/scripts/ci-slot.sh ); then ok "(B) real slot helper restored for later arms"
else no "(B) the fixture's ci-slot.sh was not restored"; fi

# (H)
run --help
if [ "$rc" -eq 0 ] && has "^ci-local.sh — " && has "^usage: ci-local.sh" && has "^Self-test: scripts/test-ci-local.sh" \
   && ! has "^#" && ! has "set -euo"; then ok "(H) --help: the whole header, de-commented, no code"
else no "(H) rc=$rc out=$out"; fi
if has "^  --affected  " && has "^  --last  " && has "^usage: ci-local.sh .*--affected.*--last"; then ok "(H) --help documents --affected and --last"
else no "(H) --affected/--last missing from --help: $out"; fi
# The header ends at the first non-comment line, whatever that line is — not at a literal `set -euo`.
sed 's/^set -euo pipefail$/set -eu -o pipefail/' "$R/scripts/ci-local.sh" > "$R/scripts/ci-local-variant.sh"
out="$(cd "$R" && bash scripts/ci-local-variant.sh --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && has "^Self-test: scripts/test-ci-local.sh" && ! has "set -eu" && ! has "shopt"; then ok "(H) --help survives a changed first code line"
else no "(H) variant: rc=$rc out=$out"; fi
rm -f "$R/scripts/ci-local-variant.sh"

# --- --affected, --last selection, pruning ------------------------------------------------------------
# Setup: a library script with its own suite, an unrelated suite, a cheap validate-version gate and a
# ci.yml-named test-check-a.sh — committed, and origin/main moved there, so the changed set is empty.
cat >> "$R/.github/workflows/ci.yml" <<'YML'
      - run: bash scripts/test-check-a.sh
      - run: bash scripts/validate-version.sh
YML
echo 'echo "test-check-a" >> "$FIXTURE_LOG"' > "$R/scripts/test-check-a.sh"
echo 'echo "validate" >> "$FIXTURE_LOG"' > "$R/scripts/validate-version.sh"
echo ': library' > "$R/loomwright/scripts/one.sh"
echo 'echo "two" >> "$FIXTURE_LOG"' > "$R/loomwright/scripts/test-two.sh"
( cd "$R" && git add -A && git commit -qm affected-fixture && git update-ref refs/remotes/origin/main HEAD )
marker="affected-only — not a pre-push gate; run ci-local.sh before pushing"
cheap_ran() { ran "check-a --self-test" && ran "check-a plain" && ran vendor && ran validate; }
# The marker is the line right before the closing log-path line.
marker_last() { [ "$(awk '{ p = c; c = $0 } END { print p }' <<<"$out")" = "$marker" ] && names_log; }
stamp_free() { [ -z "$(ls "$state/pass")" ]; }

# (AF5)
run --affected
if [ "$rc" -eq 0 ] && has "the changed set is empty" && cheap_ran && ! ran one && ! ran two && ! ran extra \
   && ! ran test-check-a && marker_last; then ok "(AF5) empty changed set: says so, ran the cheap gates only"
else no "(AF5) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi

# (AF1)
echo ': edited' >> "$R/loomwright/scripts/one.sh"
run --affected
alog="$(logpath)"
if [ "$rc" -eq 0 ] && hasf "loomwright/scripts/one.sh ⇒ loomwright/scripts/test-one.sh" && ran one && cheap_ran \
   && ! ran two && ! ran extra && ! ran test-check-a && ! has "not covered by --affected:" && marker_last; then
  ok "(AF1) changed loomwright script: its test + check-*/validate-version gates ran, no other test"
else no "(AF1) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
case "$alog" in "$state/runs/"*-affected.log) ok "(AF1) the run log is named …-affected.log" ;;
  *) no "(AF1) affected log name: [$alog]" ;; esac

# (AF6) — same changed tree, --list: the plan only.
logs_before="$(nlogs)"
run --affected --list
want_aplan=$'gate: scripts/check-a.sh --self-test\ngate: scripts/check-a.sh\ngate: scripts/check-vendor-coupling.sh\ngate: scripts/validate-version.sh\ntest: loomwright/scripts/test-one.sh'
if [ "$rc" -eq 0 ] && hasf "loomwright/scripts/one.sh ⇒ loomwright/scripts/test-one.sh" \
   && [ "$(grep -E '^(gate|test): ' <<<"$out")" = "$want_aplan" ] && [ ! -s "$FIXTURE_LOG" ] \
   && [ "$(nlogs)" = "$logs_before" ] && ! has "^ci-local: log "; then
  ok "(AF6) --affected --list: changed file, mapped plan in full-plan order; nothing ran, no log"
else no "(AF6) rc=$rc logs=$logs_before→$(nlogs) out=$out"; fi

# (AF7) — no origin/main: says so and diffs against HEAD (the uncommitted edit is still found).
om="$(cd "$R" && git rev-parse refs/remotes/origin/main)"
( cd "$R" && git update-ref -d refs/remotes/origin/main )
run --affected --list
if [ "$rc" -eq 0 ] && hasf "HEAD (origin/main is absent)" && hasf "loomwright/scripts/one.sh ⇒ loomwright/scripts/test-one.sh"; then
  ok "(AF7) origin/main absent: says so, falls back to HEAD"
else no "(AF7) rc=$rc out=$out"; fi
( cd "$R" && git update-ref refs/remotes/origin/main "$om" )

# (AF3) — never creates (PASS) nor removes (FAIL) a pass stamp.
rm -f "$state/pass/"*
run --affected
if [ "$rc" -eq 0 ] && stamp_free && marker_last; then ok "(AF3) green --affected: no pass stamp written"
else no "(AF3) green: rc=$rc pass=[$(ls "$state/pass")] out=$out"; fi
akey="$(cd "$R" && bash scripts/ci-local.sh --list 2>/dev/null | sed -n 's/^key: //p')"
echo seeded > "$state/pass/$akey"
FIXTURE_FAIL_A=1 run --affected
if [ -n "$akey" ] && [ "$rc" -eq 1 ] && [ "$(ls "$state/pass")" = "$akey" ] && [ "$(cat "$state/pass/$akey")" = seeded ] \
   && has "^ci-local --affected: FAIL" && marker_last; then
  ok "(AF3) failing --affected: exit 1, the existing stamp left exactly as it was"
else no "(AF3) fail: key=$akey rc=$rc pass=[$(ls "$state/pass")] out=$out"; fi
rm -f "$state/pass/"*
# MUTATION CONTROL: a copy that stamps on an --affected PASS must fail the same stamp_free check.
awk '/^  verdict="ci-local --affected: PASS after/ { print "  date > \"$stamp\""; n++ } { print } END { exit n != 1 }' \
  "$R/scripts/ci-local.sh" > "$R/scripts/ci-local-mutant.sh"
mut_rc=$?
: > "$FIXTURE_LOG"; out="$(cd "$R" && bash scripts/ci-local-mutant.sh --affected 2>&1)"; rc=$?
if [ "$mut_rc" -eq 0 ] && [ "$rc" -eq 0 ] && ! stamp_free; then ok "(AF3) MUTATION CONTROL: a stamping --affected is caught"
else no "(AF3) MUTATION CONTROL: anchor_found=$((1 - mut_rc)) rc=$rc pass=[$(ls "$state/pass")] — the never-stamps check proves nothing"; fi
rm -f "$R/scripts/ci-local-mutant.sh" "$state/pass/"*

# (AF2) — an untracked unmapped file and a deleted test are uncovered.
echo readme > "$R/README.md"; rm "$R/loomwright/scripts/test-two.sh"
run --affected
if [ "$rc" -eq 0 ] && has "^not covered by --affected:\$" && has "^  README.md\$" \
   && has "^  loomwright/scripts/test-two.sh\$" && ran one && ! ran two && marker_last; then
  ok "(AF2) unmapped + deleted files listed under 'not covered by --affected:'"
else no "(AF2) rc=$rc out=$out"; fi
rm -f "$R/README.md"; ( cd "$R" && git checkout -q -- loomwright/scripts/test-two.sh loomwright/scripts/one.sh )

# (AF4) — a changed root check-*.sh brings in its ci.yml-named test-check-*.sh.
echo '# edited' >> "$R/scripts/check-a.sh"
run --affected
if [ "$rc" -eq 0 ] && hasf "scripts/check-a.sh ⇒ scripts/test-check-a.sh" && ran test-check-a && cheap_ran \
   && ! ran one && ! ran extra; then ok "(AF4) changed scripts/check-a.sh: test-check-a.sh ran"
else no "(AF4) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
( cd "$R" && git checkout -q -- scripts/check-a.sh )

# (LA3) — a full run, then a newer --affected run on the same tree: --last still prints the full log.
run --force
full_log="$(logpath)"
run --affected
run --last
if [ "$rc" -eq 0 ] && [ "$(last_line)" = "ci-local --last: PASS $full_log" ] && ! hasf "-affected.log" \
   && ! hasf "$marker"; then ok "(LA3) --last skips a newer --affected log"
else no "(LA3) rc=$rc full_log=$full_log out=$out"; fi

# (AX)
for combo in "--affected --force" "--last --affected" "--last --force" "--last --list" "--force --last" \
             "--wait --force" "--wait --list" "--affected --wait"; do
  run $combo
  if [ "$rc" -eq 2 ] && has "conflicting options" && [ ! -s "$FIXTURE_LOG" ]; then ok "(AX) $combo: exit 2"
  else no "(AX) $combo: rc=$rc out=$out"; fi
done

# (PR) — no logs: --last says so; 25 seeded finished logs + one run: the newest 20 remain.
rm -f "$state/runs/"*
run --last
if [ "$rc" -eq 1 ] && has "no saved full-run log"; then ok "(PR) no logs at all: --last says so, exit 1"
else no "(PR) empty: rc=$rc out=$out"; fi
i=0
# Seeds are FINISHED logs (verdict line): prunable whatever their name's pid is doing.
seed_finished() {
  i=0
  while [ "$i" -lt 25 ]; do
    echo "ci-local: PASS after 1s" > "$state/runs/seedkey-x-Linux-20200101T0000$(printf '%02d' "$i")Z-1.log"; i=$((i + 1))
  done
}
seed_finished
run --force
prlog="$(logpath)"
gone=0; i=0
while [ "$i" -lt 6 ]; do [ -e "$state/runs/seedkey-x-Linux-20200101T0000$(printf '%02d' "$i")Z-1.log" ] || gone=$((gone + 1)); i=$((i + 1)); done
if [ "$rc" -eq 0 ] && [ "$(nlogs)" = 20 ] && [ -f "$prlog" ] && [ "$gone" = 6 ] \
   && [ -e "$state/runs/seedkey-x-Linux-20200101T000006Z-1.log" ]; then ok "(PR) 25 + 1 logs pruned to 20: the 6 oldest gone, the run's own log kept"
else no "(PR) logs=$(nlogs) gone=$gone prlog=$prlog"; fi

# (PI) — an in-flight run's log (no verdict yet, owner pid alive) survives another run's prune even
# with 20+ newer logs present, and the total stays 20 (own + live + 18 newest finished): the cap
# gives way to live logs only, never to extra finished ones; a verdict-less log whose owner is dead
# is pruned as usual.
rm -f "$state/runs/"*
sleep 60 & sleeper=$!
deadpid="$(sh -c 'echo $$')"
live_log="$state/runs/seedkey-x-Linux-20190101T000000Z-$sleeper.log"
dead_log="$state/runs/seedkey-x-Linux-20190101T000001Z-$deadpid.log"
echo "ci-local: log $live_log" > "$live_log"
echo "ci-local: log $dead_log" > "$dead_log"
seed_finished
run --force
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""
kept_seeds=0; i=0
while [ "$i" -lt 25 ]; do [ ! -e "$state/runs/seedkey-x-Linux-20200101T0000$(printf '%02d' "$i")Z-1.log" ] || kept_seeds=$((kept_seeds + 1)); i=$((i + 1)); done
if [ "$rc" -eq 0 ] && [ -f "$live_log" ] && [ "$(cat "$live_log")" = "ci-local: log $live_log" ] && [ ! -e "$dead_log" ] \
   && [ "$(nlogs)" = 20 ] && [ "$kept_seeds" = 18 ] && [ -e "$state/runs/seedkey-x-Linux-20200101T000024Z-1.log" ]; then
  ok "(PI) in-flight log kept untouched, total still 20 (own + live + 18 newest finished), dead-owner verdict-less log pruned"
else no "(PI) rc=$rc logs=$(nlogs) seeds_kept=$kept_seeds live=$([ -f "$live_log" ] && echo kept || echo GONE) dead=$([ -e "$dead_log" ] && echo KEPT || echo gone)"; fi

# (PA) — --affected logs never push the full-run log out (S3 wave-1 review of #397): one full run,
# then 25 NEWER finished --affected logs and another --affected run; the full log survives, the total
# is still 20, and --last still finds it.
rm -f "$state/runs/"*
run --force
pa_full="$(logpath)"
i=0
while [ "$i" -lt 25 ]; do
  echo "ci-local --affected: PASS after 1s" > "$state/runs/seedkey-x-Linux-20990101T0000$(printf '%02d' "$i")Z-1-affected.log"; i=$((i + 1))
done
run --affected
pa_aff="$(logpath)"
run --last
if [ -f "$pa_full" ] && [ -f "$pa_aff" ] && [ "$(nlogs)" = 20 ] && [ "$rc" -eq 0 ] \
   && [ "$(last_line)" = "ci-local --last: PASS $pa_full" ]; then
  ok "(PA) 25 newer --affected logs + an --affected run: the full-run log survives, total 20, --last finds it"
else no "(PA) full=$([ -f "$pa_full" ] && echo kept || echo GONE) logs=$(nlogs) rc=$rc last=$(last_line)"; fi

# (PG) — the run's own log removed mid-run: no verdict-only stub is recreated, the run says so.
rm -f "$state/runs/"*
FIXTURE_RMLOGS="$state/runs" run --force
if [ "$rc" -eq 0 ] && [ "$(nlogs)" = 0 ] && has "was removed while this run wrote it" && has "^ci-local: PASS after"; then
  ok "(PG) log removed mid-run: no stub recreated, verdict still printed, removal reported"
else no "(PG) rc=$rc logs=$(nlogs) out=$out"; fi

# --- early phase (iq02 T05) -----------------------------------------------------------------------------
build_fixture
cat >> "$R/.github/workflows/ci.yml" <<'YML'
      - run: bash scripts/test-check-a.sh
      - run: bash scripts/check-new.sh
      - run: bash loomwright/scripts/gen.sh --check
YML
echo 'echo "test-check-a" >> "$FIXTURE_LOG"' > "$R/scripts/test-check-a.sh"
echo 'echo "check-new" >> "$FIXTURE_LOG"' > "$R/scripts/check-new.sh"
printf '%s\n' 'echo "gen ${1:-plain}" >> "$FIXTURE_LOG"' 'exit "${FIXTURE_FAIL_GEN:-0}"' > "$R/loomwright/scripts/gen.sh"
printf '%s\n' '#!/usr/bin/env bash' '# run-self-tests: early' 'echo "mark" >> "$FIXTURE_LOG"' > "$R/loomwright/scripts/test-mark.sh"
( cd "$R" && git add -A && git commit -qm early-fixture && git update-ref refs/remotes/origin/main HEAD )
early_lines() { grep '^early: ' <<<"$out"; }
want_early=$'early: scripts/check-a.sh --self-test\nearly: scripts/check-a.sh\nearly: scripts/check-vendor-coupling.sh\nearly: scripts/check-new.sh\nearly: loomwright/scripts/gen.sh --check\nearly: loomwright/scripts/test-mark.sh'

# (EL)
run --list
if [ "$rc" -eq 0 ] && [ "$(early_lines)" = "$want_early" ] && has "^phases: 6 early, 3 in the pool$" && ! has "/gates/"; then
  ok "(EL) early set derived: new check-new.sh + gen.sh --check + the marked test; test-check-a.sh gate stays in the pool"
else no "(EL) rc=$rc out=$out"; fi
# (EM) MUTATION CONTROL — the same test without its marker line runs in the pool.
cp "$R/loomwright/scripts/test-mark.sh" "$tmp/mark.bak"
grep -vx '# run-self-tests: early' "$tmp/mark.bak" > "$R/loomwright/scripts/test-mark.sh"
run --list
if ! cmp -s "$tmp/mark.bak" "$R/loomwright/scripts/test-mark.sh" && [ "$rc" -eq 0 ] && ! has "^early: loomwright/scripts/test-mark.sh$" \
   && has "^phases: 5 early, 4 in the pool$"; then ok "(EM) MUTATION CONTROL: marker removed ⇒ the test moves to the pool"
else no "(EM) the early set ignores the marker: rc=$rc out=$out"; fi
cp "$tmp/mark.bak" "$R/loomwright/scripts/test-mark.sh"

# (ER) — two early gates red (check-a, gen --check): early phase only, all named, stamp removed.
run --list; ekey="$(sed -n 's/^key: //p' <<<"$out")"
[ -n "$ekey" ] && echo seeded > "$state/pass/$ekey"
FIXTURE_FAIL_A=1 FIXTURE_FAIL_GEN=1 run --force
elog="$(logpath)"
if [ "$rc" -eq 1 ] && [ -n "$ekey" ] && [ ! -e "$state/pass/$ekey" ] && ran mark && ran vendor && ran "check-new" \
   && ! ran one && ! ran extra && ! ran test-check-a && has "FAIL (exit 1): .*/gates/[0-9]*-check-a.sh" \
   && has "FAIL (exit 1): .*/gates/[0-9]*-gen.sh" && has "run-self-tests: FAIL (exit 1, " \
   && case "$(log_verdict "$elog")" in "ci-local: FAIL after "*"early gates failed; pool skipped"*) true ;; *) false ;; esac \
   && names_log; then ok "(ER) early red: exit 1, every red early gate named, no pool entry ran, stamp removed, FAIL verdict last"
else no "(ER) rc=$rc stamp=$([ -e "$state/pass/$ekey" ] && echo kept || echo gone) log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
run --last
if [ "$rc" -eq 1 ] && hasf "ci-local --last: FAIL $elog"; then ok "(ER) --last reports the early-red run as FAIL"
else no "(ER) --last: rc=$rc out=$out"; fi

# (EG) — green: every entry exactly once, the early set first, stamped.
run --force
want_all=$'check-a --self-test\ncheck-a plain\ncheck-new\nextra\ngen --check\nmark\none\ntest-check-a\nvendor'
want_first=$'check-a --self-test\ncheck-a plain\ncheck-new\ngen --check\nmark\nvendor'
if [ "$rc" -eq 0 ] && has "stamped" && [ "$(sort "$FIXTURE_LOG")" = "$want_all" ] \
   && [ "$(sed -n '1,6p' "$FIXTURE_LOG" | sort)" = "$want_first" ] && has "early phase green after"; then
  ok "(EG) green: every full-plan entry exactly once, the early set before the pool, stamped"
else no "(EG) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi

# (EX) MUTATION CONTROL — a copy that skips the early-red exit runs the pool on a red early phase.
awk '/^    exit 1   # early-red exit$/ { print "    :"; n++; next } { print } END { exit n != 1 }' \
  "$R/scripts/ci-local.sh" > "$R/scripts/ci-local-mutant.sh"
mut_rc=$?
if [ "$mut_rc" -eq 0 ] && [ -s "$R/scripts/ci-local-mutant.sh" ] && ! cmp -s "$R/scripts/ci-local.sh" "$R/scripts/ci-local-mutant.sh" \
   && bash -n "$R/scripts/ci-local-mutant.sh"; then
  : > "$FIXTURE_LOG"; out="$(cd "$R" && FIXTURE_FAIL_A=1 bash scripts/ci-local-mutant.sh --force 2>&1)"; rc=$?
  if ran one; then ok "(EX) MUTATION CONTROL: a copy skipping the early-red exit starts the pool — (ER)'s ! ran one catches it"
  else no "(EX) the mutant did not reach the pool — (ER) proves nothing: out=$out"; fi
else no "(EX) MUTATION CONTROL: mutant not built (anchor_found=$((1 - mut_rc)))"; fi
rm -f "$R/scripts/ci-local-mutant.sh"

# (AFC) — --affected on an empty changed set runs the whole early set (the --check gate included).
run --affected
if [ "$rc" -eq 0 ] && has "the early set only" && ran "gen --check" && ran mark && ran "check-new" && ran vendor \
   && ! ran one && ! ran extra && ! ran test-check-a; then ok "(AFC) --affected runs the --check gate and the early-marked test"
else no "(AFC) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi

# (AF8) — no early entry and nothing mapped ⇒ the empty-plan refusal still fires.
printf 'jobs:\n  ci:\n    steps:\n      - run: bash scripts/test-check-a.sh\n' > "$R/.github/workflows/ci.yml"
rm -f "$R/loomwright/scripts/test-mark.sh"
( cd "$R" && git add -A && git commit -qm only-test-gate && git update-ref refs/remotes/origin/main HEAD )
run --affected
if [ "$rc" -eq 1 ] && has "refusing to report green on an empty plan" && [ ! -s "$FIXTURE_LOG" ]; then
  ok "(AF8) early set and mapped set both empty: --affected refuses an empty plan"
else no "(AF8) rc=$rc out=$out"; fi

# (Z)
printf 'jobs:\n  ci:\n    steps:\n      - run: echo nothing\n' > "$R/.github/workflows/ci.yml"
run
if [ "$rc" -eq 1 ] && has "zero gates"; then ok "(Z) no gates in ci.yml: exit 1"
else no "(Z) rc=$rc out=$out"; fi

# (LC) — a `bash loomwright/scripts/<x>.sh --check` line is a gate; other loomwright lines are not.
printf 'jobs:\n  ci:\n    steps:\n      - run: bash scripts/check-a.sh\n      - run: bash loomwright/scripts/check-l.sh --check\n      - run: bash loomwright/scripts/run-self-tests.sh\n' > "$R/.github/workflows/ci.yml"
printf 'echo "check-l ${1:-plain}" >> "$FIXTURE_LOG"\n' > "$R/loomwright/scripts/check-l.sh"
run --list
want_lc=$'gate: scripts/check-a.sh\ngate: loomwright/scripts/check-l.sh --check'
if [ "$rc" -eq 0 ] && [ "$(grep '^gate: ' <<<"$out")" = "$want_lc" ]; then ok "(LC) a loomwright --check line is a gate; the suite runner line is not"
else no "(LC) rc=$rc out=$out"; fi
rm -f "$R/loomwright/scripts/check-l.sh"

# (A)
run --bogus
if [ "$rc" -eq 2 ]; then ok "(A) unknown argument: exit 2"; else no "(A) rc=$rc"; fi

# (W)
glob='loomwright/scripts/test-\*.sh loomwright/scripts/adapters/\*/test-\*.sh'
if grep -q "($glob)" "$SUT" && grep -q "($glob)" "$REPO_ROOT/loomwright/scripts/run-self-tests.sh"; then ok "(W) suite glob matches run-self-tests.sh"
else no "(W) ci-local.sh's loomwright glob drifted from run-self-tests.sh's"; fi
if grep -q 'bash scripts/test-ci-local.sh' "$REPO_ROOT/.github/workflows/ci.yml"; then ok "(W) ci.yml runs this self-test"
else no "(W) .github/workflows/ci.yml does not run scripts/test-ci-local.sh"; fi
if grep -q 'bash loomwright/scripts/build-capabilities.sh --check' "$REPO_ROOT/.github/workflows/ci.yml"; then ok "(W) ci.yml runs the capability-contract staleness gate (so ci-local does too)"
else no "(W) .github/workflows/ci.yml does not run loomwright/scripts/build-capabilities.sh --check"; fi

echo
echo "test-ci-local: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
