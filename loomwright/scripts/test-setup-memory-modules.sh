#!/usr/bin/env bash
# test-setup-memory-modules.sh — self-tests for the setup-memory.sh module split
# (automate-speed/20, a move-only split into setup-memory.d/). Runs against the REAL entry point
# (never the single-file bundle test-setup-memory.sh reads for its mutants), in temp dirs only,
# with HOME relocated to a temp dir. Modelled on test-automate-trail-modules.sh.
#
# Covers:
#   1. every subcommand the header's `# Usage:` block documents (bar valid-branch, which is
#      answered before the dispatch) has an arm in the final `case "$SUBCMD" in` table whose
#      do_<name> function is defined by exactly one module, and invoking it on a fixture repo
#      prints something that is NOT the usage text (the `*) usage` branch); a positive control
#      shows an unknown subcommand does reach usage. Under a bash 3.x on the host (macOS
#      /bin/bash), `mode` and `check` print the same as under `bash`.
#   2. `--help`, `-h`, no-arg, an unknown subcommand, `valid-branch` (accepted, refused, missing
#      name) and every dispatch arm on an identical fresh fixture give the same stdout, stderr
#      and exit code as the last single-file setup-memory.sh (the BASE blob below, read with
#      `git show`; a named SKIP where that commit is not in the clone, e.g. a shallow checkout).
#   3. a stray file in setup-memory.d/ is never sourced (modules are listed, never globbed).
#   4. a copy with ONE module removed (each in turn), unreadable, or emptied, exits non-zero with
#      the loader's own message `setup-memory: missing module file: setup-memory.d/<name>.sh`,
#      and so does _sm_bundle on a copy without a module.
#   5. verbatim move: _sm_bundle's output, with the Modules map, the module loader block, the
#      source markers and every line ending `# cpl-guard` (the allowlist writer's physical-path
#      containment guard, added after the split — it is the one sanctioned addition to the moved
#      text) removed, equals the BASE blob byte-for-byte — skipped with 2. A copy with one moved
#      line changed must fail that comparison (gated mutant).
#   6. every module is <= 800 lines, passes `bash -n` (and a 3.x `bash -n` when the host has
#      one); the sourced list and the setup-memory.d/ files are the same set; the Modules map
#      names them in source order; `usage` and apply_readiness_event (both resolve a path through
#      ${BASH_SOURCE[0]}) are defined in the entry and in no module.
# Every mutant is gated on non-empty + differs + bash -n. Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
E="$HERE/setup-memory.sh"
MOD_DIR="$HERE/setup-memory.d"
# The last single-file setup-memory.sh (the split's base commit).
BASE=a8819a38100d77fbeddc2ff1a56963e91f172a5d
BASE_PATH=loomwright/scripts/setup-memory.sh
MISSING_MSG="setup-memory: missing module file: setup-memory.d"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
no()   { echo "  FAIL: $1"; fail=$((fail+1)); }
skp()  { echo "  SKIP: $1"; skip=$((skip+1)); }

T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"

# a failing gh stub (no arm may reach the network) and a pinned clock for apply's backup name
mkdir -p "$T/bin" "$T/cwd" "$T/home"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/gh"; chmod +x "$T/bin/gh"
printf '#!/bin/sh\necho 20260101-000000\n' > "$T/bin/date"; chmod +x "$T/bin/date"

# fresh_fixture — (re)build the ONE fixture repo at $T/fx: a git repo with an origin, a bare
# `.supervisor/` exclude apply neutralises, and a one-record ledger; the same path every time, so
# two runs against it print the same paths. (No agent-memory exclude: its literal path is a
# vendor-coupling token, and this split adds no reference — check-vendor-coupling.sh.)
FX="$T/fx"
fresh_fixture() {
  rm -rf "$FX"; mkdir -p "$FX/.supervisor/postmortem"
  ( cd "$FX" && git init -q && git config user.email t@t && git config user.name t \
      && git config core.excludesFile /dev/null \
      && git remote add origin https://github.com/acme/widget.git ) >/dev/null 2>&1
  printf 'node_modules/\n.supervisor/\n' > "$FX/.gitignore"
  printf '{"repo":"acme/widget","n":1}\n' > "$FX/.supervisor/postmortem/results.jsonl"
}
# run_e <entry> <args…> — one invocation in the empty temp cwd; stdout → $T/o, stderr → $T/e,
# exit code → RC.
run_e() {
  local e="$1"; shift
  ( cd "$T/cwd" && env HOME="$T/home" PATH="$T/bin:$PATH" bash "$e" "$@" </dev/null >"$T/o" 2>"$T/e" ); RC=$?
}
# arm_args <sub> — the arguments one documented subcommand is invoked with
arm_args() {
  case "$1" in
    consent) echo "--root $FX consent status" ;;
    filter-ledger) echo "--root $FX filter-ledger --ledger $FX/.supervisor/postmortem/results.jsonl" ;;
    *) echo "--root $FX $1" ;;
  esac
}
# modules sourced by <entry>, in source order
mods_of() { sed -n 's/^_sm_source \([a-z][a-z-]*\)$/\1/p' "$1"; }
# mk_copy — a fresh scripts-dir copy holding the entry point + its module dir; prints its path
mk_copy() {
  local c; c="$(mktemp -d "$T/copy.XXXXXX")"
  cp "$E" "$c/setup-memory.sh"; cp -R "$MOD_DIR" "$c/setup-memory.d"
  echo "$c/setup-memory.sh"
}
# bundle_of <entry> — that entry's own _sm_bundle output (the function evaluated from it)
bundle_of() {
  ( eval "$(awk '/^_sm_bundle\(\) \{$/,/^}$/' "$1")"; _sm_bundle "$1" )
}
# strip_split <bundle-file> — the bundle without the Modules map (and the blank line closing it),
# the loader block, the source markers and the `# cpl-guard` lines (containment guard, see check 5)
strip_split() {
  sed -e '/^# Modules (sourced in this order from setup-memory\.d\/):$/,/^$/d' \
      -e '/^# >>> module loader /,/^# <<< module loader$/d' \
      -e '/^# >>> setup-memory\.d\/[a-z][a-z-]*\.sh$/d' \
      -e '/^# <<< setup-memory\.d\/[a-z][a-z-]*\.sh$/d' \
      -e '/# cpl-guard$/d' "$1"
}
# verbatim_ok <entry> — 0 iff <entry>'s stripped bundle equals $T/base.sh byte-for-byte
verbatim_ok() {
  bundle_of "$1" > "$T/vb.bundle" 2>/dev/null && [ -s "$T/vb.bundle" ] || return 1
  strip_split "$T/vb.bundle" > "$T/vb.stripped"
  cmp -s "$T/vb.stripped" "$T/base.sh"
}

MODS="$(mods_of "$E")"; NMOD="$(grep -c . <<<"$MODS")"
run_e "$E" --help; cp "$T/o" "$T/help.out"

echo "== 1. every documented subcommand reaches its function (real entry point)"
# documented subcommands: `#   setup-memory.sh <sub>` lines of the header's Usage block
DOC="$(awk '/^# Usage:$/ { s = 1; next } s && /^#$/ { exit } s && /^#   setup-memory\.sh [a-z]/ { print $3 }' "$E" | awk '!seen[$0]++')"
NDOC="$(grep -c . <<<"$DOC")"
if [ "$NDOC" -ge 7 ]; then ok "header Usage block parsed: $NDOC documented subcommands"; else no "header Usage block parse found only $NDOC subcommands"; fi
# dispatch arms: `  <sub>) <fn> ;;` inside the final `case "$SUBCMD" in`
ARMS="$(awk '/^case "\$SUBCMD" in$/ { m = 1; next } m && /^esac$/ { exit } m && /^  [a-z][a-z-]*\)[ ]+do_[a-z_]+ ;;$/ { sub(/^  /, ""); sub(/\)/, " "); print $1, $2 }' "$E")"
BROKEN=""; NREACH=0
while read -r sub; do
  [ -n "$sub" ] || continue
  [ "$sub" = valid-branch ] && continue   # answered before the dispatch (leg 2 covers it)
  fn="$(awk -v s="$sub" '$1 == s { print $2 }' <<<"$ARMS")"
  if [ -z "$fn" ]; then BROKEN="$BROKEN $sub: no arm in the dispatch;"; continue; fi
  ndef=0
  while read -r m; do
    [ -n "$m" ] || continue
    grep -q "^$fn() {" "$MOD_DIR/$m.sh" 2>/dev/null && ndef=$((ndef+1))
  done <<<"$MODS"
  [ "$ndef" = 1 ] || BROKEN="$BROKEN $sub:$fn defined in $ndef module(s);"
  fresh_fixture
  # shellcheck disable=SC2046
  run_e "$E" $(arm_args "$sub")
  if [ ! -s "$T/o" ] && [ ! -s "$T/e" ]; then BROKEN="$BROKEN $sub: no output;"
  elif cmp -s "$T/o" "$T/help.out"; then BROKEN="$BROKEN $sub: reached usage;"
  elif grep -q 'command not found' "$T/e"; then BROKEN="$BROKEN $sub: $fn not found at call time;"
  else NREACH=$((NREACH+1)); fi
done <<<"$DOC"
if [ -z "$BROKEN" ] && [ "$NREACH" -ge 7 ]; then ok "all $NREACH dispatched subcommands: one arm, function defined in exactly one module, invocation reaches it (never usage)"
else no "broken arms (reached $NREACH):$BROKEN"; fi
fresh_fixture; run_e "$E" --root "$FX" no-such-subcommand
if cmp -s "$T/o" "$T/help.out" && grep -qF "setup-memory: unknown arg 'no-such-subcommand'" "$T/e"; then
  ok "positive control: an unlisted subcommand DOES reach usage (the probe can see the failure)"
else no "positive control: an unlisted subcommand did not reach usage"; fi
B32=""
for cand in /bin/bash /usr/local/bin/bash3 /opt/bash3/bin/bash; do
  [ -x "$cand" ] || continue
  [ "$("$cand" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)" = "3" ] && { B32="$cand"; break; }
done
if [ -z "$B32" ]; then
  skp "no bash 3.x on this host — the bash-3.2 run leg is not run"
else
  B32BAD=""
  for sub in mode check; do
    fresh_fixture; run_e "$E" --root "$FX" "$sub"; cp "$T/o" "$T/o5"; cp "$T/e" "$T/e5"; r5=$RC
    fresh_fixture
    ( cd "$T/cwd" && env HOME="$T/home" PATH="$T/bin:$PATH" "$B32" "$E" --root "$FX" "$sub" </dev/null >"$T/o" 2>"$T/e" ); r3=$?
    { [ "$r3" = "$r5" ] && [ -s "$T/o" ] && cmp -s "$T/o" "$T/o5" && cmp -s "$T/e" "$T/e5"; } || B32BAD="$B32BAD $sub"
  done
  if [ -z "$B32BAD" ]; then ok "under $B32 (set -u, bash 3.x) 'mode' and 'check' print the same as under bash"
  else no "under $B32 these differ from bash:$B32BAD"; fi
fi

echo "== 2. help / usage errors / valid-branch / every arm equal the single-file base ($BASE)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
HAVE_BASE=0
if [ -n "$REPO" ] && git -C "$REPO" cat-file -e "$BASE:$BASE_PATH" 2>/dev/null \
   && git -C "$REPO" show "$BASE:$BASE_PATH" > "$T/base.sh" 2>/dev/null && [ -s "$T/base.sh" ]; then
  HAVE_BASE=1
fi
if [ "$HAVE_BASE" = 0 ]; then
  skp "base blob $BASE:$BASE_PATH not in this clone (shallow checkout?) — the base-equality legs are not run"
else
  mkdir -p "$T/basedir"; cp "$T/base.sh" "$T/basedir/setup-memory.sh"
  # one invocation per line: `<label>|<args>` (args word-split; none contains a space)
  CASES="--help|--help
-h|-h
<no-arg>|
unknown subcommand|no-such-subcommand
valid-branch accepted|valid-branch loomwright-meta
valid-branch refused|valid-branch off
valid-branch missing name|valid-branch
--root without a value|--root"
  for sub in $DOC; do
    [ "$sub" = valid-branch ] && continue
    CASES="$CASES
$sub|$(arm_args "$sub")"
  done
  while IFS='|' read -r label args; do
    [ -n "$label" ] || continue
    # shellcheck disable=SC2086
    { fresh_fixture; run_e "$T/basedir/setup-memory.sh" $args; } ; brc=$RC; cp "$T/o" "$T/bo"; cp "$T/e" "$T/be"
    # shellcheck disable=SC2086
    { fresh_fixture; run_e "$E" $args; } ; nrc=$RC
    if [ "$brc" = "$nrc" ] && cmp -s "$T/bo" "$T/o" && cmp -s "$T/be" "$T/e" && { [ -s "$T/o" ] || [ -s "$T/e" ] || [ "$label" = "valid-branch accepted" ]; }; then
      ok "'$label': stdout ($(wc -l <"$T/o" | tr -d ' ') lines), stderr and exit $nrc equal the base"
    else no "'$label': differs from the base (rc $brc vs $nrc; stdout $(wc -l <"$T/bo" | tr -d ' ') vs $(wc -l <"$T/o" | tr -d ' ') lines; stderr '$(head -1 "$T/be")' vs '$(head -1 "$T/e")')"; fi
  done <<<"$CASES"
fi

echo "== 3. no glob: a stray module file is never sourced"
C="$(mk_copy)"
printf 'echo STRAY_MODULE_SOURCED\n' > "$(dirname "$C")/setup-memory.d/zz-stray.sh"
fresh_fixture; run_e "$C" --root "$FX" mode; SO="$(cat "$T/o" "$T/e")"
fresh_fixture; run_e "$C" --root "$FX" check; SO="$SO $(cat "$T/o" "$T/e")"
if [ -n "$SO" ] && ! grep -q STRAY_MODULE_SOURCED <<<"$SO"; then ok "stray setup-memory.d/zz-stray.sh is not sourced (mode, check)"
else no "a stray module file was sourced (glob?)"; fi

echo "== 4. a missing / unreadable module fails CLOSED with the loader's own message"
if [ "$NMOD" -ge 6 ]; then ok "$NMOD modules sourced by name: $(tr '\n' ' ' <<<"$MODS")"; else no "only $NMOD _sm_source lines found"; fi
while read -r m; do
  [ -n "$m" ] || continue
  C="$(mk_copy)"; rm -f "$(dirname "$C")/setup-memory.d/$m.sh"
  if [ ! -s "$C" ] || [ -e "$(dirname "$C")/setup-memory.d/$m.sh" ] || ! bash -n "$C" \
     || diff -rq "$MOD_DIR" "$(dirname "$C")/setup-memory.d" >/dev/null 2>&1; then
    no "missing-module mutant $m: not built (copy empty, file still present, bash -n failed, or no difference)"; continue
  fi
  fresh_fixture; run_e "$C" --root "$FX" mode
  if [ "$RC" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" "$T/e"; then
    ok "$m.sh removed ⇒ exit $RC, '$MISSING_MSG/$m.sh'"
  else no "$m.sh removed ⇒ rc=$RC err='$(head -1 "$T/e")' (expected non-zero and '$MISSING_MSG/$m.sh')"; fi
done <<<"$MODS"
if [ "$(id -u)" = 0 ]; then
  skp "unreadable module: running as root, chmod 000 does not deny reads"
else
  m="$(head -1 <<<"$MODS")"; C="$(mk_copy)"; chmod 000 "$(dirname "$C")/setup-memory.d/$m.sh"
  fresh_fixture; run_e "$C" --root "$FX" check
  if [ "$RC" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" "$T/e"; then ok "unreadable $m.sh ⇒ exit $RC naming it"
  else no "unreadable $m.sh ⇒ rc=$RC err='$(head -1 "$T/e")'"; fi
fi
m="$(sed -n 2p <<<"$MODS")"; C="$(mk_copy)"; : > "$(dirname "$C")/setup-memory.d/$m.sh"
if [ -s "$(dirname "$C")/setup-memory.d/$m.sh" ] || ! [ -s "$MOD_DIR/$m.sh" ]; then
  no "empty-module mutant $m: not built (copy not emptied, or the real module is itself empty)"
else
  fresh_fixture; run_e "$C" --root "$FX" check
  if [ "$RC" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" "$T/e"; then ok "empty $m.sh ⇒ exit $RC naming it (never a silent 'command not found' later)"
  else no "empty $m.sh ⇒ rc=$RC err='$(head -1 "$T/e")'"; fi
fi
m="$(tail -1 <<<"$MODS")"; C="$(mk_copy)"; rm -f "$(dirname "$C")/setup-memory.d/$m.sh"
err="$(bundle_of "$C" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" <<<"$err"; then ok "_sm_bundle on a copy without $m.sh ⇒ exit $rc naming it"
else no "_sm_bundle without $m.sh ⇒ rc=$rc err='$err'"; fi

echo "== 5. verbatim move: the stripped bundle equals the single-file base"
if [ "$HAVE_BASE" = 0 ]; then
  skp "base blob not in this clone — the verbatim-move legs are not run"
else
  if verbatim_ok "$E"; then
    ok "bundle minus the Modules map, loader block, markers and # cpl-guard lines == $BASE:$BASE_PATH byte-for-byte"
  else no "bundle differs from the base: $(diff "$T/base.sh" "$T/vb.stripped" 2>/dev/null | head -4 | tr '\n' '|')"; fi
  # Mutation control: one moved line changed (a trailing space on the first line of the last module).
  m="$(tail -1 <<<"$MODS")"; C="$(mk_copy)"; M="$(dirname "$C")/setup-memory.d/$m.sh"
  sed '1s/$/ /' "$MOD_DIR/$m.sh" > "$M"
  if [ ! -s "$M" ] || cmp -s "$MOD_DIR/$m.sh" "$M" || ! bash -n "$M"; then
    no "verbatim mutant ($m.sh): not built (empty, sed matched nothing, or bash -n failed)"
  elif verbatim_ok "$C"; then
    no "verbatim mutant ($m.sh, one moved line changed) still compared equal — the comparison is vacuous"
  else ok "verbatim mutant ($m.sh, one moved line changed) ⇒ the comparison fails"; fi
fi

echo "== 6. module shape: size, parse, listed set, Modules map, entry-only functions"
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
if [ "$ONDISK" = "$(env LC_ALL=C sort <<<"$MODS")" ]; then ok "the sourced list and the setup-memory.d/ files are the same set (no dead or missing module)"
else no "sourced [$(tr '\n' ' ' <<<"$MODS")] vs on disk [$(tr '\n' ' ' <<<"$ONDISK")]"; fi
MAP="$(awk '/^# Modules \(sourced in this order from setup-memory\.d\/\):$/ { m = 1; next } m && /^$/ { exit } m' "$E")"
MAPMODS="$(sed -n 's/^# - \([a-z][a-z-]*\)\.sh: .*/\1/p' <<<"$MAP")"
if [ -n "$MAP" ] && [ "$MAPMODS" = "$MODS" ]; then ok "the Modules map names every module, in source order"
else no "Modules map [$(tr '\n' ' ' <<<"$MAPMODS")] vs sourced [$(tr '\n' ' ' <<<"$MODS")]"; fi
ENTRY_ONLY=""
for fn in usage apply_readiness_event _sm_source _sm_bundle; do
  [ "$(grep -c "^$fn() {\$" "$E")" = 1 ] || ENTRY_ONLY="$ENTRY_ONLY $fn: not defined once in the entry;"
  while read -r m; do
    [ -n "$m" ] || continue
    grep -q "^$fn() {" "$MOD_DIR/$m.sh" 2>/dev/null && ENTRY_ONLY="$ENTRY_ONLY $fn: also in $m.sh;"
  done <<<"$MODS"
done
if [ -z "$ENTRY_ONLY" ]; then ok "usage, apply_readiness_event (both resolve through \${BASH_SOURCE[0]}) and the loader are defined in the entry only"
else no "entry-only functions:$ENTRY_ONLY"; fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
