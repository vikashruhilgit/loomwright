#!/usr/bin/env bash
# test-format-twin-delta.sh — self-tests for format-twin-delta.sh (System Twin inline delta line).
# Mirrors test-system-contract.sh conventions: ok()/no() counters, "RESULT: N passed, M failed",
# exit 1 on any failure. Exit 0 = all pass.
#
# Covers the design's HARD invariants:
#   1. ALWAYS exits 0 (no args, unknown args, null values, malformed --from-session-end)
#   2. full signal → combined "Twin: ... · ..." (status uppercased, signed delta)
#   3. conformance-only / benchmark-only → just that one segment
#   4. no/empty/skipped/unverified/null signal → exactly "Twin: no signal this run"
#   5. no-arg → "Twin: no signal this run" and exit 0
#   6. --from-session-end round-trip (guarded behind jq availability)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FMT="$HERE/format-twin-delta.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# run <expected-line> -- <args...> : asserts both exit 0 AND exact stdout match.
run_eq() {
  local expected="$1"; shift
  local got rc
  got="$(bash "$FMT" "$@")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    no "exit was $rc (want 0) for args: $*"
    return
  fi
  if [ "$got" = "$expected" ]; then
    ok "[$got]"
  else
    no "got [$got] want [$expected] for args: $*"
  fi
}

# assert exit 0 only (don't care about the exact line).
run_exit0() {
  local label="$1"; shift
  bash "$FMT" "$@" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then ok "exit 0 — $label"; else no "exit $rc (want 0) — $label"; fi
}

echo "== 2. full signal (conformance + benchmark) =="
run_eq "Twin: conformance PASS (0 violations) · benchmark system-twin-selftest 6 (Δ +1)" \
  --conformance-status pass --violations 0 \
  --benchmark-status improved --benchmark-name system-twin-selftest --benchmark-value 6 --benchmark-delta 1
# status uppercasing + negative signed delta
run_eq "Twin: conformance ADVISORY_VIOLATIONS (3 violations) · benchmark system-twin-selftest 4 (Δ -2)" \
  --conformance-status advisory_violations --violations 3 \
  --benchmark-status regressed --benchmark-name system-twin-selftest --benchmark-value 4 --benchmark-delta -2

echo "== 3. single-segment cases =="
run_eq "Twin: conformance ADVISORY_VIOLATIONS (2 violations)" \
  --conformance-status advisory_violations --violations 2
run_eq "Twin: benchmark selftest_pass_count 4 (Δ 0)" \
  --benchmark-status pass --benchmark-metric selftest_pass_count --benchmark-value 4 --benchmark-delta 0
# negative-zero magnitude normalizes to a bare "0" (never renders the cosmetic "-0")
run_eq "Twin: benchmark 4 (Δ 0)" \
  --benchmark-status pass --benchmark-value 4 --benchmark-delta -0
# violations defaults to 0 when conformance present but --violations omitted
run_eq "Twin: conformance PASS (0 violations)" --conformance-status pass
# benchmark with no name and no metric → bare "benchmark <value>"
run_eq "Twin: benchmark 7" --benchmark-status pass --benchmark-value 7
# name takes precedence over metric for the label
run_eq "Twin: benchmark thename 5 (Δ +1)" \
  --benchmark-status improved --benchmark-name thename --benchmark-metric themetric --benchmark-value 5 --benchmark-delta 1
# benchmark present but value null → NO benchmark segment (so overall: no signal)
run_eq "Twin: no signal this run" --benchmark-status pass --benchmark-value null

echo "== 4. no/empty/skipped/unverified/null signal =="
run_eq "Twin: no signal this run" --conformance-status skipped --benchmark-status unverified --benchmark-value null
run_eq "Twin: no signal this run" --conformance-status unverified
run_eq "Twin: no signal this run" --conformance-status skipped
# skipped/unverified conformance contributes nothing even with a valid benchmark dropping out
run_eq "Twin: no signal this run" --conformance-status null --benchmark-status skipped --benchmark-value 9

echo "== 5. no-arg safety =="
run_eq "Twin: no signal this run"

echo "== 1. ALWAYS exits 0 (adversarial inputs) =="
run_exit0 "no args"
run_exit0 "unknown args" --totally --unknown flag --benchmark-value notanumber
run_exit0 "null everywhere" --conformance-status null --violations null --benchmark-status null --benchmark-value null --benchmark-delta null
run_exit0 "non-numeric violations" --conformance-status pass --violations abc
run_exit0 "non-numeric benchmark value" --benchmark-status pass --benchmark-value xyz --benchmark-delta foo
run_exit0 "malformed --from-session-end line" --from-session-end '{this is not valid json'
run_exit0 "missing flag argument" --conformance-status
run_exit0 "from-session-end nonexistent file" --from-session-end /no/such/file/here.jsonl
# non-numeric violations still falls back to 0 in the rendered line (and exits 0)
run_eq "Twin: conformance PASS (0 violations)" --conformance-status pass --violations abc

# --- delta slip-through class: embedded-hyphen + int64-overflow must NOT reach arithmetic ---
# Embedded-hyphen delta (1-2) is NOT a valid int → delta omitted, benign line, exit 0.
run_eq "Twin: benchmark 4" \
  --benchmark-status pass --benchmark-value 4 --benchmark-delta 1-2
# Overflow delta (>int64) is NOT used in arithmetic → delta omitted, benign line, exit 0,
# and CRITICALLY produces NO stderr (the old [ -gt ] path emitted "value too great for base").
se_tmp="$(mktemp)"
got_overflow="$(bash "$FMT" --benchmark-status pass --benchmark-value 4 --benchmark-delta 99999999999999999999 2>"$se_tmp")"
rc_overflow=$?
if [ "$rc_overflow" -eq 0 ] && [ "$got_overflow" = "Twin: benchmark 4" ] && [ ! -s "$se_tmp" ]; then
  ok "overflow delta: exit 0, [Twin: benchmark 4], empty stderr"
else
  no "overflow delta: rc=$rc_overflow got=[$got_overflow] stderr=[$(cat "$se_tmp")] (want rc=0, [Twin: benchmark 4], empty stderr)"
fi
rm -f "$se_tmp"
# Re-confirm legitimate NEGATIVE delta still renders correctly (the trap the naive *-* fix breaks).
run_eq "Twin: benchmark 4 (Δ -2)" \
  --benchmark-status pass --benchmark-value 4 --benchmark-delta -2

echo "== 6. --from-session-end round-trip (jq-guarded) =="
if command -v jq >/dev/null 2>&1; then
  LINE='{"event":"session_end","contract_conformance_status":"pass","contract_violations":0,"benchmark_status":"improved","benchmark_metric":"selftest_pass_count","benchmark_value":6,"benchmark_delta":1}'
  # No explicit flags → the line is built ENTIRELY from the parsed session_end fields.
  # session_end has no benchmark name, so the label falls back to the metric.
  run_eq "Twin: conformance PASS (0 violations) · benchmark selftest_pass_count 6 (Δ +1)" \
    --from-session-end "$LINE"

  # File form: last session_end line in a multi-line file wins.
  TMPF="$(mktemp)"
  {
    printf '%s\n' '{"event":"session_start"}'
    printf '%s\n' '{"event":"session_end","contract_conformance_status":"advisory_violations","contract_violations":2,"benchmark_status":"skipped","benchmark_metric":"selftest_pass_count","benchmark_value":null,"benchmark_delta":null}'
    printf '%s\n' '{"event":"session_end","contract_conformance_status":"pass","contract_violations":0,"benchmark_status":"regressed","benchmark_metric":"selftest_pass_count","benchmark_value":3,"benchmark_delta":-1}'
  } > "$TMPF"
  run_eq "Twin: conformance PASS (0 violations) · benchmark selftest_pass_count 3 (Δ -1)" \
    --from-session-end "$TMPF"
  rm -f "$TMPF"

  # Explicit flag overrides a parsed value (benchmark-name wins over the metric label).
  run_eq "Twin: conformance PASS (0 violations) · benchmark system-twin-selftest 6 (Δ +1)" \
    --from-session-end "$LINE" --benchmark-name system-twin-selftest

  # A session_end with skipped/unverified+null benchmark and skipped conformance → no signal.
  NOLINE='{"event":"session_end","contract_conformance_status":"skipped","contract_violations":0,"benchmark_status":"unverified","benchmark_metric":"selftest_pass_count","benchmark_value":null,"benchmark_delta":null}'
  run_eq "Twin: no signal this run" --from-session-end "$NOLINE"
else
  ok "jq absent — --from-session-end round-trip skipped gracefully (fail-safe)"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
