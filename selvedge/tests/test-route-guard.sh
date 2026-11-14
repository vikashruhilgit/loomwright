#!/usr/bin/env bash
# test-route-guard.sh — pins selvedge/lib/runner/route-guard.mjs (launch options, the loopback
# env-var refusal, the guarded context, the context.route layer) together with the proxy it
# launches Chromium behind, against REAL Chromium and recording fixture servers
# (tests/fixtures/servers.mjs), driven by tests/fixtures/guard-driver.mjs.
#
# Layer attribution: every block is { reason, origin, host, layer: 'route' | 'proxy' }. A route arm
# asserts layer 'route' AND that the proxy logged nothing for that host; a proxy arm runs with
# openGuardedContext's TEST-ONLY `routeLayer: false`. So a mutation to one layer is never masked by
# the other. Every arm turns red under its row of the brief's pin-mutation table.
#
# Two parts:
#   1. no-browser arms (always run): launch options, the env refusal and call order on a spy
#      chromium, the route layer's decision table, no Playwright import, no string-literal reason.
#   2. real-Chromium arms: Playwright comes from tests/lib/playwright-cache.sh (a pinned install in a
#      selvedge-owned cache — the only network this suite uses). Under CI an install failure is a
#      hard FAIL (playwright_install_failed, exit 1); outside CI it is a SKIP and part 1 decides.
#
# Hermetic otherwise: PLAYWRIGHT_BROWSERS_PATH is exported (by the helper) BEFORE HOME moves to a
# fresh temp dir, every fixture server, proxy and browser is closed by the driver.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LIB="$PLUGIN_DIR/lib"
GUARD="$LIB/runner/route-guard.mjs"
DRIVER="$TESTS_DIR/fixtures/guard-driver.mjs"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }
finish() { echo "test-route-guard: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

command -v node >/dev/null 2>&1 || { echo "  FAIL node is not on PATH (test-route-guard.sh needs it)"; echo "test-route-guard: 0 passed, 1 failed"; exit 1; }

# shellcheck source=lib/playwright-cache.sh
. "$TESTS_DIR/lib/playwright-cache.sh"   # exports PLAYWRIGHT_BROWSERS_PATH while HOME is still real

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-guard.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
REAL_HOME="$HOME"
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/logs-nb" "$TMP/logs-b"
unset PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK

# check <results file> <label> <js expression over R> [<dump expression>] — R is the driver's JSON;
# zero(f) is true when the fixture log f records no connection and no request; events(f) reads it.
check() {
  local file="$1" label="$2" expr="$3" dump="${4:-}" got
  got="$(node -e '
const fs = require("fs");
const R = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const events = (f) => JSON.parse(fs.readFileSync(f, "utf8"));
const zero = (f) => { try { return events(f).length === 0; } catch { return false; } };
let v;
try { v = eval(process.argv[2]); } catch (e) { v = "error: " + e.message; }
if (v === true) { process.stdout.write("true"); }
else { let d = ""; try { d = process.argv[3] ? JSON.stringify(eval(process.argv[3])) : ""; } catch (e) { d = e.message; } process.stdout.write("false " + d.slice(0, 1500)); }
' "$file" "$expr" "$dump" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

# run_driver <mode> <log dir> <out file> — 0 when the driver ran and printed JSON.
run_driver() {
  node "$DRIVER" "$LIB" "$2" "$1" >"$3" 2>"$3.err"; local rc=$?
  if [ "$rc" -ne 0 ] || ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$3" 2>/dev/null; then
    ko "guard-driver.mjs $1 ran (rc=$rc): $(tail -n 5 "$3.err") $(head -c 400 "$3")"
    return 1
  fi
  return 0
}

echo "-- static: injected Playwright, the one parser, no string-literal reason"
n="$(grep -cE "(from|import\() *['\"]playwright" "$GUARD")"
[ "$n" = "0" ] && ok "route-guard.mjs never imports playwright (the caller passes chromium in)" || ko "route-guard.mjs imports playwright ($n hits)"
grep -qF "from '../env-config.mjs'" "$GUARD" && ok "route-guard.mjs takes the origin parser from env-config.mjs" || ko "route-guard.mjs does not import env-config.mjs"
n="$(grep -cE "['\"\`](host_not_allowed|remote_resolves_private|remote_mutation_refused|proxy_loopback_disabled|proxy_unavailable)['\"\`]" "$GUARD")"
[ "$n" = "0" ] && ok "route-guard.mjs names no reason as a string literal (REASONS only)" || ko "route-guard.mjs has $n string-literal reasons"

NB="$TMP/nobrowser.json"
if run_driver nobrowser "$TMP/logs-nb" "$NB"; then
  echo "-- AC16 launch options and the loopback env refusal (no browser)"
  check "$NB" "AC16 buildLaunchOptions is exactly { proxy: { server: 'http://127.0.0.1:<port>' } }" \
    'JSON.stringify(R.ac16_options) === JSON.stringify({ proxy: { server: "http://127.0.0.1:4242" } })' 'R.ac16_options'
  check "$NB" "AC16 the launch options carry no bypass key and no direct:// anywhere" \
    '!JSON.stringify(R.ac16_options).includes("bypass") && !JSON.stringify(R.ac16_options).includes("direct://") && Object.keys(R.ac16_options.proxy).join() === "server"' 'R.ac16_options'
  check "$NB" "AC16 PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK=1 refuses BLOCKED proxy_loopback_disabled before Chromium launches" \
    'const a = R.ac16_env_set; a.refused === true && a.reason === "proxy_loopback_disabled" && a.blocked === true && a.launched === 0' 'R.ac16_env_set'
  check "$NB" "AC16 the variable set to an empty string is refused too (fail closed)" \
    'const a = R.ac16_env_empty; a.refused === true && a.reason === "proxy_loopback_disabled" && a.launched === 0' 'R.ac16_env_empty'

  echo "-- AC19 guarded context: call order on a spy chromium (no browser)"
  check "$NB" "AC19 Chromium is launched with exactly buildLaunchOptions for the guard's own proxy port" \
    'R.ac19_order.calls[0] === "launch:" + JSON.stringify({ proxy: { server: "http://127.0.0.1:" + R.ac19_order.proxyPort } })' 'R.ac19_order'
  check "$NB" "AC19 the context is created with serviceWorkers: 'block'" \
    'R.ac19_order.calls.includes("newContext:" + JSON.stringify({ serviceWorkers: "block" }))' 'R.ac19_order'
  check "$NB" "AC19 context.route('**/*') is installed before the first context.newPage(), and that page is returned" \
    'const c = R.ac19_order.calls; c.indexOf("route:**/*") >= 0 && c.indexOf("newPage") > c.indexOf("route:**/*") && R.ac19_order.samePage === true' 'R.ac19_order'

  echo "-- the route layer's decision table (no browser)"
  check "$NB" "route layer: a listed localhost origin (any path) is allowed" 'R.check_request.listed === "allow"' 'R.check_request'
  check "$NB" "route layer (AC14): localhost:4002 is refused host_not_allowed when only localhost:4001 is listed" \
    'R.check_request.unlisted_port === "host_not_allowed localhost:4002"' 'R.check_request'
  check "$NB" "route layer (AC18): https://shop.example.com/?next=localhost is refused host_not_allowed naming shop.example.com" \
    'R.check_request.next_localhost === "host_not_allowed shop.example.com:443"' 'R.check_request'
  check "$NB" "route layer (AC19): POST, PUT, PATCH and DELETE to a listed remote are refused remote_mutation_refused, GET is allowed" \
    'const c = R.check_request; ["remote_post","remote_put","remote_patch","remote_delete"].every((k) => c[k] === "remote_mutation_refused shop.example.com:443") && c.remote_get === "allow"' 'R.check_request'
  check "$NB" "route layer: allow_remote_mutation: true allows the remote POST; a local POST is always allowed" \
    'R.check_request.remote_post_allowed === "allow" && R.check_request.local_post === "allow"' 'R.check_request'
  check "$NB" "route layer: a listed remote without allow_remote is refused; data: is allowed; ftp: is refused" \
    'R.check_request.remote_without_allow_remote.startsWith("host_not_allowed") && R.check_request.data_url === "allow" && R.check_request.ftp_url.startsWith("host_not_allowed")' 'R.check_request'
  check "$NB" "AC17 ERR_PROXY_CONNECTION_FAILED maps to proxy_unavailable; other net errors map to nothing" \
    'R.failure_reasons.proxy_failed === R.reason_values.proxy_unavailable && R.failure_reasons.other === null' 'R.failure_reasons'
fi

echo "-- the Playwright install rule is bimodal (stub npm; nothing is downloaded)"
STUB="$TMP/stub-bin"; mkdir -p "$STUB"
printf '#!/bin/sh\necho "stub npm: offline" >&2\nexit 1\n' > "$STUB/npm"; chmod +x "$STUB/npm"
out="$(SELVEDGE_TEST_PW_CACHE="$TMP/empty-pw-cache" PATH="$STUB:$PATH" CI=1 bash -c '. "$1"; pw_require_or_skip' _ "$TESTS_DIR/lib/playwright-cache.sh" 2>&1)"; rc=$?
{ [ "$rc" -eq 1 ] && grep -qF 'FAIL playwright_install_failed' <<<"$out"; } \
  && ok "under CI an install failure is a hard FAIL playwright_install_failed (rc 1)" || ko "CI install failure: rc=$rc out='$out'"
out="$(SELVEDGE_TEST_PW_CACHE="$TMP/empty-pw-cache" PATH="$STUB:$PATH" CI= bash -c 'unset CI; . "$1"; pw_require_or_skip' _ "$TESTS_DIR/lib/playwright-cache.sh" 2>&1)"; rc=$?
{ [ "$rc" -eq 2 ] && grep -qF 'SKIP (playwright_install_failed' <<<"$out"; } \
  && ok "outside CI the same failure is a SKIP (rc 2), never a pass" || ko "non-CI install failure: rc=$rc out='$out'"
n="$(grep -cE '^PW_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$TESTS_DIR/lib/playwright-cache.sh")"
[ "$n" = "1" ] && ok "playwright-cache.sh carries exactly one PW_VERSION=<x.y.z> pin line" || ko "PW_VERSION pin lines: $n"

echo "-- real Chromium"
HOME="$REAL_HOME" pw_require_or_skip; pwrc=$?
if [ "$pwrc" -eq 1 ]; then
  ko "playwright_install_failed under CI: no browser arm can run"
  finish
fi
if [ "$pwrc" -eq 2 ]; then
  echo "  (browser arms skipped outside CI; the no-browser arms above decide)"
  finish
fi

B="$TMP/browser.json"
run_driver browser "$TMP/logs-b" "$B" || finish
check "$B" "the browser driver finished every scenario without an error" \
  'Object.values(R).every((s) => s && !s.error) && !R.watchdog' 'Object.fromEntries(Object.entries(R).filter(([, s]) => !s || s.error))'

# Shared predicates (JS): blocks for a host at a layer.
P='const at = (s, layer, reason, host) => s.blocks.filter((b) => b.layer === layer && b.reason === reason && b.host === host);
const proxyFor = (s, host) => s.proxyBlocks.filter((b) => b.host === host);
const U = (s) => "localhost:" + s.ports.U;'

echo "-- AC11 direct navigation to an unlisted port"
check "$B" "AC11 route layer: BLOCKED host_not_allowed naming localhost:<U> at layer route; the proxy logged nothing for it; U records zero connections" \
  "$P"' const s = R.ac11_route; s.nav.ok === false && at(s, "route", "host_not_allowed", U(s)).length === 1 && proxyFor(s, U(s)).length === 0 && zero(s.logs.U)' 'R.ac11_route'
check "$B" "AC11 proxy only (routeLayer: false): BLOCKED host_not_allowed naming localhost:<U> at layer proxy; U records zero connections" \
  "$P"' const s = R.ac11_proxy; s.nav.blocked === "host_not_allowed" && at(s, "proxy", "host_not_allowed", U(s)).length === 1 && s.blocks.every((b) => b.layer === "proxy") && zero(s.logs.U)' 'R.ac11_proxy'

echo "-- AC12 redirect hops (proxy only)"
check "$B" "AC12 listed A → 302 → unlisted U: BLOCKED host_not_allowed naming localhost:<U>; U records zero connections" \
  "$P"' const s = R.ac12_redirect; s.nav.blocked === "host_not_allowed" && at(s, "proxy", "host_not_allowed", U(s)).length === 1 && events(s.logs.A).some((e) => e.path && e.path.startsWith("/redirect")) && zero(s.logs.U)' 'R.ac12_redirect'
check "$B" "AC12 two-hop chain listed A → listed B → unlisted U: BLOCKED naming localhost:<U>; A and B served their hop; U records zero connections" \
  "$P"' const s = R.ac12_chain; s.nav.blocked === "host_not_allowed" && at(s, "proxy", "host_not_allowed", U(s)).length === 1 && !zero(s.logs.A) && events(s.logs.B).some((e) => e.path && e.path.startsWith("/redirect")) && zero(s.logs.U)' 'R.ac12_chain'
check "$B" "AC12 a 307 re-sending a form POST to U: the POST is BLOCKED host_not_allowed naming localhost:<U>; U records zero connections" \
  "$P"' const s = R.ac12_307; s.final.method === "POST" && s.final.blocked === "host_not_allowed" && at(s, "proxy", "host_not_allowed", U(s)).some((b) => b.method === "POST") && events(s.logs.A).some((e) => e.method === "POST" && e.path.startsWith("/r307")) && zero(s.logs.U)' 'R.ac12_307'

echo "-- AC13 ws:// and wss:// to an unlisted origin"
check "$B" "AC13 ws:// and wss:// to localhost:<U> both fail; the proxy refused their CONNECTs; U records zero connections" \
  "$P"' const s = R.ac13_ws; s.first.status === 200 && s.sockets.length === 2 && s.sockets.every((x) => x !== "open") && at(s, "proxy", "host_not_allowed", U(s)).filter((b) => b.method === "CONNECT").length >= 2 && zero(s.logs.U)' 'R.ac13_ws'

echo "-- AC14 same host, unlisted port"
check "$B" "AC14 route layer: fetch localhost:<U> from a localhost:A page is aborted, host_not_allowed at layer route, proxy logged nothing, U records zero" \
  "$P"' const s = R.ac14_route; s.first.status === 200 && s.fetch.startsWith("err:") && at(s, "route", "host_not_allowed", U(s)).length === 1 && proxyFor(s, U(s)).length === 0 && zero(s.logs.U)' 'R.ac14_route'
check "$B" "AC14 proxy only (routeLayer: false): the same fetch is refused host_not_allowed at layer proxy, U records zero" \
  "$P"' const s = R.ac14_proxy; s.first.status === 200 && s.fetch.startsWith("err:") && at(s, "proxy", "host_not_allowed", U(s)).length === 1 && s.blocks.every((b) => b.layer === "proxy") && zero(s.logs.U)' 'R.ac14_proxy'

echo "-- AC17 the proxy dies mid-run"
check "$B" "AC17 a listed page loads, the proxy is killed, then a LISTED navigation fails ERR_PROXY_CONNECTION_FAILED → BLOCKED proxy_unavailable" \
  'const s = R.ac17_kill; s.before.ok === true && s.before.status === 200 && s.after.ok === false && s.after.error.includes("ERR_PROXY_CONNECTION_FAILED") && s.blocks.some((b) => b.reason === "proxy_unavailable" && b.host === "localhost:" + s.ports.A && b.url.endsWith("/again"))' 'R.ac17_kill'
check "$B" "AC17 after the kill nothing goes direct: A served only the first load, the unlisted U records zero connections" \
  'const s = R.ac17_kill; events(s.logs.A).filter((e) => e.event === "request").length === 1 && s.fetchU.startsWith("err:") && zero(s.logs.U)' 'R.ac17_kill'

echo "-- AC18 ?next=localhost is not localhost"
check "$B" "AC18 route layer: https://shop.example.com/?next=localhost is BLOCKED host_not_allowed naming shop.example.com at layer route; the proxy logged nothing" \
  "$P"' const s = R.ac18_route; s.nav.ok === false && at(s, "route", "host_not_allowed", "shop.example.com:443").length === 1 && proxyFor(s, "shop.example.com:443").length === 0 && s.proxyBlocks.length === 0' 'R.ac18_route'

echo "-- AC19 remote mutation, service workers, route before any page"
for method in POST PUT PATCH DELETE; do
  check "$B" "AC19 route layer: a same-origin $method on a listed remote page is aborted remote_mutation_refused at layer route; the proxy never saw it" \
    "const s = R.ac19_mutation_route; s.first.status === 200 && s.$method.startsWith('err:') && s.blocks.some((b) => b.layer === 'route' && b.reason === 'remote_mutation_refused' && b.method === '$method' && b.host === s.remote) && !s.proxyBlocks.some((b) => b.method === '$method') && zero(s.logs.R)" 'R.ac19_mutation_route'
done
check "$B" "AC19 GET on the same remote is not refused by the mutation rule (route continued it; the proxy refused it only as remote_resolves_private)" \
  'const s = R.ac19_mutation_route; !s.blocks.some((b) => b.method === "GET" && b.reason === "remote_mutation_refused") && s.seen.some((x) => x.method === "GET" && x.url.endsWith("/api/get")) && s.proxyBlocks.some((b) => b.method === "GET" && b.reason === "remote_resolves_private") && zero(s.logs.R)' 'R.ac19_mutation_route'
check "$B" "AC19 service workers are blocked: register() never yields a ready worker, /sw.js is never fetched, nothing controls the page" \
  'const s = R.ac19_sw; s.first.status === 200 && s.sw !== "registered:ready" && s.controlled === false && !s.seen.some((x) => x.url.endsWith("/sw.js")) && !events(s.logs.A).some((e) => e.path === "/sw.js")' 'R.ac19_sw'
check "$B" "AC19 the first request of the first page is seen by the route layer (layer route), and a listed page loads" \
  'const s = R.ac19_first; s.nav.status === 200 && s.seen.length >= 1 && s.seen[0].url === s.want && s.seen[0].layer === "route" && s.blocks.length === 0' 'R.ac19_first'

finish
