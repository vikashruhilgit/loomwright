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
# a gate that passes everything. The same pairing is used for the schema-2
# mechanisms (cases 21-26): an adapter_frontmatter BODY injection must fail while
# the identical FRONTMATTER injection must not move the count; a raise without a
# new reason must fail while the same raise with an added/changed reason passes;
# an overlapping token must count once, whichever order the manifest lists it in.
# Later cases keep the pairing: an exemption, a dropped token or a raised
# frontmatter bound fails without a policy reason and passes with one (24t); an
# over-bound frontmatter counts while an at-bound one does not (28); a quoted-name
# or NUL-bearing file breaches while the same file with its allowance passes (30).
# Where the gate itself is mutated (24s, 28, 30), the mutant is gated non-empty,
# byte-different and `bash -n` clean before its result is trusted.
#
# Fixtures are hermetic: each case builds its own throwaway `git init` tree and
# its own manifest, driven through the gate's VENDOR_COUPLING_ROOT /
# VENDOR_COUPLING_MANIFEST overrides. The real repo is never modified. The fixture
# manifests declare a FICTIONAL vendor token, so this file contains no literal
# vendor token of its own and therefore stays at a zero allowance under the very
# gate it tests. Where the REAL token set has to be exercised (cases 12, 22c, 23i)
# the tokens are copied out of the shipped manifest with `jq` at run time — proving
# the tokens we actually ship are detectable, without hard-coding one here.
#
# The raise_check fixtures (case 24) COMMIT a base: they use inline identity and no
# signing, and pin VENDOR_COUPLING_BASE to the fixture commit, so no case depends
# on an origin remote or on the developer's git config.
#
# Fully offline and deterministic. macOS bash 3.2 / BSD userland safe: no GNU-only
# stat/sed/date flags, no `timeout`, counts validated numeric before arithmetic.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail
# CI sets these for the GATE step (base ref + require-base); a fixture must never
# inherit them, or every hermetic case would be judged against the real repo's base.
unset VENDOR_COUPLING_BASE VENDOR_COUPLING_REQUIRE_BASE

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
# The tokens array becomes ONE fictional token class. Cases that need several
# classes write their manifest with `jq` directly.
mk_manifest() {
  local out="$1" allow="$2" tokens="${3:-}" unc="${4:-core}"
  [ -n "$tokens" ] || tokens="$(printf '["%s"]' "$FTOK")"
  cat > "$out" <<JSON
{
  "scan_roots": ["core", "adapter", "coupled", "elsewhere", "agents"],
  "token_classes": { "fictional": { "tokens": $tokens } },
  "unclassified_default": "$unc",
  "classes": {
    "adapter": { "globs": ["adapter/*", "core/exempt-seam.sh"] },
    "adapter_frontmatter": { "globs": ["agents/*.md"], "max_frontmatter_lines": 60 },
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
check "case8c an empty token class exits non-zero (a no-token ratchet matches nothing)" 1 "$RC"

# 8c2 — the retired schema-1 flat list is REFUSED, not silently ignored: a manifest
# still carrying it would be read as declaring a token set its author never wrote.
jq --arg t "$FTOK" '. + {vendor_tokens: [$t]}' "$TMP/base/manifest.json" > "$TMP/base/legacy-flat.json"
run_gate "$BASE" "$TMP/base/legacy-flat.json"
check    "case8c2 a manifest still carrying the flat vendor_tokens list exits non-zero" 1 "$RC"
contains "case8c2 names the replacement" "$OUT" "token_classes"
jq 'del(.token_classes)' "$TMP/base/manifest.json" > "$TMP/base/no-classes.json"
run_gate "$BASE" "$TMP/base/no-classes.json"
check    "case8c3 a manifest with no token_classes exits non-zero" 1 "$RC"

mk_manifest "$TMP/base/adapter-default.json" "$BASE_ALLOW" '' 'adapter'
run_gate "$BASE" "$TMP/base/adapter-default.json"
check "case8d unclassified_default=adapter is rejected" 1 "$RC"
contains "case8d explains the blanket-exemption risk" "$OUT" "exempt"

# scan_roots that match nothing -> a 0-file scan is a false green, not a pass.
cat > "$TMP/base/empty-scope.json" <<JSON
{
  "scan_roots": ["no-such-dir"],
  "token_classes": { "fictional": { "tokens": ["$FTOK"] } },
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
  "token_classes": { "fictional": { "tokens": ["$FTOK"] } },
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
  "token_classes": { "fictional": { "tokens": ["$FTOK"] } },
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
# tokens we really ship were malformed and matched nothing. So: read EVERY token
# of EVERY class out of the shipped manifest's `token_classes`, and assert that
# EACH one, on its own, breaches a CORE fixture. Per-token rather than
# all-at-once, because a single dead token would otherwise be masked by its
# neighbours.
# ---------------------------------------------------------------------------
if [ -f "$REAL_MANIFEST" ]; then
  real_tokens="$(jq -r '.token_classes[].tokens[]' "$REAL_MANIFEST" 2>/dev/null)"
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
      token_classes: { probe: { tokens: [$t] } },
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
    fail=$((fail+1)); echo "FAIL - case12 the shipped manifest declares no token_classes tokens"
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
  # The raise_check only RUNS in CI if main is resolvable there, and actions/checkout
  # fetches the PR ref alone at depth 1. Pin the explicit-refspec fetch, the base
  # override pointing at the ref it writes, and the require-base switch that turns a
  # skipped raise check into a failure; without all three the check skips in CI
  # forever and the reason rule never bites where it matters.
  contains "case14d ci.yml fetches main into a dedicated ref by explicit refspec" "$ci" "git fetch --no-tags --depth=1 origin +refs/heads/main:refs/vendor-coupling/base"
  contains "case14e ci.yml points VENDOR_COUPLING_BASE at that ref"               "$ci" "VENDOR_COUPLING_BASE: refs/vendor-coupling/base"
  contains "case14f ci.yml makes a skipped raise_check fail"                       "$ci" 'VENDOR_COUPLING_REQUIRE_BASE: "1"'
else
  fail=$((fail+1)); echo "FAIL - case14 ci.yml not found at $CI_YML"
fi

# ---------------------------------------------------------------------------
# Case 15 — LIVE REPO. The shipped manifest's declared allowances must equal or
# exceed what the gate measures on this checkout: a baseline that was wrong on
# day one would grandfather coupling nobody reviewed.
# ---------------------------------------------------------------------------
# case15_report <gate output> <gate rc> -> prints ONE ok/FAIL line, returns 1 on
# FAIL. A failure here is the live gate's own verdict, so the line says so and
# reprints the gate's BREACH/ERROR rows: one cause reads as one cause, not as a
# second, unrelated red entry. The assertion itself is unchanged (exit 0).
case15_report() {
  if [ "$2" -eq 0 ]; then echo "ok   - case15 live repo passes its own ratchet (exit 0)"; return 0; fi
  echo "FAIL - case15 live repo passes its own ratchet (expected exit 0, got $2) — this is the LIVE GATE's verdict (scripts/check-vendor-coupling.sh on this checkout), the same cause as that gate's own red entry; its BREACH/ERROR rows:"
  printf '%s\n' "$1" | grep -E '  (BREACH|ERROR) |^raise_check: ERROR' | sed 's/^/       /'
  return 1
}
OUT="$(cd "$repo_root" && bash "$GATE" 2>&1)"; RC=$?
if case15_report "$OUT" "$RC"; then pass=$((pass+1)); else fail=$((fail+1)); fi
contains "case15 live run reports its scan" "$OUT" "files scanned:"
contains "case15b live run prints the per-class report" "$OUT" "per token class"
contains "case15b live run prints the flat total"       "$OUT" "TOTAL (flat)"
# AC: the SDK spike's package manifest scores under sdk_binding (it scored 0 under
# the schema-1 token list). The class name is asserted, not a count.
sdk_row="$(printf '%s\n' "$OUT" | awk '$1 == "loomwright/sdk-spike/package.json"')"
contains "case15c sdk-spike/package.json is counted under sdk_binding" "$sdk_row" "sdk_binding="

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
# Case 19 — a malformed allowance is rejected even on a file with ZERO references.
# The breach loop validates allowance values too, but it only ever iterates files
# with actual > 0, so a garbage value on a currently-CLEAN path used to sit inert
# and undetected until someone added a reference to that file — surfacing an ERROR
# far later than a manifest sanity check should. 19b is the control that makes 19a
# meaningful: the SAME garbage on a file that DOES carry references was already
# caught, so without it this case could not distinguish the fix from the old
# behaviour.
# ---------------------------------------------------------------------------
mk_manifest "$TMP/base/nonint-clean.json" '{"core/gate.sh": 2, "coupled/skill.md": 1, "core/clean.sh": "TBD"}'
run_gate "$BASE" "$TMP/base/nonint-clean.json"
check    "case19a non-integer allowance on a zero-reference file exits non-zero" 1 "$RC"
contains "case19a names the offending path"  "$OUT" "core/clean.sh"
contains "case19a says why"                  "$OUT" "not a JSON non-negative integer"

mk_manifest "$TMP/base/nonint-hits.json" '{"core/gate.sh": "TBD", "coupled/skill.md": 1}'
run_gate "$BASE" "$TMP/base/nonint-hits.json"
check    "case19b control: same garbage on a referenced file also exits non-zero" 1 "$RC"
contains "case19b names that path too"       "$OUT" "core/gate.sh"

# 19c — a NEGATIVE allowance is not a valid count either, on a clean path.
mk_manifest "$TMP/base/negative.json" '{"core/gate.sh": 2, "coupled/skill.md": 1, "core/clean.sh": -1}'
run_gate "$BASE" "$TMP/base/negative.json"
check    "case19c negative allowance on a zero-reference file exits non-zero" 1 "$RC"

# ---------------------------------------------------------------------------
# Case 20 — count_mode is a DECLARED field, so it must mean something. An unknown
# value is rejected rather than silently ignored: a knob that accepts anything
# implies an alternate mode that does not exist, so someone setting "lines" would
# expect line-based counting and silently get occurrence counting instead. 20c is
# the control — omitting the field entirely must still pass, so the validation
# cannot be satisfied by simply rejecting every manifest.
# ---------------------------------------------------------------------------
mk_manifest "$TMP/base/cm-bad.json" "$BASE_ALLOW"
jq '. + {count_mode: "lines"}' "$TMP/base/cm-bad.json" > "$TMP/base/cm-bad2.json"
run_gate "$BASE" "$TMP/base/cm-bad2.json"
check    "case20a unknown count_mode exits non-zero" 1 "$RC"
contains "case20a names the field"        "$OUT" "count_mode"
contains "case20a echoes the bad value"   "$OUT" "lines"

jq '. + {count_mode: "occurrences"}' "$TMP/base/cm-bad.json" > "$TMP/base/cm-ok.json"
run_gate "$BASE" "$TMP/base/cm-ok.json"
check "case20b declared count_mode 'occurrences' passes" 0 "$RC"

# Control: the field is OPTIONAL. Omitting it must default to occurrences and pass,
# so case20a cannot be passing merely because the gate rejects unfamiliar manifests.
run_gate "$BASE" "$TMP/base/cm-bad.json"
check "case20c omitted count_mode defaults and passes" 0 "$RC"


# ===========================================================================
# Schema-2 cases: token classes, overlap, adapter_frontmatter, raise_check.
# ===========================================================================
# Fictional stand-ins for the real classes (see the header for why fictional).
FASK="ACME_ASK_TOOL"                 # stands in for the ask-user tool name
FPFX="ACME_HARNESS_"                 # stands in for the env-var PREFIX token
FSESS="ACME_HARNESS_SESSION_ID"      # stands in for the session-id token that CONTAINS the prefix

# mk_classes_manifest <file> <classes-json> <allowances-json> — a manifest with
# several token classes over the same fixture layout as mk_manifest.
mk_classes_manifest() {
  mk_manifest "$1" "$3"
  jq --argjson tc "$2" '.token_classes = $tc' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# ---------------------------------------------------------------------------
# Case 21 — TOKEN CLASSES. Each occurrence is attributed to its class, the report
# prints a total per class plus the flat total, and allowances stay per path
# (compared with the flat total).
# ---------------------------------------------------------------------------
TC="$TMP/tc/tree"; mk_tree "$TC"
put "$TC" "core/two.sh" "#!/bin/sh" "echo \"\$$FTOK\" $FASK" "$FASK again"
stage "$TC"
TC_CLASSES="$(jq -n --arg r "$FTOK" --arg a "$FASK" '{fict_root: {tokens: [$r]}, fict_ask: {tokens: [$a]}}')"
mk_classes_manifest "$TMP/tc/m.json" "$TC_CLASSES" '{"core/two.sh": 3}'
run_gate "$TC" "$TMP/tc/m.json"
check    "case21a three references across two classes, allowance 3 -> exit 0" 0 "$RC"
contains "case21a the row carries the per-class breakdown" "$OUT" "[fict_root=1 fict_ask=2]"
fr_line="$(printf '%s\n' "$OUT" | awk '$1 == "fict_root" {print $2}')"
fa_line="$(printf '%s\n' "$OUT" | awk '$1 == "fict_ask" {print $2}')"
tot_line="$(printf '%s\n' "$OUT" | awk '$1 == "TOTAL" && $2 == "(flat)" {print $3}')"
if [ "$fr_line" = "1" ] && [ "$fa_line" = "2" ] && [ "$tot_line" = "3" ]; then pass=$((pass+1)); echo "ok   - case21b per-class totals (1, 2) and flat total (3) are reported"
else fail=$((fail+1)); echo "FAIL - case21b per-class/flat totals: fict_root='$fr_line' fict_ask='$fa_line' total='$tot_line' (expected 1/2/3)"; fi
mk_classes_manifest "$TMP/tc/m2.json" "$TC_CLASSES" '{"core/two.sh": 2}'
run_gate "$TC" "$TMP/tc/m2.json"
check    "case21c the allowance is compared with the FLAT total across classes" 1 "$RC"

# A class with no tokens and a bad class name are errors.
mk_classes_manifest "$TMP/tc/m3.json" "$(jq -n --arg r "$FTOK" '{fict_root: {tokens: [$r]}, empty_one: {tokens: []}}')" '{"core/two.sh": 3}'
run_gate "$TC" "$TMP/tc/m3.json"
check    "case21d a token class with no tokens exits non-zero" 1 "$RC"
mk_classes_manifest "$TMP/tc/m4.json" "$(jq -n --arg r "$FTOK" '{"Bad-Name": {tokens: [$r]}}')" '{"core/two.sh": 3}'
run_gate "$TC" "$TMP/tc/m4.json"
check    "case21e a token class name outside [a-z0-9_] exits non-zero" 1 "$RC"

# ---------------------------------------------------------------------------
# Case 22 — NO DOUBLE COUNT ON OVERLAPPING TOKENS (leftmost-longest).
# One occurrence of the long token is ONE reference in ONE class — whatever order
# the manifest lists the tokens or classes in (an order-dependent result would be
# exactly the BSD-vs-GNU `grep -oF` ambiguity the awk pass exists to remove).
# ---------------------------------------------------------------------------
OV="$TMP/ov/tree"; mk_tree "$OV"
put "$OV" "core/sess.sh" "#!/bin/sh" "echo \"\$$FSESS\""
stage "$OV"
for order in short-first long-first; do
  if [ "$order" = "short-first" ]; then
    OV_CLASSES="$(jq -n --arg p "$FPFX" --arg s "$FSESS" '{fict_root: {tokens: [$p]}, fict_identity: {tokens: [$s]}}')"
  else
    OV_CLASSES="$(jq -n --arg p "$FPFX" --arg s "$FSESS" '{fict_identity: {tokens: [$s]}, fict_root: {tokens: [$p]}}')"
  fi
  mk_classes_manifest "$TMP/ov/m-$order.json" "$OV_CLASSES" '{"core/sess.sh": 1}'
  run_gate "$OV" "$TMP/ov/m-$order.json"
  check    "case22a ($order) one overlapping occurrence fits an allowance of 1" 0 "$RC"
  contains "case22a ($order) it is attributed to the LONGER token's class" "$OUT" "[fict_identity=1]"
  lacks    "case22a ($order) and never also to the prefix token's class" "$OUT" "fict_root=1"
  mk_classes_manifest "$TMP/ov/m0-$order.json" "$OV_CLASSES" '{}'
  run_gate "$OV" "$TMP/ov/m0-$order.json"
  check    "case22b ($order) control: the same occurrence at allowance 0 breaches (it IS counted)" 1 "$RC"
done
# A standalone prefix occurrence beside the long one is a SECOND reference.
OV2="$TMP/ov2/tree"; mk_tree "$OV2"
put "$OV2" "core/sess.sh" "#!/bin/sh" "echo \"\$${FPFX}OTHER \$$FSESS\""
stage "$OV2"
run_gate "$OV2" "$TMP/ov/m-short-first.json"
check    "case22b2 a separate prefix occurrence on the same line is a second reference" 1 "$RC"
contains "case22b2 one per class" "$OUT" "[fict_root=1 fict_identity=1]"

# 22c — the SHIPPED token set: for every pair of real tokens where one contains the
# other, one occurrence of the longer must count exactly once, for the longer
# token's class. If the manifest ever removes every overlap, there is nothing to
# double count and the case says so.
npairs=0
while IFS="$(printf '\t')" read -r short long lcls; do
  [ -n "$long" ] || continue
  npairs=$((npairs + 1))
  T="$TMP/realov$npairs/tree"; mk_tree "$T"; mkdir -p "$T/core"
  printf 'x %s y\n' "$long" > "$T/core/probe.sh"; stage "$T"
  jq '{scan_roots: ["core"], token_classes: .token_classes, unclassified_default: "core",
      classes: {adapter: {globs: []}, coupled: {globs: []}, core: {globs: ["core/*"]}}, allowances: {"core/probe.sh": 1}}' \
      "$REAL_MANIFEST" > "$TMP/realov$npairs/m.json"
  run_gate "$T" "$TMP/realov$npairs/m.json"
  check    "case22c shipped overlap pair #$npairs: one occurrence of the longer token fits allowance 1" 0 "$RC"
  contains "case22c shipped overlap pair #$npairs: attributed to the longer token's class only" "$OUT" "[$lcls=1]"
done <<EOF
$(jq -r '[.token_classes | to_entries[] | .key as $c | .value.tokens[] | {c: $c, t: .}] as $all
  | $all[] as $a | $all[] as $b | select($a.t != $b.t and ($b.t | contains($a.t))) | [$a.t, $b.t, $b.c] | @tsv' "$REAL_MANIFEST" 2>/dev/null)
EOF
if [ "$npairs" -eq 0 ]; then pass=$((pass+1)); echo "ok   - case22c the shipped token set has no overlapping pair (nothing to double count)"; fi

# 22d — a token declared twice (same or different class) is an ERROR: the class
# it should count for would be ambiguous.
mk_classes_manifest "$TMP/ov/dup.json" "$(jq -n --arg t "$FTOK" '{one: {tokens: [$t]}, two: {tokens: [$t]}}')" '{}'
run_gate "$OV" "$TMP/ov/dup.json"
check    "case22d a token declared in two classes exits non-zero" 1 "$RC"
contains "case22d says why"                                     "$OUT" "more than once"

# 22e — token_overlap_rule is validated like count_mode: an unknown value is
# rejected, the one implemented value passes (control).
jq '. + {token_overlap_rule: "first-declared"}' "$TMP/base/manifest.json" > "$TMP/ov/r-bad.json"
run_gate "$BASE" "$TMP/ov/r-bad.json"
check    "case22e unknown token_overlap_rule exits non-zero" 1 "$RC"
contains "case22e names the field" "$OUT" "token_overlap_rule"
jq '. + {token_overlap_rule: "leftmost-longest"}' "$TMP/base/manifest.json" > "$TMP/ov/r-ok.json"
run_gate "$BASE" "$TMP/ov/r-ok.json"
check    "case22e control: token_overlap_rule leftmost-longest passes" 0 "$RC"

# ---------------------------------------------------------------------------
# Case 23 — adapter_frontmatter: the leading YAML frontmatter of a file in this
# class is NOT counted; everything after it IS. Both directions are asserted.
# ---------------------------------------------------------------------------
FM="$TMP/fm/tree"; mk_tree "$FM"
put "$FM" "agents/a.md" "---" "name: a" "tools: $FASK" "---" "# body" "uses \$$FTOK"
stage "$FM"
FM_CLASSES="$(jq -n --arg r "$FTOK" --arg a "$FASK" '{fict_root: {tokens: [$r]}, fict_ask: {tokens: [$a]}}')"
mk_classes_manifest "$TMP/fm/m.json" "$FM_CLASSES" '{"agents/a.md": 1}'
run_gate "$FM" "$TMP/fm/m.json"
check    "case23a adapter_frontmatter baseline: frontmatter token uncounted, body token counted (allowance 1) -> exit 0" 0 "$RC"
contains "case23a the row is classified adapter_frontmatter" "$OUT" "adapter_frontmatter"
contains "case23a the body reference is the only one counted" "$OUT" "[fict_root=1]"
lacks    "case23a an allowance on an adapter_frontmatter path is NOT an adapter ERROR" "$OUT" "ADAPTER-classified"

# 23b — MUTATION CONTROL (AC): a new ask-user reference in the BODY, no allowance change.
FMB="$TMP/fmb/tree"; clone_tree "$FM" "$FMB"
printf 'then call %s\n' "$FASK" >> "$FMB/agents/a.md"; stage "$FMB"
if cmp -s "$FM/agents/a.md" "$FMB/agents/a.md" || [ ! -s "$FMB/agents/a.md" ]; then
  fail=$((fail+1)); echo "FAIL - case23b mutant is empty or identical to the original (vacuous control)"
fi
run_gate "$FMB" "$TMP/fm/m.json"
check    "case23b MUTATION: new ask-user token in an adapter_frontmatter BODY exits non-zero" 1 "$RC"
contains "case23b shows a BREACH row" "$OUT" "BREACH"

# 23c — INVERSE: the identical token added inside the FRONTMATTER leaves the count unchanged.
FMF="$TMP/fmf/tree"; mk_tree "$FMF"
put "$FMF" "agents/a.md" "---" "name: a" "tools: $FASK" "allowed: $FASK" "---" "# body" "uses \$$FTOK"
stage "$FMF"
run_gate "$FMF" "$TMP/fm/m.json"
check    "case23c INVERSE: the same token added in FRONTMATTER exits 0" 0 "$RC"
contains "case23c count unchanged (still only the body reference)" "$OUT" "[fict_root=1]"

# 23d — a file whose line 1 is not `---` has no frontmatter: counted whole.
put "$FM" "agents/nofm.md" "# no frontmatter" "tools: $FASK"
# 23e — `---` on line 2 does not open frontmatter either.
put "$FM" "agents/late.md" "" "---" "tools: $FASK" "---"
# 23f — a body `---` rule after a closed frontmatter is body: both body tokens count.
put "$FM" "agents/rule.md" "---" "tools: $FASK" "---" "one $FASK" "---" "two $FASK"
# 23g — an UNCLOSED frontmatter is counted whole (it must not hide a file).
put "$FM" "agents/open.md" "---" "tools: $FASK" "more $FASK"
stage "$FM"
run_gate "$FM" "$TMP/fm/m.json"
check    "case23d-g the four shapes are counted (allowance 0 each -> exit non-zero)" 1 "$RC"
row() { printf '%s\n' "$OUT" | awk -v p="$1" '$1 == p { print $3 }'; }
r_nofm="$(row agents/nofm.md)"; r_late="$(row agents/late.md)"; r_rule="$(row agents/rule.md)"; r_open="$(row agents/open.md)"
if [ "$r_nofm" = "1" ]; then pass=$((pass+1)); echo "ok   - case23d no line-1 '---' -> counted whole (1)"; else fail=$((fail+1)); echo "FAIL - case23d no-frontmatter file counted '$r_nofm', expected 1"; fi
if [ "$r_late" = "1" ]; then pass=$((pass+1)); echo "ok   - case23e '---' on line 2 opens nothing -> counted whole (1)"; else fail=$((fail+1)); echo "FAIL - case23e line-2 '---' file counted '$r_late', expected 1"; fi
if [ "$r_rule" = "2" ]; then pass=$((pass+1)); echo "ok   - case23f a body '---' rule is body -> both body references counted (2)"; else fail=$((fail+1)); echo "FAIL - case23f body-rule file counted '$r_rule', expected 2"; fi
if [ "$r_open" = "2" ]; then pass=$((pass+1)); echo "ok   - case23g an unclosed frontmatter is counted whole (2)"; else fail=$((fail+1)); echo "FAIL - case23g unclosed-frontmatter file counted '$r_open', expected 2"; fi

# 23h — the same frontmatter-shaped file under a CORE glob is counted whole: the
# exemption is the manifest-declared class, not the `---` shape.
CW="$TMP/cw/tree"; mk_tree "$CW"
put "$CW" "core/a.md" "---" "tools: $FASK" "---" "body"
stage "$CW"
mk_classes_manifest "$TMP/cw/m.json" "$FM_CLASSES" '{}'
run_gate "$CW" "$TMP/cw/m.json"
check    "case23h frontmatter in a CORE-classified file is counted (exit non-zero)" 1 "$RC"

# 23i — THE SHIPPED MANIFEST (AC): its real classes and the real ask-user token.
# An agent file under the real adapter_frontmatter glob: body injection -> exit 1;
# frontmatter injection -> exit 0. Tokens and globs are read with jq, never typed here.
real_ask="$(jq -r '.token_classes.ask_user.tokens[0] // empty' "$REAL_MANIFEST" 2>/dev/null)"
real_fm_ok="$(jq -r '(.classes.adapter_frontmatter.globs // []) as $g | ($g | index("loomwright/agents/*.md") != null) and ($g | index("loomwright/commands/*.md") != null)' "$REAL_MANIFEST" 2>/dev/null)"
real_hooks_adapter="$(jq -r '(.classes.adapter.globs // []) | index("loomwright/hooks/*") != null' "$REAL_MANIFEST" 2>/dev/null)"
real_no_whole_agents="$(jq -r '(.classes.adapter.globs // []) | (index("loomwright/agents/*") == null) and (index("loomwright/commands/*") == null)' "$REAL_MANIFEST" 2>/dev/null)"
if [ "$real_fm_ok" = "true" ]; then pass=$((pass+1)); echo "ok   - case23i shipped manifest: agents/*.md and commands/*.md are adapter_frontmatter"; else fail=$((fail+1)); echo "FAIL - case23i shipped manifest: adapter_frontmatter globs missing agents/commands ($real_fm_ok)"; fi
if [ "$real_hooks_adapter" = "true" ]; then pass=$((pass+1)); echo "ok   - case23i shipped manifest: hooks/* stays whole-file ADAPTER"; else fail=$((fail+1)); echo "FAIL - case23i shipped manifest: hooks/* is not ADAPTER ($real_hooks_adapter)"; fi
if [ "$real_no_whole_agents" = "true" ]; then pass=$((pass+1)); echo "ok   - case23i shipped manifest: agents/commands are no longer whole-file ADAPTER"; else fail=$((fail+1)); echo "FAIL - case23i shipped manifest: agents/commands still whole-file ADAPTER ($real_no_whole_agents)"; fi
if [ -n "$real_ask" ]; then
  RA="$TMP/realask/tree"; mk_tree "$RA"
  put "$RA" "loomwright/agents/probe.md" "---" "name: probe" "---" "# body" "plain text"
  stage "$RA"
  jq '{scan_roots: ["loomwright"], token_classes: .token_classes, unclassified_default: "core",
       classes: .classes, allowances: {}}' "$REAL_MANIFEST" > "$TMP/realask/m.json"
  run_gate "$RA" "$TMP/realask/m.json"
  check "case23i baseline: a clean agent body under the shipped classes exits 0" 0 "$RC"
  RAB="$TMP/realaskb/tree"; clone_tree "$RA" "$RAB"
  printf 'then use %s here\n' "$real_ask" >> "$RAB/loomwright/agents/probe.md"; stage "$RAB"
  if cmp -s "$RA/loomwright/agents/probe.md" "$RAB/loomwright/agents/probe.md"; then
    fail=$((fail+1)); echo "FAIL - case23i mutant identical to the original (vacuous control)"
  fi
  run_gate "$RAB" "$TMP/realask/m.json"
  check    "case23i MUTATION: the shipped ask-user token in an agent BODY exits non-zero" 1 "$RC"
  contains "case23i it is counted under ask_user" "$OUT" "[ask_user=1]"
  RAF="$TMP/realaskf/tree"; mk_tree "$RAF"
  put "$RAF" "loomwright/agents/probe.md" "---" "name: probe" "tools: $real_ask" "---" "# body" "plain text"
  stage "$RAF"
  run_gate "$RAF" "$TMP/realask/m.json"
  check "case23i INVERSE: the same token in that agent's FRONTMATTER exits 0 (count unchanged)" 0 "$RC"
else
  fail=$((fail+1)); echo "FAIL - case23i the shipped manifest declares no ask_user token"
fi

# ---------------------------------------------------------------------------
# Case 24 — raise_check: a NEW or RAISED allowance passes only with an
# allowance_reasons entry that is ADDED or CHANGED versus the base manifest.
# The manifest lives INSIDE the fixture work tree (docs/, outside scan_roots) and
# the base is a real fixture commit pinned through VENDOR_COUPLING_BASE.
# ---------------------------------------------------------------------------
commit_all() { ( cd "$1" && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "$2" ) >/dev/null 2>&1; }
# run_gate_base <tree> <manifest> <base-ref-or-empty> [require-base] -> OUT, RC
run_gate_base() {
  OUT="$(VENDOR_COUPLING_ROOT="$1" VENDOR_COUPLING_MANIFEST="$2" VENDOR_COUPLING_BASE="$3" \
         VENDOR_COUPLING_REQUIRE_BASE="${4:-}" bash "$GATE" 2>&1)"
  RC=$?
}
RB="$TMP/raise/tree"; clone_tree "$BASE" "$RB"
mkdir -p "$RB/docs"
mk_manifest "$RB/docs/m.json" "$BASE_ALLOW"
jq '.allowance_reasons = {"core/gate.sh": "original reason"}' "$RB/docs/m.json" > "$RB/docs/m.tmp" && mv "$RB/docs/m.tmp" "$RB/docs/m.json"
commit_all "$RB" base
RB_SHA="$(cd "$RB" && git rev-parse HEAD 2>/dev/null)"
case "$RB_SHA" in [0-9a-f]*) pass=$((pass+1)); echo "ok   - case24 fixture base commit created" ;;
  *) fail=$((fail+1)); echo "FAIL - case24 could not create the fixture base commit" ;; esac
cp "$RB/docs/m.json" "$TMP/raise/base-manifest.json"
# set_manifest <jq-filter> — rewrite the WORKING manifest from the base copy.
set_manifest() { jq "$1" "$TMP/raise/base-manifest.json" > "$RB/docs/m.json"; }

set_manifest '.'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24a no raise vs base -> exit 0" 0 "$RC"
contains "case24a the raise check EXECUTED" "$OUT" "raise_check: executed"

set_manifest '.allowances["coupled/skill.md"] = 2'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24b raise WITHOUT a reason exits non-zero" 1 "$RC"
contains "case24b BREACH names the path" "$OUT" "coupled/skill.md"
contains "case24b says the reason is missing" "$OUT" "no allowance_reasons entry"

set_manifest '.allowances["core/gate.sh"] = 3'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24c raise with an INHERITED unchanged reason exits non-zero" 1 "$RC"
contains "case24c says the reason is inherited" "$OUT" "INHERITED"

set_manifest '.allowances["core/gate.sh"] = 3 | .allowance_reasons["core/gate.sh"] = "second reference: the new probe line"'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24d raise with a CHANGED reason exits 0" 0 "$RC"

set_manifest '.allowances["coupled/skill.md"] = 2 | .allowance_reasons["coupled/skill.md"] = "new mention in the skill"'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24e raise with an ADDED reason exits 0" 0 "$RC"

set_manifest '.allowances["core/clean.sh"] = 1'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24f a NEWLY ADDED allowance without a reason exits non-zero" 1 "$RC"
set_manifest '.allowances["core/clean.sh"] = 1 | .allowance_reasons["core/clean.sh"] = "first reference in this script"'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24f control: the same new allowance WITH a reason exits 0" 0 "$RC"

# 24g — a LOWERED allowance is not a raise (it breaches the ratchet here only
# because the tree still carries 2 references; it must not ALSO be called unreasoned).
set_manifest '.allowances["core/gate.sh"] = 1 | .allowance_reasons = {}'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
contains "case24g a lowered allowance is not counted as an unreasoned raise" "$OUT" "without an added/changed reason: 0"

set_manifest '.allowance_reasons["core/deleted-long-ago.sh"] = "stale"'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24h an allowance_reasons key with no allowances entry exits non-zero" 1 "$RC"
contains "case24h names the orphaned reason" "$OUT" "no matching allowances entry"

set_manifest '.allowances["coupled/skill.md"] = 2 | .allowance_reasons["coupled/skill.md"] = "   "'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24i a whitespace-only reason does not justify a raise" 1 "$RC"
set_manifest '.allowances["coupled/skill.md"] = 2 | .allowance_reasons["coupled/skill.md"] = "line one\nline two"'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA"
check    "case24i a multi-line reason is an ERROR" 1 "$RC"
contains "case24i says a reason is one line" "$OUT" "ONE line"

# 24j — NO BASE: an unreasoned raise, but nothing to compare with -> skipped, exit 0.
set_manifest '.allowances["coupled/skill.md"] = 2'
run_gate_base "$RB" "$RB/docs/m.json" ""
check    "case24j no origin remote and no override -> exit 0" 0 "$RC"
contains "case24j prints the skip line" "$OUT" "raise_check: skipped (no base)"
run_gate_base "$RB" "$RB/docs/m.json" "refs/heads/no-such-branch"
check    "case24j2 a base ref that does not exist -> exit 0" 0 "$RC"
contains "case24j2 prints the skip line" "$OUT" "raise_check: skipped (no base)"

# 24k — the default base is origin/main: a fixture remote-tracking ref makes it run.
RO="$TMP/raiseorigin/tree"; clone_tree "$RB" "$RO"
( cd "$RO" && git update-ref refs/remotes/origin/main "$RB_SHA" ) >/dev/null 2>&1
run_gate_base "$RO" "$RO/docs/m.json" ""
check    "case24k with origin/main resolvable and no override, the unreasoned raise exits non-zero" 1 "$RC"
contains "case24k it ran against origin/main" "$OUT" "raise_check: executed against origin/main"

# 24l — the manifest lies OUTSIDE the scan root's work tree (the layout of every
# case before 24) -> skipped with that reason, exit 0.
run_gate_base "$BASE" "$TMP/base/manifest.json" "$RB_SHA"
check    "case24l manifest outside the work tree -> exit 0" 0 "$RC"
contains "case24l prints the skip reason" "$OUT" "raise_check: skipped (manifest is outside the scan root's git work tree)"

# 24m — the manifest path does not exist at the base -> skipped, exit 0.
cp "$RB/docs/m.json" "$RB/docs/m-new.json"
run_gate_base "$RB" "$RB/docs/m-new.json" "$RB_SHA"
check    "case24m manifest path absent at the base -> exit 0" 0 "$RC"
contains "case24m prints the skip reason" "$OUT" "does not exist at base"
rm -f "$RB/docs/m-new.json"

# 24n — VENDOR_COUPLING_REQUIRE_BASE=1 turns every skip into a failure (CI sets it).
run_gate_base "$RB" "$RB/docs/m.json" "" 1
check    "case24n require-base with no base exits non-zero" 1 "$RC"
set_manifest '.'
run_gate_base "$RB" "$RB/docs/m.json" "$RB_SHA" 1
check    "case24n control: require-base with a resolvable base and no raise exits 0" 0 "$RC"

# 24o — the base manifest is read from the OBJECT STORE: a temporary index
# (scripts/ci-local.sh runs this gate with one) does not change the verdict.
set_manifest '.allowances["coupled/skill.md"] = 2'
( cd "$RB" && GIT_INDEX_FILE="$TMP/raise/tmp-index" git add -A ) >/dev/null 2>&1
OUT="$(GIT_INDEX_FILE="$TMP/raise/tmp-index" VENDOR_COUPLING_ROOT="$RB" VENDOR_COUPLING_MANIFEST="$RB/docs/m.json" \
       VENDOR_COUPLING_BASE="$RB_SHA" bash "$GATE" 2>&1)"; RC=$?
check    "case24o under a temporary GIT_INDEX_FILE the unreasoned raise still exits non-zero" 1 "$RC"
contains "case24o and the raise check still executed" "$OUT" "raise_check: executed"

# 24p — an unreadable base manifest is a failure, never a certificate.
RU="$TMP/raisebad/tree"; clone_tree "$RB" "$RU"
printf '{ not json\n' > "$RU/docs/m.json"; commit_all "$RU" garbage
RU_SHA="$(cd "$RU" && git rev-parse HEAD 2>/dev/null)"
cp "$TMP/raise/base-manifest.json" "$RU/docs/m.json"
run_gate_base "$RU" "$RU/docs/m.json" "$RU_SHA"
check    "case24p a base manifest that is not JSON exits non-zero" 1 "$RC"
contains "case24p says the base could not be read" "$OUT" "could not be read as JSON"

# ---------------------------------------------------------------------------
# Case 24q — WRONG-TYPED MANIFEST FIELDS fail CLOSED. `jq -r` prints the string
# "3" as `3`, so a quoted allowance used to pass every shell integer check while
# raise_check (numbers only) never compared it with the base: a raise with an
# inherited reason, or a brand-new entry with no reason, slipped through.
# RS = the raise fixture with core/gate.sh grown from 2 to 3 references; its base
# (RB_SHA) allows 2 with the reason "original reason".
# ---------------------------------------------------------------------------
RS="$TMP/raisestr/tree"; clone_tree "$RB" "$RS"
printf 'echo "$%s"\n' "$FTOK" >> "$RS/core/gate.sh"
stage "$RS"
rs_manifest() { jq "$1" "$TMP/raise/base-manifest.json" > "$RS/docs/m.json"; }
rs_manifest '.allowances["core/gate.sh"] = "3"'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24q1 a STRING-typed raise with an inherited reason exits non-zero" 1 "$RC"
contains "case24q1 names the type error" "$OUT" "not a JSON non-negative integer"
rs_manifest '.allowances["core/gate.sh"] = "3" | .allowance_reasons["core/gate.sh"] = "third reference"'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24q2 a STRING-typed raise exits non-zero even with a changed reason" 1 "$RC"
rs_manifest '.allowances["core/gate.sh"] = 3 | .allowance_reasons["core/gate.sh"] = "third reference"'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24q2 control: the same raise as a JSON number with a changed reason exits 0" 0 "$RC"
rs_manifest '.allowances["core/gate.sh"] = 3 | .allowances["core/clean.sh"] = "1" | .allowance_reasons["core/gate.sh"] = "third reference"'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24q3 a STRING-typed NEW entry with no reason exits non-zero" 1 "$RC"
contains "case24q3 names the new entry" "$OUT" "core/clean.sh"
rs_manifest '.allowances["core/gate.sh"] = 3 | .allowances["core/clean.sh"] = -1 | .allowance_reasons["core/gate.sh"] = "third reference"'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24q4 a NEGATIVE allowance exits non-zero" 1 "$RC"
rs_manifest '.allowances["core/gate.sh"] = 3.5 | .allowance_reasons["core/gate.sh"] = "third reference"'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24q5 a FRACTIONAL allowance exits non-zero" 1 "$RC"
rs_manifest '.allowances["core/gate.sh"] = null'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24q6 a null allowance exits non-zero" 1 "$RC"

# The rest of the both-ways-read fields: each wrong type is an ERROR, never a default.
for filt in '.count_mode = false' '.token_overlap_rule = 1' '.unclassified_default = ["core"]' \
            '.allowances = []' '.allowance_reasons = false' '.classes = []' '.classes.core = "core/*"' \
            '.classes.core.globs = "core/*"' '.classes.core.globs = ["core/*", 7]' \
            '.scan_roots = "core"' '.scan_roots = ["core", null]'; do
  rs_manifest ".allowances[\"core/gate.sh\"] = 3 | .allowance_reasons[\"core/gate.sh\"] = \"third reference\" | $filt"
  run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
  check    "case24q7 wrong-typed field ($filt) exits non-zero" 1 "$RC"
  contains "case24q7 ($filt) reports a type error" "$OUT" "manifest type error"
done

# 24r — a wrong-typed BASE reasons map must not let an inherited reason read as
# "added": the base is typed as strictly as the head.
RT="$TMP/raisebasetype/tree"; clone_tree "$RS" "$RT"
jq '.allowance_reasons = ["original reason"]' "$TMP/raise/base-manifest.json" > "$RT/docs/m.json"
commit_all "$RT" wrong-typed-base
RT_SHA="$(cd "$RT" && git rev-parse HEAD 2>/dev/null)"
jq '.allowances["core/gate.sh"] = 3' "$TMP/raise/base-manifest.json" > "$RT/docs/m.json"
run_gate_base "$RT" "$RT/docs/m.json" "$RT_SHA"
check    "case24r a base whose allowance_reasons is not an object exits non-zero" 1 "$RC"
contains "case24r says the base is wrong-typed" "$OUT" "wrong-typed base never certifies a raise"
# A string-typed BASE allowance reads as absent, so the head value is a NEW
# allowance and the inherited reason still does not justify it.
jq '.allowances["core/gate.sh"] = "2"' "$TMP/raise/base-manifest.json" > "$RT/docs/m.json"
commit_all "$RT" string-base-allowance
RT_SHA="$(cd "$RT" && git rev-parse HEAD 2>/dev/null)"
jq '.allowances["core/gate.sh"] = 3' "$TMP/raise/base-manifest.json" > "$RT/docs/m.json"
run_gate_base "$RT" "$RT/docs/m.json" "$RT_SHA"
check    "case24r2 a string-typed base allowance does not let an inherited-reason raise slip" 1 "$RC"
contains "case24r2 flags the inherited reason" "$OUT" "INHERITED"

# ---------------------------------------------------------------------------
# Case 24s — reasons are compared NORMALISED: a whitespace-only edit of an
# inherited allowance reason is still INHERITED (trailing, leading and internal
# runs alike), so an old reason cannot certify a new raise by gaining a space.
# RS carries 3 references in core/gate.sh; its base allows 2 ("original reason").
# ---------------------------------------------------------------------------
for ws in 'original reason ' ' original reason' 'original  reason' 'original	reason'; do
  rs_manifest ".allowances[\"core/gate.sh\"] = 3 | .allowance_reasons[\"core/gate.sh\"] = \"$ws\""
  run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
  check    "case24s a whitespace-only edit of the inherited reason ('$ws') does not certify the raise" 1 "$RC"
  contains "case24s ('$ws') it is reported INHERITED" "$OUT" "INHERITED"
done
# Control: a genuinely changed reason still certifies (24d's shape, on RS).
rs_manifest '.allowances["core/gate.sh"] = 3 | .allowance_reasons["core/gate.sh"] = "original reason, plus the third reference"'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24s control: a changed reason certifies the same raise" 0 "$RC"
# MUTATION CONTROL — the gate with normalisation removed (norm = identity) must let
# the trailing-space reason through; otherwise 24s proves nothing about normalising.
NORM_MUT="$TMP/gate-no-norm.sh"
sed 's/^\( *\)def norm: .*$/\1def norm: if type == "string" then . else null end;/' "$GATE" > "$NORM_MUT"
if [ -s "$NORM_MUT" ] && ! cmp -s "$NORM_MUT" "$GATE" && bash -n "$NORM_MUT"; then
  rs_manifest '.allowances["core/gate.sh"] = 3 | .allowance_reasons["core/gate.sh"] = "original reason "'
  OUT="$(VENDOR_COUPLING_ROOT="$RS" VENDOR_COUPLING_MANIFEST="$RS/docs/m.json" VENDOR_COUPLING_BASE="$RB_SHA" bash "$NORM_MUT" 2>&1)"; RC=$?
  check "case24s MUTATION CONTROL: without normalisation the trailing-space reason passes" 0 "$RC"
else
  fail=$((fail+1)); echo "FAIL - case24s MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"
fi

# ---------------------------------------------------------------------------
# Case 24t — COUNTING LESS needs a reason too (policy_reasons). Coupling growth
# must not be absorbable by exempting the path instead of raising its number, by
# narrowing the scan, or by deleting the token. RS: core/gate.sh grown to 4
# references (the finding's shape), base allowance 2 with a reason.
# ---------------------------------------------------------------------------
EXEMPT_GATE='.classes.adapter.globs += ["core/gate.sh"] | del(.allowances["core/gate.sh"]) | del(.allowance_reasons["core/gate.sh"])'
GROWN='.allowances["core/gate.sh"] = 4 | .allowance_reasons["core/gate.sh"] = "grown to four"'
printf 'echo "$%s"\n' "$FTOK" >> "$RS/core/gate.sh"; stage "$RS"
rs_manifest "$EXEMPT_GATE"
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t1 grown path moved into an ADAPTER glob with its allowance deleted, no reason -> exit 1" 1 "$RC"
contains "case24t1 names the policy id" "$OUT" "exempt:core/gate.sh"
contains "case24t1 says why" "$OUT" "now ADAPTER-classified"
lacks    "case24t1 the OK line never claims every exemption is reasoned" "$OUT" "check-vendor-coupling: OK"
rs_manifest "$EXEMPT_GATE | .policy_reasons = {\"exempt:core/gate.sh\": \"gate.sh became the adapter seam\"}"
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t1 control: the same exemption WITH an added reason -> exit 0" 0 "$RC"
contains "case24t1 control: the OK line names exemptions" "$OUT" "every raise or exemption carries a reason"

# newly ADAPTER_FRONTMATTER: coupled/skill.md (base allowance 1) joins the frontmatter class.
rs_manifest "$GROWN"' | .classes.adapter_frontmatter.globs += ["coupled/skill.md"]'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t2 a path with a base allowance newly ADAPTER_FRONTMATTER, no reason -> exit 1" 1 "$RC"
contains "case24t2 names it" "$OUT" "exempt:coupled/skill.md"
rs_manifest "$GROWN"' | .classes.adapter_frontmatter.globs += ["coupled/skill.md"] | .policy_reasons = {"exempt:coupled/skill.md": "skill gains a harness header"}'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t2 control: the same move WITH a reason -> exit 0" 0 "$RC"

# outside the scanned set: the scan root holding coupled/skill.md is dropped.
rs_manifest "$GROWN"' | .scan_roots -= ["coupled"]'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t3 a scan root narrowed past a path with a base allowance, no reason -> exit 1" 1 "$RC"
contains "case24t3 says why" "$OUT" "no longer in the scanned set"
rs_manifest "$GROWN"' | .scan_roots -= ["coupled"] | .policy_reasons = {"exempt:coupled/skill.md": "coupled/ moved out of scope"}'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t3 control: the same narrowing WITH a reason -> exit 0" 0 "$RC"

# token removed: the base token is swapped for another, so nothing counts it now.
OTHER_TOK="ACME_OTHER_TOOL"
rs_manifest ".token_classes = {fictional: {tokens: [\"$OTHER_TOK\"]}}"
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t4 a token declared at the base and dropped from token_classes, no reason -> exit 1" 1 "$RC"
contains "case24t4 names the token id" "$OUT" "token:$FTOK"
rs_manifest ".token_classes = {fictional: {tokens: [\"$OTHER_TOK\"]}} | .policy_reasons = {\"token:$FTOK\": \"the variable was retired\"}"
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t4 control: the same removal WITH a reason -> exit 0" 0 "$RC"
# A token MOVED between classes is not a removal.
rs_manifest "$GROWN | .token_classes = {renamed_class: {tokens: [\"$FTOK\"]}}"
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t4 control: a token moved to another class is not a removal -> exit 0" 0 "$RC"

# frontmatter bound raised vs the base (60 -> 61) needs a reason; lowering does not.
rs_manifest "$GROWN"' | .classes.adapter_frontmatter.max_frontmatter_lines = 61'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t5 the frontmatter bound raised without a reason -> exit 1" 1 "$RC"
contains "case24t5 names the bound id" "$OUT" "bound:max_frontmatter_lines"
rs_manifest "$GROWN"' | .classes.adapter_frontmatter.max_frontmatter_lines = 61 | .policy_reasons = {"bound:max_frontmatter_lines": "a longer real header"}'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t5 control: the raise WITH a reason -> exit 0" 0 "$RC"
rs_manifest "$GROWN"' | .classes.adapter_frontmatter.max_frontmatter_lines = 59'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t5 control: a LOWERED bound needs no reason -> exit 0" 0 "$RC"

# INHERITED policy reasons certify nothing — compared normalised like allowance reasons.
RP="$TMP/raisepolicy/tree"; clone_tree "$RS" "$RP"
jq '.policy_reasons = {"exempt:core/gate.sh": "old exemption reason"} | .vendor_tokens = ["ACME_LEGACY_VAR"]' \
   "$TMP/raise/base-manifest.json" > "$RP/docs/m.json"
commit_all "$RP" base-with-policy-reason
RP_SHA="$(cd "$RP" && git rev-parse HEAD 2>/dev/null)"
for ws in 'old exemption reason' 'old exemption reason ' 'old  exemption reason'; do
  jq "$EXEMPT_GATE | .policy_reasons = {\"exempt:core/gate.sh\": \"$ws\", \"token:ACME_LEGACY_VAR\": \"retired flat-list token\"}" \
     "$TMP/raise/base-manifest.json" > "$RP/docs/m.json"
  run_gate_base "$RP" "$RP/docs/m.json" "$RP_SHA"
  check    "case24t6 an INHERITED exemption reason ('$ws') certifies nothing -> exit 1" 1 "$RC"
  contains "case24t6 ('$ws') it is reported INHERITED" "$OUT" "policy_reasons entry is INHERITED"
done
jq "$EXEMPT_GATE | .policy_reasons = {\"exempt:core/gate.sh\": \"why THIS exemption: gate.sh is the seam now\", \"token:ACME_LEGACY_VAR\": \"retired flat-list token\"}" \
   "$TMP/raise/base-manifest.json" > "$RP/docs/m.json"
run_gate_base "$RP" "$RP/docs/m.json" "$RP_SHA"
check    "case24t6 control: a changed exemption reason certifies it -> exit 0" 0 "$RC"
# The base's RETIRED flat token list counts as declared: dropping one needs a reason.
jq "$EXEMPT_GATE | .policy_reasons = {\"exempt:core/gate.sh\": \"why THIS exemption: gate.sh is the seam now\"}" \
   "$TMP/raise/base-manifest.json" > "$RP/docs/m.json"
run_gate_base "$RP" "$RP/docs/m.json" "$RP_SHA"
check    "case24t7 a token from the base's retired vendor_tokens list, absent from the head, needs a reason" 1 "$RC"
contains "case24t7 names it" "$OUT" "token:ACME_LEGACY_VAR"

# policy_reasons format: an unknown namespace, an empty value, a non-object map are ERRORs.
rs_manifest "$GROWN"' | .policy_reasons = {"exampt:core/gate.sh": "typo"}'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t8 a policy_reasons key with an unknown namespace exits non-zero" 1 "$RC"
contains "case24t8 says which namespaces exist" "$OUT" "exempt:<path>, token:<token> or bound:max_frontmatter_lines"
rs_manifest "$GROWN"' | .policy_reasons = {"exempt:core/gate.sh": "  "}'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t8 an empty policy_reasons value exits non-zero" 1 "$RC"
rs_manifest "$GROWN"' | .policy_reasons = []'
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t8 a non-object policy_reasons exits non-zero" 1 "$RC"
contains "case24t8 reports a type error" "$OUT" "manifest type error"
rs_manifest "$GROWN"
run_gate_base "$RS" "$RS/docs/m.json" "$RB_SHA"
check    "case24t8 control: the grown fixture with a reasoned raise and no policy change exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# Case 24u — VENDOR_COUPLING_REQUIRE_BASE=1 turns EVERY skip into a failure, not
# only "no base": the manifest-outside-the-tree and path-absent-at-base skips too.
# ---------------------------------------------------------------------------
run_gate_base "$BASE" "$TMP/base/manifest.json" "$RB_SHA" 1
check    "case24u require-base with the manifest outside the work tree exits non-zero" 1 "$RC"
contains "case24u (outside) prints the require-base error" "$OUT" "VENDOR_COUPLING_REQUIRE_BASE=1 demands"
cp "$TMP/raise/base-manifest.json" "$RB/docs/m-new.json"
run_gate_base "$RB" "$RB/docs/m-new.json" "$RB_SHA" 1
check    "case24u require-base with the manifest path absent at the base exits non-zero" 1 "$RC"
contains "case24u (absent) names the skip" "$OUT" "does not exist at base"
rm -f "$RB/docs/m-new.json"
# The OFF path, with the flag scrubbed from the environment (not merely empty).
OUT="$(env -u VENDOR_COUPLING_REQUIRE_BASE VENDOR_COUPLING_ROOT="$BASE" VENDOR_COUPLING_MANIFEST="$TMP/base/manifest.json" \
       VENDOR_COUPLING_BASE="$RB_SHA" bash "$GATE" 2>&1)"; RC=$?
check    "case24u control: the same outside-tree skip with the flag unset exits 0" 0 "$RC"
contains "case24u control: the OK line admits reasons were not verified" "$OUT" "reasons were NOT verified"

# ---------------------------------------------------------------------------
# Case 27 — the allowance CAP: 999999999 is the largest accepted value; one more
# is an ERROR that names the bound (not a misleading "negative or fractional").
# ---------------------------------------------------------------------------
mk_manifest "$TMP/base/cap-ok.json" '{"core/gate.sh": 999999999, "coupled/skill.md": 1}'
run_gate "$BASE" "$TMP/base/cap-ok.json"
check    "case27a an allowance of 999999999 is accepted" 0 "$RC"
mk_manifest "$TMP/base/cap-over.json" '{"core/gate.sh": 1000000000, "coupled/skill.md": 1}'
run_gate "$BASE" "$TMP/base/cap-over.json"
check    "case27b an allowance of 1000000000 exits non-zero" 1 "$RC"
contains "case27b the error names the bound" "$OUT" "<= 999999999"
contains "case27b and says a larger value is refused" "$OUT" "a larger value is refused"
mk_manifest "$TMP/base/cap-over-clean.json" '{"core/gate.sh": 2, "coupled/skill.md": 1, "core/clean.sh": 1000000000}'
run_gate "$BASE" "$TMP/base/cap-over-clean.json"
check    "case27c the cap is enforced on a zero-reference path too" 1 "$RC"

# ---------------------------------------------------------------------------
# Case 28 — FRONTMATTER IS BOUNDED. A YAML block scalar can carry body-style
# prose inside the header; past max_frontmatter_lines the file counts WHOLE.
# The fixture bound is 5 content lines (set with jq; the shipped value is larger).
# ---------------------------------------------------------------------------
BF="$TMP/fmbound/tree"; mk_tree "$BF"
# at the bound: exactly 5 lines between the delimiters, 3 of them carrying a token.
put "$BF" "agents/at.md"   "---" "name: at" "description: |" "  call $FASK" "  then $FASK" "  and $FASK" "---" "# body" "plain"
# one over: 6 lines between the delimiters (4 tokens hidden in a block scalar).
put "$BF" "agents/over.md" "---" "name: over" "description: |" "  call $FASK" "  then $FASK" "  and $FASK" "  more $FASK" "---" "# body" "plain"
stage "$BF"
mk_classes_manifest "$TMP/fmbound/m.json" "$FM_CLASSES" '{}'
jq '.classes.adapter_frontmatter.max_frontmatter_lines = 5' "$TMP/fmbound/m.json" > "$TMP/fmbound/m5.json"
run_gate "$BF" "$TMP/fmbound/m5.json"
check    "case28a an over-bound frontmatter is counted (allowance 0 -> exit 1)" 1 "$RC"
r_over="$(printf '%s\n' "$OUT" | awk '$1 == "agents/over.md" { print $3 }')"
if [ "$r_over" = "4" ]; then pass=$((pass+1)); echo "ok   - case28a over-bound frontmatter counted WHOLE (4 block-scalar tokens)"
else fail=$((fail+1)); echo "FAIL - case28a over-bound file counted '$r_over', expected 4"; fi
lacks    "case28b an at-bound frontmatter stays exempt" "$OUT" "agents/at.md"
jq '.classes.adapter_frontmatter.max_frontmatter_lines = 6' "$TMP/fmbound/m.json" > "$TMP/fmbound/m6.json"
run_gate "$BF" "$TMP/fmbound/m6.json"
check    "case28c control: with the bound at 6 both files are exempt -> exit 0" 0 "$RC"
# MUTATION CONTROL — the gate with the bound check disabled must hide the 4 tokens again.
FM_MUT="$TMP/gate-no-bound.sh"
sed 's/++fml > fmmax + 0/0/' "$GATE" > "$FM_MUT"
if [ -s "$FM_MUT" ] && ! cmp -s "$FM_MUT" "$GATE" && bash -n "$FM_MUT"; then
  OUT="$(VENDOR_COUPLING_ROOT="$BF" VENDOR_COUPLING_MANIFEST="$TMP/fmbound/m5.json" bash "$FM_MUT" 2>&1)"; RC=$?
  check "case28 MUTATION CONTROL: without the bound the block scalar hides its tokens (exit 0)" 0 "$RC"
else
  fail=$((fail+1)); echo "FAIL - case28 MUTATION CONTROL: mutant not built (empty, unchanged or invalid)"
fi
# After an overflow no later `---` re-opens or closes an exemption: all 3 count.
put "$BF" "agents/over.md" "---" "a: 1" "b: 2" "c: 3" "d: 4" "e: 5" "f: $FASK" "---" "g $FASK" "---" "h $FASK"
stage "$BF"
run_gate "$BF" "$TMP/fmbound/m5.json"
r_over="$(printf '%s\n' "$OUT" | awk '$1 == "agents/over.md" { print $3 }')"
if [ "$r_over" = "3" ]; then pass=$((pass+1)); echo "ok   - case28d after an overflow every later line is body (3 counted)"
else fail=$((fail+1)); echo "FAIL - case28d over-bound file with later rules counted '$r_over', expected 3"; fi
# The bound is REQUIRED when adapter_frontmatter has globs, and must be a positive integer.
for filt in 'del(.classes.adapter_frontmatter.max_frontmatter_lines)' '.classes.adapter_frontmatter.max_frontmatter_lines = 0' \
            '.classes.adapter_frontmatter.max_frontmatter_lines = "60"' '.classes.adapter_frontmatter.max_frontmatter_lines = 2.5'; do
  jq "$filt" "$TMP/fmbound/m.json" > "$TMP/fmbound/mbad.json"
  run_gate "$BF" "$TMP/fmbound/mbad.json"
  check    "case28e ($filt) exits non-zero" 1 "$RC"
  contains "case28e ($filt) names the field" "$OUT" "max_frontmatter_lines"
done

# ---------------------------------------------------------------------------
# Case 29 — CRLF frontmatter: delimiters followed by CR still delimit; the
# frontmatter token is exempt and the body token counts once.
# ---------------------------------------------------------------------------
CRL="$TMP/crlf/tree"; mk_tree "$CRL"; mkdir -p "$CRL/agents"
printf -- '---\r\nname: c\r\ntools: %s\r\n---\r\n# body\r\nuses $%s\r\n' "$FASK" "$FTOK" > "$CRL/agents/c.md"
stage "$CRL"
mk_classes_manifest "$TMP/crlf/m0.json" "$FM_CLASSES" '{}'
run_gate "$CRL" "$TMP/crlf/m0.json"
check    "case29 a CRLF agent file with a body token at allowance 0 exits non-zero" 1 "$RC"
contains "case29 only the body token is counted" "$OUT" "[fict_root=1]"
lacks    "case29 the CRLF frontmatter token is exempt" "$OUT" "fict_ask="
mk_classes_manifest "$TMP/crlf/m1.json" "$FM_CLASSES" '{"agents/c.md": 1}'
run_gate "$CRL" "$TMP/crlf/m1.json"
check    "case29 control: allowance 1 fits the one body token" 0 "$RC"

# ---------------------------------------------------------------------------
# Case 30 — ENUMERATION: every tracked name arrives verbatim. A non-ASCII or
# backslash-bearing name used to be C-quoted by `git ls-files` into a path that
# names no file and was dropped silently; a NUL-bearing file was skipped as
# binary. Each is now counted (and breaches when unallowed); a listed path the
# gate cannot scan is an ERROR; a work-tree deletion is skipped.
# ---------------------------------------------------------------------------
UTF_NAME="core/$(printf 'caf\303\251').sh"
BS_NAME='core/back\slash.sh'
EN="$TMP/enum/tree"; mk_tree "$EN"
put "$EN" "$UTF_NAME" "echo \"\$$FTOK\" \"\$$FTOK\""
put "$EN" "$BS_NAME"  "echo \"\$$FTOK\" \"\$$FTOK\""
stage "$EN"
quoted="$(cd "$EN" && git -c core.quotePath=true ls-files -- core | tr '\n' ' ')"
contains "case30 fixture: git really C-quotes both names by default (the fixture exercises the old bug)" "$quoted" '"core/'
mk_manifest "$TMP/enum/m0.json" '{}'
run_gate "$EN" "$TMP/enum/m0.json"
check    "case30a quoted-name files with tokens and no allowance exit non-zero" 1 "$RC"
contains "case30a the non-ASCII name is counted" "$OUT" "$UTF_NAME"
contains "case30a the backslash name is counted"  "$OUT" "$BS_NAME"
EN_ALLOW="$(jq -cn --arg u "$UTF_NAME" --arg b "$BS_NAME" '{($u): 2, ($b): 2}')"
mk_manifest "$TMP/enum/m2.json" "$EN_ALLOW"
run_gate "$EN" "$TMP/enum/m2.json"
check    "case30b control: with allowances of 2 keyed by the verbatim names -> exit 0" 0 "$RC"
# MUTATION CONTROL — the gate with the OLD enumeration (C-quoted, newline-separated,
# a non-file silently skipped) must drop the quoted names again.
EN_MUT="$TMP/gate-old-enum.sh"
sed -e 's/git -c core.quotePath=false ls-files -z -- \$SCAN_ROOTS >/git ls-files -- $SCAN_ROOTS >/' \
    -e "s/^while IFS= read -r -d '' f; do\$/while IFS= read -r f; do/" "$GATE" > "$EN_MUT"
if [ -s "$EN_MUT" ] && ! cmp -s "$EN_MUT" "$GATE" && bash -n "$EN_MUT" && ! grep -q 'ls-files -z -- \$SCAN_ROOTS >' "$EN_MUT"; then
  OUT="$(VENDOR_COUPLING_ROOT="$EN" VENDOR_COUPLING_MANIFEST="$TMP/enum/m0.json" bash "$EN_MUT" 2>&1)"
  lacks "case30 MUTATION CONTROL: the old enumeration never counts the non-ASCII name as such" "$OUT" "$UTF_NAME "
else
  fail=$((fail+1)); echo "FAIL - case30 MUTATION CONTROL: mutant not built (empty, unchanged, invalid or not reverted)"
fi
# NUL-bearing file: counted, not skipped as binary.
printf 'x\000$%s y\000$%s\n' "$FTOK" "$FTOK" > "$EN/core/blob.dat"; stage "$EN"
run_gate "$EN" "$TMP/enum/m2.json"
check    "case30c a NUL-bearing file with tokens and no allowance exits non-zero" 1 "$RC"
r_blob="$(printf '%s\n' "$OUT" | awk '$1 == "core/blob.dat" { print $3 }')"
if [ "$r_blob" = "2" ]; then pass=$((pass+1)); echo "ok   - case30c the NUL-bearing file's two tokens are both counted"
else fail=$((fail+1)); echo "FAIL - case30c NUL-bearing file counted '$r_blob', expected 2"; fi
rm -f "$EN/core/blob.dat"; stage "$EN"
# A NUL cannot manufacture a frontmatter delimiter: such an agent file counts whole.
mkdir -p "$EN/agents"
printf -- '---\000x\nname: n\ntools: %s\n---\nbody\n' "$FASK" > "$EN/agents/nul.md"; stage "$EN"
mk_classes_manifest "$TMP/enum/mc.json" "$FM_CLASSES" "$EN_ALLOW"
run_gate "$EN" "$TMP/enum/mc.json"
check    "case30d a NUL-bearing agent file is counted WHOLE (its 'frontmatter' token breaches)" 1 "$RC"
contains "case30d names it" "$OUT" "agents/nul.md"
rm -f "$EN/agents/nul.md"; stage "$EN"
# A tracked dangling symlink is listed but is not a regular file -> ERROR.
ln -s no-such-target "$EN/core/dangling.sh"; stage "$EN"
run_gate "$EN" "$TMP/enum/m2.json"
check    "case30e a tracked path that is not a regular file exits non-zero" 1 "$RC"
contains "case30e says why" "$OUT" "not a regular file"
rm -f "$EN/core/dangling.sh"; stage "$EN"
# A work-tree deletion that is still indexed is a pending change, skipped (control).
put "$EN" "core/gone.sh" "echo portable"; stage "$EN"; rm -f "$EN/core/gone.sh"
run_gate "$EN" "$TMP/enum/m2.json"
check    "case30f control: a work-tree-deleted, still-indexed file is skipped -> exit 0" 0 "$RC"
stage "$EN"
# A name carrying a tab cannot ride the gate's tables -> ERROR, never a silent drop.
TAB_NAME="core/$(printf 'a\tb').sh"
put "$EN" "$TAB_NAME" "echo \"\$$FTOK\""; stage "$EN"
run_gate "$EN" "$TMP/enum/m2.json"
check    "case30g a tracked name carrying a tab exits non-zero" 1 "$RC"
contains "case30g says why" "$OUT" "tab, CR or newline"
rm -f "$EN/$TAB_NAME"; stage "$EN"

# ---------------------------------------------------------------------------
# Case 25 — an UNREADABLE file is an ERROR, not a silent zero. (Skipped when
# running as root, where a mode-000 file is still readable.)
# ---------------------------------------------------------------------------
if [ "$(id -u)" != "0" ]; then
  UR="$TMP/unread/tree"; clone_tree "$BASE" "$UR"
  chmod 000 "$UR/core/gate.sh"
  run_gate "$UR" "$TMP/base/manifest.json"
  chmod 644 "$UR/core/gate.sh"
  check    "case25 an unreadable tracked file exits non-zero" 1 "$RC"
  contains "case25 says it could not be read" "$OUT" "could not be read"
else
  pass=$((pass+1)); echo "ok   - case25 skipped (running as root: permissions do not block reads)"
fi

# ---------------------------------------------------------------------------
# Case 26 — THE GATE HARD-CODES NO TOKEN. Every token lives in the manifest; a
# literal copy in the script would be a second, unreviewed source of truth.
# ---------------------------------------------------------------------------
hard=0
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  if grep -qF -- "$tok" "$GATE"; then hard=$((hard + 1)); echo "     the gate spells a shipped token literally (see the manifest's token_classes)"; fi
done <<EOF
$(jq -r '.token_classes[].tokens[]' "$REAL_MANIFEST" 2>/dev/null)
EOF
check "case26 the gate script contains none of the shipped tokens" 0 "$hard"


# ---------------------------------------------------------------------------
# Case 31 — the BREACH DETAIL block (iq02 Part T09). It changes no verdict; it
# tells the author which ADDED lines tripped the ratchet and how to get out.
# Fixture: core/run.sh has ONE pre-existing reference (line 1) at its allowance,
# committed as the base with an allowance written as 1.0; the head then appends
# two lines that each carry one fictional hook_protocol token.
# ---------------------------------------------------------------------------
HT1="ACME_HOOK_EVENT"; HT2="ACME_HOOK_DECISION"
DT="$TMP/detail/tree"; mk_tree "$DT"; mkdir -p "$DT/docs"
put "$DT" core/run.sh "echo \"\$$FTOK\"" 'echo plain one' 'echo plain two'
put "$DT" adapter/cmd.md "uses $HT1"
cat > "$DT/docs/m.json" <<JSON
{
  "scan_roots": ["core", "adapter"],
  "token_classes": { "install_root": { "tokens": ["$FTOK"] }, "hook_protocol": { "tokens": ["$HT1", "$HT2"] } },
  "unclassified_default": "core",
  "classes": {
    "adapter": { "globs": ["adapter/*", "core/exempt-seam.sh"] },
    "adapter_frontmatter": { "globs": [], "max_frontmatter_lines": 60 },
    "coupled": { "globs": [] },
    "core":    { "globs": ["core/*"] }
  },
  "allowances": { "core/run.sh": 1.0 },
  "allowance_reasons": { "core/run.sh": "original reason" }
}
JSON
commit_all "$DT" base
DT_SHA="$(cd "$DT" && git rev-parse HEAD 2>/dev/null)"
cp "$DT/docs/m.json" "$TMP/detail/base-m.json"
printf 'echo "%s"\n' "$HT1" >> "$DT/core/run.sh"
printf 'echo "%s"\n' "$HT2" >> "$DT/core/run.sh"
stage "$DT"
run_gate_base "$DT" "$DT/docs/m.json" "$DT_SHA"
check    "case31a two added hook_protocol references breach (exit 1, as before)" 1 "$RC"
contains "case31a the BREACH row is printed" "$OUT" "BREACH  +2 over the declared allowance"
contains "case31b the block is labelled as added-vs-base" "$OUT" "detail: added lines vs $DT_SHA"
contains "case31b lists added line 4 with its token and class" "$OUT" "line 4: $HT1 (hook_protocol)"
contains "case31b lists added line 5 with its token and class" "$OUT" "line 5: $HT2 (hook_protocol)"
lacks    "case31b does NOT list the pre-existing reference on line 1" "$OUT" "line 1: "
DTL="$(printf '%s\n' "$OUT" | grep -c '^      line ')"
check    "case31b exactly two lines listed" 2 "$DTL"
contains "case31c adapter globs are read from the fixture manifest" "$OUT" "classes.adapter.globs: adapter/* core/exempt-seam.sh"
contains "case31d ready-to-paste allowance row" "$OUT" "allowances:        \"core/run.sh\": 3,"
contains "case31d ready-to-paste reason row carries the sentinel" "$OUT" "allowance_reasons: \"core/run.sh\": \"REASON-NOT-WRITTEN:"
# The block must never advise hiding a reference from the literal count, and
# states the rule positively instead.
BLOCK="$(printf '%s\n' "$OUT" | awk '/^    detail: /{on=1} on{print} /^      allowance_reasons: /{on=0}')"
case "$BLOCK" in *"ways out, in this order"*) pass=$((pass+1)); echo "ok   - case31e block extracted for the advice check";;
  *) fail=$((fail+1)); echo "FAIL - case31e could not extract the detail block";; esac
if grep -qiE 'concatenat|indirect|lookup|assembl|at runtime|split the token|build the (token|name)' <<<"$BLOCK"; then
  fail=$((fail+1)); echo "FAIL - case31e the block suggests hiding a reference from the literal count"
else pass=$((pass+1)); echo "ok   - case31e the block never suggests runtime assembly"; fi
contains "case31e the rule is stated positively" "$BLOCK" "rule: every reference stays a literal this gate can count"
# Order of the ways out: reword -> reuse -> adapter -> raise.
ORD="$(printf '%s\n' "$BLOCK" | grep -oE '^      \([a-d]\) [a-z]+' | awk '{print $2}' | tr '\n' ' ')"
check "case31f ways out in order reword reuse adapter raise" 0 "$([ "$ORD" = "reword reuse adapter raise " ] && echo 0 || echo 1)"

# 31g — NO BASE: the block says so and lists every token-bearing line; exit unchanged.
run_gate_base "$DT" "$DT/docs/m.json" "refs/does-not/exist"
check    "case31g no base: still exit 1" 1 "$RC"
contains "case31g says base unavailable" "$OUT" "base unavailable — showing all, not only added"
contains "case31g lists the pre-existing line too" "$OUT" "line 1: $FTOK (install_root)"
contains "case31g and the added ones" "$OUT" "line 5: $HT2 (hook_protocol)"

# 31h — THE SENTINEL STILL FAILS: paste the suggested rows unchanged.
PH="REASON-NOT-WRITTEN: replace this with one line saying why this reference is needed"
jq --arg r "$PH" '.allowances["core/run.sh"] = 3 | .allowance_reasons["core/run.sh"] = $r' "$TMP/detail/base-m.json" > "$DT/docs/m.json"
run_gate_base "$DT" "$DT/docs/m.json" "$DT_SHA"
check    "case31h pasted row with the unfilled placeholder exits 1" 1 "$RC"
contains "case31h raise_check BREACH names the unfilled reason" "$OUT" "is the unfilled placeholder"
contains "case31i raise row prints integers (base 1.0 -> 1)" "$OUT" "allowance raised (1 -> 3 vs"
lacks    "case31i raise row never prints the raw JSON literal" "$OUT" "1.0 ->"
jq '.allowance_reasons["core/run.sh"] = "the emitter needs the two hook fields to build its payload"' "$DT/docs/m.json" > "$DT/docs/m.tmp" && mv "$DT/docs/m.tmp" "$DT/docs/m.json"
run_gate_base "$DT" "$DT/docs/m.json" "$DT_SHA"
check    "case31h control: the same raise with a real reason exits 0" 0 "$RC"
# MUTATION CONTROL: drop the sentinel arm; the pasted-unchanged leg must then
# pass (proving the leg is what catches it). Mutant gated non-empty, differs, bash -n.
MUT="$TMP/detail/gate-no-sentinel.sh"
grep -v 'elif (\$r | contains(\$sent)) then "sentinel"' "$GATE" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$MUT" "$GATE" && bash -n "$MUT" 2>/dev/null; then
  jq --arg r "$PH" '.allowances["core/run.sh"] = 3 | .allowance_reasons["core/run.sh"] = $r' "$TMP/detail/base-m.json" > "$DT/docs/m.json"
  OUT="$(VENDOR_COUPLING_ROOT="$DT" VENDOR_COUPLING_MANIFEST="$DT/docs/m.json" VENDOR_COUPLING_BASE="$DT_SHA" bash "$MUT" 2>&1)"; RC=$?
  check "case31j mutant without the sentinel arm lets the pasted row through (the leg kills it)" 0 "$RC"
else
  fail=$((fail+1)); echo "FAIL - case31j mutant is empty, identical or not bash -n clean"
fi

# 31k — Entry 3: -0 is refused by the jq layer and the shell layer alike.
sed 's/"core\/run.sh": 1.0 }/"core\/run.sh": -0 }/' "$TMP/detail/base-m.json" > "$DT/docs/m.json"
grep -q '"core/run.sh": -0 }' "$DT/docs/m.json" || { fail=$((fail+1)); echo "FAIL - case31k could not write the -0 fixture"; }
run_gate_base "$DT" "$DT/docs/m.json" "$DT_SHA"
check    "case31k allowance -0 exits 1" 1 "$RC"
contains "case31k it is refused as not a non-negative integer" "$OUT" "not a JSON non-negative integer"
JQ_LAYER="$(sed -n '/^ALLOW_TSV=/,/^fi$/p' "$GATE")"
contains "case31k the jq predicate itself rejects a negative zero" "$JQ_LAYER" 'tojson | startswith("-")'

# 31l — Entry 1: the summary label no longer reads as uncounted.
contains "case31l summary label says frontmatter bodies are counted" "$OUT" "frontmatter-bounded (header exempt, body counted)"
lacks    "case31l old label is gone" "$OUT" "of which frontmatter-exempt"

# 31m — Entry 2: the class names live in the manifest only.
ARCH="$repo_root/loomwright/docs/ARCHITECTURE_CONTRACTS.md"
restated=0
for f in "$GATE" "$ARCH"; do
  if grep -qE 'install root, subagent( |$)|hook protocol, runtime identity' "$f" 2>/dev/null; then restated=$((restated + 1)); echo "     restated class list in $f"; fi
done
check "case31m neither the gate header nor ARCHITECTURE_CONTRACTS.md restates the class list" 0 "$restated"

# 31n — case15's report names the live gate's verdict on a breaching run.
run_gate_base "$DT" "$TMP/detail/base-m.json" ""
C15="$(case15_report "$OUT" "$RC")"; C15_RC=$?
check    "case31n case15 still FAILs on a breaching run" 1 "$C15_RC"
contains "case31n its line names the live gate's verdict" "$C15" "this is the LIVE GATE's verdict"
contains "case31n it reprints the BREACH row" "$C15" "BREACH  +2 over the declared allowance"
# ---------------------------------------------------------------------------
echo "---------------------------------------------------------------------------"
echo "test-check-vendor-coupling: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
