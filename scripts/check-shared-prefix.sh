#!/usr/bin/env bash
# check-shared-prefix.sh — CI gate: byte-identical shared agent prefix.
#
# WHY: every agent .md prompt opens with one shared leading block (the "Shared
# Agent Contract"), whose SINGLE canonical source is
# loomwright/docs/shared-agent-prefix.md (between the SHARED-AGENT-PREFIX v1
# BEGIN/END marker lines). Build-time includes are not available for plugin
# agents, so the copies are literal — and byte-identity is the invariant,
# not similarity: a one-char drift silently forks the contract. This gate
# extracts the canonical block and verifies every agent file contains it
# byte-identically and EXACTLY once.
#
# ── CROSS-PLUGIN DECISION (v15.37.0) — intended, and enforced in code ────────
# This repo is a marketplace wrapper with sibling plugins, and the gate now
# discovers every plugin registered in .claude-plugin/marketplace.json rather
# than hard-pinning loomwright/agents. But there is still exactly ONE canonical
# prefix file, and it lives inside the loomwright plugin
# (loomwright/docs/shared-agent-prefix.md).
#
# That is DELIBERATE, not an oversight: owner decision 2 forbids a second copy
# of the canonical text. A second copy is a second thing to drift, which is the
# precise failure this gate exists to catch — duplicating the canonical to make
# each plugin self-contained would defeat the invariant it enforces. So a
# sibling plugin's agents are checked against ANOTHER plugin's file. That is a
# real cross-plugin dependency and it is named here rather than stumbled into.
#
# WHAT HAPPENS IF loomwright IS ABSENT from the manifest: the gate FAILS LOUDLY
# ("no plugin named 'loomwright' ... canonical shared prefix is unresolvable").
# It does NOT fall back to a per-plugin copy and does NOT skip. A missing
# canonical means the byte-identity invariant is unverifiable, and an
# unverifiable fail-closed gate must fail, not pass. This branch is exercised by
# scripts/test-check-shared-prefix.sh (see its case "manifest without loomwright").
#
# FAILS CLOSED (exit 1, no `|| true`) on:
#   - missing/empty canonical file, missing or duplicated markers, or an
#     empty block body (markers with nothing between them)
#   - any agent file missing the block, containing a drifted copy, or
#     containing it more than once
#   - an empty agents dir (a 0-agent run of a fail-closed gate is a false
#     green — mirrors check-token-budget.sh's guard)
#   - a manifest that registers no agent-bearing plugin at all (anti-drift
#     tripwire: a gate that matched nothing is a false green)
#   - a registered manifest that cannot be found, or has no loomwright entry
#
# SKIPS SILENTLY (deliberately different from the above): a registered plugin
# that ships no agents/ dir at all — stackpack, mysql-mcp, and selvedge until
# its agents land. Nothing to compare; not a defect.
#
# Portability: bash 3.2 safe (macOS) + Linux CI. No GNU-only flags, no
# `${var//...}` pattern-subst on large strings, no mapfile, no sed -i.
# Deterministic and fully offline.
#
# Self-test: scripts/test-check-shared-prefix.sh (offline fixtures).

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
ROOT="$repo_root"

# Overridable for the self-test (hermetic fixtures); default to the real repo.
# Layered ABOVE discovery: when either is set the gate checks that single pair
# and returns, so every pre-existing caller keeps working byte-identically.
CANONICAL="${SHARED_PREFIX_CANONICAL:-}"
AGENTS_DIR="${SHARED_PREFIX_AGENTS_DIR:-}"

# ── Plugin discovery: ONE idiom, ONE path-base rule ──────────────────────────
# Identical to check-token-budget.sh / check-contract-parity.sh. See the long
# note in check-token-budget.sh for the two refinements over
# check-skills-index-sync.sh's original run_gate():
#   1. CHECK_MARKETPLACE_JSON (the name validate-version.sh already uses) makes
#      the manifest overridable, so this branch is REACHABLE from a fixture —
#      without it a negative test of the loop could never fail.
#   2. `.source` resolves against the MANIFEST'S OWN PLUGIN ROOT, never CWD.
#      MEASURED: that base is the manifest's GRANDPARENT dir, not
#      `dirname "$MARKETPLACE_JSON"` — sources like "./loomwright" are
#      <root>-relative while the manifest sits in <root>/.claude-plugin/.
MARKETPLACE_JSON="${CHECK_MARKETPLACE_JSON:-$ROOT/.claude-plugin/marketplace.json}"

BEGIN_MARKER='<!-- SHARED-AGENT-PREFIX v1 BEGIN -->'
END_MARKER='<!-- SHARED-AGENT-PREFIX v1 END -->'

# The plugin that owns the single canonical prefix file (see CROSS-PLUGIN
# DECISION above). Not configurable by design — one canonical, one owner.
CANONICAL_PLUGIN="loomwright"
CANONICAL_REL="docs/shared-agent-prefix.md"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shared-prefix.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

# plugin_root_base MANIFEST -> the <plugin-root> that `.source` values are relative to.
plugin_root_base() {
  local d
  d="$(dirname "$(dirname "$1")")"
  ( cd "$d" 2>/dev/null && pwd )
}

# plugin_dirs MANIFEST -> one "<name>\t<dir>" line per registered plugin.
GATE_NAME="check-shared-prefix"

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

canon_block="$tmp_dir/canonical.block"
canon_lines=0

# --- Canonical block sanity (fail CLOSED on a malformed source) -------------
prepare_canonical() { # $1 = canonical file path
  local canon="$1" canon_begin canon_end last_line
  if [ ! -f "$canon" ]; then
    echo "check-shared-prefix: FAILED — canonical file not found: $canon" >&2
    return 1
  fi
  canon_begin="$(count_exact "$canon" "$BEGIN_MARKER")"
  canon_end="$(count_exact "$canon" "$END_MARKER")"
  if [ "$canon_begin" != "1" ] || [ "$canon_end" != "1" ]; then
    echo "check-shared-prefix: FAILED — canonical $canon must contain exactly one BEGIN and one END marker line (found BEGIN=$canon_begin END=$canon_end)" >&2
    return 1
  fi
  extract_block "$canon" "$canon_block"
  canon_lines="$(wc -l < "$canon_block" | tr -d ' ')"
  # Need BEGIN + at least one body line + END, and the extraction must have
  # reached the END marker (last line == END_MARKER, i.e. markers in order).
  if [ "$canon_lines" -lt 3 ]; then
    echo "check-shared-prefix: FAILED — canonical block in $canon is empty or malformed (BEGIN/END markers out of order or nothing between them)" >&2
    return 1
  fi
  last_line="$(tail -n 1 "$canon_block")"
  if [ "$last_line" != "$END_MARKER" ]; then
    echo "check-shared-prefix: FAILED — canonical block in $canon never reaches the END marker (markers out of order?)" >&2
    return 1
  fi
  echo "check-shared-prefix — canonical: $canon ($canon_lines lines incl. markers)"
  return 0
}

# run_check AGENTS_DIR — compare every agent .md in ONE plugin's agents tree
# against the already-prepared canonical block. Returns 0/1; never exits.
run_check() {
  local agents_dir="$1" fail=0 agent_count=0 agent_file stem n_begin n_end agent_block
  if [ ! -d "$agents_dir" ]; then
    echo "check-shared-prefix: FAILED — agents dir not found: $agents_dir" >&2
    return 1
  fi
  echo "agents dir: $agents_dir"
  echo "------------------------------------------------------------------------------"

  for agent_file in "$agents_dir"/*.md; do
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
      echo "  DRIFT     $stem — block differs from canonical (byte-identity is the invariant; re-copy from the canonical)"
      fail=1
    fi
  done

  # A 0-agent run must fail LOUDLY, not silently pass.
  if [ "$agent_count" -eq 0 ]; then
    echo "check-shared-prefix: FAILED — no agent .md files found in $agents_dir — refusing to pass a 0-agent gate" >&2
    return 1
  fi

  echo "------------------------------------------------------------------------------"
  if [ "$fail" -ne 0 ]; then
    echo "check-shared-prefix: FAILED — one or more agent files missing/drifting from the canonical shared prefix (see offenders above)." >&2
    return 1
  fi
  echo "check-shared-prefix: OK — all $agent_count agent files carry the canonical shared prefix byte-identically (exactly once)."
  return 0
}

# ── Gate mode ────────────────────────────────────────────────────────────────
# Env override => ONE canonical/agents pair. Otherwise resolve the single
# canonical from the loomwright plugin source and loop every registered plugin
# that ships an agents/ dir.
run_gate() {
  if [ -n "$CANONICAL" ] || [ -n "$AGENTS_DIR" ]; then
    prepare_canonical "${CANONICAL:-loomwright/$CANONICAL_REL}" || return 1
    run_check "${AGENTS_DIR:-loomwright/agents}"
    return $?
  fi

  command -v jq >/dev/null 2>&1 || { echo "check-shared-prefix: FAILED — jq required for marketplace plugin discovery" >&2; return 1; }
  [ -f "$MARKETPLACE_JSON" ] || { echo "check-shared-prefix: FAILED — marketplace manifest not found: $MARKETPLACE_JSON" >&2; return 1; }

  local dirs canon_dir="" rc=0 checked=0 name pdir
  dirs="$(plugin_dirs "$MARKETPLACE_JSON")"

  # Resolve the ONE canonical from the ONE plugin that owns it. Absent =>
  # FAIL LOUDLY (see CROSS-PLUGIN DECISION in the header) — never a per-plugin
  # fallback copy, never a skip.
  while IFS="$(printf '\t')" read -r name pdir; do
    [ -n "$pdir" ] || continue
    [ "$name" = "$CANONICAL_PLUGIN" ] || continue
    canon_dir="$pdir"
  done <<EOF
$dirs
EOF
  if [ -z "$canon_dir" ]; then
    echo "check-shared-prefix: FAILED — no plugin named '$CANONICAL_PLUGIN' registered in $MARKETPLACE_JSON, so the canonical shared prefix is unresolvable. There is exactly one canonical ($CANONICAL_PLUGIN/$CANONICAL_REL) by design; a fail-closed byte-identity gate that cannot read it must fail, not pass." >&2
    return 1
  fi
  prepare_canonical "$canon_dir/$CANONICAL_REL" || return 1

  while IFS="$(printf '\t')" read -r name pdir; do
    [ -n "$pdir" ] || continue
    # SKIP SILENTLY: plugin ships no agents tree. Nothing to compare.
    [ -d "$pdir/agents" ] || continue
    checked=$((checked + 1))
    echo "=============================================================================="
    echo "plugin: $name"
    run_check "$pdir/agents" || rc=1
  done <<EOF
$dirs
EOF

  if [ "$checked" -eq 0 ]; then
    echo "check-shared-prefix: FAILED — no agent-bearing plugin sources found via $MARKETPLACE_JSON — gate matched nothing (anti-drift tripwire)" >&2
    return 1
  fi
  return $rc
}

run_gate
exit $?
