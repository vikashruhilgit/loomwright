#!/usr/bin/env bash
# run-self-tests: early
# (ci-local.sh early phase: deterministic, 9 s alone on 2026-10-09 — a stale --help golden fails the run in seconds)
# test-automate-helpers-dispatch.sh — self-tests for the automate-helpers.sh family-file
# split (parallel-automate/11). Runs against the REAL dispatcher (never the single-file
# bundle test-automate-helpers.sh uses), in temp dirs only. UNCOUNTED by the doc-currency gate.
#
# Covers:
#   1. every function arm of the dispatcher's `case` table names a function that is defined
#      once the dispatcher is sourced, and invoking it (no args, empty stdin, empty temp cwd,
#      failing git/gh stubs on PATH) never prints `unknown subcommand`; the sibling exec arms
#      (automate-trail.sh / automate-dismissed.sh) likewise never print it.
#   2. a stray file in automate-helpers.d/ is never sourced (names are listed, never globbed).
#   3. mutant (a): a scripts-dir copy with ONE family file removed (each family in turn) ⇒ the
#      dispatcher exits non-zero naming that file; an unreadable family file likewise.
#   4. mutant (b): a family copy with the case-table function it holds renamed (each family in
#      turn) ⇒ check 1 FAILS on that copy. Every mutant is gated on non-empty + differs + bash -n.
#   5. the loader block (_ah_source / _ah_bundle / _ah_usage) carries no `#   <lower>` line (the
#      --help filter), and the real dispatcher's --help / -h / no-arg stdout equals the ordered
#      concatenation of the per-segment fixtures fixtures/automate-helpers-help/<segment>.golden
#      (SEGMENTS below, then incidental.golden) byte-for-byte (exit 0, empty stderr); the fixture
#      dir holds exactly those files. Needs no git history, so it never skips. Mutation controls:
#      the fixture set minus one help line must fail, and a family copy with its `#:  ` usage block
#      removed (each family in turn) must change --help and fail.
#      ADDING A SUBCOMMAND? Add its `#:  ` usage line to the file that implements it (a family's
#      block in automate-helpers.d/<name>.sh, or the dispatcher's `#:@` group) and the same line,
#      `#:  ` replaced by two spaces, at the same position in that segment's <segment>.golden.
#      A NEW FAMILY also needs its name in the dispatcher's _AH_HELP_SEGMENTS and in SEGMENTS here.
#   6. each remaining _ah_usage fail-closed branch (segment marker inside a family, usage line
#      outside any segment, malformed `#:` line, segment listed twice, usage lines in an unlisted
#      segment) — one gated mutant copy each ⇒ --help exits non-zero, prints NOTHING on stdout, and
#      names the reason on stderr.
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/automate-helpers.sh"
FAM_DIR="$HERE/automate-helpers.d"
# Per-segment golden --help fixtures (split by parallel-automate/22 from the single golden seeded
# from the last single-file automate-helpers.sh, a14db34). SEGMENTS is the EXPECTED order — the
# test's own copy, so a reordered _AH_HELP_SEGMENTS in the dispatcher fails check 5.
GOLDEN_DIR="$HERE/fixtures/automate-helpers-help"
SEGMENTS="config runfile intake resume hdr-gate learning escalation reconcile-status hdr-trail meta plan-waves hdr-lanes incidental"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
no()   { echo "  FAIL: $1"; fail=$((fail+1)); }
skp()  { echo "  SKIP: $1"; skip=$((skip+1)); }

T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT

# failing git/gh stubs, so no arm can reach a real remote or repo
mkdir -p "$T/bin" "$T/cwd"
for s in git gh; do printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/$s"; chmod +x "$T/bin/$s"; done

# function arms: `    <sub>) <fn> "$@" ;;` inside main's case table
fn_arms() {
  awk '/^main\(\) \{$/ { m = 1 } m && /^    [a-z][a-z-]*\)[ ]+[a-z_]+ "\$@" ;;$/ {
         sub(/^    /, ""); sub(/\)/, " "); print $1, $2 } m && /^}$/ { exit }' "$1"
}
# exec arms: `    a|b|c) exec bash "$(dirname "$0")/<sibling>" …` — one sub per line
exec_arms() {
  awk '/^main\(\) \{$/ { m = 1 } m && /^    [a-z][a-z|-]*\)[ ]+exec bash / {
         s = $1; sub(/\)$/, "", s); n = split(s, a, "|"); for (i = 1; i <= n; i++) print a[i] }
       m && /^}$/ { exit }' "$1"
}
# functions defined once <dispatcher> is sourced (main runs with no args → --help, discarded)
defined_fns() {
  bash -c '. "$0" >/dev/null 2>&1; declare -F' "$1" 2>/dev/null | awk '{ print $3 }'
}
run_sub() {  # run_sub <dispatcher> <sub> — combined output of a no-arg invocation
  ( cd "$T/cwd" && PATH="$T/bin:$PATH" bash "$1" "$2" </dev/null 2>&1 )
}
# check_dispatch <dispatcher> — prints one line per broken function arm; empty ⇒ all reach
check_dispatch() {
  local d="$1" defs sub fn out
  defs="$(defined_fns "$d")"
  while read -r sub fn; do
    [ -n "$sub" ] || continue
    grep -qxF "$fn" <<<"$defs" || { echo "$sub: function $fn not defined after sourcing"; continue; }
    out="$(run_sub "$d" "$sub")"
    case "$out" in
      *"unknown subcommand"*) echo "$sub: unknown subcommand" ;;
      *"command not found"*) echo "$sub: $fn not found at call time" ;;
    esac
  done <<<"$(fn_arms "$d")"
}

echo "== 1. every case-table arm reaches its function (real dispatcher)"
ARMS="$(fn_arms "$D")"; NARMS="$(grep -c . <<<"$ARMS")"
if [ "$NARMS" -ge 20 ]; then ok "case table parsed: $NARMS function arms"; else no "case table parse found only $NARMS function arms"; fi
BROKEN="$(check_dispatch "$D")"
if [ -z "$BROKEN" ]; then ok "all $NARMS function arms: function defined after sourcing, invocation never 'unknown subcommand'"
else no "broken arms: $(tr '\n' ';' <<<"$BROKEN")"; fi
EXECS="$(exec_arms "$D")"; NEX="$(grep -c . <<<"$EXECS")"
EXBAD=""
while read -r sub; do
  [ -n "$sub" ] || continue
  case "$(run_sub "$D" "$sub")" in *"automate-helpers: unknown subcommand"*) EXBAD="$EXBAD $sub" ;; esac
done <<<"$EXECS"
if [ "$NEX" -ge 9 ] && [ -z "$EXBAD" ]; then ok "all $NEX sibling exec arms routed (never the dispatcher's 'unknown subcommand')"
else no "exec arms: count=$NEX unrouted=[$EXBAD]"; fi
PC="$(run_sub "$D" no-such-subcommand)"
if grep -q "unknown subcommand: no-such-subcommand" <<<"$PC"; then
  ok "positive control: an unlisted subcommand IS reported unknown (the probe can see the failure)"
else no "positive control: an unlisted subcommand was not reported unknown"; fi

# Every family the dispatcher sources, in source order.
FAMS="$(sed -n 's/^_ah_source \([a-z][a-z-]*\)$/\1/p' "$D")"
NFAM="$(grep -c . <<<"$FAMS")"
if [ "$NFAM" -ge 8 ]; then ok "$NFAM family files sourced by name: $(tr '\n' ' ' <<<"$FAMS")"; else no "only $NFAM _ah_source lines found"; fi

# mk_copy — a fresh scripts-dir copy holding the dispatcher + its family dir; prints its path
mk_copy() {
  local c; c="$(mktemp -d "$T/copy.XXXXXX")"
  cp "$D" "$c/automate-helpers.sh"; cp -R "$FAM_DIR" "$c/automate-helpers.d"
  echo "$c/automate-helpers.sh"
}

echo "== 2. no glob: a stray family file is never sourced"
C="$(mk_copy)"
printf 'echo STRAY_FAMILY_SOURCED\n' > "$(dirname "$C")/automate-helpers.d/zz-stray.sh"
SO="$(bash "$C" --help 2>&1)"
if [ -n "$SO" ] && ! grep -q STRAY_FAMILY_SOURCED <<<"$SO"; then ok "stray automate-helpers.d/zz-stray.sh is not sourced"
else no "a stray family file was sourced (glob?)"; fi

echo "== 3. mutant (a): a missing / unreadable family file fails CLOSED, naming it"
while read -r f; do
  [ -n "$f" ] || continue
  C="$(mk_copy)"; rm -f "$(dirname "$C")/automate-helpers.d/$f.sh"
  if [ ! -s "$C" ] || [ -e "$(dirname "$C")/automate-helpers.d/$f.sh" ] || ! bash -n "$C" \
     || diff -rq "$FAM_DIR" "$(dirname "$C")/automate-helpers.d" >/dev/null 2>&1; then
    no "mutant (a) $f: not built (copy empty, file still present, bash -n failed, or no difference)"; continue
  fi
  err="$(bash "$C" --help 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && grep -qF "missing family file: automate-helpers.d/$f.sh" <<<"$err"; then
    ok "mutant (a) $f.sh removed ⇒ exit $rc naming it"
  else no "mutant (a) $f.sh removed ⇒ rc=$rc err='$err' (expected non-zero naming the file)"; fi
done <<<"$FAMS"
if [ "$(id -u)" = 0 ]; then
  skp "unreadable family file: running as root, chmod 000 does not deny reads"
else
  f="$(head -1 <<<"$FAMS")"; C="$(mk_copy)"; chmod 000 "$(dirname "$C")/automate-helpers.d/$f.sh"
  err="$(bash "$C" --help 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && grep -qF "missing family file: automate-helpers.d/$f.sh" <<<"$err"; then
    ok "unreadable $f.sh ⇒ exit $rc naming it"
  else no "unreadable $f.sh ⇒ rc=$rc err='$err'"; fi
fi

echo "== 4. mutant (b): a family function renamed ⇒ the dispatch check fails"
while read -r f; do
  [ -n "$f" ] || continue
  # the first case-table function this family defines
  fn=""
  while read -r _sub cand; do
    if grep -q "^$cand() {" "$FAM_DIR/$f.sh"; then fn="$cand"; break; fi
  done <<<"$ARMS"
  if [ -z "$fn" ]; then no "mutant (b) $f: no case-table function found in the family"; continue; fi
  C="$(mk_copy)"; M="$(dirname "$C")/automate-helpers.d/$f.sh"
  sed "s/^$fn() {/${fn}_renamed() {/" "$FAM_DIR/$f.sh" > "$M"
  if [ ! -s "$M" ] || cmp -s "$FAM_DIR/$f.sh" "$M" || ! bash -n "$M"; then
    no "mutant (b) $f: not built (empty, sed matched nothing, or bash -n failed)"; continue
  fi
  MB="$(check_dispatch "$C")"
  if grep -q "function $fn not defined" <<<"$MB"; then ok "mutant (b) $f.sh: $fn renamed ⇒ dispatch check fails ($(grep -c . <<<"$MB") arm(s))"
  else no "mutant (b) $f.sh: $fn renamed but the dispatch check stayed green"; fi
done <<<"$FAMS"

echo "== 5. --help / -h / no-arg output equals the ordered per-segment golden fixtures"
LOADER="$(awk '/^# >>> family-file loader/,/^# <<< family-file loader/' "$D")"
if [ -n "$LOADER" ] && grep -q '^_ah_usage() {$' <<<"$LOADER" && ! grep -qE '^#   [a-z]' <<<"$LOADER"; then
  ok "loader block (_ah_source/_ah_bundle/_ah_usage) carries no '#   <lower>' line the --help filter could pick up"
else no "loader block missing, without _ah_usage, or it carries a '#   <lower>' line that would leak into --help"; fi
# help_matches <dispatcher> <arg> <golden> — stdout == golden byte-for-byte (files + cmp, so
# trailing newlines count), stderr empty, exit 0.
help_matches() {
  ( cd "$T/cwd" && bash "$1" $2 >"$T/ho" 2>"$T/he" ); local rc=$?
  [ "$rc" -eq 0 ] && [ -s "$T/ho" ] && [ ! -s "$T/he" ] && cmp -s "$T/ho" "$3"
}
# The fixture dir holds exactly the SEGMENTS fixtures, each non-empty (an unlisted fixture is a
# segment this test would never compare).
GBAD=""
for sg in $SEGMENTS; do [ -s "$GOLDEN_DIR/$sg.golden" ] || GBAD="$GBAD missing:$sg"; done
for gf in "$GOLDEN_DIR"/*; do
  [ -e "$gf" ] || continue
  case " $SEGMENTS " in *" $(basename "$gf" .golden) "*) [ "${gf%.golden}" != "$gf" ] && continue ;; esac
  GBAD="$GBAD unlisted:$(basename "$gf")"
done
GOLDEN="$T/help.golden"
: >"$GOLDEN"; for sg in $SEGMENTS; do cat "$GOLDEN_DIR/$sg.golden" >>"$GOLDEN" 2>/dev/null; done
if [ -n "$GBAD" ] || [ ! -s "$GOLDEN" ]; then
  no "per-segment help fixtures under $GOLDEN_DIR do not match SEGMENTS:$GBAD"
else
  ok "fixture dir holds exactly the $(wc -w <<<"$SEGMENTS" | tr -d ' ') SEGMENTS fixtures, each non-empty"
  for a in --help -h ""; do
    if help_matches "$D" "$a" "$GOLDEN"; then
      ok "'${a:-<no-arg>}' output equals the ordered segment fixtures byte-for-byte ($(grep -c . "$GOLDEN") lines, exit 0, empty stderr)"
    else no "'${a:-<no-arg>}' output differs from the ordered segment fixtures — added a subcommand? update its <segment>.golden (see header)"; fi
  done
  # Mutation control 1: the fixture set with ONE help line removed (first line of the first
  # segment's fixture) must make the comparison fail.
  MG="$T/help.golden.mutant"
  first="$(set -- $SEGMENTS; echo "$1")"
  : >"$MG"; for sg in $SEGMENTS; do
    if [ "$sg" = "$first" ]; then sed '1d' "$GOLDEN_DIR/$sg.golden" >>"$MG"; else cat "$GOLDEN_DIR/$sg.golden" >>"$MG"; fi
  done
  if [ ! -s "$MG" ] || cmp -s "$GOLDEN" "$MG" \
     || [ "$(wc -l <"$MG")" -ne "$(( $(wc -l <"$GOLDEN") - 1 ))" ]; then
    no "fixture-set mutant not built (empty, identical, or not exactly one line shorter)"
  elif help_matches "$D" --help "$MG"; then
    no "fixture-set mutant (one help line removed from $first.golden) still compared equal — the comparison is vacuous"
  else ok "fixture-set mutant (one help line removed from $first.golden) ⇒ the --help comparison fails"; fi
  # Mutation control 2: each family copy with its `#:  ` usage block removed changes --help and
  # fails (the dispatcher's _ah_usage refuses a listed segment with no usage line, exit 1).
  bash "$D" --help >"$T/help.real" 2>/dev/null
  while read -r f; do
    [ -n "$f" ] || continue
    C="$(mk_copy)"; M="$(dirname "$C")/automate-helpers.d/$f.sh"
    grep -v '^#:  ' "$FAM_DIR/$f.sh" > "$M"
    if [ ! -s "$M" ] || cmp -s "$FAM_DIR/$f.sh" "$M" || ! bash -n "$M"; then
      no "usage-block mutant $f: not built (empty, no usage line removed, or bash -n failed)"; continue
    fi
    ( cd "$T/cwd" && bash "$C" --help >"$T/hm" 2>"$T/hme" )
    if help_matches "$C" --help "$GOLDEN" || cmp -s "$T/hm" "$T/help.real"; then
      no "usage-block mutant $f.sh: usage block removed but --help unchanged / still equal to the fixtures"
    elif grep -qF "segment has no usage line: $f" "$T/hme"; then
      ok "usage-block mutant $f.sh: usage block removed ⇒ --help changes and fails, naming the empty segment"
    else no "usage-block mutant $f.sh: --help changed but stderr did not name the empty segment: $(head -1 "$T/hme")"; fi
  done <<<"$FAMS"
fi

echo "== 6. every other _ah_usage fail-closed branch: exit non-zero, EMPTY stdout, the reason on stderr"
# usage_mutant <label> <original> <mutant> <expected stderr substring> — <mutant> lives in a fresh
# mk_copy (its dispatcher is $C); gated on non-empty + differs + bash -n before it is run.
usage_mutant() {
  if [ ! -s "$3" ] || cmp -s "$2" "$3" || ! bash -n "$3"; then
    no "usage mutant ($1): not built (empty, no difference, or bash -n failed)"; return
  fi
  ( cd "$T/cwd" && bash "$C" --help >"$T/um" 2>"$T/ume" ); local rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$T/um" ] && grep -qF "automate-helpers: --help: $4" "$T/ume"; then
    ok "usage mutant ($1) ⇒ exit $rc, empty stdout, stderr names '$4'"
  else no "usage mutant ($1) ⇒ rc=$rc stdout_bytes=$(wc -c <"$T/um" | tr -d ' ') stderr='$(head -1 "$T/ume")' (expected non-zero, empty stdout, '$4')"; fi
}
f1="$(head -1 <<<"$FAMS")"
# (a) a `#:@` segment marker inside a family's markers
C="$(mk_copy)"; M="$(dirname "$C")/automate-helpers.d/$f1.sh"
{ cat "$FAM_DIR/$f1.sh"; echo '#:@ zz-bad'; } >"$M"
usage_mutant "segment marker inside family $f1" "$FAM_DIR/$f1.sh" "$M" "segment marker inside family $f1: #:@ zz-bad"
# (b) a `#:  ` usage line in the dispatcher outside any family and any open `#:@` group
C="$(mk_copy)"
sed '/^_AH_HELP_SEGMENTS=/a\
#:  zz-orphan
' "$D" >"$C"
usage_mutant "usage line outside any segment" "$D" "$C" "usage line outside any segment: #:  zz-orphan"
# (c) any other `#:` line shape
C="$(mk_copy)"
sed '/^_AH_HELP_SEGMENTS=/a\
#:zz-malformed
' "$D" >"$C"
usage_mutant "malformed usage-block line" "$D" "$C" "malformed usage-block line: #:zz-malformed"
# (d) a segment listed twice in _AH_HELP_SEGMENTS
C="$(mk_copy)"
sed "s/^_AH_HELP_SEGMENTS=\"$f1 /_AH_HELP_SEGMENTS=\"$f1 $f1 /" "$D" >"$C"
usage_mutant "segment listed twice" "$D" "$C" "segment listed twice: $f1"
# (e) a segment with usage lines dropped from _AH_HELP_SEGMENTS
C="$(mk_copy)"
sed "s/^_AH_HELP_SEGMENTS=\"$f1 /_AH_HELP_SEGMENTS=\"/" "$D" >"$C"
usage_mutant "usage lines in an unlisted segment" "$D" "$C" "usage lines in an unlisted segment: $f1"

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
