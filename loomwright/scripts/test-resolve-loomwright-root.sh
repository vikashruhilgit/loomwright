#!/usr/bin/env bash
# test-resolve-loomwright-root.sh — self-test for resolve-loomwright-root.sh.
#
# Both resolution arms are exercised by EXECUTION, not inspection:
#   * harness variable set   -> LOOMWRIGHT_ROOT is EXACTLY that value
#   * harness variable unset -> the dev-checkout fallback still succeeds
# The fallback is additionally proved to be LOCATION-DERIVED rather than
# hard-coded, by copying the resolver into an unrelated fixture layout and
# asserting it resolves to THAT layout's root. Without that case, the fallback
# test would also pass against a resolver that simply printed a constant.
#
# This file is CORE-classified under the vendor-coupling ratchet and therefore
# carries a declared allowance in loomwright/docs/vendor-coupling-manifest.json:
# testing the harness arm requires naming the harness variable literally, and the
# honest way to record that is an allowance the ratchet holds flat — not an
# adapter exemption, and not an obfuscated reference the counter cannot see.
#
# UNTESTED BY DESIGN — the exhausted-resolution failure path (exit 1, all three
# arms failing) has NO case here, and that is stated rather than left for a
# reader to discover: everything else in this file is proved by execution, so
# silence would read as coverage. Triggering it needs `BASH_SOURCE[0]`/`$0`
# unset or the script's own directory deleted mid-run, which bash effectively
# never produces and which no deterministic, bash-3.2-safe fixture can
# construct honestly. A contrived fixture that stubbed the resolver to force
# the branch would assert on the stub, not on the resolver — a check that
# backs nothing, which is the failure this whole surface exists to prevent.
# If you find a real way to reach it, add the case and delete this note.
#
# Fully offline and deterministic. macOS bash 3.2 / BSD userland safe: no
# GNU-only stat/sed/date flags, no `realpath`/`readlink -f`, no `timeout`.
# Comparisons that involve a temp dir go through `cd && pwd` on BOTH sides, so a
# symlinked TMPDIR (/var -> /private/var on macOS) cannot produce a false failure.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="$script_dir/resolve-loomwright-root.sh"
plugin_root="$(cd "$script_dir/.." && pwd)"
[ -f "$RESOLVER" ] || { echo "FAIL: resolver not found at $RESOLVER" >&2; exit 1; }

pass=0
fail=0
eq() { # eq "name" expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   - $1"; else
    fail=$((fail+1)); echo "FAIL - $1 (expected '$2', got '$3')"; fi
}
rc_is() { # rc_is "name" expected_rc actual_rc
  if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "ok   - $1 (exit $3)"; else
    fail=$((fail+1)); echo "FAIL - $1 (expected exit $2, got $3)"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/resolve-root-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Arm 1 — harness variable set: LOOMWRIGHT_ROOT is EXACTLY that path.
# The fixture value is deliberately non-existent, non-normalized and
# trailing-slashed: the harness owns that path, so the resolver must pass it
# through verbatim rather than validating or canonicalizing it.
# ---------------------------------------------------------------------------
WEIRD="/nonexistent/plugin cache/./loomwright/"
OUT="$(CLAUDE_PLUGIN_ROOT="$WEIRD" bash "$RESOLVER")"; RC=$?
rc_is "arm1 harness variable set resolves successfully" 0 "$RC"
eq    "arm1 LOOMWRIGHT_ROOT is exactly the harness value (verbatim, unnormalized)" "$WEIRD" "$OUT"

# ---------------------------------------------------------------------------
# Arm 3 — harness variable unset: the dev-checkout fallback resolves to the
# plugin root (loomwright/), the parent of this scripts directory.
# ---------------------------------------------------------------------------
OUT="$( unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT; bash "$RESOLVER" )"; RC=$?
rc_is "arm3 unset harness variable still resolves" 0 "$RC"
eq    "arm3 fallback points at the plugin root" "$plugin_root" "$OUT"

# ---------------------------------------------------------------------------
# Arm 3b — the fallback is LOCATION-DERIVED, not a constant. Copy the resolver
# into an unrelated layout and assert it resolves to THAT root. This is what
# stops arm 3 from passing against a resolver that hard-codes a path.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/relocated/scripts"
cp "$RESOLVER" "$TMP/relocated/scripts/resolve-loomwright-root.sh"
expected_relocated="$(cd "$TMP/relocated" && pwd)"
OUT="$( unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT; bash "$TMP/relocated/scripts/resolve-loomwright-root.sh" )"; RC=$?
rc_is "arm3b relocated copy resolves successfully" 0 "$RC"
eq    "arm3b relocated copy resolves to its OWN root (location-derived, not hard-coded)" "$expected_relocated" "$OUT"

# ---------------------------------------------------------------------------
# Arm 2 — a non-Claude adapter that publishes the neutral name directly is
# honoured when the harness variable is absent.
# ---------------------------------------------------------------------------
OUT="$( unset CLAUDE_PLUGIN_ROOT; LOOMWRIGHT_ROOT="/opt/some-other-harness/loomwright" bash "$RESOLVER" )"; RC=$?
rc_is "arm2 pre-set neutral name resolves successfully" 0 "$RC"
eq    "arm2 pre-set LOOMWRIGHT_ROOT is honoured when the harness variable is unset" \
      "/opt/some-other-harness/loomwright" "$OUT"

# ---------------------------------------------------------------------------
# Precedence — with BOTH set, the harness variable wins. This is the documented
# contract ("harness variable set => LOOMWRIGHT_ROOT is exactly that path"); in
# practice the two never both apply, since a non-Claude harness does not set the
# Claude variable.
# ---------------------------------------------------------------------------
OUT="$(CLAUDE_PLUGIN_ROOT="/harness/wins" LOOMWRIGHT_ROOT="/preset/loses" bash "$RESOLVER")"
eq "precedence: harness variable outranks a pre-set neutral name" "/harness/wins" "$OUT"

# ---------------------------------------------------------------------------
# Empty-string harness variable is treated as UNSET, not as an empty root. An
# exported-but-empty variable is the classic way a resolver ends up publishing
# "" and every downstream path becomes "/something".
# ---------------------------------------------------------------------------
OUT="$( unset LOOMWRIGHT_ROOT; CLAUDE_PLUGIN_ROOT="" bash "$RESOLVER" )"; RC=$?
rc_is "empty harness variable falls back instead of failing" 0 "$RC"
eq    "empty harness variable does not publish an empty root" "$plugin_root" "$OUT"

# ---------------------------------------------------------------------------
# Sourced form — the intended usage. It must EXPORT LOOMWRIGHT_ROOT into the
# caller, and must not leak its internals or its shell options.
# ---------------------------------------------------------------------------
OUT="$( unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT
        . "$RESOLVER"
        printf '%s' "${LOOMWRIGHT_ROOT:-UNSET}" )"
eq "sourced form sets LOOMWRIGHT_ROOT in the caller" "$plugin_root" "$OUT"

OUT="$( unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT
        . "$RESOLVER"
        # A child process sees it only if it was exported.
        bash -c 'printf "%s" "${LOOMWRIGHT_ROOT:-UNSET}"' )"
eq "sourced form EXPORTS LOOMWRIGHT_ROOT to child processes" "$plugin_root" "$OUT"

OUT="$( unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT
        . "$RESOLVER"
        printf '%s' "$(type -t __lw_resolve_root 2>/dev/null || true)" )"
eq "sourced form leaves no helper function in the caller" "" "$OUT"

# Sourcing must not turn on `set -e`/`set -u` in the caller: the resolver is
# sourced by scripts that have their own error-handling posture, and silently
# changing it would abort them on the next unset variable.
OUT="$( unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT
        . "$RESOLVER"
        # Both of these would abort the shell under `set -e` / `set -u`.
        false
        printf '%s' "${DEFINITELY_UNSET_VARIABLE:-ok}" )"
eq "sourcing does not leak set -e / set -u into the caller" "ok" "$OUT"

# ---------------------------------------------------------------------------
echo "---------------------------------------------------------------------------"
echo "test-resolve-loomwright-root: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
