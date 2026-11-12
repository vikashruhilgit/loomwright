#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-launch-pad-phase.sh — pins launch-pad-phase.sh's output lines.
# Exit 0 = all pass, 1 = any failure. UNCOUNTED by the doc-currency gate (test-*.sh).
#
# Covers:
#   L.  the exact marker line for every phase id in the table.
#   W.  verdict handling: multi-arg join, whitespace collapse, a literal `*`.
#   R.  refusals (exit 2, empty stdout): unknown id, no verdict, blank
#       verdict, an over-long verdict, no args.
#   T.  the table: `--list` prints exactly the nine phases in run order.
#   P.  prompt wiring: every phase the table names is called with its id from
#       agents/launch-pad.md AND commands/launch-pad.md, so a phase the
#       prompt drops (or an id the table lacks) turns this red.
#   K.  MUTATION CONTROLS against COPIES: a dropped table row; an unknown id
#       printed instead of refused; the em-dash separator changed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/launch-pad-phase.sh"
AGENT="$HERE/../agents/launch-pad.md"
CMD="$HERE/../commands/launch-pad.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-lpp.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# expect <script> <desc> <want-stdout> <args...> — exit 0 and exact stdout.
expect() {
  local s="$1" desc="$2" want="$3"; shift 3
  local got rc
  got="$(bash "$s" "$@" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then ok "$desc"; else no "$desc — rc=$rc got [$got] want [$want]"; fi
}

# refuse <script> <desc> <args...> — exit 2, empty stdout, non-empty stderr.
refuse() {
  local s="$1" desc="$2"; shift 2
  local got err rc
  got="$(bash "$s" "$@" 2>"$TMP/err")"; rc=$?
  err="$(cat "$TMP/err")"
  if [ "$rc" -eq 2 ] && [ -z "$got" ] && [ -n "$err" ]; then ok "$desc"; else no "$desc — rc=$rc out [$got] err [$err]"; fi
}

run_table() {
  local s="$1"
  echo "L. marker lines"
  expect "$s" "L 1"   '## Phase 1: VALIDATE — 0 blockers, 1 warning'  1 '0 blockers, 1 warning'
  expect "$s" "L 2"   '## Phase 2: DISCOVER — 3 criteria'             2 '3 criteria'
  expect "$s" "L 2.5" '## Phase 2.5: FEASIBILITY — CAUTION'           2.5 CAUTION
  expect "$s" "L 3"   '## Phase 3: ANALYZE — 2 modify, 1 create'      3 '2 modify, 1 create'
  expect "$s" "L 4"   '## Phase 4: DECOMPOSE — 1 subtask'             4 '1 subtask'
  expect "$s" "L 5"   '## Phase 5: PACKAGE — brief assembled'         5 'brief assembled'
  expect "$s" "L 5.5" '## Phase 5.5: PLAN REVIEW — PASS (attempt 1/3)' 5.5 'PASS (attempt 1/3)'
  expect "$s" "L 6"   '## Phase 6: SAVE — saved .supervisor/jobs/pending/x.md' 6 saved .supervisor/jobs/pending/x.md
  expect "$s" "L 7"   '## Phase 7: RESULT — status saved'             7 status saved

  echo "W. verdict handling"
  expect "$s" "W args joined"        '## Phase 2.5: FEASIBILITY — GO with notes' 2.5 GO with notes
  expect "$s" "W whitespace collapsed" '## Phase 4: DECOMPOSE — 1 subtask, LAUNCHABLE' 4 "$(printf '  1 subtask,\n\tLAUNCHABLE  ')"
  expect "$s" "W literal star kept"  '## Phase 3: ANALYZE — src/* files' 3 'src/* files'

  echo "R. refusals"
  refuse "$s" "R unknown id"      2.7 'no trigger'
  refuse "$s" "R id with suffix"  1a ok
  refuse "$s" "R no verdict"      3
  refuse "$s" "R blank verdict"   3 "$(printf ' \n\t ')"
  refuse "$s" "R over-long"       3 "$(printf '%0161d' 0)"
  refuse "$s" "R no args"
  expect "$s" "R 160 chars is allowed" "## Phase 3: ANALYZE — $(printf '%0160d' 0)" 3 "$(printf '%0160d' 0)"

  echo "T. table"
  expect "$s" "T --list" "$(printf '1 VALIDATE\n2 DISCOVER\n2.5 FEASIBILITY\n3 ANALYZE\n4 DECOMPOSE\n5 PACKAGE\n5.5 PLAN REVIEW\n6 SAVE\n7 RESULT')" --list
  refuse "$s" "T --list takes no args" --list extra
}

run_table "$SCRIPT"

echo "P. prompt wiring"
ids="$(bash "$SCRIPT" --list | cut -d' ' -f1)"
for f in "$AGENT" "$CMD"; do
  for id in $ids; do
    # The call must name this exact id: `launch-pad-phase.sh 2.5 `, never 2.5x.
    if grep -qF "launch-pad-phase.sh $id " "$f"; then
      ok "P $(basename "$(dirname "$f")")/$(basename "$f") calls phase $id"
    else
      no "P $(basename "$(dirname "$f")")/$(basename "$f") has no \`launch-pad-phase.sh $id \` call"
    fi
  done
  # Every id the prompt passes must be one the table knows.
  for used in $(grep -oE 'launch-pad-phase\.sh [0-9][0-9.]*' "$f" | cut -d' ' -f2 | sort -u); do
    if printf '%s\n' "$ids" | grep -qxF "$used"; then ok "P $(basename "$f") id $used is in the table"; else no "P $(basename "$f") passes unknown id $used"; fi
  done
done

echo "K. mutation controls"
mutant() {
  local name="$1" expr="$2" m="$TMP/mut-$1.sh"
  sed -E "$expr" "$SCRIPT" > "$m"
  if cmp -s "$m" "$SCRIPT"; then no "K $name — sed changed nothing"; return 1; fi
  printf '%s' "$m"
}
for spec in \
  'drop-row|/^2\.5\|FEASIBILITY$/d' \
  'print-unknown|s/^  exit 2$/  :/' \
  'separator|s/^printf .## Phase %s: %s — %s\\n.*/printf "## Phase %s: %s - %s\\n" "$phase" "$name" "$verdict"/'; do
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
