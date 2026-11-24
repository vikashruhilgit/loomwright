#!/usr/bin/env bash
# test-plan.sh — pins `selvedge plan` (selvedge/lib/plan.mjs), its run folders and freeze record
# (plan-runs.mjs), the planner invocation (plan-planner.mjs, prompts/planner.md), the modal
# end-to-end with real Chromium, and the docs this item owns (README, gate-scopes hand-off). Every
# arm turns red under its row of the brief's pin-mutation table.
#
# Two parts:
#   1. no-browser arms (always run): a stub SELVEDGE_PLANNER (tests/fixtures/stub-planner.sh) and a
#      PATH-stub `claude` (tests/fixtures/stub-claude.sh) stand in for the model: AC6, AC4b, AC11,
#      AC14, AC18, AC21.
#   2. AC8 against the fixture app (tests/fixtures/app-server.mjs) with Playwright from
#      tests/lib/playwright-cache.sh. Under CI an install failure is a hard FAIL
#      (playwright_install_failed); outside CI it is a SKIP and part 1 decides.
#
# Hermetic: a fresh temp HOME (PLAYWRIGHT_BROWSERS_PATH is exported by the helper BEFORE HOME moves),
# temp git repos as target projects, no model and no network beyond the helper's pinned install.
# The fixture app runs in one background process this script stops on exit. Needs node (>= 18),
# git and shasum; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
LIB="$PLUGIN_DIR/lib"
APP="$TESTS_DIR/fixtures/app-server.mjs"
export PLANNER_MD="$PLUGIN_DIR/prompts/planner.md"
export README="$PLUGIN_DIR/README.md"
export GATE_SCOPES="$PLUGIN_DIR/docs/evidence/gate-scopes.md"
export SELVEDGE_LIB="$LIB"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-plan: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git shasum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-plan.sh needs it)"; echo "test-plan: 0 passed, 1 failed"; exit 1; }
done

# shellcheck source=lib/playwright-cache.sh
. "$TESTS_DIR/lib/playwright-cache.sh"   # exports PLAYWRIGHT_BROWSERS_PATH while HOME is still real

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-plan.XXXXXX")" || exit 1
SRV_PID=""
cleanup() {
  if [ -n "$SRV_PID" ]; then
    kill "$SRV_PID" 2>/dev/null
    wait "$SRV_PID" 2>/dev/null
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
REAL_HOME="$HOME"
export HOME="$TMP/home"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$TMP/o"
# Every variable an arm asserts the unset path of starts unset; arms that set one pass it explicitly.
unset SELVEDGE_PLANNER SELVEDGE_PLANNER_MODEL SELVEDGE_PLANNER_TOKEN_BUDGET SELVEDGE_SNAPSHOT_BUDGET \
  SELVEDGE_PLAYWRIGHT_MODULE SELVEDGE_RUN_DIR SELVEDGE_CRITERIA SELVEDGE_PLAN_OUT SELVEDGE_BIN \
  SELVEDGE_PLANNER_USAGE SELVEDGE_BASE STUB_PLANNER_MODE STUB_PLANNER_LOG STUB_PLANNER_NO_USAGE STUB_CLAUDE_MODE NODE_PATH \
  STUB_WIDE_URL STUB_WIDE_RUN_DIR STUB_WIDE_BASE

# The fixture app (its origin is what every target repo below lists).
node "$APP" serve "$TMP/servers.json" >"$TMP/servers.log" 2>&1 &
SRV_PID=$!
i=0
while [ ! -s "$TMP/servers.json" ] && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
A="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).app.port))' "$TMP/servers.json" 2>/dev/null)"
[ -n "$A" ] && ok "setup: fixture app on localhost:$A" || { ko "setup: app-server.mjs did not start: $(cat "$TMP/servers.log")"; finish; }
AURL="http://localhost:$A"
export AURL

# newrepo <dir> — a temp git repo whose selvedge.json lists only the fixture app.
newrepo() { mkdir -p "$1" && git -C "$1" init -q && printf '{"schema_version":1,"origins":["%s"]}\n' "$AURL" > "$1/selvedge.json"; }
R="$TMP/repo"; newrepo "$R"
export R TMP

# Three criteria: c1 and c3 testable (a quoted literal each), c2 vague.
printf -- '- The cart Total shows "12" after the Quantity is set to 2\n- the page looks good\n- The home page heading reads "Plain page"\n' \
  | (cd "$R" && bash "$CLI" criteria from-text) > "$TMP/criteria.json" 2>/dev/null
ids="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(d.criteria.map(c=>c.id).join(" "))' "$TMP/criteria.json" 2>/dev/null)"
read -r c1 c2 c3 <<<"$ids"
[ -n "${c3:-}" ] && ok "setup: criteria from-text gives three criteria ($ids)" || { ko "setup: criteria.json: '$(cat "$TMP/criteria.json")'"; finish; }
export C1="$c1" C2="$c2" C3="$c3" CRITERIA="$TMP/criteria.json"
export BIN_REAL; BIN_REAL="$(node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' "$CLI")"

PLANNER="SELVEDGE_PLANNER=bash $TESTS_DIR/fixtures/stub-planner.sh"

# run <label> <cwd> [<env args>…] -- <plan args>…  runs `selvedge plan` with `env <env args>` (BSD
# env: every `-u NAME` before any NAME=value); sets OUT / ERR (files) and RC.
run() {
  local label="$1" cwd="$2"; shift 2
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  OUT="$TMP/o/$label.out"; ERR="$TMP/o/$label.err"
  (cd "$cwd" && env ${envs[@]+"${envs[@]}"} bash "$CLI" plan "$@" >"$OUT" 2>"$ERR"); RC=$?
  export OUT ERR RC
}

# check <label> <js expression> — evaluated over the last run(), with:
#   out err rc   the call's stdout, stderr and exit code
#   dir          the run folder: stdout's line on success, else the one stderr's
#                `selvedge plan: run folder <path>` line names ("" when none)
#   f(n) j(n)    the text / parsed JSON of <dir>/<n> (null when absent)
#   has(n)       <dir>/<n> exists
#   txt(p) jl(p) any file's text (or "") / its JSON lines parsed
#   hashes(d)    {file: sha256} of every file in folder d
check() {
  local label="$1" expr="$2" got
  got="$(node -e '
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const E = process.env;
const txt = (p) => { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } };
const out = txt(E.OUT), err = txt(E.ERR), rc = Number(E.RC);
const named = /^selvedge plan: run folder (\S+)/m.exec(err);
const dir = rc === 0 ? out.split("\n")[0] : (named ? named[1] : "");
const f = (n) => { try { return fs.readFileSync(path.join(dir, n), "utf8"); } catch { return null; } };
const j = (n) => { const t = f(n); return t === null ? null : JSON.parse(t); };
const has = (n) => fs.existsSync(path.join(dir, n));
const jl = (p) => txt(p).split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l));
const hashes = (d) => Object.fromEntries(fs.readdirSync(d).sort().map((n) => [n, crypto.createHash("sha256").update(fs.readFileSync(path.join(d, n))).digest("hex")]));
let v;
try { v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; }
if (v === true) process.stdout.write("true");
else process.stdout.write("false (" + String(v).slice(0, 80) + ") rc=" + E.RC + " out=" + JSON.stringify(out.slice(0, 400)) + " err=" + JSON.stringify(err.slice(-900)));
' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

echo "-- static: one lint, one freeze, no string-literal reason"
reasons="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
console.log(Object.keys(E.REASONS).join('|'));")"
hits="$(cd "$LIB" && grep -nE "['\"\`]($reasons)['\"\`]" plan.mjs plan-runs.mjs plan-planner.mjs)"
{ [ -n "$reasons" ] && [ -z "$hits" ]; } && ok "AC20 plan.mjs, plan-runs.mjs and plan-planner.mjs name no reason as a string literal (REASONS only)" || ko "string-literal reasons: $hits"
{ grep -qE "import \{[^}]*validatePlan[^}]*\} from './plan-validate.mjs'" "$LIB/plan.mjs" \
  && grep -qE "import \{[^}]*freezeRun[^}]*\} from './plan-runs.mjs'" "$LIB/plan.mjs" \
  && grep -qE "import \{[^}]*runPlanner[^}]*\} from './plan-planner.mjs'" "$LIB/plan.mjs" \
  && grep -qE "import \{[^}]*classifyTestability[^}]*\} from './criteria.mjs'" "$LIB/plan.mjs"; } \
  && ok "plan.mjs imports validatePlan, freezeRun, runPlanner and classifyTestability (never a second lint or pre-check)" \
  || ko "plan.mjs does not import the shared lint / freeze / planner / pre-check"
( ! grep -nE "function isMain" "$LIB/criteria.mjs" "$LIB/snapshot.mjs" "$LIB/plan.mjs" >/dev/null \
  && for m in criteria snapshot plan; do grep -qE "import \{[^}]*isMain[^}]*\} from './env-config.mjs'" "$LIB/$m.mjs" && grep -qF "if (isMain(import.meta.url))" "$LIB/$m.mjs" || exit 1; done ) \
  && ok "criteria.mjs, snapshot.mjs and plan.mjs guard main() with the one isMain from env-config.mjs (no copy)" \
  || ko "a command module copies isMain or runs main() unguarded"
out="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const P = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/plan.mjs').href);
console.log(typeof P.splitByTestability, process.exitCode === undefined ? 'no-exit-code' : process.exitCode);" 2>&1)"; prc=$?
{ [ "$prc" -eq 0 ] && [ "$out" = "function no-exit-code" ]; } && ok "importing plan.mjs for its helpers never runs the plan command" || ko "import plan.mjs: rc=$prc out='$out'"
run help "$R" -- help
check "selvedge plan help documents the bare form, --init, --validate, --freeze and SELVEDGE_PLANNER" \
  'rc === 0 && ["<criteria.json>", "--init", "--validate", "--freeze", "SELVEDGE_PLANNER"].every((s) => out.includes(s))'

echo "-- AC6 selvedge plan <criteria.json> with a stub planner"
run ac6 "$R" "$PLANNER" STUB_PLANNER_LOG="$TMP/log-ac6" -- "$CRITERIA"
check "AC6 exit 0; stdout is the new run folder .selvedge/runs/<UTC YYYYMMDDTHHMMSSZ>-<6 hex>/" \
  'rc === 0 && out.split("\n").filter(Boolean).length === 1 && path.dirname(dir) === fs.realpathSync(E.R) + "/.selvedge/runs" && /^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}$/.test(path.basename(dir))'
check "AC6 the folder holds criteria.json (a byte copy of the input), plan.json, plan.sha256 and freeze.json" \
  'f("criteria.json") === txt(E.CRITERIA) && ["plan.json", "plan.sha256", "freeze.json"].every(has)'
AC6_DIR="$(head -n 1 "$OUT")"
sha_line="$(cd "$AC6_DIR" && shasum -a 256 plan.json)"
[ -n "$sha_line" ] && [ "$(cat "$AC6_DIR/plan.sha256")" = "$sha_line" ] \
  && ok "AC6 plan.sha256 is exactly \`shasum -a 256 plan.json\` (<hex>  plan.json): the hash of the bytes written" \
  || ko "AC6 plan.sha256 is exactly \`shasum -a 256 plan.json\` — got '$(cat "$AC6_DIR/plan.sha256" 2>/dev/null)', shasum '$sha_line'"
check "AC6 plan.json is pretty-printed (2 spaces, trailing newline) with plan_revision 1 stamped" \
  'const t = f("plan.json"); t === JSON.stringify(JSON.parse(t), null, 2) + "\n" && JSON.parse(t).plan_revision === 1'
check "AC6 the stub-reported tokens (111 in / 22 out) are in freeze.json" \
  'const z = j("freeze.json"); JSON.stringify(z.planner_tokens) === JSON.stringify({ input_tokens: 111, output_tokens: 22 }) && z.plan_sha256 === f("plan.sha256").split(" ")[0] && z.run_id === path.basename(dir)'
check "AC6 runs.jsonl gains one freeze line {event, ts, run_id, criteria_sha256, plan_sha256, plan_revision, plan_time_actions, planner_tokens} carrying the tokens" \
  'const ls = jl(E.R + "/.selvedge/runs.jsonl"); const l = ls[ls.length - 1]; ls.length === 1 && Object.keys(l).join() === "event,ts,run_id,criteria_sha256,plan_sha256,plan_revision,plan_time_actions,planner_tokens" && l.event === "freeze" && l.run_id === path.basename(dir) && l.plan_sha256 === j("freeze.json").plan_sha256 && l.plan_revision === 1 && l.planner_tokens.input_tokens === 111 && l.planner_tokens.output_tokens === 22 && l.criteria_sha256 === j("plan.json").criteria_sha256'
check "AC6 the planner got SELVEDGE_RUN_DIR, SELVEDGE_CRITERIA (planner-input.json), SELVEDGE_PLAN_OUT (plan.json), SELVEDGE_BIN (this CLI) and SELVEDGE_PLANNER_USAGE" \
  'const v = JSON.parse(txt(E.TMP + "/log-ac6/env.json")); v.SELVEDGE_RUN_DIR === dir && v.SELVEDGE_CRITERIA === dir + "/planner-input.json" && v.SELVEDGE_PLAN_OUT === dir + "/plan.json" && v.SELVEDGE_BIN === E.BIN_REAL && v.SELVEDGE_PLANNER_USAGE === dir + "/planner-usage.json"'
check "the planner input lists the allowed origins and the criteria_sha256 the plan must carry" \
  'const p = JSON.parse(txt(E.TMP + "/log-ac6/input.json")); JSON.stringify(p.origins) === JSON.stringify([E.AURL]) && p.criteria_sha256 === j("plan.json").criteria_sha256 && p.snapshot_budget === 20 && p.token_budget === null && JSON.stringify(p.env_names) === "[]"'

check "the planner without --base got SELVEDGE_BASE \"\" (its snapshots read the working tree, as the plan does)" \
  'JSON.parse(txt(E.TMP + "/log-ac6/env.json")).SELVEDGE_BASE === ""'

echo "-- plan --base <ref>: the planner's snapshots read the same committed allowlist"
RW="$TMP/repo-wide"; newrepo "$RW"
git -C "$RW" add selvedge.json && git -C "$RW" -c user.name=t -c user.email=t@t commit -qm base
# The working tree widens the allowlist with an origin the committed HEAD:selvedge.json lacks.
printf '{"schema_version":1,"origins":["%s","http://localhost:4999"]}\n' "$AURL" > "$RW/selvedge.json"
export LOGW="$TMP/log-wide"
run wide "$RW" "$PLANNER" STUB_PLANNER_MODE=wide STUB_PLANNER_LOG="$LOGW" STUB_WIDE_URL=http://localhost:4999/ \
  STUB_WIDE_RUN_DIR="$TMP/elsewhere" STUB_WIDE_BASE=HEAD~0 -- "$CRITERIA" --base HEAD
check "plan --base HEAD: the plan freezes (exit 0) and the planner got SELVEDGE_BASE=HEAD" \
  'rc === 0 && has("plan.sha256") && JSON.parse(txt(E.LOGW + "/env.json")).SELVEDGE_BASE === "HEAD"'
check "plan --base HEAD: the planner's snapshot of the working-tree-only origin is BLOCKED host_not_allowed (exit 2)" \
  'txt(E.LOGW + "/wide.rc").trim() === "2" && txt(E.LOGW + "/wide.out").split("\n").includes("BLOCKED host_not_allowed")'
check "plan --base HEAD: a planner snapshot with --base naming another ref is a usage error (exit 2, conflicts with SELVEDGE_BASE)" \
  'txt(E.LOGW + "/wide-base.rc").trim() === "2" && txt(E.LOGW + "/wide-base.err").includes("conflicts with SELVEDGE_BASE")'
check "a planner snapshot with --run-dir naming another folder is a usage error and records nothing there" \
  'txt(E.LOGW + "/wide-rd.rc").trim() === "2" && txt(E.LOGW + "/wide-rd.err").includes("conflicts with SELVEDGE_RUN_DIR") && !fs.existsSync(E.TMP + "/elsewhere/snapshots.jsonl")'
check "only the one in-folder call was recorded in the run folder's snapshots.jsonl" \
  'jl(dir + "/snapshots.jsonl").length === 1 && jl(dir + "/snapshots.jsonl")[0].outcome === "blocked"'

echo "-- AC4b the vague criterion never reaches the planner; plan lists it itself"
check "AC4b planner-input.json carries the two testable criteria and not the vague one" \
  'const p = JSON.parse(txt(E.TMP + "/log-ac6/input.json")); JSON.stringify(p.criteria.map((c) => c.id)) === JSON.stringify([E.C1, E.C3]) && !txt(E.TMP + "/log-ac6/input.json").includes(E.C2) && !txt(E.TMP + "/log-ac6/input.json").includes("looks good")'
check "AC4b the frozen plan lists it under not_planned with criterion_not_testable and the pre-check rewrite" \
  'const np = j("plan.json").not_planned; np.length === 1 && np[0].id === E.C2 && np[0].reason === "criterion_not_testable" && np[0].rewrite.includes("looks good") && !(E.C2 in j("plan.json").steps_by_criterion)'

echo "-- AC6 the lint runs before hashing; planner failures"
runs_before="$(grep -c . "$R/.selvedge/runs.jsonl")"
export RUNS_BEFORE="$runs_before"
run ac6-invalid "$R" "$PLANNER" STUB_PLANNER_MODE=badsha -- "$CRITERIA"
check "AC6 a stub whose plan has a problem of the plan as a whole (criteria_sha_mismatch): exit 2 plan_invalid, no plan.sha256, no freeze.json, no runs.jsonl line" \
  'rc === 2 && err.includes("plan_invalid: (plan): criteria_sha_mismatch") && dir !== "" && has("plan.json") && !has("plan.sha256") && !has("freeze.json") && jl(E.R + "/.selvedge/runs.jsonl").length === Number(E.RUNS_BEFORE)'
run ac6-half "$R" "$PLANNER" STUB_PLANNER_MODE=half -- "$CRITERIA"
check "one criterion whose steps break the lint is set aside, the rest freeze: exit 0, the problem line on stderr, <c1> under not_planned criterion_plan_invalid with the problem as detail, <c3> still planned" \
  'const p = j("plan.json"); const np = p.not_planned.find((x) => x.id === E.C1); rc === 0 && has("plan.sha256") && err.includes("plan_invalid: " + E.C1 + ": missing_final_read_expect") && err.includes("set aside under not_planned (criterion_plan_invalid); the other criteria froze") && np && np.reason === "criterion_plan_invalid" && np.detail.startsWith("missing_final_read_expect") && !(E.C1 in p.steps_by_criterion) && (E.C3 in p.steps_by_criterion)'
out="$(node --input-type=module -e '
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const P = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/plan.mjs").href);
const V = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/plan-validate.mjs").href);
const C = await import(pathToFileURL(process.env.SELVEDGE_LIB + "/criteria.mjs").href);
const criteria = JSON.parse(readFileSync(process.env.CRITERIA, "utf8"));
const o = process.env.AURL;
const good = { interpretation: "x.", polarity: "positive", unverified_assumptions: [], steps: [{ type: "goto", url: o + "/" }, { type: "read", property: "url" }, { type: "expect", op: "equals", value: o + "/" }] };
const bad = { ...good, steps: [{ type: "goto", url: o + "/" }] };
const plan = { schema_version: 1, target: "web", criteria_sha256: C.criteriaSha256(criteria.criteria), origins: [o], steps_by_criterion: { [process.env.C1]: bad, [process.env.C2]: good, [process.env.C3]: good }, not_planned: [] };
const config = { origins: [o] };
const first = V.validatePlan(plan, { criteria, config });
const a = P.setAsideInvalid(plan, first, criteria.criteria);
const again = V.validatePlan(plan, { criteria, config });
const np2 = plan.not_planned.find((x) => x.id === process.env.C2);
console.log(first.some((p) => p.id === process.env.C2 && p.code === "vague_criterion_planned") && a && again.length === 0 && np2.reason === "criterion_not_testable" && np2.rewrite && plan.not_planned.find((x) => x.id === process.env.C1).reason === "criterion_plan_invalid" && (process.env.C3 in plan.steps_by_criterion) ? "yes" : JSON.stringify({ first, again, np: plan.not_planned }));
' 2>&1)"
[ "$out" = "yes" ] && ok "a vague criterion the planner planned anyway is set aside under criterion_not_testable with its rewrite (the reason the lint accepts), so the re-lint is clean and the rest freeze" || ko "set aside vague: $out"
run ac6-allbad "$R" "$PLANNER" STUB_PLANNER_MODE=invalid -- "$CRITERIA"
check "every criterion breaking the lint: all set aside, the plan still freezes (exit 0) with an empty steps_by_criterion" \
  'const p = j("plan.json"); rc === 0 && has("plan.sha256") && Object.keys(p.steps_by_criterion).length === 0 && [E.C1, E.C3].every((id) => p.not_planned.some((x) => x.id === id && x.reason === "criterion_plan_invalid"))'
export RUNS_BEFORE="$(grep -c . "$R/.selvedge/runs.jsonl")"
HALF_DIR="$(cat "$TMP/o/ac6-half.out")"
out="$(cd "$R" && bash "$CLI" plan --validate /dev/stdin --criteria "$HALF_DIR/criteria.json" < "$HALF_DIR/plan.json" 2>/dev/null)"; rc=$?
{ [ "$rc" -eq 0 ] && [ "$out" = "plan valid: /dev/stdin" ]; } && ok "plan --validate reads a plan from stdin (the planner's lint tool): plan valid: /dev/stdin" || ko "validate stdin: rc=$rc out='$out'"
err="$(cd "$R" && printf '%s' '{"schema_version":1}' | bash "$CLI" plan --validate /dev/stdin --criteria "$HALF_DIR/criteria.json" 2>&1 >/dev/null)"; rc=$?
{ [ "$rc" -eq 2 ] && grep -qF "plan_invalid: (plan): plan_schema_violation" <<<"$err"; } && ok "plan --validate on stdin lists the problems of a bad plan, exit 2" || ko "validate stdin bad: rc=$rc err='$err'"
err="$(cd "$R" && SELVEDGE_BASE= bash "$CLI" plan --validate /dev/stdin --criteria "$HALF_DIR/criteria.json" --base HEAD < "$HALF_DIR/plan.json" 2>&1 >/dev/null)"; rc=$?
{ [ "$rc" -eq 2 ] && grep -qF "conflicts with SELVEDGE_BASE" <<<"$err"; } && ok "under a planner (SELVEDGE_BASE set), plan --validate cannot read another allowlist (--base conflicts)" || ko "validate pinned base: rc=$rc err='$err'"
run ac6-exit1 "$R" "$PLANNER" STUB_PLANNER_MODE=exit1 -- "$CRITERIA"
check "AC6 a stub that writes a valid plan and exits 1: exit 2 planner_failed (exited 1), no plan.sha256" \
  'rc === 2 && err.includes("planner_failed") && err.includes("exited 1") && dir !== "" && has("plan.json") && !has("plan.sha256") && !has("freeze.json")'
run ac6-noplan "$R" "$PLANNER" STUB_PLANNER_MODE=noplan -- "$CRITERIA"
check "AC6 a stub that exits 0 and writes no plan: exit 2 planner_failed (wrote no plan), no plan.sha256" \
  'rc === 2 && err.includes("planner_failed") && err.includes("wrote no plan") && dir !== "" && !has("plan.json") && !has("plan.sha256")'
check "AC6 neither planner failure added a runs.jsonl line" 'jl(E.R + "/.selvedge/runs.jsonl").length === Number(E.RUNS_BEFORE)'
run notokens "$R" "$PLANNER" STUB_PLANNER_NO_USAGE=1 SELVEDGE_PLANNER_TOKEN_BUDGET=5000 -- "$CRITERIA"
check "a planner that reports no tokens: frozen with planner_tokens null; SELVEDGE_PLANNER_TOKEN_BUDGET is recorded in freeze.json" \
  'rc === 0 && j("freeze.json").planner_tokens === null && j("freeze.json").planner_token_budget === 5000'
run badbudget "$R" "$PLANNER" SELVEDGE_PLANNER_TOKEN_BUDGET=lots -- "$CRITERIA"
check "SELVEDGE_PLANNER_TOKEN_BUDGET=lots: exit 2 (a usage error) before any run folder is made" \
  'rc === 2 && err.includes("SELVEDGE_PLANNER_TOKEN_BUDGET") && dir === ""'

echo "-- AC11 plan_time_actions summed from snapshots.jsonl into freeze.json and runs.jsonl"
run ac11-init "$R" -- --init "$CRITERIA"
F="$(head -n 1 "$OUT")"; export F
check "--init prints a new run folder holding only criteria.json" \
  'rc === 0 && JSON.stringify(fs.readdirSync(dir)) === JSON.stringify(["criteria.json"]) && f("criteria.json") === txt(E.CRITERIA)'
printf '%s\n' '{"plan_time_actions":2,"outcome":"ok"}' '{"plan_time_actions":3,"outcome":"step_failed"}' '{"plan_time_actions":0,"outcome":"blocked"}' > "$F/snapshots.jsonl"
node -e 'const fs = require("fs"); const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); delete p.plan_revision; fs.writeFileSync(process.argv[2], JSON.stringify(p, null, 2) + "\n");' "$AC6_DIR/plan.json" "$F/plan.json"
run ac11 "$R" -- --freeze "$F"
check "AC11 --freeze: freeze.json plan_time_actions = 5 (2 + 3 + 0 over snapshots.jsonl)" \
  'rc === 0 && dir === E.F && j("freeze.json").plan_time_actions === 5'
check "AC11 the runs.jsonl freeze line carries plan_time_actions 5 too" \
  'const ls = jl(E.R + "/.selvedge/runs.jsonl"); const l = ls[ls.length - 1]; l.run_id === path.basename(E.F) && l.plan_time_actions === 5'

echo "-- AC14 frozen folders, revisions"
RA="$TMP/repo-auth"; mkdir -p "$RA" && git -C "$RA" init -q && printf '{"schema_version":1,"origins":["%s"],"auth":{"env":["APP_EMAIL","APP_PASS"]}}\n' "$AURL" > "$RA/selvedge.json"
run authnames "$RA" "$PLANNER" STUB_PLANNER_LOG="$TMP/log-auth" APP_EMAIL=a@b.test APP_PASS=s3cret-value -- "$CRITERIA"
check "with auth.env in selvedge.json the planner input lists those names as env_names, never their values" \
  'const t = txt(E.TMP + "/log-auth/input.json"); rc === 0 && JSON.stringify(JSON.parse(t).env_names) === "[\"APP_EMAIL\",\"APP_PASS\"]" && !t.includes("s3cret-value") && !t.includes("a@b.test")'
R14="$TMP/repo14"; newrepo "$R14"
mkdir -p "$R14/.selvedge"
SHA="$(node -e 'const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); process.stdout.write(p.criteria_sha256)' "$AC6_DIR/plan.json")"
# Seeded: a freeze line for OTHER criteria, and an item-04 run line for these criteria.
printf '%s\n' "{\"event\":\"freeze\",\"run_id\":\"seed-a\",\"criteria_sha256\":\"$(printf '0%.0s' $(seq 1 64))\",\"plan_revision\":1}" \
  "{\"event\":\"run\",\"run_id\":\"seed-b\",\"criteria_sha256\":\"$SHA\"}" > "$R14/.selvedge/runs.jsonl"
export R14
run ac14-a "$R14" "$PLANNER" -- "$CRITERIA"
FA="$(head -n 1 "$OUT")"; export FA
check "AC14 the first folder for these criteria is plan_revision 1 (only freeze lines with the same criteria_sha256 count)" \
  'rc === 0 && j("plan.json").plan_revision === 1 && j("freeze.json").plan_revision === 1'
node -e 'const fs = require("fs"), path = require("path"), crypto = require("crypto"); const d = process.argv[1]; fs.writeFileSync(process.argv[2], JSON.stringify(Object.fromEntries(fs.readdirSync(d).sort().map((n) => [n, crypto.createHash("sha256").update(fs.readFileSync(path.join(d, n))).digest("hex")]))));' "$FA" "$TMP/fa-hashes.json"
export FA_HASHES="$TMP/fa-hashes.json"
lines_a="$(grep -c . "$R14/.selvedge/runs.jsonl")"; export LINES_A="$lines_a"
run ac14-again "$R14" -- --freeze "$FA"
check "AC14 --freeze on the frozen folder: exit 2 already_frozen; no file in the folder changes; runs.jsonl unchanged" \
  'rc === 2 && err.includes("already_frozen") && JSON.stringify(hashes(E.FA)) === txt(E.FA_HASHES) && jl(E.R14 + "/.selvedge/runs.jsonl").length === Number(E.LINES_A)'
run ac14-init "$R14" -- --init "$CRITERIA"
FB="$(head -n 1 "$OUT")"; export FB
node -e 'const fs = require("fs"); const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); delete p.plan_revision; fs.writeFileSync(process.argv[2], JSON.stringify(p, null, 2) + "\n");' "$FA/plan.json" "$FB/plan.json"
run ac14-b "$R14" -- --freeze "$FB"
check "AC14 a new --init folder for the same criteria_sha256, frozen: plan_revision 2 in plan.json, freeze.json and its runs.jsonl line" \
  'const ls = jl(E.R14 + "/.selvedge/runs.jsonl"); rc === 0 && dir === E.FB && E.FB !== E.FA && j("plan.json").plan_revision === 2 && j("freeze.json").plan_revision === 2 && ls[ls.length - 1].plan_revision === 2 && ls[ls.length - 1].run_id === path.basename(E.FB)'
check "AC14 the first folder is byte-for-byte untouched by the second folder's freeze" \
  'JSON.stringify(hashes(E.FA)) === txt(E.FA_HASHES)'
run ac14-b-again "$R14" -- --freeze "$FB"
check "AC14 the second folder, frozen, is already_frozen too" 'rc === 2 && err.includes("already_frozen")'

echo "-- AC18 the default planner: claude -p (a PATH stub)"
STUBBIN="$TMP/stubbin"; mkdir -p "$STUBBIN"
printf '#!/bin/sh\nexec bash "%s" "$@"\n' "$TESTS_DIR/fixtures/stub-claude.sh" > "$STUBBIN/claude"
chmod +x "$STUBBIN/claude"
export STUB_CLAUDE_ARGV="$TMP/claude-argv.json"
R18="$TMP/repo18"; newrepo "$R18"
run ac18 "$R18" -u SELVEDGE_PLANNER PATH="$STUBBIN:$PATH" -- "$CRITERIA"
check "AC18 SELVEDGE_PLANNER unset: claude ran and the plan from its result text is frozen (exit 0)" \
  'rc === 0 && has("plan.sha256") && j("plan.json").steps_by_criterion[E.C1].unverified_assumptions[0].text === "the home page is the page meant"'
check "AC18 claude saw -p, --output-format json, --model sonnet, and the prompt text of prompts/planner.md followed by the input" \
  'const a = JSON.parse(txt(E.STUB_CLAUDE_ARGV)); const md = txt(E.PLANNER_MD).replace(/\s+$/, ""); a[0] === "-p" && a[1].startsWith(md) && a[1].includes("## Input (planner-input.json)") && a[1].includes(E.C1) && !a[1].includes(E.C2) && a[a.indexOf("--output-format") + 1] === "json" && a[a.indexOf("--model") + 1] === "sonnet"'
check "AC18 --allowedTools is exactly Bash(<SELVEDGE_BIN> snapshot:*) and Bash(<SELVEDGE_BIN> plan --validate:*), its two values, last" \
  'const a = JSON.parse(txt(E.STUB_CLAUDE_ARGV)); const k = a.indexOf("--allowedTools"); k === a.length - 3 && a[k + 1] === "Bash(" + E.BIN_REAL + " snapshot:*)" && a[k + 2] === "Bash(" + E.BIN_REAL + " plan --validate:*)" && a.filter((x) => /^--allowed-?tools$/i.test(x)).length === 1'
check "AC18 the result usage is recorded: input 1000 + 200 cache-read + 50 cache-creation = 1250, output 300" \
  'JSON.stringify(j("freeze.json").planner_tokens) === JSON.stringify({ input_tokens: 1250, output_tokens: 300 })'
run ac18-model "$R18" -u SELVEDGE_PLANNER PATH="$STUBBIN:$PATH" SELVEDGE_PLANNER_MODEL=opus -- "$CRITERIA"
check "SELVEDGE_PLANNER_MODEL=opus reaches claude as --model opus" \
  'const a = JSON.parse(txt(E.STUB_CLAUDE_ARGV)); rc === 0 && a[a.indexOf("--model") + 1] === "opus"'
run ac18-error "$R18" -u SELVEDGE_PLANNER PATH="$STUBBIN:$PATH" STUB_CLAUDE_MODE=error -- "$CRITERIA"
check "claude returning an error result: exit 2 planner_failed, no plan.sha256" \
  'rc === 2 && err.includes("planner_failed") && err.includes("error result") && !has("plan.sha256")'
run ac18-exit1 "$R18" -u SELVEDGE_PLANNER PATH="$STUBBIN:$PATH" STUB_CLAUDE_MODE=exit1 -- "$CRITERIA"
check "claude exiting 1: exit 2 planner_failed" 'rc === 2 && err.includes("planner_failed") && err.includes("exited 1") && !has("plan.sha256")'
noclaude="$TMP/noclaude-bin"; mkdir -p "$noclaude"
for c in node bash git dirname basename readlink grep head sed cat; do
  p="$(command -v "$c")" && ln -s "$p" "$noclaude/$c"
done
run ac18-none "$R18" -u SELVEDGE_PLANNER PATH="$noclaude" -- "$CRITERIA"
check "AC18 no claude on PATH: exit 2 planner_failed naming claude (not found on PATH), no plan.sha256" \
  'rc === 2 && err.includes("planner_failed") && err.includes("`claude` was not found on PATH") && dir !== "" && !has("plan.sha256")'

echo "-- AC19 / AC21 docs"
check "AC21 gate-scopes.md has a ### Hand-off to item 04 subsection naming the modal run PASS and verdict.json plan_time_actions with no reset hook, read from freeze.json" \
  'const md = txt(E.GATE_SCOPES); const m = /^### Hand-off to item 04\n([\s\S]*?)(?=^#{1,3} |(?![\s\S]))/m.exec(md); m !== null && ["PASS", "verdict.json", "plan_time_actions", "reset", "freeze.json", "runs.jsonl"].every((s) => m[1].includes(s))'
check "AC21 the README plan section says plan_time_actions is recorded in freeze.json and runs.jsonl" \
  'const md = txt(E.README); const m = /^## `plan`[^\n]*\n([\s\S]*?)(?=^## )/m.exec(md); m !== null && /plan_time_actions[\s\S]{0,200}freeze\.json[\s\S]{0,200}runs\.jsonl/.test(m[1])'
check "AC19 the README documents criteria, snapshot, plan --init/--validate/--freeze, the run folder and every SELVEDGE_* variable" \
  'const md = txt(E.README); ["## `criteria` commands", "## `snapshot`", "## `plan`", "--init", "--validate", "--freeze", "planner-input.json", "plan.sha256", "freeze.json", "runs.jsonl", "snapshots.jsonl", "SELVEDGE_PLANNER", "SELVEDGE_PLANNER_MODEL", "SELVEDGE_PLANNER_TOKEN_BUDGET", "SELVEDGE_SNAPSHOT_BUDGET", "SELVEDGE_PLAYWRIGHT_MODULE", "SELVEDGE_RUN_DIR", "prompts/planner.md"].every((s) => md.includes(s))'

echo "-- AC8 the modal: snapshot with and without a prefix, and the frozen locators resolve (real Chromium)"
HOME="$REAL_HOME" pw_require_or_skip; pwrc=$?
if [ "$pwrc" -eq 1 ]; then
  ko "playwright_install_failed under CI: no browser arm can run"
  finish
fi
if [ "$pwrc" -eq 2 ]; then
  echo "  (browser arms skipped outside CI; the no-browser arms above decide)"
  finish
fi
R8="$TMP/repo8"; newrepo "$R8"
printf -- '- Opening the cart and setting Quantity to 2 shows the Total "12"\n' | (cd "$R8" && bash "$CLI" criteria from-text) > "$TMP/modal-criteria.json" 2>/dev/null
export LOG8="$TMP/log-modal"
run ac8 "$R8" "$PLANNER" STUB_PLANNER_MODE=modal STUB_PLANNER_LOG="$LOG8" "SELVEDGE_PLAYWRIGHT_MODULE=$PW_MODULE" -- "$TMP/modal-criteria.json"
check "AC8 selvedge plan with the modal stub planner freezes a plan (exit 0)" 'rc === 0 && has("plan.sha256")'
check "AC8 the stub's snapshot WITHOUT --steps: exit 0, the tree has Open cart but none of the dialog's controls" \
  'const t = JSON.parse(txt(E.LOG8 + "/bare.json")).aria_snapshot; txt(E.LOG8 + "/bare.rc").trim() === "0" && t.includes("button \"Open cart\"") && !t.includes("Quantity") && !t.includes("dialog")'
check "AC8 the stub's snapshot WITH --steps (goto + click Open cart): exit 0, the tree holds the dialog, its Quantity spinbutton and Total" \
  'const t = JSON.parse(txt(E.LOG8 + "/open.json")).aria_snapshot; txt(E.LOG8 + "/open.rc").trim() === "0" && t.includes("dialog \"Cart\"") && t.includes("spinbutton \"Quantity\"") && t.includes("Total")'
check "AC11 the modal folder: freeze.json plan_time_actions = 1 (the prefix click; the bare call had none) from its two snapshots.jsonl lines" \
  'jl(dir + "/snapshots.jsonl").length === 2 && j("freeze.json").plan_time_actions === 1'
M8="$(head -n 1 "$OUT")"
node -e '
const fs = require("fs");
const plan = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const steps = Object.values(plan.steps_by_criterion)[0].steps;
const read = steps.find((s) => s.type === "read");
const prefix = steps.filter((s) => s.type !== "read" && s.type !== "expect").concat([{ type: "wait_for", locator: read.locator, state: "visible" }]);
fs.writeFileSync(process.argv[2], JSON.stringify(prefix) + "\n");' "$M8/plan.json" "$TMP/resolve-prefix.json"
OUT="$TMP/o/resolve.out"; ERR="$TMP/o/resolve.err"
(cd "$R8" && env "SELVEDGE_PLAYWRIGHT_MODULE=$PW_MODULE" bash "$CLI" snapshot "$AURL/cart" --steps "$TMP/resolve-prefix.json" --run-dir "$TMP/resolve-run" >"$OUT" 2>"$ERR"); RC=$?
export OUT ERR RC
check "AC8 the frozen plan's locators resolve: its steps minus read/expect plus wait_for visible on the read locator, as a snapshot prefix, exit 0 (strict mode: one element each); the Total reads 12" \
  'const r = JSON.parse(out); rc === 0 && r.failed_step === null && r.error === null && r.steps_run === 4 && r.aria_snapshot.includes("12")'

finish
