#!/usr/bin/env bash
# test-eval-harness.sh — pins selvedge/eval/stats.mjs and selvedge/eval/harness.mjs: the Clopper-Pearson
# interval table (AC1), the gate (abstention cap AC3, false-PASS cap, the known-FAIL floor AC3b),
# model-judged kept apart (AC4), repeatability apart from the main denominators (AC5), the README
# results block and its sync check (AC6), the two-revision stop (AC8), the report schema (AC9),
# tuning never feeding the gate (AC10), a results file check-leak accepts (AC11), the manifest
# refusal that runs and writes nothing (AC2), SELVEDGE_PLANNER_TOKEN_BUDGET stripped from every
# selvedge child, target_unavailable, the work dir rules, and each harness reason token on exactly
# one code line. Every arm turns red under its row of the brief's pin-mutation table.
#
# Hermetic: a temp HOME, SELVEDGE_EVAL_HELD_OUT in a temp folder, fixture sets in temp git repos, a
# stub selvedge CLI and a stub target driver (tests/fixtures/eval-harness/); no network, no Docker,
# no browser, no model. Needs node (>= 18) and git; a missing one is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/.." && pwd)"
HARNESS="$PLUGIN_DIR/eval/harness.mjs"
STATS="$PLUGIN_DIR/eval/stats.mjs"
EVALSET="$PLUGIN_DIR/eval/eval-set.mjs"
FIX="$TESTS_DIR/fixtures/eval-harness"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-eval-harness: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

for tool in node git; do
  command -v "$tool" >/dev/null 2>&1 || { ko "$tool is not on PATH (test-eval-harness.sh needs it)"; finish; }
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-eval-harness.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export SELVEDGE_EVAL_HELD_OUT="$TMP/outside"
export SELVEDGE_EVAL_SELVEDGE_BIN="bash $FIX/stub-selvedge.sh"
export SELVEDGE_EVAL_TARGET_DRIVER="bash $FIX/stub-driver.sh"
export STUB_LOG="$TMP/stub"
export SELVEDGE_PLANNER="true" # never a real planner, even if the stub were bypassed
unset SELVEDGE_PLANNER_TOKEN_BUDGET STUB_VERDICT STUB_FLIP_CALL STUB_DRIVER_FAIL 2>/dev/null || true
SEED="harness-seed"

# The stub CLI is a command line, not a path: the harness runs it with spawn, so wrap it in a file.
printf '#!/bin/sh\nexec bash %s "$@"\n' "$FIX/stub-selvedge.sh" >"$TMP/stub-selvedge"
chmod +x "$TMP/stub-selvedge"
export SELVEDGE_EVAL_SELVEDGE_BIN="$TMP/stub-selvedge"

# h <args…> — runs the harness; sets $rc, $out, $err.
h() {
  node "$HARNESS" "$@" >"$TMP/stdout" 2>"$TMP/stderr"; rc=$?
  out="$(cat "$TMP/stdout")"; err="$(cat "$TMP/stderr")"
}
expect_fail() {
  if [ "$rc" -eq 1 ] && grep -qF -- "${3:-}" < <(grep -F -- "FAIL $2" <<<"$err"); then ok "$1"; else ko "$1 (rc=$rc, want '$2${3:+ … $3}'): $err"; fi
}
expect_ok() { if [ "$rc" -eq 0 ]; then ok "$1"; else ko "$1 (rc=$rc): $err"; fi; }
# jq_ <file> <js expr over d> — prints the expression's value (JSON for objects).
jq_() { node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); const v=(new Function("d","return ("+process.argv[2]+")"))(d); process.stdout.write(typeof v==="string"?v:JSON.stringify(v));' "$1" "$2"; }

# --- stats.mjs: AC1, AC3, AC3b, AC4, AC5, AC8, AC9, AC10 (one node script, one line per arm) -----
cat >"$TMP/stats-arms.mjs" <<'EOF'
import { pathToFileURL } from 'node:url';
const S = await import(pathToFileURL(process.env.STATS).href);
const { FLOORS } = await import(pathToFileURL(process.env.EVALSET).href);
const out = (good, label, detail = '') => console.log(`${good ? 'ok' : 'FAIL'}\t${label}${good ? '' : `\t${detail}`}`);
const f4 = (v) => (v === null ? 'null' : v.toFixed(4));

// AC1 — reference values: exact Clopper-Pearson 95% (R binom.test), not re-derived from stats.mjs.
const table = [[3, 60, '0.0104', '0.1392'], [0, 60, '0.0000', '0.0596'], [60, 60, '0.9404', '1.0000'], [0, 10, '0.0000', '0.3085'], [10, 10, '0.6915', '1.0000'], [1, 20, '0.0013', '0.2487'], [5, 100, '0.0164', '0.1128']];
for (const [k, n, lo, hi] of table) {
  const c = S.clopperPearson(k, n);
  out(f4(c.lower) === lo && f4(c.upper) === hi, `AC1 clopperPearson(${k}, ${n}) = [${lo}, ${hi}]`, `got [${f4(c.lower)}, ${f4(c.upper)}]`);
}
const r0 = S.rate(0, 0);
out(r0.rate === null && r0.ci95.lower === null, 'AC1 a rate over 0 cases has no estimate and no interval', JSON.stringify(r0));

// Fixture builder: nFail known-FAIL and nPass known-PASS cases with the given verdict counts.
let seq = 0;
const build = ({ set = 'held-out', fail = [], pass = [], version = '1.0.0', extra = {} }) => {
  const cases = [];
  const plan = {};
  const add = (known, [verdict, n, ec = 'structured-read', group = 'g-a', app = 'o/r']) => {
    for (let i = 0; i < n; i++) {
      const id = `c${++seq}`;
      cases.push({ case_id: id, group_id: group, app, known });
      plan[id] = { verdict, evidence_class: ec, reason: verdict === 'PASS' || verdict === 'FAIL' ? null : 'step_failed' };
    }
  };
  for (const x of fail) add('FAIL', x);
  for (const x of pass) add('PASS', x);
  return S.buildReport({ set, engine: { selvedge_version: version, planner_model: 'sonnet' }, ts: '2026-01-01T00:00:00Z', cases, plans: [plan], ...extra });
};

// AC3 — every criterion NOT_VERIFIABLE: false-PASS 0, gate not met on abstention.
const allNv = build({ fail: [['NOT_VERIFIABLE', 70]], pass: [['NOT_VERIFIABLE', 10]] });
out(allNv.rates.false_pass.rate === 0 && allNv.rates.abstention.rate === 1 && allNv.gate.verdict === 'not met' && allNv.gate.failed.some((f) => f.startsWith('abstention 1.0000 > 0.2')), 'AC3 all NOT_VERIFIABLE: false-PASS 0%, gate not met on abstention (100% > 20%)', JSON.stringify(allNv.gate));
// The false-PASS cap: 4 of 70 (5.7%) misses; 3 of 70 (4.3%) meets.
const fp4 = build({ fail: [['PASS', 4], ['FAIL', 66]], pass: [['PASS', 10]] });
out(fp4.gate.verdict === 'not met' && fp4.gate.failed.length === 1 && fp4.gate.failed[0].startsWith('false-PASS 0.0571 > 0.05'), 'gate: not met when false-PASS is above 5% (4 of 70)', JSON.stringify(fp4.gate));
const fp3 = build({ fail: [['PASS', 3], ['FAIL', 67]], pass: [['PASS', 10]] });
out(fp3.gate.verdict === 'met' && fp3.gate.failed.length === 0, 'gate: met at false-PASS 3 of 70 with no abstention and the floor reached', JSON.stringify(fp3.gate));
// AC3b — below FLOORS.held_out_fail (read from eval-set.mjs here, never restated).
const below = build({ fail: [['FAIL', FLOORS.held_out_fail - 1]], pass: [['PASS', 10]] });
out(below.rates.false_pass.rate === 0 && below.rates.abstention.rate === 0 && below.gate.verdict === 'not met' && below.gate.failed.length === 1 && below.gate.failed[0].includes(`below the floor ${FLOORS.held_out_fail}`), `AC3b known-FAIL ${FLOORS.held_out_fail - 1} < FLOORS.held_out_fail: not met even at 0% false-PASS and 0% abstention`, JSON.stringify(below.gate));
// AC4 — a model-judged PASS on a known-FAIL is counted apart.
const mj = build({ fail: [['FAIL', 5], ['PASS', 1, 'model-judged']], pass: [['PASS', 4]] });
out(mj.rates.false_pass.numerator === 0 && mj.rates.false_pass.denominator === 5 && mj.rates.abstention.denominator === 9 && mj.model_judged.criteria === 1 && mj.model_judged.pass_on_known_fail === 1, 'AC4 model-judged: in its own section, out of the main numerators and denominators', JSON.stringify({ rates: mj.rates, model_judged: mj.model_judged }));
// AC5 — 3 runs of plan 1 (2 replays) and 3 fresh plans; flips apart; main denominators unchanged.
{
  const cases = [{ case_id: 'x', group_id: 'g', app: 'o/r', known: 'FAIL' }, { case_id: 'y', group_id: 'g', app: 'o/r', known: 'PASS' }, { case_id: 'z', group_id: 'g', app: 'o/r', known: 'PASS' }];
  const v = (x, y, z) => ({ x: { verdict: x, evidence_class: 'structured-read' }, y: { verdict: y, evidence_class: 'structured-read' }, z: { verdict: z, evidence_class: 'structured-read' } });
  const r = S.buildReport({ set: 'held-out', engine: { selvedge_version: '1', planner_model: 'm' }, ts: 't', cases, plans: [v('FAIL', 'PASS', 'PASS'), v('FAIL', 'BLOCKED', 'PASS'), v('FAIL', 'PASS', 'PASS')], replays: [v('PASS', 'PASS', 'PASS'), v('FAIL', 'PASS', 'PASS')] });
  const R = r.repeatability;
  out(JSON.stringify(R.runner.flips) === JSON.stringify([{ case_id: 'x', verdicts: ['FAIL', 'PASS', 'FAIL'] }]) && R.runner.repeats === 3 && R.runner.flipped === 1, 'AC5 runner flips: the case whose 3 runs of one frozen plan differ, listed on its own', JSON.stringify(R.runner));
  out(JSON.stringify(R.planner.flips) === JSON.stringify([{ case_id: 'y', verdicts: ['PASS', 'BLOCKED', 'PASS'] }]) && R.planner.repeats === 3 && R.planner.flipped === 1, 'AC5 planner flips: the case whose 3 fresh plans differ, listed on its own', JSON.stringify(R.planner));
  out(r.rates.false_pass.denominator === 1 && r.rates.false_fail.denominator === 2 && r.rates.abstention.denominator === 3 && r.rates.false_pass.numerator === 0 && r.rates.abstention.numerator === 0, 'AC5 the main denominators equal the case counts, unchanged by the repeats', JSON.stringify(r.rates));
}
// AC9 — the report schema: false-FAIL with its interval, groups per defect and per app, runs.
{
  const r = build({ fail: [['FAIL', 2, 'structured-read', 'g-1', 'o/r'], ['PASS', 1, 'structured-read', 'pd-x', 'sample-app']], pass: [['FAIL', 1, 'structured-read', 'g-1', 'o/r'], ['PASS', 3, 'structured-read', 'g-2', 'o/r']], extra: { runs: [{ target: 't1', plan: 1, run: 1, planner_tokens: 120, duration_ms: 900 }, { target: 't2', plan: 1, run: 1, planner_tokens: 80, duration_ms: 100 }] } });
  const ff = r.rates.false_fail;
  out(ff && ff.numerator === 1 && ff.denominator === 4 && ff.rate === 0.25 && ff.ci95.lower !== null && ff.ci95.upper !== null, 'AC9 false-FAIL = FAIL on known-PASS / known-PASS, with numerator, denominator and interval', JSON.stringify(ff));
  const g1 = r.per_group.find((g) => g.group_id === 'g-1');
  const app = r.per_app.find((a) => a.app === 'sample-app');
  out(Array.isArray(r.per_group) && g1 && g1.known_fail === 2 && g1.fail_on_known_pass === 1 && app && app.pass_on_known_fail === 1 && r.per_app.some((a) => a.app === 'o/r'), 'AC9 groups per defect (group_id) and per app (repo, or sample-app for a variant)', JSON.stringify({ g: r.per_group, a: r.per_app }));
  out(r.runs.length === 2 && r.runs[0].planner_tokens === 120 && r.runs[0].duration_ms === 900 && r.totals.planner_tokens === 200 && r.totals.duration_ms === 1000, 'AC9 tokens and duration per run, with totals', JSON.stringify({ runs: r.runs, totals: r.totals }));
  out(!JSON.stringify(r).includes('"answer"') && !JSON.stringify(r).includes('"known"'), 'AC11 a report carries no answer and no known key', '');
}
// AC10 — a tuning report never feeds the gate or the two-revision rule.
const tun = build({ set: 'tuning', fail: [['PASS', 70]], pass: [['PASS', 10]] });
out(tun.gate === null && S.gateVerdict(tun) === null, 'AC10 a tuning report has no gate verdict', JSON.stringify(tun.gate));
const t1 = build({ set: 'tuning', fail: [['PASS', 70]], version: '1.0.0' });
const t2 = build({ set: 'tuning', fail: [['PASS', 70]], version: '1.1.0' });
out(S.revisionRule([t1, t2]).stop === false, 'AC10 two tuning reports that would miss never trigger the two-revision stop', JSON.stringify(S.revisionRule([t1, t2])));
// AC8 — two engine versions whose held-out reports (at the floor) both miss: stop.
const m1 = build({ fail: [['PASS', 10], ['FAIL', 60]], version: '1.0.0' });
const m2 = build({ fail: [['PASS', 9], ['FAIL', 61]], version: '1.1.0' });
const met = build({ fail: [['FAIL', 70]], version: '1.2.0' });
const sub = build({ fail: [['PASS', 50]], version: '1.3.0' });
const rr = S.revisionRule([m1, m2]);
out(rr.stop === true && JSON.stringify(rr.versions) === '["1.0.0","1.1.0"]', 'AC8 two revisions at the floor both miss: stop and review', JSON.stringify(rr));
out(S.revisionRule([m1]).stop === false && S.revisionRule([m1, met]).stop === false && S.revisionRule([m1, m1]).stop === false, 'AC8 one revision, a met one, or the same version twice: no stop', '');
out(S.revisionRule([m1, sub]).stop === false, 'AC8 a below-floor held-out report does not count as a revision', '');
out(S.GATE.false_pass_max === 0.05 && S.GATE.abstention_max === 0.2 && S.GATE.revisions_before_review === 2 && Object.isFrozen(S.GATE), 'GATE is frozen at the plan\'s values', JSON.stringify(S.GATE));
EOF
STATS="$STATS" EVALSET="$EVALSET" node "$TMP/stats-arms.mjs" >"$TMP/stats-arms.out" 2>&1 || ko "stats arms: the script did not finish: $(tail -n 3 "$TMP/stats-arms.out")"
while IFS="$(printf '\t')" read -r st label detail; do
  case "$st" in
    ok) ok "$label" ;;
    FAIL) ko "$label: $detail" ;;
    *) ko "stats arms: unexpected line: $st $label" ;;
  esac
done <"$TMP/stats-arms.out"

# --- a fixture set in a temp repo ------------------------------------------------------------------
B="$TMP/base"
mkdir -p "$B/selvedge/eval" "$B/selvedge/.claude-plugin" && git -C "$B" init -q
RULE="$(EVAL_MOD="$EVALSET" node --input-type=module -e "import { pathToFileURL } from 'node:url'; const M = await import(pathToFileURL(process.env.EVAL_MOD).href); process.stdout.write(M.SPLIT_RULE)")"
printf '{\n  "schema_version": 1,\n  "rule": "%s",\n  "seed": "%s"\n}\n' "$RULE" "$SEED" >"$B/selvedge/eval/split.json"
groups=""; i=0; while [ "$i" -lt 60 ]; do groups="$groups g$i"; i=$((i + 1)); done
# shellcheck disable=SC2086
sides="$(node "$EVALSET" --repo "$B" side $groups)"
GT="$(awk -F'\t' '$2 == "tuning" { print $1; exit }' <<<"$sides")"
GH="$(awk -F'\t' '$2 == "held-out" { print $1; exit }' <<<"$sides")"
[ -n "$GT" ] && [ -n "$GH" ] && ok "setup: groups $GT (tuning) and $GH (held-out)" || { ko "setup: no groups picked: $sides"; finish; }
node - "$TMP/all.json" "$B/selvedge/eval/real-bugs.json" "$GT" "$GH" "$PLUGIN_DIR/lib/criteria.mjs" <<'EOF'
const fs = require('fs');
const [out, bugs, T, H, critLib] = process.argv.slice(2);
import(require('url').pathToFileURL(critLib).href).then(({ criterionId }) => {
  const crit = (text) => ({ id: criterionId(text), text });
  const commit = (d) => ({ kind: 'commit', repo: 'o/r', sha: d.repeat(40) });
  const c = (case_id, group_id, source, text, d, answer) => ({ case_id, group_id, source, criterion: crit(text), target: commit(d), answer });
  fs.writeFileSync(out, JSON.stringify({ schema_version: 1, cases: [
    c('t-fail', T, 'real-bug', 'The total shows "12"', '3', 'FAIL'),
    c('t-pass', T, 'real-bug', 'The total shows "12"', '4', 'PASS'),
    c('t-nd', T, 'non-defect', 'The page title reads "Cart"', '4', 'PASS'),
    c('h-fail', H, 'real-bug', 'Saving shows "Saved"', '1', 'FAIL'),
    c('h-pass', H, 'real-bug', 'Saving shows "Saved"', '2', 'PASS'),
    c('h-nd', H, 'non-defect', 'The header reads "Team"', '2', 'PASS'),
  ] }, null, 2));
  const e = (pr, p, f) => ({ repo: 'o/r', pr, parent_sha: p.repeat(40), fix_sha: f.repeat(40), setup: { parent: ['npm ci'], fix: ['npm ci', 'fixture SQL (scratch DB only): SELECT 1;'] }, status: 'used', group_id: pr === 1 ? H : T });
  fs.writeFileSync(bugs, JSON.stringify({ schema_version: 1, entries: [e(1, '1', '2'), e(2, '3', '4')] }, null, 2));
});
EOF
node "$EVALSET" --repo "$B" split "$TMP/all.json" >/dev/null 2>"$TMP/split.err" && node "$EVALSET" --repo "$B" manifest write >/dev/null 2>>"$TMP/split.err" \
  && ok "setup: fixture set split, manifest written" || { ko "setup: split failed: $(cat "$TMP/split.err")"; finish; }
cp "$PLUGIN_DIR/.claude-plugin/plugin.json" "$B/selvedge/.claude-plugin/plugin.json"
printf '# fixture\n\n## Measuring Selvedge: the known-answer set\n\nThe set.\n\n## Releasing\n\nNotes.\n' >"$B/selvedge/README.md"
git -C "$B" add -A && git -C "$B" commit -qm base
VERSION="$(jq_ "$PLUGIN_DIR/.claude-plugin/plugin.json" 'd.version')"

# fresh <name> — a copy of the base repo and outside folder; sets $R, $W (a work dir) and resets the stub log.
fresh() {
  R="$TMP/$1"; W="$TMP/$1.work"; rm -rf "$R" "$R.outside" "$W" "$STUB_LOG"
  cp -R "$B" "$R"; cp -R "$TMP/outside" "$R.outside"
  export SELVEDGE_EVAL_HELD_OUT="$R.outside"
}

# --- AC2: a manifest that fails refuses before any target, writes nothing -------------------------
for mode in byte missing extra; do
  fresh "manifest-$mode"
  printf '{"schema_version": 1, "reports": []}\n' >"$R/selvedge/eval/results.json"
  cp "$R/selvedge/eval/results.json" "$TMP/results.before"; cp "$R/selvedge/README.md" "$TMP/readme.before"
  case "$mode" in
    byte) node -e 'const fs=require("fs"); const f=process.argv[1]; const b=fs.readFileSync(f); b[b.length-3]^=1; fs.writeFileSync(f,b);' "$R.outside/answers.json"; want="manifest_mismatch"; file="answers.json" ;;
    missing) rm "$R.outside/answers.json"; want="manifest_missing_file"; file="answers.json" ;;
    extra) echo stray >"$R.outside/stray.txt"; want="manifest_extra_file"; file="stray.txt" ;;
  esac
  h run --repo "$R" --set held-out --work-dir "$W"
  if [ "$rc" -eq 1 ] && grep -qF -- "$file" < <(grep -F -- "FAIL $want" <<<"$err"); then ok "AC2 run refuses on $want, naming $file"; else ko "AC2 $mode: rc=$rc err=$err"; fi
  [ ! -e "$STUB_LOG/driver.log" ] && [ ! -e "$STUB_LOG/calls.log" ] && [ ! -e "$W" ] && ok "AC2 $mode: no target brought up, no selvedge call, no work dir" || ko "AC2 $mode: something ran ($(cat "$STUB_LOG"/*.log 2>/dev/null | head -n 3))"
  cmp -s "$TMP/results.before" "$R/selvedge/eval/results.json" && cmp -s "$TMP/readme.before" "$R/selvedge/README.md" && ok "AC2 $mode: results file and README byte-identical" || ko "AC2 $mode: results file or README changed"
done

# --- a held-out run end to end (stub CLI, stub driver), with repeats ------------------------------
fresh e2e
export SELVEDGE_PLANNER_TOKEN_BUDGET=1 # set in the parent: the harness must strip it from every child
STUB_FLIP_CALL=2 h run --repo "$R" --set held-out --work-dir "$W" --planner-repeats 3 --runner-repeats 3
unset SELVEDGE_PLANNER_TOKEN_BUDGET
expect_ok "run --set held-out: exits 0 with a report"
RES="$R/selvedge/eval/results.json"
[ "$(jq_ "$RES" 'd.reports.length')" = "1" ] && [ "$(jq_ "$RES" 'd.reports[0].set')" = "held-out" ] && [ "$(jq_ "$RES" 'd.reports[0].engine.selvedge_version')" = "$VERSION" ] \
  && ok "run: one held-out report for engine $VERSION in selvedge/eval/results.json" || ko "run: unexpected results: $(cat "$RES" 2>/dev/null | head -c 400)"
[ "$(jq_ "$RES" 'd.reports[0].budget_exceeded')" = "0" ] && ! grep -q 'budget=set' "$STUB_LOG/calls.log" && grep -q '^plan budget=unset' "$STUB_LOG/calls.log" && grep -q '^run budget=unset' "$STUB_LOG/calls.log" \
  && ok "SELVEDGE_PLANNER_TOKEN_BUDGET set in the parent reaches no selvedge child: no budget_exceeded" || ko "budget stripping: $(sort "$STUB_LOG/calls.log" | uniq -c | tr '\n' ' ') report budget_exceeded=$(jq_ "$RES" 'd.reports[0].budget_exceeded')"
# 2 targets × (3 plans + 3 runs of plan 1 + 1 run each of plans 2 and 3) = 6 plan and 10 run calls.
np="$(grep -c '^plan ' "$STUB_LOG/calls.log")"; nr="$(grep -c '^run ' "$STUB_LOG/calls.log")"
[ "$np" = 6 ] && [ "$nr" = 10 ] && ok "run: 3 plans per target, plan 1 run 3 times, plans 2 and 3 once" || ko "run: $np plan and $nr run call(s)"
[ "$(grep -c '^up ' "$STUB_LOG/driver.log")" = 2 ] && [ "$(grep -c '^down ' "$STUB_LOG/driver.log")" = 2 ] && [ "$(grep -c '^stop ' "$STUB_LOG/driver.log")" = 1 ] \
  && ok "run: each target up and down once, the shared stop once" || ko "run: driver calls: $(cat "$STUB_LOG/driver.log")"
grep -q '"fixture SQL (scratch DB only): SELECT 1;"' "$W"/targets/*/target.json && ok "run: the driver gets the commit's recorded setup lines" || ko "run: no setup lines in target.json"
[ "$(jq_ "$RES" 'd.reports[0].rates.abstention.denominator')" = 3 ] && [ "$(jq_ "$RES" 'd.reports[0].rates.false_pass.denominator')" = 1 ] && [ "$(jq_ "$RES" 'd.reports[0].rates.false_pass.numerator')" = 1 ] \
  && ok "run: main denominators equal the held-out case counts (3 scored, 1 known-FAIL), repeats left out" || ko "run: rates $(jq_ "$RES" 'd.reports[0].rates')"
[ "$(jq_ "$RES" 'd.reports[0].repeatability.runner.flipped')" -ge 1 ] && [ "$(jq_ "$RES" 'Array.isArray(d.reports[0].repeatability.runner.flips) && d.reports[0].repeatability.runner.flips.every(f => typeof f.case_id === "string" && Array.isArray(f.verdicts))')" = true ] \
  && ok "run: runner flips are an array of {case_id, verdicts}" || ko "run: flips $(jq_ "$RES" 'd.reports[0].repeatability')"
[ "$(jq_ "$RES" 'd.reports[0].runs.length')" = 10 ] && [ "$(jq_ "$RES" 'd.reports[0].totals.planner_tokens')" = 720 ] && ok "run: tokens and duration per run recorded (10 runs, 720 planner tokens)" || ko "run: runs $(jq_ "$RES" 'd.reports[0].totals')"
grep -qE '^gate: not met — known-FAIL denominator 1 is below the floor' <<<"$out" && ok "run: prints the gate line (not met, below the known-FAIL floor)" || ko "run: gate line: $out"
case "$W" in "$R"/*) ko "run: the work dir is inside the repo" ;; *) [ -z "$(git -C "$R" status --porcelain -- . ':!selvedge/eval/results.json')" ] && ok "run: nothing written into the repo but the results file" || ko "run: stray files: $(git -C "$R" status --porcelain)" ;; esac

# AC11 — the committed results file passes check-leak (fixture repo).
git -C "$R" add -A && git -C "$R" commit -qm results
node "$EVALSET" --repo "$R" check-leak >/dev/null 2>"$TMP/leak.err" && ok "AC11 check-leak passes with the results file committed" || ko "AC11 check-leak: $(cat "$TMP/leak.err")"

# --resume: finished targets are kept, nothing is brought up again.
rm -f "$STUB_LOG/driver.log"
h run --repo "$R" --set held-out --work-dir "$W" --planner-repeats 3 --runner-repeats 3 --resume
expect_ok "run --resume on a finished work dir"
! grep -q '^up ' "$STUB_LOG/driver.log" 2>/dev/null && [ "$(jq_ "$RES" 'd.reports.length')" = 2 ] && ok "run --resume: no target brought up again, a second report appended" || ko "run --resume: $(cat "$STUB_LOG/driver.log" 2>/dev/null)"
h run --repo "$R" --set held-out --work-dir "$W" --planner-repeats 3 --runner-repeats 3
expect_fail "run: an existing work dir without --resume" work_dir_invalid "--resume"
h run --repo "$R" --set held-out --work-dir "$W" --planner-repeats 2 --runner-repeats 3 --resume
expect_fail "run --resume: other repeat counts than the work dir's" work_dir_invalid "another set"
h run --repo "$R" --set held-out --work-dir "$R/work"
expect_fail "run: a work dir inside the repository" work_dir_invalid "inside the repository"

# score: a finished work dir again; an unfinished one is run_incomplete.
h score --repo "$R" --work-dir "$W"
expect_ok "score: a finished work dir"
rm "$(ls -d "$W"/targets/* | head -n 1)/result.json"
h score --repo "$R" --work-dir "$W"
expect_fail "score: a work dir with a target not finished" run_incomplete "1 of 2 target(s)"

# --- target_unavailable ------------------------------------------------------------------------------
fresh unavailable
STUB_DRIVER_FAIL=1 h run --repo "$R" --set held-out --work-dir "$W"
expect_fail "run: a target the driver cannot bring up stops the run" target_unavailable "step 'npm ci'"
[ ! -e "$R/selvedge/eval/results.json" ] && ! grep -q '^plan ' "$STUB_LOG/calls.log" 2>/dev/null && ok "target_unavailable: no plan, no results written" || ko "target_unavailable: something was written or planned"

# --- AC10: a tuning run is marked tuning and never gated ------------------------------------------
fresh tuning
h run --repo "$R" --set tuning --work-dir "$W"
expect_ok "run --set tuning"
[ "$(jq_ "$R/selvedge/eval/results.json" 'd.reports[0].set')" = tuning ] && [ "$(jq_ "$R/selvedge/eval/results.json" 'd.reports[0].gate')" = null ] && grep -q '^gate: not evaluated (set tuning' <<<"$out" \
  && ok "AC10 run --set tuning: report marked set tuning, no gate verdict" || ko "AC10 tuning: $(jq_ "$R/selvedge/eval/results.json" 'd.reports[0].gate') / $out"

# --- AC6: the README block is generated from the results file and checked against it ---------------
fresh readme
cp "$TMP/e2e/selvedge/eval/results.json" "$R/selvedge/eval/results.json"
h check-readme --repo "$R"
expect_fail "check-readme: a results file and no block in the README" readme_results_out_of_sync
h readme --repo "$R"
expect_ok "readme: writes the block"
grep -qF '<!-- selvedge-eval-results:begin' "$R/selvedge/README.md" && awk '/^## Measuring Selvedge/{m=1} /^## Releasing/{m=0} m && /selvedge-eval-results:end/{f=1} END{exit !f}' "$R/selvedge/README.md" \
  && ok "readme: the block sits in the Measuring Selvedge section" || ko "readme: block not placed: $(cat "$R/selvedge/README.md")"
grep -qE '^\| false-PASS .*\| 1 / 1 \| 1\.0000 \| 0\.0250 – 1\.0000 \|$' "$R/selvedge/README.md" && grep -qF 'Phase 3 gate: **not met**' "$R/selvedge/README.md" \
  && ok "readme: shows the gate verdict and each rate with its interval" || ko "readme: block body: $(sed -n '/selvedge-eval-results:begin/,/selvedge-eval-results:end/p' "$R/selvedge/README.md")"
cp "$R/selvedge/README.md" "$TMP/readme.1"
h readme --repo "$R"
cmp -s "$TMP/readme.1" "$R/selvedge/README.md" && ok "readme: a second write changes nothing" || ko "readme: not idempotent"
h check-readme --repo "$R"
expect_ok "check-readme: the block matches the results file"
sed 's/| 1 \/ 1 | 1\.0000 |/| 0 \/ 1 | 0.0000 |/' "$TMP/readme.1" >"$R/selvedge/README.md"
h check-readme --repo "$R"
expect_fail "AC6 check-readme: a hand edit inside the block" readme_results_out_of_sync
cp "$TMP/readme.1" "$R/selvedge/README.md"
jq_ "$R/selvedge/eval/results.json" '(d.reports[d.reports.length - 1].rates.false_pass.numerator = 0, d)' >"$TMP/res2.json" && mv "$TMP/res2.json" "$R/selvedge/eval/results.json"
h check-readme --repo "$R"
expect_fail "AC6 check-readme: the results file changed and the block was not regenerated" readme_results_out_of_sync
rm "$R/selvedge/eval/results.json"
h check-readme --repo "$R"
expect_fail "check-readme: a block with no results file" readme_results_out_of_sync "does not exist"
echo '{"reports": 1}' >"$R/selvedge/eval/results.json"
h readme --repo "$R"
expect_fail "readme: a malformed results file" results_invalid
printf '{"schema_version": 1, "reports": []}\n' >"$R/selvedge/eval/results.json"
grep -v 'selvedge-eval-results:end' "$TMP/readme.1" >"$R/selvedge/README.md"
h readme --repo "$R"
expect_fail "readme: a begin marker without its end" readme_markers_missing

# --- AC8: two revisions that miss, at the floor: the stop line, and no option to loosen --------------
fresh revisions
node -e '
const fs = require("fs");
const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).reports[0];
const miss = (v) => ({ ...r, engine: { ...r.engine, selvedge_version: v }, rates: { ...r.rates, false_pass: { numerator: 9, denominator: 70, rate: 0.128571, ci95: { lower: 0.06, upper: 0.23 } } } });
fs.writeFileSync(process.argv[2], JSON.stringify({ schema_version: 1, reports: [miss("0.0.1"), miss("0.0.2")] }, null, 2));' "$TMP/e2e/selvedge/eval/results.json" "$R/selvedge/eval/results.json"
h run --repo "$R" --set held-out --work-dir "$W"
expect_ok "run with two missing revisions already in the results file"
grep -qE '^two-revision rule: .*0\.0\.1 and 0\.0\.2 .*stop and run the section 8 review now' <<<"$out" && ok "AC8 the harness prints the stop-and-review line" || ko "AC8 no stop line: $out"
grep -qiE 'raise|loosen|--abstention|--false-pass|--gate|abstention_max|override' <<<"$out$err" && ko "AC8 the output offers a way to loosen the gate: $out" || ok "AC8 the output offers no option to raise the abstention cap or loosen the gate"
grep -qiE -- '--(abstention|false-pass|gate|cap|floor)' "$HARNESS" && ko "AC8 harness.mjs has a flag that loosens the gate" || ok "AC8 harness.mjs has no flag for the cap, the gate or the floor"

# --- usage ---------------------------------------------------------------------------------------------
h run --repo "$B" --set both
[ "$rc" -eq 2 ] && ok "run: an unknown --set is a usage error" || ko "run --set both: rc=$rc"
h run --repo "$B" --set held-out --planner-repeats 0
[ "$rc" -eq 2 ] && ok "run: --planner-repeats 0 is a usage error" || ko "--planner-repeats 0: rc=$rc"

# --- each harness reason token on exactly one code line; listed in the header and eval/README.md --------
TOKENS="target_unavailable results_invalid readme_results_out_of_sync readme_markers_missing work_dir_invalid run_incomplete"
for t in $TOKENS; do
  n="$(grep -vE '^[[:space:]]*//' "$HARNESS" | grep -cE "(^|[^a-z_])${t}([^a-z_]|$)")"
  hd="$(grep -E '^//' "$HARNESS" | grep -cE "(^|[^a-z_])${t}([^a-z_]|$)")"
  r="$(grep -cF "\`$t\`" "$PLUGIN_DIR/eval/README.md")"
  [ "$n" -eq 1 ] && [ "$hd" -ge 1 ] && [ "$r" -ge 1 ] && ok "token $t: one code line, in the header, in eval/README.md" || ko "token $t: $n code line(s), header $hd, README $r"
done

# --- the real tree: the README block matches the committed results file (or neither exists) ------------
tracked="$(git -C "$REPO_ROOT" ls-files -- selvedge/eval/results.json)"
h check-readme --repo "$REPO_ROOT"
if [ -n "$tracked" ]; then
  expect_ok "check-readme: the real README block matches selvedge/eval/results.json"
else
  if [ "$rc" -eq 0 ] && ! grep -qF 'selvedge-eval-results:begin' "$PLUGIN_DIR/README.md"; then ok "check-readme: no results file committed yet, and no block in the real README"; else ko "check-readme on the real tree (no results file): rc=$rc $err"; fi
fi

finish
