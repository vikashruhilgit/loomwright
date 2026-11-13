#!/usr/bin/env bash
# test-check-release.sh — pins selvedge/tests/check-release.sh: the real plugin passes, and each
# broken fixture copy fails with its own named reason (asserting the reason, not just the exit
# code, so deleting one check is caught even when a later check would also trip).
#
# Hermetic: fixtures live in a fresh temp dir with its own HOME; nothing outside selvedge/ is read.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
GATE="$TESTS_DIR/check-release.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-check-release.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

pass=0; fail=0

# expect_gate <label> <0|nonzero> <token-or-empty> <plugin-dir>
expect_gate() {
  local label="$1" want="$2" token="$3" dir="$4" out rc=0
  out="$(bash "$GATE" "$dir" 2>&1)" || rc=$?
  if [ "$want" = 0 ] && [ "$rc" -ne 0 ]; then
    fail=$((fail + 1)); echo "  FAIL $label: expected exit 0, got $rc — $out"; return
  fi
  if [ "$want" = nonzero ] && [ "$rc" -eq 0 ]; then
    fail=$((fail + 1)); echo "  FAIL $label: expected a non-zero exit, got 0 — $out"; return
  fi
  if [ -n "$token" ] && ! grep -qF -- "$token" <<<"$out"; then
    fail=$((fail + 1)); echo "  FAIL $label: output does not name $token — $out"; return
  fi
  pass=$((pass + 1)); echo "  ok   $label"
}

# fixture <name> — a copy of the real plugin's manifest + changelog; prints its dir.
fixture() {
  local d="$TMP/$1"
  mkdir -p "$d/.claude-plugin"
  cp "$PLUGIN_DIR/.claude-plugin/plugin.json" "$d/.claude-plugin/plugin.json"
  cp "$PLUGIN_DIR/CHANGELOG.md" "$d/CHANGELOG.md"
  printf '%s\n' "$d"
}

expect_gate "real plugin passes" 0 "check-release: OK" "$PLUGIN_DIR"
expect_gate "unmodified fixture copy passes" 0 "" "$(fixture aligned)"

d="$(fixture mismatch)"
jq '.version = "9.9.9"' "$PLUGIN_DIR/.claude-plugin/plugin.json" > "$d/.claude-plugin/plugin.json"
expect_gate "plugin.json version != changelog top heading fails" nonzero changelog_version_mismatch "$d"

d="$(fixture top-heading)"
{ printf '# Changelog\n\n## 0.2.0 — 2026-12-01\n\n- newer\n\n'; sed -n '/^## [0-9]/,$p' "$PLUGIN_DIR/CHANGELOG.md"; } > "$d/CHANGELOG.md"
expect_gate "only the FIRST release heading counts" nonzero changelog_version_mismatch "$d"

d="$(fixture invalid-json)"
printf '{ "name": "selvedge", "version": "0.1.0", \n' > "$d/.claude-plugin/plugin.json"
expect_gate "invalid-JSON manifest fails" nonzero manifest_invalid_json "$d"

d="$(fixture no-version)"
jq 'del(.version)' "$PLUGIN_DIR/.claude-plugin/plugin.json" > "$d/.claude-plugin/plugin.json"
expect_gate "manifest missing version fails" nonzero manifest_missing_field "$d"

d="$(fixture empty-description)"
jq '.description = ""' "$PLUGIN_DIR/.claude-plugin/plugin.json" > "$d/.claude-plugin/plugin.json"
expect_gate "manifest with an empty description fails" nonzero manifest_missing_field "$d"

d="$(fixture no-heading)"
printf '# Changelog\n\nNothing released yet.\n' > "$d/CHANGELOG.md"
expect_gate "changelog without a release heading fails" nonzero changelog_no_release "$d"

d="$(fixture no-manifest)"
rm "$d/.claude-plugin/plugin.json"
expect_gate "absent manifest fails" nonzero manifest_absent "$d"

d="$(fixture no-changelog)"
rm "$d/CHANGELOG.md"
expect_gate "absent changelog fails" nonzero changelog_absent "$d"

# The two CANNOT RUN branches exit 2 (cannot check), never 1 (violated) or 0.
# expect_cannot_run <label> <message> <out> <rc>
expect_cannot_run() {
  if [ "$4" -eq 2 ] && grep -qF -- "$2" <<<"$3"; then
    pass=$((pass + 1)); echo "  ok   $1"
  else
    fail=$((fail + 1)); echo "  FAIL $1: expected exit 2 naming '$2', got rc=$4 — $3"
  fi
}
rc=0; out="$(bash "$GATE" "$TMP/no-such-plugin" 2>&1)" || rc=$?
expect_cannot_run "a missing plugin dir exits 2 (cannot check)" "check-release: CANNOT RUN — no such plugin dir: $TMP/no-such-plugin" "$out" "$rc"
d="$(fixture nojq)"
rc=0; out="$(PATH="$TMP/empty-path" "$BASH" "$GATE" "$d" 2>&1)" || rc=$?
expect_cannot_run "no jq on PATH exits 2 (cannot check)" "check-release: CANNOT RUN — jq not found" "$out" "$rc"

# run.sh fails CLOSED: a fixture plugin whose tests/ holds the gate scripts but no test-*.sh, then
# the same with one failing test-*.sh.
runner_fixture() {
  local d; d="$(fixture "$1")"
  mkdir -p "$d/tests"
  cp "$TESTS_DIR/run.sh" "$TESTS_DIR/check-release.sh" "$d/tests/"
  printf '%s\n' "$d"
}
d="$(runner_fixture runner-empty)"
rc=0; out="$(bash "$d/tests/run.sh" 2>&1)" || rc=$?
{ [ "$rc" -ne 0 ] && grep -qF "no tests/test-*.sh found" <<<"$out"; } \
  && { pass=$((pass + 1)); echo "  ok   run.sh with zero test files fails closed"; } \
  || { fail=$((fail + 1)); echo "  FAIL run.sh with zero test files: rc=$rc — $out"; }
d="$(runner_fixture runner-red)"
printf 'exit 1\n' > "$d/tests/test-red.sh"
rc=0; out="$(bash "$d/tests/run.sh" 2>&1)" || rc=$?
{ [ "$rc" -ne 0 ] && grep -qF "FAIL test-red.sh" <<<"$out"; } \
  && { pass=$((pass + 1)); echo "  ok   run.sh fails when one test file fails"; } \
  || { fail=$((fail + 1)); echo "  FAIL run.sh with a failing test: rc=$rc — $out"; }

echo "test-check-release: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
