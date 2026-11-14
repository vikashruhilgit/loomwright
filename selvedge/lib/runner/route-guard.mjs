// route-guard.mjs — the guarded browser: launch options, the loopback env-var refusal, a guarded
// context, and the `context.route` second layer in front of the runner-owned proxy (proxy.mjs).
//
// Two independent layers check every browser request by origin:
//   proxy  (proxy.mjs) — every TCP connection Chromium makes, including redirect hops, ws/wss and
//          CONNECT tunnels the route handler never sees. Chromium has no other way out: the launch
//          options carry the proxy and nothing else (no `bypass`, no `direct://`), and Playwright
//          forces loopback through it unless PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK is
//          set — so that variable makes openGuardedContext refuse before launching.
//   route  (this file) — `context.route('**/*')`, installed before any page exists, aborts a request
//          to an unlisted origin (host_not_allowed) and, without allow_remote_mutation, any request
//          to a remote origin whose method is not GET, HEAD or OPTIONS (remote_mutation_refused) —
//          including over https, where the proxy sees host and port only.
//
// Redirects: Chromium follows a redirect without showing the next hop to `context.route`, and over
// https the proxy sees only CONNECT host:port, so neither layer would see the method of a redirect
// hop. Chromium keeps the method and body on 307/308, and on 301/302 for every method but POST
// (POST becomes GET); 303 makes every method but HEAD a GET (nextRedirectMethod). So when a remote
// origin is listed and allow_remote_mutation is off, a non-read request the route layer allows is
// not continued: the route layer sends it itself (`route.fetch({ maxRedirects: 0 })`, through the
// same proxy). A 3xx whose next hop is a read is fulfilled to the page and Chromium follows it
// (the proxy checks its host). A 3xx whose next hop keeps a non-read method depends on the
// request's redirect mode, which Playwright does not expose to a route handler, so the page tells
// it: under such a config an init script wraps the page's `fetch` and tags every non-read fetch
// with its redirect and credentials modes (FETCH_MODE_HEADER, removed before anything is sent).
//   follow   (every navigation, form and XHR, and a fetch tagged follow): the route layer checks
//            the hop with checkRequest before sending it — a hop to a remote origin is refused
//            remote_mutation_refused (layer 'route') — and follows it itself, with the browser's
//            redirect rules for credentials: Authorization is dropped once a hop changes origin,
//            and cookies go only where the credentials mode lets them (redirectHopHeaders).
//   manual, error, or unknown (a fetch with no valid tag: a Worker's fetch, a no-cors POST): the
//            hop is never sent by the route layer. The page gets the 3xx with its Location
//            withheld (WITHHELD_LOCATION), so Chromium applies the page's own mode: `manual` gives
//            an opaque redirect, `error` a network error, and a fetch that does follow goes to a
//            host neither layer lets through (it fails; nothing reaches a real server).
// Costs of the follow path: the page gets the final response under the URL it asked for (not the
// redirect target), and cookies on a followed hop are the context's for that URL (SameSite is not
// applied). Every other request is continued untouched (sent once, by Chromium).
// Service workers are blocked (`serviceWorkers: 'block'`), so no worker can answer or issue
// requests outside the route layer.
//
// Each refusal is recorded as { reason, origin, host, layer: 'route' | 'proxy', … } in the guard's
// `blocks`. A request that fails because the proxy is gone (ERR_PROXY_CONNECTION_FAILED, or a
// route.fetch that cannot reach the closed proxy) is recorded as proxy_unavailable (layer 'proxy'):
// the browser fails closed, it never falls back to a direct connection.
//
// Playwright is injected: the caller passes its own `chromium` (openGuardedContext({ chromium, … })).
// This module never imports `playwright`, so the runner decides how it is packaged.
//
// Node >= 18, standard library only.
import { EnvError, REASONS, isLocalOrigin, isOriginAllowed, parseOrigin } from '../env-config.mjs';
import { BLOCKED_HEADER, startProxy } from './proxy.mjs';

export const LOOPBACK_ENV = 'PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK';

// The route layer's own read-only method set: without allow_remote_mutation a remote origin gets
// these methods and no other (proxy.mjs keeps its own; the layers are independent).
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

// The most redirect hops the route layer follows for one request (Chromium's own limit is 20).
const MAX_REDIRECT_HOPS = 20;

// The header the page's fetch wrapper (tagFetchModes) puts on every non-read fetch under a config
// whose non-read requests the route layer sends itself: `redirect=<mode>;credentials=<mode>`. The
// route layer reads it and removes it; it never leaves the browser.
export const FETCH_MODE_HEADER = 'x-selvedge-fetch-mode';

// The Location a 3xx is handed to the page with when the route layer will not follow it: an
// unlisted host under the reserved .invalid TLD, so a browser that follows it anyway is refused.
export const WITHHELD_LOCATION = 'http://selvedge-redirect-withheld.invalid/';

const REDIRECT_MODES = new Set(['follow', 'manual', 'error']);
const CREDENTIALS_MODES = new Set(['omit', 'same-origin', 'include']);

// The init script (runs in every frame before the page's own scripts): wraps fetch so a non-read
// request carries its redirect and credentials modes in `tag`. A Request whose headers cannot take
// the tag (mode no-cors) goes untagged. Self-contained: it is serialized into the page.
export function tagFetchModes(tag) {
  const original = globalThis.fetch;
  if (typeof original !== 'function') return;
  const reads = ['GET', 'HEAD', 'OPTIONS'];
  globalThis.fetch = function fetch(input, init) {
    let request;
    try {
      request = new Request(input, init);
    } catch {
      return original.apply(this, arguments);
    }
    if (reads.includes(request.method.toUpperCase())) return original.call(this, request);
    const headers = new Headers(request.headers);
    headers.set(tag, `redirect=${request.redirect};credentials=${request.credentials}`);
    return original.call(this, new Request(request, { headers }));
  };
}

// The redirect and credentials modes of a request the route layer sends itself. A fetch carries
// them in FETCH_MODE_HEADER; one without a valid tag has redirect mode 'unknown'. Every other
// resource type (navigation, form, XHR, beacon) can only follow; its credentials are taken as
// 'same-origin', the choice that sends fewer credentials on a cross-origin hop.
export function requestModes(resourceType, headers) {
  if (resourceType !== 'fetch') return { redirect: 'follow', credentials: 'same-origin' };
  const m = /^redirect=([a-z-]+);credentials=([a-z-]+)$/.exec(String((headers && headers[FETCH_MODE_HEADER]) || ''));
  if (!m || !REDIRECT_MODES.has(m[1]) || !CREDENTIALS_MODES.has(m[2])) return { redirect: 'unknown', credentials: 'same-origin' };
  return { redirect: m[1], credentials: m[2] };
}

function originOf(url) {
  try {
    const o = new URL(url).origin;
    return o === 'null' ? null : o;
  } catch {
    return null;
  }
}

// The headers for a followed redirect hop, by the browser's fetch rules. `base` is the original
// request's headers (without FETCH_MODE_HEADER). Authorization is dropped once any hop so far
// changed origin (`crossed`). Cookies: the context's for the hop URL (route.fetch adds them when no
// Cookie header is given) when credentials are 'include', or 'same-origin' while every URL so far
// has the page's origin (`tainted` false); otherwise none — an empty Cookie header stops route.fetch
// adding them.
export function redirectHopHeaders(base, { credentials, crossed, tainted }) {
  const headers = { ...base };
  delete headers.cookie;
  if (crossed) delete headers.authorization;
  if (!(credentials === 'include' || (credentials === 'same-origin' && !tainted))) headers.cookie = '';
  return headers;
}

// The method Chromium sends on the hop after a redirect with this status (the Fetch spec rule), or
// null when Chromium does not follow the status. 307/308 keep the method and body; 301/302 keep
// them unless the method is POST (then GET, no body); 303 turns every method but HEAD into GET.
// The result is upper-cased for the route layer's checks.
export function nextRedirectMethod(status, method) {
  const m = String(method).toUpperCase();
  if (status === 307 || status === 308) return m;
  if (status === 301 || status === 302) return m === 'POST' ? 'GET' : m;
  if (status === 303) return m === 'HEAD' ? 'HEAD' : 'GET';
  return null;
}

// URL schemes that never open a network connection; the route layer lets them through.
const NO_NETWORK_SCHEMES = new Set(['data:', 'blob:', 'about:']);

// Chromium net error → BLOCKED reason, for failures the browser reports rather than a layer refusing.
const FAILURE_REASONS = Object.freeze({
  'net::ERR_PROXY_CONNECTION_FAILED': REASONS.proxy_unavailable,
});

// The BLOCKED reason a browser request failure stands for, or null when it is not a guard outcome.
export function reasonForFailure(errorText) {
  if (typeof errorText !== 'string') return null;
  for (const [needle, reason] of Object.entries(FAILURE_REASONS)) {
    if (errorText.includes(needle)) return reason;
  }
  return null;
}

// The BLOCKED reason a response from the proxy carries (its X-Selvedge-Blocked header), or null.
export function reasonOfResponse(response) {
  if (!response || typeof response.headers !== 'function') return null;
  const value = response.headers()[BLOCKED_HEADER];
  return Object.values(REASONS).includes(value) ? value : null;
}

// Refuse when Playwright's forced loopback proxying is switched off: localhost would then bypass
// the proxy. Any value counts (fail closed), even one Playwright itself would ignore.
export function assertLoopbackProxied() {
  if (process.env[LOOPBACK_ENV] !== undefined) {
    throw new EnvError(
      REASONS.proxy_loopback_disabled,
      `${LOOPBACK_ENV} is set, so Chromium would reach localhost without the proxy; unset it`,
      { blocked: true },
    );
  }
}

// The launch options for a guarded Chromium: exactly { proxy: { server: 'http://127.0.0.1:<port>' } }.
// No `bypass` key (a bypass entry naming loopback turns Playwright's forced loopback proxying off)
// and no `direct://` fallback (a dead proxy must fail the request, not route around it).
export function buildLaunchOptions({ proxyPort } = {}) {
  const port = Number(proxyPort);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new TypeError(`proxyPort must be a TCP port, got ${proxyPort}`);
  return { proxy: { server: `http://127.0.0.1:${port}` } };
}

// The route layer's decision for one request: { allow: true } or { allow: false, reason, origin, host }.
export function checkRequest(config, url, method) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return { allow: false, reason: REASONS.host_not_allowed, origin: String(url), host: String(url) };
  }
  if (NO_NETWORK_SCHEMES.has(parsed.protocol)) return { allow: true };
  const target = parsed.protocol === 'http:' || parsed.protocol === 'https:' ? parseOrigin(parsed.origin) : null;
  if (!target) return { allow: false, reason: REASONS.host_not_allowed, origin: parsed.protocol, host: parsed.host || parsed.protocol };
  const host = `${target.hostname}:${target.port}`;
  const local = isLocalOrigin(target);
  if (!isOriginAllowed(config, url) || (!local && config.allow_remote !== true)) {
    return { allow: false, reason: REASONS.host_not_allowed, origin: target.origin, host };
  }
  if (!local && !SAFE_METHODS.has(String(method).toUpperCase()) && config.allow_remote_mutation !== true) {
    return { allow: false, reason: REASONS.remote_mutation_refused, origin: target.origin, host };
  }
  return { allow: true };
}

// True when a request that the route layer allowed could be redirected, with its method kept
// (nextRedirectMethod), to a remote origin that refuses mutations: a remote origin is listed and
// allowed, mutations to it are not, and the method is not read-only.
export function needsRedirectCheck(config, method) {
  if (SAFE_METHODS.has(String(method).toUpperCase())) return false;
  if (config.allow_remote_mutation === true || config.allow_remote !== true) return false;
  return config.origins.some((o) => {
    const t = parseOrigin(o);
    return t !== null && !isLocalOrigin(t);
  });
}

// True when a route.fetch failed because the guard's proxy is gone: it was closed, or the connection
// to its port was refused. Any other failure (a closed page, a refused CONNECT) is not proxy_unavailable.
export function proxyUnreachable(proxy, err) {
  if (proxy.closed === true) return true;
  const text = String(err && err.message ? err.message : err);
  return text.includes('ECONNREFUSED') && new RegExp(`127\\.0\\.0\\.1:${proxy.port}(?!\\d)`).test(text);
}

function originAndHost(url) {
  try {
    const u = new URL(url);
    const target = parseOrigin(u.origin);
    if (target) return { origin: target.origin, host: `${target.hostname}:${target.port}` };
    return { origin: u.origin, host: u.host };
  } catch {
    return { origin: String(url), host: String(url) };
  }
}

// openGuardedContext({ chromium, config, lookup?, routeLayer?, contextOptions? }) →
//   { browser, context, page, proxy, blocks, seen, close() }
//   chromium        the caller's Playwright `chromium` (this module never imports playwright)
//   config          a loaded selvedge config (env-config.mjs loadConfig().config)
//   lookup          passed to the proxy (dns.promises.lookup-compatible); programmatic only
//   routeLayer      TEST-ONLY. `false` turns the route layer's checks off so a test can prove the
//                   proxy alone refuses; production callers never pass it.
// The route is installed on the context before its first page is created; `page` is that page.
// `blocks` gathers both layers' refusals; `seen` lists every request the route layer saw.
export async function openGuardedContext({ chromium, config, lookup, routeLayer = true } = {}) {
  assertLoopbackProxied();
  if (!chromium || typeof chromium.launch !== 'function') throw new TypeError('openGuardedContext needs the caller\'s Playwright chromium');
  if (!config || !Array.isArray(config.origins)) throw new TypeError('openGuardedContext needs a loaded selvedge config');

  const blocks = [];
  const seen = [];
  const proxyOptions = { config, onBlock: (record) => blocks.push(record) };
  if (lookup !== undefined) proxyOptions.lookup = lookup;
  const proxy = await startProxy(proxyOptions);

  let browser = null;
  const close = async () => {
    try {
      if (browser) await browser.close();
    } catch {
      // already gone
    }
    await proxy.close();
  };

  try {
    browser = await chromium.launch(buildLaunchOptions({ proxyPort: proxy.port }));
    const context = await browser.newContext({ serviceWorkers: 'block' });
    // Only a config whose non-read requests the route layer sends itself needs the fetch modes.
    if (routeLayer !== false && needsRedirectCheck(config, 'POST')) await context.addInitScript(tagFetchModes, FETCH_MODE_HEADER);

    await context.route('**/*', async (route) => {
      const request = route.request();
      const url = request.url();
      const method = request.method();
      seen.push(Object.freeze({ url, method, layer: 'route' }));
      const decision = routeLayer === false ? { allow: true } : checkRequest(config, url, method);
      let hopUrl = url;
      let fetching = false;
      try {
        if (!decision.allow) {
          blocks.push(Object.freeze({ reason: decision.reason, origin: decision.origin, host: decision.host, layer: 'route', method, url }));
          await route.abort('blockedbyclient');
          return;
        }
        if (routeLayer === false || !needsRedirectCheck(config, method)) {
          if (request.headers()[FETCH_MODE_HEADER] === undefined) {
            await route.continue();
          } else {
            const headers = { ...request.headers() };
            delete headers[FETCH_MODE_HEADER];
            await route.continue({ headers });
          }
          return;
        }
        // Send it ourselves, one hop at a time, so no hop that keeps a non-read method leaves
        // unchecked. Each hop is sent exactly once; the request is never also continued. A hop is
        // followed here only when its next method is not a read and the page's redirect mode is
        // follow, and nextRedirectMethod changes a method only into a read, so every followed hop
        // re-sends the original method and body (route.fetch's default).
        const sent = { ...request.headers() };
        const modes = requestModes(request.resourceType(), sent);
        delete sent[FETCH_MODE_HEADER];
        const pageOrigin = originOf(sent.origin);
        let crossed = false;
        let tainted = pageOrigin === null || originOf(url) !== pageOrigin;
        let hopMethod = String(method).toUpperCase();
        // hop 0 carries the browser's own headers; a fetch tagged credentials 'omit' gets an empty
        // Cookie so route.fetch does not add the context's cookies the browser would not send
        let hopHeaders = modes.credentials === 'omit' ? { ...sent, cookie: '' } : sent;
        for (let hop = 0; ; hop += 1) {
          fetching = true;
          const response = await route.fetch(hop === 0 ? { headers: hopHeaders, maxRedirects: 0 } : { url: hopUrl, headers: hopHeaders, maxRedirects: 0 });
          fetching = false;
          const location = response.headers().location;
          const nextMethod = location ? nextRedirectMethod(response.status(), hopMethod) : null;
          if (nextMethod === null || SAFE_METHODS.has(nextMethod)) {
            // not a redirect Chromium follows, or one whose next hop is a read: hand it to the page
            await route.fulfill({ response });
            return;
          }
          if (modes.redirect !== 'follow') {
            // manual, error or unknown: never sent from here; Chromium applies the page's own mode
            await route.fulfill({ response, headers: { ...response.headers(), location: WITHHELD_LOCATION } });
            return;
          }
          let next;
          try {
            next = new URL(location, hopUrl).href;
          } catch {
            next = location;
          }
          const hopDecision = checkRequest(config, next, nextMethod);
          if (!hopDecision.allow) {
            blocks.push(Object.freeze({ reason: hopDecision.reason, origin: hopDecision.origin, host: hopDecision.host, layer: 'route', method: nextMethod, url: next, redirectedFrom: hopUrl }));
            await route.abort('blockedbyclient');
            return;
          }
          if (hop + 1 >= MAX_REDIRECT_HOPS) {
            await route.abort('failed');
            return;
          }
          seen.push(Object.freeze({ url: next, method: nextMethod, layer: 'route', redirectedFrom: hopUrl }));
          const nextOrigin = originOf(next);
          crossed = crossed || nextOrigin === null || nextOrigin !== originOf(hopUrl);
          tainted = tainted || nextOrigin === null || nextOrigin !== pageOrigin;
          hopHeaders = redirectHopHeaders(sent, { credentials: modes.credentials, crossed, tainted });
          hopUrl = next;
          hopMethod = nextMethod;
        }
      } catch (err) {
        // the page or context closed while the request was in flight, or a hop could not be sent:
        // fail the request (never continue it, which would send it a second time). A hop that could
        // not be sent because the proxy is gone is labelled proxy_unavailable, as the browser's own
        // ERR_PROXY_CONNECTION_FAILED is; the abort below reports net::ERR_FAILED, which the
        // requestfailed listener maps to nothing, so it is recorded once.
        if (fetching && proxyUnreachable(proxy, err)) {
          const { origin, host } = originAndHost(hopUrl);
          blocks.push(Object.freeze({ reason: REASONS.proxy_unavailable, origin, host, layer: 'proxy', method, url: hopUrl }));
        }
        try {
          await route.abort('failed');
        } catch {
          // already handled
        }
      }
    });

    context.on('requestfailed', (request) => {
      const failure = request.failure();
      const reason = reasonForFailure(failure && failure.errorText);
      if (!reason) return;
      const { origin, host } = originAndHost(request.url());
      blocks.push(Object.freeze({ reason, origin, host, layer: 'proxy', method: request.method(), url: request.url() }));
    });

    const page = await context.newPage();
    return { browser, context, page, proxy, blocks, seen, close };
  } catch (err) {
    await close();
    throw err;
  }
}
