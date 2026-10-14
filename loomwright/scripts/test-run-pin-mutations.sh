#!/usr/bin/env bash
# test-run-pin-mutations.sh — hermetic self-test for run-pin-mutations.sh (automate-speed/02).
# Every leg drives the REAL script against a fixture git repo in a mktemp dir; no network, no gh.
#
# Legs:
#   (H)  held: every row's mutant turns its pin red ⇒ each line `held`, summary line, exit 0
#   (N)  not_held: a pin that stays green on its mutant ⇒ `not_held`, exit 1
#        MUTATION CONTROL (Validation 2): a copy that skips the "must fail mutated" run (treats the
#        mutated pin as red without running it) reads the same row `held` ⇒ (N) catches it
#   (U1) mutation does not apply: 0 and 2 matches ⇒ `unverified (mutation_does_not_apply: <n> matches)`
#   (U2) the unmutated pin is red ⇒ `unverified (pin_red_unmutated)`, exit 2
#   (U3) prose wording ⇒ `unverified (not_machine_applicable)`
#   (U4) pin token matches no file / two files ⇒ `unverified (pin_not_found)`; a target matching
#        nothing ⇒ `unverified (target_not_found)`; a non-.sh pin ⇒ `unverified (unsupported_pin_runner)`
#   (I)  invalid mutants never read `held`: empty, unchanged (A == B), `bash -n` broken, invalid JSON
#   (T)  a pin past --timeout ⇒ `unverified (timeout)`, and the run ends within a few seconds
#   (L)  literals are FIXED strings: regex/sed metacharacters (`.*[]\&/$`) match only themselves
#   (W)  the WORKING TREE is copied: an untracked file and an uncommitted edit reach the pin
#   (Z)  no leak: checkout status (incl. ignored), index bytes and `git worktree list` identical, no
#        scratch dir left in TMPDIR, nothing written to the caller's HOME (HOME is relocated)
#   (G)  a caller-exported GIT_DIR / GIT_INDEX_FILE (pointing at the checkout) leaves its HEAD, index
#        bytes and `status --porcelain` unchanged — the scratch copy never commits/stages into it
#        MUTATION CONTROL: a copy without the git-env `unset` line moves HEAD or the index ⇒ (G) catches it
#   (P)  exit precedence: not_held + unverified ⇒ exit 1
#   (C)  cache: a second run re-runs nothing (every line `(cached)`, pin execution counter 0)
#   (CI) cache invalidation: the target changes ⇒ that row re-runs; unverified rows are never cached
#   (O)  --only-paths: rows outside the globs print nothing; zero selected ⇒ `pin-mutations: none selected`
#   (S)  section handling: no section ⇒ `pin-mutations: none`, exit 0; a fenced heading is not the
#        section; the section ends at the next `##` heading; `\|` in a literal reads as `|`
#   (E)  usage / unreadable brief / non-git root ⇒ one `pin-mutations: unverified (<reason>)` line, exit 2
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -u
# The fixture's own git calls must hit the fixture, never a repo a caller's exported GIT_DIR names.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/run-pin-mutations.sh"
[ -f "$SUT" ] || { echo "test-run-pin-mutations: $SUT not found" >&2; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/test-run-pin-mutations.XXXXXX")"
trap 'rm -rf "$T"' EXIT
# The script's scratch dirs land here, so the no-leak leg can see them; HOME is a sandbox whose
# contents are checked after every run.
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export HOME="$T/home"; mkdir -p "$HOME"
export PIN_COUNTER="$T/counter"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }
has()  { grep -qF -- "$1" <<<"$out"; }
line() { grep -F -- "pin-mutation $1:" <<<"$out"; }
execs() { [ -f "$PIN_COUNTER" ] && wc -l < "$PIN_COUNTER" | tr -d ' ' || echo 0; }

R="$T/repo"
build_repo() {
  rm -rf "$R"; mkdir -p "$R/a" "$R/b" "$R/c" "$R/d"
  cat > "$R/a/lib.sh" <<'SH'
value() { echo 42; }
guard() {
  [ "$1" = ok ] || return 1
  return 0
}
pattern='a.*b[x]\n&/$HOME'
SH
  cat > "$R/a/test-lib.sh" <<'SH'
echo run >> "$PIN_COUNTER"
. "$(dirname "$0")/lib.sh"
[ "$(value)" = 42 ] || exit 1
guard ok || exit 1
guard bad && exit 1
[ "$pattern" = 'a.*b[x]\n&/$HOME' ] || exit 1
[ -z "${NEED_EXTRA:-}" ] || [ "$(extra)" = 7 ] || exit 1
echo touched > "$HOME/pin-was-here"
exit 0
SH
  printf 'echo run >> "$PIN_COUNTER"\nexit 0\n' > "$R/a/test-weak.sh"
  printf 'echo run >> "$PIN_COUNTER"\nexit 1\n' > "$R/a/test-red.sh"
  printf 'echo run >> "$PIN_COUNTER"\nsleep 30\n' > "$R/a/test-slow.sh"
  printf 'echo dup\n' > "$R/b/test-dup.sh"; printf 'echo dup\n' > "$R/c/test-dup.sh"
  printf '{"mode": "strict", "n": 1}\n' > "$R/d/conf.json"
  cat > "$R/d/test-conf.sh" <<'SH'
echo run >> "$PIN_COUNTER"
grep -q '"mode": "strict"' "$(dirname "$0")/conf.json"
SH
  printf 'only\n' > "$R/d/one.sh"
  printf 'x=1\nx=1\n' > "$R/d/twice.sh"
  printf 'print("hi")\n' > "$R/d/test-py.py"
  printf 'ignored.txt\n' > "$R/.gitignore"
  ( cd "$R" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm fixture )
}

# brief <file> <rows...> — a brief whose Pin mutations section holds the given table rows.
brief() {
  local f="$1"; shift
  { printf '# Brief\n\n## Task\nx\n\n## Pin mutations\n\n| Pin | Mutation (one line) |\n|-----|-----|\n'
    for r in "$@"; do printf '%s\n' "$r"; done
    printf '\n## Subtask Structure\n\n| a | b |\n|---|---|\n| `a/test-weak.sh` | flip `42` → `43` in `a/lib.sh` |\n'
  } > "$f"
}
run() { : > "$PIN_COUNTER"; out="$(cd "$R" && bash "$SUT" "$@" 2>"$T/stderr")"; rc=$?; }

ROW_VALUE='| `a/test-lib.sh` — value | flip `echo 42` → `echo 43` in `a/lib.sh` ⇒ leg red |'
ROW_GUARD='| `test-lib.sh` — guard | delete `[ "$1" = ok ] || return 1` in `lib.sh` |'
ROW_WEAK='| `a/test-weak.sh` — weak | flip `echo 42` -> `echo 41` in `a/lib.sh` |'
ROW_RED='| `a/test-red.sh` — red | flip `echo 42` → `echo 40` in `a/lib.sh` |'
ROW_PROSE='| `a/test-lib.sh` — prose | make the guard always pass ⇒ red |'

build_repo
B="$T/brief.md"

# (H)
brief "$B" "$ROW_VALUE" "$ROW_GUARD"
run "$B"
if [ "$rc" -eq 0 ] && [ "$(line 1)" = 'pin-mutation 1: held — a/test-lib.sh :: flip `echo 42` → `echo 43` in `a/lib.sh` ⇒ leg red' ] \
   && [ "$(line 2)" = 'pin-mutation 2: held — a/test-lib.sh :: delete `[ "$1" = ok ] || return 1` in `lib.sh`' ] \
   && [ "$(sed -n '$p' <<<"$out")" = "pin-mutations: 2 held, 0 not_held, 0 unverified (0 cached)" ] \
   && ! has "pin-mutation 3:" && [ "$(execs)" = 3 ]; then
  ok "(H) every mutant red ⇒ held ×2, exit 0, one unmutated run per distinct pin (3 executions), the next section's table ignored"
else no "(H) rc=$rc execs=$(execs) out=$out"; fi

# (N)
brief "$B" "$ROW_WEAK"
run "$B"
if [ "$rc" -eq 1 ] && [ "$(line 1)" = 'pin-mutation 1: not_held — a/test-weak.sh :: flip `echo 42` -> `echo 41` in `a/lib.sh`' ]; then
  ok "(N) a pin green on its mutant ⇒ not_held, exit 1 (\`->\` accepted)"
else no "(N) rc=$rc out=$out"; fi
# MUTATION CONTROL — skip the mutated run (treat the mutant as red without running it).
awk '/^      run_pin "\$pin" "\$SCRATCH\/logs\/mutated\.\$idx\.log"$/ { print "      RUN_RC=1; RUN_TIMED_OUT=0"; n++; next } { print } END { exit n != 1 }' \
  "$SUT" > "$T/mutant-skip.sh"
mrc=$?
if [ "$mrc" -eq 0 ] && ! cmp -s "$SUT" "$T/mutant-skip.sh" && bash -n "$T/mutant-skip.sh"; then
  : > "$PIN_COUNTER"; mout="$(cd "$R" && bash "$T/mutant-skip.sh" "$B" 2>&1)"; mrc2=$?
  if [ "$mrc2" -eq 0 ] && grep -qF 'pin-mutation 1: held' <<<"$mout"; then
    ok "(N) MUTATION CONTROL: a copy that skips the mutated run reads the weak pin held — (N)'s not_held assertion catches it"
  else no "(N) MUTATION CONTROL: the skip-mutant did not change the verdict: rc=$mrc2 out=$mout"; fi
else no "(N) MUTATION CONTROL: mutant not built (anchor_found=$((1 - mrc)))"; fi

# (U1)
brief "$B" '| `a/test-lib.sh` | delete `no such text` in `a/lib.sh` |' '| `d/test-conf.sh` | delete `x=1` in `d/twice.sh` |'
run "$B"
if [ "$rc" -eq 2 ] && has 'pin-mutation 1: unverified (mutation_does_not_apply: 0 matches)' \
   && has 'pin-mutation 2: unverified (mutation_does_not_apply: 2 matches)' && [ "$(execs)" = 0 ]; then
  ok "(U1) 0 and 2 matches ⇒ mutation_does_not_apply, exit 2, no pin ran"
else no "(U1) rc=$rc execs=$(execs) out=$out"; fi

# (U2)
brief "$B" "$ROW_RED"
run "$B"
if [ "$rc" -eq 2 ] && has 'pin-mutation 1: unverified (pin_red_unmutated) — a/test-red.sh' && [ "$(execs)" = 1 ]; then
  ok "(U2) a pin red before any mutation ⇒ pin_red_unmutated, exit 2, the mutated run never happened"
else no "(U2) rc=$rc execs=$(execs) out=$out"; fi

# (U3)
brief "$B" "$ROW_PROSE"
run "$B"
if [ "$rc" -eq 2 ] && has 'pin-mutation 1: unverified (not_machine_applicable) — a/test-lib.sh :: make the guard always pass ⇒ red'; then
  ok "(U3) prose wording ⇒ not_machine_applicable"
else no "(U3) rc=$rc out=$out"; fi

# (U4)
brief "$B" '| `test-nope.sh` | flip `echo 42` → `echo 43` in `a/lib.sh` |' \
           '| `test-dup.sh` | flip `echo 42` → `echo 43` in `a/lib.sh` |' \
           '| no backtick here | flip `echo 42` → `echo 43` in `a/lib.sh` |' \
           '| `a/test-lib.sh` | flip `echo 42` → `echo 43` in `zz/none.sh` |' \
           '| `d/test-py.py` | flip `echo 42` → `echo 43` in `a/lib.sh` |'
run "$B"
if [ "$rc" -eq 2 ] && has 'pin-mutation 1: unverified (pin_not_found) — test-nope.sh' \
   && has 'pin-mutation 2: unverified (pin_not_found) — test-dup.sh' && has 'pin-mutation 3: unverified (pin_not_found) — -' \
   && has 'pin-mutation 4: unverified (target_not_found)' && has 'pin-mutation 5: unverified (unsupported_pin_runner) — d/test-py.py'; then
  ok "(U4) missing / ambiguous / absent pin ⇒ pin_not_found; missing target ⇒ target_not_found; .py pin ⇒ unsupported_pin_runner"
else no "(U4) rc=$rc out=$out"; fi

# (I)
brief "$B" '| `d/test-conf.sh` | delete `only` in `d/one.sh` |' \
           '| `a/test-lib.sh` | flip `echo 42` → `echo 42` in `a/lib.sh` |' \
           '| `a/test-lib.sh` | delete `guard() {` in `a/lib.sh` |' \
           '| `d/test-conf.sh` | flip `"n": 1}` → `"n": 1` in `d/conf.json` |'
run "$B"
if [ "$rc" -eq 2 ] && has 'pin-mutation 1: unverified (invalid_mutant: empty)' && has 'pin-mutation 2: unverified (invalid_mutant: unchanged)' \
   && has 'pin-mutation 3: unverified (invalid_mutant: bash -n)' && has 'pin-mutation 4: unverified (invalid_mutant: jq empty)' \
   && ! has ': held' && [ "$(execs)" = 0 ]; then
  ok "(I) empty / unchanged / bash -n / invalid JSON mutants ⇒ invalid_mutant, never held, validated before any run"
else no "(I) rc=$rc execs=$(execs) out=$out"; fi

# (T)
brief "$B" '| `a/test-slow.sh` | flip `echo 42` → `echo 43` in `a/lib.sh` |'
start=$SECONDS
run "$B" --timeout 1
took=$((SECONDS - start))
if [ "$rc" -eq 2 ] && has 'pin-mutation 1: unverified (timeout)' && [ "$took" -le 10 ]; then
  ok "(T) a pin past --timeout ⇒ unverified (timeout) in ${took}s (watchdog, no timeout(1))"
else no "(T) rc=$rc took=${took}s out=$out"; fi

# (L) — the regex/sed metacharacter literal matches only itself.
brief "$B" '| `a/test-lib.sh` | flip `a.*b[x]\n&/$HOME` → `literal` in `a/lib.sh` |'
run "$B"
if [ "$rc" -eq 0 ] && has 'pin-mutation 1: held'; then
  ok "(L) a literal full of regex/sed metacharacters is matched and replaced as a fixed string"
else no "(L) rc=$rc out=$out"; fi

# (W) + (Z) — the working tree (untracked + uncommitted) is what runs; nothing leaks.
printf '# untracked helper\nextra() { echo 7; }\n' > "$R/a/extra.sh"            # untracked, not ignored
printf '. "$(dirname "${BASH_SOURCE[0]}")/extra.sh"\nNEED_EXTRA=1\n' >> "$R/a/lib.sh"   # uncommitted edit
echo "stays" > "$R/ignored.txt"
before_status="$(cd "$R" && git status --porcelain --ignored)"
before_index="$(cksum < "$R/.git/index")"
before_wt="$(cd "$R" && git worktree list --porcelain)"
brief "$B" "$ROW_VALUE" '| `a/test-lib.sh` | delete `echo 7` in `a/extra.sh` |'
run "$B"
after_status="$(cd "$R" && git status --porcelain --ignored)"
if [ "$rc" -eq 0 ] && has 'pin-mutation 1: held' && has 'pin-mutation 2: held'; then
  ok "(W) the scratch copy carries the untracked file and the uncommitted edit (unmutated pin green, both rows held)"
else no "(W) rc=$rc out=$out"; fi
if [ "$before_status" = "$after_status" ] && [ "$before_index" = "$(cksum < "$R/.git/index")" ] \
   && [ "$before_wt" = "$(cd "$R" && git worktree list --porcelain)" ] && [ -z "$(ls -A "$TMPDIR")" ] \
   && [ ! -e "$HOME/pin-was-here" ]; then
  ok "(Z) checkout status/index/worktree list identical, scratch dir gone, the caller's HOME untouched"
else no "(Z) status_same=$([ "$before_status" = "$after_status" ] && echo y || echo n) tmp=[$(ls -A "$TMPDIR")] home=[$(ls -A "$HOME")]"; fi
( cd "$R" && git checkout -q -- . && rm -f a/extra.sh ignored.txt )

# (G) — caller git env. A pending edit + an untracked file; GIT_DIR / GIT_INDEX_FILE exported for the run only.
# g_run <sut> — runs <sut> with the vars exported; sets g_same=y when HEAD, index bytes, status are unchanged.
g_run() {
  printf '# pending edit\n' >> "$R/a/lib.sh"; printf 'u\n' > "$R/a/untracked.txt"
  local h0 i0 s0
  h0="$(git -C "$R" rev-parse HEAD)"; i0="$(cksum < "$R/.git/index")"; s0="$(git -C "$R" status --porcelain)"
  : > "$PIN_COUNTER"
  out="$(cd "$R" && GIT_DIR="$R/.git" GIT_INDEX_FILE="$R/.git/index" bash "$1" "$B" 2>"$T/stderr")"; rc=$?
  g_same=n
  if [ "$h0" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$i0" = "$(cksum < "$R/.git/index")" ] \
     && [ "$s0" = "$(git -C "$R" status --porcelain)" ]; then g_same=y; fi
  # restore the fixture whatever the run did (a mutant may have committed onto it)
  git -C "$R" reset -q --hard "$h0" 2>/dev/null; rm -f "$R/a/untracked.txt"
}
brief "$B" "$ROW_VALUE"
g_run "$SUT"
if [ "$g_same" = y ] && [ "$rc" -eq 0 ] && has 'pin-mutation 1: held'; then
  ok "(G) caller-exported GIT_DIR + GIT_INDEX_FILE: checkout HEAD, index bytes and status unchanged, row still held"
else no "(G) same=$g_same rc=$rc out=$out"; fi
# MUTATION CONTROL — drop the git-env unset.
awk '/^unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE / { n++; next } { print } END { exit n != 1 }' "$SUT" > "$T/mutant-genv.sh"
mrc=$?
if [ "$mrc" -eq 0 ] && bash -n "$T/mutant-genv.sh"; then
  g_run "$T/mutant-genv.sh"
  if [ "$g_same" = n ]; then
    ok "(G) MUTATION CONTROL: without the unset the scratch copy's git reaches the checkout — (G) catches it"
  else no "(G) MUTATION CONTROL: the no-unset mutant left the checkout unchanged: rc=$rc out=$out"; fi
else no "(G) MUTATION CONTROL: mutant not built (anchor_found=$((1 - mrc)))"; fi

# (P)
brief "$B" "$ROW_WEAK" "$ROW_PROSE"
run "$B"
if [ "$rc" -eq 1 ] && has 'not_held' && has 'unverified (not_machine_applicable)' \
   && [ "$(sed -n '$p' <<<"$out")" = "pin-mutations: 0 held, 1 not_held, 1 unverified (0 cached)" ]; then
  ok "(P) not_held + unverified ⇒ exit 1 (not_held wins)"
else no "(P) rc=$rc out=$out"; fi

# (C) — second run with the same files: nothing re-runs.
CF="$T/cache/pins.tsv"
brief "$B" "$ROW_VALUE" "$ROW_WEAK" "$ROW_PROSE"
run "$B" --cache "$CF"; first="$out"; first_rc=$rc
run "$B" --cache "$CF"
if [ "$first_rc" -eq 1 ] && [ "$rc" -eq 1 ] && [ "$(execs)" = 0 ] && has 'pin-mutation 1: held (cached)' \
   && has 'pin-mutation 2: not_held (cached)' && has 'pin-mutation 3: unverified (not_machine_applicable) —' \
   && [ "$(sed -n '$p' <<<"$out")" = "pin-mutations: 1 held, 1 not_held, 1 unverified (2 cached)" ] \
   && [ "$(wc -l < "$CF" | tr -d ' ')" = 2 ] && ! grep -q unverified "$CF"; then
  ok "(C) second run: both decided rows (cached), 0 pin executions, unverified never cached"
else no "(C) rc=$rc execs=$(execs) cache=[$(cat "$CF" 2>/dev/null)] first=$first out=$out"; fi

# (CI) — the target of row 1 changes (not row 2's pin or target? both target a/lib.sh) ⇒ both re-run;
# a row on another target stays cached.
brief "$B" "$ROW_VALUE" '| `d/test-conf.sh` | flip `strict` → `loose` in `d/conf.json` |'
run "$B" --cache "$CF"
printf '# comment\n' >> "$R/a/lib.sh"
run "$B" --cache "$CF"
if [ "$rc" -eq 0 ] && has 'pin-mutation 1: held —' && ! has 'pin-mutation 1: held (cached)' \
   && has 'pin-mutation 2: held (cached)' && [ "$(execs)" -ge 2 ]; then
  ok "(CI) a changed target re-runs its row; a row on an unchanged target stays (cached)"
else no "(CI) rc=$rc execs=$(execs) out=$out"; fi
( cd "$R" && git checkout -q -- . )

# (O)
brief "$B" "$ROW_VALUE" '| `d/test-conf.sh` | flip `strict` → `loose` in `d/conf.json` |' "$ROW_PROSE"
run "$B" --only-paths 'a/*'
if [ "$rc" -eq 0 ] && has 'pin-mutation 1: held' && ! has 'pin-mutation 2:' && ! has 'pin-mutation 3:'; then
  ok "(O) --only-paths a/*: only the a/ row prints; the d/ row and the prose row print nothing"
else no "(O) rc=$rc out=$out"; fi
run "$B" --only-paths 'zzz/*' 'q/'
if [ "$rc" -eq 0 ] && [ "$out" = "pin-mutations: none selected" ]; then ok "(O) zero selected rows ⇒ 'pin-mutations: none selected', exit 0"
else no "(O) none-selected: rc=$rc out=$out"; fi
run "$B" --only-paths 'd/'
if [ "$rc" -eq 0 ] && has 'pin-mutation 2: held' && ! has 'pin-mutation 1:'; then ok "(O) a trailing-/ glob is a directory prefix"
else no "(O) dir prefix: rc=$rc out=$out"; fi

# (S)
printf '# Brief\n\n```\n## Pin mutations\n| `a/test-weak.sh` | flip `42` → `43` in `a/lib.sh` |\n```\n\n## Task\n' > "$T/nosec.md"
run "$T/nosec.md"
if [ "$rc" -eq 0 ] && [ "$out" = "pin-mutations: none" ]; then ok "(S) no section (a fenced heading does not count) ⇒ 'pin-mutations: none', exit 0"
else no "(S) rc=$rc out=$out"; fi
brief "$B"
run "$B"
if [ "$rc" -eq 0 ] && [ "$out" = "pin-mutations: none" ]; then ok "(S) a section with no rows ⇒ 'pin-mutations: none'"
else no "(S) empty section: rc=$rc out=$out"; fi
printf 'v="a|b"\n' > "$R/d/pipe.sh"; ( cd "$R" && git add d/pipe.sh && git commit -qm pipe )
printf 'echo run >> "$PIN_COUNTER"\ngrep -qF %s "$(dirname "$0")/pipe.sh"\n' "'a|b'" > "$R/d/test-pipe.sh"
brief "$B" '| `d/test-pipe.sh` | flip `a\|b` → `a/b` in `d/pipe.sh` |'
run "$B"
if [ "$rc" -eq 0 ] && has 'pin-mutation 1: held'; then ok "(S) \`\\|\` in a backticked literal reads as \`|\`"
else no "(S) escaped pipe: rc=$rc out=$out"; fi
rm -f "$R/d/test-pipe.sh"

# (E)
run "$T/missing.md"
if [ "$rc" -eq 2 ] && [ "$out" = "pin-mutations: unverified (brief_unreadable)" ]; then ok "(E) unreadable brief ⇒ exit 2, one line"
else no "(E) brief: rc=$rc out=$out"; fi
mkdir -p "$T/notgit"
run "$B" --root "$T/notgit"
if [ "$rc" -eq 2 ] && [ "$out" = "pin-mutations: unverified (root_not_git)" ]; then ok "(E) non-git --root ⇒ exit 2"
else no "(E) root: rc=$rc out=$out"; fi
run "$B" --bogus
if [ "$rc" -eq 2 ] && has 'pin-mutations: unverified (usage:'; then ok "(E) unknown option ⇒ exit 2"
else no "(E) usage: rc=$rc out=$out"; fi
run "$B" --timeout 0
if [ "$rc" -eq 2 ] && has 'pin-mutations: unverified (usage:'; then ok "(E) --timeout 0 ⇒ exit 2"
else no "(E) timeout: rc=$rc out=$out"; fi

[ -z "$(ls -A "$TMPDIR")" ] && ok "every run removed its scratch dir" || no "scratch dirs left: $(ls -A "$TMPDIR")"

echo
echo "test-run-pin-mutations: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
