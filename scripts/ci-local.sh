#!/usr/bin/env bash
# ci-local.sh — the ONE pre-push command: every gate the `ci` CI job runs, in one concurrent pool,
# safe to call from any number of sessions, and free to repeat on an unchanged tree.
#
# Why it exists: sessions kept hand-rolling `for t in …/test-*.sh; do bash "$t"; done` loops before
# each push — serial (1 of N cores), a shared fixed /tmp log, root gates forgotten (PR #217/#218),
# and the same unchanged tree re-tested several times a session while other sessions did the same,
# all contending for the same CPUs. This script fixes each of those by construction:
#
#   SAME GATES AS CI   every `bash scripts/<gate>.sh [--self-test]` line in .github/workflows/ci.yml
#                      (derived, not hand-listed — a gate added to ci.yml is picked up automatically)
#                      + every root scripts/test-*.sh + the loomwright self-test suite. All of them
#                      go into ONE pool run by loomwright/scripts/run-self-tests.sh (concurrency,
#                      per-test watchdog, `# run-self-tests: serial` marker, egress-hermetic layer,
#                      every failure's full log printed, fail-closed on a missing result).
#   UNTRACKED FILES    check-vendor-coupling.sh scans `git ls-files`, so a NEW file was invisible
#                      to it until staged (PR #294). Here it runs against a throwaway index holding
#                      the whole working tree (`git add -A` into a temp GIT_INDEX_FILE — your real
#                      index and staging area are never touched), so local == what CI will see
#                      once you commit everything.
#   PASS CACHE         a full pass stamps a content key: the working tree's git tree hash (tracked
#                      + untracked, .gitignore'd files excluded) + origin/main's sha (check-doc-
#                      currency compares against the merge-base) + OS. The same key later — in
#                      this session, another session, or another worktree of this repo — returns
#                      instantly. Only PASSES are cached; a failure always re-runs. Stamps live in
#                      `<ci-slot.sh dir>/pass/` — the repo-keyed state dir every checkout of this
#                      repo shares (primary, linked worktrees, lane clones), so a tree that passed
#                      in any checkout is cached for all.
#   SHARED CI SLOTS    full runs take one of N machine-wide slots from loomwright/scripts/ci-slot.sh
#                      (default N = max(1, floor(CPUs / 6)); LOOMWRIGHT_CI_SLOTS overrides), keyed
#                      by the repo's normalised `origin` URL — the git-common-dir only as the
#                      no-origin fallback. A run with N starts only while fewer than N suites run
#                      across every checkout; the rest wait in ticket order and print their position.
#                      Each run gets SELF_TEST_JOBS = max(2, floor(CPUs / N)) unless SELF_TEST_JOBS is
#                      set (an explicit value wins). LOOMWRIGHT_CI_SLOTS=1 makes this run wait until no
#                      other suite runs, then use every CPU; strict one-at-a-time across sessions needs
#                      the same value in every session (a larger-N session may still start beside it,
#                      and a smaller-N waiter can be passed while the pool is at its cap — ci-slot.sh
#                      CLAIM BY COUNT). A waiter re-checks the cache after it gets a slot, so
#                      if a holder just verified the same tree it returns at once. A slot whose
#                      holder pid is dead is taken over. Sharing assumes every checkout's `origin`
#                      is the same remote URL; a clone whose `origin` is a local path does not share.
#   TREE MOVED         the key is recomputed after the run; if the tree changed mid-run (a
#                      concurrent writer on this checkout), the verdict is reported but NOT cached.
#
# usage: ci-local.sh [--force] [--list]
#   --force   ignore the pass cache and run everything
#   --list    print the planned gate/test list and the content key, run nothing
# env:   SELF_TEST_JOBS / SELF_TEST_TIMEOUT   passed through to run-self-tests.sh
#        CI_LOCAL_LOCK_WAIT   seconds to wait for a CI slot before failing (default 1800)
#        LOOMWRIGHT_CI_SLOTS  number of shared slots (see SHARED CI SLOTS; never raise it to "go faster")
# exit:  0 = every gate passed (fresh or cached) · 1 = a gate failed / fail-closed condition · 2 = usage
#
# Honest limits: (1) .gitignore'd files are outside the key — a test that reads one is not
# re-run when only it changes (none should; tests build their fixtures in mktemp dirs).
# (2) NOT run here: ci.yml's sdk-spike step (npm ci + build + node suites) — CI still runs it.
# (3) This is macOS-green, not CI-green: the BSD/GNU userland differences in CLAUDE.md still apply.
# Self-test: scripts/test-ci-local.sh. Portability: bash 3.2 safe, no GNU-only flags.
set -euo pipefail
shopt -s nullglob

force=0; list=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --list)  list=1; shift ;;
    # --help = the header comment block: every line after the shebang up to the first line that is
    # not a comment. Anchored on comment-ness, not on whatever code follows the header.
    -h|--help) awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "ci-local: unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
runner="loomwright/scripts/run-self-tests.sh"
[ -f "$runner" ] || { echo "ci-local: $runner is missing — refusing to run" >&2; exit 1; }
[ -f .github/workflows/ci.yml ] || { echo "ci-local: .github/workflows/ci.yml is missing — cannot derive the CI gates" >&2; exit 1; }

slot_helper="loomwright/scripts/ci-slot.sh"
[ -f "$slot_helper" ] || { echo "ci-local: $slot_helper is missing — refusing to run" >&2; exit 1; }
lock_wait="${CI_LOCAL_LOCK_WAIT:-1800}"
case "$lock_wait" in ''|*[!0-9]*) echo "ci-local: CI_LOCAL_LOCK_WAIT must be a non-negative integer, got '$lock_wait'" >&2; exit 2 ;; esac
# The repo-keyed shared dir comes from the helper (never re-derived here): the PASS-cache check
# and --list need it before any slot is taken.
state="$(bash "$slot_helper" dir)" && [ -n "$state" ] \
  || { echo "ci-local: $slot_helper dir failed — cannot locate the shared state dir" >&2; exit 1; }
mkdir -p "$state/pass"

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/ci-local.XXXXXX")"
have_lock=0
acq_pid=""
cleanup() {
  # A queued acquire still running (INT/TERM arrived mid-wait): stop it and reap it BEFORE the
  # release below, so it can neither claim a slot after that release nor write into $tmpd after the
  # rm. Its own TERM trap removes its ticket; the release then frees anything recorded under $$.
  if [ -n "$acq_pid" ]; then kill -TERM "$acq_pid" 2>/dev/null || true; wait "$acq_pid" 2>/dev/null || true; fi
  if [ "$have_lock" -eq 1 ]; then bash "$slot_helper" release --pid "$$" || true; fi
  rm -rf "$tmpd"
}
trap cleanup EXIT
# Turn INT/TERM into a normal exit so the EXIT trap releases the slot (a SIGKILLed holder leaves a
# stale slot instead, which the next run takes over once that pid is gone).
trap 'exit 130' INT
trap 'exit 143' TERM

# content_key — writes the whole working tree (tracked + untracked, ignores honoured) into the
# throwaway index $tmpd/index and prints "<tree>-<origin/main sha>-<OS>". Seeding from the real
# index only reuses its stat cache (speed); the real index is never written.
content_key() {
  local real_idx
  real_idx="$(git rev-parse --git-path index)"
  rm -f "$tmpd/index"
  if [ -f "$real_idx" ]; then cp "$real_idx" "$tmpd/index"; fi
  GIT_INDEX_FILE="$tmpd/index" git add -A >/dev/null 2>&1 \
    || { echo "ci-local: could not snapshot the working tree into a temp index" >&2; return 1; }
  local tree base
  tree="$(GIT_INDEX_FILE="$tmpd/index" git write-tree)" || return 1
  base="$(git rev-parse -q --verify origin/main 2>/dev/null || echo no-origin-main)"
  printf '%s-%s-%s\n' "$tree" "$base" "$(uname -s)"
}

key="$(content_key)"
stamp="$state/pass/$key"

# --- plan: ci.yml gates (as wrappers, so arguments survive the runner's `bash "$t"`), root tests
# ci.yml does not already name, then the loomwright suite (the same two globs run-self-tests.sh
# uses with no arguments — test-ci-local.sh pins that they match). ---------------------------------
gates=()
while IFS= read -r g; do gates+=("$g"); done < <(
  grep -oE 'bash scripts/[A-Za-z0-9_.-]+\.sh( --self-test)?' .github/workflows/ci.yml \
    | sed 's/^bash //' | awk '!seen[$0]++')
if [ "${#gates[@]}" -eq 0 ]; then
  echo "ci-local: found no \`bash scripts/<gate>.sh\` lines in .github/workflows/ci.yml — refusing to report green on zero gates" >&2
  exit 1
fi

mkdir -p "$tmpd/gates"
plan=(); listed=" "; n=0
for g in "${gates[@]}"; do
  script="${g%% *}"
  [ -f "$script" ] || { echo "ci-local: ci.yml runs $script but it does not exist" >&2; exit 1; }
  listed="$listed$script "
  n=$((n + 1))
  name="$(basename "$script" .sh)"; case "$g" in *--self-test) name="$name--self-test" ;; esac
  w="$tmpd/gates/$(printf '%02d' "$n")-$name.sh"
  {
    printf 'cd %q || exit 1\n' "$repo"
    if [ "$(basename "$script")" = "check-vendor-coupling.sh" ]; then
      # see UNTRACKED FILES in the header
      printf 'GIT_INDEX_FILE=%q exec bash %s\n' "$tmpd/index" "$g"
    else
      printf 'exec bash %s\n' "$g"
    fi
  } > "$w"
  plan+=("$w")
done
for t in scripts/test-*.sh; do
  case "$listed" in *" $t "*) ;; *) plan+=("$t") ;; esac
done
suite=(loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh)
if [ "${#suite[@]}" -eq 0 ]; then
  echo "ci-local: the loomwright self-test globs matched nothing — refusing to report green" >&2
  exit 1
fi
plan+=("${suite[@]}")

if [ "$list" -eq 1 ]; then
  echo "key: $key"
  [ -f "$stamp" ] && echo "cache: PASS stamped $(cat "$stamp")" || echo "cache: miss"
  for g in "${gates[@]}"; do echo "gate: $g"; done
  for p in "${plan[@]}"; do case "$p" in "$tmpd"/*) ;; *) echo "test: $p" ;; esac; done
  exit 0
fi

cached_exit() {
  echo "ci-local: PASS (cached) — this exact tree already passed every gate at $(cat "$stamp")"
  echo "ci-local: key $key  (use --force to re-run anyway)"
  exit 0
}
if [ "$force" -eq 0 ] && [ -f "$stamp" ]; then cached_exit; fi

# --- shared CI slot (the helper prints progress on stderr, only `slot=<k> jobs=<j>` on stdout) -------
# have_lock is set BEFORE acquiring: a run interrupted mid-wait still has its queued ticket released.
# The acquire runs in the background and is awaited with the `wait` builtin, never inside `$(...)`:
# bash defers a trapped INT/TERM until a foreground child exits, so a `$(...)` acquire would ignore
# them for up to CI_LOCAL_LOCK_WAIT seconds, while `wait` returns at once and lets the trap run.
have_lock=1
bash "$slot_helper" acquire ci-local --pid "$$" --wait "$lock_wait" > "$tmpd/slot" &
acq_pid=$!
acq_rc=0
wait "$acq_pid" || acq_rc=$?
acq_pid=""
if [ "$acq_rc" -ne 0 ]; then
  echo "ci-local: no CI slot after ${lock_wait}s — giving up (FAIL). Holders: bash $slot_helper status" >&2
  exit 1
fi
got="$(cat "$tmpd/slot")"
slot="${got#slot=}"; slot="${slot%% *}"; slot_jobs="${got##*jobs=}"
case "$slot_jobs" in ''|*[!0-9]*) echo "ci-local: unexpected answer from $slot_helper: '$got'" >&2; exit 1 ;; esac
if [ -n "${SELF_TEST_JOBS:-}" ]; then
  echo "ci-local: CI slot $slot (SELF_TEST_JOBS=$SELF_TEST_JOBS set by the caller; slot share would be $slot_jobs)"
else
  export SELF_TEST_JOBS="$slot_jobs"
  echo "ci-local: CI slot $slot, $slot_jobs jobs"
fi
# The holder we waited on may have just verified this same tree.
if [ "$force" -eq 0 ] && [ -f "$stamp" ]; then cached_exit; fi

# --- run -------------------------------------------------------------------------------------------
echo "ci-local: ${#gates[@]} ci.yml gates + $(( ${#plan[@]} - ${#gates[@]} )) self-tests, one pool (key ${key%%-*})"
start=$(date +%s)
rc=0
bash "$runner" "${plan[@]}" || rc=$?
wall=$(( $(date +%s) - start ))

echo
echo "ci-local: not run locally — ci.yml's sdk-spike step (npm build + node suites); CI still runs it."
if [ "$rc" -ne 0 ]; then
  # A tree that just failed must not keep an older PASS stamp (e.g. a --force re-run exposing a
  # flaky or environment-dependent gate): the cache only ever vouches for the latest verdict.
  rm -f "$stamp"
  echo "ci-local: FAIL after ${wall}s — see the FAIL banners above (nothing cached)" >&2
  exit 1
fi
after="$(content_key)"
if [ "$after" != "$key" ]; then
  echo "ci-local: PASS after ${wall}s, but the working tree changed during the run — result NOT cached; re-run before pushing"
  exit 0
fi
date '+%Y-%m-%dT%H:%M:%S%z' > "$stamp"
echo "ci-local: PASS after ${wall}s — stamped; re-running on this exact tree is instant"
