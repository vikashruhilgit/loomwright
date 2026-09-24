#!/usr/bin/env bash
# run-self-tests.sh — run the deterministic self-test suite CONCURRENTLY and gate on every result.
# `.github/workflows/ci.yml`'s "Run full deterministic self-test suite" step calls this; the same
# command works locally, so "run the full loop before pushing" and CI are one code path.
#
# Why it exists: the suite used to be a serial `for t in …; do bash "$t"; done` loop that left
# three of the runner's four vCPUs idle and grew from ~5 to ~14 min of wall time (Aug → Sep 2026).
# The tests are already isolated (each works in its own mktemp dir), so running them N-way cuts the
# loop to roughly the longest single test plus (total / N). Measured 4-way on the full suite:
# 1040 s of test time in 292 s wall, 98/98 green.
#
# Contract:
#   usage: run-self-tests.sh [<test.sh> ...]
#          no arguments = the canonical suite: loomwright/scripts/test-*.sh plus
#          loomwright/scripts/adapters/*/test-*.sh (adapter self-tests live one directory deeper
#          than the flat glob reaches — without the second glob they are committed tests nothing
#          runs). Future tests are auto-included — anti-drift.
#   env:   SELF_TEST_JOBS  concurrency (default: CPU count, fallback 4)
#   marker: a test carrying the exact line `# run-self-tests: serial` runs ALONE, after the
#          concurrent batch — for tests that measure wall-clock time and need an idle machine
#   exit 0 = every test ran AND exited 0
#   exit 1 = FAIL CLOSED: any test exited non-zero, any test left no result (its worker died), or
#            the glob matched nothing (a moved/renamed scripts dir fails LOUDLY, never green)
#
# Unlike the serial `set -e` loop, a red test does not hide the ones after it: every test runs,
# then each failure's full log is printed at the end. Passing logs are printed too (collapsed in
# `::group::` blocks under GitHub Actions), so a CI reader loses nothing the serial loop showed.
# No `|| true` anywhere on the gate path: this is a fail-CLOSED correctness gate (CLAUDE.md
# §"Failure-Mode Invariants").
set -euo pipefail
shopt -s nullglob

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -gt 0 ]; then
  tests=("$@")
else
  repo="$(cd "$here/../.." && pwd)"
  cd "$repo"
  tests=(loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh)
fi
if [ "${#tests[@]}" -eq 0 ]; then
  echo "no self-tests found (loomwright/scripts/test-*.sh, loomwright/scripts/adapters/*/test-*.sh) — the suite matched nothing" >&2
  exit 1
fi

jobs="${SELF_TEST_JOBS:-}"
if [ -z "$jobs" ]; then
  jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi
case "$jobs" in ''|*[!0-9]*|0) echo "SELF_TEST_JOBS must be a positive integer, got '$jobs'" >&2; exit 1 ;; esac

out="$(mktemp -d "${TMPDIR:-/tmp}/self-tests.XXXXXX")"
trap 'rm -rf "$out"' EXIT

# One worker per test. It ALWAYS exits 0 so xargs keeps scheduling; the verdict is the per-test
# `<idx>.rc` file it writes LAST. A missing rc file therefore means the worker never finished,
# and is counted as a failure below — never as a pass.
worker='
idx="$1"; t="$2"
start=$(date +%s)
rc=0; bash "$t" > "$SELF_TEST_OUT/$idx.log" 2>&1 < /dev/null || rc=$?
printf "%s %s\n" "$rc" "$(( $(date +%s) - start ))" > "$SELF_TEST_OUT/$idx.rc.tmp"
mv "$SELF_TEST_OUT/$idx.rc.tmp" "$SELF_TEST_OUT/$idx.rc"
'
export SELF_TEST_OUT="$out"

# Tests that measure wall-clock time (calibrated runtime ratios, deliberate races, sleep-then-type
# PTY feeds) declare `# run-self-tests: serial` on a line of their own; they run one at a time
# AFTER the concurrent batch, on an otherwise idle machine — the conditions they were written for.
# Observed flaking under an oversubscribed concurrent run before being marked: test-build-floor.sh
# (x), test-write-agent-memory.sh (j5/X), test-harvest-conventions.sh (M1a).
par_idx=(); ser_idx=()
i=0
for t in "${tests[@]}"; do
  if grep -qx '# run-self-tests: serial' "$t" 2>/dev/null; then ser_idx+=("$i"); else par_idx+=("$i"); fi
  i=$((i + 1))
done

# schedule <jobs> <idx...> — feed (idx, path) pairs to xargs; records a scheduler failure in xargs_rc.
schedule() {
  local n="$1"; shift
  [ "$#" -gt 0 ] || return 0
  local k
  for k in "$@"; do printf '%s\0%s\0' "$k" "${tests[$k]}"; done \
    | xargs -0 -n 2 -P "$n" bash -c "$worker" worker || xargs_rc=$?
}

echo "running ${#tests[@]} self-tests: ${#par_idx[@]} concurrently ($jobs at a time), then ${#ser_idx[@]} serially"
wall_start=$(date +%s)
xargs_rc=0
schedule "$jobs" ${par_idx[@]+"${par_idx[@]}"}
schedule 1 ${ser_idx[@]+"${ser_idx[@]}"}
# xargs itself failing (e.g. a worker killed by a signal makes it stop scheduling) is recorded
# here and gated on below — AFTER the report, so the logs that exist still get printed.
wall=$(( $(date +%s) - wall_start ))

# Collect verdicts in suite order. Passing logs first (collapsed on GitHub), failures last so they
# are the final thing a reader sees.
gh_groups=0; [ "${GITHUB_ACTIONS:-}" = "true" ] && gh_groups=1
failed=(); timings=""
i=0
for t in "${tests[@]}"; do
  rcfile="$out/$i.rc"
  if [ -f "$rcfile" ]; then
    read -r rc secs < "$rcfile"
  else
    rc="no-result"; secs="?"
  fi
  timings="$timings$secs $t"$'\n'
  if [ "$rc" = "0" ]; then
    if [ "$gh_groups" -eq 1 ]; then
      echo "::group::PASS ${secs}s $t"; cat "$out/$i.log" 2>/dev/null; echo "::endgroup::"
    else
      echo "PASS ${secs}s $t"
    fi
  else
    failed+=("$i")
  fi
  i=$((i + 1))
done

echo
echo "slowest tests:"
printf '%s' "$timings" | sort -rn | sed -n '1,10s/^/  /p'

if [ "${#failed[@]}" -gt 0 ]; then
  for i in "${failed[@]}"; do
    t="${tests[$i]}"
    rc="no-result"; [ -f "$out/$i.rc" ] && read -r rc _ < "$out/$i.rc"
    echo
    echo "================ FAIL (exit $rc): $t ================"
    cat "$out/$i.log" 2>/dev/null || echo "(no output captured)"
  done
  echo
  echo "${#failed[@]} of ${#tests[@]} self-tests FAILED (wall ${wall}s):" >&2
  for i in "${failed[@]}"; do echo "  ${tests[$i]}" >&2; done
  exit 1
fi
if [ "$xargs_rc" -ne 0 ]; then
  echo "xargs exited $xargs_rc — the scheduler did not complete cleanly; treating the run as FAILED" >&2
  exit 1
fi
echo
echo "all ${#tests[@]} self-tests passed (wall ${wall}s, $jobs-way)"
