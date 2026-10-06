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
#   RUN LOGS           every run that starts the pool (plain, --force, --affected) keeps its whole
#                      transcript (stdout + stderr, FAIL banners included) in
#                      `<ci-slot.sh dir>/runs/<key>-<YYYYmmddTHHMMSSZ>-<pid>[-affected].log` and
#                      prints that path as its first and its last line (on FAIL and INT/TERM too).
#                      A finished log ends with its verdict line (`ci-local: PASS …` / `ci-local:
#                      FAIL …`; an --affected log with the affected-only marker), so a result is
#                      read later with --last instead of re-running the suite to see it. At most 20
#                      logs are kept (shared by every checkout of the repo): every log still being
#                      written (no verdict line, owner pid alive) is kept — never pruned mid-run, so
#                      a long or queued run keeps its transcript however many runs start after it —
#                      and the newest finished logs fill the rest. Only when more than 20 runs are
#                      live at once do more than 20 (all live) remain (honest limit: a pid reused
#                      after a SIGKILL keeps that verdict-less log until the new owner exits). A
#                      cached PASS found before the slot acquire, and --list, write no log.
#   --affected         the inner-loop check while iterating — NOT a pre-push gate. The changed set is
#                      every file differing between `git merge-base origin/main HEAD` and the working
#                      tree, plus untracked non-ignored files (HEAD when origin/main is absent). Map:
#                      loomwright/scripts/<x>.sh ⇒ loomwright/scripts/test-<x>.sh; scripts/<x>.sh ⇒
#                      scripts/test-<x>.sh (each when it exists); a test-*.sh the full run would run
#                      ⇒ itself. Plus, always, the cheap static gates ci.yml names (every
#                      scripts/check-*.sh and scripts/validate-version.sh line, with its argument).
#                      The plan is a subset of the full plan, run through the same pool under a CI
#                      slot. A changed file with no mapped suite is listed under "not covered by
#                      --affected:". It never reads, writes or removes a pass stamp, and always ends
#                      with the affected-only marker line. Honest limit: a file-name map only — a
#                      change that breaks a suite with a different name is caught by the full run.
#   --last             prints the newest saved FULL-run log for the current content key and its
#                      verdict (`ci-local --last: PASS|FAIL <log>`); `stale-key` (newest full log of
#                      another tree) when none matches; `INCOMPLETE` for a log with no verdict line
#                      (interrupted, or still being written by another checkout); `UNVERIFIED` for a
#                      run that passed while the tree changed under it (its verdict says NOT cached —
#                      it vouches for no tree, so --last exits 1). Runs no gate.
#
# usage: ci-local.sh [--force] [--list] | --affected [--list] | --last
#   --force     ignore the pass cache and run everything
#   --list      print the planned gate/test list and the content key, run nothing
#               (with --affected: the changed files, the affected plan and the uncovered files)
#   --affected  run only the suites mapped from the changed files + the cheap gates (never stamps)
#   --last      show the newest saved full-run log for this tree and its verdict, run nothing
#   --last takes no other flag, and --affected does not take --force (exit 2)
# env:   SELF_TEST_JOBS / SELF_TEST_TIMEOUT   passed through to run-self-tests.sh
#        CI_LOCAL_LOCK_WAIT   seconds to wait for a CI slot before failing (default 1800)
#        LOOMWRIGHT_CI_SLOTS  number of shared slots (see SHARED CI SLOTS; never raise it to "go faster")
# exit:  0 = every gate passed (fresh or cached) · 1 = a gate failed / fail-closed condition · 2 = usage
#        --last: 0 = PASS · 1 = FAIL / UNVERIFIED / INCOMPLETE / stale-key / no log
#
# Honest limits: (1) .gitignore'd files are outside the key — a test that reads one is not
# re-run when only it changes (none should; tests build their fixtures in mktemp dirs).
# (2) NOT run here: ci.yml's sdk-spike step (npm ci + build + node suites) — CI still runs it.
# (3) This is macOS-green, not CI-green: the BSD/GNU userland differences in CLAUDE.md still apply.
# Self-test: scripts/test-ci-local.sh. Portability: bash 3.2 safe, no GNU-only flags.
set -euo pipefail
shopt -s nullglob

force=0; list=0; affected=0; last=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --list)  list=1; shift ;;
    --affected) affected=1; shift ;;
    --last)  last=1; shift ;;
    # --help = the header comment block: every line after the shebang up to the first line that is
    # not a comment. Anchored on comment-ness, not on whatever code follows the header.
    -h|--help) awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "ci-local: unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
done
# --affected and --last are modes of their own: neither consults the pass cache (so --force means
# nothing to them) and they exclude each other. Refuse a mix rather than guess which was meant.
if { [ "$last" -eq 1 ] && [ $((force + list + affected)) -gt 0 ]; } || { [ "$affected" -eq 1 ] && [ "$force" -eq 1 ]; }; then
  echo "ci-local: conflicting options — use [--force] [--list], --affected [--list], or --last alone (try --help)" >&2
  exit 2
fi

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
# --last only reads the shared dir; it creates nothing there.
[ "$last" -eq 1 ] || mkdir -p "$state/pass"
runs="$state/runs"
keep_runs=20
affected_marker="affected-only — not a pre-push gate; run ci-local.sh before pushing"

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/ci-local.XXXXXX")"
have_lock=0
acq_pid=""
log=""; log_open=0; tee_pids=""; verdict=""; verdict_fd=1

# finish_log — EXIT-trap half of the run log. Restores the real stdout/stderr, lets the two tee
# children drain (bounded: one still held open by a straggling grandchild is killed after ~5s, so a
# TERM still exits within seconds), then prints the verdict to the terminal AND appends it to the log
# — after the drain, so it is always the log's last content line — and ends with the log path.
finish_log() {
  local rc="$1" p i
  if [ "$log_open" -eq 1 ]; then
    exec 1>&3 2>&4 3>&- 4>&-
    for p in $tee_pids; do
      i=0
      while kill -0 "$p" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
      kill -KILL "$p" 2>/dev/null || true
      wait "$p" 2>/dev/null || true
    done
  fi
  # A non-zero exit that set no verdict (slot timeout, malformed slot answer, a `set -e` abort) is a
  # FAIL; INT/TERM (130/143) leave the log without one, which --last reports as INCOMPLETE.
  if [ -z "$verdict" ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 130 ] && [ "$rc" -ne 143 ]; then
    verdict="ci-local: FAIL (exit $rc) — see the message above"; verdict_fd=2
  fi
  # The log can only be gone if something outside the in-flight-aware prune removed it. Appending
  # would recreate it as a verdict-only stub that --last then trusts — say so instead.
  local log_gone=0
  [ -e "$log" ] || log_gone=1
  if [ -n "$verdict" ]; then
    if [ "$verdict_fd" -eq 2 ]; then printf '%s\n' "$verdict" >&2; else printf '%s\n' "$verdict"; fi
    [ "$log_gone" -eq 1 ] || printf '%s\n' "$verdict" >> "$log"
  fi
  if [ "$affected" -eq 1 ]; then
    printf '%s\n' "$affected_marker"
    [ "$log_gone" -eq 1 ] || printf '%s\n' "$affected_marker" >> "$log"
  fi
  if [ "$log_gone" -eq 1 ]; then
    printf 'ci-local: log %s was removed while this run wrote it — its transcript is lost (the verdict above is this run'\''s)\n' "$log" >&2
  else
    printf 'ci-local: log %s\n' "$log"
  fi
}

cleanup() {
  local rc=$?
  # A queued acquire still running (INT/TERM arrived mid-wait): stop it and reap it BEFORE the
  # release below, so it can neither claim a slot after that release nor write into $tmpd after the
  # rm. Its own TERM trap removes its ticket; the release then frees anything recorded under $$.
  if [ -n "$acq_pid" ]; then kill -TERM "$acq_pid" 2>/dev/null || true; wait "$acq_pid" 2>/dev/null || true; fi
  if [ "$have_lock" -eq 1 ]; then bash "$slot_helper" release --pid "$$" || true; fi
  if [ -n "$log" ]; then finish_log "$rc" || true; fi
  rm -rf "$tmpd"
}
trap cleanup EXIT
# Turn INT/TERM into a normal exit so the EXIT trap releases the slot (a SIGKILLed holder leaves a
# stale slot instead, which the next run takes over once that pid is gone).
trap 'exit 130' INT
trap 'exit 143' TERM

# runs_newest_first — the saved run logs (basenames), newest first: by the timestamp embedded in the
# name, ties (same second) by `ls -t` mtime order. Pure bash + POSIX sort, no stat/date flags.
runs_newest_first() {
  [ -d "$runs" ] || return 0
  local f s ts n=0
  ls -t "$runs" | while IFS= read -r f; do
    case "$f" in *.log) ;; *) continue ;; esac
    n=$((n + 1))
    s="${f%.log}"; s="${s%-affected}"; s="${s%-*}"; ts="${s##*-}"
    case "$ts" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;; *) ts=00000000T000000Z ;; esac
    printf '%s %s %s\n' "$ts" "$n" "$f"
  done | env LC_ALL=C sort -k1,1r -k2,2n | cut -d' ' -f3-
}
# log_key NAME — the content key a log was written for (the name minus -<timestamp>-<pid>[-affected].log).
log_key() { local s="${1%.log}"; s="${s%-affected}"; s="${s%-*}"; printf '%s\n' "${s%-*}"; }
# log_in_flight NAME — true when that log is still being written: its owner pid (from the name) is
# alive AND the log has no verdict line yet. Liveness is checked FIRST: a dead owner has already run
# its EXIT trap (verdict written, or interrupted), so its log is finished either way; a live owner
# whose log already ends in a verdict is past finish_log and prunable too.
log_in_flight() {
  local s="${1%.log}" pid
  s="${s%-affected}"; pid="${s##*-}"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  case "$(awk 'NF { l = $0 } END { print l }' "$runs/$1" 2>/dev/null)" in
    "ci-local: PASS"*|"ci-local: FAIL"*|"$affected_marker") return 1 ;;
  esac
  return 0
}

# open_log — creates this run's log, prunes runs/ to at most $keep_runs logs in total, prints its
# path as the first output line, then routes stdout and stderr through one tee each: the terminal
# keeps its two streams and the log gets both. The tees ignore INT/TERM so a Ctrl-C cannot cut the
# transcript short; they end on EOF once finish_log restores the real descriptors.
# Prune rule: every in-flight log is kept (a live transcript is never cut, this run's own included);
# finished logs fill the remaining room newest first; the rest go. So the total is $keep_runs unless
# more than $keep_runs runs are live at once (then only the live logs remain). Each log is classified
# ONCE, before any rm: a log seen live may finish meanwhile (kept, harmless); a finished log never
# becomes live again.
open_log() {
  local sfx="" f line nlive=0 room
  [ "$affected" -eq 0 ] || sfx="-affected"
  mkdir -p "$runs"
  log="$runs/$key-$(date -u '+%Y%m%dT%H%M%SZ')-$$$sfx.log"
  printf 'ci-local: log %s\n' "$log" > "$log"
  printf 'ci-local: log %s\n' "$log"
  : > "$tmpd/runs.lst"
  while IFS= read -r f; do
    if log_in_flight "$f"; then printf 'L %s\n' "$f"; nlive=$((nlive + 1)); else printf 'F %s\n' "$f"; fi >> "$tmpd/runs.lst"
  done < <(runs_newest_first)
  room=$((keep_runs - nlive))
  while IFS= read -r line; do
    case "$line" in
      "F "*) if [ "$room" -gt 0 ]; then room=$((room - 1)); else rm -f "$runs/${line#F }"; fi ;;
    esac
  done < "$tmpd/runs.lst"
  mkfifo "$tmpd/out.fifo" "$tmpd/err.fifo"
  exec 3>&1 4>&2
  ( trap '' INT TERM; exec tee -a "$log" ) < "$tmpd/out.fifo" >&3 &
  tee_pids="$!"
  ( trap '' INT TERM; exec tee -a "$log" ) < "$tmpd/err.fifo" >&4 &
  tee_pids="$tee_pids $!"
  exec > "$tmpd/out.fifo" 2> "$tmpd/err.fifo"
  log_open=1
}

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

if [ "$last" -eq 1 ]; then
  # --last writes nothing outside $tmpd: the blobs/trees hashing the key creates go to a temp object
  # dir (the repo's own objects stay readable through the alternates). Same key either way.
  objs="$(cd "$(git rev-parse --git-path objects)" && pwd)"
  mkdir -p "$tmpd/objects"
  export GIT_OBJECT_DIRECTORY="$tmpd/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$objs"
fi

key="$(content_key)"
stamp="$state/pass/$key"

# --- --last: the newest saved FULL-run log for this key, its verdict read from the log itself -------
if [ "$last" -eq 1 ]; then
  sel=""; newest=""
  while IFS= read -r f; do
    case "$f" in *-affected.log) continue ;; esac
    [ -n "$newest" ] || newest="$f"
    if [ "$(log_key "$f")" = "$key" ]; then sel="$f"; break; fi
  done < <(runs_newest_first)
  if [ -z "$newest" ]; then echo "ci-local --last: no saved full-run log in $runs"; exit 1; fi
  if [ -z "$sel" ]; then
    cat "$runs/$newest"
    echo "ci-local --last: stale-key (log key $(log_key "$newest"), current key $key) $runs/$newest"
    exit 1
  fi
  cat "$runs/$sel"
  vline="$(awk 'NF { l = $0 } END { print l }' "$runs/$sel")"
  # The tree-moved verdict starts with "ci-local: PASS" too, but that run refused to vouch for its
  # tree (nothing cached) — match it BEFORE the generic PASS so --last never reports it as PASS.
  case "$vline" in
    "ci-local: PASS"*"result NOT cached"*)
       echo "ci-local --last: UNVERIFIED (tree changed during the run — result not cached) $runs/$sel"; exit 1 ;;
    "ci-local: PASS"*) echo "ci-local --last: PASS $runs/$sel"; exit 0 ;;
    "ci-local: FAIL"*) echo "ci-local --last: FAIL $runs/$sel"; exit 1 ;;
    *) echo "ci-local --last: (no verdict line: the run was interrupted, or is still running in another checkout)"
       echo "ci-local --last: INCOMPLETE $runs/$sel"; exit 1 ;;
  esac
fi

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

# plan_src / plan_label run parallel to plan: the script each entry runs, and its --list line —
# --affected selects from this one plan, so it can never schedule a file the full run would not.
mkdir -p "$tmpd/gates"
plan=(); plan_src=(); plan_label=(); listed=" "; n=0
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
  plan+=("$w"); plan_src+=("$script"); plan_label+=("gate: $g")
done
for t in scripts/test-*.sh; do
  case "$listed" in *" $t "*) ;; *) plan+=("$t"); plan_src+=("$t"); plan_label+=("test: $t") ;; esac
done
suite=(loomwright/scripts/test-*.sh loomwright/scripts/adapters/*/test-*.sh)
if [ "${#suite[@]}" -eq 0 ]; then
  echo "ci-local: the loomwright self-test globs matched nothing — refusing to report green" >&2
  exit 1
fi
for t in "${suite[@]}"; do plan+=("$t"); plan_src+=("$t"); plan_label+=("test: $t"); done

# --- --affected: changed files ⇒ mapped suites; the plan entries kept are the cheap static gates +
# the mapped suites, in full-plan order (see --affected in the header). ---------------------------
if [ "$affected" -eq 1 ]; then
  if ! git rev-parse -q --verify origin/main >/dev/null 2>&1; then
    base="HEAD"; base_desc="HEAD (origin/main is absent)"
  elif base="$(git merge-base origin/main HEAD 2>/dev/null)"; then
    base_desc="the merge-base with origin/main ($(git rev-parse --short "$base"))"
  else
    base="HEAD"; base_desc="HEAD (origin/main shares no merge-base with HEAD)"
  fi
  changed=()
  while IFS= read -r f; do if [ -n "$f" ]; then changed+=("$f"); fi; done < <(
    { git diff --name-only --no-renames "$base" --; git ls-files -o --exclude-standard; } | env LC_ALL=C sort -u)
  mapped=" "; map_lines=(); uncovered=()
  for f in ${changed[@]+"${changed[@]}"}; do
    d="${f%/*}"; [ "$d" != "$f" ] || d="."
    b="${f##*/}"; t=""
    case "$b" in
      test-*.sh)
        case "$d" in
          scripts|loomwright/scripts) t="$f" ;;
          loomwright/scripts/adapters/*) if [ "${d%/*}" = loomwright/scripts/adapters ]; then t="$f"; fi ;;
        esac ;;
      *.sh)
        case "$d" in scripts|loomwright/scripts) t="$d/test-$b" ;; esac ;;
    esac
    if [ -n "$t" ] && [ -f "$t" ]; then
      mapped="$mapped$t "; map_lines+=("  $f ⇒ $t")
    else
      uncovered+=("$f")
    fi
  done
  aplan=(); alabel=(); n_cheap=0; n_mapped=0; i=0
  while [ "$i" -lt "${#plan[@]}" ]; do
    s="${plan_src[$i]}"
    case "$s" in
      scripts/check-*.sh|scripts/validate-version.sh) aplan+=("${plan[$i]}"); alabel+=("${plan_label[$i]}"); n_cheap=$((n_cheap + 1)) ;;
      *) case "$mapped" in *" $s "*) aplan+=("${plan[$i]}"); alabel+=("${plan_label[$i]}"); n_mapped=$((n_mapped + 1)) ;; esac ;;
    esac
    i=$((i + 1))
  done
  affected_report() {
    local l
    if [ "${#changed[@]}" -eq 0 ]; then
      echo "ci-local --affected: the changed set is empty (against $base_desc) — the cheap gates only"
    else
      echo "ci-local --affected: ${#changed[@]} changed file(s) against $base_desc"
      for l in ${map_lines[@]+"${map_lines[@]}"}; do echo "$l"; done
    fi
    if [ "${#uncovered[@]}" -gt 0 ]; then
      echo "not covered by --affected:"
      for l in "${uncovered[@]}"; do echo "  $l"; done
    fi
  }
fi

if [ "$list" -eq 1 ]; then
  if [ "$affected" -eq 1 ]; then
    affected_report
    for l in ${alabel[@]+"${alabel[@]}"}; do echo "$l"; done
    exit 0
  fi
  echo "key: $key"
  [ -f "$stamp" ] && echo "cache: PASS stamped $(cat "$stamp")" || echo "cache: miss"
  for g in "${gates[@]}"; do echo "gate: $g"; done
  for p in "${plan[@]}"; do case "$p" in "$tmpd"/*) ;; *) echo "test: $p" ;; esac; done
  exit 0
fi

cached_exit() {
  if [ -n "$log" ]; then
    # Logged (a waiter's post-slot re-check): the verdict must be the log's last content line.
    echo "ci-local: key $key  (use --force to re-run anyway)"
    verdict="ci-local: PASS (cached) — this exact tree already passed every gate at $(cat "$stamp")"; verdict_fd=1
  else
    echo "ci-local: PASS (cached) — this exact tree already passed every gate at $(cat "$stamp")"
    echo "ci-local: key $key  (use --force to re-run anyway)"
  fi
  exit 0
}
# --affected never consults the cache: it neither vouches for a tree nor is excused by a stamp.
if [ "$affected" -eq 0 ] && [ "$force" -eq 0 ] && [ -f "$stamp" ]; then cached_exit; fi

# From here on the pool will (try to) run: keep the transcript. Opened before the slot acquire, so a
# run interrupted while queued still names its log.
open_log
if [ "$affected" -eq 1 ]; then
  affected_report
  if [ "${#aplan[@]}" -eq 0 ]; then
    verdict="ci-local --affected: FAIL — ci.yml names no check-*/validate-version gate and nothing mapped; refusing to report green on an empty plan"
    verdict_fd=2
    exit 1
  fi
fi

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

# --- --affected run: never reads, writes or removes a pass stamp --------------------------------------
if [ "$affected" -eq 1 ]; then
  echo "ci-local --affected: $n_cheap cheap gates + $n_mapped mapped suites, one pool (key ${key%%-*})"
  start=$(date +%s)
  rc=0
  bash "$runner" "${aplan[@]}" || rc=$?
  wall=$(( $(date +%s) - start ))
  echo
  if [ "$rc" -ne 0 ]; then
    verdict="ci-local --affected: FAIL after ${wall}s — see the FAIL banners above"; verdict_fd=2
    exit 1
  fi
  verdict="ci-local --affected: PASS after ${wall}s — ${#aplan[@]} of the full run's ${#plan[@]} entries"; verdict_fd=1
  exit 0
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
  verdict="ci-local: FAIL after ${wall}s — see the FAIL banners above (nothing cached)"; verdict_fd=2
  exit 1
fi
after="$(content_key)"
if [ "$after" != "$key" ]; then
  verdict="ci-local: PASS after ${wall}s, but the working tree changed during the run — result NOT cached; re-run before pushing"
  verdict_fd=1
  exit 0
fi
date '+%Y-%m-%dT%H:%M:%S%z' > "$stamp"
verdict="ci-local: PASS after ${wall}s — stamped; re-running on this exact tree is instant"; verdict_fd=1
exit 0
