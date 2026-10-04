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
#   (LS) --list                       → key + cache status, exactly the ci.yml gates (with args) and the
#                                       plain tests in order, no temp wrapper paths, nothing ran;
#                                       a changed tree lists "cache: miss"
#   (H)  --help                       → the whole header de-commented, no code; still correct when the
#                                       first code line after the header changes
#   (Z)  ci.yml names no gates        → exit 1 (no green on zero gates)
#   (A)  unknown argument             → exit 2
#   (W)  wiring: ci-local.sh's loomwright glob line is the one run-self-tests.sh uses, and the real
#        ci.yml runs this self-test
# Slot state lives under a sandboxed XDG_STATE_HOME: an inner fixture run must never queue on the
# real shared pool that an outer ci-local.sh run is holding (that would deadlock it).
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
unset SELF_TEST_JOBS LOOMWRIGHT_CI_SLOTS LOOMWRIGHT_CI_CPUS LOOMWRIGHT_CI_SLOT_PRINT_EVERY CI_LOCAL_LOCK_WAIT
export LOOMWRIGHT_CI_SLOT_POLL=0.2
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
     "$REPO_ROOT/loomwright/scripts/ci-slot.sh" "$R/loomwright/scripts/"
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

build_fixture
state="$(slot dir)"
case "$state" in "$tmp/state/"*) ok "(S) slot state is inside the sandboxed XDG_STATE_HOME" ;;
  *) no "(S) slot state escaped the sandbox: $state"; exit 1 ;; esac

# (P)
run
if [ "$rc" -eq 0 ] && ran "check-a --self-test" && ran "check-a plain" && ran vendor && ran extra && ran one \
   && has "stamped"; then ok "(P) green: every gate + test ran, stamped"
else no "(P) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi

# (C)
run
if [ "$rc" -eq 0 ] && has "PASS (cached)" && [ ! -s "$FIXTURE_LOG" ]; then ok "(C) unchanged tree: cached, nothing ran"
else no "(C) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi

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
run
if [ "$rc" -eq 0 ] && ran one && ! has "PASS (cached)"; then ok "(M) next run re-ran"
else no "(M) next run: rc=$rc out=$out"; fi

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
run --list
if [ "$rc" -eq 0 ] && has "^key: " && has "^cache: PASS stamped" && [ ! -s "$FIXTURE_LOG" ]; then ok "(LS) --list: key + cached status, nothing ran"
else no "(LS) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi
want_gates=$'gate: scripts/check-a.sh --self-test\ngate: scripts/check-a.sh\ngate: scripts/check-vendor-coupling.sh'
want_tests=$'test: scripts/test-extra.sh\ntest: loomwright/scripts/test-one.sh'
if [ "$(grep '^gate: ' <<<"$out")" = "$want_gates" ] && [ "$(grep '^test: ' <<<"$out")" = "$want_tests" ]; then
  ok "(LS) --list: exactly the ci.yml gates (with arguments) and the plain tests, in order"
else no "(LS) plan lines: $out"; fi
if has "/gates/"; then no "(LS) --list leaked a temp gate-wrapper path: $out"; else ok "(LS) --list hides the temp gate wrappers"; fi
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
rm -f "$R/q-probe.txt"

# (H)
run --help
if [ "$rc" -eq 0 ] && has "^ci-local.sh — " && has "^usage: ci-local.sh" && has "^Self-test: scripts/test-ci-local.sh" \
   && ! has "^#" && ! has "set -euo"; then ok "(H) --help: the whole header, de-commented, no code"
else no "(H) rc=$rc out=$out"; fi
# The header ends at the first non-comment line, whatever that line is — not at a literal `set -euo`.
sed 's/^set -euo pipefail$/set -eu -o pipefail/' "$R/scripts/ci-local.sh" > "$R/scripts/ci-local-variant.sh"
out="$(cd "$R" && bash scripts/ci-local-variant.sh --help 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && has "^Self-test: scripts/test-ci-local.sh" && ! has "set -eu" && ! has "shopt"; then ok "(H) --help survives a changed first code line"
else no "(H) variant: rc=$rc out=$out"; fi
rm -f "$R/scripts/ci-local-variant.sh"

# (Z)
printf 'jobs:\n  ci:\n    steps:\n      - run: echo nothing\n' > "$R/.github/workflows/ci.yml"
run
if [ "$rc" -eq 1 ] && has "zero gates"; then ok "(Z) no gates in ci.yml: exit 1"
else no "(Z) rc=$rc out=$out"; fi

# (A)
run --bogus
if [ "$rc" -eq 2 ]; then ok "(A) unknown argument: exit 2"; else no "(A) rc=$rc"; fi

# (W)
glob='loomwright/scripts/test-\*.sh loomwright/scripts/adapters/\*/test-\*.sh'
if grep -q "($glob)" "$SUT" && grep -q "($glob)" "$REPO_ROOT/loomwright/scripts/run-self-tests.sh"; then ok "(W) suite glob matches run-self-tests.sh"
else no "(W) ci-local.sh's loomwright glob drifted from run-self-tests.sh's"; fi
if grep -q 'bash scripts/test-ci-local.sh' "$REPO_ROOT/.github/workflows/ci.yml"; then ok "(W) ci.yml runs this self-test"
else no "(W) .github/workflows/ci.yml does not run scripts/test-ci-local.sh"; fi

echo
echo "test-ci-local: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
