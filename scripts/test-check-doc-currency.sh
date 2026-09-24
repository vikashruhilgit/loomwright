#!/usr/bin/env bash
# test-check-doc-currency.sh — self-test for the description-length +
# single-version-token gate added to scripts/check-doc-currency.sh
# (red-team-hardening item 08, Fix 4).
#
# The gate has no env-var fixture seam (it always resolves plugin.json /
# marketplace.json relative to its own script location), so this harness
# copies the REAL working tree into a hermetic temp dir (the gate's own
# repo-root detection then treats that copy as "the repo") and mutates only
# the copy's plugin.json description — the checked-in repo is never touched.
#
# Cases:
#   1. LIVE REPO — the real gate passes against the checked-in repo's
#      current (<=400 char, single-version-token) description card.
#   2. 601-CHAR DESCRIPTION -> DRIFT [description-length], exit 1.
#   3. TWO vX.Y.Z TOKENS -> DRIFT [description-version-tokens], exit 1.
#   4. Restoring the real <=400-char card on the copy -> PASS again (proves
#      the drift above was the description, not fixture corruption).
#
# bash-3.2-safe: no mapfile, no associative arrays.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$repo_root/scripts/check-doc-currency.sh"
[ -f "$GATE" ] || { echo "FAIL: gate not found at $GATE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required" >&2; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
no() { fail=$((fail + 1)); echo "FAIL - $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/doc-currency-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ---- Hermetic copy of the working tree (git-tracked + currently-dirty files
#      both matter here, since this run's uncommitted description-card fix
#      is exactly what case 1 below needs to see). .git is dropped: it can be
#      large and the gate never reads it. ---------------------------------
cp -a "$repo_root/." "$TMP/" 2>/dev/null
rm -rf "$TMP/.git"

FIXTURE_PLUGIN_JSON="$TMP/loomwright/.claude-plugin/plugin.json"
[ -f "$FIXTURE_PLUGIN_JSON" ] || { echo "FAIL: fixture copy missing plugin.json" >&2; exit 1; }

set_description() { # set_description <text>
  python3 -c '
import json, sys
p, text = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["description"] = text
with open(p, "w") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
' "$FIXTURE_PLUGIN_JSON" "$1"
}

ORIGINAL_DESC="$(jq -r '.description' "$FIXTURE_PLUGIN_JSON")"

# ---- Case 1: the copy, unmodified, passes (proves the live card is clean) --
OUT1="$(cd "$TMP" && bash scripts/check-doc-currency.sh 2>&1)"; RC1=$?
if [ "$RC1" -eq 0 ]; then
  ok "case 1: live repo's own description card passes the gate (exit 0)"
else
  no "case 1: live repo's own description card should pass (exit $RC1): $(printf '%s' "$OUT1" | grep -i description)"
fi

# ---- Case 2: a 601-char description fails on length --------------------
LONG_601="$(python3 -c 'print("x" * 601)')"
set_description "$LONG_601"
OUT2="$(cd "$TMP" && bash scripts/check-doc-currency.sh 2>&1)"; RC2=$?
if [ "$RC2" -ne 0 ] && grep -q 'DRIFT \[description-length\]' < <(printf '%s' "$OUT2"); then
  ok "case 2: a 601-char description FAILS with a description-length DRIFT line"
else
  no "case 2: a 601-char description should fail with description-length DRIFT (rc=$RC2): $(printf '%s' "$OUT2" | tail -5)"
fi

# ---- Case 2b: exactly 600 chars is the boundary and PASSES on length -----
EXACT_600="$(python3 -c 'print("x" * 600)')"
set_description "$EXACT_600"
OUT2B="$(cd "$TMP" && bash scripts/check-doc-currency.sh 2>&1)"
if ! grep -q 'DRIFT \[description-length\]' < <(printf '%s' "$OUT2B"); then
  ok "case 2b: exactly 600 chars does NOT trigger description-length DRIFT (boundary is 'exceeds 600', not '>= 600')"
else
  no "case 2b: exactly 600 chars should not trigger description-length DRIFT: $(printf '%s' "$OUT2B" | tail -5)"
fi

# ---- Case 3: two vX.Y.Z-shaped tokens fails even though it is short ------
TWO_VERSIONS="Loomwright v1.2.3 replaces v1.0.0 with a shorter card."
set_description "$TWO_VERSIONS"
OUT3="$(cd "$TMP" && bash scripts/check-doc-currency.sh 2>&1)"; RC3=$?
if [ "$RC3" -ne 0 ] && grep -q 'DRIFT \[description-version-tokens\]' < <(printf '%s' "$OUT3"); then
  ok "case 3: two vX.Y.Z tokens FAILS with a description-version-tokens DRIFT line"
else
  no "case 3: two vX.Y.Z tokens should fail with description-version-tokens DRIFT (rc=$RC3): $(printf '%s' "$OUT3" | tail -5)"
fi

# ---- Case 3b: exactly one vX.Y.Z token is fine ---------------------------
ONE_VERSION="Loomwright v1.2.3 is a plan-first system."
set_description "$ONE_VERSION"
OUT3B="$(cd "$TMP" && bash scripts/check-doc-currency.sh 2>&1)"
if ! grep -q 'DRIFT \[description-version-tokens\]' < <(printf '%s' "$OUT3B"); then
  ok "case 3b: exactly one vX.Y.Z token does NOT trigger description-version-tokens DRIFT"
else
  no "case 3b: exactly one vX.Y.Z token should not trigger DRIFT: $(printf '%s' "$OUT3B" | tail -5)"
fi

# ---- Case 4: restoring the real card passes again (rules out fixture rot) -
set_description "$ORIGINAL_DESC"
OUT4="$(cd "$TMP" && bash scripts/check-doc-currency.sh 2>&1)"; RC4=$?
if [ "$RC4" -eq 0 ]; then
  ok "case 4: restoring the original description passes again"
else
  no "case 4: restoring the original description should pass again (rc=$RC4): $(printf '%s' "$OUT4" | tail -5)"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
