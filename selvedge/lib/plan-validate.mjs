// plan-validate.mjs — the static lint a plan.json must pass before it is hashed.
//
// validatePlan returns EVERY problem it finds (never only the first), each one PLAN_PROBLEMS code
// with the criterion it belongs to. `selvedge plan --validate` prints one stderr line per problem:
//   plan_invalid: <criterion id | (plan)>: <code>: <detail>
//
// What it enforces (00-plan D6/D7):
//  - the PASS rule: a criterion's steps end in `read` then `expect` — a value read after the last
//    action — and that expect checks a value, not existence or visibility;
//  - negative criteria read a baseline before their first action and do not check only that an
//    element is absent or hidden;
//  - each planned criterion states its interpretation, polarity and unverified assumptions;
//  - vague criteria are never planned; they sit under not_planned with a rewrite;
//  - every criterion of criteria.json is accounted for, and criteria_sha256 matches it;
//  - every step passes validateSteps (plan-steps.mjs, the one step validator).
//
// Node >= 18, standard library only.
import { REASONS, isOriginAllowed, parseOrigin } from './env-config.mjs';
import { classifyTestability, criteriaSha256 } from './criteria.mjs';
import { ACTION_TYPES, validateSteps } from './plan-steps.mjs';

// The closed list of plan-lint problem codes. selvedge/README.md lists each one;
// selvedge/tests/test-plan-validate.sh asserts the two match.
export const PLAN_PROBLEMS = Object.freeze([
  'missing_final_read_expect',
  'existence_only_expect',
  'unknown_step_type',
  'unknown_field',
  'invalid_locator',
  'code_like_content',
  'origin_not_allowed',
  'missing_interpretation',
  'missing_polarity',
  'invalid_assumptions',
  'negative_without_baseline',
  'negative_absence_only',
  'vague_criterion_planned',
  'criterion_unaccounted',
  'criteria_sha_mismatch',
  'prefix_step_not_allowed',
  'prefix_too_long',
  'invalid_not_planned',
  'plan_schema_violation',
]);

export const PLAN_SCHEMA_VERSION = 1;
export const PLAN_TARGETS = Object.freeze(['web']);
// The validator's accepted key sets; selvedge/schemas/plan.schema.json declares the same names.
export const PLAN_KEYS = Object.freeze(['schema_version', 'target', 'criteria_sha256', 'plan_revision', 'origins', 'steps_by_criterion', 'not_planned']);
export const PLAN_REQUIRED_KEYS = Object.freeze(['schema_version', 'target', 'criteria_sha256', 'origins', 'steps_by_criterion']);
export const CRITERION_PLAN_KEYS = Object.freeze(['interpretation', 'polarity', 'unverified_assumptions', 'steps']);
export const POLARITIES = Object.freeze(['positive', 'negative']);
export const ASSUMPTION_KEYS = Object.freeze(['text', 'material']);
export const NOT_PLANNED_KEYS = Object.freeze(['id', 'reason', 'rewrite', 'detail']);
export const NOT_PLANNED_REASONS = Object.freeze([
  REASONS.criterion_not_testable,
  REASONS.side_effect_not_observable,
  REASONS.exploration_budget,
]);

// A final expect with one of these ops checks only that something exists or shows.
export const EXISTENCE_OPS = Object.freeze(['visible', 'hidden', 'exists', 'attached', 'detached']);
// A wait_for in one of these states, as a negative criterion's last check, checks only absence.
const ABSENCE_STATES = Object.freeze(['hidden', 'detached']);

export const PLAN_SCOPE = '(plan)';

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function nonEmptyString(v) {
  return typeof v === 'string' && v.trim() !== '';
}

export function problemLine(p) {
  return `${REASONS.plan_invalid}: ${p.id}: ${p.code}${p.detail ? `: ${p.detail}` : ''}`;
}

// A `read count` then an expect that holds whenever at least one element exists.
function isCountExistence(read, expect) {
  return read.property === 'count' && expect.op === 'gt' && typeof expect.value === 'number' && expect.value < 1;
}

// A `read count` then an expect that holds only when no element exists.
function isCountAbsence(read, expect) {
  return read.property === 'count'
    && ((expect.op === 'equals' && expect.value === 0) || (expect.op === 'lt' && typeof expect.value === 'number' && expect.value <= 1));
}

function lintSteps(id, entry, add) {
  const steps = entry.steps;
  if (!Array.isArray(steps)) return;
  const n = steps.length;
  const last = n ? steps[n - 1] : null;
  const prev = n > 1 ? steps[n - 2] : null;
  const endsInReadExpect = isPlainObject(last) && last.type === 'expect' && isPlainObject(prev) && prev.type === 'read';
  if (!endsInReadExpect) {
    const tail = isPlainObject(last) ? last.type : '(nothing)';
    add(id, 'missing_final_read_expect', `the steps must end in read then expect (a value read after the last action); they end in ${JSON.stringify(tail)}`);
  }
  if (isPlainObject(last) && last.type === 'expect' && EXISTENCE_OPS.includes(last.op)) {
    add(id, 'existence_only_expect', `the final expect op ${JSON.stringify(last.op)} checks only existence or visibility; check a value`);
  }
  if (endsInReadExpect && isCountExistence(prev, last)) {
    add(id, 'existence_only_expect', 'read count then expect gt 0 checks only that an element exists; check a value');
  }
  if (entry.polarity !== 'negative') return;
  const firstAction = steps.findIndex((s) => isPlainObject(s) && ACTION_TYPES.includes(s.type));
  if (firstAction >= 0 && !steps.slice(0, firstAction).some((s) => isPlainObject(s) && s.type === 'read')) {
    add(id, 'negative_without_baseline', `a negative criterion reads a baseline of the side effect before its first action (steps[${firstAction}] ${steps[firstAction].type})`);
  }
  const checks = steps.filter((s) => isPlainObject(s) && (s.type === 'wait_for' || s.type === 'expect'));
  const lastCheck = checks.length ? checks[checks.length - 1] : null;
  if ((endsInReadExpect && isCountAbsence(prev, last)) || (lastCheck && lastCheck.type === 'wait_for' && ABSENCE_STATES.includes(lastCheck.state))) {
    add(id, 'negative_absence_only', 'a negative criterion proves the side effect is absent by comparing it with its baseline (e.g. count unchanged, changed_from false), not only that an element is absent or hidden');
  }
}

function lintCriterion(id, entry, ctx, add) {
  if (!isPlainObject(entry)) {
    add(id, 'plan_schema_violation', 'a planned criterion must be an object');
    return;
  }
  for (const k of Object.keys(entry)) {
    if (!CRITERION_PLAN_KEYS.includes(k)) add(id, 'unknown_field', `${k} is not a criterion field (allowed: ${CRITERION_PLAN_KEYS.join(', ')})`);
  }
  if (!nonEmptyString(entry.interpretation)) add(id, 'missing_interpretation', 'interpretation: one sentence saying what the criterion means');
  if (!POLARITIES.includes(entry.polarity)) add(id, 'missing_polarity', `polarity must be ${POLARITIES.join(' or ')}`);
  const a = entry.unverified_assumptions;
  const assumptionOk = (x) => isPlainObject(x)
    && Object.keys(x).length === ASSUMPTION_KEYS.length
    && nonEmptyString(x.text) && typeof x.material === 'boolean';
  if (!Array.isArray(a) || !a.every(assumptionOk)) {
    add(id, 'invalid_assumptions', 'unverified_assumptions must be an array of {text, material} (text a non-empty string, material true or false)');
  }
  const text = ctx.textById.get(id);
  if (text !== undefined && classifyTestability(text).testability === 'vague') {
    add(id, 'vague_criterion_planned', `"${text}" is vague; list it under not_planned with reason ${REASONS.criterion_not_testable} and a rewrite`);
  }
  if (!('steps' in entry)) {
    add(id, 'plan_schema_violation', 'a planned criterion needs steps');
  } else {
    for (const p of validateSteps(entry.steps, { config: ctx.config, origins: ctx.origins })) add(id, p.code, p.detail);
  }
  lintSteps(id, entry, add);
}

function lintNotPlanned(list, ctx, add) {
  const seen = new Set();
  list.forEach((np, i) => {
    const at = `not_planned[${i}]`;
    if (!isPlainObject(np)) {
      add(PLAN_SCOPE, 'invalid_not_planned', `${at} must be an object`);
      return;
    }
    const who = typeof np.id === 'string' ? np.id : PLAN_SCOPE;
    const bad = (msg) => add(who, 'invalid_not_planned', `${at}: ${msg}`);
    for (const k of Object.keys(np)) if (!NOT_PLANNED_KEYS.includes(k)) bad(`unknown key ${k} (allowed: ${NOT_PLANNED_KEYS.join(', ')})`);
    if (typeof np.id !== 'string' || !ctx.textById.has(np.id)) bad(`id ${JSON.stringify(np.id)} is not a criterion of criteria.json`);
    else if (seen.has(np.id)) bad(`${np.id} is listed twice`);
    else if (ctx.planned.has(np.id)) bad(`${np.id} is both planned and not_planned`);
    if (typeof np.id === 'string') seen.add(np.id);
    if (!NOT_PLANNED_REASONS.includes(np.reason)) bad(`reason must be one of ${NOT_PLANNED_REASONS.join(', ')}`);
    if ('rewrite' in np && typeof np.rewrite !== 'string') bad('rewrite must be a string');
    if ('detail' in np && typeof np.detail !== 'string') bad('detail must be a string');
    if (np.reason === REASONS.criterion_not_testable && !nonEmptyString(np.rewrite)) bad(`${REASONS.criterion_not_testable} needs a non-empty rewrite`);
    const text = ctx.textById.get(np.id);
    if (text !== undefined && classifyTestability(text).testability === 'vague' && np.reason !== REASONS.criterion_not_testable) {
      bad(`a vague criterion is not planned under ${REASONS.criterion_not_testable}, with a rewrite`);
    }
  });
  return seen;
}

// validatePlan(plan, { criteria, config }) → [{ id, code, detail }] (empty when the plan is valid).
//  - criteria: the run folder's criteria.json document (validated by criteria.mjs).
//  - config: the loaded selvedge.json; every plan origin and goto must be allowed by it.
export function validatePlan(plan, { criteria, config } = {}) {
  if (!isPlainObject(criteria) || !Array.isArray(criteria.criteria)) {
    throw new TypeError('validatePlan needs the criteria.json document');
  }
  const problems = [];
  const add = (id, code, detail) => problems.push({ id, code, detail });
  if (!isPlainObject(plan)) {
    add(PLAN_SCOPE, 'plan_schema_violation', 'plan.json must be a JSON object');
    return problems;
  }
  for (const k of Object.keys(plan)) {
    if (!PLAN_KEYS.includes(k)) add(PLAN_SCOPE, 'unknown_field', `${k} is not a plan field (allowed: ${PLAN_KEYS.join(', ')})`);
  }
  for (const k of PLAN_REQUIRED_KEYS) if (!(k in plan)) add(PLAN_SCOPE, 'plan_schema_violation', `missing ${k}`);
  if ('schema_version' in plan && plan.schema_version !== PLAN_SCHEMA_VERSION) add(PLAN_SCOPE, 'plan_schema_violation', `schema_version must be ${PLAN_SCHEMA_VERSION}`);
  if ('target' in plan && !PLAN_TARGETS.includes(plan.target)) add(PLAN_SCOPE, 'plan_schema_violation', `target must be ${PLAN_TARGETS.join(' or ')}`);
  if ('plan_revision' in plan && !(Number.isInteger(plan.plan_revision) && plan.plan_revision >= 1)) {
    add(PLAN_SCOPE, 'plan_schema_violation', 'plan_revision must be an integer >= 1');
  }
  if ('criteria_sha256' in plan) {
    const want = criteriaSha256(criteria.criteria);
    if (typeof plan.criteria_sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(plan.criteria_sha256)) {
      add(PLAN_SCOPE, 'plan_schema_violation', 'criteria_sha256 must be 64 lowercase hex');
    } else if (plan.criteria_sha256 !== want) {
      add(PLAN_SCOPE, 'criteria_sha_mismatch', `criteria_sha256 ${plan.criteria_sha256} is not criteria.json's ${want}`);
    }
  }
  let origins;
  if ('origins' in plan) {
    if (!Array.isArray(plan.origins) || !plan.origins.every((o) => typeof o === 'string')) {
      add(PLAN_SCOPE, 'plan_schema_violation', 'origins must be an array of strings');
    } else {
      origins = plan.origins;
      for (const o of origins) {
        if (!parseOrigin(o)) add(PLAN_SCOPE, 'plan_schema_violation', `origin ${JSON.stringify(o)} is not exactly scheme://host[:port]`);
        else if (!isOriginAllowed(config, o)) add(PLAN_SCOPE, 'origin_not_allowed', `origin ${o} is not allowed by selvedge.json`);
      }
    }
  }
  const textById = new Map(criteria.criteria.map((c) => [c.id, c.text]));
  const planned = new Set();
  const ctx = { config, origins, textById, planned };
  if ('steps_by_criterion' in plan) {
    if (!isPlainObject(plan.steps_by_criterion)) {
      add(PLAN_SCOPE, 'plan_schema_violation', 'steps_by_criterion must be an object keyed by criterion id');
    } else {
      for (const id of Object.keys(plan.steps_by_criterion)) planned.add(id);
      for (const [id, entry] of Object.entries(plan.steps_by_criterion)) {
        if (!textById.has(id)) add(id, 'criterion_unaccounted', `${id} is planned but is not a criterion of criteria.json`);
        lintCriterion(id, entry, ctx, add);
      }
    }
  }
  let notPlanned = new Set();
  if ('not_planned' in plan) {
    if (!Array.isArray(plan.not_planned)) add(PLAN_SCOPE, 'invalid_not_planned', 'not_planned must be an array');
    else notPlanned = lintNotPlanned(plan.not_planned, ctx, add);
  }
  for (const c of criteria.criteria) {
    if (!planned.has(c.id) && !notPlanned.has(c.id)) {
      add(c.id, 'criterion_unaccounted', `"${c.text}" is neither planned nor listed under not_planned`);
    }
  }
  return problems;
}
