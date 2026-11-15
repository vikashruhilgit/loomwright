// plan-runs.mjs — run folders, the revision count and the freeze record.
//
// A run folder is `<repo root>/.selvedge/runs/<run-id>/`, run id `<UTC YYYYMMDDTHHMMSSZ>-<6 hex>`.
// It holds:
//   criteria.json         a copy of the criteria the plan answers (written by initRun)
//   planner-input.json    what the planner was given (the testable criteria and allowed origins)
//   planner-usage.json    {"input_tokens", "output_tokens"} the planner reported, when it did
//   snapshots.jsonl       one line per `selvedge snapshot` call made for this folder
//   plan.json             the plan; rewritten once by freezeRun with `plan_revision` stamped
//   plan.sha256           `<hex>  plan.json` — the sha256 of plan.json's bytes as written. Its
//                         presence is what "frozen" means: a frozen folder is never written again.
//   freeze.json           the freeze record (below)
//
// `<repo root>/.selvedge/runs.jsonl` is the append-only audit trail across run folders. This module
// appends one line per freeze:
//   {"event":"freeze", ts, run_id, criteria_sha256, plan_sha256, plan_revision, plan_time_actions,
//    planner_tokens}
// A plan's revision is 1 + the number of `event: "freeze"` lines with the same criteria_sha256, so
// every re-plan of the same criteria is a numbered revision in its own folder (00-plan D6). The
// count is read, not locked: two freezes of the same criteria at the same moment can take the same
// number. The trail is an audit record, not a lock. Item 04 appends its own `event: "run"` lines
// and reuses nextPlanRevision / readRunsLog / runsLogPath.
//
// freezeRun never validates: its caller (plan.mjs) runs the plan lint first, and freezeRun only
// stamps, writes and hashes.
//
// Node >= 18, standard library only.
import { createHash, randomBytes } from 'node:crypto';
import { appendFileSync, copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS } from './env-config.mjs';
import { PLAN_KEYS } from './plan-validate.mjs';

export const SELVEDGE_DIR = '.selvedge';
export const RUNS_DIR = 'runs';
export const RUNS_LOG = 'runs.jsonl';
export const RUN_FILES = Object.freeze({
  criteria: 'criteria.json',
  plannerInput: 'planner-input.json',
  plannerUsage: 'planner-usage.json',
  snapshots: 'snapshots.jsonl',
  plan: 'plan.json',
  planSha: 'plan.sha256',
  freeze: 'freeze.json',
});
export const FREEZE_EVENT = 'freeze';
export const FREEZE_SCHEMA_VERSION = 1;
export const RUN_ID_PATTERN = '^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}$';

function sha256Hex(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

// JSON as every selvedge file writes it: 2 spaces, a trailing newline.
export function prettyJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

// Write a file whole or not at all (a temp name in the same folder, then a rename).
function writeAtomic(file, text) {
  const tmp = `${file}.tmp-${process.pid}`;
  writeFileSync(tmp, text);
  renameSync(tmp, file);
}

export function runsRoot(root) {
  return path.join(root, SELVEDGE_DIR, RUNS_DIR);
}

export function runsLogPath(root) {
  return path.join(root, SELVEDGE_DIR, RUNS_LOG);
}

// newRunId(now) → `<UTC YYYYMMDDTHHMMSSZ>-<6 random hex>`.
export function newRunId(now = new Date()) {
  const stamp = now.toISOString().replace(/\.\d{3}Z$/, 'Z').replace(/[-:]/g, '');
  return `${stamp}-${randomBytes(3).toString('hex')}`;
}

// initRun({ root, criteriaFile }) → { runId, runDir }. Creates a new run folder and copies the
// (already validated) criteria.json into it byte for byte. Never reuses a folder.
export function initRun({ root, criteriaFile, now = new Date() }) {
  const parent = runsRoot(root);
  mkdirSync(parent, { recursive: true });
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const runId = newRunId(now);
    const runDir = path.join(parent, runId);
    try {
      mkdirSync(runDir); // not recursive: an existing folder is EEXIST, never shared
    } catch (e) {
      if (e && e.code === 'EEXIST') continue;
      throw e;
    }
    copyFileSync(criteriaFile, path.join(runDir, RUN_FILES.criteria));
    return { runId, runDir };
  }
  throw new Error(`could not create a new run folder under ${parent}`);
}

// readRunsLog(root) → { entries, unparsable }: every JSON-object line of runs.jsonl (none when the
// file is absent) and the count of lines that are not one.
export function readRunsLog(root) {
  let raw;
  try {
    raw = readFileSync(runsLogPath(root), 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') return { entries: [], unparsable: 0 };
    throw e;
  }
  const entries = [];
  let unparsable = 0;
  for (const line of raw.split('\n')) {
    if (line.trim() === '') continue;
    try {
      const v = JSON.parse(line);
      if (v !== null && typeof v === 'object' && !Array.isArray(v)) entries.push(v);
      else unparsable += 1;
    } catch {
      unparsable += 1;
    }
  }
  return { entries, unparsable };
}

// nextPlanRevision(root, criteriaSha256) → 1 + the freeze lines in runs.jsonl for those criteria.
export function nextPlanRevision(root, criteriaSha256) {
  const { entries } = readRunsLog(root);
  return 1 + entries.filter((e) => e.event === FREEZE_EVENT && e.criteria_sha256 === criteriaSha256).length;
}

// The sum of plan_time_actions over the run folder's snapshots.jsonl (0 when there is none).
export function sumPlanTimeActions(runDir) {
  let raw;
  try {
    raw = readFileSync(path.join(runDir, RUN_FILES.snapshots), 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') return 0;
    throw e;
  }
  let sum = 0;
  for (const line of raw.split('\n')) {
    if (line.trim() === '') continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch {
      continue;
    }
    const n = rec && rec.plan_time_actions;
    if (Number.isInteger(n) && n > 0) sum += n;
  }
  return sum;
}

// The tokens the planner reported in planner-usage.json: { input_tokens, output_tokens } (whole
// numbers), or null when there is no such file. A file that is not that shape is an Error.
export function readPlannerUsage(runDir) {
  const file = path.join(runDir, RUN_FILES.plannerUsage);
  let raw;
  try {
    raw = readFileSync(file, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') return null;
    throw e;
  }
  let u;
  try {
    u = JSON.parse(raw);
  } catch (e) {
    throw new Error(`${file} is not valid JSON: ${e && e.message}`);
  }
  const whole = (n) => Number.isInteger(n) && n >= 0;
  if (u === null || typeof u !== 'object' || !whole(u.input_tokens) || !whole(u.output_tokens)) {
    throw new Error(`${file} must be {"input_tokens": N, "output_tokens": M} with whole numbers`);
  }
  return { input_tokens: u.input_tokens, output_tokens: u.output_tokens };
}

export function isFrozen(runDir) {
  return existsSync(path.join(runDir, RUN_FILES.planSha));
}

// Throws already_frozen when the folder holds plan.sha256. Called before anything is read for a
// freeze, so a frozen folder is never written again.
export function assertNotFrozen(runDir) {
  if (isFrozen(runDir)) {
    throw new EnvError(
      REASONS.already_frozen,
      `${runDir} is already frozen (${RUN_FILES.planSha} exists); a new plan goes in a new run folder: selvedge plan --init <criteria.json>`,
    );
  }
}

// The plan with plan_revision stamped (overwriting any planner value), keys in PLAN_KEYS order.
function stampRevision(plan, revision) {
  const out = {};
  for (const k of PLAN_KEYS) {
    if (k === 'plan_revision') out[k] = revision;
    else if (k in plan) out[k] = plan[k];
  }
  return out;
}

// freezeRun({ root, runDir, plan, criteriaSha256, plannerTokenBudget }) → the freeze record.
// `plan` has passed the plan lint. Stamps plan_revision, writes plan.json, hashes the bytes written,
// writes freeze.json, then plan.sha256 (the frozen marker, created exclusively), then appends the
// runs.jsonl freeze line. Throws already_frozen when the folder is frozen.
export function freezeRun({ root, runDir, plan, criteriaSha256, plannerTokenBudget = null, now = new Date() }) {
  assertNotFrozen(runDir);
  const runId = path.basename(runDir);
  const planTimeActions = sumPlanTimeActions(runDir);
  const plannerTokens = readPlannerUsage(runDir);
  const revision = nextPlanRevision(root, criteriaSha256);

  const planFile = path.join(runDir, RUN_FILES.plan);
  writeAtomic(planFile, prettyJson(stampRevision(plan, revision)));
  const planSha256 = sha256Hex(readFileSync(planFile));

  const ts = now.toISOString();
  const record = {
    schema_version: FREEZE_SCHEMA_VERSION,
    ts,
    run_id: runId,
    criteria_sha256: criteriaSha256,
    plan_sha256: planSha256,
    plan_revision: revision,
    plan_time_actions: planTimeActions,
    planner_tokens: plannerTokens,
    planner_token_budget: plannerTokenBudget,
  };
  writeAtomic(path.join(runDir, RUN_FILES.freeze), prettyJson(record));
  try {
    writeFileSync(path.join(runDir, RUN_FILES.planSha), `${planSha256}  ${RUN_FILES.plan}\n`, { flag: 'wx' });
  } catch (e) {
    if (e && e.code === 'EEXIST') assertNotFrozen(runDir);
    throw e;
  }

  const line = {
    event: FREEZE_EVENT,
    ts,
    run_id: runId,
    criteria_sha256: criteriaSha256,
    plan_sha256: planSha256,
    plan_revision: revision,
    plan_time_actions: planTimeActions,
    planner_tokens: plannerTokens,
  };
  mkdirSync(path.dirname(runsLogPath(root)), { recursive: true });
  appendFileSync(runsLogPath(root), `${JSON.stringify(line)}\n`);
  return record;
}
