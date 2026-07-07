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
else
  skip "failure-path dry-runs skipped — dist/runner.js not available"
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
