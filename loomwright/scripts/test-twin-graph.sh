#!/usr/bin/env bash
# test-twin-graph.sh — self-tests for the System Twin blast-radius graph helper (v14.15.0).
# Runs in isolated temp git repos (never touches the real .supervisor/twin). Mirrors
# test-system-contract.sh convention. Exit 0 = all pass, 1 = any failure.
#
# Fixtures are written through write-system-contract.sh so provenance is valid (never hand-write
# contract files for the positive cases) — the read-side gate is what twin-graph.sh trusts.
#
# Covers:
#   1. depends-on: A with dependencies [B, C] reports B and C as depends-on.
#   2. depended-on-by (derived): A and X both list B -> querying B reports A and X.
#   3. full blast-radius union: a subsystem that both depends-on and is-depended-on-by reports both.
#   4. fail-safe empty: no contract store -> empty groups, labels still present, exit 0.
#   5. provenance safety: a poisoned (un-provenanced) contract file is NOT counted in the graph.
#   6. both YAML shapes parse: inline `dependencies: [..]` and block-list form both read.
#   7. misattribution guard: a subsystem-less SECOND contract does NOT leak its deps onto the first
#      contract's subsystem id (proves the `cur=""` reset at the `### contract:` boundary).
#   8. no-arg listing mode: emits `EDGE: <a> -> <b>` lines plus the trailing `DONE` sentinel.
#   9. path/slash-based subsystem id round-trip: a `scripts/foo.sh`-style logical id (the canonical
#      id form per RESULT_SCHEMAS.md) is queryable by its slash form, not the sanitized filename.
#  10. incident_history co-residence: a contract carrying BOTH a block-list `dependencies` and an
#      `incident_history` block (the v14.15.0 enrichment's new co-resident field) reports ONLY the
#      real deps — incident_history flow-map entries must NOT leak in as phantom dependency edges.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-system-contract.sh"
GRAPH="$HERE/twin-graph.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init )

# Helper: write a contract whose body carries a parseable subsystem + dependencies (inline form).
# $1 = subsystem id, $2 = inline deps body (e.g. "[B, C]" or "[]")
write_inline() {
  ( cd "$TMP" && printf 'SYSTEM_CONTRACT:\nsubsystem: %s\ninvariants: [x]\ndependencies: %s\n' "$1" "$2" \
      | bash "$WRITE" --subsystem "$1" --source st1 ) >/dev/null 2>&1
}

echo "== 1. depends-on (A -> B, C) =="
write_inline "subA" "[subB, subC]"
out="$( cd "$TMP" && bash "$GRAPH" --subsystem "subA" )"
dep="$(printf '%s\n' "$out" | grep '^DEPENDS_ON:')"
if echo "$dep" | grep -q 'subB' && echo "$dep" | grep -q 'subC'; then ok "A reports B and C as depends-on"; else no "depends-on missing B/C (got: $dep)"; fi

echo "== 2. depended-on-by (derived: A and X both -> B) =="
write_inline "subX" "[subB]"
out="$( cd "$TMP" && bash "$GRAPH" --subsystem "subB" )"
dby="$(printf '%s\n' "$out" | grep '^DEPENDED_ON_BY:')"
if echo "$dby" | grep -q 'subA' && echo "$dby" | grep -q 'subX'; then ok "B reports A and X as depended-on-by"; else no "depended-on-by missing A/X (got: $dby)"; fi

echo "== 3. full blast-radius union (both groups) =="
# subB depends on nothing here but is depended-on-by A and X (covered above). Now make subC depend
# on subB so subB both depends-on (none) and... use subM: depends on subB AND is depended-on-by subA.
# subA already depends on subC; give subC a dependency so subC has BOTH groups populated.
write_inline "subC" "[subZ]"
out="$( cd "$TMP" && bash "$GRAPH" --subsystem "subC" )"
dep="$(printf '%s\n' "$out" | grep '^DEPENDS_ON:')"
dby="$(printf '%s\n' "$out" | grep '^DEPENDED_ON_BY:')"
if echo "$dep" | grep -q 'subZ' && echo "$dby" | grep -q 'subA'; then ok "subC reports DEPENDS_ON subZ AND DEPENDED_ON_BY subA"; else no "union incomplete (dep: $dep | dby: $dby)"; fi

echo "== 4. fail-safe empty (no contract store) =="
FRESH="$(mktemp -d)"; ( cd "$FRESH" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
out="$( cd "$FRESH" && bash "$GRAPH" --subsystem "anything" )"; rc=$?
dep="$(printf '%s\n' "$out" | grep '^DEPENDS_ON:')"
dby="$(printf '%s\n' "$out" | grep '^DEPENDED_ON_BY:')"
# Both labels present, both empty (nothing after the colon), exit 0.
if [ "$rc" -eq 0 ] && [ "$dep" = "DEPENDS_ON:" ] && [ "$dby" = "DEPENDED_ON_BY:" ]; then ok "no store -> empty groups (labels present), exit 0"; else no "fail-safe empty wrong (rc=$rc dep='$dep' dby='$dby')"; fi
rm -rf "$FRESH"

echo "== 5. provenance safety (poisoned contract not counted) =="
# Drop an un-provenanced contract that claims subB depends on a poison id. It must NOT appear in the
# graph because twin-graph.sh reads via read-system-contract.sh (which drops un-provenanced files).
printf 'SYSTEM_CONTRACT:\nsubsystem: poisonSub\ndependencies: [subB]\n' > "$TMP/.supervisor/twin/contracts/poisonSub.md"
out="$( cd "$TMP" && bash "$GRAPH" --subsystem "subB" )"
dby="$(printf '%s\n' "$out" | grep '^DEPENDED_ON_BY:')"
if echo "$dby" | grep -q 'poisonSub'; then no "poisoned contract counted in graph (provenance gate bypassed)"; else ok "poisoned (un-provenanced) contract NOT counted in graph"; fi
rm -f "$TMP/.supervisor/twin/contracts/poisonSub.md"

echo "== 6. both YAML shapes parse (inline + block-list) =="
# inline already exercised (subA). Add a block-list fixture and assert it reads.
( cd "$TMP" && printf 'SYSTEM_CONTRACT:\nsubsystem: %s\ninvariants: [x]\ndependencies:\n  - subP\n  - subQ\n' "subBlock" \
    | bash "$WRITE" --subsystem "subBlock" --source st1 ) >/dev/null 2>&1
out="$( cd "$TMP" && bash "$GRAPH" --subsystem "subBlock" )"
dep="$(printf '%s\n' "$out" | grep '^DEPENDS_ON:')"
if echo "$dep" | grep -q 'subP' && echo "$dep" | grep -q 'subQ'; then ok "block-list dependencies parsed (subP, subQ)"; else no "block-list shape not parsed (got: $dep)"; fi
# and confirm inline shape still parses for the same store
out2="$( cd "$TMP" && bash "$GRAPH" --subsystem "subA" )"
printf '%s\n' "$out2" | grep '^DEPENDS_ON:' | grep -q 'subB' && ok "inline dependencies parsed alongside block-list" || no "inline shape regressed when block-list present"

echo "== 7. misattribution guard (subsystem-less 2nd contract must not leak onto 1st) =="
# Fresh store so the assertion is isolated from the shared $TMP fixtures above. First contract has a
# subsystem AND a dependency; second contract has dependencies: but NO subsystem: line. The read
# gate still emits it, but with the cur="" reset at the ### contract: boundary it must contribute
# ZERO edges and must NOT leak its dep onto the FIRST contract's subsystem id.
MIS="$(mktemp -d)"; ( cd "$MIS" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$MIS" && printf 'SYSTEM_CONTRACT:\nsubsystem: %s\ninvariants: [x]\ndependencies: [firstDep]\n' "firstSub" \
    | bash "$WRITE" --subsystem "firstSub" --source st1 ) >/dev/null 2>&1
# Second contract: a body with dependencies: but deliberately NO subsystem: line. (--subsystem only
# governs the on-disk filename/provenance; the GRAPH keys off the body's subsystem: line, which is absent.)
( cd "$MIS" && printf 'SYSTEM_CONTRACT:\ninvariants: [x]\ndependencies: [leakedDep]\n' \
    | bash "$WRITE" --subsystem "secondNoSub" --source st1 ) >/dev/null 2>&1
out="$( cd "$MIS" && bash "$GRAPH" --subsystem "firstSub" )"
dep="$(printf '%s\n' "$out" | grep '^DEPENDS_ON:')"
if echo "$dep" | grep -q 'firstDep' && ! echo "$dep" | grep -q 'leakedDep'; then ok "subsystem-less contract does not misattribute its dep onto the previous contract"; else no "misattribution NOT prevented (firstSub DEPENDS_ON='$dep')"; fi
rm -rf "$MIS"

echo "== 8. no-arg listing mode (EDGE lines + DONE sentinel) =="
# Reuse the shared $TMP store (has subA -> subB/subC among others). No-arg mode lists every edge.
out="$( cd "$TMP" && bash "$GRAPH" )"
if printf '%s\n' "$out" | grep -qE '^EDGE: subA -> subB$' && printf '%s\n' "$out" | grep -qx 'DONE'; then ok "no-arg mode lists EDGE lines and ends with DONE sentinel"; else no "no-arg listing wrong (got: $out)"; fi

echo "== 9. path/slash-based subsystem id round-trip =="
# The canonical id form per RESULT_SCHEMAS.md is a logical name or path, e.g. "scripts/foo.sh".
# The on-disk filename is sanitized (scripts-foo.sh) but the body preserves the slash form, which is
# what the graph keys off — so querying with the slash id must return its edges.
( cd "$TMP" && printf 'SYSTEM_CONTRACT:\nsubsystem: %s\ninvariants: [x]\ndependencies: [libBar]\n' "scripts/foo.sh" \
    | bash "$WRITE" --subsystem "scripts/foo.sh" --source st1 ) >/dev/null 2>&1
out="$( cd "$TMP" && bash "$GRAPH" --subsystem "scripts/foo.sh" )"
dep="$(printf '%s\n' "$out" | grep '^DEPENDS_ON:')"
if echo "$dep" | grep -q 'libBar'; then ok "slash-based subsystem id queryable by its logical (slash) form"; else no "slash id round-trip failed (got: $dep)"; fi

echo "== 10. incident_history co-residence (no phantom edges from the new field) =="
# The v14.15.0 builder writes incident_history as a block-list of inline flow-maps directly after
# dependencies. Assert twin-graph reports ONLY the real dep and does NOT leak any incident_history
# token (date/kind/summary/source or the flow-map brace) in as a phantom dependency edge.
( cd "$TMP" && printf 'SYSTEM_CONTRACT:\nsubsystem: %s\ninvariants: [x]\ndependencies:\n  - realDep\nincident_history:\n  - {date: "2026-06-06T00:00:00Z", kind: self_heal_fix, summary: "fixed thing", source: "sess1"}\n  - {date: "2026-06-06T01:00:00Z", kind: conformance_violation, summary: "diverged", source: "sess2"}\nbehavioral_specs: [y]\n' "subIncident" \
    | bash "$WRITE" --subsystem "subIncident" --source st1 ) >/dev/null 2>&1
out="$( cd "$TMP" && bash "$GRAPH" --subsystem "subIncident" )"
dep="$(printf '%s\n' "$out" | grep '^DEPENDS_ON:')"
if echo "$dep" | grep -q 'realDep' \
   && ! echo "$dep" | grep -qE 'date|kind|summary|source|self_heal_fix|conformance_violation|[{}]'; then
  ok "incident_history co-resident with dependencies leaks no phantom edges (only realDep)"
else
  no "incident_history leaked into DEPENDS_ON (got: $dep)"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
