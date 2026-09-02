#!/usr/bin/env bash
# test-capture-task-spawn-payload.sh — self-test for the out-of-session hook-payload
# probe harness (`capture-task-spawn-payload.sh`).
#
# WHY THIS EXISTS
# ----------------
# The harness's mutation controls (MC1-MC4) originally existed ONLY as a prose table in
# `docs/SPIKES/AGENT_SPAWN_PAYLOAD_PROBE.md`. Nothing in the repo could re-run them, so a
# future edit reintroducing the zero-byte-counts-as-capture defect would produce a SILENT
# FALSE NO-GO with every gate green — the exact failure the harness exists to prevent, one
# level down. Flagged MEDIUM in the PR #170 Phase 4.5 review; this file is the fix.
#
# THE DEFECT THIS PINS (MC1, a real bug found and fixed during the probe run)
# --------------------------------------------------------------------------
# The sink uses `mktemp`, which CREATES the output file BEFORE stdin is written. A
# file-existence count (`[ -f ]`) therefore reports a totally broken sink — one that writes
# nothing at all — as a SUCCESSFUL capture. `[ -s ]` (non-empty) is the load-bearing test.
# Case 1 below fails if that ever regresses to `-f`.
#
# SCOPE: the hook-to-disk path and the counter only. The harness's headless CLI invocation
# is NOT exercised here — it needs live auth and a real subagent spawn, and a test that shells
# out to a paid API is not a unit test. That limit is stated rather than papered over.
#
# (The CLI command is deliberately not spelled out literally above: this file is CORE under
# the vendor-coupling ratchet, and an incidental prose mention would have added coupling debt
# to a test that needs none. Paying it down beats declaring an allowance for it.)
#
# Runs fully offline. Touches nothing outside its own mktemp dir.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS="$SCRIPT_DIR/capture-task-spawn-payload.sh"

PASS_COUNT=0
FAIL_COUNT=0
ok() { echo "  ok: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
no() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label  expected='$expected' actual='$actual'"; fi
}

TMPROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

[ -f "$HARNESS" ] || { echo "FATAL: harness not found at $HARNESS"; exit 1; }

# The counter is inlined here rather than sourced: the harness runs its probe path at
# source time, so it cannot be sourced for a unit test. This copy is kept honest by the
# mutation control in case 6, which asserts the harness's own text still uses `-s`.
count_nonempty_ref() {
  _dir="$1"; _pat="$2"; _n=0; _empty=0
  for _f in "$_dir"/${_pat}-*; do
    [ -f "$_f" ] || continue
    if [ -s "$_f" ]; then _n=$(( _n + 1 )); else _empty=$(( _empty + 1 )); fi
  done
  printf '%s %s' "$_n" "$_empty"
}

echo "== 1. MC1: sink writes stdin verbatim, and a non-empty capture counts as FIRED =="
D1="$TMPROOT/d1"
printf '{"hook_event_name":"PreToolUse","tool_name":"Agent"}' | bash "$HARNESS" --sink "$D1" pretooluse-task
rc=$?
assert_eq "case1 sink exits 0" "0" "$rc"
set -- $(count_nonempty_ref "$D1" pretooluse-task)
assert_eq "case1 non-empty captures" "1" "$1"
assert_eq "case1 empty captures" "0" "$2"
WROTE="$(cat "$D1"/pretooluse-task-* 2>/dev/null)"
assert_eq "case1 payload written verbatim" '{"hook_event_name":"PreToolUse","tool_name":"Agent"}' "$WROTE"

echo "== 2. MC1 (the load-bearing half): an EMPTY capture must NOT count as FIRED =="
# This is the mirror-image hazard: mktemp pre-creates the file, so a sink that writes
# nothing still leaves a file on disk. A `-f` count would report FIRED here.
D2="$TMPROOT/d2"; mkdir -p "$D2"; : > "$D2/pretooluse-task-EMPTY1"
set -- $(count_nonempty_ref "$D2" pretooluse-task)
assert_eq "case2 empty file is NOT counted as a capture" "0" "$1"
assert_eq "case2 empty file IS counted as empty" "1" "$2"

echo "== 3. MC3: counter over no-files / one-empty / empty+non-empty =="
D3="$TMPROOT/d3"; mkdir -p "$D3"
set -- $(count_nonempty_ref "$D3" pretooluse-task)
assert_eq "case3a no files -> 0 non-empty" "0" "$1"
assert_eq "case3a no files -> 0 empty" "0" "$2"
: > "$D3/pretooluse-task-A"
set -- $(count_nonempty_ref "$D3" pretooluse-task)
assert_eq "case3b one empty -> 0 non-empty" "0" "$1"
assert_eq "case3b one empty -> 1 empty" "1" "$2"
printf '{"x":1}' > "$D3/pretooluse-task-B"
set -- $(count_nonempty_ref "$D3" pretooluse-task)
assert_eq "case3c empty+non-empty -> 1 non-empty" "1" "$1"
assert_eq "case3c empty+non-empty -> 1 empty" "1" "$2"

echo "== 4. MC2: degenerate stdin, each case separately, all fail SAFE (exit 0) =="
# Separate cases on purpose — a single combined case cannot tell you WHICH input broke.
D4="$TMPROOT/d4"
printf '' | bash "$HARNESS" --sink "$D4" empty-stdin;      assert_eq "case4a empty stdin exits 0" "0" "$?"
printf 'not json at all' | bash "$HARNESS" --sink "$D4" non-json; assert_eq "case4b non-JSON stdin exits 0" "0" "$?"
printf '\x00\x01\x02binary' | bash "$HARNESS" --sink "$D4" binary; assert_eq "case4c binary stdin exits 0" "0" "$?"
printf '{}' | bash "$HARNESS" --sink; assert_eq "case4d missing sink dir arg exits 0" "0" "$?"
UNWRITABLE="$TMPROOT/unwritable"; mkdir -p "$UNWRITABLE"; chmod 500 "$UNWRITABLE"
printf '{}' | bash "$HARNESS" --sink "$UNWRITABLE/nested" x; assert_eq "case4e unwritable dir exits 0" "0" "$?"
chmod 700 "$UNWRITABLE"
# The empty-stdin case must ALSO not be counted as a capture (ties case 2 to the real sink).
set -- $(count_nonempty_ref "$D4" empty-stdin)
assert_eq "case4f empty stdin produced NO non-empty capture" "0" "$1"

echo "== 5. concurrent hooks do not clobber each other (distinct filename per event) =="
D5="$TMPROOT/d5"
printf '{"n":1}' | bash "$HARNESS" --sink "$D5" subagentstop
printf '{"n":2}' | bash "$HARNESS" --sink "$D5" subagentstop
set -- $(count_nonempty_ref "$D5" subagentstop)
assert_eq "case5 two events -> two distinct captures" "2" "$1"

echo "== 6. MUTATION CONTROL: the harness must still use -s, not -f, to count =="
# Gated on validity per the repo's mutant-is-evidence-only-if-valid rule: the mutant must
# be non-empty, differ from the original, and pass `bash -n` before its result is trusted.
MUT="$TMPROOT/mutant.sh"
sed 's/if \[ -s "\$_f" \]; then/if [ -f "$_f" ]; then/' "$HARNESS" > "$MUT" 2>/dev/null
if [ ! -s "$MUT" ]; then
  no "case6 mutant is empty — control INVALID, not evidence"
elif cmp -s "$MUT" "$HARNESS"; then
  no "case6 mutation was a no-op (the '-s' counter text was not found) — control INVALID"
elif ! bash -n "$MUT" 2>/dev/null; then
  no "case6 mutant does not parse — control INVALID"
else
  ok "case6 mutant is valid (non-empty, differs, parses) — its result is evidence"
  # Run the VALIDATED MUTANT's own counter, not a re-implementation of it. An earlier
  # revision re-declared a `[ -f ]` counter here and asserted against that; since $D2 holds
  # exactly one empty file, both assertions were arithmetically forced and never touched
  # $MUT at all. Extracting and eval'ing the function from each file is what makes the
  # validity gate above actually load-bearing.
  extract_counter() { sed -n '/^count_nonempty() {/,/^}/p' "$1"; }
  run_counter() { ( eval "$(extract_counter "$1")"; CAP_DIR="$2"; count_nonempty "$3" ); }
  MUT_OUT="$(run_counter "$MUT" "$D2" pretooluse-task | cut -d' ' -f1)"
  REAL_OUT="$(run_counter "$HARNESS" "$D2" pretooluse-task | cut -d' ' -f1)"
  if [ -z "$MUT_OUT" ] || [ -z "$REAL_OUT" ]; then
    no "case6 counter extraction produced nothing — control INVALID, not evidence"
  else
    ok "case6 both counters were extracted and ran (control is exercising \$MUT itself)"
    assert_eq "case6 MUTANT counter miscounts the empty file as a capture (the defect)" "1" "$MUT_OUT"
    assert_eq "case6 REAL counter correctly rejects it" "0" "$REAL_OUT"
  fi
fi

echo "== 7. harness discipline: fail-SAFE and portable (CLAUDE.md invariants) =="
grep -q '^set -u' "$HARNESS" && ok "case7 uses 'set -u'" || no "case7 missing 'set -u'"
# Anchored to column 0 in an earlier revision, so an INDENTED `set -e` inside a function or
# if-block walked straight past the absence guard. Same vacuity class as the two above.
grep -qE '^[[:space:]]*set -e' "$HARNESS" && no "case7 must NOT use 'set -e' (fail-safe emitter)" || ok "case7 correctly has no 'set -e' at any indent"
grep -q "trap 'exit 0' EXIT" "$HARNESS" && ok "case7 has trap 'exit 0' EXIT" || no "case7 missing exit-0 trap"
# Portability: no timeout(1) (absent on stock macOS), no BSD-only `stat -f`
# (succeeds with GARBAGE under GNU/Linux CI — macOS-green is not CI-green).
#
# COMMENTS ARE STRIPPED FIRST, and that is load-bearing rather than cosmetic: the harness's
# own PORTABILITY header says it avoids `stat -f`, so a naive grep matches that sentence and
# reports a violation the code never commits. A guard that fires on its own documentation is
# worthless. The mutation control below proves the stripped guard still catches a real one.
# The strip must NOT eat `$#`, `${v#p}` or `${v##p}`. A naive `s/[[:space:]]*#.*$//`
# turns the harness's own `while [ "$#" -gt 0 ]; do` into `while [ "$`, leaving $CODE_ONLY
# unparseable — so a real violation sharing a line with a parameter expansion would be
# invisible to BOTH guards below. Strip only a `#` at line-start or after whitespace.
strip_comments() { sed -E 's/(^|[[:space:]])#.*$/\1/' "$1"; }

CODE_ONLY="$TMPROOT/harness-code-only.sh"
strip_comments "$HARNESS" > "$CODE_ONLY"
# The strip is only trustworthy if it left valid shell behind — assert it, never assume it.
bash -n "$CODE_ONLY" 2>/dev/null && ok "case7 comment-strip left parseable shell (did not eat \$#)" \
  || no "case7 comment-strip CORRUPTED the code — both portability guards below are unreliable"
# SUBSTANTIALITY. `bash -n` alone does NOT catch an over-strip, because an EMPTY file parses
# cleanly and then both greps below find nothing and cheerfully report "no violation" — a
# false CLEAN, the same class this whole section keeps re-learning. Verified: emptying
# $CODE_ONLY left the suite fully green until this assertion existed. Pin code landmarks that
# any correct strip must preserve, so a guard can never scan a gutted file and pass.
_landmarks_missing=""
for _lm in 'count_nonempty() {' '"--sink"' 'trap ' 'mktemp'; do
  grep -qF "$_lm" "$CODE_ONLY" || _landmarks_missing="$_landmarks_missing [$_lm]"
done
[ -z "$_landmarks_missing" ] \
  && ok "case7 stripped code retains its landmarks (guards are scanning real code, not a gutted file)" \
  || no "case7 stripped code LOST landmarks:$_landmarks_missing — the guards below would scan a gutted file and falsely report clean"
grep -qE '(^|[^-[:alnum:]])timeout ' "$CODE_ONLY" && no "case7 uses timeout(1) — absent on stock macOS" || ok "case7 no timeout(1) in code"
grep -q 'stat -f' "$CODE_ONLY" && no "case7 uses BSD-only 'stat -f'" || ok "case7 no BSD-only 'stat -f' in code"

# MUTATION CONTROL for the guard itself. The previous revision of this control was VACUOUS:
# it printf'd `stat -f` into a file and grepped that same file for it, OUTSIDE the strip —
# a round-trip that could not fail, and which stayed green even with $CODE_ONLY emptied to
# zero bytes. It must inject into the SOURCE and run the SAME strip, or it certifies nothing.
MUT7_SRC="$TMPROOT/mutant7-src.sh"; MUT7_CODE="$TMPROOT/mutant7-code.sh"
{ printf 'mtime=$(stat -f %%m "$0")\n'; cat "$HARNESS"; } > "$MUT7_SRC"
strip_comments "$MUT7_SRC" > "$MUT7_CODE"
if grep -q 'stat -f' "$MUT7_CODE"; then
  ok "case7 POSITIVE control: guard catches a real 'stat -f' surviving the strip (not vacuous)"
else
  no "case7 guard is VACUOUS — it missed a 'stat -f' injected into the source"
fi
# NEGATIVE control: a source whose ONLY `stat -f` is in a comment must NOT be flagged.
# Without this, "strip everything" would pass the positive control above.
NEG7_SRC="$TMPROOT/neg7-src.sh"; NEG7_CODE="$TMPROOT/neg7-code.sh"
{ printf '# portability note: this file avoids stat -f on purpose\n'; printf 'echo ok\n'; } > "$NEG7_SRC"
strip_comments "$NEG7_SRC" > "$NEG7_CODE"
if grep -q 'stat -f' "$NEG7_CODE"; then
  no "case7 NEGATIVE control: guard flags a comment-only mention — it fires on documentation"
else
  ok "case7 NEGATIVE control: comment-only 'stat -f' is correctly not flagged"
fi
bash -n "$HARNESS" 2>/dev/null && ok "case7 harness parses" || no "case7 harness does not parse"

echo
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
