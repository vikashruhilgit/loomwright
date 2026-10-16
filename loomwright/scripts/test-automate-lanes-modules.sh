#!/usr/bin/env bash
# test-automate-lanes-modules.sh — self-tests for the automate-lanes.sh module split (automate-speed/19,
# move-only). Runs against the REAL entry point (never the single-file bundle test-automate-lanes.sh
# builds its mutants from), in temp dirs only. Modelled on test-automate-helpers-dispatch.sh.
#
# Covers:
#   1. every function arm of lanes_main's `case` table equals this test's own ARMS list, names a
#      function defined once the entry point is sourced, and invoking it (no args, empty stdin, empty
#      temp cwd, failing git / gh / claude stubs on PATH) never reaches _lanes_usage's unknown branch;
#      an unlisted subcommand does (positive control).
#   2. the entry point sources exactly MODS, by name, in this order; automate-lanes.d/ holds exactly
#      those files; each module passes `bash -n` and stays within 800 lines; the entry point sourced by
#      /bin/bash under `set -u` defines every arm's function (AC4); the header's module map names every
#      module once, in source order (AC13).
#   3. a stray file in automate-lanes.d/ is never sourced (names are listed, never globbed).
#   4. a copy with ONE module removed (each module in turn): run directly ⇒ non-zero exit with the
#      loader's own `automate-lanes: missing module file: automate-lanes.d/<name>.sh`; SOURCED ⇒ the
#      source returns non-zero and the sourcing shell survives; an unreadable module likewise.
#      The two sourcing callers keep their own fallback: guard-lane-wait-armed.sh prints `{}` (it
#      BLOCKS with the complete copy — control) and automate-wave.sh refuses `automate-lanes.sh
#      unreadable`.
#   5. AC3 verbatim move: _lanes_bundle's output, with the loader block, the source-marker lines and
#      the header's module map removed, equals the last single-file automate-lanes.sh (BASE_SHA's
#      blob via `git show`) byte-for-byte; a one-character edit in a module (each module in turn)
#      breaks the equality; a missing or empty module makes _lanes_bundle fail naming it.
#   6. `--help` / `-h` / `help`, no-arg and an unknown subcommand: stdout, stderr and exit code equal
#      the BASE_SHA blob's; every arm's no-arg invocation equals base too, after normalising bash's own
#      `<file>: line <n>:` diagnostics (the only text a move changes — the moved code reports its
#      module and line). Mutation control: _lanes_usage's header anchor flipped ⇒ the --help check fails.
#   Checks 5 and 6 need the BASE_SHA blob: a shallow clone without it prints a named SKIP for each.
#   Every mutant / copy is gated on non-empty + differs + `bash -n` before it is used.
# Exit 0 = all pass, 1 = any failure.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E="$HERE/automate-lanes.sh"
MOD_DIR="$HERE/automate-lanes.d"
# The last single-file automate-lanes.sh (the split's base, origin/main after PRs #569, #572, #574).
BASE_SHA=e2327712af6edf79d381b5a816af49729bc5be9f
# The expected function arms (`<sub>:<function>`) and modules — the test's OWN copies, so a dropped
# or added arm / module fails check 1 / 2 rather than silently changing what is checked.
ARMS="lane-create:lanes_create lane-launch:lanes_launch relay-hook:lanes_relay_hook lane-answer:lanes_answer
lane-remove:lanes_remove lane-convert-ready:lanes_convert_ready lane-info:lanes_info lane-park:lanes_park
lane-drain-check:lanes_drain_check init-check:lanes_init_check pick-guard:lanes_pick_guard
branch-check:lanes_branch_check lane-status:lanes_status lane-feed:lanes_feed lane-readiness:lanes_readiness
validation-gate:lanes_validation_gate lane-park-notify:lanes_park_notify lane-wait:lanes_wait
fleet-closeout:lanes_fleet_closeout wave-plan:lanes_wave_plan _lane-run:lanes_run_wrapper
_merge-hooks:_lanes_merge_hooks"
MODS_WANT="common create launch relay remove notify-guards status-read park-leaks status readiness wave"
USAGE_HEAD='# Usage (standalone: `bash automate-lanes.sh <subcmd> ...`):'
MISSING_MSG='automate-lanes: missing module file: automate-lanes.d/'

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
no()   { echo "  FAIL: $1"; fail=$((fail+1)); }
skp()  { echo "  SKIP: $1"; skip=$((skip+1)); }

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/cwd" "$T/home"

# The base blob, read with the REAL git before any stub is on PATH. Empty ⇒ checks 5 and 6 SKIP.
BASE_BLOB="$T/base-automate-lanes.sh"
git -C "$HERE" show "$BASE_SHA:loomwright/scripts/automate-lanes.sh" > "$BASE_BLOB" 2>/dev/null || : > "$BASE_BLOB"

# failing git / gh / claude stubs, so no arm can reach a real remote, repo or session
for s in git gh claude; do printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/$s"; chmod +x "$T/bin/$s"; done

# fn_arms <entry> — `<sub>:<fn>` per function arm of lanes_main's case table, one per line
fn_arms() {
  awk '/^lanes_main\(\) \{$/ { m = 1 } m && /^    [a-z_][a-z-]*\)[ ]+[a-z_]+ "\$@" ;;$/ {
         sub(/^    /, ""); sub(/\)/, " "); print $1 ":" $2 } m && /^}$/ { exit }' "$1"
}
# defined_fns <entry> — functions defined once <entry> is sourced
defined_fns() { bash -c '. "$1" >/dev/null 2>&1; declare -F' _ "$1" 2>/dev/null | awk '{ print $3 }'; }
# run_sub <entry> <sub> — stdout to $T/rs.out, stderr to $T/rs.err, exit code echoed
run_sub() {
  ( cd "$T/cwd" && HOME="$T/home" PATH="$T/bin:$PATH" bash "$1" ${2:+"$2"} </dev/null >"$T/rs.out" 2>"$T/rs.err" ); echo $?
}
# mk_copy — a fresh scripts-dir copy holding the entry point + its module dir; prints the entry's path
mk_copy() {
  local c; c="$(mktemp -d "$T/copy.XXXXXX")"
  cp "$E" "$c/automate-lanes.sh"; cp -R "$MOD_DIR" "$c/automate-lanes.d"
  cp "$HERE/resolve-loomwright-root.sh" "$c/" 2>/dev/null
  echo "$c/automate-lanes.sh"
}
# copy_differs <copy entry> — the copy's module dir differs from the real one (the mutant took effect)
copy_differs() { ! diff -rq "$MOD_DIR" "$(dirname "$1")/automate-lanes.d" >/dev/null 2>&1; }

echo "== 1. every case-table arm reaches its function (real entry point)"
GOT_ARMS="$(fn_arms "$E" | tr '\n' ' ' | sed 's/ $//')"
WANT_ARMS="$(printf '%s\n' $ARMS | tr '\n' ' ' | sed 's/ $//')"
if [ "$GOT_ARMS" = "$WANT_ARMS" ]; then ok "lanes_main's function arms equal the expected $(printf '%s\n' $ARMS | grep -c .) (same order)"
else no "lanes_main's function arms differ from ARMS — got [$GOT_ARMS]"; fi
DEFS="$(defined_fns "$E")"
BROKEN=""
for a in $ARMS; do
  sub="${a%%:*}"; fn="${a#*:}"
  grep -qxF "$fn" <<<"$DEFS" || { BROKEN="$BROKEN $sub(fn $fn not defined)"; continue; }
  rc="$(run_sub "$E" "$sub")"
  if grep -qxF -- "$USAGE_HEAD" "$T/rs.out" "$T/rs.err"; then BROKEN="$BROKEN $sub(usage, rc=$rc)"; fi
  if grep -qF 'command not found' "$T/rs.err"; then BROKEN="$BROKEN $sub(command not found)"; fi
done
if [ -z "$BROKEN" ]; then ok "every arm: its function is defined after sourcing and a no-arg call never reaches the unknown branch"
else no "broken arms:$BROKEN"; fi
rc="$(run_sub "$E" no-such-subcommand)"
if [ "$rc" = 2 ] && [ ! -s "$T/rs.out" ] && grep -qxF -- "$USAGE_HEAD" "$T/rs.err"; then
  ok "positive control: an unlisted subcommand reaches the unknown branch (usage on stderr, exit 2)"
else no "positive control: an unlisted subcommand gave rc=$rc (the probe cannot see the unknown branch)"; fi

echo "== 2. modules sourced by name, in order; sizes; bash -n; bash 3.2 + set -u; the header's module map"
MODS="$(sed -n 's/^_lanes_source \([a-z][a-z-]*\) || { return 1 2>\/dev\/null || exit 1; }$/\1/p' "$E" | tr '\n' ' ' | sed 's/ $//')"
if [ "$MODS" = "$MODS_WANT" ]; then ok "the entry point sources [$MODS] by name, in that order"
else no "sourced modules [$MODS] differ from [$MODS_WANT]"; fi
ONDISK="$(cd "$MOD_DIR" 2>/dev/null && for f in *.sh; do [ -f "$f" ] && printf '%s\n' "${f%.sh}"; done | sort | tr '\n' ' ' | sed 's/ $//')"
WANTSORTED="$(printf '%s\n' $MODS_WANT | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$ONDISK" = "$WANTSORTED" ]; then ok "automate-lanes.d/ holds exactly the sourced modules (no dead module file)"
else no "automate-lanes.d/ holds [$ONDISK], expected [$WANTSORTED]"; fi
SZBAD=""
for m in $MODS_WANT; do
  f="$MOD_DIR/$m.sh"; n="$(wc -l < "$f" 2>/dev/null | tr -d ' ')"
  { [ -s "$f" ] && bash -n "$f" && [ "${n:-0}" -le 800 ]; } || SZBAD="$SZBAD $m(${n:-missing} lines)"
done
if [ -z "$SZBAD" ] && bash -n "$E"; then ok "every module is non-empty, passes bash -n and is <= 800 lines; the entry point passes bash -n"
else no "module size / syntax:$SZBAD"; fi
if [ -x /bin/bash ]; then
  B32="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')"
  DEF32="$(/bin/bash -uc '. "$1" >/dev/null 2>&1 || exit 7; declare -F' _ "$E" 2>/dev/null | awk '{ print $3 }')"
  MISS32=""
  for a in $ARMS; do grep -qxF "${a#*:}" <<<"$DEF32" || MISS32="$MISS32 ${a#*:}"; done
  if [ -z "$MISS32" ] && [ -n "$DEF32" ]; then ok "/bin/bash (major $B32) with set -u sources the entry point and defines every arm's function"
  else no "/bin/bash (major $B32) set -u: functions missing after sourcing:$MISS32"; fi
else skp "/bin/bash absent: the bash 3.2 + set -u source check needs it"; fi
MAP="$(awk '/^# Modules \(sourced in this order from automate-lanes\.d\/\):$/ { on = 1; next } on && !/^#/ { exit }
            on && /^# - [a-z][a-z-]*\.sh: / { s = $3; sub(/\.sh:$/, "", s); print s }' "$E" | tr '\n' ' ' | sed 's/ $//')"
if [ "$MAP" = "$MODS_WANT" ] && [ "$(grep -c '^# Modules (sourced in this order from automate-lanes\.d/):$' "$E")" = 1 ]; then
  ok "the header carries ONE module map naming every module, in source order"
else no "header module map [$MAP] differs from [$MODS_WANT] (or the map heading is not there exactly once)"; fi

echo "== 3. no glob: a stray module file is never sourced"
C="$(mk_copy)"; printf 'echo STRAY_MODULE_SOURCED\n' > "$(dirname "$C")/automate-lanes.d/zz-stray.sh"
if [ -s "$C" ] && bash -n "$C" && copy_differs "$C"; then
  SO="$(bash "$C" --help 2>&1)"; SS="$(bash -c '. "$1" 2>&1; echo "sourced rc=$?"' _ "$C" 2>&1)"
  if [ -n "$SO" ] && grep -qx 'sourced rc=0' <<<"$SS" && ! grep -q STRAY_MODULE_SOURCED <<<"$SO$SS"; then
    ok "stray automate-lanes.d/zz-stray.sh is sourced neither when run nor when sourced"
  else no "a stray module file was sourced (glob?) — run=[$(head -1 <<<"$SO")] sourced=[$(tr '\n' ' ' <<<"$SS")]"; fi
else no "stray-file copy not built (empty, bash -n failed, or no difference)"; fi

echo "== 4. a missing / unreadable module fails CLOSED, naming it — run directly and sourced"
for m in $MODS_WANT; do
  C="$(mk_copy)"; rm -f "$(dirname "$C")/automate-lanes.d/$m.sh"
  if [ ! -s "$C" ] || [ -e "$(dirname "$C")/automate-lanes.d/$m.sh" ] || ! bash -n "$C" || ! copy_differs "$C"; then
    no "missing $m: copy not built (empty, file still present, bash -n failed, or no difference)"; continue
  fi
  err="$(bash "$C" --help 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && [ "$err" = "${MISSING_MSG}$m.sh" ]; then ok "missing $m.sh, run directly ⇒ exit $rc with the loader's own message"
  else no "missing $m.sh, run directly ⇒ rc=$rc err='$err' (expected non-zero and exactly '${MISSING_MSG}$m.sh')"; fi
  so="$(bash -c '. "$1"; echo "rc=$?"; echo SHELL_SURVIVED' _ "$C" 2>"$T/src.err")"
  if grep -qE '^rc=[1-9]' <<<"$so" && grep -qx SHELL_SURVIVED <<<"$so" && grep -qxF "${MISSING_MSG}$m.sh" "$T/src.err"; then
    ok "missing $m.sh, SOURCED ⇒ the source returns non-zero, names it, and the sourcing shell survives"
  else no "missing $m.sh, SOURCED ⇒ out=[$(tr '\n' ' ' <<<"$so")] err=[$(head -1 "$T/src.err")] (expected rc=<non-zero> + SHELL_SURVIVED)"; fi
done
if [ "$(id -u)" = 0 ]; then
  skp "unreadable module: running as root, chmod 000 does not deny reads"
else
  m="$(set -- $MODS_WANT; echo "$1")"; C="$(mk_copy)"; chmod 000 "$(dirname "$C")/automate-lanes.d/$m.sh"
  err="$(bash "$C" --help 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && [ "$err" = "${MISSING_MSG}$m.sh" ]; then ok "unreadable $m.sh ⇒ exit $rc naming it"
  else no "unreadable $m.sh ⇒ rc=$rc err='$err'"; fi
fi
# The sourcing callers' own fallbacks. A coordinator fixture the Stop hook BLOCKS on (its lock, a run
# file, one `created` lane), so `{}` from the broken copy is the fallback and not an earlier allow.
GR="$T/guard/primary"; GRUN=automate-2026-01-01-000000; mkdir -p "$GR/.supervisor/run.lock" "$GR/.supervisor/automate" "$T/guard/L1"
printf 'owner\tautomate-lanes:%s\nsession_id\tsess-mod-1\n' "$GRUN" > "$GR/.supervisor/run.lock/meta"
printf '# Automate Run: %s\n\n## Status: running\n' "$GRUN" > "$GR/.supervisor/automate/$GRUN.md"
printf '#lane\tpath\titem\trun_id\tpid\tpid_start\tsession_id\tstate\tlast_launch_utc\tblocked_reason\nL1\t%s\treqs/a.md\tr1\t-\t-\t-\tcreated\t-\t-\n' "$T/guard/L1" > "$GR/.supervisor/automate/$GRUN.lanes"
GPL="$(jq -n -c --arg cwd "$GR" '{session_id: "sess-mod-1", cwd: $cwd, hook_event_name: "Stop", stop_hook_active: false, background_tasks: []}')"
gcopy() { local c; c="$(mk_copy)"; cp "$HERE/guard-lane-wait-armed.sh" "$HERE/automate-wave.sh" "$(dirname "$c")/"; echo "$c"; }
C="$(gcopy)"
GFULL="$(printf '%s' "$GPL" | bash "$(dirname "$C")/guard-lane-wait-armed.sh" 2>/dev/null | jq -r '.decision // "allow"' 2>/dev/null)"
m="$(set -- $MODS_WANT; echo "$1")"
C="$(gcopy)"; rm -f "$(dirname "$C")/automate-lanes.d/status.sh"
if copy_differs "$C" && bash -n "$C"; then
  GOUT="$(printf '%s' "$GPL" | bash "$(dirname "$C")/guard-lane-wait-armed.sh" 2>/dev/null)"; grc=$?
  if [ "$GFULL" = block ] && [ "$GOUT" = "{}" ] && [ "$grc" = 0 ]; then
    ok "guard-lane-wait-armed.sh: complete copy BLOCKS (control); status.sh missing ⇒ its own fallback prints {} (exit 0)"
  else no "guard-lane-wait-armed.sh: complete copy=[$GFULL] (want block), status.sh missing=[$GOUT] rc=$grc (want {})"; fi
else no "guard copy not built (no difference or bash -n failed)"; fi
C="$(gcopy)"; rm -f "$(dirname "$C")/automate-lanes.d/$m.sh"
if copy_differs "$C" && bash -n "$C"; then
  WOUT="$(cd "$T/cwd" && PATH="$T/bin:$PATH" bash "$(dirname "$C")/automate-wave.sh" 2>/dev/null)"; wrc=$?
  if [ "$wrc" = 1 ] && grep -qxF 'wave-build: refused — automate-lanes.sh unreadable' <<<"$WOUT"; then
    ok "automate-wave.sh: $m.sh missing ⇒ its own 'automate-lanes.sh unreadable' refusal fires (exit 1)"
  else no "automate-wave.sh: $m.sh missing ⇒ rc=$wrc out=[$(head -2 <<<"$WOUT" | tr '\n' ' ')]"; fi
else no "wave copy not built (no difference or bash -n failed)"; fi

echo "== 5. AC3: the bundle minus the loader, the source markers and the module map is the base file"
eval "$(awk '/^_lanes_bundle\(\) \{$/,/^}$/' "$E")"
# strip_split — drop the split's own additions: the module map (with the `#` line above it), the
# `# >>> module loader` … `# <<< module loader` block, and every `# >>>/<<< automate-lanes.d/` marker.
strip_split() {
  awk '
    held_set { if ($0 ~ /^# Modules \(sourced in this order from automate-lanes\.d\/\):$/) { held_set = 0; map = 1; next }
               print held; held_set = 0 }
    map { if ($0 ~ /^#/) next; map = 0 }
    /^# >>> module loader/ { skip = 1 }
    skip { if ($0 ~ /^# <<< module loader$/) skip = 0; next }
    /^# (>>>|<<<) automate-lanes\.d\/[a-z][a-z-]*\.sh$/ { next }
    $0 == "#" { held = $0; held_set = 1; next }
    { print }
    END { if (held_set) print held }' "$1"
}
if ! declare -F _lanes_bundle >/dev/null; then
  no "_lanes_bundle could not be extracted from the entry point"
else
  _lanes_bundle "$E" > "$T/bundle.sh"; brc=$?
  if [ "$brc" = 0 ] && [ -s "$T/bundle.sh" ] && bash -n "$T/bundle.sh" && ! grep -q '^_lanes_source [a-z]' "$T/bundle.sh"; then
    ok "_lanes_bundle builds ONE self-contained file (no _lanes_source line left, bash -n)"
  else no "_lanes_bundle failed (rc=$brc) or left a _lanes_source line"; fi
  if [ ! -s "$BASE_BLOB" ]; then
    skp "AC3 verbatim move: base blob $BASE_SHA unreachable (shallow clone?)"
  else
    strip_split "$T/bundle.sh" > "$T/bundle.stripped"
    if cmp -s "$T/bundle.stripped" "$BASE_BLOB"; then ok "AC3: stripped bundle == git show ${BASE_SHA:0:7}:loomwright/scripts/automate-lanes.sh byte-for-byte"
    else no "AC3: stripped bundle differs from the base file: $(diff "$BASE_BLOB" "$T/bundle.stripped" | head -4 | tr '\n' ' ')"; fi
    # Mutation control: one moved line edited (a trailing space on its first line), each module in turn.
    for m in $MODS_WANT; do
      C="$(mk_copy)"; M="$(dirname "$C")/automate-lanes.d/$m.sh"
      sed '1s/$/ /' "$MOD_DIR/$m.sh" > "$M"
      if [ ! -s "$M" ] || cmp -s "$MOD_DIR/$m.sh" "$M" || ! bash -n "$M"; then no "AC3 mutant $m: not built"; continue; fi
      _lanes_bundle "$C" > "$T/mb.sh" 2>/dev/null; strip_split "$T/mb.sh" > "$T/mb.stripped"
      if cmp -s "$T/mb.stripped" "$BASE_BLOB"; then no "AC3 mutant $m: an edited moved line still compared equal — the check is vacuous"
      else ok "AC3 mutant $m: one moved line edited ⇒ the verbatim-move check fails"; fi
    done
  fi
  m="$(set -- $MODS_WANT; echo "$1")"; C="$(mk_copy)"; rm -f "$(dirname "$C")/automate-lanes.d/$m.sh"
  berr="$(_lanes_bundle "$C" 2>&1 >/dev/null)"; brc=$?
  if [ "$brc" -ne 0 ] && [ "$berr" = "${MISSING_MSG}$m.sh" ]; then ok "_lanes_bundle with $m.sh missing ⇒ rc=$brc naming it"
  else no "_lanes_bundle with $m.sh missing ⇒ rc=$brc err='$berr'"; fi
  C="$(mk_copy)"; : > "$(dirname "$C")/automate-lanes.d/$m.sh"
  berr="$(_lanes_bundle "$C" 2>&1 >/dev/null)"; brc=$?
  if [ "$brc" -ne 0 ] && [ "$berr" = "${MISSING_MSG}$m.sh" ]; then ok "_lanes_bundle with $m.sh EMPTY ⇒ rc=$brc naming it (never a silently shorter bundle)"
  else no "_lanes_bundle with $m.sh empty ⇒ rc=$brc err='$berr'"; fi
fi

echo "== 6. help / no-arg / unknown output, and every arm's no-arg output, equal the base file's"
if [ ! -s "$BASE_BLOB" ]; then
  skp "help / unknown equal base: base blob $BASE_SHA unreachable (shallow clone?)"
  skp "every arm's no-arg output equal base: base blob $BASE_SHA unreachable (shallow clone?)"
else
  # The base file in a dir of symlinks to every other scripts/ entry, so its sibling lookups resolve
  # exactly as the entry point's do.
  BD="$T/base"; mkdir -p "$BD"
  for e in "$HERE"/*; do
    case "$(basename "$e")" in automate-lanes.sh|automate-lanes.d) ;; *) ln -s "$e" "$BD/$(basename "$e")" ;; esac
  done
  cp "$BASE_BLOB" "$BD/automate-lanes.sh"
  # same_as_base <entry> [<arg>] — stdout, stderr and rc of <entry> equal the base file's (paths and
  # bash's `<file>: line <n>:` locations normalised: the move changes the file and line, nothing else)
  norm() { sed -e "s#$HERE/automate-lanes\.d/[a-z-]*\.sh: line [0-9]*:#<script>: line <n>:#g" \
               -e "s#$HERE/automate-lanes\.sh: line [0-9]*:#<script>: line <n>:#g" \
               -e "s#$BD/automate-lanes\.sh: line [0-9]*:#<script>: line <n>:#g" -e "s#$BD/#<D>/#g" -e "s#$HERE/#<D>/#g" "$1"; }
  same_as_base() {
    local rb rn
    rb="$(run_sub "$BD/automate-lanes.sh" "${2:-}")"; norm "$T/rs.out" > "$T/b.out"; norm "$T/rs.err" > "$T/b.err"
    rn="$(run_sub "$1" "${2:-}")"; norm "$T/rs.out" > "$T/n.out"; norm "$T/rs.err" > "$T/n.err"
    [ "$rb" = "$rn" ] && cmp -s "$T/b.out" "$T/n.out" && cmp -s "$T/b.err" "$T/n.err"
  }
  for a in --help -h help "" no-such-subcommand; do
    if same_as_base "$E" "$a"; then ok "'${a:-<no-arg>}': stdout, stderr and exit code equal base ($(wc -l < "$T/n.out" | tr -d ' ')+$(wc -l < "$T/n.err" | tr -d ' ') lines)"
    else no "'${a:-<no-arg>}': differs from base — $(diff "$T/b.out" "$T/n.out" | head -2 | tr '\n' ' ')$(diff "$T/b.err" "$T/n.err" | head -2 | tr '\n' ' ')"; fi
  done
  ARMDIFF=""
  for a in $ARMS; do same_as_base "$E" "${a%%:*}" || ARMDIFF="$ARMDIFF ${a%%:*}"; done
  if [ -z "$ARMDIFF" ]; then ok "every arm's no-arg invocation: stdout, stderr and exit code equal base"
  else no "arms whose no-arg output differs from base:$ARMDIFF"; fi
  # Mutation control: the usage reader's header anchor flipped ⇒ --help no longer equals base.
  C="$(mk_copy)"
  sed 's|^_lanes_usage() { awk '"'"'/^# Usage \\(standalone/|_lanes_usage() { awk '"'"'/^# Usage \\(standalonX/|' "$E" > "$C"
  if [ ! -s "$C" ] || cmp -s "$E" "$C" || ! bash -n "$C"; then no "usage mutant not built (empty, sed matched nothing, or bash -n failed)"
  elif same_as_base "$C" --help; then no "usage mutant (anchor flipped) still equal to base — the --help check is vacuous"
  else ok "usage mutant (_lanes_usage anchor flipped) ⇒ the --help comparison fails"; fi
fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
