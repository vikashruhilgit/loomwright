// request-driver.mjs — drives the `request` step (runner/steps.mjs sendRequest, runner/execute.mjs)
// through the real guarded browser for test-request-step.sh. Not named test-*, so
// selvedge/tests/run.sh never runs it directly.
//
//   node request-driver.mjs <lib dir> <log dir> browser   → imports Playwright from $PW_MODULE
//
// Prints one JSON object { <scenario>: result, … }. Every scenario gets its own recording fixture
// servers (servers.mjs; each server's JSON log path is in result.logs) and its own guarded browser,
// closed before the next starts. A scenario that throws reports { error } instead.
//
// This is the 2026-11-23 probe as a fixture: a request step leaves through the page, so the route
// layer (context.route) sees and refuses it, while Playwright's context.request is not seen by the
// route layer at all (probe_context_request, the reason the runner never uses it). A remote origin
// is `http://remote.selvedge.test:<port of a local fixture>`, its lookup injected (programmatic
// only) to answer 127.0.0.1, so a request that got past the route layer would be refused by the
// proxy as remote_resolves_private and never reach the fixture.
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { startServers } from './servers.mjs';

const [libDir, logRoot, mode] = process.argv.slice(2);
const G = await import(pathToFileURL(path.join(libDir, 'runner', 'route-guard.mjs')).href);
const S = await import(pathToFileURL(path.join(libDir, 'runner', 'steps.mjs')).href);
const X = await import(pathToFileURL(path.join(libDir, 'runner', 'execute.mjs')).href);

const results = {};
const watchdog = setTimeout(() => {
  process.stdout.write(`${JSON.stringify({ ...results, watchdog: 'request-driver timed out' })}\n`);
  process.exit(3);
}, 180000);
const errText = (e) => String(e && e.message ? e.message : e).split('\n')[0];

if (mode !== 'browser') {
  process.stderr.write('usage: request-driver.mjs <lib dir> <log dir> browser\n');
  process.exit(2);
}

const { chromium } = await import(pathToFileURL(process.env.PW_MODULE).href);
const REMOTE_LOOKUP = async () => [{ address: '127.0.0.1', family: 4 }];
const remoteOf = (R) => `http://remote.selvedge.test:${R.port}`;
const remoteConfig = ({ A, R }) => ({ origins: [A.origin, remoteOf(R)], allow_remote: true, allow_remote_mutation: false });
const REMOTE_PAGE = { status: 200, contentType: 'text/html', body: '<!doctype html><title>remote</title><p>remote</p>' };

let n = 0;
const dirFor = (name) => {
  n += 1;
  const dir = path.join(logRoot, `${n}-${name}`);
  mkdirSync(dir, { recursive: true });
  return dir;
};

// One request step through the one executor, in an open guarded context: { ok, status } or
// { ok: false, guard: <GuardRefusal?>, reason, error }.
const send = async (page, guard, step) => {
  try {
    const reply = await S.runStep(page, step, { state: {}, blocks: guard.blocks });
    return { ok: true, status: reply.status };
  } catch (e) {
    return { ok: false, guard: e instanceof S.GuardRefusal, reason: e.reason || null, error: errText(e) };
  }
};

const scenario = async (name, { names = ['A', 'U'], config, routeLayer = true, lookup }, body) => {
  const dir = dirFor(name);
  const servers = await startServers(names, dir);
  let guard = null;
  try {
    guard = await G.openGuardedContext({ chromium, config: config(servers), routeLayer, lookup });
    const extra = await body(guard, servers);
    results[name] = {
      ...extra,
      blocks: guard.blocks,
      seen: guard.seen,
      logs: Object.fromEntries(names.map((k) => [k, servers[k].logFile])),
    };
  } catch (e) {
    results[name] = { error: String(e && e.stack ? e.stack : e) };
  } finally {
    if (guard) await guard.close();
    await servers.closeAll();
  }
};

// A GET request step to an unlisted local origin, from a listed page: the route layer refuses it.
await scenario('route_unlisted', { config: ({ A }) => ({ origins: [A.origin] }) }, async ({ page, ...guard }, { A, U }) => {
  await page.goto(`${A.origin}/`);
  return { r: await send(page, guard, { type: 'request', method: 'GET', url: `${U.origin}/api/x` }), want: `${U.origin}/api/x` };
});

// A remote POST with allow_remote_mutation off: the route layer refuses it remote_mutation_refused.
// The remote page itself is fulfilled by a page-level route (test fixture only; page routes run
// before the guard's context route), so the request is same-origin, as the lint requires.
await scenario('route_remote_post', { names: ['A', 'R'], config: remoteConfig, lookup: REMOTE_LOOKUP }, async ({ page, ...guard }, { R }) => {
  await page.route(`${remoteOf(R)}/`, (route) => route.fulfill(REMOTE_PAGE));
  await page.goto(`${remoteOf(R)}/`);
  const r = await send(page, guard, { type: 'request', method: 'POST', url: `${remoteOf(R)}/api/login`, json: { email: 'a@b.c' } });
  return { r, want: `${remoteOf(R)}/api/login` };
});

// A remote GET passes the route layer, so the proxy decides: its lookup answers 127.0.0.1, it
// answers 403 X-Selvedge-Blocked remote_resolves_private, and the request step names that reason.
await scenario('proxy_remote_get', { names: ['A', 'R'], config: remoteConfig, lookup: REMOTE_LOOKUP }, async ({ page, ...guard }, { R }) => {
  await page.route(`${remoteOf(R)}/`, (route) => route.fulfill(REMOTE_PAGE));
  await page.goto(`${remoteOf(R)}/`);
  return { r: await send(page, guard, { type: 'request', method: 'GET', url: `${remoteOf(R)}/api/forecast` }) };
});

// With the route layer off (TEST-ONLY), the proxy alone refuses an unlisted local origin; the
// fetch fails (no CORS header on the proxy's 403) and the step finds the proxy's record.
await scenario('proxy_only_unlisted', { config: ({ A }) => ({ origins: [A.origin] }), routeLayer: false }, async ({ page, ...guard }, { A, U }) => {
  await page.goto(`${A.origin}/`);
  return { r: await send(page, guard, { type: 'request', method: 'GET', url: `${U.origin}/api/x` }) };
});

// A listed, same-origin request whose connection drops mid-reply: no guard layer refused it, so
// the step throws a plain Error (not GuardRefusal) and the guard records no block.
await scenario('network_drop', { names: ['A'], config: ({ A }) => ({ origins: [A.origin] }) }, async ({ page, ...guard }, { A }) => {
  await page.goto(`${A.origin}/`);
  return { r: await send(page, guard, { type: 'request', method: 'GET', url: `${A.origin}/drop` }), want: `${A.origin}/drop` };
});

// The probe: Playwright's APIRequestContext never reaches the route layer (so the runner never
// uses it). The proxy still refuses the unlisted port here, so U records nothing either way.
await scenario('probe_context_request', { config: ({ A }) => ({ origins: [A.origin] }) }, async ({ context }, { U }) => {
  let status = null;
  try {
    const res = await context.request.get(`${U.origin}/probe`, { timeout: 10000 });
    status = res.status();
  } catch (e) {
    status = `error: ${errText(e)}`;
  }
  return { status, want: `${U.origin}/probe` };
});

// executeCriterion, as `selvedge run` calls it, with a step list the lint would refuse (so only
// the guard stands between the step and the host). `wrap` lets a scenario add a page-level route
// to the page openGuardedContext creates.
const execute = async (name, { names, config, steps, wrap = null }) => {
  const dir = dirFor(name);
  const servers = await startServers(names, dir);
  const lines = [];
  const runDir = path.join(dir, 'run');
  mkdirSync(runDir, { recursive: true });
  const wrapped = {
    launch: async (opts) => {
      const browser = await chromium.launch(opts);
      const newContext = browser.newContext.bind(browser);
      browser.newContext = async (o) => {
        const context = await newContext(o);
        const newPage = context.newPage.bind(context);
        context.newPage = async () => {
          const page = await newPage();
          if (wrap) await wrap(page, servers);
          return page;
        };
        return context;
      };
      return browser;
    },
  };
  try {
    const s = steps(servers);
    const end = await X.executeCriterion({
      id: 'c-000000000001', steps: s, resolved: s, chromium: wrapped, config: config(servers), runDir, stepTimeoutMs: 5000, write: (l) => lines.push(l),
    });
    results[name] = { end, lines, logs: Object.fromEntries(names.map((k) => [k, servers[k].logFile])) };
  } catch (e) {
    results[name] = { error: String(e && e.stack ? e.stack : e) };
  } finally {
    await servers.closeAll();
  }
};

await execute('exec_unlisted', {
  names: ['A', 'U'],
  config: ({ A }) => ({ origins: [A.origin] }),
  steps: ({ A, U }) => [
    { type: 'goto', url: `${A.origin}/` },
    { type: 'request', method: 'GET', url: `${U.origin}/api/x` },
    { type: 'read', property: 'response_status' },
    { type: 'expect', op: 'equals', value: 200 },
  ],
});

// The executeCriterion path does not take a lookup, so the remote host never resolves; the page
// is fulfilled by a page route and the POST is refused by the route layer before any lookup.
await execute('exec_remote_post', {
  names: ['A', 'R'],
  config: remoteConfig,
  wrap: async (page, { R }) => page.route(`${remoteOf(R)}/`, (route) => route.fulfill(REMOTE_PAGE)),
  steps: ({ R }) => [
    { type: 'goto', url: `${remoteOf(R)}/` },
    { type: 'request', method: 'POST', url: `${remoteOf(R)}/api/login`, json: { email: 'a@b.c' } },
    { type: 'read', property: 'response_status' },
    { type: 'expect', op: 'equals', value: 200 },
  ],
});

await execute('exec_network_drop', {
  names: ['A'],
  config: ({ A }) => ({ origins: [A.origin] }),
  steps: ({ A }) => [
    { type: 'goto', url: `${A.origin}/` },
    { type: 'request', method: 'GET', url: `${A.origin}/drop` },
    { type: 'read', property: 'response_status' },
    { type: 'expect', op: 'equals', value: 200 },
  ],
});

clearTimeout(watchdog);
process.stdout.write(`${JSON.stringify(results)}\n`);
