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

# --- 9+: MULTI-PLUGIN DISCOVERY (v15.37.0) -----------------------------------
#
# These cases run with BOTH SHARED_PREFIX_* overrides UNSET — that is the whole
# point. The per-gate overrides are layered ABOVE discovery and return first, so
# a case that sets one proves nothing about the new loop (that is exactly how a
# "negative" test ends up unable to fail). Only CHECK_MARKETPLACE_JSON is set,
# pointing at a fixture manifest listing TWO plugin sources.
#
# MUTATION CONTROL — state the exact mutation and its MEASURED blast radius.
# An earlier version of this comment said "every case below fails", which is an
# overclaim: several cases here cover canonical resolution, the tripwire and the
# missing-manifest guard, which a discovery mutation never reaches. Flagged in
# review of PR #155.
#
# Measured mutation: make plugin_dirs() emit nothing (`return 0` before its read
# loop), i.e. discovery finds no plugins at all.
# Measured result: 5 cases fail — second plugin's agents checked, drift inside
# the second plugin caught, agent-less plugin skipped silently, registered
# loomwright without the canonical file, and the anti-drift tripwire.
# Restored: 15/15.

# mkroot <path> — create and echo the CANONICAL path. The gate resolves plugin
# dirs with `cd ... && pwd`, so a $TMPDIR with a trailing slash (macOS default)
# would make a literal "$tmp/..." assertion fail on a doubled slash while the
# gate is behaving correctly.
mkroot() { mkdir -p "$1" && ( cd "$1" && pwd ); }

# mk_plugin <root> <name> <mode> — mode: full | no-agents | drifted | no-canonical
# Only the plugin literally named "loomwright" gets the canonical prefix file:
# there is exactly ONE canonical by design (see the gate's CROSS-PLUGIN DECISION).
mk_plugin() {
  local root="$1" name="$2" mode="$3" p="$1/$2"
  mkdir -p "$p/docs"
  if [ "$name" = "loomwright" ] && [ "$mode" != "no-canonical" ]; then
    write_canonical "$p/docs/shared-agent-prefix.md"
  fi
  if [ "$mode" != "no-agents" ]; then
    mkdir -p "$p/agents"
    write_agent "$p/agents/$name-one.md"
    write_agent "$p/agents/$name-two.md"
    if [ "$mode" = "drifted" ]; then
      sed 's/smallest/smaIlest/' "$p/agents/$name-two.md" > "$p/agents/$name-two.md.new"
      mv "$p/agents/$name-two.md.new" "$p/agents/$name-two.md"
    fi
  fi
}

# mk_manifest <root> <name>...
mk_manifest() {
  local root="$1"; shift
  mkdir -p "$root/.claude-plugin"
  {
    printf '{ "name": "fixture", "plugins": ['
    local first=1 n
    for n in "$@"; do
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{ "name": "%s", "source": "./%s", "version": "1.0.0" }' "$n" "$n"
    done
    printf '] }\n'
  } > "$root/.claude-plugin/marketplace.json"
}

# run_disc NAME EXPECT MANIFEST [GREP_MUST_MATCH] — SHARED_PREFIX_* left unset.
run_disc() {
  name="$1"; expect="$2"; manifest="$3"; must_match="${4:-}"
  out="$(CHECK_MARKETPLACE_JSON="$manifest" bash "$CHECK" 2>&1)"
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

# 9. a SECOND plugin's agents are checked against loomwright's canonical
R9="$(mkroot "$tmp/d9")"
mk_plugin "$R9" loomwright full
mk_plugin "$R9" sibling    full
mk_manifest "$R9" loomwright sibling
run_disc "discovery: second plugin's agents are checked (cross-plugin canonical)" \
  zero "$R9/.claude-plugin/marketplace.json" "$R9/sibling/agents"

# 10. drift in the SECOND plugin fails — the invariant really reaches it
R10="$(mkroot "$tmp/d10")"
mk_plugin "$R10" loomwright full
mk_plugin "$R10" sibling    drifted
mk_manifest "$R10" loomwright sibling
run_disc "discovery: drift inside the second plugin is caught" \
  nonzero "$R10/.claude-plugin/marketplace.json" "DRIFT     sibling-two.md"

# 11. SKIP SILENTLY — a registered plugin with no agents/ tree
R11="$(mkroot "$tmp/d11")"
mk_plugin "$R11" loomwright full
mk_plugin "$R11" sibling    no-agents
mk_manifest "$R11" loomwright sibling
run_disc "discovery: agent-less plugin is skipped silently" \
  zero "$R11/.claude-plugin/marketplace.json" "$R11/loomwright/agents"

# 12. the CROSS-PLUGIN DECISION's documented branch, in code: no loomwright entry
R12="$(mkroot "$tmp/d12")"
mk_plugin "$R12" sibling full
mk_manifest "$R12" sibling
run_disc "discovery: manifest without loomwright fails loudly (canonical unresolvable)" \
  nonzero "$R12/.claude-plugin/marketplace.json" "canonical shared prefix is unresolvable"

# 13. loomwright registered but its canonical file is gone
R13="$(mkroot "$tmp/d13")"
mk_plugin "$R13" loomwright no-canonical
mk_manifest "$R13" loomwright
run_disc "discovery: registered loomwright without the canonical file fails" \
  nonzero "$R13/.claude-plugin/marketplace.json" "canonical file not found"

# 14. ANTI-DRIFT TRIPWIRE — no agent-bearing plugin at all
R14="$(mkroot "$tmp/d14")"
mk_plugin "$R14" loomwright no-agents
mk_manifest "$R14" loomwright
run_disc "discovery: zero agent-bearing plugins trips the anti-drift tripwire" \
  nonzero "$R14/.claude-plugin/marketplace.json" "gate matched nothing"

# 15. missing manifest fails CLOSED
run_disc "discovery: missing marketplace manifest fails closed" \
  nonzero "$tmp/d15-does-not-exist/.claude-plugin/marketplace.json" "marketplace manifest not found"

# --- Summary -----------------------------------------------------------------
echo "----------------------------------------"
echo "test-check-shared-prefix: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  echo "test-check-shared-prefix: FAILED" >&2
  exit 1
fi
echo "test-check-shared-prefix: OK"
exit 0
