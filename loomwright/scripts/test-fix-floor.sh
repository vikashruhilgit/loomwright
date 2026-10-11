#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-fix-floor.sh — table-driven self-tests for fix-floor.sh.
# Exit 0 = all pass, 1 = any failure. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# Covers:
#   R.  resolve precedence: flag > config `.fix_floor` > default MEDIUM;
#       case-insensitive; absent file / absent key / null ⇒ default.
#   C.  resolve fails CLOSED (exit 2, empty stdout): bad flag, bad config
#       level, non-string level, unparseable / trailing-junk / non-object
#       config, missing flag value, unknown argument.
#   M.  meets: the full severity × floor table; BLOCKING always fixes; an
#       absent or unrecognised severity fixes (never a silent pass).
#   S.  split: order kept, non-object ⇒ fix, refusal of a non-array.
#   X.  usage: no / unknown subcommand ⇒ 2 with empty stdout.
#   K.  MUTATION CONTROLS against COPIES: `-ge` → `-gt` in meets; dropping
#       the unknown-severity guard; defaulting instead of refusing a bad
#       config level.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/fix-floor.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-ff.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# root_with <name> <config body | ABSENT> — a project root, prints its path.
root_with() {
  local r="$TMP/$1"
  mkdir -p "$r/.supervisor"
  if [ "$2" != "ABSENT" ]; then printf '%s' "$2" > "$r/.supervisor/config.json"; fi
  printf '%s' "$r"
}

# expect <script> <desc> <want-stdout> <args...> — exit 0 and exact stdout.
expect() {
  local s="$1" desc="$2" want="$3"; shift 3
  local got rc
  got="$(bash "$s" "$@" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then ok "$desc"; else no "$desc — rc=$rc got [$got] want [$want]"; fi
}

# refused <script> <desc> <args...> — exit 2, empty stdout, a reason on stderr.
refused() {
  local s="$1" desc="$2"; shift 2
  local out err rc
  out="$(bash "$s" "$@" 2>"$TMP/err")"; rc=$?
  err="$(cat "$TMP/err")"
  if [ "$rc" -eq 2 ] && [ -z "$out" ] && [ -n "$err" ]; then ok "$desc"; else no "$desc — rc=$rc out [$out] err [$err]"; fi
}

run_table() {
  local s="$1" r
  # R — precedence
  r="$(root_with none ABSENT)"
  expect "$s" "R1 no config ⇒ MEDIUM" MEDIUM resolve --root "$r"
  expect "$s" "R2 flag wins over no config" LOW resolve --flag low --root "$r"
  r="$(root_with high '{"fix_floor":"High","auto_review":false}')"
  expect "$s" "R3 config level, case-insensitive" HIGH resolve --root "$r"
  expect "$s" "R4 flag wins over config" MEDIUM resolve --flag MEDIUM --root "$r"
  expect "$s" "R5 empty flag falls through to config" HIGH resolve --flag "" --root "$r"
  r="$(root_with nokey '{"auto_review":false}')"
  expect "$s" "R6 absent key ⇒ MEDIUM" MEDIUM resolve --root "$r"
  r="$(root_with null '{"fix_floor":null}')"
  expect "$s" "R7 null ⇒ MEDIUM" MEDIUM resolve --root "$r"

  # C — fail closed
  refused "$s" "C1 bad flag" resolve --flag medum --root "$r"
  refused "$s" "C2 BLOCKING is not a floor" resolve --flag BLOCKING --root "$r"
  r="$(root_with bad '{"fix_floor":"bogus"}')"
  refused "$s" "C3 bad config level" resolve --root "$r"
  r="$(root_with num '{"fix_floor":2}')"
  refused "$s" "C4 non-string config level" resolve --root "$r"
  r="$(root_with junk '{"fix_floor":"LOW"} junk')"
  refused "$s" "C5 trailing junk after the object" resolve --root "$r"
  r="$(root_with arr '["LOW"]')"
  refused "$s" "C6 config is not an object" resolve --root "$r"
  r="$(root_with garbage 'not json')"
  refused "$s" "C7 unparseable config" resolve --root "$r"
  refused "$s" "C8 --flag with no value" resolve --flag
  refused "$s" "C9 unknown resolve argument" resolve --nope

  # M — the full table
  local sev fl want
  for row in \
    "BLOCKING HIGH fix" "HIGH HIGH fix" "MEDIUM HIGH pass" "LOW HIGH pass" \
    "BLOCKING MEDIUM fix" "HIGH MEDIUM fix" "MEDIUM MEDIUM fix" "LOW MEDIUM pass" \
    "BLOCKING LOW fix" "HIGH LOW fix" "MEDIUM LOW fix" "LOW LOW fix" \
    "medium high pass" "INFO LOW fix" "weird HIGH fix"; do
    set -- $row; sev="$1"; fl="$2"; want="$3"
    expect "$s" "M $sev @ $fl ⇒ $want" "$want" meets "$sev" "$fl"
  done
  expect "$s" "M empty severity ⇒ fix" fix meets "" HIGH
  refused "$s" "M bad floor refused" meets HIGH BLOCKING
  refused "$s" "M wrong arity refused" meets HIGH

  # S — split
  printf '%s' '[{"severity":"LOW","n":1},{"severity":"MEDIUM","n":2},{"n":3},"s",{"severity":"HIGH","n":5}]' > "$TMP/issues.json"
  expect "$s" "S1 split @ MEDIUM keeps order, unknown ⇒ fix" \
    '{"fix":[{"severity":"MEDIUM","n":2},{"n":3},"s",{"severity":"HIGH","n":5}],"pass":[{"severity":"LOW","n":1}]}' \
    split MEDIUM "$TMP/issues.json"
  expect "$s" "S2 split @ HIGH" \
    '{"fix":[{"n":3},"s",{"severity":"HIGH","n":5}],"pass":[{"severity":"LOW","n":1},{"severity":"MEDIUM","n":2}]}' \
    split high "$TMP/issues.json"
  expect "$s" "S3 empty array" '{"fix":[],"pass":[]}' split LOW - <<<'[]'
  refused "$s" "S4 object is not an array" split LOW - <<<'{}'
  refused "$s" "S5 bad floor" split NONE "$TMP/issues.json"

  # X — usage
  refused "$s" "X1 no subcommand"
  refused "$s" "X2 unknown subcommand" decide
}

echo "test-fix-floor.sh"
run_table "$SCRIPT"

# K — mutation controls: each mutant must turn at least one case red.
mutant() {
  local name="$1" expr="$2" m="$TMP/mut-$1.sh"
  sed -e "$expr" "$SCRIPT" > "$m"
  if [ ! -s "$m" ] || cmp -s "$m" "$SCRIPT" || ! bash -n "$m" 2>/dev/null; then
    no "K $name — mutant did not apply"; return 1
  fi
  printf '%s' "$m"
}
for spec in \
  'ge-to-gt|s/\[ "\$r" -ge "\$f" \]/[ "$r" -gt "$f" ]/' \
  'unknown-sev|s/if \[ "\$r" -eq 0 \] || /if /' \
  'bad-config-defaults|s/\[ -n "\$c" \] || refuse .*$/[ -n "$c" ] || c="$DEFAULT_FLOOR"/'; do
  name="${spec%%|*}"; expr="${spec#*|}"
  m="$(mutant "$name" "$expr")" || continue
  saved_pass=$pass; saved_fail=$fail
  mout="$(run_table "$m")"
  pass=$saved_pass; fail=$saved_fail
  reds="$(printf '%s\n' "$mout" | grep -c '  FAIL: ' || true)"
  if [ "${reds:-0}" -ge 1 ]; then ok "K $name — mutant turns $reds case(s) red"; else no "K $name — mutant SURVIVED the table"; fi
done

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
