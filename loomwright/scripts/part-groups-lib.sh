#!/usr/bin/env bash
# part-groups-lib.sh — run ONE pool group of a parted self-test, so run-self-tests.sh can run a long
# suite's parts concurrently. Sourced, never run: deliberately not named test-*.sh (the pool glob would
# run it as a test). Self-test: loomwright/scripts/test-part-groups-lib.sh.
#
# Why: the pool runs each test-*.sh as ONE job under a 900 s per-test cap (SELF_TEST_TIMEOUT). A suite
# whose legs live in test-<x>.d/ parts but are all sourced by one entry is still one job:
# test-automate-next-step.sh and test-automate-trail.sh took 700–755 s on a quiet machine (78–84 % of
# the cap) and both hit it (exit 124) at load average 32–34 on 2026-11-02, stopping wave-build before
# its push although every assertion they reached passed. A bigger cap only moves that wall.
#
# Layout: group 1 runs from the entry test-<x>.sh; group <g> >= 2 runs from a sibling pool entry
# test-<x>.<g>.sh beside it, whose only work after the hermetic source line is the exact line
#     exec "${BASH:-bash}" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-<x>.sh" --group <g>
# Every group runs the entry's shared setup, then only its own parts, in base order.
#
#   pg_select <entry> <parts> <groups> [<arg>…]
#       <entry>   the entry's path (test-<x>.sh); siblings are looked up beside it
#       <parts>   every part, base order, space-separated
#       <groups>  `<g>=<part>,<part>…` words — g runs 1..N with no gap, every part in exactly one group
#       args      none = group 1 | --group <g> | --all (every part: one process, as before the split)
#     Sets PG_SEL (" <part> … ") and PG_LABEL (e.g. `group 2/3 (03-x 04-y)`). Prints ONE
#     `  FAIL: …` line and returns 1 on: a group naming an unknown part, a part in no group or in two,
#     group numbers not 1..N, a sibling missing or not exec-ing its own group, a test-<x>.<n>.sh for no
#     group, an unknown argument. The caller exits on it: a part is never silently left out of the pool.
#   pg_want <part>    0 when <part> is in PG_SEL
#
# Bash 3.2 / BSD safe; no state outside the PG_* variables and pg_-prefixed locals.

pg_fail() { echo "  FAIL: part-groups: $*"; return 1; }

pg_select() {
  local entry="$1" parts="$2" groups="$3" dir stem w g list p n want_g seen_n=0 f sib line arg
  shift 3
  dir="$(cd "$(dirname "$entry")" && pwd)" || { pg_fail "entry dir unreadable: $entry"; return 1; }
  stem="$(basename "$entry" .sh)"
  # the map: every group's parts are known parts; each part in exactly one group; groups 1..N
  local owned=" " gl=" "
  for w in $groups; do
    g="${w%%=*}"; list="${w#*=}"
    case "$w" in *=*) ;; *) pg_fail "group word without '=': $w"; return 1 ;; esac
    case "$g" in ''|*[!0-9]*|0*) pg_fail "group number not a positive integer: '$g'"; return 1 ;; esac
    case "$gl" in *" $g "*) pg_fail "group $g declared twice"; return 1 ;; esac
    gl="$gl$g "; seen_n=$((seen_n + 1))
    [ -n "$list" ] || { pg_fail "group $g has no parts"; return 1; }
    for p in $(printf '%s' "$list" | tr ',' ' '); do
      case " $parts " in *" $p "*) ;; *) pg_fail "group $g names an unknown part: $p"; return 1 ;; esac
      case "$owned" in *" $p "*) pg_fail "part in two groups: $p"; return 1 ;; esac
      owned="$owned$p "
    done
  done
  [ "$seen_n" -gt 0 ] || { pg_fail "no groups declared"; return 1; }
  n=1; while [ "$n" -le "$seen_n" ]; do
    case "$gl" in *" $n "*) ;; *) pg_fail "groups are not 1..$seen_n (missing $n)"; return 1 ;; esac
    n=$((n + 1))
  done
  for p in $parts; do
    case "$owned" in *" $p "*) ;; *) pg_fail "part in no group (it would never run in the pool): $p"; return 1 ;; esac
  done
  # siblings: one per group >= 2, each exec-ing exactly its own group; none for an undeclared group
  n=2; while [ "$n" -le "$seen_n" ]; do
    sib="$dir/$stem.$n.sh"
    [ -f "$sib" ] || { pg_fail "missing pool entry for group $n: $stem.$n.sh"; return 1; }
    line="exec \"\${BASH:-bash}\" \"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)/$stem.sh\" --group $n"
    grep -qxF -- "$line" "$sib" || { pg_fail "$stem.$n.sh does not exec group $n (want the line: $line)"; return 1; }
    n=$((n + 1))
  done
  for f in "$dir/$stem".*.sh; do
    [ -e "$f" ] || continue
    g="${f#"$dir/$stem".}"; g="${g%.sh}"
    case "$g" in ''|*[!0-9]*|0*) continue ;; esac
    { [ "$g" -ge 2 ] && [ "$g" -le "$seen_n" ]; } || { pg_fail "$(basename "$f") is a pool entry for no declared group (groups 1..$seen_n)"; return 1; }
  done
  # the selection
  want_g=1
  if [ "$#" -gt 0 ]; then
    arg="$1"
    case "$arg" in
      --all) [ "$#" -eq 1 ] || { pg_fail "--all takes nothing after it"; return 1; }
             PG_SEL=" $parts "; PG_LABEL="all parts ($parts)"; return 0 ;;
      --group) [ "$#" -eq 2 ] || { pg_fail "usage: --group <1..$seen_n>"; return 1; }
               want_g="$2"
               case "$gl" in *" $want_g "*) ;; *) pg_fail "no group '$want_g' (groups 1..$seen_n)"; return 1 ;; esac ;;
      *) pg_fail "unknown argument: $arg (usage: [--group <1..$seen_n> | --all])"; return 1 ;;
    esac
  fi
  PG_SEL=" "
  for w in $groups; do
    [ "${w%%=*}" = "$want_g" ] || continue
    list=" $(printf '%s' "${w#*=}" | tr ',' ' ') "
    for p in $parts; do case "$list" in *" $p "*) PG_SEL="$PG_SEL$p " ;; esac; done
  done
  PG_LABEL="group $want_g/$seen_n ($(printf '%s' "$PG_SEL" | sed 's/^ //; s/ $//'))"
  return 0
}

pg_want() { case "${PG_SEL:-}" in *" $1 "*) return 0 ;; esac; return 1; }
