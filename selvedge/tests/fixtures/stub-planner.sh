#!/usr/bin/env bash
# stub-planner.sh — a SELVEDGE_PLANNER for test-plan.sh (not named test-*, so run.sh never runs it).
# No model: it writes a fixed-shape plan for the criteria in $SELVEDGE_CRITERIA.
#
# Used as SELVEDGE_PLANNER="bash <this file>". The mode comes from STUB_PLANNER_MODE:
#   valid    a valid plan (each criterion: goto <origin>/, read url, expect equals <origin>/)
#   invalid  a plan whose steps end in a click (missing_final_read_expect)
#   exit1    a valid plan, then exit 1 (the exit status alone must fail the planner)
#   noplan   writes nothing, exits 0
#   modal    calls "$SELVEDGE_BIN" snapshot <origin>/cart without and with a prefix (goto + click
#            "Open cart"), keeping both outputs, then plans the first criterion against the cart
#            dialog: open it, fill Quantity 2, read the Total, expect "12"
#   wide     calls "$SELVEDGE_BIN" snapshot $STUB_WIDE_URL (an origin only the working tree lists),
#            then the same with --run-dir $STUB_WIDE_RUN_DIR and with --base $STUB_WIDE_BASE,
#            keeping each stdout / stderr / exit code as wide*.{out,err,rc}; then plans as valid
# Every mode records the SELVEDGE_* variables it was given, and a copy of the input, under
# $STUB_PLANNER_LOG/ (when set), and reports tokens 111 in / 22 out to $SELVEDGE_PLANNER_USAGE
# unless STUB_PLANNER_NO_USAGE is set.
set -uo pipefail

mode="${STUB_PLANNER_MODE:-valid}"
log="${STUB_PLANNER_LOG:-}"

if [ -n "$log" ]; then
  mkdir -p "$log"
  node -e '
const E = process.env;
const keys = ["SELVEDGE_RUN_DIR", "SELVEDGE_CRITERIA", "SELVEDGE_PLAN_OUT", "SELVEDGE_BIN", "SELVEDGE_PLANNER_USAGE", "SELVEDGE_BASE"];
require("fs").writeFileSync(process.argv[1], JSON.stringify(Object.fromEntries(keys.map((k) => [k, E[k] === undefined ? null : E[k]]))) + "\n");' \
    "$log/env.json"
  cp "$SELVEDGE_CRITERIA" "$log/input.json"
fi

[ "$mode" = "noplan" ] && exit 0

origin="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).origins[0])' "$SELVEDGE_CRITERIA")"

if [ "$mode" = "modal" ]; then
  "$SELVEDGE_BIN" snapshot "$origin/cart" >"$log/bare.json" 2>"$log/bare.err"
  echo "$?" >"$log/bare.rc"
  printf '[{"type":"goto","url":"%s/cart"},{"type":"click","locator":{"role":"button","name":"Open cart"}}]\n' "$origin" >"$log/open-prefix.json"
  "$SELVEDGE_BIN" snapshot "$origin/cart" --steps "$log/open-prefix.json" >"$log/open.json" 2>"$log/open.err"
  echo "$?" >"$log/open.rc"
fi

if [ "$mode" = "wide" ]; then
  "$SELVEDGE_BIN" snapshot "$STUB_WIDE_URL" >"$log/wide.out" 2>"$log/wide.err"
  echo "$?" >"$log/wide.rc"
  "$SELVEDGE_BIN" snapshot "$STUB_WIDE_URL" --run-dir "$STUB_WIDE_RUN_DIR" >"$log/wide-rd.out" 2>"$log/wide-rd.err"
  echo "$?" >"$log/wide-rd.rc"
  "$SELVEDGE_BIN" snapshot "$STUB_WIDE_URL" --base "$STUB_WIDE_BASE" >"$log/wide-base.out" 2>"$log/wide-base.err"
  echo "$?" >"$log/wide-base.rc"
fi

STUB_MODE="$mode" node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(process.env.SELVEDGE_CRITERIA, "utf8"));
const origin = input.origins[0];
const mode = process.env.STUB_MODE;
const entry = (steps) => ({ interpretation: "The page reached shows the value the criterion names.", polarity: "positive", unverified_assumptions: [], steps });
const plan = { schema_version: 1, target: "web", criteria_sha256: input.criteria_sha256, origins: [origin], steps_by_criterion: {} };
input.criteria.forEach((c, i) => {
  let steps = [{ type: "goto", url: origin + "/" }, { type: "read", property: "url" }, { type: "expect", op: "equals", value: origin + "/" }];
  if (mode === "invalid") steps = [{ type: "goto", url: origin + "/cart" }, { type: "click", locator: { role: "button", name: "Open cart" } }];
  if (mode === "modal" && i === 0) {
    steps = [
      { type: "goto", url: origin + "/cart" },
      { type: "click", locator: { role: "button", name: "Open cart" } },
      { type: "fill", locator: { role: "spinbutton", name: "Quantity" }, value: "2" },
      { type: "read", property: "text", locator: { testid: "total" } },
      { type: "expect", op: "equals", value: "12" },
    ];
  }
  plan.steps_by_criterion[c.id] = entry(steps);
});
fs.writeFileSync(process.env.SELVEDGE_PLAN_OUT, JSON.stringify(plan, null, 2) + "\n");
if (!process.env.STUB_PLANNER_NO_USAGE) fs.writeFileSync(process.env.SELVEDGE_PLANNER_USAGE, JSON.stringify({ input_tokens: 111, output_tokens: 22 }) + "\n");
' || exit 1

[ "$mode" = "exit1" ] && exit 1
exit 0
