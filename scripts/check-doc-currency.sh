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
# `plugin.json` / the `Loomwright vX.Y.Z` headline / the README intro's
# `Plugin (vX.Y.Z)` and `(vX.Y.Z) includes:` claims, and explicit count phrases
# ("N quality gate hooks", "N agent roles", "Slash commands (N)", ...). It never
# scans bare numbers, so dated changelog entries like "v12.2.0 took the count
# 13 -> 14" do NOT trigger it.
#
# SURFACES THIS GATE DOES NOT SCAN (recurring drift, integration-review-only —
# relocated here from CLAUDE.md in the v15.21.0 diet, content moved never deleted):
# Supervisor phase enumerations (agent-help.md, command docs), per-run YAML
# frontmatter field lists in build-insights.sh, budget/zone numbers, and /insights
# dashboard section enumerations. Per-row skill `version:` cells in SKILLS_INDEX.md
# are instead mechanically enforced by scripts/check-skills-index-sync.sh, and the
# ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets" per-agent mirror table's budget
# cells are mechanically synced to prompt-token-budgets.json by
# scripts/check-token-budget.sh (drifted/missing/ghost rows fail CI closed there) —
# neither needs this gate's coverage.
#
# FROZEN, VERSION-AGNOSTIC EXAMPLE VALUES ARE INTENTIONALLY LEFT ALONE: sample
# `session_end` / `POSTMORTEM_RESULT` JSONL records and `e.g. "X.Y.Z"`
# `plugin_version` placeholders (in docs/RESULT_SCHEMAS.md, agents/supervisor.md,
# and similar) illustrate *format* only — the real value is read at runtime from
# plugin.json via jq, so they are NOT current-claims and carry no currency
# requirement. Do not "fix" them to the current version on a bump; bumping them
# every release is a drift-treadmill this gate cannot enforce (they re-stale at the
# next version) — a stale-looking version inside an example block is intended, not
# drift. On any phase/version/budget/section change, grep the OLD value repo-wide —
# a green run of this gate is necessary but NOT sufficient.
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
check_version 'Loomwright v[0-9]+\.[0-9]+\.[0-9]+'                       "headline-version"

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

# --- Description card: length + single-version-token gate (red-team-hardening
#     item 08, Fix 4). CLAUDE.md's own "description is a summary, not a
#     changelog" rule had no mechanical enforcement until now: plugin.json's
#     description accreted to 3,131 chars of release narrative before this
#     check existed. 600 is a wider ceiling than the ~400-char card this PR
#     ships (a soft-fail buffer, not the target — the target is the AC's
#     <=400), so the gate does not force a re-edit on every small addition
#     while still catching the accretion pattern early. More than one
#     vX.Y.Z-shaped token is the same "restate history in the card"
#     anti-pattern a single token already flags. -----------------------------
run_description_length_check() {
  local rc=0
  local plugin_desc marketplace_desc plugin_len marketplace_len plugin_vtoks marketplace_vtoks
  plugin_desc="$(jq -r '.description // ""' "$PLUGIN_JSON" 2>/dev/null)"
  marketplace_desc="$(jq -r '[.plugins[]? | select(.name == "loomwright") | .description] | first // ""' .claude-plugin/marketplace.json 2>/dev/null)"
  plugin_len=${#plugin_desc}
  marketplace_len=${#marketplace_desc}
  plugin_vtoks="$(printf '%s' "$plugin_desc" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | wc -l | tr -d ' ')"
  marketplace_vtoks="$(printf '%s' "$marketplace_desc" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | wc -l | tr -d ' ')"
  if [ "$plugin_len" -gt 600 ]; then
    echo "  DRIFT [description-length] $PLUGIN_JSON — description is $plugin_len chars, exceeds 600"
    rc=1
  fi
  if [ "$marketplace_len" -gt 600 ]; then
    echo "  DRIFT [description-length] .claude-plugin/marketplace.json (loomwright) — description is $marketplace_len chars, exceeds 600"
    rc=1
  fi
  if [ "$plugin_vtoks" -gt 1 ]; then
    echo "  DRIFT [description-version-tokens] $PLUGIN_JSON — description contains $plugin_vtoks vX.Y.Z-shaped tokens, expected at most 1"
    rc=1
  fi
  if [ "$marketplace_vtoks" -gt 1 ]; then
    echo "  DRIFT [description-version-tokens] .claude-plugin/marketplace.json (loomwright) — description contains $marketplace_vtoks vX.Y.Z-shaped tokens, expected at most 1"
    rc=1
  fi
  return $rc
}
run_description_length_check || fail=1

# --- Color legend (generated table vs agent frontmatter) ---
# The legend in ARCHITECTURE_CONTRACTS.md is GENERATED OUTPUT, so its currency is checked by
# re-running the generator rather than by a prose pattern: gen-color-legend.sh --check compares
# the marked block against agent frontmatter and exits non-zero with a `LEGEND DRIFT` /
# `LEGEND MARKERS MISSING` diagnostic. Folded in here rather than added as a separate CI step,
# per the requirement — this gate is already the doc-currency surface.
#
# The invocation is a single line on purpose. test-gen-color-legend.sh's mutation control
# deletes exactly that line from a COPY of this script and proves the gate then wrongly PASSES
# on a genuinely drifted fixture — which is what shows the check EXECUTED, not merely that it
# is reachable. Keep it one line, and keep the function separate from its call.
run_legend_check() {
  local out rc
  out="$(bash "$repo_root/loomwright/scripts/gen-color-legend.sh" --check 2>&1)"; rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  return $rc
}
run_legend_check || fail=1

# --- mysql-mcp: exact-version pin, no --refresh (red-team-hardening item 07) -----------------
# The FILES/authoritative-version scan above is scoped to the loomwright plugin only — it does
# not scan mysql-mcp's own launch config. Without this check, a `--refresh` reintroduced into
# mysql-mcp/.mcp.json (which forces `uvx` to re-resolve the latest PyPI release into a
# credentialed process on every session start) or a version pin silently stripped back to a
# floating `--from vikashruhil-mysql-mcp` would pass every other gate in this file.
run_mysql_mcp_pin_check() {
  local mcp_json="$repo_root/mysql-mcp/.mcp.json" args pinned
  # Skip (not a drift) when the file is absent — mirrors the FILES-loop convention above
  # (`[ -f "$f" ] || continue`); a tree that doesn't model the mysql-mcp sibling plugin at all
  # (e.g. this gate's own test fixtures) has nothing for this assertion to check.
  [ -f "$mcp_json" ] || return 0
  args="$(jq -r '.mcpServers.mysql.args[]?' "$mcp_json" 2>/dev/null)"
  if [ -z "$args" ]; then
    echo "  DRIFT [mysql-mcp-pin] mysql-mcp/.mcp.json — could not read .mcpServers.mysql.args"
    return 1
  fi
  if printf '%s\n' "$args" | grep -qx -- '--refresh'; then
    echo "  DRIFT [mysql-mcp-pin] mysql-mcp/.mcp.json — --refresh present (forces an unpinned re-resolve into a credentialed process on every launch)"
    return 1
  fi
  pinned="$(printf '%s\n' "$args" | grep -E '^vikashruhil-mysql-mcp==')"
  if [ -z "$pinned" ]; then
    echo "  DRIFT [mysql-mcp-pin] mysql-mcp/.mcp.json — vikashruhil-mysql-mcp is not pinned to an exact \`==\` version"
    return 1
  fi
  return 0
}
run_mysql_mcp_pin_check || fail=1

# --- Every counted command is actually documented -------------------------------------------
# A count claim can match the directory while the thing it counts is undocumented: bumping
# "23 slash commands" is invisible to every pattern above if no `### /<cmd>` section was added.
# That is the gap that shipped /propose in v15.57.0 with the count bumped and the command
# absent from /agent-help's own Command Reference -- the file CLAUDE.md tells contributors to
# use to VERIFY a new command. The postmortem ledger records this class (a new subcommand
# shipped without its restatement across the enumerating surfaces) as a repeat self-heal miss,
# so check the SUBJECT of the count, not only its magnitude.
#
# /agent-help is exempt: it is the Command Reference, and a section describing the file you
# are reading is not what a user needs. Every other command must appear.
help_md="$repo_root/loomwright/commands/agent-help.md"
cmds_seen=0
undocumented=""
for cmd_file in "$repo_root"/loomwright/commands/*.md; do
  # A non-matching glob expands to the literal pattern; without this the loop would report a
  # bogus "*" as undocumented in any tree with no command files.
  [ -e "$cmd_file" ] || continue
  cmd="$(basename "$cmd_file" .md)"
  [ "$cmd" = "agent-help" ] && continue
  cmds_seen=$((cmds_seen + 1))
  grep -qE "^### .*/${cmd} " "$help_md" 2>/dev/null || undocumented="$undocumented $cmd"
done
# Only demand the reference exist when there is something for it to document. A tree with no
# commands (a fixture, a partial checkout) makes this vacuously true, and the count checks
# above are what catch a commands/ directory that wrongly went empty.
if [ "$cmds_seen" -gt 0 ]; then
  if [ ! -r "$help_md" ]; then
    echo "  DRIFT [command-documented] loomwright/commands/agent-help.md — unreadable, so the per-command check would be vacuous for $cmds_seen command(s)"
    fail=1
  elif [ -n "$undocumented" ]; then
    echo "  DRIFT [command-documented] loomwright/commands/agent-help.md — counted but with no \`### /<cmd>\` section:$undocumented"
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "✗ doc-currency drift detected — update the offending lines to match the authoritative values above."
  exit 1
fi
echo "✓ doc-currency: all checked version/count claims match the authoritative source."
exit 0
