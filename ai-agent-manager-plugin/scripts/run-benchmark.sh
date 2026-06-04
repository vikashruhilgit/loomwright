#!/usr/bin/env bash
# run-benchmark.sh — the System Twin "provable-done" benchmark harness (Pillar 2 / ST3).
#
# Produces a DETERMINISTIC hard-signal metric — `selftest_pass_count` — by validating a fixed
# corpus of candidate `session_end` hard-signal events (scripts/benchmark-corpus/*.jsonl) against
# the hard-signal field contract (docs/RESULT_SCHEMAS.md §"`session_end` JSONL hard-signal fields").
# The metric is the COUNT of corpus fixtures that conform to that contract. Same corpus + same
# checker => same value, every run; there is NO wall-clock-sensitive primary signal (a duration is
# recorded for information only and is NEVER the pass/fail signal).
#
# This is meaningful to "provable-done": the very fields ST4/build-insights.sh aggregates are the
# thing being measured, so a regression in this count is a regression in the project's ability to
# emit a valid hard signal.
#
# Output shape maps 1:1 onto SUPERVISOR_RESULT.benchmark_result (docs/RESULT_SCHEMAS.md):
#   name, metric, value, unit, baseline, delta, status.
# Emitted in two forms on stdout: a `key: value` block (human/grep) AND a single `BENCHMARK_JSON: {...}`
# line (machine — the Supervisor Phase 4.5 parses this to populate benchmark_result + the flat
# session_end fields). When `jq` is present the JSON line is jq-built; otherwise a printf fallback.
#
# Baseline: read from / written to .supervisor/twin/benchmark-baseline.json (under .supervisor/,
# which is gitignored — session-local, not committed). `delta = value - baseline`, or null when
# there is no prior baseline. `--update-baseline` records the current value as the new baseline
# (the SOLE baseline write path; a plain run never mutates the baseline).
#
# Fail-safe: ALWAYS exits 0. When the corpus is missing or no JSON tool is available it emits
# `status: unverified` with `value: null` (mirroring the plugin's other scripts — a benchmark that
# cannot run must never break its caller).
#
# Usage:  run-benchmark.sh [--corpus <dir>] [--baseline-file <path>] [--update-baseline]
# Exit:   always 0.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$HERE/benchmark-corpus"
NAME="system-twin-selftest"
METRIC="selftest_pass_count"
UNIT="assertions"
UPDATE_BASELINE=0
BASELINE_FILE=""   # resolved against the repo root below unless overridden

while [ $# -gt 0 ]; do
  case "$1" in
    --corpus)         CORPUS="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --corpus=*)       CORPUS="${1#--corpus=}"; shift ;;
    --baseline-file)  BASELINE_FILE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --baseline-file=*) BASELINE_FILE="${1#--baseline-file=}"; shift ;;
    --update-baseline) UPDATE_BASELINE=1; shift ;;
    *) shift ;;
  esac
done

# Resolve the default baseline path under .supervisor/twin/ at the repo root (gitignored store).
if [ -z "$BASELINE_FILE" ]; then
  GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  BASELINE_FILE="$GITROOT/.supervisor/twin/benchmark-baseline.json"
fi

# ---- emit helpers ---------------------------------------------------------
# emit_result <status> <value-or-null> <baseline-or-null> <delta-or-null>
emit_result() {
  status="$1"; value="$2"; baseline="$3"; delta="$4"
  echo "name: $NAME"
  echo "metric: $METRIC"
  echo "value: $value"
  echo "unit: $UNIT"
  echo "baseline: $baseline"
  echo "delta: $delta"
  echo "status: $status"
  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg name "$NAME" --arg metric "$METRIC" --arg unit "$UNIT" --arg status "$status" \
      --argjson value "$value" --argjson baseline "$baseline" --argjson delta "$delta" \
      '{ran:true,status:$status,name:$name,metric:$metric,value:$value,baseline:$baseline,delta:$delta,unit:$unit}' \
      | sed 's/^/BENCHMARK_JSON: /'
  else
    printf 'BENCHMARK_JSON: {"ran":true,"status":"%s","name":"%s","metric":"%s","value":%s,"baseline":%s,"delta":%s,"unit":"%s"}\n' \
      "$status" "$NAME" "$METRIC" "$value" "$baseline" "$delta" "$UNIT"
  fi
}

# Fail-safe: no JSON tool at all (we use jq for both checking and baseline I/O). Emit unverified.
if ! command -v jq >/dev/null 2>&1; then
  echo "run-benchmark: no jq available — benchmark cannot run, fail-safe no-op" >&2
  emit_result "unverified" "null" "null" "null"
  exit 0
fi

# Fail-safe: corpus missing/empty. Emit unverified.
if [ ! -d "$CORPUS" ]; then
  echo "run-benchmark: corpus dir '$CORPUS' not found — fail-safe no-op" >&2
  emit_result "unverified" "null" "null" "null"
  exit 0
fi
shopt -s nullglob 2>/dev/null || true
fixtures=( "$CORPUS"/*.jsonl )
if [ "${#fixtures[@]}" -eq 0 ]; then
  echo "run-benchmark: no *.jsonl fixtures in '$CORPUS' — fail-safe no-op" >&2
  emit_result "unverified" "null" "null" "null"
  exit 0
fi

# ---- conformance check (the deterministic metric) -------------------------
# A fixture CONFORMS iff it is one JSON object with event=="session_end" AND all six flat
# hard-signal fields present with valid type/enum (docs/RESULT_SCHEMAS.md). This jq program
# returns "1" for conform, "0" otherwise — pure function of the fixture bytes.
CHECK='
  def ok:
    (.event == "session_end")
    and ((.contract_conformance_status|type=="string")
         and (.contract_conformance_status | IN("pass","advisory_violations","unverified","skipped")))
    and ((.contract_violations|type=="number"))
    and ((.benchmark_status|type=="string")
         and (.benchmark_status | IN("pass","regressed","improved","unverified","skipped")))
    and ((.benchmark_metric|type=="string"))
    and (has("benchmark_value") and ((.benchmark_value|type)|IN("number","null")))
    and (has("benchmark_delta") and ((.benchmark_delta|type)|IN("number","null")));
  if ok then 1 else 0 end
'

value=0
for f in "${fixtures[@]}"; do
  # `jq -e` would conflate errors with false; instead default a parse failure to 0 (non-conform).
  r="$(jq -r "$CHECK" "$f" 2>/dev/null)" || r="0"
  case "$r" in 1) value=$((value+1)) ;; *) : ;; esac
done

# ---- baseline read + delta ------------------------------------------------
baseline="null"
if [ -f "$BASELINE_FILE" ]; then
  b="$(jq -r '.value // empty' "$BASELINE_FILE" 2>/dev/null || true)"
  case "$b" in (''|*[!0-9]*) baseline="null" ;; (*) baseline="$b" ;; esac
fi

if [ "$baseline" = "null" ]; then
  delta="null"
  status="pass"   # first run: no baseline to regress against; the count itself is the signal
else
  delta=$((value - baseline))
  if   [ "$delta" -lt 0 ]; then status="regressed"
  elif [ "$delta" -gt 0 ]; then status="improved"
  else status="pass"; fi
fi

# ---- baseline write (sole path: --update-baseline) ------------------------
if [ "$UPDATE_BASELINE" -eq 1 ]; then
  mkdir -p "$(dirname "$BASELINE_FILE")" 2>/dev/null || true
  tmp="$(mktemp "$(dirname "$BASELINE_FILE")/.bl.XXXXXX" 2>/dev/null || mktemp)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  if jq -cn --arg name "$NAME" --arg metric "$METRIC" --arg unit "$UNIT" --arg ts "$ts" --argjson value "$value" \
        '{name:$name,metric:$metric,unit:$unit,value:$value,updated_at:$ts}' > "$tmp" 2>/dev/null; then
    mv "$tmp" "$BASELINE_FILE" 2>/dev/null \
      && echo "run-benchmark: baseline updated -> $BASELINE_FILE (value=$value)" >&2 \
      || { rm -f "$tmp" 2>/dev/null; echo "run-benchmark: baseline write failed (non-fatal)" >&2; }
  else
    rm -f "$tmp" 2>/dev/null
    echo "run-benchmark: baseline encode failed (non-fatal)" >&2
  fi
fi

emit_result "$status" "$value" "$baseline" "$delta"
exit 0
