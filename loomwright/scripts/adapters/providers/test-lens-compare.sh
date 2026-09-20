#!/usr/bin/env bash
# test-lens-compare.sh — stub-backed self-tests for lens-compare.sh. Mirrors
# test-lens-run.sh's stub-on-PATH convention (own provider-table entries,
# written at test start, removed in this test's own EXIT trap). lens-run.sh's
# OWN mechanics (sandbox isolation, mutation detection, timeout) are already
# covered by test-lens-run.sh; this suite only exercises lens-compare.sh's
# OWN logic — argument parsing and the agree/only-A/only-B set computation —
# so stubs here just return fixed issues[] JSON, no sandbox-mutation cases.
#
# Covers:
#   A. two providers, overlapping + disjoint findings -> agree/only_a/only_b
#      partition correctly, each entry carries full evidence
#   B. provider B unavailable (no provider-table entry) -> degraded_b,
#      provider A's findings all land in only_a, agree empty
#   C. --providers missing the comma -> usage error, exit 64
#   D. --providers with a third comma -> usage error, exit 64
#
# Exit: 0 = all pass, 1 = any failure.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPARE="$HERE/lens-compare.sh"
REPO_ROOT="$(cd "$HERE/../../../.." && pwd)"
BASH_BIN="$(command -v bash)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label (expected [$expected] got [$actual])"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-lens-compare.sh: jq is required to run this suite"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi
if [ ! -f "$COMPARE" ]; then
  echo "test-lens-compare.sh: lens-compare.sh not found at $COMPARE"; echo "RESULT: 0 passed, 1 failed"; exit 1
fi

TMP="$(mktemp -d)"
PROVIDER_X_FILE="$HERE/provider-teststubx.sh"
PROVIDER_Y_FILE="$HERE/provider-teststuby.sh"
cleanup() { rm -rf "$TMP"; rm -f "$PROVIDER_X_FILE" "$PROVIDER_Y_FILE"; }
trap cleanup EXIT

DIFF_FILE="$TMP/diff.txt"
PROMPT_FILE="$TMP/prompt.txt"
printf 'diff --git a/src/foo.py b/src/foo.py\n+bug here\n' > "$DIFF_FILE"
printf 'Review this diff for bugs.\n' > "$PROMPT_FILE"

STUB_X_DIR="$TMP/stub-x"; mkdir -p "$STUB_X_DIR"
STUB_X_CLI="loomwright-test-stub-x-cli"
cat > "$STUB_X_DIR/$STUB_X_CLI" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"issues":[
  {"severity":"HIGH","category":"new","file":"src/foo.py","line":10,"description":"A: shared finding","suggestion":null},
  {"severity":"MEDIUM","category":"new","file":"src/foo.py","line":99,"description":"A: only-A finding","suggestion":null}
]}'
STUB
chmod +x "$STUB_X_DIR/$STUB_X_CLI"
cat > "$PROVIDER_X_FILE" <<PROVIDER
#!/usr/bin/env bash
PROVIDER_CLI_NAME="$STUB_X_CLI"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1
provider_build_argv() { PROVIDER_ARGV=("\$PROMPT_CONTENT"); }
provider_extract_text() {
  local raw_file="\$1"
  PROVIDER_EXTRACTED=""
  [ -s "\$raw_file" ] || return 1
  PROVIDER_EXTRACTED="\$(cat "\$raw_file")"
  [ -n "\$PROVIDER_EXTRACTED" ] || return 1
  return 0
}
PROVIDER
chmod +x "$PROVIDER_X_FILE"

STUB_Y_DIR="$TMP/stub-y"; mkdir -p "$STUB_Y_DIR"
STUB_Y_CLI="loomwright-test-stub-y-cli"
cat > "$STUB_Y_DIR/$STUB_Y_CLI" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"issues":[
  {"severity":"BLOCKING","category":"new","file":"src/foo.py","line":10,"description":"B: shared finding, different wording","suggestion":"fix it"},
  {"severity":"LOW","category":"new","file":"src/bar.py","line":1,"description":"B: only-B finding","suggestion":null}
]}'
STUB
chmod +x "$STUB_Y_DIR/$STUB_Y_CLI"
cat > "$PROVIDER_Y_FILE" <<PROVIDER
#!/usr/bin/env bash
PROVIDER_CLI_NAME="$STUB_Y_CLI"
PROVIDER_WORKSPACE_FLAG=0
PROVIDER_HOME_SCRUB=1
provider_build_argv() { PROVIDER_ARGV=("\$PROMPT_CONTENT"); }
provider_extract_text() {
  local raw_file="\$1"
  PROVIDER_EXTRACTED=""
  [ -s "\$raw_file" ] || return 1
  PROVIDER_EXTRACTED="\$(cat "\$raw_file")"
  [ -n "\$PROVIDER_EXTRACTED" ] || return 1
  return 0
}
PROVIDER
chmod +x "$PROVIDER_Y_FILE"

run_compare() {
  local providers="$1" outfile="$2" stubpath="$3"
  ( cd "$REPO_ROOT" && PATH="$stubpath:$PATH" "$BASH_BIN" "$COMPARE" \
      --providers "$providers" --role review \
      --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$outfile" )
}

echo "==== A: overlapping + disjoint findings -> agree/only_a/only_b partition ===="
OUT_A="$TMP/out-a.json"
RC_A=0
run_compare "teststubx,teststuby" "$OUT_A" "$STUB_X_DIR:$STUB_Y_DIR" || RC_A=$?
assert_eq "A rc=0" "0" "$RC_A"
assert_eq "A compare_status=ok" "ok" "$(jq -r '.compare_status' "$OUT_A" 2>/dev/null)"
assert_eq "A agree has exactly 1 entry" "1" "$(jq '.agree | length' "$OUT_A" 2>/dev/null)"
assert_eq "A agree entry is at src/foo.py:10" "src/foo.py:10" "$(jq -r '.agree[0] | "\(.file):\(.line)"' "$OUT_A" 2>/dev/null)"
assert_eq "A agree keeps A's own description as evidence" "A: shared finding" "$(jq -r '.agree[0].a.description' "$OUT_A" 2>/dev/null)"
assert_eq "A agree keeps B's own description as evidence" "B: shared finding, different wording" "$(jq -r '.agree[0].b.description' "$OUT_A" 2>/dev/null)"
assert_eq "A only_a has exactly 1 entry" "1" "$(jq '.only_a | length' "$OUT_A" 2>/dev/null)"
assert_eq "A only_a entry is the MEDIUM at line 99" "A: only-A finding" "$(jq -r '.only_a[0].description' "$OUT_A" 2>/dev/null)"
assert_eq "A only_b has exactly 1 entry" "1" "$(jq '.only_b | length' "$OUT_A" 2>/dev/null)"
assert_eq "A only_b entry is the LOW in bar.py" "B: only-B finding" "$(jq -r '.only_b[0].description' "$OUT_A" 2>/dev/null)"

echo ""
echo "==== B: provider B unavailable -> degraded_b, all of A's findings in only_a ===="
OUT_B="$TMP/out-b.json"
RC_B=0
run_compare "teststubx,does-not-exist" "$OUT_B" "$STUB_X_DIR" || RC_B=$?
assert_eq "B rc=0" "0" "$RC_B"
assert_eq "B compare_status=degraded_b" "degraded_b" "$(jq -r '.compare_status' "$OUT_B" 2>/dev/null)"
assert_eq "B provider_b lens_status=provider_unavailable" "provider_unavailable" "$(jq -r '.provider_b.lens_status' "$OUT_B" 2>/dev/null)"
assert_eq "B agree empty" "0" "$(jq '.agree | length' "$OUT_B" 2>/dev/null)"
assert_eq "B only_a has both of A's findings" "2" "$(jq '.only_a | length' "$OUT_B" 2>/dev/null)"
assert_eq "B only_b empty" "0" "$(jq '.only_b | length' "$OUT_B" 2>/dev/null)"

echo ""
echo "==== C: --providers missing a comma -> usage error, exit 64 ===="
RC_C=0
( cd "$REPO_ROOT" && "$BASH_BIN" "$COMPARE" --providers onlyone --role review \
    --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$TMP/out-c.json" ) >/dev/null 2>&1 || RC_C=$?
assert_eq "C exit=64" "64" "$RC_C"

echo ""
echo "==== D: --providers with a third comma -> usage error, exit 64 ===="
RC_D=0
( cd "$REPO_ROOT" && "$BASH_BIN" "$COMPARE" --providers "a,b,c" --role review \
    --diff "$DIFF_FILE" --prompt "$PROMPT_FILE" --out "$TMP/out-d.json" ) >/dev/null 2>&1 || RC_D=$?
assert_eq "D exit=64" "64" "$RC_D"

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
