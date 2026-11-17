#!/usr/bin/env bash
# stub-claude.sh — a PATH stub for `claude`, for test-plan.sh and test-auth-run.sh (not named
# test-*, so run.sh never runs it). Each links it as <dir>/claude and puts <dir> first on PATH.
# No model, no network.
#
# It writes its argv as a JSON array to $STUB_CLAUDE_ARGV, then prints what
# `claude -p --output-format json` prints: one result object whose `result` text holds a plan in a
# ```json block (a valid plan for the criteria in $SELVEDGE_CRITERIA, built the way
# stub-planner.sh's `valid` mode builds it) and whose `usage` reports 1000 input + 200 cache-read
# + 50 cache-creation tokens and 300 output tokens.
#   STUB_CLAUDE_MODE=error   prints an error result (is_error true) and exits 0
#   STUB_CLAUDE_MODE=exit1   prints nothing and exits 1
#   STUB_CLAUDE_SNAPSHOT_OUT=<file>  first looks at the page the way a planner does: runs
#                            `$SELVEDGE_BIN snapshot <first origin>/` (the run folder and config source
#                            plan pins) and writes its stdout and stderr to <file>, what the model
#                            would read back as the tool's result
set -uo pipefail

node -e '
const fs = require("fs");
const E = process.env;
fs.writeFileSync(E.STUB_CLAUDE_ARGV, JSON.stringify(process.argv.slice(1)) + "\n");
const mode = E.STUB_CLAUDE_MODE || "ok";
if (mode === "exit1") process.exit(1);
if (mode === "error") {
  process.stdout.write(JSON.stringify({ type: "result", subtype: "error_during_execution", is_error: true, result: "" }) + "\n");
  process.exit(0);
}
const input = JSON.parse(fs.readFileSync(E.SELVEDGE_CRITERIA, "utf8"));
const origin = input.origins[0];
if (E.STUB_CLAUDE_SNAPSHOT_OUT) {
  const r = require("child_process").spawnSync("bash", [E.SELVEDGE_BIN, "snapshot", origin + "/"], { encoding: "utf8" });
  fs.writeFileSync(E.STUB_CLAUDE_SNAPSHOT_OUT, String(r.stdout) + String(r.stderr));
}
const plan = { schema_version: 1, target: "web", criteria_sha256: input.criteria_sha256, origins: [origin], steps_by_criterion: {} };
for (const c of input.criteria) {
  plan.steps_by_criterion[c.id] = {
    interpretation: "The page reached shows the value the criterion names.",
    polarity: "positive",
    unverified_assumptions: [{ text: "the home page is the page meant", material: false }],
    steps: [{ type: "goto", url: origin + "/" }, { type: "read", property: "url" }, { type: "expect", op: "equals", value: origin + "/" }],
  };
}
const result = "I looked at the page. Here is the plan:\n\n```json\n" + JSON.stringify(plan, null, 2) + "\n```\n";
process.stdout.write(JSON.stringify({
  type: "result", subtype: "success", is_error: false, result,
  usage: { input_tokens: 1000, cache_read_input_tokens: 200, cache_creation_input_tokens: 50, output_tokens: 300 },
}) + "\n");
' -- "$@"   # `--`: without it node would read the planner's `-p` as its own --print
