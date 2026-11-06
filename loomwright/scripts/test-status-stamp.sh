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
mk fenced-parked    "# t\n\n## Status: pending\n\n$FENCE\n## Status: parked\n$FENCE\n"

# run_lib <lib> <fn> <file> — the function's exit status, in a clean shell
run_lib() { ( . "$1" && "$2" "$3" ) >/dev/null 2>&1; }

# expect_done <lib> ⇒ 0 when every done/not-done shape reads as expected; else prints the first miss
expect_done() {
  local lib="$1" n
  for n in plain stale-first pr-suffix escalated abandoned crlf fenced-then-real unclosed-fence; do
    run_lib "$lib" status_is_done "$F/$n.md" || { echo "$n read not done"; return 1; }
  done
  for n in fenced-only fenced-pending two-then-unclosed quoted not-a-stamp none; do
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
m1="$W/lib-nofence.sh"; sed 's/^    \/\^```\/ .*$/    \/^NEVER\/ { next }/' "$LIB" > "$m1"
if cmp -s "$m1" "$LIB"; then no "mutant 1 did not change the library"; elif expect_done "$m1" >/dev/null; then no "fence handling removed and the shapes still pass"; else ok "fence handling removed ⇒ the shape case turns red"; fi
m2="$W/lib-noflush.sh"; sed 's/if (inf) print buf\[i\]/if (0) print buf[i]/' "$LIB" > "$m2"
if cmp -s "$m2" "$LIB"; then no "mutant 2 did not change the library"; elif expect_done "$m2" >/dev/null; then no "the unclosed-fence flush removed and the shapes still pass"; else ok "the unclosed-fence flush removed ⇒ the shape case turns red"; fi

echo "-- resolve-folder, the real intake reader"
got="$(bash "$HERE/automate-helpers.sh" resolve-folder "$F" 2>/dev/null | sed 's|.*/||' | env LC_ALL=C sort | tr '\n' ' ')"
want="fenced-only.md fenced-parked.md fenced-pending.md none.md not-a-stamp.md two-then-unclosed.md "
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

echo "PASS: $pass FAIL: $fail"
[ "$fail" -eq 0 ]
