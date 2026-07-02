#!/usr/bin/env bash
# check-doc-currency.sh — mechanical doc-currency gate (v14.3.0).
#
# WHY: version/count drift repeatedly slipped past both human review and CI —
# doc surfaces asserting a stale plugin version or a stale agent/command/hook/
# skill count while the authoritative source (plugin.json, hooks.json, and the
# agents/commands/skills directories) had moved on. `validate-version.sh` only
# diffs plugin.json vs marketplace.json; this gate checks the *prose* claims
# across every doc surface and fails the build when one drifts.
#
# SCOPE (deliberately narrow to avoid false positives): only high-confidence
# "current claim" phrasings are checked — version annotations next to
# `plugin.json` / the `AI agents vX.Y.Z` headline / the README intro's
# `Plugin (vX.Y.Z)` and `(vX.Y.Z) includes:` claims, and explicit count phrases
# ("N quality gate hooks", "N agent roles", "Slash commands (N)", ...). It never
# scans bare numbers, so dated changelog entries like "v12.2.0 took the count
# 13 -> 14" do NOT trigger it.
#
# Exit 0 = clean, 1 = drift detected (prints every offending file:line).

set -uo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

PLUGIN_JSON="loomwright/.claude-plugin/plugin.json"
HOOKS_JSON="loomwright/hooks/hooks.json"

command -v jq >/dev/null 2>&1 || { echo "check-doc-currency: jq required" >&2; exit 1; }

VERSION="$(jq -r '.version' "$PLUGIN_JSON")"
AGENTS="$(find loomwright/agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
COMMANDS="$(find loomwright/commands -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
SKILLS="$(find loomwright/skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
HOOKS="$(jq '[.hooks[][].hooks[]] | length' "$HOOKS_JSON")"

echo "Authoritative → version=$VERSION  agents=$AGENTS  commands=$COMMANDS  skills=$SKILLS  hooks=$HOOKS"

# Doc/config surfaces that carry current-state claims.
FILES=(
  CLAUDE.md
  README.md
  AGENT_GUIDELINES.md
  .claude-plugin/README.md
  .claude-plugin/marketplace.json
  "$PLUGIN_JSON"
  loomwright/commands/agent-help.md
  loomwright/docs/ARCHITECTURE.md
  loomwright/docs/ARCHITECTURE_CONTRACTS.md
  # .github/workflows/*.yml are deliberately NOT scanned: anthropics/claude-code-action@v1
  # refuses to run when a PR branch's workflow file differs from the default-branch copy,
  # so a count claim there would force a workflow edit on every counts-bump PR — which then
  # guarantees a red claude-review check on that same PR. Workflow prompts must stay free of
  # current-tense version/count claims (point at CLAUDE.md instead of naming numbers).
)

fail=0
report() { echo "  DRIFT [$1] $2:$3 — \"$4\""; fail=1; }

# Markdown bold is stripped (`tr -d '*'`) before matching, so a bolded claim like
# "**13 agent roles** (" is gated identically to the unbolded form — closes the
# coverage gap where bold between the number and the anchor defeated the pattern.
#
# check_count <ERE-with-the-number> <expected> <label>
check_count() {
  local pat="$1" expected="$2" label="$3" f lineno tok num
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    while IFS=: read -r lineno tok; do
      [ -n "${lineno:-}" ] || continue
      num="$(printf '%s' "$tok" | grep -oE '[0-9]+' | head -1)"
      if [ -n "$num" ] && [ "$num" != "$expected" ]; then
        report "$label" "$f" "$lineno" "$tok"
      fi
    done < <(tr -d '*' < "$f" 2>/dev/null | grep -nEo "$pat")
  done
}

# check_version <ERE-with-an-X.Y.Z> <label>
check_version() {
  local pat="$1" label="$2" f lineno tok ver
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    while IFS=: read -r lineno tok; do
      [ -n "${lineno:-}" ] || continue
      ver="$(printf '%s' "$tok" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
      if [ -n "$ver" ] && [ "$ver" != "$VERSION" ]; then
        report "$label" "$f" "$lineno" "$tok"
      fi
    done < <(tr -d '*' < "$f" 2>/dev/null | grep -nEo "$pat")
  done
}

echo "Scanning $(echo "${FILES[@]}" | wc -w | tr -d ' ') surfaces..."

# --- Version annotations (anchored so historical "(v12.2.0)" mentions are skipped) ---
check_version 'plugin\.json[^[:space:]]* \(v[0-9]+\.[0-9]+\.[0-9]+\)' "manifest-version"
check_version 'Plugin (manifest|metadata) \(v[0-9]+\.[0-9]+\.[0-9]+\)'  "manifest-version"
check_version 'AI agents v[0-9]+\.[0-9]+\.[0-9]+'                        "headline-version"

# --- README intro / Overview version claims (the prose that slipped past the gate
#     once: "The Loomwright Plugin (v14.2.2) includes:"). High-confidence
#     current claims — a parenthesized single version tied to "Plugin" or to an
#     "includes" feature-list intro. NOT matched by the manifest/metadata patterns
#     above (which require the word "manifest"/"metadata" between Plugin and the
#     version), and a historical range like "v14.1.0–v14.2.2" lacks the
#     parenthesized-single-version + anchor, so it stays exempt.
#     NOTE: the second pattern ("(vX.Y.Z) includes") matches that phrase in ANY
#     scanned surface — so a *historical* mid-sentence mention such as
#     "...introduced in (v14.1.0) includes a worker pool..." in an architecture doc
#     WOULD be flagged. If such phrasing ever appears, reword it (or keep it out of
#     the FILES allowlist) rather than loosening this gate. ---
check_version 'Plugin \(v[0-9]+\.[0-9]+\.[0-9]+\)'   "intro-version"
check_version '\(v[0-9]+\.[0-9]+\.[0-9]+\) includes' "intro-version"

# --- Hook count ---
check_count '[0-9]+ quality gate hooks'  "$HOOKS" "hook-count"
check_count '[0-9]+ hooks centralized'   "$HOOKS" "hook-count"

# --- Agent count (total-claim phrasings only; sub-group labels such as
#     "(2 agent roles)" / "(5 agent roles)" are intentionally NOT matched) ---
check_count '[0-9]+ agent roles \('     "$AGENTS" "agent-count"
check_count '[0-9]+ agent roles,'       "$AGENTS" "agent-count"
check_count '[0-9]+-agent system'       "$AGENTS" "agent-count"
check_count '[0-9]+ specialized agents' "$AGENTS" "agent-count"
check_count '[0-9]+ markdown prompts'   "$AGENTS" "agent-count"

# --- Command count ---
check_count 'Slash commands \([0-9]+\)' "$COMMANDS" "command-count"
check_count '[0-9]+ slash commands'     "$COMMANDS" "command-count"
check_count '[0-9]+ entry points'       "$COMMANDS" "command-count"

# --- Skill count ---
check_count '[0-9]+ reusable skills' "$SKILLS" "skill-count"
check_count '[0-9]+ focused skill'   "$SKILLS" "skill-count"
check_count 'and [0-9]+ skills'      "$SKILLS" "skill-count"

if [ "$fail" -ne 0 ]; then
  echo "✗ doc-currency drift detected — update the offending lines to match the authoritative values above."
  exit 1
fi
echo "✓ doc-currency: all checked version/count claims match the authoritative source."
exit 0
