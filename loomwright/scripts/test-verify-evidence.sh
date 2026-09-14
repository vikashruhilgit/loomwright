#!/usr/bin/env bash
# test-verify-evidence.sh — self-tests for the `/verify` evidence store seam: the VERIFY_EVIDENCE
# line validator (validate-verify-evidence.py) and — appended by the helper subtask below the marked
# anchor — the append-only writer / derived-summary helper (verify-helpers.sh). Schema authority:
# docs/RESULT_SCHEMAS.md §VERIFY_EVIDENCE.
#
# WHY THE VALIDATOR'S EXIT STATUS IS ASSERTED ON EVERY CASE. Unlike its hook-emitter siblings this
# validator is a CLI GATE: `verify-helpers.sh evidence-append` appends a line only when it exits 0,
# so a validator that decided "invalid" on stdout but exited 0 would let the fact through. Every
# reject case therefore asserts rc=1 AND the reason; every accept case asserts rc=0 AND `.ok==true`;
# the usage cases assert rc=2 AND an EMPTY stdout. Statuses are captured as `$?` in the statement
# after the call — never `if ! rc=$(...)`, never `producer | grep -q` under pipefail (the status of
# the producer is lost / SIGPIPE'd — memory bash-grep-pipefail-nul-traps).
#
# Static-only: no network, no `gh`, no Docker. Every fixture lives under a `mktemp -d`. Exit 0 = all
# pass, 1 = any failure (auto-registered by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Validator cases (line mode unless stated):
#   (V1)  one VALID line per event accepted — run_start (null env_contract_hash), env pass, env fail
#         with reason, auth, ac PASS (classification null), ac FAIL (reason + classification), ac
#         BLOCKED, ac NOT_VERIFIABLE (reason, no classification), issue, pause, resume, run_end
#   (V2)  not_json / not_object
#   (V3)  schema_version_mismatch — absent, 2, "1", true (a JSON true is NOT the integer 1)
#   (V4)  missing_key:<k> — each common key; per-event keys; env.reason on outcome fail (absent AND
#         empty); pause/resume reason (absent, null, empty); ac steps / artifacts / ac_id
#   (V5)  bad_type:<k> — ts non-string and non-ISO; run_id without the `verify-` prefix; steps not an
#         array; artifacts entry non-string / absolute; env_contract_hash number; classification number
#   (V6)  unknown_event
#   (V7)  unknown_verdict — lower-case `pass`, `MAYBE`
#   (V8)  unknown_enum:<k> — ticket_kind, step, outcome, state, scope, severity, classification, status
#   (V9)  non_pass_without_reason — FAIL absent / empty / null reason; BLOCKED; NOT_VERIFIABLE
#   (V10) missing_classification — FAIL and BLOCKED with reason but absent / null classification
#   (V11) classification_on_pass — PASS and NOT_VERIFIABLE carrying a classification
#   (V12) run_end_carries_counts — top-level `counts`, nested `meta.totals`, inside an array
#   (V13) forward-compat — unknown additive keys tolerated on `ac` and on `run_end`
#   (V14) file mode — 3-line file with line 2 broken reports `"line": 2`; blank lines are skipped but
#         COUNTED (valid, blank, broken ⇒ line 3); an all-valid file with blanks ⇒ rc 0; an empty file
#         ⇒ rc 0; the first offending line wins when two are broken
#   (V15) exit 2 — no args, `--line` without a value, `--line` with two values, unknown option,
#         missing file, a directory; stdout EMPTY on every one
#   (V16) line mode reports `"line": null`; stdout is exactly ONE line of JSON on every decision
#   (V17) REASON-SET CLOSURE — every one of the 12 AC6 codes was provoked above; nothing outside the
#         set was ever emitted; the validator docstring AND the schema section name all 12
#   (V18) the validator is stdlib-only (no result_block_parser, no third-party import) and the schema
#         section sits between `## VERIFY_ENV` and `## Validation Location` with its Version History
#         bullet and `Current versions:` mention present (a claim no check backs is a defect)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$HERE/validate-verify-evidence.py"
SCHEMA_DOC="$HERE/../docs/RESULT_SCHEMAS.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$VALIDATOR" "$SCHEMA_DOC"; do
  if [ ! -f "$f" ]; then
    echo "  FAIL: required file not found at $f"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done
for tool in python3 jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "  FAIL: $tool is required by this suite"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# ---------------------------------------------------------------------------
# Harness helpers.
# ---------------------------------------------------------------------------
LAST_OUT="$ROOT/last-stdout.txt"
LAST_ERR="$ROOT/last-stderr.txt"
SEEN_REASONS="$ROOT/seen-reasons.txt"   # every reason the validator emitted, one per line
: > "$SEEN_REASONS"

# run_v <args...> — runs the validator; stdout/stderr into FIXED files; the function's status is the
# validator's exit status (capture it as `$?` in the very next statement).
run_v() {
  : > "$LAST_OUT"; : > "$LAST_ERR"
  python3 "$VALIDATOR" "$@" >"$LAST_OUT" 2>"$LAST_ERR"
}

out_field() { jq -r "$1" "$LAST_OUT" 2>/dev/null; }
out_lines() { grep -c . "$LAST_OUT"; }   # count of non-empty stdout lines (never `|| echo 0`: grep -c prints 0 itself)

# expect_accept <label> <json>
expect_accept() {
  local label="$1" json="$2" rc okf n
  run_v --line "$json"; rc=$?
  okf="$(out_field '.ok')"; n="$(out_lines)"
  if [ "$rc" -eq 0 ] && [ "$okf" = "true" ] && [ "$n" -eq 1 ]; then
    ok "$label → rc 0, {\"ok\": true}"
  else
    no "$label: rc=$rc ok=$okf stdout=$(cat "$LAST_OUT") stderr=$(cat "$LAST_ERR")"
  fi
}

# expect_reject <label> <expected_reason> <json>
expect_reject() {
  local label="$1" want="$2" json="$3" rc okf got n
  run_v --line "$json"; rc=$?
  okf="$(out_field '.ok')"; got="$(out_field '.reason // empty')"; n="$(out_lines)"
  [ -n "$got" ] && printf '%s\n' "$got" >> "$SEEN_REASONS"
  if [ "$rc" -eq 1 ] && [ "$okf" = "false" ] && [ "$got" = "$want" ] && [ "$n" -eq 1 ]; then
    ok "$label → rc 1, reason $want"
  else
    no "$label: want=$want rc=$rc ok=$okf reason=$got stdout=$(cat "$LAST_OUT") stderr=$(cat "$LAST_ERR")"
  fi
}

# expect_usage <label> <args...> — rc 2, EMPTY stdout, something on stderr
expect_usage() {
  local label="$1"; shift
  local rc
  run_v "$@"; rc=$?
  if [ "$rc" -eq 2 ] && [ ! -s "$LAST_OUT" ] && [ -s "$LAST_ERR" ]; then
    ok "$label → rc 2, empty stdout, reason on stderr"
  else
    no "$label: rc=$rc stdout=$(cat "$LAST_OUT") stderr=$(cat "$LAST_ERR")"
  fi
}

# mut <json> <jq-filter> — a mutated copy of a fixture line (compact). `jq -c` never fails on these
# well-formed fixtures; a jq error would surface as an empty string and a loud reject-case failure.
mut() { printf '%s' "$1" | jq -c "$2"; }

# ---------------------------------------------------------------------------
# Canonical VALID fixtures — one per event (the frozen example values from the schema section).
# ---------------------------------------------------------------------------
COMMON='"schema_version":1,"ts":"2026-09-14T10:00:00Z","run_id":"verify-20260914T100000Z-example"'
L_RUN_START="{$COMMON,\"event\":\"run_start\",\"ticket_path\":\".supervisor/requirements/example/01-login.md\",\"ticket_kind\":\"requirement\",\"branch\":\"feature/login\",\"head_sha\":\"0123456789abcdef0123456789abcdef01234567\",\"base_sha\":\"fedcba9876543210fedcba9876543210fedcba98\",\"env_contract_hash\":null}"
L_ENV_PASS="{$COMMON,\"event\":\"env\",\"step\":\"non_prod_assert\",\"outcome\":\"pass\"}"
L_ENV_FAIL="{$COMMON,\"event\":\"env\",\"step\":\"seed\",\"outcome\":\"fail\",\"reason\":\"prisma db seed exited 1\"}"
L_AUTH="{$COMMON,\"event\":\"auth\",\"state\":\"authenticated\"}"
L_AC_PASS="{$COMMON,\"event\":\"ac\",\"ac_id\":\"AC1\",\"text\":\"Given a registered user, when they log in, then the dashboard loads\",\"scope\":\"ticket\",\"verdict\":\"PASS\",\"classification\":null,\"steps\":[\"open /login\",\"submit valid credentials\"],\"artifacts\":[\"artifacts/AC1/dashboard.png\"]}"
L_AC_FAIL="{$COMMON,\"event\":\"ac\",\"ac_id\":\"AC2\",\"text\":\"Given a wrong password, when submitted, then an error is shown\",\"scope\":\"ticket\",\"verdict\":\"FAIL\",\"classification\":\"REAL_BUG\",\"reason\":\"no error rendered; form silently resets\",\"steps\":[\"open /login\",\"submit wrong password\"],\"artifacts\":[\"artifacts/AC2/after-submit.png\",\"artifacts/AC2/trace.zip\"]}"
L_AC_BLOCKED="$(mut "$L_AC_FAIL" '.ac_id="AC3" | .verdict="BLOCKED" | .classification="ENVIRONMENT_ISSUE" | .reason="seed step failed; fixture user absent"')"
L_AC_NV="$(mut "$L_AC_PASS" '.ac_id="AC4" | .verdict="NOT_VERIFIABLE" | .reason="AC names no observable outcome" | del(.classification)')"
L_ISSUE="{$COMMON,\"event\":\"issue\",\"text\":\"Console error on every page: hydration mismatch\",\"severity\":\"MEDIUM\",\"route\":\"/\",\"artifacts\":[\"artifacts/console.txt\"]}"
L_PAUSE="{$COMMON,\"event\":\"pause\",\"reason\":\"needs_auth: storage state expired\"}"
L_RESUME="{$COMMON,\"event\":\"resume\",\"reason\":\"storage state refreshed\"}"
L_RUN_END="{$COMMON,\"event\":\"run_end\",\"status\":\"completed\"}"

# ============================================================================
echo "== (V1) one valid line per event is accepted =="
expect_accept "(V1) run_start with env_contract_hash null" "$L_RUN_START"
expect_accept "(V1) run_start with a sha env_contract_hash" "$(mut "$L_RUN_START" '.env_contract_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"')"
expect_accept "(V1) env pass (no reason)" "$L_ENV_PASS"
expect_accept "(V1) env fail with reason" "$L_ENV_FAIL"
expect_accept "(V1) env skipped with an optional reason" "$(mut "$L_ENV_PASS" '.step="reset" | .outcome="skipped" | .reason="reset: null in the contract"')"
expect_accept "(V1) auth" "$L_AUTH"
expect_accept "(V1) ac PASS with classification null" "$L_AC_PASS"
expect_accept "(V1) ac PASS with classification absent" "$(mut "$L_AC_PASS" 'del(.classification)')"
expect_accept "(V1) ac PASS with an optional reason" "$(mut "$L_AC_PASS" '.reason="verified on first attempt"')"
expect_accept "(V1) ac FAIL with reason + classification" "$L_AC_FAIL"
expect_accept "(V1) ac BLOCKED with reason + classification" "$L_AC_BLOCKED"
expect_accept "(V1) ac NOT_VERIFIABLE with reason, no classification" "$L_AC_NV"
expect_accept "(V1) ac with empty steps and artifacts" "$(mut "$L_AC_PASS" '.steps=[] | .artifacts=[]')"
expect_accept "(V1) ac scope impact" "$(mut "$L_AC_PASS" '.scope="impact"')"
expect_accept "(V1) issue" "$L_ISSUE"
expect_accept "(V1) issue without the optional route/artifacts" "$(mut "$L_ISSUE" 'del(.route) | del(.artifacts)')"
expect_accept "(V1) pause" "$L_PAUSE"
expect_accept "(V1) resume" "$L_RESUME"
expect_accept "(V1) run_end completed" "$L_RUN_END"
expect_accept "(V1) run_end aborted" "$(mut "$L_RUN_END" '.status="aborted"')"
expect_accept "(V1) ts with fractional seconds" "$(mut "$L_AUTH" '.ts="2026-09-14T10:00:00.123Z"')"

# ============================================================================
echo "== (V2) not_json / not_object =="
expect_reject "(V2) truncated object" not_json '{"schema_version":1,'
expect_reject "(V2) plain word" not_json 'nope'
expect_reject "(V2) empty string" not_json ''
expect_reject "(V2) array root" not_object '[1,2,3]'
expect_reject "(V2) string root" not_object '"a string"'
expect_reject "(V2) number root" not_object '42'
expect_reject "(V2) null root" not_object 'null'

# ============================================================================
echo "== (V3) schema_version_mismatch =="
expect_reject "(V3) schema_version absent" schema_version_mismatch "$(mut "$L_AUTH" 'del(.schema_version)')"
expect_reject "(V3) schema_version 2" schema_version_mismatch "$(mut "$L_AUTH" '.schema_version=2')"
expect_reject "(V3) schema_version \"1\" (string)" schema_version_mismatch "$(mut "$L_AUTH" '.schema_version="1"')"
expect_reject "(V3) schema_version true (bool is not the integer 1)" schema_version_mismatch "$(mut "$L_AUTH" '.schema_version=true')"
expect_reject "(V3) schema_version null" schema_version_mismatch "$(mut "$L_AUTH" '.schema_version=null')"

# ============================================================================
echo "== (V4) missing_key:<k> =="
expect_reject "(V4) ts absent" missing_key:ts "$(mut "$L_AUTH" 'del(.ts)')"
expect_reject "(V4) run_id absent" missing_key:run_id "$(mut "$L_AUTH" 'del(.run_id)')"
expect_reject "(V4) event absent" missing_key:event "$(mut "$L_AUTH" 'del(.event)')"
expect_reject "(V4) run_start.ticket_path absent" missing_key:ticket_path "$(mut "$L_RUN_START" 'del(.ticket_path)')"
expect_reject "(V4) run_start.ticket_kind absent" missing_key:ticket_kind "$(mut "$L_RUN_START" 'del(.ticket_kind)')"
expect_reject "(V4) run_start.branch absent" missing_key:branch "$(mut "$L_RUN_START" 'del(.branch)')"
expect_reject "(V4) run_start.head_sha absent" missing_key:head_sha "$(mut "$L_RUN_START" 'del(.head_sha)')"
expect_reject "(V4) run_start.base_sha absent" missing_key:base_sha "$(mut "$L_RUN_START" 'del(.base_sha)')"
expect_reject "(V4) run_start.env_contract_hash ABSENT (null is legal, absent is not)" missing_key:env_contract_hash "$(mut "$L_RUN_START" 'del(.env_contract_hash)')"
expect_reject "(V4) env.step absent" missing_key:step "$(mut "$L_ENV_PASS" 'del(.step)')"
expect_reject "(V4) env.outcome absent" missing_key:outcome "$(mut "$L_ENV_PASS" 'del(.outcome)')"
expect_reject "(V4) env fail without reason" missing_key:reason "$(mut "$L_ENV_FAIL" 'del(.reason)')"
expect_reject "(V4) env fail with EMPTY reason" missing_key:reason "$(mut "$L_ENV_FAIL" '.reason=""')"
expect_reject "(V4) env fail with null reason" missing_key:reason "$(mut "$L_ENV_FAIL" '.reason=null')"
expect_reject "(V4) auth.state absent" missing_key:state "$(mut "$L_AUTH" 'del(.state)')"
expect_reject "(V4) ac.ac_id absent" missing_key:ac_id "$(mut "$L_AC_PASS" 'del(.ac_id)')"
expect_reject "(V4) ac.text absent" missing_key:text "$(mut "$L_AC_PASS" 'del(.text)')"
expect_reject "(V4) ac.scope absent" missing_key:scope "$(mut "$L_AC_PASS" 'del(.scope)')"
expect_reject "(V4) ac.verdict absent" missing_key:verdict "$(mut "$L_AC_PASS" 'del(.verdict)')"
expect_reject "(V4) ac.steps absent (may be empty, never absent)" missing_key:steps "$(mut "$L_AC_PASS" 'del(.steps)')"
expect_reject "(V4) ac.artifacts absent (may be empty, never absent)" missing_key:artifacts "$(mut "$L_AC_PASS" 'del(.artifacts)')"
expect_reject "(V4) issue.text absent" missing_key:text "$(mut "$L_ISSUE" 'del(.text)')"
expect_reject "(V4) issue.severity absent" missing_key:severity "$(mut "$L_ISSUE" 'del(.severity)')"
expect_reject "(V4) pause without reason" missing_key:reason "$(mut "$L_PAUSE" 'del(.reason)')"
expect_reject "(V4) pause with empty reason" missing_key:reason "$(mut "$L_PAUSE" '.reason=""')"
expect_reject "(V4) resume without reason" missing_key:reason "$(mut "$L_RESUME" 'del(.reason)')"
expect_reject "(V4) resume with null reason" missing_key:reason "$(mut "$L_RESUME" '.reason=null')"
expect_reject "(V4) run_end.status absent" missing_key:status "$(mut "$L_RUN_END" 'del(.status)')"

# ============================================================================
echo "== (V5) bad_type:<k> =="
expect_reject "(V5) ts is a number" bad_type:ts "$(mut "$L_AUTH" '.ts=1757844000')"
expect_reject "(V5) ts is not ISO-8601 UTC" bad_type:ts "$(mut "$L_AUTH" '.ts="14/09/2026 10:00"')"
expect_reject "(V5) ts without the Z suffix" bad_type:ts "$(mut "$L_AUTH" '.ts="2026-09-14T10:00:00+02:00"')"
expect_reject "(V5) run_id is a number" bad_type:run_id "$(mut "$L_AUTH" '.run_id=7')"
expect_reject "(V5) run_id without the verify- prefix" bad_type:run_id "$(mut "$L_AUTH" '.run_id="qa-20260914T100000Z-example"')"
expect_reject "(V5) event is a number" bad_type:event "$(mut "$L_AUTH" '.event=3')"
expect_reject "(V5) run_start.env_contract_hash is a number" bad_type:env_contract_hash "$(mut "$L_RUN_START" '.env_contract_hash=123')"
expect_reject "(V5) run_start.branch is an array" bad_type:branch "$(mut "$L_RUN_START" '.branch=["main"]')"
expect_reject "(V5) env fail with a non-string reason" bad_type:reason "$(mut "$L_ENV_FAIL" '.reason=42')"
expect_reject "(V5) ac.steps is a string, not an array" bad_type:steps "$(mut "$L_AC_PASS" '.steps="open /login"')"
expect_reject "(V5) ac.steps holds a non-string" bad_type:steps "$(mut "$L_AC_PASS" '.steps=[1,2]')"
expect_reject "(V5) ac.artifacts holds a non-string" bad_type:artifacts "$(mut "$L_AC_PASS" '.artifacts=[7]')"
expect_reject "(V5) ac.artifacts holds an ABSOLUTE path" bad_type:artifacts "$(mut "$L_AC_PASS" '.artifacts=["/etc/passwd"]')"
expect_reject "(V5) ac.artifacts holds an empty path" bad_type:artifacts "$(mut "$L_AC_PASS" '.artifacts=[""]')"
expect_reject "(V5) ac.ac_id empty" bad_type:ac_id "$(mut "$L_AC_PASS" '.ac_id=""')"
expect_reject "(V5) ac.classification is a number on FAIL" bad_type:classification "$(mut "$L_AC_FAIL" '.classification=1')"
expect_reject "(V5) ac.reason is a number" bad_type:reason "$(mut "$L_AC_FAIL" '.reason=1')"
expect_reject "(V5) issue.route is a number" bad_type:route "$(mut "$L_ISSUE" '.route=1')"
expect_reject "(V5) issue.artifacts is an object" bad_type:artifacts "$(mut "$L_ISSUE" '.artifacts={}')"
expect_reject "(V5) pause.reason is an array" bad_type:reason "$(mut "$L_PAUSE" '.reason=["x"]')"

# ============================================================================
echo "== (V6) unknown_event =="
expect_reject "(V6) event ac_result" unknown_event "$(mut "$L_AUTH" '.event="ac_result"')"
expect_reject "(V6) event RUN_START (case matters)" unknown_event "$(mut "$L_RUN_START" '.event="RUN_START"')"
expect_reject "(V6) event empty" unknown_event "$(mut "$L_AUTH" '.event=""')"

# ============================================================================
echo "== (V7) unknown_verdict =="
expect_reject "(V7) verdict pass (lower-case)" unknown_verdict "$(mut "$L_AC_PASS" '.verdict="pass"')"
expect_reject "(V7) verdict MAYBE" unknown_verdict "$(mut "$L_AC_PASS" '.verdict="MAYBE"')"
expect_reject "(V7) verdict is a number" bad_type:verdict "$(mut "$L_AC_PASS" '.verdict=1')"

# ============================================================================
echo "== (V8) unknown_enum:<k> =="
expect_reject "(V8) run_start.ticket_kind" unknown_enum:ticket_kind "$(mut "$L_RUN_START" '.ticket_kind="epic"')"
expect_reject "(V8) env.step" unknown_enum:step "$(mut "$L_ENV_PASS" '.step="deploy"')"
expect_reject "(V8) env.outcome" unknown_enum:outcome "$(mut "$L_ENV_PASS" '.outcome="PASS"')"
expect_reject "(V8) auth.state" unknown_enum:state "$(mut "$L_AUTH" '.state="logged_in"')"
expect_reject "(V8) ac.scope" unknown_enum:scope "$(mut "$L_AC_PASS" '.scope="global"')"
expect_reject "(V8) ac.classification on FAIL" unknown_enum:classification "$(mut "$L_AC_FAIL" '.classification="FLAKY"')"
expect_reject "(V8) issue.severity" unknown_enum:severity "$(mut "$L_ISSUE" '.severity="critical"')"
expect_reject "(V8) run_end.status" unknown_enum:status "$(mut "$L_RUN_END" '.status="done"')"

# ============================================================================
echo "== (V9) non_pass_without_reason =="
expect_reject "(V9) FAIL with reason absent" non_pass_without_reason "$(mut "$L_AC_FAIL" 'del(.reason)')"
expect_reject "(V9) FAIL with reason empty" non_pass_without_reason "$(mut "$L_AC_FAIL" '.reason=""')"
expect_reject "(V9) FAIL with reason null" non_pass_without_reason "$(mut "$L_AC_FAIL" '.reason=null')"
expect_reject "(V9) BLOCKED with reason absent" non_pass_without_reason "$(mut "$L_AC_BLOCKED" 'del(.reason)')"
expect_reject "(V9) NOT_VERIFIABLE with reason absent" non_pass_without_reason "$(mut "$L_AC_NV" 'del(.reason)')"
expect_reject "(V9) FAIL with NEITHER reason nor classification reports the reason first" non_pass_without_reason "$(mut "$L_AC_FAIL" 'del(.reason) | del(.classification)')"

# ============================================================================
echo "== (V10) missing_classification =="
expect_reject "(V10) FAIL with reason, classification absent" missing_classification "$(mut "$L_AC_FAIL" 'del(.classification)')"
expect_reject "(V10) FAIL with reason, classification null" missing_classification "$(mut "$L_AC_FAIL" '.classification=null')"
expect_reject "(V10) BLOCKED with reason, classification absent" missing_classification "$(mut "$L_AC_BLOCKED" 'del(.classification)')"

# ============================================================================
echo "== (V11) classification_on_pass =="
expect_reject "(V11) PASS carrying REAL_BUG" classification_on_pass "$(mut "$L_AC_PASS" '.classification="REAL_BUG"')"
expect_reject "(V11) NOT_VERIFIABLE carrying DISCOVERY_GAP" classification_on_pass "$(mut "$L_AC_NV" '.classification="DISCOVERY_GAP"')"
expect_reject "(V11) PASS carrying an out-of-enum classification is still classification_on_pass" classification_on_pass "$(mut "$L_AC_PASS" '.classification="whatever"')"

# ============================================================================
echo "== (V12) run_end_carries_counts =="
expect_reject "(V12) top-level counts" run_end_carries_counts "$(mut "$L_RUN_END" '.counts={"PASS":2,"FAIL":0}')"
expect_reject "(V12) top-level totals" run_end_carries_counts "$(mut "$L_RUN_END" '.totals=2')"
expect_reject "(V12) nested meta.totals" run_end_carries_counts "$(mut "$L_RUN_END" '.meta={"totals":{"PASS":2}}')"
expect_reject "(V12) counts nested inside an array element" run_end_carries_counts "$(mut "$L_RUN_END" '.extra=[{"deep":{"counts":1}}]')"
expect_reject "(V12) counts wins over a bad status (the headline invariant is reported first)" run_end_carries_counts "$(mut "$L_RUN_END" '.status="done" | .counts={}')"

# ============================================================================
echo "== (V13) forward-compat: unknown additive keys are tolerated =="
expect_accept "(V13) ac with an additive key" "$(mut "$L_AC_PASS" '.duration_ms=1200 | .browser="chromium"')"
expect_accept "(V13) run_end with an additive key that is not counts/totals" "$(mut "$L_RUN_END" '.note="clean run" | .meta={"summary_path":"summary.md"}')"
expect_accept "(V13) a key NAMED like counts but on an ac line is tolerated (the rule is run_end-only)" "$(mut "$L_AC_PASS" '.counts=1')"

# ============================================================================
echo "== (V14) file mode =="
FD="$(mktmp)"
printf '%s\n%s\n%s\n' "$L_RUN_START" '{"schema_version":1,"broken' "$L_RUN_END" > "$FD/broken2.jsonl"
run_v "$FD/broken2.jsonl"; rc=$?
[ "$rc" -eq 1 ] && [ "$(out_field '.ok')" = "false" ] && [ "$(out_field '.reason')" = "not_json" ] && [ "$(out_field '.line')" = "2" ] \
  && ok "(V14) 3-line file with line 2 broken → rc 1, reason not_json, \"line\": 2" \
  || no "(V14) broken2: rc=$rc stdout=$(cat "$LAST_OUT")"
printf '%s\n' not_json >> "$SEEN_REASONS"

printf '%s\n\n%s\n' "$L_RUN_START" "$(mut "$L_AC_FAIL" 'del(.reason)')" > "$FD/blank-then-bad.jsonl"
run_v "$FD/blank-then-bad.jsonl"; rc=$?
[ "$rc" -eq 1 ] && [ "$(out_field '.reason')" = "non_pass_without_reason" ] && [ "$(out_field '.line')" = "3" ] \
  && ok "(V14) blank lines are skipped but COUNTED: valid, blank, bad → \"line\": 3" \
  || no "(V14) blank-then-bad: rc=$rc stdout=$(cat "$LAST_OUT")"

printf '%s\n%s\n%s\n' "$L_RUN_START" "$(mut "$L_AC_FAIL" 'del(.reason)')" '{bad' > "$FD/two-bad.jsonl"
run_v "$FD/two-bad.jsonl"; rc=$?
[ "$rc" -eq 1 ] && [ "$(out_field '.reason')" = "non_pass_without_reason" ] && [ "$(out_field '.line')" = "2" ] \
  && ok "(V14) two broken lines → the FIRST (line 2) is reported" \
  || no "(V14) two-bad: rc=$rc stdout=$(cat "$LAST_OUT")"

printf '%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n\n%s\n%s\n' "$L_RUN_START" "$L_ENV_PASS" "$L_ENV_FAIL" "$L_AUTH" "$L_AC_PASS" "$L_AC_FAIL" "$L_ISSUE" "$L_PAUSE" "$L_RESUME" "$L_RUN_END" > "$FD/all-valid.jsonl"
run_v "$FD/all-valid.jsonl"; rc=$?
[ "$rc" -eq 0 ] && [ "$(out_field '.ok')" = "true" ] && [ "$(out_lines)" -eq 1 ] \
  && ok "(V14) all-valid file with interspersed blank lines → rc 0, {\"ok\": true}" \
  || no "(V14) all-valid: rc=$rc stdout=$(cat "$LAST_OUT") stderr=$(cat "$LAST_ERR")"

: > "$FD/empty.jsonl"
run_v "$FD/empty.jsonl"; rc=$?
[ "$rc" -eq 0 ] && [ "$(out_field '.ok')" = "true" ] \
  && ok "(V14) an EMPTY file is valid (0 lines) → rc 0" \
  || no "(V14) empty file: rc=$rc stdout=$(cat "$LAST_OUT")"

printf '%s' "$L_RUN_END" > "$FD/no-trailing-newline.jsonl"
run_v "$FD/no-trailing-newline.jsonl"; rc=$?
[ "$rc" -eq 0 ] && ok "(V14) a file without a trailing newline still validates its last line → rc 0" \
  || no "(V14) no-trailing-newline: rc=$rc stdout=$(cat "$LAST_OUT")"

# ============================================================================
echo "== (V15) exit 2 on usage / unreadable input, stdout EMPTY =="
expect_usage "(V15) no arguments"
expect_usage "(V15) --line without a value" --line
expect_usage "(V15) --line with two values" --line "$L_AUTH" extra
expect_usage "(V15) unknown option" --bogus
expect_usage "(V15) two file paths" "$FD/all-valid.jsonl" "$FD/empty.jsonl"
expect_usage "(V15) missing file" "$FD/does-not-exist.jsonl"
expect_usage "(V15) a directory" "$FD"

# ============================================================================
echo "== (V16) decision shape =="
run_v --line "$(mut "$L_AC_FAIL" 'del(.reason)')"; rc=$?
[ "$rc" -eq 1 ] && [ "$(out_field '.line')" = "null" ] && [ "$(out_field '. | has("line")')" = "true" ] \
  && ok "(V16) line mode reports \"line\": null (key PRESENT, value null)" \
  || no "(V16) line-mode line field: rc=$rc stdout=$(cat "$LAST_OUT")"
printf '%s\n' non_pass_without_reason >> "$SEEN_REASONS"
run_v --line "$L_AUTH"; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$LAST_OUT")" = '{"ok": true}' ] \
  && ok "(V16) the valid decision is exactly {\"ok\": true}" \
  || no "(V16) valid decision shape: $(cat "$LAST_OUT")"
[ ! -s "$LAST_ERR" ] && ok "(V16) a valid line writes nothing to stderr" || no "(V16) stderr noise on a valid line: $(cat "$LAST_ERR")"

# ============================================================================
echo "== (V17) reason-set closure: all 12 AC6 codes provoked, nothing outside the set emitted, both surfaces name them =="
AC6_REASONS="not_json not_object schema_version_mismatch missing_key bad_type unknown_event unknown_verdict unknown_enum non_pass_without_reason missing_classification classification_on_pass run_end_carries_counts"
# Codes whose emitted form carries a `:<k>` suffix.
SUFFIXED="missing_key bad_type unknown_enum"
seen_n="$(grep -c . "$SEEN_REASONS")"
[ "$seen_n" -gt 0 ] && ok "(V17) positive control: $seen_n reasons were recorded by the reject cases" || no "(V17) no reasons recorded — the coverage check below would be vacuous"
missing=""
for code in $AC6_REASONS; do
  case " $SUFFIXED " in
    *" $code "*) hits="$(grep -c "^${code}:[a-z_]*$" "$SEEN_REASONS")" ;;
    *)           hits="$(grep -c "^${code}$" "$SEEN_REASONS")" ;;
  esac
  [ "$hits" -gt 0 ] || missing="$missing $code"
done
[ -z "$missing" ] && ok "(V17) every one of the 12 reason codes was provoked at least once" || no "(V17) reason codes never provoked:$missing"
# Nothing outside the closed set was ever emitted (strip suffixes, then diff against the set).
stray=""
for r in $(sed 's/:.*$//' "$SEEN_REASONS" | LC_ALL=C sort -u); do
  case " $AC6_REASONS " in
    *" $r "*) ;;
    *) stray="$stray $r" ;;
  esac
done
[ -z "$stray" ] && ok "(V17) no reason outside the closed set was emitted" || no "(V17) stray reason codes emitted:$stray"
# The validator's docstring (text before the first `import`) names every code.
DOCSTRING="$ROOT/docstring.txt"
awk '/^import /{exit} {print}' "$VALIDATOR" > "$DOCSTRING"
[ -s "$DOCSTRING" ] || no "(V17) validator docstring extraction is EMPTY (positive control)"
missing=""
for code in $AC6_REASONS; do
  hits="$(grep -c -- "$code" "$DOCSTRING")"; [ "$hits" -gt 0 ] || missing="$missing $code"
done
[ -z "$missing" ] && ok "(V17) the validator docstring lists all 12 reason codes" || no "(V17) docstring omits:$missing"
# The schema section (from `## VERIFY_EVIDENCE` to the next `## ` heading) names every code too.
SECTION="$ROOT/section.md"
awk '/^## VERIFY_EVIDENCE/{on=1; print; next} on && /^## /{exit} on{print}' "$SCHEMA_DOC" > "$SECTION"
[ -s "$SECTION" ] || no "(V17) schema section extraction is EMPTY (positive control)"
missing=""
for code in $AC6_REASONS; do
  hits="$(grep -c -- "\`$code" "$SECTION")"; [ "$hits" -gt 0 ] || missing="$missing $code"
done
[ -z "$missing" ] && ok "(V17) docs/RESULT_SCHEMAS.md §VERIFY_EVIDENCE lists all 12 reason codes" || no "(V17) schema section omits:$missing"
# Enum-value parity: every enum constant the validator holds appears verbatim in the schema section.
missing=""
for val in run_start env auth ac issue pause resume run_end requirement brief non_prod_assert start health seed reset stop pass fail skipped authenticated anonymous needs_auth expired ticket impact PASS FAIL BLOCKED NOT_VERIFIABLE REAL_BUG DISCOVERY_GAP ENVIRONMENT_ISSUE BLOCKING HIGH MEDIUM LOW completed aborted; do
  hits="$(grep -c -w -- "$val" "$SECTION")"; [ "$hits" -gt 0 ] || missing="$missing $val"
done
[ -z "$missing" ] && ok "(V17) every validator enum value appears in the schema section (name parity, one source three surfaces)" || no "(V17) enum values absent from the schema section:$missing"

# ============================================================================
echo "== (V18) static shape of the two deliverables =="
imports="$(grep -E '^(import|from) ' "$VALIDATOR" | awk '{print $2}' | LC_ALL=C sort -u | tr '\n' ' ')"
case "$imports" in
  *result_block_parser*) no "(V18) the validator imports result_block_parser (it must read JSON lines with stdlib only)" ;;
  *) ok "(V18) the validator does not import result_block_parser" ;;
esac
stray=""
for m in $imports; do case "$m" in json|re|sys) ;; *) stray="$stray $m" ;; esac; done
[ -z "$stray" ] && ok "(V18) validator imports are stdlib-only: $imports" || no "(V18) non-stdlib / unexpected imports:$stray"
python3 -m py_compile "$VALIDATOR" 2>"$LAST_ERR" && ok "(V18) the validator byte-compiles" || no "(V18) py_compile failed: $(cat "$LAST_ERR")"
hits="$(grep -c 'exit status\|EXIT STATUS' "$DOCSTRING")"
[ "$hits" -gt 0 ] && ok "(V18) the docstring states the exit-status deviation from the always-exit-0 siblings" || no "(V18) docstring does not state the exit-status deviation"
# Section placement: after ## VERIFY_ENV, before ## Validation Location, each exactly once.
n_env="$(grep -n '^## VERIFY_ENV$' "$SCHEMA_DOC" | cut -d: -f1 | head -1)"
n_evd="$(grep -n '^## VERIFY_EVIDENCE$' "$SCHEMA_DOC" | cut -d: -f1 | head -1)"
n_loc="$(grep -n '^## Validation Location$' "$SCHEMA_DOC" | cut -d: -f1 | head -1)"
c_evd="$(grep -c '^## VERIFY_EVIDENCE$' "$SCHEMA_DOC")"
if [ -n "$n_env" ] && [ -n "$n_evd" ] && [ -n "$n_loc" ] && [ "$c_evd" -eq 1 ] && [ "$n_env" -lt "$n_evd" ] && [ "$n_evd" -lt "$n_loc" ]; then
  ok "(V18) ## VERIFY_EVIDENCE sits once, after ## VERIFY_ENV and before ## Validation Location"
else
  no "(V18) section placement: VERIFY_ENV=$n_env VERIFY_EVIDENCE=$n_evd (count $c_evd) Validation Location=$n_loc"
fi
hits="$(grep -c 'schema_version: 1' "$SECTION")"
[ "$hits" -gt 0 ] && ok "(V18) the section declares schema_version: 1" || no "(V18) the section does not declare schema_version: 1"
hits="$(grep -c '^- \*\*VERIFY_EVIDENCE (schema_version 1)\*\* (2026-09-14):' "$SCHEMA_DOC")"
[ "$hits" -eq 1 ] && ok "(V18) Version History carries the dated VERIFY_EVIDENCE bullet exactly once" || no "(V18) Version History bullet count: $hits"
hits="$(grep -c 'Current versions:.*VERIFY_EVIDENCE at `schema_version: 1`' "$SCHEMA_DOC")"
[ "$hits" -eq 1 ] && ok "(V18) the intro Current versions: line mentions VERIFY_EVIDENCE at schema_version: 1" || no "(V18) Current versions: mention count: $hits"
hits="$(grep -c 'verify-20260914T100000Z-example' "$SECTION")"
[ "$hits" -ge 8 ] && ok "(V18) the frozen example block carries the fixed run_id on every event line ($hits lines)" || no "(V18) frozen example lines with the fixed run_id: $hits"
# The frozen example lines themselves validate (the doc's illustration is a true one).
awk '/^```jsonl$/{on=1; next} on && /^```$/{exit} on{print}' "$SECTION" > "$FD/frozen.jsonl"
run_v "$FD/frozen.jsonl"; rc=$?
[ -s "$FD/frozen.jsonl" ] && [ "$rc" -eq 0 ] \
  && ok "(V18) the schema section's frozen example block validates end-to-end in file mode" \
  || no "(V18) frozen example block: rc=$rc size=$(wc -c < "$FD/frozen.jsonl") stdout=$(cat "$LAST_OUT")"

# --- helper cases (Subtask 2 appends below this line) ---

# ============================================================================
# Helper cases — verify-helpers.sh (the append-only writer + the derived summary). Every mutation
# control (a, b, c) is GATED on "the mutant differs from the original": an edit that matched nothing
# is reported UNPROVEN and counted as a no() — the suite exits 1 on it, never treats an unproven
# mutation as a pass. Fixtures live under mktmp(); statuses are `$?` in the statement after the call.
# ============================================================================
HELPER="$HERE/verify-helpers.sh"
BASH_BIN="$(command -v bash)"
if [ ! -f "$HELPER" ]; then
  no "helper: required file not found at $HELPER"
else
  ok "helper: verify-helpers.sh present"
fi
bash -n "$HELPER" 2>"$LAST_ERR"; rc=$?
[ "$rc" -eq 0 ] && ok "helper: bash -n parses verify-helpers.sh" || no "helper: bash -n rc=$rc: $(cat "$LAST_ERR")"

# run_h <args...> — runs the helper; stdout/stderr into the fixed files; status = the helper's exit status.
run_h() {
  : > "$LAST_OUT"; : > "$LAST_ERR"
  "$BASH_BIN" "$HELPER" "$@" >"$LAST_OUT" 2>"$LAST_ERR"
}
unproven() { no "UNPROVEN: $1 — the mutant is byte-identical to the original (the edit matched nothing)"; }
counts_row() { grep -c -F "$1" "$2/summary.md"; }   # exact-literal count of a counts row (never `|| echo 0`)

RID="verify-20260914T100000Z-t"
# L <event fragment> — a full VERIFY_EVIDENCE line around the fixed common keys
L() { printf '{"schema_version":1,"ts":"2026-09-14T10:00:00Z","run_id":"%s",%s}' "$RID" "$1"; }
# AC <id> <verdict> [classification] [reason] — an `ac` line (classification/reason omitted when empty)
AC() {
  local id="$1" v="$2" cls="${3:-}" why="${4:-}" extra=""
  [ -n "$cls" ] && extra="$extra,\"classification\":\"$cls\""
  [ -n "$why" ] && extra="$extra,\"reason\":\"$why\""
  L "\"event\":\"ac\",\"ac_id\":\"$id\",\"text\":\"t\",\"scope\":\"ticket\",\"verdict\":\"$v\"$extra,\"steps\":[],\"artifacts\":[]"
}
RUN_START="$(L '"event":"run_start","ticket_path":"x.md","ticket_kind":"brief","branch":"b","head_sha":"h","base_sha":"s","env_contract_hash":null')"
ISSUE="$(L '"event":"issue","text":"console error","severity":"LOW"')"

# ----------------------------------------------------------------------------
echo "== (AC1) refusal: FAIL without reason → exit 1, rejected.jsonl wrapped, evidence.jsonl byte-identical =="
D1="$(mktmp)"
run_h evidence-append "$D1" "$(AC AC1 PASS)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$D1/evidence.jsonl" ] && ok "(AC1) a valid PASS line appends (rc 0)" || no "(AC1) valid append rc=$rc stderr=$(cat "$LAST_ERR")"
cp "$D1/evidence.jsonl" "$D1/before.jsonl"
BAD="$(AC AC2 FAIL REAL_BUG)"   # verdict FAIL, classification present, NO reason
run_h evidence-append "$D1" "$BAD"; rc=$?
[ "$rc" -eq 1 ] && ok "(AC1) FAIL-without-reason → rc 1" || no "(AC1) refusal rc=$rc (want 1) stderr=$(cat "$LAST_ERR")"
cmp -s "$D1/before.jsonl" "$D1/evidence.jsonl" && ok "(AC1) evidence.jsonl is byte-identical before and after the refusal" || no "(AC1) evidence.jsonl CHANGED on a refusal"
n="$(grep -c . "$D1/rejected.jsonl" 2>/dev/null)"
[ "$n" -eq 1 ] && ok "(AC1) rejected.jsonl holds exactly one wrapped line" || no "(AC1) rejected.jsonl lines: $n"
jq -c . "$D1/rejected.jsonl" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(AC1) rejected.jsonl is valid JSONL" || no "(AC1) rejected.jsonl is not valid JSONL"
got="$(jq -r '.line' "$D1/rejected.jsonl")"
[ "$got" = "$BAD" ] && ok "(AC1) .line round-trips the raw input verbatim" || no "(AC1) .line=$got"
got="$(jq -r '.reason' "$D1/rejected.jsonl")"
[ "$got" = "non_pass_without_reason" ] && ok "(AC1/AC8) .reason carries the validator's own code (non_pass_without_reason)" || no "(AC1) .reason=$got"
got="$(jq -r '.rejected_at' "$D1/rejected.jsonl")"
case "$got" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ok "(AC1) .rejected_at is ISO-8601 UTC" ;; *) no "(AC1) .rejected_at=$got" ;; esac
hits="$(grep -c 'REFUSED (non_pass_without_reason)' "$LAST_ERR")"
[ "$hits" -eq 1 ] && ok "(AC1) the reason is named on stderr" || no "(AC1) stderr lacks the reason: $(cat "$LAST_ERR")"
# a NOT-JSON input is still recorded as valid JSONL (the wrapper is built with jq --arg)
run_h evidence-append "$D1" 'not json {'; rc=$?
jq -c . "$D1/rejected.jsonl" >/dev/null 2>&1; rc2=$?
got="$(tail -1 "$D1/rejected.jsonl" | jq -r '.reason')"
[ "$rc" -eq 1 ] && [ "$rc2" -eq 0 ] && [ "$got" = "not_json" ] && ok "(AC1) a non-JSON input is refused (not_json) and rejected.jsonl stays valid JSONL" || no "(AC1) non-JSON: rc=$rc jsonl_rc=$rc2 reason=$got"
cmp -s "$D1/before.jsonl" "$D1/evidence.jsonl" && ok "(AC1) evidence.jsonl still byte-identical after a second refusal" || no "(AC1) evidence.jsonl changed on the second refusal"

# ----------------------------------------------------------------------------
echo "== (AC2) summary regenerated on every append; header line =="
D2="$(mktmp)"
run_h evidence-append "$D2" "$RUN_START"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$D2/summary.md" ] && ok "(AC2) summary.md exists after the first successful append" || no "(AC2) summary.md missing after append rc=$rc"
run_h evidence-append "$D2" "$(AC AC1 PASS)"
run_h evidence-append "$D2" "$(AC AC2 FAIL REAL_BUG "no error rendered")"; rc=$?
[ "$rc" -eq 0 ] && ok "(AC2) two distinct ids appended (AC1 PASS, AC2 FAIL)" || no "(AC2) second ac append rc=$rc stderr=$(cat "$LAST_ERR")"
line2="$(sed -n 2p "$D2/summary.md")"
hits="$(printf '%s\n' "$line2" | grep -c -F 'DERIVED by `verify-helpers.sh summary-build`')"
[ "$hits" -eq 1 ] && ok "(AC2) line 2 contains the literal DERIVED by \`verify-helpers.sh summary-build\`" || no "(AC2) line 2 lacks the DERIVED literal: $line2"
hits="$(printf '%s\n' "$line2" | grep -c -F 'do not edit')"
[ "$hits" -eq 1 ] && ok "(AC2) line 2 contains the literal 'do not edit'" || no "(AC2) line 2 lacks 'do not edit': $line2"
case "$line2" in ">"*) ok "(AC2) line 2 is a blockquote" ;; *) no "(AC2) line 2 is not a blockquote: $line2" ;; esac
hits="$(sed -n 1p "$D2/summary.md" | grep -c -F "# Verify run $RID — summary")"
[ "$hits" -eq 1 ] && ok "(AC2) line 1 names the run_id" || no "(AC2) line 1: $(sed -n 1p "$D2/summary.md")"
ROW_TRUE='PASS: 1 · FAIL: 1 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2'
ROW_LIE='PASS: 2 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 2'
hits="$(counts_row "$ROW_TRUE" "$D2")"
[ "$hits" -eq 1 ] && ok "(AC2) counts row reads exactly: $ROW_TRUE" || no "(AC2) counts row hits=$hits: $(grep -n 'total:' "$D2/summary.md")"

echo "== (AC2) mutation control a =="
# Hand-edit the summary to claim 2 PASS / 0 FAIL over a store holding 1 PASS + 1 FAIL; gated on the
# mutant differing from the original; a bare summary-build AND the next append both overwrite it.
cp "$D2/summary.md" "$D2/summary.orig.md"
sed "s/$ROW_TRUE/$ROW_LIE/" "$D2/summary.orig.md" > "$D2/summary.mut.md" && cp "$D2/summary.mut.md" "$D2/summary.md"
if cmp -s "$D2/summary.orig.md" "$D2/summary.md"; then
  unproven "(AC2) mutation control a"
else
  hits="$(counts_row "$ROW_LIE" "$D2")"
  [ "$hits" -eq 1 ] && ok "(AC2) mutant summary now lies: $ROW_LIE" || no "(AC2) mutant does not carry the lie (hits=$hits)"
  run_h summary-build "$D2"; rc=$?
  hits="$(counts_row "$ROW_TRUE" "$D2")"; lies="$(counts_row "$ROW_LIE" "$D2")"
  [ "$rc" -eq 0 ] && [ "$hits" -eq 1 ] && [ "$lies" -eq 0 ] \
    && ok "(AC2) mutation control a: bare summary-build overwrote the hand-edit → $ROW_TRUE" \
    || no "(AC2) mutation control a (summary-build): rc=$rc true=$hits lie=$lies"
  # again via the append path
  cp "$D2/summary.mut.md" "$D2/summary.md"
  cmp -s "$D2/summary.orig.md" "$D2/summary.md" && unproven "(AC2) mutation control a (append path)"
  run_h evidence-append "$D2" "$ISSUE"; rc=$?
  hits="$(counts_row "$ROW_TRUE" "$D2")"; lies="$(counts_row "$ROW_LIE" "$D2")"
  [ "$rc" -eq 0 ] && [ "$hits" -eq 1 ] && [ "$lies" -eq 0 ] \
    && ok "(AC2) mutation control a: the next evidence-append overwrote the hand-edit → $ROW_TRUE" \
    || no "(AC2) mutation control a (append): rc=$rc true=$hits lie=$lies"
fi

# ----------------------------------------------------------------------------
echo "== (AC3) run_end cannot carry counts; 5-AC fixture counts; mutation control b =="
D3="$(mktmp)"
run_h evidence-append "$D3" "$RUN_START"
cp "$D3/evidence.jsonl" "$D3/before.jsonl"
run_h evidence-append "$D3" "$(L '"event":"run_end","status":"completed","counts":{"PASS":1}')"; rc=$?
got="$(tail -1 "$D3/rejected.jsonl" 2>/dev/null | jq -r '.reason')"
[ "$rc" -eq 1 ] && [ "$got" = "run_end_carries_counts" ] && ok "(AC3) run_end with top-level counts → rc 1, run_end_carries_counts" || no "(AC3) counts: rc=$rc reason=$got"
run_h evidence-append "$D3" "$(L '"event":"run_end","status":"completed","meta":{"totals":{"FAIL":0}}')"; rc=$?
got="$(tail -1 "$D3/rejected.jsonl" 2>/dev/null | jq -r '.reason')"
[ "$rc" -eq 1 ] && [ "$got" = "run_end_carries_counts" ] && ok "(AC3) run_end with nested meta.totals → rc 1, run_end_carries_counts" || no "(AC3) nested totals: rc=$rc reason=$got"
cmp -s "$D3/before.jsonl" "$D3/evidence.jsonl" && ok "(AC3) evidence.jsonl unchanged by both refusals" || no "(AC3) evidence.jsonl changed on a counts refusal"
run_h evidence-append "$D3" "$(AC AC1 PASS)"
run_h evidence-append "$D3" "$(AC AC2 PASS)"
run_h evidence-append "$D3" "$(AC AC3 FAIL REAL_BUG "broken")"
run_h evidence-append "$D3" "$(AC AC4 BLOCKED ENVIRONMENT_ISSUE "db down")"
run_h evidence-append "$D3" "$(AC AC5 NOT_VERIFIABLE "" "no UI for it")"; rc=$?
[ "$rc" -eq 0 ] && ok "(AC3) 5-AC fixture appended (2 PASS / 1 FAIL / 1 BLOCKED / 1 NOT_VERIFIABLE)" || no "(AC3) fixture append rc=$rc stderr=$(cat "$LAST_ERR")"
ROW5='PASS: 2 · FAIL: 1 · BLOCKED: 1 · NOT_VERIFIABLE: 1 · total: 5'
run_h summary-build "$D3"; rc=$?
hits="$(counts_row "$ROW5" "$D3")"
[ "$rc" -eq 0 ] && [ "$hits" -eq 1 ] && ok "(AC3) counts row reads exactly: $ROW5" || no "(AC3) counts row hits=$hits rc=$rc: $(grep -n 'total:' "$D3/summary.md")"
# mutation control b — delete the FAIL line; gated on the store actually shrinking
n_before=$(( $(wc -l < "$D3/evidence.jsonl") ))
grep -v '"verdict":"FAIL"' "$D3/evidence.jsonl" > "$D3/evidence.mut.jsonl"
n_after=$(( $(wc -l < "$D3/evidence.mut.jsonl") ))
if [ "$n_after" -eq "$n_before" ]; then
  unproven "(AC3) mutation control b"
else
  cp "$D3/evidence.mut.jsonl" "$D3/evidence.jsonl"
  [ "$n_after" -eq $((n_before - 1)) ] && ok "(AC3) mutant store has exactly one line fewer ($n_before → $n_after)" || no "(AC3) mutant store lines $n_before → $n_after"
  run_h summary-build "$D3"; rc=$?
  ROW4='PASS: 2 · FAIL: 0 · BLOCKED: 1 · NOT_VERIFIABLE: 1 · total: 4'
  hits="$(counts_row "$ROW4" "$D3")"; old="$(counts_row "$ROW5" "$D3")"
  [ "$rc" -eq 0 ] && [ "$hits" -eq 1 ] && [ "$old" -eq 0 ] \
    && ok "(AC3) mutation control b: deleting the FAIL line changes the summary to FAIL: 0 · total: 4" \
    || no "(AC3) mutation control b: rc=$rc new=$hits old=$old: $(grep -n 'total:' "$D3/summary.md")"
fi

# ----------------------------------------------------------------------------
echo "== (AC4) evidence_append() never reads the store; mutation control c =="
extract_body() { awk '/^evidence_append\(\) \{/{on=1; next} on && /^\}/{exit} on{print}' "$1"; }
hits="$(grep -c '^evidence_append() {$' "$HELPER")"
[ "$hits" -eq 1 ] && ok "(AC4) the helper spells 'evidence_append() {' at column 0 exactly once" || no "(AC4) 'evidence_append() {' count: $hits"
hits="$(grep -c '^summary_build() {$' "$HELPER")"
[ "$hits" -eq 1 ] && ok "(AC4) summary_build() is a separate function (the reader)" || no "(AC4) 'summary_build() {' count: $hits"
BODY="$ROOT/ea-body.txt"
extract_body "$HELPER" > "$BODY"
[ -s "$BODY" ] && ok "(AC4) positive control: the extracted function body is non-empty ($(grep -c . "$BODY") lines)" || no "(AC4) extracted body is EMPTY — the awk anchor matched nothing"
n_all="$(grep -c 'evidence\.jsonl' "$BODY")"
[ "$n_all" -eq 1 ] && ok "(AC4) positive control: exactly ONE body line names evidence.jsonl" || no "(AC4) body lines naming evidence.jsonl: $n_all (want 1)"
n_w="$(grep 'evidence\.jsonl' "$BODY" | grep -c '>>')"
[ "$n_w" -eq 1 ] && ok "(AC4) that one line is the >> append" || no "(AC4) evidence.jsonl lines carrying >>: $n_w"
n_r="$(grep 'evidence\.jsonl' "$BODY" | grep -vc '>>')"
[ "$n_r" -eq 0 ] && ok "(AC4) zero body lines name evidence.jsonl without >> (no read)" || no "(AC4) body lines naming evidence.jsonl WITHOUT >>: $n_r"
n_tok="$(grep -cE '(^|[^a-z_])(cat|jq|grep|wc|tail|head|read|sed|awk)([^a-z_]|$)[^#]*evidence\.jsonl|<[^<]*evidence\.jsonl' "$BODY")"
[ "$n_tok" -eq 0 ] && ok "(AC4) no read token (cat/</jq/grep/wc/tail/head/read) has evidence.jsonl as its operand" || no "(AC4) read tokens on evidence.jsonl: $n_tok"
n_cmt="$(grep -c '^[[:space:]]*#.*evidence\.jsonl' "$BODY")"
[ "$n_cmt" -eq 0 ] && ok "(AC4) no comment inside the body names evidence.jsonl" || no "(AC4) comments naming evidence.jsonl inside the body: $n_cmt"
hits="$(grep -c 'mkdir -p' "$BODY")"
[ "$hits" -ge 1 ] && ok "(AC4/AC7) the body creates the run dir (mkdir -p) before the write" || no "(AC4) no mkdir -p in the body"
# mutation control c — a COPY with a read inserted after the mkdir -p; gated on copy-differs + bash -n
MUT="$ROOT/verify-helpers.mut.sh"
awk '{print} on && /mkdir -p/ && !done {print "  cat \"$run_dir/evidence.jsonl\""; done=1} /^evidence_append\(\) \{/{on=1} /^\}/{on=0}' "$HELPER" > "$MUT"
if cmp -s "$HELPER" "$MUT"; then
  unproven "(AC4) mutation control c"
else
  bash -n "$MUT" 2>/dev/null; rc=$?
  if [ "$rc" -ne 0 ]; then
    no "(AC4) mutation control c: the mutant does not parse (bash -n rc=$rc) — control invalid"
  else
    extract_body "$MUT" > "$ROOT/ea-body.mut.txt"
    n_r="$(grep 'evidence\.jsonl' "$ROOT/ea-body.mut.txt" | grep -vc '>>')"
    n_all="$(grep -c 'evidence\.jsonl' "$ROOT/ea-body.mut.txt")"
    [ "$n_r" -eq 1 ] && [ "$n_all" -eq 2 ] \
      && ok "(AC4) mutation control c: the no-read grep FAILS on the copy with a cat inserted (reads=$n_r, total=$n_all)" \
      || no "(AC4) mutation control c: reads=$n_r total=$n_all — the grep did not catch the inserted read"
  fi
fi

# ----------------------------------------------------------------------------
echo "== (AC8) trailer: derived_from N == wc -l, sha256 == shasum, and one more line changes it =="
trailer() { tail -1 "$1/summary.md"; }
run_h summary-build "$D3"
t="$(trailer "$D3")"
n_wc=$(( $(wc -l < "$D3/evidence.jsonl") ))
h_sha="$(shasum -a 256 "$D3/evidence.jsonl" | cut -d' ' -f1)"
[ "$t" = "derived_from: $n_wc lines, sha256 $h_sha" ] && ok "(AC8) trailer is exactly 'derived_from: $n_wc lines, sha256 <shasum -a 256>'" || no "(AC8) trailer=$t want N=$n_wc sha=$h_sha"
run_h evidence-append "$D3" "$ISSUE"; rc=$?
t2="$(trailer "$D3")"
n_wc2=$(( $(wc -l < "$D3/evidence.jsonl") ))
h_sha2="$(shasum -a 256 "$D3/evidence.jsonl" | cut -d' ' -f1)"
[ "$rc" -eq 0 ] && [ "$n_wc2" -eq $((n_wc + 1)) ] && [ "$h_sha2" != "$h_sha" ] && [ "$t2" = "derived_from: $n_wc2 lines, sha256 $h_sha2" ] \
  && ok "(AC8) appending one more line bumps N ($n_wc → $n_wc2) and changes the hash" \
  || no "(AC8) after append: rc=$rc trailer=$t2 N=$n_wc2 sha=$h_sha2 (old $h_sha)"
[ "$t2" != "$t" ] && ok "(AC8) the trailer differs after the append" || no "(AC8) trailer unchanged after an append"

echo "== (AC8) stdin round-trip: evidence-append <run_dir> - =="
D8="$(mktmp)"
LINE="$(AC AC9 PASS)"
: > "$LAST_OUT"; : > "$LAST_ERR"
printf '%s' "$LINE" | "$BASH_BIN" "$HELPER" evidence-append "$D8" - >"$LAST_OUT" 2>"$LAST_ERR"; rc=$?
got="$(tail -1 "$D8/evidence.jsonl" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$got" = "$LINE" ] && ok "(AC8) a record piped on stdin (-) is appended verbatim" || no "(AC8) stdin: rc=$rc got=$got stderr=$(cat "$LAST_ERR")"
n="$(grep -c . "$D8/evidence.jsonl")"
[ "$n" -eq 1 ] && ok "(AC8) stdin append wrote exactly one line" || no "(AC8) stdin append lines: $n"

echo "== (AC8) empty / absent store: summary-build yields the 0-lines trailer with the empty-input hash =="
D9="$(mktmp)"
run_h summary-build "$D9"; rc=$?
t="$(trailer "$D9" 2>/dev/null)"
EMPTY_SHA="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
[ "$rc" -eq 0 ] && [ "$t" = "derived_from: 0 lines, sha256 $EMPTY_SHA" ] && ok "(AC8) absent evidence.jsonl → 'derived_from: 0 lines, sha256 <sha256 of empty input>'" || no "(AC8) empty store: rc=$rc trailer=$t"
hits="$(counts_row 'PASS: 0 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 0' "$D9")"
[ "$hits" -eq 1 ] && ok "(AC8) empty store counts row is all zeros" || no "(AC8) empty store counts row hits=$hits"
line2="$(sed -n 2p "$D9/summary.md")"
hits="$(printf '%s\n' "$line2" | grep -c -F 'do not edit')"
[ "$hits" -eq 1 ] && ok "(AC8) empty store summary still carries the DERIVED header" || no "(AC8) empty store line 2: $line2"
: > "$D9/evidence.jsonl"
run_h summary-build "$D9"; rc=$?
t="$(trailer "$D9")"
[ "$rc" -eq 0 ] && [ "$t" = "derived_from: 0 lines, sha256 $EMPTY_SHA" ] && ok "(AC8) an EMPTY evidence.jsonl yields the same 0-lines trailer" || no "(AC8) empty file: rc=$rc trailer=$t"
n="$(ls "$D9" | grep -c 'summary\.md\.tmp')"
[ "$n" -eq 0 ] && ok "(AC8) run_dir holds no summary temp files" || no "(AC8) leftover temp files: $n"

# ----------------------------------------------------------------------------
echo "== (AC7) run-id shape + slug normalisation; run_dir auto-created with artifacts/ =="
run_h run-id 'My Ticket!'; rc=$?
got="$(cat "$LAST_OUT")"
m="$(printf '%s\n' "$got" | grep -Ec '^verify-[0-9]{8}T[0-9]{6}Z-[a-z0-9-]+$')"
if [ "$rc" -eq 0 ] && [ "$m" -eq 1 ]; then
  ok "(AC7) run-id matches ^verify-[0-9]{8}T[0-9]{6}Z-[a-z0-9-]+$ ($got)"
else
  no "(AC7) run-id rc=$rc out=$got"
fi
case "$got" in *-my-ticket) ok "(AC7) slug 'My Ticket!' → 'my-ticket' (lower-cased, run collapsed, trailing - trimmed)" ;; *) no "(AC7) slug: $got" ;; esac
n="$(grep -c . "$LAST_OUT")"
[ "$n" -eq 1 ] && ok "(AC7) run-id prints exactly one line" || no "(AC7) run-id stdout lines: $n"
run_h run-id '--Foo__Bar--'; got="$(cat "$LAST_OUT")"
case "$got" in *-foo-bar) ok "(AC7) slug '--Foo__Bar--' → 'foo-bar'" ;; *) no "(AC7) slug: $got" ;; esac
run_h run-id; rc=$?
[ "$rc" -eq 2 ] && [ ! -s "$LAST_OUT" ] && ok "(AC7) run-id without a slug → rc 2, empty stdout" || no "(AC7) run-id no-arg rc=$rc"
D7="$(mktmp)/nested/run"
[ ! -d "$D7" ] && ok "(AC7) precondition: run_dir does not exist yet" || no "(AC7) precondition failed"
run_h evidence-append "$D7" "$(AC AC1 PASS)"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$D7/artifacts" ] && [ -f "$D7/evidence.jsonl" ] && [ -f "$D7/summary.md" ] \
  && ok "(AC7) evidence-append creates <run_dir>/ and <run_dir>/artifacts/ before the write" \
  || no "(AC7) auto-create: rc=$rc artifacts=$([ -d "$D7/artifacts" ] && echo y || echo n)"
run_h evidence-append; rc=$?
[ "$rc" -eq 2 ] && ok "(AC7) evidence-append without args → rc 2 (usage)" || no "(AC7) usage rc=$rc"
run_h bogus-subcommand; rc=$?
[ "$rc" -eq 1 ] && ok "(AC7) unknown subcommand → rc 1" || no "(AC7) unknown subcommand rc=$rc"
run_h --help; rc=$?
n="$(grep -c -E '^  (run-id|evidence-append|summary-build) ' "$LAST_OUT")"
[ "$rc" -eq 0 ] && [ "$n" -eq 3 ] && ok "(AC7) --help lists the three subcommands" || no "(AC7) --help rc=$rc listed=$n"

# ----------------------------------------------------------------------------
echo "== (AC8) latest-per-ac_id: AC1 PASS then AC1 FAIL → PASS: 0 · FAIL: 1 · total: 1 =="
D10="$(mktmp)"
run_h evidence-append "$D10" "$(AC AC1 PASS)"
run_h evidence-append "$D10" "$(AC AC1 FAIL REAL_BUG "regressed on retry")"; rc=$?
hits="$(counts_row 'PASS: 0 · FAIL: 1 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 1' "$D10")"
[ "$rc" -eq 0 ] && [ "$hits" -eq 1 ] && ok "(AC8) the newest ac line per ac_id wins the count" || no "(AC8) latest-per-ac_id: rc=$rc hits=$hits: $(grep -n 'total:' "$D10/summary.md")"
n="$(grep -c . "$D10/evidence.jsonl")"
[ "$n" -eq 2 ] && ok "(AC8) both lines stay in the store as history (append-only)" || no "(AC8) store lines: $n"
n="$(grep -c '^| AC1 |' "$D10/summary.md")"
[ "$n" -eq 1 ] && ok "(AC8) the per-AC table shows AC1 once" || no "(AC8) AC1 table rows: $n"
n="$(grep -c '^| AC1 | ticket | FAIL | REAL_BUG | regressed on retry |' "$D10/summary.md")"
[ "$n" -eq 1 ] && ok "(AC8) …and that row is the FAIL (latest) line" || no "(AC8) AC1 row is not the FAIL line"

# ----------------------------------------------------------------------------
echo "== (AC8) python3 absent on PATH → refused (validator_unavailable), line in rejected.jsonl =="
STUB="$ROOT/stub-bin"; mkdir -p "$STUB"
for t in jq date mkdir mv cat cut dirname tr sed wc shasum sha256sum grep cp; do
  p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -s "$p" "$STUB/$t"
done
PATH="$STUB" "$BASH_BIN" -c 'command -v python3' >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "(AC8) positive control: python3 is NOT resolvable on the stub PATH" || no "(AC8) stub PATH still resolves python3 — control invalid"
PATH="$STUB" "$BASH_BIN" -c 'command -v jq' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(AC8) positive control: jq IS resolvable on the stub PATH" || no "(AC8) stub PATH lacks jq — control invalid"
D11="$(mktmp)"
GOOD="$(AC AC1 PASS)"
: > "$LAST_OUT"; : > "$LAST_ERR"
PATH="$STUB" "$BASH_BIN" "$HELPER" evidence-append "$D11" "$GOOD" >"$LAST_OUT" 2>"$LAST_ERR"; rc=$?
got="$(jq -r '.reason' "$D11/rejected.jsonl" 2>/dev/null)"
[ "$rc" -eq 1 ] && [ "$got" = "validator_unavailable" ] && ok "(AC8) a VALID line is refused when python3 is absent (rc 1, validator_unavailable)" || no "(AC8) python3-absent: rc=$rc reason=$got stderr=$(cat "$LAST_ERR")"
[ ! -f "$D11/evidence.jsonl" ] && ok "(AC8) nothing reached evidence.jsonl without the validator" || no "(AC8) evidence.jsonl was written with the validator absent"
got="$(jq -r '.line' "$D11/rejected.jsonl" 2>/dev/null)"
[ "$got" = "$GOOD" ] && ok "(AC8) the refused (valid) line is preserved verbatim in rejected.jsonl" || no "(AC8) rejected .line=$got"
# the same line appends fine with python3 back on PATH — the refusal was the missing validator, not the line
run_h evidence-append "$D11" "$GOOD"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$D11/evidence.jsonl" ] && ok "(AC8) the same line appends once python3 is available again" || no "(AC8) re-append rc=$rc"

# ----------------------------------------------------------------------------
echo "== (AC9) the helper locates its validator as a sibling (vendor-neutral core) =="
# The zero-vendor-token claim itself is owned by the root ratchet (scripts/check-vendor-coupling.sh),
# which scans this file and the helper as core — spelling the tokens here would trip it.
n="$(grep -c 'validate-verify-evidence.py' "$HELPER")"
[ "$n" -ge 1 ] && ok "(AC9) the validator is located as a sibling of the helper" || no "(AC9) the helper does not name the validator"

# ----------------------------------------------------------------------------
echo "== (R1) review iteration 1 — the post-validate path may neither corrupt nor misreport a stored fact =="
# (R1a) a pretty-printed record (jq's DEFAULT output shape, no -c) is ONE physical line once stored.
# `json.loads` tolerates inter-token newlines, so the validator alone would let N lines through for one fact.
PRETTY="$(printf '%s' "$(AC AC1 PASS)" | jq .)"   # multi-line by construction
n_in=$(( $(printf '%s\n' "$PRETTY" | wc -l) ))
[ "$n_in" -gt 1 ] && ok "(R1a) positive control: the pretty-printed input spans $n_in physical lines" || no "(R1a) control invalid: pretty input is $n_in line(s)"
D12="$(mktmp)"
: > "$LAST_OUT"; : > "$LAST_ERR"
printf '%s\n' "$PRETTY" | "$BASH_BIN" "$HELPER" evidence-append "$D12" - >"$LAST_OUT" 2>"$LAST_ERR"; rc=$?
[ "$rc" -eq 0 ] && ok "(R1a) the pretty-printed record is accepted (rc 0)" || no "(R1a) rc=$rc stderr=$(cat "$LAST_ERR")"
n=$(( $(wc -l < "$D12/evidence.jsonl") ))
[ "$n" -eq 1 ] && ok "(R1a) evidence.jsonl holds exactly ONE physical line for the one fact" || no "(R1a) evidence.jsonl physical lines: $n (want 1)"
python3 "$VALIDATOR" "$D12/evidence.jsonl" >"$LAST_OUT" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "(R1a) the store re-validates in file mode (rc 0)" || no "(R1a) file-mode re-validation rc=$rc: $(cat "$LAST_OUT")"
hits="$(grep -c '^derived_from: 1 lines, ' "$D12/summary.md")"
[ "$hits" -eq 1 ] && ok "(R1a) trailer reports derived_from: 1 lines" || no "(R1a) trailer: $(tail -1 "$D12/summary.md")"
stored="$(cat "$D12/evidence.jsonl")"
[ "$stored" = "$(printf '%s' "$PRETTY" | jq -c .)" ] && ok "(R1a) the stored line is the compact form of the input" || no "(R1a) stored=$stored"
jq -e -n --argjson a "$stored" --argjson b "$PRETTY" '$a == $b' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(R1a) compaction is value-preserving (stored == input as JSON)" || no "(R1a) stored value differs from the input"
hits="$(grep -c 'PASS: 1 · FAIL: 0 · BLOCKED: 0 · NOT_VERIFIABLE: 0 · total: 1' "$D12/summary.md")"
[ "$hits" -eq 1 ] && ok "(R1a) the derived counts row sees ONE fact, not N fragments" || no "(R1a) counts row missing/wrong in summary.md"
# a trailing CR (CRLF producer) is whitespace to json.loads and would otherwise be stored inside the line
D13="$(mktmp)"
: > "$LAST_OUT"; : > "$LAST_ERR"
printf '%s\r\n' "$(AC AC1 PASS)" | "$BASH_BIN" "$HELPER" evidence-append "$D13" - >"$LAST_OUT" 2>"$LAST_ERR"; rc=$?
n_cr="$(tr -cd '\r' < "$D13/evidence.jsonl" | wc -c | tr -d ' ')"
[ "$rc" -eq 0 ] && [ "$n_cr" -eq 0 ] && ok "(R1a) a CRLF-terminated record is stored with no CR byte (rc 0)" || no "(R1a) CRLF: rc=$rc CR bytes in store=$n_cr"

# (R1b) the refusal path is untouched by compaction: the RAW (pretty) input round-trips into rejected.jsonl
D14="$(mktmp)"
BAD_PRETTY="$(printf '%s' "$(AC AC2 FAIL REAL_BUG)" | jq .)"   # FAIL without reason, pretty-printed
: > "$LAST_OUT"; : > "$LAST_ERR"
printf '%s\n' "$BAD_PRETTY" | "$BASH_BIN" "$HELPER" evidence-append "$D14" - >"$LAST_OUT" 2>"$LAST_ERR"; rc=$?
[ "$rc" -eq 1 ] && ok "(R1b) a pretty-printed INVALID record is still refused (rc 1)" || no "(R1b) rc=$rc"
got="$(jq -r '.line' "$D14/rejected.jsonl" 2>/dev/null)"
[ "$got" = "$BAD_PRETTY" ] && ok "(R1b) rejected.jsonl .line carries the RAW pretty-printed input verbatim (not the compact form)" || no "(R1b) .line=$got"
got="$(jq -r '.reason' "$D14/rejected.jsonl" 2>/dev/null)"
[ "$got" = "non_pass_without_reason" ] && ok "(R1b) .reason is the validator's own code" || no "(R1b) .reason=$got"
[ ! -f "$D14/evidence.jsonl" ] && ok "(R1b) nothing reached evidence.jsonl on the refusal" || no "(R1b) evidence.jsonl was created on a refusal"
# two concatenated JSON values are NOT split into two facts — refused as not_json, the store untouched
D15="$(mktmp)"
TWO="$(AC AC1 PASS) $(AC AC2 PASS)"
run_h evidence-append "$D15" "$TWO"; rc=$?
got="$(jq -r '.reason' "$D15/rejected.jsonl" 2>/dev/null)"
[ "$rc" -eq 1 ] && [ "$got" = "not_json" ] && [ ! -f "$D15/evidence.jsonl" ] && ok "(R1b) two concatenated JSON values are refused as one not_json input, never stored as two facts" || no "(R1b) concatenated: rc=$rc reason=$got store_exists=$([ -f "$D15/evidence.jsonl" ] && echo yes || echo no)"
got="$(jq -r '.line' "$D15/rejected.jsonl" 2>/dev/null)"
[ "$got" = "$TWO" ] && ok "(R1b) the concatenated raw input round-trips verbatim" || no "(R1b) .line=$got"

# (R1c) a summary derivation failure after a SUCCESSFUL append exits 0 and names the failure — never a
# fake refusal (a caller retrying on rc 1 would replay the append and duplicate the fact).
D16="$(mktmp)"
printf 'this is not json\n' > "$D16/evidence.jsonl"   # a corrupt store: jq -s cannot parse it
GOOD="$(AC AC1 PASS)"
run_h evidence-append "$D16" "$GOOD"; rc=$?
[ "$rc" -eq 0 ] && ok "(R1c) a valid append onto a corrupt store exits 0 (the fact IS stored)" || no "(R1c) rc=$rc (want 0) stderr=$(cat "$LAST_ERR")"
n=$(( $(wc -l < "$D16/evidence.jsonl") ))
[ "$n" -eq 2 ] && ok "(R1c) the store grew by exactly one line" || no "(R1c) store lines: $n (want 2)"
[ "$(tail -1 "$D16/evidence.jsonl")" = "$GOOD" ] && ok "(R1c) the appended fact is the last line, intact" || no "(R1c) last line=$(tail -1 "$D16/evidence.jsonl")"
hits="$(grep -c 'summary-build failed after a successful append' "$LAST_ERR")"
[ "$hits" -eq 1 ] && ok "(R1c) stderr names the derivation failure" || no "(R1c) stderr lacks the derivation-failure line: $(cat "$LAST_ERR")"
hits="$(grep -c 'summary-build: jq could not derive' "$LAST_ERR")"
[ "$hits" -eq 1 ] && ok "(R1c) stderr carries summary-build's own reason (jq could not derive)" || no "(R1c) stderr lacks summary-build's reason: $(cat "$LAST_ERR")"
[ ! -f "$D16/summary.md" ] && ok "(R1c) no summary.md is written from a corrupt store" || no "(R1c) summary.md exists despite the derivation failure"
[ ! -f "$D16/rejected.jsonl" ] && ok "(R1c) nothing was recorded as a refusal (the append succeeded)" || no "(R1c) rejected.jsonl exists after a successful append"
# ...and a genuine WRITE failure is still fatal (rc 1, nothing stored) — the subshell guards derivation only
D17="$(mktmp)"; mkdir -p "$D17/evidence.jsonl"   # the store path is a DIRECTORY: `>>` cannot open it
run_h evidence-append "$D17" "$GOOD"; rc=$?
hits="$(grep -c 'append failed' "$LAST_ERR")"
[ "$rc" -eq 1 ] && [ "$hits" -eq 1 ] && ok "(R1c) a genuine write failure is still fatal (rc 1, 'append failed' on stderr)" || no "(R1c) write failure: rc=$rc stderr=$(cat "$LAST_ERR")"

# Mutants d/e are RUN (control c is only grepped), and the helper locates its validator as a sibling
# of $0 — so the mutant dir needs a copy of the validator or every append is refused as
# `validator_error:2`, which would look like "the mutant exited 1" without exercising the defect.
MUT_DIR="$ROOT/mut"; mkdir -p "$MUT_DIR"; cp "$VALIDATOR" "$MUT_DIR/validate-verify-evidence.py"
# mutation control d — a COPY with the subshell removed: the same corrupt-store append must exit 1
# (the defect this case exists to catch). Gated on copy-differs + bash -n + "the fact WAS stored"
# (so a mutant refused for an unrelated reason cannot pass as the defect).
MUT_D="$MUT_DIR/verify-helpers.mut-d.sh"
awk '{ if (!done && index($0, "( summary_build \"$run_dir\" )")) { sub(/\( summary_build "\$run_dir" \)/, "summary_build \"$run_dir\""); done=1 } print }' "$HELPER" > "$MUT_D"
if cmp -s "$HELPER" "$MUT_D"; then
  unproven "(R1c) mutation control d"
else
  bash -n "$MUT_D" 2>/dev/null; rc=$?
  if [ "$rc" -ne 0 ]; then
    no "(R1c) mutation control d: the mutant does not parse (bash -n rc=$rc) — control invalid"
  else
    D18="$(mktmp)"; printf 'this is not json\n' > "$D18/evidence.jsonl"
    "$BASH_BIN" "$MUT_D" evidence-append "$D18" "$GOOD" >/dev/null 2>"$LAST_ERR"; rc=$?
    n=$(( $(wc -l < "$D18/evidence.jsonl") ))
    [ ! -f "$D18/rejected.jsonl" ] && [ "$n" -eq 2 ] && ok "(R1c) mutation control d: positive control — the mutant DID store the fact (no refusal, store +1)" || no "(R1c) mutation control d: control invalid — refusal=$([ -f "$D18/rejected.jsonl" ] && jq -r .reason "$D18/rejected.jsonl") lines=$n"
    hits="$(grep -c 'summary-build: jq could not derive' "$LAST_ERR")"
    [ "$rc" -eq 1 ] && [ "$hits" -eq 1 ] \
      && ok "(R1c) mutation control d: without the subshell the SAME successful append exits 1 — the case detects the defect" \
      || no "(R1c) mutation control d: rc=$rc derive_msgs=$hits — the mutant did not reproduce the fake refusal"
  fi
fi
# mutation control e — a COPY that skips compaction (line="$json"): the pretty input lands as N lines.
MUT_E="$MUT_DIR/verify-helpers.mut-e.sh"
awk '{ if (!done && index($0, "jq -cs ")) { print "  line=\"$json\""; done=1; next } print }' "$HELPER" > "$MUT_E"
if cmp -s "$HELPER" "$MUT_E"; then
  unproven "(R1a) mutation control e"
else
  bash -n "$MUT_E" 2>/dev/null; rc=$?
  if [ "$rc" -ne 0 ]; then
    no "(R1a) mutation control e: the mutant does not parse (bash -n rc=$rc) — control invalid"
  else
    D19="$(mktmp)"
    printf '%s\n' "$PRETTY" | "$BASH_BIN" "$MUT_E" evidence-append "$D19" - >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 0 ] && [ ! -f "$D19/rejected.jsonl" ] && ok "(R1a) mutation control e: positive control — the mutant accepted the record (rc 0, no refusal)" || no "(R1a) mutation control e: control invalid — rc=$rc refusal=$([ -f "$D19/rejected.jsonl" ] && jq -r .reason "$D19/rejected.jsonl")"
    n=$(( $(wc -l < "$D19/evidence.jsonl" 2>/dev/null) ))
    [ "$rc" -eq 0 ] && [ "$n" -eq "$n_in" ] \
      && ok "(R1a) mutation control e: without compaction the pretty record is stored as $n physical lines (rc 0) — the case detects the defect" \
      || no "(R1a) mutation control e: rc=$rc lines=$n (expected $n_in) — the mutant did not reproduce the multi-line store"
  fi
fi

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
