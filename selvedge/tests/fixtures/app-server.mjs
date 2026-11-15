// app-server.mjs — a small web app for selvedge's snapshot and plan tests (test-snapshot.sh,
// test-plan.sh). Not named test-*, so selvedge/tests/run.sh never runs it directly.
//
// Pages (every page is a complete HTML document; scripts are inline, nothing loads from elsewhere):
//   /             a plain page: heading "Plain page", no controls
//   /cart         heading "Shop" and an "Open cart" button; the button opens a role=dialog named
//                 "Cart" holding a "Quantity" spinbutton (a number input, value 1) and a "Total"
//                 value (data-testid "total": 6 × the quantity), plus a "Close" button. The dialog
//                 is `hidden` until the click, so it is absent from the accessibility tree before it.
//   /echo         a "User" text field, a "Reset" button and a paragraph (data-testid "echo") that
//                 reads "Hello, <the field's value>" ("Hello, nobody" when empty) on every input,
//                 and one (data-testid "echo-reversed") reading "Reversed: <the value reversed>"
//                 (how a test sees that the page got a value snapshot prints as {{NAME}});
//                 a "Size" select (S, M, L), a "Gift wrap" checkbox and a paragraph (data-testid
//                 "order") reading "size <S|M|L>, gift wrap <yes|no>, last key <key|none>" (the
//                 last key pressed anywhere on the page)
//   /cookie       a paragraph "cookie: <the request's Cookie header, or none>"; with ?set=1 the
//                 response also sets the cookie selvedge_fixture=seen (path /)
//   anything else 404 text
// Every request is recorded (method, path, Cookie header) in `events`.
//
// Library:  startAppServer() → Promise<{ port, origin, events, close() }> (binds 127.0.0.1, random
//           port; origin is http://localhost:<port>).
// Command:  node app-server.mjs serve <info.json> [<log dir>]
//           starts the app (and, with a log dir, a servers.mjs recording server named U whose JSON
//           log is <log dir>/U.json), writes {app: {port, origin}, U?: {port, origin, logFile}} to
//           <info.json> (atomically: written to a temp name, then renamed), and runs until SIGTERM
//           or SIGINT closes every server. A watchdog exits it after 15 minutes so a test that dies
//           without killing it never leaves it running.
import http from 'node:http';
import { renameSync, writeFileSync } from 'node:fs';
import { startServer } from './servers.mjs';

const UNIT_PRICE = 6;

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function page(title, body) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${escapeHtml(title)}</title></head><body>${body}</body></html>`;
}

const PLAIN = page('Plain', '<main><h1>Plain page</h1><p>Nothing to open here.</p></main>');

const CART = page(
  'Shop',
  `<main><h1>Shop</h1>
<button type="button" id="open">Open cart</button>
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

// startAppServer() → Promise<{ port, origin, events, close() }>
export async function startAppServer() {
  const events = [];
  const sockets = new Set();
  const server = http.createServer((req, res) => {
    events.push({ method: req.method, path: req.url, cookie: req.headers.cookie || null });
    req.resume();
    const url = new URL(req.url, 'http://fixture.invalid');
    const send = (status, html, headers = {}) => {
      res.writeHead(status, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', ...headers });
      res.end(html);
    };
    switch (url.pathname) {
      case '/':
        send(200, PLAIN);
        return;
      case '/cart':
        send(200, CART);
        return;
      case '/echo':
        send(200, ECHO);
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
    server.listen(0, '127.0.0.1', resolve);
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

if (process.argv[2] === 'serve') {
  if (!process.argv[3]) {
    process.stderr.write('usage: node app-server.mjs serve <info.json> [<log dir>]\n');
    process.exit(2);
  }
  await serve(process.argv[3], process.argv[4]);
}
