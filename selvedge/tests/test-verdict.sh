#!/usr/bin/env bash
# test-verdict.sh — pins `selvedge verdict` (selvedge/lib/verdict.mjs: deriveVerdict, VERDICTS,
# EVIDENCE_CLASSES, the D7 exit precedence, prior_revisions), the evidence.jsonl line contract
# (selvedge/lib/runner/evidence.mjs: EVIDENCE_KINDS, readEvidence), selvedge/schemas/
# verdict.schema.json and the no-string-literal-reason rule for verdict.mjs and lib/runner/*.mjs.
# Every arm turns red under its row of the brief's pin-mutation table.
#
# No browser: every run folder is synthetic — a hand-written plan.json and an evidence.jsonl whose
# run_start carries that plan's sha256, built by a small generator this script writes to its temp
# dir. Hermetic: a fresh temp HOME and a temp git repo as the target project; no model, no network.
# Needs node (>= 18) and git; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
LIB="$PLUGIN_DIR/lib"
export SELVEDGE_LIB="$LIB"
export SCHEMA="$PLUGIN_DIR/schemas/verdict.schema.json"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-verdict: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-verdict.sh needs it)"; echo "test-verdict: 0 passed, 1 failed"; exit 1; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-verdict.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$TMP/o"
unset SELVEDGE_PLANNER SELVEDGE_PLAYWRIGHT_MODULE SELVEDGE_ENTRY SELVEDGE_RUN_BUDGET_MS \
  SELVEDGE_PLANNER_TOKEN_BUDGET SELVEDGE_STEP_TIMEOUT_MS SELVEDGE_RUN_DIR SELVEDGE_BASE NODE_PATH

R="$TMP/repo"
mkdir -p "$R" && git -C "$R" init -q
export R

# The generator: node build.mjs <run-id> '<spec JSON>' writes <R>/.selvedge/runs/<run-id>/ with a
# plan.json, plan.sha256 and (unless spec.evidence === false) an evidence.jsonl, one criterion per
# entry of spec.shapes (criterion i has id c-<i as 12 digits>):
#   pass         read "12", expect equals "12" matched, completed
#   fail         read "6", expect equals "12" mismatched (stable_wait), completed
#   empty        read spec.empty ("" by default), expect equals "" matched, completed
#   material     as pass, with a material: true assumption
#   material_fail as fail, with a material: true assumption
#   blocked      goto ok, click ok, click failed: criterion_end step_failed, failed_step 2
#   interrupted  read "12", expect matched, no criterion_end line
#   no_expect    read "12", no expect line, completed
#   not_planned  listed under the plan's not_planned (criterion_not_testable)
# Other spec keys: plan_revision, criteria_sha256, data_state, hooks_run, replay_of, extra (raw
# lines appended to evidence.jsonl, after run_end unless no_end_line), no_end_line (omit run_end),
# evidence: false (no evidence.jsonl) or "" (an empty one).
cat > "$TMP/build.mjs" <<'EOF'
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
const [runId, specText] = process.argv.slice(2);
const spec = JSON.parse(specText);
const dir = path.join(process.env.R, '.selvedge', 'runs', runId);
mkdirSync(dir, { recursive: true });
const id = (i) => `c-${String(i).padStart(12, '0')}`;
const total = { testid: 'total' };
const plan = {
  schema_version: 1,
  target: 'web',
  criteria_sha256: spec.criteria_sha256 || 'a'.repeat(64),
  plan_revision: spec.plan_revision || 1,
  origins: ['http://localhost:4001'],
  steps_by_criterion: {},
  not_planned: [],
};
const ev = [];
const step = (c, i, type, outcome, value, extra = {}) =>
  ev.push({ kind: 'step', criterion: c, step: i, type, locator: type === 'goto' || type === 'expect' ? null : total, outcome, value, duration_ms: 5, ...extra });
const end = (c, outcome, reason = null, failed = null) =>
  ev.push({ kind: 'criterion_end', criterion: c, outcome, reason, failed_step: failed, screenshot: `screenshots/${c}.png` });
spec.shapes.forEach((shape, i) => {
  const c = id(i);
  if (shape === 'not_planned') {
    plan.not_planned.push({ id: c, reason: 'criterion_not_testable', rewrite: 'name the value to check' });
    end(c, 'not_planned', 'criterion_not_testable');
    return;
  }
  const material = shape.startsWith('material');
  const want = shape === 'empty' ? '' : '12';
  plan.steps_by_criterion[c] = {
    interpretation: `criterion ${i} reads the total`,
    polarity: 'positive',
    unverified_assumptions: material ? [{ text: 'the total is shown without tax', material: true }] : [{ text: 'a minor one', material: false }],
    steps: [
      { type: 'goto', url: 'http://localhost:4001/cart' },
      { type: 'click', locator: { role: 'button', name: 'Open cart' } },
      { type: 'click', locator: { role: 'button', name: 'Recalculate' } },
      { type: 'read', locator: total, property: 'text' },
      { type: 'expect', op: 'equals', value: want },
    ],
  };
  step(c, 0, 'goto', 'ok', null);
  if (shape === 'blocked') {
    step(c, 1, 'click', 'ok', null);
    step(c, 2, 'click', 'failed', null, { error: 'locator matched nothing' });
    end(c, 'step_failed', 'step_failed', 2);
    return;
  }
  step(c, 1, 'click', 'ok', null);
  step(c, 2, 'click', 'ok', null);
  const failing = shape === 'fail' || shape === 'material_fail';
  const read = shape === 'empty' ? ('empty' in spec ? spec.empty : '') : failing ? '6' : '12';
  step(c, 3, 'read', 'ok', read);
  if (shape !== 'no_expect') step(c, 4, 'expect', failing ? 'mismatched' : 'matched', null, failing ? { stable_wait: true } : {});
  if (shape !== 'interrupted') end(c, 'completed');
});
const planText = `${JSON.stringify(plan, null, 2)}\n`;
writeFileSync(path.join(dir, 'plan.json'), planText);
const sha = createHash('sha256').update(planText).digest('hex');
writeFileSync(path.join(dir, 'plan.sha256'), `${sha}  plan.json\n`);
if (spec.evidence === '') writeFileSync(path.join(dir, 'evidence.jsonl'), '');
else if (spec.evidence !== false) {
  const dataState = spec.data_state || 'unmanaged';
  const start = {
    kind: 'run_start', ts: '2026-11-16T12:00:00.000Z', run_id: runId, plan_sha256: sha, playwright_version: '1.65.1',
    data_state: dataState, hooks_run: spec.hooks_run || [], plan_time_actions: dataState === 'unmanaged' ? 4 : null,
    replay_of: spec.replay_of || null,
  };
  const lines = [start, ...ev];
  if (!spec.no_end_line) lines.push({ kind: 'run_end', ts: '2026-11-16T12:00:09.000Z', duration_ms: 9000 });
  const text = lines.map((l) => JSON.stringify(l)).join('\n') + '\n' + (spec.extra || []).map((l) => `${l}\n`).join('');
  writeFileSync(path.join(dir, 'evidence.jsonl'), text);
}
process.stdout.write(dir);
EOF

# mk <run-id> '<spec JSON>' → prints the run folder (the generator above).
mk() { node "$TMP/build.mjs" "$@"; }
# vd <label> <run-dir> — runs `selvedge verdict <run-dir>`; sets OUT / ERR (files), RC and DIR.
vd() {
  OUT="$TMP/o/$1.out"; ERR="$TMP/o/$1.err"; DIR="$2"
  (cd "$R" && bash "$CLI" verdict "$DIR" >"$OUT" 2>"$ERR"); RC=$?
  export OUT ERR RC DIR
}
# check <label> <js expression> — evaluated over the last vd(), with out err rc, v (verdict.json
# parsed, or null), c(i) (criterion i's entry), has(n) (<DIR>/<n> exists), S (the schema).
check() {
  local label="$1" expr="$2" got
  got="$(node -e '
const fs = require("fs");
const path = require("path");
const E = process.env;
const txt = (p) => { try { return fs.readFileSync(p, "utf8"); } catch { return ""; } };
const out = txt(E.OUT), err = txt(E.ERR), rc = Number(E.RC);
const has = (n) => fs.existsSync(path.join(E.DIR, n));
const v = has("verdict.json") ? JSON.parse(txt(path.join(E.DIR, "verdict.json"))) : null;
const c = (i) => (v && v.criteria ? v.criteria["c-" + String(i).padStart(12, "0")] : undefined);
const S = JSON.parse(txt(E.SCHEMA));
let r;
try { r = eval(process.argv[1]); } catch (e) { r = "error: " + e.message; }
if (r === true) process.stdout.write("true");
else process.stdout.write("false (" + String(r).slice(0, 80) + ") rc=" + E.RC + " out=" + JSON.stringify(out.slice(0, 500)) + " err=" + JSON.stringify(err.slice(-600)) + " verdict=" + JSON.stringify(v).slice(0, 900));
' "$expr" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}
# node_eval '<js>' — runs <js> as a module with V (verdict.mjs), Ev (runner/evidence.mjs),
# E (env-config.mjs), P (plan-steps.mjs) and S (the schema) in scope.
node_eval() {
  node --input-type=module -e "
import { pathToFileURL } from 'node:url';
import { readFileSync } from 'node:fs';
const L = process.env.SELVEDGE_LIB;
const V = await import(pathToFileURL(L + '/verdict.mjs').href);
const Ev = await import(pathToFileURL(L + '/runner/evidence.mjs').href);
const E = await import(pathToFileURL(L + '/env-config.mjs').href);
const P = await import(pathToFileURL(L + '/plan-steps.mjs').href);
const S = JSON.parse(readFileSync(process.env.SCHEMA, 'utf8'));
const same = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
$1"
}

echo "-- static: no string-literal reason, one evidence reader (AC1, AC7)"
reasons="$(node_eval 'console.log(Object.keys(E.REASONS).join("|"));')"
mods="$(cd "$LIB" && bash -c 'shopt -s nullglob; echo verdict.mjs runner/*.mjs')"
hits="$(cd "$LIB" && grep -nE "['\"\`]($reasons)['\"\`]" $mods)"
{ [ -n "$reasons" ] && [ -n "$mods" ] && [ -z "$hits" ]; } \
  && ok "AC1 verdict.mjs and lib/runner/*.mjs ($mods) name no reason as a string literal (REASONS only)" || ko "AC1 string-literal reasons: $hits"
{ grep -qE "import \{[^}]*readEvidence[^}]*\} from './runner/evidence.mjs'" "$LIB/verdict.mjs" \
  && ! grep -qF "evidence.jsonl'" "$LIB/verdict.mjs" \
  && grep -qE "import \{[^}]*readRunsLog[^}]*\} from './plan-runs.mjs'" "$LIB/verdict.mjs"; } \
  && ok "AC7 verdict.mjs reads evidence only through readEvidence and runs.jsonl only through readRunsLog" \
  || ko "verdict.mjs does not import readEvidence / readRunsLog, or opens evidence.jsonl itself"
grep -qF "if (isMain(import.meta.url))" "$LIB/verdict.mjs" && grep -qE "import \{[^}]*isMain[^}]*\} from './env-config.mjs'" "$LIB/verdict.mjs" \
  && ok "verdict.mjs guards main() with the one isMain from env-config.mjs" || ko "verdict.mjs: no isMain guard"

echo "-- static: the schema and the frozen sets (AC7)"
out="$(node_eval '
const d = S.$defs.criterion.properties;
console.log(JSON.stringify([
  S.$schema === "https://json-schema.org/draft/2020-12/schema",
  S.additionalProperties === false && S.$defs.criterion.additionalProperties === false,
  Object.isFrozen(V.VERDICTS) && same(S.$defs.verdict.enum, Object.values(V.VERDICTS)),
  Object.isFrozen(V.EVIDENCE_CLASSES) && same(d.evidence_class.enum, Object.values(V.EVIDENCE_CLASSES)),
  same(d.steps.items.properties.outcome.enum, Object.values(Ev.STEP_OUTCOMES)),
  same(d.steps.items.properties.type.enum, P.STEP_TYPES),
  same(d.expected.oneOf[0].properties.op.enum, P.EXPECT_OPS),
  same(S.properties.data_state.enum, Object.values(Ev.DATA_STATES)),
]));')"
[ "$out" = '[true,true,true,true,true,true,true,true]' ] \
  && ok "AC7 verdict.schema.json is draft 2020-12, closed, and its verdict / evidence_class / step outcome / step type / op / data_state enums equal VERDICTS, EVIDENCE_CLASSES, STEP_OUTCOMES, STEP_TYPES, EXPECT_OPS, DATA_STATES" \
  || ko "schema vs frozen sets: $out"
out="$(node_eval '
const kinds = Object.values(Ev.EVIDENCE_KINDS);
console.log(Object.isFrozen(Ev.EVIDENCE_KINDS) && same(kinds, ["run_start","step","criterion_end","run_end"]) && same(Object.keys(Ev.EVIDENCE_FIELDS), kinds) ? "yes" : "no " + JSON.stringify(kinds));')"
[ "$out" = "yes" ] && ok "AC7 EVIDENCE_KINDS is frozen: run_start, step, criterion_end, run_end (each with its EVIDENCE_FIELDS)" || ko "EVIDENCE_KINDS: $out"
out="$(node_eval '
const R = E.REASONS;
console.log(JSON.stringify([Ev.CRITERION_OUTCOMES.step_failed === R.step_failed, Ev.CRITERION_OUTCOMES.stuck_screen === R.stuck_screen, Ev.CRITERION_OUTCOMES.budget_exceeded === R.budget_exceeded, Object.isFrozen(Ev.CRITERION_OUTCOMES)]));')"
[ "$out" = '[true,true,true,true]' ] && ok "the criterion_end outcomes that are reasons are the REASONS values" || ko "CRITERION_OUTCOMES: $out"

echo "-- exitCodeFor: the D7 precedence (AC2)"
out="$(node_eval '
const P0 = V.VERDICTS;
console.log(JSON.stringify([
  V.exitCodeFor([P0.PASS, P0.NOT_VERIFIABLE, P0.BLOCKED]), V.exitCodeFor([P0.PASS, P0.NOT_VERIFIABLE, P0.BLOCKED, P0.FAIL]),
  V.exitCodeFor([P0.PASS, P0.NOT_VERIFIABLE]), V.exitCodeFor([P0.PASS]), V.exitCodeFor([]),
  V.overallVerdict([P0.NOT_VERIFIABLE, P0.BLOCKED]),
]));')"
[ "$out" = '[2,1,3,0,3,"BLOCKED"]' ] \
  && ok "exitCodeFor: FAIL > BLOCKED > NOT_VERIFIABLE > PASS → 1 / 2 / 3 / 0; no criterion is NOT_VERIFIABLE (3), never PASS" || ko "exitCodeFor: $out"

echo "-- CLI surface"
out="$(bash "$CLI" 2>&1)"
grep -qE '^ +verdict <run-dir> ' <<<"$out" && ok "the CLI help lists verdict" || ko "help: '$out'"
vd help "help"
check "selvedge verdict help exits 0 and documents the exit precedence" 'rc === 0 && out.includes("Usage: selvedge verdict <run-dir>") && out.includes("1 any FAIL")'
OUT="$TMP/o/noarg.out"; ERR="$TMP/o/noarg.err"; DIR="$TMP"; (bash "$CLI" verdict >"$OUT" 2>"$ERR"); RC=$?; export OUT ERR RC DIR
check "no <run-dir>: exit 2 with the usage" 'rc === 2 && err.includes("Usage: selvedge verdict")'
vd notdir "$TMP/no-such-dir"
check "a <run-dir> that is not a directory: exit 2 naming it" 'rc === 2 && err.includes("no-such-dir") && err.includes("is not a directory")'

echo "-- verdicts and exit codes (AC2)"
D="$(mk 20261116T120000Z-aaaa01 '{"shapes":["pass","empty","blocked"]}')"
vd ac2-pnb "$D"
check "AC2 {PASS, NOT_VERIFIABLE, BLOCKED} → exit 2" 'rc === 2 && c(0).verdict === "PASS" && c(1).verdict === "NOT_VERIFIABLE" && c(2).verdict === "BLOCKED"'
check "AC2 stdout: one '<VERDICT> [<reason>] <id>' line per criterion, then 'verdict <overall> <file>'" \
  'out === "PASS c-000000000000\nNOT_VERIFIABLE no_value_read c-000000000001\nBLOCKED step_failed c-000000000002\nverdict BLOCKED " + require("path").join(E.DIR, "verdict.json") + "\n"'
D="$(mk 20261116T120000Z-aaaa02 '{"shapes":["pass","empty","blocked","fail"]}')"
vd ac2-fail "$D"
check "AC2 with a FAIL added → exit 1" 'rc === 1 && c(3).verdict === "FAIL" && out.includes("verdict FAIL ")'
D="$(mk 20261116T120000Z-aaaa03 '{"shapes":["pass","empty"]}')"
vd ac2-pn "$D"
check "AC2 only PASS + NOT_VERIFIABLE → exit 3" 'rc === 3 && out.includes("verdict NOT_VERIFIABLE ")'
D="$(mk 20261116T120000Z-aaaa04 '{"shapes":["pass","pass"]}')"
vd ac2-p "$D"
check "AC2 only PASS → exit 0" 'rc === 0 && c(0).verdict === "PASS" && c(1).verdict === "PASS" && c(0).reason === null && out.includes("verdict PASS ")'

echo "-- an empty read is never PASS (AC3)"
D="$(mk 20261116T120000Z-aaaa05 '{"shapes":["empty"],"empty":""}')"
vd ac3-empty "$D"
check "AC3 read \"\" with expect equals \"\" (matched) → NOT_VERIFIABLE no_value_read, exit 3" \
  'rc === 3 && c(0).verdict === "NOT_VERIFIABLE" && c(0).reason === "no_value_read" && c(0).matched === true && c(0).read_value === "" && c(0).expected.value === ""'
D="$(mk 20261116T120000Z-aaaa06 '{"shapes":["empty"],"empty":null}')"
vd ac3-null "$D"
check "AC3 read null → NOT_VERIFIABLE no_value_read" 'rc === 3 && c(0).verdict === "NOT_VERIFIABLE" && c(0).reason === "no_value_read" && c(0).read_value === null'
D="$(mk 20261116T120000Z-aaac05 '{"shapes":["empty"],"empty":"  "}')"
vd ac3-blank "$D"
check "a whitespace-only read is empty too → NOT_VERIFIABLE no_value_read" 'rc === 3 && c(0).reason === "no_value_read"'
D="$(mk 20261116T120000Z-aaac06 '{"shapes":["empty","empty"],"empty":0}')"
vd ac3-zero "$D"
check "a read of 0 (a count) is a value, not empty: matched → PASS" 'rc === 0 && c(0).verdict === "PASS" && c(0).read_value === 0'
D="$(mk 20261116T120000Z-aaac07 '{"shapes":["empty"],"empty":false}')"
vd ac3-false "$D"
check "a read of false (checked) is a value, not empty: matched → PASS" 'rc === 0 && c(0).verdict === "PASS" && c(0).read_value === false'

echo "-- FAIL carries the read and expected values (AC4)"
D="$(mk 20261116T120000Z-aaaa07 '{"shapes":["fail"]}')"
vd ac4 "$D"
check "AC4 a mismatched final expect → FAIL with read_value, expected and matched: false, reason null" \
  'rc === 1 && c(0).verdict === "FAIL" && c(0).read_value === "6" && JSON.stringify(c(0).expected) === JSON.stringify({ op: "equals", value: "12" }) && c(0).matched === false && c(0).reason === null'

echo "-- a material assumption is never PASS (AC5)"
D="$(mk 20261116T120000Z-aaaa08 '{"shapes":["material"]}')"
vd ac5 "$D"
check "AC5 expect held + material: true → NOT_VERIFIABLE material_assumption, with the assumption text" \
  'rc === 3 && c(0).verdict === "NOT_VERIFIABLE" && c(0).reason === "material_assumption" && c(0).matched === true && c(0).unverified_assumptions[0].text === "the total is shown without tax" && c(0).unverified_assumptions[0].material === true'
D="$(mk 20261116T120000Z-aaaa09 '{"shapes":["material_fail","pass"]}')"
vd ac5-fail "$D"
check "a mismatched expect stays FAIL under a material assumption; a material: false one does not stop PASS" \
  'rc === 1 && c(0).verdict === "FAIL" && c(1).verdict === "PASS" && c(1).unverified_assumptions[0].material === false'

echo "-- prior_revisions (AC6)"
# runs.jsonl: revision 1 of these criteria (CS) ran FAIL; before that line sit a run line of OTHER
# criteria (OS) with the same revision number (PASS) and a replay of revision 1 (PASS) — neither is
# revision 1's own run.
CS="$(printf 'b%.0s' $(seq 64))"; OS="$(printf 'c%.0s' $(seq 64))"
mkdir -p "$R/.selvedge"
{
  printf '{"event":"freeze","ts":"t","run_id":"20261116T110000Z-bbbb01","criteria_sha256":"%s","plan_sha256":"%s","plan_revision":1,"plan_time_actions":0,"planner_tokens":null}\n' "$CS" "$(printf 'd%.0s' $(seq 64))"
  printf '{"event":"freeze","ts":"t","run_id":"20261116T110000Z-cccc01","criteria_sha256":"%s","plan_sha256":"%s","plan_revision":1,"plan_time_actions":0,"planner_tokens":null}\n' "$OS" "$(printf 'd%.0s' $(seq 64))"
  printf '{"event":"run","ts":"t","run_id":"20261116T110000Z-cccc01","criteria_sha256":"%s","plan_revision":1,"replay_of":null,"verdict":"PASS"}\n' "$OS"
  printf '{"event":"run","ts":"t","run_id":"20261116T110500Z-bbbb0f","criteria_sha256":"%s","plan_revision":1,"replay_of":"20261116T110000Z-bbbb01","verdict":"PASS"}\n' "$CS"
  printf '{"event":"run","ts":"t","run_id":"20261116T110000Z-bbbb01","criteria_sha256":"%s","plan_revision":1,"replay_of":null,"verdict":"FAIL"}\n' "$CS"
  printf '{"event":"freeze","ts":"t","run_id":"20261116T120000Z-bbbb02","criteria_sha256":"%s","plan_sha256":"%s","plan_revision":2,"plan_time_actions":0,"planner_tokens":null}\n' "$CS" "$(printf 'd%.0s' $(seq 64))"
} > "$R/.selvedge/runs.jsonl"
D="$(mk 20261116T120000Z-bbbb02 '{"shapes":["pass"],"plan_revision":2,"criteria_sha256":"'"$CS"'"}')"
before="$(cksum < "$R/.selvedge/runs.jsonl")"
vd ac6 "$D"
check "AC6 revision 2 carries plan_revision: 2 and prior_revisions: [{revision: 1, verdict: FAIL}] (its own run line: same criteria_sha256, not a replay)" \
  'rc === 0 && v.plan_revision === 2 && JSON.stringify(v.prior_revisions) === JSON.stringify([{ revision: 1, verdict: "FAIL" }])'
[ "$(cksum < "$R/.selvedge/runs.jsonl")" = "$before" ] && ok "AC18 (verdict side) selvedge verdict appends nothing to runs.jsonl" || ko "verdict changed runs.jsonl"
printf '{"event":"freeze","ts":"t","run_id":"20261116T130000Z-bbbb03","criteria_sha256":"%s","plan_sha256":"%s","plan_revision":3,"plan_time_actions":0,"planner_tokens":null}\n' "$CS" "$(printf 'd%.0s' $(seq 64))" >> "$R/.selvedge/runs.jsonl"
D="$(mk 20261116T130000Z-bbbb03 '{"shapes":["pass"],"plan_revision":3,"criteria_sha256":"'"$CS"'"}')"
vd ac6-null "$D"
check "AC6 one entry per earlier revision, first first; a revision that never ran has verdict null" \
  'rc === 0 && JSON.stringify(v.prior_revisions) === JSON.stringify([{ revision: 1, verdict: "FAIL" }, { revision: 2, verdict: null }])'
D="$(mk 20261116T120000Z-aaaa0a '{"shapes":["pass"],"plan_revision":1,"criteria_sha256":"'"$CS"'"}')"
vd ac6-first "$D"
check "AC6 revision 1 has no prior revisions" 'rc === 0 && JSON.stringify(v.prior_revisions) === "[]"'

echo "-- verdict.json carries exactly the schema's keys (AC7)"
D="$(mk 20261116T120000Z-aaaa0b '{"shapes":["pass","blocked","not_planned"]}')"
vd ac7 "$D"
check "AC7 the written top-level keys equal the schema's properties (data_state unmanaged → plan_time_actions present)" \
  'rc === 2 && v && JSON.stringify(Object.keys(v).sort()) === JSON.stringify(Object.keys(S.properties).sort()) && v.data_state === "unmanaged" && v.plan_time_actions === 4'
check "AC7 every criterion entry has exactly the schema's criterion keys, evidence_class structured-read" \
  'Object.values(v.criteria).length === 3 && Object.values(v.criteria).every((e) => JSON.stringify(Object.keys(e).sort()) === JSON.stringify(Object.keys(S.$defs.criterion.properties).sort()) && e.evidence_class === "structured-read")'
check "AC7 schema_version, target, plan_sha256, playwright_version, replay_of and hooks_run come from the plan and run_start" \
  'v.schema_version === 1 && v.target === "web" && /^[0-9a-f]{64}$/.test(v.plan_sha256) && v.playwright_version === "1.65.1" && v.replay_of === null && Array.isArray(v.hooks_run) && v.hooks_run.length === 0'
check "AC7 a step_failed criterion: BLOCKED step_failed with failed_step 2 and its step summary" \
  'c(1).verdict === "BLOCKED" && c(1).reason === "step_failed" && c(1).failed_step === 2 && JSON.stringify(c(1).steps.map((s) => s.outcome)) === JSON.stringify(["ok","ok","failed"]) && c(1).steps.every((s) => JSON.stringify(Object.keys(s)) === JSON.stringify(["step","type","outcome","duration_ms"]))'
check "AC7 interpretation and unverified_assumptions come from the plan; a not_planned criterion is NOT_VERIFIABLE with the plan's reason" \
  'c(0).interpretation === "criterion 0 reads the total" && c(0).failed_step === null && c(2).verdict === "NOT_VERIFIABLE" && c(2).reason === "criterion_not_testable" && c(2).interpretation === null && c(2).expected === null'
D="$(mk 20261116T120000Z-aaaa0c '{"shapes":["pass"],"data_state":"managed","hooks_run":["reset","seed"]}')"
vd ac7-managed "$D"
check "AC7 data_state managed: hooks_run as recorded, no plan_time_actions key" \
  'rc === 0 && v.data_state === "managed" && JSON.stringify(v.hooks_run) === JSON.stringify(["reset","seed"]) && !("plan_time_actions" in v)'
D="$(mk 20261116T120000Z-aaaa0d '{"shapes":["pass"],"replay_of":"20261116T110000Z-bbbb01"}')"
vd ac7-replay "$D"
check "AC7 replay_of from run_start" 'rc === 0 && v.replay_of === "20261116T110000Z-bbbb01"'
first="$(cat "$D/verdict.json")"; vd ac7-again "$D"
[ "$(cat "$D/verdict.json")" = "$first" ] && [ "$RC" -eq 0 ] && ok "re-running verdict re-derives the same verdict.json" || ko "verdict.json differs on a re-run (rc=$RC)"

echo "-- missing and interrupted evidence (AC8)"
D="$(mk 20261116T120000Z-aaaa0e '{"shapes":["pass"],"evidence":false}')"
vd ac8-none "$D"
check "AC8 no evidence.jsonl → exit 2 evidence_missing on stderr, no verdict.json" 'rc === 2 && err.includes("evidence_missing") && !has("verdict.json")'
D="$(mk 20261116T120000Z-aaaa0f '{"shapes":["interrupted","pass"],"no_end_line":true}')"
vd ac8-cut "$D"
check "AC8 no criterion_end for a planned criterion (its expect matched) → BLOCKED run_interrupted" \
  'rc === 2 && c(0).verdict === "BLOCKED" && c(0).reason === "run_interrupted" && c(0).matched === true && c(1).verdict === "PASS"'
D="$(mk 20261116T120000Z-aaac08 '{"shapes":["no_expect"]}')"
vd no-expect "$D"
check "a completed criterion with no expect line is never PASS → BLOCKED run_interrupted, matched null" \
  'rc === 2 && c(0).verdict === "BLOCKED" && c(0).reason === "run_interrupted" && c(0).matched === null && c(0).read_value === "12"'
D="$(mk 20261116T120000Z-aaac09 '{"shapes":["pass"],"evidence":""}')"
vd empty-file "$D"
check "an empty evidence.jsonl (no run_start) → exit 2 evidence_missing" 'rc === 2 && err.includes("evidence_missing") && err.includes("not run_start") && !has("verdict.json")'

echo "-- evidence that cannot be trusted is refused (AC7, readEvidence)"
D="$(mk 20261116T120000Z-aaab01 '{"shapes":["pass"],"no_end_line":true,"extra":["{\"kind\":\"screenshot\",\"criterion\":\"c-000000000000\"}"]}')"
vd bad-kind "$D"
check "a line with an unknown kind → exit 2 evidence_missing naming the kind, no verdict.json" 'rc === 2 && err.includes("evidence_missing") && err.includes("unknown kind \"screenshot\"") && !has("verdict.json")'
D="$(mk 20261116T120000Z-aaab02 '{"shapes":["pass"],"no_end_line":true,"extra":["{not json"]}')"
vd bad-json "$D"
check "a line that is not JSON (a torn write) → exit 2 evidence_missing" 'rc === 2 && err.includes("evidence_missing") && err.includes("not valid JSON") && !has("verdict.json")'
D="$(mk 20261116T120000Z-aaab03 '{"shapes":["pass"],"no_end_line":true,"extra":["{\"kind\":\"step\",\"criterion\":\"c-000000000000\",\"step\":4,\"type\":\"expect\",\"locator\":null,\"outcome\":\"matched\",\"value\":null,\"duration_ms\":1}"]}')"
vd late-step "$D"
check "a step line after its criterion's criterion_end → exit 2 evidence_missing" 'rc === 2 && err.includes("evidence_missing") && err.includes("after its criterion_end")'
D="$(mk 20261116T120000Z-aaab04 '{"shapes":["pass"],"no_end_line":true,"extra":["{\"kind\":\"criterion_end\",\"criterion\":\"c-000000000000\",\"outcome\":\"completed\",\"reason\":\"nope\",\"failed_step\":null,\"screenshot\":null}"]}')"
vd bad-reason "$D"
check "a criterion_end whose reason is not in REASONS → exit 2 evidence_missing" 'rc === 2 && err.includes("evidence_missing") && err.includes("reason has the wrong value")'
D="$(mk 20261116T120000Z-aaab05 '{"shapes":["pass"],"no_end_line":true,"extra":["{\"kind\":\"criterion_end\",\"criterion\":\"c-0000000000ff\",\"outcome\":\"completed\",\"reason\":null,\"failed_step\":null,\"screenshot\":null}"]}')"
vd stray "$D"
check "evidence naming a criterion the plan does not hold → exit 2 evidence_missing" 'rc === 2 && err.includes("evidence_missing") && err.includes("c-0000000000ff")'
D="$(mk 20261116T120000Z-aaab08 '{"shapes":["pass"],"extra":["{\"kind\":\"run_end\",\"ts\":\"t\",\"duration_ms\":1}"]}')"
vd after-end "$D"
check "a line after run_end → exit 2 evidence_missing" 'rc === 2 && err.includes("evidence_missing") && err.includes("follows run_end")'
out="$(node_eval '
const p = Ev.evidenceLineProblem;
console.log(JSON.stringify([
  p({ kind: "run_end", ts: "t", duration_ms: 1 }),
  p({ kind: "run_end", ts: "t", duration_ms: 1, extra: 1 }) !== null,
  p({ kind: "run_end", ts: "t" }) !== null,
  p({ kind: "step", criterion: "c", step: 0, type: "click", locator: null, outcome: "matched", value: null, duration_ms: 1 }) !== null,
  p({ kind: "criterion_end", criterion: "c", outcome: "blocked", reason: null, failed_step: null, screenshot: null }) !== null,
]));')"
[ "$out" = '[null,true,true,true,true]' ] \
  && ok "evidenceLineProblem: a known kind with its fields passes; an unknown field, a missing field, an expect outcome on a click, a blocked end with no reason are refused" \
  || ko "evidenceLineProblem: $out"

echo "-- the verdict is derived from the plan the run executed"
D="$(mk 20261116T120000Z-aaab06 '{"shapes":["material"]}')"
node -e 'const f=process.argv[1]; const fs=require("fs"); fs.writeFileSync(f, fs.readFileSync(f,"utf8").replace("\"material\": true","\"material\": false"));' "$D/plan.json"
vd edited "$D"
check "plan.json edited after the run (an assumption un-marked material) → exit 2 plan_modified, no verdict.json" 'rc === 2 && err.includes("plan_modified") && !has("verdict.json")'
D="$(mk 20261116T120000Z-aaab07 '{"shapes":["pass"]}')"
rm "$D/plan.json"
vd no-plan "$D"
check "no plan.json → exit 2 not_frozen" 'rc === 2 && err.includes("not_frozen") && !has("verdict.json")'
D="$(mk 20261116T120000Z-aaab09 '{"shapes":["pass"]}')"
printf '{' > "$D/plan.json"
vd bad-plan "$D"
check "a plan.json that is not JSON → exit 2 plan_invalid" 'rc === 2 && err.includes("plan_invalid") && !has("verdict.json")'

finish
