#!/usr/bin/env bash
# test-run.sh — pins `selvedge run` (selvedge/lib/runner/run.mjs), the one step executor
# (runner/steps.mjs), one criterion in a fresh guarded context (runner/execute.mjs: stable wait,
# stuck screen, screenshot) and the evidence writer (runner/evidence.mjs: appendEvidence). Every arm
# turns red under its row of the brief's pin-mutation table.
#
# Two parts:
#   1. no-browser arms (always run): SELVEDGE_PLAYWRIGHT_MODULE is tests/fixtures/stub-playwright.mjs,
#      whose chromium.launch appends `launch` to $STUB_PW_LOG and returns a fake browser, so "no
#      browser launched" is read from that marker file: AC9, AC10, AC17, AC18, AC19, AC20.
#   2. real-Chromium arms against the fixture app (tests/fixtures/app-server.mjs) with Playwright from
#      tests/lib/playwright-cache.sh: AC11–AC17, AC21. Under CI an install failure is a hard FAIL
#      (playwright_install_failed); outside CI it is a SKIP and part 1 decides.
#
# Plans are hand-written (the generator in tests/lib/run-helpers.sh) and frozen with `selvedge plan --init` + `--freeze`
# (no planner), except AC21's, which tests/fixtures/stub-planner.sh mode `modal` writes. Every run
# gets a recording SELVEDGE_PLANNER and a PATH-stub `claude`; AC17 asserts neither was ever called.
# Hermetic: a fresh temp HOME (PLAYWRIGHT_BROWSERS_PATH is exported by the helper BEFORE HOME moves),
# temp git repos as target projects, no model and no network beyond the helper's pinned install.
# One fixture app process for the whole file, stopped on exit. Needs node (>= 18) and git.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
LIB="$PLUGIN_DIR/lib"
APP="$TESTS_DIR/fixtures/app-server.mjs"
export STUB_PW="$TESTS_DIR/fixtures/stub-playwright.mjs"
export SELVEDGE_LIB="$LIB"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-run: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-run.sh needs it)"; echo "test-run: 0 passed, 1 failed"; exit 1; }
done

# shellcheck source=lib/playwright-cache.sh
. "$TESTS_DIR/lib/playwright-cache.sh"   # exports PLAYWRIGHT_BROWSERS_PATH while HOME is still real

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-run.XXXXXX")" || exit 1
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
unset SELVEDGE_PLANNER SELVEDGE_PLAYWRIGHT_MODULE SELVEDGE_ENTRY SELVEDGE_RUN_BUDGET_MS \
  SELVEDGE_PLANNER_TOKEN_BUDGET SELVEDGE_STEP_TIMEOUT_MS SELVEDGE_RUN_DIR SELVEDGE_BASE NODE_PATH \
  PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK STUB_PW_GOTO_MS STUB_PW_TEXT STUB_PLANNER_MODE \
  STUB_PLANNER_LOG SHOP_USER SHOP_BLANK SHOP_UNSET

# shellcheck source=lib/run-helpers.sh
. "$TESTS_DIR/lib/run-helpers.sh"   # the fixture app, newrepo, folder, stub_spec, the planner shims
rh_start_app
rh_setup
R="$TMP/repo"; newrepo "$R"
export STUB_PW_LOG="$TMP/launches.log"

# run <label> <run-dir> [<env args>…] — `selvedge run <run-dir>` in $R (or $RUN_CWD) with the
# recording planner shims and `env <env args>`; sets OUT / ERR (files), RC and DIR; empties the
# launch log first.
run() {
  local label="$1" dir="$2"; shift 2
  OUT="$TMP/o/$label.out"; ERR="$TMP/o/$label.err"
  : > "$STUB_PW_LOG"
  (cd "${RUN_CWD:-$R}" && env "SELVEDGE_PLANNER=sh $TMP/planner-shim.sh" "PATH=$TMP/stubbin:$PATH" "$@" bash "$CLI" run "$dir" >"$OUT" 2>"$ERR"); RC=$?
  DIR="$dir"
  export OUT ERR RC DIR
}

# check <label> <js expression> — evaluated over the last run(), with:
#   out err rc    the call's stdout, stderr and exit code
#   ev            the run folder's evidence.jsonl lines, parsed ([] when absent)
#   vj ids vc(i)  verdict.json (null when absent), plan.json's criterion ids, criterion i's entry
#   has(n) f(n)   <DIR>/<n> exists / its text (null when absent)
#   txt(p) jl(p)  any file's text (or "") / its JSON lines
#   launches()    `launch` lines in the stub's marker file for this run
#   hashes(d)     {file: sha256} of every file under folder d
check() {
  local label="$1" expr="$2" got
  got="$(node -e '
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const E = process.env;
const txt = (p) => { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } };
const jl = (p) => txt(p).split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l));
const out = txt(E.OUT), err = txt(E.ERR), rc = Number(E.RC);
const f = (n) => { try { return fs.readFileSync(path.join(E.DIR, n), "utf8"); } catch { return null; } };
const has = (n) => fs.existsSync(path.join(E.DIR, n));
const ev = jl(path.join(E.DIR, "evidence.jsonl"));
const vj = f("verdict.json") === null ? null : JSON.parse(f("verdict.json"));
const ids = Object.keys(JSON.parse(f("plan.json") || "{\"steps_by_criterion\":{}}").steps_by_criterion);
const vc = (i) => vj.criteria[ids[i]];
const launches = () => txt(E.STUB_PW_LOG).split("\n").filter((l) => l === "launch").length;
const walk = (d) => fs.readdirSync(d).sort().flatMap((n) => { const p = path.join(d, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; });
const hashes = (d) => Object.fromEntries(walk(d).map((p) => [p, crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex")]));
let v;
try { v = eval(process.argv[1]); } catch (e) { v = "error: " + e.message; }
if (v === true) process.stdout.write("true");
else process.stdout.write("false (" + String(v).slice(0, 80) + ") rc=" + E.RC + " out=" + JSON.stringify(out.slice(0, 500)) + " err=" + JSON.stringify(err.slice(-900)) + " verdict=" + JSON.stringify(vj && vj.criteria).slice(0, 600));
' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

STUB="SELVEDGE_PLAYWRIGHT_MODULE=$STUB_PW"

echo "-- static: one executor, no Playwright import, no string-literal reason, guarded main()"
reasons="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
console.log(Object.keys(E.REASONS).join('|'));")"
hits="$(cd "$LIB/runner" && grep -nE "['\"\`]($reasons)['\"\`]" run.mjs steps.mjs execute.mjs evidence.mjs)"
{ [ -n "$reasons" ] && [ -z "$hits" ]; } && ok "AC1 runner/run.mjs, steps.mjs, execute.mjs and evidence.mjs name no reason as a string literal (REASONS only)" || ko "string-literal reasons: $hits"
n="$(grep -cE "(from|import\() *['\"]playwright" "$LIB/runner/run.mjs" "$LIB/runner/steps.mjs" "$LIB/runner/execute.mjs" | awk -F: '{s += $2} END {print s + 0}')"
[ "$n" = "0" ] && ok "the runner modules never import playwright by name (resolved at run time)" || ko "runner modules import playwright ($n hits)"
{ grep -qE "import \{[^}]*runStep[^}]*\} from './runner/steps.mjs'" "$LIB/snapshot.mjs" \
  && ! grep -qE "^(async )?function (locate|navigate|runStep)\b" "$LIB/snapshot.mjs" \
  && grep -qE "import \{[^}]*runStep[^}]*\} from './steps.mjs'" "$LIB/runner/execute.mjs" \
  && grep -qE "import \{[^}]*openGuardedContext[^}]*\} from './route-guard.mjs'" "$LIB/runner/execute.mjs" \
  && grep -qE "import \{[^}]*deriveVerdict[^}]*\} from '../verdict.mjs'" "$LIB/runner/run.mjs"; } \
  && ok "one executor: snapshot.mjs and execute.mjs import runStep from runner/steps.mjs (snapshot.mjs defines none); execute.mjs opens the one guard; run.mjs derives the verdict through deriveVerdict" \
  || ko "a second executor, guard or verdict path"
{ grep -qE "import \{[^}]*isMain[^}]*\} from '../env-config.mjs'" "$LIB/runner/run.mjs" && grep -qF "if (isMain(import.meta.url))" "$LIB/runner/run.mjs"; } \
  && ok "run.mjs guards main() with the one isMain from env-config.mjs" || ko "run.mjs main() is unguarded or isMain is copied"

echo "-- CLI surface and usage"
out="$(bash "$CLI" 2>&1)"
grep -qE '^ +run <run-dir> ' <<<"$out" && ok "the CLI help lists run" || ko "help: '$out'"
DIR="$TMP/none"; run help help
check "selvedge run help exits 0 and documents SELVEDGE_ENTRY, SELVEDGE_RUN_BUDGET_MS and the exit codes" 'rc === 0 && ["SELVEDGE_ENTRY", "SELVEDGE_RUN_BUDGET_MS", "SELVEDGE_STEP_TIMEOUT_MS", "already_run", "plan_modified"].every((s) => out.includes(s))'
run nodir "$TMP/no-such-dir" "$STUB"
check "a <run-dir> that is not a directory: exit 2 (usage); nothing launched" 'rc === 2 && err.includes("is not a directory") && launches() === 0'

echo "-- AC9 plan_modified / not_frozen before anything launches"
F9="$(folder ac9 "$R" "$(stub_spec 9)")"
[ -n "$F9" ] && ok "setup: a frozen folder" || ko "setup: folder ac9: $(cat "$TMP/o/freeze-ac9.err" 2>/dev/null)"
node -e 'const fs = require("fs"); const f = process.argv[1]; const b = fs.readFileSync(f); const i = b.indexOf("stub"); b[i] = "S".charCodeAt(0); fs.writeFileSync(f, b);' "$F9/plan.json"
run ac9 "$F9" "$STUB"
check "AC9 one byte of plan.json edited: exit 2 plan_modified on stderr, no evidence.jsonl, no verdict.json, no browser launched" \
  'rc === 2 && err.includes("plan_modified") && !has("evidence.jsonl") && !has("verdict.json") && launches() === 0'
F9b="$(cd "$R" && bash "$CLI" plan --init "$TMP/crit-ac9.json" 2>/dev/null)"
cp "$F9/plan.json" "$F9b/plan.json"
run ac9-nofreeze "$F9b" "$STUB"
check "AC9 a folder with no plan.sha256: exit 2 not_frozen, no evidence.jsonl, no browser launched" \
  'rc === 2 && err.includes("not_frozen") && !has("evidence.jsonl") && launches() === 0'
F9c="$(folder ac9-both "$R" "$(stub_spec 40)")"
node -e 'const fs = require("fs"), c = require("crypto"); const d = process.argv[1]; const f = d + "/plan.json"; const b = fs.readFileSync(f); const i = b.indexOf("stub"); b[i] = "S".charCodeAt(0); fs.writeFileSync(f, b); fs.writeFileSync(d + "/plan.sha256", c.createHash("sha256").update(b).digest("hex") + "  plan.json\n");' "$F9c"
run ac9-both "$F9c" "$STUB"
check "AC9 a first run: plan.json and plan.sha256 edited together still exit 2 plan_modified (the folder's freeze line in runs.jsonl disagrees), no evidence.jsonl, no browser launched" \
  'rc === 2 && err.includes("plan_modified") && err.includes("freeze line") && !has("evidence.jsonl") && !has("run.claim") && launches() === 0'

echo "-- AC10, AC18, AC17 a run, a second run of the same folder, the runs.jsonl line (stub browser)"
R18="$TMP/repo18"; newrepo "$R18"; export R18
F18="$(folder ac18 "$R18" "$(stub_spec 1 2)")"
RUN_CWD="$R18" run ac18 "$F18" "$STUB"
check "a stub-browser run of two criteria: exit 0, both PASS, one launch per criterion (a fresh context each)" \
  'rc === 0 && vc(0).verdict === "PASS" && vc(1).verdict === "PASS" && launches() === 2 && out.includes("verdict PASS")'
check "AC18 runs.jsonl gains one event:\"run\" line for the run, with every field; entry session by default" \
  'const ls = jl(E.R18 + "/.selvedge/runs.jsonl").filter((l) => l.event === "run"); const l = ls[0]; const keys = ["event", "ts", "run_id", "entry", "counts", "verdict", "planner_tokens", "duration_ms", "plan_sha256", "criteria_sha256", "plan_revision", "replay_of"]; ls.length === 1 && JSON.stringify(Object.keys(l)) === JSON.stringify(keys) && l.run_id === path.basename(E.DIR) && l.entry === "session" && l.verdict === "PASS" && l.counts.PASS === 2 && l.counts.FAIL === 0 && l.plan_revision === 1 && l.replay_of === null && l.plan_sha256 === vj.plan_sha256 && l.criteria_sha256 === JSON.parse(f("plan.json")).criteria_sha256 && Number.isInteger(l.duration_ms)'
node -e 'const fs = require("fs"), path = require("path"), crypto = require("crypto"); const walk = (d) => fs.readdirSync(d).sort().flatMap((n) => { const p = path.join(d, n); return fs.statSync(p).isDirectory() ? walk(p) : [p]; }); fs.writeFileSync(process.argv[2], JSON.stringify(Object.fromEntries(walk(process.argv[1]).map((p) => [p, crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex")]))));' "$F18" "$TMP/f18-hashes.json"
export F18_HASHES="$TMP/f18-hashes.json"
RUN_CWD="$R18" run ac10 "$F18" "$STUB"
check "AC10 the same folder again: exit 2 already_run, no browser launched, no file in the folder changes, no run line added" \
  'rc === 2 && err.includes("already_run") && launches() === 0 && JSON.stringify(hashes(E.DIR)) === txt(E.F18_HASHES) && jl(E.R18 + "/.selvedge/runs.jsonl").filter((l) => l.event === "run").length === 1'
(cd "$R18" && bash "$CLI" verdict "$F18" >/dev/null 2>&1)
check "AC18 re-running selvedge verdict on the folder adds no runs.jsonl line" 'jl(E.R18 + "/.selvedge/runs.jsonl").filter((l) => l.event === "run").length === 1'
F18b="$(folder ac18b "$R18" "$(stub_spec 3)")"
RUN_CWD="$R18" run ac18-ci "$F18b" "$STUB" SELVEDGE_ENTRY=ci
check "AC18 a second run with SELVEDGE_ENTRY=ci: exactly one more run line, entry ci" \
  'const ls = jl(E.R18 + "/.selvedge/runs.jsonl").filter((l) => l.event === "run"); rc === 0 && ls.length === 2 && ls[1].entry === "ci" && ls[1].run_id === path.basename(E.DIR)'
F18c="$(folder ac18c "$R18" "$(stub_spec 4)")"
RUN_CWD="$R18" run ac18-bad "$F18c" "$STUB" SELVEDGE_ENTRY=nightly
check "AC18 SELVEDGE_ENTRY=nightly: a usage error (exit 2) naming SELVEDGE_ENTRY; no evidence, no launch, no run line" \
  'rc === 2 && err.includes("SELVEDGE_ENTRY") && !has("evidence.jsonl") && launches() === 0 && jl(E.R18 + "/.selvedge/runs.jsonl").filter((l) => l.event === "run").length === 2'

echo "-- AC19 budgets (stub browser)"
F19="$(folder ac19 "$R" "$(stub_spec 5 6 7)")"
run ac19 "$F19" "$STUB" STUB_PW_GOTO_MS=700 SELVEDGE_RUN_BUDGET_MS=300
check "AC19 SELVEDGE_RUN_BUDGET_MS spent by the first criterion: it PASSes, the other two are BLOCKED budget_exceeded and get no browser (one launch)" \
  'rc === 2 && vc(0).verdict === "PASS" && vc(1).verdict === "BLOCKED" && vc(1).reason === "budget_exceeded" && vc(2).reason === "budget_exceeded" && launches() === 1 && ev.filter((l) => l.kind === "step" && l.criterion !== ids[0]).length === 0'
F19b="$(folder ac19b "$R" "$(SPEC_EXTRA=',"usage":{"input_tokens":111,"output_tokens":22}' stub_spec 8 9)")"
run ac19b "$F19b" "$STUB" SELVEDGE_PLANNER_TOKEN_BUDGET=100
check "AC19 freeze.json planner tokens 133 > SELVEDGE_PLANNER_TOKEN_BUDGET=100: every criterion BLOCKED budget_exceeded, no browser launched, exit 2" \
  'rc === 2 && JSON.parse(f("freeze.json")).planner_tokens.input_tokens === 111 && ids.every((id) => vj.criteria[id].verdict === "BLOCKED" && vj.criteria[id].reason === "budget_exceeded") && launches() === 0'

echo "-- AC20 hooks and data_state (stub browser)"
F20="$(folder ac20 "$R" "$(SPEC_EXTRA=',"plan_time_actions":2' stub_spec 10)")"
run ac20 "$F20" "$STUB"
check "AC20 no seed/reset hook: data_state unmanaged, hooks_run [], plan_time_actions 2 = freeze.json's" \
  'rc === 0 && vj.data_state === "unmanaged" && JSON.stringify(vj.hooks_run) === "[]" && JSON.parse(f("freeze.json")).plan_time_actions === 2 && vj.plan_time_actions === 2'
RH="$TMP/repo-hook"; newrepo "$RH"
printf '{"schema_version":1,"origins":["%s"],"hooks":{"reset":"echo reset >> \\"$STUB_PW_LOG\\""}}\n' "$AURL" > "$RH/selvedge.json"
(cd "$RH" && node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const A = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-approvals.mjs').href);
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const { config, root } = E.loadConfig();
A.writeApproval({ root, identity: A.repoIdentity(root), sha256: A.hooksSha256(config.hooks) });") \
  && ok "setup: the reset hook is approved for its repo" || ko "setup: approval not written"
F20b="$(folder ac20b "$RH" "$(stub_spec 11)")"
RUN_CWD="$RH" run ac20-hook "$F20b" "$STUB"
check "AC20 an approved reset hook runs before the first browser launch; data_state managed, hooks_run [\"reset\"], no plan_time_actions" \
  'rc === 0 && txt(E.STUB_PW_LOG) === "reset\nlaunch\n" && vj.data_state === "managed" && JSON.stringify(vj.hooks_run) === "[\"reset\"]" && !("plan_time_actions" in vj)'
RUN_CWD="$RH" run ac10-hook "$F20b" "$STUB"
check "AC10 a folder that already ran, in a repo with an approved reset hook: already_run is refused before the hook runs or a browser launches" \
  'rc === 2 && err.includes("already_run") && txt(E.STUB_PW_LOG) === "" && !has("run.claim")'
F20h="$(folder ac20h "$RH" "$(stub_spec 41)")"
: > "$F20h/run.claim"
RUN_CWD="$RH" run claim-held "$F20h" "$STUB"
check "a folder another run has claimed (run.claim): exit 2 already_run before the hook runs or a browser launches; the other run's claim is left alone" \
  'rc === 2 && err.includes("already_run") && err.includes("run.claim") && txt(E.STUB_PW_LOG) === "" && !has("evidence.jsonl") && has("run.claim")'
RS="$TMP/repo-slow-hook"; newrepo "$RS"
printf '{"schema_version":1,"origins":["%s"],"hooks":{"reset":"sleep 1; echo reset >> \\"$STUB_PW_LOG\\""}}\n' "$AURL" > "$RS/selvedge.json"
(cd "$RS" && node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const A = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-approvals.mjs').href);
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const { config, root } = E.loadConfig();
A.writeApproval({ root, identity: A.repoIdentity(root), sha256: A.hooksSha256(config.hooks) });")
FR="$(folder race "$RS" "$(stub_spec 42)")"
: > "$STUB_PW_LOG"
race_pids=""
for n in 1 2; do
  (cd "$RS" && env "SELVEDGE_PLANNER=sh $TMP/planner-shim.sh" "PATH=$TMP/stubbin:$PATH" "$STUB" bash "$CLI" run "$FR" >"$TMP/o/race$n.out" 2>"$TMP/o/race$n.err"; echo $? > "$TMP/o/race$n.rc") &
  race_pids="$race_pids $!"
done
# shellcheck disable=SC2086  # the two pids, split on purpose; a bare `wait` would also wait on the fixture app
wait $race_pids
OUT="$TMP/o/race1.out"; ERR="$TMP/o/race2.err"; RC=0; DIR="$FR"; export OUT ERR RC DIR TMP
check "two runs started together on one folder with a slow approved reset hook: the hook runs once, one run exits 0 and the other 2 already_run, no run.claim left" \
  'const rcs = [1, 2].map((n) => Number(txt(E.TMP + "/o/race" + n + ".rc").trim())).sort(); const errs = txt(E.TMP + "/o/race1.err") + txt(E.TMP + "/o/race2.err"); txt(E.STUB_PW_LOG).split("\n").filter((l) => l === "reset").length === 1 && JSON.stringify(rcs) === "[0,2]" && errs.includes("already_run") && has("evidence.jsonl") && !has("run.claim")'
RU="$TMP/repo-unapproved"; newrepo "$RU"
printf '{"schema_version":1,"origins":["%s"],"hooks":{"reset":"echo reset >> \\"$STUB_PW_LOG\\""}}\n' "$AURL" > "$RU/selvedge.json"
F20c="$(folder ac20c "$RU" "$(stub_spec 12 13)")"
RUN_CWD="$RU" run ac20-unapproved "$F20c" "$STUB"
check "AC20 a reset hook not approved: every criterion BLOCKED env_hooks_unapproved, the hook did not run, no browser launched" \
  'rc === 2 && ids.every((id) => vj.criteria[id].reason === "env_hooks_unapproved") && txt(E.STUB_PW_LOG) === "" && JSON.stringify(vj.hooks_run) === "[]"'

echo "-- changed_from compares the previous read of the same locator and property"
cf="$(node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const S = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/runner/steps.mjs').href);
const count = { type: 'read', property: 'text', locator: { testid: 'count' } };
const other = { type: 'read', property: 'text', locator: { testid: 'other' } };
const no = { op: 'changed_from', value: false }, yes = { op: 'changed_from', value: true };
const r = (st, v) => S.readEntry(st, v);
const out = [
  S.expectMatches(no, [r(count, '0'), r(other, '1'), r(count, '1')]) === false,
  S.expectMatches(yes, [r(count, '0'), r(other, '1'), r(count, '1')]) === true,
  S.expectMatches(no, [r(count, '0'), r(other, '7'), r(count, '0')]) === true,
  S.expectMatches(no, [r(other, '1'), r(count, '1')]) === false,
  S.expectMatches(no, [r({ type: 'read', property: 'text', locator: { role: 'button', name: 'A' } }, '1'), r({ type: 'read', property: 'text', locator: { name: 'A', role: 'button' } }, '1')]) === true,
  S.expectMatches(no, [r({ type: 'read', property: 'value', locator: { testid: 'count' } }, '1'), r(count, '1')]) === false,
];
process.stdout.write(out.join(','));")"
[ "$cf" = "true,true,true,true,true,true" ] \
  && ok "expectMatches changed_from: baseline 0, an unrelated read 1, counter 1 is changed (false does not match); no earlier read of that locator+property never matches; key order of a locator does not matter" \
  || ko "changed_from over reads: $cf"
FCF="$(folder changed-from "$R" '{"criteria":[{"text":"Opening page two leaves the url unchanged","polarity":"negative","steps":[{"type":"goto","url":"$O/"},{"type":"read","property":"url"},{"type":"read","property":"text","locator":{"testid":"x"}},{"type":"goto","url":"$O/two"},{"type":"read","property":"url"},{"type":"expect","op":"changed_from","value":false}]}]}')"
[ -n "$FCF" ] && ok "setup: a frozen changed_from folder" || ko "setup: folder changed-from: $(cat "$TMP/o/freeze-changed-from.err" 2>/dev/null)"
run changed-from "$FCF" "$STUB" "STUB_PW_TEXT=$AURL/two"
check "a run whose url changes (/ → /two) with an unrelated read equal to the new url in between: changed_from false is mismatched, FAIL (never PASS)" \
  'const x = ev.find((l) => l.type === "expect"); rc === 1 && vc(0).verdict === "FAIL" && x.outcome === "mismatched" && vc(0).read_value === E.AURL + "/two"'

echo "-- per-criterion and pre-launch refusals (stub browser)"
RB="$TMP/repo-branches"; newrepo "$RB"
printf '{"schema_version":1,"origins":["%s","http://localhost:1"]}\n' "$AURL" > "$RB/selvedge.json"
FB="$(folder branches "$RB" '{"origins":["$O","http://localhost:1"],"criteria":[
{"text":"Port one reads \"stub\"","steps":[{"type":"goto","url":"http://localhost:1/"},{"type":"read","property":"text","locator":{"testid":"x"}},{"type":"expect","op":"equals","value":"stub"}]},
{"text":"An unset user reads \"stub\"","steps":[{"type":"goto","url":"$O/echo"},{"type":"fill","locator":{"label":"User"},"value":"{{SHOP_UNSET}}"},{"type":"read","property":"text","locator":{"testid":"x"}},{"type":"expect","op":"equals","value":"stub"}]},
{"text":"The audit log records \"sent\"","not_planned":{"reason":"side_effect_not_observable","detail":"no page shows the audit log"}},
{"text":"Criterion B4 reads \"stub\"","steps":[{"type":"goto","url":"$O/"},{"type":"read","property":"text","locator":{"testid":"x"}},{"type":"expect","op":"equals","value":"stub"}]}]}')"
printf '{"schema_version":1,"origins":["%s"]}\n' "$AURL" > "$RB/selvedge.json"
RUN_CWD="$RB" run branches "$FB" "$STUB"
check "a goto origin selvedge.json no longer allows: that criterion BLOCKED host_not_allowed, before any browser" \
  'rc === 2 && vc(0).verdict === "BLOCKED" && vc(0).reason === "host_not_allowed" && !ev.some((l) => l.kind === "step" && l.criterion === ids[0])'
check "an unset {{NAME}}: that criterion BLOCKED placeholder_unset, the name on stderr; the other criteria still run (one launch)" \
  'vc(1).reason === "placeholder_unset" && err.includes("SHOP_UNSET") && vc(2).verdict === "PASS" && launches() === 1'
check "a not_planned criterion: a criterion_end not_planned line with the plan reason; NOT_VERIFIABLE side_effect_not_observable" \
  'const np = JSON.parse(f("plan.json")).not_planned[0].id; const e = ev.find((l) => l.kind === "criterion_end" && l.criterion === np); e.outcome === "not_planned" && e.reason === "side_effect_not_observable" && vj.criteria[np].verdict === "NOT_VERIFIABLE" && vj.criteria[np].reason === "side_effect_not_observable"'
FP="$(folder nopw "$R" "$(stub_spec 14)")"
run nopw "$FP" "SELVEDGE_PLAYWRIGHT_MODULE=$TMP/no-such-playwright.mjs"
check "Playwright that does not resolve: every criterion BLOCKED playwright_unavailable; run_start playwright_version null" \
  'rc === 2 && vc(0).reason === "playwright_unavailable" && ev[0].playwright_version === null'
RF="$TMP/repo-failing-hook"; newrepo "$RF"
printf '{"schema_version":1,"origins":["%s"],"hooks":{"reset":"exit 7"}}\n' "$AURL" > "$RF/selvedge.json"
(cd "$RF" && node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const A = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-approvals.mjs').href);
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const { config, root } = E.loadConfig();
A.writeApproval({ root, identity: A.repoIdentity(root), sha256: A.hooksSha256(config.hooks) });")
FF="$(folder failhook "$RF" "$(stub_spec 15)")"
RUN_CWD="$RF" run failhook "$FF" "$STUB"
check "an approved reset hook that fails (exit 7): exit 1, nothing written to the run folder, no browser launched" \
  'rc === 1 && err.includes("hook reset failed") && !has("evidence.jsonl") && !has("verdict.json") && !has("run.claim") && launches() === 0'
run badbudget "$FF" "$STUB" SELVEDGE_RUN_BUDGET_MS=soon
check "SELVEDGE_RUN_BUDGET_MS=soon: a usage error (exit 2) naming it; nothing written" 'rc === 2 && err.includes("SELVEDGE_RUN_BUDGET_MS") && !has("evidence.jsonl") && launches() === 0'
run badtimeout "$FF" "$STUB" SELVEDGE_STEP_TIMEOUT_MS=0
check "SELVEDGE_STEP_TIMEOUT_MS=0: a usage error (exit 2) naming it; nothing written" 'rc === 2 && err.includes("SELVEDGE_STEP_TIMEOUT_MS") && !has("evidence.jsonl")'
rm "$RF/selvedge.json"
RUN_CWD="$RF" run noconfig "$FF" "$STUB"
check "no selvedge.json: exit 2 config_absent; nothing written, no browser launched" 'rc === 2 && err.includes("config_absent") && !has("evidence.jsonl") && launches() === 0'

echo "-- real Chromium: AC11–AC16, AC21"
HOME="$REAL_HOME" pw_require_or_skip; pwrc=$?
if [ "$pwrc" -eq 1 ]; then
  ko "playwright_install_failed under CI: no browser arm can run"
  finish
fi
if [ "$pwrc" -eq 0 ]; then
  PW="SELVEDGE_PLAYWRIGHT_MODULE=$PW_MODULE"

  F11="$(folder ac11 "$R" '{"criteria":[{"text":"Loading the price shows \"42\"","steps":[{"type":"goto","url":"$O/slow"},{"type":"click","locator":{"role":"button","name":"Load price"}},{"type":"read","property":"text","locator":{"testid":"price"}},{"type":"expect","op":"equals","value":"42"}]}]}')"
  run ac11 "$F11" "$PW"
  check "AC11 a value the server sends 1.5 s after the click: PASS after the stable wait and one re-read; the expect line records stable_wait: true" \
    'const reads = ev.filter((l) => l.type === "read"); const x = ev.find((l) => l.type === "expect"); rc === 0 && vc(0).verdict === "PASS" && x.stable_wait === true && x.outcome === "matched" && reads.length === 2 && reads[0].value === "pending" && reads[1].value === "42" && reads[1].stable_wait === true'

  FNS="$(folder neg-slow "$R" '{"criteria":[{"text":"Loading the price leaves it \"pending\"","polarity":"negative","steps":[{"type":"goto","url":"$O/slow"},{"type":"read","property":"text","locator":{"testid":"price"}},{"type":"click","locator":{"role":"button","name":"Load price"}},{"type":"read","property":"text","locator":{"testid":"price"}},{"type":"expect","op":"changed_from","value":false}]}]}')"
  run neg-slow "$FNS" "$PW"
  check "a negative check whose first read still holds (\"pending\") while a 1.5 s request is in flight: the stable wait runs anyway, the re-read sees \"42\", changed_from false is mismatched, FAIL (never an early PASS)" \
    'const x = ev.find((l) => l.type === "expect"); const reads = ev.filter((l) => l.type === "read"); rc === 1 && vc(0).verdict === "FAIL" && x.stable_wait === true && x.outcome === "mismatched" && reads[reads.length - 1].value === "42" && reads[reads.length - 1].stable_wait === true'

  FAL="$(folder at-load "$R" '{"criteria":[{"text":"Right after /slow-auto loads, the price reads \"pending\"","steps":[{"type":"goto","url":"$O/slow-auto"},{"type":"read","property":"text","locator":{"testid":"price"},"at_load":true},{"type":"expect","op":"equals","value":"pending"}]},{"text":"The /slow-auto price reads \"pending\" once the page settles","steps":[{"type":"goto","url":"$O/slow-auto"},{"type":"read","property":"text","locator":{"testid":"price"}},{"type":"expect","op":"equals","value":"pending"}]}]}')"
  run at-load "$FAL" "$PW"
  check "a read at_load on a page whose value a 1.5 s fetch replaces: PASS on the read as taken (one read, the expect has stable_wait false); the same read without at_load waits, re-reads \"42\" and FAILs" \
    'const of = (k) => ev.filter((l) => l.criterion === ids[k]); const r0 = of(0).filter((l) => l.type === "read"); const x0 = of(0).find((l) => l.type === "expect"); const r1 = of(1).filter((l) => l.type === "read"); vc(0).verdict === "PASS" && r0.length === 1 && r0[0].value === "pending" && x0.stable_wait === false && vc(1).verdict === "FAIL" && r1[r1.length - 1].value === "42"'

  F12="$(folder ac12 "$R" '{"criteria":[{"text":"The greeting reads \"Hello, alice\"","steps":[{"type":"goto","url":"$O/echo"},{"type":"read","property":"text","locator":{"testid":"echo"}},{"type":"expect","op":"equals","value":"Hello, alice"}]},{"text":"Adding one leaves the count \"0\" unchanged","polarity":"negative","steps":[{"type":"goto","url":"$O/controls"},{"type":"read","property":"text","locator":{"testid":"count"}},{"type":"click","locator":{"role":"button","name":"Add one"}},{"type":"read","property":"text","locator":{"testid":"count"}},{"type":"expect","op":"changed_from","value":false}]}]}')"
  run ac12 "$F12" "$PW"
  check "AC12 a genuinely wrong value: exit 1, FAIL with read_value \"Hello, nobody\" and expected {equals, \"Hello, alice\"}, matched false (after the stable wait)" \
    'const c = vc(0); rc === 1 && c.verdict === "FAIL" && c.read_value === "Hello, nobody" && c.expected.op === "equals" && c.expected.value === "Hello, alice" && c.matched === false && ev.find((l) => l.criterion === ids[0] && l.type === "expect").stable_wait === true'
  check "AC15 a negative criterion whose counter goes 0 → 1 (changed_from false): FAIL" \
    'const c = vc(1); const reads = ev.filter((l) => l.criterion === ids[1] && l.type === "read"); c.verdict === "FAIL" && reads[0].value === "0" && reads[reads.length - 1].value === "1"'

  F13="$(folder ac13 "$R" '{"criteria":[
{"text":"Checkout shows the Total \"6\"","steps":[{"type":"goto","url":"$O/cart"},{"type":"click","locator":{"role":"button","name":"Open cart"}},{"type":"click","locator":{"role":"button","name":"Checkout"}},{"type":"read","property":"text","locator":{"testid":"total"}},{"type":"expect","op":"equals","value":"6"}]},
{"text":"The hidden action shows the count \"0\"","steps":[{"type":"goto","url":"$O/controls"},{"type":"wait_for","locator":{"testid":"count"},"state":"visible"},{"type":"click","locator":{"role":"button","name":"Hidden action"}},{"type":"read","property":"text","locator":{"testid":"count"}},{"type":"expect","op":"equals","value":"0"}]},
{"text":"The covered action shows the count \"covered clicked\"","steps":[{"type":"goto","url":"$O/controls"},{"type":"wait_for","locator":{"testid":"count"},"state":"visible"},{"type":"click","locator":{"role":"button","name":"Covered action"}},{"type":"read","property":"text","locator":{"testid":"count"}},{"type":"expect","op":"equals","value":"covered clicked"}]},
{"text":"The empty value reads \"x\"","steps":[{"type":"goto","url":"$O/controls"},{"type":"read","property":"text","locator":{"testid":"empty"}},{"type":"expect","op":"equals","value":"x"}]},
{"text":"Three clicks on Do nothing show the count \"0\"","steps":[{"type":"goto","url":"$O/controls"},{"type":"click","locator":{"role":"button","name":"Do nothing"}},{"type":"click","locator":{"role":"button","name":"Do nothing"}},{"type":"click","locator":{"role":"button","name":"Do nothing"}},{"type":"read","property":"text","locator":{"testid":"count"}},{"type":"expect","op":"equals","value":"0"}]},
{"text":"The home page url is \"/\"","steps":[{"type":"goto","url":"$O/"},{"type":"read","property":"url"},{"type":"expect","op":"equals","value":"$O/"}]}]}')"
  run ac13 "$F13" "$PW" SELVEDGE_STEP_TIMEOUT_MS=400
  check "AC13 step 2 clicks a locator that matches nothing: BLOCKED step_failed, failed_step 2 (not FAIL); its failed step line carries the error" \
    'const c = vc(0); const s = ev.find((l) => l.criterion === ids[0] && l.step === 2); rc === 2 && c.verdict === "BLOCKED" && c.reason === "step_failed" && c.failed_step === 2 && s.outcome === "failed" && typeof s.error === "string" && !ev.some((l) => l.criterion === ids[0] && l.step > 2)'
  check "AC13 a click on a hidden element: BLOCKED step_failed, failed_step 2" 'vc(1).verdict === "BLOCKED" && vc(1).reason === "step_failed" && vc(1).failed_step === 2'
  check "AC13 a click on a covered element: BLOCKED step_failed, failed_step 2" 'vc(2).verdict === "BLOCKED" && vc(2).reason === "step_failed" && vc(2).failed_step === 2'
  check "AC13 a read locator that resolves to an empty text: NOT_VERIFIABLE no_value_read (its read line value is \"\")" \
    'const r = ev.filter((l) => l.criterion === ids[3] && l.type === "read"); vc(3).verdict === "NOT_VERIFIABLE" && vc(3).reason === "no_value_read" && r[r.length - 1].value === ""'
  check "AC14 three clicks on the dead button: BLOCKED stuck_screen (STUCK_SCREEN_ACTIONS = 3), failed_step 3" \
    'vc(4).verdict === "BLOCKED" && vc(4).reason === "stuck_screen" && vc(4).failed_step === 3'
  check "AC13 the criteria after the failed ones still run: the last one PASSes" 'vc(5).verdict === "PASS"'

  F16="$(folder ac16 "$R" '{"criteria":[
{"text":"After a cookie is set, filling User shows \"Reversed: pohs-ecila\"","steps":[{"type":"goto","url":"$O/cookie?set=1"},{"type":"goto","url":"$O/echo"},{"type":"fill","locator":{"label":"User"},"value":"{{SHOP_USER}}"},{"type":"read","property":"text","locator":{"testid":"echo-reversed"}},{"type":"expect","op":"equals","value":"Reversed: pohs-ecila"}]},
{"text":"A fresh visit shows \"cookie: none\"","steps":[{"type":"goto","url":"$O/cookie"},{"type":"read","property":"text","locator":{"text":"cookie:"}},{"type":"expect","op":"equals","value":"cookie: none"}]},
{"text":"A blank user shows \"Hello, nobody\"","steps":[{"type":"goto","url":"$O/echo"},{"type":"fill","locator":{"label":"User"},"value":"{{SHOP_BLANK}}"},{"type":"read","property":"text","locator":{"testid":"echo"}},{"type":"expect","op":"equals","value":"Hello, nobody"}]}]}')"
  run ac16 "$F16" "$PW" SHOP_USER=alice-shop SHOP_BLANK=
  check "AC16 evidence: run_start first, one step line per executed step (criterion, step, type, locator, outcome, value, duration_ms) plus one stable-wait re-read per expect, one criterion_end per criterion, run_end last" \
    'const kinds = ev.map((l) => l.kind); const steps = ev.filter((l) => l.kind === "step"); const reread = (l) => l.type === "read" && l.stable_wait === true; rc === 0 && kinds[0] === "run_start" && kinds[kinds.length - 1] === "run_end" && ev.filter((l) => l.kind === "criterion_end").length === 3 && steps.filter((l) => !reread(l)).length === 12 && steps.filter(reread).length === 3 && steps.every((l) => ["criterion", "step", "type", "locator", "outcome", "value", "duration_ms"].every((k) => k in l))'
  check "AC16 the fill of {{SHOP_USER}} is written as {{SHOP_USER}} and the value appears in no evidence line; the page got the value (the reversed text PASSes)" \
    'const fl = ev.find((l) => l.criterion === ids[0] && l.type === "fill"); fl.value === "{{SHOP_USER}}" && !f("evidence.jsonl").includes("alice-shop") && !f("verdict.json").includes("alice-shop") && vc(0).verdict === "PASS"'
  check "AC16 a {{NAME}} whose value is empty is still written as the plan wrote it ({{SHOP_BLANK}})" \
    'ev.find((l) => l.criterion === ids[2] && l.type === "fill").value === "{{SHOP_BLANK}}" && vc(2).verdict === "PASS"'
  check "AC16 one end-state screenshot per criterion: screenshots/<criterion-id>.png, a PNG, named by its criterion_end line" \
    'ids.every((id) => { const e = ev.find((l) => l.kind === "criterion_end" && l.criterion === id); const p = path.join(E.DIR, "screenshots", id + ".png"); return e.screenshot === "screenshots/" + id + ".png" && fs.existsSync(p) && fs.readFileSync(p).subarray(1, 4).toString() === "PNG"; })'
  check "AC16 each criterion runs in a fresh context: the cookie criterion 1 set is absent in criterion 2" \
    'vc(1).verdict === "PASS" && vc(1).read_value === "cookie: none"'

  R21="$TMP/repo21"; newrepo "$R21"
  printf -- '- Opening the cart and setting Quantity to 2 shows the Total "12"\n' | (cd "$R21" && bash "$CLI" criteria from-text) > "$TMP/modal-criteria.json" 2>/dev/null
  F21="$(cd "$R21" && env "SELVEDGE_PLANNER=bash $TESTS_DIR/fixtures/stub-planner.sh" STUB_PLANNER_MODE=modal STUB_PLANNER_LOG="$TMP/log-modal" "$PW" bash "$CLI" plan "$TMP/modal-criteria.json" 2>"$TMP/o/plan21.err")"
  RUN_CWD="$R21" run ac21 "$F21" "$PW"
  check "AC21 the modal plan frozen by stub-planner.sh mode modal (open the cart, fill Quantity 2, read total, expect \"12\"): PASS" \
    'rc === 0 && vc(0).verdict === "PASS" && vc(0).read_value === "12"'
else
  echo "  (browser arms skipped outside CI; the no-browser arms above decide)"
fi

echo "-- AC17 no model in any run"
check "AC17 the recording SELVEDGE_PLANNER and the PATH-stub claude recorded zero calls across every run above" \
  '!fs.existsSync(E.PLANNER_CALLS) && !fs.existsSync(E.CLAUDE_CALLS)'

finish
