#!/usr/bin/env bash
# test-no-pipefail-grep-q.sh — gate: no self-test may pipe INTO `grep -q` while `pipefail` is on.
#
# Why: `grep -q` exits on its first match. If the producer is still writing, it gets EPIPE (or
# SIGPIPE), and under `set -o pipefail` the PIPELINE fails although grep matched — an assertion
# that goes red on a correct result. It only bites when the scheduler lets grep exit between two
# of the producer's writes, so it is rare on an idle machine and common on a loaded one: once CI
# ran the suite concurrently (run-self-tests.sh) it failed test-retention-sweep.sh's AC-11 upper-bound
# arm and test-verify-provides.sh's em_gate_ok helper on the same run, both `write error: Broken
# pipe`. ~840 sites were
# rewritten to `grep -q PAT < <(producer)` — the same bytes reach grep, and a process
# substitution's status is not part of the pipeline, so a writer's EPIPE can no longer decide the
# assertion. This gate keeps new ones out.
#
# Scope: loomwright/scripts/test-*.sh, loomwright/scripts/adapters/*/test-*.sh and root
# scripts/test-*.sh — every file that mentions `pipefail`. Comment lines are ignored. Exit 0 = clean,
# 1 = a violation (or a broken detector — see the controls).
#
# RULE 2 — a builtin WRITER (printf / echo) piped into `grep -q`, in ANY shell script, pipefail or
# not. The rule above missed exactly this on ci run 37126834145: curation-status.sh is not a test and
# never sets pipefail, yet its `printf '%s\n' "$consumed"` piped into `grep -qxF` wrote
# "printf: write error: Broken pipe" to stderr and failed test-curation-status.sh's --json
# stderr-is-empty check. Without pipefail grep's verdict still decides the status, but the WRITER
# still races grep's early exit: under the default SIGPIPE disposition it dies silently (why it
# passed 5/5 locally), while a runner that hands SIGPIPE down IGNORED (GitHub Actions does) turns
# the race into EPIPE plus that stderr line. The value is already in a variable, so the fix is
# free: `grep -q PAT <<<"$var"` (bash 3.2 safe; same bytes as printf '%s\n'). Backslash-continued
# lines are joined before matching, and a trailing ` # comment` is stripped. Pre-existing sites are
# a per-file count RATCHET (WRITER_BASELINE below): any increase, or any file not listed, is red;
# a count that FALLS without the baseline being lowered is red too, so it only ever shrinks.
# Other producers (jq, cat, ...) piped into grep -q are only covered by rule 1 — rule 2 is scoped
# to the builtin writers, whose value can always move into a here-string.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# a `|` that is not half of `||`, then `grep` with q in ANY of its leading flag tokens — `-q`, `-qF`,
# and split forms like `-F -q` / `-v -q` alike (a first-token-only match missed the split forms)
RE='(^[[:space:]]*|[^|])\|[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*q'

# scan <file...> — prints file:line:text for each violation
scan() {
  local f
  for f in "$@"; do
    grep -q pipefail "$f" 2>/dev/null || continue
    grep -nE "$RE" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|"
  done
  return 0
}

# Rule 2: printf/echo (as a word) then a single `|` then grep with q in any leading flag token.
# `[^|]*` cannot cross a `|`, so `printf x || grep -q` (an OR, not a pipe) never matches.
WRE='(^|[^[:alnum:]_-])(printf|echo)([[:space:]][^|]*)?[|][[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*q'

# logical_lines <file> — prints `startline:text`, backslash-continued lines joined, whole-line
# comments dropped, a trailing ` # comment` stripped
logical_lines() {
  awk '{ if (buf == "") start = NR
         if ($0 ~ /\\$/) { buf = buf substr($0, 1, length($0) - 1) " "; next }
         print start ":" buf $0; buf = "" }
       END { if (buf != "") print start ":" buf }' "$1" \
    | grep -vE '^[0-9]+:[[:space:]]*#' | sed -E 's/[[:space:]]#[[:space:]].*$//'
  return 0
}

# scan_writer <file...> — prints file:line:text for each logical line holding a rule-2 violation
scan_writer() {
  local f
  for f in "$@"; do
    logical_lines "$f" | grep -E "$WRE" | sed "s|^|$f:|"
  done
  return 0
}

# count_writer <file> — number of rule-2 OCCURRENCES (not lines) in one file
count_writer() { logical_lines "$1" | grep -oE "$WRE" | wc -l | tr -d ' '; }

# ratchet <root> <baseline> <rel...> — compares each file's rule-2 count against <baseline>
# (`count path` lines) and prints ONE tagged line per violation, nothing when clean:
#   OVER <rel> <got> <base>   more occurrences than the baseline allows (an unlisted file has 0)
#   UNDER <rel> <got> <base>  fewer than the baseline — the baseline must be lowered to match
#   STALE <rel>               a baseline entry whose file is not among <rel...>
# A function, so the controls below drive every branch on fixtures — the live tree alone sits at
# got == base everywhere and would leave all three dead.
ratchet() {
  local root="$1" baseline="$2" rel got base seen=""
  shift 2
  for rel in "$@"; do
    got="$(count_writer "$root/$rel")"
    base="$(awk -v p="$rel" '$2 == p { print $1 }' <<<"$baseline")"
    [ -n "$base" ] && seen="$seen$rel
"
    if [ "$got" -gt "${base:-0}" ]; then
      echo "OVER $rel $got ${base:-0}"
    elif [ -n "$base" ] && [ "$got" -lt "$base" ]; then
      echo "UNDER $rel $got $base"
    fi
  done
  while read -r base rel; do
    [ -n "$rel" ] || continue
    grep -qxF -- "$rel" <<<"$seen" || echo "STALE $rel"
  done <<<"$baseline"
  return 0
}

T="$(mktemp -d "${TMPDIR:-/tmp}/test-no-pipefail-grep-q.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

echo "== detector controls (fixtures are assembled at runtime so this file never contains the pattern) =="
P='|'
{ echo 'set -uo pipefail'; printf '%s %s grep -q y && echo hit\n' 'printf "%s" "$x"' "$P"; } > "$T/bad-inline.sh"
{ echo 'set -uo pipefail'; printf '%s \\\n  %s grep -qF y\n' 'some_fn "$x"' "$P"; } > "$T/bad-continued.sh"
{ echo 'set -uo pipefail'; printf '%s %s grep -F -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/bad-split.sh"
{ echo 'set -uo pipefail'; printf '%s %s grep -F -i y\n' 'printf "%s" "$x"' "$P"; } > "$T/good-noq.sh"
{ echo 'set -uo pipefail'; echo 'grep -q y < <(printf "%s" "$x") && echo hit'; } > "$T/good-procsub.sh"
{ echo 'set -uo pipefail'; printf 'a %s%s grep -q y "$f"\n' "$P" "$P"; } > "$T/good-or.sh"
{ echo 'set -uo pipefail'; printf '# %s %s grep -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/good-comment.sh"
{ printf '%s %s grep -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/good-nopipefail.sh"

[ -n "$(scan "$T/bad-inline.sh")" ] && ok "a producer piped into grep -q under pipefail IS flagged" \
  || no "detector missed an inline producer piped into grep -q — the gate below would be vacuous"
[ -n "$(scan "$T/bad-continued.sh")" ] && ok "a backslash-continued pipe into grep -qF on its own line IS flagged" \
  || no "detector missed a continued-line pipe into grep -qF"
[ -n "$(scan "$T/bad-split.sh")" ] && ok "a split flag form (grep -F -q) IS flagged" \
  || no "detector missed a split flag form — q in a later flag token slips past"
[ -z "$(scan "$T/good-noq.sh")" ] && ok "a pipe into grep with NO q flag (reads to EOF) is NOT flagged" \
  || no "detector flags a grep that never exits early"
[ -z "$(scan "$T/good-procsub.sh")" ] && ok "'grep -q PAT < <(producer)' (the fix) is NOT flagged" \
  || no "detector flags the sanctioned process-substitution form"
[ -z "$(scan "$T/good-or.sh")" ] && ok "'a || grep -q' is NOT flagged (|| is not a pipe)" \
  || no "detector mistakes || for a pipe"
[ -z "$(scan "$T/good-comment.sh")" ] && ok "a comment line is NOT flagged" \
  || no "detector flags comment lines"
[ -z "$(scan "$T/good-nopipefail.sh")" ] && ok "a file without pipefail is NOT flagged (the hazard needs pipefail)" \
  || no "detector flags a file that never sets pipefail"

echo "== rule 2 detector controls: a builtin writer piped into grep -q, pipefail or not =="
# The exact ci-37126834145 shape, in a file with NO pipefail — the case rule 1 cannot see.
{ printf '%s %s grep -qxF -- "$id" && continue\n' "printf '%s\\n' \"\$consumed\"" "$P"; } > "$T/w-bad-nopipefail.sh"
{ printf '%s %s grep -q y\n' 'echo "$x"' "$P"; } > "$T/w-bad-echo.sh"
{ printf '%s \\\n  %s grep -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/w-bad-continued.sh"
{ printf 'if %s %s grep -F -q y; then :; fi\n' 'printf "%s" "$x"' "$P"; } > "$T/w-bad-split.sh"
{ echo 'grep -qxF -- "$id" <<<"$consumed" && continue'; } > "$T/w-good-herestring.sh"
{ printf '%s %s grep -c y\n' 'printf "%s" "$x"' "$P"; } > "$T/w-good-noq.sh"
{ printf '%s %s%s grep -q y f\n' 'printf x' "$P" "$P"; } > "$T/w-good-or.sh"
{ printf '%s %s grep -q y\n' 'my_printf "$x"' "$P"; } > "$T/w-good-notbuiltin.sh"
{ printf '[ -n "$x" ] || return 0   # never %s %s grep -q here\n' 'printf' "$P"; } > "$T/w-good-trailing-comment.sh"
{ printf '  # %s %s grep -q y\n' 'printf "%s" "$x"' "$P"; } > "$T/w-good-comment.sh"
for c in w-bad-nopipefail w-bad-echo w-bad-continued w-bad-split; do
  [ -n "$(scan_writer "$T/$c.sh")" ] && ok "rule 2 flags $c" \
    || no "rule 2 missed $c: $(cat "$T/$c.sh")"
done
for c in w-good-herestring w-good-noq w-good-or w-good-notbuiltin w-good-trailing-comment w-good-comment; do
  [ -z "$(scan_writer "$T/$c.sh")" ] && ok "rule 2 does not flag $c" \
    || no "rule 2 false positive on $c: $(cat "$T/$c.sh")"
done
[ "$(count_writer "$T/w-bad-continued.sh")" = "1" ] && ok "a continued pipe counts as ONE occurrence" \
  || no "count_writer miscounts a continued line: $(count_writer "$T/w-bad-continued.sh")"
# The red the user saw: the pre-fix curation-status.sh line itself must be caught by rule 2 and
# missed by rule 1 (no pipefail in that file, and it is not a test) — the gap this rule closes.
[ -z "$(scan "$T/w-bad-nopipefail.sh")" ] && ok "rule 1 alone misses the no-pipefail writer (the gap)" \
  || no "rule 1 unexpectedly flags a no-pipefail file — the controls above are stale"

echo "== rule 2 ratchet controls: every branch fires on fixtures =="
RT="$T/ratchet"; mkdir -p "$RT/sub"
w1="$(printf '%s %s grep -q y' 'printf "%s" "$x"' "$P")"
printf '%s\n%s\n' "$w1" "$w1" > "$RT/over.sh"       # 2 occurrences, baseline 1
printf '%s\n' "$w1"            > "$RT/under.sh"      # 1 occurrence,  baseline 2
printf '%s\n' "$w1"            > "$RT/equal.sh"      # 1 occurrence,  baseline 1
printf '%s\n' "$w1"            > "$RT/new.sh"        # 1 occurrence,  unlisted
printf 'grep -q y <<<"$x"\n'  > "$RT/clean.sh"      # 0 occurrences, unlisted
printf '%s\n' "$w1"            > "$RT/sub/equal.sh"  # same basename as a listed file, unlisted
RB='1 over.sh
2 under.sh
1 equal.sh
1 gone.sh'
rout="$(ratchet "$RT" "$RB" over.sh under.sh equal.sh new.sh clean.sh sub/equal.sh)"
want='OVER over.sh 2 1
UNDER under.sh 1 2
OVER new.sh 1 0
OVER sub/equal.sh 1 0
STALE gone.sh'
[ "$rout" = "$want" ] && ok "ratchet reports exactly OVER (raised + unlisted), UNDER, STALE — and nothing for equal/clean" \
  || no "ratchet output wrong — want:
$want
got:
$rout"
[ -z "$(ratchet "$RT" '1 equal.sh' equal.sh clean.sh)" ] && ok "ratchet is silent when every count equals its baseline" \
  || no "ratchet flags a tree that matches its baseline: $(ratchet "$RT" '1 equal.sh' equal.sh clean.sh)"

echo "== the suite =="
shopt -s nullglob
files=("$REPO_ROOT"/loomwright/scripts/test-*.sh "$REPO_ROOT"/loomwright/scripts/adapters/*/test-*.sh "$REPO_ROOT"/scripts/test-*.sh)
[ "${#files[@]}" -gt 10 ] && ok "scanned ${#files[@]} test files" || no "only ${#files[@]} test files found — the scan set is wrong"
hits="$(scan "${files[@]}")"
if [ -z "$hits" ]; then
  ok "no test pipes into grep -q under pipefail"
else
  no "these pipe into grep -q under pipefail — rewrite as: grep -q PAT < <(producer)"
  printf '%s\n' "$hits" | sed "s|^$REPO_ROOT/|    |"
fi

echo "== rule 2 over every shell script (ratchet) =="
# WRITER_BASELINE — pre-existing rule-2 sites, `count path` (occurrences, not lines). Lower a count
# when you convert a site to a here-string; never raise one or add a path — fix the new site instead.
WRITER_BASELINE='2 loomwright/scripts/add-orientation.sh
1 loomwright/scripts/automate-helpers.sh
1 loomwright/scripts/build-loop-evidence.sh
4 loomwright/scripts/dispatch-pr-review.sh
1 loomwright/scripts/notify-click-target.sh
1 loomwright/scripts/reconcile-resume-state.sh
1 loomwright/scripts/resolve-egress-config.sh
1 loomwright/scripts/send-telemetry-core.sh
1 loomwright/scripts/verify-run.sh
13 loomwright/sdk-spike/test/self-test.sh
1 scripts/bump-version.sh
1 scripts/check-doc-currency.sh
2 scripts/check-skills-index-sync.sh'
# Tracked AND untracked-but-not-ignored, so a new script is gated before it is ever committed.
all_sh=()
while IFS= read -r rel; do
  [ -f "$REPO_ROOT/$rel" ] && all_sh+=("$rel")
done < <(git -C "$REPO_ROOT" ls-files -co --exclude-standard -- '*.sh' 2>/dev/null)
[ "${#all_sh[@]}" -gt 100 ] && ok "rule 2 scanned ${#all_sh[@]} shell scripts" \
  || no "rule 2 found only ${#all_sh[@]} shell scripts (git ls-files failed?) — the scan set is wrong"
rhits="$(ratchet "$REPO_ROOT" "$WRITER_BASELINE" "${all_sh[@]}")"
if [ -z "$rhits" ]; then
  ok "no builtin writer is piped into grep -q beyond the baseline"
else
  while read -r kind rel got base; do
    case "$kind" in
      OVER)  no "$rel: $got builtin-writer pipe(s) into grep -q, baseline $base — rewrite as: grep -q PAT <<<\"\$var\""
             scan_writer "$REPO_ROOT/$rel" | sed "s|^$REPO_ROOT/|    |" ;;
      UNDER) no "$rel: $got builtin-writer pipe(s) into grep -q, below baseline $base — lower WRITER_BASELINE to $got" ;;
      STALE) no "WRITER_BASELINE lists $rel, which no longer exists — drop the entry" ;;
    esac
  done <<<"$rhits"
fi

echo
echo "test-no-pipefail-grep-q: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
