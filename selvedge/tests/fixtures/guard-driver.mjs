// guard-driver.mjs — drives selvedge/lib/runner/route-guard.mjs for test-route-guard.sh.
// Not named test-*, so selvedge/tests/run.sh never runs it directly.
//
//   node guard-driver.mjs <lib dir> <log dir> nobrowser   → arms that need no Chromium
//   node guard-driver.mjs <lib dir> <log dir> browser     → real-Chromium arms; imports Playwright
//                                                          from $PW_MODULE (tests/lib/playwright-cache.sh)
// Prints one JSON object { <scenario>: result, … }. Every browser scenario gets its own recording
// fixture servers (servers.mjs; each server's JSON log path is in result.logs) and its own guarded
// browser, closed before the next starts. A scenario that throws reports { error } instead.
//
// `routeLayer: false` is openGuardedContext's TEST-ONLY switch: those scenarios prove the proxy
// alone refuses. A remote origin is `http://remote.selvedge.test:<port of a local fixture>`; its
// lookup is injected (programmatic only) and answers 127.0.0.1, so a request that gets past the
// route layer is refused by the proxy as remote_resolves_private and never reaches the fixture.
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { startServers } from './servers.mjs';

const [libDir, logRoot, mode] = process.argv.slice(2);
const G = await import(pathToFileURL(path.join(libDir, 'runner', 'route-guard.mjs')).href);
const { REASONS } = await import(pathToFileURL(path.join(libDir, 'env-config.mjs')).href);

const results = {};
// A watchdog: a scenario that hangs fails the run (exit 3) instead of stalling the suite.
const watchdog = setTimeout(() => {
  process.stdout.write(`${JSON.stringify({ ...results, watchdog: 'guard-driver timed out' })}\n`);
  process.exit(3);
}, 240000);
const errText = (e) => String(e && e.message ? e.message : e).split('\n')[0];

if (mode === 'nobrowser') {
  // AC16 — the launch options, exactly.
  results.ac16_options = G.buildLaunchOptions({ proxyPort: 4242 });

  // AC16 — the loopback env var refuses before Chromium is launched (a spy chromium records launches).
  for (const [label, value] of [['set', '1'], ['empty', '']]) {
    let launched = 0;
    const chromium = { launch: async () => { launched += 1; throw new Error('must not launch'); } };
    process.env[G.LOOPBACK_ENV] = value;
    try {
      await G.openGuardedContext({ chromium, config: { origins: ['http://localhost:3000'] } });
      results[`ac16_env_${label}`] = { refused: false, launched };
    } catch (e) {
      results[`ac16_env_${label}`] = { refused: true, reason: e.reason || null, blocked: e.blocked === true, launched, message: errText(e) };
    } finally {
      delete process.env[G.LOOPBACK_ENV];
    }
  }

  // AC19 — call order on a spy chromium: the context is created with serviceWorkers 'block' and
  // context.route('**/*') is installed before the first context.newPage().
  {
    const calls = [];
    const page = { spy: 'page' };
    const context = {
      route: async (pattern) => { calls.push(`route:${pattern}`); },
      addInitScript: async () => { calls.push('addInitScript'); },
      on: (event) => { calls.push(`on:${event}`); },
      newPage: async () => { calls.push('newPage'); return page; },
    };
    const browser = {
      newContext: async (opts) => { calls.push(`newContext:${JSON.stringify(opts)}`); return context; },
      close: async () => { calls.push('browser.close'); },
    };
    const chromium = { launch: async (opts) => { calls.push(`launch:${JSON.stringify(opts)}`); return browser; } };
    try {
      const guard = await G.openGuardedContext({ chromium, config: { origins: ['http://localhost:3000'] } });
      const proxyPort = guard.proxy.port;
      const samePage = guard.page === page;
      await guard.close();
      results.ac19_order = { calls, proxyPort, samePage };
    } catch (e) {
      results.ac19_order = { error: errText(e), calls };
    }
  }

  // The route layer's decision table (the same function the route handler calls).
  const local = { origins: ['http://localhost:4001'] };
  const remote = { origins: ['http://localhost:4001', 'https://shop.example.com'], allow_remote: true };
  const d = (cfg, url, method = 'GET') => {
    const r = G.checkRequest(cfg, url, method);
    return r.allow ? 'allow' : `${r.reason} ${r.host}`;
  };
  results.check_request = {
    listed: d(local, 'http://localhost:4001/x?y=1'),
    unlisted_port: d(local, 'http://localhost:4002/'),
    next_localhost: d(local, 'https://shop.example.com/?next=localhost'),
    remote_get: d(remote, 'https://shop.example.com/cart'),
    remote_post: d(remote, 'https://shop.example.com/cart', 'POST'),
    remote_put: d(remote, 'https://shop.example.com/cart', 'PUT'),
    remote_patch: d(remote, 'https://shop.example.com/cart', 'PATCH'),
    remote_delete: d(remote, 'https://shop.example.com/cart', 'DELETE'),
    remote_propfind: d(remote, 'https://shop.example.com/cart', 'PROPFIND'),
    remote_mkcol: d(remote, 'https://shop.example.com/cart', 'MKCOL'),
    remote_custom: d(remote, 'https://shop.example.com/cart', 'MERGE'),
    remote_head: d(remote, 'https://shop.example.com/cart', 'HEAD'),
    remote_options: d(remote, 'https://shop.example.com/cart', 'OPTIONS'),
    remote_post_allowed: d({ ...remote, allow_remote_mutation: true }, 'https://shop.example.com/cart', 'POST'),
    local_post: d(local, 'http://localhost:4001/form', 'POST'),
    remote_without_allow_remote: d({ origins: ['https://shop.example.com'] }, 'https://shop.example.com/'),
    data_url: d(local, 'data:text/plain,hi'),
    ftp_url: d(local, 'ftp://localhost:4001/f'),
  };
  // When the route layer sends a request itself to check its 307/308 hops: a non-read method, a
  // listed remote, allow_remote on, allow_remote_mutation off. Anything else is continued untouched.
  results.redirect_check = {
    local_post_remote_listed: G.needsRedirectCheck(remote, 'POST'),
    local_propfind_remote_listed: G.needsRedirectCheck(remote, 'PROPFIND'),
    get_remote_listed: G.needsRedirectCheck(remote, 'GET'),
    head_remote_listed: G.needsRedirectCheck(remote, 'HEAD'),
    post_local_only: G.needsRedirectCheck(local, 'POST'),
    post_mutation_allowed: G.needsRedirectCheck({ ...remote, allow_remote_mutation: true }, 'POST'),
    post_without_allow_remote: G.needsRedirectCheck({ origins: remote.origins }, 'POST'),
  };
  // Chromium's redirect method rule, as a table: [status, method] → the next hop's method.
  results.next_method = Object.fromEntries(
    [
      [307, 'POST'], [308, 'PUT'], [307, 'DELETE'],
      [301, 'POST'], [302, 'POST'], [301, 'PUT'], [302, 'PUT'], [301, 'DELETE'], [302, 'PATCH'], [302, 'PROPFIND'], [302, 'GET'],
      [303, 'POST'], [303, 'PUT'], [303, 'DELETE'], [303, 'HEAD'], [303, 'GET'],
      [300, 'PUT'], [304, 'PUT'], [200, 'PUT'],
    ].map(([status, method]) => [`${status} ${method}`, G.nextRedirectMethod(status, method)]),
  );
  results.failure_reasons = {
    proxy_failed: G.reasonForFailure('net::ERR_PROXY_CONNECTION_FAILED'),
    other: G.reasonForFailure('net::ERR_CONNECTION_REFUSED'),
  };
  results.reason_values = { proxy_unavailable: REASONS.proxy_unavailable };

  // proxyUnreachable on stub proxies: each of its two branches alone, the port boundary, and an
  // unrelated error.
  {
    const P = 41234;
    results.proxy_unreachable = {
      closed_any: G.proxyUnreachable({ closed: true, port: P }, new Error('Target page, context or browser has been closed')),
      refused_port: G.proxyUnreachable({ closed: false, port: P }, new Error(`connect ECONNREFUSED 127.0.0.1:${P}`)),
      refused_longer_port: G.proxyUnreachable({ closed: false, port: P }, new Error(`connect ECONNREFUSED 127.0.0.1:${P}5`)),
      unrelated: G.proxyUnreachable({ closed: false, port: P }, new Error('Target page, context or browser has been closed')),
    };
  }

  // The route handler itself, driven with a stub route (a spy chromium hands it over), under a
  // config whose POSTs the route layer sends itself (route.fetch). Each case gets its own guard.
  const remoteListed = { origins: ['http://localhost:4001', 'https://remote.selvedge.test:8443'], allow_remote: true, allow_remote_mutation: false };
  const handlerCase = async ({ fetchImpl, fulfillImpl, closeProxy = false, request = {}, config = remoteListed }) => {
    let handler = null;
    let initsBeforePage = null;
    const inits = [];
    const context = {
      route: async (_pattern, h) => { handler = h; },
      on: () => {},
      addInitScript: async (fn, arg) => { inits.push({ fn: typeof fn, arg }); },
      newPage: async () => { initsBeforePage = inits.length; return {}; },
    };
    const browser = { newContext: async () => context, close: async () => {} };
    const guard = await G.openGuardedContext({ chromium: { launch: async () => browser }, config });
    const calls = [];
    const sent = [];
    const fulfilled = [];
    let n = 0;
    try {
      if (closeProxy) await guard.proxy.close();
      const req = { url: 'http://localhost:4001/x-post', method: 'POST', headers: {}, resourceType: 'xhr', ...request };
      const route = {
        request: () => ({ url: () => req.url, method: () => req.method, headers: () => ({ ...req.headers }), resourceType: () => req.resourceType }),
        fetch: async (opts) => {
          calls.push(`fetch:${JSON.stringify({ url: opts.url, maxRedirects: opts.maxRedirects })}`);
          sent.push({ url: opts.url || req.url, headers: opts.headers });
          n += 1;
          return fetchImpl(guard.proxy, opts, n);
        },
        fulfill: async (opts) => { calls.push('fulfill'); fulfilled.push({ status: opts.response.status(), location: (opts.headers || opts.response.headers()).location || null }); if (fulfillImpl) await fulfillImpl(); },
        abort: async (code) => { calls.push(`abort:${code}`); },
        continue: async (opts) => { calls.push(opts ? `continue:${JSON.stringify(opts)}` : 'continue'); },
      };
      await handler(route);
      return { calls, sent, fulfilled, inits, initsBeforePage, blocks: guard.blocks.map((b) => ({ ...b })) };
    } finally {
      await guard.close();
    }
  };
  const response = (status, headers = {}) => ({ status: () => status, headers: () => headers });
  const TAG = G.FETCH_MODE_HEADER;
  const tagged = (redirect, credentials = 'same-origin', extra = {}) => ({ resourceType: 'fetch', headers: { [TAG]: `redirect=${redirect};credentials=${credentials}`, origin: 'http://localhost:4001', ...extra } });
  try {
    results.handler = {
      // route.fetch fails with a plain error after the proxy closed: proxy_unavailable, once
      fetch_fails_proxy_closed: await handlerCase({ closeProxy: true, fetchImpl: async () => { throw new Error('socket hang up'); } }),
      // the proxy is open (not closed) but its port refuses: proxy_unavailable, once
      fetch_refused_proxy_open: await handlerCase({ fetchImpl: async (proxy) => { throw new Error(`connect ECONNREFUSED 127.0.0.1:${proxy.port}`); } }),
      // the proxy is open and the error is not a refused connection to it: no proxy_unavailable
      fetch_fails_proxy_open: await handlerCase({ fetchImpl: async () => { throw new Error('socket hang up'); } }),
      // route.fetch returned, then route.fulfill fails while the proxy is closed: not proxy_unavailable
      fulfill_fails_proxy_closed: await handlerCase({ closeProxy: true, fetchImpl: async () => response(200), fulfillImpl: async () => { throw new Error('Target page, context or browser has been closed'); } }),
      // a 307 whose Location is not a URL: refused host_not_allowed at layer route, never sent
      bad_location: await handlerCase({ fetchImpl: async () => response(307, { location: 'http://[bad' }) }),
      // redirect modes: a 307 PUT to the listed https remote from a fetch tagged manual, tagged
      // error, or untagged is never followed or refused here: the page gets the 3xx, Location withheld
      manual_withheld: await handlerCase({ request: { method: 'PUT', ...tagged('manual') }, fetchImpl: async () => response(307, { location: 'https://remote.selvedge.test:8443/api' }) }),
      error_withheld: await handlerCase({ request: { method: 'PUT', ...tagged('error') }, fetchImpl: async () => response(307, { location: 'https://remote.selvedge.test:8443/api' }) }),
      untagged_fetch_withheld: await handlerCase({ request: { method: 'PUT', resourceType: 'fetch', headers: { origin: 'http://localhost:4001' } }, fetchImpl: async () => response(307, { location: 'http://localhost:4001/landing' }) }),
      // follow: a 307 PUT hop to another origin is followed with the tag removed and Authorization dropped
      follow_cross_origin: await handlerCase({
        config: { ...remoteListed, origins: [...remoteListed.origins, 'http://localhost:4002'] },
        request: { method: 'PUT', ...tagged('follow', 'same-origin', { authorization: 'Bearer t', cookie: 'sid=s' }) },
        fetchImpl: async (_p, _o, i) => (i === 1 ? response(307, { location: 'http://localhost:4002/landing' }) : response(200)),
      }),
    };
  } catch (e) {
    results.handler = { error: errText(e) };
  }
  results.request_modes = {
    fetch_follow: G.requestModes('fetch', { [TAG]: 'redirect=follow;credentials=include' }),
    fetch_manual: G.requestModes('fetch', { [TAG]: 'redirect=manual;credentials=same-origin' }),
    fetch_untagged: G.requestModes('fetch', {}),
    fetch_bad_tag: G.requestModes('fetch', { [TAG]: 'redirect=sideways;credentials=include' }),
    xhr_tag_ignored: G.requestModes('xhr', { [TAG]: 'redirect=manual;credentials=omit' }),
    document: G.requestModes('document', {}),
  };
  {
    const base = { authorization: 'Bearer t', cookie: 'sid=s', accept: '*/*' };
    const h = (credentials, crossed, tainted) => G.redirectHopHeaders(base, { credentials, crossed, tainted });
    results.hop_headers = {
      same_origin_clean: h('same-origin', false, false),
      same_origin_tainted: h('same-origin', true, true),
      include_crossed: h('include', true, true),
      omit_same: h('omit', false, false),
    };
  }
} else if (mode === 'browser') {
  const { chromium } = await import(pathToFileURL(process.env.PW_MODULE).href);

  let n = 0;
  const scenario = async (name, { names = ['A', 'U'], config, routeLayer = true, lookup }, body) => {
    n += 1;
    const dir = path.join(logRoot, `${n}-${name}`);
    mkdirSync(dir, { recursive: true });
    const servers = await startServers(names, dir);
    let guard = null;
    try {
      guard = await G.openGuardedContext({ chromium, config: config(servers), routeLayer, lookup });
      const extra = await body(guard, servers);
      results[name] = {
        ...extra,
        blocks: guard.blocks,
        proxyBlocks: guard.proxy.blocks,
        proxyLog: guard.proxy.log,
        seen: guard.seen,
        logs: Object.fromEntries(names.map((k) => [k, servers[k].logFile])),
        ports: Object.fromEntries(names.map((k) => [k, servers[k].port])),
      };
    } catch (e) {
      results[name] = { error: String(e && e.stack ? e.stack : e) };
    } finally {
      if (guard) await guard.close();
      await servers.closeAll();
    }
  };

  const nav = async (page, url) => {
    try {
      const response = await page.goto(url, { timeout: 15000 });
      return { ok: true, status: response ? response.status() : null, blocked: G.reasonOfResponse(response), url: page.url() };
    } catch (e) {
      return { ok: false, error: errText(e) };
    }
  };
  const fetchIn = (page, url, init = {}) =>
    page
      .evaluate(
      async ([u, i]) => {
        try {
          const r = await fetch(u, i);
          return `ok:${r.status}`;
        } catch (e) {
          return `err:${e && e.name}`;
        }
      },
      [url, init],
      )
      .catch((e) => `evalerr:${errText(e)}`);
  const onlyA = ({ A }) => ({ origins: [A.origin] });

  // AC11 — direct navigation to an unlisted port: the route layer refuses (and the proxy never sees it) …
  await scenario('ac11_route', { config: onlyA }, async ({ page }, { U }) => ({ nav: await nav(page, `${U.origin}/`) }));
  // … and with the route layer off, the proxy alone refuses.
  await scenario('ac11_proxy', { config: onlyA, routeLayer: false }, async ({ page }, { U }) => ({ nav: await nav(page, `${U.origin}/`) }));

  // AC12 — redirect hops, proxy only.
  await scenario('ac12_redirect', { config: onlyA, routeLayer: false }, async ({ page }, { A, U }) => ({
    nav: await nav(page, `${A.origin}/redirect?to=${encodeURIComponent(`${U.origin}/landing`)}`),
  }));
  await scenario('ac12_chain', { names: ['A', 'B', 'U'], config: ({ A, B }) => ({ origins: [A.origin, B.origin] }), routeLayer: false }, async ({ page }, { A, B, U }) => {
    const hop2 = `${B.origin}/redirect?to=${encodeURIComponent(`${U.origin}/landing`)}`;
    return { nav: await nav(page, `${A.origin}/redirect?to=${encodeURIComponent(hop2)}`) };
  });
  await scenario('ac12_307', { config: onlyA, routeLayer: false }, async ({ page }, { A, U }) => {
    const reached = page
      .waitForResponse((r) => r.url().startsWith(U.origin), { timeout: 15000 })
      .then((r) => ({ status: r.status(), method: r.request().method(), blocked: G.reasonOfResponse(r) }))
      .catch((e) => ({ error: errText(e) }));
    const first = await nav(page, `${A.origin}/form307?to=${encodeURIComponent(`${U.origin}/landing`)}`);
    return { first, final: await reached };
  });

  // AC13 — ws:// and wss:// to an unlisted origin (no TLS server needed: the CONNECT is refused).
  await scenario('ac13_ws', { config: onlyA, routeLayer: false }, async ({ page }, { A, U }) => {
    const first = await nav(page, `${A.origin}/`);
    const sockets = await page.evaluate(async ([ws, wss]) => {
      const one = (u) =>
        new Promise((resolve) => {
          let s;
          try {
            s = new WebSocket(u);
          } catch (e) {
            resolve(`throw:${e && e.name}`);
            return;
          }
          const t = setTimeout(() => resolve('timeout'), 10000);
          s.onopen = () => { clearTimeout(t); resolve('open'); };
          s.onerror = () => { clearTimeout(t); resolve('error'); };
        });
      return [await one(ws), await one(wss)];
    }, [`ws://localhost:${U.port}/ws`, `wss://localhost:${U.port}/ws`]);
    return { first, sockets };
  });

  // AC14 — a listed localhost:A page fetching localhost:U (same host, other port), both layers.
  for (const [name, routeLayer] of [['ac14_route', true], ['ac14_proxy', false]]) {
    await scenario(name, { config: onlyA, routeLayer }, async ({ page }, { A, U }) => {
      const first = await nav(page, `${A.origin}/`);
      return { first, fetch: await fetchIn(page, `${U.origin}/x`) };
    });
  }

  // AC17 — the proxy dies mid-run: a listed request then fails closed (proxy_unavailable) and an
  // unlisted one never connects. Route layer off, so nothing but the proxy stands in the way.
  await scenario('ac17_kill', { config: onlyA, routeLayer: false }, async (guard, { A, U }) => {
    const before = await nav(guard.page, `${A.origin}/`);
    await guard.proxy.close();
    const fetchU = await fetchIn(guard.page, `${U.origin}/x`);
    const after = await nav(guard.page, `${A.origin}/again`);
    return { before, fetchU, after };
  });
  // … and under a config with a listed remote and no allow_remote_mutation, where a POST is sent by
  // the route layer itself (route.fetch), not by Chromium: that POST is labelled proxy_unavailable
  // too, once, and so is a GET in the same run.
  await scenario(
    'ac17_kill_post',
    {
      config: ({ A }) => ({ origins: [A.origin, 'https://remote.selvedge.test:8443'], allow_remote: true, allow_remote_mutation: false }),
      lookup: async () => [{ address: '93.184.216.34', family: 4 }],
    },
    async (guard, { A }) => {
      const before = await nav(guard.page, `${A.origin}/`);
      await guard.proxy.close();
      const post = await fetchIn(guard.page, `${A.origin}/x-post`, { method: 'POST', body: 'k=v' });
      const after = await nav(guard.page, `${A.origin}/again`);
      return { before, post, after };
    },
  );

  // AC18 — `?next=localhost` does not make shop.example.com local: the route layer refuses it.
  await scenario('ac18_route', { config: onlyA }, async ({ page }) => ({ nav: await nav(page, 'https://shop.example.com/?next=localhost') }));

  // AC19 — mutations to a listed remote without allow_remote_mutation: refused by the route layer.
  // The remote page itself is fulfilled by a page-level route (test fixture only; page routes run
  // before the guard's context route), so its fetches are same-origin and need no CORS preflight.
  await scenario(
    'ac19_mutation_route',
    {
      names: ['A', 'R'],
      config: ({ A, R }) => ({ origins: [A.origin, `http://remote.selvedge.test:${R.port}`], allow_remote: true, allow_remote_mutation: false }),
      lookup: async () => [{ address: '127.0.0.1', family: 4 }],
    },
    async ({ page }, { R }) => {
      const remote = `http://remote.selvedge.test:${R.port}`;
      await page.route(`${remote}/`, (route) => route.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>remote</title>' }));
      const first = await nav(page, `${remote}/`);
      const out = { first, remote: `remote.selvedge.test:${R.port}` };
      for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'PROPFIND', 'GET']) {
        out[method] = await fetchIn(page, `/api/${method.toLowerCase()}`, method === 'GET' ? { method } : { method, body: 'k=v' });
      }
      return out;
    },
  );

  // AC19 — a 307/308 from a listed LOCAL page re-sending a POST to a listed HTTPS remote (the proxy
  // sees only CONNECT for https, Chromium never shows the hop to context.route): the route layer
  // refuses the hop remote_mutation_refused before it is sent. The lookup answers a PUBLIC address,
  // so the proxy would NOT have refused the CONNECT (remote_resolves_private) — only the route layer
  // stands in the way. `direct` = A → remote; `chain` = A → listed local B → remote.
  const REMOTE_TLS = 'https://remote.selvedge.test:8443';
  for (const [name, viaB] of [['ac19_redirect_direct', false], ['ac19_redirect_chain', true]]) {
    await scenario(
      name,
      {
        names: ['A', 'B'],
        config: ({ A, B }) => ({ origins: [A.origin, B.origin, REMOTE_TLS], allow_remote: true, allow_remote_mutation: false }),
        lookup: async () => [{ address: '93.184.216.34', family: 4 }],
      },
      async ({ page }, { A, B }) => {
        const target = `${REMOTE_TLS}/api`;
        const to = viaB ? `${B.origin}/r307?to=${encodeURIComponent(target)}` : target;
        const failed = page
          .waitForEvent('requestfailed', { predicate: (r) => r.url().includes('/r307'), timeout: 15000 })
          .then((r) => ({ method: r.method(), url: r.url(), error: (r.failure() || {}).errorText || null }))
          .catch((e) => ({ error: errText(e) }));
        const first = await nav(page, `${A.origin}/form307?to=${encodeURIComponent(to)}`);
        return { first, failed: await failed, remote: 'remote.selvedge.test:8443' };
      },
    );
  }
  // 301/302 keep every method but POST, so a PUT, DELETE or PATCH 301/302-redirected to the listed
  // HTTPS remote is a remote mutation too: the route layer refuses that hop before it is sent.
  // `direct` = A /r30x → remote; `chain` = A /r30x → listed local B /r30y → remote.
  const ARMS_301_302 = [['PUT', 302, 301], ['DELETE', 301, 302], ['PATCH', 302, 302], ['PUT', 301, 302]];
  for (const [name, viaB] of [['ac19_redirect_direct_301_302', false], ['ac19_redirect_chain_301_302', true]]) {
    await scenario(
      name,
      {
        names: ['A', 'B'],
        config: ({ A, B }) => ({ origins: [A.origin, B.origin, REMOTE_TLS], allow_remote: true, allow_remote_mutation: false }),
        lookup: async () => [{ address: '93.184.216.34', family: 4 }],
      },
      async ({ page }, { A, B }) => {
        const first = await nav(page, `${A.origin}/`);
        const arms = [];
        for (const [method, s1, s2] of ARMS_301_302) {
          const target = `${REMOTE_TLS}/api/${method.toLowerCase()}-${s1}`;
          const to = viaB ? `${B.origin}/r${s2}?to=${encodeURIComponent(target)}` : target;
          const out = await fetchIn(page, `${A.origin}/r${s1}?to=${encodeURIComponent(to)}`, { method, body: 'k=v' });
          arms.push({ method, s1, s2, target, out });
        }
        return { first, arms, remote: 'remote.selvedge.test:8443' };
      },
    );
  }
  // … a local-only same-origin 302 → 301 PUT chain under the same config completes: every hop sent
  // once with the method kept, the page gets the final response.
  await scenario(
    'ac19_redirect_local_301_302',
    {
      names: ['A', 'B'],
      config: ({ A, B }) => ({ origins: [A.origin, B.origin, REMOTE_TLS], allow_remote: true, allow_remote_mutation: false }),
      lookup: async () => [{ address: '93.184.216.34', family: 4 }],
    },
    async ({ page }, { A }) => {
      const first = await nav(page, `${A.origin}/`);
      const to = `${A.origin}/r301?to=${encodeURIComponent(`${A.origin}/landing`)}`;
      const put = await page
        .evaluate(async (u) => {
          try {
            const r = await fetch(u, { method: 'PUT', body: 'k=v' });
            return `ok:${r.status}:${(await r.text()).trim()}`;
          } catch (e) {
            return `err:${e && e.name}`;
          }
        }, `${A.origin}/r302?to=${encodeURIComponent(to)}`)
        .catch((e) => `evalerr:${errText(e)}`);
      return { first, put };
    },
  );
  // … and a local-only 307 chain (A → B → A) under the same config still completes, each hop sent
  // exactly once (no double send), and the page gets the final response.
  await scenario(
    'ac19_redirect_local',
    {
      names: ['A', 'B'],
      config: ({ A, B }) => ({ origins: [A.origin, B.origin, REMOTE_TLS], allow_remote: true, allow_remote_mutation: false }),
      lookup: async () => [{ address: '93.184.216.34', family: 4 }],
    },
    async ({ page }, { A, B }) => {
      const to = `${B.origin}/r307?to=${encodeURIComponent(`${A.origin}/landing`)}`;
      const done = page
        .waitForResponse((r) => r.url().includes('/r307') && r.request().method() === 'POST', { timeout: 15000 })
        .then(async (r) => ({ status: r.status(), body: await r.text().catch((e) => `bodyerr:${errText(e)}`) }))
        .catch((e) => ({ error: errText(e) }));
      const first = await nav(page, `${A.origin}/form307?to=${encodeURIComponent(to)}`);
      const final = await done;
      const get = await fetchIn(page, `${A.origin}/plain-get`);
      return { first, final, get };
    },
  );

  // The page's redirect and credentials modes on a non-read hop the route layer would follow
  // (route-guard.mjs header, README §"The browser guard"): a PUT with redirect 'manual' (307) or
  // 'error' (302) from A to listed local B is never sent to B (an opaque redirect / a TypeError, as
  // in plain Chromium); a followed hop to another origin loses Authorization and, under the default
  // credentials, cookies, while a same-origin hop keeps both and `credentials: 'include'` keeps
  // cookies; a non-read fetch from a Worker (no tag) is never followed by the route layer.
  await scenario(
    'ac19_redirect_modes',
    {
      names: ['A', 'B'],
      config: ({ A, B }) => ({ origins: [A.origin, B.origin, REMOTE_TLS], allow_remote: true, allow_remote_mutation: false }),
      lookup: async () => [{ address: '93.184.216.34', family: 4 }],
    },
    async ({ page, context }, { A, B }) => {
      await context.addCookies([{ name: 'sid', value: 'selvedge-cookie', url: A.origin }]);
      const first = await nav(page, `${A.origin}/`);
      const out = { first };
      const AUTH = { authorization: 'Bearer selvedge-test' };
      for (const [key, code, target, init] of [
        ['manual', 307, B, { redirect: 'manual' }],
        ['errormode', 302, B, { redirect: 'error' }],
        ['cross', 307, B, { headers: AUTH }],
        ['include', 307, B, { headers: AUTH, credentials: 'include' }],
        ['same', 307, A, { headers: AUTH }],
      ]) {
        out[key] = await page
          .evaluate(async ([u, i]) => {
            try {
              const r = await fetch(u, i);
              return `ok:${r.status}:${r.type}:${(await r.text()).trim()}`;
            } catch (e) {
              return `err:${e && e.name}`;
            }
          }, [`${A.origin}/r${code}?to=${encodeURIComponent(`${target.origin}/landing-${key}`)}`, { method: 'PUT', body: 'k=v', ...init }])
          .catch((e) => `evalerr:${errText(e)}`);
      }
      out.omit = await fetchIn(page, `${A.origin}/plain-omit`, { method: 'PUT', body: 'k=v', credentials: 'omit' });
      out.worker = await page
        .evaluate(async (u) => {
          const src = `fetch(${JSON.stringify(u)}, { method: 'PUT', body: 'k=v' }).then((r) => postMessage('ok:' + r.status), (e) => postMessage('err:' + (e && e.name)));`;
          const w = new Worker(URL.createObjectURL(new Blob([src], { type: 'text/javascript' })));
          return new Promise((resolve) => {
            const t = setTimeout(() => resolve('timeout'), 10000);
            w.onmessage = (m) => { clearTimeout(t); resolve(m.data); };
            w.onerror = () => { clearTimeout(t); resolve('worker-error'); };
          });
        }, `${A.origin}/r307?to=${encodeURIComponent(`${A.origin}/landing-worker`)}`)
        .catch((e) => `evalerr:${errText(e)}`);
      return out;
    },
  );
  // The route layer follows at most 20 hops of a non-read request itself, then fails it: a PUT down
  // a 22-hop local 307 chain (A → A → … → /landing) is sent 20 times and never reaches /landing.
  await scenario(
    'ac19_redirect_hop_limit',
    {
      config: ({ A }) => ({ origins: [A.origin, REMOTE_TLS], allow_remote: true, allow_remote_mutation: false }),
      lookup: async () => [{ address: '93.184.216.34', family: 4 }],
    },
    async ({ page }, { A }) => {
      const first = await nav(page, `${A.origin}/`);
      let u = `${A.origin}/landing`;
      for (let i = 0; i < 22; i += 1) u = `${A.origin}/r307?to=${encodeURIComponent(u)}`;
      return { first, put: await fetchIn(page, u, { method: 'PUT', body: 'k=v' }) };
    },
  );

  // AC19 — service workers are blocked.
  await scenario('ac19_sw', { config: onlyA }, async ({ page }, { A }) => {
    const first = await nav(page, `${A.origin}/`);
    const sw = await page.evaluate(async () => {
      if (!('serviceWorker' in navigator)) return 'unavailable';
      const within = (p, ms, label) => Promise.race([p, new Promise((resolve) => setTimeout(() => resolve(label), ms))]);
      try {
        const reg = await within(navigator.serviceWorker.register('/sw.js'), 5000, 'register-timeout');
        if (reg === 'register-timeout') return reg;
        const ready = await within(navigator.serviceWorker.ready.then(() => 'ready'), 5000, 'not-ready');
        return `registered:${ready}`;
      } catch (e) {
        return `rejected:${e && e.name}`;
      }
    });
    const controlled = await page.evaluate(() => Boolean(navigator.serviceWorker && navigator.serviceWorker.controller));
    return { first, sw, controlled };
  });

  // AC19 — the first request of the first page is seen by the route layer; a listed page loads.
  await scenario('ac19_first', { config: onlyA }, async ({ page }, { A }) => ({ nav: await nav(page, `${A.origin}/`), want: `${A.origin}/` }));
} else {
  process.stderr.write('usage: guard-driver.mjs <lib dir> <log dir> nobrowser|browser\n');
  process.exit(2);
}

clearTimeout(watchdog);
process.stdout.write(`${JSON.stringify(results)}\n`);
