#!/usr/bin/env bash
# check-shared-prefix.sh — CI gate: byte-identical shared agent prefix.
#
# WHY: every loomwright/agents/*.md prompt opens with one shared leading block
# (the "Shared Agent Contract"), whose SINGLE canonical source is
# loomwright/docs/shared-agent-prefix.md (between the SHARED-AGENT-PREFIX v1
# BEGIN/END marker lines). Build-time includes are not available for plugin
# agents, so the 14 copies are literal — and byte-identity is the invariant,
# not similarity: a one-char drift silently forks the contract. This gate
# extracts the canonical block and verifies every agent file contains it
# byte-identically and EXACTLY once.
#
# FAILS CLOSED (exit 1, no `|| true`) on:
#   - missing/empty canonical file, missing or duplicated markers, or an
#     empty block body (markers with nothing between them)
#   - any agent file missing the block, containing a drifted copy, or
#     containing it more than once
#   - an empty agents dir (a 0-agent run of a fail-closed gate is a false
#     green — mirrors check-token-budget.sh's guard)
#
# Portability: bash 3.2 safe (macOS) + Linux CI. No GNU-only flags, no
# `${var//...}` pattern-subst on large strings, no mapfile, no sed -i.
# Deterministic and fully offline.
#
# Self-test: scripts/test-check-shared-prefix.sh (offline fixtures).

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# Overridable for the self-test (hermetic fixtures); default to the real repo.
CANONICAL="${SHARED_PREFIX_CANONICAL:-loomwright/docs/shared-agent-prefix.md}"
AGENTS_DIR="${SHARED_PREFIX_AGENTS_DIR:-loomwright/agents}"

BEGIN_MARKER='<!-- SHARED-AGENT-PREFIX v1 BEGIN -->'
END_MARKER='<!-- SHARED-AGENT-PREFIX v1 END -->'

if [ ! -f "$CANONICAL" ]; then
  echo "check-shared-prefix: FAILED — canonical file not found: $CANONICAL" >&2
  exit 1
fi
if [ ! -d "$AGENTS_DIR" ]; then
  echo "check-shared-prefix: FAILED — agents dir not found: $AGENTS_DIR" >&2
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shared-prefix.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# extract_block FILE OUT — prints the block (marker lines included) from FILE
# into OUT. Marker lines must match EXACTLY ($0 == marker): a marker line with
# trailing whitespace or any other byte difference is NOT recognized, so a
# drifted marker surfaces as a missing/short extraction and fails the compare.
extract_block() {
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    $0 == b { infb = 1 }
    infb    { print }
    infb && $0 == e { exit }
  ' "$1" > "$2"
}

# count_exact FILE MARKER — number of lines in FILE that are EXACTLY MARKER.
count_exact() {
  awk -v m="$2" '$0 == m { n++ } END { print n + 0 }' "$1"
}

# --- Canonical block sanity (fail CLOSED on a malformed source) -------------
canon_begin="$(count_exact "$CANONICAL" "$BEGIN_MARKER")"
canon_end="$(count_exact "$CANONICAL" "$END_MARKER")"
if [ "$canon_begin" != "1" ] || [ "$canon_end" != "1" ]; then
  echo "check-shared-prefix: FAILED — canonical $CANONICAL must contain exactly one BEGIN and one END marker line (found BEGIN=$canon_begin END=$canon_end)" >&2
  exit 1
fi

canon_block="$tmp_dir/canonical.block"
extract_block "$CANONICAL" "$canon_block"
canon_lines="$(wc -l < "$canon_block" | tr -d ' ')"
# Need BEGIN + at least one body line + END, and the extraction must have
# reached the END marker (last line == END_MARKER, i.e. markers in order).
if [ "$canon_lines" -lt 3 ]; then
  echo "check-shared-prefix: FAILED — canonical block in $CANONICAL is empty or malformed (BEGIN/END markers out of order or nothing between them)" >&2
  exit 1
fi
last_line="$(tail -n 1 "$canon_block")"
if [ "$last_line" != "$END_MARKER" ]; then
  echo "check-shared-prefix: FAILED — canonical block in $CANONICAL never reaches the END marker (markers out of order?)" >&2
  exit 1
fi

echo "check-shared-prefix — canonical: $CANONICAL ($canon_lines lines incl. markers)"
echo "agents dir: $AGENTS_DIR"
echo "------------------------------------------------------------------------------"

fail=0
agent_count=0

for agent_file in "$AGENTS_DIR"/*.md; do
  [ -f "$agent_file" ] || continue
  agent_count=$((agent_count + 1))
  stem="$(basename "$agent_file")"

  n_begin="$(count_exact "$agent_file" "$BEGIN_MARKER")"
  n_end="$(count_exact "$agent_file" "$END_MARKER")"

  if [ "$n_begin" = "0" ] && [ "$n_end" = "0" ]; then
    echo "  MISSING   $stem — shared prefix block not found"
    fail=1
    continue
  fi
  if [ "$n_begin" != "1" ] || [ "$n_end" != "1" ]; then
    if [ "$n_begin" = "$n_end" ]; then label="DUPLICATE"; else label="MALFORMED"; fi
    echo "  $label $stem — block markers must appear exactly once and balanced (found BEGIN=$n_begin END=$n_end)"
    fail=1
    continue
  fi

  agent_block="$tmp_dir/agent.block"
  extract_block "$agent_file" "$agent_block"
  if cmp -s "$canon_block" "$agent_block"; then
    echo "  OK        $stem"
  else
    echo "  DRIFT     $stem — block differs from canonical (byte-identity is the invariant; re-copy from $CANONICAL)"
    fail=1
  fi
done

# A 0-agent run must fail LOUDLY, not silently pass.
if [ "$agent_count" -eq 0 ]; then
  echo "check-shared-prefix: FAILED — no agent .md files found in $AGENTS_DIR — refusing to pass a 0-agent gate" >&2
  exit 1
fi

echo "------------------------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then
  echo "check-shared-prefix: FAILED — one or more agent files missing/drifting from the canonical shared prefix (see offenders above)." >&2
  exit 1
fi
echo "check-shared-prefix: OK — all $agent_count agent files carry the canonical shared prefix byte-identically (exactly once)."
exit 0
