#!/usr/bin/env bash
# test-token-ledger.sh — offline self-tests for emit-token-ledger.sh
#
# Guarantees:
#   - mktemp sandbox CWD (script resolves .supervisor/logs from $PWD)
#   - NEVER touches the real repo .supervisor/
#   - Every SUT invocation asserts exit 0 (fail-SAFE invariant)
#   - JSONL shape asserted with jq
#
# Cases:
#   1. proxy path — usage absent; transcript bytes recorded
#   2. empty stdin — no-op, no log file
#   3. missing session_id — no-op
#   4. usage-present (synthetic) — proxy:false + real usage fields
#   5. unreadable proxy paths — no-op
#   6. agent_transcript_path preferred over transcript_path
#
# EXIT: 0 on full pass, 1 on any failed assertion.
# Style mirrors test-insights.sh / test-send-telemetry-core.sh.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$SCRIPT_DIR/emit-token-ledger.sh"
FIXDIR="$SCRIPT_DIR/token-ledger-fixtures"

if [ ! -f "$SUT" ]; then
  echo "FATAL  emit-token-ledger.sh not found: $SUT" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL  python3 required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL  jq required to assert JSONL shape" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

ok() { echo "  ok: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
no() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label  expected='$expected' actual='$actual'"; fi
}

# Snapshot real .supervisor/logs — must be untouched.
REAL_LOGS="$REPO_ROOT/.supervisor/logs"
snapshot_real() {
  if [ -d "$REAL_LOGS" ]; then
    find "$REAL_LOGS" -type f 2>/dev/null | sort | cksum
  else
    echo "logs:ABSENT"
  fi
}
REAL_BEFORE="$(snapshot_real)"

SANDBOX="$(mktemp -d 2>/dev/null)" || { echo "FATAL  mktemp failed" >&2; exit 1; }
cleanup() { rm -rf "$SANDBOX" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

run_sut() {
  # Usage: run_sut <payload-file-or--> [stdin via file]
  # Echoes rc on last line as RC=<n>; stdout ignored (SUT is silent).
  local payload="$1"
  local out rc
  if [ "$payload" = "--empty" ]; then
    out="$( cd "$SANDBOX" && bash "$SUT" </dev/null 2>&1 )"
    rc=$?
  else
    out="$( cd "$SANDBOX" && bash "$SUT" < "$payload" 2>&1 )"
    rc=$?
  fi
  printf '%s\n' "$out"
  printf 'RC=%s\n' "$rc"
}

echo "== 1. proxy path (usage absent → transcript_bytes) =="
PROXY_SID="fixture-token-ledger-proxy-001"
TRANSCRIPT="$SANDBOX/agent-transcript.jsonl"
# Deterministic 42-byte body (length asserted below).
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' > "$TRANSCRIPT"   # 42 A's
EXPECTED_BYTES="$(wc -c < "$TRANSCRIPT" | tr -d '[:space:]')"
PAYLOAD1="$SANDBOX/proxy-payload.json"
jq --arg tp "$TRANSCRIPT" \
  '. + {agent_transcript_path: $tp, transcript_path: "/nonexistent/session.jsonl"}' \
  "$FIXDIR/proxy-base.json" > "$PAYLOAD1"

OUT1="$(run_sut "$PAYLOAD1")"
RC1="$(printf '%s\n' "$OUT1" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case1 exit 0" "0" "$RC1"
LOG1="$SANDBOX/.supervisor/logs/${PROXY_SID}.jsonl"
if [ -f "$LOG1" ]; then ok "case1 log file created"; else no "case1 log file missing"; fi
LINES1="$(wc -l < "$LOG1" 2>/dev/null | tr -d '[:space:]')"
assert_eq "case1 exactly one JSONL line" "1" "$LINES1"
LINE1="$(head -1 "$LOG1")"
assert_eq "case1 event=token_ledger" "token_ledger" "$(printf '%s' "$LINE1" | jq -r '.event')"
assert_eq "case1 proxy=true" "true" "$(printf '%s' "$LINE1" | jq -r '.proxy')"
assert_eq "case1 token_proxy_kind" "transcript_bytes" "$(printf '%s' "$LINE1" | jq -r '.token_proxy_kind')"
assert_eq "case1 transcript_bytes" "$EXPECTED_BYTES" "$(printf '%s' "$LINE1" | jq -r '.token_proxy_transcript_bytes')"
assert_eq "case1 session_id" "$PROXY_SID" "$(printf '%s' "$LINE1" | jq -r '.session_id')"
assert_eq "case1 agent_type" "loomwright:code-reviewer" "$(printf '%s' "$LINE1" | jq -r '.agent_type')"
# Must NOT invent token counts or claim proxy is tokens.
if printf '%s' "$LINE1" | jq -e 'has("input_tokens") or has("output_tokens")' >/dev/null 2>&1; then
  no "case1 invented token count fields"
else
  ok "case1 no invented token counts"
fi
if printf '%s' "$LINE1" | jq -e 'has("graph_context_used")' >/dev/null 2>&1; then
  no "case1 emitted reserved graph_context_used"
else
  ok "case1 reserved graph_context_used absent"
fi

echo "== 2. empty stdin → no-op, exit 0 =="
# Fresh sid dir probe: no new file under a known name from empty input.
BEFORE_LS="$(find "$SANDBOX/.supervisor/logs" -type f 2>/dev/null | sort | cksum)"
OUT2="$(run_sut --empty)"
RC2="$(printf '%s\n' "$OUT2" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case2 exit 0" "0" "$RC2"
AFTER_LS="$(find "$SANDBOX/.supervisor/logs" -type f 2>/dev/null | sort | cksum)"
assert_eq "case2 no new log files" "$BEFORE_LS" "$AFTER_LS"

echo "== 3. missing session_id → no-op, exit 0 =="
BEFORE3="$(find "$SANDBOX/.supervisor/logs" -type f 2>/dev/null | sort | cksum)"
OUT3="$(run_sut "$FIXDIR/missing-session.json")"
RC3="$(printf '%s\n' "$OUT3" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case3 exit 0" "0" "$RC3"
AFTER3="$(find "$SANDBOX/.supervisor/logs" -type f 2>/dev/null | sort | cksum)"
assert_eq "case3 no new log files" "$BEFORE3" "$AFTER3"
# Also ensure no file named after empty/nosession appeared.
if ls "$SANDBOX/.supervisor/logs/"*nosession* >/dev/null 2>&1; then
  no "case3 wrote a nosession fallback file"
else
  ok "case3 no nosession fallback file"
fi

echo "== 4. usage-present (synthetic) → proxy:false + real fields =="
USAGE_SID="fixture-token-ledger-usage-001"
OUT4="$(run_sut "$FIXDIR/usage-present.json")"
RC4="$(printf '%s\n' "$OUT4" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case4 exit 0" "0" "$RC4"
LOG4="$SANDBOX/.supervisor/logs/${USAGE_SID}.jsonl"
if [ -f "$LOG4" ]; then ok "case4 log file created"; else no "case4 log file missing"; fi
LINE4="$(tail -1 "$LOG4")"
assert_eq "case4 event" "token_ledger" "$(printf '%s' "$LINE4" | jq -r '.event')"
assert_eq "case4 proxy=false" "false" "$(printf '%s' "$LINE4" | jq -r '.proxy')"
assert_eq "case4 usage.input_tokens" "1200" "$(printf '%s' "$LINE4" | jq -r '.usage.input_tokens')"
assert_eq "case4 usage.output_tokens" "340" "$(printf '%s' "$LINE4" | jq -r '.usage.output_tokens')"
# Proxy fields must be absent on the real-usage path.
if printf '%s' "$LINE4" | jq -e 'has("token_proxy_kind") or has("token_proxy_transcript_bytes")' >/dev/null 2>&1; then
  no "case4 leaked proxy fields onto usage-present path"
else
  ok "case4 no proxy fields on usage-present path"
fi

echo "== 5. unreadable proxy paths → no-op, exit 0 =="
PAYLOAD5="$SANDBOX/unreadable.json"
jq -n '{
  session_id: "fixture-token-ledger-unreadable-001",
  agent_type: "loomwright:qa-executor",
  agent_transcript_path: "/nonexistent/agent.jsonl",
  transcript_path: "/nonexistent/session.jsonl"
}' > "$PAYLOAD5"
BEFORE5="$(find "$SANDBOX/.supervisor/logs" -type f 2>/dev/null | sort | cksum)"
OUT5="$(run_sut "$PAYLOAD5")"
RC5="$(printf '%s\n' "$OUT5" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case5 exit 0" "0" "$RC5"
AFTER5="$(find "$SANDBOX/.supervisor/logs" -type f 2>/dev/null | sort | cksum)"
assert_eq "case5 no new log files" "$BEFORE5" "$AFTER5"
[ ! -f "$SANDBOX/.supervisor/logs/fixture-token-ledger-unreadable-001.jsonl" ] \
  && ok "case5 no log for unreadable sid" \
  || no "case5 unexpectedly wrote unreadable-sid log"

echo "== 6. agent_transcript_path preferred over transcript_path =="
PREF_SID="fixture-token-ledger-pref-001"
AGENT_T="$SANDBOX/pref-agent.jsonl"
SESS_T="$SANDBOX/pref-session.jsonl"
printf 'AAAA' > "$AGENT_T"          # 4 bytes — must win
printf 'BBBBBBBBBB' > "$SESS_T"     # 10 bytes — must lose
PAYLOAD6="$SANDBOX/pref.json"
jq -n --arg a "$AGENT_T" --arg s "$SESS_T" '{
  session_id: "fixture-token-ledger-pref-001",
  agent_type: "loomwright:supervisor-runner",
  agent_transcript_path: $a,
  transcript_path: $s
}' > "$PAYLOAD6"
OUT6="$(run_sut "$PAYLOAD6")"
RC6="$(printf '%s\n' "$OUT6" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case6 exit 0" "0" "$RC6"
LINE6="$(tail -1 "$SANDBOX/.supervisor/logs/${PREF_SID}.jsonl")"
assert_eq "case6 prefers agent transcript bytes (4)" "4" "$(printf '%s' "$LINE6" | jq -r '.token_proxy_transcript_bytes')"

echo "== 7. real repo .supervisor/logs untouched =="
REAL_AFTER="$(snapshot_real)"
assert_eq "real logs snapshot unchanged" "$REAL_BEFORE" "$REAL_AFTER"

echo ""
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
