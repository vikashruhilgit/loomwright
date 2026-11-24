// stats.mjs — the eval harness's pure arithmetic: the rates, their exact Clopper-Pearson 95%
// intervals, the per-defect and per-app groups, the repeatability flips, the Phase 3 gate and the
// two-revision rule. No I/O: selvedge/eval/harness.mjs reads and writes; this file only computes.
//
// Scoring (selvedge/eval/README.md, "The eval harness"):
//   abstention  = (BLOCKED + NOT_VERIFIABLE) / every criterion scored
//   false-PASS  = PASS on a known-FAIL case / every known-FAIL case
//   false-FAIL  = FAIL on a known-PASS case / every known-PASS case
// A criterion whose evidence class is model-judged is counted in its own section and never in
// those numerators or denominators. Only plan 1's first run feeds the main rates; the replays of
// plan 1 and the extra plans feed the two repeatability numbers only.
//
// Gate (a held-out report only): `met` iff the known-FAIL denominator is at least
// FLOORS.held_out_fail (from eval-set.mjs, never restated) AND the false-PASS point estimate is at
// most GATE.false_pass_max AND abstention is at most GATE.abstention_max. Two-revision rule: when
// the latest held-out reports (each at or above the floor) of GATE.revisions_before_review distinct
// engine versions all miss the gate, the owner stops and runs the section 8 review early.
//
// Node >= 18, standard library only.
import { FLOORS } from './eval-set.mjs';

export const GATE = Object.freeze({ false_pass_max: 0.05, abstention_max: 0.2, revisions_before_review: 2 });
export const ALPHA = 0.05;
export const VERDICT_VALUES = Object.freeze(['PASS', 'FAIL', 'BLOCKED', 'NOT_VERIFIABLE']);
export const GATE_SET = 'held-out';
const ABSTAIN = new Set(['BLOCKED', 'NOT_VERIFIABLE']);
const MODEL_JUDGED = 'model-judged';

// ln Γ(x), Lanczos approximation (g = 7, n = 9); accurate to ~1e-15 for x > 0.
const LANCZOS = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
function lnGamma(x) {
  if (x < 0.5) return Math.log(Math.PI / Math.sin(Math.PI * x)) - lnGamma(1 - x);
  const z = x - 1;
  let a = LANCZOS[0];
  const t = z + 7.5;
  for (let i = 1; i < 9; i++) a += LANCZOS[i] / (z + i);
  return 0.5 * Math.log(2 * Math.PI) + (z + 0.5) * Math.log(t) - t + Math.log(a);
}

// Continued fraction for the incomplete beta (modified Lentz).
function betaCf(x, a, b) {
  const TINY = 1e-300;
  let c = 1;
  let d = 1 - ((a + b) * x) / (a + 1);
  if (Math.abs(d) < TINY) d = TINY;
  d = 1 / d;
  let h = d;
  for (let m = 1; m <= 1000; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((a - 1 + m2) * (a + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < TINY) d = TINY;
    c = 1 + aa / c;
    if (Math.abs(c) < TINY) c = TINY;
    d = 1 / d;
    h *= d * c;
    aa = (-(a + m) * (a + b + m) * x) / ((a + m2) * (a + 1 + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < TINY) d = TINY;
    c = 1 + aa / c;
    if (Math.abs(c) < TINY) c = TINY;
    d = 1 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1) < 1e-15) break;
  }
  return h;
}

// The regularized incomplete beta I_x(a, b).
export function incBeta(x, a, b) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const front = Math.exp(lnGamma(a + b) - lnGamma(a) - lnGamma(b) + a * Math.log(x) + b * Math.log(1 - x));
  return x < (a + 1) / (a + b + 2) ? (front * betaCf(x, a, b)) / a : 1 - (front * betaCf(1 - x, b, a)) / b;
}

// The p-quantile of Beta(a, b), by bisection (I_x is increasing in x).
function betaQuantile(p, a, b) {
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (incBeta(mid, a, b) < p) lo = mid;
    else hi = mid;
  }
  return (lo + hi) / 2;
}

// clopperPearson(k, n) → {lower, upper}: the exact two-sided (1 - alpha) interval for k successes
// in n trials. lower = 0 when k = 0, upper = 1 when k = n; both null when n = 0 (no rate).
export function clopperPearson(k, n, alpha = ALPHA) {
  if (!(Number.isInteger(k) && Number.isInteger(n) && k >= 0 && n >= 0 && k <= n)) throw new RangeError(`clopperPearson: need integers 0 <= k <= n, got k=${k}, n=${n}`);
  if (n === 0) return { lower: null, upper: null };
  const lower = k === 0 ? 0 : betaQuantile(alpha / 2, k, n - k + 1);
  const upper = k === n ? 1 : betaQuantile(1 - alpha / 2, k + 1, n - k);
  return { lower, upper };
}

const round6 = (v) => (v === null ? null : Math.round(v * 1e6) / 1e6);

// rate(k, n) → {numerator, denominator, rate, ci95: {lower, upper}} (rate and bounds null when n = 0).
export function rate(k, n) {
  const ci = clopperPearson(k, n);
  return { numerator: k, denominator: n, rate: n === 0 ? null : round6(k / n), ci95: { lower: round6(ci.lower), upper: round6(ci.upper) } };
}

// The app name harness.mjs gives every variant target, planted or not; use a case's `source` to know which.
export const SAMPLE_APP = 'sample-app';

// withoutSplit(group row) → the row without its known_fail / known_pass counts.
export function withoutSplit(g) {
  const { known_fail: _f, known_pass: _p, ...rest } = g;
  return rest;
}

function emptyTally() {
  return { criteria: 0, known_fail: 0, known_pass: 0, pass_on_known_fail: 0, fail_on_known_pass: 0, abstained: 0 };
}

// One scored row into a tally: row = {known: 'PASS' | 'FAIL', verdict}.
function addRow(t, row) {
  t.criteria += 1;
  if (row.known === 'FAIL') t.known_fail += 1;
  if (row.known === 'PASS') t.known_pass += 1;
  if (row.known === 'FAIL' && row.verdict === 'PASS') t.pass_on_known_fail += 1;
  if (row.known === 'PASS' && row.verdict === 'FAIL') t.fail_on_known_pass += 1;
  if (ABSTAIN.has(row.verdict)) t.abstained += 1;
}

// flips(perCase) → [{case_id, verdicts}] for every case whose verdicts are not all equal, sorted by
// case_id. perCase: [{case_id, verdicts: [...]}] (one verdict per repeat, in order).
export function flips(perCase) {
  return perCase
    .filter((c) => new Set(c.verdicts).size > 1)
    .map((c) => ({ case_id: c.case_id, verdicts: [...c.verdicts] }))
    .sort((a, b) => (a.case_id < b.case_id ? -1 : a.case_id > b.case_id ? 1 : 0));
}

function repeatability(cases, series) {
  const perCase = cases.map((c) => ({ case_id: c.case_id, verdicts: series.map((s) => (s[c.case_id] ? s[c.case_id].verdict : 'MISSING')) }));
  const f = flips(perCase);
  return { repeats: series.length, cases: cases.length, flipped: f.length, flips: f };
}

// buildReport(input) → the report object written to results.json.
//   input.set        'held-out' | 'tuning'
//   input.engine     {selvedge_version, planner_model}
//   input.ts         ISO time
//   input.cases      [{case_id, group_id, source, app, known: 'PASS' | 'FAIL'}] — `source` 'planted'
//                    marks a planted case. `known` is used here and
//                    never written to the report
//   input.plans      [plan 1, plan 2, …], each {<case_id>: {verdict, evidence_class, reason}}: the
//                    first run of each fresh plan
//   input.replays    [replay 1, …] of plan 1, same shape
//   input.not_replayed [case_id, …] whose plan 1 never froze, so it was never replayed: left out of
//                    the runner series (a missing replay is not a flip); the main rates still count it
//   input.runs       [{target, plan, run, planner_tokens, duration_ms}] (tokens and duration per run)
export function buildReport(input) {
  const { set, engine, ts, cases, plans, replays = [], not_replayed: notReplayed = [], runs = [] } = input;
  const skipReplay = new Set(notReplayed);
  const main = plans[0];
  const tally = emptyTally();
  const modelJudged = emptyTally();
  const counts = Object.fromEntries(VERDICT_VALUES.map((v) => [v, 0]));
  const reasons = {};
  const byGroup = new Map();
  const byApp = new Map();
  const plantedGroups = new Set(cases.filter((c) => c.source === 'planted').map((c) => c.group_id));
  let budgetExceeded = 0;
  for (const c of cases) {
    const v = main[c.case_id];
    if (!v) throw new Error(`buildReport: case ${c.case_id} has no verdict in plan 1's run`);
    const row = { known: c.known, verdict: v.verdict };
    if (v.evidence_class === MODEL_JUDGED) {
      addRow(modelJudged, row);
      continue;
    }
    addRow(tally, row);
    counts[v.verdict] = (counts[v.verdict] || 0) + 1;
    if (ABSTAIN.has(v.verdict)) {
      const key = `${v.verdict} ${v.reason || '(no reason)'}`;
      reasons[key] = (reasons[key] || 0) + 1;
      if (v.reason === 'budget_exceeded') budgetExceeded += 1;
    }
    if (!byGroup.has(c.group_id)) byGroup.set(c.group_id, emptyTally());
    addRow(byGroup.get(c.group_id), row);
    if (!byApp.has(c.app)) byApp.set(c.app, emptyTally());
    addRow(byApp.get(c.app), row);
  }
  const sortedReasons = Object.fromEntries(Object.keys(reasons).sort().map((k) => [k, reasons[k]]));
  const grouped = (m, key) => [...m.keys()].sort().map((k) => ({ [key]: k, ...m.get(k) }));
  // A held-out planted group's answers live only in the outside folder, and its criteria are
  // committed in held-out/cases.json, so its FAIL/PASS split would narrow every answer: drop it.
  // Real-bug and non-defect answers can be worked out from committed data, so they keep theirs.
  // per_app is left whole: the planted cases' total split is already public, as the false-PASS
  // denominator less the real-bug and non-defect known-FAIL count, both derivable from committed data.
  const perGroup = grouped(byGroup, 'group_id').map((g) => (set === 'held-out' && plantedGroups.has(g.group_id) ? withoutSplit(g) : g));
  const totals = runs.reduce((a, r) => ({ planner_tokens: a.planner_tokens + (r.planner_tokens || 0), duration_ms: a.duration_ms + (r.duration_ms || 0) }), { planner_tokens: 0, duration_ms: 0 });
  const report = {
    set,
    engine: { selvedge_version: engine.selvedge_version, planner_model: engine.planner_model },
    ts,
    cases: cases.length,
    rates: {
      false_pass: rate(tally.pass_on_known_fail, tally.known_fail),
      false_fail: rate(tally.fail_on_known_pass, tally.known_pass),
      abstention: rate(tally.abstained, tally.criteria),
    },
    verdict_counts: counts,
    abstention_reasons: sortedReasons,
    budget_exceeded: budgetExceeded,
    model_judged: modelJudged,
    per_group: perGroup,
    per_app: grouped(byApp, 'app'),
    repeatability: {
      runner: repeatability(cases.filter((c) => !skipReplay.has(c.case_id)), [main, ...replays]),
      planner: repeatability(cases, plans),
    },
    runs,
    totals,
  };
  report.gate = gateVerdict(report);
  return report;
}

// gateVerdict(report) → {verdict: 'met' | 'not met', failed: [...]} for a held-out report, null for
// any other set (a tuning report never feeds the gate).
export function gateVerdict(report) {
  if (!report || report.set !== GATE_SET) return null;
  const { false_pass: fp, abstention: ab } = report.rates;
  const failed = [];
  if (fp.denominator < FLOORS.held_out_fail) failed.push(`known-FAIL denominator ${fp.denominator} is below the floor ${FLOORS.held_out_fail} (FLOORS.held_out_fail)`);
  if (fp.rate === null || fp.rate > GATE.false_pass_max) failed.push(`false-PASS ${fp.rate === null ? 'has no rate' : fp.rate.toFixed(4)} > ${GATE.false_pass_max}`);
  if (ab.rate === null || ab.rate > GATE.abstention_max) failed.push(`abstention ${ab.rate === null ? 'has no rate' : ab.rate.toFixed(4)} > ${GATE.abstention_max}`);
  return { verdict: failed.length ? 'not met' : 'met', failed };
}

// atFloor(report) — the report's known-FAIL denominator reaches FLOORS.held_out_fail.
export function atFloor(report) {
  return report.rates.false_pass.denominator >= FLOORS.held_out_fail;
}

// revisionRule(reports) → {stop, versions}: stop is true when the latest held-out report (at or
// above the floor) of each of the last GATE.revisions_before_review distinct engine versions misses
// the gate. Tuning reports and below-floor held-out reports never count.
export function revisionRule(reports) {
  const latest = new Map();
  for (const r of reports) {
    if (r.set !== GATE_SET || !atFloor(r)) continue;
    const v = r.engine.selvedge_version;
    latest.delete(v);
    latest.set(v, r);
  }
  const lastN = [...latest.values()].slice(-GATE.revisions_before_review);
  const stop = lastN.length >= GATE.revisions_before_review && lastN.every((r) => gateVerdict(r).verdict === 'not met');
  return { stop, versions: lastN.map((r) => r.engine.selvedge_version) };
}
