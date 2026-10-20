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
# Scope: loomwright/scripts/test-*.sh, their sourced parts loomwright/scripts/test-*.d/*.sh,
# loomwright/scripts/adapters/*/test-*.sh and root scripts/test-*.sh — every file that mentions
# `pipefail` (a part: or whose runner does). Comment lines are ignored. Exit 0 = clean,
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
# Other producers (jq, cat, ...) piped into grep -q are covered by rules 1 and 3 — rule 2 is scoped
# to the builtin writers, whose value can always move into a here-string.
#
# RULE 3 — ANY producer piped into `grep -q` in a NON-test script that runs under pipefail. Rule 1
# sees only test files and rule 2 only builtin writers, so `tail | grep -q` in a production script was
# invisible to both: lanes_run_wrapper (automate-lanes.d/launch.sh) decided `.died` from exactly that
# pipe under automate-lanes.sh's `set -uo pipefail`, grep's first-match exit SIGPIPEd tail, the
# pipeline read 141, and a Supervisor phase that had finished and opened its PR was marked dead (wave 7,
# lane L22; PR #643). Scope = every shell script outside rule 1's set that SETS pipefail (`set …
# pipefail` at a command position) or is SOURCED by one, transitively: an `X.d/<m>.sh` module of
# `X.sh`, a `. <path>/<name>.sh` line, or a `. "$VAR"` line whose VAR is assigned a `*.sh` path in the
# same file (a `$NAME` inside the basename matches any). A source path built any other way, or a script
# only a TEST sources, is not seen. Builtin-writer occurrences are left to rule 2, so a site is counted
# once. Pre-existing sites are a per-file RATCHET (PROD_BASELINE below), the same OVER / UNDER / STALE
# contract as rule 2. The fix is the rule-1 form, `grep -q PAT < <(producer)`.
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

# scan <file...> — prints file:line:text for each violation. A test PART (test-<x>.d/*.sh) is sourced
# by its runner test-<x>.sh and runs under the runner's `set -o pipefail`, so it is scanned when it OR
# that runner mentions pipefail (a part never sets it itself — automate-speed/19).
scan() {
  local f r d
  for f in "$@"; do
    # the PARENT dir's own name, never a pattern over the whole path: `*/test-*.d/*.sh` also matches a
    # file anywhere below a `test-…` directory, such as this test's own mktemp dir
    r="$f"; d="${f%/*}"; case "${d##*/}" in test-*.d) r="${d%.d}.sh" ;; esac
    { grep -q pipefail "$f" || grep -q pipefail "$r"; } 2>/dev/null || continue
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

# count_prod <file> — number of rule-3 OCCURRENCES in one file: every pipe into grep -q on a logical
# line, minus the builtin-writer ones rule 2 already counts
count_prod() {
  local a
  a="$(logical_lines "$1" | grep -oE "$RE" | wc -l | tr -d ' ')"
  echo $(( a - $(count_writer "$1") ))
}

# scan_prod <file...> — prints file:line:text for each logical line holding a rule-3 violation
scan_prod() {
  local f
  for f in "$@"; do
    logical_lines "$f" | grep -E "$RE" | grep -vE "$WRE" | sed "s|^|$f:|"
  done
  return 0
}

# pipefail_edges <root> <rel...> — ONE awk pass over the files (paths relative to <root>): prints
# `P <rel>` for a file that sets pipefail at a command position, and `E <rel> <glob>` for each `*.sh`
# basename it sources — literally on the `.`/`source` line, or through the assignments of the bare
# `$VAR` that line sources. A `$NAME` inside a basename becomes the glob `*`; a positional `$1` drops it.
pipefail_edges() {
  local root="$1"; shift
  [ "$#" -gt 0 ] || return 0
  ( cd "$root" && awk '
    function words(s,   out, w) {
      out = ""
      while (match(s, /[A-Za-z0-9_.${}-]+\.sh/)) {
        w = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        if (w ~ /\$\{?[0-9@*#]/) continue   # `$1.sh`: an X.d/ loader, covered by the X.d/ rule instead
        gsub(/\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/, "*", w); gsub(/[${}]/, "", w)
        out = out " " w
      }
      return out
    }
    function flush(   i, r, v, n, a, j) {
      if (cur == "") return
      if (pf) print "P " cur
      for (i = 1; i <= ns; i++) {
        r = srcs[i]
        if (r ~ /^"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?([ \t)]|$)/) {
          v = r; sub(/^"?\$\{?/, "", v); match(v, /^[A-Za-z_][A-Za-z0-9_]*/); v = substr(v, 1, RLENGTH)
          n = split(words(asg[v]), a, " ")
        } else n = split(words(r), a, " ")
        for (j = 1; j <= n; j++) print "E " cur " " a[j]
      }
    }
    FNR == 1 { flush(); cur = FILENAME; pf = 0; ns = 0; split("", srcs); split("", asg); buf = "" }
    /\\$/ { buf = buf substr($0, 1, length($0) - 1) " "; next }
    {
      l = buf $0; buf = ""
      if (l ~ /^[ \t]*#/) next
      sub(/[ \t]#[ \t].*$/, "", l)
      if (l ~ /(^|[;&|({!]|then[ \t]|do[ \t]|else[ \t])[ \t]*set[ \t][^#]*pipefail/ && l !~ /\+o[ \t]+pipefail/) pf = 1
      rest = l
      while (match(rest, /(^|[ \t;&(])[A-Za-z_][A-Za-z0-9_]*=/)) {
        nm = substr(rest, RSTART, RLENGTH - 1); sub(/^[ \t;&(]/, "", nm)
        rest = substr(rest, RSTART + RLENGTH); r = rest
        if (match(r, /;|&&|\|\|/)) r = substr(r, 1, RSTART - 1)   # this assignment only, not the next one
        asg[nm] = asg[nm] " " r
      }
      rest = l
      while (match(rest, /(^|[;&|({!]|then[ \t]|do[ \t]|else[ \t])[ \t]*(\.|source)[ \t]+/)) {
        rest = substr(rest, RSTART + RLENGTH); r = rest
        if (match(r, /;|&&|\|\|/)) r = substr(r, 1, RSTART - 1)
        srcs[++ns] = r
      }
    }
    END { flush() }' "$@" )
  return 0
}

# pipefail_scope <root> <rel...> — prints each <rel> that runs under pipefail: it sets it, or it is
# sourced by a file that does (an X.d/<m>.sh module by X.sh, or a pipefail_edges edge), to a fixed point
pipefail_scope() {
  local root="$1"; shift
  [ "$#" -gt 0 ] || return 0
  { printf 'F %s\n' "$@"; pipefail_edges "$root" "$@"; } | awk '
    function glob2re(g) { gsub(/[.]/, "\\.", g); gsub(/[*]/, "[^/]*", g); return "^" g "$" }
    $1 == "F" { n++; f[n] = $2; b = $2; sub(/.*\//, "", b); base[n] = b
                if ($2 ~ /\.d\/[^\/]*\.sh$/) { p = $2; sub(/\.d\/[^\/]*\.sh$/, ".sh", p); nd++; ds[nd] = p; dt[nd] = $2 }
                next }
    $1 == "P" { on[$2] = 1; next }
    $1 == "E" { ne++; es[ne] = $2; eg[ne] = glob2re($3); next }
    END {
      ch = 1   # a while, not do…while: test-no-fixed-sleep-race.sh counts a line-start `do` as a shell loop
      while (ch) {
        ch = 0
        for (k = 1; k <= ne; k++) if (es[k] in on) for (i = 1; i <= n; i++) if (!(f[i] in on) && base[i] ~ eg[k]) { on[f[i]] = 1; ch = 1 }
        for (k = 1; k <= nd; k++) if ((ds[k] in on) && !(dt[k] in on)) { on[dt[k]] = 1; ch = 1 }
      }
      for (i = 1; i <= n; i++) if (f[i] in on) print f[i]
    }'
}

# ratchet <root> <baseline> <count_fn> <rel...> — compares each file's <count_fn> count (count_writer
# for rule 2, count_prod for rule 3) against <baseline> (`count path` lines) and prints ONE tagged line
# per violation, nothing when clean:
#   OVER <rel> <got> <base>   more occurrences than the baseline allows (an unlisted file has 0)
#   UNDER <rel> <got> <base>  fewer than the baseline — the baseline must be lowered to match
#   STALE <rel>               a baseline entry whose file is not among <rel...>
# A function, so the controls below drive every branch on fixtures — the live tree alone sits at
# got == base everywhere and would leave all three dead.
ratchet() {
  local root="$1" baseline="$2" count_fn="$3" rel got base seen=""
  shift 3
  for rel in "$@"; do
    got="$("$count_fn" "$root/$rel")"
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
rout="$(ratchet "$RT" "$RB" count_writer over.sh under.sh equal.sh new.sh clean.sh sub/equal.sh)"
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
[ -z "$(ratchet "$RT" '1 equal.sh' count_writer equal.sh clean.sh)" ] && ok "ratchet is silent when every count equals its baseline" \
  || no "ratchet flags a tree that matches its baseline: $(ratchet "$RT" '1 equal.sh' count_writer equal.sh clean.sh)"

echo "== rule 3 detector controls: a non-test script under pipefail, its own or inherited =="
# A mirror tree of production scripts. Every path is relative to the mirror root, as in the live run.
PR3="$T/prod"; S3="$PR3/loomwright/scripts"; mkdir -p "$S3/entry.d" "$S3/lone.d"
# the exact wave-7 L22 shape: a MODULE that never sets pipefail, sourced by an entry point that does
{ echo 'set -uo pipefail'; echo '_src() { . "$HERE/entry.d/$1.sh"; }'; echo '_src launch'; } > "$S3/entry.sh"
{ echo 'lanes_run_wrapper() {'
  printf '  if ! tail -c +"$((off + 1))" "$log" 2>/dev/null %s grep -q %s; then\n' "$P" "'\"type\": *\"result\"'"
  echo '    : > "$died"'; echo '  fi'; echo '}'; } > "$S3/entry.d/launch.sh"
# a planted violation in a script that sets pipefail itself
{ echo 'set -euo pipefail'; printf 'if git log --oneline %s grep -qF x; then :; fi\n' "$P"; } > "$S3/planted.sh"
# the sanctioned form, and a builtin writer (rule 2's), in a pipefail script — neither is rule 3's
{ echo 'set -uo pipefail'; echo 'grep -q y < <(tail -n 5 "$f") && echo hit'
  printf 'printf "%%s" "$x" %s grep -q y\n' "$P"; } > "$S3/procsub.sh"
# a literal `. x.sh` source, a `. "$VAR"` source resolved through its assignment, a glob-named source
# (provider-$NAME.sh), and a two-hop chain — all sourced, directly or not, by pipefail scripts
{ echo 'set -o pipefail'; echo '. "$HERE/lib-literal.sh"'; echo 'LIB="${OVERRIDE:-$HERE/lib-var.sh}"'
  echo '[ -r "$LIB" ] && . "$LIB"'; echo 'PF="$HERE/provider-$NAME.sh"'; echo '. "$PF"'
  echo 'A="$HERE/lib-a.sh"; B="$HERE/lib-b.sh"'; echo '. "$A"'; } > "$S3/sourcer.sh"
{ echo '. "$(dirname "$0")/lib-hop2.sh"'; printf 'cat "$f" %s grep -q a\n' "$P"; } > "$S3/lib-literal.sh"
printf 'jq -r .x "$f" %s grep -qx true\n' "$P" > "$S3/lib-var.sh"
printf 'cut -f1 "$f" %s grep -qxF -- k\n' "$P" > "$S3/provider-claude.sh"
printf 'sort "$f" %s grep -qF z\n' "$P" > "$S3/lib-hop2.sh"
: > "$S3/lib-a.sh"; : > "$S3/lib-b.sh"   # only A is sourced; B, assigned on the same line, is not
# NOT under pipefail: a script that never sets it (one that only names it in a comment or a string),
# a lib only it sources, a module of an entry point without pipefail, and a `set +o pipefail` line
{ echo '# deliberately no pipefail here'; echo 'echo "set -uo pipefail" > "$gen"'; echo '. "$HERE/lib-lone.sh"'
  printf 'tail -n 5 "$f" %s grep -q a\n' "$P"; } > "$S3/nopf.sh"
printf 'tail -n 5 "$f" %s grep -q a\n' "$P" > "$S3/lib-lone.sh"
echo ': no pipefail' > "$S3/lone.sh"; printf 'tail -n 5 "$f" %s grep -q a\n' "$P" > "$S3/lone.d/mod.sh"
{ echo 'set +o pipefail'; printf 'tail -n 5 "$f" %s grep -q a\n' "$P"; } > "$S3/plusopf.sh"
r3=(loomwright/scripts/entry.sh loomwright/scripts/entry.d/launch.sh loomwright/scripts/planted.sh
    loomwright/scripts/procsub.sh loomwright/scripts/sourcer.sh loomwright/scripts/lib-literal.sh
    loomwright/scripts/lib-var.sh loomwright/scripts/provider-claude.sh loomwright/scripts/lib-hop2.sh
    loomwright/scripts/lib-a.sh loomwright/scripts/lib-b.sh
    loomwright/scripts/nopf.sh loomwright/scripts/lib-lone.sh loomwright/scripts/lone.sh
    loomwright/scripts/lone.d/mod.sh loomwright/scripts/plusopf.sh)
scope3="$(pipefail_scope "$PR3" "${r3[@]}")"
in_scope() { grep -qxF -- "loomwright/scripts/$1" <<<"$scope3"; }
for c in entry.sh entry.d/launch.sh planted.sh procsub.sh sourcer.sh lib-literal.sh lib-var.sh provider-claude.sh lib-hop2.sh lib-a.sh; do
  in_scope "$c" && ok "rule 3 scope includes $c" || no "rule 3 scope MISSES $c — scope: $(tr '\n' ' ' <<<"$scope3")"
done
for c in nopf.sh lib-lone.sh lone.sh lone.d/mod.sh plusopf.sh lib-b.sh; do
  in_scope "$c" && no "rule 3 scope wrongly includes $c (it never runs under pipefail)" || ok "rule 3 scope excludes $c"
done
scope3_a=(); while IFS= read -r rel; do scope3_a+=("$rel"); done <<<"$scope3"
r3out="$(ratchet "$PR3" '' count_prod "${scope3_a[@]}")"
want3='OVER loomwright/scripts/entry.d/launch.sh 1 0
OVER loomwright/scripts/planted.sh 1 0
OVER loomwright/scripts/lib-literal.sh 1 0
OVER loomwright/scripts/lib-var.sh 1 0
OVER loomwright/scripts/provider-claude.sh 1 0
OVER loomwright/scripts/lib-hop2.sh 1 0'
[ "$r3out" = "$want3" ] && ok "rule 3 flags the L22 module, the planted site and every sourced lib — not procsub.sh's sanctioned form or its builtin writer" \
  || no "rule 3 ratchet output wrong — want:
$want3
got:
$r3out"
[ "$(count_writer "$S3/procsub.sh")" = "1" ] && ok "the builtin writer in procsub.sh stays rule 2's (counted there once)" \
  || no "count_writer misses the writer in procsub.sh: $(count_writer "$S3/procsub.sh")"
# The gap this rule closes: rule 1 never looks at the module (not a test), rule 2 not at tail.
[ -z "$(scan "$S3/entry.d/launch.sh")$(scan_writer "$S3/entry.d/launch.sh")" ] && ok "rules 1 and 2 alone miss the L22 module (the gap)" \
  || no "rule 1 or 2 unexpectedly flags the L22 module — the controls above are stale"

echo "== the suite =="
shopt -s nullglob
# suite_files <root> — sets files=(…) to the rule-1 scan set under <root>: every test file, plus every
# sourced test part (test-<x>.d/*.sh), so test code moved out of a runner is never exempted.
suite_files() {
  files=("$1"/loomwright/scripts/test-*.sh "$1"/loomwright/scripts/test-*.d/*.sh "$1"/loomwright/scripts/adapters/*/test-*.sh "$1"/scripts/test-*.sh)
}
# planted violation in a test PART (no pipefail of its own; its runner sets it) under a mirror root —
# the same scan set must reach it, or moved test code would slip past the gate
PL="$T/mirror/loomwright/scripts"; mkdir -p "$PL/test-planted.d"
{ echo 'set -uo pipefail'; echo '. "$HERE/test-planted.d/01-part.sh"'; } > "$PL/test-planted.sh"
{ printf '%s %s grep -q y && echo hit\n' 'printf "%s" "$x"' "$P"; } > "$PL/test-planted.d/01-part.sh"
suite_files "$T/mirror"
case "$(scan "${files[@]}")" in *"/test-planted.d/01-part.sh:1:"*) ok "a planted violation in a sourced test part (test-*.d/*.sh) IS flagged" ;;
  *) no "a planted violation in a test part was NOT flagged — the scan set or the runner-pipefail rule misses test parts" ;; esac
suite_files "$REPO_ROOT"
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
1 loomwright/scripts/automate-helpers.d/reconcile-status.sh
1 loomwright/scripts/build-loop-evidence.sh
4 loomwright/scripts/dispatch-pr-review.sh
1 loomwright/scripts/notify-click-target.sh
1 loomwright/scripts/reconcile-resume-state.sh
1 loomwright/scripts/resolve-egress-config.sh
1 loomwright/scripts/verify-run.sh
13 loomwright/sdk-spike/test/self-test.sh
1 scripts/check-doc-currency.sh
2 scripts/check-skills-index-sync.sh'
# Tracked AND untracked-but-not-ignored, so a new script is gated before it is ever committed.
all_sh=()
while IFS= read -r rel; do
  [ -f "$REPO_ROOT/$rel" ] && all_sh+=("$rel")
done < <(git -C "$REPO_ROOT" ls-files -co --exclude-standard -- '*.sh' 2>/dev/null)
[ "${#all_sh[@]}" -gt 100 ] && ok "rule 2 scanned ${#all_sh[@]} shell scripts" \
  || no "rule 2 found only ${#all_sh[@]} shell scripts (git ls-files failed?) — the scan set is wrong"
rhits="$(ratchet "$REPO_ROOT" "$WRITER_BASELINE" count_writer "${all_sh[@]}")"
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

echo "== rule 3 over every non-test script under pipefail (ratchet) =="
# PROD_BASELINE — pre-existing rule-3 sites, `count path`. Empty: every site was rewritten when the rule
# landed. Never add a path — rewrite the new site as `grep -q PAT < <(producer)` instead.
PROD_BASELINE=''
# rule 1's scan set (suite_files) is excluded, so no file is under two rules' ratchets
prod_sh=()
while IFS= read -r rel; do prod_sh+=("$rel"); done < <(printf '%s\n' "${all_sh[@]}" \
  | grep -vE '^(loomwright/scripts/test-[^/]*\.sh|loomwright/scripts/test-[^/]*\.d/[^/]*\.sh|loomwright/scripts/adapters/[^/]*/test-[^/]*\.sh|scripts/test-[^/]*\.sh)$')
[ "${#prod_sh[@]}" -lt "${#all_sh[@]}" ] && [ "${#prod_sh[@]}" -gt 100 ] && ok "rule 3 candidates: ${#prod_sh[@]} non-test shell scripts" \
  || no "rule 3 candidate set is wrong (${#prod_sh[@]} of ${#all_sh[@]})"
scope_live=()
while IFS= read -r rel; do scope_live+=("$rel"); done < <(pipefail_scope "$REPO_ROOT" "${prod_sh[@]}")
# the live L22 entry point and its module must be in scope, or the scope rules have rotted
case " ${scope_live[*]} " in *" loomwright/scripts/automate-lanes.d/launch.sh "*)
  ok "rule 3 scanned ${#scope_live[@]} scripts under pipefail, automate-lanes.d/launch.sh among them" ;;
  *) no "rule 3 scope misses automate-lanes.d/launch.sh — got ${#scope_live[@]} files" ;; esac
phits="$(ratchet "$REPO_ROOT" "$PROD_BASELINE" count_prod "${scope_live[@]}")"
if [ -z "$phits" ]; then
  ok "no non-test script pipes into grep -q under pipefail beyond the baseline"
else
  while read -r kind rel got base; do
    case "$kind" in
      OVER)  no "$rel: $got pipe(s) into grep -q under pipefail, baseline $base — rewrite as: grep -q PAT < <(producer)"
             scan_prod "$REPO_ROOT/$rel" | sed "s|^$REPO_ROOT/|    |" ;;
      UNDER) no "$rel: $got pipe(s) into grep -q under pipefail, below baseline $base — lower PROD_BASELINE to $got" ;;
      STALE) no "PROD_BASELINE lists $rel, which no longer exists or no longer runs under pipefail — drop the entry" ;;
    esac
  done <<<"$phits"
fi

echo
echo "test-no-pipefail-grep-q: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
