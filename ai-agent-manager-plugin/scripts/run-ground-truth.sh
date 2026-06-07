#!/usr/bin/env bash
# run-ground-truth.sh — the System Twin GROUND-TRUTH execution runner (M2b slice 1a).
#
# This is the GROUND-TRUTH instrument: an ADVISORY runner that resolves a set of project-declared
# executable acceptance checks, runs each one (exit 0 = pass, non-0 = fail), and emits a single hard
# PASS/FAIL signal. Where the EVAL harness (run-eval.sh) scores plugin output quality over a fixed
# corpus, and the canary benchmark (run-benchmark.sh) validates hard-signal fixtures, THIS runner
# executes the actual acceptance checks a brief / project declares and reports whether they pass.
# "ground-truth" != "eval" != "benchmark" — kept distinct by name and intent.
#
# Output shape on stdout: a human/grep per-check block (one `  [PASS]/[FAIL]/[DEFERRED] <kind>:<target>`
# line per resolved check) + a `Checks passed: M/N` line, AND exactly ONE machine-readable line:
#   GROUND_TRUTH_JSON: {schema_version,ran,status,checks_total,checks_passed,pass_rate,per_check,commit,date}
# The JSON line is jq-built for injection safety (--arg/--argjson), with a printf fallback only on
# the no-jq path (mirrors run-benchmark.sh).
#
# Fail-safe: ALWAYS exits 0. A check's non-zero exit is a normal `fail` tally, NEVER a script crash.
#   - status "skipped"            — no check source resolved (no --check, no --brief Executable
#                                   Acceptance section, no --checks-file/stdin, no
#                                   .supervisor/twin/ground-truth.json). ran:false, 0/0, per_check [].
#   - status "unverified"         — fail-safe tooling path: jq unavailable (ran:false, 0/0, []), OR
#                                   the edge where checks resolved but NONE could actually be verified
#                                   (zero passes AND zero fails AND >=1 deferred — honest: nothing
#                                   was actually verified).
#   - status "advisory_failures"  — >=1 resolved check exited non-zero (a per_check fail present).
#   - status "pass"               — >=1 check executed and passed, and ZERO checks failed (deferred
#                                   qa-executor checks may coexist; they never block a pass).
#
# Check resolution (priority order):
#   1. Explicit: repeatable `--check '<line>'`; `--brief <path>` (extract the optional
#      `## Executable Acceptance` section — leading-`-` bullets between that heading and the next
#      `## ` heading); `--checks-file <path>` or stdin (one bullet per line).
#   2. Fallback: `.supervisor/twin/ground-truth.json` (gitignored) — a JSON array of check-line
#      strings, or {checks:[...]}; jq-parsed, tolerant.
#   3. None -> status "skipped".
#
# A check line is a `- `-stripped bullet that is EITHER a raw shell command OR `<kind>: <target>`
# where kind in {cmd, corpus-task, qa-executor}. Per-kind execution:
#   - cmd: <shell>   (or a bare line with no recognized kind:) -> run from repo root via
#                    `bash -c '<shell>' >/dev/null 2>&1`; exit 0 = pass.
#   - corpus-task: <task-id> -> resolve to $SCRIPT_DIR/eval-corpus/<task-id>/check.sh and run it the
#                    SAME way run-eval.sh does: `( cd "<task-dir>" && bash check.sh >/dev/null 2>&1 )`;
#                    exit 0 = pass. Missing task dir / check.sh -> per_check fail, reason
#                    "corpus_task_not_found" (a missing dogfood target is a real failure, not a drop).
#   - qa-executor: <target> -> RECOGNIZED but DEFERRED to slice 1b. Does NOT spawn anything; records
#                    per_check status "unverified", reason "qa_executor_dispatch_deferred_m2b_1b".
#                    Counts toward checks_total but neither checks_passed nor a fail.
#
# The runner is READ-ONLY w.r.t. the repo (it only executes the checks it is given). No network.
# eval-corpus is resolved relative to $SCRIPT_DIR so `corpus-task:` works regardless of CWD.
#
# Test-only env hook: GROUND_TRUTH_FORCE_NO_JQ=1 forces the no-jq fail-safe branch (so the self-test
# can deterministically exercise the "unverified" tooling path without a brittle PATH shim). It is a
# TEST-ONLY hook and has no effect on normal operation.
#
# Usage:  run-ground-truth.sh [--check '<line>']... [--brief <path>] [--checks-file <path>]
# Exit:   always 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORPUS="$SCRIPT_DIR/eval-corpus"

# ---- contextual fields (NOT part of the determinism invariant) ------------
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# ---- argv parse -----------------------------------------------------------
EXPLICIT_CHECKS=()   # collected from --check / --brief / --checks-file (in resolution order)
BRIEF=""
CHECKS_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)        EXPLICIT_CHECKS+=("${2:-}"); shift; [ $# -gt 0 ] && shift ;;
    --check=*)      EXPLICIT_CHECKS+=("${1#--check=}"); shift ;;
    --brief)        BRIEF="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --brief=*)      BRIEF="${1#--brief=}"; shift ;;
    --checks-file)  CHECKS_FILE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --checks-file=*) CHECKS_FILE="${1#--checks-file=}"; shift ;;
    *) shift ;;
  esac
done

# ---- emit helpers ---------------------------------------------------------
# emit_no_jq_unverified: hand-built minimal JSON (only fixed/whitelisted values — injection-safe).
emit_no_jq_unverified() {
  echo "Checks passed: 0/0"
  printf 'GROUND_TRUTH_JSON: {"schema_version":1,"ran":false,"status":"unverified","checks_total":0,"checks_passed":0,"pass_rate":"0/0","per_check":[],"commit":"%s","date":"%s"}\n' \
    "$COMMIT" "$DATE"
}

# emit_jq <ran-bool> <status> <total> <passed> <pass_rate> <per_check_json>
emit_jq() {
  local ran="$1" status="$2" total="$3" passed="$4" pr="$5" per_check="$6"
  echo "Checks passed: $pr"
  jq -cn \
    --argjson ran "$ran" \
    --arg status "$status" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --arg pr "$pr" \
    --argjson per_check "$per_check" \
    --arg commit "$COMMIT" \
    --arg date "$DATE" \
    '{schema_version:1,ran:$ran,status:$status,checks_total:$total,checks_passed:$passed,pass_rate:$pr,per_check:$per_check,commit:$commit,date:$date}' \
    | sed 's/^/GROUND_TRUTH_JSON: /'
}

# ---- fail-safe: no jq -----------------------------------------------------
# GROUND_TRUTH_FORCE_NO_JQ=1 forces this branch for deterministic self-testing.
if [ "${GROUND_TRUTH_FORCE_NO_JQ:-0}" = "1" ] || ! command -v jq >/dev/null 2>&1; then
  echo "run-ground-truth: no jq available — cannot build result, fail-safe no-op" >&2
  emit_no_jq_unverified
  exit 0
fi

# ---- resolve check lines (priority order) ---------------------------------
# CHECK_LINES is the ordered list of resolved bullet strings (already `- `-stripped, trimmed).
CHECK_LINES=()

# strip a leading `- ` (or `-`) bullet marker and surrounding whitespace.
strip_bullet() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim
  line="${line#- }"
  line="${line#-}"
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim again (after marker)
  line="${line%"${line##*[![:space:]]}"}"   # rtrim
  printf '%s' "$line"
}

add_line() {  # add a raw bullet line if non-empty after stripping
  local s; s="$(strip_bullet "$1")"
  [ -n "$s" ] && CHECK_LINES+=("$s")
}

# 1a. Explicit --check args (highest priority, in order).
if [ "${#EXPLICIT_CHECKS[@]}" -gt 0 ]; then
  for c in "${EXPLICIT_CHECKS[@]}"; do
    add_line "$c"
  done
fi

# 1b. --brief: extract the `## Executable Acceptance` section's leading-`-` bullets.
if [ -n "$BRIEF" ] && [ -f "$BRIEF" ]; then
  in_section=0
  while IFS= read -r raw || [ -n "$raw" ]; do
    case "$raw" in
      "## Executable Acceptance"*) in_section=1; continue ;;
      "## "*) [ "$in_section" -eq 1 ] && in_section=0 ;;
    esac
    if [ "$in_section" -eq 1 ]; then
      # only collect leading-`-` bullet lines (ignore blank lines / prose)
      trimmed="${raw#"${raw%%[![:space:]]*}"}"
      case "$trimmed" in
        -*) add_line "$raw" ;;
      esac
    fi
  done < "$BRIEF"
fi

# 1c. --checks-file (or stdin via "-"): one bullet per line.
if [ -n "$CHECKS_FILE" ]; then
  if [ "$CHECKS_FILE" = "-" ]; then
    while IFS= read -r raw || [ -n "$raw" ]; do add_line "$raw"; done
  elif [ -f "$CHECKS_FILE" ]; then
    while IFS= read -r raw || [ -n "$raw" ]; do add_line "$raw"; done < "$CHECKS_FILE"
  fi
fi

# 2. Fallback: .supervisor/twin/ground-truth.json (only if nothing explicit resolved).
if [ "${#CHECK_LINES[@]}" -eq 0 ]; then
  GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  GT_FILE="$GITROOT/.supervisor/twin/ground-truth.json"
  if [ -f "$GT_FILE" ]; then
    # Tolerant: accept a top-level array of strings OR {checks:[...]}; sort for stable order.
    gt_lines="$(jq -r '
        (if type=="array" then . elif (type=="object" and (.checks|type=="array")) then .checks else [] end)
        | map(select(type=="string")) | .[]
      ' "$GT_FILE" 2>/dev/null | LC_ALL=C sort)"
    if [ -n "$gt_lines" ]; then
      while IFS= read -r raw; do add_line "$raw"; done <<EOF
$gt_lines
EOF
    fi
  fi
fi

# 3. None resolved -> skipped.
if [ "${#CHECK_LINES[@]}" -eq 0 ]; then
  echo "run-ground-truth: no check source resolved — nothing to verify (skipped)" >&2
  emit_jq false "skipped" 0 0 "0/0" "[]"
  exit 0
fi

# ---- execute each resolved check ------------------------------------------
total=0
passed=0
failures=0
deferred=0
per_check_json="[]"

# append_check <kind> <target> <status> [reason]
append_check() {
  local kind="$1" target="$2" status="$3" reason="${4:-}"
  if [ -n "$reason" ]; then
    per_check_json="$(printf '%s' "$per_check_json" \
      | jq -c --arg k "$kind" --arg t "$target" --arg s "$status" --arg r "$reason" \
        '. + [{kind:$k,target:$t,status:$s,reason:$r}]')"
  else
    per_check_json="$(printf '%s' "$per_check_json" \
      | jq -c --arg k "$kind" --arg t "$target" --arg s "$status" \
        '. + [{kind:$k,target:$t,status:$s}]')"
  fi
}

for line in "${CHECK_LINES[@]}"; do
  total=$((total+1))

  # Classify: <kind>: <target> where kind in {cmd, corpus-task, qa-executor}; else bare shell cmd.
  kind=""
  target=""
  case "$line" in
    cmd:*)          kind="cmd";          target="$(strip_bullet "${line#cmd:}")" ;;
    corpus-task:*)  kind="corpus-task";  target="$(strip_bullet "${line#corpus-task:}")" ;;
    qa-executor:*)  kind="qa-executor";  target="$(strip_bullet "${line#qa-executor:}")" ;;
    *)              kind="cmd";          target="$line" ;;   # bare line -> treat as shell cmd
  esac

  case "$kind" in
    cmd)
      if bash -c "$target" >/dev/null 2>&1; then
        passed=$((passed+1))
        echo "  [PASS] cmd:$target"
        append_check "cmd" "$target" "pass"
      else
        failures=$((failures+1))
        echo "  [FAIL] cmd:$target"
        append_check "cmd" "$target" "fail"
      fi
      ;;
    corpus-task)
      # A corpus task-id is a single path segment under eval-corpus/. Reject empty ids and any
      # '/' or '..' so a target can never escape $CORPUS (resolve eval-corpus relative to SCRIPT_DIR).
      case "$target" in
        ""|*/*|*..*)
          failures=$((failures+1))
          echo "  [FAIL] corpus-task:$target (invalid task id)"
          append_check "corpus-task" "$target" "fail" "corpus_task_invalid_id"
          continue
          ;;
      esac
      task_dir="$CORPUS/$target"
      check="$task_dir/check.sh"
      if [ ! -f "$check" ]; then
        failures=$((failures+1))
        echo "  [FAIL] corpus-task:$target (check.sh not found)"
        append_check "corpus-task" "$target" "fail" "corpus_task_not_found"
      elif ( cd "$task_dir" && bash "$check" >/dev/null 2>&1 ); then
        passed=$((passed+1))
        echo "  [PASS] corpus-task:$target"
        append_check "corpus-task" "$target" "pass"
      else
        failures=$((failures+1))
        echo "  [FAIL] corpus-task:$target"
        append_check "corpus-task" "$target" "fail"
      fi
      ;;
    qa-executor)
      # DEFERRED to slice 1b — recognized, recorded, never spawned. Neither pass nor fail.
      deferred=$((deferred+1))
      echo "  [DEFERRED] qa-executor:$target (dispatch deferred to M2b slice 1b)"
      append_check "qa-executor" "$target" "unverified" "qa_executor_dispatch_deferred_m2b_1b"
      ;;
  esac
done

pass_rate="$passed/$total"

# ---- derive status --------------------------------------------------------
# advisory_failures: any check failed.
# pass:              >=1 real pass AND zero failures.
# unverified:        zero passes AND zero failures (only deferred checks resolved) — nothing verified.
if [ "$failures" -gt 0 ]; then
  status="advisory_failures"
elif [ "$passed" -gt 0 ]; then
  status="pass"
else
  # passed==0 && failures==0 => only deferred checks (deferred >= 1 by construction here).
  status="unverified"
fi

emit_jq true "$status" "$total" "$passed" "$pass_rate" "$per_check_json"
exit 0
