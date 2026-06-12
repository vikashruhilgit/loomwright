#!/usr/bin/env bash
# test-session-probe.sh — self-tests for the observability_probe in
# session-resume.sh (ST3). Static only: NO Docker, NO network.
#
# Technique:
#   - HOME is a temp fixture (settings.json written per-case).
#   - curl is a PATH shim that logs its argv and reads a mode file
#     (healthy → exit 0, down → exit 7). docker is also shimmed to PROVE the
#     probe never invokes it.
#   - notify-desktop.sh is stubbed by invoking session-resume.sh through a
#     SYMLINK in a temp dir that also contains the stub — the probe resolves
#     siblings via `dirname "$0"`, so the symlinked invocation finds the stub
#     while still executing the REAL script body.
#
# Covers the probe's 4 states plus invariants:
#   1. unconfigured            → no-op, zero output delta (baseline)
#   1b. explicit-off ("0"/"false") → treated as unconfigured (byte-identical
#      to baseline, no probe)
#   2. configured + healthy    → silent (byte-identical to baseline)
#   3. configured + down       → warning + marker + notify-desktop called
#   4. configured + down + fresh marker → fully suppressed (byte-identical
#      to baseline, no notification)
#   5. invariants: silent on startup source; docker never invoked; exit 0.
#
# Exit 0 = all pass, 1 = any failure. Conventions match test-insights.sh.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL="$HERE/session-resume.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH (required by session-resume.sh)"; exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- Shim dir: symlink the REAL script + stub notify-desktop.sh beside it ---
SHIM="$TMP/shim"
mkdir -p "$SHIM"
ln -s "$REAL" "$SHIM/session-resume.sh"
cat > "$SHIM/notify-desktop.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
[ -n "${NOTIFY_LOG_FILE:-}" ] && echo "notified" >> "$NOTIFY_LOG_FILE"
exit 0
EOF
chmod +x "$SHIM/notify-desktop.sh"

# ---- PATH shims: curl (mode-controlled) + docker (must NEVER be called) -----
BIN="$TMP/bin"
mkdir -p "$BIN"
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
[ -n "${CURL_LOG_FILE:-}" ] && echo "curl $*" >> "$CURL_LOG_FILE"
mode="$(cat "${CURL_MODE_FILE:-/nonexistent}" 2>/dev/null || echo down)"
[ "$mode" = "healthy" ] && exit 0
exit 7
EOF
chmod +x "$BIN/curl"
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
[ -n "${DOCKER_LOG_FILE:-}" ] && echo "docker $*" >> "$DOCKER_LOG_FILE"
exit 1
EOF
chmod +x "$BIN/docker"
export PATH="$BIN:$PATH"

export CURL_LOG_FILE="$TMP/curl.log"
export CURL_MODE_FILE="$TMP/curl.mode"
export NOTIFY_LOG_FILE="$TMP/notify.log"
export DOCKER_LOG_FILE="$TMP/docker.log"

# ---- HOME fixture ------------------------------------------------------------
FAKEHOME="$TMP/home"
mkdir -p "$FAKEHOME/.claude"
export HOME="$FAKEHOME"
SETTINGS="$FAKEHOME/.claude/settings.json"
MARKER="$FAKEHOME/.claude/ai-agent-manager/observability/.last-warned"

configure() {
  printf '%s' '{"env":{"CLAUDE_CODE_ENABLE_TELEMETRY":"1","OTEL_EXPORTER_OTLP_ENDPOINT":"http://localhost:4318"}}' > "$SETTINGS"
}
configure_off() { # $1 = explicit-off value ("0" or "false")
  printf '{"env":{"CLAUDE_CODE_ENABLE_TELEMETRY":"%s","OTEL_EXPORTER_OTLP_ENDPOINT":"http://localhost:4318"}}' "$1" > "$SETTINGS"
}
unconfigure() { rm -f "$SETTINGS"; }

# ---- Project fixture (deterministic .supervisor so output is comparable) ----
PROJ="$TMP/proj"
mkdir -p "$PROJ/.supervisor"
printf 'phase: test\nstatus: idle\n' > "$PROJ/.supervisor/state.md"

run_hook() { # $1 = source value; stdout = hook output; rc preserved
  ( cd "$PROJ" && printf '{"source":"%s"}' "$1" | bash "$SHIM/session-resume.sh" )
}

reset_logs() { rm -f "$CURL_LOG_FILE" "$NOTIFY_LOG_FILE" "$DOCKER_LOG_FILE"; }

echo "== 1. unconfigured → no-op, zero output delta (baseline) =="
unconfigure; rm -f "$MARKER"; reset_logs
BASELINE="$(run_hook resume)"; rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || no "rc=$rc"
[ -n "$BASELINE" ] && printf '%s' "$BASELINE" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
  && ok "normal context envelope still emitted" || no "context envelope missing/invalid"
printf '%s' "$BASELINE" | grep -qi "observability" && no "probe text leaked into unconfigured output" || ok "no probe text in output"
[ ! -f "$CURL_LOG_FILE" ] && ok "curl never invoked when unconfigured" || no "curl was invoked when unconfigured"
[ ! -f "$MARKER" ] && ok "no marker written" || no "marker written when unconfigured"

echo "== 1b. explicit-off telemetry → treated as unconfigured (baseline) =="
for offval in 0 false; do
  configure_off "$offval"; rm -f "$MARKER"; reset_logs
  echo "down" > "$CURL_MODE_FILE"   # stack IS down — but explicit-off must gate first
  OUT1B="$(run_hook resume)"; rc=$?
  [ "$rc" -eq 0 ] && ok "exits 0 (CLAUDE_CODE_ENABLE_TELEMETRY=$offval)" || no "rc=$rc (offval=$offval)"
  [ "$OUT1B" = "$BASELINE" ] && ok "explicit-off ($offval) output byte-identical to baseline" || no "explicit-off ($offval) output differs from baseline"
  [ ! -f "$CURL_LOG_FILE" ] && ok "curl never invoked when explicitly off ($offval)" || no "curl invoked despite explicit-off ($offval)"
  [ ! -f "$MARKER" ] && ok "no marker when explicitly off ($offval)" || no "marker written despite explicit-off ($offval)"
done

echo "== 2. configured + healthy → silent (byte-identical to baseline) =="
configure; rm -f "$MARKER"; reset_logs
echo "healthy" > "$CURL_MODE_FILE"
OUT2="$(run_hook resume)"; rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || no "rc=$rc"
[ "$OUT2" = "$BASELINE" ] && ok "output byte-identical to unconfigured baseline" || no "healthy output differs from baseline"
grep -q "localhost:4318" "$CURL_LOG_FILE" 2>/dev/null && ok "curl probed the derived endpoint URL" || no "curl not invoked / wrong URL"
grep -q -- "--max-time 1" "$CURL_LOG_FILE" 2>/dev/null && ok "curl bounded with --max-time 1" || no "--max-time 1 missing from curl argv"
[ ! -f "$MARKER" ] && ok "no marker when healthy" || no "marker written when healthy"
[ ! -f "$NOTIFY_LOG_FILE" ] && ok "notify-desktop not called when healthy" || no "notify-desktop called when healthy"

echo "== 3. configured + down → warning + marker + notification =="
configure; rm -f "$MARKER"; reset_logs
echo "down" > "$CURL_MODE_FILE"
OUT3="$(run_hook resume)"; rc=$?
[ "$rc" -eq 0 ] && ok "exits 0 even when stack is down" || no "rc=$rc"
printf '%s' "$OUT3" | grep -qF "Observability stack unreachable" && ok "warning block emitted" || no "warning block missing"
printf '%s' "$OUT3" | grep -qF "docker compose -f ~/.claude/ai-agent-manager/observability/docker-compose.yml up -d" \
  && ok "exact restart command present" || no "restart command missing/garbled"
printf '%s' "$OUT3" | grep -qF "/setup observability" && ok "/setup observability pointer present" || no "/setup observability pointer missing"
printf '%s' "$OUT3" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 && ok "warning rides inside the context envelope" || no "down-case output is not a valid envelope"
[ -f "$MARKER" ] && ok "marker .last-warned written" || no "marker not written"
grep -q "notified" "$NOTIFY_LOG_FILE" 2>/dev/null && ok "notify-desktop stub called" || no "notify-desktop stub NOT called"

echo "== 4. configured + down + fresh marker → suppressed =="
# marker from case 3 is seconds old → fresh. Keep it; clear the call logs.
configure; reset_logs
echo "down" > "$CURL_MODE_FILE"
OUT4="$(run_hook resume)"; rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || no "rc=$rc"
printf '%s' "$OUT4" | grep -qF "Observability stack unreachable" && no "warning NOT suppressed despite fresh marker" || ok "warning suppressed by fresh (<24h) marker"
[ "$OUT4" = "$BASELINE" ] && ok "suppressed output byte-identical to baseline" || no "suppressed output differs from baseline"
[ ! -f "$NOTIFY_LOG_FILE" ] && ok "notification also suppressed" || no "notify-desktop fired despite fresh marker"

echo "== 5. invariants =="
# silent-on-startup preserved (probe must not run on startup source)
configure; rm -f "$MARKER"; reset_logs
echo "down" > "$CURL_MODE_FILE"
OUT5="$(run_hook startup)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$OUT5" ] && ok "startup source stays fully silent" || no "startup source produced output (rc=$rc)"
[ ! -f "$CURL_LOG_FILE" ] && ok "no probe on startup source" || no "curl invoked on startup source"
# docker must NEVER be invoked by any case above
[ ! -f "$DOCKER_LOG_FILE" ] && ok "docker never invoked by the probe" || no "probe invoked docker"
# stale (>24h) marker re-warns: backdate the marker, expect the warning again
configure; reset_logs
mkdir -p "$(dirname "$MARKER")"
: > "$MARKER"
touch -t 202601010000 "$MARKER" 2>/dev/null || touch -d '2 days ago' "$MARKER" 2>/dev/null
echo "down" > "$CURL_MODE_FILE"
OUT5B="$(run_hook resume)"
printf '%s' "$OUT5B" | grep -qF "Observability stack unreachable" && ok "stale (>24h) marker re-warns" || no "stale marker did not re-warn"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
