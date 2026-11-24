// runner/steps.mjs — the ONE plan-step executor: how a typed plan step drives a Playwright page.
//
// `selvedge snapshot` (lib/snapshot.mjs) runs a prefix through runStep, and `selvedge run`
// (runner/execute.mjs) runs a criterion's steps through runStep, readValue and expectMatches. There
// is no second executor: a step means the same thing in a snapshot prefix and in a run.
//
//   locate(page, locator)      the Playwright locator for a plan locator (role / label / text /
//                              testid; never CSS or XPath)
//   navigate(page, url)        goto, failing on an HTTP status >= 400 (naming the guard's reason
//                              when the guard refused the request)
//   runStep(page, step, ctx)   one resolved goto / click / fill / select / check / press / wait_for
//                              / request step; any other type throws (read and expect are not
//                              actions). A request returns its reply and keeps it as ctx.state.reply
//   sendRequest(page, step, blocks)
//                              one `request` step (below); → { status, text, content_type, truncated }
//   readValue(page, step, state)
//                              one `read` step's value: text (innerText, trimmed), value
//                              (inputValue), checked (boolean), count (number), url, or
//                              attribute:<name> (string, or null when the attribute is absent);
//                              focused (the focused element's aria-snapshot line, e.g. `button
//                              "Save"`, or null when focus is on no element);
//                              response_header:<name> (string, or null) of state.reply;
//                              response_json_each:<array>|<item> (JSON text of each element's
//                              value, or null) and response_json_length:<array> (a number, or
//                              null) of state.reply;
//                              cookie_attribute:<name>:<attr> (http_only / secure booleans,
//                              same_site / path / domain strings; null when there is no cookie);
//                              response_status (number), response_text (string, trimmed like
//                              text: a body's trailing newline is not part of its value),
//                              response_json:<pointer> (a scalar, or null) of state.reply;
//                              cookie:<name> (cookieFingerprint, or null when there is no cookie)
//   readEntry(step, value)     one read as expectMatches takes it: { key, value }, the key naming
//                              the read's locator and property
//   expectMatches(step, reads) whether an `expect` step holds over the criterion's reads so far
//                              (absent: the last read does not contain the value)
//                              (the last read is the value checked; changed_from compares it with
//                              the previous read of the same locator and property)
//
// The request step. The runner sends it as a fetch from INSIDE the page: pageFetch is a fixed,
// runner-owned function, run by page.evaluate with the method, URL and body passed as ARGUMENTS,
// never as source text. So the request leaves through the browser and both guard layers check it
// (route-guard.mjs's context.route and the proxy), as the page's own requests are. Playwright's
// APIRequestContext (`context.request`) is never used: it bypasses context.route, so the route
// layer's host_not_allowed and remote_mutation_refused would not apply (probed with Playwright
// 1.65.1). Neither is a Node-side HTTP client. The fetch is same-origin with the page (the lint's
// origin rule), credentials 'same-origin' (the context's cookies go with it), redirect 'follow',
// cache 'no-store'; a json body is sent as application/json, a raw `body` as given (text/plain
// unless the step's `headers` name a content-type), with the step's `headers` added. The reply
// text is kept up to RESPONSE_TEXT_CAP characters (truncated: true past it), and its headers
// (lower-cased names; Set-Cookie is never visible to page code) up to RESPONSE_HEADERS_CAP. A refusal by either guard layer throws
// GuardRefusal naming the guard's reason (host_not_allowed, remote_mutation_refused, ...): the
// route layer aborts the fetch, and the runner finds its record among the guard's blocks; the
// proxy answers 403 with its X-Selvedge-Blocked header, read like reasonOfResponse does for goto.
//
// cookie:<name> reads the context's cookies (context.cookies(), which sees HttpOnly cookies page code
// cannot) for the page's URL and returns cookieFingerprint(value): `sha256:` + the first
// COOKIE_FINGERPRINT_HEX hex digits of the value's sha256. Never the value: two reads compare
// (changed_from) without any read holding it.
//
// Playwright's own actionability checks stay on (no `force`): a click on a hidden or covered
// element, or a locator that matches nothing or more than one element (strict mode), fails the step
// after the page's default timeout.
//
// Node >= 18, standard library only (Playwright is the caller's; never imported here).
import { createHash } from 'node:crypto';
import { REASONS } from '../env-config.mjs';
import { BLOCKED_HEADER } from './proxy.mjs';
import { reasonOfResponse } from './route-guard.mjs';

const ATTRIBUTE_PREFIX = 'attribute:';
const RESPONSE_JSON_PREFIX = 'response_json:';
const RESPONSE_JSON_EACH_PREFIX = 'response_json_each:';
const RESPONSE_JSON_LENGTH_PREFIX = 'response_json_length:';
const RESPONSE_HEADER_PREFIX = 'response_header:';
const COOKIE_PREFIX = 'cookie:';
const COOKIE_ATTRIBUTE_PREFIX = 'cookie_attribute:';
// cookie_attribute's names → the Playwright cookie field.
const COOKIE_FIELDS = Object.freeze({ http_only: 'httpOnly', secure: 'secure', same_site: 'sameSite', path: 'path', domain: 'domain' });

export const RESPONSE_TEXT_CAP = 64 * 1024;
export const RESPONSE_HEADERS_CAP = 64;
export const COOKIE_FINGERPRINT_HEX = 16;

// A refusal by one of the guard's layers, while a request step ran: `reason` is the guard's.
export class GuardRefusal extends Error {
  constructor(reason, message) {
    super(message);
    this.name = 'GuardRefusal';
    this.reason = reason;
  }
}

// The reasons a guard layer refuses a request with (route-guard.mjs, proxy.mjs).
export const GUARD_REASONS = Object.freeze([REASONS.host_not_allowed, REASONS.remote_resolves_private, REASONS.remote_mutation_refused, REASONS.proxy_unavailable]);

// The fixed page-side function a request step runs (header). Self-contained: page.evaluate sends
// its source to the page, so it refers to nothing outside itself; everything it needs is an argument.
async function pageFetch([method, url, body, headers, cap, headerCap, blockedHeader]) {
  try {
    const init = { method, credentials: 'same-origin', redirect: 'follow', cache: 'no-store', headers: headers || {} };
    if (body !== null) init.body = body;
    const res = await fetch(url, init);
    const text = await res.text();
    const replyHeaders = {};
    let n = 0;
    res.headers.forEach((v, k) => {
      if (n < headerCap) replyHeaders[k] = v;
      n += 1;
    });
    return {
      ok: true,
      status: res.status,
      contentType: res.headers.get('content-type'),
      blocked: res.headers.get(blockedHeader),
      headers: replyHeaders,
      text: text.length > cap ? text.slice(0, cap) : text,
      truncated: text.length > cap,
    };
  } catch (e) {
    return { ok: false, error: `${e && e.name}: ${e && e.message}` };
  }
}

const originOfUrl = (u) => {
  try {
    return new URL(u).origin;
  } catch {
    return null;
  }
};

// sendRequest(page, step, blocks) → the reply (header). `blocks` is the guard's refusal list
// (openGuardedContext's `blocks`), read to name the reason of a request the route layer aborted.
export async function sendRequest(page, step, blocks = null) {
  const url = new URL(step.url, page.url()).href;
  const headers = { ...(step.headers || {}) };
  const named = (h) => Object.keys(headers).some((k) => k.toLowerCase() === h);
  let body = null;
  if (step.json !== undefined) {
    body = JSON.stringify(step.json);
    if (!named('content-type')) headers['content-type'] = 'application/json';
  } else if (typeof step.body === 'string') {
    body = step.body;
  }
  const before = Array.isArray(blocks) ? blocks.length : 0;
  const r = await page.evaluate(pageFetch, [step.method, url, body, headers, RESPONSE_TEXT_CAP, RESPONSE_HEADERS_CAP, BLOCKED_HEADER]);
  if (!r || r.ok !== true) {
    const fresh = Array.isArray(blocks) ? blocks.slice(before) : [];
    const origin = originOfUrl(url);
    const refusal = fresh.find((b) => b.url === url || b.redirectedFrom === url) || fresh.find((b) => b.origin === origin) || null;
    if (refusal && GUARD_REASONS.includes(refusal.reason)) {
      throw new GuardRefusal(refusal.reason, `${step.method} ${url}: the guard refused it (${refusal.reason}, ${refusal.layer} layer)`);
    }
    throw new Error(`${step.method} ${url}: the request failed (${r && r.error ? r.error : 'no reply'})`);
  }
  if (r.status === 403 && GUARD_REASONS.includes(r.blocked)) {
    throw new GuardRefusal(r.blocked, `${step.method} ${url}: the guard refused it (${r.blocked}, proxy layer)`);
  }
  return { status: r.status, text: r.text, content_type: r.contentType, headers: r.headers || {}, truncated: r.truncated === true };
}

// cookieFingerprint(value) → `sha256:<COOKIE_FINGERPRINT_HEX hex>` (never the value itself).
export function cookieFingerprint(value) {
  return `sha256:${createHash('sha256').update(String(value)).digest('hex').slice(0, COOKIE_FINGERPRINT_HEX)}`;
}

// resolvePointer(doc, pointer) → the RFC 6901 pointer's value in doc, or undefined.
export function resolvePointer(doc, pointer) {
  if (pointer === '') return doc;
  if (!pointer.startsWith('/')) return undefined;
  let at = doc;
  for (const raw of pointer.slice(1).split('/')) {
    const token = raw.replace(/~1/g, '/').replace(/~0/g, '~');
    if (Array.isArray(at)) {
      if (!/^(0|[1-9][0-9]*)$/.test(token) || Number(token) >= at.length) return undefined;
      at = at[Number(token)];
    } else if (at !== null && typeof at === 'object' && Object.prototype.hasOwnProperty.call(at, token)) {
      at = at[token];
    } else {
      return undefined;
    }
  }
  return at;
}

// The value a response_json:<pointer> read gives: a string, number or boolean; null when the body
// is not JSON, the pointer does not resolve, or it names null, an object or an array.
export function responseJsonValue(text, pointer) {
  let doc;
  try {
    doc = JSON.parse(text);
  } catch {
    return null;
  }
  const v = resolvePointer(doc, pointer);
  return ['string', 'number', 'boolean'].includes(typeof v) ? v : null;
}

// The array a response_json_each / response_json_length read looks at: the parsed body's value at
// `pointer` when it is an array, else null (not JSON, no such value, not an array).
function responseArray(text, pointer) {
  let doc;
  try {
    doc = JSON.parse(text);
  } catch {
    return null;
  }
  const v = resolvePointer(doc, pointer);
  return Array.isArray(v) ? v : null;
}

// response_json_each:<array>|<item> → JSON text of each element's value at <item> (null where it is
// missing), or null when <array> is not a non-empty array.
export function responseJsonEach(text, spec) {
  const cut = spec.indexOf('|');
  const list = responseArray(text, spec.slice(0, cut));
  if (!list || list.length === 0) return null;
  return JSON.stringify(list.map((el) => {
    const v = resolvePointer(el, spec.slice(cut + 1));
    return v === undefined ? null : v;
  }));
}

// response_json_length:<pointer> → the array's length, or null when it is not an array.
export function responseJsonLength(text, pointer) {
  const list = responseArray(text, pointer);
  return list ? list.length : null;
}

// The Playwright locator for a plan-step locator (role / label / text / testid; never CSS).
export function locate(page, loc) {
  if ('role' in loc) {
    const opts = {};
    if ('name' in loc) opts.name = loc.name;
    if ('exact' in loc) opts.exact = loc.exact;
    return page.getByRole(loc.role, opts);
  }
  if ('label' in loc) return page.getByLabel(loc.label);
  if ('text' in loc) return page.getByText(loc.text);
  return page.getByTestId(loc.testid);
}

// Navigate, and fail on an HTTP error status (naming the guard's reason when the guard refused it).
export async function navigate(page, url) {
  const response = await page.goto(url);
  if (response && response.status() >= 400) {
    const reason = reasonOfResponse(response);
    throw new Error(`${url} answered HTTP ${response.status()}${reason ? ` (the guard refused it: ${reason})` : ''}`);
  }
}

// Run one validated, resolved step. Playwright's strict mode makes a locator that matches more than
// one element fail the step, as a locator matching nothing does (after the timeout).
export async function runStep(page, step, ctx = {}) {
  switch (step.type) {
    case 'request': {
      const reply = await sendRequest(page, step, ctx.blocks);
      if (ctx.state) ctx.state.reply = reply;
      return reply;
    }
    case 'goto':
      await navigate(page, step.url);
      return;
    case 'click':
      await locate(page, step.locator).click();
      return;
    case 'fill':
      await locate(page, step.locator).fill(step.value);
      return;
    case 'select':
      await locate(page, step.locator).selectOption(step.value);
      return;
    case 'check':
      await locate(page, step.locator).setChecked(step.checked !== false);
      return;
    case 'press':
      if (step.locator) await locate(page, step.locator).press(step.key);
      else await page.keyboard.press(step.key);
      return;
    case 'wait_for':
      await locate(page, step.locator).waitFor({ state: step.state });
      return;
    default:
      // read / expect go through readValue / expectMatches; nothing else is a step.
      throw new Error(`step type ${JSON.stringify(step.type)} is not an action runStep runs`);
  }
}

// readValue(page, step) → the value one `read` step reads (see the header).
export async function readValue(page, step, state = {}) {
  const p = step.property;
  if (p === 'url') return page.url();
  if (p === 'focused') {
    // runner-owned: :focus is never a plan locator (plans hold no CSS)
    const f = page.locator('*:focus');
    if ((await f.count()) === 0) return null;
    const line = String(await f.first().ariaSnapshot()).split('\n')[0].replace(/^\s*-\s*/, '').replace(/:$/, '').trim();
    return line === '' ? null : line;
  }
  if (typeof p === 'string' && p.startsWith(COOKIE_ATTRIBUTE_PREFIX)) {
    const rest = p.slice(COOKIE_ATTRIBUTE_PREFIX.length);
    const cut = rest.lastIndexOf(':');
    const name = rest.slice(0, cut);
    const field = COOKIE_FIELDS[rest.slice(cut + 1)];
    const found = (await page.context().cookies([page.url()])).find((c) => c.name === name);
    return found && field && found[field] !== undefined ? found[field] : null;
  }
  if (typeof p === 'string' && p.startsWith(COOKIE_PREFIX)) {
    const name = p.slice(COOKIE_PREFIX.length);
    const found = (await page.context().cookies([page.url()])).find((c) => c.name === name);
    return found ? cookieFingerprint(found.value) : null;
  }
  if (p === 'response_status' || p === 'response_text' || (typeof p === 'string' && (p.startsWith(RESPONSE_JSON_PREFIX) || p.startsWith(RESPONSE_JSON_EACH_PREFIX)
    || p.startsWith(RESPONSE_JSON_LENGTH_PREFIX) || p.startsWith(RESPONSE_HEADER_PREFIX)))) {
    const reply = state && state.reply;
    if (!reply) throw new Error(`read ${p}: no request step has replied in this criterion`);
    if (p === 'response_status') return reply.status;
    if (p.startsWith(RESPONSE_HEADER_PREFIX)) {
      const v = (reply.headers || {})[p.slice(RESPONSE_HEADER_PREFIX.length).toLowerCase()];
      return typeof v === 'string' ? v : null;
    }
    if (p === 'response_text') return String(reply.text).trim();
    if (p.startsWith(RESPONSE_JSON_EACH_PREFIX)) return responseJsonEach(reply.text, p.slice(RESPONSE_JSON_EACH_PREFIX.length));
    if (p.startsWith(RESPONSE_JSON_LENGTH_PREFIX)) return responseJsonLength(reply.text, p.slice(RESPONSE_JSON_LENGTH_PREFIX.length));
    return responseJsonValue(reply.text, p.slice(RESPONSE_JSON_PREFIX.length));
  }
  const loc = locate(page, step.locator);
  if (p === 'text') return String(await loc.innerText()).trim();
  if (p === 'value') return await loc.inputValue();
  if (p === 'checked') return await loc.isChecked();
  if (p === 'count') return await loc.count();
  if (typeof p === 'string' && p.startsWith(ATTRIBUTE_PREFIX)) {
    // getAttribute does not wait; waitFor makes an absent element fail the step, as the others do
    await loc.waitFor({ state: 'attached' });
    return await loc.getAttribute(p.slice(ATTRIBUTE_PREFIX.length));
  }
  throw new Error(`read property ${JSON.stringify(p)} is not one readValue reads`);
}

const isNumberLike = (v) => (typeof v === 'number' && Number.isFinite(v)) || (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
// JSON with object keys sorted, so {role, name} and {name, role} are one locator.
const canonical = (v) => {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (v !== null && typeof v === 'object') return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`;
  return JSON.stringify(v === undefined ? null : v);
};

// readEntry(step, value) → { key, value }: what a `read` step returned, keyed by its locator and
// property (a `url` read has no locator).
export function readEntry(step, value) {
  return { key: canonical({ locator: step.locator === undefined ? null : step.locator, property: step.property }), value };
}

// expectMatches(step, reads) → true when the expect holds. `reads` is every read the criterion's
// read steps returned so far, in order, as readEntry built them; the last one is checked. No read,
// or a null last read, never matches (except changed_from, which compares the last read with the
// previous read of the same locator and property; with no such read it never matches).
export function expectMatches(step, reads) {
  const list = Array.isArray(reads) ? reads : [];
  if (list.length === 0) return false;
  const lastEntry = list[list.length - 1];
  const last = lastEntry.value;
  const { op, value } = step;
  switch (op) {
    case 'equals':
      return last !== null && last !== undefined && String(last) === String(value);
    case 'contains':
      return typeof last === 'string' && last.includes(value);
    case 'absent':
      // no value read never matches (as contains); a number or boolean is compared as its text
      return last !== null && last !== undefined && !String(last).includes(value);
    case 'matches':
      return last !== null && last !== undefined && new RegExp(value).test(String(last));
    case 'gt':
      return isNumberLike(last) && Number(last) > value;
    case 'lt':
      return isNumberLike(last) && Number(last) < value;
    case 'changed_from': {
      let previous = null;
      for (let i = list.length - 2; i >= 0; i -= 1) {
        if (list[i].key === lastEntry.key) {
          previous = list[i];
          break;
        }
      }
      if (previous === null) return false;
      const changed = !same(last, previous.value);
      return changed === value;
    }
    default:
      throw new Error(`expect op ${JSON.stringify(op)} is not one expectMatches knows`);
  }
}
