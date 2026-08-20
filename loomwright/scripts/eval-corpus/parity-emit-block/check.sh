#!/usr/bin/env bash
# check.sh — parity-emit-block eval task.
# Stronger oracle than check-contract-parity Check 1: hook-required fields must
# live INSIDE the agent's emit-block TEMPLATE, not just anywhere in the file.
# Reuses the parity script's MANIFEST as the single field-truth source.
# Deterministic and read-only.
#
# Usage: bash check.sh [--root <dir>]
#   --root defaults to the enclosing git repo root (the runner cd's into this
#   task dir, which lives inside the repo). The mutation self-test points it at
#   a fixture tree carrying scripts/check-contract-parity.sh + loomwright/agents/.
set -uo pipefail

if [ "${1:-}" = "--root" ]; then
  repo_root="${2:?--root requires a directory}"
else
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "parity-emit-block: not inside a git repo (and no --root given)" >&2
    exit 1
  }
fi
parity="$repo_root/scripts/check-contract-parity.sh"
[ -f "$parity" ] || { echo "parity-emit-block: $parity missing" >&2; exit 1; }
manifest_json="$repo_root/.claude-plugin/marketplace.json"

# agents_dir_for PLUGIN -> the agents dir of the plugin named in MANIFEST column 1.
#
# THIS FILE IS A SECOND, DERIVED CONSUMER OF THAT MANIFEST, and it was the one
# the plugin-aware sweep missed. check-contract-parity.sh itself was taught to
# resolve AGENTS from the row's plugin; this task re-parses the same heredoc and
# kept a hard-coded `loomwright/agents`, so the first row naming another plugin
# resolved to a file that had moved away and the task failed. Note WHY a literal
# grep for the agent name could never have found it: the name is derived from
# the MANIFEST at runtime, so this file contains zero occurrences of it. A
# DERIVED pin is invisible to a literal grep.
#
# Resolution mirrors the gates' idiom (manifest `.source`, resolved against the
# manifest's GRANDPARENT dir), with a convention fallback to <root>/<plugin> so
# the mutation self-test's hermetic fixture tree — which ships
# scripts/check-contract-parity.sh + loomwright/agents/ and no manifest — keeps
# working unchanged.
agents_dir_for() {
  local want="$1" src=""
  if [ -f "$manifest_json" ] && command -v jq >/dev/null 2>&1; then
    src="$(jq -r --arg n "$want" '.plugins[] | select(.name == $n) | .source // ""' "$manifest_json" 2>/dev/null | head -1)"
    src="${src#./}"; src="${src%/}"
  fi
  [ -n "$src" ] || src="$want"
  printf '%s\n' "$repo_root/$src/agents"
}

# Pull the MANIFEST heredoc body: lines between MANIFEST=" and the closing quote.
# (Parse re-verified against the current check-contract-parity.sh — the MANIFEST
# assignment still opens with a bare `MANIFEST="` line and closes with a bare `"`.)
manifest="$(awk '/^MANIFEST="$/{f=1;next} f&&/^"$/{exit} f' "$parity")"
[ -n "$manifest" ] || { echo "parity-emit-block: could not parse MANIFEST from $parity" >&2; exit 1; }

fail=0
while IFS='|' read -r matcher agent block fields; do
  [ -n "$matcher" ] || continue
  # Column 1 carries the plugin dimension INSIDE the matcher ("<plugin>:<name>")
  # — the row format is a four-column public contract and deliberately gains no
  # fifth column for it.
  agent_path="$(agents_dir_for "${matcher%%:*}")/$agent"
  [ -f "$agent_path" ] || { echo "FAIL: $agent missing at $agent_path" >&2; fail=1; continue; }

  # Extract every emit template for this block, in either authoring style:
  #   cap=1 — YAML style: a `BLOCK:` line plus its indented body (until dedent
  #           back to the key's indent level or a fence line).
  #   cap=2 — markdown style: a `## BLOCK` heading plus its `- field:` bullets.
  # Fence toggling is deliberately avoided — agent files contain unbalanced fences.
  # Multiple occurrences (e.g. success + failure examples) are concatenated; the
  # field check runs against the union.
  region="$(awk -v blk="$block" '
    function indent(s,  n) { n=0; while (substr(s, n+1, 1) == " ") n++; return n }
    cap == 1 {
      if ($0 ~ /^[[:space:]]*```/ || (NF > 0 && indent($0) <= base)) { cap=0 }
      else { out = out $0 "\n"; next }
    }
    cap == 2 {
      if ($0 ~ /^[[:space:]]*-[[:space:]]/) { out = out $0 "\n"; next } else { cap=0 }
    }
    $0 ~ ("^[[:space:]]*" blk ":[[:space:]]*$") { cap=1; base=indent($0); out = out $0 "\n" }
    $0 ~ ("^#+[[:space:]]+" blk "[[:space:]]*$") { cap=2; out = out $0 "\n" }
    END { printf "%s", out }
  ' "$agent_path")"

  if [ -z "$region" ]; then
    echo "FAIL: $agent has no emit template anchored on '$block:' or '## $block' — emit template missing" >&2
    fail=1
    continue
  fi

  IFS=',' read -ra fl <<<"$fields"
  for f in "${fl[@]}"; do
    # Field must appear as an actual key line (YAML "field:" or bullet "- field:"),
    # not merely as a word inside another field's comment.
    if ! grep -qE "^[[:space:]]*(-[[:space:]])?${f}:" <<<"$region"; then
      echo "FAIL: $agent: $block field '$f' absent from the emit-block template (prose mention alone will hook-reject at runtime)" >&2
      fail=1
    fi
  done
done <<<"$manifest"

if [ "$fail" -ne 0 ]; then
  echo "✗ parity-emit-block: emit-template drift detected." >&2
  exit 1
fi
echo "✓ parity-emit-block: all hook-required fields present inside their emit-block templates."
