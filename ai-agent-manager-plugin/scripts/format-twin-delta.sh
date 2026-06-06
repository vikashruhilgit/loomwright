#!/usr/bin/env bash
# format-twin-delta.sh — render THIS run's System Twin hard signal as ONE advisory line.
#
# Pillar 3 / "compound" surface helper: takes the six FLAT session_end hard-signal fields
# (docs/RESULT_SCHEMAS.md §"`session_end` JSONL hard-signal fields") — sourced either from
# explicit flags or parsed out of a `session_end` JSONL line/file — and prints exactly ONE
# human-readable line to stdout:
#
#   Twin: conformance PASS (0 violations) · benchmark system-twin-selftest 6 (Δ +1)
#   Twin: conformance ADVISORY_VIOLATIONS (2 violations)
#   Twin: benchmark selftest_pass_count 4 (Δ 0)
#   Twin: no signal this run
#
# A segment is emitted ONLY when a real result was computed:
#   - conformance segment  : status ∈ {pass, advisory_violations}
#   - benchmark segment     : status ∉ {skipped, unverified} AND value is a real number
# When both are empty → "Twin: no signal this run".
#
# Fail-safe like the rest of the Twin scripts: ALWAYS exits 0. Unknown args, null values,
# malformed --from-session-end input, missing jq — none of these are errors; they just yield
# "no signal this run" (or fall back to whatever explicit flags provided). Explicit flags ALWAYS
# take precedence over values parsed from --from-session-end.
#
# Usage:
#   format-twin-delta.sh [--conformance-status <s>] [--violations <n>]
#                        [--benchmark-status <s>] [--benchmark-name <s>] [--benchmark-metric <s>]
#                        [--benchmark-value <n>] [--benchmark-delta <n>]
#                        [--from-session-end <jsonl-line-or-file>]
# Exit: always 0.

set -uo pipefail

# ---- raw flag holders (empty = not provided) ------------------------------
F_CONF_STATUS=""
F_VIOLATIONS=""
F_BM_STATUS=""
F_BM_NAME=""
F_BM_METRIC=""
F_BM_VALUE=""
F_BM_DELTA=""
F_FROM=""

# Track which explicit flags were actually given (so they win over parsed values).
G_CONF_STATUS=0; G_VIOLATIONS=0; G_BM_STATUS=0; G_BM_NAME=0; G_BM_METRIC=0; G_BM_VALUE=0; G_BM_DELTA=0

while [ $# -gt 0 ]; do
  case "$1" in
    --conformance-status)  F_CONF_STATUS="${2:-}"; G_CONF_STATUS=1; shift; [ $# -gt 0 ] && shift ;;
    --conformance-status=*) F_CONF_STATUS="${1#--conformance-status=}"; G_CONF_STATUS=1; shift ;;
    --violations)          F_VIOLATIONS="${2:-}"; G_VIOLATIONS=1; shift; [ $# -gt 0 ] && shift ;;
    --violations=*)        F_VIOLATIONS="${1#--violations=}"; G_VIOLATIONS=1; shift ;;
    --benchmark-status)    F_BM_STATUS="${2:-}"; G_BM_STATUS=1; shift; [ $# -gt 0 ] && shift ;;
    --benchmark-status=*)  F_BM_STATUS="${1#--benchmark-status=}"; G_BM_STATUS=1; shift ;;
    --benchmark-name)      F_BM_NAME="${2:-}"; G_BM_NAME=1; shift; [ $# -gt 0 ] && shift ;;
    --benchmark-name=*)    F_BM_NAME="${1#--benchmark-name=}"; G_BM_NAME=1; shift ;;
    --benchmark-metric)    F_BM_METRIC="${2:-}"; G_BM_METRIC=1; shift; [ $# -gt 0 ] && shift ;;
    --benchmark-metric=*)  F_BM_METRIC="${1#--benchmark-metric=}"; G_BM_METRIC=1; shift ;;
    --benchmark-value)     F_BM_VALUE="${2:-}"; G_BM_VALUE=1; shift; [ $# -gt 0 ] && shift ;;
    --benchmark-value=*)   F_BM_VALUE="${1#--benchmark-value=}"; G_BM_VALUE=1; shift ;;
    --benchmark-delta)     F_BM_DELTA="${2:-}"; G_BM_DELTA=1; shift; [ $# -gt 0 ] && shift ;;
    --benchmark-delta=*)   F_BM_DELTA="${1#--benchmark-delta=}"; G_BM_DELTA=1; shift ;;
    --from-session-end)    F_FROM="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --from-session-end=*)  F_FROM="${1#--from-session-end=}"; shift ;;
    *) shift ;;   # unknown args are ignored (fail-safe), never an error
  esac
done

# ---- helpers --------------------------------------------------------------
# "not provided" if empty, literal "null", or the string "None".
is_unset() {
  case "${1:-}" in
    ""|null|None) return 0 ;;
    *) return 1 ;;
  esac
}

# integer test: accepts an optional SINGLE leading minus followed by one-or-more
# digits; rejects embedded hyphens (e.g. 1-2, -1-2), bare "-", and int64-overflow
# magnitudes. The magnitude guard (≤18 significant digits — int64 max is 19 digits
# but a flat ≤18 cap is unambiguously in-range) means an overflow string is treated
# as NOT-an-int, so the delta is omitted rather than mis-rendered. Even so, every
# downstream consumer stays arithmetic-free (see the string-only delta sign block)
# as defense-in-depth, so a slip-through could never emit a stderr diagnostic.
#
# INTEGER-VALUED METRICS ONLY (by design). The schema permits `benchmark_value` /
# `benchmark_delta` to be any `number | null` (RESULT_SCHEMAS.md:249,251), but the
# only benchmark today (run-benchmark.sh → selftest_pass_count) is an integer count,
# so this guard accepts integers only. A non-integer (float) value/delta is treated
# as "not a number" and its segment is simply OMITTED — it fails safe (no error, no
# mis-render), but it would silently drop a float benchmark. If a float-valued metric
# is ever added, widen this guard to accept a single decimal point (and update the
# zero-magnitude normalization + the delta-sign block accordingly).
is_int() {
  s="${1:-}"
  case "$s" in ""|null|None) return 1 ;; esac
  s="${s#-}"                       # strip ONE optional leading minus
  case "$s" in
    ""|*[!0-9]*) return 1 ;;       # empty (was just "-") or any non-digit (catches 1-2, abc, -1-2)
  esac
  # range guard: reject magnitudes with more than 18 digits (definitely > int64).
  [ "${#s}" -le 18 ] || return 1
  return 0
}

# ---- parse --from-session-end (only fills holes left by explicit flags) ---
# Best-effort: requires jq; any failure is a silent no-op (treated as "no signal").
if [ -n "$F_FROM" ] && command -v jq >/dev/null 2>&1; then
  # Resolve the JSONL line: if F_FROM is an existing file, take its LAST session_end line;
  # otherwise treat F_FROM itself as the JSONL line.
  se_line=""
  if [ -f "$F_FROM" ]; then
    se_line="$(grep -E '"event"[[:space:]]*:[[:space:]]*"session_end"' "$F_FROM" 2>/dev/null | tail -n 1)"
    # legacy logs may only carry "type":"session_end"
    if [ -z "$se_line" ]; then
      se_line="$(grep -E '"type"[[:space:]]*:[[:space:]]*"session_end"' "$F_FROM" 2>/dev/null | tail -n 1)"
    fi
  else
    se_line="$F_FROM"
  fi

  if [ -n "$se_line" ]; then
    # Extract the six flat fields; emit literal "null" for absent/null so we can detect "not provided".
    # A jq parse failure => parsed values stay empty (no signal), per fail-safe contract.
    parsed="$(printf '%s' "$se_line" | jq -r '
      [ (.contract_conformance_status // "null"),
        (.contract_violations // "null" | tostring),
        (.benchmark_status // "null"),
        (.benchmark_metric // "null"),
        (.benchmark_value // "null" | tostring),
        (.benchmark_delta // "null" | tostring) ] | @tsv
    ' 2>/dev/null)" || parsed=""

    if [ -n "$parsed" ]; then
      # Split the TSV into the six fields.
      OLD_IFS="$IFS"; IFS=$'\t'
      # shellcheck disable=SC2086
      set -- $parsed
      IFS="$OLD_IFS"
      p_conf_status="${1:-null}"; p_violations="${2:-null}"
      p_bm_status="${3:-null}";  p_bm_metric="${4:-null}"
      p_bm_value="${5:-null}";   p_bm_delta="${6:-null}"

      # Explicit flags win; parsed fills only what was NOT given on the command line.
      [ "$G_CONF_STATUS" -eq 0 ] && F_CONF_STATUS="$p_conf_status"
      [ "$G_VIOLATIONS"  -eq 0 ] && F_VIOLATIONS="$p_violations"
      [ "$G_BM_STATUS"   -eq 0 ] && F_BM_STATUS="$p_bm_status"
      [ "$G_BM_METRIC"   -eq 0 ] && F_BM_METRIC="$p_bm_metric"
      [ "$G_BM_VALUE"    -eq 0 ] && F_BM_VALUE="$p_bm_value"
      [ "$G_BM_DELTA"    -eq 0 ] && F_BM_DELTA="$p_bm_delta"
      # NOTE: session_end has no benchmark name field — F_BM_NAME comes only from the explicit flag.
    fi
  fi
fi

# ---- build the conformance segment ----------------------------------------
conf_seg=""
case "$F_CONF_STATUS" in
  pass|advisory_violations)
    up="$(printf '%s' "$F_CONF_STATUS" | tr '[:lower:]' '[:upper:]')"
    # note B: emit "(N violations)" ONLY when --violations is a valid integer (incl. genuine 0).
    # When null/non-numeric/absent, OMIT the parenthetical — never fabricate "(0 violations)",
    # so a genuine zero stays distinguishable from an unparseable/absent count. This also avoids
    # the self-contradictory "conformance ADVISORY_VIOLATIONS (0 violations)" line.
    if is_int "$F_VIOLATIONS"; then
      conf_seg="conformance $up ($F_VIOLATIONS violations)"
    else
      conf_seg="conformance $up"
    fi
    ;;
esac

# ---- build the benchmark segment ------------------------------------------
bm_seg=""
case "$F_BM_STATUS" in
  ""|null|None|skipped|unverified) : ;;   # no real benchmark result → no segment
  *)
    if is_int "$F_BM_VALUE"; then
      # label: name > metric > literal "benchmark" (omit the redundant word in the last case)
      if ! is_unset "$F_BM_NAME"; then
        bm_seg="benchmark $F_BM_NAME $F_BM_VALUE"
      elif ! is_unset "$F_BM_METRIC"; then
        bm_seg="benchmark $F_BM_METRIC $F_BM_VALUE"
      else
        bm_seg="benchmark $F_BM_VALUE"
      fi
      # signed delta, only when delta is a real number. Sign detection is purely
      # STRING-based (no arithmetic) so an int64-overflow string can never reach
      # [ -gt ]/[ -lt ] and emit a stderr diagnostic — the line stays clean and exit 0.
      if is_int "$F_BM_DELTA"; then
        # Normalize zero magnitude (0, 00, -0, -00) to a bare "0" so the cosmetic
        # "-0" never renders. Otherwise keep the verbatim sign for real magnitudes.
        case "${F_BM_DELTA#-}" in
          *[!0]*)                              # has a non-zero digit → real magnitude
            case "$F_BM_DELTA" in
              -*) sd="$F_BM_DELTA" ;;          # negative — already carries the minus
              *)  sd="+$F_BM_DELTA" ;;         # positive
            esac ;;
          *) sd="0" ;;                          # all-zero magnitude → normalized 0
        esac
        bm_seg="$bm_seg (Δ $sd)"
      fi
    fi
    ;;
esac

# ---- join + print ---------------------------------------------------------
if [ -n "$conf_seg" ] && [ -n "$bm_seg" ]; then
  printf 'Twin: %s · %s\n' "$conf_seg" "$bm_seg"
elif [ -n "$conf_seg" ]; then
  printf 'Twin: %s\n' "$conf_seg"
elif [ -n "$bm_seg" ]; then
  printf 'Twin: %s\n' "$bm_seg"
else
  printf 'Twin: no signal this run\n'
fi

exit 0
