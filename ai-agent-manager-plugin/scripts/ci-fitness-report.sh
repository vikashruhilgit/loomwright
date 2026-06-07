#!/usr/bin/env bash
# ci-fitness-report.sh — ADVISORY, NON-GATING fitness summary for CI.
#
# Runs the three System Twin "fitness" runners (eval harness, ground-truth, benchmark),
# tolerantly parses each one-line JSON result with jq, and writes a readable markdown
# summary to STDOUT. The CI step redirects this stdout into $GITHUB_STEP_SUMMARY.
#
# CONTRACT: this report is ADVISORY ONLY and NEVER fails the build. It does not use
# `set -e`; every command is guarded; the script ALWAYS ends with `exit 0`. M3 hard-gating
# of these signals is explicitly out of scope.
#
# This helper deliberately is NOT named test-*.sh, so the CI self-test gate loop
# (which globs ai-agent-manager-plugin/scripts/test-*.sh) never picks it up.
#
# Usage:  bash ai-agent-manager-plugin/scripts/ci-fitness-report.sh   # prints markdown, exits 0

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"

# jq is the only hard dependency of the runners; ubuntu-latest ships it. If it is somehow
# absent we still emit a well-formed (degraded) summary rather than erroring.
HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# jget <json> <filter> — tolerant field extract: prints jq result or "n/a" on any failure.
jget() {
  local json="$1" filter="$2" out=""
  if [ "$HAVE_JQ" -eq 1 ] && [ -n "$json" ]; then
    out="$(printf '%s' "$json" | jq -r "$filter // \"n/a\"" 2>/dev/null || true)"
  fi
  [ -n "$out" ] && printf '%s' "$out" || printf 'n/a'
}

# --- run the three runners, capturing stdout so machine lines do not leak into the summary ---
eval_out="$(bash "$HERE/run-eval.sh" 2>/dev/null || true)"
gt_out="$(bash "$HERE/run-ground-truth.sh" --check 'corpus-task: version-consistent' 2>/dev/null || true)"
bench_out="$(bash "$HERE/run-benchmark.sh" 2>/dev/null || true)"

# --- extract the single machine line from each (strip the prefix) ---
eval_line="$(printf '%s\n' "$eval_out"  | grep '^EVAL_RESULT:'      2>/dev/null | head -n1 | sed 's/^EVAL_RESULT: *//'        || true)"
gt_line="$(printf '%s\n'   "$gt_out"    | grep '^GROUND_TRUTH_JSON:' 2>/dev/null | head -n1 | sed 's/^GROUND_TRUTH_JSON: *//'  || true)"
bench_line="$(printf '%s\n' "$bench_out" | grep '^BENCHMARK_JSON:'    2>/dev/null | head -n1 | sed 's/^BENCHMARK_JSON: *//'     || true)"

# --- eval fields ---
eval_pass_rate="$(jget "$eval_line" '.pass_rate')"
eval_status="$(jget "$eval_line" '.status')"

# --- ground-truth fields ---
gt_status="$(jget "$gt_line" '.status')"
gt_passed="$(jget "$gt_line" '.checks_passed')"
gt_total="$(jget "$gt_line" '.checks_total')"

# --- benchmark fields ---
bench_metric="$(jget "$bench_line" '.metric')"
bench_value="$(jget "$bench_line" '.value')"
bench_status="$(jget "$bench_line" '.status')"

# --- write the markdown summary to stdout ---
printf '## System Twin — Fitness (advisory, non-gating)\n\n'
printf '| Signal | Result | Status |\n'
printf '| --- | --- | --- |\n'
printf '| Eval harness (pass_rate) | %s | %s |\n' "$eval_pass_rate" "$eval_status"
printf '| Ground-truth (checks) | %s/%s | %s |\n' "$gt_passed" "$gt_total" "$gt_status"
printf '| Benchmark (%s) | %s | %s |\n' "$bench_metric" "$bench_value" "$bench_status"
printf '\n_This report is **advisory** and **never fails the build** — hard-gating of these fitness signals (M3) is out of scope._\n'

exit 0
