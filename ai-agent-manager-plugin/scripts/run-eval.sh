#!/usr/bin/env bash
# run-eval.sh — the System Twin EVAL harness (output-quality fitness function over a task corpus).
#
# This is the EVAL instrument: a deterministic runner/scorer that measures plugin *output quality*
# against a fixed corpus of tasks. Each task lives in its own self-contained dir
# (eval-corpus/<task-id>/) carrying an executable `check.sh` acceptance check (exit 0 = pass,
# non-0 = fail) that deterministically verifies the task's outcome. The metric is the pass rate
# M/N over the corpus: same corpus + same checks => identical tasks_total/tasks_passed/pass_rate/
# per_task, every run (the contextual `commit`/`date` fields legitimately vary and are NOT part of
# the determinism invariant).
#
# DISTINCT from the canary benchmark (run-benchmark.sh): the benchmark is the hard-signal pipeline
# canary (validates `session_end` hard-signal fixtures and produces selftest_pass_count). The EVAL
# harness here is a fitness function over an output-quality corpus. "eval" != "benchmark" — keep
# them separate in naming and directory.
#
# Output shape on stdout: a human/grep per-task block (one `  [PASS]/[FAIL] <task-id>` line per
# task) + a `Pass rate: M/N` line, AND exactly ONE machine-readable line:
#   EVAL_RESULT: {schema_version,tasks_total,tasks_passed,pass_rate,per_task,commit,date,status}
# The JSON line is jq-built for injection safety.
#
# Fail-safe: ALWAYS exits 0. When the corpus dir is missing OR `jq` is unavailable, emit
# `EVAL_RESULT: {...,"status":"unverified",...}` with tasks_total 0, pass_rate "0/0", per_task []
# (mirroring run-benchmark.sh — an eval that cannot run must never break its caller). A single
# task's non-zero check.sh is a normal "fail" tally, NOT a script crash.
#
# Out of scope here (M2b follow-ups): wiring this to auto-run the full agent loop in CI, and wiring
# it into Supervisor Phase 4.5 as a ground-truth signal. This script only runs the corpus checks.
#
# Usage:  run-eval.sh
# Env:    EVAL_CORPUS_DIR  — override the corpus dir (default: $SCRIPT_DIR/eval-corpus)
# Exit:   always 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="${EVAL_CORPUS_DIR:-$SCRIPT_DIR/eval-corpus}"

# ---- contextual fields (NOT part of the determinism invariant) ------------
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# ---- emit helpers ---------------------------------------------------------
# emit_unverified: fail-safe path — no corpus or no jq. tasks 0, pass_rate 0/0, per_task [].
emit_unverified() {
  echo "Pass rate: 0/0"
  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg pr "0/0" --arg commit "$COMMIT" --arg date "$DATE" \
      '{schema_version:1,tasks_total:0,tasks_passed:0,pass_rate:$pr,per_task:[],commit:$commit,date:$date,status:"unverified"}' \
      | sed 's/^/EVAL_RESULT: /'
  else
    # No jq: hand-built minimal JSON (only fixed/whitelisted values interpolated — injection-safe).
    printf 'EVAL_RESULT: {"schema_version":1,"tasks_total":0,"tasks_passed":0,"pass_rate":"0/0","per_task":[],"commit":"%s","date":"%s","status":"unverified"}\n' \
      "$COMMIT" "$DATE"
  fi
}

# Fail-safe: no jq available. Emit unverified.
if ! command -v jq >/dev/null 2>&1; then
  echo "run-eval: no jq available — eval cannot build its result, fail-safe no-op" >&2
  emit_unverified
  exit 0
fi

# Fail-safe: corpus dir missing. Emit unverified.
if [ ! -d "$CORPUS" ]; then
  echo "run-eval: corpus dir '$CORPUS' not found — fail-safe no-op" >&2
  emit_unverified
  exit 0
fi

# ---- discover tasks (deterministic, sorted) -------------------------------
# A task is a dir eval-corpus/<task-id>/ containing an executable check.sh.
total=0
passed=0
per_task_json="[]"   # jq-accumulated array of {id,status}

# Collect candidate task dirs in sorted order. `find ... | LC_ALL=C sort` gives deterministic
# ordering independent of filesystem enumeration order AND of the caller's locale (LC_COLLATE).
task_dirs="$(find "$CORPUS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)"

if [ -n "$task_dirs" ]; then
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    check="$dir/check.sh"
    # Only count dirs that carry an executable check.sh.
    [ -f "$check" ] && [ -x "$check" ] || continue

    task_id="$(basename "$dir")"
    total=$((total+1))

    # Run the check. A non-zero exit is a normal "fail" tally — never let it abort this script.
    if ( cd "$dir" && bash "$check" >/dev/null 2>&1 ); then
      status="pass"
      passed=$((passed+1))
      echo "  [PASS] $task_id"
    else
      status="fail"
      echo "  [FAIL] $task_id"
    fi

    # Append {id,status} to the accumulator via jq (injection-safe — values pass as --arg).
    per_task_json="$(printf '%s' "$per_task_json" \
      | jq -c --arg id "$task_id" --arg st "$status" '. + [{id:$id,status:$st}]')"
  done <<EOF
$task_dirs
EOF
fi

pass_rate="$passed/$total"
echo "Pass rate: $pass_rate"

# ---- emit the single machine-readable result line -------------------------
jq -cn \
  --argjson total "$total" \
  --argjson passed "$passed" \
  --arg pr "$pass_rate" \
  --argjson per_task "$per_task_json" \
  --arg commit "$COMMIT" \
  --arg date "$DATE" \
  '{schema_version:1,tasks_total:$total,tasks_passed:$passed,pass_rate:$pr,per_task:$per_task,commit:$commit,date:$date,status:"ok"}' \
  | sed 's/^/EVAL_RESULT: /'

exit 0
