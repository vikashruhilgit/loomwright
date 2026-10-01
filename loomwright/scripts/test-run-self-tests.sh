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

echo
echo "test-run-self-tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
