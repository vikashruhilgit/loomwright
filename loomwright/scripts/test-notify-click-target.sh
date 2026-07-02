#!/usr/bin/env bash
# test-notify-click-target.sh — self-test for notify-click-target.sh.
# Mirrors the scripts/test-format-twin-delta.sh pattern. Not counted by the
# doc-currency gate. Exits 0 on pass, 1 on first failure.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/notify-click-target.sh"

VALID_UUID="9341af25-b817-4b41-afd5-e8755d027f20"
BUNDLE="com.anthropic.claudefordesktop"
RESUME_URL="claude://claude.ai/resume?session=${VALID_UUID}"

pass=0
fail=0

# check <description> <expected-stdout> <args...>
check() {
  local desc="$1"; shift
  local expected="$1"; shift
  local actual
  actual="$(bash "$SUT" "$@" 2>/dev/null)"
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  args:     %s\n  expected: %s\n  actual:   %s\n' \
      "$desc" "$*" "$(printf '%s' "$expected" | tr '\n' '|')" \
      "$(printf '%s' "$actual" | tr '\n' '|')"
  fi
}

A_OPEN="ACTION=open
TARGET=${RESUME_URL}"
A_ACTIVATE="ACTION=activate
TARGET=${BUNDLE}"
A_NONE="ACTION=none
TARGET="

# --- resume mode -------------------------------------------------------------
check "resume + valid UUID → deep link"            "$A_OPEN"     resume "$VALID_UUID" cli
check "resume + valid UUID (desktop entrypoint) → still deep link" \
                                                   "$A_OPEN"     resume "$VALID_UUID" claude-desktop
check "resume + empty session → activate"          "$A_ACTIVATE" resume "" cli
check "resume + malformed session → activate"      "$A_ACTIVATE" resume "not-a-uuid" cli
check "resume + truncated UUID → activate"         "$A_ACTIVATE" resume "9341af25-b817" cli

# --- activate mode -----------------------------------------------------------
check "activate ignores a valid UUID"              "$A_ACTIVATE" activate "$VALID_UUID" cli

# --- auto mode ---------------------------------------------------------------
check "auto + desktop entrypoint → activate"       "$A_ACTIVATE" auto "$VALID_UUID" claude-desktop
check "auto + cli entrypoint + UUID → deep link"   "$A_OPEN"     auto "$VALID_UUID" cli
check "auto + cli entrypoint + no UUID → activate" "$A_ACTIVATE" auto "" cli

# --- off mode ----------------------------------------------------------------
check "off → none (use fallback banner)"           "$A_NONE"     off "$VALID_UUID" cli

# --- defaults / robustness ---------------------------------------------------
# Default is now `activate` (reliable on modern macOS); only explicit `resume`
# opts into the deep-link.
check "default mode (no arg) → activate"           "$A_ACTIVATE" "" "$VALID_UUID" cli
check "unknown mode falls back to activate"        "$A_ACTIVATE" bogus "$VALID_UUID" cli
check "no args at all → activate (degrade safe)"   "$A_ACTIVATE" "" "" ""

# --- security: a session id with shell/URL metacharacters must NOT pass the
#     UUID gate, so it can never reach the deep link unescaped --------------
check "injection-y session id rejected"            "$A_ACTIVATE" resume '$(rm -rf /)' cli
check "uuid with trailing junk rejected"           "$A_ACTIVATE" resume "${VALID_UUID}&x=1" cli

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
