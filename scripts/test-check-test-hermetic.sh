#!/usr/bin/env bash
# test-check-test-hermetic.sh — offline self-test for check-test-hermetic.sh.
#
# Builds fixture trees in a temp dir (never touches the real repo files) and asserts the gate's
# discrimination, fail-CLOSED:
#   1. green              — every covered fixture test sources the helper first -> exit 0, count shown
#   2. missing line       — a test without the source line -> exit != 0, offender named
#   3. line added         — the same test fixed -> green again (the gate is not failing everything)
#   4. after `set -u`     — source line placed after the test's set line -> red
#   5. after other code   — source line placed after an assignment -> red
#   6. wrong path         — canonical form but a relative path that does not exist -> red
#   7. adapter + root globs are covered — an offender under adapters/*/ and under scripts/ is named
#   8. zero covered files — an empty tree -> red (never green on nothing)
#   9. the real tree      — green
#
# Portability: bash 3.2 safe (macOS) + Linux CI. No sed -i, no mapfile, offline.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
CHECK="$script_dir/check-test-hermetic.sh"
[ -f "$CHECK" ] || { echo "test-check-test-hermetic: gate script not found: $CHECK" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-hermetic-lint.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# The exact source statements, by directory depth.
SRC_FLAT='. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"'
SRC_ADAPTER='. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../hermetic-test-env.sh"'
SRC_ROOT='. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"'

# write_test <path> <source-line-or-empty> [placement: first|after-set|after-code]
write_test() {
  local p="$1" src="$2" where="${3:-first}"
  mkdir -p "$(dirname "$p")"
  {
    printf '#!/usr/bin/env bash\n# fixture test — header comment\n#\n\n'
    case "$where" in
      first)      [ -n "$src" ] && printf '%s\n' "$src"; printf 'set -uo pipefail\n' ;;
      after-set)  printf 'set -u\n'; printf '%s\n' "$src" ;;
      after-code) printf 'X=1\n'; printf '%s\n' "$src"; printf 'set -u\n' ;;
    esac
    printf 'echo fixture\n'
  } > "$p"
}

# fresh_tree — a green fixture tree: helper + one test per covered glob.
fresh_tree() {
  rm -rf "$tmp/r"; mkdir -p "$tmp/r/loomwright/scripts/adapters/tool" "$tmp/r/scripts"
  printf '# helper stand-in\n' > "$tmp/r/loomwright/scripts/hermetic-test-env.sh"
  write_test "$tmp/r/loomwright/scripts/test-a.sh" "$SRC_FLAT"
  write_test "$tmp/r/loomwright/scripts/adapters/tool/test-b.sh" "$SRC_ADAPTER"
  write_test "$tmp/r/scripts/test-c.sh" "$SRC_ROOT"
}

run() { bash "$CHECK" --root "$tmp/r" > "$tmp/out" 2>&1; }

echo "== 1. green fixture tree =="
fresh_tree; run; rc=$?
[ "$rc" -eq 0 ] && grep -q '3/3 covered tests' "$tmp/out" && ok "1. green tree exits 0 and reports 3/3" || no "1. rc=$rc: $(cat "$tmp/out")"

echo "== 2. missing source line => red, offender named =="
write_test "$tmp/r/loomwright/scripts/test-new.sh" ""
run; rc=$?
[ "$rc" -ne 0 ] && grep -q 'OFFENDER loomwright/scripts/test-new.sh' "$tmp/out" && ok "2. a test without the line fails the gate, named" \
  || no "2. rc=$rc: $(cat "$tmp/out")"

echo "== 3. adding the line => green again =="
write_test "$tmp/r/loomwright/scripts/test-new.sh" "$SRC_FLAT"
run; rc=$?
[ "$rc" -eq 0 ] && grep -q '4/4 covered tests' "$tmp/out" && ok "3. the fixed test turns the gate green (4/4)" || no "3. rc=$rc: $(cat "$tmp/out")"

echo "== 4. source line after \`set -u\` => red =="
write_test "$tmp/r/loomwright/scripts/test-new.sh" "$SRC_FLAT" after-set
run; rc=$?
[ "$rc" -ne 0 ] && grep -q 'OFFENDER loomwright/scripts/test-new.sh' "$tmp/out" && ok "4. a source line placed after set -u is red" \
  || no "4. rc=$rc: $(cat "$tmp/out")"

echo "== 5. source line after other code => red =="
write_test "$tmp/r/loomwright/scripts/test-new.sh" "$SRC_FLAT" after-code
run; rc=$?
[ "$rc" -ne 0 ] && grep -q 'OFFENDER loomwright/scripts/test-new.sh' "$tmp/out" && ok "5. a source line placed after other code is red" \
  || no "5. rc=$rc: $(cat "$tmp/out")"

echo "== 6. canonical form but a path that does not exist => red =="
fresh_tree
write_test "$tmp/r/loomwright/scripts/adapters/tool/test-b.sh" "$SRC_FLAT"   # flat path from one level deeper
run; rc=$?
[ "$rc" -ne 0 ] && grep -q 'OFFENDER loomwright/scripts/adapters/tool/test-b.sh.*does not exist' "$tmp/out" \
  && ok "6. a wrong relative helper path is red" || no "6. rc=$rc: $(cat "$tmp/out")"

echo "== 7. adapter and root-scripts globs are covered =="
fresh_tree
write_test "$tmp/r/loomwright/scripts/adapters/tool/test-b.sh" ""
write_test "$tmp/r/scripts/test-c.sh" ""
run; rc=$?
[ "$rc" -ne 0 ] && grep -q 'OFFENDER loomwright/scripts/adapters/tool/test-b.sh' "$tmp/out" && grep -q 'OFFENDER scripts/test-c.sh' "$tmp/out" \
  && grep -q '2 of 3 covered tests' "$tmp/out" && ok "7. offenders under adapters/*/ and scripts/ are both named (2 of 3)" \
  || no "7. rc=$rc: $(cat "$tmp/out")"

echo "== 8. zero covered files => red =="
rm -rf "$tmp/r"; mkdir -p "$tmp/r/loomwright/scripts"
run; rc=$?
[ "$rc" -ne 0 ] && grep -q 'matched nothing' "$tmp/out" && ok "8. an empty tree fails closed" || no "8. rc=$rc: $(cat "$tmp/out")"

echo "== 9. the real tree is green =="
bash "$CHECK" > "$tmp/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "9. real tree: $(cat "$tmp/out")" || no "9. real tree rc=$rc: $(cat "$tmp/out")"

echo
echo "test-check-test-hermetic: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
