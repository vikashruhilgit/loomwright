#!/usr/bin/env bash
# test-check-shared-prefix.sh — offline self-test for check-shared-prefix.sh.
#
# Builds hermetic fixtures in a temp dir (never touches the real repo files)
# and asserts the gate's fail-CLOSED behavior:
#   1. green            — all agents carry the canonical block byte-identically -> exit 0
#   2. 1-char drift     — a single character changed inside one agent's copy -> exit != 0, offender named
#   3. missing block    — an agent without the block -> exit != 0, offender named
#   4. missing canonical -> exit != 0
#   5. duplicate block  — block present twice in one agent -> exit != 0
#   6. empty agents dir -> exit != 0 (0-agent false-green guard)
#   7. malformed canonical (no END marker) -> exit != 0
#   8. asymmetric markers — an agent with BEGIN but no END -> exit != 0, MALFORMED label
#
# Portability: bash 3.2 safe (macOS) + Linux CI. No sed -i, no mapfile, offline.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
CHECK="$script_dir/check-shared-prefix.sh"
[ -f "$CHECK" ] || { echo "test-check-shared-prefix: gate script not found: $CHECK" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/shared-prefix-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

# run_case NAME EXPECT(zero|nonzero) [GREP_MUST_MATCH] — runs the gate against
# the current fixture env vars, captures output+status, asserts expectation.
run_case() {
  name="$1"; expect="$2"; must_match="${3:-}"
  out="$(SHARED_PREFIX_CANONICAL="$CANON" SHARED_PREFIX_AGENTS_DIR="$AGENTS" bash "$CHECK" 2>&1)"
  status=$?
  ok=1
  if [ "$expect" = "zero" ] && [ "$status" -ne 0 ]; then ok=0; fi
  if [ "$expect" = "nonzero" ] && [ "$status" -eq 0 ]; then ok=0; fi
  if [ "$ok" -eq 1 ] && [ -n "$must_match" ]; then
    if ! printf '%s\n' "$out" | grep -qF "$must_match"; then ok=0; fi
  fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (exit=$status, expected $expect${must_match:+, expected output to contain: $must_match})"
    printf '%s\n' "$out" | sed 's/^/    | /'
    fail=$((fail + 1))
  fi
}

# --- Fixture builders --------------------------------------------------------

write_canonical() {
  cat > "$1" <<'EOF'
# Fixture canonical source

Header prose the gate must ignore.

<!-- SHARED-AGENT-PREFIX v1 BEGIN -->
## Shared Agent Contract

- **Mission:** the smallest correct thing.
- **Safety:** no destructive actions without approval.
<!-- SHARED-AGENT-PREFIX v1 END -->
EOF
}

# write_agent OUT — a fixture agent file carrying the canonical block.
write_agent() {
  cat > "$1" <<'EOF'
---
tools: Read
---

<!-- SHARED-AGENT-PREFIX v1 BEGIN -->
## Shared Agent Contract

- **Mission:** the smallest correct thing.
- **Safety:** no destructive actions without approval.
<!-- SHARED-AGENT-PREFIX v1 END -->

# Fixture Agent

Role-specific content.
EOF
}

reset_fixture() {
  rm -rf "$tmp/fx"
  mkdir -p "$tmp/fx/agents"
  CANON="$tmp/fx/canonical.md"
  AGENTS="$tmp/fx/agents"
  write_canonical "$CANON"
  write_agent "$AGENTS/alpha.md"
  write_agent "$AGENTS/beta.md"
  write_agent "$AGENTS/gamma.md"
}

# --- 1. green ----------------------------------------------------------------
reset_fixture
run_case "green: all agents byte-identical" zero "all 3 agent files"

# --- 2. 1-char drift ---------------------------------------------------------
reset_fixture
# Change exactly ONE character inside beta's copy of the block ("smallest" ->
# "smaIlest"). sed without -i (portable): write to a new file, then move.
sed 's/smallest/smaIlest/' "$AGENTS/beta.md" > "$AGENTS/beta.md.new"
mv "$AGENTS/beta.md.new" "$AGENTS/beta.md"
run_case "1-char drift in one agent fails and names the offender" nonzero "DRIFT     beta.md"

# --- 3. missing block --------------------------------------------------------
reset_fixture
cat > "$AGENTS/gamma.md" <<'EOF'
---
tools: Read
---

# Fixture Agent Without Block

Role-specific content only.
EOF
run_case "missing block in one agent fails and names the offender" nonzero "MISSING   gamma.md"

# --- 4. missing canonical ----------------------------------------------------
reset_fixture
rm -f "$CANON"
run_case "missing canonical file fails" nonzero "canonical file not found"

# --- 5. duplicate block ------------------------------------------------------
reset_fixture
# Append a second full copy of the block to alpha (exactly-once invariant).
awk '/<!-- SHARED-AGENT-PREFIX v1 BEGIN -->/,/<!-- SHARED-AGENT-PREFIX v1 END -->/' "$CANON" >> "$AGENTS/alpha.md"
run_case "duplicate block in one agent fails" nonzero "DUPLICATE alpha.md"

# --- 6. empty agents dir -----------------------------------------------------
reset_fixture
rm -f "$AGENTS"/*.md
run_case "empty agents dir fails (0-agent false-green guard)" nonzero "refusing to pass a 0-agent gate"

# --- 7. malformed canonical (no END marker) ----------------------------------
reset_fixture
grep -vF '<!-- SHARED-AGENT-PREFIX v1 END -->' "$CANON" > "$CANON.new"
mv "$CANON.new" "$CANON"
run_case "canonical without END marker fails" nonzero "exactly one BEGIN and one END"

# --- 8. asymmetric markers in an agent (END deleted) -------------------------
reset_fixture
grep -vF '<!-- SHARED-AGENT-PREFIX v1 END -->' "$AGENTS/beta.md" > "$AGENTS/beta.md.new"
mv "$AGENTS/beta.md.new" "$AGENTS/beta.md"
run_case "agent with BEGIN but no END fails as MALFORMED" nonzero "MALFORMED beta.md"

# --- Summary -----------------------------------------------------------------
echo "----------------------------------------"
echo "test-check-shared-prefix: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  echo "test-check-shared-prefix: FAILED" >&2
  exit 1
fi
echo "test-check-shared-prefix: OK"
exit 0
