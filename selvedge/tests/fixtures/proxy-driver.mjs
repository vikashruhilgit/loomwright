// proxy-driver.mjs — drives selvedge/lib/runner/proxy.mjs with no browser, for test-proxy.sh.
// Not named test-*, so selvedge/tests/run.sh never runs it directly.
//
//   node proxy-driver.mjs <lib dir> <log dir>   → prints one JSON object { <arm>: result, … }
//
// Every arm starts its own proxy and recording fixture servers (servers.mjs) and closes them. A
// remote origin is `http://remote.selvedge.test:<port of a local fixture>`: the proxy never asks the
// system resolver about it — every arm injects a COUNTING `lookup`, and the arms that must reach the
// fixture also inject a `dial` that records the address it was asked for and connects to the
// fixture on 127.0.0.1. Both are programmatic test seams of startProxy, nothing else sets them.
import net from 'node:net';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { startServers } from './servers.mjs';

const [libDir, logRoot] = process.argv.slice(2);
const { startProxy } = await import(pathToFileURL(path.join(libDir, 'runner', 'proxy.mjs')).href);

// rawExchange(port, text, { then? }) → { status, headers, body, tunnel? }. Sends `text`, reads until
// the proxy closes (or, for an established CONNECT, sends `then` through the tunnel and reads that).
function rawExchange(port, text, { then } = {}) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port });
    let buf = '';
    let tunnelled = false;
    let tunnelHead = null;
    const finish = (extra = {}) => {
      socket.destroy();
      const source = tunnelHead !== null ? tunnelHead : buf;
      const [head, ...rest] = source.split('\r\n\r\n');
      const lines = head.split('\r\n');
      const status = Number((lines[0] || '').split(' ')[1]) || 0;
      const headers = {};
      for (const line of lines.slice(1)) {
        const i = line.indexOf(':');
        if (i > 0) headers[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
      }
      resolve({ status, headers, body: rest.join('\r\n\r\n'), ...extra });
    };
    const timer = setTimeout(() => finish({ timeout: true }), 5000);
    socket.on('connect', () => socket.write(text));
    socket.on('data', (d) => {
      buf += d.toString('latin1');
      if (then && !tunnelled && buf.includes('\r\n\r\n') && / 200 /.test(buf.split('\r\n')[0])) {
        tunnelled = true;
        tunnelHead = buf;
        buf = '';
        socket.write(then);
      }
    });
    const done = () => {
      clearTimeout(timer);
      if (tunnelled) {
        const inner = buf;
        const status = Number(((inner.split('\r\n')[0] || '').split(' ')[1])) || 0;
        finish({ tunnel: { status, body: inner.split('\r\n\r\n').slice(1).join('\r\n\r\n') } });
      } else {
        finish();
      }
    };
    socket.on('end', done);
    socket.on('error', done);
  });
}

function countingLookup(addresses) {
  const fn = async (host, opts) => {
    fn.calls.push({ host, opts });
    return addresses.map((address) => ({ address, family: net.isIP(address) }));
  };
  fn.calls = [];
  return fn;
}

// A dial that records the address it was given and connects to the fixture instead.
function recordingDial(fixturePort) {
  const fn = (address, port) => {
    fn.calls.push({ address, port: String(port) });
    return net.connect({ host: '127.0.0.1', port: fixturePort });
  };
  fn.calls = [];
  return fn;
}

let armNo = 0;
async function arm(names, body) {
  armNo += 1;
  const dir = path.join(logRoot, `arm-${armNo}`);
  mkdirSync(dir, { recursive: true });
  const servers = await startServers(names, dir);
  const opened = [];
  const open = async (opts) => {
    const p = await startProxy(opts);
    opened.push(p);
    return p;
  };
  try {
    return await body(servers, open);
  } catch (err) {
    return { error: String(err && err.stack ? err.stack : err) };
  } finally {
    for (const p of opened) await p.close();
    await servers.closeAll();
  }
}

const logOf = (server) => ({ events: server.events.length, log: server.logFile });
const GET = (url, extra = '') => `GET ${url} HTTP/1.1\r\nHost: ${new URL(url).host}\r\n${extra}Connection: close\r\n\r\n`;
const remoteOf = (server) => `http://remote.selvedge.test:${server.port}`;

const results = {};

results.allowed_get = await arm(['A'], async ({ A }, open) => {
  const lookup = countingLookup(['93.184.216.34']);
  const p = await open({ config: { origins: [A.origin] }, lookup });
  const r = await rawExchange(p.port, GET(`${A.origin}/x?y=1`));
  return { status: r.status, body: r.body.trim(), A: A.events, lookups: lookup.calls.length, blocks: p.blocks };
});

results.unlisted_port = await arm(['A', 'U'], async ({ A, U }, open) => {
  const p = await open({ config: { origins: [A.origin] } });
  const r = await rawExchange(p.port, GET(`${U.origin}/`));
  return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, U: logOf(U), blocks: p.blocks, want: `localhost:${U.port}` };
});

results.connect_unlisted_local = await arm(['A', 'U'], async ({ A, U }, open) => {
  const p = await open({ config: { origins: [A.origin] } });
  const r = await rawExchange(p.port, `CONNECT localhost:${U.port} HTTP/1.1\r\nHost: localhost:${U.port}\r\n\r\n`);
  return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, U: logOf(U), blocks: p.blocks, want: `localhost:${U.port}` };
});

results.connect_allowed_local = await arm(['A'], async ({ A }, open) => {
  const p = await open({ config: { origins: [A.origin] } });
  const r = await rawExchange(p.port, `CONNECT localhost:${A.port} HTTP/1.1\r\nHost: localhost:${A.port}\r\n\r\n`, {
    then: `GET /through-tunnel HTTP/1.1\r\nHost: localhost:${A.port}\r\nConnection: close\r\n\r\n`,
  });
  return { status: r.status, tunnel: r.tunnel || null, A: A.events, blocks: p.blocks };
});

results.upgrade_unlisted = await arm(['A', 'U'], async ({ A, U }, open) => {
  const p = await open({ config: { origins: [A.origin] } });
  const r = await rawExchange(p.port, GET(`${U.origin}/ws`, 'Upgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n').replace('Connection: close', 'Connection: Upgrade'));
  return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, U: logOf(U), blocks: p.blocks, want: `localhost:${U.port}` };
});

results.upgrade_allowed = await arm(['A'], async ({ A }, open) => {
  const p = await open({ config: { origins: [A.origin] } });
  await rawExchange(p.port, GET(`${A.origin}/ws`, 'Upgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n').replace('Connection: close', 'Connection: Upgrade'));
  return { A: A.events, blocks: p.blocks };
});

// AC15 — a listed remote whose name resolves private: refused after ONE lookup, no dial, no connection.
results.ac15 = {};
for (const [label, addresses] of [
  ['v4_loopback', ['127.0.0.1']],
  ['v6_loopback', ['::1']],
  ['v6_link_local', ['fe80::1']],
  ['one_of_several_private', ['93.184.216.34', '10.0.0.1']],
  ['one_of_several_mapped', ['93.184.216.34', '::ffff:127.0.0.1']],
  ['unspecified', ['0.0.0.0']],
]) {
  for (const kind of ['http', 'connect']) {
    results.ac15[`${label}_${kind}`] = await arm(['R'], async ({ R }, open) => {
      const lookup = countingLookup(addresses);
      const dial = recordingDial(R.port);
      const p = await open({ config: { origins: [remoteOf(R)], allow_remote: true }, lookup, dial });
      const text = kind === 'http' ? GET(`${remoteOf(R)}/p`) : `CONNECT remote.selvedge.test:${R.port} HTTP/1.1\r\nHost: remote.selvedge.test:${R.port}\r\n\r\n`;
      const r = await rawExchange(p.port, text);
      return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, lookups: lookup.calls.length, dials: dial.calls.length, R: logOf(R), blocks: p.blocks };
    });
  }
}

// AC15 — the proxy connects to the validated address, never to the name (one lookup in total).
results.ac15_validated = await arm(['R'], async ({ R }, open) => {
  const lookup = countingLookup(['93.184.216.34']);
  const dial = recordingDial(R.port);
  const p = await open({ config: { origins: [remoteOf(R)], allow_remote: true }, lookup, dial });
  const r = await rawExchange(p.port, GET(`${remoteOf(R)}/v`));
  const lookupsAfterGet = lookup.calls.length;
  const dialsAfterGet = dial.calls.slice();
  const r2 = await rawExchange(p.port, `CONNECT remote.selvedge.test:${R.port} HTTP/1.1\r\nHost: remote.selvedge.test:${R.port}\r\n\r\n`, {
    then: `GET /tunnelled HTTP/1.1\r\nHost: remote.selvedge.test:${R.port}\r\nConnection: close\r\n\r\n`,
  });
  return { status: r.status, connectStatus: r2.status, tunnel: r2.tunnel || null, lookupsAfterGet, dialsAfterGet, lookups: lookup.calls.length, lookupHosts: lookup.calls.map((c) => c.host), lookupAll: lookup.calls.every((c) => c.opts && c.opts.all === true), dials: dial.calls, R: R.events };
});

// AC18 — an unlisted remote is refused before any lookup, CONNECT and plain alike.
// Each injects a recording dial aimed at a local fixture, so even a mutant that let the request
// through would never reach the real network.
results.ac18_connect = await arm(['A'], async ({ A }, open) => {
  const lookup = countingLookup(['93.184.216.34']);
  const p = await open({ config: { origins: [A.origin] }, lookup, dial: recordingDial(A.port) });
  const r = await rawExchange(p.port, 'CONNECT shop.example.com:443 HTTP/1.1\r\nHost: shop.example.com:443\r\n\r\n');
  return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, lookups: lookup.calls.length, blocks: p.blocks };
});
results.ac18_get = await arm(['A'], async ({ A }, open) => {
  const lookup = countingLookup(['93.184.216.34']);
  const p = await open({ config: { origins: [A.origin] }, lookup, dial: recordingDial(A.port) });
  const r = await rawExchange(p.port, GET('http://shop.example.com/?next=localhost'));
  return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, lookups: lookup.calls.length, blocks: p.blocks };
});

// AC19 — a plain-HTTP mutation to a listed remote without allow_remote_mutation: refused before lookup.
results.ac19 = {};
for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'GET']) {
  results.ac19[method] = await arm(['R'], async ({ R }, open) => {
    const lookup = countingLookup(['93.184.216.34']);
    const dial = recordingDial(R.port);
    const p = await open({ config: { origins: [remoteOf(R)], allow_remote: true, allow_remote_mutation: false }, lookup, dial });
    const body = method === 'GET' ? '' : 'k=v';
    const r = await rawExchange(
      p.port,
      `${method} ${remoteOf(R)}/m HTTP/1.1\r\nHost: remote.selvedge.test:${R.port}\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n${body}`,
    );
    return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, lookups: lookup.calls.length, R: logOf(R), blocks: p.blocks };
  });
}
results.ac19_mutation_allowed = await arm(['R'], async ({ R }, open) => {
  const lookup = countingLookup(['93.184.216.34']);
  const dial = recordingDial(R.port);
  const p = await open({ config: { origins: [remoteOf(R)], allow_remote: true, allow_remote_mutation: true }, lookup, dial });
  const r = await rawExchange(p.port, `POST ${remoteOf(R)}/m HTTP/1.1\r\nHost: remote.selvedge.test:${R.port}\r\nContent-Length: 3\r\nConnection: close\r\n\r\nk=v`);
  return { status: r.status, R: R.events };
});

// A listed remote without allow_remote (an unvalidated config) is refused, before any lookup.
results.remote_without_allow_remote = await arm(['R'], async ({ R }, open) => {
  const lookup = countingLookup(['93.184.216.34']);
  const p = await open({ config: { origins: [remoteOf(R)] }, lookup, dial: recordingDial(R.port) });
  const r = await rawExchange(p.port, GET(`${remoteOf(R)}/`));
  return { status: r.status, blockedHeader: r.headers['x-selvedge-blocked'] || null, lookups: lookup.calls.length, R: logOf(R) };
});

// close() stops the listener: a new connection to the proxy port is refused.
results.close_refuses = await arm(['A'], async ({ A }, open) => {
  const p = await open({ config: { origins: [A.origin] } });
  await p.close();
  const outcome = await new Promise((resolve) => {
    const s = net.connect({ host: '127.0.0.1', port: p.port });
    s.on('connect', () => {
      s.destroy();
      resolve('connected');
    });
    s.on('error', (e) => resolve(e.code || 'error'));
  });
  return { outcome };
});

process.stdout.write(`${JSON.stringify(results)}\n`);
