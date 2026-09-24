#!/usr/bin/env bash
# test-read-playwright-pin.sh — self-tests for read-playwright-pin.sh, the ONE reader of the
# `PW_TEST_VERSION=<x.y.z>` pin line in test-verify-walkthrough.sh from which `.github/workflows/ci.yml`
# derives its @playwright/test + chromium actions/cache key. The pin-line mutations (a range, a quoted
# value, a trailing comment, a missing line) were hand-tested when the workflow carried the `sed`
# inline; this file COMMITS them, so a loosened pattern can never again go green with nothing
# asserting on it. Every fixture lives under a `mktemp -d`; no network, nothing outside the temp dir
# is touched. Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's
# `loomwright/scripts/test-*.sh` glob).
#
# Arms:
#   (C)  control          → against the REAL test-verify-walkthrough.sh the reader prints an `x.y.z`
#                           that EQUALS the value a plain `grep '^PW_TEST_VERSION=' | cut -d= -f2`
#                           returns — the reader is not vacuous, and the pin is currently exact
#   (F)  fixtures         → exact `PW_TEST_VERSION=1.63.0` ⇒ stdout `1.63.0`, exit 0; a range (`=1`),
#                           a quoted value (`="1.63.0"`), a trailing comment (`=1.63.0 # …`), the line
#                           missing, the line present TWICE (ambiguous), a nonexistent path ⇒ exit 1
#                           with stdout EMPTY (an empty key must never leak into the cache step) and a
#                           reason on stderr
#   (W)  wiring           → ci.yml's pw-pin step invokes `read-playwright-pin.sh` (not an inline sed
#                           that could drift from this file's subject) and that line carries no
#                           `|| true` (fail-CLOSED gate, CLAUDE.md §"Failure-Mode Invariants")
#   (M)  mutation control → a COPY of the reader with the anchored pattern loosened to
#                           `s/^PW_TEST_VERSION=\(.*\)$/\1/p` (gated on non-empty + differs + `bash -n`)
#                           ACCEPTS the range fixture the real reader refuses — the (F) range arm tests
#                           the pattern, not the harness

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
S="$HERE/read-playwright-pin.sh"
SUBJECT="$HERE/test-verify-walkthrough.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$S" "$SUBJECT" "$CI_YML"; do
  if [ ! -f "$f" ]; then
    echo "  FAIL: required file not found at $f"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run <file...> — runs the reader, captures stdout/stderr separately, leaves rc in $rc.
OUT="$TMP/out"; ERR="$TMP/err"
run() { bash "$S" "$@" > "$OUT" 2> "$ERR"; rc=$?; }
fixture() { printf 'x=1\n%s\ny=2\n' "$2" > "$TMP/$1"; }

# ============================================================================
echo "== (C) control: the real pin line =="
run
bash_n_rc=0; bash -n "$S" 2>/dev/null || bash_n_rc=$?
[ "$bash_n_rc" -eq 0 ] && ok "(C) read-playwright-pin.sh parses (bash -n)" || no "(C) bash -n failed on the reader"
[ "$rc" -eq 0 ] && ok "(C) exit 0 against test-verify-walkthrough.sh" || no "(C) rc=$rc; stderr: $(cat "$ERR")"
got="$(cat "$OUT")"
grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' < <(printf '%s\n' "$got") && ok "(C) stdout is an exact x.y.z ($got)" || no "(C) stdout is not x.y.z: '$got'"
want="$(grep '^PW_TEST_VERSION=' "$SUBJECT" | cut -d= -f2)"
[ -n "$want" ] && [ "$got" = "$want" ] && ok "(C) equals the plain grep|cut of the pin line ($want) — not vacuous" || no "(C) reader='$got' grep|cut='$want'"
[ "$(wc -l < "$OUT" | tr -d ' ')" -eq 1 ] && ok "(C) exactly one stdout line" || no "(C) $(wc -l < "$OUT") stdout lines"
[ ! -s "$ERR" ] && ok "(C) stderr empty on success" || no "(C) stderr on success: $(cat "$ERR")"

# ============================================================================
echo "== (F) fixtures: exact accepted; range / quoted / trailing comment / missing / twice / no file refused with EMPTY stdout =="
fixture exact 'PW_TEST_VERSION=1.63.0'
run "$TMP/exact"
[ "$rc" -eq 0 ] && [ "$(cat "$OUT")" = "1.63.0" ] && ok "(F1) exact \`PW_TEST_VERSION=1.63.0\` → stdout 1.63.0, exit 0" || no "(F1) exact: rc=$rc stdout='$(cat "$OUT")'"

refused() { # <label> <fixture-path-or-arg>
  local label="$1"; shift
  run "$@"
  [ "$rc" -eq 1 ] && ok "($label) exit 1" || no "($label) rc=$rc (expected 1)"
  [ ! -s "$OUT" ] && ok "($label) stdout EMPTY (no empty key leaks)" || no "($label) stdout leaked: '$(cat "$OUT")'"
  [ -s "$ERR" ] && ok "($label) reason on stderr" || no "($label) stderr empty"
}
fixture range 'PW_TEST_VERSION=1';                   refused F2-range "$TMP/range"
fixture quoted 'PW_TEST_VERSION="1.63.0"';           refused F3-quoted "$TMP/quoted"
fixture comment 'PW_TEST_VERSION=1.63.0 # trailing'; refused F4-comment "$TMP/comment"
fixture missing 'PW_OTHER=1.63.0';                   refused F5-missing "$TMP/missing"
printf 'PW_TEST_VERSION=1.63.0\nx=1\nPW_TEST_VERSION=1.64.0\n' > "$TMP/twice"
refused F6-twice "$TMP/twice"
grep -q 'ambiguous' "$ERR" && ok "(F6-twice) stderr names the ambiguity" || no "(F6-twice) stderr: $(cat "$ERR")"
refused F7-nofile "$TMP/does-not-exist"
run "$TMP/exact" extra-arg
[ "$rc" -eq 1 ] && [ ! -s "$OUT" ] && ok "(F8) two positional args → usage error, exit 1, stdout empty" || no "(F8) rc=$rc stdout='$(cat "$OUT")'"

# ============================================================================
echo "== (W) wiring: ci.yml invokes the reader (no inline sed drift) and the line is fail-CLOSED =="
grep -q 'read-playwright-pin.sh' "$CI_YML" && ok "(W) ci.yml names read-playwright-pin.sh" || no "(W) ci.yml does not invoke read-playwright-pin.sh"
invoke_lines="$(grep 'read-playwright-pin.sh' "$CI_YML" | grep -v '^ *#')"
[ -n "$invoke_lines" ] && ok "(W) at least one NON-comment invoking line" || no "(W) read-playwright-pin.sh appears only in comments"
! grep -q '|| true' < <(printf '%s\n' "$invoke_lines") && ok "(W) the invoking line carries no \`|| true\`" || no "(W) the invoking line masks failure with || true"
! grep -qE "^[^#]*sed -n 's/\^PW_TEST_VERSION=" "$CI_YML" && ok "(W) no inline PW_TEST_VERSION sed remains in ci.yml" || no "(W) an inline PW_TEST_VERSION sed still lives in ci.yml"
# The invoking step must be under `set -euo pipefail` so a non-zero exit from the reader fails the step
# BEFORE `echo "version=$pin"` can write an empty key.
pwpin_block="$(awk '/id: pw-pin/{f=1} f&&/read-playwright-pin.sh/{print; exit} f{print}' "$CI_YML")"
grep -q 'set -euo pipefail' < <(printf '%s\n' "$pwpin_block") && ok "(W) the pw-pin step runs under set -euo pipefail" || no "(W) pw-pin step: no set -euo pipefail before the reader call"

# ============================================================================
echo "== (M) mutation control: a loosened pattern ACCEPTS the range fixture the real reader refuses =="
MUT="$TMP/read-playwright-pin.mutant.sh"
# A LITERAL replacement (awk index/substr, no regex): the reader's pattern is itself a regex full of
# escapes, and a regex-on-regex rewrite is exactly the kind of thing that silently matches nothing.
STRICT='s/^PW_TEST_VERSION=\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p'
LOOSE='s/^PW_TEST_VERSION=\(.*\)$/\1/p'
# ENVIRON, not `-v`: `-v` processes backslash escapes (`\1` would become a control byte); ENVIRON is raw.
STRICT="$STRICT" LOOSE="$LOOSE" awk 'BEGIN { s = ENVIRON["STRICT"]; l = ENVIRON["LOOSE"] }
  { i = index($0, s); if (i) $0 = substr($0, 1, i-1) l substr($0, i+length(s)); print }' "$S" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$S" "$MUT" && bash -n "$MUT" 2>/dev/null; then
  ok "(M) mutant gated: non-empty, differs from the reader, parses"
  m_out="$(bash "$MUT" "$TMP/range" 2>/dev/null)"; m_rc=$?
  [ "$m_rc" -eq 0 ] && [ "$m_out" = "1" ] && ok "(M) the loosened copy accepts \`PW_TEST_VERSION=1\` (prints 1, exit 0) — so (F2-range) tests the anchor, not the harness" \
    || no "(M) mutant rc=$m_rc stdout='$m_out' (expected 0 / '1')"
  m_out="$(bash "$MUT" "$TMP/comment" 2>/dev/null)"; m_rc=$?
  [ "$m_rc" -eq 0 ] && ok "(M) the loosened copy also accepts the trailing-comment fixture — (F4-comment) tests the anchor too" || no "(M) mutant refused the comment fixture (rc=$m_rc)"
else
  no "(M) mutant not gated (empty, identical to the reader, or bash -n failed) — the sed in this test no longer matches the reader's pattern line"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
