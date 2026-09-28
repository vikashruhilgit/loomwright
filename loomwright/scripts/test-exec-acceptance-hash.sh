#!/usr/bin/env bash
# test-exec-acceptance-hash.sh — self-tests for exec-acceptance-hash.sh (and, by extension, the
# shared exec-acceptance-lib.sh both it and run-ground-truth.sh source). Isolated, deterministic,
# no network. Exit 0 = all pass, 1 = any failure. Prints "RESULT: N passed, M failed".
#
# Covers AC1 (loomwright/red-team-hardening item 05 — "cmd: valve by provenance"):
#   (a) brief with ONLY cmd:/bare bullets           => sha256:<hex> covering all of them.
#   (b) brief with ONLY corpus-task:/qa-executor:    => hash == "none" (nothing hashable).
#   (c) brief with a MIX of kinds                    => hash covers ONLY the cmd:/bare subset,
#                                                       identical to hashing just that subset alone.
#   (d) whitespace normalization                     => a trailing-space-only edit to a bullet does
#                                                       NOT change the hash (matches run-ground-truth.sh's
#                                                       own bullet trimming).
#   (e) absent `## Executable Acceptance` section     => hash == "none" (including a brief that has
#                                                       no such section at all).
#   (f) determinism + sensitivity                    => same input -> same hash twice; ANY bullet
#                                                       edit (incl. reordering) changes the hash.
#   (g) usage / missing-brief errors                 => exit 1, no stdout.
#   (h) classification cross-check (AC1 risk mitigation) => exec-acceptance-hash.sh and
#                                                       run-ground-truth.sh both source the SAME
#                                                       exec-acceptance-lib.sh file (byte-identical
#                                                       classify_kind definition) — structurally
#                                                       impossible to diverge, verified here by
#                                                       grepping both scripts' source line.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HASH="$HERE/exec-acceptance-hash.sh"
RUN="$HERE/run-ground-truth.sh"
LIB="$HERE/exec-acceptance-lib.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "== (a) brief with ONLY cmd:/bare bullets => sha256:<hex> covering them =="
A_BRIEF="$TMP/a.md"
printf '## Executable Acceptance\n- cmd: true\n- npm test\n' > "$A_BRIEF"
outA="$(bash "$HASH" "$A_BRIEF")"; rcA=$?
if [ "$rcA" -eq 0 ] && grep -qE '^sha256:[0-9a-f]{64}$' < <(printf '%s' "$outA"); then
  ok "(a) cmd:/bare-only brief prints sha256:<64-hex>"
else
  no "(a) wrong (rc=$rcA): $outA"
fi

echo "== (b) brief with ONLY corpus-task:/qa-executor: => hash == none =="
B_BRIEF="$TMP/b.md"
printf '## Executable Acceptance\n- corpus-task: version-consistent\n- qa-executor: login-smoke\n' > "$B_BRIEF"
outB="$(bash "$HASH" "$B_BRIEF")"; rcB=$?
if [ "$rcB" -eq 0 ] && [ "$outB" = "none" ]; then
  ok "(b) corpus-task:/qa-executor:-only brief => none"
else
  no "(b) wrong (rc=$rcB): $outB"
fi

echo "== (c) brief with a MIX => hash covers ONLY the cmd:/bare subset =="
C_BRIEF="$TMP/c.md"
printf '## Executable Acceptance\n- corpus-task: version-consistent\n- cmd: true\n- qa-executor: x\n- npm test\n' > "$C_BRIEF"
outC="$(bash "$HASH" "$C_BRIEF")"; rcC=$?
# A brief with ONLY the cmd:/bare subset, in the same relative order, must hash identically —
# proving corpus-task:/qa-executor: bullets are excluded from the hash input entirely (not merely
# order-invariant, but genuinely absent).
CSUB_BRIEF="$TMP/c-subset.md"
printf '## Executable Acceptance\n- cmd: true\n- npm test\n' > "$CSUB_BRIEF"
outCsub="$(bash "$HASH" "$CSUB_BRIEF")"
if [ "$rcC" -eq 0 ] && [ "$outC" = "$outCsub" ] && [ "$outC" != "none" ]; then
  ok "(c) mixed brief hashes identically to the cmd:/bare-only subset (corpus-task/qa-executor excluded)"
else
  no "(c) wrong (rc=$rcC): mixed=$outC subset-only=$outCsub"
fi

echo "== (d) whitespace normalization: trailing-space-only edit does NOT change the hash =="
D1_BRIEF="$TMP/d1.md"
printf '## Executable Acceptance\n- cmd: true\n' > "$D1_BRIEF"
D2_BRIEF="$TMP/d2.md"
printf '## Executable Acceptance\n- cmd: true   \n' > "$D2_BRIEF"   # trailing spaces on the bullet
outD1="$(bash "$HASH" "$D1_BRIEF")"
outD2="$(bash "$HASH" "$D2_BRIEF")"
if [ "$outD1" = "$outD2" ] && [ "$outD1" != "none" ]; then
  ok "(d) trailing-space-only bullet edit does not change the hash"
else
  no "(d) wrong: no-trailing-space=$outD1 trailing-space=$outD2"
fi

echo "== (e) absent '## Executable Acceptance' section (incl. no section at all) => none =="
E1_BRIEF="$TMP/e1.md"
printf '## Task\nSome text.\n' > "$E1_BRIEF"
outE1="$(bash "$HASH" "$E1_BRIEF")"; rcE1=$?
E2_BRIEF="$TMP/e2.md"
printf '## Executable Acceptance Notes\n- cmd: true\n' > "$E2_BRIEF"   # sibling heading only
outE2="$(bash "$HASH" "$E2_BRIEF")"; rcE2=$?
if [ "$rcE1" -eq 0 ] && [ "$outE1" = "none" ] && [ "$rcE2" -eq 0 ] && [ "$outE2" = "none" ]; then
  ok "(e) no section at all, and a sibling-heading-only brief, both hash to none"
else
  no "(e) wrong: no-section(rc=$rcE1)=$outE1 sibling-heading(rc=$rcE2)=$outE2"
fi

echo "== (f) determinism + sensitivity =="
outF1="$(bash "$HASH" "$A_BRIEF")"
outF2="$(bash "$HASH" "$A_BRIEF")"
F_EDIT="$TMP/f-edit.md"
printf '## Executable Acceptance\n- cmd: true\n- npm run test\n' > "$F_EDIT"   # one word changed
outF3="$(bash "$HASH" "$F_EDIT")"
F_REORDER="$TMP/f-reorder.md"
printf '## Executable Acceptance\n- npm test\n- cmd: true\n' > "$F_REORDER"   # same bullets, reordered
outF4="$(bash "$HASH" "$F_REORDER")"
if [ "$outF1" = "$outF2" ] && [ "$outF1" != "$outF3" ] && [ "$outF1" != "$outF4" ]; then
  ok "(f) same input hashes identically twice; a content edit OR a reorder both change the hash"
else
  no "(f) wrong: run1=$outF1 run2=$outF2 edited=$outF3 reordered=$outF4"
fi

echo "== (g) usage / missing-brief errors => exit 1, no stdout =="
outG1="$(bash "$HASH" 2>/dev/null)"; rcG1=$?
outG2="$(bash "$HASH" "$TMP/does-not-exist.md" 2>/dev/null)"; rcG2=$?
if [ "$rcG1" -eq 1 ] && [ -z "$outG1" ] && [ "$rcG2" -eq 1 ] && [ -z "$outG2" ]; then
  ok "(g) missing-arg and missing-brief both exit 1 with no stdout"
else
  no "(g) wrong: no-arg(rc=$rcG1)='$outG1' missing-file(rc=$rcG2)='$outG2'"
fi

echo "== (h) classification cross-check: both scripts source the SAME lib file (AC1 risk mitigation) =="
if [ -f "$LIB" ] \
  && grep -qE '\. "\$SCRIPT_DIR/exec-acceptance-lib\.sh"' "$HASH" \
  && grep -qE '\. "\$SCRIPT_DIR/exec-acceptance-lib\.sh"' "$RUN"; then
  ok "(h) exec-acceptance-hash.sh and run-ground-truth.sh both source exec-acceptance-lib.sh — one shared classify_kind() definition, cannot silently diverge"
else
  no "(h) one or both scripts do not source the shared lib — classification could silently diverge"
fi

echo "== (i) rule: is its own kind — never 'cmd', never hashed (plan-time-rule-routing AC5) =="
kI1="$( . "$LIB"; classify_kind "rule: x" )"
kI2="$( . "$LIB"; classify_kind "rule:no-space" )"
kI3="$( . "$LIB"; classify_kind "rules are fun" )"
if [ "$kI1" = "rule" ] && [ "$kI2" = "rule" ]; then
  ok "(i1) classify_kind 'rule: x' => rule (and 'rule:no-space' => rule)"
else
  no "(i1) classify_kind rule: gave '$kI1' / '$kI2' (would fall through to cmd and be EXECUTED)"
fi
[ "$kI3" = "cmd" ] && ok "(i2) a bare line merely starting with 'rule' (no colon) is still cmd — the prefix is exact" \
  || no "(i2) 'rules are fun' classified as '$kI3'"
I_BRIEF="$TMP/i.md"
printf '## Executable Acceptance\n- rule: some-rule\n- corpus-task: version-consistent\n' > "$I_BRIEF"
outI="$(bash "$HASH" "$I_BRIEF")"; rcI=$?
[ "$rcI" -eq 0 ] && [ "$outI" = "none" ] \
  && ok "(i3) a brief with ONLY rule: + corpus-task: bullets => hash none (never subject to cmd_unapproved)" \
  || no "(i3) rule:+corpus-task: brief hashed as '$outI' (rc=$rcI)"
I2_BRIEF="$TMP/i2.md"
printf '## Executable Acceptance\n- rule: some-rule\n- cmd: true\n- rule: other\n' > "$I2_BRIEF"
I2_SUB="$TMP/i2-sub.md"
printf '## Executable Acceptance\n- cmd: true\n' > "$I2_SUB"
outI2="$(bash "$HASH" "$I2_BRIEF")"; outI2s="$(bash "$HASH" "$I2_SUB")"
[ "$outI2" = "$outI2s" ] && [ "$outI2" != "none" ] \
  && ok "(i4) a mixed cmd:+rule: brief hashes identically to its cmd:-only subset (rule: excluded from the stamp)" \
  || no "(i4) rule: bullets leaked into the stamp hash: '$outI2' vs '$outI2s'"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
