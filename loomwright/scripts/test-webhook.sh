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
# Every case runs send-webhook.sh in DRY-RUN (LOOMWRIGHT_WEBHOOK_DRY_RUN=1
# with LOOMWRIGHT_WEBHOOK_URL=test) so the composed JSON payload is printed
# to stdout instead of POSTed, and asserts on it. The always-exit-0 invariant is
# asserted on every case.
#
# Cases 10+ (script-test gap closure): hostile-string EXACT round-trip proofs
# on the gate path (--context/--session-id) and the supervisor_result path
# (flat top-level fallback + in-block yaml_field line), paused-event
# format-branch coverage (ntfy.sh URL / LOOMWRIGHT_WEBHOOK_FORMAT=ntfy /
# default JSON — which is also the Slack shape: send-webhook.sh has no
# dedicated Slack branch), and exit-0-on-every-failure-path assertions.
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
assert_valid_json() {
  local label="$1" json="$2"
  if printf '%s' "$json" | jq -e . >/dev/null 2>&1; then pass "$label"; else fail "$label  not valid JSON: '$json'"; fi
}
assert_absent() {
  local label="$1" path="$2"
  if [ ! -e "$path" ]; then pass "$label"; else fail "$label  file unexpectedly exists: $path"; fi
}

# run_dry_run <payload_json>  →  sets OUT (stdout), ERR (stderr), RC.
run_dry_run() {
  local payload="$1" errtmp
  errtmp="$(mktemp)"
  OUT="$(printf '%s' "$payload" \
    | LOOMWRIGHT_WEBHOOK_URL=test LOOMWRIGHT_WEBHOOK_DRY_RUN=1 \
      bash "$WEBHOOK" 2>"$errtmp")"
  RC=$?
  ERR="$(cat "$errtmp")"
  rm -f "$errtmp"
}

# run_paused <webhook_url> <format_or_empty> <payload_json>  →  sets OUT, ERR, RC.
# Paused-event dry-run with a controlled URL. LOOMWRIGHT_NOTIFY_SCOPE=all makes
# the scope gate deterministic (independent of any .supervisor/ state in the
# cwd). When <format_or_empty> is empty, LOOMWRIGHT_WEBHOOK_FORMAT is scrubbed
# via `env -u` so a dev-environment export can never flip the asserted branch
# (repo lesson: scrub webhook/telemetry env vars wherever an OFF-path is
# asserted).
run_paused() {
  local url="$1" fmt="$2" payload="$3" errtmp
  errtmp="$(mktemp)"
  if [ -n "$fmt" ]; then
    OUT="$(printf '%s' "$payload" \
      | env LOOMWRIGHT_WEBHOOK_URL="$url" LOOMWRIGHT_WEBHOOK_DRY_RUN=1 \
            LOOMWRIGHT_NOTIFY_SCOPE=all LOOMWRIGHT_WEBHOOK_FORMAT="$fmt" \
        bash "$WEBHOOK" 2>"$errtmp")"
  else
    OUT="$(printf '%s' "$payload" \
      | env -u LOOMWRIGHT_WEBHOOK_FORMAT \
            LOOMWRIGHT_WEBHOOK_URL="$url" LOOMWRIGHT_WEBHOOK_DRY_RUN=1 \
            LOOMWRIGHT_NOTIFY_SCOPE=all \
        bash "$WEBHOOK" 2>"$errtmp")"
  fi
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
  '{session_id:"s1", agent_type:"loomwright:supervisor-runner", last_assistant_message:$m, transcript_path:"/nonexistent.jsonl"}')"
run_dry_run "$PAYLOAD1"
assert_eq   "case1 exit 0" "0" "$RC"
assert_eq   "case1 status=completed" "completed" "$(printf '%s' "$OUT" | jq -r '.status // empty')"
assert_eq   "case1 pr_url extracted" "https://github.com/example/repo/pull/42" "$(printf '%s' "$OUT" | jq -r '.pr_url // empty')"
assert_match "case1 summary extracted" "Three subtasks merged cleanly" "$(printf '%s' "$OUT" | jq -r '.summary // empty')"
assert_eq   "case1 agent=supervisor" "supervisor" "$(printf '%s' "$OUT" | jq -r '.agent // empty')"

echo ""
echo "==== Case 2: legacy result_block (back-compat) ===="
PAYLOAD2="$(jq -nc --arg m "$RESULT_TEXT" \
  '{session_id:"s2", agent_type:"loomwright:supervisor-runner", result_block:$m}')"
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
  '{session_id:"s3", agent_type:"loomwright:supervisor-runner", agent_transcript_path:$tp, transcript_path:"/nonexistent.jsonl"}')"
run_dry_run "$PAYLOAD3"
assert_eq   "case3 exit 0" "0" "$RC"
assert_eq   "case3 status from transcript" "completed" "$(printf '%s' "$OUT" | jq -r '.status // empty')"
assert_eq   "case3 pr_url from transcript" "https://github.com/example/repo/pull/42" "$(printf '%s' "$OUT" | jq -r '.pr_url // empty')"

echo ""
echo "==== Case 4: no result block present → suppress POST (no payload) ===="
PAYLOAD4="$(jq -nc '{session_id:"s4", agent_type:"loomwright:supervisor-runner", last_assistant_message:"Just some prose with no result block."}')"
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
OUT6="$(LOOMWRIGHT_WEBHOOK_URL=test LOOMWRIGHT_WEBHOOK_DRY_RUN=1 \
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
# LOOMWRIGHT_WEBHOOK_URL UNSET, the URL must come from the legacy file.
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
  && unset LOOMWRIGHT_WEBHOOK_URL \
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
  && unset LOOMWRIGHT_WEBHOOK_URL \
  && CURL_TARGET_FILE="$CURL_TARGET8" PATH="$WD8/bin:$PATH" \
     bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s8 >/dev/null 2>&1 )
RC8=$?
URL8="$(cat "$CURL_TARGET8" 2>/dev/null || true)"
assert_eq "case8 exit 0" "0" "$RC8"
assert_eq "case8 new config.json wins (legacy ignored)" "https://new.example/hook" "$URL8"

echo ""
echo "==== Case 9: config resolution — unreadable NEW file falls back to legacy ===="
# Proves the `[ -r "$CONFIG_FILE" ]` branch: when .supervisor/config.json exists
# but is NOT readable (chmod 000), resolution must fall back to the legacy
# .supervisor/notify-config.json. The new file's webhook_url must NOT be used.
WD9="$TMPDIR_TEST/case9"
mkdir -p "$WD9/.supervisor" "$WD9/bin"
printf '{"webhook_url": "https://unreadable-new.example/hook"}\n' > "$WD9/.supervisor/config.json"
printf '{"webhook_url": "https://legacy.example/hook"}\n'         > "$WD9/.supervisor/notify-config.json"
chmod 000 "$WD9/.supervisor/config.json"
cat > "$WD9/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in -*) ;; *) url="$a" ;; esac; done
printf '%s\n' "$url" > "$CURL_TARGET_FILE"
exit 0
STUB
chmod +x "$WD9/bin/curl"
# Guard: if the harness runs as a user that can still read a 000 file (e.g. root),
# the [ -r ] branch can't be exercised — SKIP rather than spuriously fail.
if [ -r "$WD9/.supervisor/config.json" ]; then
  echo "SKIP  case9 unreadable-config fallback (platform reports 000 file readable, e.g. root)"
else
  CURL_TARGET9="$WD9/curl-target.txt"
  ( cd "$WD9" \
    && unset LOOMWRIGHT_WEBHOOK_URL \
    && CURL_TARGET_FILE="$CURL_TARGET9" PATH="$WD9/bin:$PATH" \
       bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s9 >/dev/null 2>&1 )
  RC9=$?
  URL9="$(cat "$CURL_TARGET9" 2>/dev/null || true)"
  assert_eq "case9 exit 0" "0" "$RC9"
  assert_eq "case9 unreadable new → legacy URL used" "https://legacy.example/hook" "$URL9"
fi
# Restore perms so the trap teardown (rm -rf) can remove the temp dir cleanly.
chmod 644 "$WD9/.supervisor/config.json" 2>/dev/null || true

echo ""
echo "==== Case 10: gate path — hostile-string EXACT round-trip (injection safety) ===="
# Hostile value covering the full injection-safety contract: double quotes,
# backslashes, an embedded newline, $(...)/backtick command-substitution TEXT,
# single quotes, and multibyte unicode. Built via literal-segment concatenation
# (no ${var//...} pattern-sub — bash-3.2 lesson) around a REAL marker path so
# that if any layer ever eval'd the string, the marker file would appear and
# assert_absent would fail.
PWNED_MARKER="$TMPDIR_TEST/pwned-marker"
NL=$'\n'
HOSTILE_Q='he said "hi" with \back\slash and '\''single quotes'\'''
HOSTILE_CMD='$(touch '"$PWNED_MARKER"') and `touch '"$PWNED_MARKER"'`'
HOSTILE_UNI='ünïcødé — 日本語 ✓'
HOSTILE="${HOSTILE_Q}${NL}${HOSTILE_CMD}${NL}${HOSTILE_UNI}"
HOSTILE_SID='sid "quoted" \back'
OUT10="$(LOOMWRIGHT_WEBHOOK_URL=test LOOMWRIGHT_WEBHOOK_DRY_RUN=1 \
  bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 3 \
    --session-id "$HOSTILE_SID" --context "$HOSTILE" 2>/dev/null)"
RC10=$?
assert_eq         "case10 exit 0" "0" "$RC10"
assert_valid_json "case10 payload is valid JSON" "$OUT10"
assert_eq         "case10 context round-trips EXACTLY" "$HOSTILE" "$(printf '%s' "$OUT10" | jq -r '.context')"
assert_eq         "case10 session_id round-trips EXACTLY" "$HOSTILE_SID" "$(printf '%s' "$OUT10" | jq -r '.session_id')"
assert_absent     "case10 command substitution NOT executed" "$PWNED_MARKER"

echo ""
echo "==== Case 11: supervisor_result path — hostile summary via top-level fields ===="
# Flat-object fixture shape (documented fallback: top-level .status/.summary
# are consulted when the result text carries no `key: value` line). The full
# hostile string — including double quotes and the embedded newline — must
# round-trip EXACTLY through the stdin → jq extraction → jq --arg composition.
PAYLOAD11="$(jq -nc --arg s "$HOSTILE" \
  '{session_id:"s11", agent_type:"loomwright:supervisor-runner",
    last_assistant_message:"prose without a result block",
    status:"completed", pr_url:"https://github.com/example/repo/pull/44", summary:$s}')"
run_dry_run "$PAYLOAD11"
assert_eq         "case11 exit 0" "0" "$RC"
assert_valid_json "case11 payload is valid JSON" "$OUT"
assert_eq         "case11 status=completed" "completed" "$(printf '%s' "$OUT" | jq -r '.status')"
assert_eq         "case11 hostile summary round-trips EXACTLY" "$HOSTILE" "$(printf '%s' "$OUT" | jq -r '.summary')"
assert_absent     "case11 command substitution NOT executed" "$PWNED_MARKER"

echo ""
echo "==== Case 12: supervisor_result path — hostile summary INSIDE the result block ===="
# The yaml_field extractor is documented single-line and stops at the first
# embedded double-quote (send-webhook.sh "Value-shape assumption" comment), so
# this case uses the yaml-safe hostile subset: command-substitution text,
# backticks, single quotes, backslashes, unicode — no double quotes, no newline.
HOSTILE_LINE='fix user'\''s $(touch '"$PWNED_MARKER"') and `touch '"$PWNED_MARKER"'` — ünïcødé \back\slash'
RESULT_TEXT12="## SUPERVISOR_RESULT
- schema_version: 1
- status: completed
- pr_url: https://github.com/example/repo/pull/45
- summary: $HOSTILE_LINE"
PAYLOAD12="$(jq -nc --arg m "$RESULT_TEXT12" \
  '{session_id:"s12", agent_type:"loomwright:supervisor-runner", last_assistant_message:$m}')"
run_dry_run "$PAYLOAD12"
assert_eq         "case12 exit 0" "0" "$RC"
assert_valid_json "case12 payload is valid JSON" "$OUT"
assert_eq         "case12 hostile summary line round-trips EXACTLY" "$HOSTILE_LINE" "$(printf '%s' "$OUT" | jq -r '.summary')"
assert_absent     "case12 command substitution NOT executed" "$PWNED_MARKER"

echo ""
echo "==== Case 13: paused event — ntfy.sh URL selects the plain-text ntfy branch ===="
PAUSED_PAYLOAD="$(jq -nc \
  '{hook_event_name:"PreToolUse", tool_name:"AskUserQuestion",
    tool_input:{questions:[{question:"Merge iteration 2 before continuing?"}]}}')"
run_paused "https://ntfy.sh/loomwright-test" "" "$PAUSED_PAYLOAD"
assert_eq    "case13 exit 0" "0" "$RC"
assert_match "case13 ntfy plain-text branch taken" "NTFY paused: title=[Claude needs your input]" "$OUT"
assert_match "case13 question in ntfy body" "Merge iteration 2 before continuing?" "$OUT"

echo ""
echo "==== Case 14: paused event — LOOMWRIGHT_WEBHOOK_FORMAT=ntfy forces ntfy on a generic URL ===="
run_paused "https://example.com/generic-hook" "ntfy" "$PAUSED_PAYLOAD"
assert_eq    "case14 exit 0" "0" "$RC"
assert_match "case14 ntfy branch via FORMAT env" "NTFY paused: title=[Claude needs your input]" "$OUT"

echo ""
echo "==== Case 15: paused event — Slack-shaped URL takes the default JSON branch ===="
# send-webhook.sh has NO dedicated Slack branch: everything that is not ntfy
# ("Everything else (Slack/Discord/custom) gets the structured JSON payload")
# receives {event:"paused", question, timestamp}. Assert that shape on a
# hooks.slack.com URL, with the hostile question proving jq --arg round-trip
# on this path too. LOOMWRIGHT_WEBHOOK_FORMAT is scrubbed (env -u) so a dev
# export of the ntfy format cannot flip the asserted branch.
PAUSED_HOSTILE="$(jq -nc --arg q "$HOSTILE" \
  '{hook_event_name:"PreToolUse", tool_name:"AskUserQuestion",
    tool_input:{questions:[{question:$q}]}}')"
run_paused "https://hooks.slack.com/services/T000/B000/XXXX" "" "$PAUSED_HOSTILE"
assert_eq         "case15 exit 0" "0" "$RC"
assert_valid_json "case15 payload is valid JSON (not ntfy plain text)" "$OUT"
assert_eq         "case15 event=paused" "paused" "$(printf '%s' "$OUT" | jq -r '.event')"
assert_eq         "case15 hostile question round-trips EXACTLY" "$HOSTILE" "$(printf '%s' "$OUT" | jq -r '.question')"
assert_absent     "case15 command substitution NOT executed" "$PWNED_MARKER"

echo ""
echo "==== Case 16: paused event — URL merely containing 'ntfy' stays JSON ===="
# Regression guard for the tightened ntfy glob (*ntfy.sh/*): a hostname that
# contains "ntfy" but is NOT the ntfy.sh service (e.g. ntfy.example.com) must
# NOT receive an ntfy-shaped plain-text request.
run_paused "https://ntfy.example.com/hook" "" "$PAUSED_PAYLOAD"
assert_eq         "case16 exit 0" "0" "$RC"
assert_valid_json "case16 JSON branch taken (not ntfy)" "$OUT"
assert_eq         "case16 event=paused" "paused" "$(printf '%s' "$OUT" | jq -r '.event')"

echo ""
echo "==== Case 17: gate event without --gate-type → skip, exit 0 ===="
ERR17_TMP="$(mktemp)"
OUT17="$(LOOMWRIGHT_WEBHOOK_URL=test LOOMWRIGHT_WEBHOOK_DRY_RUN=1 \
  bash "$WEBHOOK" --event-type gate --iteration 1 --session-id s17 2>"$ERR17_TMP")"
RC17=$?
ERR17="$(cat "$ERR17_TMP")"
rm -f "$ERR17_TMP"
assert_eq    "case17 exit 0 on failure path" "0" "$RC17"
assert_empty "case17 no payload printed" "$OUT17"
assert_match "case17 skip message on stderr" "--gate-type is required" "$ERR17"

echo ""
echo "==== Case 18: malformed (non-JSON) stdin on supervisor_result path → skip, exit 0 ===="
run_dry_run 'this is {{{ not json'
assert_eq    "case18 exit 0 on failure path" "0" "$RC"
assert_empty "case18 no payload printed" "$OUT"
assert_match "case18 skip message on stderr" "skipping POST" "$ERR"

echo ""
echo "==== Case 19: AskUserQuestion payload lacking tool_input.questions → skip, exit 0 ===="
# Defense-in-depth guard runs BEFORE the scope gate; assert the exact skip.
PAYLOAD19="$(jq -nc '{hook_event_name:"PreToolUse", tool_name:"AskUserQuestion", tool_input:{}}')"
run_paused "https://example.com/hook" "" "$PAYLOAD19"
assert_eq    "case19 exit 0 on failure path" "0" "$RC"
assert_empty "case19 no payload printed" "$OUT"
assert_match "case19 skip message on stderr" "lacks tool_input.questions" "$ERR"

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
