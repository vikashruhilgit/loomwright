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
import { EnvError, REASONS, isLocalOrigin, isOriginAllowed, parseOrigin } from './env-config.mjs';

export const STEP_TYPES = Object.freeze(['goto', 'click', 'fill', 'select', 'check', 'press', 'wait_for', 'request', 'read', 'expect']);

// Per step type: the fields it must carry and the ones it may carry (besides `type`).
export const STEP_FIELDS = Object.freeze({
  goto: Object.freeze({ required: Object.freeze(['url']), optional: Object.freeze([]) }),
  click: Object.freeze({ required: Object.freeze(['locator']), optional: Object.freeze([]) }),
  fill: Object.freeze({ required: Object.freeze(['locator', 'value']), optional: Object.freeze([]) }),
  select: Object.freeze({ required: Object.freeze(['locator', 'value']), optional: Object.freeze([]) }),
  check: Object.freeze({ required: Object.freeze(['locator']), optional: Object.freeze(['checked']) }),
  press: Object.freeze({ required: Object.freeze(['key']), optional: Object.freeze(['locator']) }),
  wait_for: Object.freeze({ required: Object.freeze(['locator', 'state']), optional: Object.freeze([]) }),
  request: Object.freeze({ required: Object.freeze(['method', 'url']), optional: Object.freeze(['json', 'body', 'headers']) }),
  read: Object.freeze({ required: Object.freeze(['property']), optional: Object.freeze(['locator', 'at_load']) }),
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

// The steps that change app state (a plan-time action when a snapshot prefix runs them). A
// `request` whose method is not GET is an action too (isActionStep): REQUEST_ACTION_METHODS.
export const ACTION_TYPES = Object.freeze(['click', 'fill', 'select', 'check', 'press']);

// A `request` step: one fetch from inside the page (runner/steps.mjs), to the origin of the page
// the criterion is on. GET reads; every other method is an action. `json` is a plain object (a
// non-GET body), its string leaves literals or {{NAME}}. `body` is a raw text body instead (a
// non-GET request that is not JSON, or malformed JSON on purpose); never both. `headers` names
// request headers (string values, literals or {{NAME}}); a header the browser forbids page code
// to set (FORBIDDEN_REQUEST_HEADERS) would be dropped silently, so it is refused.
export const REQUEST_METHODS = Object.freeze(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
export const REQUEST_ACTION_METHODS = Object.freeze(REQUEST_METHODS.filter((m) => m !== 'GET'));
// How deep a `json` body may nest, and how many leaves it may hold.
export const REQUEST_JSON_MAX_DEPTH = 6;
export const REQUEST_JSON_MAX_LEAVES = 64;
export const REQUEST_BODY_MAX_CHARS = 8192;
export const REQUEST_HEADERS_MAX = 16;
export const REQUEST_HEADER_NAME_PATTERN = '^[A-Za-z0-9][A-Za-z0-9-]*$';
// fetch() drops these (the Fetch standard's forbidden request headers): a plan cannot set them.
export const FORBIDDEN_REQUEST_HEADERS = Object.freeze([
  'accept-charset', 'accept-encoding', 'access-control-request-headers', 'access-control-request-method',
  'connection', 'content-length', 'cookie', 'cookie2', 'date', 'dnt', 'expect', 'host', 'keep-alive',
  'origin', 'referer', 'set-cookie', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'via',
]);
const FORBIDDEN_HEADER_PREFIXES = Object.freeze(['proxy-', 'sec-']);
export function isForbiddenHeader(name) {
  const n = String(name).toLowerCase();
  return FORBIDDEN_REQUEST_HEADERS.includes(n) || FORBIDDEN_HEADER_PREFIXES.some((x) => n.startsWith(x));
}

// isActionStep(step) → true for a step that can change app state: ACTION_TYPES, or a `request`
// whose method is not GET.
export function isActionStep(step) {
  if (!isPlainObject(step)) return false;
  if (ACTION_TYPES.includes(step.type)) return true;
  return step.type === 'request' && REQUEST_ACTION_METHODS.includes(step.method);
}

export const WAIT_STATES = Object.freeze(['attached', 'detached', 'visible', 'hidden']);
// focused: the element that holds keyboard focus, as its accessibility-tree line (`button "Save"`),
// or no value when focus is on no element (the page body).
export const READ_PROPERTIES = Object.freeze(['text', 'value', 'checked', 'count', 'url', 'focused', 'response_status', 'response_text']);
export const READ_ATTRIBUTE_PATTERN = '^attribute:[A-Za-z_][-A-Za-z0-9_:.]*$';
// response_json:<RFC 6901 pointer> into the last reply's parsed body (at least one reference
// token; `~` only as ~0 or ~1).
export const READ_RESPONSE_JSON_PATTERN = '^response_json:(/([^~/]|~[01])*)+$';
// cookie:<name>: a fingerprint of the context's cookie of that name, never its value.
export const READ_COOKIE_PATTERN = '^cookie:[A-Za-z0-9_.-]+$';
// response_json_each:<array pointer>|<item pointer>: the value at <item pointer> in every element of
// the array at <array pointer> (empty: the body itself), as JSON text (`["Soccer","Tennis"]`; an empty
// item pointer is the whole element), so "some element is named Soccer" is `contains "\"Soccer\""`
// and "no element has an email key" `response_json_each:/posts|` then `absent "\"email\""`; no
// value when the pointer is not a non-empty array or any element lacks the item (never a null). response_json_length:<pointer>:
// the length of that array (0 for an empty one; no value when it is not an array).
export const READ_RESPONSE_JSON_EACH_PATTERN = '^response_json_each:(/([^~/|]|~[01])*)*\\|(/([^~/|]|~[01])*)*$';
export const READ_RESPONSE_JSON_LENGTH_PATTERN = '^response_json_length:(/([^~/]|~[01])*)*$';
// response_header:<name>: a header of the last reply (its value, or no value when it is absent;
// Set-Cookie is never readable by page code: read cookie_attribute instead).
export const READ_RESPONSE_HEADER_PATTERN = '^response_header:[A-Za-z0-9][A-Za-z0-9-]*$';
// cookie_attribute:<name>:<attribute>: one attribute of the context's cookie of that name (never
// its value): http_only and secure (booleans), same_site (Strict, Lax or None), path, domain.
export const COOKIE_ATTRIBUTES = Object.freeze(['http_only', 'secure', 'same_site', 'path', 'domain']);
export const READ_COOKIE_ATTRIBUTE_PATTERN = `^cookie_attribute:[A-Za-z0-9_.-]+:(${COOKIE_ATTRIBUTES.join('|')})$`;
// The reads about the last reply of a `request` step (response_without_request without one).
export const RESPONSE_READ_PREFIX = 'response_';
// The reads that take no locator.
export function readTakesNoLocator(p) {
  return p === 'url' || p === 'focused' || isResponseRead(p) || isCookieRead(p) || isCookieAttributeRead(p);
}
export function isResponseRead(p) {
  return typeof p === 'string' && (p === 'response_status' || p === 'response_text' || new RegExp(READ_RESPONSE_JSON_PATTERN).test(p)
    || new RegExp(READ_RESPONSE_JSON_EACH_PATTERN).test(p) || new RegExp(READ_RESPONSE_JSON_LENGTH_PATTERN).test(p)
    || new RegExp(READ_RESPONSE_HEADER_PATTERN).test(p));
}
export function isCookieAttributeRead(p) {
  return typeof p === 'string' && new RegExp(READ_COOKIE_ATTRIBUTE_PATTERN).test(p);
}
export function isCookieRead(p) {
  return typeof p === 'string' && new RegExp(READ_COOKIE_PATTERN).test(p);
}
// absent: the value read does not contain `value` (the read must still have read a value: an empty
// read is NOT_VERIFIABLE no_value_read, and a locator that matches nothing fails its step).
export const EXPECT_OPS = Object.freeze(['equals', 'contains', 'absent', 'matches', 'gt', 'lt', 'changed_from']);

// A snapshot prefix: the plan step types except read/expect, at most PREFIX_MAX_STEPS of them. A
// `request` in a prefix that is not a GET goes only to a local origin (localhost, 127.0.0.1, [::1]):
// a planner may try a POST against the app it runs, as it may click a form's submit button, and it
// counts as a plan-time action; to a remote origin it is prefix_mutation_refused.
export const PREFIX_STEP_TYPES = Object.freeze(STEP_TYPES.filter((t) => t !== 'read' && t !== 'expect'));
export const PREFIX_MAX_STEPS = 15;

// `{{NAME}}` — an environment variable resolved at run time; allowed only in a fill/select value
// and in a request's `json` string leaves, `body` and `headers` values.
const PLACEHOLDER_RE = /\{\{([A-Z_][A-Z0-9_]*)\}\}/g;
const PLACEHOLDER_FIELDS = Object.freeze({ fill: ['value'], select: ['value'], request: ['json', 'body', 'headers'] });

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
  return typeof p === 'string' && (READ_PROPERTIES.includes(p) || new RegExp(READ_ATTRIBUTE_PATTERN).test(p)
    || isResponseRead(p) || isCookieRead(p) || isCookieAttributeRead(p));
}

// The origin of an http(s) URL through the one origin parser, or null.
export function urlOrigin(url) {
  try {
    const u = new URL(url);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    const o = parseOrigin(u.origin);
    return o ? o.origin : null;
  } catch {
    return null;
  }
}

// A request's `json` problem, or null: a plain object of objects, arrays and scalar leaves, at most
// REQUEST_JSON_MAX_DEPTH deep and REQUEST_JSON_MAX_LEAVES leaves.
function jsonBodyProblem(body) {
  if (!isPlainObject(body)) return 'json must be a plain JSON object';
  let leaves = 0;
  const walk = (v, depth) => {
    if (depth > REQUEST_JSON_MAX_DEPTH) return `json nests deeper than ${REQUEST_JSON_MAX_DEPTH}`;
    if (Array.isArray(v) || isPlainObject(v)) {
      for (const x of Object.values(v)) {
        const p = walk(x, depth + 1);
        if (p) return p;
      }
      return null;
    }
    leaves += 1;
    if (v === null || typeof v === 'string' || typeof v === 'boolean') return null;
    if (typeof v === 'number' && Number.isFinite(v)) return null;
    return 'json leaves must be strings, finite numbers, booleans or null';
  };
  const p = walk(body, 1);
  if (p) return p;
  if (leaves > REQUEST_JSON_MAX_LEAVES) return `json holds ${leaves} leaves; at most ${REQUEST_JSON_MAX_LEAVES}`;
  return null;
}

// Every object key in a value (a request's json keys get the code-like check too).
function keysOf(v, outList = []) {
  if (Array.isArray(v)) v.forEach((x) => keysOf(x, outList));
  else if (isPlainObject(v)) for (const [k, x] of Object.entries(v)) { outList.push(k); keysOf(x, outList); }
  return outList;
}

// Every string leaf of a value (the `json` placeholder walk).
function stringLeaves(v, outList = []) {
  if (typeof v === 'string') outList.push(v);
  else if (Array.isArray(v) || isPlainObject(v)) for (const x of Object.values(v)) stringLeaves(x, outList);
  return outList;
}

// A copy of a value with every string leaf passed through fn.
function mapStrings(v, fn) {
  if (typeof v === 'string') return fn(v);
  if (Array.isArray(v)) return v.map((x) => mapStrings(x, fn));
  if (isPlainObject(v)) return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, mapStrings(x, fn)]));
  return v;
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
    case 'request':
      if (!REQUEST_METHODS.includes(step.method)) add('plan_schema_violation', `${at}.method must be one of ${REQUEST_METHODS.join(', ')}`);
      if (!nonEmptyString(step.url)) add('plan_schema_violation', `${at}.url must be a non-empty string`);
      if ('json' in step) {
        const p = jsonBodyProblem(step.json);
        if (p) add('plan_schema_violation', `${at}: ${p}`);
        else if (step.method === 'GET') add('plan_schema_violation', `${at}: a GET request carries no json body`);
      }
      if ('body' in step) {
        if (typeof step.body !== 'string') add('plan_schema_violation', `${at}.body must be a string (a raw request body)`);
        else if (step.body.length > REQUEST_BODY_MAX_CHARS) add('plan_schema_violation', `${at}.body holds ${step.body.length} characters; at most ${REQUEST_BODY_MAX_CHARS}`);
        if ('json' in step) add('plan_schema_violation', `${at}: a request carries json or body, never both`);
        if (step.method === 'GET') add('plan_schema_violation', `${at}: a GET request carries no body`);
      }
      if ('headers' in step) {
        const h = step.headers;
        if (!isPlainObject(h)) {
          add('plan_schema_violation', `${at}.headers must be an object of header name to string value`);
        } else {
          const names = Object.keys(h);
          if (names.length > REQUEST_HEADERS_MAX) add('plan_schema_violation', `${at}.headers names ${names.length} headers; at most ${REQUEST_HEADERS_MAX}`);
          const seen = new Set();
          for (const n of names) {
            if (!new RegExp(REQUEST_HEADER_NAME_PATTERN).test(n)) add('plan_schema_violation', `${at}.headers: ${JSON.stringify(n)} is not a header name`);
            else if (isForbiddenHeader(n)) add('plan_schema_violation', `${at}.headers: ${n} is a header the browser forbids page code to set (it would be dropped); it cannot be part of a plan`);
            if (seen.has(n.toLowerCase())) add('plan_schema_violation', `${at}.headers names ${n} twice`);
            seen.add(n.toLowerCase());
            if (typeof h[n] !== 'string') add('plan_schema_violation', `${at}.headers.${n} must be a string`);
          }
        }
      }
      break;
    case 'read':
      if (!isReadProperty(step.property)) {
        add('plan_schema_violation', `${at}.property must be one of ${READ_PROPERTIES.join(', ')}, attribute:<name>, response_json:<JSON Pointer>, response_json_each:<array pointer>|<item pointer>, response_json_length:<pointer>, response_header:<name>, cookie:<name> or cookie_attribute:<name>:<${COOKIE_ATTRIBUTES.join('|')}>`);
      } else if (readTakesNoLocator(step.property) && 'locator' in step) {
        add('plan_schema_violation', `${at}: read ${step.property} takes no locator`);
      } else if (!readTakesNoLocator(step.property) && !('locator' in step)) {
        add('plan_schema_violation', `${at}: read ${step.property} needs a locator`);
      }
      if ('at_load' in step && typeof step.at_load !== 'boolean') add('plan_schema_violation', `${at}.at_load must be true or false`);
      break;
    case 'expect': {
      const { op, value } = step;
      if (!EXPECT_OPS.includes(op)) {
        add('plan_schema_violation', `${at}.op ${JSON.stringify(op)} is not one of ${EXPECT_OPS.join(', ')}`);
      } else if ((op === 'gt' || op === 'lt') && (typeof value !== 'number' || !Number.isFinite(value))) {
        add('plan_schema_violation', `${at}: ${op} needs a number value`);
      } else if (op === 'changed_from' && typeof value !== 'boolean') {
        add('plan_schema_violation', `${at}: changed_from needs a boolean value (whether the last read must differ from the previous read)`);
      } else if ((op === 'contains' || op === 'absent' || op === 'matches') && typeof value !== 'string') {
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
//  - prefix: a snapshot prefix — only PREFIX_STEP_TYPES, at most PREFIX_MAX_STEPS steps, and a
//    request that is not a GET only to a local origin (prefix_mutation_refused).
//  - pageOrigin: the origin of the page before the first step (a snapshot's <url>), or null.
// A request's url must pass the same origin checks as a goto, and its origin must equal the origin
// of the page at that point: the last goto before it (else pageOrigin). A cross-origin fetch would
// depend on the app's CORS policy, not on Selvedge.
// Codes are plan-lint problem codes (PLAN_PROBLEMS in plan-validate.mjs). `index` is 0-based, or
// null for a problem with the whole list.
export function validateSteps(steps, { config, origins, prefix = false, pageOrigin = null } = {}) {
  const problems = [];
  if (!Array.isArray(steps)) {
    problems.push({ index: null, code: 'plan_schema_violation', detail: 'steps must be an array' });
    return problems;
  }
  if (prefix && steps.length > PREFIX_MAX_STEPS) {
    problems.push({ index: null, code: 'prefix_too_long', detail: `a prefix has ${steps.length} steps; at most ${PREFIX_MAX_STEPS}` });
  }
  let onOrigin = pageOrigin;
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
    if (prefix && t === 'request' && step.method !== 'GET' && !(typeof step.url === 'string' && isLocalOrigin(urlOrigin(step.url) || ''))) {
      add('prefix_mutation_refused', `${at}: a snapshot prefix sends a ${JSON.stringify(step.method)} request only to a local origin (it would change a remote app while planning)`);
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
    if (t === 'request') {
      for (const k of [...keysOf(step.json), ...keysOf(step.headers)]) if (isCodeLike(k)) add('code_like_content', `${at} key ${JSON.stringify(k.slice(0, 60))} looks like code`);
    }
    if ((t === 'goto' || t === 'request') && typeof step.url === 'string' && !isCodeLike(step.url)) {
      const origin = urlOrigin(step.url);
      if (!origin || !isOriginAllowed(config, step.url)) {
        add('origin_not_allowed', `${at}.url ${JSON.stringify(step.url)}: origin ${origin || '(none)'} is not allowed by selvedge.json`);
      } else if (Array.isArray(origins) && !isOriginAllowed({ origins }, step.url)) {
        add('origin_not_allowed', `${at}.url ${JSON.stringify(step.url)}: origin ${origin} is not in the plan's origins`);
      } else if (t === 'request' && origin !== onOrigin) {
        add('origin_not_allowed', `${at}.url ${JSON.stringify(step.url)}: a request goes to the origin of the page it is sent from (${onOrigin || 'no page yet: goto that origin first'}), never across origins`);
      }
    }
    if (t === 'goto') onOrigin = typeof step.url === 'string' ? urlOrigin(step.url) : null;
  });
  return problems;
}

// The `{{NAME}}` placeholders a step list uses, in first-use order (only fill/select values and
// a request's json string leaves, body and header values).
export function placeholderNames(steps) {
  const names = [];
  if (!Array.isArray(steps)) return names;
  for (const step of steps) {
    const fields = isPlainObject(step) ? PLACEHOLDER_FIELDS[step.type] : undefined;
    if (!fields) continue;
    for (const field of fields) {
      if (!(field in step)) continue;
      for (const leaf of stringLeaves(step[field])) {
        for (const m of leaf.matchAll(PLACEHOLDER_RE)) if (!names.includes(m[1])) names.push(m[1]);
      }
    }
  }
  return names;
}

// resolvePlaceholders(steps, env) → a new step list with every `{{NAME}}` in a fill/select value
// (and a request's json string leaves, body and header values) replaced by env[NAME]. The input is never changed (callers log the given steps, never the values).
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
    const fields = isPlainObject(step) ? PLACEHOLDER_FIELDS[step.type] : undefined;
    if (!fields) return step;
    const out = { ...step };
    for (const field of fields) {
      if (field in step) out[field] = mapStrings(step[field], (v) => v.replace(PLACEHOLDER_RE, (_, n) => env[n]));
    }
    return out;
  });
}
