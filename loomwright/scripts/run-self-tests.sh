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
#          run-self-tests.sh --select-marked early|serial <test.sh> ...
#          (prints, in input order, the tests carrying that marker, and runs nothing — the ONE marker
#          parser: scripts/ci-local.sh derives its early phase from it instead of re-implementing it)
#          run-self-tests.sh [--shard K/N] [--list]
#          --shard K/N (1 <= K <= N): run only shard K of the canonical no-argument suite. The split is
#          a deterministic greedy longest-first partition by the weights in
#          fixtures/self-test-weights.tsv (a test absent from it gets weight 20 — never dropped); the
#          union of shards 1..N is exactly the suite, with no duplicates (test-run-self-tests.sh).
#          --list: print the selected tests (the whole suite, or one shard), one per line, run nothing.
#          Either flag with explicit test arguments, or a malformed K/N, is a usage error (exit 1).
#          A shard keeps every per-test rule below (serial tail, watchdog, admission, hermetic layer).
#   env:   SELF_TEST_MANIFEST  when set, a result manifest is written there: one `<rc>\t<secs>\t<test>`
#          line per selected test (`no-result` for a worker that died) — CI's `ci` job aggregates them
#          no arguments = the canonical suite: loomwright/scripts/test-*.sh plus
#          loomwright/scripts/adapters/*/test-*.sh (adapter self-tests live one directory deeper
#          than the flat glob reaches — without the second glob they are committed tests nothing
#          runs). Future tests are auto-included — anti-drift.
#   env:   SELF_TEST_JOBS  concurrency (default: the job share of the CI slot it is admitted with)
#          SELF_TEST_TIMEOUT  per-test wall-clock limit in seconds (default 900). A test still
#          running at the limit is a FAILURE (exit 124 in its banner): its process tree and log
#          tail are printed to stderr THE MOMENT it times out (so a CI log names the hung test
#          even if the job is later killed), then the whole tree is killed. Before this, one test
#          that never exited held the step until GitHub's 6-hour default (15 CI runs, 2026-09-27
#          → 2026-10-01, each cancelled at ~361 min with no test named in the log).
#          SELF_TEST_SLOT_WAIT  seconds to wait for machine admission (a ci-slot.sh slot; see below)
#   marker: a test carrying the exact line `# run-self-tests: serial` runs ALONE, after the
#          concurrent batch — for tests that measure wall-clock time and need an idle machine.
#          A test carrying the exact line `# run-self-tests: early` is a cheap, deterministic test
#          that scripts/ci-local.sh runs in its EARLY phase (before the pool, so a red one fails the
#          run in seconds). In this runner's own run the `early` marker changes NOTHING: the test
#          stays in the concurrent batch. Both markers are matched with the same `grep -qx`
#          exact-line rule; a test carrying BOTH is a usage error (exit 1, named) — the two phases
#          conflict.
#   exit 0 = every test ran AND exited 0
#   exit 1 = FAIL CLOSED: any test exited non-zero or timed out, any test left no result (its worker died), or
#            the glob matched nothing (a moved/renamed scripts dir fails LOUDLY, never green), or no admission
#
# Unlike the serial `set -e` loop, a red test does not hide the ones after it: every test runs,
# then each failure's full log is printed at the end. A red test is ALSO streamed the moment it
# finishes — one `run-self-tests: FAIL (exit <rc>, <secs>s): <test>` line, as a TIMEOUT already is —
# so a reader of a running log (or of `ci-local.sh --wait`) sees it within seconds. Passing logs are printed too (collapsed in
# `::group::` blocks under GitHub Actions), so a CI reader loses nothing the serial loop showed.
# No `|| true` anywhere on the gate path: this is a fail-CLOSED correctness gate (CLAUDE.md
# §"Failure-Mode Invariants").
set -euo pipefail
shopt -s nullglob

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# has_marker NAME TEST — the one marker parser: an exact `# run-self-tests: NAME` line (grep -qx).
has_marker() { grep -qx "# run-self-tests: $1" "$2" 2>/dev/null; }
# marker_conflict TEST — a test marked both `early` and `serial` is a usage error (the phases conflict).
marker_conflict() {
  if has_marker early "$1" && has_marker serial "$1"; then
    echo "run-self-tests: $1 carries both \`# run-self-tests: early\` and \`# run-self-tests: serial\` — the early phase and the serial tail conflict; keep one" >&2
    return 0
  fi
  return 1
}

# --select-marked runs nothing: no hermetic layer, no admission, no slot.
if [ "${1:-}" = "--select-marked" ]; then
  case "${2:-}" in
    early|serial) ;;
    *) echo "usage: run-self-tests.sh --select-marked early|serial <test.sh> ... (got '${2:-}')" >&2; exit 1 ;;
  esac
  sel_marker="$2"; shift 2
  for t in "$@"; do
    if marker_conflict "$t"; then exit 1; fi
    if has_marker "$sel_marker" "$t"; then printf '%s\n' "$t"; fi
  done
  exit 0
fi

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

shard=""; list=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --shard) [ "$#" -ge 2 ] || { echo "run-self-tests: --shard wants K/N" >&2; exit 1; }; shard="$2"; shift 2 ;;
    --list) list=1; shift ;;
    *) break ;;
  esac
done
if [ -n "$shard" ] || [ "$list" -eq 1 ]; then
  if [ "$#" -gt 0 ]; then echo "run-self-tests: --shard/--list select from the canonical suite — they take no test arguments" >&2; exit 1; fi
fi
shard_k=0; shard_n=0
if [ -n "$shard" ]; then
  case "$shard" in
    [1-9]*/[1-9]*) shard_k="${shard%%/*}"; shard_n="${shard#*/}" ;;
  esac
  case "$shard_k:$shard_n" in
    *[!0-9:]*|0:*|*:0) echo "run-self-tests: --shard wants K/N with 1 <= K <= N, got '$shard'" >&2; exit 1 ;;
  esac
  if [ "$shard_k" -gt "$shard_n" ]; then echo "run-self-tests: --shard wants K/N with 1 <= K <= N, got '$shard'" >&2; exit 1; fi
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

# --shard: greedy longest-first by weight (ties: path order), each test to the least-loaded shard
# (ties: the lowest shard). Deterministic for a given file set + weights file; the kept tests stay in
# suite order.
if [ "$shard_n" -gt 0 ]; then
  weights="$here/fixtures/self-test-weights.tsv"
  sel="$(printf '%s\n' "${tests[@]}" | awk -F'\t' -v k="$shard_k" -v n="$shard_n" -v wf="$weights" '
    BEGIN { while ((getline l < wf) > 0) { if (l ~ /^#/ || l == "") continue; split(l, a, "\t"); w[a[2]] = a[1] + 0 } }
    { t[NR] = $0; wt[NR] = ($0 in w) ? w[$0] : 20 }
    END {
      m = NR
      for (i = 1; i <= m; i++) o[i] = i
      for (i = 2; i <= m; i++) { x = o[i]; j = i - 1
        while (j >= 1 && (wt[o[j]] < wt[x] || (wt[o[j]] == wt[x] && t[o[j]] > t[x]))) { o[j + 1] = o[j]; j-- }
        o[j + 1] = x }
      for (s = 1; s <= n; s++) load[s] = 0
      for (i = 1; i <= m; i++) { b = 1; for (s = 2; s <= n; s++) if (load[s] < load[b]) b = s
        own[o[i]] = b; load[b] += wt[o[i]] }
      for (i = 1; i <= m; i++) if (own[i] == k) print t[i]
    }')"
  tests=()
  while IFS= read -r t; do [ -n "$t" ] && tests+=("$t"); done <<<"$sel"
fi
if [ "$list" -eq 1 ]; then
  for t in ${tests[@]+"${tests[@]}"}; do printf '%s\n' "$t"; done
  exit 0
fi
if [ "$shard_n" -gt 0 ] && [ "${#tests[@]}" -eq 0 ]; then
  echo "run-self-tests: shard $shard selected no tests (more shards than tests) — nothing to run"
  [ -z "${SELF_TEST_MANIFEST:-}" ] || : > "$SELF_TEST_MANIFEST"
  exit 0
fi

# Unset/empty SELF_TEST_JOBS = the admitted slot's job share (set after admission, below).
jobs="${SELF_TEST_JOBS:-}"
if [ -n "$jobs" ]; then
  case "$jobs" in *[!0-9]*|0) echo "SELF_TEST_JOBS must be a positive integer, got '$jobs'" >&2; exit 1 ;; esac
fi
limit="${SELF_TEST_TIMEOUT:-900}"
case "$limit" in ''|*[!0-9]*|0) echo "SELF_TEST_TIMEOUT must be a positive integer (seconds), got '$limit'" >&2; exit 1 ;; esac
export SELF_TEST_TIMEOUT="$limit"
slot_wait="${SELF_TEST_SLOT_WAIT:-1800}"
case "$slot_wait" in ''|*[!0-9]*) echo "SELF_TEST_SLOT_WAIT must be a non-negative integer (seconds), got '$slot_wait'" >&2; exit 1 ;; esac
slot_helper="$here/ci-slot.sh"
if [ ! -f "$slot_helper" ]; then
  echo "run-self-tests: $slot_helper is missing — refusing to run the suite without machine admission" >&2
  exit 1
fi

out="$(mktemp -d "${TMPDIR:-/tmp}/self-tests.XXXXXX")"
have_slot=0; acq_pid=""
cleanup() {
  # A queued acquire still running (INT/TERM arrived mid-wait): stop and reap it BEFORE the release,
  # so it cannot claim a slot after that release. Its own TERM trap drops its ticket; the release
  # then frees anything recorded under $$. A failed release only warns: the run's verdict stands,
  # and a slot whose holder pid is gone is taken over by the next caller anyway.
  if [ -n "$acq_pid" ]; then
    kill -TERM "$acq_pid" 2>/dev/null || :
    wait "$acq_pid" 2>/dev/null || :
  fi
  if [ "$have_slot" -eq 1 ] && ! ( cd "$here" && bash "$slot_helper" release --pid "$$" ); then
    echo "run-self-tests: warning: releasing the CI slot failed — the next caller takes it over once pid $$ is gone" >&2
  fi
  rm -rf "$out"
}
trap cleanup EXIT
# INT/TERM become a normal exit so the EXIT trap releases the slot.
trap 'exit 130' INT
trap 'exit 143' TERM

# --- machine admission: before scheduling anything the runner takes a slot from ci-slot.sh (beside
# it), as scripts/ci-local.sh does, recorded under the runner's own pid and released by the EXIT trap
# — so a bare run (a lane worker, an owner's terminal, CI) waits behind the repo's slot pool and the
# machine gate (load, committed work) instead of piling onto a loaded machine. Under a live holder
# (ci-local.sh running this runner as its pool) the call FOLDS into that holder at once: no second
# slot, no second machine record (ci-slot.sh NESTED). No slot within SELF_TEST_SLOT_WAIT (default
# 1800 s), a missing ci-slot.sh, or a malformed answer = exit 1. Not covered: a single test-*.sh run
# directly never asks the gate (ci-slot.sh honest limit 9). stderr: the helper's waiting lines;
# stdout: ONLY `slot=<k> jobs=<j>`. It runs from this script's own checkout, so it is keyed to this
# repo wherever the caller's cwd is. Backgrounded and awaited with the `wait` builtin, never `$(...)`: bash defers a
# trapped INT/TERM until a foreground child exits, while `wait` returns at once and lets the trap run.
# have_slot is set BEFORE acquiring: a run interrupted mid-wait still has its queued ticket dropped.
have_slot=1
( cd "$here" && exec bash "$slot_helper" acquire self-tests --pid "$$" --wait "$slot_wait" ) > "$out/slot" &   # ADMISSION
acq_pid=$!
acq_rc=0
wait "$acq_pid" || acq_rc=$?
acq_pid=""
if [ "$acq_rc" -ne 0 ]; then
  echo "run-self-tests: no CI slot after ${slot_wait}s (machine admission) — giving up (FAIL). Holders: bash $slot_helper status" >&2
  exit 1
fi
got="$(cat "$out/slot")"
slot="${got#slot=}"; slot="${slot%% *}"; slot_jobs="${got##* jobs=}"
case "$got" in slot=*" jobs="*) ;; *) slot="" ;; esac
case "$slot:$slot_jobs" in
  :*|*[!0-9:]*|*:) echo "run-self-tests: unexpected answer from $slot_helper: '$got'" >&2; exit 1 ;;
esac
[ "$slot_jobs" -gt 0 ] || { echo "run-self-tests: unexpected answer from $slot_helper: '$got'" >&2; exit 1; }
[ -n "$jobs" ] || jobs="$slot_jobs"

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
  # One pid per line, then joined with commas by paste: no reliance on unquoted word-splitting
  # to trim a trailing separator (GNU `ps -p 1,` errors "improper list").
  tree_lines="$( { echo "$pid"; descendants "$pid"; } | grep -E '^[0-9]+$')"
  tree_csv="$(printf '%s\n' "$tree_lines" | paste -sd, -)"
  {
    echo "run-self-tests: TIMEOUT after ${limit}s: $t — still running; process tree:"
    ps -o pid= -o ppid= -o etime= -o command= -p "$tree_csv" 2>/dev/null | sed 's/^/    /'
    echo "  last 20 lines of its output:"
    tail -n 20 "$log" 2>/dev/null | sed 's/^/    /'
  } > "$SELF_TEST_OUT/$idx.hang" 2>&1
  cat "$SELF_TEST_OUT/$idx.hang" >&2
  { echo; echo "================ killed by run-self-tests watchdog ================"; cat "$SELF_TEST_OUT/$idx.hang"; } >> "$log"
  for k in $tree_lines; do kill -TERM "$k" 2>/dev/null; done
  sleep 2
  for k in $tree_lines; do kill -KILL "$k" 2>/dev/null; done
  wait "$pid" 2>/dev/null
  rc=124
else
  rc=0; wait "$pid" || rc=$?
fi
secs=$(( $(date +%s) - start ))
printf "%s %s\n" "$rc" "$secs" > "$SELF_TEST_OUT/$idx.rc.tmp"
mv "$SELF_TEST_OUT/$idx.rc.tmp" "$SELF_TEST_OUT/$idx.rc"
# Streamed at once (the end-of-run banner + full log still follow): a red test is visible in seconds.
if [ "$rc" -ne 0 ]; then echo "run-self-tests: FAIL (exit $rc, ${secs}s): $t"; fi
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
  if marker_conflict "$t"; then exit 1; fi
  # `early` is inert here (ci-local.sh's phase, not this runner's): an early test stays concurrent.
  if has_marker serial "$t"; then ser_idx+=("$i"); else par_idx+=("$i"); fi
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

echo "running ${#tests[@]} self-tests: ${#par_idx[@]} concurrently ($jobs at a time), then ${#ser_idx[@]} serially — CI slot $slot"
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
  [ -z "${SELF_TEST_MANIFEST:-}" ] || printf '%s\t%s\t%s\n' "$rc" "$secs" "$t" >> "$out/manifest"
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

# The manifest is copied out before any exit below, so a red shard still reports every test.
if [ -n "${SELF_TEST_MANIFEST:-}" ]; then cp "$out/manifest" "$SELF_TEST_MANIFEST" 2>/dev/null || : > "$SELF_TEST_MANIFEST"; fi
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
