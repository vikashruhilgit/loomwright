// plan.mjs — `selvedge plan`, run by selvedge/bin/selvedge.
//
//   selvedge plan <criteria.json> [--base <ref>]           init + planner + validate + freeze
//   selvedge plan --init <criteria.json>                   a new run folder holding criteria.json
//   selvedge plan --validate <plan.json> [--criteria <criteria.json>] [--base <ref>]
//   selvedge plan --freeze <run-dir> [--base <ref>]        validate, stamp plan_revision, hash
//
// A run folder is `<repo root>/.selvedge/runs/<run-id>/` (plan-runs.mjs lists its files). The bare
// form creates one, writes planner-input.json (the TESTABLE criteria only: a vague one never reaches
// the planner; env_names, the auth.env names a {{NAME}} may use), runs the planner (plan-planner.mjs: SELVEDGE_PLANNER, else `claude -p`), lists every
// vague criterion under not_planned with criterion_not_testable and its rewrite, then freezes.
//
// A freeze ALWAYS runs the plan lint (plan-validate.mjs) first: an invalid plan is never hashed (no
// plan.sha256, exit 2 plan_invalid with one stderr line per problem). The bare form first sets aside
// the planner's criteria whose own steps broke the lint (setAsideInvalid): each moves to
// not_planned with criterion_plan_invalid and its problem lines as the detail, so one bad criterion
// no longer stops the rest from freezing. A problem with the plan as a whole (its origins, its
// criteria_sha256, a criterion unaccounted for, a bad not_planned entry) still fails the freeze.
// --freeze and --validate stay strict: a plan written by hand is fixed by hand. A folder that already holds
// plan.sha256 is already_frozen and nothing in it is written. Every re-plan of the same criteria
// goes in a new folder and gets the next plan_revision.
//
// --validate runs the static lint against the run folder's criteria.json (the file beside the plan
// unless --criteria names another) and selvedge.json (the working tree, or the committed
// <ref>:selvedge.json with --base, exactly as `env check --base`; under a planner, SELVEDGE_BASE
// pins it as it pins snapshot's). The plan may be /dev/stdin (a planner linting its own plan). Every problem is one stderr line
// `plan_invalid: <criterion id | (plan)>: <code>: <detail>`; any problem exits 2.
//
// stdout: --init, --freeze and the bare form print the run folder's path (one line); --validate
// prints `plan valid: <file>`. Everything else goes to stderr.
//
// Exit codes (00-plan D7): 0 ok, 1 an operation failed, 2 usage error, BLOCKED or a named reason,
// 3 NOT_VERIFIABLE. Every reason comes from REASONS in env-config.mjs.
//
// Node >= 18, standard library only.
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { EnvError, REASONS, UsageError, isMain, loadConfig, parseCliArgs, repoRoot } from './env-config.mjs';
import { classifyTestability, criteriaSha256, readCriteriaFile } from './criteria.mjs';
import { PLAN_SCHEMA_VERSION, PLAN_SCOPE, PLAN_TARGETS, problemLine, validatePlan } from './plan-validate.mjs';
import { RUN_FILES, assertNotFrozen, freezeRun, initRun, prettyJson } from './plan-runs.mjs';
import { PLANNER_TOKEN_BUDGET_ENV, runPlanner } from './plan-planner.mjs';
import { pinnedBase, snapshotBudget } from './snapshot.mjs';

const LIB_DIR = path.dirname(fileURLToPath(import.meta.url));
// This CLI (what a planner calls for `snapshot`) and the default planner's fixed prompt.
export const SELVEDGE_BIN = path.resolve(LIB_DIR, '..', 'bin', 'selvedge');
export const PLANNER_PROMPT = path.resolve(LIB_DIR, '..', 'prompts', 'planner.md');
export const PLANNER_INPUT_SCHEMA_VERSION = 1;

const USAGE = `Usage: selvedge plan <command>

Commands:
  <criteria.json> [--base <ref>]
                           plan in one go: --init, the planner, --validate, --freeze. Prints the
                           run folder (.selvedge/runs/<run-id>/). The planner is SELVEDGE_PLANNER
                           (a /bin/sh -c command) or, unset, claude -p with prompts/planner.md.
  --init <criteria.json>   create a run folder holding a copy of criteria.json; print its path
  --validate <plan.json> [--criteria <criteria.json>] [--base <ref>]
                           lint a plan: the PASS rule (a value read after the last action),
                           negative baselines, interpretation/polarity/assumptions, criterion
                           coverage, criteria_sha256, and every step's type, fields, locator,
                           content and goto origin. Lists every problem, one stderr line each.
                           criteria.json defaults to the file beside the plan.
  --freeze <run-dir> [--base <ref>]
                           lint the folder's plan.json, stamp plan_revision, write it, and record
                           plan.sha256, freeze.json and a .selvedge/runs.jsonl line. A frozen
                           folder is never written again (already_frozen).

Environment: SELVEDGE_PLANNER, SELVEDGE_PLANNER_MODEL (default sonnet),
SELVEDGE_PLANNER_TOKEN_BUDGET (recorded in freeze.json), SELVEDGE_SNAPSHOT_BUDGET (snapshot calls
per run folder, default 20).

Exit codes: 0 ok, 1 an operation failed, 2 usage error, BLOCKED or a named reason, 3 NOT_VERIFIABLE.`;

function err(line) {
  process.stderr.write(`selvedge plan: ${line}\n`);
}

// A plan_invalid failure carrying its problem list (printed one line each).
class PlanInvalid extends Error {
  constructor(problems, where) {
    super(`${problems.length} problem(s) in ${where}`);
    this.problems = problems;
  }
}

// The plan file's JSON, or a plan_invalid problem list when it cannot be read or parsed.
function readPlan(file) {
  let raw;
  try {
    raw = readFileSync(file, 'utf8');
  } catch (e) {
    return { problems: [{ id: PLAN_SCOPE, code: 'plan_schema_violation', detail: `cannot read ${file}: ${e && e.code ? e.code : e && e.message}` }] };
  }
  try {
    return { plan: JSON.parse(raw) };
  } catch (e) {
    return { problems: [{ id: PLAN_SCOPE, code: 'plan_schema_violation', detail: `${file} is not valid JSON: ${e && e.message}` }] };
  }
}

// SELVEDGE_PLANNER_TOKEN_BUDGET: a whole number of tokens, or null when unset. Recorded, not
// enforced here (enforcing it is the runner's budget_exceeded).
export function plannerTokenBudget(env = process.env) {
  const raw = env[PLANNER_TOKEN_BUDGET_ENV];
  if (raw === undefined || raw === '') return null;
  if (!/^[0-9]+$/.test(raw)) throw new UsageError(`${PLANNER_TOKEN_BUDGET_ENV} must be a whole number of tokens (got ${JSON.stringify(raw)})`);
  return Number(raw);
}

// The criteria split by the testability pre-check: vague ones are never sent to a planner.
export function splitByTestability(criteria) {
  const testable = [];
  const vague = [];
  for (const c of criteria) {
    const r = classifyTestability(c.text);
    if (r.testability === 'vague') vague.push({ id: c.id, rewrite: r.rewrite });
    else testable.push(c);
  }
  return { testable, vague };
}

// Lists every vague criterion the plan does not account for under not_planned, with
// criterion_not_testable and its rewrite. A vague criterion the planner DID plan is left as it is:
// the lint rejects it (vague_criterion_planned).
export function addVagueNotPlanned(plan, vague) {
  if (plan === null || typeof plan !== 'object' || Array.isArray(plan)) return plan;
  if (!('not_planned' in plan)) plan.not_planned = [];
  if (!Array.isArray(plan.not_planned)) return plan;
  const planned = plan.steps_by_criterion && typeof plan.steps_by_criterion === 'object' ? Object.keys(plan.steps_by_criterion) : [];
  const listed = new Set(plan.not_planned.map((np) => (np && typeof np === 'object' ? np.id : undefined)));
  for (const v of vague) {
    if (planned.includes(v.id) || listed.has(v.id)) continue;
    plan.not_planned.push({ id: v.id, reason: REASONS.criterion_not_testable, rewrite: v.rewrite });
  }
  return plan;
}

// The problem codes that belong to one planned criterion's own entry (its steps, interpretation,
// polarity, assumptions): every PLAN_PROBLEMS code but these plan-wide ones.
const PLAN_WIDE_CODES = Object.freeze(['criterion_unaccounted', 'criteria_sha_mismatch', 'invalid_not_planned']);
export const SET_ASIDE_DETAIL_MAX = 2000;

// setAsideInvalid(plan, problems, criteria) → { plan, setAside: [{id, reason}] } or null. When every
// problem names a criterion planned under steps_by_criterion with a code of its own entry, each such
// criterion moves to not_planned with criterion_plan_invalid and its problem lines (capped) as the
// detail; else null (the plan fails as a whole). A criterion whose TEXT is vague (`criteria`, the
// criteria.json list, by classifyTestability) moves under criterion_not_testable with its rewrite
// instead, the one not_planned reason the lint accepts for a vague criterion.
export function setAsideInvalid(plan, problems, criteria = []) {
  if (!problems.length || plan === null || typeof plan !== 'object' || Array.isArray(plan)) return null;
  const sbc = plan.steps_by_criterion;
  if (sbc === null || typeof sbc !== 'object' || Array.isArray(sbc) || !Array.isArray(plan.not_planned ?? [])) return null;
  const own = (p) => p.id !== PLAN_SCOPE && Object.prototype.hasOwnProperty.call(sbc, p.id) && !PLAN_WIDE_CODES.includes(p.code);
  if (!problems.every(own)) return null;
  const ids = [...new Set(problems.map((p) => p.id))];
  if (!Array.isArray(plan.not_planned)) plan.not_planned = [];
  const textById = new Map((Array.isArray(criteria) ? criteria : []).map((c) => [c.id, c.text]));
  const setAside = [];
  for (const id of ids) {
    delete sbc[id];
    const text = textById.get(id);
    const t = text === undefined ? null : classifyTestability(text);
    if (t && t.testability === 'vague') {
      plan.not_planned.push({ id, reason: REASONS.criterion_not_testable, rewrite: t.rewrite });
      setAside.push({ id, reason: REASONS.criterion_not_testable });
      continue;
    }
    const lines = problems.filter((p) => p.id === id).map((p) => `${p.code}${p.detail ? `: ${p.detail}` : ''}`).join('; ');
    plan.not_planned.push({ id, reason: REASONS.criterion_plan_invalid, detail: lines.length > SET_ASIDE_DETAIL_MAX ? `${lines.slice(0, SET_ASIDE_DETAIL_MAX - 1)}…` : lines });
    setAside.push({ id, reason: REASONS.criterion_plan_invalid });
  }
  return { plan, setAside };
}

// Lint, then freeze. The lint runs before anything is hashed; an invalid plan throws PlanInvalid.
function freezeChecked({ root, runDir, plan, criteria, config, env }) {
  const problems = validatePlan(plan, { criteria, config });
  if (problems.length) throw new PlanInvalid(problems, path.join(runDir, RUN_FILES.plan));
  return freezeRun({
    root,
    runDir,
    plan,
    criteriaSha256: criteriaSha256(criteria.criteria),
    plannerTokenBudget: plannerTokenBudget(env),
  });
}

function reportFreeze(runDir, rec) {
  process.stdout.write(`${runDir}\n`);
  const tokens = rec.planner_tokens ? `${rec.planner_tokens.input_tokens} in / ${rec.planner_tokens.output_tokens} out` : 'not reported';
  err(`frozen: plan.json sha256 ${rec.plan_sha256}, plan_revision ${rec.plan_revision}, plan_time_actions ${rec.plan_time_actions}, planner tokens ${tokens}`);
}

function cmdValidate(args) {
  const { flags, positional } = parseCliArgs(args, { values: ['validate', 'criteria', 'base'] });
  if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
  const file = flags.validate;
  const criteriaFile = flags.criteria || path.join(path.dirname(file), 'criteria.json');
  const criteria = readCriteriaFile(criteriaFile);
  // a planner's lint reads the allowlist its plan is frozen against (SELVEDGE_BASE), as its snapshots do
  const { config, source } = loadConfig({ base: pinnedBase(flags) });
  const read = readPlan(file);
  const problems = read.problems || validatePlan(read.plan, { criteria, config });
  if (problems.length) {
    for (const p of problems) process.stderr.write(`${problemLine(p)}\n`);
    err(`${problems.length} problem(s) in ${file} (criteria: ${criteriaFile}; config source: ${source})`);
    return 2;
  }
  process.stdout.write(`plan valid: ${file}\n`);
  err(`criteria: ${criteriaFile}; config source: ${source}`);
  return 0;
}

function cmdInit(args) {
  const { flags, positional } = parseCliArgs(args, { values: ['init'] });
  if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
  readCriteriaFile(flags.init); // only a valid criteria.json is copied
  const root = repoRoot() || process.cwd();
  const { runDir } = initRun({ root, criteriaFile: flags.init });
  process.stdout.write(`${runDir}\n`);
  err(`run folder created with ${RUN_FILES.criteria}; write ${RUN_FILES.plan} there, then: selvedge plan --freeze ${runDir}`);
  return 0;
}

function cmdFreeze(args, env) {
  const { flags, positional } = parseCliArgs(args, { values: ['freeze', 'base'] });
  if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
  const runDir = path.resolve(flags.freeze);
  if (!existsSync(runDir) || !statSync(runDir).isDirectory()) throw new UsageError(`no run folder at ${runDir}`);
  assertNotFrozen(runDir); // before anything is read: a frozen folder is never written again
  plannerTokenBudget(env);
  const criteria = readCriteriaFile(path.join(runDir, RUN_FILES.criteria));
  const { config, root } = loadConfig({ base: flags.base });
  const read = readPlan(path.join(runDir, RUN_FILES.plan));
  if (read.problems) throw new PlanInvalid(read.problems, path.join(runDir, RUN_FILES.plan));
  reportFreeze(runDir, freezeChecked({ root, runDir, plan: read.plan, criteria, config, env }));
  return 0;
}

function cmdPlan(args, env) {
  const { flags, positional } = parseCliArgs(args, { values: ['base'] });
  if (positional.length !== 1) throw new UsageError(positional.length ? `unexpected argument: ${positional[1]}` : 'plan needs a <criteria.json>');
  const criteriaFile = positional[0];
  // Everything that can refuse the call is checked before a folder exists.
  const criteria = readCriteriaFile(criteriaFile);
  const { config, root, source } = loadConfig({ base: flags.base });
  const snapshots = snapshotBudget(env);
  const tokenBudget = plannerTokenBudget(env);

  const { runDir } = initRun({ root, criteriaFile });
  err(`run folder ${runDir} (config source: ${source})`);
  try {
    const { testable, vague } = splitByTestability(criteria.criteria);
    const sha = criteriaSha256(criteria.criteria);
    for (const v of vague) err(`${v.id} is vague: not sent to the planner, listed under not_planned (${REASONS.criterion_not_testable})`);
    let plan;
    if (testable.length === 0) {
      // Nothing a planner could plan: no planner call; every criterion is not_planned.
      plan = { schema_version: PLAN_SCHEMA_VERSION, target: PLAN_TARGETS[0], criteria_sha256: sha, origins: [], steps_by_criterion: {} };
      writeFileSync(path.join(runDir, RUN_FILES.plan), prettyJson(plan));
      err('no testable criterion: the planner was not run');
    } else {
      const input = {
        schema_version: PLANNER_INPUT_SCHEMA_VERSION,
        criteria_sha256: sha,
        origins: [...config.origins],
        criteria: testable,
        selvedge_bin: SELVEDGE_BIN,
        run_dir: runDir,
        snapshot_budget: snapshots,
        token_budget: tokenBudget,
        // the {{NAME}}s a run can resolve: selvedge.json's auth.env names (never their values)
        env_names: config.auth && Array.isArray(config.auth.env) ? [...config.auth.env] : [],
      };
      writeFileSync(path.join(runDir, RUN_FILES.plannerInput), prettyJson(input));
      const { planner } = runPlanner({ root, runDir, base: flags.base, env, selvedgeBin: SELVEDGE_BIN, promptFile: PLANNER_PROMPT });
      err(`planner: ${planner}`);
      const read = readPlan(path.join(runDir, RUN_FILES.plan));
      if (read.problems) throw new PlanInvalid(read.problems, path.join(runDir, RUN_FILES.plan));
      plan = read.plan;
    }
    addVagueNotPlanned(plan, vague);
    const problems = validatePlan(plan, { criteria, config });
    const aside = setAsideInvalid(plan, problems, criteria.criteria);
    if (aside) for (const p of problems) process.stderr.write(`${problemLine(p)}\n`);
    // the set-aside lines only once the rest froze: a freeze that still fails says nothing froze
    const rec = freezeChecked({ root, runDir, plan, criteria, config, env });
    if (aside) for (const a of aside.setAside) err(`${a.id}: set aside under not_planned (${a.reason}); the other criteria froze`);
    reportFreeze(runDir, rec);
    return 0;
  } catch (e) {
    err(`nothing was frozen in ${runDir}; fix ${RUN_FILES.plan} there and run: selvedge plan --freeze ${runDir}`);
    throw e;
  }
}

async function main(argv, env = process.env) {
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= 18)) {
    err(`needs Node.js >= 18 (this is ${process.versions.node})`);
    return 1;
  }
  const has = (flag) => argv.some((a) => a === flag || a.startsWith(`${flag}=`));
  try {
    if (argv.length === 0) {
      process.stderr.write(`${USAGE}\n`);
      return 2;
    }
    if (['help', '-h', '--help'].includes(argv[0])) {
      process.stdout.write(`${USAGE}\n`);
      return 0;
    }
    const modes = ['--validate', '--init', '--freeze'].filter(has);
    if (modes.length > 1) throw new UsageError(`${modes.join(' and ')} cannot be combined`);
    if (has('--validate')) return cmdValidate(argv);
    if (has('--init')) return cmdInit(argv);
    if (has('--freeze')) return cmdFreeze(argv, env);
    return cmdPlan(argv, env);
  } catch (e) {
    if (e instanceof UsageError) {
      err(e.message);
      process.stderr.write(`\n${USAGE}\n`);
      return 2;
    }
    if (e instanceof PlanInvalid) {
      for (const p of e.problems) process.stderr.write(`${problemLine(p)}\n`);
      err(`${REASONS.plan_invalid}: ${e.message}; nothing was hashed`);
      return 2;
    }
    if (e instanceof EnvError) {
      if (e.blocked) {
        process.stdout.write(`BLOCKED ${e.reason}\n`);
      }
      err(`${e.reason}: ${e.message}`);
      return 2;
    }
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
