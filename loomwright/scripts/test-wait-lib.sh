#!/usr/bin/env bash
# test-wait-lib.sh — self-test for wait-lib.sh (bounded condition waits, iq02 T07).
#   (W1) a condition that becomes true after 0.5 s ⇒ 0, well inside the bound
#   (W2) a condition that never becomes true ⇒ 1 after ~the timeout, stderr names the condition
#   (W3) wait_for_pid_gone: a child that exits ⇒ 0; a live one ⇒ 1, naming the pid
#   (W4) wait_for_cmd passes arguments through; a bad timeout ⇒ 1
#   (W5) a slow `sleep` on PATH (0.5 s a call): the CLOCK bound still holds (timeout 2 ⇒ ≤ 4 s);
#        MUTATION CONTROL: a copy bounded by an iteration count instead runs far past it
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/wait-lib.sh"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/test-wait-lib.XXXXXX")"
trap 'rm -rf "$T"' EXIT
. "$LIB"

# (W1)
( sleep 0.5; echo ready > "$T/w1" ) &   # fixed-sleep-ok: the fixture's late writer, not a wait
s=$(date +%s); wait_for_file_content "$T/w1" ready 5; rc=$?; el=$(( $(date +%s) - s ))
if [ "$rc" -eq 0 ] && [ "$el" -le 3 ]; then ok "(W1) late condition (0.5 s) ⇒ 0 in ${el}s"; else no "(W1) rc=$rc el=${el}s"; fi

# (W2)
s=$(date +%s); wait_for_file_content "$T/never" ready 1 2> "$T/w2.err"; rc=$?; el=$(( $(date +%s) - s ))
if [ "$rc" -eq 1 ] && [ "$el" -ge 1 ] && [ "$el" -le 3 ] && grep -qF "waiting for: 'ready' in $T/never" "$T/w2.err"; then
  ok "(W2) never-true condition ⇒ 1 after ${el}s, naming the condition"
else no "(W2) rc=$rc el=${el}s err=$(cat "$T/w2.err")"; fi

# (W3)
( exit 0 ) & gone=$!
if wait_for_pid_gone "$gone" 5; then ok "(W3) an exited child ⇒ 0"; else no "(W3) exited pid $gone still seen alive"; fi
sleep 30 & live=$!   # fixed-sleep-ok: a live holder process for the negative case
wait_for_pid_gone "$live" 1 2> "$T/w3.err"; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
if [ "$rc" -eq 1 ] && grep -qF "waiting for: pid $live to exit" "$T/w3.err"; then ok "(W3) a live pid ⇒ 1, naming it"
else no "(W3) live: rc=$rc err=$(cat "$T/w3.err")"; fi

# (W4)
if wait_for_cmd 2 test -d "$T"; then ok "(W4) arguments pass through to the command"; else no "(W4) test -d failed"; fi
if wait_for_cmd x true 2>/dev/null; then no "(W4) a non-numeric timeout was accepted"; else ok "(W4) a non-numeric timeout ⇒ 1"; fi

# (W5) slow sleep on PATH — run in a child shell so the stub never leaks into this file's own waits.
mkdir -p "$T/slow"
printf '#!/bin/sh\nexec /bin/sleep 0.5\n' > "$T/slow/sleep"; chmod +x "$T/slow/sleep"
slow_run() {  # slow_run <lib> — seconds a never-true 2 s wait takes under the slow sleep
  PATH="$T/slow:$PATH" bash -c '. "$1"; s=$(date +%s); wait_for_cmd 2 false 2>/dev/null; echo $(( $(date +%s) - s ))' _ "$1"
}
el="$(slow_run "$LIB")"
if [ "${el:-99}" -le 4 ]; then ok "(W5) clock bound holds under a slow sleep: ${el}s for a 2 s wait"; else no "(W5) ${el}s for a 2 s wait"; fi
# MUTATION CONTROL: the deadline check replaced by an iteration count (20 x 0.1 s "= 2 s").
sed -e 's/^  end=\$(( \$(date +%s) + t ))$/  n=0/' \
    -e 's/^    if \[ "\$(date +%s)" -ge "\$end" \]; then$/    n=$((n + 1)); if [ "$n" -ge $((t * 10)) ]; then/' "$LIB" > "$T/mutant.sh"
if [ -s "$T/mutant.sh" ] && ! cmp -s "$LIB" "$T/mutant.sh" && bash -n "$T/mutant.sh" && grep -q 'n=\$((n + 1))' "$T/mutant.sh"; then
  el="$(slow_run "$T/mutant.sh")"
  if [ "${el:-0}" -gt 4 ]; then ok "(W5) MUTATION CONTROL: a count-bounded copy takes ${el}s — (W5) can fail"
  else no "(W5) MUTATION CONTROL: count-bounded copy took only ${el}s — the slow-sleep check proves nothing"; fi
else no "(W5) MUTATION CONTROL: mutant not built"; fi

echo
echo "test-wait-lib: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
