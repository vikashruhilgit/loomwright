#!/usr/bin/env bash
# test-part-groups-lib.sh — self-test for part-groups-lib.sh (pg_select / pg_want), the selection a
# parted suite's entry and its test-<x>.<g>.sh pool entries share. Offline: every case builds a scratch
# entry + siblings in its own temp dir. A mutation control per fail-closed check that guards the pool's
# coverage (a part in no group, a sibling exec-ing another group): each mutant must
# turn its case red. Exit 0 = all pass. Bash 3.2 / BSD safe.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/part-groups-lib.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

W="$(mktemp -d "${TMPDIR:-/tmp}/test-part-groups-lib.XXXXXX")" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$W"' EXIT

PARTS="01-a 02-b 03-c 04-d"
GROUPS_OK="1=01-a 2=04-d,02-b 3=03-c"

# fixture <dir> <n>… — an entry test-x.sh plus a well-formed sibling test-x.<n>.sh per <n>
fixture() {
  local d="$1" n; shift
  rm -rf "$d"; mkdir -p "$d"; : > "$d/test-x.sh"
  for n in "$@"; do
    printf '%s\n' '#!/usr/bin/env bash' \
      "exec \"\${BASH:-bash}\" \"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)/test-x.sh\" --group $n" > "$d/test-x.$n.sh"
  done
}
# sel <lib> <dir> <groups> [<arg>…] — pg_select in a subshell; prints `rc|PG_SEL|PG_LABEL|output`
sel() {
  local lib="$1" d="$2" g="$3"; shift 3
  ( . "$lib"; out="$(pg_select "$d/test-x.sh" "$PARTS" "$g" "$@")"; rc=$?
    if [ "$rc" -eq 0 ]; then pg_select "$d/test-x.sh" "$PARTS" "$g" "$@" >/dev/null; fi
    printf '%s|%s|%s|%s' "$rc" "${PG_SEL:-}" "${PG_LABEL:-}" "$out" )
}
rc_of() { printf '%s' "${1%%|*}"; }

echo "== selection =="
fixture "$W/ok" 2 3
r="$(sel "$LIB" "$W/ok" "$GROUPS_OK")"
[ "$(rc_of "$r")" = 0 ] && case "$r" in "0| 01-a |group 1/3 (01-a)|") true ;; *) false ;; esac \
  && ok "no argument ⇒ group 1 only" || no "no argument: $r"
r="$(sel "$LIB" "$W/ok" "$GROUPS_OK" --group 2)"
case "$r" in "0| 02-b 04-d |group 2/3 (02-b 04-d)|") ok "--group 2 ⇒ its parts in base order (declared 04-d,02-b)" ;; *) no "--group 2: $r" ;; esac
r="$(sel "$LIB" "$W/ok" "$GROUPS_OK" --all)"
case "$r" in "0| 01-a 02-b 03-c 04-d |all parts (01-a 02-b 03-c 04-d)|") ok "--all ⇒ every part, base order" ;; *) no "--all: $r" ;; esac
( . "$LIB"; PG_SEL=" 01-a 03-c "; pg_want 03-c && ! pg_want 02-b && ! pg_want 03 ) && ok "pg_want matches whole part names only" || no "pg_want"
fixture "$W/mod" 2 3; : > "$W/mod/test-x.modules.sh"
[ "$(rc_of "$(sel "$LIB" "$W/mod" "$GROUPS_OK")")" = 0 ] && ok "a non-numeric test-x.<word>.sh is not a pool entry (ignored)" || no "test-x.modules.sh refused"

echo "== the map fails closed =="
# case_fail <label> <expected FAIL substring> <dir> <groups> [<arg>…]
case_fail() {
  local label="$1" want="$2" d="$3" g="$4" r; shift 4
  r="$(sel "$LIB" "$d" "$g" "$@")"
  if [ "$(rc_of "$r")" = 1 ] && case "$r" in *"FAIL: part-groups: "*"$want"*) true ;; *) false ;; esac; then ok "$label"
  else no "$label: $r"; fi
}
case_fail "a part in no group ⇒ refused" "part in no group" "$W/ok" "1=01-a 2=02-b 3=03-c"
case_fail "a part in two groups ⇒ refused" "part in two groups: 02-b" "$W/ok" "1=01-a,02-b 2=04-d,02-b 3=03-c"
case_fail "a group naming an unknown part ⇒ refused" "unknown part: 05-e" "$W/ok" "1=01-a,05-e 2=04-d,02-b 3=03-c"
fixture "$W/gap" 3
case_fail "group numbers with a gap ⇒ refused" "not 1..2" "$W/gap" "1=01-a,02-b,04-d 3=03-c"
case_fail "a group declared twice ⇒ refused" "declared twice" "$W/ok" "1=01-a 1=04-d,02-b 3=03-c"
case_fail "an empty group ⇒ refused" "has no parts" "$W/ok" "1=01-a,02-b,03-c,04-d 2= 3=01-a"
case_fail "group 0 ⇒ refused" "positive integer" "$W/ok" "0=01-a 2=04-d,02-b 3=03-c"
fixture "$W/miss" 2
case_fail "a missing sibling ⇒ refused" "missing pool entry for group 3: test-x.3.sh" "$W/miss" "$GROUPS_OK"
fixture "$W/wrong" 2 3; sed 's/--group 3$/--group 2/' "$W/wrong/test-x.3.sh" > "$W/wrong/t" && mv "$W/wrong/t" "$W/wrong/test-x.3.sh"
case_fail "a sibling exec-ing another group ⇒ refused" "test-x.3.sh does not exec group 3" "$W/wrong" "$GROUPS_OK"
fixture "$W/extra" 2 3 4
case_fail "a sibling for an undeclared group ⇒ refused" "test-x.4.sh is a pool entry for no declared group" "$W/extra" "$GROUPS_OK"
case_fail "--group naming no group ⇒ refused" "no group '9'" "$W/ok" "$GROUPS_OK" --group 9
case_fail "an unknown argument ⇒ refused" "unknown argument: 02-b" "$W/ok" "$GROUPS_OK" 02-b

echo "== mutation controls (each mutant must turn its case red) =="
# mutant <name> <fixed string of the line to neuter> — a lib copy with that line replaced by `:`; gated:
# exactly one line matches, the copy differs and parses
mutant() {
  local m="$W/mut-$1.sh" c
  c="$(grep -cF -- "$2" "$LIB")"; [ "$c" = 1 ] || { echo "anchor occurs $c time(s)" >&2; return 1; }
  AN="$2" awk 'index($0, ENVIRON["AN"]) { print "    :"; next } { print }' "$LIB" > "$m" && ! cmp -s "$LIB" "$m" && bash -n "$m" 2>/dev/null || return 1
  printf '%s' "$m"
}
if m="$(mutant noowner 'part in no group (it would never run in the pool)')"; then
  [ "$(rc_of "$(sel "$m" "$W/ok" "1=01-a 2=02-b 3=03-c")")" = 0 ] && ok "M-noowner: without the no-group check a dropped part passes (control)" \
    || no "M-noowner: the mutant still refuses — the case does not pin the check"
else no "M-noowner: mutant not built"; fi
if m="$(mutant noline 'grep -qxF -- "$line" "$sib" ||')"; then
  [ "$(rc_of "$(sel "$m" "$W/wrong" "$GROUPS_OK")")" = 0 ] && ok "M-noline: without the exec-line check a sibling running another group passes (control)" \
    || no "M-noline: the mutant still refuses"
else no "M-noline: mutant not built"; fi

echo
echo "test-part-groups-lib: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
