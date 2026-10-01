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
#          SELF_TEST_TIMEOUT  per-test wall-clock limit in seconds (default 900). A test still
#          running at the limit is a FAILURE (exit 124 in its banner): its process tree and log
#          tail are printed to stderr THE MOMENT it times out (so a CI log names the hung test
#          even if the job is later killed), then the whole tree is killed. Before this, one test
#          that never exited held the step until GitHub's 6-hour default (15 CI runs, 2026-09-27
#          → 2026-10-01, each cancelled at ~361 min with no test named in the log).
#   marker: a test carrying the exact line `# run-self-tests: serial` runs ALONE, after the
#          concurrent batch — for tests that measure wall-clock time and need an idle machine
#   exit 0 = every test ran AND exited 0
#   exit 1 = FAIL CLOSED: any test exited non-zero or timed out, any test left no result (its worker died), or
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

# Egress-hermetic layer for every worker (second layer — each test ALSO sources the helper itself,
# enforced by scripts/check-test-hermetic.sh). Sourcing it here scrubs the egress env vars, sets
# LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 and PATH-prepends the recording notifier/curl/wget stubs, and
# every `bash "$t"` worker below inherits that exported state — so even a test that somehow skipped
# its own source line gets no egress env and no real notifier/curl/wget through this runner. (Not
# covered here or in the helper: the user-scope $HOME-rooted egress.json and `gh` — a test
# that exercises webhook/telemetry resolution sandboxes HOME itself; see the helper's SCOPE LIMIT.)
# FAIL CLOSED when the helper is missing OR sourced without producing a shim dir (it never exits
# itself, it only warns when mktemp fails twice): running the suite without the stubs is exactly
# what this layer exists to prevent.
if [ ! -f "$here/hermetic-test-env.sh" ]; then
  echo "run-self-tests: $here/hermetic-test-env.sh is missing — refusing to run the suite without the egress-hermetic layer" >&2
  exit 1
fi
# shellcheck source=hermetic-test-env.sh
. "$here/hermetic-test-env.sh"
if [ -z "${HERMETIC_SHIM_DIR:-}" ] || [ ! -d "$HERMETIC_SHIM_DIR" ]; then
  echo "run-self-tests: hermetic-test-env.sh left no shim dir (HERMETIC_SHIM_DIR='${HERMETIC_SHIM_DIR:-}') — refusing to run the suite without the recording notifier/curl/wget stubs" >&2
  exit 1
fi

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
limit="${SELF_TEST_TIMEOUT:-900}"
case "$limit" in ''|*[!0-9]*|0) echo "SELF_TEST_TIMEOUT must be a positive integer (seconds), got '$limit'" >&2; exit 1 ;; esac
export SELF_TEST_TIMEOUT="$limit"

out="$(mktemp -d "${TMPDIR:-/tmp}/self-tests.XXXXXX")"
trap 'rm -rf "$out"' EXIT

# One worker per test. It ALWAYS exits 0 so xargs keeps scheduling; the verdict is the per-test
# `<idx>.rc` file it writes LAST. A missing rc file therefore means the worker never finished,
# and is counted as a failure below — never as a pass.
#
# The worker is a file (not a `bash -c` string) so the watchdog's awk program can be quoted
# normally. Watchdog: no `timeout(1)` (absent on stock macOS) — the test runs in the background
# and the worker polls it every 0.5 s against SELF_TEST_TIMEOUT. On expiry it collects the test's
# descendants from `ps -A -o pid= -o ppid=` (same flags on BSD and procps), prints them with their
# command lines plus the log tail to stderr immediately, appends the same to the test's log, then
# TERMs and (2 s later) KILLs the tree. rc 124 = timed out, matching timeout(1).
cat > "$out/worker.sh" <<'WORKER'
idx="$1"; t="$2"; limit="$SELF_TEST_TIMEOUT"
log="$SELF_TEST_OUT/$idx.log"
descendants() {
  local c
  for c in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1 }'); do
    echo "$c"; descendants "$c"
  done
}
start=$(date +%s)
bash "$t" > "$log" 2>&1 < /dev/null &
pid=$!
timed_out=0
while kill -0 "$pid" 2>/dev/null; do
  if [ $(( $(date +%s) - start )) -ge "$limit" ]; then timed_out=1; break; fi
  sleep 0.5
done
if [ "$timed_out" -eq 1 ]; then
  tree="$pid $(descendants "$pid" | tr '\n' ' ')"
  {
    echo "run-self-tests: TIMEOUT after ${limit}s: $t — still running; process tree:"
    ps -o pid= -o ppid= -o etime= -o command= -p "$(echo $tree | tr ' ' ',')" 2>/dev/null | sed 's/^/    /'
    echo "  last 20 lines of its output:"
    tail -n 20 "$log" 2>/dev/null | sed 's/^/    /'
  } > "$SELF_TEST_OUT/$idx.hang" 2>&1
  cat "$SELF_TEST_OUT/$idx.hang" >&2
  { echo; echo "================ killed by run-self-tests watchdog ================"; cat "$SELF_TEST_OUT/$idx.hang"; } >> "$log"
  kill -TERM $tree 2>/dev/null
  sleep 2
  kill -KILL $tree 2>/dev/null
  wait "$pid" 2>/dev/null
  rc=124
else
  rc=0; wait "$pid" || rc=$?
fi
printf "%s %s\n" "$rc" "$(( $(date +%s) - start ))" > "$SELF_TEST_OUT/$idx.rc.tmp"
mv "$SELF_TEST_OUT/$idx.rc.tmp" "$SELF_TEST_OUT/$idx.rc"
WORKER
export SELF_TEST_OUT="$out"

# Tests that measure wall-clock time (calibrated runtime ratios, deliberate races, sleep-then-type
# PTY feeds) declare `# run-self-tests: serial` on a line of their own; they run one at a time
# AFTER the concurrent batch, on an otherwise idle machine — the conditions they were written for.
# Observed flaking under an oversubscribed concurrent run before being marked: test-build-floor.sh
# (x), test-harvest-conventions.sh (M1a). Serial is a mitigation, not a fix: test-write-agent-memory.sh
# (j5/X) was marked too and STILL flaked under outside load, then was made deterministic (barriers
# instead of sleeps) and unmarked — prefer that repair whenever the ordering can be pinned.
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
    | xargs -0 -n 2 -P "$n" bash "$out/worker.sh" || xargs_rc=$?
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
    if [ "$rc" = "124" ]; then
      echo "================ FAIL (exit 124 — TIMEOUT after ${limit}s): $t ================"
    else
      echo "================ FAIL (exit $rc): $t ================"
    fi
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
