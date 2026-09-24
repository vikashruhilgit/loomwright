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
#   (W)  wiring: ci.yml's self-test step invokes run-self-tests.sh
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
printf 'echo flat > "%s/flat.ran"\n' "$T" > "$G/loomwright/scripts/test-flat.sh"
printf 'echo adapter > "%s/adapter.ran"\n' "$T" > "$G/loomwright/scripts/adapters/tool/test-adapter.sh"
( cd / && GITHUB_ACTIONS= bash "$G/loomwright/scripts/run-self-tests.sh" > "$T/g.out" 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/flat.ran" ] && [ -f "$T/adapter.ran" ] \
  && ok "(G) no args, run from an unrelated cwd: both the flat and the adapters/*/ test ran" \
  || no "(G) rc=$rc flat=$([ -f "$T/flat.ran" ] && echo y) adapter=$([ -f "$T/adapter.ran" ] && echo y): $(cat "$T/g.out")"
E="$T/empty-repo"
mkdir -p "$E/loomwright/scripts"
cp "$RUNNER" "$E/loomwright/scripts/run-self-tests.sh"
GITHUB_ACTIONS= bash "$E/loomwright/scripts/run-self-tests.sh" > "$T/e.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "matched nothing" "$T/e.out" \
  && ok "(G) an empty layout fails LOUDLY (exit 1, 'matched nothing') — never green on zero tests" \
  || no "(G) empty layout: rc=$rc $(cat "$T/e.out")"

echo "== (W) wiring: ci.yml invokes the runner =="
if [ -f "$CI_YML" ]; then
  grep -q 'bash loomwright/scripts/run-self-tests.sh' "$CI_YML" \
    && ok "(W) ci.yml's self-test step invokes run-self-tests.sh" \
    || no "(W) ci.yml does not invoke loomwright/scripts/run-self-tests.sh"
else
  no "(W) ci.yml not found at $CI_YML"
fi

echo
echo "test-run-self-tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
