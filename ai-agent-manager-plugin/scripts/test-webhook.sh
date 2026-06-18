#!/usr/bin/env bash
# test-webhook.sh — dry-run self-tests for send-webhook.sh (supervisor_result path)
#
# Added in v14.2.1 alongside the result-extraction fix. The supervisor_result
# path now resolves the agent's output text from the REAL SubagentStop fields:
#   last_assistant_message → (legacy) result_block/output/agent_output
#     → last assistant message read from agent_transcript_path / transcript_path
# (the pre-fix reader looked only at `.result_block`, which a real Claude Code
# SubagentStop payload never populates — so the webhook silently sent an
# all-empty / suppressed payload).
#
# Every case runs send-webhook.sh in DRY-RUN (AI_AGENT_MANAGER_WEBHOOK_DRY_RUN=1
# with AI_AGENT_MANAGER_WEBHOOK_URL=test) so the composed JSON payload is printed
# to stdout instead of POSTed, and asserts on it. The always-exit-0 invariant is
# asserted on every case.
#
# EXIT: 0 on full pass, 1 on any failure.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBHOOK="$SCRIPT_DIR/send-webhook.sh"

if [ ! -x "$WEBHOOK" ]; then
  echo "FATAL  send-webhook.sh not found or not executable: $WEBHOOK" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL  jq required to run these self-tests" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
declare -a FAIL_LINES=()

pass() { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL  $1"; FAIL_LINES+=("FAIL  $1"); FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label  expected='$expected' actual='$actual'"; fi
}
assert_match() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then pass "$label"; else fail "$label  needle='$needle' not found"; fi
}
assert_empty() {
  local label="$1" value="$2"
  if [ -z "$value" ]; then pass "$label"; else fail "$label  expected empty, got '$value'"; fi
}

# run_dry_run <payload_json>  →  sets OUT (stdout), ERR (stderr), RC.
run_dry_run() {
  local payload="$1" errtmp
  errtmp="$(mktemp)"
  OUT="$(printf '%s' "$payload" \
    | AI_AGENT_MANAGER_WEBHOOK_URL=test AI_AGENT_MANAGER_WEBHOOK_DRY_RUN=1 \
      bash "$WEBHOOK" 2>"$errtmp")"
  RC=$?
  ERR="$(cat "$errtmp")"
  rm -f "$errtmp"
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT INT TERM

RESULT_TEXT='## SUPERVISOR_RESULT
- schema_version: 1
- status: completed
- pr_url: https://github.com/example/repo/pull/42
- summary: Three subtasks merged cleanly; integration review fixed two minor issues.'

echo "==== Case 1: REAL payload shape (last_assistant_message) ===="
PAYLOAD1="$(jq -nc --arg m "$RESULT_TEXT" \
  '{session_id:"s1", agent_type:"ai-agent-manager-plugin:supervisor-runner", last_assistant_message:$m, transcript_path:"/nonexistent.jsonl"}')"
run_dry_run "$PAYLOAD1"
assert_eq   "case1 exit 0" "0" "$RC"
assert_eq   "case1 status=completed" "completed" "$(printf '%s' "$OUT" | jq -r '.status // empty')"
assert_eq   "case1 pr_url extracted" "https://github.com/example/repo/pull/42" "$(printf '%s' "$OUT" | jq -r '.pr_url // empty')"
assert_match "case1 summary extracted" "Three subtasks merged cleanly" "$(printf '%s' "$OUT" | jq -r '.summary // empty')"
assert_eq   "case1 agent=supervisor" "supervisor" "$(printf '%s' "$OUT" | jq -r '.agent // empty')"

echo ""
echo "==== Case 2: legacy result_block (back-compat) ===="
PAYLOAD2="$(jq -nc --arg m "$RESULT_TEXT" \
  '{session_id:"s2", agent_type:"ai-agent-manager-plugin:supervisor-runner", result_block:$m}')"
run_dry_run "$PAYLOAD2"
assert_eq "case2 exit 0" "0" "$RC"
assert_eq "case2 status=completed" "completed" "$(printf '%s' "$OUT" | jq -r '.status // empty')"

echo ""
echo "==== Case 3: transcript fallback (agent_transcript_path) ===="
TRANSCRIPT="$TMPDIR_TEST/subagent.jsonl"
python3 - "$TRANSCRIPT" "$RESULT_TEXT" <<'PY'
import json, sys
path, text = sys.argv[1], sys.argv[2]
with open(path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps({"type":"user","message":{"role":"user","content":"go"}}) + "\n")
    fh.write("not valid json line\n")
    fh.write(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ignore me"}]}}) + "\n")
    fh.write(json.dumps({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":text}]}}) + "\n")
PY
PAYLOAD3="$(jq -nc --arg tp "$TRANSCRIPT" \
  '{session_id:"s3", agent_type:"ai-agent-manager-plugin:supervisor-runner", agent_transcript_path:$tp, transcript_path:"/nonexistent.jsonl"}')"
run_dry_run "$PAYLOAD3"
assert_eq   "case3 exit 0" "0" "$RC"
assert_eq   "case3 status from transcript" "completed" "$(printf '%s' "$OUT" | jq -r '.status // empty')"
assert_eq   "case3 pr_url from transcript" "https://github.com/example/repo/pull/42" "$(printf '%s' "$OUT" | jq -r '.pr_url // empty')"

echo ""
echo "==== Case 4: no result block present → suppress POST (no payload) ===="
PAYLOAD4="$(jq -nc '{session_id:"s4", agent_type:"ai-agent-manager-plugin:supervisor-runner", last_assistant_message:"Just some prose with no result block."}')"
run_dry_run "$PAYLOAD4"
assert_eq    "case4 exit 0" "0" "$RC"
assert_empty "case4 no payload printed" "$OUT"
assert_match "case4 skip message on stderr" "skipping POST" "$ERR"

echo ""
echo "==== Case 5: empty stdin → exit 0, no payload ===="
run_dry_run ""
assert_eq    "case5 exit 0" "0" "$RC"
assert_empty "case5 no payload printed" "$OUT"

echo ""
echo "==== Case 6: gate event injection-safety smoke (regression guard) ===="
OUT6="$(AI_AGENT_MANAGER_WEBHOOK_URL=test AI_AGENT_MANAGER_WEBHOOK_DRY_RUN=1 \
  bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 2 --session-id s \
    --context 'fix user'"'"'s "auth" bug' 2>/dev/null)"
RC6=$?
assert_eq    "case6 exit 0" "0" "$RC6"
assert_eq    "case6 valid json" "gate" "$(printf '%s' "$OUT6" | jq -r '.event_type // empty')"
assert_eq    "case6 context round-trips" 'fix user'"'"'s "auth" bug' "$(printf '%s' "$OUT6" | jq -r '.context // empty')"

echo ""
echo "==== Case 7: config resolution — LEGACY-ONLY fallback honored ===="
# Mirrors test-dispatch-pr-postmortem.sh case 8b: an old install with ONLY the
# legacy .supervisor/notify-config.json must still be read. With
# AI_AGENT_MANAGER_WEBHOOK_URL UNSET, the URL must come from the legacy file.
# Observe the resolved URL via a curl STUB on PATH that records its final arg
# (the webhook URL) — we run a NON-dry-run gate event so curl is actually invoked
# but the stub captures the target instead of making a network call.
WD7="$TMPDIR_TEST/case7"
mkdir -p "$WD7/.supervisor" "$WD7/bin"
printf '{"webhook_url": "https://legacy.example/hook"}\n' > "$WD7/.supervisor/notify-config.json"
cat > "$WD7/bin/curl" <<'STUB'
#!/usr/bin/env bash
# curl stub: record only the URL (last non-flag arg) and exit 0; no network.
url=""
for a in "$@"; do case "$a" in -*) ;; *) url="$a" ;; esac; done
printf '%s\n' "$url" > "$CURL_TARGET_FILE"
exit 0
STUB
chmod +x "$WD7/bin/curl"
CURL_TARGET7="$WD7/curl-target.txt"
( cd "$WD7" \
  && unset AI_AGENT_MANAGER_WEBHOOK_URL \
  && CURL_TARGET_FILE="$CURL_TARGET7" PATH="$WD7/bin:$PATH" \
     bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s7 >/dev/null 2>&1 )
RC7=$?
URL7="$(cat "$CURL_TARGET7" 2>/dev/null || true)"
assert_eq "case7 exit 0" "0" "$RC7"
assert_eq "case7 legacy URL used (fallback honored)" "https://legacy.example/hook" "$URL7"

echo ""
echo "==== Case 8: config resolution — BOTH present, NEW file wins ===="
# Mirrors test-dispatch-pr-postmortem.sh case 8c: when both files exist with
# DIFFERENT webhook_url values, the new .supervisor/config.json must win.
WD8="$TMPDIR_TEST/case8"
mkdir -p "$WD8/.supervisor" "$WD8/bin"
printf '{"webhook_url": "https://new.example/hook"}\n'    > "$WD8/.supervisor/config.json"
printf '{"webhook_url": "https://legacy.example/hook"}\n' > "$WD8/.supervisor/notify-config.json"
cat > "$WD8/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in -*) ;; *) url="$a" ;; esac; done
printf '%s\n' "$url" > "$CURL_TARGET_FILE"
exit 0
STUB
chmod +x "$WD8/bin/curl"
CURL_TARGET8="$WD8/curl-target.txt"
( cd "$WD8" \
  && unset AI_AGENT_MANAGER_WEBHOOK_URL \
  && CURL_TARGET_FILE="$CURL_TARGET8" PATH="$WD8/bin:$PATH" \
     bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s8 >/dev/null 2>&1 )
RC8=$?
URL8="$(cat "$CURL_TARGET8" 2>/dev/null || true)"
assert_eq "case8 exit 0" "0" "$RC8"
assert_eq "case8 new config.json wins (legacy ignored)" "https://new.example/hook" "$URL8"

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "=========================================="
echo "RESULT  total=$TOTAL  passed=$PASS_COUNT  failed=$FAIL_COUNT"
echo "=========================================="
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf '  %s\n' "${FAIL_LINES[@]}"
  exit 1
fi
exit 0
