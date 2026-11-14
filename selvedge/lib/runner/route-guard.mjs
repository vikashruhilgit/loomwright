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
//          to an unlisted origin (host_not_allowed) and a POST/PUT/PATCH/DELETE to a remote origin
//          without allow_remote_mutation (remote_mutation_refused) — including over https, where the
//          proxy sees host and port only.
// Service workers are blocked (`serviceWorkers: 'block'`), so no worker can answer or issue
// requests outside the route layer.
//
// Each refusal is recorded as { reason, origin, host, layer: 'route' | 'proxy', … } in the guard's
// `blocks`. A request that fails because the proxy is gone (ERR_PROXY_CONNECTION_FAILED) is recorded
// as proxy_unavailable: the browser fails closed, it never falls back to a direct connection.
//
// Playwright is injected: the caller passes its own `chromium` (openGuardedContext({ chromium, … })).
// This module never imports `playwright`, so the runner decides how it is packaged.
//
// Node >= 18, standard library only.
import { EnvError, REASONS, isLocalOrigin, isOriginAllowed, parseOrigin } from '../env-config.mjs';
import { BLOCKED_HEADER, startProxy } from './proxy.mjs';

export const LOOPBACK_ENV = 'PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK';

// The route layer's own mutating-method set (proxy.mjs keeps its own; the layers are independent).
const MUTATING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

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
  if (!local && MUTATING_METHODS.has(String(method).toUpperCase()) && config.allow_remote_mutation !== true) {
    return { allow: false, reason: REASONS.remote_mutation_refused, origin: target.origin, host };
  }
  return { allow: true };
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

    await context.route('**/*', async (route) => {
      const request = route.request();
      const url = request.url();
      const method = request.method();
      seen.push(Object.freeze({ url, method, layer: 'route' }));
      const decision = routeLayer === false ? { allow: true } : checkRequest(config, url, method);
      try {
        if (decision.allow) {
          await route.continue();
          return;
        }
        blocks.push(Object.freeze({ reason: decision.reason, origin: decision.origin, host: decision.host, layer: 'route', method, url }));
        await route.abort('blockedbyclient');
      } catch {
        // the page or context closed while the request was in flight
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
