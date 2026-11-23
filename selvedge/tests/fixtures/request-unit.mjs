// request-unit.mjs — the no-browser half of test-request-step.sh: the request step's validator,
// lint, placeholder, reply-read, evidence and comment rules, computed over selvedge/lib and printed
// as one JSON object { <arm>: value }. Not named test-*, so selvedge/tests/run.sh never runs it.
//
//   node request-unit.mjs <lib dir>
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [libDir] = process.argv.slice(2);
const load = (f) => import(pathToFileURL(path.join(libDir, f)).href);
const S = await load('plan-steps.mjs');
const V = await load('plan-validate.mjs');
const C = await load('criteria.mjs');
const X = await load('runner/steps.mjs');
const EV = await load('runner/evidence.mjs');
const CR = await load('comment-render.mjs');

const O = 'http://localhost:4100';
const OTHER = 'http://localhost:4200';
const config = { origins: [O, OTHER] };
const codes = (steps, opts = {}) => S.validateSteps(steps, { config, origins: [O, OTHER], ...opts }).map((p) => `${p.index}:${p.code}`);

const out = {};

// -- validateSteps: the step's fields, its origin rule, code-like content
const goto = { type: 'goto', url: `${O}/` };
out.valid_get = codes([goto, { type: 'request', method: 'GET', url: `${O}/api/forecast` }]);
out.valid_post = codes([goto, { type: 'request', method: 'POST', url: `${O}/api/login`, json: { email: 'a@b.c', nested: { list: [1, true, null, 'x'] } } }]);
out.bad_method = codes([goto, { type: 'request', method: 'HEAD', url: `${O}/` }]);
out.get_with_json = codes([goto, { type: 'request', method: 'GET', url: `${O}/`, json: { a: 1 } }]);
out.json_not_object = codes([goto, { type: 'request', method: 'POST', url: `${O}/`, json: '{"a":1}' }]);
out.json_array = codes([goto, { type: 'request', method: 'POST', url: `${O}/`, json: [1] }]);
out.json_too_deep = codes([goto, { type: 'request', method: 'POST', url: `${O}/`, json: { a: { b: { c: { d: { e: { f: 1 } } } } } } }]);
out.header_field = codes([goto, { type: 'request', method: 'GET', url: `${O}/`, headers: { authorization: 'x' } }]);
out.cross_origin = codes([goto, { type: 'request', method: 'GET', url: `${OTHER}/api/x` }]);
out.no_goto_first = codes([{ type: 'request', method: 'GET', url: `${O}/api/x` }]);
out.after_second_goto = codes([goto, { type: 'goto', url: `${OTHER}/` }, { type: 'request', method: 'GET', url: `${OTHER}/api/x` }]);
out.unlisted_origin = S.validateSteps([{ type: 'goto', url: 'http://localhost:4999/' }, { type: 'request', method: 'GET', url: 'http://localhost:4999/api' }], { config, origins: [O, OTHER] }).map((p) => `${p.index}:${p.code}`);
out.code_like_leaf = codes([goto, { type: 'request', method: 'POST', url: `${O}/`, json: { a: '${process.env.X}' } }]);
out.code_like_key = codes([goto, { type: 'request', method: 'POST', url: `${O}/`, json: { 'eval(1)': 'x' } }]);
out.reads_no_locator = codes([goto, { type: 'request', method: 'GET', url: `${O}/` },
  { type: 'read', property: 'response_status' }, { type: 'read', property: 'response_text' },
  { type: 'read', property: 'response_json:/0/createdBy/name' }, { type: 'read', property: 'response_json:/a~1b/~0c' }, { type: 'read', property: 'cookie:next-auth.session_token' }]);
out.reads_with_locator = codes([goto, { type: 'request', method: 'GET', url: `${O}/` }, { type: 'read', property: 'response_status', locator: { testid: 'x' } }, { type: 'read', property: 'cookie:s', locator: { testid: 'x' } }]);
out.bad_pointer = codes([goto, { type: 'request', method: 'GET', url: `${O}/` }, { type: 'read', property: 'response_json:a/b' }, { type: 'read', property: 'response_json:/a~2' }, { type: 'read', property: 'response_json:' }]);
out.is_action = [
  S.isActionStep({ type: 'request', method: 'GET', url: O }),
  ...['POST', 'PUT', 'PATCH', 'DELETE'].map((m) => S.isActionStep({ type: 'request', method: m, url: O })),
  S.isActionStep({ type: 'click', locator: { testid: 'x' } }),
  S.isActionStep({ type: 'goto', url: O }),
];

// -- the snapshot prefix: a GET only, from the snapshot's own page origin
out.prefix_get = S.validateSteps([{ type: 'request', method: 'GET', url: `${O}/api/x` }], { config, prefix: true, pageOrigin: O }).map((p) => p.code);
out.prefix_post = S.validateSteps([{ type: 'request', method: 'POST', url: `${O}/api/x`, json: { a: 1 } }], { config, prefix: true, pageOrigin: O }).map((p) => p.code);
out.prefix_delete = S.validateSteps([{ type: 'request', method: 'DELETE', url: `${O}/api/x` }], { config, prefix: true, pageOrigin: O }).map((p) => p.code);

// -- the plan lint (validatePlan): reply reads, cookie reads, the negative baseline
const crit = (texts) => {
  const criteria = texts.map((text) => ({ id: C.criterionId(text), text }));
  return { criteria: { schema_version: 1, criteria }, ids: criteria.map((c) => c.id) };
};
const lint = (steps, { polarity = 'positive', text = 'GET /api/forecast without a session answers 401' } = {}) => {
  const { criteria, ids } = crit([text]);
  const plan = {
    schema_version: 1,
    target: 'web',
    criteria_sha256: C.criteriaSha256(criteria.criteria),
    origins: [O],
    steps_by_criterion: { [ids[0]]: { interpretation: 'The reply says so.', polarity, unverified_assumptions: [], steps } },
  };
  return V.validatePlan(plan, { criteria, config: { origins: [O] } }).map((p) => p.code);
};
const req = (method = 'GET', extra = {}) => ({ type: 'request', method, url: `${O}/api/forecast`, ...extra });
out.lint_acceptance = lint([goto, req(), { type: 'read', property: 'response_status' }, { type: 'expect', op: 'equals', value: 401 }]);
out.lint_no_request = lint([goto, { type: 'read', property: 'response_status' }, { type: 'expect', op: 'equals', value: 401 }]);
out.lint_json_no_request = lint([goto, { type: 'read', property: 'response_json:/error' }, { type: 'expect', op: 'equals', value: 'unauthorized' }]);
out.lint_read_before_request = lint([goto, { type: 'read', property: 'response_text' }, req(), { type: 'read', property: 'response_status' }, { type: 'expect', op: 'equals', value: 401 }]);
const cookieSteps = (op, value, baseline) => [goto, ...(baseline ? [{ type: 'read', property: 'cookie:sid' }] : []), req('POST', { json: { email: 'a' } }), { type: 'read', property: 'cookie:sid' }, { type: 'expect', op, value }];
out.lint_cookie_changed = lint(cookieSteps('changed_from', true, true), { text: 'Signing in sets a session cookie' });
out.lint_cookie_no_baseline = lint(cookieSteps('changed_from', true, false), { text: 'Signing in sets a session cookie' });
out.lint_cookie_matches = lint(cookieSteps('matches', '^sha256:', true), { text: 'Signing in sets a session cookie' });
out.lint_cookie_contains = lint(cookieSteps('contains', '', true), { text: 'Signing in sets a session cookie' });
out.lint_cookie_gt = lint(cookieSteps('gt', 0, true), { text: 'Signing in sets a session cookie' });
out.lint_cookie_equals = lint(cookieSteps('equals', 'sha256:0123456789abcdef', true), { text: 'Signing in sets a session cookie' });
out.lint_negative_post_no_baseline = lint([goto, req('POST', { json: { a: 1 } }), { type: 'read', property: 'response_status' }, { type: 'expect', op: 'changed_from', value: false }], { polarity: 'negative', text: 'Posting an empty form does not change the count' });
out.lint_negative_get_no_baseline = lint([goto, req('GET'), { type: 'read', property: 'response_status' }, { type: 'expect', op: 'equals', value: 401 }], { polarity: 'negative', text: 'GET /api/forecast without a session does not answer 200' });
out.problems = V.PLAN_PROBLEMS;

// -- placeholders in json leaves
const pSteps = [goto, req('POST', { json: { email: '{{SHOP_USER}}', password: '{{PASS}}', deep: { list: ['{{PASS}}-x', 2] } } })];
out.placeholder_names = S.placeholderNames(pSteps);
const resolved = S.resolvePlaceholders(pSteps, { SHOP_USER: 'alice', PASS: 'hunter2$&' });
out.placeholder_resolved = resolved[1].json;
out.placeholder_input_kept = pSteps[1].json;
try {
  S.resolvePlaceholders(pSteps, { SHOP_USER: 'alice' });
  out.placeholder_unset = 'no throw';
} catch (e) {
  out.placeholder_unset = [e.reason, e.blocked, (e.names || []).join('+')].join('|');
}

// -- reply reads
const body = JSON.stringify([{ createdBy: { name: 'Ada' }, 'a/b': { '~c': 7 }, ok: true, gone: null, list: [1, 2] }]);
out.pointer = {
  name: X.responseJsonValue(body, '/0/createdBy/name'),
  escaped: X.responseJsonValue(body, '/0/a~1b/~0c'),
  bool: X.responseJsonValue(body, '/0/ok'),
  missing: X.responseJsonValue(body, '/0/nope'),
  out_of_range: X.responseJsonValue(body, '/5'),
  leading_zero: X.responseJsonValue(body, '/0/list/01'),
  index: X.responseJsonValue(body, '/0/list/1'),
  json_null: X.responseJsonValue(body, '/0/gone'),
  object: X.responseJsonValue(body, '/0/createdBy'),
  array: X.responseJsonValue(body, '/0/list'),
  not_json: X.responseJsonValue('<html>401</html>', '/0'),
};
const fp = X.cookieFingerprint('apisess-7f3c9d-secretvalue');
out.fingerprint = { fp, again: X.cookieFingerprint('apisess-7f3c9d-secretvalue'), other: X.cookieFingerprint('apisess-7f3c9d-othervalue') };
out.text_cap = X.RESPONSE_TEXT_CAP;

// -- the evidence line of a request step: method, url, json keys and status, never the body
const reqStep = req('POST', { json: { password: '{{PASS}}', email: 'a@b.c' } });
const line = EV.stepLine({ criterion: 'c-000000000001', index: 1, step: reqStep, outcome: EV.STEP_OUTCOMES.ok, durationMs: 3, status: 200 });
out.evidence_line = line;
out.evidence_line_problem = EV.evidenceLineProblem(line);
out.evidence_request_on_click = EV.evidenceLineProblem({ ...EV.stepLine({ criterion: 'c-1', index: 0, step: { type: 'click', locator: { testid: 'x' } }, outcome: 'ok', durationMs: 1 }), request: line.request });
const noRequest = { ...line };
delete noRequest.request;
out.evidence_request_missing = EV.evidenceLineProblem(noRequest);
out.evidence_request_body = EV.evidenceLineProblem({ ...line, request: { ...line.request, json: { password: 'x' } } });

// -- the comment: a request step shows its method and path, never its json; a cookie read's value
//    is never published, even with read_values on
const { criteria, ids } = crit(['Signing in sets a session cookie', 'GET /api/forecast without a session answers 401']);
const verdictEntry = (readValue) => ({
  verdict: 'PASS', evidence_class: 'structured-read', read_value: readValue, matched: true, expected: { op: 'equals', value: 401 },
  reason: null, failed_step: null, interpretation: 'x', unverified_assumptions: [], steps: [],
});
const verdict = { schema_version: 1, target: 'web', plan_sha256: 'a'.repeat(64), plan_revision: 1, prior_revisions: [], criteria: { [ids[0]]: verdictEntry(fp), [ids[1]]: verdictEntry(401) } };
const plan = {
  steps_by_criterion: {
    [ids[0]]: { steps: cookieSteps('changed_from', true, true).map((s) => (s.type === 'request' ? { ...s, json: { email: 'a', password: '{{PASS}}' } } : s)) },
    [ids[1]]: { steps: [goto, req(), { type: 'read', property: 'response_status' }, { type: 'expect', op: 'equals', value: 401 }] },
  },
};
out.comment = CR.renderComment({ verdict, plan, criteria: criteria.criteria, readValues: true });
out.fp_hex = fp.slice('sha256:'.length);

process.stdout.write(`${JSON.stringify(out)}\n`);
