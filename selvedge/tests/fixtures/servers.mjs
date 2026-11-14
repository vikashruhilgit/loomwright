// servers.mjs — recording fixture servers for selvedge's guard tests (test-proxy.sh,
// test-route-guard.sh). Not named test-*, so selvedge/tests/run.sh never runs it directly.
//
// Each server binds 127.0.0.1 on a random port and appends every accepted TCP connection and every
// request line (method, path, Upgrade header) to its own JSON log file (a JSON array, rewritten on
// each event). Tests assert "records zero connections" on that file, so a connection the guard was
// meant to stop is visible even when the browser reports nothing.
//
// Routes:
//   /                 an HTML page naming the server
//   /redirect?to=U    302 to U
//   /form307?to=U     a page that auto-submits a form POST to /r307?to=U
//   /r307?to=U        307 to U (the browser re-sends the POST)
//   /sw.js            a service worker script
//   anything else     200 text naming the server, method and path
// A WebSocket upgrade is recorded and then refused (the socket is destroyed).
import http from 'node:http';
import { writeFileSync } from 'node:fs';
import path from 'node:path';

function html(body) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>fixture</title></head><body>${body}</body></html>`;
}

function escapeAttr(s) {
  return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

// startServer(name, logDir) → Promise<{ name, port, origin, logFile, events, close() }>
export async function startServer(name, logDir) {
  const events = [];
  const logFile = path.join(logDir, `${name}.json`);
  const sockets = new Set();
  const record = (event) => {
    events.push(event);
    writeFileSync(logFile, JSON.stringify(events));
  };
  writeFileSync(logFile, '[]');

  const server = http.createServer((req, res) => {
    record({ event: 'request', method: req.method, path: req.url, upgrade: req.headers.upgrade || null });
    const url = new URL(req.url, 'http://fixture.invalid');
    const to = url.searchParams.get('to');
    req.resume();
    if (url.pathname === '/redirect' && to) {
      res.writeHead(302, { location: to, 'content-type': 'text/plain' });
      res.end('redirect\n');
      return;
    }
    if (url.pathname === '/r307' && to) {
      res.writeHead(307, { location: to, 'content-type': 'text/plain' });
      res.end('redirect 307\n');
      return;
    }
    if (url.pathname === '/form307' && to) {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(
        html(
          `<form id="f" method="POST" action="/r307?to=${escapeAttr(encodeURIComponent(to))}"><input name="k" value="v"></form>` +
            '<script>document.getElementById("f").submit()</script>',
        ),
      );
      return;
    }
    if (url.pathname === '/sw.js') {
      res.writeHead(200, { 'content-type': 'application/javascript' });
      res.end("self.addEventListener('fetch', () => {});\n");
      return;
    }
    if (url.pathname === '/') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(html(`<h1>fixture ${escapeAttr(name)}</h1>`));
      return;
    }
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'access-control-allow-origin': '*' });
    res.end(`fixture ${name} ${req.method} ${url.pathname}\n`);
  });
  server.on('connection', (socket) => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
    record({ event: 'connection' });
  });
  server.on('upgrade', (req, socket) => {
    record({ event: 'request', method: req.method, path: req.url, upgrade: req.headers.upgrade || null });
    socket.destroy();
  });
  server.on('clientError', (_err, socket) => socket.destroy());

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const port = server.address().port;
  return {
    name,
    port,
    origin: `http://localhost:${port}`,
    logFile,
    events,
    close: () =>
      new Promise((resolve) => {
        server.close(() => resolve());
        for (const s of sockets) s.destroy();
      }),
  };
}

// startServers(names, logDir) → { [name]: server } plus closeAll().
export async function startServers(names, logDir) {
  const servers = {};
  for (const name of names) servers[name] = await startServer(name, logDir);
  Object.defineProperty(servers, 'closeAll', {
    enumerable: false,
    value: async () => {
      await Promise.all(names.map((n) => servers[n].close()));
    },
  });
  return servers;
}
