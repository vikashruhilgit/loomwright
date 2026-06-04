#!/usr/bin/env bash
# test-benchmark.sh — self-tests for the System Twin "provable-done" benchmark harness (ST3).
# Mirrors test-system-contract.sh / test-project-memory.sh: isolated, deterministic, no network.
# Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M failed".
#
# Covers:
#   1. determinism — same corpus => identical value across two runs
#   2. known pass count — the committed corpus yields exactly the expected conformer count
#   3. no baseline => delta null, status pass
#   4. baseline read + delta math (regressed / improved / pass)
#   5. --update-baseline writes the baseline (and a plain run does NOT mutate it)
#   6. fail-safe — missing corpus => status unverified, value null, exit 0
#   7. BENCHMARK_JSON line is valid JSON carrying the benchmark_result fields

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run-benchmark.sh"
CORPUS="$HERE/benchmark-corpus"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

val() { printf '%s\n' "$1" | sed -n 's/^value: //p' | head -n1; }
sts() { printf '%s\n' "$1" | sed -n 's/^status: //p' | head -n1; }
dlt() { printf '%s\n' "$1" | sed -n 's/^delta: //p' | head -n1; }
bln() { printf '%s\n' "$1" | sed -n 's/^baseline: //p' | head -n1; }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-benchmark: jq not available — cannot exercise the benchmark; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

# Compute the expected conformer count straight from the corpus with the SAME contract the script
# uses, so the self-test stays green whenever the corpus + checker agree (no magic constant to drift).
expected=0
for f in "$CORPUS"/*.jsonl; do
  r="$(jq -r '
    def ok:
      (.event=="session_end")
      and ((.contract_conformance_status|type=="string") and (.contract_conformance_status|IN("pass","advisory_violations","unverified","skipped")))
      and ((.contract_violations|type=="number"))
      and ((.benchmark_status|type=="string") and (.benchmark_status|IN("pass","regressed","improved","unverified","skipped")))
      and ((.benchmark_metric|type=="string"))
      and (has("benchmark_value") and ((.benchmark_value|type)|IN("number","null")))
      and (has("benchmark_delta") and ((.benchmark_delta|type)|IN("number","null")));
    if ok then 1 else 0 end' "$f" 2>/dev/null)" || r=0
  [ "$r" = "1" ] && expected=$((expected+1))
done

BL="$(mktemp -d)/baseline.json"   # isolated baseline; never touches the real .supervisor/twin

echo "== 1. determinism (same corpus => same value) =="
o1="$( bash "$RUN" --baseline-file "$BL" 2>/dev/null )"
o2="$( bash "$RUN" --baseline-file "$BL" 2>/dev/null )"
v1="$(val "$o1")"; v2="$(val "$o2")"
[ -n "$v1" ] && [ "$v1" = "$v2" ] && ok "deterministic value ($v1 == $v2)" || no "non-deterministic ($v1 vs $v2)"

echo "== 2. known pass count (corpus conformers) =="
[ "$v1" = "$expected" ] && ok "value matches expected conformer count ($v1 == $expected)" || no "value $v1 != expected $expected"

echo "== 3. no baseline => delta null, status pass =="
[ "$(dlt "$o1")" = "null" ] && [ "$(bln "$o1")" = "null" ] && [ "$(sts "$o1")" = "pass" ] \
  && ok "first run: baseline=null, delta=null, status=pass" || no "no-baseline path wrong (status=$(sts "$o1") delta=$(dlt "$o1"))"

echo "== 4. baseline read + delta math =="
# regressed: baseline above the real value
printf '{"value":%s}\n' "$((v1+5))" > "$BL"
oR="$( bash "$RUN" --baseline-file "$BL" 2>/dev/null )"
[ "$(dlt "$oR")" = "-5" ] && [ "$(sts "$oR")" = "regressed" ] && ok "regressed: delta=-5, status=regressed" || no "regressed math wrong (delta=$(dlt "$oR") status=$(sts "$oR"))"
# improved: baseline below the real value
printf '{"value":%s}\n' "$((v1-3))" > "$BL"
oI="$( bash "$RUN" --baseline-file "$BL" 2>/dev/null )"
[ "$(dlt "$oI")" = "3" ] && [ "$(sts "$oI")" = "improved" ] && ok "improved: delta=3, status=improved" || no "improved math wrong (delta=$(dlt "$oI") status=$(sts "$oI"))"
# equal: delta 0, status pass
printf '{"value":%s}\n' "$v1" > "$BL"
oE="$( bash "$RUN" --baseline-file "$BL" 2>/dev/null )"
[ "$(dlt "$oE")" = "0" ] && [ "$(sts "$oE")" = "pass" ] && ok "equal: delta=0, status=pass" || no "equal math wrong (delta=$(dlt "$oE") status=$(sts "$oE"))"

echo "== 5. --update-baseline writes baseline; plain run does not mutate =="
BL2="$(mktemp -d)/bl2.json"
bash "$RUN" --baseline-file "$BL2" --update-baseline >/dev/null 2>&1
if [ -f "$BL2" ] && [ "$(jq -r '.value' "$BL2" 2>/dev/null)" = "$v1" ]; then ok "--update-baseline wrote value=$v1"; else no "--update-baseline did not write expected baseline"; fi
before="$(cat "$BL2")"
bash "$RUN" --baseline-file "$BL2" >/dev/null 2>&1
[ "$(cat "$BL2")" = "$before" ] && ok "plain run did NOT mutate baseline" || no "plain run mutated baseline"

echo "== 6. fail-safe (missing corpus) =="
oM="$( bash "$RUN" --corpus "$(mktemp -d)/nope" --baseline-file "$BL" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && [ "$(sts "$oM")" = "unverified" ] && [ "$(val "$oM")" = "null" ] \
  && ok "missing corpus => status unverified, value null, exit 0" || no "fail-safe path wrong (rc=$rc status=$(sts "$oM"))"

echo "== 7. BENCHMARK_JSON is valid JSON with benchmark_result fields =="
jline="$(printf '%s\n' "$o1" | sed -n 's/^BENCHMARK_JSON: //p' | head -n1)"
if printf '%s' "$jline" | jq -e '.status and .name and .metric and (has("value")) and (has("baseline")) and (has("delta")) and .unit' >/dev/null 2>&1; then
  ok "BENCHMARK_JSON parses and carries the benchmark_result fields"
else
  no "BENCHMARK_JSON missing/invalid: $jline"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
