// proxy.mjs — the runner-owned forward proxy every guarded browser connection goes through.
//
// Chromium is launched with this proxy as its only route out (route-guard.mjs builds the launch
// options), so every connection it makes — a navigation, each redirect hop, a fetch, a ws/wss
// handshake, an https CONNECT — arrives here and is checked by ORIGIN before any byte leaves:
//
//   1. allowlist: the target's origin must be listed (isOriginAllowed from env-config.mjs — the one
//      origin parser; exact scheme, host AND port). A remote origin also needs allow_remote: true.
//      Unlisted ⇒ BLOCKED host_not_allowed, decided before any DNS lookup.
//   2. mutation: a plain-HTTP POST/PUT/PATCH/DELETE to a remote origin without
//      allow_remote_mutation ⇒ BLOCKED remote_mutation_refused, also before any lookup. (A CONNECT
//      tunnel hides the method; route-guard.mjs's route layer covers https.)
//   3. resolution: a remote host is looked up ONCE (`lookup(host, { all: true })`); if ANY resolved
//      address is private, loopback, link-local, unique-local, multicast or unspecified ⇒ BLOCKED
//      remote_resolves_private and no connection is attempted. Otherwise the proxy connects to the
//      validated addresses themselves, never to the name (so no second lookup can rebind it). Local
//      origins (localhost, 127.0.0.1, [::1]) need no lookup: localhost is loopback by definition.
//
// HTTPS and WSS are tunnelled (CONNECT host:port): the proxy sees host and port only, never the
// path or the method — no TLS interception. A CONNECT is allowed when http:// or https:// with that
// exact host and port is listed (Chromium tunnels ws:// through CONNECT too).
//
// Every refusal is recorded as { reason, origin, host, layer: 'proxy', … } in `blocks` (and passed
// to `onBlock`), and answered with `403` plus an `X-Selvedge-Blocked: <reason>` header.
//
// Node >= 18, standard library only. Reads no environment variable: `lookup` and `dial` are
// programmatic options only (tests inject them); no env var or CLI flag can set them.
import http from 'node:http';
import net from 'node:net';
import { lookup as dnsLookup } from 'node:dns/promises';
import { REASONS, isLocalOrigin, isOriginAllowed, parseOrigin } from '../env-config.mjs';

// The proxy layer's own mutating-method set. route-guard.mjs keeps its own copy on purpose: the two
// layers are independent, so a change to one cannot silently weaken the other.
const MUTATING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

export const BLOCKED_HEADER = 'x-selvedge-blocked';

const HOP_BY_HOP = new Set([
  'connection',
  'keep-alive',
  'proxy-connection',
  'proxy-authorization',
  'proxy-authenticate',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

// Addresses a remote origin may never resolve to. Two lists on purpose: a BlockList holding an
// IPv4-mapped IPv6 subnet also matches plain IPv4 queries, so the families never share one list.
const PRIVATE4 = new net.BlockList();
const PRIVATE6 = new net.BlockList();
for (const [net4, prefix] of [
  ['0.0.0.0', 8], // "this network", incl. the unspecified 0.0.0.0
  ['10.0.0.0', 8], // private
  ['100.64.0.0', 10], // carrier-grade NAT (shared)
  ['127.0.0.0', 8], // loopback
  ['169.254.0.0', 16], // link-local
  ['172.16.0.0', 12], // private
  ['192.0.0.0', 24], // IETF protocol assignments
  ['192.168.0.0', 16], // private
  ['198.18.0.0', 15], // benchmarking
  ['224.0.0.0', 4], // multicast
  ['240.0.0.0', 4], // reserved, incl. broadcast
]) {
  PRIVATE4.addSubnet(net4, prefix, 'ipv4');
}
for (const [net6, prefix] of [
  ['::', 96], // unspecified ::, loopback ::1, IPv4-compatible
  ['::ffff:0:0', 96], // IPv4-mapped (fail closed: never dial a mapped address)
  ['fc00::', 7], // unique-local
  ['fe80::', 10], // link-local
  ['fec0::', 10], // site-local (deprecated)
  ['ff00::', 8], // multicast
]) {
  PRIVATE6.addSubnet(net6, prefix, 'ipv6');
}

// True when `address` is not a public unicast IP (anything unparsable counts as private).
export function isPrivateAddress(address) {
  const family = net.isIP(address);
  if (family === 4) return PRIVATE4.check(address, 'ipv4');
  if (family === 6) return PRIVATE6.check(address, 'ipv6');
  return true;
}

const LOCAL_ADDRESSES = Object.freeze({
  localhost: Object.freeze(['127.0.0.1', '::1']),
  '127.0.0.1': Object.freeze(['127.0.0.1']),
  '[::1]': Object.freeze(['::1']),
});

function hostOf(target) {
  return `${target.hostname}:${target.port}`;
}

function defaultDial(address, port) {
  return net.connect({ host: address, port: Number(port) });
}

// Connect to the first reachable address, in order. Resolves with a connected socket.
function connectFirst(addresses, port, dial) {
  return new Promise((resolve, reject) => {
    let i = 0;
    const next = (lastErr) => {
      if (i >= addresses.length) {
        reject(lastErr || new Error('no address to connect to'));
        return;
      }
      const address = addresses[i++];
      let socket;
      try {
        socket = dial(address, port);
      } catch (err) {
        next(err);
        return;
      }
      const onError = (err) => {
        socket.removeListener('connect', onConnect);
        socket.destroy();
        next(err);
      };
      const onConnect = () => {
        socket.removeListener('error', onError);
        resolve(socket);
      };
      socket.once('error', onError);
      socket.once('connect', onConnect);
    };
    next(null);
  });
}

function filterHeaders(headers) {
  const outHeaders = {};
  for (const [name, value] of Object.entries(headers)) {
    if (!HOP_BY_HOP.has(name.toLowerCase())) outHeaders[name] = value;
  }
  return outHeaders;
}

// startProxy({ config, lookup?, dial?, host?, port?, onBlock? }) → Promise<{ port, url, blocks, log,
// lookups, close() }>.
//   config  a loaded selvedge config ({ origins, allow_remote, allow_remote_mutation })
//   lookup  dns.promises.lookup-compatible; injected by tests only (default node:dns/promises)
//   dial    (address, port) → net.Socket; injected by tests only (default net.connect)
// `blocks` holds every refusal, `log` every request the proxy received, `lookups` the number of
// lookups it ran. close() stops listening and destroys every open socket (the browser then sees
// ERR_PROXY_CONNECTION_FAILED, never a direct connection).
export async function startProxy({ config, lookup = dnsLookup, dial = defaultDial, host = '127.0.0.1', port = 0, onBlock } = {}) {
  if (!config || !Array.isArray(config.origins)) throw new TypeError('startProxy needs a loaded config with an origins list');
  const blocks = [];
  const log = [];
  const sockets = new Set();
  const state = { lookups: 0, closed: false };

  const track = (socket) => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
    return socket;
  };

  const block = (reason, target, extra = {}) => {
    const record = Object.freeze({ reason, origin: target.origin, host: hostOf(target), layer: 'proxy', ...extra });
    blocks.push(record);
    if (typeof onBlock === 'function') {
      try {
        onBlock(record);
      } catch {
        // an observer's failure never changes the decision
      }
    }
    return record;
  };

  // The per-connection origin check: listed, and (when remote) allow_remote is on.
  const checkOrigin = (target) =>
    isOriginAllowed(config, target.origin) && (isLocalOrigin(target) || config.allow_remote === true);

  // The addresses to dial for an allowed target. Throws { reason } when a remote resolves private.
  const resolveTarget = async (target) => {
    if (isLocalOrigin(target)) return LOCAL_ADDRESSES[target.hostname];
    const bare = target.hostname.replace(/^\[(.*)\]$/, '$1');
    let addresses;
    if (net.isIP(bare)) {
      addresses = [bare];
    } else {
      state.lookups += 1;
      const rows = await lookup(bare, { all: true, verbatim: true });
      addresses = (Array.isArray(rows) ? rows : [rows]).map((r) => (r && typeof r === 'object' ? r.address : r));
    }
    if (addresses.length === 0 || addresses.some((a) => typeof a !== 'string' || isPrivateAddress(a))) {
      const err = new Error(`${target.hostname} resolves to a private, loopback or link-local address (${addresses.join(', ')})`);
      err.reason = REASONS.remote_resolves_private;
      throw err;
    }
    return addresses;
  };

  const refuseHttp = (res, record) => {
    if (res.headersSent) {
      res.destroy();
      return;
    }
    res.writeHead(403, { 'content-type': 'text/plain; charset=utf-8', [BLOCKED_HEADER]: record.reason, connection: 'close' });
    res.end(`BLOCKED ${record.reason} ${record.host}\n`);
  };

  const refuseRaw = (socket, record) => {
    if (socket.destroyed) return;
    socket.end(
      `HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain; charset=utf-8\r\n${BLOCKED_HEADER}: ${record.reason}\r\nConnection: close\r\n\r\nBLOCKED ${record.reason} ${record.host}\n`,
    );
  };

  const failRaw = (socket, status, text) => {
    if (!socket.destroyed) socket.end(`HTTP/1.1 ${status}\r\nConnection: close\r\n\r\n${text}\n`);
  };

  // Plain HTTP: absolute-form request lines (`GET http://host:port/path`).
  const onRequest = async (req, res) => {
    let url;
    try {
      url = new URL(req.url);
    } catch {
      url = null;
    }
    if (!url || url.protocol !== 'http:') {
      res.writeHead(400, { 'content-type': 'text/plain; charset=utf-8', connection: 'close' });
      res.end('selvedge proxy: expected an absolute http:// request URL\n');
      return;
    }
    const target = parseOrigin(url.origin);
    log.push(Object.freeze({ kind: 'http', method: req.method, origin: target ? target.origin : url.origin }));
    if (!target || !checkOrigin(target)) {
      refuseHttp(res, block(REASONS.host_not_allowed, target || { origin: url.origin, hostname: url.hostname, port: url.port }, { method: req.method }));
      return;
    }
    if (!isLocalOrigin(target) && MUTATING_METHODS.has(req.method) && config.allow_remote_mutation !== true) {
      refuseHttp(res, block(REASONS.remote_mutation_refused, target, { method: req.method }));
      return;
    }
    let socket;
    try {
      const addresses = await resolveTarget(target);
      socket = track(await connectFirst(addresses, target.port, dial));
    } catch (err) {
      if (err && err.reason) {
        refuseHttp(res, block(err.reason, target, { method: req.method }));
      } else if (!res.headersSent) {
        res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8', connection: 'close' });
        res.end(`selvedge proxy: cannot reach ${hostOf(target)}: ${err && err.message}\n`);
      }
      return;
    }
    const headers = filterHeaders(req.headers);
    headers.connection = 'close';
    const upstream = http.request({
      method: req.method,
      path: `${url.pathname}${url.search}`,
      headers,
      setHost: false,
      // No `agent` key: with one (even `false`) Node ignores createConnection and dials the
      // request's own host — the request must go only to the socket already validated above.
      createConnection: () => socket,
    });
    upstream.on('response', (ures) => {
      res.writeHead(ures.statusCode || 502, ures.statusMessage, filterHeaders(ures.headers));
      ures.pipe(res);
      ures.on('error', () => res.destroy());
    });
    upstream.on('error', (err) => {
      if (!res.headersSent) {
        res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8', connection: 'close' });
        res.end(`selvedge proxy: upstream error: ${err && err.message}\n`);
      } else {
        res.destroy();
      }
    });
    req.pipe(upstream);
  };

  // CONNECT host:port — https and ws/wss tunnels. Only host and port are visible.
  const onConnect = async (req, clientSocket, head) => {
    track(clientSocket);
    clientSocket.on('error', () => clientSocket.destroy());
    // Exactly `host:port` (authority-form); anything else is not a CONNECT this proxy serves.
    let target = null;
    if (/^(?:[^\s/?#@[\]:]+|\[[0-9A-Fa-f:.]+\]):\d{1,5}$/.test(String(req.url))) {
      try {
        target = parseOrigin(new URL(`https://${req.url}`).origin);
      } catch {
        target = null;
      }
    }
    if (!target) {
      log.push(Object.freeze({ kind: 'connect', method: 'CONNECT', origin: String(req.url) }));
      failRaw(clientSocket, '400 Bad Request', 'selvedge proxy: CONNECT needs host:port');
      return;
    }
    // Chromium tunnels https and ws/wss alike; either scheme listed with this exact host and port allows it.
    const httpTwin = parseOrigin(`http://${target.hostname}${target.port === '80' ? '' : `:${target.port}`}`);
    log.push(Object.freeze({ kind: 'connect', method: 'CONNECT', origin: target.origin }));
    const allowed = checkOrigin(target) || (httpTwin !== null && checkOrigin(httpTwin));
    if (!allowed) {
      refuseRaw(clientSocket, block(REASONS.host_not_allowed, target, { method: 'CONNECT' }));
      return;
    }
    let upstream;
    try {
      const addresses = await resolveTarget(target);
      upstream = track(await connectFirst(addresses, target.port, dial));
    } catch (err) {
      if (err && err.reason) refuseRaw(clientSocket, block(err.reason, target, { method: 'CONNECT' }));
      else failRaw(clientSocket, '502 Bad Gateway', `selvedge proxy: cannot reach ${hostOf(target)}`);
      return;
    }
    if (clientSocket.destroyed) {
      upstream.destroy();
      return;
    }
    upstream.on('error', () => clientSocket.destroy());
    clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    if (head && head.length) upstream.write(head);
    upstream.pipe(clientSocket);
    clientSocket.pipe(upstream);
  };

  // Plain-HTTP upgrades (`GET http://host:port/ws` + `Upgrade: websocket`) through the proxy.
  const onUpgrade = async (req, clientSocket, head) => {
    track(clientSocket);
    clientSocket.on('error', () => clientSocket.destroy());
    let url;
    try {
      url = new URL(req.url);
    } catch {
      url = null;
    }
    const target = url && url.protocol === 'http:' ? parseOrigin(url.origin) : null;
    log.push(Object.freeze({ kind: 'upgrade', method: req.method, origin: target ? target.origin : String(req.url) }));
    if (!target) {
      failRaw(clientSocket, '400 Bad Request', 'selvedge proxy: expected an absolute http:// upgrade URL');
      return;
    }
    if (!checkOrigin(target)) {
      refuseRaw(clientSocket, block(REASONS.host_not_allowed, target, { method: req.method }));
      return;
    }
    let upstream;
    try {
      const addresses = await resolveTarget(target);
      upstream = track(await connectFirst(addresses, target.port, dial));
    } catch (err) {
      if (err && err.reason) refuseRaw(clientSocket, block(err.reason, target, { method: req.method }));
      else failRaw(clientSocket, '502 Bad Gateway', `selvedge proxy: cannot reach ${hostOf(target)}`);
      return;
    }
    if (clientSocket.destroyed) {
      upstream.destroy();
      return;
    }
    upstream.on('error', () => clientSocket.destroy());
    const lines = [`${req.method} ${url.pathname}${url.search} HTTP/1.1`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const name = req.rawHeaders[i];
      const lower = name.toLowerCase();
      if (lower === 'proxy-connection' || lower === 'proxy-authorization') continue;
      lines.push(`${name}: ${req.rawHeaders[i + 1]}`);
    }
    upstream.write(`${lines.join('\r\n')}\r\n\r\n`);
    if (head && head.length) upstream.write(head);
    upstream.pipe(clientSocket);
    clientSocket.pipe(upstream);
  };

  const server = http.createServer((req, res) => {
    onRequest(req, res).catch(() => res.destroy());
  });
  server.on('connection', track);
  server.on('connect', (req, socket, head) => {
    onConnect(req, socket, head).catch(() => socket.destroy());
  });
  server.on('upgrade', (req, socket, head) => {
    onUpgrade(req, socket, head).catch(() => socket.destroy());
  });
  server.on('clientError', (_err, socket) => socket.destroy());

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.removeListener('error', reject);
      resolve();
    });
  });
  const boundPort = server.address().port;

  const close = () =>
    new Promise((resolve) => {
      if (state.closed) {
        resolve();
        return;
      }
      state.closed = true;
      server.close(() => resolve());
      for (const s of sockets) s.destroy();
      sockets.clear();
    });

  return {
    port: boundPort,
    url: `http://${host}:${boundPort}`,
    blocks,
    log,
    get lookups() {
      return state.lookups;
    },
    close,
  };
}
