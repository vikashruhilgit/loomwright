#!/usr/bin/env bash
# test-result-validators.sh (selvedge) — self-tests for validate-qa-result.py.
#
# PROVENANCE: this is the QA arm of loomwright's test-result-validators.sh,
# MOVED here (not copied) when the QA subsystem was relocated into selvedge.
# A plugin's tests belong with the plugin; CI's hard-gate loop already runs
# every plugin's scripts/test-*.sh. Loomwright's suite keeps the other four
# validators and does NOT reach cross-plugin for this one.
#
# DETERMINISTIC, NO LIVE SIDE EFFECTS. Every case feeds a synthesized
# SubagentStop payload to the validator and asserts on its stdout JSON and its
# exit code. The committed fixture lives in result-validator-fixtures/;
# negative variants are synthesized in-harness so each reads next to the rule
# it falsifies.
#
# SECTION C IS LOAD-BEARING, NOT CEREMONY. validate-qa-result.py imports
# `result_block_parser` — a LOOMWRIGHT-OWNED single-copy asset deliberately not
# duplicated into selvedge. The validator's import guard fails SAFE (ok:true,
# exit 0) when that module cannot be resolved, so a BROKEN cross-plugin
# resolution would leave every ok:true assertion in section A green while the
# hook validated nothing. Section C asserts the negative directly: a
# block-free probe must be REJECTED, which is only possible once the module
# genuinely imported.
#
# EXIT: 0 on full pass, 1 on any failed assertion.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXDIR="$SCRIPT_DIR/result-validator-fixtures"

V_QA="$SCRIPT_DIR/validate-qa-result.py"

for f in "$V_QA" "$FIXDIR/qa-result-valid.md"; do
  if [ ! -e "$f" ]; then
    echo "FATAL  required file not found: $f" >&2
    exit 1
  fi
done
if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL  python3 required to run this suite" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
ok() { echo "  ok: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
no() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMPROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPROOT" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# SANDBOX is the cwd the validator runs in. QA_RESULT has no on-disk evidence
# tier, so an empty dir is correct and deliberately vouches for nothing.
SANDBOX="$TMPROOT/sandbox"
mkdir -p "$SANDBOX"

GARBAGE="$TMPROOT/garbage.txt"
printf 'not { valid json at all' > "$GARBAGE"

# ── helpers (lifted verbatim from the loomwright suite this arm came from) ───

F=""
# mk <name> — read a heredoc from stdin into $TMPROOT/<name>; sets $F.
mk() { F="$TMPROOT/$1"; cat > "$F"; }

# cat_mk <name> <base-file> — base file + heredoc from stdin; sets $F.
# text_payload <textfile> — wrap agent output text in a realistic SubagentStop
# payload (the `last_assistant_message` rung of the extraction ladder).
text_payload() {
  python3 -c 'import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    text = fh.read()
sys.stdout.write(json.dumps({
    "session_id": "test-result-validators",
    "hook_event_name": "SubagentStop",
    "agent_type": "test",
    "last_assistant_message": text,
}))' "$1"
}

LAST_OUT=""
LAST_RC=""

# run_v <validator> <textfile> [cwd] — run a validator over wrapped text.
#
# THE PAYLOAD IS MATERIALISED TO A FILE AND REDIRECTED, NEVER PIPED. Piping it
# made this helper intermittently report a FALSE failure, and the mechanism is
# worth recording because it looks like a validator bug and is not:
# the import-guard paths (sections J's ABSENT / CORRUPT module cases) fail
# before any stdin read and `os._exit(0)` immediately, so the writing process
# gets EPIPE on a payload larger than the pipe buffer, dies with rc 1/120, and
# `set -o pipefail` promotes THAT to the pipeline's status. The validator's own
# verdict and exit code were correct every time; only the harness lied. Observed
# as a one-off `exit 120, expected 0` and reproduced deterministically at a
# 200KB payload. A file redirect has no writer to break.
run_v() {
  local validator="$1" textfile="$2" wd="${3:-$SANDBOX}"
  text_payload "$textfile" > "$TMPROOT/.payload.json"
  LAST_OUT="$( ( cd "$wd" && python3 "$validator" < "$TMPROOT/.payload.json" ) 2>/dev/null)"
  LAST_RC=$?
}

# run_raw <validator> <stdin-file> [cwd] — feed a file straight to stdin
# (used for the garbage-payload cases, where the input is NOT valid JSON).
run_raw() {
  local validator="$1" stdinfile="$2" wd="${3:-$SANDBOX}"
  LAST_OUT="$( ( cd "$wd" && python3 "$validator" < "$stdinfile" ) 2>/dev/null)"
  LAST_RC=$?
}

json_ok() {
  printf '%s' "$LAST_OUT" | python3 -c 'import json,sys
try:
    print("true" if json.load(sys.stdin).get("ok") is True else "false")
except Exception:
    print("PARSE_ERROR")'
}

json_reason() {
  printf '%s' "$LAST_OUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("reason", ""))
except Exception:
    print("")'
}

# assert_pass <label> — the last run decided ok:true and exited 0.
assert_pass() {
  local label="$1"
  if [ "$LAST_RC" != "0" ]; then
    no "$label  (exit $LAST_RC, expected 0)"
    return
  fi
  if [ "$(json_ok)" = "true" ]; then
    ok "$label"
  else
    no "$label  expected ok:true, got: $LAST_OUT"
  fi
}

# assert_fail <label> [reason-substring] — ok:false, exit 0, reason matches.
assert_fail() {
  local label="$1" needle="${2:-}" reason
  if [ "$LAST_RC" != "0" ]; then
    no "$label  (exit $LAST_RC, expected 0 — validators are exit-0-by-contract)"
    return
  fi
  if [ "$(json_ok)" != "false" ]; then
    no "$label  expected ok:false, got: $LAST_OUT"
    return
  fi
  if [ -n "$needle" ]; then
    reason="$(json_reason)"
    case "$reason" in
      *"$needle"*) ok "$label" ;;
      *) no "$label  reason did not mention '$needle'; got: $reason" ;;
    esac
  else
    ok "$label"
  fi
}
# ── E. qa-executor validator ─────────────────────────────────────────────────
echo "== E. validate-qa-result.py — 5 rules =="

run_v "$V_QA" "$FIXDIR/qa-result-valid.md"
assert_pass "qa: valid block (committed fixture)"

mk qa-no-block.md <<'EOF'
Ran the tests, everything passed, but no result block was emitted.
EOF
run_v "$V_QA" "$F"
assert_fail "qa: MISSING block" "missing QA_RESULT block"

run_raw "$V_QA" "$GARBAGE"
assert_pass "qa: malformed (non-JSON) payload -> ok:true"

mk qa-malformed.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: passed
  files_created: [a.spec.ts
  tests_generated: 1
  tests_passed: 1
  coverage_estimate: 0.5
  summary: broken flow array
EOF
run_v "$V_QA" "$F"
assert_fail "qa: malformed BLOCK body -> explicit parse failure" "could not be parsed"

mk qa-missing-key.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: passed
  tests_generated: 5
  coverage_estimate: 0.6
  summary: tests_passed is absent
EOF
run_v "$V_QA" "$F"
assert_fail "qa: MISSING required key (tests_passed) [rule 2]" "missing the tests_passed field"

mk qa-null-key.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: passed
  tests_generated: 5
  tests_passed:
  coverage_estimate: 0.6
  summary: tests_passed is EXPLICITLY null
EOF
run_v "$V_QA" "$F"
assert_fail "qa: EXPLICIT-NULL required key (tests_passed:) [rule 2]" "must be an integer"

mk qa-sv.md <<'EOF'
QA_RESULT:
  schema_version: 2
  status: passed
  tests_generated: 0
  tests_passed: 0
  summary: wrong schema version
EOF
run_v "$V_QA" "$F"
assert_fail "qa: schema_version != 1 [rule 1]" "must be the integer 1"

mk qa-no-summary.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: skipped
  tests_generated: 0
  tests_passed: 0
EOF
run_v "$V_QA" "$F"
assert_fail "qa: MISSING summary [rule 3]" "(rule 3)"

mk qa-no-coverage.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: passed
  tests_generated: 12
  tests_passed: 12
  summary: 12 tests run but coverage_estimate is absent
EOF
run_v "$V_QA" "$F"
assert_fail "qa: CROSS-FIELD tests_generated>0 without coverage_estimate [rule 4]" \
  "coverage_estimate must be present"

mk qa-null-coverage.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: passed
  tests_generated: 12
  tests_passed: 12
  coverage_estimate:
  summary: coverage_estimate is present but EXPLICITLY null
EOF
run_v "$V_QA" "$F"
assert_fail "qa: EXPLICIT-NULL coverage_estimate with tests run [rule 4]" "present but null"

mk qa-zero-tests.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: plan_created
  tests_generated: 0
  tests_passed: 0
  summary: plan-only session, no tests run, so no coverage_estimate is required
EOF
run_v "$V_QA" "$F"
assert_pass "qa: tests_generated=0 does not require coverage_estimate [rule 4]"

mk qa-bad-status.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: green
  tests_generated: 0
  tests_passed: 0
  summary: out-of-enum status
EOF
run_v "$V_QA" "$F"
assert_fail "qa: out-of-enum status [rule 5]" "(rule 5)"

for st in passed failed partial skipped needs_human plan_created all_scopes_completed; do
  mk qa-status.md <<EOF
QA_RESULT:
  schema_version: 1
  status: $st
  tests_generated: 0
  tests_passed: 0
  summary: enum probe for $st
EOF
  run_v "$V_QA" "$F"
  assert_pass "qa: status '$st' accepted [rule 5]"
done

# --- FINDING 7 (second validator): the SPURIOUS-REJECT half of the defect ----
# Worker showed the fail-OPEN half. Here is the other half on a different
# schema: QA's status IS enum-checked, so a polluted `passed  # all green`
# tripped rule 5 and REJECTED a conforming block. Both halves come from the one
# parser defect, which is why the fix is in the parser and not in any validator.
mk qa-c7-comment.md <<'EOF'
QA_RESULT:
  schema_version: 1  # v1
  status: passed  # all green
  tests_generated: 4  # four scenarios
  tests_passed: 4
  coverage_estimate: 0.82  # rough
  summary: "a conforming block that annotates itself, including a # in quotes"
EOF
run_v "$V_QA" "$F"
assert_pass "qa: [FALSIFIES] trailing comments no longer cause a spurious reject"

mk qa-c7-control.md <<'EOF'
QA_RESULT:
  schema_version: 1
  status: passed#green
  tests_generated: 0
  tests_passed: 0
  summary: a '#' with no preceding whitespace is part of the value, so this is out-of-enum
EOF
run_v "$V_QA" "$F"
assert_fail "qa: [CONTROL] a '#' with no preceding whitespace is NOT a comment [rule 5]" \
  "(rule 5)"

# ── B. exit-0-by-contract (R3) ───────────────────────────────────────────────
# A validator wired as `type: command` under `|| true` that exits non-zero is a
# SILENTLY DEAD validator — the shell swallows the status and the hook reports
# nothing. Asserted per input shape, never masked.
echo "== B. exit-0-by-contract — garbage / empty / wrong-type payload =="

printf 'garbage' | ( cd "$SANDBOX" && python3 "$V_QA" ) >/dev/null 2>&1
rc=$?
if [ "$rc" = "0" ]; then ok "exit 0 on garbage stdin: validate-qa-result.py"
else no "exit $rc on garbage stdin: validate-qa-result.py  (|| true would MASK this)"; fi

( cd "$SANDBOX" && python3 "$V_QA" ) >/dev/null 2>&1 </dev/null
rc=$?
if [ "$rc" = "0" ]; then ok "exit 0 on EMPTY stdin: validate-qa-result.py"
else no "exit $rc on empty stdin: validate-qa-result.py"; fi

printf '{"last_assistant_message": 12345}' | ( cd "$SANDBOX" && python3 "$V_QA" ) >/dev/null 2>&1
rc=$?
if [ "$rc" = "0" ]; then ok "exit 0 on a WRONG-TYPE payload field: validate-qa-result.py"
else no "exit $rc on a wrong-type payload field: validate-qa-result.py"; fi

# ── C. cross-plugin import resolution + import-time fail-safe ────────────────
echo "== C. result_block_parser resolves cross-plugin (loomwright-owned, single copy) =="

# The probe is DISCRIMINATING on purpose: it carries no QA_RESULT block, so a
# validator whose import SUCCEEDED must answer ok:FALSE. ok:true therefore
# proves the fail-safe path was taken — which is exactly what a broken
# cross-plugin resolution would look like, and why this control cannot pass
# vacuously.
mk import-guard-probe.md <<'EOF'
There is no result block anywhere in this text, so a WORKING validator answers ok:false.
EOF
GUARD_PROBE="$F"

run_v "$V_QA" "$GUARD_PROBE"
assert_fail "qa: [CONTROL] result_block_parser IS importable from selvedge — the probe is rejected, so section A is not vacuously green" \
  "missing QA_RESULT block"

NOMOD="$TMPROOT/nomod"
BADMOD="$TMPROOT/badmod"
mkdir -p "$NOMOD" "$BADMOD"
printf 'def broken(:\n' > "$BADMOD/result_block_parser.py"
cp "$V_QA" "$NOMOD/validate-qa-result.py"
cp "$V_QA" "$BADMOD/validate-qa-result.py"

run_v "$NOMOD/validate-qa-result.py" "$GUARD_PROBE"
assert_pass "qa: result_block_parser ABSENT -> exit 0 + ok:true (never a masked traceback)"

run_v "$BADMOD/validate-qa-result.py" "$GUARD_PROBE"
assert_pass "qa: result_block_parser CORRUPT -> exit 0 + ok:true (never a masked traceback)"

echo ""
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
