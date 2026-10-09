#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-drain-subfloor-decision.sh — table-driven self-tests for
# drain-subfloor-decision.sh (implementation-quality/02, Part T01).
# Exit 0 = all pass, 1 = any failure. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# Covers:
#   R.  replay of the 2026-10-08 PR #435 round 1 (one LOW finding, floor HIGH)
#       ⇒ eligible prints `confirm`; decide on a green SETTLED line + rules
#       `none` ⇒ READY sub_floor_converged with exactly that one finding.
#   E.  every eligible row (HIGH / MEDIUM-at-floor, required_failing,
#       needs_human, empty auto_fixable, garbage/missing input, unknown
#       severity, unknown floor) ⇒ `continue`.
#   D.  every decide row (red ± repeat_check_failure, unknown, ELAPSED, sha
#       mismatch, empty/garbage line, rules fail/unresolved/unreadable,
#       unstamped after a remembered fail) and the passable verdicts.
#   T.  a two-round drain: `sub_floor_fixed` holds the FINAL round's findings only.
#   X.  exit codes: unknown subcommand ⇒ 2 with empty stdout.
#       Free-text names: a space-named red check round-trips (D18/D20), and a
#       pending name containing ` required=`/` sha=` cannot override them (D19).
#   F.  (fix-now C) a value-taking flag followed directly by another `--flag`
#       (an empty list rendered as nothing) keeps its empty default and never
#       swallows the next flag or its value; the quoted "" form; stderr reason.
#   M.  MUTATION CONTROLS against COPIES (gated non-empty + differs + bash -n):
#       `<` → `<=` in the severity comparison; dropping the required=green test;
#       dropping the `--…`-value refusal; restoring the whitespace `set --`
#       split of the wait line; restoring the stream (non-slurped) round read.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/drain-subfloor-decision.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-dsd.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

SHA_OK="77fc06b0000000000000000000000000000000aa"
GREEN="SETTLED sha=$SHA_OK required=green review_producing=settled"
LOW_ROUND='{"required_failing":[],"needs_human":[],"auto_fixable":[{"id":"darwin-click-action","title":"Darwin CLICK_ACTION mirror in lane-park-notify","severity":"LOW"}],"severity_floor":"HIGH"}'

# rf <name> <json> — write a round fixture, print its path.
rf() { printf '%s' "$2" > "$TMP/$1.json"; printf '%s' "$TMP/$1.json"; }

# expect <script> <desc> <want-stdout> <args...>
expect() {
  local s="$1" desc="$2" want="$3"; shift 3
  local got; got="$(bash "$s" "$@" 2>/dev/null)"
  if [ "$got" = "$want" ]; then ok "$desc"; else no "$desc — want [$want] got [$got]"; fi
}
dec() { local s="$1" desc="$2" want="$3" round="$4" line="$5" rules="$6"; shift 6
  expect "$s" "$desc" "$want" decide "$round" --sha "$SHA_OK" --wait-line "$line" --rules "$rules" "$@"; }

# run_table <script> — the whole decision table; the mutation controls rerun it.
run_table() {
  local s="$1" r_low
  r_low="$(rf low "$LOW_ROUND")"
  echo "== R. replay 2026-10-08 round 1 =="
  expect "$s" "R1 eligible ⇒ confirm" "confirm" eligible "$r_low"
  dec "$s" "R2 decide green+none ⇒ READY with the one finding" \
    "READY sub_floor_converged sub_floor_fixed=[{\"id\":\"darwin-click-action\",\"title\":\"Darwin CLICK_ACTION mirror in lane-park-notify\",\"severity\":\"LOW\"}]" \
    "$r_low" "$GREEN" none
  expect "$s" "R3 eligible via stdin ⇒ confirm" "confirm" eligible - <<<"$LOW_ROUND"

  echo "== E. eligible rows =="
  expect "$s" "E1 HIGH at floor HIGH ⇒ continue" continue eligible \
    "$(rf e1 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"severity":"HIGH"}],"severity_floor":"HIGH"}')"
  expect "$s" "E2 MEDIUM at floor MEDIUM ⇒ continue" continue eligible \
    "$(rf e2 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"severity":"LOW"},{"severity":"MEDIUM"}],"severity_floor":"MEDIUM"}')"
  expect "$s" "E3 MEDIUM under floor HIGH ⇒ confirm" confirm eligible \
    "$(rf e3 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"severity":"medium"},{"severity":"LOW"}],"severity_floor":"HIGH"}')"
  expect "$s" "E4 required_failing != [] ⇒ continue" continue eligible \
    "$(rf e4 '{"required_failing":["ci"],"needs_human":[],"auto_fixable":[{"severity":"LOW"}],"severity_floor":"HIGH"}')"
  expect "$s" "E5 needs_human != [] ⇒ continue" continue eligible \
    "$(rf e5 '{"required_failing":[],"needs_human":[{"severity":"LOW"}],"auto_fixable":[{"severity":"LOW"}],"severity_floor":"HIGH"}')"
  expect "$s" "E6 auto_fixable == [] ⇒ continue" continue eligible \
    "$(rf e6 '{"required_failing":[],"needs_human":[],"auto_fixable":[],"severity_floor":"HIGH"}')"
  expect "$s" "E7 garbage input ⇒ continue" continue eligible "$(rf e7 'not json {')"
  expect "$s" "E8 missing file ⇒ continue" continue eligible "$TMP/absent.json"
  # a valid leading object followed by junk / a second object is malformed as a WHOLE (a stream
  # read printed the leading object, so `decide` said READY on input that does not parse)
  expect "$s" "E7b object + trailing junk ⇒ continue" continue eligible "$(rf e7b "$LOW_ROUND garbage{")"
  expect "$s" "E7c two objects ⇒ continue" continue eligible "$(rf e7c "$LOW_ROUND{\"x\":1}")"
  dec "$s" "E7d decide on object + trailing junk ⇒ continue (never READY)" continue "$TMP/e7b.json" "$GREEN" none
  expect "$s" "E9 no input arg ⇒ continue" continue eligible
  expect "$s" "E10 unknown finding severity ⇒ continue" continue eligible \
    "$(rf e10 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"severity":"LOW"},{"severity":"TRIVIAL"}],"severity_floor":"HIGH"}')"
  expect "$s" "E11 absent finding severity ⇒ continue" continue eligible \
    "$(rf e11 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"title":"x"}],"severity_floor":"HIGH"}')"
  expect "$s" "E12 unknown floor ⇒ continue" continue eligible \
    "$(rf e12 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"severity":"LOW"}],"severity_floor":"URGENT"}')"
  expect "$s" "E13 non-array field ⇒ continue" continue eligible \
    "$(rf e13 '{"required_failing":"none","needs_human":[],"auto_fixable":[{"severity":"LOW"}],"severity_floor":"HIGH"}')"
  expect "$s" "E14 LOW under floor MEDIUM ⇒ confirm" confirm eligible \
    "$(rf e14 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"severity":"LOW"}],"severity_floor":"MEDIUM"}')"

  echo "== D. decide rows =="
  local RED="SETTLED sha=$SHA_OK required=red review_producing=settled pending_names=none red_names=ci@123"
  dec "$s" "D1 required=red, ci never fixed ⇒ ESCALATED false" "ESCALATED repeat_check_failure=false" "$r_low" "$RED" none
  dec "$s" "D2 required=red, ci in checks_ever_fixed ⇒ ESCALATED true" "ESCALATED repeat_check_failure=true" \
    "$r_low" "$RED" none --checks-ever-fixed "lint,ci"
  dec "$s" "D3 required=unknown ⇒ ESCALATED" "ESCALATED repeat_check_failure=false" \
    "$r_low" "SETTLED sha=$SHA_OK required=unknown review_producing=settled" none --checks-ever-fixed ci
  dec "$s" "D4 ELAPSED ⇒ ESCALATED" "ESCALATED repeat_check_failure=false" \
    "$r_low" "ELAPSED sha=$SHA_OK required=pending review_producing=settled pending=none" none
  dec "$s" "D5 sha mismatch ⇒ ESCALATED" "ESCALATED repeat_check_failure=false" \
    "$r_low" "SETTLED sha=842cbe7 required=green review_producing=settled" none
  dec "$s" "D6 empty line ⇒ ESCALATED" "ESCALATED repeat_check_failure=false" "$r_low" "" none
  dec "$s" "D7 garbage line ⇒ ESCALATED" "ESCALATED repeat_check_failure=false" "$r_low" "* garbage required=green" none
  expect "$s" "D8 no --wait-line ⇒ ESCALATED" "ESCALATED repeat_check_failure=false" decide "$r_low" --sha "$SHA_OK" --rules none
  expect "$s" "D9 no --sha ⇒ ESCALATED" "ESCALATED repeat_check_failure=false" decide "$r_low" --wait-line "$GREEN" --rules none
  dec "$s" "D10 green + rules fail ⇒ continue" continue "$r_low" "$GREEN" fail
  dec "$s" "D11 green + rules unresolved ⇒ continue" continue "$r_low" "$GREEN" unresolved
  dec "$s" "D12 green + rules unreadable ⇒ continue" continue "$r_low" "$GREEN" unreadable
  dec "$s" "D13 green + unrecognised verdict ⇒ continue" continue "$r_low" "$GREEN" maybe
  dec "$s" "D14 green + missing verdict ⇒ continue" continue "$r_low" "$GREEN" ""
  dec "$s" "D15 green + unstamped after remembered fail ⇒ continue" continue "$r_low" "$GREEN" unstamped --rules-failed-seen "R1"
  local v
  for v in ok unstamped cmd_disabled; do
    case "$(bash "$s" decide "$r_low" --sha "$SHA_OK" --wait-line "$GREEN" --rules "$v" 2>/dev/null)" in
      "READY sub_floor_converged sub_floor_fixed="*) ok "D16 green + rules $v ⇒ READY" ;;
      *) no "D16 green + rules $v ⇒ READY" ;;
    esac
  done
  dec "$s" "D17 decide on a non-eligible round ⇒ continue" continue \
    "$(rf d17 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"severity":"HIGH"}],"severity_floor":"HIGH"}')" "$GREEN" none
  local RED_SP="SETTLED sha=$SHA_OK required=red review_producing=settled pending_names=none red_names=lint@7,build (ubuntu-latest)@99"
  dec "$s" "D18 space-named red check in checks_ever_fixed ⇒ ESCALATED true" "ESCALATED repeat_check_failure=true" \
    "$r_low" "$RED_SP" none --checks-ever-fixed "build (ubuntu-latest)"
  dec "$s" "D19 pending name containing ' required=' / ' sha=' cannot override them ⇒ READY" \
    "READY sub_floor_converged sub_floor_fixed=[{\"id\":\"darwin-click-action\",\"title\":\"Darwin CLICK_ACTION mirror in lane-park-notify\",\"severity\":\"LOW\"}]" \
    "$r_low" "SETTLED sha=$SHA_OK required=green review_producing=settled pending_names=odd required=red sha=0bad red_names=none" none
  dec "$s" "D20 only the first word of a space-named red check was fixed ⇒ ESCALATED false" "ESCALATED repeat_check_failure=false" \
    "$r_low" "$RED_SP" none --checks-ever-fixed "build"
  echo "== F. a value-taking flag never swallows the next --flag (an empty list rendered as nothing) =="
  dec "$s" "F1 bare --rules-failed-seen before --checks-ever-fixed ci: ci is kept ⇒ ESCALATED true" "ESCALATED repeat_check_failure=true" \
    "$r_low" "$RED" none --rules-failed-seen --checks-ever-fixed ci
  dec "$s" "F2 bare --rules-failed-seen is EMPTY (not '--checks-ever-fixed') ⇒ unstamped green ⇒ READY" \
    "READY sub_floor_converged sub_floor_fixed=[{\"id\":\"darwin-click-action\",\"title\":\"Darwin CLICK_ACTION mirror in lane-park-notify\",\"severity\":\"LOW\"}]" \
    "$r_low" "$GREEN" unstamped --rules-failed-seen --checks-ever-fixed ci
  dec "$s" "F3 a quoted \"\" empty list is the documented form ⇒ ESCALATED true" "ESCALATED repeat_check_failure=true" \
    "$r_low" "$RED" none --rules-failed-seen "" --checks-ever-fixed ci
  dec "$s" "F4 bare --rules before --rules-failed-seen R1: rules stays empty ⇒ continue" continue \
    "$r_low" "$GREEN" --rules-failed-seen R1
  local ferr
  ferr="$(bash "$s" decide "$r_low" --sha "$SHA_OK" --wait-line "$RED" --rules none --rules-failed-seen --checks-ever-fixed ci 2>&1 >/dev/null)"
  case "$ferr" in *"--rules-failed-seen has no value (next arg '--checks-ever-fixed' is a flag)"*) ok "F5 the refused value is named on stderr" ;;
    *) no "F5 no stderr reason for the refused value: [$ferr]" ;; esac
}

run_table "$SCRIPT"

echo "== T. two-round drain: sub_floor_fixed = final round only =="
r1="$(rf t1 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"id":"r1-high","severity":"HIGH"}],"severity_floor":"HIGH"}')"
r2="$(rf t2 '{"required_failing":[],"needs_human":[],"auto_fixable":[{"id":"r2-low","severity":"LOW"}],"severity_floor":"HIGH"}')"
t1="$(bash "$SCRIPT" eligible "$r1" 2>/dev/null)"
t2="$(bash "$SCRIPT" decide "$r2" --sha "$SHA_OK" --wait-line "$GREEN" --rules none 2>/dev/null)"
fixed="${t2#READY sub_floor_converged sub_floor_fixed=}"
if [ "$t1" = "continue" ] && [ "$fixed" != "$t2" ] \
   && [ "$(printf '%s' "$fixed" | jq -r '[.[].id] | join(",")')" = "r2-low" ]; then
  ok "T1 round 1 continues; READY lists only round 2's finding"
else
  no "T1 two-round sub_floor_fixed — r1=[$t1] r2=[$t2]"
fi

echo "== X. exit codes =="
out="$(bash "$SCRIPT" bogus 2>/dev/null)"; rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then ok "X1 unknown subcommand ⇒ exit 2, empty stdout"; else no "X1 rc=$rc out=[$out]"; fi
bash "$SCRIPT" decide "$TMP/low.json" --sha "$SHA_OK" --wait-line "$GREEN" --rules none >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok "X2 READY path exits 0"; else no "X2 READY rc=$rc"; fi

echo "== M. mutation controls (copies only) =="
# mutant <name> <sed-expr> — a gated COPY of the script; prints its path or nothing.
mutant() {
  local m="$TMP/mut-$1.sh"
  sed -e "$2" "$SCRIPT" > "$m"
  if [ ! -s "$m" ]; then no "M $1 — mutant is EMPTY (vacuous control)"; return 1; fi
  if cmp -s "$SCRIPT" "$m"; then no "M $1 — mutation changed NOTHING (vacuous control)"; return 1; fi
  if ! bash -n "$m" 2>/dev/null; then no "M $1 — mutant does not parse (vacuous control)"; return 1; fi
  printf '%s' "$m"
}
# stream: restore the pre-fix stream read (accepts a leading object followed by junk).
STREAM_SPEC="stream|s/-cse 'if length == 1 and (.\\[0\\] | type) == \"object\" then .\\[0\\] else empty end'/-ce 'select(type == \"object\")'/"
for spec in 'le|s/all(\. < \$floor)/all(. <= $floor)/' \
            'nogreen|s/^if \[ "\$required" != "green" \]; then   # GREEN-REQUIRED.*/if false; then/' \
            'flagguard|/^    --\*) reason "\$1 has no value/d' \
            "$STREAM_SPEC" \
            'wsplit|s/   # RED-NAMES-REMAINDER$/; set -f; set -- $_wl; set +f; for tok in "$@"; do case "$tok" in sha=*) line_sha="${tok#sha=}" ;; required=*) required="${tok#required=}" ;; red_names=*) red_names="${tok#red_names=}" ;; esac; done/'; do
  name="${spec%%|*}"; expr="${spec#*|}"
  m="$(mutant "$name" "$expr")" || continue
  [ -n "$m" ] || continue
  saved_pass=$pass; saved_fail=$fail
  mout="$(run_table "$m")"
  pass=$saved_pass; fail=$saved_fail
  reds="$(printf '%s\n' "$mout" | grep -c '  FAIL: ' || true)"
  if [ "${reds:-0}" -ge 1 ]; then ok "M $name — mutant turns $reds case(s) red"; else no "M $name — mutant SURVIVED the table"; fi
done

echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
