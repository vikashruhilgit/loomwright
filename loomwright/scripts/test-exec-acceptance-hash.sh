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
if [ "$rcA" -eq 0 ] && printf '%s' "$outA" | grep -qE '^sha256:[0-9a-f]{64}$'; then
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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
