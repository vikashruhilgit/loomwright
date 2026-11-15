// plan-steps.mjs — the plan step registry and the ONE step validator.
//
// A plan step is a typed object; nothing else runs. STEP_TYPES and the per-type field sets below are
// the closed vocabulary. selvedge/schemas/plan.schema.json declares the same names, and
// selvedge/tests/test-plan-validate.sh asserts the two are equal (the schema is not read at run
// time, so it is a real second copy, not a tautology).
//
// validateSteps is shared by the plan lint (plan-validate.mjs) and the snapshot prefix (snapshot.mjs);
// neither re-implements it. It returns every problem it finds, never only the first.
//
// Node >= 18, standard library only.
import { EnvError, REASONS, isOriginAllowed, parseOrigin } from './env-config.mjs';

export const STEP_TYPES = Object.freeze(['goto', 'click', 'fill', 'select', 'check', 'press', 'wait_for', 'read', 'expect']);

// Per step type: the fields it must carry and the ones it may carry (besides `type`).
export const STEP_FIELDS = Object.freeze({
  goto: Object.freeze({ required: Object.freeze(['url']), optional: Object.freeze([]) }),
  click: Object.freeze({ required: Object.freeze(['locator']), optional: Object.freeze([]) }),
  fill: Object.freeze({ required: Object.freeze(['locator', 'value']), optional: Object.freeze([]) }),
  select: Object.freeze({ required: Object.freeze(['locator', 'value']), optional: Object.freeze([]) }),
  check: Object.freeze({ required: Object.freeze(['locator']), optional: Object.freeze(['checked']) }),
  press: Object.freeze({ required: Object.freeze(['key']), optional: Object.freeze(['locator']) }),
  wait_for: Object.freeze({ required: Object.freeze(['locator', 'state']), optional: Object.freeze([]) }),
  read: Object.freeze({ required: Object.freeze(['property']), optional: Object.freeze(['locator']) }),
  expect: Object.freeze({ required: Object.freeze(['op', 'value']), optional: Object.freeze([]) }),
});

// Locator forms: exactly one primary key, plus the optional keys of its form. Playwright role, label,
// text and test-id locators only; never CSS or XPath.
export const LOCATOR_FORMS = Object.freeze({
  role: Object.freeze(['role', 'name', 'exact']),
  label: Object.freeze(['label']),
  text: Object.freeze(['text']),
  testid: Object.freeze(['testid']),
});

// The steps that change app state (a plan-time action when a snapshot prefix runs them).
export const ACTION_TYPES = Object.freeze(['click', 'fill', 'select', 'check', 'press']);

export const WAIT_STATES = Object.freeze(['attached', 'detached', 'visible', 'hidden']);
export const READ_PROPERTIES = Object.freeze(['text', 'value', 'checked', 'count', 'url']);
export const READ_ATTRIBUTE_PATTERN = '^attribute:[A-Za-z_][-A-Za-z0-9_:.]*$';
export const EXPECT_OPS = Object.freeze(['equals', 'contains', 'matches', 'gt', 'lt', 'changed_from']);

// A snapshot prefix: the plan step types except read/expect, at most PREFIX_MAX_STEPS of them.
export const PREFIX_STEP_TYPES = Object.freeze(STEP_TYPES.filter((t) => t !== 'read' && t !== 'expect'));
export const PREFIX_MAX_STEPS = 15;

// `{{NAME}}` — an environment variable resolved at run time; allowed only in a fill/select value.
const PLACEHOLDER_RE = /\{\{([A-Z_][A-Z0-9_]*)\}\}/g;
const PLACEHOLDER_FIELDS = Object.freeze({ fill: 'value', select: 'value' });

// Anything that looks like code, in any string field of a step. A step is data; a model that writes
// script into one is refused, not interpreted.
export const CODE_LIKE_PATTERNS = Object.freeze([
  /=>/,
  /\bfunction\s*\(/,
  /<script/i,
  /javascript:/i,
  /\$\{/,
  /`/,
  /\beval\s*\(/,
  /\bdocument\./,
  /\bwindow\./,
  /\brequire\s*\(/,
  /\bimport /,
]);

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function nonEmptyString(v) {
  return typeof v === 'string' && v.trim() !== '';
}

export function isCodeLike(s) {
  return typeof s === 'string' && CODE_LIKE_PATTERNS.some((re) => re.test(s));
}

export function isReadProperty(p) {
  return typeof p === 'string' && (READ_PROPERTIES.includes(p) || new RegExp(READ_ATTRIBUTE_PATTERN).test(p));
}

// Every string in a value (a step, a locator), with its dotted path, for the code-like check.
function stringsOf(value, at, outList) {
  if (typeof value === 'string') outList.push([at, value]);
  else if (Array.isArray(value)) value.forEach((v, i) => stringsOf(v, `${at}[${i}]`, outList));
  else if (isPlainObject(value)) for (const [k, v] of Object.entries(value)) stringsOf(v, `${at}.${k}`, outList);
  return outList;
}

function checkLocator(loc, at, add) {
  if (!isPlainObject(loc)) {
    add('invalid_locator', `${at} must be an object with exactly one of ${Object.keys(LOCATOR_FORMS).join(', ')}`);
    return;
  }
  const primary = Object.keys(loc).filter((k) => Object.prototype.hasOwnProperty.call(LOCATOR_FORMS, k));
  if (primary.length !== 1) {
    add('invalid_locator', `${at} must name exactly one of ${Object.keys(LOCATOR_FORMS).join(', ')} (has ${primary.length ? primary.join(', ') : 'none'}; CSS and XPath are never accepted)`);
    return;
  }
  const form = primary[0];
  const allowed = LOCATOR_FORMS[form];
  const extra = Object.keys(loc).filter((k) => !allowed.includes(k));
  if (extra.length) {
    add('invalid_locator', `${at}: ${extra.join(', ')} not allowed in a ${form} locator (allowed: ${allowed.join(', ')})`);
    return;
  }
  if (!nonEmptyString(loc[form])) add('plan_schema_violation', `${at}.${form} must be a non-empty string`);
  if ('name' in loc && typeof loc.name !== 'string') add('plan_schema_violation', `${at}.name must be a string`);
  if ('exact' in loc && typeof loc.exact !== 'boolean') add('plan_schema_violation', `${at}.exact must be true or false`);
}

function checkFieldValues(step, at, add) {
  const t = step.type;
  if ('locator' in step) checkLocator(step.locator, `${at}.locator`, add);
  switch (t) {
    case 'goto':
      if (!nonEmptyString(step.url)) add('plan_schema_violation', `${at}.url must be a non-empty string`);
      break;
    case 'fill':
    case 'select':
      if (typeof step.value !== 'string') add('plan_schema_violation', `${at}.value must be a string`);
      break;
    case 'check':
      if ('checked' in step && typeof step.checked !== 'boolean') add('plan_schema_violation', `${at}.checked must be true or false`);
      break;
    case 'press':
      if (!nonEmptyString(step.key)) add('plan_schema_violation', `${at}.key must be a non-empty string`);
      break;
    case 'wait_for':
      if (!WAIT_STATES.includes(step.state)) add('plan_schema_violation', `${at}.state must be one of ${WAIT_STATES.join(', ')}`);
      break;
    case 'read':
      if (!isReadProperty(step.property)) {
        add('plan_schema_violation', `${at}.property must be one of ${READ_PROPERTIES.join(', ')} or attribute:<name>`);
      } else if (step.property === 'url' && 'locator' in step) {
        add('plan_schema_violation', `${at}: read url takes no locator`);
      } else if (step.property !== 'url' && !('locator' in step)) {
        add('plan_schema_violation', `${at}: read ${step.property} needs a locator`);
      }
      break;
    case 'expect': {
      const { op, value } = step;
      if (!EXPECT_OPS.includes(op)) {
        add('plan_schema_violation', `${at}.op ${JSON.stringify(op)} is not one of ${EXPECT_OPS.join(', ')}`);
      } else if ((op === 'gt' || op === 'lt') && (typeof value !== 'number' || !Number.isFinite(value))) {
        add('plan_schema_violation', `${at}: ${op} needs a number value`);
      } else if (op === 'changed_from' && typeof value !== 'boolean') {
        add('plan_schema_violation', `${at}: changed_from needs a boolean value (whether the last read must differ from the previous read)`);
      } else if ((op === 'contains' || op === 'matches') && typeof value !== 'string') {
        add('plan_schema_violation', `${at}: ${op} needs a string value`);
      } else if (op === 'equals' && !['string', 'number', 'boolean'].includes(typeof value)) {
        add('plan_schema_violation', `${at}: equals needs a string, number or boolean value`);
      } else if (op === 'matches') {
        try {
          new RegExp(value); // eslint-disable-line no-new
        } catch (e) {
          add('plan_schema_violation', `${at}: matches value is not a valid regular expression (${e.message})`);
        }
      }
      break;
    }
    default:
      break;
  }
}

// validateSteps(steps, { config, origins, prefix }) → [{ index, code, detail }] (empty when valid).
//  - config: a loaded selvedge.json (loadConfig().config); every goto origin must be allowed by it
//    (isOriginAllowed). No config allows nothing: the check fails closed.
//  - origins: when an array, every goto origin must also be one of these (the plan's `origins`).
//  - prefix: a snapshot prefix — only PREFIX_STEP_TYPES, at most PREFIX_MAX_STEPS steps.
// Codes are plan-lint problem codes (PLAN_PROBLEMS in plan-validate.mjs). `index` is 0-based, or
// null for a problem with the whole list.
export function validateSteps(steps, { config, origins, prefix = false } = {}) {
  const problems = [];
  if (!Array.isArray(steps)) {
    problems.push({ index: null, code: 'plan_schema_violation', detail: 'steps must be an array' });
    return problems;
  }
  if (prefix && steps.length > PREFIX_MAX_STEPS) {
    problems.push({ index: null, code: 'prefix_too_long', detail: `a prefix has ${steps.length} steps; at most ${PREFIX_MAX_STEPS}` });
  }
  steps.forEach((step, index) => {
    const at = `steps[${index}]`;
    const add = (code, detail) => problems.push({ index, code, detail });
    if (!isPlainObject(step)) {
      add('plan_schema_violation', `${at} must be an object`);
      return;
    }
    const t = step.type;
    if (typeof t !== 'string' || !STEP_TYPES.includes(t)) {
      add('unknown_step_type', `${at}.type ${JSON.stringify(t)} is not one of ${STEP_TYPES.join(', ')}`);
      return;
    }
    if (prefix && !PREFIX_STEP_TYPES.includes(t)) {
      add('prefix_step_not_allowed', `${at}: ${t} is not allowed in a snapshot prefix (allowed: ${PREFIX_STEP_TYPES.join(', ')})`);
    }
    const { required, optional } = STEP_FIELDS[t];
    for (const k of Object.keys(step)) {
      if (k !== 'type' && !required.includes(k) && !optional.includes(k)) {
        add('unknown_field', `${at}.${k} is not a ${t} field (allowed: ${[...required, ...optional].join(', ') || 'none'})`);
      }
    }
    for (const k of required) {
      if (!(k in step)) add('plan_schema_violation', `${at}: ${t} needs ${k}`);
    }
    checkFieldValues(step, at, add);
    for (const [p, s] of stringsOf(step, at, [])) {
      if (isCodeLike(s)) add('code_like_content', `${p} looks like code (${JSON.stringify(s.slice(0, 60))})`);
    }
    if (t === 'goto' && typeof step.url === 'string' && !isCodeLike(step.url)) {
      let origin = null;
      try {
        const u = new URL(step.url);
        origin = parseOrigin(u.origin) ? u.origin : null;
      } catch {
        origin = null;
      }
      if (!origin || !isOriginAllowed(config, step.url)) {
        add('origin_not_allowed', `${at}.url ${JSON.stringify(step.url)}: origin ${origin || '(none)'} is not allowed by selvedge.json`);
      } else if (Array.isArray(origins) && !isOriginAllowed({ origins }, step.url)) {
        add('origin_not_allowed', `${at}.url ${JSON.stringify(step.url)}: origin ${origin} is not in the plan's origins`);
      }
    }
  });
  return problems;
}

// The `{{NAME}}` placeholders a step list uses, in first-use order (only fill/select values).
export function placeholderNames(steps) {
  const names = [];
  if (!Array.isArray(steps)) return names;
  for (const step of steps) {
    const field = isPlainObject(step) ? PLACEHOLDER_FIELDS[step.type] : undefined;
    if (!field || typeof step[field] !== 'string') continue;
    for (const m of step[field].matchAll(PLACEHOLDER_RE)) if (!names.includes(m[1])) names.push(m[1]);
  }
  return names;
}

// resolvePlaceholders(steps, env) → a new step list with every `{{NAME}}` in a fill/select value
// replaced by env[NAME]. The input is never changed (callers log the given steps, never the values).
// Any unset name throws EnvError placeholder_unset (blocked) naming every unset one: an unset value
// is never resolved to an empty string.
export function resolvePlaceholders(steps, env = process.env) {
  const missing = placeholderNames(steps).filter((n) => env[n] === undefined);
  if (missing.length) {
    const e = new EnvError(REASONS.placeholder_unset, `unset: ${missing.join(', ')} (set each in the environment)`, { blocked: true });
    e.names = missing;
    throw e;
  }
  return steps.map((step) => {
    const field = isPlainObject(step) ? PLACEHOLDER_FIELDS[step.type] : undefined;
    if (!field || typeof step[field] !== 'string') return step;
    return { ...step, [field]: step[field].replace(PLACEHOLDER_RE, (_, n) => env[n]) };
  });
}
