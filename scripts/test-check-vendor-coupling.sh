#!/usr/bin/env bash
# test-check-vendor-coupling.sh — self-test AND MUTATION CONTROL for
# scripts/check-vendor-coupling.sh.
#
# The point of this file is not coverage, it is FALSIFIABILITY. A ratchet that
# matches nothing passes forever and is indistinguishable, from CI's point of
# view, from a ratchet that works. So every claim about the gate is proved by
# EXECUTING it against a fixture tree and asserting the exit code — never by
# inspection, and never by a comment asserting the mechanism works.
#
# The two load-bearing assertions are deliberately opposite:
#   * inject a vendor reference into a CORE path  -> the gate MUST exit non-zero
#   * inject the IDENTICAL reference into an ADAPTER path -> it MUST exit 0
# Only the pair is meaningful. A test that only ever asserts failure passes just
# as happily against a gate that fails everything, which is exactly as useless as
# a gate that passes everything.
#
# Fixtures are hermetic: each case builds its own throwaway `git init` tree and
# its own manifest, driven through the gate's VENDOR_COUPLING_ROOT /
# VENDOR_COUPLING_MANIFEST overrides. The real repo is never modified. The fixture
# manifests declare a FICTIONAL vendor token, so this file contains no literal
# vendor token of its own and therefore stays at a zero allowance under the very
# gate it tests. Where the REAL token set has to be exercised (case 12) the tokens
# are copied out of the shipped manifest with `jq` at run time — proving the
# tokens we actually ship are detectable, without hard-coding one here.
#
# Fully offline and deterministic. macOS bash 3.2 / BSD userland safe: no GNU-only
# stat/sed/date flags, no `timeout`, counts validated numeric before arithmetic.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$repo_root/scripts/check-vendor-coupling.sh"
REAL_MANIFEST="$repo_root/loomwright/docs/vendor-coupling-manifest.json"
CI_YML="$repo_root/.github/workflows/ci.yml"
[ -f "$GATE" ] || { echo "FAIL: gate not found at $GATE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required" >&2; exit 1; }

pass=0
fail=0
check() { # check "name" expected_exit actual_exit
  if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "ok   - $1 (exit $3)"; else
    fail=$((fail+1)); echo "FAIL - $1 (expected exit $2, got $3)"; fi
}
contains() { # contains "name" haystack needle
  case "$2" in *"$3"*) pass=$((pass+1)); echo "ok   - $1";; *) fail=$((fail+1)); echo "FAIL - $1 (missing: $3)";; esac
}
lacks() { # lacks "name" haystack needle
  case "$2" in *"$3"*) fail=$((fail+1)); echo "FAIL - $1 (unexpectedly present: $3)";; *) pass=$((pass+1)); echo "ok   - $1";; esac
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/vendor-coupling-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# A fictional stand-in for a real harness variable. Using a fake token keeps this
# test file itself free of vendor references (see the header).
FTOK="ACME_HARNESS_ROOT"

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# mk_tree <dir> — a throwaway git work tree. `git ls-files` is the gate's
# enumeration mechanism, so a fixture MUST be a git repo with its files staged;
# `git add` (no commit) is enough to populate the index, and needs no identity
# config, which keeps this hermetic on a bare CI runner.
mk_tree() {
  mkdir -p "$1"
  ( cd "$1" && git -c init.defaultBranch=main init -q . ) >/dev/null 2>&1
}

# put <tree> <relpath> <line>... — write a file with the given lines.
put() {
  local tree="$1" rel="$2"; shift 2
  mkdir -p "$tree/$(dirname "$rel")"
  : > "$tree/$rel"
  local l
  for l in "$@"; do printf '%s\n' "$l" >> "$tree/$rel"; done
}

stage() { ( cd "$1" && git add -A ) >/dev/null 2>&1; }

# clone_tree <src> <dest> — a byte copy of a staged fixture tree (index and all),
# so a mutation case differs from its baseline by exactly the injected line.
clone_tree() { mkdir -p "$(dirname "$2")"; cp -R "$1" "$2"; }

# mk_manifest <file> <allowances-json> [tokens-json] [unclassified-default]
mk_manifest() {
  local out="$1" allow="$2" tokens="${3:-}" unc="${4:-core}"
  [ -n "$tokens" ] || tokens="$(printf '["%s"]' "$FTOK")"
  cat > "$out" <<JSON
{
  "scan_roots": ["core", "adapter", "coupled", "elsewhere"],
  "vendor_tokens": $tokens,
  "unclassified_default": "$unc",
  "classes": {
    "adapter": { "globs": ["adapter/*", "core/exempt-seam.sh"] },
    "coupled": { "globs": ["coupled/*"] },
    "core":    { "globs": ["core/*"] }
  },
  "allowances": $allow
}
JSON
}

# run_gate <tree> <manifest> -> sets OUT, RC
run_gate() {
  OUT="$(VENDOR_COUPLING_ROOT="$1" VENDOR_COUPLING_MANIFEST="$2" bash "$GATE" 2>&1)"
  RC=$?
}

# ---------------------------------------------------------------------------
# The baseline fixture, reused by cases 1-6.
#   core/gate.sh      2 references, allowance 2  (at its baseline)
#   core/clean.sh     0 references, no allowance (a currently-clean core file)
#   adapter/cmd.md    2 references, never counted
#   core/exempt-seam.sh  stands in for resolve-loomwright-root.sh: a single-file
#                        ADAPTER exemption living INSIDE the CORE glob
# ---------------------------------------------------------------------------
BASE="$TMP/base/tree"
mk_tree "$BASE"
put "$BASE" "core/gate.sh"        "#!/bin/sh" "echo \"\$$FTOK\"" "cd \"\$$FTOK\" || exit 1"
put "$BASE" "core/clean.sh"       "#!/bin/sh" "echo portable"
put "$BASE" "core/exempt-seam.sh" "#!/bin/sh" "echo \"\$$FTOK\"" "echo \"\$$FTOK\""
put "$BASE" "adapter/cmd.md"      "# command" "uses \$$FTOK" "and \$$FTOK again"
put "$BASE" "coupled/skill.md"    "# skill"   "mentions \$$FTOK"
stage "$BASE"

BASE_ALLOW='{"core/gate.sh": 2, "coupled/skill.md": 1}'
mk_manifest "$TMP/base/manifest.json" "$BASE_ALLOW"

# ---------------------------------------------------------------------------
# Case 1 — baseline tree is at its declared allowances -> exit 0.
# Also proves the ADAPTER-inside-CORE exemption (core/exempt-seam.sh carries 2
# references and has NO allowance): if adapter globs were not matched first, or
# not matched at all, this case would fail. That is the hermetic form of "the
# LOOMWRIGHT_ROOT resolver is not flagged by the gate it ships with".
# ---------------------------------------------------------------------------
run_gate "$BASE" "$TMP/base/manifest.json"
check "case1 baseline at allowance exits 0" 0 "$RC"
contains "case1 reports the core path"      "$OUT" "core/gate.sh"
lacks    "case1 has no BREACH row"          "$OUT" "BREACH"
lacks    "case1 never counts the adapter-exempt seam" "$OUT" "core/exempt-seam.sh"
lacks    "case1 never counts the adapter dir"         "$OUT" "adapter/cmd.md"

# ---------------------------------------------------------------------------
# Case 2 — MUTATION CONTROL (the whole reason this file exists).
# Inject ONE more vendor reference into a CORE path already at its allowance.
# The gate MUST exit non-zero and MUST name the path with declared-vs-actual.
# ---------------------------------------------------------------------------
MUT="$TMP/mut/tree"
clone_tree "$BASE" "$MUT"
printf 'export PATH="$%s/bin:$PATH"\n' "$FTOK" >> "$MUT/core/gate.sh"
stage "$MUT"
run_gate "$MUT" "$TMP/base/manifest.json"
check "case2 MUTATION: new core reference exits non-zero" 1 "$RC"
contains "case2 shows a BREACH row"          "$OUT" "BREACH"
contains "case2 names the offending path"    "$OUT" "core/gate.sh"
contains "case2 prints actual count (3)"     "$OUT" "3"
contains "case2 prints declared allowance"   "$OUT" "2"
contains "case2 says how to fix it"          "$OUT" "raise the allowance"

# ---------------------------------------------------------------------------
# Case 3 — INVERSE CONTROL. The IDENTICAL injection into an ADAPTER path must
# still exit 0. Without this, case 2 would also pass against a gate that simply
# failed everything.
# ---------------------------------------------------------------------------
ADP="$TMP/adp/tree"
clone_tree "$BASE" "$ADP"
printf 'export PATH="$%s/bin:$PATH"\n' "$FTOK" >> "$ADP/adapter/cmd.md"
printf 'and $%s once more\n' "$FTOK" >> "$ADP/adapter/cmd.md"
stage "$ADP"
run_gate "$ADP" "$TMP/base/manifest.json"
check "case3 INVERSE: same injection in an adapter path exits 0" 0 "$RC"
lacks "case3 has no BREACH row" "$OUT" "BREACH"

# ---------------------------------------------------------------------------
# Case 4 — a currently-CLEAN core file (allowance 0 by omission) gets its FIRST
# reference -> breach. This is the case that makes the ratchet bite for the ~98
# core files that carry no allowance entry at all.
# ---------------------------------------------------------------------------
NEW="$TMP/new/tree"
clone_tree "$BASE" "$NEW"
printf 'echo "$%s"\n' "$FTOK" >> "$NEW/core/clean.sh"
stage "$NEW"
run_gate "$NEW" "$TMP/base/manifest.json"
check "case4 first reference in a clean core file exits non-zero" 1 "$RC"
contains "case4 names the newly-coupled file" "$OUT" "core/clean.sh"

# ---------------------------------------------------------------------------
# Case 5 — RAISE IN THE SAME COMMIT. The breached tree from case 2, with the
# allowance raised in the manifest, passes. The raise is a visible diff, which is
# the entire review mechanism.
# ---------------------------------------------------------------------------
mk_manifest "$TMP/base/manifest-raised.json" '{"core/gate.sh": 3, "coupled/skill.md": 1}'
run_gate "$MUT" "$TMP/base/manifest-raised.json"
check "case5 allowance raised in the same commit exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# Case 6 — ONE-DIRECTIONAL. actual BELOW the declared allowance passes; the
# ratchet must never demand exact equality, or every improvement breaks CI.
# ---------------------------------------------------------------------------
mk_manifest "$TMP/base/manifest-slack.json" '{"core/gate.sh": 9, "coupled/skill.md": 4}'
run_gate "$BASE" "$TMP/base/manifest-slack.json"
check "case6 actual below allowance exits 0 (debt paid down)" 0 "$RC"
contains "case6 reports the headroom" "$OUT" "below allowance"

# ---------------------------------------------------------------------------
# Case 7 — UNCLASSIFIED DEFAULT. A path matched by no class glob is CORE with
# allowance 0, so a brand-new directory cannot become a coupling haven.
# ---------------------------------------------------------------------------
UNC="$TMP/unc/tree"
clone_tree "$BASE" "$UNC"
put "$UNC" "elsewhere/brandnew.sh" "#!/bin/sh" "echo \"\$$FTOK\""
stage "$UNC"
run_gate "$UNC" "$TMP/base/manifest.json"
check "case7 unclassified path defaults to core+0 -> non-zero" 1 "$RC"
contains "case7 names the unclassified file" "$OUT" "elsewhere/brandnew.sh"

# ---------------------------------------------------------------------------
# Case 8 — FAIL-CLOSED CONFIGURATION ERRORS. Each of these is a way the ratchet
# could be silently neutered, so each must be an exit-1 ERROR, never a pass.
# ---------------------------------------------------------------------------
run_gate "$BASE" "$TMP/base/nonexistent-manifest.json"
check "case8a missing manifest exits non-zero" 1 "$RC"

printf '{ this is not json\n' > "$TMP/base/malformed.json"
run_gate "$BASE" "$TMP/base/malformed.json"
check "case8b malformed manifest exits non-zero" 1 "$RC"
contains "case8b explains it failed closed" "$OUT" "not valid JSON"

mk_manifest "$TMP/base/no-tokens.json" "$BASE_ALLOW" '[]'
run_gate "$BASE" "$TMP/base/no-tokens.json"
check "case8c empty vendor_tokens exits non-zero (a no-token ratchet matches nothing)" 1 "$RC"

mk_manifest "$TMP/base/adapter-default.json" "$BASE_ALLOW" '' 'adapter'
run_gate "$BASE" "$TMP/base/adapter-default.json"
check "case8d unclassified_default=adapter is rejected" 1 "$RC"
contains "case8d explains the blanket-exemption risk" "$OUT" "exempt"

# scan_roots that match nothing -> a 0-file scan is a false green, not a pass.
cat > "$TMP/base/empty-scope.json" <<JSON
{
  "scan_roots": ["no-such-dir"],
  "vendor_tokens": ["$FTOK"],
  "unclassified_default": "core",
  "classes": { "adapter": { "globs": [] }, "coupled": { "globs": [] }, "core": { "globs": ["*"] } },
  "allowances": {}
}
JSON
run_gate "$BASE" "$TMP/base/empty-scope.json"
check "case8e zero-file scan exits non-zero (no empty ratchet)" 1 "$RC"

# A non-git scan root must fail, not fall back to `find`: a fallback would mean
# this self-test exercises a different enumeration path from the one CI runs.
NOGIT="$TMP/nogit/tree"
mkdir -p "$NOGIT/core"
printf 'echo "$%s"\n' "$FTOK" > "$NOGIT/core/x.sh"
run_gate "$NOGIT" "$TMP/base/manifest.json"
check "case8f non-git scan root exits non-zero" 1 "$RC"

# A scan root containing whitespace would word-split into two wrong pathspecs and
# silently SHRINK the scanned set — a fail-open shaped exactly like the one this
# gate exists to prevent, so it is rejected rather than mis-scanned.
cat > "$TMP/base/spacey-root.json" <<JSON
{
  "scan_roots": ["core", "two words"],
  "vendor_tokens": ["$FTOK"],
  "unclassified_default": "core",
  "classes": { "adapter": { "globs": [] }, "coupled": { "globs": [] }, "core": { "globs": ["core/*"] } },
  "allowances": {"core/gate.sh": 2, "core/exempt-seam.sh": 2}
}
JSON
run_gate "$BASE" "$TMP/base/spacey-root.json"
check "case8g a whitespace-bearing scan root is rejected, not silently mis-scanned" 1 "$RC"
contains "case8g explains the split-pathspec risk" "$OUT" "whitespace"

# Control for case8g: the SAME manifest with the whitespace root removed passes,
# so 8g proves the guard fires rather than that the fixture was broken anyway.
cat > "$TMP/base/spacey-root-fixed.json" <<JSON
{
  "scan_roots": ["core"],
  "vendor_tokens": ["$FTOK"],
  "unclassified_default": "core",
  "classes": { "adapter": { "globs": [] }, "coupled": { "globs": [] }, "core": { "globs": ["core/*"] } },
  "allowances": {"core/gate.sh": 2, "core/exempt-seam.sh": 2}
}
JSON
run_gate "$BASE" "$TMP/base/spacey-root-fixed.json"
check "case8g control: the same manifest without the whitespace root passes" 0 "$RC"

# ---------------------------------------------------------------------------
# Case 9 — SELF-CLEANING MANIFEST. An allowance for a path that does not exist,
# or for an ADAPTER path, is an ERROR. The second half closes the loophole of
# granting an allowance as a back-door reclassification.
# ---------------------------------------------------------------------------
mk_manifest "$TMP/base/orphan.json" '{"core/gate.sh": 2, "coupled/skill.md": 1, "core/deleted-long-ago.sh": 4}'
run_gate "$BASE" "$TMP/base/orphan.json"
check "case9a allowance for a nonexistent path exits non-zero" 1 "$RC"
contains "case9a names the stale entry" "$OUT" "core/deleted-long-ago.sh"

mk_manifest "$TMP/base/adapter-allow.json" '{"core/gate.sh": 2, "coupled/skill.md": 1, "adapter/cmd.md": 3}'
run_gate "$BASE" "$TMP/base/adapter-allow.json"
check "case9b allowance for an ADAPTER path exits non-zero" 1 "$RC"
contains "case9b explains adapters are never counted" "$OUT" "ADAPTER-classified"

# ---------------------------------------------------------------------------
# Case 10 — COUPLED paths are ratcheted too (they are grandfathered debt, not an
# exemption): adding a reference to one breaches just like CORE.
# ---------------------------------------------------------------------------
CPL="$TMP/cpl/tree"
clone_tree "$BASE" "$CPL"
printf 'another $%s\n' "$FTOK" >> "$CPL/coupled/skill.md"
stage "$CPL"
run_gate "$CPL" "$TMP/base/manifest.json"
check "case10 new reference in a COUPLED path exits non-zero" 1 "$RC"
contains "case10 names the coupled path" "$OUT" "coupled/skill.md"

# ---------------------------------------------------------------------------
# Case 11 — OCCURRENCES, NOT LINES. Two references on ONE line must count as 2.
# A line-based counter would let the second reference hide, and this case is the
# only thing standing between the ratchet and that evasion.
# ---------------------------------------------------------------------------
ONE="$TMP/oneline/tree"
clone_tree "$BASE" "$ONE"
put "$ONE" "core/clean.sh" "#!/bin/sh" "cp \"\$$FTOK/a\" \"\$$FTOK/b\""
stage "$ONE"
mk_manifest "$TMP/base/oneline.json" '{"core/gate.sh": 2, "coupled/skill.md": 1, "core/clean.sh": 1}'
run_gate "$ONE" "$TMP/base/oneline.json"
check "case11 two references on one line count as 2, not 1" 1 "$RC"
contains "case11 names the file" "$OUT" "core/clean.sh"

# ---------------------------------------------------------------------------
# Case 12 — THE SHIPPED TOKEN SET ACTUALLY BITES.
# Every case above uses a fictional token, which would pass just as well if the
# tokens we really ship were malformed and matched nothing. So: read the REAL
# `vendor_tokens` out of the shipped manifest, and assert that EACH one, on its
# own, breaches a CORE fixture. Per-token rather than all-at-once, because a
# single dead token would otherwise be masked by its neighbours.
# ---------------------------------------------------------------------------
if [ -f "$REAL_MANIFEST" ]; then
  real_tokens="$(jq -r '.vendor_tokens[]' "$REAL_MANIFEST" 2>/dev/null)"
  ntok=0
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    ntok=$((ntok + 1))
    T="$TMP/real$ntok/tree"
    mk_tree "$T"
    mkdir -p "$T/core"
    printf 'reference: %s\n' "$tok" > "$T/core/probe.sh"
    stage "$T"
    # A manifest that declares ONLY this one real token.
    jq -n --arg t "$tok" '{
      scan_roots: ["core"],
      vendor_tokens: [$t],
      unclassified_default: "core",
      classes: { adapter: { globs: [] }, coupled: { globs: [] }, core: { globs: ["core/*"] } },
      allowances: {}
    }' > "$TMP/real$ntok/manifest.json"
    run_gate "$T" "$TMP/real$ntok/manifest.json"
    check "case12 shipped vendor token #$ntok is detected (breaches a core fixture)" 1 "$RC"
  done <<EOF
$real_tokens
EOF
  if [ "$ntok" -eq 0 ]; then
    fail=$((fail+1)); echo "FAIL - case12 the shipped manifest declares no vendor_tokens"
  else
    pass=$((pass+1)); echo "ok   - case12 exercised all $ntok shipped vendor tokens individually"
  fi
else
  fail=$((fail+1)); echo "FAIL - case12 shipped manifest not found at $REAL_MANIFEST"
fi

# ---------------------------------------------------------------------------
# Case 13 — FAIL-CLOSED INVARIANT (CLAUDE.md §"Failure-Mode Invariants").
# The gate is a correctness gate, not a runtime emitter, so neither it nor its CI
# invocation may carry `|| true` — that would silently neuter it.
# ---------------------------------------------------------------------------
# Comment lines are excluded deliberately: both files DISCUSS `|| true` in prose
# explaining why they must not use it, and a grep that counted those would be a
# false positive of exactly the kind CLAUDE.md's `gh pr merge --squash` invariant
# check filters out. What matters is an EXECUTABLE `|| true`.
count_uncommented() { # count_uncommented <file> <needle> -> occurrences on non-comment lines
  awk -v needle="$2" '{ l=$0; sub(/^[[:space:]]+/, "", l); if (l ~ /^#/) next; if (index($0, needle) > 0) n++ } END { print n+0 }' "$1"
}

gate_or_true="$(count_uncommented "$GATE" '|| true')"
case "$gate_or_true" in ''|*[!0-9]*) gate_or_true=-1 ;; esac
check "case13a the gate carries no executable '|| true'" 0 "$gate_or_true"

# Mutation control ON THE CONTROL: the same counter must SEE a real `|| true` when
# one exists, otherwise case13a would pass against a counter that reports 0 for
# everything. Asserted against a fixture, not against the gate.
printf '#!/bin/sh\n# a comment mentioning || true\nfoo || true\n' > "$TMP/or-true-probe.sh"
probe="$(count_uncommented "$TMP/or-true-probe.sh" '|| true')"
check "case13b the '|| true' counter detects a real one (and ignores the comment)" 1 "$probe"

# ---------------------------------------------------------------------------
# Case 14 — THE GATE IS ACTUALLY WIRED INTO CI.
# Root `scripts/` is NOT matched by ci.yml's `loomwright/scripts/test-*.sh`
# anti-drift glob, so this test and the gate only ever run if ci.yml names them
# explicitly. A mutation control that CI never invokes is not a control — so the
# wiring is asserted here rather than trusted.
# ---------------------------------------------------------------------------
if [ -f "$CI_YML" ]; then
  ci="$(cat "$CI_YML")"
  contains "case14a ci.yml invokes the gate"          "$ci" "scripts/check-vendor-coupling.sh"
  contains "case14b ci.yml invokes this self-test"    "$ci" "scripts/test-check-vendor-coupling.sh"
  # No `|| true` on either invocation (fail-CLOSED correctness gate).
  wired_or_true="$(awk '{ l=$0; sub(/^[[:space:]]+/, "", l); if (l ~ /^#/) next; if (index($0, "check-vendor-coupling.sh") > 0 && index($0, "|| true") > 0) n++ } END { print n+0 }' "$CI_YML")"
  case "$wired_or_true" in ''|*[!0-9]*) wired_or_true=-1 ;; esac
  check "case14c no '|| true' on either CI invocation" 0 "$wired_or_true"
else
  fail=$((fail+1)); echo "FAIL - case14 ci.yml not found at $CI_YML"
fi

# ---------------------------------------------------------------------------
# Case 15 — LIVE REPO. The shipped manifest's declared allowances must equal or
# exceed what the gate measures on this checkout: a baseline that was wrong on
# day one would grandfather coupling nobody reviewed.
# ---------------------------------------------------------------------------
OUT="$(cd "$repo_root" && bash "$GATE" 2>&1)"; RC=$?
check "case15 live repo passes its own ratchet" 0 "$RC"
contains "case15 live run reports its scan" "$OUT" "files scanned:"

# ---------------------------------------------------------------------------
# Case 16 — `--print-allowances` is the regeneration mechanism, so it is proved
# by EXECUTION, not by reading. This flag is what produces every number in the
# committed manifest ("never hand-typed"), which makes it the highest-stakes
# untested path in the gate: if it silently broke, CI would stay green and the
# next regeneration would emit WRONG numbers that still LOOK measured. Verified
# three ways — it emits valid JSON, the values equal what the gate enforces, and
# (case 16d) it is not a constant echo of the manifest it was handed.
# ---------------------------------------------------------------------------
PA_OUT="$(VENDOR_COUPLING_ROOT="$BASE" VENDOR_COUPLING_MANIFEST="$TMP/base/manifest.json" \
          bash "$GATE" --print-allowances 2>&1)"; PA_RC=$?
check "case16a --print-allowances exits 0" 0 "$PA_RC"

printf '%s' "$PA_OUT" | jq -e . >/dev/null 2>&1
check "case16b --print-allowances emits parseable JSON" 0 $?

# The values must equal what the gate ENFORCES, so a regenerated manifest is
# green by construction. core/gate.sh carries 2 references in the baseline tree.
PA_GATE="$(printf '%s' "$PA_OUT" | jq -r '(.allowances // .)["core/gate.sh"] // "ABSENT"' 2>/dev/null)"
if [ "$PA_GATE" = "2" ]; then pass=$((pass+1)); echo "ok   - case16c printed allowance equals the enforced count"
else fail=$((fail+1)); echo "FAIL - case16c printed allowance for core/gate.sh: expected 2, got '$PA_GATE'"; fi

# The ADAPTER-exempt seam must NOT appear: an allowance for an adapter path is an
# ERROR elsewhere in this gate (case9b), so emitting one would regenerate a
# manifest that fails its own check.
PA_SEAM="$(printf '%s' "$PA_OUT" | jq -r '((.allowances // .) | has("core/exempt-seam.sh"))' 2>/dev/null)"
if [ "$PA_SEAM" = "false" ]; then pass=$((pass+1)); echo "ok   - case16c2 adapter-exempt seam is omitted from printed allowances"
else fail=$((fail+1)); echo "FAIL - case16c2 adapter-exempt seam leaked into printed allowances ($PA_SEAM)"; fi

# case16d — MUTATION CONTROL for the flag itself. Add a reference to a clean core
# file; the printed value must MOVE. Without this, cases 16a-c would still pass if
# --print-allowances simply echoed the manifest it was given, which is precisely
# the "measured-looking but not measured" failure this flag must never have.
PA_TREE="$TMP/printalw/tree"; clone_tree "$BASE" "$PA_TREE"
put "$PA_TREE" "core/clean.sh" "#!/bin/sh" "echo portable" "now uses \$$FTOK"
stage "$PA_TREE"
PA_OUT2="$(VENDOR_COUPLING_ROOT="$PA_TREE" VENDOR_COUPLING_MANIFEST="$TMP/base/manifest.json" \
           bash "$GATE" --print-allowances 2>&1)"
PA_CLEAN="$(printf '%s' "$PA_OUT2" | jq -r '(.allowances // .)["core/clean.sh"] // "ABSENT"' 2>/dev/null)"
if [ "$PA_CLEAN" = "1" ]; then pass=$((pass+1)); echo "ok   - case16d printed allowances track the tree, not the input manifest"
else fail=$((fail+1)); echo "FAIL - case16d expected core/clean.sh -> 1 after injection, got '$PA_CLEAN'"; fi

# ---------------------------------------------------------------------------
# Case 17 — an unknown argument is rejected, not silently ignored. A gate that
# ignored a typo'd flag would run in an unintended mode while looking fine.
# ---------------------------------------------------------------------------
UA_OUT="$(VENDOR_COUPLING_ROOT="$BASE" VENDOR_COUPLING_MANIFEST="$TMP/base/manifest.json" \
          bash "$GATE" --not-a-real-flag 2>&1)"; UA_RC=$?
check "case17 unknown argument exits non-zero" 1 "$UA_RC"
contains "case17 names the offending argument" "$UA_OUT" "--not-a-real-flag"

# ---------------------------------------------------------------------------
# Case 18 — a scan root that does not exist AT ALL fails closed. Distinct from
# case8f (exists but is not a git repo): this is the typo'd/moved-path case, and
# it must not degrade to "scanned nothing, found nothing, exit 0".
# ---------------------------------------------------------------------------
NX_OUT="$(VENDOR_COUPLING_ROOT="$TMP/definitely/not/here" VENDOR_COUPLING_MANIFEST="$TMP/base/manifest.json" \
          bash "$GATE" 2>&1)"; NX_RC=$?
check "case18 nonexistent scan root exits non-zero" 1 "$NX_RC"
lacks "case18 does not report a clean pass" "$NX_OUT" "breaches: 0 | errors: 0"

# ---------------------------------------------------------------------------
echo "---------------------------------------------------------------------------"
echo "test-check-vendor-coupling: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
