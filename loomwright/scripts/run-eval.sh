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
# Result persistence: on a normal run the EVAL_RESULT is appended as ONE JSON line to a small
# history file (default: <gitroot>/.supervisor/eval/results.jsonl) so a trend exists release over
# release. The appended object is the full EVAL_RESULT plus a `recorded_at` UTC timestamp. Recording
# is BEST-EFFORT / fail-safe: any failure (no git root, cannot mkdir, cannot write) never changes the
# exit code or stdout — recording is a side effect, never a hard dependency. `--no-record` suppresses
# it entirely; EVAL_RESULTS_FILE redirects the history file (used by the self-test). recorded_at,
# commit, date legitimately vary and are NOT part of the determinism invariant.
#
# Project root: every check.sh is run with CWD = its task dir (task-local relative paths keep working)
# and with EVAL_PROJECT_ROOT exported = the project it must VERIFY: `--project <dir>` if given, else
# the git toplevel of the CALLER's CWD, else the caller's CWD. A check.sh must never derive the
# project from its own location — on a marketplace install this script and its corpus live under
# the plugin manager's install cache, outside any git repo, so a `git rev-parse --show-toplevel` from the task
# dir fails there while the caller's project is perfectly resolvable (the run-ground-truth.sh
# 2026-09-13 incident; contract in eval-corpus/README.md §"Project root"). The `commit` field and the
# default results.jsonl location are read from the same root. A `--project` that is not a directory
# is a caller error: emit the fail-safe "unverified" shape (0/0, per_task []) rather than scoring the
# corpus against some other directory.
#
# Usage:  run-eval.sh [--no-record] [--project <dir>]
# Env:    EVAL_CORPUS_DIR    — override the corpus dir (default: $SCRIPT_DIR/eval-corpus)
#         EVAL_RESULTS_FILE  — override the history file (default: <project-root>/.supervisor/eval/results.jsonl)
# Exit:   always 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="${EVAL_CORPUS_DIR:-$SCRIPT_DIR/eval-corpus}"

# ---- argv parse -----------------------------------------------------------
RECORD=1
PROJECT_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-record) RECORD=0; shift ;;
    --project)   PROJECT_ARG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --project=*) PROJECT_ARG="${1#--project=}"; shift ;;
    *) shift ;;
  esac
done

# ---- project root (what every check.sh verifies; see header) --------------
# `--project <dir>` wins; else the caller's git toplevel; else the caller's CWD. Exported ONCE as
# EVAL_PROJECT_ROOT before any task runs. RECORD_ROOT_OK gates the DEFAULT results.jsonl
# location: recording into an arbitrary non-git CWD would litter it with .supervisor/, so absent an
# explicit --project and a git root, default recording is skipped (as before this flag existed).
PROJECT_ROOT=""
RECORD_ROOT_OK=0
PROJECT_ARG_INVALID=0
if [ -n "$PROJECT_ARG" ]; then
  if [ -d "$PROJECT_ARG" ]; then
    PROJECT_ROOT="$(cd "$PROJECT_ARG" && pwd -P)"
    RECORD_ROOT_OK=1   # explicit: the caller named the project, so recording there is wanted even if it is not a git repo
  else
    PROJECT_ARG_INVALID=1
  fi
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$PROJECT_ROOT" ]; then
    RECORD_ROOT_OK=1
  else
    PROJECT_ROOT="$(pwd -P)"
  fi
fi
export EVAL_PROJECT_ROOT="$PROJECT_ROOT"

# ---- results history file (best-effort persistence target) ----------------
# Resolve once. Default to <project-root>/.supervisor/eval/results.jsonl; guard the no-git/no-flag
# case so we never litter an arbitrary CWD (and never produce a path beginning with "/.supervisor/").
if [ -n "${EVAL_RESULTS_FILE:-}" ]; then
  RESULTS_FILE="$EVAL_RESULTS_FILE"
elif [ "$RECORD_ROOT_OK" -eq 1 ] && [ -n "$PROJECT_ROOT" ]; then
  RESULTS_FILE="$PROJECT_ROOT/.supervisor/eval/results.jsonl"
else
  RESULTS_FILE=""   # no project root — recording will be skipped (fail-safe)
fi

# record_result <eval-result-json>: append the EVAL_RESULT object (no "EVAL_RESULT: " prefix) plus a
# `recorded_at` UTC timestamp as ONE JSON line to $RESULTS_FILE. Requires jq (callers guarantee it on
# this path). BEST-EFFORT: gated by --no-record and an empty target, and wrapped so any failure is
# swallowed — recording must NEVER change the exit code or stdout.
record_result() {
  [ "$RECORD" -eq 1 ] || return 0
  [ -n "$RESULTS_FILE" ] || return 0
  local obj="$1"
  {
    mkdir -p "$(dirname "$RESULTS_FILE")" \
      && printf '%s' "$obj" \
        | jq -c --arg ra "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" '. + {recorded_at:$ra}' \
        >> "$RESULTS_FILE"
  } 2>/dev/null || true
}

# ---- contextual fields (NOT part of the determinism invariant) ------------
# `commit` describes the PROJECT being scored (not this script's own checkout — they differ on a
# marketplace install), so it is read from PROJECT_ROOT.
if [ -n "$PROJECT_ROOT" ]; then
  COMMIT="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
else
  COMMIT="unknown"
fi
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# ---- emit helpers ---------------------------------------------------------
# emit_unverified: fail-safe path — no corpus or no jq. tasks 0, pass_rate 0/0, per_task [].
emit_unverified() {
  echo "Pass rate: 0/0"
  if command -v jq >/dev/null 2>&1; then
    local obj
    obj="$(jq -cn \
      --arg pr "0/0" --arg commit "$COMMIT" --arg date "$DATE" \
      '{schema_version:1,tasks_total:0,tasks_passed:0,pass_rate:$pr,per_task:[],commit:$commit,date:$date,status:"unverified"}')"
    printf 'EVAL_RESULT: %s\n' "$obj"
    # Record the unverified result too, for trend continuity (jq IS available on this branch).
    record_result "$obj"
  else
    # No jq: hand-built minimal JSON (only fixed/whitelisted values interpolated — injection-safe).
    # Recording is skipped here on purpose — record_result requires jq to build the line cleanly.
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

# Fail-safe: --project names a non-directory. Emit unverified (never score against another dir).
if [ "$PROJECT_ARG_INVALID" -eq 1 ]; then
  echo "run-eval: --project '$PROJECT_ARG' is not a directory — fail-safe no-op" >&2
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
# A task is a dir eval-corpus/<task-id>/ containing a check.sh. An executable check.sh is run;
# a present-but-NON-executable check.sh is counted as a FAIL (with a stderr warning) rather than
# silently dropped, so a forgotten `chmod +x` cannot quietly shrink N and mask a regression.
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
    # A dir without any check.sh is not a task — skip it silently.
    [ -f "$check" ] || continue

    task_id="$(basename "$dir")"
    total=$((total+1))

    if [ ! -x "$check" ]; then
      # Present-but-not-executable: count as FAIL and warn loudly rather than silently dropping
      # the task. A silently dropped task shrinks N (tasks_total) and can MASK a regression — a
      # would-be-failing task vanishing keeps pass_rate green. A visible FAIL protects the M/N signal.
      echo "WARN: $task_id: check.sh is present but not executable (run: chmod +x) — counting as FAIL" >&2
      status="fail"
      echo "  [FAIL] $task_id (check.sh not executable)"
    # Run the check. A non-zero exit is a normal "fail" tally — never let it abort this script.
    # CWD = task dir; the project to VERIFY reaches the check via the exported EVAL_PROJECT_ROOT.
    elif ( cd "$dir" && bash "$check" >/dev/null 2>&1 ); then
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
# Build the object once, emit it (prefixed) to stdout, then record it (best-effort).
result_json="$(jq -cn \
  --argjson total "$total" \
  --argjson passed "$passed" \
  --arg pr "$pass_rate" \
  --argjson per_task "$per_task_json" \
  --arg commit "$COMMIT" \
  --arg date "$DATE" \
  '{schema_version:1,tasks_total:$total,tasks_passed:$passed,pass_rate:$pr,per_task:$per_task,commit:$commit,date:$date,status:"ok"}')"
printf 'EVAL_RESULT: %s\n' "$result_json"
record_result "$result_json"

exit 0
