// app-server.mjs — a small web app for selvedge's snapshot, plan and run tests (test-snapshot.sh,
// test-plan.sh, test-run.sh, test-replay.sh, test-auth-run.sh), and the quick start's sample app
// (`selvedge sample-app`, test-sample-app.sh). Not named test-*, so selvedge/tests/run.sh never
// runs it directly.
//
// Pages (every page is a complete HTML document; scripts are inline, nothing loads from elsewhere):
//   /             a plain page: heading "Plain page", no controls
//   /cart         heading "Shop" and an "Open cart" button; the button opens a role=dialog named
//                 "Cart" holding a "Quantity" spinbutton (a number input, value 1) and a "Total"
//                 value (data-testid "total": 6 × the quantity), plus a "Close" button. The dialog
//                 is `hidden` until the click, so it is absent from the accessibility tree before it.
//                 After a /control/cart-label request the button's accessible name (aria-label) is
//                 that label while its visible text still reads "Open cart" (a renamed control a
//                 role locator no longer matches, though a text match still would).
//   /echo         a "User" text field, a "Reset" button and a paragraph (data-testid "echo") that
//                 reads "Hello, <the field's value>" ("Hello, nobody" when empty) on every input,
//                 and one (data-testid "echo-reversed") reading "Reversed: <the value reversed>"
//                 (how a test sees that the page got a value snapshot prints as {{NAME}});
//                 a "Size" select (S, M, L), a "Gift wrap" checkbox and a paragraph (data-testid
//                 "order") reading "size <S|M|L>, gift wrap <yes|no>, last key <key|none>" (the
//                 last key pressed anywhere on the page)
//   /cookie       a paragraph "cookie: <the request's Cookie header, or none>"; with ?set=1 the
//                 response also sets the cookie selvedge_fixture=seen (path /)
//   /slow         a "Load price" button and a value (data-testid "price") reading "pending"; the
//                 click fetches /api/price, which the server answers only after SLOW_PRICE_MS
//                 (1.5 s) with "42", and only then does the value read "42"
//   /api/price    the slow answer above (text/plain "42")
//   /controls     a "Do nothing" button (no handler: clicking it changes nothing), an empty value
//                 (data-testid "empty", no text), a hidden "Hidden action" button, a "Covered action"
//                 button under an overlay that takes its clicks, and a side-effect counter
//                 (data-testid "count", "0") that an "Add one" button increments
//   /silent-cookie  sets the cookie selvedge_secret=SILENT_COOKIE_VALUE (path /, HttpOnly) and
//                 never prints it; its script fetches /api/whoami with the header
//                 `Authorization: Bearer <BEARER_TOKEN>` and shows the answer (data-testid "whoami")
//   /api/whoami   text/plain "signed in" when the Authorization header is that bearer, else "anonymous"
//   /control/cart-label?name=<label>  sets the /cart button's aria-label (above); with no name it is
//                 reset. Server state, reset on every server start; answers text "ok"
//   /login        GET: a sign-in form ("User" and "Password" fields, a "Sign in" button) posting to
//                 /login. POST (form-encoded user, pass, both non-empty): starts a session (cookie
//                 selvedge_session=<random id>, path /, HttpOnly) and redirects 303 to /account; an
//                 empty field answers 401 with the form again
//   /account      the login wall: with a live session cookie, heading "Account", "Signed in as
//                 <user>" (data-testid "signed-in-as") and "Your password is <pass>" (data-testid
//                 "password-echo": a page that shows a credential, which a run must redact); without
//                 one, a 302 redirect to /login. Every request to /account is counted
//   /control/hits?path=<path>  text: how many requests <path> has had since the server started
//                 (only /account is counted)
//   /control/expire-sessions  ends every session, so a saved cookie is no longer accepted; answers
//                 text "ok"
//   /api/forecast  GET: with a live API session cookie (selvedge_api, below) 200 JSON
//                 {"days": [{"day": "mon", "high": 21}, …]}; without one 401 JSON {"error": "unauthorized"}
//   /api/login    POST JSON {email, password}, both non-empty strings: 200 JSON {"user": {"email"},
//                 "echo": <the password>} (a reply that holds a credential, which a run must redact)
//                 and the cookie selvedge_api=<API_COOKIE_PREFIX><random> (path /, HttpOnly); else 400
//                 JSON {"error": "email and password are required"}. Every POST is counted
//                 (/control/hits?path=/api/login)
//   /api/big      GET: text/plain of BIG_REPLY_CHARS characters (past the runner's 64 KiB reply cap)
//   anything else 404 text
// Every request is recorded (method, path, Cookie header) in `events`.
//
// Library:  startAppServer({ port }?) → Promise<{ port, origin, events, close() }> (binds 127.0.0.1;
//           with no argument, or port 0, a random port; origin is http://localhost:<port>). A port
//           already in use rejects with the listen error (code EADDRINUSE).
// Command:  node app-server.mjs serve <info.json> [<log dir>]
//           starts the app (and, with a log dir, a servers.mjs recording server named U whose JSON
//           log is <log dir>/U.json), writes {app: {port, origin}, U?: {port, origin, logFile}} to
//           <info.json> (atomically: written to a temp name, then renamed), and runs until SIGTERM
//           or SIGINT closes every server. A watchdog exits it after 15 minutes so a test that dies
//           without killing it never leaves it running.
// Command:  node app-server.mjs sample [--port <N>]   (what `selvedge sample-app [--port N]` runs)
//           the quick start's sample app: serves on port N (default 4173, DEFAULT_SAMPLE_PORT) in
//           the foreground until Ctrl-C (SIGINT) or SIGTERM, and prints its origin and the
//           `selvedge env init --port N` line to use. No watchdog in this mode: a user runs it as
//           long as they like. Before it listens it connects to 127.0.0.1:N and [::1]:N
//           (`localhost` can resolve to either): a connection that is accepted on either means
//           something already serves there (a listener on 127.0.0.1, on ::1, or on the wildcard
//           `::` / 0.0.0.0, which a bind on 127.0.0.1 alone would sit beside unnoticed), so it
//           exits 1 with one line naming the port; then it binds 127.0.0.1, and that listen's own
//           EADDRINUSE exits 1 the same way. A bad --port exits 2.
import { randomBytes } from 'node:crypto';
import http from 'node:http';
import net from 'node:net';
import { renameSync, writeFileSync } from 'node:fs';
import { startServer } from './servers.mjs';

const UNIT_PRICE = 6;
const SLOW_PRICE_MS = 1500;
const SLOW_PRICE = '42';
// What a trace must never keep (test-replay.sh greps for both).
export const SILENT_COOKIE_VALUE = 'ckv-7Q2mZp4Lr9Xs';
export const BEARER_TOKEN = 'tok-Hb81Vd3Nq6Wf';

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function page(title, body) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${escapeHtml(title)}</title></head><body>${body}</body></html>`;
}

const PLAIN = page('Plain', '<main><h1>Plain page</h1><p>Nothing to open here.</p></main>');

// The /cart page; `label` (a /control/cart-label name) becomes the Open cart button's aria-label.
const cartPage = (label) => page(
  'Shop',
  `<main><h1>Shop</h1>
<button type="button" id="open"${label ? ` aria-label="${escapeHtml(label)}"` : ''}>Open cart</button>
<div role="dialog" aria-label="Cart" id="cart" hidden>
  <label>Quantity <input type="number" id="qty" min="0" value="1"></label>
  <p>Total: <span data-testid="total" id="total">${UNIT_PRICE}</span></p>
  <button type="button" id="close">Close</button>
</div></main>
<script>
const cart = document.getElementById('cart');
const qty = document.getElementById('qty');
const total = document.getElementById('total');
document.getElementById('open').addEventListener('click', () => { cart.hidden = false; });
document.getElementById('close').addEventListener('click', () => { cart.hidden = true; });
qty.addEventListener('input', () => { total.textContent = String((Number(qty.value) || 0) * ${UNIT_PRICE}); });
</script>`,
);

const ECHO = page(
  'Echo',
  `<main><h1>Echo</h1>
<label>User <input type="text" id="user" name="user"></label>
<button type="button" id="reset">Reset</button>
<p data-testid="echo" id="echo">Hello, nobody</p>
<p data-testid="echo-reversed" id="rev">Reversed: nobody</p>
<label>Size <select id="size"><option>S</option><option>M</option><option>L</option></select></label>
<label><input type="checkbox" id="wrap"> Gift wrap</label>
<p data-testid="order" id="order">size S, gift wrap no, last key none</p></main>
<script>
const user = document.getElementById('user');
const echo = document.getElementById('echo');
const rev = document.getElementById('rev');
const size = document.getElementById('size');
const wrap = document.getElementById('wrap');
const order = document.getElementById('order');
let lastKey = 'none';
const show = () => {
  echo.textContent = 'Hello, ' + (user.value || 'nobody');
  rev.textContent = 'Reversed: ' + (user.value ? user.value.split('').reverse().join('') : 'nobody');
};
const showOrder = () => { order.textContent = 'size ' + size.value + ', gift wrap ' + (wrap.checked ? 'yes' : 'no') + ', last key ' + lastKey; };
user.addEventListener('input', show);
document.getElementById('reset').addEventListener('click', () => { user.value = ''; show(); });
size.addEventListener('change', showOrder);
wrap.addEventListener('change', showOrder);
document.addEventListener('keydown', (e) => { lastKey = e.key; showOrder(); });
</script>`,
);

const SLOW = page(
  'Slow',
  `<main><h1>Slow</h1>
<button type="button" id="load">Load price</button>
<p>Price: <span data-testid="price" id="price">pending</span></p></main>
<script>
const price = document.getElementById('price');
document.getElementById('load').addEventListener('click', () => {
  fetch('/api/price').then((r) => r.text()).then((t) => { price.textContent = t; });
});
</script>`,
);

const CONTROLS = page(
  'Controls',
  `<main><h1>Controls</h1>
<button type="button" id="dead">Do nothing</button>
<p>Empty: <span data-testid="empty" id="empty"></span></p>
<button type="button" id="hidden" hidden>Hidden action</button>
<div style="position: relative; width: 240px; height: 48px;">
  <button type="button" id="covered">Covered action</button>
  <div id="overlay" style="position: absolute; inset: 0; background: #fff;"></div>
</div>
<p>Count: <span data-testid="count" id="count">0</span></p>
<button type="button" id="add">Add one</button></main>
<script>
const count = document.getElementById('count');
const addOne = () => { count.textContent = String(Number(count.textContent) + 1); };
document.getElementById('add').addEventListener('click', addOne);
document.getElementById('add').addEventListener('click', () => addOne());
document.getElementById('covered').addEventListener('click', () => { count.textContent = 'covered clicked'; });
</script>`,
);

const LOGIN = page(
  'Sign in',
  `<main><h1>Sign in</h1>
<form method="post" action="/login">
<label>User <input type="text" name="user"></label>
<label>Password <input type="password" name="pass"></label>
<button type="submit">Sign in</button>
</form></main>`,
);

const accountPage = ({ user, pass }) => page(
  'Account',
  `<main><h1>Account</h1>
<p data-testid="signed-in-as">Signed in as ${escapeHtml(user)}</p>
<p data-testid="password-echo">Your password is ${escapeHtml(pass)}</p></main>`,
);

const SESSION_COOKIE = 'selvedge_session';

// The value of cookie `name` in a Cookie header, or null.
function cookieValue(header, name) {
  for (const part of String(header || '').split(';')) {
    const eq = part.indexOf('=');
    if (eq > 0 && part.slice(0, eq).trim() === name) return part.slice(eq + 1).trim();
  }
  return null;
}

// The value prefix of every /api/login session cookie: a test checks no output holds it.
export const API_COOKIE_PREFIX = 'apisess-7f3c9d-';
export const API_COOKIE = 'selvedge_api';
export const BIG_REPLY_CHARS = 70000;

const SILENT = page(
  'Account',
  `<main><h1>Account</h1>
<p>Session: <span data-testid="whoami" id="whoami">checking</span></p></main>
<script>
fetch('/api/whoami', { headers: { Authorization: 'Bearer ${BEARER_TOKEN}' } })
  .then((r) => r.text()).then((t) => { document.getElementById('whoami').textContent = t; });
</script>`,
);

// startAppServer({ port = 0 }?) → Promise<{ port, origin, events, close() }>
export async function startAppServer({ port: listenPort = 0 } = {}) {
  const events = [];
  let cartLabel = null; // /control/cart-label; null: the button's name is its text
  const sessions = new Map(); // session id → { user, pass } (/login, /account)
  const apiSessions = new Set(); // /api/login cookie values
  const hits = new Map(); // counted path → requests (/account)
  const sockets = new Set();
  const server = http.createServer((req, res) => {
    events.push({ method: req.method, path: req.url, cookie: req.headers.cookie || null });
    const url = new URL(req.url, 'http://fixture.invalid');
    const send = (status, html, headers = {}) => {
      res.writeHead(status, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', ...headers });
      res.end(html);
    };
    const text = (body) => {
      res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
      res.end(body);
    };
    const json = (status, body, headers = {}) => {
      res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers });
      res.end(JSON.stringify(body));
    };
    if (url.pathname === '/api/login' && req.method === 'POST') {
      hits.set('/api/login', (hits.get('/api/login') || 0) + 1);
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        let body = null;
        try {
          body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        } catch {
          body = null;
        }
        const ok = body && typeof body.email === 'string' && body.email !== '' && typeof body.password === 'string' && body.password !== '';
        if (!ok) {
          json(400, { error: 'email and password are required' });
          return;
        }
        const id = `${API_COOKIE_PREFIX}${randomBytes(8).toString('hex')}`;
        apiSessions.add(id);
        json(200, { user: { email: body.email }, echo: body.password }, { 'set-cookie': `${API_COOKIE}=${id}; Path=/; HttpOnly` });
      });
      return;
    }
    if (url.pathname === '/login' && req.method === 'POST') {
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        const form = new URLSearchParams(Buffer.concat(chunks).toString('utf8'));
        const user = form.get('user') || '';
        const pass = form.get('pass') || '';
        if (!user || !pass) {
          send(401, LOGIN);
          return;
        }
        const id = randomBytes(16).toString('hex');
        sessions.set(id, { user, pass });
        res.writeHead(303, { location: '/account', 'cache-control': 'no-store', 'set-cookie': `${SESSION_COOKIE}=${id}; Path=/; HttpOnly` });
        res.end();
      });
      return;
    }
    req.resume();
    switch (url.pathname) {
      case '/':
        send(200, PLAIN);
        return;
      case '/cart':
        send(200, cartPage(cartLabel));
        return;
      case '/control/cart-label':
        cartLabel = url.searchParams.get('name') || null;
        res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
        res.end('ok\n');
        return;
      case '/silent-cookie':
        send(200, SILENT, { 'set-cookie': `selvedge_secret=${SILENT_COOKIE_VALUE}; Path=/; HttpOnly` });
        return;
      case '/api/whoami':
        res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
        res.end(req.headers.authorization === `Bearer ${BEARER_TOKEN}` ? 'signed in' : 'anonymous');
        return;
      case '/login':
        send(200, LOGIN);
        return;
      case '/account': {
        hits.set('/account', (hits.get('/account') || 0) + 1);
        const session = sessions.get(cookieValue(req.headers.cookie, SESSION_COOKIE));
        if (!session) {
          res.writeHead(302, { location: '/login', 'cache-control': 'no-store' });
          res.end();
          return;
        }
        send(200, accountPage(session));
        return;
      }
      case '/control/hits':
        text(`${hits.get(url.searchParams.get('path')) || 0}\n`);
        return;
      case '/control/expire-sessions':
        sessions.clear();
        text('ok\n');
        return;
      case '/echo':
        send(200, ECHO);
        return;
      case '/slow':
        send(200, SLOW);
        return;
      case '/api/price': {
        const timer = setTimeout(() => {
          res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
          res.end(SLOW_PRICE);
        }, SLOW_PRICE_MS);
        res.once('close', () => clearTimeout(timer));
        return;
      }
      case '/controls':
        send(200, CONTROLS);
        return;
      case '/api/forecast':
        if (apiSessions.has(cookieValue(req.headers.cookie, API_COOKIE))) json(200, { days: [{ day: 'mon', high: 21 }, { day: 'tue', high: 19 }] });
        else json(401, { error: 'unauthorized' });
        return;
      case '/api/big':
        text('x'.repeat(BIG_REPLY_CHARS));
        return;
      case '/cookie': {
        const headers = url.searchParams.get('set') === '1' ? { 'set-cookie': 'selvedge_fixture=seen; Path=/' } : {};
        send(200, page('Cookie', `<main><h1>Cookie</h1><p>cookie: ${escapeHtml(req.headers.cookie || 'none')}</p></main>`), headers);
        return;
      }
      default:
        res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
        res.end(`not found: ${url.pathname}\n`);
    }
  });
  server.on('connection', (socket) => {
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
  });
  server.on('clientError', (_err, socket) => socket.destroy());
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(listenPort, '127.0.0.1', resolve);
  });
  const { port } = server.address();
  return {
    port,
    origin: `http://localhost:${port}`,
    events,
    close: () =>
      new Promise((resolve) => {
        server.close(() => resolve());
        for (const s of sockets) s.destroy();
      }),
  };
}

async function serve(infoFile, logDir) {
  const app = await startAppServer();
  const info = { app: { port: app.port, origin: app.origin } };
  let recorder = null;
  if (logDir) {
    recorder = await startServer('U', logDir);
    info.U = { port: recorder.port, origin: recorder.origin, logFile: recorder.logFile };
  }
  let closing = false;
  const stop = async (code) => {
    if (closing) return;
    closing = true;
    await Promise.all([app.close(), recorder ? recorder.close() : null]);
    process.exit(code);
  };
  process.on('SIGTERM', () => stop(0));
  process.on('SIGINT', () => stop(0));
  setTimeout(() => {
    process.stderr.write('app-server.mjs: watchdog: exiting after 15 minutes\n');
    stop(3);
  }, 15 * 60 * 1000);
  writeFileSync(`${infoFile}.tmp`, `${JSON.stringify(info)}\n`);
  renameSync(`${infoFile}.tmp`, infoFile);
}

export const DEFAULT_SAMPLE_PORT = 4173;
const SAMPLE_USAGE = 'usage: selvedge sample-app [--port <N>]   (default port 4173)';

// The `sample` command's port: `--port <N>` / `--port=<N>`, else DEFAULT_SAMPLE_PORT; null when bad.
function samplePort(args) {
  let value = String(DEFAULT_SAMPLE_PORT);
  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (a === '--port') {
      i += 1;
      if (i >= args.length) return null;
      value = args[i];
    } else if (a.startsWith('--port=')) {
      value = a.slice('--port='.length);
    } else {
      return null;
    }
  }
  if (!/^[0-9]+$/.test(value)) return null;
  const port = Number(value);
  return port >= 1 && port <= 65535 ? port : null;
}

// Connect errors that mean "nothing is listening at this address" (refused), or "this machine has
// no such address" (no IPv6 loopback): either way nothing there can take localhost's traffic.
const PORT_FREE_CODES = new Set(['ECONNREFUSED', 'EADDRNOTAVAIL', 'ENETUNREACH', 'EHOSTUNREACH', 'EAFNOSUPPORT']);
const PROBE_TIMEOUT_MS = 1000;

// probeInUse(host, port) → Promise<null | 'in-use' | Error>: connects to host:port once. null when
// the connection is refused (or the address does not exist here); 'in-use' when it is accepted
// (something already serves there); an Error otherwise, including no answer within
// PROBE_TIMEOUT_MS (a loopback port that neither accepts nor refuses is not one to serve on).
// The probe socket is destroyed before this resolves, on every path.
function probeInUse(host, port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port });
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      resolve(result);
    };
    const timer = setTimeout(() => {
      finish(new Error(`no answer from ${host === '::1' ? '[::1]' : host}:${port} within ${PROBE_TIMEOUT_MS} ms`));
    }, PROBE_TIMEOUT_MS);
    socket.once('connect', () => finish('in-use'));
    socket.once('error', (e) => finish(e && PORT_FREE_CODES.has(e.code) ? null : e));
  });
}

async function sample(args) {
  if (args[0] === 'help' || args[0] === '-h' || args[0] === '--help') {
    process.stdout.write(`${SAMPLE_USAGE}\n`);
    return;
  }
  const port = samplePort(args);
  if (port === null) {
    process.stderr.write(`selvedge sample-app: --port needs a port number from 1 to 65535\n${SAMPLE_USAGE}\n`);
    process.exit(2);
  }
  const inUse = () => {
    process.stderr.write(`selvedge sample-app: port ${port} is already in use; stop what is using it, or pick another with --port <N>\n`);
    process.exit(1);
  };
  // The app binds 127.0.0.1 only, but `localhost` can resolve to ::1 first (Node's fetch, Chromium),
  // and a listener on [::1]:N or on the wildcard `::` (Node's default listen(N), vite preview) does
  // not stop a bind on 127.0.0.1:N, yet takes the quick start's traffic. So connect first: before
  // this process listens, an accepted connection can only be another server's. (Something that
  // starts listening between the probe and the listen below is not caught; the listen's own
  // EADDRINUSE still catches a holder of 127.0.0.1:N.)
  for (const host of ['127.0.0.1', '::1']) {
    const probe = await probeInUse(host, port);
    if (probe === 'in-use') inUse();
    if (probe) {
      process.stderr.write(`selvedge sample-app: cannot check port ${port}: ${probe.message || probe}\n`);
      process.exit(1);
    }
  }
  let app;
  try {
    app = await startAppServer({ port });
  } catch (e) {
    if (e && e.code === 'EADDRINUSE') inUse();
    process.stderr.write(`selvedge sample-app: cannot listen on port ${port}: ${e && e.message ? e.message : e}\n`);
    process.exit(1);
  }
  let closing = false;
  const stop = async () => {
    if (closing) return;
    closing = true;
    await app.close();
    process.exit(0);
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
  process.stdout.write(
    `selvedge sample app: serving on ${app.origin} (Ctrl-C to stop)\n`
    + `pages: ${app.origin}/cart, ${app.origin}/echo, ${app.origin}/slow\n`
    + `in your demo repo: selvedge env init --port ${port}\n`,
  );
}

if (process.argv[2] === 'sample') {
  await sample(process.argv.slice(3));
} else if (process.argv[2] === 'serve') {
  if (!process.argv[3]) {
    process.stderr.write('usage: node app-server.mjs serve <info.json> [<log dir>]\n');
    process.exit(2);
  }
  await serve(process.argv[3], process.argv[4]);
}
