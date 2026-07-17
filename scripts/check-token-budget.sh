#!/usr/bin/env bash
# check-token-budget.sh — CI-enforced per-agent prompt token budgets (ratchet).
#
# WHY: 14 agent prompts x 41 skills accrete words every release and nothing
# pushes back. Prompt inventory weight grows unmeasured, and every spawn pays
# for it. This gate makes an agent's effective spawn-time prompt weight — the
# agent .md PLUS every skill preloaded via its frontmatter `skills:` list — a
# mechanically enforced contract, exactly like check-doc-currency.sh does for
# version/count claims. It fails CLOSED (exit 1) on any breach.
#
# IMPORTANT — PROXY, NOT A REAL TOKEN COUNT. The weight is an OFFLINE PROXY
# (bytes / 4), never a call to Anthropic's count_tokens API (no network in CI).
# It therefore controls PROMPT INVENTORY GROWTH (how many words we ship per
# spawn), NOT live tokenizer inflation (Opus vs pre-4.7 token ratios). A byte
# proxy cannot track tokenizer changes; that is out of scope by design. Every
# number this gate prints is labeled "proxy tokens" — never an exact count.
#
# SCOPE: only skills PRELOADED via agent frontmatter are counted (they are
# injected at spawn time). Command docs, on-demand skills, and non-preloaded
# references are deliberately excluded — they are not part of spawn-time weight.
#
# Budgets are declared in ONE authoritative machine-readable source
# (loomwright/docs/prompt-token-budgets.json), mirrored for humans in
# loomwright/docs/ARCHITECTURE_CONTRACTS.md #"Prompt Token Budgets". To raise a
# budget: raise it in prompt-token-budgets.json in the SAME PR that breaches it,
# with a one-line justification in the `note` field — the gate reads the JSON,
# so the raise is visible in the PR diff.
#
# Exit 0 = every agent within budget. Exit 1 = at least one breach OR a broken
# frontmatter skill reference OR an agent with no declared budget.
#
# Portability: bash 3.2 safe (macOS). No `${var//...}` pattern-subst on large
# strings (O(n^2) wedge on macOS bash 3.2). No GNU-only stat/sed/date flags —
# byte sizes come from `wc -c`. Deterministic and fully offline.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# Overridable for the self-test (hermetic fixtures); default to the real repo.
AGENTS_DIR="${TOKEN_BUDGET_AGENTS_DIR:-loomwright/agents}"
SKILLS_DIR="${TOKEN_BUDGET_SKILLS_DIR:-loomwright/skills}"
BUDGET_JSON="${TOKEN_BUDGET_JSON:-loomwright/docs/prompt-token-budgets.json}"

command -v jq >/dev/null 2>&1 || { echo "check-token-budget: jq required" >&2; exit 1; }
[ -d "$AGENTS_DIR" ] || { echo "check-token-budget: agents dir not found: $AGENTS_DIR" >&2; exit 1; }
[ -f "$BUDGET_JSON" ] || { echo "check-token-budget: budget file not found: $BUDGET_JSON" >&2; exit 1; }

# Proxy divisor (bytes per proxy-token). Sourced from the JSON so the label and
# the math never drift; defaults to 4 if unset.
DIVISOR="$(jq -r '.proxy_bytes_per_token // 4' "$BUDGET_JSON")"
case "$DIVISOR" in ''|*[!0-9]*) DIVISOR=4 ;; esac
[ "$DIVISOR" -ge 1 ] 2>/dev/null || DIVISOR=4

# proxy_tokens FILE -> echoes floor(bytes / DIVISOR). `wc -c` is portable.
proxy_tokens() {
  local b
  b="$(wc -c < "$1" | tr -d ' ')"
  echo "$(( b / DIVISOR ))"
}

# preloaded_skills FILE -> prints one skill name per line from the frontmatter
# `skills:` YAML list. Parsing is BOUNDED to the frontmatter (between the first
# two `^---$` lines) so body bullets and prose never leak in. Inline `# comment`
# suffixes and surrounding whitespace are stripped.
preloaded_skills() {
  awk '
    NR==1 && $0=="---" { infm=1; next }        # opening fence
    infm && $0=="---"  { exit }                # closing fence -> stop
    !infm              { next }                # never parse the body
    /^skills:[[:space:]]*$/ { insk=1; next }   # enter the skills: list
    insk && /^[A-Za-z_][A-Za-z0-9_-]*:/ { insk=0 }  # next top-level key -> leave
    insk && /^[[:space:]]*-[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)  # drop the "- " bullet
      sub(/[[:space:]]*#.*$/, "", line)            # drop inline comment
      gsub(/[[:space:]]/, "", line)                # drop stray whitespace
      if (line != "") print line
    }
  ' "$1"
}

exit_code=0
breaches=0
errors=0
agent_count=0

echo "check-token-budget — proxy tokens = bytes / $DIVISOR (OFFLINE PROXY, not an Anthropic token count)"
echo "authoritative budgets: $BUDGET_JSON"
echo "------------------------------------------------------------------------------"
printf "%-22s %8s %8s  %-6s  %s\n" "AGENT" "PROXY" "BUDGET" "STATUS" "DETAIL"

for agent_file in "$AGENTS_DIR"/*.md; do
  [ -f "$agent_file" ] || continue
  agent_count=$((agent_count + 1))
  stem="$(basename "$agent_file" .md)"

  total="$(proxy_tokens "$agent_file")"
  nskills=0
  detail_missing=""
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    nskills=$((nskills + 1))
    skill_file="$SKILLS_DIR/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      total=$((total + $(proxy_tokens "$skill_file")))
    else
      detail_missing="$detail_missing $skill"
    fi
  done <<EOF
$(preloaded_skills "$agent_file")
EOF

  if [ -n "$detail_missing" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$stem" "$total" "-" "ERROR" "missing preloaded SKILL.md for:$detail_missing"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi

  budget="$(jq -r --arg k "$stem" '.agents[$k].budget // "null"' "$BUDGET_JSON")"
  if [ "$budget" = "null" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$stem" "$total" "-" "ERROR" "no budget declared in $BUDGET_JSON (add an .agents[\"$stem\"] entry)"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi

  if [ "$total" -gt "$budget" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$stem" "$total" "$budget" "BREACH" "over by $((total - budget)) proxy tokens ($nskills preloaded skills) — raise the budget in the same PR (with a note) or trim the prompt"
    breaches=$((breaches + 1))
    exit_code=1
  else
    printf "%-22s %8s %8s  %-6s  %s\n" "$stem" "$total" "$budget" "OK" "$((budget - total)) headroom ($nskills preloaded skills)"
  fi
done

# Anti-drift: an empty/misconfigured agents dir must fail LOUDLY, not silently pass
# (a 0-agent run of a fail-closed ratchet is a false green). Mirrors the ci.yml
# self-test loop's `[ "${#tests[@]}" -gt 0 ] || exit 1` guard.
if [ "$agent_count" -eq 0 ]; then
  echo "check-token-budget: no agent .md files found in $AGENTS_DIR — refusing to pass a 0-agent ratchet" >&2
  exit 1
fi

echo "------------------------------------------------------------------------------"
echo "agents checked: $agent_count | breaches: $breaches | errors: $errors | proxy tokens = bytes/$DIVISOR (NOT exact Anthropic counts)"

if [ "$exit_code" -ne 0 ]; then
  echo "check-token-budget: FAILED — prompt inventory ratchet tripped (see BREACH/ERROR rows above)." >&2
else
  echo "check-token-budget: OK — all agents within their declared prompt-inventory budgets."
fi
exit "$exit_code"
