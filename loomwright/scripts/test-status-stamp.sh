#!/usr/bin/env bash
# test-status-stamp.sh — self-test for automate-helpers.d/status-stamp.sh, the one fence-aware reader of a
# requirement's `## Status:` stamps. Offline. Cases at three levels: the library against each file
# shape, the real `resolve-folder` against the same files, and a pin that every requirement-status
# reader goes through the library. Mutation controls: each mutant must turn its case red.
# Exit 0 = all pass. Bash 3.2 / BSD safe.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/automate-helpers.d/status-stamp.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }

W="$(mktemp -d "${TMPDIR:-/tmp}/test-status-stamp.XXXXXX")" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$W"' EXIT
F="$W/files"; mkdir -p "$F"
FENCE='```'

# <name> <body> — one requirement-shaped file
mk() { printf '%b' "$2" > "$F/$1.md"; }
mk plain            '# t\n\n## Status: done\n'
mk stale-first      '# t\n\n## Status: pending\n\nbody\n\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **PR:** x\n'
mk pr-suffix        '# t\n\n## Status: brief-shipped\n\n## Status: done (PR #269, merge e319536)\n'
mk escalated        '# t\n\n## Status: pending\n\n## Status: done_with_escalation\n'
mk abandoned        '# t\n\n## Status: done_with_escalation \xe2\x80\x94 ABANDONED (superseded)\n'
mk crlf             '# t\r\n\r\n## Status: done\r\n'
mk fenced-only      "# t\n\n## Status: pending\n\n$FENCE\n<!-- loomwright:requirement-closeout -->\n## Status: done\n$FENCE\n"
mk fenced-pending   "# t\n\n## Status: pending\n\n$FENCE\n## Status: done\n$FENCE\n\nmore\n"
mk fenced-then-real "# t\n\n$FENCE\n## Status: pending\n$FENCE\n\n## Status: done\n"
mk unclosed-fence   "# t\n\n## Status: pending\n\n$FENCE\nnever closed\n\n<!-- loomwright:requirement-closeout -->\n## Status: done\n"
mk two-then-unclosed "# t\n\n$FENCE\n## Status: done\n$FENCE\n\n$FENCE\n## Status: pending\n"
mk quoted           '# t\n\n## Status: proposed\n\n> ## Status: done\n'
mk not-a-stamp      '# t\n\n## Status: donegal\n\n## Status note\n'
mk none             '# t\n'
mk parked           '# t\n\n## Status: parked (merged into x)\n'
mk tilde-only       '# t\n\n## Status: pending\n\n~~~\n## Status: done\n~~~\n'
mk fenced-parked    "# t\n\n## Status: pending\n\n$FENCE\n## Status: parked\n$FENCE\n"

# run_lib <lib> <fn> <file> — the function's exit status, in a clean shell
run_lib() { ( . "$1" && "$2" "$3" ) >/dev/null 2>&1; }

# expect_done <lib> ⇒ 0 when every done/not-done shape reads as expected; else prints the first miss
expect_done() {
  local lib="$1" n
  for n in plain stale-first pr-suffix escalated abandoned crlf fenced-then-real unclosed-fence; do
    run_lib "$lib" status_is_done "$F/$n.md" || { echo "$n read not done"; return 1; }
  done
  for n in fenced-only fenced-pending tilde-only two-then-unclosed quoted not-a-stamp none; do
    if run_lib "$lib" status_is_done "$F/$n.md"; then echo "$n read done"; return 1; fi
  done
  return 0
}

echo "-- status_is_done: every file shape"
if m="$(expect_done "$LIB")"; then
  ok "a real stamp reads done (plain, under a stale first line, a suffix, escalated, abandoned, CRLF, after a closed fence, after an unclosed fence); a stamp only in a closed fence, a quoted line, a longer word or no stamp does not"
else no "status_is_done: $m"; fi

echo "-- status_is_not_ready"
run_lib "$LIB" status_is_not_ready "$F/parked.md" && ok "a real parked heading is not ready" || no "a real parked heading read ready"
if run_lib "$LIB" status_is_not_ready "$F/fenced-parked.md"; then no "a parked heading only in a fence read not ready"; else ok "a parked heading only in a fence does not count"; fi
if run_lib "$LIB" status_is_not_ready "$F/plain.md"; then no "a done file read not ready"; else ok "a done file is not 'not ready'"; fi

echo "-- fail directions"
if run_lib "$LIB" status_is_done "$F/missing.md"; then no "a missing file read done"; else ok "a missing file is not done"; fi
sh_d="$W/noawk"; mkdir -p "$sh_d"; for t in grep env; do ln -s "$(command -v "$t")" "$sh_d/$t"; done
printf '#!/bin/sh\nexit 3\n' > "$sh_d/awk"; chmod +x "$sh_d/awk"
if ( . "$LIB"; PATH="$sh_d" status_is_done "$F/stale-first.md" ) >/dev/null 2>&1; then
  ok "a failing fence filter keeps the any-line answer: done work is not re-offered"
else no "a failing fence filter turned a done file into not-done, which would re-run merged work"; fi

echo "-- mutation controls"
m1="$W/lib-nofence.sh"; sed 's/^    \/\^(```|~~~)\/ .*$/    \/^NEVER\/ { next }/' "$LIB" > "$m1"
if cmp -s "$m1" "$LIB"; then no "mutant 1 did not change the library"; elif expect_done "$m1" >/dev/null; then no "fence handling removed and the shapes still pass"; else ok "fence handling removed ⇒ the shape case turns red"; fi
m2="$W/lib-noflush.sh"; sed 's/if (inf) print buf\[i\]/if (0) print buf[i]/' "$LIB" > "$m2"
if cmp -s "$m2" "$LIB"; then no "mutant 2 did not change the library"; elif expect_done "$m2" >/dev/null; then no "the unclosed-fence flush removed and the shapes still pass"; else ok "the unclosed-fence flush removed ⇒ the shape case turns red"; fi

echo "-- resolve-folder, the real intake reader"
got="$(bash "$HERE/automate-helpers.sh" resolve-folder "$F" 2>/dev/null | sed 's|.*/||' | env LC_ALL=C sort | tr '\n' ' ')"
want="fenced-only.md fenced-parked.md fenced-pending.md none.md not-a-stamp.md tilde-only.md two-then-unclosed.md "
[ "$got" = "$want" ] && ok "resolve-folder lists exactly the not-done, ready files" || no "resolve-folder listed: $got"
mkdir -p "$W/p"; printf '# t\n\n## Status: proposed\n\n%s\n## Status: done\n%s\n' "$FENCE" "$FENCE" > "$W/p/draft.md"
[ -z "$(bash "$HERE/automate-helpers.sh" resolve-folder "$W/p" 2>/dev/null)" ] \
  && ok "a proposed draft quoting a done stamp stays out of the queue, as not ready rather than as done" \
  || no "a proposed draft was queued"

echo "-- pin: requirement-status readers go through the library"
for c in automate-helpers.sh reconcile-jobs.sh propose-work.sh propose-domain.sh automate-lanes.d/remove.sh; do
  if grep -E '^[^#]*grep -[a-zA-Z]*E[a-zA-Z]* .*\^##.*Status:.*done' "$HERE/$c" >/dev/null 2>&1; then
    no "$c reads a done stamp with its own grep: use automate-helpers.d/status-stamp.sh"
  else ok "$c has no private done-stamp grep"; fi
done

echo "-- the trail readers: closeout's already-stamped check and the evidence gate's done claims"
TR="$HERE/automate-trail.d/trail-pr.sh"; CO="$HERE/automate-trail.d/closeout.sh"
# trail_fns <trail-pr file> <closeout file> — the three real functions, in a sourceable form
trail_fns() {
  sed -n '/^AB_PREFIX=/p' "$1"
  awk '/^_unfenced_text\(\) \{/,/^}/' "$1"; awk '/^_done_prs\(\) \{/,/^}/' "$1"; awk '/^_co_stamped\(\) \{/,/^}/' "$2"
}
URL='https://github.com/o/r/pull/7'
BLOCK="<!-- loomwright:requirement-closeout -->\n## Status: done\n- **PR:** $URL\n"
mk co-real     "# t\n\n## Status: pending\n\n$BLOCK"
mk co-fenced   "# t\n\n## Status: proposed\n\n$FENCE\n$BLOCK$FENCE\n"
mk co-both     "# t\n\n$FENCE\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **PR:** https://github.com/o/r/pull/1\n$FENCE\n\n$BLOCK"
mk co-unclosed "# t\n\n$FENCE\nstray\n\n$BLOCK"
# trail_case <fns file> ⇒ 0 when every shape reads as expected; else prints the first miss
trail_case() (
  HERE_REAL="$HERE"; HERE="$HERE_REAL"; . "$1"
  _co_stamped "$F/co-real.md"     || { echo "a real block read not stamped"; exit 1; }
  _co_stamped "$F/co-unclosed.md" || { echo "a real block under an unclosed fence read not stamped"; exit 1; }
  if _co_stamped "$F/co-fenced.md"; then echo "a fenced block read stamped"; exit 1; fi
  [ "$(_done_prs "$F/co-real.md")" = "$URL" ]   || { echo "a real claim lost its PR"; exit 1; }
  [ -z "$(_done_prs "$F/co-fenced.md")" ]       || { echo "a fenced claim was read"; exit 1; }
  [ "$(_done_prs "$F/co-both.md")" = "$URL" ]   || { echo "a fenced PR leaked in beside the real claim"; exit 1; }
  exit 0
)
trail_fns "$TR" "$CO" > "$W/fns.sh"
if m="$(trail_case "$W/fns.sh")"; then ok "_co_stamped and _done_prs read a real block, also under an unclosed fence, and ignore a fenced one"; else no "trail readers: $m"; fi
sed 's/status_unfenced "$1" ) || cat "$1"/false ) || cat "$1"/' "$W/fns.sh" > "$W/fns-mut.sh"
if cmp -s "$W/fns.sh" "$W/fns-mut.sh"; then no "trail mutant did not change the functions"
elif trail_case "$W/fns-mut.sh" >/dev/null; then no "the fence filter removed and the trail case still passes"
else ok "the fence filter removed ⇒ the trail case turns red"; fi
( HERE="$W/no-such-dir"; . "$W/fns.sh"; _co_stamped "$F/co-real.md" && [ "$(_done_prs "$F/co-real.md")" = "$URL" ] ) \
  && ok "without the library the trail readers still see a real block" \
  || no "a missing library hid a real block from the trail readers"

echo "-- pin: a library-missing fallback reads done exactly as the library does"
fallback_ere() { sed -n "s/^ *status_is_done() { status_has \"\$1\" '\(.*\)'; }\$/\1/p" "$1"; }
lib_ere="$( . "$LIB" && printf '%s' "$STATUS_DONE_ERE" )"
for c in reconcile-jobs.sh automate-lanes.d/remove.sh; do
  got="$(fallback_ere "$HERE/$c")"
  [ "$got" = "$lib_ere" ] && ok "$c: its fallback pattern equals STATUS_DONE_ERE" \
    || no "$c: its fallback pattern '$got' differs from STATUS_DONE_ERE '$lib_ere'"
done
m3="$W/remove-drifted.sh"; sed 's/done(_with_escalation)?\\b/done/' "$HERE/automate-lanes.d/remove.sh" > "$m3"
if cmp -s "$m3" "$HERE/automate-lanes.d/remove.sh"; then no "mutant 3 did not change remove.sh"
elif [ "$(fallback_ere "$m3")" = "$lib_ere" ]; then no "a drifted fallback still compares equal"
else ok "a drifted fallback pattern ⇒ the comparison turns red"; fi

echo "-- reconcile-jobs.sh and remove.sh, with and without the library"
# stage_lib <dir> — give <dir> the library, as an install has it
stage_lib() { mkdir -p "$1/automate-helpers.d"; cp "$LIB" "$1/automate-helpers.d/"; }

# rj_answer <script dir> <file> — reconcile-jobs.sh's real is_done and requirement_status, run from
# <script dir>: "<done|not> <status>"
rj_src() { awk '/^_rj_status_lib=/,/^is_done\(\)/' "$1"; awk '/^requirement_status\(\) \{/,/^}/' "$1"; }
rj_answer() {
  { rj_src "$RJ"; printf 'if is_done "$1"; then printf "done "; else printf "not "; fi; requirement_status "$1"\n'; } > "$1/probe.sh"
  bash "$1/probe.sh" "$2" 2>/dev/null
}
RJ="$HERE/reconcile-jobs.sh"
rj_case() { # <dir with library> <dir without>
  [ "$(rj_answer "$1" "$F/escalated.md")" = "done done_with_escalation" ] || { echo "library: an escalated stamp"; return 1; }
  [ "$(rj_answer "$1" "$F/fenced-pending.md")" = "not " ] || { echo "library: a fenced stamp read done"; return 1; }
  [ "$(rj_answer "$2" "$F/stale-first.md")" = "done done" ] || { echo "no library: a real stamp"; return 1; }
  [ "$(rj_answer "$2" "$F/not-a-stamp.md")" = "not " ] || { echo "no library: a longer word read done"; return 1; }
  [ "$(rj_answer "$2" "$F/fenced-pending.md")" = "done done" ] || { echo "no library: the plain read should err toward done"; return 1; }
}
RW="$W/rj-with"; RN="$W/rj-none"; mkdir -p "$RW" "$RN"; stage_lib "$RW"
if m="$(rj_case "$RW" "$RN")"; then ok "reconcile-jobs.sh: fence-aware with the library; the plain read without it, erring toward done"; else no "reconcile-jobs.sh: $m"; fi
RJ_REAL="$RJ"; RJ="$W/rj-typo.sh"; sed 's|/automate-helpers.d/status-stamp.sh"$|/automate-helpers.d/status-stampp.sh"|' "$RJ_REAL" > "$RJ"
if cmp -s "$RJ" "$RJ_REAL"; then no "reconcile-jobs mutant did not change the script"; elif rj_case "$RW" "$RN" >/dev/null; then no "a wrong library path in reconcile-jobs.sh stays green"; else ok "a wrong library path in reconcile-jobs.sh ⇒ the case turns red"; fi
RJ="$RJ_REAL"

# lane_list <remove.sh copy> <HERE> — _lanes_noclaim_files' real answer over one lane
LANE="$W/lane"; mkdir -p "$LANE/.supervisor/automate" "$LANE/.supervisor/requirements/proposed"
printf '# Automate Run: x\n## Queue\n## Current\n' > "$LANE/.supervisor/automate/R.md"
cp "$F/plain.md"          "$LANE/.supervisor/requirements/proposed/real-done.md"
cp "$F/fenced-pending.md" "$LANE/.supervisor/requirements/proposed/quoted.md"
cp "$F/none.md"           "$LANE/.supervisor/requirements/proposed/open.md"
lane_list() (
  HERE="$2"; LN_DIR="$LANE"; LN_RUN="R"
  eval "$(awk '/^_lanes_noclaim_files\(\) \{/,/^}/' "$1")"
  _lanes_noclaim_files 2>/dev/null | sed 's|.*/||' | env LC_ALL=C sort | tr '\n' ' '
)
RM="$HERE/automate-lanes.d/remove.sh"
LW="$W/lane-with"; mkdir -p "$LW"; stage_lib "$LW"
got="$(lane_list "$RM" "$LW")"
[ "$got" = "open.md quoted.md " ] && ok "remove.sh with the library: a quoted stamp stays pushable, a real done claim does not" || no "remove.sh with the library listed: $got"
got="$(lane_list "$RM" "$W/no-such-dir")"
[ "$got" = "open.md " ] && ok "remove.sh without the library: the plain read still lists unpushed files, erring toward a done claim" || no "remove.sh without the library listed: $got"
m4="$W/remove-typo.sh"; sed 's|automate-helpers.d/status-stamp.sh|automate-helpers.d/status-stampp.sh|g' "$RM" > "$m4"
if cmp -s "$m4" "$RM"; then no "remove.sh mutant did not change the script"
elif [ "$(lane_list "$m4" "$LW")" = "open.md quoted.md " ]; then no "a wrong library path in remove.sh stays green"
else ok "a wrong library path in remove.sh ⇒ the case turns red"; fi

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
