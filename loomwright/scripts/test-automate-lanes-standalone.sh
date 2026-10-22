#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-automate-lanes-standalone.sh — a test-automate-lanes.d/ part run on its own must never signal a
# process outside the suite. The parts are sourced by test-automate-lanes.sh, which sets the hermetic $T;
# run standalone, $T was empty, so 06-phase-sessions.sh's AN-z cleanup `pgrep -f "_lane-run $T"` read
# `_lane-run ` and SIGTERMed every live /automate lane wrapper on the machine (2026-10-22, two lanes of a
# live wave). Every leg here runs the parts against a DECOY `_lane-run` process outside any suite dir.
#
#   S3 (runs first) static: every part's first line is the guard, and no part or entry line runs `pkill -f`
#      or `pgrep -f` outside tal_pgrep (a read-only raw pgrep carries `raw-pgrep-ok`) + mutation controls
#      on copies (never run: running a guard-stripped part is the bug)
#   S1 each part, run standalone (no $T, then an exported $T naming the decoy's dir), exits 2 before any
#      leg runs, names the entry script, and the decoy is still alive — with a positive control that
#      the decoy's command line IS what the bug's pattern matched; S1 runs only after S3a passes, under
#      pgrep / pkill stubs, and asserts no part reached either
#   S2 tal_pgrep (the one pattern finder the suite uses) refuses an empty $T, a relative $T, a path
#      outside $T, and finds a process under $T
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E="$HERE/test-automate-lanes.sh"
PD="$HERE/test-automate-lanes.d"
D="$(mktemp -d)" && D="$(cd "$D" && pwd -P)" && [ -n "$D" ] && [ -d "$D" ] || { echo "FAIL - mktemp -d failed"; exit 1; }
DECOY=""
cleanup() { [ -n "$DECOY" ] && kill -TERM "$DECOY" 2>/dev/null; rm -rf "$D"; }
trap cleanup EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$(printf '%s' "$2" | head -c 600)]" ;; esac; }

shopt -s nullglob
PARTS=("$PD"/*.sh)
[ "${#PARTS[@]}" -gt 0 ] || { echo "FAIL - no test-automate-lanes.d/*.sh parts found"; exit 1; }

# ---- the decoy: a stand-in for a live lane wrapper (`bash automate-lanes.sh _lane-run <lane_dir>`) ----
mkdir -p "$D/decoy/lane"
printf '%s\n' "trap 'kill \$! 2>/dev/null; exit 143' TERM" 'sleep 120 & wait $!' > "$D/decoy/automate-lanes.sh"
bash "$D/decoy/automate-lanes.sh" _lane-run "$D/decoy/lane" & DECOY=$!
ere() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
alive() { kill -0 "$DECOY" 2>/dev/null && echo alive || echo dead; }
i=0; until pgrep -f "_lane-run $(ere "$D/decoy/lane")" >/dev/null 2>&1 || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done

echo "== S3. static: the guard heads every part; no raw name-pattern kill anywhere in the suite =="
GUARD='declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ] && [ -d "$T" ] || {'
# guard_missing <file>… — the parts whose first line is not the guard
guard_missing() { local f; for f in "$@"; do case "$(head -1 "$f")" in "$GUARD"*"exit 2; }") ;; *) echo "${f##*/}" ;; esac; done; }
# raw_patterns <file>… — code lines running `pkill -f` / `pgrep -f` other than tal_pgrep's own and a
# marked read-only `raw-pgrep-ok` line (which must not also signal)
raw_patterns() {
  awk '/^[[:space:]]*#/ { next }
       /^tal_pgrep\(\) \{$/ { inf = 1 } inf { if ($0 ~ /^}$/) inf = 0; next }
       /raw-pgrep-ok/ && !/kill/ { next }
       /(^|[^[:alnum:]_-])(pkill|pgrep)([[:space:]]+-[[:alnum:]]+)*[[:space:]]+-[[:alnum:]]*f/ { print FILENAME ":" FNR ": " $0 }' "$@"
}
check "S3a every part's first line is the standalone guard" "$(guard_missing "${PARTS[@]}")" ""
check "S3b no raw pgrep -f / pkill -f in the entry or any part" "$(raw_patterns "$E" "${PARTS[@]}")" ""
# Mutation controls — on COPIES, never executed.
mkdir -p "$D/mut"
sed '1d' "$PD/06-phase-sessions.sh" > "$D/mut/06-phase-sessions.sh"
check "S3c MUTATION CONTROL: a part with its guard line removed is caught" "$(guard_missing "$D/mut/06-phase-sessions.sh")" "06-phase-sessions.sh"
{ cat "$PD/06-phase-sessions.sh"; printf '%s\n' 'for p in $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done'; } > "$D/mut/raw.sh"
has "S3d MUTATION CONTROL: the original AN-z kill line is caught" "$(raw_patterns "$D/mut/raw.sh")" 'pgrep -f "_lane-run $T"'
printf '%s\n' 'pkill -TERM -f "$(ere "$T")" 2>/dev/null' > "$D/mut/pkill.sh"
has "S3e MUTATION CONTROL: a pkill -TERM -f line is caught" "$(raw_patterns "$D/mut/pkill.sh")" "pkill -TERM -f"
printf '%s\n' 'pgrep -f "x $LR2" >/dev/null && kill 1   # raw-pgrep-ok' > "$D/mut/marked.sh"
has "S3f MUTATION CONTROL: a raw-pgrep-ok line that also kills is caught" "$(raw_patterns "$D/mut/marked.sh")" "raw-pgrep-ok"

echo "== S1. a part run standalone exits 2 before any leg, and the decoy lane survives =="
check "S1a positive control: the decoy is up and its command line holds \`_lane-run <dir>\` (the bug's match)" \
  "$(pgrep -f "_lane-run $(ere "$D/decoy/lane")" 2>/dev/null)" "$DECOY"
# Belt and braces while a real wave may be live: S1 runs only when S3a found the guard on every part, and
# under pgrep / pkill stubs that log and match nothing, so even a broken guard could signal no lane.
mkdir -p "$D/stub"; : > "$D/stub.log"
for c in pgrep pkill; do printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit 1\n' "$c" "$D/stub.log" > "$D/stub/$c"; chmod +x "$D/stub/$c"; done
if [ -n "$(guard_missing "${PARTS[@]}")" ]; then
  bad "S1 skipped: a part lacks the guard (S3a) — running it standalone is the bug"
else
for f in "${PARTS[@]}"; do
  n="${f##*/}"
  out="$(cd "$D" && env -u T PATH="$D/stub:$PATH" bash "$f" 2>"$D/err")"; rc=$?
  check "S1b $n standalone (no \$T) exits 2" "$rc" 2
  check "S1c $n standalone ran no leg (empty stdout)" "$out" ""
  has "S1d $n names the entry script" "$(cat "$D/err")" "run via test-automate-lanes.sh"
  check "S1e the decoy lane survives $n" "$(alive)" alive
  # an exported T naming an existing dir (a user shell's stray export) must not satisfy the guard
  out="$(cd "$D" && T="$D/decoy" PATH="$D/stub:$PATH" bash "$f" 2>/dev/null)"; rc=$?
  check "S1f $n standalone with an exported \$T still exits 2 (the guard needs the entry's tal_pgrep)" "$rc:$out" "2:"
  check "S1g the decoy lane survives $n with \$T exported" "$(alive)" alive
done
check "S1h no standalone part reached a pgrep / pkill" "$(cat "$D/stub.log")" ""
fi

echo "== S2. tal_pgrep only ever finds processes under \$T =="
eval "$(awk '/^ere\(\) \{/' "$E")"
eval "$(awk '/^tal_pgrep\(\) \{$/,/^}$/' "$E")"
if declare -F tal_pgrep >/dev/null; then
  r="$(T="" tal_pgrep "" "_lane-run ")"; rc=$?
  check "S2a an empty \$T and path ⇒ nothing, exit 2 (was: every lane on the machine)" "$rc:$r" "2:"
  r="$(T="decoy" tal_pgrep "decoy" "_lane-run ")"; rc=$?
  check "S2b a relative \$T ⇒ nothing, exit 2" "$rc:$r" "2:"
  r="$(T="$D/other" tal_pgrep "$D/decoy/lane" "_lane-run ")"; rc=$?
  check "S2c a path outside \$T ⇒ nothing, exit 2" "$rc:$r" "2:"
  mkdir -p "$D/other"
  r="$(T="$D/other" tal_pgrep "$D/other" "_lane-run ")"; rc=$?
  check "S2d an existing \$T with no process under it ⇒ nothing (the decoy is outside)" "$r" ""
  r="$(T="$D/decoy" tal_pgrep "$D/decoy/lane" "_lane-run ")"
  check "S2e positive control: a process under \$T is found" "$r" "$DECOY"
  check "S2f the decoy is still alive (tal_pgrep only lists)" "$(alive)" alive
else
  bad "S2 tal_pgrep could not be read from test-automate-lanes.sh"
fi

check "S9 the decoy lane is alive at the end of the suite" "$(alive)" alive
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
