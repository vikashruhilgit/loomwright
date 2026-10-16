#!/usr/bin/env bash
# test-automate-trail-modules.sh — self-tests for the automate-trail.sh module split
# (automate-speed/19, a move-only split into automate-trail.d/). Runs against the REAL entry
# point (never the single-file bundle test-automate-trail.sh reads for its mutants), in temp
# dirs only. Modelled on test-automate-helpers-dispatch.sh.
#
# Covers:
#   1. every function arm of main's `case` table names a function defined by exactly one
#      module, and invoking the arm (no args, empty stdin, empty temp cwd, failing git/gh stubs
#      on PATH) prints something and never `unknown subcommand` / `command not found`; every
#      subcommand the header's `# Subcommands:` block documents is routed (never `unknown`).
#   2. `--help`, `-h`, no-arg and an unknown subcommand give the same stdout, stderr and exit
#      code as the last single-file automate-trail.sh (the BASE blob below, read with
#      `git show`; a named SKIP where that commit is not in the clone, e.g. a shallow checkout).
#   3. a stray file in automate-trail.d/ is never sourced (modules are listed, never globbed).
#   4. a copy with ONE module removed (each in turn), or unreadable, exits non-zero with the
#      loader's own message `automate-trail: missing module file: automate-trail.d/<name>.sh`.
#   5. verbatim move: _trail_bundle's output, with the header's Modules map, the module loader
#      block and the source markers removed, equals the BASE blob byte-for-byte except the one
#      --help line (which now greps the bundle) — skipped with 2. A copy with one moved line
#      changed must fail that comparison (gated mutant).
#   6. every module is <= 800 lines, passes `bash -n` (and a 3.x `bash -n` when the host has
#      one); the sourced list and the automate-trail.d/ files are the same set; the header's
#      Modules map names them in source order; neither the map nor the loader block carries a
#      `#   <lower>` line the --help filter would pick up.
# Every mutant is gated on non-empty + differs + bash -n. Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
E="$HERE/automate-trail.sh"
MOD_DIR="$HERE/automate-trail.d"
# The last single-file automate-trail.sh (the split's base commit).
BASE=051553e6c8d757ceac36fd22afe01475bcf2c8bb
BASE_PATH=loomwright/scripts/automate-trail.sh
MISSING_MSG="automate-trail: missing module file: automate-trail.d"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
no()   { echo "  FAIL: $1"; fail=$((fail+1)); }
skp()  { echo "  SKIP: $1"; skip=$((skip+1)); }

T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT

# failing git/gh stubs, so no arm can reach a real remote or repo
mkdir -p "$T/bin" "$T/cwd"
for s in git gh; do printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/$s"; chmod +x "$T/bin/$s"; done

# function arms: `    <sub>) <fn> "$@" ;;` inside main's case table (any spacing after the `)`)
fn_arms() {
  awk '/^main\(\) \{$/ { m = 1 } m && /^    [a-z][a-z-]*\)[ ]+[a-z_]+ "\$@" ;;$/ {
         sub(/^    /, ""); sub(/\)/, " "); print $1, $2 } m && /^}$/ { exit }' "$1"
}
run_sub() {  # run_sub <entry> <args…> — combined output of an invocation in the empty temp cwd
  local e="$1"; shift
  ( cd "$T/cwd" && PATH="$T/bin:$PATH" bash "$e" "$@" </dev/null 2>&1 )
}
# modules sourced by <entry>, in source order
mods_of() { sed -n 's/^_trail_source \([a-z][a-z-]*\)$/\1/p' "$1"; }
# mk_copy — a fresh scripts-dir copy holding the entry point + its module dir; prints its path
mk_copy() {
  local c; c="$(mktemp -d "$T/copy.XXXXXX")"
  cp "$E" "$c/automate-trail.sh"; cp -R "$MOD_DIR" "$c/automate-trail.d"
  echo "$c/automate-trail.sh"
}
# bundle_of <entry> — that entry's own _trail_bundle output (the function evaluated from it)
bundle_of() {
  ( eval "$(awk '/^_trail_bundle\(\) \{$/,/^}$/' "$1")"; _trail_bundle "$1" )
}
# strip_split <bundle-file> — the bundle without the Modules map, the loader block and the markers
strip_split() {
  sed -e '/^# Modules (sourced in this order from automate-trail\.d\/):$/,/^#$/d' \
      -e '/^# >>> module loader /,/^# <<< module loader$/d' \
      -e '/^# >>> automate-trail\.d\/[a-z][a-z-]*\.sh$/d' \
      -e '/^# <<< automate-trail\.d\/[a-z][a-z-]*\.sh$/d' "$1"
}
NEW_HELP="    \"\"|-h|--help)  _trail_bundle | grep -E '^#   [a-z]' | sed 's/^#   /  /' ;;"
OLD_HELP="    \"\"|-h|--help)  grep -E '^#   [a-z]' \"\$0\" | sed 's/^#   /  /' ;;"
# verbatim_ok <entry> — 0 iff <entry>'s stripped bundle, with the one help line put back, equals
# $T/base.sh byte-for-byte and the new help line occurs exactly once.
verbatim_ok() {
  bundle_of "$1" > "$T/vb.bundle" 2>/dev/null && [ -s "$T/vb.bundle" ] || return 1
  strip_split "$T/vb.bundle" > "$T/vb.stripped"
  [ "$(grep -cxF -- "$NEW_HELP" "$T/vb.stripped")" = 1 ] || return 1
  NEW="$NEW_HELP" OLD="$OLD_HELP" awk '$0 == ENVIRON["NEW"] { print ENVIRON["OLD"]; next } { print }' \
    "$T/vb.stripped" > "$T/vb.restored"
  cmp -s "$T/vb.restored" "$T/base.sh"
}

MODS="$(mods_of "$E")"; NMOD="$(grep -c . <<<"$MODS")"

echo "== 1. every case-table arm reaches its function (real entry point)"
ARMS="$(fn_arms "$E")"; NARMS="$(grep -c . <<<"$ARMS")"
if [ "$NARMS" -ge 8 ]; then ok "case table parsed: $NARMS function arms"; else no "case table parse found only $NARMS function arms"; fi
BROKEN=""
while read -r sub fn; do
  [ -n "$sub" ] || continue
  # where the function is defined: exactly one module (listed by name, never globbed)
  ndef=0
  while read -r m; do
    [ -n "$m" ] || continue
    grep -q "^$fn() {" "$MOD_DIR/$m.sh" 2>/dev/null && ndef=$((ndef+1))
  done <<<"$MODS"
  [ "$ndef" = 1 ] || BROKEN="$BROKEN $sub:$fn defined in $ndef module(s);"
  out="$(run_sub "$E" "$sub")"
  case "$out" in
    "") BROKEN="$BROKEN $sub: no output;" ;;
    *"unknown subcommand"*) BROKEN="$BROKEN $sub: unknown subcommand;" ;;
    *"command not found"*) BROKEN="$BROKEN $sub: $fn not found at call time;" ;;
  esac
done <<<"$ARMS"
if [ -z "$BROKEN" ]; then ok "all $NARMS function arms: defined in exactly one module, invocation reaches it (never 'unknown subcommand')"
else no "broken arms:$BROKEN"; fi
# Every subcommand the header's `# Subcommands:` block documents is routed by the case table.
DOC="$(awk '/^# Subcommands:$/ { s = 1; next } s && /^#$/ { exit } s && /^#   [a-z]/ { print $2 }' "$E")"
NDOC="$(grep -c . <<<"$DOC")"; UNROUTED=""
while read -r sub; do
  [ -n "$sub" ] || continue
  case "$(run_sub "$E" "$sub")" in *"unknown subcommand"*) UNROUTED="$UNROUTED $sub" ;; esac
done <<<"$DOC"
if [ "$NDOC" -ge 8 ] && [ -z "$UNROUTED" ]; then ok "all $NDOC subcommands the header documents are routed (never 'unknown subcommand')"
else no "documented subcommands: count=$NDOC unrouted=[$UNROUTED]"; fi
PC="$(run_sub "$E" no-such-subcommand)"
if grep -qF "automate-trail: unknown subcommand: no-such-subcommand" <<<"$PC"; then
  ok "positive control: an unlisted subcommand IS reported unknown (the probe can see the failure)"
else no "positive control: an unlisted subcommand was not reported unknown"; fi

echo "== 2. --help / -h / no-arg / unknown equal the single-file base ($BASE)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
HAVE_BASE=0
if [ -n "$REPO" ] && git -C "$REPO" cat-file -e "$BASE:$BASE_PATH" 2>/dev/null \
   && git -C "$REPO" show "$BASE:$BASE_PATH" > "$T/base.sh" 2>/dev/null && [ -s "$T/base.sh" ]; then
  HAVE_BASE=1
fi
if [ "$HAVE_BASE" = 0 ]; then
  skp "base blob $BASE:$BASE_PATH not in this clone (shallow checkout?) — the --help/unknown equality legs are not run"
else
  mkdir -p "$T/basedir"; cp "$T/base.sh" "$T/basedir/automate-trail.sh"
  for a in --help -h "" no-such-subcommand; do
    ( cd "$T/cwd" && bash "$T/basedir/automate-trail.sh" $a >"$T/bo" 2>"$T/be" ); brc=$?
    ( cd "$T/cwd" && bash "$E" $a >"$T/no" 2>"$T/ne" ); nrc=$?
    if [ "$brc" = "$nrc" ] && cmp -s "$T/bo" "$T/no" && cmp -s "$T/be" "$T/ne" && { [ -s "$T/no" ] || [ -s "$T/ne" ]; }; then
      ok "'${a:-<no-arg>}': stdout ($(wc -l <"$T/no" | tr -d ' ') lines), stderr and exit $nrc equal the base"
    else no "'${a:-<no-arg>}': differs from the base (rc $brc vs $nrc; stdout $(wc -l <"$T/bo" | tr -d ' ') vs $(wc -l <"$T/no" | tr -d ' ') lines; stderr '$(head -1 "$T/be")' vs '$(head -1 "$T/ne")')"; fi
  done
fi

echo "== 3. no glob: a stray module file is never sourced"
C="$(mk_copy)"
printf 'echo STRAY_MODULE_SOURCED\n' > "$(dirname "$C")/automate-trail.d/zz-stray.sh"
SO="$(run_sub "$C" --help) $(run_sub "$C" sidecar-check)"
if [ -n "$SO" ] && ! grep -q STRAY_MODULE_SOURCED <<<"$SO"; then ok "stray automate-trail.d/zz-stray.sh is not sourced"
else no "a stray module file was sourced (glob?)"; fi

echo "== 4. a missing / unreadable module fails CLOSED with the loader's own message"
if [ "$NMOD" -ge 6 ]; then ok "$NMOD modules sourced by name: $(tr '\n' ' ' <<<"$MODS")"; else no "only $NMOD _trail_source lines found"; fi
while read -r m; do
  [ -n "$m" ] || continue
  C="$(mk_copy)"; rm -f "$(dirname "$C")/automate-trail.d/$m.sh"
  if [ ! -s "$C" ] || [ -e "$(dirname "$C")/automate-trail.d/$m.sh" ] || ! bash -n "$C" \
     || diff -rq "$MOD_DIR" "$(dirname "$C")/automate-trail.d" >/dev/null 2>&1; then
    no "missing-module mutant $m: not built (copy empty, file still present, bash -n failed, or no difference)"; continue
  fi
  err="$( ( cd "$T/cwd" && bash "$C" sidecar-check ) 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" <<<"$err"; then
    ok "$m.sh removed ⇒ exit $rc, '$MISSING_MSG/$m.sh'"
  else no "$m.sh removed ⇒ rc=$rc err='$err' (expected non-zero and '$MISSING_MSG/$m.sh')"; fi
done <<<"$MODS"
if [ "$(id -u)" = 0 ]; then
  skp "unreadable module: running as root, chmod 000 does not deny reads"
else
  m="$(head -1 <<<"$MODS")"; C="$(mk_copy)"; chmod 000 "$(dirname "$C")/automate-trail.d/$m.sh"
  err="$( ( cd "$T/cwd" && bash "$C" --help ) 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" <<<"$err"; then ok "unreadable $m.sh ⇒ exit $rc naming it"
  else no "unreadable $m.sh ⇒ rc=$rc err='$err'"; fi
fi
m="$(tail -1 <<<"$MODS")"; C="$(mk_copy)"; rm -f "$(dirname "$C")/automate-trail.d/$m.sh"
err="$(bundle_of "$C" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" <<<"$err"; then ok "_trail_bundle on a copy without $m.sh ⇒ exit $rc naming it"
else no "_trail_bundle without $m.sh ⇒ rc=$rc err='$err'"; fi

echo "== 5. verbatim move: the stripped bundle equals the base except the one --help line"
if [ "$HAVE_BASE" = 0 ]; then
  skp "base blob not in this clone — the verbatim-move legs are not run"
else
  if verbatim_ok "$E"; then
    ok "bundle minus the Modules map, loader block and markers == $BASE:$BASE_PATH (only the --help input differs)"
  else no "bundle differs from the base beyond the --help line: $(diff "$T/base.sh" "$T/vb.restored" 2>/dev/null | head -4 | tr '\n' '|')"; fi
  # Mutation control: one moved line changed (a trailing space on the first line of the last module).
  m="$(tail -1 <<<"$MODS")"; C="$(mk_copy)"; M="$(dirname "$C")/automate-trail.d/$m.sh"
  sed '1s/$/ /' "$MOD_DIR/$m.sh" > "$M"
  if [ ! -s "$M" ] || cmp -s "$MOD_DIR/$m.sh" "$M" || ! bash -n "$M"; then
    no "verbatim mutant ($m.sh): not built (empty, sed matched nothing, or bash -n failed)"
  elif verbatim_ok "$C"; then
    no "verbatim mutant ($m.sh, one moved line changed) still compared equal — the comparison is vacuous"
  else ok "verbatim mutant ($m.sh, one moved line changed) ⇒ the comparison fails"; fi
fi

echo "== 6. module shape: size, parse, listed set, header map, help-filter hygiene"
B32=""
for cand in /bin/bash /usr/local/bin/bash3 /opt/bash3/bin/bash; do
  [ -x "$cand" ] || continue
  [ "$("$cand" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)" = "3" ] && { B32="$cand"; break; }
done
SHAPE=""
while read -r m; do
  [ -n "$m" ] || continue
  f="$MOD_DIR/$m.sh"
  [ -s "$f" ] || { SHAPE="$SHAPE $m: missing/empty;"; continue; }
  n="$(wc -l <"$f" | tr -d ' ')"
  [ "$n" -le 800 ] || SHAPE="$SHAPE $m: $n lines > 800;"
  bash -n "$f" 2>/dev/null || SHAPE="$SHAPE $m: bash -n failed;"
  if [ -n "$B32" ]; then "$B32" -n "$f" 2>/dev/null || SHAPE="$SHAPE $m: $B32 -n failed;"; fi
done <<<"$MODS"
if [ -z "$SHAPE" ]; then ok "every module <= 800 lines and parses (bash -n${B32:+, $B32 -n})"
else no "module shape:$SHAPE"; fi
ONDISK="$(cd "$MOD_DIR" && for f in *.sh; do [ -e "$f" ] && echo "${f%.sh}"; done | env LC_ALL=C sort)"
if [ "$ONDISK" = "$(env LC_ALL=C sort <<<"$MODS")" ]; then ok "the sourced list and the automate-trail.d/ files are the same set (no dead or missing module)"
else no "sourced [$(tr '\n' ' ' <<<"$MODS")] vs on disk [$(tr '\n' ' ' <<<"$ONDISK")]"; fi
MAP="$(awk '/^# Modules \(sourced in this order from automate-trail\.d\/\):$/ { m = 1; next } m && /^#$/ { exit } m' "$E")"
MAPMODS="$(sed -n 's/^# - \([a-z][a-z-]*\)\.sh: .*/\1/p' <<<"$MAP")"
if [ -n "$MAP" ] && [ "$MAPMODS" = "$MODS" ]; then ok "the header's Modules map names every module, in source order"
else no "Modules map [$(tr '\n' ' ' <<<"$MAPMODS")] vs sourced [$(tr '\n' ' ' <<<"$MODS")]"; fi
LOADER="$(awk '/^# >>> module loader /,/^# <<< module loader$/' "$E")"
if [ -n "$LOADER" ] && grep -q '^_trail_bundle() {$' <<<"$LOADER" \
   && ! grep -qE '^#   [a-z]' <<<"$LOADER" && ! grep -qE '^#   [a-z]' <<<"$MAP"; then
  ok "neither the loader block nor the Modules map carries a '#   <lower>' line the --help filter could pick up"
else no "loader block missing / without _trail_bundle, or it or the map carries a '#   <lower>' line"; fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
