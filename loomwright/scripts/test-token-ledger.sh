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
#   7. real repo .supervisor/logs untouched
#   8. active state.md session_id wins over CC uuid (+ cc_session_id retained)
#   9. completed state.md is ignored (stale) → falls back to CC uuid
#  10. ledger-only file under plugin sid (no session_end) is written to join path
#  11. top-level usage keys (no nested usage object) → proxy:false, fields copied
#  12. unrelated dict field with a usage sub-object stays proxy:true (scoped scan)
#  13. all-zero usage falls back to proxy; any non-zero field stays real usage
#  14. orientation_source: valid LOOMWRIGHT_ORIENTATION_SOURCE value emitted;
#      unset ⇒ field absent; invalid value ⇒ field absent (fail-safe omission)
#  15. shared_prefix: LOOMWRIGHT_SHARED_PREFIX=1 ⇒ shared_prefix:true emitted;
#      unset ⇒ field absent; any other value ⇒ field absent (fail-safe omission)

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
  # LOOMWRIGHT_ORIENTATION_SOURCE and LOOMWRIGHT_SHARED_PREFIX are scrubbed via
  # `env -u` so a dev-environment export can never flip the field-absent
  # assertions (cases 14b/15b and all pre-14 cases); case 14 sets the
  # orientation var explicitly via run_sut_env, case 15 the prefix var via
  # run_sut_sp.
  local payload="$1"
  local out rc
  if [ "$payload" = "--empty" ]; then
    out="$( cd "$SANDBOX" && env -u LOOMWRIGHT_ORIENTATION_SOURCE -u LOOMWRIGHT_SHARED_PREFIX bash "$SUT" </dev/null 2>&1 )"
    rc=$?
  else
    out="$( cd "$SANDBOX" && env -u LOOMWRIGHT_ORIENTATION_SOURCE -u LOOMWRIGHT_SHARED_PREFIX bash "$SUT" < "$payload" 2>&1 )"
    rc=$?
  fi
  printf '%s\n' "$out"
  printf 'RC=%s\n' "$rc"
}

run_sut_env() {
  # Usage: run_sut_env <LOOMWRIGHT_ORIENTATION_SOURCE-value> <payload-file>
  # Same contract as run_sut, with the orientation env var set explicitly
  # (the shared-prefix var stays scrubbed).
  local osrc="$1" payload="$2"
  local out rc
  out="$( cd "$SANDBOX" && env -u LOOMWRIGHT_SHARED_PREFIX LOOMWRIGHT_ORIENTATION_SOURCE="$osrc" bash "$SUT" < "$payload" 2>&1 )"
  rc=$?
  printf '%s\n' "$out"
  printf 'RC=%s\n' "$rc"
}

run_sut_sp() {
  # Usage: run_sut_sp <LOOMWRIGHT_SHARED_PREFIX-value> <payload-file>
  # Same contract as run_sut, with the shared-prefix env var set explicitly
  # (the orientation var stays scrubbed).
  local spv="$1" payload="$2"
  local out rc
  out="$( cd "$SANDBOX" && env -u LOOMWRIGHT_ORIENTATION_SOURCE LOOMWRIGHT_SHARED_PREFIX="$spv" bash "$SUT" < "$payload" 2>&1 )"
  rc=$?
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
assert_eq "case1 cc_session_id retained" "$PROXY_SID" "$(printf '%s' "$LINE1" | jq -r '.cc_session_id')"
assert_eq "case1 agent_type" "loomwright:code-reviewer" "$(printf '%s' "$LINE1" | jq -r '.agent_type')"
# ts must be ISO or omitted — never the literal "unknown"
TS1="$(printf '%s' "$LINE1" | jq -r '.ts // empty')"
case "$TS1" in
  ""|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ok "case1 ts iso-or-absent" ;;
  *) no "case1 ts invalid: $TS1" ;;
esac
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

echo "== 8. active state.md session_id wins over CC uuid =="
PLUGIN_SID="supervisor-fixture-active-001"
CC_UUID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
mkdir -p "$SANDBOX/.supervisor"
cat > "$SANDBOX/.supervisor/state.md" <<EOF
## Session
- session_id: $PLUGIN_SID
- status: running
- phase: EXECUTE
- branch: feature/token-ledger
EOF
TRANSCRIPT8="$SANDBOX/state-join-transcript.jsonl"
printf 'CCCCCCCC' > "$TRANSCRIPT8"   # 8 bytes
PAYLOAD8="$SANDBOX/state-join.json"
jq -n --arg tp "$TRANSCRIPT8" --arg cc "$CC_UUID" '{
  session_id: $cc,
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD8"
OUT8="$(run_sut "$PAYLOAD8")"
RC8="$(printf '%s\n' "$OUT8" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case8 exit 0" "0" "$RC8"
# Must write under the PLUGIN sid, not the CC uuid.
if [ -f "$SANDBOX/.supervisor/logs/${PLUGIN_SID}.jsonl" ]; then
  ok "case8 wrote plugin-sid log (join path)"
else
  no "case8 missing plugin-sid log"
fi
if [ -f "$SANDBOX/.supervisor/logs/${CC_UUID}.jsonl" ]; then
  no "case8 incorrectly wrote CC-uuid log"
else
  ok "case8 no CC-uuid log file"
fi
LINE8="$(tail -1 "$SANDBOX/.supervisor/logs/${PLUGIN_SID}.jsonl")"
assert_eq "case8 session_id=plugin" "$PLUGIN_SID" "$(printf '%s' "$LINE8" | jq -r '.session_id')"
assert_eq "case8 cc_session_id=uuid" "$CC_UUID" "$(printf '%s' "$LINE8" | jq -r '.cc_session_id')"
assert_eq "case8 proxy bytes" "8" "$(printf '%s' "$LINE8" | jq -r '.token_proxy_transcript_bytes')"

echo "== 9. completed state.md is ignored (stale) → CC uuid fallback =="
# Overwrite state.md as completed — must NOT join to that finished run.
cat > "$SANDBOX/.supervisor/state.md" <<EOF
## Session
- session_id: supervisor-fixture-stale-completed
- status: completed
- phase: FINALIZE
- branch: feature/old
EOF
STALE_CC="bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
TRANSCRIPT9="$SANDBOX/stale-transcript.jsonl"
printf 'DDDDDD' > "$TRANSCRIPT9"   # 6 bytes
PAYLOAD9="$SANDBOX/stale.json"
jq -n --arg tp "$TRANSCRIPT9" --arg cc "$STALE_CC" '{
  session_id: $cc,
  agent_type: "loomwright:qa-executor",
  agent_transcript_path: $tp
}' > "$PAYLOAD9"
OUT9="$(run_sut "$PAYLOAD9")"
RC9="$(printf '%s\n' "$OUT9" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case9 exit 0" "0" "$RC9"
if [ -f "$SANDBOX/.supervisor/logs/${STALE_CC}.jsonl" ]; then
  ok "case9 wrote CC-uuid log (stale state ignored)"
else
  no "case9 missing CC-uuid fallback log"
fi
if [ -f "$SANDBOX/.supervisor/logs/supervisor-fixture-stale-completed.jsonl" ]; then
  no "case9 polluted completed session log"
else
  ok "case9 did not write to completed session log"
fi
LINE9="$(tail -1 "$SANDBOX/.supervisor/logs/${STALE_CC}.jsonl")"
assert_eq "case9 session_id=cc" "$STALE_CC" "$(printf '%s' "$LINE9" | jq -r '.session_id')"
assert_eq "case9 cc_session_id=cc" "$STALE_CC" "$(printf '%s' "$LINE9" | jq -r '.cc_session_id')"

echo "== 10. ledger-only file under plugin sid (join path ready for session_end) =="
# Re-activate state.md and confirm a ledger-only JSONL (no session_end) lands
# on the plugin sid path — the file job 04 / insights will later join against.
rm -f "$SANDBOX/.supervisor/logs/${PLUGIN_SID}.jsonl"
cat > "$SANDBOX/.supervisor/state.md" <<EOF
## Session
- session_id: $PLUGIN_SID
- status: running
- phase: EXECUTE
- branch: feature/token-ledger
EOF
TRANSCRIPT10="$SANDBOX/ledger-only.jsonl"
printf 'EEEEEEEEEE' > "$TRANSCRIPT10"   # 10 bytes
PAYLOAD10="$SANDBOX/ledger-only-payload.json"
jq -n --arg tp "$TRANSCRIPT10" --arg cc "cccccccc-dddd-eeee-ffff-000000000000" '{
  session_id: $cc,
  agent_type: "loomwright:supervisor-runner",
  agent_transcript_path: $tp
}' > "$PAYLOAD10"
OUT10="$(run_sut "$PAYLOAD10")"
RC10="$(printf '%s\n' "$OUT10" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case10 exit 0" "0" "$RC10"
LOG10="$SANDBOX/.supervisor/logs/${PLUGIN_SID}.jsonl"
if [ -f "$LOG10" ]; then ok "case10 ledger-only plugin-sid file exists"; else no "case10 ledger-only file missing"; fi
# Confirm the file has token_ledger and NO session_end (ledger-only).
EVENTS10="$(jq -r '.event' "$LOG10" 2>/dev/null | sort -u | tr '\n' ',')"
assert_eq "case10 only token_ledger event" "token_ledger," "$EVENTS10"
if jq -e 'select(.event=="session_end")' "$LOG10" >/dev/null 2>&1; then
  no "case10 unexpectedly contains session_end"
else
  ok "case10 ledger-only (no session_end) — join path ready"
fi

echo "== 11. top-level usage keys (no nested usage object) → proxy:false, fields copied =="
# Deactivate the sandbox state.md so the CC uuid join path is exercised.
rm -f "$SANDBOX/.supervisor/state.md" 2>/dev/null || true
USAGE_TOP_SID="fixture-token-ledger-usage-top-001"
OUT11="$(run_sut "$FIXDIR/usage-top-level.json")"
RC11="$(printf '%s\n' "$OUT11" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case11 exit 0" "0" "$RC11"
LOG11="$SANDBOX/.supervisor/logs/${USAGE_TOP_SID}.jsonl"
if [ -f "$LOG11" ]; then ok "case11 log file created"; else no "case11 log file missing"; fi
LINE11="$(tail -1 "$LOG11" 2>/dev/null)"
assert_eq "case11 event" "token_ledger" "$(printf '%s' "$LINE11" | jq -r '.event')"
assert_eq "case11 proxy=false" "false" "$(printf '%s' "$LINE11" | jq -r '.proxy')"
assert_eq "case11 top-level input_tokens copied" "900" "$(printf '%s' "$LINE11" | jq -r '.input_tokens')"
assert_eq "case11 top-level output_tokens copied" "210" "$(printf '%s' "$LINE11" | jq -r '.output_tokens')"
# Numeric-zero must be preserved, not dropped (cache_read_input_tokens: 0).
assert_eq "case11 zero cache_read preserved" "0" "$(printf '%s' "$LINE11" | jq -r '.cache_read_input_tokens')"
# No nested usage object and no proxy fields on this path.
if printf '%s' "$LINE11" | jq -e 'has("usage") or has("token_proxy_kind") or has("token_proxy_transcript_bytes")' >/dev/null 2>&1; then
  no "case11 leaked usage object or proxy fields onto top-level-usage path"
else
  ok "case11 no usage object / proxy fields on top-level-usage path"
fi

echo "== 12. unrelated dict field with usage sub-object does NOT flip to real-usage =="
TRANSCRIPT12="$SANDBOX/agent-transcript-12.jsonl"
printf 'FFFFFFFFFFFF' > "$TRANSCRIPT12"   # 12 bytes
PAYLOAD12="$SANDBOX/unrelated-usage-payload.json"
jq -n --arg tp "$TRANSCRIPT12" '{
  session_id: "fixture-token-ledger-unrelated-001",
  agent_type: "loomwright:qa-executor",
  agent_transcript_path: $tp,
  some_random_field: { usage: { widgets: 7 } }
}' > "$PAYLOAD12"
OUT12="$(run_sut "$PAYLOAD12")"
RC12="$(printf '%s\n' "$OUT12" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case12 exit 0" "0" "$RC12"
LOG12="$SANDBOX/.supervisor/logs/fixture-token-ledger-unrelated-001.jsonl"
LINE12="$(tail -1 "$LOG12" 2>/dev/null)"
assert_eq "case12 stays proxy:true despite unrelated usage sub-object" "true" "$(printf '%s' "$LINE12" | jq -r '.proxy')"
assert_eq "case12 transcript bytes recorded" "12" "$(printf '%s' "$LINE12" | jq -r '.token_proxy_transcript_bytes')"

echo "== 13. all-zero usage payload falls back to transcript-byte proxy =="
TRANSCRIPT13="$SANDBOX/agent-transcript-13.jsonl"
printf 'GGGGGGGG' > "$TRANSCRIPT13"   # 8 bytes
PAYLOAD13="$SANDBOX/all-zero-usage-payload.json"
jq -n --arg tp "$TRANSCRIPT13" '{
  session_id: "fixture-token-ledger-allzero-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp,
  input_tokens: 0,
  output_tokens: 0,
  usage: { input_tokens: 0, output_tokens: 0 }
}' > "$PAYLOAD13"
OUT13="$(run_sut "$PAYLOAD13")"
RC13="$(printf '%s\n' "$OUT13" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case13 exit 0" "0" "$RC13"
LOG13="$SANDBOX/.supervisor/logs/fixture-token-ledger-allzero-001.jsonl"
LINE13="$(tail -1 "$LOG13" 2>/dev/null)"
assert_eq "case13 all-zero usage → proxy:true" "true" "$(printf '%s' "$LINE13" | jq -r '.proxy')"
assert_eq "case13 transcript bytes recorded" "8" "$(printf '%s' "$LINE13" | jq -r '.token_proxy_transcript_bytes')"
# Mixed case: any non-zero usage field must still be treated as real usage.
PAYLOAD13B="$SANDBOX/mixed-zero-usage-payload.json"
jq -n --arg tp "$TRANSCRIPT13" '{
  session_id: "fixture-token-ledger-mixedzero-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp,
  usage: { input_tokens: 0, output_tokens: 5 }
}' > "$PAYLOAD13B"
OUT13B="$(run_sut "$PAYLOAD13B")"
LINE13B="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-mixedzero-001.jsonl" 2>/dev/null)"
assert_eq "case13b mixed-zero usage stays proxy:false" "false" "$(printf '%s' "$LINE13B" | jq -r '.proxy')"
assert_eq "case13b zero field preserved inside usage" "0" "$(printf '%s' "$LINE13B" | jq -r '.usage.input_tokens')"

echo "== 14. orientation_source — valid emitted / unset absent / invalid absent =="
TRANSCRIPT14="$SANDBOX/agent-transcript-14.jsonl"
printf 'HHHHHH' > "$TRANSCRIPT14"   # 6 bytes
# 14a: valid value ("memos") → field present with that exact value.
PAYLOAD14A="$SANDBOX/orientation-valid-payload.json"
jq -n --arg tp "$TRANSCRIPT14" '{
  session_id: "fixture-token-ledger-orientation-valid-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD14A"
OUT14A="$(run_sut_env memos "$PAYLOAD14A")"
RC14A="$(printf '%s\n' "$OUT14A" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case14a exit 0" "0" "$RC14A"
LINE14A="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-orientation-valid-001.jsonl" 2>/dev/null)"
assert_eq "case14a orientation_source=memos" "memos" "$(printf '%s' "$LINE14A" | jq -r '.orientation_source')"
# Also prove a second enum value round-trips (repo_map — underscore, not hyphen).
PAYLOAD14A2="$SANDBOX/orientation-valid2-payload.json"
jq -n --arg tp "$TRANSCRIPT14" '{
  session_id: "fixture-token-ledger-orientation-valid-002",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD14A2"
OUT14A2="$(run_sut_env repo_map "$PAYLOAD14A2")"
LINE14A2="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-orientation-valid-002.jsonl" 2>/dev/null)"
assert_eq "case14a2 orientation_source=repo_map" "repo_map" "$(printf '%s' "$LINE14A2" | jq -r '.orientation_source')"
# 14b: unset → field absent (run_sut scrubs the env var).
PAYLOAD14B="$SANDBOX/orientation-unset-payload.json"
jq -n --arg tp "$TRANSCRIPT14" '{
  session_id: "fixture-token-ledger-orientation-unset-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD14B"
OUT14B="$(run_sut "$PAYLOAD14B")"
RC14B="$(printf '%s\n' "$OUT14B" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case14b exit 0" "0" "$RC14B"
LINE14B="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-orientation-unset-001.jsonl" 2>/dev/null)"
if printf '%s' "$LINE14B" | jq -e 'has("orientation_source")' >/dev/null 2>&1; then
  no "case14b orientation_source present despite unset env"
else
  ok "case14b orientation_source absent when env unset"
fi
# 14c: invalid value → field absent (fail-safe omission, exit still 0).
PAYLOAD14C="$SANDBOX/orientation-invalid-payload.json"
jq -n --arg tp "$TRANSCRIPT14" '{
  session_id: "fixture-token-ledger-orientation-invalid-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD14C"
OUT14C="$(run_sut_env "bogus-source" "$PAYLOAD14C")"
RC14C="$(printf '%s\n' "$OUT14C" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case14c exit 0" "0" "$RC14C"
LINE14C="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-orientation-invalid-001.jsonl" 2>/dev/null)"
if printf '%s' "$LINE14C" | jq -e 'has("orientation_source")' >/dev/null 2>&1; then
  no "case14c orientation_source present despite invalid value"
else
  ok "case14c orientation_source absent on invalid value"
fi
# The line itself must still be written (invalid attribution never drops the event).
assert_eq "case14c event still written" "token_ledger" "$(printf '%s' "$LINE14C" | jq -r '.event')"
# Empty-string value behaves like unset.
PAYLOAD14D="$SANDBOX/orientation-empty-payload.json"
jq -n --arg tp "$TRANSCRIPT14" '{
  session_id: "fixture-token-ledger-orientation-empty-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD14D"
OUT14D="$(run_sut_env "" "$PAYLOAD14D")"
LINE14D="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-orientation-empty-001.jsonl" 2>/dev/null)"
if printf '%s' "$LINE14D" | jq -e 'has("orientation_source")' >/dev/null 2>&1; then
  no "case14d orientation_source present despite empty-string value"
else
  ok "case14d orientation_source absent on empty-string value"
fi

echo "== 15. shared_prefix — =1 emitted / unset absent / other value absent =="
TRANSCRIPT15="$SANDBOX/agent-transcript-15.jsonl"
printf 'IIIIII' > "$TRANSCRIPT15"   # 6 bytes
# 15a: LOOMWRIGHT_SHARED_PREFIX=1 → shared_prefix:true present (JSON boolean).
PAYLOAD15A="$SANDBOX/shared-prefix-on-payload.json"
jq -n --arg tp "$TRANSCRIPT15" '{
  session_id: "fixture-token-ledger-sharedprefix-on-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD15A"
OUT15A="$(run_sut_sp "1" "$PAYLOAD15A")"
RC15A="$(printf '%s\n' "$OUT15A" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case15a exit 0" "0" "$RC15A"
LINE15A="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-sharedprefix-on-001.jsonl" 2>/dev/null)"
assert_eq "case15a shared_prefix=true" "true" "$(printf '%s' "$LINE15A" | jq -r '.shared_prefix')"
# Must be the JSON boolean true, not the string "true".
if printf '%s' "$LINE15A" | jq -e '.shared_prefix == true' >/dev/null 2>&1; then
  ok "case15a shared_prefix is JSON boolean true"
else
  no "case15a shared_prefix is not the JSON boolean true"
fi
# 15b: unset → field absent (run_sut scrubs the env var).
PAYLOAD15B="$SANDBOX/shared-prefix-unset-payload.json"
jq -n --arg tp "$TRANSCRIPT15" '{
  session_id: "fixture-token-ledger-sharedprefix-unset-001",
  agent_type: "loomwright:code-reviewer",
  agent_transcript_path: $tp
}' > "$PAYLOAD15B"
OUT15B="$(run_sut "$PAYLOAD15B")"
RC15B="$(printf '%s\n' "$OUT15B" | grep '^RC=' | tail -1 | cut -d= -f2)"
assert_eq "case15b exit 0" "0" "$RC15B"
LINE15B="$(tail -1 "$SANDBOX/.supervisor/logs/fixture-token-ledger-sharedprefix-unset-001.jsonl" 2>/dev/null)"
if printf '%s' "$LINE15B" | jq -e 'has("shared_prefix")' >/dev/null 2>&1; then
  no "case15b shared_prefix present despite unset env"
else
  ok "case15b shared_prefix absent when env unset"
fi
# 15c: any other value ("0", "true", empty) → field absent, event still written.
for spv in "0" "true" ""; do
  SPSLUG="$(printf '%s' "$spv" | tr -cd 'a-z0-9')"
  SPSID="fixture-token-ledger-sharedprefix-off-${SPSLUG:-empty}-001"
  PAYLOAD15C="$SANDBOX/shared-prefix-off-${SPSLUG:-empty}-payload.json"
  jq -n --arg tp "$TRANSCRIPT15" --arg sid "$SPSID" '{
    session_id: $sid,
    agent_type: "loomwright:code-reviewer",
    agent_transcript_path: $tp
  }' > "$PAYLOAD15C"
  OUT15C="$(run_sut_sp "$spv" "$PAYLOAD15C")"
  RC15C="$(printf '%s\n' "$OUT15C" | grep '^RC=' | tail -1 | cut -d= -f2)"
  assert_eq "case15c(${spv:-empty}) exit 0" "0" "$RC15C"
  LINE15C="$(tail -1 "$SANDBOX/.supervisor/logs/${SPSID}.jsonl" 2>/dev/null)"
  if printf '%s' "$LINE15C" | jq -e 'has("shared_prefix")' >/dev/null 2>&1; then
    no "case15c(${spv:-empty}) shared_prefix present despite non-1 value"
  else
    ok "case15c(${spv:-empty}) shared_prefix absent on non-1 value"
  fi
  # The line itself must still be written (marker never drops the event).
  assert_eq "case15c(${spv:-empty}) event still written" "token_ledger" "$(printf '%s' "$LINE15C" | jq -r '.event')"
done

echo ""
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
