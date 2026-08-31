#!/usr/bin/env bash
# check-vendor-coupling.sh — CI-enforced vendor-coupling ratchet.
#
# WHY: this plugin's portability to non-Claude harnesses is asserted in docs and
# in a requirement, and nothing enforced it — so every release was free to weld
# more harness-specific coupling onto the vendor-neutral core, and did. This gate
# turns that assertion into a mechanically checked contract: the core's count of
# vendor references may FALL or stay FLAT, but it may not RISE without a reviewed
# edit to the manifest. It fails CLOSED (exit 1) on any breach.
#
# HOW IT COUNTS — AND WHAT IT CANNOT SEE (read this before trusting a green run):
#   * It counts LITERAL, fixed-string occurrences of the vendor tokens declared
#     in the manifest's `vendor_tokens`, one count per file (`grep -oF`), summed
#     over all tokens. Multiple hits on ONE line each count, deliberately: a
#     line-based count would let a second reference hide on an existing line.
#   * It therefore CANNOT see a reference ASSEMBLED AT RUNTIME — a path or
#     variable name built by concatenation, indirection, or a lookup table
#     contains no literal token and is invisible to this mechanism. That is a
#     real limit of grep-based detection, stated here rather than papered over.
#     A green run means "no new LITERAL coupling", not "no new coupling".
#   * Files are enumerated with `git ls-files`, so the scanned set is exactly the
#     TRACKED tree. Untracked scratch files and gitignored build output
#     (node_modules/, dist/, .supervisor/) are never scanned, which is what keeps
#     a developer's checkout and CI measuring the identical file set. CONSEQUENCE
#     FOR LOCAL RUNS: a brand-new file is invisible to this gate until it has been
#     `git add`ed. That is moot in CI, where the checkout is fully committed, but a
#     developer establishing or re-measuring a baseline must stage first or they
#     will measure a tree that is missing their own new files.
#
# CLASSIFICATION (declared in the manifest, justified there in per-class `note`s):
#   ADAPTER  — may name any harness freely; NOT counted at all. These files exist
#              to speak the harness's language.
#   CORE     — must be vendor-neutral; ratcheted against a per-path allowance.
#   COUPLED  — grandfathered debt; also ratcheted, just from a higher baseline.
#   A path matched by no class glob falls to the manifest's
#   `unclassified_default` (a new directory cannot silently become a coupling
#   haven). That default may be `core` or `coupled` only — `adapter` is rejected,
#   because a blanket adapter default would silently exempt the whole tree.
#
# THE RATCHET IS ONE-DIRECTIONAL: breach = actual > allowance. actual < allowance
# PASSES — that is debt being paid down, and pinning counts to exact equality
# would turn every improvement into a CI failure.
#
# TO RAISE AN ALLOWANCE: raise it in loomwright/docs/vendor-coupling-manifest.json
# in the SAME PR that adds the reference. The gate reads the JSON, so the raise is
# visible in the PR diff and gets reviewed — exactly the convention
# scripts/check-token-budget.sh uses for prompt budgets.
#
# EXIT CODES
#   0 = every scanned path at or under its declared allowance.
#   1 = at least one BREACH, or an ERROR (missing/malformed/unreadable manifest,
#       empty token set, illegal unclassified_default, an allowance entry for a
#       path that does not exist or is ADAPTER-classified, an empty scan, or a
#       missing dependency). An unreadable manifest is a FAILURE, never a silent
#       pass.
#   There is no third state and no `|| true`: this is a correctness gate, not a
#   runtime emitter (CLAUDE.md §"Failure-Mode Invariants").
#
# USAGE
#   bash scripts/check-vendor-coupling.sh                    # the gate
#   bash scripts/check-vendor-coupling.sh --print-allowances # emit the measured
#       allowance map as JSON, for pasting into the manifest when establishing or
#       re-baselining it. Its output is a MEASUREMENT, not an approval — the diff
#       still has to be read by a human.
#
# Env overrides (hermetic self-test only; unset in real runs):
#   VENDOR_COUPLING_MANIFEST — path to the manifest JSON
#   VENDOR_COUPLING_ROOT     — root of the tree to scan (must be a git work tree)
#
# Portability: bash 3.2 / BSD userland safe (macOS dev, GNU CI). No `timeout`, no
# GNU-only stat/sed/date flags, no `${var//...}` pattern substitution on large
# strings. Counts are captured into variables and validated numeric BEFORE any
# arithmetic under `set -u`. Deterministic and fully offline.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

MANIFEST="${VENDOR_COUPLING_MANIFEST:-$repo_root/loomwright/docs/vendor-coupling-manifest.json}"
SCAN_ROOT="${VENDOR_COUPLING_ROOT:-$repo_root}"

MODE="check"
case "${1:-}" in
  "")                  : ;;
  --print-allowances)  MODE="print" ;;
  *) echo "check-vendor-coupling: unknown argument '$1' (expected none or --print-allowances)" >&2; exit 1 ;;
esac

command -v jq  >/dev/null 2>&1 || { echo "check-vendor-coupling: jq required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "check-vendor-coupling: git required" >&2; exit 1; }

[ -f "$MANIFEST" ] || { echo "check-vendor-coupling: manifest not found: $MANIFEST" >&2; exit 1; }
jq -e . "$MANIFEST" >/dev/null 2>&1 || {
  echo "check-vendor-coupling: manifest is not valid JSON: $MANIFEST (fail CLOSED — an unreadable manifest is never a silent pass)" >&2
  exit 1
}
[ -d "$SCAN_ROOT" ] || { echo "check-vendor-coupling: scan root not found: $SCAN_ROOT" >&2; exit 1; }

cd "$SCAN_ROOT" || exit 1

# ---------------------------------------------------------------------------
# Manifest -> shell
# ---------------------------------------------------------------------------
SCAN_ROOTS="$(jq -r '.scan_roots[]? // empty' "$MANIFEST")"
if [ -z "$SCAN_ROOTS" ]; then
  echo "check-vendor-coupling: manifest declares no scan_roots — refusing to pass a zero-scope ratchet" >&2
  exit 1
fi
# The roots are word-split into the `git ls-files` pathspec below, so a root
# containing whitespace would silently split into two wrong pathspecs and quietly
# shrink the scanned set. Reject it rather than mis-scan.
case "$SCAN_ROOTS" in
  *[[:blank:]]*)
    echo "check-vendor-coupling: a scan_roots entry contains whitespace, which would silently split the scan pathspec — rename the path or extend this gate to handle it" >&2
    exit 1 ;;
esac

UNCLASSIFIED_DEFAULT="$(jq -r '.unclassified_default // ""' "$MANIFEST")"
case "$UNCLASSIFIED_DEFAULT" in
  core|coupled) : ;;
  *)
    echo "check-vendor-coupling: unclassified_default must be 'core' or 'coupled' (got '$UNCLASSIFIED_DEFAULT'). 'adapter' is rejected — a blanket adapter default would exempt the entire tree." >&2
    exit 1 ;;
esac

# count_mode is declared in the manifest, so it must MEAN something. This gate
# implements exactly one counting mode — occurrences (every match counted, so a
# second reference cannot hide on a line that already has one). The field is
# validated rather than merely read, because a knob that silently accepts any
# value implies an alternate mode that does not exist: someone setting
# "lines" would reasonably expect line-based counting and would instead get
# occurrence counting with no warning. Rejecting the unknown value keeps the
# manifest's declaration and the gate's behaviour in agreement — the same reason
# unclassified_default is validated above rather than defaulted.
COUNT_MODE="$(jq -r '.count_mode // "occurrences"' "$MANIFEST")"
case "$COUNT_MODE" in
  occurrences) : ;;
  *)
    echo "check-vendor-coupling: count_mode must be 'occurrences' (got '$COUNT_MODE'). This gate implements occurrence counting only — a second reference must not be able to hide on a line that already carries one. Remove the field to accept the default, or implement the mode you are asking for." >&2
    exit 1 ;;
esac

ADAPTER_GLOBS="$(jq -r '.classes.adapter.globs[]? // empty' "$MANIFEST")"
COUPLED_GLOBS="$(jq -r '.classes.coupled.globs[]? // empty' "$MANIFEST")"
CORE_GLOBS="$(jq -r '.classes.core.globs[]? // empty'       "$MANIFEST")"

# Vendor tokens -> a `grep -e tok` argument vector. `-e` keeps a token that
# starts with `-` from being read as an option; `-F` keeps `.` and `-` literal.
GREP_ARGS=()
ntokens=0
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  GREP_ARGS[${#GREP_ARGS[@]}]="-e"
  GREP_ARGS[${#GREP_ARGS[@]}]="$tok"
  ntokens=$((ntokens + 1))
done <<EOF
$(jq -r '.vendor_tokens[]? // empty' "$MANIFEST")
EOF

if [ "$ntokens" -eq 0 ]; then
  echo "check-vendor-coupling: manifest declares no vendor_tokens — a ratchet with an empty token set matches nothing and would pass forever" >&2
  exit 1
fi

# Allowance table -> a TSV side file, read ONCE. (bash 3.2 has no associative
# arrays; per-path `jq` calls would be one process per file.)
TMPDIR_GATE="$(mktemp -d "${TMPDIR:-/tmp}/vendor-coupling.XXXXXX")" || exit 1
trap 'rm -rf "$TMPDIR_GATE"' EXIT
ALLOW_TSV="$TMPDIR_GATE/allowances.tsv"
jq -r '(.allowances // {}) | to_entries[] | "\(.key)\t\(.value)"' "$MANIFEST" > "$ALLOW_TSV" 2>/dev/null || : > "$ALLOW_TSV"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# match_any PATH GLOBLIST -> rc 0 if PATH matches any glob in the list.
# Globs are shell `case` patterns; `*` matches `/` (so "loomwright/skills/*"
# covers the whole subtree). The pattern must stay UNQUOTED in the `case` to
# keep its pattern meaning.
match_any() {
  local p="$1" list="$2" g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    case "$p" in $g) return 0 ;; esac
  done <<EOF
$list
EOF
  return 1
}

# classify PATH -> echoes adapter | coupled | core
# ADAPTER is tested FIRST so a single-file adapter exemption (the
# LOOMWRIGHT_ROOT resolver) wins over the broader CORE glob that contains it.
classify() {
  local p="$1"
  if match_any "$p" "$ADAPTER_GLOBS"; then echo "adapter"; return; fi
  if match_any "$p" "$COUPLED_GLOBS"; then echo "coupled"; return; fi
  if match_any "$p" "$CORE_GLOBS";    then echo "core";    return; fi
  echo "$UNCLASSIFIED_DEFAULT"
}

# count_refs FILE -> echoes the number of literal vendor-token occurrences.
# `grep -o` prints one line per occurrence; `-I` skips binary files; the count is
# captured and validated numeric before it is ever used in arithmetic (memory:
# stat-flavor-setu-arithmetic-trap). Deliberately NOT `grep -c ... || echo 0`,
# which emits two lines, and deliberately not `producer | grep -q`, which can
# return 141 under pipefail even on a match.
count_refs() {
  local f="$1" n
  n="$(grep -oIF ${GREP_ARGS[@]+"${GREP_ARGS[@]}"} -- "$f" 2>/dev/null | wc -l | tr -d '[:space:]')"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# allowance_for PATH -> echoes the declared allowance (0 when undeclared).
allowance_for() {
  awk -F'\t' -v p="$1" '$1==p { print $2; found=1; exit } END { if (!found) print 0 }' "$ALLOW_TSV"
}

# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------
FILES="$TMPDIR_GATE/files.txt"
# `git ls-files` fixes the scanned set to the TRACKED tree, identically on a dev
# checkout and in CI. A non-git tree is a hard failure, not a fallback to `find`:
# a fallback would mean the self-test exercises a different enumeration path from
# the one CI runs.
if ! git ls-files -- $SCAN_ROOTS > "$FILES" 2>/dev/null; then
  echo "check-vendor-coupling: 'git ls-files' failed in $SCAN_ROOT — the scan root must be a git work tree" >&2
  exit 1
fi

scanned=0
counted=0
adapter_files=0
HITS="$TMPDIR_GATE/hits.tsv"   # path \t class \t actual   (only files with actual > 0)
: > "$HITS"

while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue          # deleted-but-still-indexed paths
  scanned=$((scanned + 1))
  cls="$(classify "$f")"
  if [ "$cls" = "adapter" ]; then
    adapter_files=$((adapter_files + 1))
    continue
  fi
  counted=$((counted + 1))
  n="$(count_refs "$f")"
  [ "$n" -gt 0 ] 2>/dev/null || continue
  printf '%s\t%s\t%s\n' "$f" "$cls" "$n" >> "$HITS"
done < "$FILES"

# Anti-drift: a zero-file scan of a fail-closed ratchet is a false green (the
# same guard check-token-budget.sh puts on an empty agents dir).
if [ "$scanned" -eq 0 ]; then
  echo "check-vendor-coupling: scanned 0 files under scan_roots [$(echo $SCAN_ROOTS)] in $SCAN_ROOT — refusing to pass an empty ratchet" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# --print-allowances: emit the measured map, then stop.
# ---------------------------------------------------------------------------
if [ "$MODE" = "print" ]; then
  echo "{"
  first=1
  while IFS="$(printf '\t')" read -r p c n; do
    [ -n "$p" ] || continue
    if [ "$first" -eq 1 ]; then first=0; else echo ","; fi
    printf '    "%s": %s' "$p" "$n"
  done < "$HITS"
  echo ""
  echo "}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Compare
# ---------------------------------------------------------------------------
exit_code=0
breaches=0
errors=0
total_refs=0

echo "check-vendor-coupling — literal vendor-token occurrences per tracked file (grep -oF; a runtime-assembled reference is invisible to it)"
echo "authoritative manifest: $MANIFEST"
echo "scan roots: $(echo $SCAN_ROOTS) | vendor tokens: $ntokens | unclassified default: $UNCLASSIFIED_DEFAULT"
echo "---------------------------------------------------------------------------------------------"
printf "%-62s %-8s %7s %7s  %s\n" "PATH" "CLASS" "ACTUAL" "ALLOW" "STATUS"

while IFS="$(printf '\t')" read -r p cls n; do
  [ -n "$p" ] || continue
  total_refs=$((total_refs + n))
  allow="$(allowance_for "$p")"
  case "$allow" in ''|*[!0-9]*)
    printf "%-62s %-8s %7s %7s  %s\n" "$p" "$cls" "$n" "$allow" "ERROR   non-integer allowance in manifest (must be a non-negative integer)"
    errors=$((errors + 1))
    exit_code=1
    continue ;;
  esac
  if [ "$n" -gt "$allow" ]; then
    printf "%-62s %-8s %7s %7s  %s\n" "$p" "$cls" "$n" "$allow" "BREACH  +$((n - allow)) over the declared allowance — remove the reference, or raise the allowance in the manifest in this same PR"
    breaches=$((breaches + 1))
    exit_code=1
  elif [ "$n" -lt "$allow" ]; then
    printf "%-62s %-8s %7s %7s  %s\n" "$p" "$cls" "$n" "$allow" "OK      $((allow - n)) below allowance (debt paid down — the ratchet never requires exact equality)"
  else
    printf "%-62s %-8s %7s %7s  %s\n" "$p" "$cls" "$n" "$allow" "OK      at allowance"
  fi
done < "$HITS"

# Orphaned / illegitimate allowance entries. Symmetric with the breach check and
# with check-token-budget.sh's orphaned-budget rule: it keeps the manifest
# self-cleaning, and it closes the loophole of "grant an allowance to a path the
# gate would never have counted" as a way to quietly reclassify something.
while IFS="$(printf '\t')" read -r p allow; do
  [ -n "$p" ] || continue
  if [ ! -f "$p" ]; then
    printf "%-62s %-8s %7s %7s  %s\n" "$p" "-" "-" "$allow" "ERROR   allowance declared for a path that does not exist — remove the stale entry"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi
  if [ "$(classify "$p")" = "adapter" ]; then
    printf "%-62s %-8s %7s %7s  %s\n" "$p" "adapter" "-" "$allow" "ERROR   allowance declared for an ADAPTER-classified path — adapters are never counted, so the entry is meaningless (remove it)"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi
  # Value sanity, for EVERY declared allowance — not only the ones that happen to
  # have references today. The breach loop above also rejects a non-integer, but it
  # only ever iterates files with actual > 0, so a garbage value on a currently-CLEAN
  # path used to sit inert and undetected until the day someone added a reference to
  # that file — surfacing an ERROR far later than a manifest sanity check should.
  # Validating here makes "the manifest stays self-cleaning" true for the whole table
  # rather than for its referenced subset.
  case "$allow" in ''|*[!0-9]*)
    printf "%-62s %-8s %7s %7s  %s\n" "$p" "$(classify "$p")" "-" "$allow" "ERROR   non-integer allowance in manifest (must be a non-negative integer)"
    errors=$((errors + 1))
    exit_code=1
    continue ;;
  esac
done < "$ALLOW_TSV"

echo "---------------------------------------------------------------------------------------------"
echo "files scanned: $scanned (counted: $counted, adapter-exempt: $adapter_files) | files with references: $(wc -l < "$HITS" | tr -d '[:space:]') | total references: $total_refs | breaches: $breaches | errors: $errors"

if [ "$exit_code" -ne 0 ]; then
  echo "check-vendor-coupling: FAILED — vendor-coupling ratchet tripped (see BREACH/ERROR rows above)." >&2
else
  echo "check-vendor-coupling: OK — no path exceeds its declared vendor-coupling allowance."
fi
exit "$exit_code"
