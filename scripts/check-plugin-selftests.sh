#!/usr/bin/env bash
# check-plugin-selftests.sh — CI hard gate: run EVERY plugin's deterministic
# self-test suite.
#
# WHY THIS EXISTS AS A SCRIPT (v15.37.0): the loop used to be eight lines inlined
# in .github/workflows/ci.yml, globbing `loomwright/scripts/test-*.sh` only. Two
# problems with that. First, a `selvedge/scripts/test-*.sh` would simply never
# run — silently. Second, and worse for a slice whose thesis is "a gate that
# cannot fail is worse than no gate", loop logic living inside a workflow file
# cannot be exercised: there is no CI test harness in this repo, and the only way
# to observe a change to it is to push and watch. Extracted here, the per-plugin
# loud-on-empty branch has a real self-test
# (scripts/test-check-plugin-selftests.sh) that can be mutation-controlled.
#
# HONEST SCOPE NOTE: after this slice exactly ONE plugin ships a scripts/ dir
# (loomwright). stackpack, mysql-mcp and selvedge ship none. So the per-plugin
# branch has NO live subject in this repo, and "proven" here means proven
# against a temp fixture tree, NOT observed in live state. That is why the
# fixture cases exist and why this comment says so instead of implying coverage
# the repo cannot supply.
#
# Two branches, deliberately different (same distinction as the other widened gates):
#   * SKIP SILENTLY — a plugin with no scripts/ dir at all. It ships no suites;
#     that is not a defect.
#   * FAIL LOUDLY   — a plugin that HAS a scripts/ dir but no test-*.sh inside
#     it. That is the anti-drift case the original inline loop guarded with
#     `[ "${#tests[@]}" -gt 0 ]`: a moved or renamed scripts dir must fail, not
#     pass vacuously. The message NAMES the plugin.
# Plus the tripwire: zero suite-bearing plugins matched at all is a failure.
#
# Usage: bash scripts/check-plugin-selftests.sh [--root <dir>] [--dry-run]
#   --dry-run enumerates the suites it WOULD run (one per line) without
#   executing them, and applies exactly the same skip/fail branches.
#
# Portability: bash 3.2 safe (macOS) + Ubuntu CI. nullglob, no GNU-only flags.

set -uo pipefail
shopt -s nullglob

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)    ROOT="${2:?--root requires a directory}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "check-plugin-selftests: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

# ── Plugin discovery: ONE idiom, ONE path-base rule ──────────────────────────
# Same as check-token-budget.sh / check-shared-prefix.sh / check-contract-parity.sh.
# MEASURED: `.source` resolves against the manifest's GRANDPARENT dir — sources
# like "./loomwright" are <root>-relative while the manifest sits in
# <root>/.claude-plugin/.
MARKETPLACE_JSON="${CHECK_MARKETPLACE_JSON:-$ROOT/.claude-plugin/marketplace.json}"

plugin_root_base() {
  local d
  d="$(dirname "$(dirname "$1")")"
  ( cd "$d" 2>/dev/null && pwd )
}

GATE_NAME="check-plugin-selftests"

plugin_dirs() {
  local manifest="$1" base name src raw want got
  base="$(plugin_root_base "$manifest")" || return 1
  [ -n "$base" ] || return 1

  # Capture jq's OUTPUT AND STATUS before consuming it. The previous form piped
  # jq straight into a heredoc with `2>/dev/null`, which threw the status away:
  # jq that dies partway through `.plugins[]` still emits the entries it parsed
  # BEFORE the error, so the caller silently discovered a TRUNCATED plugin list
  # and every gate built on it reported OK on the plugins it never looked at.
  # A fail-closed ratchet that silently stops covering a plugin is a false green
  # — the exact failure this whole plugin-aware change exists to prevent.
  # Found in review of PR #155; reproduced with jq exiting 5 after emitting 1 of
  # 3 entries. Two guards, because either alone leaves a hole: the status check
  # catches a parse error, and the count assertion catches any other way the
  # emitted list could come up short.
  raw="$(jq -r '.plugins[] | ((.name // "") + "\t" + (.source // ""))' "$manifest" 2>&1)" || {
    echo "${GATE_NAME:-plugin-discovery}: cannot parse $manifest — $raw" >&2
    return 1
  }
  want="$(jq -r '.plugins | length' "$manifest" 2>/dev/null)" || want=""
  got="$(printf '%s\n' "$raw" | grep -c .)"
  case "$want" in
    ''|*[!0-9]*) echo "${GATE_NAME:-plugin-discovery}: cannot read plugin count from $manifest" >&2; return 1 ;;
  esac
  if [ "$got" -ne "$want" ]; then
    echo "${GATE_NAME:-plugin-discovery}: discovered $got of $want plugin entries in $manifest — refusing to run against a truncated plugin list" >&2
    return 1
  fi

  while IFS="$(printf '\t')" read -r name src; do
    [ -n "$src" ] && [ "$src" != "null" ] || continue
    src="${src#./}"; src="${src%/}"
    [ -n "$name" ] && [ "$name" != "null" ] || name="$src"
    printf '%s\t%s\n' "$name" "$base/$src"
  done <<EOF
$raw
EOF
}

command -v jq >/dev/null 2>&1 || { echo "check-plugin-selftests: jq required for marketplace plugin discovery" >&2; exit 1; }
[ -f "$MARKETPLACE_JSON" ] || { echo "check-plugin-selftests: marketplace manifest not found: $MARKETPLACE_JSON" >&2; exit 1; }

rc=0
checked=0
ran=0

while IFS="$(printf '\t')" read -r name pdir; do
  [ -n "$pdir" ] || continue

  # SKIP SILENTLY: plugin ships no scripts/ dir (stackpack, mysql-mcp, selvedge).
  [ -d "$pdir/scripts" ] || continue
  checked=$((checked + 1))

  tests=("$pdir"/scripts/test-*.sh)

  # FAIL LOUDLY, PER PLUGIN: a scripts/ dir with no suites in it. nullglob makes
  # the array empty rather than passing the literal glob to bash as a confusing
  # "No such file".
  if [ "${#tests[@]}" -eq 0 ]; then
    echo "check-plugin-selftests: plugin '$name' has a scripts/ dir but no test-*.sh in $pdir/scripts — anti-drift loop matched nothing (moved or renamed suite dir?)" >&2
    rc=1
    continue
  fi

  echo "=============================================================================="
  echo "plugin: $name (${#tests[@]} suites)"
  for t in "${tests[@]}"; do
    ran=$((ran + 1))
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "would run: $t"
      continue
    fi
    echo "== $t =="
    if ! bash "$t"; then
      echo "check-plugin-selftests: FAILED — $t exited non-zero" >&2
      rc=1
    fi
  done
done <<EOF
$(plugin_dirs "$MARKETPLACE_JSON")
EOF

# Anti-drift tripwire: no suite-bearing plugin at all is a false green.
if [ "$checked" -eq 0 ]; then
  echo "check-plugin-selftests: no self-test-bearing plugin sources found via $MARKETPLACE_JSON — gate matched nothing (anti-drift tripwire)" >&2
  exit 1
fi

echo "------------------------------------------------------------------------------"
if [ "$rc" -ne 0 ]; then
  echo "check-plugin-selftests: FAILED — see the offending plugin/suite above." >&2
  exit 1
fi
# A dry run EXECUTED NOTHING, so it must not claim anything passed. Saying
# "N suites passed" after running zero of them is a false success claim — the
# exact defect class this gate exists to catch, which is why the wording is
# branched here rather than left to the reader to interpret.
if [ "$DRY_RUN" -eq 1 ]; then
  echo "check-plugin-selftests: DRY RUN — enumerated $ran suites across $checked plugin(s); NOTHING was executed."
else
  echo "check-plugin-selftests: OK — $ran suites across $checked plugin(s) passed."
fi
exit 0
