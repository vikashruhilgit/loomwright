// runner/evidence.mjs — the evidence.jsonl line contract: the frozen line kinds, each kind's
// fields, the one reader and the one writer. `selvedge verdict` (lib/verdict.mjs) reads a run
// folder's evidence only through readEvidence; the runner (`selvedge run`) writes it only through appendEvidence, which
// checks every line with evidenceLineProblem before it is appended, so the writer and the reader
// share one contract.
//
// A run folder's evidence.jsonl holds, in this order:
//   {"kind":"run_start", ts, run_id, plan_sha256, playwright_version, data_state, hooks_run,
//    plan_time_actions, replay_of}                                       exactly one, the first line
//   {"kind":"step", criterion, step, type, locator, outcome, value, duration_ms[, error][, stable_wait]}
//                                                                        one per executed step
//   {"kind":"criterion_end", criterion, outcome, reason, failed_step, screenshot}
//                                                                        at most one per criterion
//   {"kind":"run_end", ts, duration_ms}                                  at most one, the last line
// A step line's `value` is the read value for `read`, the plan's own value for `fill` / `select`
// (a {{NAME}} kept as written) and null otherwise; an `expect` line's outcome is matched or
// mismatched, every other step's ok or failed. A criterion_end line's reason is null for a
// completed criterion and one of REASONS otherwise.
//
// A criterion with no criterion_end line was cut short (an interrupted run): the reader keeps it as
// it is, and the verdict says BLOCKED run_interrupted. Anything else the reader cannot trust — the
// file is absent, a line is not a JSON object of a known kind with that kind's fields, or the
// lines are out of order — throws evidence_missing: no verdict is derived from it (fail closed; a
// torn last line included).
//
// The writer (appendEvidence) is the only code that writes evidence.jsonl. It passes every string
// of a line through redactValues (snapshot.mjs) with the run's resolved {{NAME}} values, checks the
// line with evidenceLineProblem, and creates the file exclusively with the run_start line (an
// existing file is already_run: one run per folder). stepLine builds a step line from the plan step
// AS GIVEN, so a fill / select value is written as the plan wrote it ({{NAME}} kept), never the
// value the page received.
//
// Node >= 18, standard library only.
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { EnvError, REASONS } from '../env-config.mjs';
import { STEP_TYPES } from '../plan-steps.mjs';
import { redactValues } from '../snapshot.mjs';

export const EVIDENCE_FILE = 'evidence.jsonl';

// The line kinds, frozen (value == key).
export const EVIDENCE_KINDS = Object.freeze({
  run_start: 'run_start',
  step: 'step',
  criterion_end: 'criterion_end',
  run_end: 'run_end',
});

// Each kind's fields besides `kind`: every `required` one is present (its value may be null), an
// `optional` one may be absent, and any other key is refused.
export const EVIDENCE_FIELDS = Object.freeze({
  [EVIDENCE_KINDS.run_start]: Object.freeze({
    required: Object.freeze(['ts', 'run_id', 'plan_sha256', 'playwright_version', 'data_state', 'hooks_run', 'plan_time_actions', 'replay_of']),
    optional: Object.freeze([]),
  }),
  [EVIDENCE_KINDS.step]: Object.freeze({
    required: Object.freeze(['criterion', 'step', 'type', 'locator', 'outcome', 'value', 'duration_ms']),
    optional: Object.freeze(['error', 'stable_wait']),
  }),
  [EVIDENCE_KINDS.criterion_end]: Object.freeze({
    required: Object.freeze(['criterion', 'outcome', 'reason', 'failed_step', 'screenshot']),
    optional: Object.freeze([]),
  }),
  [EVIDENCE_KINDS.run_end]: Object.freeze({
    required: Object.freeze(['ts', 'duration_ms']),
    optional: Object.freeze([]),
  }),
});

// A step line's outcome. `expect` lines carry matched / mismatched; every other step ok / failed.
export const STEP_OUTCOMES = Object.freeze({
  ok: 'ok',
  failed: 'failed',
  matched: 'matched',
  mismatched: 'mismatched',
});

// A criterion_end line's outcome. The three that are also reasons are taken from REASONS.
export const CRITERION_OUTCOMES = Object.freeze({
  completed: 'completed', // every step ran; the verdict comes from the final read and expect
  step_failed: REASONS.step_failed,
  stuck_screen: REASONS.stuck_screen,
  budget_exceeded: REASONS.budget_exceeded,
  blocked: 'blocked', // stopped before or at launch; `reason` names why (host_not_allowed, …)
  not_planned: 'not_planned', // the plan lists it under not_planned; `reason` is the plan's
});

// run_start's data_state: managed when an approved seed/reset hook ran, else unmanaged.
export const DATA_STATES = Object.freeze({ managed: 'managed', unmanaged: 'unmanaged' });

const SHA256_HEX = /^[0-9a-f]{64}$/;
const REASON_VALUES = Object.freeze(Object.values(REASONS));

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isWhole = (n) => Number.isInteger(n) && n >= 0;
const isDuration = (n) => typeof n === 'number' && Number.isFinite(n) && n >= 0;
const isScalar = (v) => v === null || ['string', 'number', 'boolean'].includes(typeof v);
const nullOr = (test) => (v) => v === null || test(v);
const isString = (v) => typeof v === 'string';
const isNonEmpty = (v) => typeof v === 'string' && v !== '';

// Per-kind field checks: each returns the name of the first field whose value is wrong, or null.
const FIELD_CHECKS = Object.freeze({
  [EVIDENCE_KINDS.run_start]: {
    ts: isNonEmpty,
    run_id: isNonEmpty,
    plan_sha256: (v) => typeof v === 'string' && SHA256_HEX.test(v),
    playwright_version: nullOr(isString),
    data_state: (v) => Object.values(DATA_STATES).includes(v),
    hooks_run: (v) => Array.isArray(v) && v.every(isNonEmpty),
    plan_time_actions: nullOr(isWhole),
    replay_of: nullOr(isNonEmpty),
  },
  [EVIDENCE_KINDS.step]: {
    criterion: isNonEmpty,
    step: isWhole,
    type: (v) => STEP_TYPES.includes(v),
    locator: nullOr(isPlainObject),
    outcome: (v) => Object.values(STEP_OUTCOMES).includes(v),
    value: isScalar,
    duration_ms: isDuration,
    error: isString,
    stable_wait: (v) => typeof v === 'boolean',
  },
  [EVIDENCE_KINDS.criterion_end]: {
    criterion: isNonEmpty,
    outcome: (v) => Object.values(CRITERION_OUTCOMES).includes(v),
    reason: nullOr((v) => REASON_VALUES.includes(v)),
    failed_step: nullOr(isWhole),
    screenshot: nullOr(isNonEmpty),
  },
  [EVIDENCE_KINDS.run_end]: {
    ts: isNonEmpty,
    duration_ms: isDuration,
  },
});

// evidenceLineProblem(line) → null when `line` is a valid evidence line, else a short description
// of the first problem. The writer calls it before appending; readEvidence calls it on every line.
export function evidenceLineProblem(line) {
  if (!isPlainObject(line)) return 'not a JSON object';
  if (!Object.values(EVIDENCE_KINDS).includes(line.kind)) {
    return `unknown kind ${JSON.stringify(line.kind)} (allowed: ${Object.values(EVIDENCE_KINDS).join(', ')})`;
  }
  const { required, optional } = EVIDENCE_FIELDS[line.kind];
  for (const k of Object.keys(line)) {
    if (k !== 'kind' && !required.includes(k) && !optional.includes(k)) return `${line.kind}: unknown field ${k}`;
  }
  for (const k of required) if (!(k in line)) return `${line.kind}: missing ${k}`;
  const checks = FIELD_CHECKS[line.kind];
  for (const k of Object.keys(line)) {
    if (k !== 'kind' && !checks[k](line[k])) return `${line.kind}: ${k} has the wrong value ${JSON.stringify(line[k])}`;
  }
  if (line.kind === EVIDENCE_KINDS.step) {
    const isExpect = line.type === 'expect';
    const expectOutcome = line.outcome === STEP_OUTCOMES.matched || line.outcome === STEP_OUTCOMES.mismatched;
    if (isExpect !== expectOutcome) return `step: outcome ${line.outcome} does not fit a ${line.type} step`;
  }
  if (line.kind === EVIDENCE_KINDS.criterion_end) {
    const completed = line.outcome === CRITERION_OUTCOMES.completed;
    if (completed && line.reason !== null) return 'criterion_end: a completed criterion carries no reason';
    if (!completed && line.reason === null) return `criterion_end: outcome ${line.outcome} needs a reason`;
  }
  return null;
}

// readEvidence(runDir) → { file, runStart, steps, ends, runEnd, lines }.
//   runStart  the run_start line
//   steps     every step line, in file order
//   ends      Map criterion id → its criterion_end line
//   runEnd    the run_end line, or null (the run did not finish)
//   lines     every line, in file order
// Throws EnvError evidence_missing (see the header) when the evidence cannot be trusted.
export function readEvidence(runDir) {
  const file = path.join(runDir, EVIDENCE_FILE);
  const refuse = (why) => new EnvError(REASONS.evidence_missing, `${file}: ${why}; no verdict is derived from it`);
  let raw;
  try {
    raw = readFileSync(file, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') {
      throw new EnvError(REASONS.evidence_missing, `no ${EVIDENCE_FILE} in ${runDir}; run the plan first: selvedge run <run-dir>`);
    }
    throw refuse(`cannot be read (${e && e.message})`);
  }
  const lines = [];
  const rows = raw.split('\n');
  for (let i = 0; i < rows.length; i += 1) {
    if (rows[i].trim() === '') continue;
    let v;
    try {
      v = JSON.parse(rows[i]);
    } catch {
      throw refuse(`line ${i + 1} is not valid JSON`);
    }
    const problem = evidenceLineProblem(v);
    if (problem) throw refuse(`line ${i + 1}: ${problem}`);
    lines.push(v);
  }
  if (lines.length === 0 || lines[0].kind !== EVIDENCE_KINDS.run_start) throw refuse('the first line is not run_start');
  const steps = [];
  const ends = new Map();
  let runEnd = null;
  for (let i = 1; i < lines.length; i += 1) {
    const l = lines[i];
    if (runEnd) throw refuse('a line follows run_end');
    if (l.kind === EVIDENCE_KINDS.run_start) throw refuse('a second run_start line');
    if (l.kind === EVIDENCE_KINDS.run_end) runEnd = l;
    else if (l.kind === EVIDENCE_KINDS.criterion_end) {
      if (ends.has(l.criterion)) throw refuse(`a second criterion_end line for ${l.criterion}`);
      ends.set(l.criterion, l);
    } else {
      if (ends.has(l.criterion)) throw refuse(`a step line for ${l.criterion} after its criterion_end`);
      steps.push(l);
    }
  }
  return { file, runStart: lines[0], steps, ends, runEnd, lines };
}

// Every string in a value (nested in arrays and objects) passed through redactValues.
function redactDeep(value, secrets) {
  if (typeof value === 'string') return redactValues(value, secrets);
  if (Array.isArray(value)) return value.map((v) => redactDeep(v, secrets));
  if (isPlainObject(value)) return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, redactDeep(v, secrets)]));
  return value;
}

// stepLine({ criterion, index, step, outcome, value, durationMs, error, stableWait }) → a step line.
//   step   the plan step AS GIVEN (never the resolved copy): its type, locator and, for fill /
//          select, its value ({{NAME}} kept)
//   value  the value a read step read (ignored for every other type)
// error and stableWait are written only when given.
export function stepLine({ criterion, index, step, outcome, value = null, durationMs, error, stableWait }) {
  let written = null;
  if (step.type === 'read') written = value;
  else if (step.type === 'fill' || step.type === 'select') written = step.value;
  const line = {
    kind: EVIDENCE_KINDS.step,
    criterion,
    step: index,
    type: step.type,
    locator: isPlainObject(step.locator) ? step.locator : null,
    outcome,
    value: written === undefined ? null : written,
    duration_ms: durationMs,
  };
  if (error !== undefined) line.error = error;
  if (stableWait !== undefined) line.stable_wait = stableWait;
  return line;
}

// appendEvidence(runDir, line, { secrets, first }) — redacts, checks and appends one line to
// <runDir>/evidence.jsonl. `secrets` is [{ name, value }] (placeholderValues). With `first` (the
// run_start line) the file is created exclusively: an existing one throws EnvError already_run and
// nothing is written. A line that fails evidenceLineProblem is never written (an Error: the
// writer and the reader disagree, a bug).
export function appendEvidence(runDir, line, { secrets = [], first = false } = {}) {
  const out = redactDeep(line, secrets);
  const problem = evidenceLineProblem(out);
  if (problem) throw new Error(`refusing to write an evidence line the reader would refuse (${problem})`);
  const file = path.join(runDir, EVIDENCE_FILE);
  const text = `${JSON.stringify(out)}\n`;
  if (!first) {
    appendFileSync(file, text);
    return;
  }
  try {
    writeFileSync(file, text, { flag: 'wx' });
  } catch (e) {
    if (e && e.code === 'EEXIST') {
      throw new EnvError(REASONS.already_run, `${file} exists: this run folder has already run; a new run needs a new run folder`);
    }
    throw e;
  }
}
