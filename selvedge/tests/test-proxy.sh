#!/usr/bin/env bash
# test-proxy.sh — pins selvedge/lib/runner/proxy.mjs, the runner-owned forward proxy, with no
# browser: raw HTTP, CONNECT and upgrade requests against recording fixture servers
# (tests/fixtures/servers.mjs), driven by tests/fixtures/proxy-driver.mjs. Every remote lookup is an
# injected COUNTING lookup, so "refused before any lookup" (AC18, AC19) and "the lookup ran once"
# (AC15) are counts, and no arm ever asks the system resolver. Every arm turns red under its row of
# the brief's pin-mutation table.
#
# Hermetic: a fresh temp HOME, fixture servers and proxies on 127.0.0.1 random ports, all closed by
# the driver; no network. Needs node (>= 18); a missing node is a FAIL, never a skip.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LIB="$PLUGIN_DIR/lib"
PROXY="$LIB/runner/proxy.mjs"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

command -v node >/dev/null 2>&1 || { echo "  FAIL node is not on PATH (test-proxy.sh needs it)"; echo "test-proxy: 0 passed, 1 failed"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-proxy.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/logs"

RESULTS="$TMP/results.json"
node "$TESTS_DIR/fixtures/proxy-driver.mjs" "$LIB" "$TMP/logs" >"$RESULTS" 2>"$TMP/driver.err"; drc=$?
if [ "$drc" -ne 0 ] || ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$RESULTS" 2>/dev/null; then
  ko "proxy-driver.mjs ran (rc=$drc): $(tail -n 5 "$TMP/driver.err")"
  echo "test-proxy: $pass passed, $fail failed"
  exit 1
fi

# check <label> <js expression over R> — R is the driver's JSON; zero(f) is true when the fixture
# log file f records no connection and no request. On failure the arm's JSON is printed.
check() {
  local label="$1" expr="$2" dump="${3:-}" got
  got="$(node -e '
const fs = require("fs");
const R = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const zero = (f) => { try { return JSON.parse(fs.readFileSync(f, "utf8")).length === 0; } catch { return false; } };
let v;
try { v = eval(process.argv[2]); } catch (e) { v = "error: " + e.message; }
if (v === true) { process.stdout.write("true"); }
else { let d = ""; try { d = process.argv[3] ? JSON.stringify(eval(process.argv[3])) : ""; } catch (e) { d = e.message; } process.stdout.write("false " + d.slice(0, 1500)); }
' "$RESULTS" "$expr" "$dump" 2>&1)"
  if [ "$got" = "true" ]; then ok "$label"; else ko "$label — $got"; fi
}

echo "-- the one origin parser, no environment"
grep -qF "from '../env-config.mjs'" "$PROXY" && ok "proxy.mjs imports the origin parser from env-config.mjs" || ko "proxy.mjs does not import env-config.mjs"
n="$(grep -c 'process\.env' "$PROXY")"
[ "$n" = "0" ] && ok "proxy.mjs reads no environment variable (lookup/dial are programmatic options only)" || ko "proxy.mjs reads process.env ($n hits)"
n="$(grep -cE "['\"\`](host_not_allowed|remote_resolves_private|remote_mutation_refused|proxy_unavailable)['\"\`]" "$PROXY")"
[ "$n" = "0" ] && ok "proxy.mjs names no reason as a string literal (REASONS only)" || ko "proxy.mjs has $n string-literal reasons"

echo "-- plain HTTP, CONNECT and upgrade by origin"
check "a listed localhost:A GET is forwarded to A (and needs no lookup)" \
  'const a = R.allowed_get; a.status === 200 && a.A.some((e) => e.event === "request" && e.method === "GET" && e.path === "/x?y=1") && a.lookups === 0 && a.blocks.length === 0' 'R.allowed_get'
check "an unlisted port on a listed host: 403 host_not_allowed naming localhost:<U>, U records nothing" \
  'const a = R.unlisted_port; a.status === 403 && a.blockedHeader === "host_not_allowed" && a.blocks.length === 1 && a.blocks[0].reason === "host_not_allowed" && a.blocks[0].host === a.want && a.blocks[0].layer === "proxy" && zero(a.U.log)' 'R.unlisted_port'
check "CONNECT to an unlisted localhost:<U>: 403 host_not_allowed, U records nothing" \
  'const a = R.connect_unlisted_local; a.status === 403 && a.blockedHeader === "host_not_allowed" && a.blocks[0].host === a.want && zero(a.U.log)' 'R.connect_unlisted_local'
check "CONNECT to a listed localhost:A tunnels to A" \
  'const a = R.connect_allowed_local; a.status === 200 && a.tunnel && a.tunnel.status === 200 && a.A.some((e) => e.path === "/through-tunnel")' 'R.connect_allowed_local'
check "an Upgrade: websocket to an unlisted localhost:<U>: 403 host_not_allowed, U records nothing" \
  'const a = R.upgrade_unlisted; a.status === 403 && a.blockedHeader === "host_not_allowed" && a.blocks[0].host === a.want && zero(a.U.log)' 'R.upgrade_unlisted'
check "an Upgrade: websocket to a listed localhost:A reaches A" \
  'R.upgrade_allowed.A.some((e) => e.event === "request" && e.path === "/ws" && e.upgrade === "websocket")' 'R.upgrade_allowed'

echo "-- AC15 a listed remote that resolves private"
for label in v4_loopback v6_loopback v6_link_local one_of_several_private one_of_several_mapped unspecified nat64_loopback sixto4_private; do
  for kind in http connect; do
    check "AC15 $label via $kind: 403 remote_resolves_private, lookup ran once, nothing dialled, R records nothing" \
      "const a = R.ac15['${label}_${kind}']; a.status === 403 && a.blockedHeader === 'remote_resolves_private' && a.blocks.length === 1 && a.blocks[0].reason === 'remote_resolves_private' && a.lookups === 1 && a.dials === 0 && zero(a.R.log)" \
      "R.ac15['${label}_${kind}']"
  done
done
check "AC15 NAT64 (64:ff9b::/96) and 6to4 (2002::/16) embedding a private IPv4 are private; local-use NAT64 and Teredo fail closed; public embeddings stay public" \
  'const e = R.ac15_embedded; ["64:ff9b::7f00:1","64:ff9b::127.0.0.1","64:ff9b::a00:1","2002:7f00:1::1","2002:c0a8:101::","64:ff9b:1::1","2001:0:4136:e378::1"].every((a) => e[a] === true) && ["64:ff9b::5db8:d822","2002:5db8:d822::1","2606:4700::1111"].every((a) => e[a] === false)' 'R.ac15_embedded'
check "AC15 a public resolution is dialled by its validated address, never the name (one lookup per connection)" \
  'const a = R.ac15_validated; a.status === 200 && a.lookupsAfterGet === 1 && a.dialsAfterGet.length === 1 && a.dialsAfterGet[0].address === "93.184.216.34" && a.lookupAll === true && a.lookupHosts.every((h) => h === "remote.selvedge.test") && a.R.some((e) => e.path === "/v")' 'R.ac15_validated'
check "AC15 a CONNECT to the same remote also dials the validated address" \
  'const a = R.ac15_validated; a.connectStatus === 200 && a.tunnel && a.tunnel.status === 200 && a.lookups === 2 && a.dials.length === 2 && a.dials.every((d) => d.address === "93.184.216.34") && a.R.some((e) => e.path === "/tunnelled")' 'R.ac15_validated'

echo "-- AC18 an unlisted remote is refused before any lookup"
check "AC18 CONNECT shop.example.com:443 (only localhost listed): 403 host_not_allowed naming shop.example.com, lookup count 0" \
  'const a = R.ac18_connect; a.status === 403 && a.blockedHeader === "host_not_allowed" && a.blocks[0].host === "shop.example.com:443" && a.lookups === 0' 'R.ac18_connect'
check "AC18 GET http://shop.example.com/?next=localhost: 403 host_not_allowed, lookup count 0" \
  'const a = R.ac18_get; a.status === 403 && a.blockedHeader === "host_not_allowed" && a.blocks[0].host === "shop.example.com:80" && a.lookups === 0' 'R.ac18_get'
check "a remote origin listed without allow_remote is refused host_not_allowed, before any lookup" \
  'const a = R.remote_without_allow_remote; a.status === 403 && a.blockedHeader === "host_not_allowed" && a.lookups === 0 && zero(a.R.log)' 'R.remote_without_allow_remote'

echo "-- AC19 plain-HTTP mutation to a listed remote"
for method in POST PUT PATCH DELETE PROPFIND MKCOL; do
  check "AC19 $method to a listed remote (allow_remote_mutation false): 403 remote_mutation_refused before any lookup, R records nothing" \
    "const a = R.ac19.$method; a.status === 403 && a.blockedHeader === 'remote_mutation_refused' && a.blocks.length === 1 && a.blocks[0].method === '$method' && a.lookups === 0 && zero(a.R.log)" "R.ac19.$method"
done
for method in GET HEAD OPTIONS; do
  check "AC19 $method to the same remote is not refused by the mutation rule (forwarded after one lookup)" \
    "const a = R.ac19.$method; a.status === 200 && a.blockedHeader === null && a.blocks.length === 0 && a.lookups === 1 && !zero(a.R.log)" "R.ac19.$method"
done
check "AC19 an Upgrade sent with POST to a listed remote: 403 remote_mutation_refused before any lookup, R records nothing" \
  'const a = R.ac19_upgrade_post; a.status === 403 && a.blockedHeader === "remote_mutation_refused" && a.lookups === 0 && zero(a.R.log)' 'R.ac19_upgrade_post'
check "AC19 with allow_remote_mutation: true the POST is forwarded" \
  'R.ac19_mutation_allowed.status === 200 && R.ac19_mutation_allowed.R.some((e) => e.method === "POST")' 'R.ac19_mutation_allowed'

echo "-- lifecycle"
check "close() stops the listener (a new connection is refused)" 'R.close_refuses.outcome === "ECONNREFUSED"' 'R.close_refuses'

echo "test-proxy: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
