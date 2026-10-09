#!/usr/bin/env bash
# test-run-self-tests.sh — self-test for run-self-tests.sh, the concurrent runner behind CI's
# "Run full deterministic self-test suite" step. Every arm drives the runner against FIXTURE tests
# in a mktemp dir, never the real suite (the real suite includes this file). Exit 0 = all pass,
# 1 = any failure (auto-registered by the runner's own test-*.sh glob).
#
# Arms:
#   (P)  all fixtures pass                         → exit 0, "all N self-tests passed"
#   (F)  one fixture fails among passes            → exit 1, the FAIL banner names it, its output is
#                                                    printed, and a test AFTER it in the list still
#                                                    ran (a red test must not hide the rest)
#   (K)  a fixture kills its own worker            → exit 1 (a missing result is a failure, never a pass)
#   (C)  concurrency is real: A waits for a file B writes → passes 2-way;
#        MUTATION CONTROL: the same pair 1-way     → exit 1 (A runs alone and times out) — proves (C)
#                                                    can tell a parallel runner from a serial one
#   (S)  a `# run-self-tests: serial` fixture runs AFTER the concurrent batch (it sees the file a
#        slow concurrent fixture writes last) → exit 0;
#        MUTATION CONTROL: the same fixture WITHOUT the marker runs alongside it → exit 1
#   (J)  SELF_TEST_JOBS not a positive integer     → exit 1
#   (G)  no-argument glob, in a fake repo layout   → runs flat test-*.sh AND adapters/*/test-*.sh;
#        an empty layout                           → exit 1, "matched nothing"
#   (G2) hermetic-test-env.sh missing beside the runner → exit 1, "refusing", no fixture test ran
#   (G3) the helper present but mktemp failing everywhere (it leaves HERMETIC_SHIM_DIR empty)
#                                                  → exit 1, "left no shim dir", no fixture test ran
#   (H)  egress-hermetic runner layer: a worker sees the helper's effect though the parent exported
#        LOOMWRIGHT_WEBHOOK_URL
#   (T)  a fixture that never exits (with a background child) under SELF_TEST_TIMEOUT=2
#                                                  → exit 1, TIMEOUT banner, stderr names the test
#                                                    and prints its process tree, the child is
#                                                    killed, and a passing fixture still passes;
#        MUTATION CONTROL: a slow fixture that FINISHES inside the limit → exit 0 (no false timeout)
#   (TJ) SELF_TEST_TIMEOUT not a positive integer  → exit 1
#   (W)  wiring: ci.yml's self-test step invokes run-self-tests.sh, and the ci job is capped
#        with timeout-minutes
#   (AD) machine admission through ci-slot.sh (12 CPUs, 2 slots ⇒ 6 jobs a suite): with two live
#        6-job holders in two OTHER repos, a bare runner gives up after SELF_TEST_SLOT_WAIT=1
#        (exit 1, nothing ran); with a longer wait it is queued ("held for load: committed") and
#        runs nothing until a holder releases, then passes with the slot's job share; under a live
#        parent holder of its own pool (N=1, load overloaded — ci-local.sh's shape) it FOLDS: runs
#        at once, adds no slot or machine record.
#        MUTATION CONTROL: the admission call replaced by a fake grant ⇒ the wait check fails.
#   (AD2) ci-slot.sh missing beside the runner → exit 1, "refusing", no fixture test ran
#   (FS) iq02 T05: a red test is STREAMED — `run-self-tests: FAIL (exit <rc>, <secs>s): <test>` is in
#        the output while a slow green test is still running (it waits, bounded, for that line) and
#        precedes its PASS line; the end-of-run banner + summary are unchanged;
#        MUTATION CONTROL: a runner copy without the streamed line ⇒ the slow test never sees it
#   (SH) iq02 T08 --shard K/N / --list: in a fake layout and on the REAL suite, the union of shards
#        1..N equals --list with no duplicate (N = 1..4); a test absent from the weights file is still
#        scheduled; malformed K/N, a bare --shard and --shard with test arguments ⇒ exit 1; more shards
#        than tests ⇒ an empty shard exits 0; SELF_TEST_MANIFEST names every selected test with its rc
#        (a red one too); MUTATION CONTROL: a split that drops one test breaks the union check
#   (AG) iq02 T08: the REAL ci.yml `ci` job's inline aggregation block, extracted and run against
#        manifests built from the real shards: all green ⇒ 0; a dropped manifest, a test no shard
#        ran, a test run twice, a non-zero rc, a failed or skipped needed job ⇒ exit 1, each named
#   (EM) `# run-self-tests: early`: --select-marked early prints the marked subset in input order and
#        runs nothing; in a default run the marker is inert (the test stays concurrent); a test
#        marked both early and serial ⇒ exit 1, named (default run and --select-marked)
#
# Admission sandbox: every runner call here takes its ci-slot.sh slot from a sandboxed pool and
# machine list, with a fixture load reader, so neither a real holder nor a loaded machine holds it.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/run-self-tests.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

T="$(mktemp -d "${TMPDIR:-/tmp}/test-run-self-tests.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
export XDG_STATE_HOME="$T/state" LOOMWRIGHT_MACHINE_STATE_DIR="$T/machine" LOOMWRIGHT_MACHINE_LOAD_CMD="$T/load.sh"
export LOOMWRIGHT_CI_SLOT_POLL=0.2 LOOMWRIGHT_MACHINE_LOAD_RECHECK=1
unset LOOMWRIGHT_CI_SLOTS LOOMWRIGHT_CI_CPUS SELF_TEST_SLOT_WAIT
cat > "$T/load.sh" <<'EOF'
echo "load1=1.00"; echo "state=$(cat "$(dirname "$0")/load.state" 2>/dev/null || echo ok)"
EOF

# run <outfile> <runner args...> — runs the runner with GitHub grouping OFF, returns its exit code
run() {
  local o="$1"; shift
  GITHUB_ACTIONS= bash "$RUNNER" "$@" > "$o" 2>&1
}

cat > "$T/pass1.sh" <<'EOF'
echo "pass1 says hi"
EOF
cat > "$T/pass2.sh" <<'EOF'
echo ran > "$(dirname "$0")/pass2.ran"
EOF
cat > "$T/fail.sh" <<'EOF'
echo "fail-marker-output"
exit 3
EOF
cat > "$T/killer.sh" <<'EOF'
kill -9 "$PPID"
sleep 5
EOF
# rendezvous: A waits (bounded) for the file B writes. Serially A runs first and times out.
cat > "$T/rv-a.sh" <<'EOF'
d="$(dirname "$0")"; n=0
while [ ! -f "$d/rv.flag" ]; do sleep 0.1; n=$((n+1)); [ "$n" -ge 50 ] && { echo "rendezvous timed out"; exit 1; }; done
rm -f "$d/rv.flag"
EOF
cat > "$T/rv-b.sh" <<'EOF'
touch "$(dirname "$0")/rv.flag"
EOF

echo "== (P) all pass =="
run "$T/p.out" "$T/pass1.sh" "$T/pass2.sh"; rc=$?
[ "$rc" -eq 0 ] && grep -q "all 2 self-tests passed" "$T/p.out" \
  && ok "(P) two passing fixtures → exit 0 and the pass summary" \
  || no "(P) rc=$rc: $(cat "$T/p.out")"

echo "== (F) a failure is reported, and does not hide later tests =="
rm -f "$T/pass2.ran"
SELF_TEST_JOBS=1 run "$T/f.out" "$T/pass1.sh" "$T/fail.sh" "$T/pass2.sh"; rc=$?
[ "$rc" -eq 1 ] && ok "(F) exit 1 when one fixture fails" || no "(F) expected exit 1, got $rc"
grep -q "FAIL (exit 3): $T/fail.sh" "$T/f.out" && ok "(F) the FAIL banner names the failing test and its exit code" \
  || no "(F) no FAIL banner for fail.sh: $(cat "$T/f.out")"
grep -q "fail-marker-output" "$T/f.out" && ok "(F) the failing test's own output is printed" \
  || no "(F) failing test's output missing"
[ -f "$T/pass2.ran" ] && ok "(F) the test listed AFTER the failure still ran (serial set -e loop hid these)" \
  || no "(F) pass2.sh never ran after the failure"

echo "== (K) a worker that dies leaves no result → failure =="
run "$T/k.out" "$T/killer.sh" "$T/pass1.sh"; rc=$?
[ "$rc" -eq 1 ] && ok "(K) a killed worker fails the run (exit 1), never counted as a pass" \
  || no "(K) expected exit 1, got $rc: $(cat "$T/k.out")"

echo "== (C) concurrency is real, with a serial mutation control =="
rm -f "$T/rv.flag"
SELF_TEST_JOBS=2 run "$T/c.out" "$T/rv-a.sh" "$T/rv-b.sh"; rc=$?
[ "$rc" -eq 0 ] && ok "(C) 2-way: A and B overlap, the rendezvous completes" \
  || no "(C) 2-way rendezvous failed (rc=$rc): $(cat "$T/c.out")"
rm -f "$T/rv.flag"
SELF_TEST_JOBS=1 run "$T/c1.out" "$T/rv-a.sh" "$T/rv-b.sh"; rc=$?
rm -f "$T/rv.flag"
[ "$rc" -eq 1 ] && grep -q "rendezvous timed out" "$T/c1.out" \
  && ok "(C) MUTATION CONTROL: 1-way, the same pair deadlocks and fails — (C) distinguishes parallel from serial" \
  || no "(C) MUTATION CONTROL: 1-way expected exit 1 + timeout, got $rc"

echo "== (S) serial-marked tests run after the concurrent batch, with a mutation control =="
cat > "$T/slow-par.sh" <<'EOF'
sleep 1; touch "$(dirname "$0")/slow-par.done"
EOF
{ echo '# run-self-tests: serial'; echo '[ -f "$(dirname "$0")/slow-par.done" ] || { echo "ran before the concurrent batch finished"; exit 1; }'; } > "$T/ser.sh"
grep -v '^# run-self-tests: serial$' "$T/ser.sh" > "$T/ser-unmarked.sh"
rm -f "$T/slow-par.done"
SELF_TEST_JOBS=4 run "$T/s.out" "$T/ser.sh" "$T/slow-par.sh"; rc=$?
[ "$rc" -eq 0 ] && grep -q "1 concurrently (4 at a time), then 1 serially" "$T/s.out" \
  && ok "(S) the marked test ran alone AFTER the concurrent batch, though listed first" \
  || no "(S) rc=$rc: $(cat "$T/s.out")"
rm -f "$T/slow-par.done"
SELF_TEST_JOBS=4 run "$T/s2.out" "$T/ser-unmarked.sh" "$T/slow-par.sh"; rc=$?
[ "$rc" -eq 1 ] && grep -q "ran before the concurrent batch finished" "$T/s2.out" \
  && ok "(S) MUTATION CONTROL: without the marker the same test runs concurrently and fails — the marker is load-bearing" \
  || no "(S) MUTATION CONTROL: unmarked expected exit 1, got $rc"

echo "== (J) SELF_TEST_JOBS validation =="
for bad in abc 0 -2; do
  SELF_TEST_JOBS="$bad" run "$T/j.out" "$T/pass1.sh"; rc=$?
  [ "$rc" -eq 1 ] && ok "(J) SELF_TEST_JOBS='$bad' refused (exit 1)" || no "(J) SELF_TEST_JOBS='$bad' → rc=$rc"
done

echo "== (G) no-argument glob covers flat AND adapter tests; empty fails closed =="
G="$T/fake-repo"
mkdir -p "$G/loomwright/scripts/adapters/tool"
cp "$RUNNER" "$G/loomwright/scripts/run-self-tests.sh"
cp "$HERE/hermetic-test-env.sh" "$G/loomwright/scripts/hermetic-test-env.sh"
cp "$HERE/ci-slot.sh" "$G/loomwright/scripts/ci-slot.sh"; git init -q "$G"   # machine admission needs both
printf 'echo flat > "%s/flat.ran"\n' "$T" > "$G/loomwright/scripts/test-flat.sh"
printf 'echo adapter > "%s/adapter.ran"\n' "$T" > "$G/loomwright/scripts/adapters/tool/test-adapter.sh"
( cd / && GITHUB_ACTIONS= bash "$G/loomwright/scripts/run-self-tests.sh" > "$T/g.out" 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/flat.ran" ] && [ -f "$T/adapter.ran" ] \
  && ok "(G) no args, run from an unrelated cwd: both the flat and the adapters/*/ test ran" \
  || no "(G) rc=$rc flat=$([ -f "$T/flat.ran" ] && echo y) adapter=$([ -f "$T/adapter.ran" ] && echo y): $(cat "$T/g.out")"
E="$T/empty-repo"
mkdir -p "$E/loomwright/scripts"
cp "$RUNNER" "$E/loomwright/scripts/run-self-tests.sh"
cp "$HERE/hermetic-test-env.sh" "$E/loomwright/scripts/hermetic-test-env.sh"
GITHUB_ACTIONS= bash "$E/loomwright/scripts/run-self-tests.sh" > "$T/e.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "matched nothing" "$T/e.out" \
  && ok "(G) an empty layout fails LOUDLY (exit 1, 'matched nothing') — never green on zero tests" \
  || no "(G) empty layout: rc=$rc $(cat "$T/e.out")"

echo "== (G2) helper missing: the runner refuses to run un-hermetic =="
G2="$T/no-helper-repo"
mkdir -p "$G2/loomwright/scripts"
cp "$RUNNER" "$G2/loomwright/scripts/run-self-tests.sh"
printf 'echo ran > "%s/g2.ran"\n' "$T" > "$G2/loomwright/scripts/test-g2.sh"
[ ! -e "$G2/loomwright/scripts/hermetic-test-env.sh" ] || no "(G2) precondition: the fixture must NOT carry the helper"
GITHUB_ACTIONS= bash "$G2/loomwright/scripts/run-self-tests.sh" > "$T/g2.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "refusing to run the suite without the egress-hermetic layer" "$T/g2.out" && [ ! -f "$T/g2.ran" ] \
  && ok "(G2) no hermetic-test-env.sh beside the runner → exit 1, 'refusing', and the fixture test never ran" \
  || no "(G2) rc=$rc ran=$([ -f "$T/g2.ran" ] && echo y || echo n): $(cat "$T/g2.out")"

echo "== (G3) helper present but no shim dir (mktemp fails everywhere): the runner fails closed =="
# A failing `mktemp` shadows the real one, and this test's own shim dir is stripped from the
# environment so the helper cannot reuse it — both of its mktemp attempts fail and it leaves
# HERMETIC_SHIM_DIR empty (it only warns; it never exits). The runner must refuse, not run bare.
G3="$T/no-shim-repo"
mkdir -p "$G3/loomwright/scripts" "$T/g3-bin"
cp "$RUNNER" "$G3/loomwright/scripts/run-self-tests.sh"
cp "$HERE/hermetic-test-env.sh" "$G3/loomwright/scripts/hermetic-test-env.sh"
printf 'echo ran > "%s/g3.ran"\n' "$T" > "$G3/loomwright/scripts/test-g3.sh"
printf '#!/bin/sh\nexit 1\n' > "$T/g3-bin/mktemp"; chmod +x "$T/g3-bin/mktemp"
( PATH="$T/g3-bin:$(hermetic_path_without_shims)"
  unset HERMETIC_SHIM_DIR HERMETIC_EGRESS_LOG HERMETIC_TEST_ENV
  GITHUB_ACTIONS= bash "$G3/loomwright/scripts/run-self-tests.sh" > "$T/g3.out" 2>&1 ); rc=$?
[ "$rc" -eq 1 ] && grep -q "left no shim dir" "$T/g3.out" && grep -q "WARNING: mktemp failed" "$T/g3.out" && [ ! -f "$T/g3.ran" ] \
  && ok "(G3) helper warned (mktemp failed twice) → runner exit 1, 'left no shim dir', fixture test never ran" \
  || no "(G3) rc=$rc ran=$([ -f "$T/g3.ran" ] && echo y || echo n): $(cat "$T/g3.out")"

echo "== (H) egress-hermetic runner layer: workers see the helper's effect even when the parent exports the egress env =="
# The fixture test deliberately does NOT source the helper, so what it observes is the RUNNER's layer.
# The parent is re-dangered first: this test's own helper state is stripped (shim dir off PATH,
# markers unset) and LOOMWRIGHT_WEBHOOK_URL is exported, exactly like an owner's terminal.
cat > "$T/hermetic-probe.sh" <<'EOF'
printf '%s|%s|%s|%s\n' "${HERMETIC_TEST_ENV:-unset}" "${LOOMWRIGHT_WEBHOOK_URL:-unset}" \
  "${LOOMWRIGHT_DESKTOP_NOTIFICATIONS:-unset}" "$(command -v osascript 2>/dev/null)" > "$(dirname "$0")/hermetic-probe.seen"
EOF
( PATH="$(hermetic_path_without_shims)"
  unset HERMETIC_TEST_ENV HERMETIC_SHIM_DIR HERMETIC_EGRESS_LOG LOOMWRIGHT_DESKTOP_NOTIFICATIONS
  export LOOMWRIGHT_WEBHOOK_URL="http://127.0.0.1:9/parent-exported"
  [ "${LOOMWRIGHT_WEBHOOK_URL:-}" = "http://127.0.0.1:9/parent-exported" ] && [ -z "${HERMETIC_TEST_ENV:-}" ] \
    && echo "parent-dangered" > "$T/hermetic-parent.state"
  run "$T/h.out" "$T/hermetic-probe.sh" ); rc=$?
seen="$(cat "$T/hermetic-probe.seen" 2>/dev/null || true)"
IFS='|' read -r h_marker h_url h_desk h_osa <<<"$seen"
if [ "$rc" -eq 0 ] && [ -f "$T/hermetic-parent.state" ] && [ "$h_marker" = "1" ] && [ "$h_url" = "unset" ] \
   && [ "$h_desk" = "0" ] && [ -n "$h_osa" ] && [ -f "$(dirname "$h_osa")/.hermetic-shim-dir" ]; then
  ok "(H) worker saw HERMETIC_TEST_ENV=1, LOOMWRIGHT_WEBHOOK_URL unset, notifications=0, osascript -> a hermetic stub, though the parent exported the URL"
else
  no "(H) runner layer missing: rc=$rc parent=$(cat "$T/hermetic-parent.state" 2>/dev/null) seen='$seen' $(cat "$T/h.out")"
fi

echo "== (T) per-test watchdog: a test that never exits is killed and named =="
# The hung fixture mimics the CI hang's footprint: a background python-like child plus a
# foreground wait that never returns. Its pid file lets us prove the child was killed too.
cat > "$T/hang.sh" <<'EOF'
d="$(dirname "$0")"
sleep 300 & echo $! > "$d/hang-child.pid"
echo "hang-marker-before-wait"
sleep 300
EOF
cat > "$T/slow-ok.sh" <<'EOF'
sleep 1; echo done
EOF
rm -f "$T/hang-child.pid"
t0=$(date +%s)
SELF_TEST_TIMEOUT=2 run "$T/t.out" "$T/hang.sh" "$T/pass1.sh"; rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 1 ] && ok "(T) a never-exiting test fails the run (exit 1)" || no "(T) expected exit 1, got $rc: $(cat "$T/t.out")"
[ "$el" -lt 30 ] && ok "(T) the run ended in ${el}s (limit 2s + kill grace) instead of waiting on the hung test" || no "(T) run took ${el}s"
grep -q "FAIL (exit 124 — TIMEOUT after 2s): $T/hang.sh" "$T/t.out" && ok "(T) the FAIL banner says TIMEOUT and names the test" \
  || no "(T) no TIMEOUT banner: $(cat "$T/t.out")"
grep -q "run-self-tests: TIMEOUT after 2s: $T/hang.sh" "$T/t.out" && grep -q "sleep 300" "$T/t.out" \
  && ok "(T) the live stderr report names the test and lists its process tree (the hung 'sleep 300')" \
  || no "(T) live report missing test name or process tree: $(cat "$T/t.out")"
grep -q "hang-marker-before-wait" "$T/t.out" && ok "(T) the hung test's own output tail is printed" || no "(T) output tail missing"
grep -q "PASS .* $T/pass1.sh" "$T/t.out" && ok "(T) the passing fixture alongside it still passed" || no "(T) pass1.sh not reported PASS"
cpid="$(cat "$T/hang-child.pid" 2>/dev/null || true)"
if [ -n "$cpid" ] && ! kill -0 "$cpid" 2>/dev/null; then ok "(T) the hung test's background child was killed with it"
else no "(T) background child ${cpid:-<no pid>} survived the watchdog"; kill "$cpid" 2>/dev/null; fi
SELF_TEST_TIMEOUT=5 run "$T/t2.out" "$T/slow-ok.sh"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q TIMEOUT "$T/t2.out" \
  && ok "(T) MUTATION CONTROL: a 1s test under a 5s limit passes — the watchdog fires only on a real overrun" \
  || no "(T) MUTATION CONTROL: slow-but-finishing test rc=$rc: $(cat "$T/t2.out")"

echo "== (TJ) SELF_TEST_TIMEOUT validation =="
for bad in abc 0 -5; do
  SELF_TEST_TIMEOUT="$bad" run "$T/tj.out" "$T/pass1.sh"; rc=$?
  [ "$rc" -eq 1 ] && grep -q "SELF_TEST_TIMEOUT must be a positive integer" "$T/tj.out" \
    && ok "(TJ) SELF_TEST_TIMEOUT='$bad' refused (exit 1)" || no "(TJ) SELF_TEST_TIMEOUT='$bad' → rc=$rc"
done

echo "== (W) wiring: ci.yml invokes the runner =="
if [ -f "$CI_YML" ]; then
  grep -q 'bash loomwright/scripts/run-self-tests.sh' "$CI_YML" \
    && ok "(W) ci.yml's self-test step invokes run-self-tests.sh" \
    || no "(W) ci.yml does not invoke loomwright/scripts/run-self-tests.sh"
  grep -qE '^    timeout-minutes: [0-9]+' "$CI_YML" \
    && ok "(W) the ci job carries a timeout-minutes cap (backstop for the per-test watchdog)" \
    || no "(W) ci.yml's ci job has no timeout-minutes — a hung step would run to GitHub's 6-hour default"
else
  no "(W) ci.yml not found at $CI_YML"
fi

echo "== (AD) machine admission: a bare run waits behind two live 6-job holders, folds under a live parent =="
# adm_layout DIR RUNNER — a git checkout holding RUNNER with the helpers it needs beside it.
adm_layout() {
  rm -rf "$1"; mkdir -p "$1/loomwright/scripts"
  cp "$2" "$1/loomwright/scripts/run-self-tests.sh"
  cp "$HERE/hermetic-test-env.sh" "$HERE/ci-slot.sh" "$1/loomwright/scripts/"
  git init -q "$1"
}
cat > "$T/adm-probe.sh" <<'EOF'
echo ran >> "$(dirname "$0")/adm.ran"
EOF
git init -q "$T/adm-other1"; git init -q "$T/adm-other2"
# admission_holds RUNNER — exit 0 iff RUNNER waits for machine admission; ADWHY says what failed.
admission_holds() {
  local d="$T/adm-run" h1 h2 rp i rc
  ADWHY=""; rm -f "$T/adm.ran" "$T/adm.rc" "$T/load.state"; rm -rf "$T/machine" "$T/state"
  adm_layout "$d" "$1"
  sleep 120 & h1=$!; sleep 120 & h2=$!
  ( cd "$T/adm-other1" && LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 bash "$HERE/ci-slot.sh" acquire h1 --pid "$h1" ) >/dev/null 2>&1
  ( cd "$T/adm-other2" && LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 bash "$HERE/ci-slot.sh" acquire h2 --pid "$h2" ) >/dev/null 2>&1
  [ "$(ls "$T/machine/holders" 2>/dev/null | wc -l | tr -d ' ')" = 2 ] || ADWHY="precondition: two machine holders not recorded"
  if [ -z "$ADWHY" ]; then
    LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 SELF_TEST_SLOT_WAIT=1 GITHUB_ACTIONS= \
      bash "$d/loomwright/scripts/run-self-tests.sh" "$T/adm-probe.sh" > "$T/adm1.out" 2>&1; rc=$?
    if [ "$rc" -ne 1 ] || [ -f "$T/adm.ran" ] || ! grep -q "no CI slot after 1s" "$T/adm1.out"; then
      ADWHY="SELF_TEST_SLOT_WAIT=1 behind two 6-job holders: rc=$rc ran=$([ -f "$T/adm.ran" ] && echo y || echo n): $(cat "$T/adm1.out")"
    fi
  fi
  if [ -z "$ADWHY" ]; then
    rm -f "$T/adm.ran"
    ( LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=2 SELF_TEST_SLOT_WAIT=30 GITHUB_ACTIONS= \
        bash "$d/loomwright/scripts/run-self-tests.sh" "$T/adm-probe.sh" > "$T/adm2.out" 2>&1; echo "$?" > "$T/adm.rc" ) &
    rp=$!
    i=0
    while ! grep -q '"waiters":\[{' <<<"$(cd "$d" && bash loomwright/scripts/ci-slot.sh status --json 2>/dev/null)" && [ "$i" -lt 50 ]; do
      sleep 0.1; i=$((i + 1))
    done
    sleep 1
    if [ "$i" -ge 50 ]; then ADWHY="the runner never queued for a slot (ran=$([ -f "$T/adm.ran" ] && echo y || echo n)): $(cat "$T/adm2.out")"
    elif [ -f "$T/adm.ran" ] || [ -f "$T/adm.rc" ]; then ADWHY="the runner did not wait while both holders lived: $(cat "$T/adm2.out")"
    fi
    ( cd "$T/adm-other1" && bash "$HERE/ci-slot.sh" release --pid "$h1" )
    i=0; while [ ! -f "$T/adm.rc" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
    if [ -z "$ADWHY" ]; then
      if [ "$(cat "$T/adm.rc" 2>/dev/null)" != 0 ] || [ ! -f "$T/adm.ran" ]; then
        ADWHY="after a holder released the runner did not pass: rc=$(cat "$T/adm.rc" 2>/dev/null): $(cat "$T/adm2.out")"
      elif ! grep -q "held for load: committed 12+6 jobs > 12 CPUs" "$T/adm2.out" || ! grep -q "(6 at a time)" "$T/adm2.out"; then
        ADWHY="no committed-work hold line, or not the slot's 6-job share: $(cat "$T/adm2.out")"
      fi
    fi
    kill "$rp" 2>/dev/null; wait "$rp" 2>/dev/null
  fi
  ( cd "$T/adm-other2" && bash "$HERE/ci-slot.sh" release --pid "$h2" )
  kill "$h1" "$h2" 2>/dev/null; wait "$h1" "$h2" 2>/dev/null
  [ -z "$ADWHY" ]
}
if admission_holds "$RUNNER"; then
  ok "(AD) behind two live 6-job holders: gives up at SELF_TEST_SLOT_WAIT=1 (nothing ran); queued and idle until a holder releases, then passes 6-way"
else no "(AD) $ADWHY"; fi
mut="$T/mut-run-self-tests.sh"
sed 's|^( cd "$here" \&\& exec bash "$slot_helper" acquire .*# ADMISSION$|echo "slot=0 jobs=2" > "$out/slot" \&|' "$RUNNER" > "$mut"
if [ -s "$mut" ] && ! cmp -s "$mut" "$RUNNER" && bash -n "$mut" && ! grep -q '# ADMISSION$' "$mut"; then
  if admission_holds "$mut"; then no "(AD) MUTATION CONTROL: without the admission call the runner still waited — (AD) proves nothing"
  else ok "(AD) MUTATION CONTROL: the admission call replaced by a fake grant fails (AD) ($ADWHY)"; fi
else no "(AD) MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"; fi

# Fold: a parent holding the ONLY slot of the runner's own pool runs the runner as its child, at load
# overloaded — without the fold the child would wait on its own parent until SELF_TEST_SLOT_WAIT.
adm_layout "$T/adm-fold" "$RUNNER"; rm -rf "$T/machine" "$T/state"; rm -f "$T/adm.ran" "$T/load.state"
cat > "$T/adm-parent.sh" <<'EOF'
cd "$1" || exit 1
export LOOMWRIGHT_CI_CPUS=12 LOOMWRIGHT_CI_SLOTS=1
bash loomwright/scripts/ci-slot.sh acquire parent --pid $$ >/dev/null 2>&1 || { echo "parent-not-granted"; exit 1; }
echo overloaded > "$2/load.state"
GITHUB_ACTIONS= SELF_TEST_SLOT_WAIT=3 bash loomwright/scripts/run-self-tests.sh "$2/adm-probe.sh" > "$2/fold.out" 2>&1; rc=$?
echo ok > "$2/load.state"
slots="$(ls "$(bash loomwright/scripts/ci-slot.sh dir)/slots" | wc -l | tr -d ' ')"
mrecs="$(ls "$2/machine/holders" | wc -l | tr -d ' ')"
bash loomwright/scripts/ci-slot.sh release --pid $$
echo "rc=$rc slots=$slots mrecs=$mrecs"
EOF
fold="$(bash "$T/adm-parent.sh" "$T/adm-fold" "$T")"
if [ "$fold" = "rc=0 slots=1 mrecs=1" ] && [ -f "$T/adm.ran" ] && grep -q "CI slot 1$" "$T/fold.out"; then
  ok "(AD) under a live parent holder of its own pool (N=1, overloaded) the runner folds: ran at once, parent's slot 1, no second slot or machine record"
else no "(AD) fold: $fold ran=$([ -f "$T/adm.ran" ] && echo y || echo n): $(cat "$T/fold.out" 2>/dev/null)"; fi

echo "== (AD2) ci-slot.sh missing beside the runner: refuses to run without admission =="
A2="$T/no-slot-repo"
mkdir -p "$A2/loomwright/scripts"
cp "$RUNNER" "$HERE/hermetic-test-env.sh" "$A2/loomwright/scripts/"
rm -f "$T/adm.ran"
GITHUB_ACTIONS= bash "$A2/loomwright/scripts/run-self-tests.sh" "$T/adm-probe.sh" > "$T/a2.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "refusing to run the suite without machine admission" "$T/a2.out" && [ ! -f "$T/adm.ran" ] \
  && ok "(AD2) no ci-slot.sh beside the runner → exit 1, 'refusing', the fixture test never ran" \
  || no "(AD2) rc=$rc ran=$([ -f "$T/adm.ran" ] && echo y || echo n): $(cat "$T/a2.out")"

echo "== (FS) a red test is streamed the moment it finishes =="
cat > "$T/fs-slow.sh" <<'EOF'
# bounded wait (FS_WAIT seconds) for the streamed FAIL line in the runner's own output
n=0
while ! grep -q "^run-self-tests: FAIL (exit 3, [0-9]*s): .*/fail.sh$" "$FS_OUT" 2>/dev/null; do
  n=$((n + 1)); [ "$n" -le $((FS_WAIT * 10)) ] || { echo notseen > "$FS_OUT.seen"; exit 0; }
  sleep 0.1
done
echo seen > "$FS_OUT.seen"
EOF
rm -f "$T/fs.out.seen"
FS_OUT="$T/fs.out" FS_WAIT=30 SELF_TEST_JOBS=2 run "$T/fs.out" "$T/fs-slow.sh" "$T/fail.sh"; rc=$?
fl="$(grep -n '^run-self-tests: FAIL (exit 3, ' "$T/fs.out" | head -1 | cut -d: -f1)"
pl="$(grep -n "^PASS [0-9]*s $T/fs-slow.sh\$" "$T/fs.out" | cut -d: -f1)"
if [ "$rc" -eq 1 ] && [ "$(cat "$T/fs.out.seen" 2>/dev/null)" = seen ] && [ -n "$fl" ] && [ -n "$pl" ] && [ "$fl" -lt "$pl" ] \
   && grep -q "FAIL (exit 3): $T/fail.sh" "$T/fs.out" && grep -q "1 of 2 self-tests FAILED" "$T/fs.out"; then
  ok "(FS) the FAIL line was in the output while the slow test still ran, before its PASS line; the end report is unchanged"
else no "(FS) rc=$rc seen=$(cat "$T/fs.out.seen" 2>/dev/null) fail_line=$fl pass_line=$pl: $(cat "$T/fs.out")"; fi
# MUTATION CONTROL: a runner copy without the streamed FAIL line (beside its helpers, same layout).
FSM="$T/fs-mutant"; mkdir -p "$FSM"; git init -q "$FSM"   # ci-slot.sh keys admission by repo
cp "$HERE/hermetic-test-env.sh" "$HERE/ci-slot.sh" "$HERE/machine-load.sh" "$FSM/" 2>/dev/null
grep -v 'then echo "run-self-tests: FAIL (exit \$rc, \${secs}s): \$t"; fi$' "$RUNNER" > "$FSM/run-self-tests.sh"
if [ -s "$FSM/run-self-tests.sh" ] && ! cmp -s "$RUNNER" "$FSM/run-self-tests.sh" && bash -n "$FSM/run-self-tests.sh"; then
  rm -f "$T/fsm.out.seen"
  FS_OUT="$T/fsm.out" FS_WAIT=3 SELF_TEST_JOBS=2 GITHUB_ACTIONS= bash "$FSM/run-self-tests.sh" "$T/fs-slow.sh" "$T/fail.sh" > "$T/fsm.out" 2>&1
  [ "$(cat "$T/fsm.out.seen" 2>/dev/null)" = notseen ] \
    && ok "(FS) MUTATION CONTROL: without the streamed line the slow test never sees a FAIL — (FS) can fail" \
    || no "(FS) MUTATION CONTROL: seen=$(cat "$T/fsm.out.seen" 2>/dev/null): $(cat "$T/fsm.out")"
else no "(FS) MUTATION CONTROL: mutant not built"; fi

echo "== (SH) --shard K/N and --list: the union of the shards is the suite =="
SH="$T/shard-repo"; mkdir -p "$SH/loomwright/scripts/fixtures" "$SH/loomwright/scripts/adapters/tool"
cp "$RUNNER" "$HERE/hermetic-test-env.sh" "$HERE/ci-slot.sh" "$HERE/machine-load.sh" "$SH/loomwright/scripts/"
git init -q "$SH"
for n in a b c d e f g; do printf '%s\n' "exit 0" > "$SH/loomwright/scripts/test-$n.sh"; done
printf '%s\n' 'echo red-out; exit 4' > "$SH/loomwright/scripts/test-red.sh"
printf '%s\n' 'exit 0' > "$SH/loomwright/scripts/adapters/tool/test-ad.sh"
printf '# w\n50\tloomwright/scripts/test-a.sh\n40\tloomwright/scripts/test-b.sh\n5\tloomwright/scripts/test-c.sh\n' > "$SH/loomwright/scripts/fixtures/self-test-weights.tsv"
SHR="$SH/loomwright/scripts/run-self-tests.sh"
# union_ok <runner> <N> — every shard's --list concatenated equals --list exactly once each
union_ok() {
  local r="$1" n="$2" k=1
  bash "$r" --list | env LC_ALL=C sort > "$T/u.want" || return 1
  : > "$T/u.got"
  while [ "$k" -le "$n" ]; do bash "$r" --shard "$k/$n" --list >> "$T/u.got" || return 1; k=$((k + 1)); done
  env LC_ALL=C sort "$T/u.got" > "$T/u.sorted"
  [ -s "$T/u.want" ] && cmp -s "$T/u.want" "$T/u.sorted"
}
uok=1; for n in 1 2 3 4; do union_ok "$SHR" "$n" || uok=0; done
[ "$uok" = 1 ] && [ "$(bash "$SHR" --list | wc -l | tr -d ' ')" = 9 ] \
  && ok "(SH) fake layout: shards 1..N union to the 9-test --list with no duplicate, N = 1..4 (flat + adapter tests, weighted and default-weight)" \
  || no "(SH) fake-layout union broken"
grep -qx 'loomwright/scripts/test-g.sh' <(bash "$SHR" --shard 1/2 --list; bash "$SHR" --shard 2/2 --list) \
  && ok "(SH) a test absent from the weights file is still scheduled" || no "(SH) unweighted test-g.sh dropped"
uok=1; for n in 1 2 3 4; do union_ok "$RUNNER" "$n" || uok=0; done
[ "$uok" = 1 ] && ok "(SH) REAL suite: shards 1..N union to run-self-tests.sh --list exactly, N = 1..4" || no "(SH) real-suite union broken"
for badarg in "0/2" "3/2" "x" "2/0" "1/2/3"; do
  bash "$SHR" --shard "$badarg" --list > "$T/sh.bad" 2>&1; rc=$?
  { [ "$rc" -eq 1 ] && grep -q "wants K/N" "$T/sh.bad"; } || no "(SH) --shard $badarg: rc=$rc $(cat "$T/sh.bad")"
done; ok "(SH) malformed K/N (0/2, 3/2, x, 2/0, 1/2/3) ⇒ exit 1, named"
bash "$SHR" --shard > "$T/sh.bare" 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "(SH) a bare --shard ⇒ exit 1" || no "(SH) bare --shard rc=$rc"
bash "$SHR" --shard 1/2 "$T/pass1.sh" > "$T/sh.args" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "take no test arguments" "$T/sh.args" && ok "(SH) --shard with test arguments ⇒ exit 1" || no "(SH) args+shard rc=$rc $(cat "$T/sh.args")"
[ -z "$(bash "$SHR" --shard 12/12 --list)" ] && SELF_TEST_MANIFEST="$T/m.empty" GITHUB_ACTIONS= bash "$SHR" --shard 12/12 > "$T/sh.e" 2>&1 \
  && [ -f "$T/m.empty" ] && [ ! -s "$T/m.empty" ] && ok "(SH) more shards than tests: the empty shard exits 0 with an empty manifest" || no "(SH) empty shard: $(cat "$T/sh.e")"
redk=""; for k in 1 2 3; do grep -qx 'loomwright/scripts/test-red.sh' <(bash "$SHR" --shard "$k/3" --list) && redk="$k"; done
SELF_TEST_MANIFEST="$T/m.red" GITHUB_ACTIONS= bash "$SHR" --shard "$redk/3" > "$T/sh.r" 2>&1; rc=$?
want_n="$(bash "$SHR" --shard "$redk/3" --list | wc -l | tr -d ' ')"
if [ "$rc" -eq 1 ] && [ "$(wc -l < "$T/m.red" | tr -d ' ')" = "$want_n" ] && grep -q $'^4\t[0-9]*\tloomwright/scripts/test-red.sh$' "$T/m.red" \
   && [ -z "$(awk -F'\t' '$3 != "loomwright/scripts/test-red.sh" && $1 != "0"' "$T/m.red")" ]; then
  ok "(SH) a red shard still writes a manifest naming every selected test with its rc (test-red.sh = 4)"
else no "(SH) manifest: rc=$rc want=$want_n $(cat "$T/m.red" 2>/dev/null)"; fi
# MUTATION CONTROL: a split that never assigns the heaviest test.
sed 's/for (i = 1; i <= m; i++) if (own\[i\] == k) print t\[i\]/for (i = 1; i <= m; i++) if (own[i] == k \&\& i != 1) print t[i]/' "$SHR" > "$SH/loomwright/scripts/run-mut.sh"
if [ -s "$SH/loomwright/scripts/run-mut.sh" ] && ! cmp -s "$SHR" "$SH/loomwright/scripts/run-mut.sh" && bash -n "$SH/loomwright/scripts/run-mut.sh"; then
  union_ok "$SH/loomwright/scripts/run-mut.sh" 2 && no "(SH) MUTATION CONTROL: a split dropping a test passed the union check" \
    || ok "(SH) MUTATION CONTROL: a split that drops one test fails the union check"
else no "(SH) MUTATION CONTROL: mutant not built"; fi

echo "== (AG) ci.yml's aggregating ci job fails closed =="
awk '/- name: Aggregate static \+ every shard/ { f = 1 } f && /^        run: \|$/ { r = 1; next } r && /^          / { sub(/^          /, ""); print; next } r && !/^          / && NF { exit }' "$CI_YML" > "$T/agg.sh"
AGT="$T/agg-temp"; AGM="$T/agg-m"
agg_setup() {
  rm -rf "$AGT" "$AGM"; mkdir -p "$AGT"
  local k
  for k in 1 2 3; do
    mkdir -p "$AGM/self-test-manifest-$k"
    ( cd "$REPO_ROOT" && bash "$RUNNER" --shard "$k/3" --list ) | awk '{ printf "0\t1\t%s\n", $0 }' > "$AGM/self-test-manifest-$k/self-test-manifest.tsv"
  done
}
agg_run() {  # agg_run <static> <suite> — runs the extracted block from the repo root
  ( cd "$REPO_ROOT" && STATIC_RESULT="$1" SUITE_RESULT="$2" MDIR="$AGM" SHARDS=3 RUNNER_TEMP="$AGT" bash "$T/agg.sh" ) > "$T/agg.out" 2>&1
}
if [ -s "$T/agg.sh" ] && grep -q 'comm -23' "$T/agg.sh" && bash -n "$T/agg.sh"; then
  agg_setup; agg_run success success; rc=$?
  [ "$rc" -eq 0 ] && ok "(AG) every shard green + every manifest present ⇒ ci passes" || no "(AG) green: rc=$rc $(cat "$T/agg.out")"
  agg_setup; rm -rf "$AGM/self-test-manifest-2"; agg_run success success; rc=$?
  [ "$rc" -eq 1 ] && grep -q "shard 2 left no result manifest" "$T/agg.out" && ok "(AG) a dropped manifest ⇒ ci fails, naming the shard" || no "(AG) dropped: rc=$rc $(cat "$T/agg.out")"
  agg_setup; m1="$AGM/self-test-manifest-1/self-test-manifest.tsv"; gone="$(head -1 "$m1" | cut -f3)"; sed -i.bak '1d' "$m1"
  agg_run success success; rc=$?
  [ "$rc" -eq 1 ] && grep -q "tests no shard ran" "$T/agg.out" && grep -qxF "$gone" "$T/agg.out" && ok "(AG) a test no shard ran ⇒ ci fails, naming it ($gone)" || no "(AG) missing: rc=$rc $(cat "$T/agg.out")"
  agg_setup; head -1 "$m1" >> "$AGM/self-test-manifest-2/self-test-manifest.tsv"; agg_run success success; rc=$?
  [ "$rc" -eq 1 ] && grep -q "more than one shard" "$T/agg.out" && ok "(AG) a test run by two shards ⇒ ci fails" || no "(AG) duplicate: rc=$rc $(cat "$T/agg.out")"
  agg_setup; sed -i.bak '1s/^0/3/' "$m1"; agg_run success success; rc=$?
  [ "$rc" -eq 1 ] && grep -q "non-zero results" "$T/agg.out" && ok "(AG) a non-zero rc in a manifest ⇒ ci fails" || no "(AG) red rc: rc=$rc $(cat "$T/agg.out")"
  agg_setup; agg_run success failure; rc=$?
  [ "$rc" -eq 1 ] && grep -q "job suite: failure" "$T/agg.out" && ok "(AG) a failed suite job ⇒ ci fails (not skipped)" || no "(AG) suite failure: rc=$rc"
  agg_setup; agg_run skipped success; rc=$?
  [ "$rc" -eq 1 ] && grep -q "job static: skipped" "$T/agg.out" && ok "(AG) a skipped static job ⇒ ci fails (skipped is not success)" || no "(AG) static skipped: rc=$rc"
else no "(AG) could not extract the ci job's aggregation block from $CI_YML"; fi
if grep -qx '  ci:' "$CI_YML" && [ "$(grep -c '^  [a-z][a-z_-]*:$' "$CI_YML")" -ge 3 ] && grep -q '^    if: always()$' "$CI_YML" \
   && grep -q '^      fail-fast: false$' "$CI_YML" && ! grep -q . < <(awk '/^  ci:$/ { f = 1 } f && /bash scripts\//' "$CI_YML"); then
  ok "(AG) exactly one job named ci, with if: always(), the suite matrix fail-fast: false, and no bash scripts/<x>.sh line in ci"
else no "(AG) ci.yml job shape"; fi

echo "== (EM) the early marker: --select-marked, inert in a default run, early+serial conflict =="
printf '%s\n' '# run-self-tests: early' 'echo early-ran > "$(dirname "$0")/em.ran"' > "$T/em-early.sh"
printf '%s\n' '# run-self-tests: earlyish' 'exit 0' > "$T/em-near.sh"
printf '%s\n' '# run-self-tests: early' '# run-self-tests: serial' 'exit 0' > "$T/em-both.sh"
sel="$(bash "$RUNNER" --select-marked early "$T/pass1.sh" "$T/em-early.sh" "$T/em-near.sh" "$T/em-early.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$sel" = "$T/em-early.sh"$'\n'"$T/em-early.sh" ] \
  && ok "(EM) --select-marked early prints exactly the marked tests, in input order (exact-line match only)" \
  || no "(EM) select: rc=$rc out=[$sel]"
sel="$(bash "$RUNNER" --select-marked serial "$T/em-early.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$sel" ] && ok "(EM) --select-marked serial does not match an early test" || no "(EM) serial select: rc=$rc out=[$sel]"
rm -f "$T/em.ran"
run "$T/em.out" "$T/em-early.sh" "$T/pass1.sh"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/em.ran" ] && grep -q "2 concurrently (.* at a time), then 0 serially" "$T/em.out" \
  && ok "(EM) a default run treats the early marker as inert: the test stays in the concurrent batch" \
  || no "(EM) default run: rc=$rc: $(cat "$T/em.out")"
run "$T/emb.out" "$T/em-both.sh" "$T/pass1.sh"; rc=$?
[ "$rc" -eq 1 ] && grep -q "$T/em-both.sh carries both" "$T/emb.out" \
  && ok "(EM) early+serial on one test: default run exits 1, naming it" || no "(EM) both: rc=$rc: $(cat "$T/emb.out")"
sel="$(bash "$RUNNER" --select-marked early "$T/em-both.sh" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && grep -q "em-both.sh carries both" <<<"$sel" \
  && ok "(EM) early+serial on one test: --select-marked exits 1, naming it" || no "(EM) both select: rc=$rc out=[$sel]"
bash "$RUNNER" --select-marked bogus "$T/pass1.sh" > "$T/emu.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "usage: run-self-tests.sh --select-marked" "$T/emu.out" && ok "(EM) an unknown marker name is a usage error" \
  || no "(EM) unknown marker: rc=$rc: $(cat "$T/emu.out")"

echo
echo "test-run-self-tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
