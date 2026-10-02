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
#                      the shared git dir (`git rev-parse --git-common-dir`/loomwright-ci-local/).
#   ONE RUN AT A TIME  a lock in the same shared dir serializes full runs across sessions and
#                      worktrees: two N-way suites on one machine both run ~2x slower and push the
#                      timing-sensitive tests into flaking. A waiter re-checks the cache after
#                      acquiring, so if the holder just verified the same tree it returns at once.
#                      A lock whose holder pid is dead is taken over.
#   TREE MOVED         the key is recomputed after the run; if the tree changed mid-run (a
#                      concurrent writer on this checkout), the verdict is reported but NOT cached.
#
# usage: ci-local.sh [--force] [--list]
#   --force   ignore the pass cache and run everything
#   --list    print the planned gate/test list and the content key, run nothing
# env:   SELF_TEST_JOBS / SELF_TEST_TIMEOUT   passed through to run-self-tests.sh
#        CI_LOCAL_LOCK_WAIT   seconds to wait for another run's lock before failing (default 1800)
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
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "ci-local: unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
runner="loomwright/scripts/run-self-tests.sh"
[ -f "$runner" ] || { echo "ci-local: $runner is missing — refusing to run" >&2; exit 1; }
[ -f .github/workflows/ci.yml ] || { echo "ci-local: .github/workflows/ci.yml is missing — cannot derive the CI gates" >&2; exit 1; }

state="$(cd "$(git rev-parse --git-common-dir)" && pwd)/loomwright-ci-local"
mkdir -p "$state/pass"
lockdir="$state/lock"
lock_wait="${CI_LOCAL_LOCK_WAIT:-1800}"
case "$lock_wait" in ''|*[!0-9]*) echo "ci-local: CI_LOCAL_LOCK_WAIT must be a non-negative integer, got '$lock_wait'" >&2; exit 2 ;; esac

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/ci-local.XXXXXX")"
have_lock=0
cleanup() {
  if [ "$have_lock" -eq 1 ]; then rm -rf "$lockdir"; fi
  rm -rf "$tmpd"
}
trap cleanup EXIT
# Turn INT/TERM into a normal exit so the EXIT trap releases the lock (a SIGKILLed holder leaves a
# stale lock instead, which the next run takes over once that pid is gone).
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

# --- lock ------------------------------------------------------------------------------------------
waited=0; announced=0
while ! mkdir "$lockdir" 2>/dev/null; do
  holder="$(cat "$lockdir/pid" 2>/dev/null || true)"
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    echo "ci-local: taking over a stale lock (holder pid $holder is gone)"
    rm -rf "$lockdir"
    continue
  fi
  if [ "$waited" -ge "$lock_wait" ]; then
    echo "ci-local: still locked by pid ${holder:-?} after ${lock_wait}s — giving up (FAIL). If no run is active: rm -rf '$lockdir'" >&2
    exit 1
  fi
  if [ "$announced" -eq 0 ]; then
    echo "ci-local: another run (pid ${holder:-starting}) holds the lock — waiting up to ${lock_wait}s so the two suites do not fight over the CPUs"
    announced=1
  fi
  sleep 2; waited=$((waited + 2))
done
have_lock=1
echo "$$" > "$lockdir/pid"
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
