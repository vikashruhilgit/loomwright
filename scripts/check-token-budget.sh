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
# CAVEAT: the weight sizes the ENTIRE agent .md and SKILL.md, frontmatter
# included — it is NOT the literal injected system prompt (frontmatter tools/
# model/hooks blocks are metadata the model never sees; Claude Code even ignores
# plugin-agent frontmatter hooks at runtime). This is a deliberate, CONSISTENT
# over-count: safe for a fail-closed ratchet (over-counting only makes the gate
# stricter, never lets real growth slip through). Do NOT chase frontmatter bytes
# when trimming a prompt — they inflate the proxy but not real tokens.
#
# Budgets are declared in ONE authoritative machine-readable source
# (loomwright/docs/prompt-token-budgets.json), mirrored for humans in
# loomwright/docs/ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets". To raise a
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

# has_inline_skills FILE -> exit 0 if the frontmatter has a `skills:` key with a
# NON-empty inline value (flow style `skills: [a, b]` or a scalar). We only
# support the block form (`skills:` then `- name` lines); an inline form would
# parse to ZERO skills and silently UNDER-count, defeating the fail-closed
# ratchet. Callers treat a true result as an ERROR, not a 0.
has_inline_skills() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit 1 }
    !infm              { next }
    /^skills:[[:space:]]*$/          { next }            # block form -> fine
    /^skills:[[:space:]]*#/          { next }            # only a comment -> fine
    /^skills:[[:space:]]*[^[:space:]]/ { found=1; exit }  # inline value -> flag
    END { exit (found ? 0 : 1) }
  ' "$1"
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
    /^skills:[[:space:]]*$/    { insk=1; next }   # enter the list (bare "skills:")
    /^skills:[[:space:]]*#/    { insk=1; next }   # ...or "skills:  # trailing comment"
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

  # Fail CLOSED on an unsupported inline/flow-style `skills:` list — it would
  # parse to zero skills and silently under-measure (defeating the ratchet).
  if has_inline_skills "$agent_file"; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$stem" "-" "-" "ERROR" "unsupported inline/flow-style 'skills:' list — use the block form ('skills:' then '- name' lines)"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi

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

  # Fail CLOSED on a non-integer budget (float, stray space, quoted typo): the
  # -gt test below would error out falsy and fall into the OK branch — a false
  # green in a fail-closed gate (§Failure-Mode Invariants).
  case "$budget" in ''|*[!0-9]*)
    printf "%-22s %8s %8s  %-6s  %s\n" "$stem" "$total" "$budget" "ERROR" "non-integer budget in $BUDGET_JSON (must be a positive integer)"
    errors=$((errors + 1))
    exit_code=1
    continue ;;
  esac

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

# Orphaned-budget detection (symmetric with the per-agent no-budget ERROR): a
# budget key with no matching agent .md is stale (e.g. an agent was deleted but
# its entry lingers). Fail CLOSED so the JSON stays self-cleaning.
while IFS= read -r key; do
  [ -n "$key" ] || continue
  if [ ! -f "$AGENTS_DIR/$key.md" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$key" "-" "-" "ERROR" "orphaned budget in $BUDGET_JSON — no $AGENTS_DIR/$key.md (remove the stale entry)"
    errors=$((errors + 1))
    exit_code=1
  fi
done <<EOF
$(jq -r '.agents | keys[]' "$BUDGET_JSON" 2>/dev/null)
EOF

# Mirror-table sync (mechanized — the ARCHITECTURE_CONTRACTS human mirror was
# the one unguarded drift surface left; same move as check-skills-index-sync.sh
# for SKILLS_INDEX version cells). Every JSON agent must have a table row whose
# budget cell equals .agents[<stem>].budget, and every table row must have a
# JSON entry (no ghost rows). TOKEN_BUDGET_CONTRACTS_MD set-but-EMPTY skips the
# check (hermetic self-test fixtures only); unset uses the real file; a missing
# file fails CLOSED.
CONTRACTS_MD="${TOKEN_BUDGET_CONTRACTS_MD-loomwright/docs/ARCHITECTURE_CONTRACTS.md}"
if [ -n "$CONTRACTS_MD" ]; then
  if [ ! -f "$CONTRACTS_MD" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "(mirror)" "-" "-" "ERROR" "contracts mirror file not found: $CONTRACTS_MD"
    errors=$((errors + 1))
    exit_code=1
  else
    # Body rows of the §Prompt Token Budgets table: "| `stem` | budget | ..."
    mirror_rows="$(awk '/^## Prompt Token Budgets/{s=1;next} s && /^## /{exit} s && /^\| `/ {print}' "$CONTRACTS_MD")"

    # (a) every JSON agent has a row with an equal budget cell
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      jbudget="$(jq -r --arg k "$key" '.agents[$k].budget' "$BUDGET_JSON")"
      row="$(printf '%s\n' "$mirror_rows" | awk -F'|' -v k="$key" '{s=$2; gsub(/[` ]/,"",s); if (s==k) {print; exit}}')"
      if [ -z "$row" ]; then
        printf "%-22s %8s %8s  %-6s  %s\n" "$key" "-" "$jbudget" "ERROR" "no row in $CONTRACTS_MD §'Prompt Token Budgets' — add the mirror row in the same edit"
        errors=$((errors + 1))
        exit_code=1
      else
        mbudget="$(printf '%s\n' "$row" | awk -F'|' '{b=$3; gsub(/[[:space:]]/,"",b); print b}')"
        if [ "$mbudget" != "$jbudget" ]; then
          printf "%-22s %8s %8s  %-6s  %s\n" "$key" "-" "$jbudget" "ERROR" "mirror drift: table budget cell '$mbudget' != JSON budget '$jbudget' in $CONTRACTS_MD — update both in the same edit"
          errors=$((errors + 1))
          exit_code=1
        fi
      fi
    done <<EOF
$(jq -r '.agents | keys[]' "$BUDGET_JSON" 2>/dev/null)
EOF

    # (b) no ghost rows (a table row whose stem has no JSON entry)
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      rstem="$(printf '%s\n' "$row" | awk -F'|' '{s=$2; gsub(/[` ]/,"",s); print s}')"
      [ -n "$rstem" ] || continue
      if ! jq -e --arg k "$rstem" '.agents | has($k)' "$BUDGET_JSON" >/dev/null 2>&1; then
        printf "%-22s %8s %8s  %-6s  %s\n" "$rstem" "-" "-" "ERROR" "ghost mirror row: table lists an agent with no entry in $BUDGET_JSON"
        errors=$((errors + 1))
        exit_code=1
      fi
    done <<EOF
$mirror_rows
EOF
  fi
fi

echo "------------------------------------------------------------------------------"
echo "agents checked: $agent_count | breaches: $breaches | errors: $errors | proxy tokens = bytes/$DIVISOR (NOT exact Anthropic counts)"

if [ "$exit_code" -ne 0 ]; then
  echo "check-token-budget: FAILED — prompt inventory ratchet tripped (see BREACH/ERROR rows above)." >&2
else
  echo "check-token-budget: OK — all agents within their declared prompt-inventory budgets."
fi
exit "$exit_code"
