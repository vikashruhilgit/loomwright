#!/usr/bin/env bash
# test-plan-validate.sh — pins `selvedge plan --validate` and the modules behind it
# (selvedge/lib/plan-steps.mjs, plan-validate.mjs, plan.mjs, schemas/plan.schema.json): the PASS
# rule (a value read after the last action), existence-only expects, the step registry (types,
# fields, locators, code-like content, goto origins), negative baselines, interpretation / polarity /
# assumptions, vague criteria, criterion coverage and criteria_sha256; every problem listed; the
# snapshot-prefix mode of validateSteps; {{NAME}} resolution; the schema equal to the validator's
# frozen sets; and the README's PLAN_PROBLEMS list. Every arm turns red under its row of the
# brief's pin-mutation table.
#
# Hermetic: a fresh temp HOME, a temp git repo as the target project, no network, no browser.
# Needs node (>= 18) and git; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"
export SELVEDGE_LIB="$PLUGIN_DIR/lib"
export SELVEDGE_PLAN_SCHEMA="$PLUGIN_DIR/schemas/plan.schema.json"
export SELVEDGE_README="$PLUGIN_DIR/README.md"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "  FAIL $tool is not on PATH (test-plan-validate.sh needs it)"; echo "test-plan-validate: 0 passed, 1 failed"; exit 1; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-plan-validate.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1

# node_eval <js> — an ES module with E (env-config), S (plan-steps) and V (plan-validate) imported.
node_eval() {
  node --input-type=module -e "
import { pathToFileURL } from 'node:url';
const E = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/env-config.mjs').href);
const S = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/plan-steps.mjs').href);
const V = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/plan-validate.mjs').href);
$1"
}

# The target project: selvedge.json lists localhost:4100 and :4101.
R="$TMP/repo"
mkdir -p "$R" && git -C "$R" init -q
printf '{"schema_version":1,"origins":["http://localhost:4100","http://localhost:4101"]}' > "$R/selvedge.json"

# Three criteria: c1 positive and testable, c2 vague, c3 negative.
printf -- '- The cart total shows "12" when the quantity is 2\n- the page looks good\n- Saving a draft must not change the "Sent" count\n' \
  | (cd "$R" && bash "$CLI" criteria from-text) > "$TMP/criteria.json" 2>/dev/null
ids="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(d.criteria.map(c=>c.id).join(" "))' "$TMP/criteria.json" 2>/dev/null)"
read -r c1 c2 c3 <<<"$ids"
[ -n "${c3:-}" ] && ok "setup: criteria from-text gives three criteria ($ids)" || { ko "setup: criteria.json: '$(cat "$TMP/criteria.json")'"; echo "test-plan-validate: $pass passed, $fail failed"; exit 1; }

# The plan builder: a valid base plan for the three criteria, then a JS body that mutates `p`.
# Helpers inside the body: c1 c2 c3 (ids), steps(id), crit(id).
cat > "$TMP/mkplan.mjs" <<'EOF'
import { mkdirSync, readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const C = await import(pathToFileURL(process.env.SELVEDGE_LIB + '/criteria.mjs').href);
const [dir, criteriaFile, body] = process.argv.slice(2);
const doc = JSON.parse(readFileSync(criteriaFile, 'utf8'));
const [c1, c2, c3] = doc.criteria.map((c) => c.id);
const p = {
  schema_version: 1,
  target: 'web',
  criteria_sha256: C.criteriaSha256(doc.criteria),
  origins: ['http://localhost:4100'],
  steps_by_criterion: {
    [c1]: {
      interpretation: 'Setting the quantity to 2 makes the total read 12.',
      polarity: 'positive',
      unverified_assumptions: [{ text: 'a unit costs 6', material: false }],
      steps: [
        { type: 'goto', url: 'http://localhost:4100/cart' },
        { type: 'click', locator: { role: 'button', name: 'Open cart', exact: true } },
        { type: 'fill', locator: { label: 'Quantity' }, value: '2' },
        { type: 'read', property: 'text', locator: { testid: 'total' } },
        { type: 'expect', op: 'equals', value: '12' },
      ],
    },
    [c3]: {
      interpretation: 'Saving a draft leaves the Sent count unchanged.',
      polarity: 'negative',
      unverified_assumptions: [],
      steps: [
        { type: 'goto', url: 'http://localhost:4100/mail' },
        { type: 'read', property: 'text', locator: { testid: 'sent-count' } },
        { type: 'click', locator: { role: 'button', name: 'Save draft' } },
        { type: 'read', property: 'text', locator: { testid: 'sent-count' } },
        { type: 'expect', op: 'changed_from', value: false },
      ],
    },
  },
  not_planned: [{ id: c2, reason: 'criterion_not_testable', rewrite: 'The home page shows the heading "Welcome"' }],
};
const steps = (id) => p.steps_by_criterion[id].steps;
const crit = (id) => p.steps_by_criterion[id];
new Function('p', 'c1', 'c2', 'c3', 'steps', 'crit', body)(p, c1, c2, c3, steps, crit);
mkdirSync(dir, { recursive: true });
writeFileSync(path.join(dir, 'plan.json'), `${JSON.stringify(p, null, 2)}\n`);
copyFileSync(criteriaFile, path.join(dir, 'criteria.json'));
EOF

n=0
# validate <js body> — builds a fresh run folder from the base plan + body and runs
# `selvedge plan --validate` on it from the repo; sets $rc, $out, $err, $dir.
validate() {
  n=$((n + 1)); dir="$R/.selvedge/runs/t$n"
  node "$TMP/mkplan.mjs" "$dir" "$TMP/criteria.json" "$1" || { rc=99; out=''; err='mkplan failed'; return; }
  out="$(cd "$R" && bash "$CLI" plan --validate "$dir/plan.json" 2>"$TMP/stderr" </dev/null)"; rc=$?
  err="$(cat "$TMP/stderr")"
}

# want_problem <label> <id> <code> — the last validate exited 2 with a line naming id and code.
want_problem() {
  { [ "$rc" -eq 2 ] && grep -qF "plan_invalid: $2: $3" <<<"$err"; } && ok "$1" || ko "$1: rc=$rc err='$err'"
}

echo "-- the base plan is valid (control)"
validate ''
{ [ "$rc" -eq 0 ] && grep -qF 'plan valid:' <<<"$out" && ! grep -q 'plan_invalid' <<<"$err"; } \
  && ok "the base plan (positive, negative with a baseline, vague under not_planned) validates, exit 0" || ko "base plan: rc=$rc out='$out' err='$err'"

echo "-- the PASS rule (AC1, AC2)"
validate 'crit(c1).steps = steps(c1).slice(0, 2);'
want_problem "AC1 a criterion whose steps end in click: exit 2, plan_invalid: <id>: missing_final_read_expect" "$c1" missing_final_read_expect
grep -qF "plan_invalid: $c3:" <<<"$err" && ko "AC1 the problem names only the faulty criterion: err='$err'" || ok "AC1 the problem names only the faulty criterion"
validate 'steps(c1).pop();'
want_problem "AC1 steps ending in read (no expect) are rejected missing_final_read_expect" "$c1" missing_final_read_expect
for op in visible hidden exists attached; do
  validate "steps(c1)[4] = { type: 'expect', op: '$op', value: true };"
  want_problem "AC2 a final expect with op $op is rejected existence_only_expect" "$c1" existence_only_expect
done
validate "steps(c1).splice(3, 2, { type: 'read', property: 'count', locator: { testid: 'total' } }, { type: 'expect', op: 'gt', value: 0 });"
want_problem "AC2 read count then expect gt 0 is rejected existence_only_expect" "$c1" existence_only_expect
validate "steps(c1).splice(3, 2, { type: 'read', property: 'count', locator: { testid: 'line' } }, { type: 'expect', op: 'equals', value: 2 });"
[ "$rc" -eq 0 ] && ok "AC2 read count then expect equals 2 (a value) is accepted" || ko "AC2 count equals 2: rc=$rc err='$err'"

echo "-- a final expect any read value meets (vacuousExpect)"
for v in "''" "'   '"; do
  validate "steps(c1)[4] = { type: 'expect', op: 'contains', value: $v };"
  want_problem "a final expect contains $v (holds for any text) is rejected existence_only_expect" "$c1" existence_only_expect
done
for v in "''" "'.*'" "'^\\\\d*\$'"; do
  validate "steps(c1)[4] = { type: 'expect', op: 'matches', value: $v };"
  want_problem "a final expect matches $v (a pattern matching the empty string) is rejected existence_only_expect" "$c1" existence_only_expect
done
for v in "'.'" "'^.+\$'" "'\\\\S'" "'[\\\\s\\\\S]'" "'\\\\w'" "'..'" "'^.{2,}\$'" "'[\\\\s\\\\S]{2}'" "'^(?:.|\\\\n){2,}\$'"; do
  validate "steps(c1)[4] = { type: 'expect', op: 'matches', value: $v };"
  want_problem "a final expect matches $v (a pattern any non-empty text meets) is rejected existence_only_expect" "$c1" existence_only_expect
done
for v in "'^\\\\\$\\\\d+\\\\.\\\\d{2}\$'" "'Total: 12'" "'^\\\\d+\$'" "'^[a-z0-9-]+\$'" "'^[A-Za-z ]+\$'" "'^[A-Z0-9]+\$'" "'^ORD-\\\\d+\$'"; do
  validate "steps(c1)[4] = { type: 'expect', op: 'matches', value: $v };"
  [ "$rc" -eq 0 ] && ok "control: a final expect matches $v (a value or a format) is accepted" || ko "matches $v: rc=$rc err='$err'"
done
validate "steps(c1).splice(3, 2, { type: 'read', property: 'count', locator: { testid: 'line' } }, { type: 'expect', op: 'lt', value: 1000000 });"
want_problem "read count then expect lt 1000000 (holds when nothing exists) is rejected existence_only_expect" "$c1" existence_only_expect
validate "steps(c1)[4] = { type: 'expect', op: 'contains', value: '12' };"
[ "$rc" -eq 0 ] && ok "control: a final expect contains '12' (a non-blank value) is accepted" || ko "contains 12: rc=$rc err='$err'"
validate "steps(c1)[4] = { type: 'expect', op: 'matches', value: '^12\$' };"
[ "$rc" -eq 0 ] && ok "control: a final expect matches '^12\$' (no empty match) is accepted" || ko "matches ^12$: rc=$rc err='$err'"
validate "steps(c1).splice(3, 2, { type: 'read', property: 'count', locator: { testid: 'line' } }, { type: 'expect', op: 'gt', value: 1 });"
[ "$rc" -eq 0 ] && ok "control: read count then expect gt 1 (a lower bound above existence) is accepted" || ko "count gt 1: rc=$rc err='$err'"
validate "steps(c1)[4] = { type: 'expect', op: 'lt', value: 13 };"
[ "$rc" -eq 0 ] && ok "control: read text then expect lt 13 (a bound on a read value, not a count) is accepted" || ko "text lt 13: rc=$rc err='$err'"
validate "steps(c1)[4] = { type: 'expect', op: 'equals', value: '' };"
[ "$rc" -eq 0 ] && ok "control: a final expect equals '' (the value is empty, e.g. a cleared field) is accepted" || ko "equals '': rc=$rc err='$err'"

echo "-- the step registry (AC3)"
validate "steps(c1).splice(1, 0, { type: 'hover', locator: { text: 'Cart' } });"
want_problem "AC3 an unknown step type is rejected unknown_step_type" "$c1" unknown_step_type
validate "steps(c1)[1].timeout = 5000;"
want_problem "AC3 a known type with an extra field is rejected unknown_field" "$c1" unknown_field
validate "delete steps(c1)[0].url;"
want_problem "a goto with no url is rejected plan_schema_violation" "$c1" plan_schema_violation
for bad in "steps(c1)[4] = { type: 'expect', op: 'gt', value: '3' };" \
           "steps(c1)[4] = { type: 'expect', op: 'changed_from', value: 'no' };" \
           "steps(c1)[4] = { type: 'expect', op: 'matches', value: '(' };" \
           "steps(c1)[4] = { type: 'expect', op: 'equals', value: null };" \
           "steps(c1)[3] = { type: 'read', property: 'url', locator: { testid: 'total' } };" \
           "steps(c1)[3] = { type: 'read', property: 'text' };" \
           "steps(c1)[3].property = 'innerHTML';" \
           "steps(c1)[2].value = 2;" \
           "steps(c1).splice(1, 0, { type: 'wait_for', locator: { text: 'Cart' }, state: 'gone' });" \
           "steps(c1).splice(1, 0, { type: 'check', locator: { text: 'Gift' }, checked: 'yes' });" \
           "steps(c1).splice(1, 0, 'click');"; do
  validate "$bad"
  want_problem "a malformed step value ($bad) is rejected plan_schema_violation" "$c1" plan_schema_violation
done
validate "steps(c1)[3] = { type: 'read', property: 'attribute:aria-valuenow', locator: { label: 'Quantity' } }; steps(c1)[4] = { type: 'expect', op: 'matches', value: '^2$' };"
[ "$rc" -eq 0 ] && ok "read attribute:<name> with a locator and expect matches a valid regex are accepted" || ko "attribute read: rc=$rc err='$err'"
for loc in '{ css: "#buy" }' '{ xpath: "//button" }' '{ selector: "button" }' '{ role: "button", text: "Buy" }' '{}' '"button"' '{ label: "Qty", exact: true }'; do
  validate "steps(c1)[1].locator = $loc;"
  want_problem "AC3 the locator $loc is rejected invalid_locator" "$c1" invalid_locator
done
validate "steps(c1).splice(1, 1, { type: 'click', locator: { role: 'button' } }, { type: 'click', locator: { text: 'Cart' } }, { type: 'check', locator: { testid: 'gift' }, checked: true }, { type: 'press', key: 'Enter' }, { type: 'wait_for', locator: { label: 'Quantity' }, state: 'visible' }, { type: 'select', locator: { label: 'Size' }, value: 'M' });"
[ "$rc" -eq 0 ] && ok "AC3 every step type and locator form (role, label, text, testid) with its own fields is accepted" || ko "AC3 all forms: rc=$rc err='$err'"
# One sample per code-like pattern, each in a fill value.
for sample in '() => 1' 'function(){}' '<script>x' 'javascript:alert(1)' '${x}' 'a`b' 'eval(1)' 'document.cookie' 'window.x' 'require(1)' 'import x'; do
  export SAMPLE="$sample"
  validate "steps(c1)[2].value = process.env.SAMPLE;"
  want_problem "AC3 a step value '$sample' is rejected code_like_content" "$c1" code_like_content
done
unset SAMPLE
validate "steps(c1)[1].locator.name = 'Pay => now';"
want_problem "AC3 code-like content in a locator field is rejected too" "$c1" code_like_content
validate "p.origins.push('http://localhost:4199'); steps(c1)[0].url = 'http://localhost:4199/cart';"
want_problem "AC3 a goto to an origin listed in the plan but not in selvedge.json is rejected origin_not_allowed" "$c1" origin_not_allowed
validate "steps(c1)[0].url = 'http://localhost:4101/cart';"
want_problem "AC3 a goto to an origin in selvedge.json but not in the plan's origins is rejected origin_not_allowed" "$c1" origin_not_allowed
validate "steps(c1)[1].type = 'hover'; steps(c1)[2].delay = 1; steps(c1)[3].locator = { css: '.total' };"
lines="$(grep -c '^plan_invalid: ' <<<"$err")"
{ [ "$rc" -eq 2 ] && [ "$lines" = "3" ] && grep -qF "plan_invalid: $c1: unknown_step_type" <<<"$err" \
  && grep -qF "plan_invalid: $c1: unknown_field" <<<"$err" && grep -qF "plan_invalid: $c1: invalid_locator" <<<"$err"; } \
  && ok "AC3 a plan with three problems lists all three, one stderr line each" || ko "AC3 every problem: rc=$rc lines=$lines err='$err'"

echo "-- vague criteria (AC4)"
validate "crit(c1); p.steps_by_criterion[c2] = JSON.parse(JSON.stringify(crit(c1))); p.not_planned = [];"
want_problem "AC4 a planned vague criterion is rejected vague_criterion_planned" "$c2" vague_criterion_planned
validate "p.not_planned[0].rewrite = '';"
want_problem "AC4 a vague criterion under not_planned with an empty rewrite is rejected invalid_not_planned" "$c2" invalid_not_planned
validate "delete p.not_planned[0].rewrite;"
want_problem "AC4 a vague criterion under not_planned with no rewrite is rejected invalid_not_planned" "$c2" invalid_not_planned
validate "p.not_planned[0].reason = 'side_effect_not_observable';"
want_problem "AC4 a vague criterion not_planned under another reason is rejected invalid_not_planned" "$c2" invalid_not_planned
validate "p.not_planned.push({ ...p.not_planned[0] });"
want_problem "a criterion listed twice under not_planned is rejected invalid_not_planned" "$c2" invalid_not_planned
validate "p.not_planned.push({ id: c3, reason: 'side_effect_not_observable', detail: 'no counter' });"
want_problem "a criterion both planned and not_planned is rejected invalid_not_planned" "$c3" invalid_not_planned
validate "p.not_planned.push({ id: 'c-111111111111', reason: 'exploration_budget' });"
want_problem "a not_planned id that is not in criteria.json is rejected invalid_not_planned" "c-111111111111" invalid_not_planned
validate "p.not_planned[0].reason = 'too_hard';"
want_problem "an unknown not_planned reason is rejected invalid_not_planned" "$c2" invalid_not_planned
validate "delete p.steps_by_criterion[c3]; p.not_planned.push({ id: c3, reason: 'side_effect_not_observable', detail: 'looked at /mail and /outbox; the send is an email no page lists' });"
[ "$rc" -eq 0 ] && ok "a negative criterion under not_planned side_effect_not_observable with a detail (no rewrite needed) is accepted" || ko "side_effect_not_observable: rc=$rc err='$err'"
validate "delete p.steps_by_criterion[c3]; p.not_planned.push({ id: c3, reason: 'side_effect_not_observable' });"
want_problem "side_effect_not_observable with no detail is rejected invalid_not_planned" "$c3" invalid_not_planned
validate "delete p.steps_by_criterion[c3]; p.not_planned.push({ id: c3, reason: 'side_effect_not_observable', detail: ' ' });"
want_problem "side_effect_not_observable with a blank detail is rejected invalid_not_planned" "$c3" invalid_not_planned

echo "-- negative criteria (AC12)"
validate "steps(c3).splice(1, 1);"
want_problem "AC12 a negative criterion with no read before its first action is rejected negative_without_baseline" "$c3" negative_without_baseline
validate "steps(c3).splice(3, 2, { type: 'read', property: 'count', locator: { text: 'Sent' } }, { type: 'expect', op: 'equals', value: 0 });"
want_problem "AC12 a negative whose final check is read count + expect equals 0 is rejected negative_absence_only" "$c3" negative_absence_only
validate "steps(c3).splice(3, 2, { type: 'wait_for', locator: { role: 'button', name: 'Send' }, state: 'hidden' });"
want_problem "AC12 a negative whose last check is wait_for hidden is rejected negative_absence_only" "$c3" negative_absence_only
validate "crit(c1).polarity = 'negative'; steps(c1).splice(1, 0, { type: 'read', property: 'text', locator: { testid: 'total' } });"
[ "$rc" -eq 0 ] && ok "AC12 a negative with a baseline read and a value check is accepted" || ko "AC12 negative ok: rc=$rc err='$err'"
validate "steps(c3).splice(0, 5, { type: 'goto', url: 'http://localhost:4100/sent' }, { type: 'read', property: 'count', locator: { role: 'row' } }, { type: 'goto', url: 'http://localhost:4100/mail' }, { type: 'click', locator: { role: 'button', name: 'Save draft' } }, { type: 'goto', url: 'http://localhost:4100/sent' }, { type: 'read', property: 'count', locator: { role: 'row' } }, { type: 'expect', op: 'changed_from', value: false });"
[ "$rc" -eq 0 ] && ok "a negative that reads its baseline on another page, acts, then goes back and reads again is accepted (the prompt's cross-page shape)" || ko "cross-page negative: rc=$rc err='$err'"

echo "-- absent, and an absence hidden in a lookahead"
validate "steps(c1)[4] = { type: 'expect', op: 'absent', value: '14-day' };"
[ "$rc" -eq 0 ] && ok "expect absent with a non-blank text is accepted" || ko "absent ok: rc=$rc err='$err'"
validate "steps(c1)[4] = { type: 'expect', op: 'absent', value: ' ' };"
want_problem "expect absent with a blank text is rejected existence_only_expect" "$c1" existence_only_expect
validate "steps(c1)[4] = { type: 'expect', op: 'absent', value: 3 };"
want_problem "expect absent with a number is rejected plan_schema_violation" "$c1" plan_schema_violation
validate "steps(c1)[4] = { type: 'expect', op: 'matches', value: '^(?![\\\\s\\\\S]*14-day)[\\\\s\\\\S]+\$' };"
want_problem "a final matches with a whole-text negative lookahead (the 0.11.2 tuning shape) is rejected existence_only_expect" "$c1" existence_only_expect
validate "steps(c1).splice(4, 0, { type: 'expect', op: 'matches', value: '^(?!.*card).+\$' });"
want_problem "an earlier expect with a whole-text negative lookahead is rejected too" "$c1" existence_only_expect
validate "steps(c1)[4] = { type: 'expect', op: 'matches', value: '^(?!0)\\\\d+\$' };"
[ "$rc" -eq 0 ] && ok "a format lookahead (^(?!0)\\d+\$: no leading zero) is accepted" || ko "format lookahead: rc=$rc err='$err'"

echo "-- at_load reads"
AT_LOAD="crit(c1).steps = [{ type: 'goto', url: 'http://localhost:4100/slow' }, { type: 'read', property: 'text', locator: { testid: 'price' }, at_load: true }, { type: 'expect', op: 'equals', value: 'pending' }];"
validate "$AT_LOAD"
[ "$rc" -eq 0 ] && ok "a read at_load before any action, in a positive criterion, checked with equals, is accepted" || ko "at_load ok: rc=$rc err='$err'"
validate "steps(c1)[3].at_load = true;"
want_problem "a read at_load after an action (click, fill) is rejected at_load_misused" "$c1" at_load_misused
validate "$AT_LOAD crit(c1).polarity = 'negative';"
want_problem "a read at_load in a negative criterion is rejected at_load_misused" "$c1" at_load_misused
validate "$AT_LOAD steps(c1).push({ type: 'read', property: 'text', locator: { testid: 'price' }, at_load: true }, { type: 'expect', op: 'changed_from', value: false });"
want_problem "an at_load read checked with changed_from is rejected at_load_misused" "$c1" at_load_misused
validate "$AT_LOAD steps(c1)[1].at_load = 'yes';"
want_problem "at_load that is not a boolean is rejected plan_schema_violation" "$c1" plan_schema_violation

echo "-- interpretation, polarity, assumptions, coverage, criteria_sha256 (AC13)"
validate "delete crit(c1).interpretation;"
want_problem "AC13 a planned criterion with no interpretation is rejected missing_interpretation" "$c1" missing_interpretation
validate "crit(c1).interpretation = '  ';"
want_problem "AC13 a blank interpretation is rejected missing_interpretation" "$c1" missing_interpretation
validate "delete crit(c1).polarity;"
want_problem "AC13 a planned criterion with no polarity is rejected missing_polarity" "$c1" missing_polarity
validate "crit(c1).polarity = 'neutral';"
want_problem "AC13 polarity other than positive/negative is rejected missing_polarity" "$c1" missing_polarity
for a in 'undefined' '"none"' '[{ text: "x" }]' '[{ text: "x", material: "yes" }]' '[{ text: "", material: true }]' '[{ text: "x", material: true, why: 1 }]'; do
  validate "crit(c1).unverified_assumptions = $a;"
  want_problem "AC13 unverified_assumptions = $a is rejected invalid_assumptions" "$c1" invalid_assumptions
done
validate "delete p.steps_by_criterion[c3];"
want_problem "AC13 a criterion neither planned nor not_planned is rejected criterion_unaccounted" "$c3" criterion_unaccounted
validate "p.steps_by_criterion['c-000000000000'] = crit(c1);"
want_problem "a planned id that is not in criteria.json is rejected criterion_unaccounted" "c-000000000000" criterion_unaccounted
validate "p.criteria_sha256 = '0'.repeat(64);"
want_problem "AC13 a criteria_sha256 that is not criteria.json's is rejected criteria_sha_mismatch" "(plan)" criteria_sha_mismatch
validate "p.target = 'cli'; p.extra = 1;"
{ [ "$rc" -eq 2 ] && grep -qF 'plan_invalid: (plan): plan_schema_violation' <<<"$err" && grep -qF 'plan_invalid: (plan): unknown_field' <<<"$err"; } \
  && ok "a target other than web and an unknown top-level key are both rejected" || ko "plan shape: rc=$rc err='$err'"

echo "-- inputs"
printf '{"schema_version":1,' > "$TMP/bad-plan.json"; cp "$TMP/criteria.json" "$TMP/criteria-beside.json"
out="$(cd "$R" && bash "$CLI" plan --validate "$TMP/bad-plan.json" --criteria "$TMP/criteria-beside.json" 2>&1 </dev/null)"; rc=$?
{ [ "$rc" -eq 2 ] && grep -qF 'plan_invalid: (plan): plan_schema_violation' <<<"$out"; } \
  && ok "malformed plan JSON exits 2 plan_invalid (with --criteria naming criteria.json)" || ko "bad JSON: rc=$rc out='$out'"
mkdir -p "$TMP/lonely"; cp "$dir/plan.json" "$TMP/lonely/plan.json"
out="$(cd "$R" && bash "$CLI" plan --validate "$TMP/lonely/plan.json" 2>&1 </dev/null)"; rc=$?
{ [ "$rc" -eq 2 ] && grep -qF 'criteria_not_found' <<<"$out"; } && ok "no criteria.json beside the plan: exit 2 criteria_not_found" || ko "no criteria: rc=$rc out='$out'"
validate ''
mv "$R/selvedge.json" "$TMP/selvedge.json.aside"
out="$(cd "$R" && bash "$CLI" plan --validate "$dir/plan.json" 2>&1 </dev/null)"; rc=$?
mv "$TMP/selvedge.json.aside" "$R/selvedge.json"
{ [ "$rc" -eq 2 ] && grep -qF 'config_absent' <<<"$out"; } && ok "no selvedge.json: exit 2 config_absent (origins are never assumed)" || ko "no config: rc=$rc out='$out'"
out="$(cd "$R" && bash "$CLI" plan --frobnicate 2>&1 </dev/null)"; rc=$?
[ "$rc" -eq 2 ] && ok "an unknown plan command exits 2" || ko "unknown plan command: rc=$rc out='$out'"

echo "-- validateSteps: the snapshot prefix mode, no config"
out="$(node_eval '
const cfg = { origins: ["http://localhost:4100"] };
const goto = { type: "goto", url: "http://localhost:4100/" };
const click = { type: "click", locator: { role: "button", name: "Open cart" } };
const codes = (steps, o) => S.validateSteps(steps, o).map((p) => p.code).join(",");
const r = {
  ok: codes([goto, click], { config: cfg, prefix: true }),
  read: codes([goto, { type: "read", property: "url" }], { config: cfg, prefix: true }),
  expect: codes([goto, { type: "expect", op: "equals", value: "x" }], { config: cfg, prefix: true }),
  fifteen: codes([goto, ...Array(14).fill(click)], { config: cfg, prefix: true }),
  sixteen: codes([goto, ...Array(15).fill(click)], { config: cfg, prefix: true }),
  noconfig: codes([goto], { prefix: true }),
  readidx: S.validateSteps([goto, click, { type: "read", property: "url" }], { config: cfg, prefix: true })[0].index,
};
console.log(JSON.stringify(r));')"
[ "$out" = '{"ok":"","read":"prefix_step_not_allowed","expect":"prefix_step_not_allowed","fifteen":"","sixteen":"prefix_too_long","noconfig":"origin_not_allowed","readidx":2}' ] \
  && ok "prefix mode: read/expect rejected prefix_step_not_allowed (0-based index), 15 steps ok, 16 prefix_too_long, no config allows no goto" || ko "prefix mode: $out"

echo "-- {{NAME}} placeholders"
out="$(SHOP_USER='alice$&' node_eval '
const steps = [{ type: "fill", locator: { label: "User" }, value: "{{SHOP_USER}}" }, { type: "click", locator: { text: "{{SHOP_USER}}" } }];
const res = S.resolvePlaceholders(steps, process.env);
let unset;
try { S.resolvePlaceholders([{ type: "fill", locator: { label: "P" }, value: "{{NOPE_A}}-{{NOPE_B}}" }], {}); unset = "no throw"; }
catch (e) { unset = [e.reason, e.blocked, (e.names || []).join("+")].join("|"); }
console.log(JSON.stringify([res[0].value, res[1].locator.text, steps[0].value, unset, S.validateSteps(steps, { config: { origins: [] } }).length]));')"
[ "$out" = '["alice$&","{{SHOP_USER}}","{{SHOP_USER}}","placeholder_unset|true|NOPE_A+NOPE_B",0]' ] \
  && ok "resolvePlaceholders fills a fill value from env (literally), leaves the input untouched, and an unset name throws BLOCKED placeholder_unset naming it" || ko "placeholders: $out"

echo "-- the schema equals the validator's frozen sets (AC20)"
out="$(node_eval '
const s = JSON.parse((await import("node:fs")).readFileSync(process.env.SELVEDGE_PLAN_SCHEMA, "utf8"));
const eq = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
const d = s.$defs;
const checks = {
  draft: s["$schema"] === "https://json-schema.org/draft/2020-12/schema",
  closed: s.additionalProperties === false,
  keys: eq(Object.keys(s.properties), V.PLAN_KEYS) && eq(s.required, V.PLAN_REQUIRED_KEYS),
  target: s.properties.target.const === "web",
  types: JSON.stringify(d.step_type.enum) === JSON.stringify(S.STEP_TYPES),
  oneOf: eq(d.step.oneOf.map((r) => r.$ref), S.STEP_TYPES.map((t) => "#/$defs/step_" + t)),
  fields: S.STEP_TYPES.every((t) => {
    const x = d["step_" + t]; const f = S.STEP_FIELDS[t];
    return x.additionalProperties === false && x.properties.type.const === t
      && eq(Object.keys(x.properties).filter((k) => k !== "type"), [...f.required, ...f.optional])
      && eq(x.required, ["type", ...f.required]);
  }),
  locators: eq(d.locator.oneOf.map((r) => r.$ref), Object.keys(S.LOCATOR_FORMS).map((k) => "#/$defs/locator_" + k))
    && Object.entries(S.LOCATOR_FORMS).every(([k, f]) => eq(Object.keys(d["locator_" + k].properties), f)
      && d["locator_" + k].additionalProperties === false && eq(d["locator_" + k].required, [k])),
  ops: eq(d.step_expect.properties.op.enum, S.EXPECT_OPS),
  states: eq(d.step_wait_for.properties.state.enum, S.WAIT_STATES),
  read: eq(d.step_read.properties.property.anyOf[0].enum, S.READ_PROPERTIES) && d.step_read.properties.property.anyOf[1].pattern === S.READ_ATTRIBUTE_PATTERN
    && d.step_read.properties.property.anyOf[2].pattern === S.READ_RESPONSE_JSON_PATTERN && d.step_read.properties.property.anyOf[3].pattern === S.READ_COOKIE_PATTERN
    && d.step_read.properties.property.anyOf[4].pattern === S.READ_RESPONSE_HEADER_PATTERN && d.step_read.properties.property.anyOf[5].pattern === S.READ_COOKIE_ATTRIBUTE_PATTERN
    && d.step_read.properties.property.anyOf[6].pattern === S.READ_RESPONSE_JSON_EACH_PATTERN && d.step_read.properties.property.anyOf[7].pattern === S.READ_RESPONSE_JSON_LENGTH_PATTERN
    && d.step_read.properties.property.anyOf.length === 8,
  request: eq(d.step_request.properties.method.enum, S.REQUEST_METHODS),
  criterion: eq(Object.keys(d.criterion_plan.properties), V.CRITERION_PLAN_KEYS) && d.criterion_plan.additionalProperties === false
    && eq(d.criterion_plan.properties.polarity.enum, V.POLARITIES)
    && eq(Object.keys(d.assumption.properties), V.ASSUMPTION_KEYS) && d.assumption.additionalProperties === false,
  not_planned: eq(Object.keys(d.not_planned.properties), V.NOT_PLANNED_KEYS) && eq(d.not_planned.properties.reason.enum, V.NOT_PLANNED_REASONS)
    && d.not_planned.additionalProperties === false,
};
const bad = Object.entries(checks).filter(([, v]) => v !== true).map(([k]) => k);
console.log(bad.length ? "mismatch " + bad.join(",") : "yes");')"
[ "$out" = "yes" ] && ok "AC20 plan.schema.json (draft 2020-12, closed, target const web): step-type enum, per-type field names, locator forms, ops, states, read properties and criterion/not_planned keys equal plan-steps.mjs / plan-validate.mjs" || ko "AC20 schema/validator equality: $out"

echo "-- README lists every PLAN_PROBLEMS code (AC20)"
out="$(node_eval '
const md = (await import("node:fs")).readFileSync(process.env.SELVEDGE_README, "utf8");
const listed = [...md.matchAll(/^- `([a-z_]+)` — /gm)].map((m) => m[1]);
const missing = V.PLAN_PROBLEMS.filter((c) => !listed.includes(c));
console.log(Object.isFrozen(V.PLAN_PROBLEMS) && missing.length === 0 ? "yes" : "missing " + missing.join(","));')"
[ "$out" = "yes" ] && ok "AC20 every PLAN_PROBLEMS code has a bullet in README's plan-lint problems list" || ko "AC20 README PLAN_PROBLEMS: $out"
out="$(node_eval '
const fs = await import("node:fs");
const codes = new Set(V.PLAN_PROBLEMS);
const src = ["plan-steps.mjs", "plan-validate.mjs", "plan.mjs"].map((f) => fs.readFileSync(process.env.SELVEDGE_LIB + "/" + f, "utf8")).join("\n");
const used = [...src.matchAll(/(?:add\([^,\x27()]*,\s*|add\(|code: )\x27([a-z_]+)\x27/g)].map((m) => m[1]);
const unknown = [...new Set(used)].filter((c) => !codes.has(c));
console.log(used.length && unknown.length === 0 ? "yes" : "unknown " + unknown.join(",") + " used " + used.length);' 2>&1)"
[ "$out" = "yes" ] && ok "every problem code the lint emits is a PLAN_PROBLEMS code" || ko "emitted codes: $out"

echo "-- no reason is a string literal (REASONS only) (AC20)"
reasons="$(node_eval 'console.log(Object.keys(E.REASONS).join("|"))')"
hits="$(cd "$SELVEDGE_LIB" && grep -nE "['\"\`]($reasons)['\"\`]" plan-steps.mjs plan-validate.mjs plan.mjs)"
{ [ -n "$reasons" ] && [ -z "$hits" ]; } && ok "plan-steps.mjs, plan-validate.mjs and plan.mjs name no reason as a string literal" || ko "string-literal reasons: $hits"

echo "test-plan-validate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
