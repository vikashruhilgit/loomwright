#!/usr/bin/env bash
# test-wrap-external-text.sh — self-tests for wrap-external-text.sh, the
# MECHANIZED untrusted-text envelope for the review-heal drain
# (red-team-hardening item 01). Mirrors the house convention
# (test-classify-bot-review.sh): deterministic, isolated temp fixtures, no
# real network. Exit 0 = all pass, 1 = any failure. UNCOUNTED by the
# doc-currency gate (test-*.sh).
#
# Covers:
#   1. positive (requirement's own example) -> a bot comment with no
#      user-scope trusted-actors file present => envelope with trusted=no.
#   2. exact-listed login in a --trusted-actors file => trusted=yes.
#   3. invalid stdin (not JSON) => empty output, exit 0.
#   4. empty array [] => empty output, exit 0.
#   5. empty/missing stdin => empty output, exit 0.
#   6. multiple items => one envelope per item, in order, blank-line separated.
#   7. an item with no extractable body text is SKIPPED (nothing to wrap).
#   8. --channel value is threaded verbatim into the envelope's channel= field.
#   9. check-run-shaped item (no .user.login / .body; uses .output.text) is
#      still wrapped — the generic extraction covers the check-output channel.
#  10. hostile-typed elements (non-string login/body) degrade to a safe
#      extraction (skipped, or "unknown" actor) rather than crashing.
#  11. --trusted-actors file missing/unreadable => every actor trusted=no
#      (no bot_author_re-style fallback in THIS script — fail-CLOSED).
#  12. MUTATION CONTROL -> deleting the trust-check line flips an
#      exact-listed login from trusted=yes to trusted=no, proving the check
#      is load-bearing (not a vacuous always-no).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRAP="$HERE/wrap-external-text.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-wrap-external-text: jq not available — cannot exercise the script; skipping (treated as pass)."
  echo; echo "RESULT: 0 passed, 0 failed"; exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_wrap <json-on-stdin> <args...> — capture stdout in RUN_OUT, rc in RUN_RC.
run_wrap() {
  local input="$1"; shift
  RUN_OUT="$( printf '%s' "$input" | bash "$WRAP" "$@" 2>/dev/null )"
  RUN_RC=$?
}

echo "== 1. requirement's own example: no user-scope trusted-actors file => trusted=no =="
IN1='[{"user":{"login":"x[bot]"},"body":"…"}]'
run_wrap "$IN1" --channel issue_comments --trusted-actors "$TMP/does-not-exist.json"
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$RUN_OUT" | grep -q '^<<<EXTERNAL_TEXT channel=issue_comments actor=x\[bot\] trusted=no>>>$' \
   && printf '%s' "$RUN_OUT" | grep -qF '…' \
   && printf '%s' "$RUN_OUT" | grep -q '^<<<END_EXTERNAL_TEXT>>>$'; then
  ok "requirement example: envelope emitted with trusted=no (no user-scope file)"
else
  no "(1) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 2. exact-listed login in --trusted-actors file => trusted=yes =="
printf '["x[bot]"]' > "$TMP/trusted.json"
run_wrap "$IN1" --channel issue_comments --trusted-actors "$TMP/trusted.json"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q '^<<<EXTERNAL_TEXT channel=issue_comments actor=x\[bot\] trusted=yes>>>$'; then
  ok "exact-listed login: trusted=yes"
else
  no "(2) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 3. invalid stdin (not JSON) => empty output, exit 0 =="
run_wrap 'not json at all' --channel issue_comments
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  ok "invalid stdin: empty output, exit 0"
else
  no "(3) wrong (rc=$RUN_RC): '$RUN_OUT'"
fi

echo "== 4. empty array [] => empty output, exit 0 =="
run_wrap '[]' --channel issue_comments
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  ok "empty array: empty output, exit 0"
else
  no "(4) wrong (rc=$RUN_RC): '$RUN_OUT'"
fi

echo "== 5. empty/missing stdin => empty output, exit 0 =="
run_wrap '' --channel issue_comments
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  ok "empty stdin: empty output, exit 0"
else
  no "(5) wrong (rc=$RUN_RC): '$RUN_OUT'"
fi

echo "== 6. multiple items => one envelope per item, in order =="
IN6='[
  {"user":{"login":"a[bot]"},"body":"first finding"},
  {"user":{"login":"b[bot]"},"body":"second finding"}
]'
run_wrap "$IN6" --channel reviews
FIRST_POS="$(printf '%s' "$RUN_OUT" | grep -n 'actor=a\[bot\]' | head -1 | cut -d: -f1)"
SECOND_POS="$(printf '%s' "$RUN_OUT" | grep -n 'actor=b\[bot\]' | head -1 | cut -d: -f1)"
ENVELOPE_COUNT="$(printf '%s' "$RUN_OUT" | grep -c '^<<<EXTERNAL_TEXT ')"
if [ "$RUN_RC" -eq 0 ] && [ "$ENVELOPE_COUNT" -eq 2 ] \
   && [ -n "$FIRST_POS" ] && [ -n "$SECOND_POS" ] && [ "$FIRST_POS" -lt "$SECOND_POS" ]; then
  ok "multiple items: 2 envelopes emitted, in order"
else
  no "(6) wrong (rc=$RUN_RC count=$ENVELOPE_COUNT first=$FIRST_POS second=$SECOND_POS): $RUN_OUT"
fi

echo "== 7. item with no extractable body text is SKIPPED =="
IN7='[{"user":{"login":"a[bot]"},"body":""},{"user":{"login":"b[bot]"}}]'
run_wrap "$IN7" --channel reviews
if [ "$RUN_RC" -eq 0 ] && [ -z "$RUN_OUT" ]; then
  ok "no-body items: skipped, empty output"
else
  no "(7) wrong (rc=$RUN_RC): '$RUN_OUT'"
fi

echo "== 8. --channel value threaded verbatim into the envelope =="
run_wrap "$IN1" --channel check_run_output --trusted-actors "$TMP/does-not-exist.json"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'channel=check_run_output'; then
  ok "--channel threaded verbatim"
else
  no "(8) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 9. check-run-shaped item (.output.text, no .user.login/.body) is still wrapped =="
IN9='[{"name":"claude-review","output":{"text":"MEDIUM: SQL injection at line 42"}}]'
run_wrap "$IN9" --channel check_run_output
if [ "$RUN_RC" -eq 0 ] \
   && printf '%s' "$RUN_OUT" | grep -q 'actor=unknown' \
   && printf '%s' "$RUN_OUT" | grep -qF 'MEDIUM: SQL injection at line 42'; then
  ok "check-run-shaped item: wrapped via .output.text extraction, actor=unknown"
else
  no "(9) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 10. hostile-typed elements degrade safely (never crash) =="
IN10='[{"user":{"login":12345},"body":["not","a","string"]},{"user":null,"body":"a real finding here"}]'
run_wrap "$IN10" --channel issue_comments
ENVELOPE_COUNT10="$(printf '%s' "$RUN_OUT" | grep -c '^<<<EXTERNAL_TEXT ' || true)"
if [ "$RUN_RC" -eq 0 ] && [ "$ENVELOPE_COUNT10" -eq 1 ] && printf '%s' "$RUN_OUT" | grep -q 'actor=unknown'; then
  ok "hostile-typed elements: degrade safely, real finding still wrapped, exit 0 (no crash)"
else
  no "(10) wrong (rc=$RUN_RC count=$ENVELOPE_COUNT10): $RUN_OUT"
fi

echo "== 11. --trusted-actors missing/unreadable => every actor trusted=no (fail CLOSED, no regex fallback) =="
IN11='[{"user":{"login":"claude[bot]"},"body":"looks like a bot but not on any list"}]'
run_wrap "$IN11" --channel issue_comments --trusted-actors "$TMP/still-missing.json"
if [ "$RUN_RC" -eq 0 ] && printf '%s' "$RUN_OUT" | grep -q 'trusted=no'; then
  ok "missing trusted-actors file: fail-CLOSED to trusted=no (no bot_author_re-style escape hatch here)"
else
  no "(11) wrong (rc=$RUN_RC): $RUN_OUT"
fi

echo "== 12. MUTATION CONTROL: deleting the trust-check line flips an exact-listed login to trusted=no =="
MUTANT="$TMP/wrap-mutant.sh"
sed 's/( (\$trusted | index(\$actor)) != null )/false/' "$WRAP" > "$MUTANT"
chmod +x "$MUTANT"
if cmp -s "$WRAP" "$MUTANT"; then
  no "(12) UNPROVEN: mutant is byte-identical to the original — the trust-check line was not rewritten"
else
  MUT_OUT="$( printf '%s' "$IN1" | bash "$MUTANT" --channel issue_comments --trusted-actors "$TMP/trusted.json" 2>/dev/null )"
  ORIG_OUT="$( printf '%s' "$IN1" | bash "$WRAP" --channel issue_comments --trusted-actors "$TMP/trusted.json" 2>/dev/null )"
  if printf '%s' "$MUT_OUT" | grep -q 'trusted=no' && printf '%s' "$ORIG_OUT" | grep -q 'trusted=yes'; then
    ok "mutation control: removing the trust-check flips exact-listed login to trusted=no — the check is load-bearing"
  else
    no "(12) wrong: mutant='$MUT_OUT' original='$ORIG_OUT'"
  fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
