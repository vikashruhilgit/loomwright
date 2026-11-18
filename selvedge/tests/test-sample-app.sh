#!/usr/bin/env bash
# test-sample-app.sh — pins `selvedge sample-app [--port N]` (bin/selvedge → tests/fixtures/
# app-server.mjs sample): on a given free port it serves /cart (heading "Shop"), /echo ("Hello, ")
# and /api/price ("42") — the literals the README quick start's example criteria rely on — prints
# its origin and the `selvedge env init --port N` line, stops on SIGTERM with no process left, and a
# port already in use exits 1 naming the port.
#
# The server's stdout/stderr go to a temp file, never this test's stdout (sample mode has no
# watchdog, so a server holding the suite's stdout would hang a piped run.sh). An EXIT trap stops
# any server still running (TERM, then KILL). Not pinned here: the 4173 default and the absence of
# the watchdog (a test would have to bind 4173 or wait 15 minutes); both are documented in the
# README and app-server.mjs's header.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

if ! command -v node >/dev/null 2>&1; then
  echo "  SKIP node is not on PATH (sample-app needs Node)"
  echo "test-sample-app: 0 passed, 0 failed (skipped)"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-sample.XXXXXX")" || exit 1
SRV_PID=""; HOLD_PID=""

# alive <pid> — the process exists and is not a zombie.
alive() {
  local st
  kill -0 "$1" 2>/dev/null || return 1
  st="$(ps -o stat= -p "$1" 2>/dev/null)"
  case "$st" in Z*|"") return 1 ;; esac
  return 0
}

# stop_pid <pid> — TERM, wait up to 5 s for it to go, then KILL. Returns 0 when TERM alone stopped it.
stop_pid() {
  local pid="$1" i=0
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null
  while alive "$pid" && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.1; done
  if alive "$pid"; then
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 1
  fi
  wait "$pid" 2>/dev/null
  return 0
}

cleanup() {
  stop_pid "$SRV_PID"
  stop_pid "$HOLD_PID"
  rm -rf "$TMP"
}
trap cleanup EXIT

# A free localhost port (bound then released: another process could take it, but rarely does).
free_port() {
  node -e 'const s = require("net").createServer(); s.listen(0, "127.0.0.1", () => { process.stdout.write(String(s.address().port)); s.close(); });'
}

# fetch <url> — the body (any status) on stdout; exit 1 when the request fails.
fetch_body() {
  node -e 'fetch(process.argv[1]).then((r) => r.text()).then((t) => process.stdout.write(t), () => process.exit(1));' "$1"
}

# --- serves the sample app on the given port -----------------------------------------------------
port="$(free_port)"
[ -n "$port" ] || { ko "setup: no free port"; echo "test-sample-app: $pass passed, $fail failed"; exit 1; }
bash "$CLI" sample-app --port "$port" >"$TMP/sample.log" 2>&1 &
SRV_PID=$!
i=0
while ! grep -qF "serving on" "$TMP/sample.log" 2>/dev/null && alive "$SRV_PID" && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
origin="http://localhost:$port"
if grep -qF "serving on $origin" "$TMP/sample.log"; then
  ok "sample-app --port $port prints its origin ($origin)"
else
  ko "sample-app did not start on $port: $(cat "$TMP/sample.log")"
fi
grep -qF "selvedge env init --port $port" "$TMP/sample.log" \
  && ok "it prints the selvedge env init --port $port line to use" || ko "no env init line: $(cat "$TMP/sample.log")"

# Fetched on 127.0.0.1 (where it binds): a Node whose fetch tries ::1 first for localhost still connects.
ip_origin="http://127.0.0.1:$port"
body="$(fetch_body "$ip_origin/cart")"
grep -qF "<h1>Shop</h1>" <<<"$body" && ok "/cart serves the \"Shop\" heading on port $port" || ko "/cart: '$body'"
body="$(fetch_body "$ip_origin/echo")"
grep -qF "Hello, " <<<"$body" && ok "/echo carries \"Hello, \" (the README's echo criterion)" || ko "/echo: '$body'"
body="$(fetch_body "$ip_origin/api/price")"
[ "$body" = "42" ] && ok "/api/price answers 42 (the README's slow-price criterion)" || ko "/api/price: '$body'"

# --- stop: SIGTERM (what Ctrl-C's SIGINT does too) ends it and leaves no process -----------------
if [ -n "$SRV_PID" ] && alive "$SRV_PID"; then
  kill -TERM "$SRV_PID" 2>/dev/null
  i=0
  while alive "$SRV_PID" && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.1; done
  if alive "$SRV_PID"; then
    ko "the server process $SRV_PID is still running 5 s after SIGTERM (the EXIT trap kills it)"
  else
    wait "$SRV_PID" 2>/dev/null
    ok "the server process is gone after the stop (SIGTERM)"
    SRV_PID=""
  fi
else
  ko "the server process was not running before the stop: $(cat "$TMP/sample.log")"
fi

# --- a port already in use exits 1 naming the port -----------------------------------------------
busy="$(free_port)"
node -e 'const s = require("net").createServer(); s.listen(Number(process.argv[1]), "127.0.0.1", () => process.stdout.write("held\n"));' "$busy" >"$TMP/hold.log" 2>&1 &
HOLD_PID=$!
i=0
while ! grep -qF held "$TMP/hold.log" 2>/dev/null && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.1; done
grep -qF held "$TMP/hold.log" || ko "setup: could not hold port $busy: $(cat "$TMP/hold.log")"
# In the background with a deadline: a regression that serves anyway must not hang this test.
bash "$CLI" sample-app --port "$busy" >"$TMP/busy.log" 2>&1 &
BUSY_PID=$!
i=0
while alive "$BUSY_PID" && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
if alive "$BUSY_PID"; then
  stop_pid "$BUSY_PID"
  ko "sample-app on the busy port $busy kept running: $(cat "$TMP/busy.log")"
else
  wait "$BUSY_PID"; rc=$?
  { [ "$rc" -eq 1 ] && grep -qF "port $busy" "$TMP/busy.log" && [ "$(wc -l <"$TMP/busy.log" | tr -d ' ')" = "1" ]; } \
    && ok "a port already in use exits 1 with one line naming the port ($busy)" || ko "busy port: rc=$rc out='$(cat "$TMP/busy.log")'"
fi
stop_pid "$HOLD_PID"; HOLD_PID=""

# --- a bad --port is a usage error ---------------------------------------------------------------
out="$(bash "$CLI" sample-app --port nope 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "a bad --port exits 2" || ko "bad --port: rc=$rc out='$out'"

echo "test-sample-app: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
