#!/usr/bin/env bash
# test-meta-sync-modules.sh — self-tests for the meta-sync.sh module split (automate-speed/20, a
# move-only split into meta-sync.d/). Runs against the REAL entry point (never the single-file
# bundle test-meta-sync.sh reads for its mutants), in temp dirs only: a scratch git repo whose
# origin is a path that does not exist, so no arm can reach a real remote. Modelled on
# test-automate-trail-modules.sh.
#
# Covers:
#   1. every subcommand the argument parser accepts has an arm in the final `case "$SUBCMD" in`
#      table; the function each arm calls is defined by exactly one module; invoking the arm prints
#      a line only that subcommand's function prints (never empty, never `command not found`),
#      under bash on PATH and under a 3.x /bin/bash when the host has one.
#   2. `--help`, `-h`, no-arg, an unknown argument, every argument-parser refusal and every arm's
#      invocation give the same stdout, stderr and exit code as the last single-file meta-sync.sh
#      (the BASE blob below, read with `git show`; a named SKIP where that commit is not in the
#      clone, e.g. a shallow checkout).
#   3. a stray file in meta-sync.d/ is never sourced (modules are listed, never globbed).
#   4. a copy with ONE module removed (each in turn), unreadable or empty, exits non-zero with the
#      loader's own message `meta-sync: missing module file: meta-sync.d/<name>.sh` as its ONLY
#      output — and a `pull` then takes no lock, runs no fetch / remote probe (git shim log),
#      writes no meta-base and leaves no temp dir behind.
#   5. verbatim move: _ms_bundle's output, with the Modules map, the module loader block and the
#      source markers removed, equals the BASE blob byte-for-byte — skipped with 2. A copy with one
#      moved line changed must fail that comparison (gated mutant).
#   6. every module is <= 800 lines, passes `bash -n` (and a 3.x `bash -n` when the host has one);
#      the sourced list and the meta-sync.d/ files are the same set; the Modules map names them in
#      source order; the map and the loader sit outside the header block `usage` prints.
# Every mutant is gated on non-empty + differs + bash -n. Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
E="$HERE/meta-sync.sh"
MOD_DIR="$HERE/meta-sync.d"
# The last single-file meta-sync.sh (the split's base commit).
BASE=a8819a38100d77fbeddc2ff1a56963e91f172a5d
BASE_PATH=loomwright/scripts/meta-sync.sh
MISSING_MSG="meta-sync: missing module file: meta-sync.d"
BR="as20-modules-probe"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
no()   { echo "  FAIL: $1"; fail=$((fail+1)); }
skp()  { echo "  SKIP: $1"; skip=$((skip+1)); }

T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@test.invalid
export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@test.invalid
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="owner/repo"

# The scratch checkout every arm runs against: one managed file, a clean file to scrub, and an
# origin that does not exist (every remote probe / fetch is `unreachable`, offline and instant).
R="$T/repo"; mkdir -p "$T/cwd"
git init -q "$R"
git -C "$R" remote add origin "$T/no-such-origin.git"
mkdir -p "$R/.supervisor/requirements/q"; printf 'x\n' > "$R/.supervisor/requirements/q/x.md"
printf 'plain text\n' > "$R/clean.txt"; printf 'clean.txt\n' > "$T/scrub.list"

# args_of <sub> — the arguments that take <sub> past the parser to its function (the explicit
# --branch override skips the mode read, so no setup-memory.sh answer is involved).
args_of() {
  case "$1" in
    init|pull|status) echo "$1 --branch $BR --allow-branch-mismatch" ;;
    push)         echo "push --branch $BR --allow-branch-mismatch --paths-from $T/no-such-list" ;;
    scrub)        echo "scrub --paths-from $T/scrub.list" ;;
    list-managed) echo "list-managed" ;;
    *)            echo "" ;;
  esac
}
# marker_of <sub> — a line only that subcommand's own function prints for args_of <sub>.
marker_of() {
  case "$1" in
    init)         echo "meta_sync: fetch_failed — origin is unreachable; nothing was created" ;;
    pull)         echo "meta_sync: fetch_failed — could not fetch '$BR' from origin" ;;
    push)         echo "meta_sync: usage: --paths-from '$T/no-such-list' is not a file" ;;
    status)       echo "unreachable" ;;
    scrub)        echo "meta_sync: clean (1 file(s) scanned)" ;;
    list-managed) echo ".supervisor/requirements/q/x.md" ;;
    *)            echo "" ;;
  esac
}
# run_sub <bash> <entry> <args…> — combined output of an invocation in the empty temp cwd
run_sub() {
  local b="$1" e="$2"; shift 2
  ( cd "$T/cwd" && "$b" "$e" "$@" --root "$R" </dev/null 2>&1 )
}
# subcommands the argument parser accepts (its `a|b|c)` subcommand arm)
parser_subs() {
  sed -n 's/^    \(init|[a-z|-]*\))$/\1/p' "$1" | tr '|' '\n'
}
# case_arms <entry> — `<sub> <last command before ;;>` for each arm of the FINAL dispatch
case_arms() {
  awk '/^case "\$SUBCMD" in$/ { m = 1; next } m && /^esac$/ { exit }
       m && /^  [a-z][a-z-]*\)/ { s = $1; sub(/\)$/, "", s); c = $0; sub(/[ ]*;;[ ]*$/, "", c); n = split(c, w, /[ ;]+/); print s, w[n] }' "$1"
}
# modules sourced by <entry>, in source order
mods_of() { sed -n 's/^_ms_source \([a-z][a-z-]*\)$/\1/p' "$1"; }
# mk_copy — a fresh scripts-dir copy: the entry, its module dir and the sibling setup-memory.sh
mk_copy() {
  local c; c="$(mktemp -d "$T/copy.XXXXXX")"
  cp "$E" "$c/meta-sync.sh"; cp -R "$MOD_DIR" "$c/meta-sync.d"
  cp "$HERE/setup-memory.sh" "$c/"
  [ -d "$HERE/setup-memory.d" ] && cp -R "$HERE/setup-memory.d" "$c/"
  echo "$c/meta-sync.sh"
}
# bundle_of <entry> — that entry's own _ms_bundle output (the function evaluated from it)
bundle_of() {
  ( eval "$(awk '/^_ms_bundle\(\) \{$/,/^}$/' "$1")"; _ms_bundle "$1" )
}
# strip_split <bundle-file> — the bundle without the Modules map, the loader block and the markers
strip_split() {
  sed -e '/^# Modules (sourced in this order from meta-sync\.d\/):$/,/^$/d' \
      -e '/^# >>> module loader /,/^# <<< module loader$/d' \
      -e '/^# >>> meta-sync\.d\/[a-z][a-z-]*\.sh$/d' \
      -e '/^# <<< meta-sync\.d\/[a-z][a-z-]*\.sh$/d' "$1"
}
# verbatim_ok <entry> — 0 iff <entry>'s stripped bundle equals $T/base.sh byte-for-byte
verbatim_ok() {
  bundle_of "$1" > "$T/vb.bundle" 2>/dev/null && [ -s "$T/vb.bundle" ] || return 1
  strip_split "$T/vb.bundle" > "$T/vb.stripped"
  cmp -s "$T/vb.stripped" "$T/base.sh"
}

B32=""
for cand in /bin/bash /usr/local/bin/bash3 /opt/bash3/bin/bash; do
  [ -x "$cand" ] || continue
  [ "$("$cand" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)" = "3" ] && { B32="$cand"; break; }
done
BASHES="bash"; [ -z "$B32" ] || BASHES="bash $B32"

MODS="$(mods_of "$E")"; NMOD="$(grep -c . <<<"$MODS")"

echo "== 1. every subcommand reaches its own function (real entry point)"
SUBS="$(parser_subs "$E")"; NSUBS="$(grep -c . <<<"$SUBS")"
ARMS="$(case_arms "$E")"; NARMS="$(grep -c . <<<"$ARMS")"
if [ "$NSUBS" -ge 6 ] && [ "$NARMS" -ge 6 ]; then ok "parser accepts $NSUBS subcommands; the final dispatch has $NARMS arms"
else no "parse found $NSUBS parser subcommands / $NARMS dispatch arms (expected >= 6 each)"; fi
# probe_sub <bash> <entry> <sub> — prints nothing when <sub> has an arm in <entry>'s final dispatch,
# the arm's function is defined in exactly one module, and the invocation prints that function's
# own marker line; otherwise one `<sub>: <reason>;` string.
probe_sub() {
  local b="$1" e="$2" sub="$3" fn ndef=0 m mk out
  fn="$(case_arms "$e" | awk -v s="$sub" '$1 == s { print $2 }')"
  [ -n "$fn" ] || { echo " $sub: no arm in the final dispatch;"; return 0; }
  while read -r m; do
    [ -n "$m" ] || continue
    grep -q "^$fn() {" "$MOD_DIR/$m.sh" 2>/dev/null && ndef=$((ndef+1))
  done <<<"$MODS"
  [ "$ndef" = 1 ] || echo " $sub:$fn defined in $ndef module(s);"
  mk="$(marker_of "$sub")"; [ -n "$mk" ] || { echo " $sub: no probe marker (add one to marker_of);"; return 0; }
  # shellcheck disable=SC2046
  out="$(run_sub "$b" "$e" $(args_of "$sub"))"
  case "$out" in
    "") echo " $sub: no output;" ;;
    *"command not found"*) echo " $sub: a function was not found at call time;" ;;
  esac
  grep -qxF -- "$mk" <<<"$out" || echo " $sub: '$mk' not printed (got '$(head -1 <<<"$out")');"
  return 0
}
for b in $BASHES; do
  BROKEN=""
  while read -r sub; do
    [ -n "$sub" ] || continue
    BROKEN="$BROKEN$(probe_sub "$b" "$E" "$sub")"
  done <<<"$SUBS"
  if [ -z "$BROKEN" ]; then ok "[$b] all $NSUBS subcommands: one arm each, its function defined in exactly one module, the invocation prints that function's own line"
  else no "[$b] broken subcommands:$BROKEN"; fi
done
# Mutation control: a copy whose dispatch lost its `status` arm must fail the probe.
C="$(mk_copy)"; sed '/^  status) cmd_status ;;$/d' "$E" > "$C"
if [ ! -s "$C" ] || cmp -s "$E" "$C" || ! bash -n "$C"; then
  no "dispatch mutant (status arm deleted): not built (empty, sed matched nothing, or bash -n failed)"
elif [ -n "$(probe_sub bash "$C" status)" ]; then
  ok "dispatch mutant (status arm deleted) ⇒ the probe fails:$(probe_sub bash "$C" status)"
else no "dispatch mutant (status arm deleted) still passed the probe — the arm check is vacuous"; fi

echo "== 2. --help / -h / no-arg / refusals / every arm equal the single-file base ($BASE)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
HAVE_BASE=0
if [ -n "$REPO" ] && git -C "$REPO" cat-file -e "$BASE:$BASE_PATH" 2>/dev/null \
   && git -C "$REPO" show "$BASE:$BASE_PATH" > "$T/base.sh" 2>/dev/null && [ -s "$T/base.sh" ]; then
  HAVE_BASE=1
fi
if [ "$HAVE_BASE" = 0 ]; then
  skp "base blob $BASE:$BASE_PATH not in this clone (shallow checkout?) — the base-equality legs are not run"
else
  mkdir -p "$T/basedir"; cp "$T/base.sh" "$T/basedir/meta-sync.sh"
  cp "$HERE/setup-memory.sh" "$T/basedir/"
  [ -d "$HERE/setup-memory.d" ] && cp -R "$HERE/setup-memory.d" "$T/basedir/"
  # same_as_base <label> <args…> — the base copy and the entry, same cwd, same args
  same_as_base() {
    local label="$1" brc nrc; shift
    ( cd "$T/cwd" && bash "$T/basedir/meta-sync.sh" "$@" </dev/null >"$T/bo" 2>"$T/be" ); brc=$?
    ( cd "$T/cwd" && bash "$E" "$@" </dev/null >"$T/no" 2>"$T/ne" ); nrc=$?
    if [ "$brc" = "$nrc" ] && cmp -s "$T/bo" "$T/no" && cmp -s "$T/be" "$T/ne" && { [ -s "$T/no" ] || [ -s "$T/ne" ]; }; then
      ok "'$label': stdout ($(wc -l <"$T/no" | tr -d ' ') lines), stderr and exit $nrc equal the base"
    else no "'$label': differs from the base (rc $brc vs $nrc; stdout $(wc -l <"$T/bo" | tr -d ' ') vs $(wc -l <"$T/no" | tr -d ' ') lines; stderr '$(head -1 "$T/be")' vs '$(head -1 "$T/ne")')"; fi
  }
  same_as_base "--help" --help
  same_as_base "-h" -h
  same_as_base "<no-arg>"
  same_as_base "unknown argument" no-such-subcommand
  same_as_base "two subcommands" pull push
  same_as_base "value flag without a value" status --branch
  same_as_base "--paths-from on status" status --paths-from "$T/scrub.list" --root "$R"
  same_as_base "scrub without --paths-from" scrub --root "$R"
  same_as_base "--tracked on status" status --tracked --root "$R"
  same_as_base "--paths on pull" pull --paths --root "$R"
  same_as_base "--learning on push" push --learning --root "$R"
  same_as_base "--tree on status" status --tree HEAD --root "$R"
  same_as_base "--tree with --tracked" list-managed --tree HEAD --tracked --root "$R"
  same_as_base "--branch on scrub" scrub --paths-from "$T/scrub.list" --branch "$BR" --root "$R"
  same_as_base "--allow-branch-mismatch alone" pull --allow-branch-mismatch --root "$R"
  same_as_base "--root not a directory" status --root "$T/no-such-dir"
  same_as_base "--root not a work tree" list-managed --root "$T/cwd"
  same_as_base "invalid branch name" status --branch "bad..name" --allow-branch-mismatch --root "$R"
  while read -r sub; do
    [ -n "$sub" ] || continue
    # shellcheck disable=SC2046
    same_as_base "arm $sub" $(args_of "$sub") --root "$R"
  done <<<"$SUBS"
fi

echo "== 3. no glob: a stray module file is never sourced"
C="$(mk_copy)"
printf 'echo STRAY_MODULE_SOURCED\n' > "$(dirname "$C")/meta-sync.d/zz-stray.sh"
SO="$(run_sub bash "$C" list-managed)"$'\n'"$(run_sub bash "$C" $(args_of status))"
if grep -qxF ".supervisor/requirements/q/x.md" <<<"$SO" && ! grep -q STRAY_MODULE_SOURCED <<<"$SO"; then
  ok "stray meta-sync.d/zz-stray.sh is not sourced (the copy still ran list-managed and status)"
else no "a stray module file was sourced (glob?), or the copy did not run: '$(head -2 <<<"$SO" | tr '\n' '|')'"; fi

echo "== 4. a missing / unreadable module fails CLOSED with the loader's own message, before any lock or fetch"
if [ "$NMOD" -ge 6 ]; then ok "$NMOD modules sourced by name: $(tr '\n' ' ' <<<"$MODS")"; else no "only $NMOD _ms_source lines found"; fi
# A git shim that logs every argv, so a remote probe / fetch / write is visible.
REAL_GIT="$(command -v git)"; mkdir -p "$T/gitlog"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$GITLOG"\nexec "%s" "$@"\n' "$REAL_GIT" > "$T/gitlog/git"; chmod +x "$T/gitlog/git"
GITDIR_R="$(git -C "$R" rev-parse --absolute-git-dir)"
# pull_probe <entry> — a pull with the branch override through the git shim and a private TMPDIR;
# sets PO (stdout), PE (stderr), PRC, and PG (the git argv log).
pull_probe() {
  : > "$T/git.log"; rm -rf "$T/tmpd"; mkdir -p "$T/tmpd"
  ( cd "$T/cwd" && GITLOG="$T/git.log" TMPDIR="$T/tmpd" PATH="$T/gitlog:$PATH" \
      bash "$1" pull --branch "$BR" --allow-branch-mismatch --root "$R" </dev/null >"$T/po" 2>"$T/pe" ); PRC=$?
  PO="$(cat "$T/po")"; PE="$(cat "$T/pe")"; PG="$(cat "$T/git.log")"
}
# Positive control: with every module present the same pull DOES probe the remote through the shim.
C="$(mk_copy)"; pull_probe "$C"
if grep -q 'ls-remote' <<<"$PG" && [ -z "$(ls -A "$T/tmpd")" ] && [ ! -e "$GITDIR_R/meta-sync.lock" ]; then
  ok "positive control: a full copy's pull is seen probing the remote (git shim), cleans its temp dir and lock (rc=$PRC)"
else no "positive control: the git shim saw no ls-remote, or a temp dir / lock was left (rc=$PRC log='$(tr '\n' '|' <<<"$PG")')"; fi
while read -r m; do
  [ -n "$m" ] || continue
  C="$(mk_copy)"; rm -f "$(dirname "$C")/meta-sync.d/$m.sh"
  if [ ! -s "$C" ] || [ -e "$(dirname "$C")/meta-sync.d/$m.sh" ] || ! bash -n "$C" \
     || diff -rq "$MOD_DIR" "$(dirname "$C")/meta-sync.d" >/dev/null 2>&1; then
    no "missing-module mutant $m: not built (copy empty, file still present, bash -n failed, or no difference)"; continue
  fi
  err="$( ( cd "$T/cwd" && bash "$C" list-managed --root "$R" ) 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && [ "$err" = "$MISSING_MSG/$m.sh" ]; then
    ok "$m.sh removed ⇒ list-managed exits $rc, stderr is exactly '$MISSING_MSG/$m.sh'"
  else no "$m.sh removed ⇒ list-managed rc=$rc err='$err' (expected non-zero and exactly '$MISSING_MSG/$m.sh')"; fi
  pull_probe "$C"
  if [ "$PRC" -ne 0 ] && [ "$PE" = "$MISSING_MSG/$m.sh" ] && [ -z "$PO" ] \
     && [ ! -e "$GITDIR_R/meta-sync.lock" ] && [ ! -e "$GITDIR_R/meta-base" ] && [ -z "$(ls -A "$T/tmpd")" ] \
     && ! grep -qE '(^| )(ls-remote|fetch|push|update-ref|update-index|read-tree|write-tree|commit-tree|hash-object|mktree)( |$)' <<<"$PG"; then
    ok "$m.sh removed ⇒ pull exits $PRC with only the loader message: no lock, no remote probe or fetch, no meta-base, no temp dir left"
  else no "$m.sh removed ⇒ pull rc=$PRC err='$(tr '\n' '|' <<<"$PE")' out='$PO' git='$(tr '\n' '|' <<<"$PG")' lock=$([ -e "$GITDIR_R/meta-sync.lock" ] && echo yes || echo no) tmp='$(ls -A "$T/tmpd" | tr '\n' ' ')'"; fi
done <<<"$MODS"
if [ "$(id -u)" = 0 ]; then
  skp "unreadable module: running as root, chmod 000 does not deny reads"
else
  m="$(head -1 <<<"$MODS")"; C="$(mk_copy)"; chmod 000 "$(dirname "$C")/meta-sync.d/$m.sh"
  err="$( ( cd "$T/cwd" && bash "$C" list-managed --root "$R" ) 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && [ "$err" = "$MISSING_MSG/$m.sh" ]; then ok "unreadable $m.sh ⇒ exit $rc naming it"
  else no "unreadable $m.sh ⇒ rc=$rc err='$err'"; fi
fi
# An EMPTY module (a truncated install) is refused like a missing one — by the loader before the
# lock (the pull probe), and by _ms_bundle — never sourced as a no-op that fails later.
m="$(tail -1 <<<"$MODS")"; C="$(mk_copy)"; : > "$(dirname "$C")/meta-sync.d/$m.sh"
pull_probe "$C"; berr="$(bundle_of "$C" 2>&1 >/dev/null)"; brc=$?
if [ ! -f "$(dirname "$C")/meta-sync.d/$m.sh" ] || [ -s "$(dirname "$C")/meta-sync.d/$m.sh" ]; then
  no "empty-module mutant $m: not built"
elif [ "$PRC" -ne 0 ] && [ "$PE" = "$MISSING_MSG/$m.sh" ] && [ ! -e "$GITDIR_R/meta-sync.lock" ] \
     && ! grep -qE '(^| )(ls-remote|fetch)( |$)' <<<"$PG" && [ "$brc" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" <<<"$berr"; then
  ok "empty $m.sh ⇒ pull exits $PRC with only the loader message (no lock, no fetch); _ms_bundle exits $brc naming it"
else no "empty $m.sh ⇒ pull rc=$PRC err='$(tr '\n' '|' <<<"$PE")' git='$(tr '\n' '|' <<<"$PG")'; bundle rc=$brc err='$berr'"; fi
m="$(tail -1 <<<"$MODS")"; C="$(mk_copy)"; rm -f "$(dirname "$C")/meta-sync.d/$m.sh"
err="$(bundle_of "$C" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -ne 0 ] && grep -qxF "$MISSING_MSG/$m.sh" <<<"$err"; then ok "_ms_bundle on a copy without $m.sh ⇒ exit $rc naming it"
else no "_ms_bundle without $m.sh ⇒ rc=$rc err='$err'"; fi

echo "== 5. verbatim move: the stripped bundle equals the base byte-for-byte"
if [ "$HAVE_BASE" = 0 ]; then
  skp "base blob not in this clone — the verbatim-move legs are not run"
else
  if verbatim_ok "$E"; then
    ok "bundle minus the Modules map, loader block and markers == $BASE:$BASE_PATH"
  else no "bundle differs from the base: $(diff "$T/base.sh" "$T/vb.stripped" 2>/dev/null | head -4 | tr '\n' '|')"; fi
  # Mutation control: one moved line changed (a trailing space on the first line of the last module).
  m="$(tail -1 <<<"$MODS")"; C="$(mk_copy)"; M="$(dirname "$C")/meta-sync.d/$m.sh"
  sed '1s/$/ /' "$MOD_DIR/$m.sh" > "$M"
  if [ ! -s "$M" ] || cmp -s "$MOD_DIR/$m.sh" "$M" || ! bash -n "$M"; then
    no "verbatim mutant ($m.sh): not built (empty, sed matched nothing, or bash -n failed)"
  elif verbatim_ok "$C"; then
    no "verbatim mutant ($m.sh, one moved line changed) still compared equal — the comparison is vacuous"
  else ok "verbatim mutant ($m.sh, one moved line changed) ⇒ the comparison fails"; fi
fi

echo "== 6. module shape: size, parse, listed set, header map, usage block"
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
if [ "$ONDISK" = "$(env LC_ALL=C sort <<<"$MODS")" ]; then ok "the sourced list and the meta-sync.d/ files are the same set (no dead or missing module)"
else no "sourced [$(tr '\n' ' ' <<<"$MODS")] vs on disk [$(tr '\n' ' ' <<<"$ONDISK")]"; fi
MAP="$(awk '/^# Modules \(sourced in this order from meta-sync\.d\/\):$/ { m = 1; next } m && /^$/ { exit } m' "$E")"
MAPMODS="$(sed -n 's/^# - \([a-z][a-z-]*\)\.sh: .*/\1/p' <<<"$MAP")"
if [ -n "$MAP" ] && [ "$MAPMODS" = "$MODS" ]; then ok "the Modules map names every module, in source order"
else no "Modules map [$(tr '\n' ' ' <<<"$MAPMODS")] vs sourced [$(tr '\n' ' ' <<<"$MODS")]"; fi
USAGE_BLOCK="$(awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$E")"
LOADER="$(awk '/^# >>> module loader /,/^# <<< module loader$/' "$E")"
if [ -n "$USAGE_BLOCK" ] && [ -n "$LOADER" ] && grep -q '^_ms_bundle() {$' <<<"$LOADER" \
   && ! grep -qF 'Modules (sourced in this order' <<<"$USAGE_BLOCK" && ! grep -qF 'module loader' <<<"$USAGE_BLOCK"; then
  ok "the Modules map and the loader block sit outside the header block usage prints"
else no "loader block missing / without _ms_bundle, or the map / loader leaked into the usage block"; fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
