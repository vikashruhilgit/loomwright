#!/usr/bin/env bash
# test-sample-app.sh — pins `selvedge sample-app [--port N]` (bin/selvedge → tests/fixtures/
# app-server.mjs sample): on a given free port it serves /cart (heading "Shop"), /echo ("Hello, ")
# and /api/price ("42") — the literals the README quick start's example criteria rely on — prints
# its origin and the `selvedge env init --port N` line, stops on SIGTERM with no process left; a
# port already in use on 127.0.0.1, on [::1] only (skipped, with a note, where ::1 cannot be
# bound), or by a listener with no host (Node's default listen(N): the wildcard, which a bind on
# 127.0.0.1 alone sits beside) exits 1 naming the port; a port that neither accepts nor refuses a
# connection (bound, not listening: silent on macOS; skipped, with a note, where it is refused) exits
# 1 with "cannot check port N"; another listen error (EACCES on port 1, where this user may not
# bind it; skipped elsewhere) exits 1 naming the port; `--port=N` and `--help` work.
#
# The server's stdout/stderr go to a temp file, never this test's stdout (sample mode has no
# watchdog, so a server holding the suite's stdout would hang a piped run.sh). An EXIT trap stops
# any server still running (TERM, then KILL); a PID variable it reads is only ever reassigned after
# the process it held is stopped, so no server is orphaned. Not pinned here: the 4173 default and the absence of
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
    ko "the server process $SRV_PID is still running 5 s after SIGTERM (killed now)"
    stop_pid "$SRV_PID"
    SRV_PID=""
  else
    wait "$SRV_PID" 2>/dev/null
    ok "the server process is gone after the stop (SIGTERM)"
    SRV_PID=""
  fi
else
  ko "the server process was not running before the stop: $(cat "$TMP/sample.log")"
fi

# expect_exit1 <port> <label> <literal> — `sample-app --port <port>` exits 1 with one line holding
# <literal> (run in the background with a deadline: a regression that serves anyway must not hang).
expect_exit1() {
  local p="$1" label="$2" want="$3" pid rc j=0
  bash "$CLI" sample-app --port "$p" >"$TMP/exit1.log" 2>&1 &
  pid=$!
  while alive "$pid" && [ "$j" -lt 100 ]; do j=$((j + 1)); sleep 0.1; done
  if alive "$pid"; then
    stop_pid "$pid"
    ko "$label: sample-app on port $p kept running: $(cat "$TMP/exit1.log")"
    return
  fi
  wait "$pid"; rc=$?
  { [ "$rc" -eq 1 ] && grep -qF "$want" "$TMP/exit1.log" && [ "$(wc -l <"$TMP/exit1.log" | tr -d ' ')" = "1" ]; } \
    && ok "$label: exits 1 with one line naming the port ($p)" || ko "$label: rc=$rc out='$(cat "$TMP/exit1.log")'"
}

# hold <host> <port> — hold host:port in the background (HOLD_PID); prints "held" or the error code.
# An empty <host> listens with no host at all (Node's default: the wildcard, `::` dual-stack where
# IPv6 exists). Any earlier holder is stopped first, so HOLD_PID never loses a live process.
hold() {
  stop_pid "$HOLD_PID"; HOLD_PID=""
  : >"$TMP/hold.log"
  node -e 'const s = require("net").createServer(); s.on("error", (e) => { process.stdout.write(`${e.code}\n`); process.exit(1); }); const ok = () => process.stdout.write("held\n"); if (process.argv[1]) s.listen(Number(process.argv[2]), process.argv[1], ok); else s.listen(Number(process.argv[2]), ok);' "$1" "$2" >"$TMP/hold.log" 2>&1 &
  HOLD_PID=$!
  local j=0
  while ! grep -q . "$TMP/hold.log" 2>/dev/null && alive "$HOLD_PID" && [ "$j" -lt 50 ]; do j=$((j + 1)); sleep 0.1; done
}

# --- a port already in use exits 1 naming the port: on 127.0.0.1 ---------------------------------
busy="$(free_port)"
hold 127.0.0.1 "$busy"
if grep -qF held "$TMP/hold.log"; then
  expect_exit1 "$busy" "a port already in use on 127.0.0.1" "port $busy is already in use"
else
  ko "setup: could not hold 127.0.0.1:$busy: $(cat "$TMP/hold.log")"
fi
stop_pid "$HOLD_PID"; HOLD_PID=""

# --- ... and on [::1] (localhost can resolve there first, so that server would get the traffic) ---
busy="$(free_port)"
hold ::1 "$busy"
if grep -qF held "$TMP/hold.log"; then
  expect_exit1 "$busy" "a port already in use on [::1] only" "port $busy is already in use"
else
  echo "  note: [::1]:$busy cannot be bound here ($(cat "$TMP/hold.log")); the IPv6 in-use case is skipped"
fi
stop_pid "$HOLD_PID"; HOLD_PID=""

# --- ... and by a listener with no host (the wildcard: a bind on 127.0.0.1 alone would succeed
# beside it, and localhost traffic would reach that listener instead) ------------------------------
busy="$(free_port)"
hold "" "$busy"
if grep -qF held "$TMP/hold.log"; then
  expect_exit1 "$busy" "a port held by a listener with no host (wildcard)" "port $busy is already in use"
else
  ko "setup: could not hold the wildcard port $busy: $(cat "$TMP/hold.log")"
fi
stop_pid "$HOLD_PID"; HOLD_PID=""

# --- a port that neither accepts nor refuses a connection exits 1 naming the port -----------------
# The holder binds 127.0.0.1:N without listening (python3: Node cannot bind a TCP socket without
# listening). On macOS a connect there gets no answer, so the probe's 1 s timeout fires: "cannot
# check port N". On Linux the connect is refused instead, so that case is skipped with a note (it
# would only reach the listen's own EADDRINUSE). Which one this machine does is read first with a
# separate connect (2 s deadline), never from sample-app's output. The holder sleeps at most 120 s,
# and the EXIT trap stops it.
if command -v python3 >/dev/null 2>&1; then
  busy="$(free_port)"
  stop_pid "$HOLD_PID"; HOLD_PID=""
  : >"$TMP/hold.log"
  python3 -c 'import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind(("127.0.0.1", int(sys.argv[1])))
except OSError as e:
    print("bind failed: %s" % e, flush=True); sys.exit(1)
print("held", flush=True)
time.sleep(120)' "$busy" >"$TMP/hold.log" 2>&1 &
  HOLD_PID=$!
  j=0
  while ! grep -q . "$TMP/hold.log" 2>/dev/null && alive "$HOLD_PID" && [ "$j" -lt 50 ]; do j=$((j + 1)); sleep 0.1; done
  if grep -qF held "$TMP/hold.log"; then
    answer="$(node -e 'const c = require("net").connect({ host: "127.0.0.1", port: Number(process.argv[1]) }); const done = (s) => { process.stdout.write(s); c.destroy(); process.exit(0); }; setTimeout(() => done("none"), 2000); c.once("connect", () => done("accepted")); c.once("error", (e) => done(e.code || "error"));' "$busy")"
    if [ "$answer" = "none" ]; then
      expect_exit1 "$busy" "a port that gives no answer (bound, not listening)" "cannot check port $busy: no answer from 127.0.0.1:$busy within 1000 ms"
    else
      echo "  note: a connect to a bound-but-not-listening 127.0.0.1:$busy gets '$answer' here, not silence; the no-answer (probe timeout) case is skipped"
    fi
  else
    ko "setup: could not bind 127.0.0.1:$busy without listening: $(cat "$TMP/hold.log")"
  fi
  stop_pid "$HOLD_PID"; HOLD_PID=""
else
  echo "  note: python3 is not on PATH; the no-answer (probe timeout) case is skipped"
fi

# --- a listen error other than in-use exits 1 naming the port (port 1: EACCES where unprivileged) --
if node -e 'const s = require("net").createServer(); s.on("error", (e) => process.exit(e.code === "EACCES" ? 0 : 1)); s.listen(1, "127.0.0.1", () => s.close(() => process.exit(1)));' 2>/dev/null; then
  expect_exit1 1 "a port this user may not bind (EACCES)" "cannot listen on port 1"
else
  echo "  note: port 1 is bindable here (or not EACCES); the other-listen-error case is skipped"
fi

# --- the --port=N form works too, and --help prints the usage -------------------------------------
port="$(free_port)"
stop_pid "$SRV_PID"; SRV_PID=""
bash "$CLI" sample-app "--port=$port" >"$TMP/eq.log" 2>&1 &
SRV_PID=$!
i=0
while ! grep -qF "serving on" "$TMP/eq.log" 2>/dev/null && alive "$SRV_PID" && [ "$i" -lt 100 ]; do i=$((i + 1)); sleep 0.1; done
grep -qF "serving on http://localhost:$port" "$TMP/eq.log" \
  && ok "sample-app --port=$port serves on that port" || ko "--port=N: $(cat "$TMP/eq.log")"
stop_pid "$SRV_PID" && ok "the --port=N server stops on SIGTERM" || ko "the --port=N server needed SIGKILL"
SRV_PID=""
out="$(bash "$CLI" sample-app --help 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && grep -qF "usage: selvedge sample-app [--port <N>]" <<<"$out"; } \
  && ok "sample-app --help prints the usage, exit 0" || ko "sample-app --help: rc=$rc out='$out'"

# --- a bad --port is a usage error ---------------------------------------------------------------
out="$(bash "$CLI" sample-app --port nope 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "a bad --port exits 2" || ko "bad --port: rc=$rc out='$out'"

echo "test-sample-app: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
