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
#   (L)  lock held by a live pid      → waits, then exit 1 after CI_LOCAL_LOCK_WAIT, nothing ran;
#        lock held by a dead pid      → taken over ("stale"), run proceeds, lock released after
#   (LS) --list                       → key + cache status, exactly the ci.yml gates (with args) and the
#                                       plain tests in order, no temp wrapper paths, nothing ran;
#                                       a changed tree lists "cache: miss"
#   (H)  --help                       → the whole header de-commented, no code; still correct when the
#                                       first code line after the header changes
#   (Z)  ci.yml names no gates        → exit 1 (no green on zero gates)
#   (A)  unknown argument             → exit 2
#   (W)  wiring: ci-local.sh's loomwright glob line is the one run-self-tests.sh uses, and the real
#        ci.yml runs this self-test
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SUT="$HERE/ci-local.sh"
[ -f "$SUT" ] || { echo "test-ci-local: $SUT not found" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ci-local-test.XXXXXX")"
sleeper=""
trap '[ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null; rm -rf "$tmp"' EXIT

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }

R="$tmp/repo"
export FIXTURE_LOG="$tmp/ran.log"

# build_fixture — a minimal repo shaped like this one.
build_fixture() {
  rm -rf "$R"; mkdir -p "$R/.github/workflows" "$R/scripts" "$R/loomwright/scripts"
  cp "$SUT" "$R/scripts/ci-local.sh"
  cp "$REPO_ROOT/loomwright/scripts/run-self-tests.sh" "$REPO_ROOT/loomwright/scripts/hermetic-test-env.sh" "$R/loomwright/scripts/"
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
      && git add -A && git commit -qm fixture && git update-ref refs/remotes/origin/main HEAD )
}

run() { : > "$FIXTURE_LOG"; out="$(cd "$R" && bash scripts/ci-local.sh "$@" 2>&1)"; rc=$?; }
ran() { grep -qx "$1" "$FIXTURE_LOG"; }
# has PAT — `grep -q` on a here-string, never a pipe (test-no-pipefail-grep-q.sh).
has() { grep -q "$1" <<<"$out"; }

build_fixture

# (P)
run
if [ "$rc" -eq 0 ] && ran "check-a --self-test" && ran "check-a plain" && ran vendor && ran extra && ran one \
   && has "stamped"; then ok "(P) green: every gate + test ran, stamped"
else no "(P) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi

# (C)
run
if [ "$rc" -eq 0 ] && has "PASS (cached)" && [ ! -s "$FIXTURE_LOG" ]; then ok "(C) unchanged tree: cached, nothing ran"
else no "(C) rc=$rc log=[$(tr '\n' ' ' < "$FIXTURE_LOG")] out=$out"; fi

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

# (L)
lockdir="$R/.git/loomwright-ci-local/lock"
sleep 30 & sleeper=$!
mkdir -p "$lockdir"; echo "$sleeper" > "$lockdir/pid"
CI_LOCAL_LOCK_WAIT=2 run --force
if [ "$rc" -eq 1 ] && has "giving up" && [ ! -s "$FIXTURE_LOG" ]; then ok "(L) live holder: waited, then exit 1, nothing ran"
else no "(L) live: rc=$rc out=$out"; fi
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; sleeper=""
run --force
if [ "$rc" -eq 0 ] && has "stale" && ran one && [ ! -d "$lockdir" ]; then ok "(L) dead holder: lock taken over, run passed, lock released"
else no "(L) dead: rc=$rc lock_left=$([ -d "$lockdir" ] && echo yes || echo no) out=$out"; fi

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
