#!/usr/bin/env bash
# check.sh — parity-emit-block eval task.
# Stronger oracle than check-contract-parity Check 1: hook-required fields must
# live INSIDE the fenced emit-block template, not just anywhere in the file.
# Reuses the parity script's MANIFEST as the single field-truth source.
# Deterministic and read-only.
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "parity-emit-block: not inside a git repo" >&2
  exit 1
}
parity="$repo_root/scripts/check-contract-parity.sh"
agents="$repo_root/loomwright/agents"
[ -f "$parity" ] || { echo "parity-emit-block: $parity missing" >&2; exit 1; }

# Pull the MANIFEST heredoc body: lines between MANIFEST=" and the closing quote.
manifest="$(awk '/^MANIFEST="$/{f=1;next} f&&/^"$/{exit} f' "$parity")"
[ -n "$manifest" ] || { echo "parity-emit-block: could not parse MANIFEST from $parity" >&2; exit 1; }

fail=0
while IFS='|' read -r matcher agent block fields; do
  [ -n "$matcher" ] || continue
  agent_path="$agents/$agent"
  [ -f "$agent_path" ] || { echo "FAIL: $agent missing at $agent_path" >&2; fail=1; continue; }

  # Extract every YAML-style emit template: a "BLOCK:" line plus its indented
  # body (until dedent to the key's indent level or a fence line). Fence
  # toggling is deliberately avoided — agent files contain unbalanced fences.
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
    echo "FAIL: $agent has no YAML emit template starting with '$block:' — emit template missing" >&2
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
