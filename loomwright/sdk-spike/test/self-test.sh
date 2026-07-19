#!/usr/bin/env bash
# self-test.sh — offline-safe self-test for the QUARANTINED sdk-spike.
#
# bash-3.2-safe (macOS stock bash): no associative arrays, no mapfile, no ${var,,}.
# Exits non-zero on any FAIL. Degrades gracefully offline:
#   - node_modules absent  -> compile step SKIPped (offline CI safety)
#   - no compiled dist and no local tsx -> dry-run step degrades to
#     fixture-vs-schema required-key checks (node preferred, jq fallback)
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SPIKE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$SPIKE_DIR" || { echo "FATAL: cannot cd to spike dir"; exit 1; }

FAILURES=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; }

HAVE_NODE=0; command -v node >/dev/null 2>&1 && HAVE_NODE=1
HAVE_NPM=0;  command -v npm  >/dev/null 2>&1 && HAVE_NPM=1
HAVE_JQ=0;   command -v jq   >/dev/null 2>&1 && HAVE_JQ=1

WORKER_FIXTURE="src/dry-run-fixtures/worker-result.fixture.json"
REVIEW_FIXTURE="src/dry-run-fixtures/code-review-result.fixture.json"
WORKER_FAIL_FIXTURE="src/dry-run-fixtures/worker-result-fail.fixture.json"
REVIEW_FAIL_FIXTURE="src/dry-run-fixtures/code-review-result-fail.fixture.json"
MINI_BRIEF="test/fixtures/mini-brief.md"

# ---------------------------------------------------------------------------
# (0) Static file presence
# ---------------------------------------------------------------------------
for f in package.json tsconfig.json src/runner.ts src/schemas.ts README.md \
         "$WORKER_FIXTURE" "$REVIEW_FIXTURE" \
         "$WORKER_FAIL_FIXTURE" "$REVIEW_FAIL_FIXTURE" "$MINI_BRIEF"; do
  if [ -f "$f" ]; then
    pass "file present: $f"
  else
    fail "file missing: $f"
  fi
done

# ---------------------------------------------------------------------------
# (a) Compile — only when node_modules is present (offline CI safety)
# ---------------------------------------------------------------------------
if [ -d node_modules ] && [ "$HAVE_NPM" = 1 ]; then
  BUILD_LOG=$(mktemp -t sdk-spike-build) || BUILD_LOG=".self-test-build.log"
  if npm run build >"$BUILD_LOG" 2>&1; then
    pass "npm run build compiles"
  else
    fail "npm run build failed (see $BUILD_LOG)"
  fi
else
  skip "compile skipped — node_modules absent or npm unavailable (offline CI safety)"
fi

# ---------------------------------------------------------------------------
# (b) Dry-run against the mini fixture brief (offline, deterministic).
#     Prefer compiled output; fall back to a LOCAL tsx (--no-install keeps
#     this offline); else degrade to fixture-vs-schema checks below.
# ---------------------------------------------------------------------------
RUNNER_OUT=""
RUNNER_RAN=0
if [ "$HAVE_NODE" = 1 ] && [ -f dist/runner.js ]; then
  if RUNNER_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run 2>&1); then
    RUNNER_RAN=1
    pass "dry-run executed via compiled dist/runner.js"
  else
    fail "dry-run via dist/runner.js exited non-zero: $RUNNER_OUT"
  fi
elif [ "$HAVE_NODE" = 1 ] && [ -x node_modules/.bin/tsx ]; then
  if RUNNER_OUT=$(node_modules/.bin/tsx src/runner.ts --brief "$MINI_BRIEF" --dry-run 2>&1); then
    RUNNER_RAN=1
    pass "dry-run executed via local tsx"
  else
    fail "dry-run via tsx exited non-zero: $RUNNER_OUT"
  fi
else
  skip "dry-run execution skipped — no dist/runner.js and no local tsx (degrading to fixture-vs-schema checks)"
fi

if [ "$RUNNER_RAN" = 1 ]; then
  if [ "$HAVE_NODE" = 1 ]; then
    if printf '%s' "$RUNNER_OUT" | node -e '
      const data = require("fs").readFileSync(0, "utf8");
      const r = JSON.parse(data);
      const problems = [];
      if (r.schema_version !== 1) problems.push("schema_version !== 1");
      if (r.mode !== "dry-run") problems.push("mode !== dry-run");
      for (const k of ["subtasks_completed","subtasks_failed","merge_order","worktrees","branches"])
        if (!Array.isArray(r[k])) problems.push("not an array: " + k);
      if (typeof r.summary !== "string" || r.summary.length === 0) problems.push("summary missing");
      // mini-brief: subtask 1 launchable, subtask 2 unblocks after 1 -> both complete
      if (!Array.isArray(r.subtasks_completed) || r.subtasks_completed.length !== 2)
        problems.push("expected 2 completed subtasks, got " + JSON.stringify(r.subtasks_completed));
      if (Array.isArray(r.subtasks_failed) && r.subtasks_failed.length !== 0)
        problems.push("expected 0 failed subtasks");
      if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
    '; then
      pass "dry-run output is a valid EXECUTE_RESULT-equivalent block (2/2 completed, wave unblock worked)"
    else
      fail "dry-run output failed EXECUTE_RESULT-equivalent assertions"
    fi
  elif [ "$HAVE_JQ" = 1 ]; then
    if printf '%s' "$RUNNER_OUT" | jq -e '
      .schema_version == 1 and .mode == "dry-run"
      and (.subtasks_completed | length) == 2
      and (.subtasks_failed | length) == 0
      and (.merge_order | type) == "array"
      and (.worktrees | type) == "array"
      and (.summary | type) == "string"
    ' >/dev/null 2>&1; then
      pass "dry-run output is a valid EXECUTE_RESULT-equivalent block (jq)"
    else
      fail "dry-run output failed EXECUTE_RESULT-equivalent assertions (jq)"
    fi
  else
    skip "dry-run output assertions skipped — neither node nor jq available"
  fi
fi

# ---------------------------------------------------------------------------
# (b1a) Per-subtask token accounting on completed entries (dry-run zeros are
#       synthesized, so every completed entry must carry token_usage with
#       proxy:true — never invented token counts).
# ---------------------------------------------------------------------------
if [ "$RUNNER_RAN" = 1 ] && [ "$HAVE_NODE" = 1 ]; then
  if printf '%s' "$RUNNER_OUT" | node -e '
      const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const problems = [];
      if (!Array.isArray(r.subtasks_completed) || r.subtasks_completed.length === 0)
        problems.push("no completed entries to check token_usage on");
      for (const s of r.subtasks_completed ?? []) {
        const t = s.token_usage;
        if (!t || typeof t !== "object") { problems.push(s.task_id + ": token_usage missing"); continue; }
        if (t.proxy !== true) problems.push(s.task_id + ": proxy !== true on dry-run entry");
        for (const role of ["worker", "reviewer"]) {
          if (!t[role] || typeof t[role].input_tokens !== "number" || typeof t[role].total_cost_usd !== "number")
            problems.push(s.task_id + ": " + role + " role usage missing/malformed");
        }
        if (typeof t.total_tokens !== "number" || typeof t.total_cost_usd !== "number")
          problems.push(s.task_id + ": total_tokens/total_cost_usd missing");
      }
      if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
    '; then
    pass "dry-run completed entries carry token_usage (worker+reviewer roles, proxy:true)"
  else
    fail "dry-run completed entries missing/malformed token_usage (proxy:true expected)"
  fi
else
  skip "token-accounting check on completed entries skipped — dry-run output or node unavailable"
fi

# ---------------------------------------------------------------------------
# (b1b) Failure-path dry-runs (offline): --dry-run-fixture-set fail /
#       review-fail exercise the worker-failed gate, the review-FAIL branch,
#       and the blocked-forever sweep (dependent subtask lands failed).
# ---------------------------------------------------------------------------
if [ "$HAVE_NODE" = 1 ] && [ -f dist/runner.js ]; then
  FAIL_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --dry-run-fixture-set fail 2>&1)
  FAIL_CODE=$?
  if [ "$FAIL_CODE" = 1 ] && printf '%s' "$FAIL_OUT" | node -e '
      const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const problems = [];
      if (r.subtasks_completed.length !== 0) problems.push("expected 0 completed");
      if (r.subtasks_failed.length !== 2) problems.push("expected 2 failed (worker-failed + blocked dependent)");
      if (!r.subtasks_failed.some((s) => s.error.includes("status=failed"))) problems.push("worker-failed gate error missing");
      if (!r.subtasks_failed.some((s) => s.error.includes("blocked"))) problems.push("blocked-forever sweep error missing");
      if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
    '; then
    pass "failure dry-run (fixture-set fail): worker-failed gate + blocked-forever sweep, exit 1"
  else
    fail "failure dry-run (fixture-set fail) assertions failed (exit $FAIL_CODE): $FAIL_OUT"
  fi
  REVFAIL_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --dry-run-fixture-set review-fail 2>&1)
  REVFAIL_CODE=$?
  if [ "$REVFAIL_CODE" = 1 ] && printf '%s' "$REVFAIL_OUT" | node -e '
      const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const problems = [];
      if (r.subtasks_completed.length !== 0) problems.push("expected 0 completed");
      if (r.subtasks_failed.length !== 2) problems.push("expected 2 failed (review FAIL + blocked dependent)");
      if (!r.subtasks_failed.some((s) => s.error.includes("review decision FAIL"))) problems.push("review-FAIL branch error missing");
      if (!r.subtasks_failed.some((s) => s.error.includes("blocked"))) problems.push("blocked-forever sweep error missing");
      if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
    '; then
    pass "failure dry-run (fixture-set review-fail): review-FAIL branch + blocked-forever sweep, exit 1"
  else
    fail "failure dry-run (fixture-set review-fail) assertions failed (exit $REVFAIL_CODE): $REVFAIL_OUT"
  fi
  # Token accounting on the failure path: the worker-failed entry ran ONLY the
  # worker query (worker usage present, reviewer null — review never ran); the
  # blocked-forever entry ran NO query (token_usage null, nothing invented).
  if printf '%s' "$FAIL_OUT" | node -e '
      const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const problems = [];
      const workerFailed = (r.subtasks_failed ?? []).filter((s) => s.error.includes("status=failed"));
      const blocked = (r.subtasks_failed ?? []).filter((s) => s.error.includes("blocked"));
      if (workerFailed.length === 0) problems.push("no worker-failed entry found");
      if (blocked.length === 0) problems.push("no blocked entry found");
      for (const s of workerFailed) {
        const t = s.token_usage;
        if (!t || typeof t !== "object") { problems.push(s.task_id + ": worker-failed entry missing token_usage"); continue; }
        if (!t.worker || typeof t.worker.input_tokens !== "number")
          problems.push(s.task_id + ": worker usage missing on worker-failed entry");
        if (t.reviewer !== null) problems.push(s.task_id + ": reviewer must be null (review never ran)");
      }
      for (const s of blocked) {
        if (s.token_usage !== null) problems.push(s.task_id + ": blocked entry token_usage must be null");
      }
      if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
    '; then
    pass "failure dry-run token accounting: worker-failed entry has worker usage + reviewer null; blocked entry null"
  else
    fail "failure dry-run token accounting assertions failed: $FAIL_OUT"
  fi
  # QueryFailedError fold-back (offline): fixture-set throw-usage makes the
  # reviewer query throw AFTER usage capture; the runSubtask catch must fold
  # the thrown query's synthetic usage (proxy:true — never invented as real)
  # into the failed entry's token_usage.reviewer.
  THROW_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --dry-run-fixture-set throw-usage 2>&1)
  THROW_CODE=$?
  if [ "$THROW_CODE" = 1 ] && printf '%s' "$THROW_OUT" | node -e '
      const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const problems = [];
      if (r.subtasks_completed.length !== 0) problems.push("expected 0 completed");
      const thrown = (r.subtasks_failed ?? []).filter((s) => s.error.includes("throw-usage fixture"));
      if (thrown.length === 0) problems.push("no reviewer-threw entry found");
      for (const s of thrown) {
        const t = s.token_usage;
        if (!t || typeof t !== "object") { problems.push(s.task_id + ": token_usage missing on thrown entry"); continue; }
        if (!t.reviewer) { problems.push(s.task_id + ": reviewer usage not folded back from QueryFailedError"); continue; }
        if (t.reviewer.input_tokens !== 1000 || t.reviewer.output_tokens !== 200 ||
            t.reviewer.cache_creation_input_tokens !== 50 || t.reviewer.cache_read_input_tokens !== 300)
          problems.push(s.task_id + ": folded reviewer usage does not match the thrown fixture usage");
        if (t.proxy !== true) problems.push(s.task_id + ": proxy must be true (synthetic thrown usage)");
        if (!t.worker) problems.push(s.task_id + ": worker usage missing (worker ran before the throw)");
      }
      if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
    '; then
    pass "failure dry-run (fixture-set throw-usage): QueryFailedError usage folded into failed entry (proxy:true), exit 1"
  else
    fail "failure dry-run (fixture-set throw-usage) fold-back assertions failed (exit $THROW_CODE): $THROW_OUT"
  fi
  # Symmetric WORKER-arm fold-back (offline): fixture-set throw-usage-worker
  # makes the WORKER query throw after usage capture; the catch must fold the
  # usage into token_usage.worker, and reviewer stays null (never ran).
  THROWW_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --dry-run-fixture-set throw-usage-worker 2>&1)
  THROWW_CODE=$?
  if [ "$THROWW_CODE" = 1 ] && printf '%s' "$THROWW_OUT" | node -e '
      const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const problems = [];
      if (r.subtasks_completed.length !== 0) problems.push("expected 0 completed");
      const thrown = (r.subtasks_failed ?? []).filter((s) => s.error.includes("throw-usage-worker fixture"));
      if (thrown.length === 0) problems.push("no worker-threw entry found");
      for (const s of thrown) {
        const t = s.token_usage;
        if (!t || typeof t !== "object") { problems.push(s.task_id + ": token_usage missing on thrown entry"); continue; }
        if (!t.worker) { problems.push(s.task_id + ": worker usage not folded back from QueryFailedError"); continue; }
        if (t.worker.input_tokens !== 700 || t.worker.output_tokens !== 150 ||
            t.worker.cache_creation_input_tokens !== 40 || t.worker.cache_read_input_tokens !== 250)
          problems.push(s.task_id + ": folded worker usage does not match the thrown fixture usage");
        if (t.proxy !== true) problems.push(s.task_id + ": proxy must be true (synthetic thrown usage)");
        if (t.reviewer !== null) problems.push(s.task_id + ": reviewer must be null (reviewer never ran)");
      }
      if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
    '; then
    pass "failure dry-run (fixture-set throw-usage-worker): worker-arm fold-back proven (worker usage folded, reviewer null, proxy:true, exit 1)"
  else
    fail "failure dry-run (fixture-set throw-usage-worker) fold-back assertions failed (exit $THROWW_CODE): $THROWW_OUT"
  fi
else
  skip "failure-path dry-runs skipped — dist/runner.js not available"
fi

# ---------------------------------------------------------------------------
# (b1c) Config-lever CLI validation (fail-closed, BEFORE any query) +
#       task-budget boundary acceptance — dist-guarded like (b1b).
# ---------------------------------------------------------------------------
if [ "$HAVE_NODE" = 1 ] && [ -f dist/runner.js ]; then
  WEFF_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --worker-effort turbo 2>&1)
  WEFF_CODE=$?
  if [ "$WEFF_CODE" != 0 ] && printf '%s' "$WEFF_OUT" | grep -q -- "--worker-effort must be one of"; then
    pass "invalid --worker-effort fails closed (exit $WEFF_CODE, names the flag + allowed set)"
  else
    fail "invalid --worker-effort did not fail closed (exit $WEFF_CODE): $WEFF_OUT"
  fi
  GEFF_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --effort ludicrous 2>&1)
  GEFF_CODE=$?
  if [ "$GEFF_CODE" != 0 ] && printf '%s' "$GEFF_OUT" | grep -q -- "--effort must be one of"; then
    pass "invalid --effort fails closed (exit $GEFF_CODE, names the flag + allowed set)"
  else
    fail "invalid --effort did not fail closed (exit $GEFF_CODE): $GEFF_OUT"
  fi
  TBLO_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --task-budget 100 2>&1)
  TBLO_CODE=$?
  if [ "$TBLO_CODE" != 0 ] && printf '%s' "$TBLO_OUT" | grep -q "20000"; then
    pass "--task-budget 100 fails closed citing the 20000-token minimum (exit $TBLO_CODE)"
  else
    fail "--task-budget 100 did not fail closed citing the minimum (exit $TBLO_CODE): $TBLO_OUT"
  fi
  TBNI_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --task-budget 1.5 2>&1)
  TBNI_CODE=$?
  if [ "$TBNI_CODE" != 0 ] && printf '%s' "$TBNI_OUT" | grep -q -- "--task-budget must be an integer"; then
    pass "--task-budget 1.5 (non-integer) fails closed (exit $TBNI_CODE)"
  else
    fail "--task-budget 1.5 did not fail closed on the non-integer branch (exit $TBNI_CODE): $TBNI_OUT"
  fi
  REFF_OUT=$(node dist/runner.js --brief "$MINI_BRIEF" --dry-run --reviewer-effort bogus 2>&1)
  REFF_CODE=$?
  if [ "$REFF_CODE" != 0 ] && printf '%s' "$REFF_OUT" | grep -q -- "--reviewer-effort must be one of"; then
    pass "invalid --reviewer-effort fails closed (exit $REFF_CODE, names the flag + allowed set)"
  else
    fail "invalid --reviewer-effort did not fail closed (exit $REFF_CODE): $REFF_OUT"
  fi
  TBOK_OUT=$(SDK_SPIKE_TRACE_OPTS=1 node dist/runner.js --brief "$MINI_BRIEF" --dry-run --task-budget 20000 2>&1)
  TBOK_CODE=$?
  if [ "$TBOK_CODE" = 0 ]; then
    pass "--task-budget 20000 boundary accepted (dry-run completes, exit 0)"
  else
    fail "--task-budget 20000 boundary rejected (exit $TBOK_CODE): $TBOK_OUT"
  fi

  # Positive-path effort-precedence assertions (via the dry-run seam's
  # DRY-RUN opts trace on stderr — asserts the RESOLVED values the real call
  # sites pass, closing the gap where a precedence regression would pass
  # silently offline because dry-run never acts on effort).
  PDEF_OUT=$(SDK_SPIKE_TRACE_OPTS=1 node dist/runner.js --brief "$MINI_BRIEF" --dry-run 2>&1)
  if printf '%s' "$PDEF_OUT" | grep -q "DRY-RUN worker opts: effort=medium taskBudget=(omitted)" \
     && printf '%s' "$PDEF_OUT" | grep -q "DRY-RUN reviewer opts: effort=high taskBudget=(omitted)"; then
    pass "effort precedence (no flags): ROLE_CONFIG defaults resolve (worker=medium, reviewer=high; taskBudget omitted)"
  else
    fail "effort precedence (no flags) trace missing or wrong: $PDEF_OUT"
  fi
  PGLO_OUT=$(SDK_SPIKE_TRACE_OPTS=1 node dist/runner.js --brief "$MINI_BRIEF" --dry-run --effort low 2>&1)
  if printf '%s' "$PGLO_OUT" | grep -q "DRY-RUN worker opts: effort=low" \
     && printf '%s' "$PGLO_OUT" | grep -q "DRY-RUN reviewer opts: effort=low"; then
    pass "effort precedence (--effort low): global override beats ROLE_CONFIG for BOTH roles"
  else
    fail "effort precedence (--effort low) trace missing or wrong: $PGLO_OUT"
  fi
  PPER_OUT=$(SDK_SPIKE_TRACE_OPTS=1 node dist/runner.js --brief "$MINI_BRIEF" --dry-run --effort low --worker-effort max 2>&1)
  if printf '%s' "$PPER_OUT" | grep -q "DRY-RUN worker opts: effort=max" \
     && printf '%s' "$PPER_OUT" | grep -q "DRY-RUN reviewer opts: effort=low"; then
    pass "effort precedence (--worker-effort max --effort low): per-role beats global; other role keeps global"
  else
    fail "effort precedence (per-role over global) trace missing or wrong: $PPER_OUT"
  fi
  # Worker-only taskBudget passthrough: reviewer stays (omitted) even when set.
  if printf '%s' "$TBOK_OUT" | grep -q "DRY-RUN worker opts: effort=medium taskBudget=20000" \
     && printf '%s' "$TBOK_OUT" | grep -q "DRY-RUN reviewer opts: effort=high taskBudget=(omitted)"; then
    pass "--task-budget 20000 reaches WORKER queries only (reviewer trace shows taskBudget omitted)"
  else
    fail "worker-only taskBudget passthrough trace missing or wrong: $TBOK_OUT"
  fi
else
  skip "config-lever CLI validation checks skipped — dist/runner.js not available"
fi

# ---------------------------------------------------------------------------
# (b2) Fixture-vs-schema required-key checks — ALWAYS run (cheap; this is the
#      degraded offline path when the runner itself could not execute).
#      Key lists mirror src/schemas.ts `required` arrays; a drift guard below
#      greps each key back against schemas.ts.
# ---------------------------------------------------------------------------
WORKER_REQUIRED="schema_version task_id status files_modified files_created tests_added tests_passed outputs_verified outputs_gap memory_candidates summary error"
REVIEW_REQUIRED="schema_version review_mode audit_focus trigger_paths_detected scope_expanded files_checked consistency_checks consistency_summary decision issues pattern_proposals knowledge_sources_used summary"

check_fixture_node() {
  # $1 = fixture path, $2 = space-separated required keys, $3 = expected schema_version
  node -e '
    const fs = require("fs");
    const [file, keysCsv, ver] = process.argv.slice(1);
    const obj = JSON.parse(fs.readFileSync(file, "utf8"));
    const problems = [];
    for (const k of keysCsv.split(" ")) if (!(k in obj)) problems.push("missing required key: " + k);
    if (obj.schema_version !== Number(ver)) problems.push("schema_version !== " + ver);
    if ("status" in obj && !["completed","failed","partial"].includes(obj.status)) problems.push("bad status enum");
    if ("decision" in obj && !["PASS","FAIL","NEEDS_HUMAN"].includes(obj.decision)) problems.push("bad decision enum");
    if ("outputs_gap" in obj && obj.outputs_gap !== "" && obj.status === "completed")
      problems.push("outputs_gap non-empty must map to status partial");
    if (problems.length) { console.error(problems.join("; ")); process.exit(1); }
  ' "$1" "$2" "$3"
}

check_fixture_jq() {
  # $1 = fixture path, $2 = space-separated required keys, $3 = expected schema_version
  FIX="$1"; VER="$3"; OK=0
  for key in $2; do
    jq -e --arg k "$key" 'has($k)' "$FIX" >/dev/null 2>&1 || OK=1
  done
  jq -e --argjson v "$VER" '.schema_version == $v' "$FIX" >/dev/null 2>&1 || OK=1
  return $OK
}

if [ "$HAVE_NODE" = 1 ]; then
  if check_fixture_node "$WORKER_FIXTURE" "$WORKER_REQUIRED" 2; then
    pass "worker fixture satisfies WORKER_RESULT v2 required keys + invariants (node)"
  else
    fail "worker fixture fails WORKER_RESULT v2 required-key check (node)"
  fi
  if check_fixture_node "$REVIEW_FIXTURE" "$REVIEW_REQUIRED" 3; then
    pass "review fixture satisfies CODE_REVIEW_RESULT v3 required keys (node)"
  else
    fail "review fixture fails CODE_REVIEW_RESULT v3 required-key check (node)"
  fi
elif [ "$HAVE_JQ" = 1 ]; then
  if check_fixture_jq "$WORKER_FIXTURE" "$WORKER_REQUIRED" 2; then
    pass "worker fixture satisfies WORKER_RESULT v2 required keys (jq)"
  else
    fail "worker fixture fails WORKER_RESULT v2 required-key check (jq)"
  fi
  if check_fixture_jq "$REVIEW_FIXTURE" "$REVIEW_REQUIRED" 3; then
    pass "review fixture satisfies CODE_REVIEW_RESULT v3 required keys (jq)"
  else
    fail "review fixture fails CODE_REVIEW_RESULT v3 required-key check (jq)"
  fi
else
  skip "fixture-vs-schema checks skipped — neither node nor jq available"
fi

# Drift guard: every required key asserted above must literally appear in
# src/schemas.ts (keeps the hardcoded lists honest against the schema source).
DRIFT=0
for key in $WORKER_REQUIRED $REVIEW_REQUIRED; do
  grep -q "\"$key\"" src/schemas.ts || { DRIFT=1; printf 'drift: key %s not found in src/schemas.ts\n' "$key"; }
done
if [ "$DRIFT" = 0 ]; then
  pass "required-key lists match src/schemas.ts (drift guard)"
else
  fail "required-key drift between self-test and src/schemas.ts"
fi

# ---------------------------------------------------------------------------
# (c) Fail-closed handling present in the runner source
# ---------------------------------------------------------------------------
if grep -q "error_max_structured_output_retries" src/runner.ts; then
  pass "runner.ts contains fail-closed error_max_structured_output_retries handling"
else
  fail "runner.ts missing fail-closed error_max_structured_output_retries handling"
fi

# ---------------------------------------------------------------------------
# (c2) Live-mode worktree/branch lifecycle invariants (source-level)
#      - worker output is committed before worktree removal (commitWorktree)
#      - stale per-subtask branch fails closed (no silent featureBranch fallback)
# ---------------------------------------------------------------------------
if grep -q "commitWorktree" src/runner.ts && grep -q '"status", "--porcelain"' src/runner.ts \
   && grep -q '"add", "-A"' src/runner.ts && grep -q '"commit", "-m"' src/runner.ts; then
  pass "runner.ts commits worker output in the worktree before removal (commit-if-dirty)"
else
  fail "runner.ts missing worktree commit-before-removal lifecycle"
fi
if grep -q "stale branch" src/runner.ts && grep -q '"worktree", "add", "-b"' src/runner.ts; then
  pass "runner.ts creates deterministic per-subtask branches and fails closed on stale branches"
else
  fail "runner.ts missing stale-branch fail-closed handling for worktree add -b"
fi

# ---------------------------------------------------------------------------
# (c3) Validator recursion into array items (only when compiled output exists)
# ---------------------------------------------------------------------------
if [ "$HAVE_NODE" = 1 ] && [ -f dist/schemas.js ]; then
  if node -e '
    const { validateAgainstSchema, WORKER_RESULT_SCHEMA } = require("./dist/schemas.js");
    const good = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (validateAgainstSchema(good, WORKER_RESULT_SCHEMA).length !== 0) {
      console.error("good fixture unexpectedly failed"); process.exit(1);
    }
    const bad = JSON.parse(JSON.stringify(good));
    bad.outputs_verified[0].status = "not-an-enum-value";
    delete bad.outputs_verified[1].path;
    const errs = validateAgainstSchema(bad, WORKER_RESULT_SCHEMA);
    if (errs.length < 2) {
      console.error("nested item violations not caught: " + JSON.stringify(errs)); process.exit(1);
    }
  ' "$WORKER_FIXTURE"; then
    pass "validateAgainstSchema recurses into array items (nested enum + required-key violations caught)"
  else
    fail "validateAgainstSchema does not catch nested array-item violations"
  fi
  # minItems + nested object-property (consistency_checks) violations
  if node -e '
    const { validateAgainstSchema, CODE_REVIEW_RESULT_SCHEMA } = require("./dist/schemas.js");
    const good = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (validateAgainstSchema(good, CODE_REVIEW_RESULT_SCHEMA).length !== 0) {
      console.error("good review fixture unexpectedly failed"); process.exit(1);
    }
    const minItemsBad = JSON.parse(JSON.stringify(good));
    minItemsBad.files_checked = []; // schema declares minItems: 1
    const e1 = validateAgainstSchema(minItemsBad, CODE_REVIEW_RESULT_SCHEMA);
    if (!e1.some((m) => m.includes("files_checked") && m.includes("at least"))) {
      console.error("minItems violation not caught: " + JSON.stringify(e1)); process.exit(1);
    }
    const nestedBad = JSON.parse(JSON.stringify(good));
    nestedBad.consistency_checks = { mirrored_prompts: "not-an-enum-value" }; // 4 required keys missing + bad enum
    const e2 = validateAgainstSchema(nestedBad, CODE_REVIEW_RESULT_SCHEMA);
    if (e2.length < 5 || !e2.some((m) => m.includes("consistency_checks."))) {
      console.error("nested consistency_checks violations not caught: " + JSON.stringify(e2)); process.exit(1);
    }
  ' "$REVIEW_FIXTURE"; then
    pass "validateAgainstSchema enforces minItems and recurses into object properties (consistency_checks)"
  else
    fail "validateAgainstSchema misses minItems or nested object-property violations"
  fi
else
  skip "validator recursion check skipped — dist/schemas.js not available"
fi

# ---------------------------------------------------------------------------
# (c4) Config-lever source invariants (static, always run)
#      - taskBudget is omit-when-unset: guarded by a strict `!== undefined`
#        check (never sent as null/0 when the flag is absent)
#      - ROLE_CONFIG table is the single source of per-role effort defaults
#        (worker medium, reviewer high — not hard-coded inline at call sites)
# ---------------------------------------------------------------------------
if grep -q "opts.taskBudget !== undefined" src/runner.ts; then
  pass "runner.ts guards taskBudget with !== undefined (omitted from Options when unset)"
else
  fail "runner.ts missing the taskBudget !== undefined omit-when-unset guard"
fi
if grep -q "ROLE_CONFIG" src/runner.ts \
   && grep -q 'worker: { effort: "medium" }' src/runner.ts \
   && grep -q 'reviewer: { effort: "high" }' src/runner.ts; then
  pass "runner.ts ROLE_CONFIG table present (worker: medium, reviewer: high)"
else
  fail "runner.ts missing ROLE_CONFIG table with worker medium + reviewer high defaults"
fi

# README contract + quarantine statement (cheap contract checks)
if grep -qF 'node dist/runner.js --brief <path> [--dry-run]' README.md; then
  pass "README.md carries the runner CLI contract line"
else
  fail "README.md missing the runner CLI contract line"
fi
if grep -qi "quarantine" README.md; then
  pass "README.md states the quarantine"
else
  fail "README.md missing quarantine statement"
fi

# ---------------------------------------------------------------------------
printf '\n%s\n' "self-test: $FAILURES failure(s)"
[ "$FAILURES" = 0 ] || exit 1
exit 0
