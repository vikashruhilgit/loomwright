// verdict.mjs — `selvedge verdict <run-dir>` and deriveVerdict, run by selvedge/bin/selvedge.
//
//   selvedge verdict <run-dir>
//
// Turns a run folder's evidence.jsonl (read only through readEvidence, runner/evidence.mjs) and its
// plan.json into one verdict per criterion, written to <run-dir>/verdict.json
// (selvedge/schemas/verdict.schema.json). Nothing else decides a verdict: `run` calls deriveVerdict
// once its evidence is closed, and `selvedge verdict` re-derives the same file from disk. Neither
// is a model; both read the files, never a runner's memory. `verdict` appends nothing to
// runs.jsonl (the run line is `run`'s, one per run).
//
// The rule per planned criterion (00-plan D7), first match wins:
//   no criterion_end line (the run stopped)            BLOCKED run_interrupted
//   criterion_end outcome not_planned                   NOT_VERIFIABLE <its reason>
//   any other outcome but completed                     BLOCKED <its reason> (step_failed, …)
//   completed, the final read empty ("" or none)        NOT_VERIFIABLE no_value_read — even when
//                                                       the expect is `equals ""`
//   completed, no expect result recorded                BLOCKED run_interrupted
//   completed, the final expect mismatched              FAIL (the stable wait ran before it)
//   completed, matched, a `material: true` assumption   NOT_VERIFIABLE material_assumption
//   completed, matched                                  PASS
// A criterion under plan.json's not_planned is NOT_VERIFIABLE with the plan's reason.
//
// The run's verdict is the highest by precedence FAIL > BLOCKED > NOT_VERIFIABLE > PASS, and so is
// the exit code: 1 / 2 / 3 / 0 (exitCodeFor). A run with no criterion is NOT_VERIFIABLE.
//
// prior_revisions is the only value read from <repo root>/.selvedge/runs.jsonl: for each earlier
// revision of the same criteria (its `event: "freeze"` lines with the same criteria_sha256 and a
// lower plan_revision), the verdict of that revision's own run line (`event: "run"`, replay_of
// null; the first one when there are several), or null when it never ran; ascending by revision.
// It never changes a criterion's verdict.
//
// Refused before anything is written (exit 2, the reason on stderr): no evidence.jsonl or evidence
// that cannot be trusted (evidence_missing), no plan.json (not_frozen), a plan.json that is not a
// plan object (plan_invalid), a plan.json whose sha256 is not run_start's plan_sha256
// (plan_modified: the verdict would be derived from a plan the run did not execute).
//
// Every reason comes from REASONS in env-config.mjs.
//
// Node >= 18, standard library only.
import { createHash } from 'node:crypto';
import { readFileSync, renameSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS, UsageError, isMain, parseCliArgs, repoRoot } from './env-config.mjs';
import { FREEZE_EVENT, RUNS_DIR, RUN_FILES, SELVEDGE_DIR, prettyJson, readRunsLog } from './plan-runs.mjs';
import { CRITERION_OUTCOMES, DATA_STATES, STEP_OUTCOMES, readEvidence } from './runner/evidence.mjs';

export const VERDICT_SCHEMA_VERSION = 1;
export const VERDICT_FILE = 'verdict.json';
// The runs.jsonl event `run` appends (one line per run); prior_revisions reads it.
export const RUN_EVENT = 'run';

// The four verdicts, frozen (value == key). selvedge/schemas/verdict.schema.json declares the same
// names; selvedge/tests/test-verdict.sh asserts the two are equal.
export const VERDICTS = Object.freeze({
  PASS: 'PASS',
  FAIL: 'FAIL',
  BLOCKED: 'BLOCKED',
  NOT_VERIFIABLE: 'NOT_VERIFIABLE',
});

// How a verdict's value was obtained (00-plan D9). The web runner reads values through Playwright:
// structured-read. The other two are reserved for later adapters and never PASS a web criterion.
export const EVIDENCE_CLASSES = Object.freeze({
  structured_read: 'structured-read',
  in_process_assert: 'in-process-assert',
  model_judged: 'model-judged',
});

// D7 precedence, highest first, and each verdict's exit code.
export const VERDICT_PRECEDENCE = Object.freeze([VERDICTS.FAIL, VERDICTS.BLOCKED, VERDICTS.NOT_VERIFIABLE, VERDICTS.PASS]);
export const VERDICT_EXIT_CODES = Object.freeze({
  [VERDICTS.FAIL]: 1,
  [VERDICTS.BLOCKED]: 2,
  [VERDICTS.NOT_VERIFIABLE]: 3,
  [VERDICTS.PASS]: 0,
});

const USAGE = `Usage: selvedge verdict <run-dir>

Derive PASS / FAIL / BLOCKED / NOT_VERIFIABLE for every criterion of a run folder from its
evidence.jsonl and plan.json only (no model), and write <run-dir>/verdict.json. Re-running it
re-derives the same file and appends nothing to .selvedge/runs.jsonl.

stdout: one line per criterion, \`<VERDICT> [<reason>] <criterion-id>\`, then
\`verdict <VERDICT> <path to verdict.json>\`.

Exit codes (precedence when several apply): 1 any FAIL, else 2 any BLOCKED (or a usage error:
evidence_missing, not_frozen, plan_invalid, plan_modified), else 3 any NOT_VERIFIABLE, else 0.`;

function err(line) {
  process.stderr.write(`selvedge verdict: ${line}\n`);
}

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

// overallVerdict(verdicts) → the highest by precedence; NOT_VERIFIABLE for an empty list (nothing
// was verified). An unknown verdict is an Error.
export function overallVerdict(verdicts) {
  const list = [...verdicts];
  for (const v of list) if (!Object.values(VERDICTS).includes(v)) throw new Error(`not a verdict: ${JSON.stringify(v)}`);
  if (list.length === 0) return VERDICTS.NOT_VERIFIABLE;
  return VERDICT_PRECEDENCE.find((v) => list.includes(v));
}

// exitCodeFor(verdicts) → 1 any FAIL, else 2 any BLOCKED, else 3 any NOT_VERIFIABLE, else 0.
export function exitCodeFor(verdicts) {
  return VERDICT_EXIT_CODES[overallVerdict(verdicts)];
}

// countVerdicts(verdicts) → { PASS, FAIL, BLOCKED, NOT_VERIFIABLE } counts (every key present).
export function countVerdicts(verdicts) {
  const counts = Object.fromEntries(Object.values(VERDICTS).map((v) => [v, 0]));
  for (const v of verdicts) counts[v] += 1;
  return counts;
}

// The repo root whose .selvedge/runs.jsonl holds the folder's history: the folder's own
// <root>/.selvedge/runs/<run-id> layout when it has it, else the git top level (or null).
function rootOfRunDir(runDir) {
  const runs = path.dirname(path.resolve(runDir));
  const selvedge = path.dirname(runs);
  if (path.basename(runs) === RUNS_DIR && path.basename(selvedge) === SELVEDGE_DIR) return path.dirname(selvedge);
  return repoRoot(runDir);
}

// priorRevisions(root, criteriaSha256, revision) → [{revision, verdict}] (header).
export function priorRevisions(root, criteriaSha256, revision) {
  if (!root || !Number.isInteger(revision)) return [];
  const { entries } = readRunsLog(root);
  const earlier = new Set();
  for (const e of entries) {
    if (e.event === FREEZE_EVENT && e.criteria_sha256 === criteriaSha256 && Number.isInteger(e.plan_revision) && e.plan_revision < revision) {
      earlier.add(e.plan_revision);
    }
  }
  return [...earlier].sort((a, b) => a - b).map((r) => {
    const own = entries.find((e) => e.event === RUN_EVENT && e.criteria_sha256 === criteriaSha256 && e.plan_revision === r && e.replay_of === null);
    return { revision: r, verdict: own && Object.values(VERDICTS).includes(own.verdict) ? own.verdict : null };
  });
}

const isEmptyRead = (v) => v === null || v === undefined || (typeof v === 'string' && v.trim() === '');
const findLast = (list, pred) => {
  for (let i = list.length - 1; i >= 0; i -= 1) if (pred(list[i])) return list[i];
  return null;
};

// The plan's final expect as { op, value }, or null.
function plannedExpect(steps) {
  const e = findLast(Array.isArray(steps) ? steps : [], (s) => isPlainObject(s) && s.type === 'expect');
  return e ? { op: e.op, value: e.value } : null;
}

// One planned criterion's verdict.json entry from its plan entry and its evidence lines.
function judgePlanned(cp, stepLines, end) {
  const lastRead = findLast(stepLines, (s) => s.type === 'read');
  const lastExpect = findLast(stepLines, (s) => s.type === 'expect');
  const assumptions = Array.isArray(cp.unverified_assumptions) ? cp.unverified_assumptions : [];
  const entry = {
    verdict: null,
    evidence_class: EVIDENCE_CLASSES.structured_read,
    read_value: lastRead ? lastRead.value : null,
    matched: lastExpect ? lastExpect.outcome === STEP_OUTCOMES.matched : null,
    expected: plannedExpect(cp.steps),
    reason: null,
    failed_step: end ? end.failed_step : null,
    interpretation: typeof cp.interpretation === 'string' ? cp.interpretation : null,
    unverified_assumptions: assumptions,
    steps: stepLines.map((s) => ({ step: s.step, type: s.type, outcome: s.outcome, duration_ms: s.duration_ms })),
  };
  const set = (verdict, reason = null) => Object.assign(entry, { verdict, reason });
  if (!end) return set(VERDICTS.BLOCKED, REASONS.run_interrupted);
  if (end.outcome === CRITERION_OUTCOMES.not_planned) return set(VERDICTS.NOT_VERIFIABLE, end.reason);
  if (end.outcome !== CRITERION_OUTCOMES.completed) return set(VERDICTS.BLOCKED, end.reason);
  if (isEmptyRead(entry.read_value)) return set(VERDICTS.NOT_VERIFIABLE, REASONS.no_value_read);
  if (entry.matched === null) return set(VERDICTS.BLOCKED, REASONS.run_interrupted);
  if (entry.matched === false) return set(VERDICTS.FAIL);
  if (assumptions.some((a) => isPlainObject(a) && a.material === true)) return set(VERDICTS.NOT_VERIFIABLE, REASONS.material_assumption);
  return set(VERDICTS.PASS);
}

function judgeNotPlanned(np) {
  return {
    verdict: VERDICTS.NOT_VERIFIABLE,
    evidence_class: EVIDENCE_CLASSES.structured_read,
    read_value: null,
    matched: null,
    expected: null,
    reason: np.reason,
    failed_step: null,
    interpretation: null,
    unverified_assumptions: [],
    steps: [],
  };
}

// Reads and checks plan.json: { plan, sha256 }.
function readPlan(runDir) {
  const file = path.join(runDir, RUN_FILES.plan);
  let bytes;
  try {
    bytes = readFileSync(file);
  } catch (e) {
    if (e && e.code === 'ENOENT') throw new EnvError(REASONS.not_frozen, `no ${RUN_FILES.plan} in ${runDir}; nothing was planned or frozen there`);
    throw e;
  }
  let plan;
  try {
    plan = JSON.parse(bytes.toString('utf8'));
  } catch (e) {
    throw new EnvError(REASONS.plan_invalid, `${file} is not valid JSON: ${e && e.message}`);
  }
  const notPlanned = isPlainObject(plan) && plan.not_planned !== undefined ? plan.not_planned : [];
  if (!isPlainObject(plan) || !isPlainObject(plan.steps_by_criterion) || !Array.isArray(notPlanned)
    || !Object.values(plan.steps_by_criterion).every(isPlainObject) || !notPlanned.every((np) => isPlainObject(np) && typeof np.id === 'string')) {
    throw new EnvError(REASONS.plan_invalid, `${file} is not a plan (steps_by_criterion object, not_planned list)`);
  }
  return { plan, notPlanned, sha256: createHash('sha256').update(bytes).digest('hex') };
}

// deriveVerdict(runDir, { root }) → { verdict, overall, counts, exitCode, file }.
// Reads evidence.jsonl and plan.json (and runs.jsonl for prior_revisions only), writes
// <runDir>/verdict.json (`verdict` is what it holds) and returns the run's overall verdict, the
// per-verdict counts and the exit code. `root` defaults to the folder's repo root. Throws EnvError
// (evidence_missing, not_frozen, plan_invalid, plan_modified) before anything is written.
export function deriveVerdict(runDir, { root } = {}) {
  const evidence = readEvidence(runDir);
  const { plan, notPlanned, sha256 } = readPlan(runDir);
  const rs = evidence.runStart;
  if (sha256 !== rs.plan_sha256) {
    throw new EnvError(
      REASONS.plan_modified,
      `${path.join(runDir, RUN_FILES.plan)} has sha256 ${sha256}, but the run executed ${rs.plan_sha256}; no verdict is derived from a plan the run did not execute`,
    );
  }
  const planned = plan.steps_by_criterion;
  for (const id of new Set([...evidence.steps.map((s) => s.criterion), ...evidence.ends.keys()])) {
    if (!(id in planned) && !notPlanned.some((np) => np.id === id)) {
      throw new EnvError(REASONS.evidence_missing, `${evidence.file} names criterion ${id}, which ${RUN_FILES.plan} does not hold; no verdict is derived from it`);
    }
  }

  const criteria = {};
  for (const [id, cp] of Object.entries(planned)) {
    criteria[id] = judgePlanned(cp, evidence.steps.filter((s) => s.criterion === id), evidence.ends.get(id));
  }
  for (const np of notPlanned) if (!(np.id in criteria)) criteria[np.id] = judgeNotPlanned(np);

  const planRevision = Number.isInteger(plan.plan_revision) ? plan.plan_revision : null;
  const runsRootDir = root === undefined ? rootOfRunDir(runDir) : root;
  const verdict = {
    schema_version: VERDICT_SCHEMA_VERSION,
    target: plan.target,
    plan_sha256: rs.plan_sha256,
    playwright_version: rs.playwright_version,
    plan_revision: planRevision,
    prior_revisions: priorRevisions(runsRootDir, plan.criteria_sha256, planRevision),
    replay_of: rs.replay_of,
    data_state: rs.data_state,
    hooks_run: rs.hooks_run,
  };
  if (rs.data_state === DATA_STATES.unmanaged) verdict.plan_time_actions = rs.plan_time_actions;
  verdict.criteria = criteria;

  const list = Object.values(criteria).map((c) => c.verdict);
  const file = path.join(runDir, VERDICT_FILE);
  // Whole or not at all: a temp name in the same folder, then a rename.
  const tmp = `${file}.tmp-${process.pid}`;
  writeFileSync(tmp, prettyJson(verdict));
  renameSync(tmp, file);
  return { verdict, overall: overallVerdict(list), counts: countVerdicts(list), exitCode: exitCodeFor(list), file };
}

// ---- CLI ---------------------------------------------------------------------------------------
function cmdVerdict(argv) {
  const { positional } = parseCliArgs(argv);
  if (positional.length !== 1) throw new UsageError(positional.length === 0 ? 'a <run-dir> is required' : `one <run-dir> only (got ${positional.length})`);
  const runDir = positional[0];
  let isDir = false;
  try {
    isDir = statSync(runDir).isDirectory();
  } catch {
    isDir = false;
  }
  if (!isDir) throw new UsageError(`${runDir} is not a directory`);
  const result = deriveVerdict(runDir);
  for (const [id, c] of Object.entries(result.verdict.criteria)) {
    process.stdout.write(`${c.verdict}${c.reason ? ` ${c.reason}` : ''} ${id}\n`);
  }
  process.stdout.write(`verdict ${result.overall} ${result.file}\n`);
  return result.exitCode;
}

async function main(argv) {
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= 18)) {
    err(`needs Node.js >= 18 (this is ${process.versions.node})`);
    return 1;
  }
  try {
    if (argv.length === 0) {
      process.stderr.write(`${USAGE}\n`);
      return 2;
    }
    if (['help', '-h', '--help'].includes(argv[0])) {
      process.stdout.write(`${USAGE}\n`);
      return 0;
    }
    return cmdVerdict(argv);
  } catch (e) {
    if (e instanceof UsageError) {
      err(e.message);
      process.stderr.write(`\n${USAGE}\n`);
      return 2;
    }
    if (e instanceof EnvError) {
      if (e.blocked) process.stdout.write(`BLOCKED ${e.reason}\n`);
      err(`${e.reason}: ${e.message}`);
      return 2;
    }
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
