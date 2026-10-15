#!/usr/bin/env bash
# check-token-budget.sh — CI-enforced prompt-size ceilings (ratchet) for every
# agent, every skill dir and every command doc.
#
# WHY: agent prompts, skills and command docs accrete words every release and
# nothing pushes back. Prompt inventory weight grows unmeasured, and every spawn
# or on-demand read pays for it. This gate makes three sizes mechanically
# enforced contracts, exactly like check-doc-currency.sh does for version/count
# claims, and fails CLOSED (exit 1) on any breach:
#   .agents[<stem>]   — an agent's effective spawn-time weight: the agent .md
#                       PLUS every skill preloaded via its frontmatter `skills:`.
#   .skills[<dir>]    — a skill dir's weight: EVERY *.md under the dir, counted
#                       recursively (a future references/ subfolder is measured,
#                       never silently skipped). Loose files at the skills root
#                       (SKILLS_INDEX.md, SKILL_TEMPLATE.md) are not skill dirs.
#   .commands[<stem>] — a command doc's weight: <commands dir>/<stem>.md.
# Each table fails CLOSED on a breach, a missing entry, an orphaned entry, a
# non-integer budget, and a missing or empty dir.
#
# IMPORTANT — PROXY, NOT A REAL TOKEN COUNT. The weight is an OFFLINE PROXY
# (bytes / 4), never a call to Anthropic's count_tokens API (no network in CI).
# It therefore controls PROMPT INVENTORY GROWTH (how many words we ship per
# spawn), NOT live tokenizer inflation (Opus vs pre-4.7 token ratios). A byte
# proxy cannot track tokenizer changes; that is out of scope by design. Every
# number this gate prints is labeled "proxy tokens" — never an exact count.
#
# SCOPE: an agent row counts only the skills PRELOADED via its frontmatter (they
# are injected at spawn time). On-demand skills and command docs are not
# spawn-time weight, so they are gated by their OWN ceilings (.skills/.commands)
# rather than folded into an agent's row — a preloaded skill is therefore
# measured twice, once in each agent that preloads it and once in its own row.
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
# loomwright/docs/ARCHITECTURE_CONTRACTS.md §"Prompt Token Budgets" (one mirror
# table per JSON table). To raise a budget: raise it in prompt-token-budgets.json
# in the SAME PR that breaches it, with a ONE-line reason in the `note` field
# (history goes to CHANGELOG.md) — the gate reads the JSON, so the raise is
# visible in the PR diff.
#
# Exit 0 = every agent, skill dir and command doc within budget. Exit 1 = at
# least one breach OR a broken frontmatter skill reference OR a missing,
# orphaned or non-integer entry OR a missing/empty dir OR mirror-table drift.
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
COMMANDS_DIR="${TOKEN_BUDGET_COMMANDS_DIR:-loomwright/commands}"
BUDGET_JSON="${TOKEN_BUDGET_JSON:-loomwright/docs/prompt-token-budgets.json}"

command -v jq >/dev/null 2>&1 || { echo "check-token-budget: jq required" >&2; exit 1; }
[ -d "$AGENTS_DIR" ] || { echo "check-token-budget: agents dir not found: $AGENTS_DIR" >&2; exit 1; }
[ -f "$BUDGET_JSON" ] || { echo "check-token-budget: budget file not found: $BUDGET_JSON" >&2; exit 1; }

# Proxy divisor (bytes per proxy-token). Sourced from the JSON so the label and
# the math never drift; defaults to 4 if unset.
DIVISOR="$(jq -r '.proxy_bytes_per_token // 4' "$BUDGET_JSON")"
# A leading-zero value ("08") passes a digits-only check but is OCTAL inside
# $((...)): "08"/"09" abort the arithmetic, so every proxy_tokens call would echo
# nothing and each row would compare an EMPTY total — a false green. Reject it.
case "$DIVISOR" in ''|*[!0-9]*|0[0-9]*) DIVISOR=4 ;; esac
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
  # green in a fail-closed gate (§Failure-Mode Invariants). A leading-zero value
  # ("08") is refused too: [ -gt ] reads it as decimal, but $((total - budget))
  # reads it as OCTAL and aborts the branch before the BREACH is counted.
  case "$budget" in ''|*[!0-9]*|0[0-9]*)
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


# check_ceiling TABLE KEY TOTAL DETAIL -> one row for a .skills/.commands entry:
# ERROR on a missing or non-integer budget, BREACH over it, OK otherwise. Same
# wording and the same fail-CLOSED rules as the agent rows above. A jq error (a
# table that is not an object) yields an empty budget, which the non-integer
# guard turns into an ERROR — never a false green.
check_ceiling() {
  local table="$1" key="$2" total="$3" detail="$4" budget
  budget="$(jq -r --arg t "$table" --arg k "$key" '.[$t][$k].budget // "null"' "$BUDGET_JSON" 2>/dev/null)"
  if [ "$budget" = "null" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$key" "$total" "-" "ERROR" "no budget declared in $BUDGET_JSON (add a .$table[\"$key\"] entry)"
    errors=$((errors + 1))
    exit_code=1
    return
  fi
  # Leading zero refused for the same octal reason as the agent rows above.
  case "$budget" in ''|*[!0-9]*|0[0-9]*)
    printf "%-22s %8s %8s  %-6s  %s\n" "$key" "$total" "$budget" "ERROR" "non-integer budget in $BUDGET_JSON (must be a positive integer)"
    errors=$((errors + 1))
    exit_code=1
    return ;;
  esac
  if [ "$total" -gt "$budget" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$key" "$total" "$budget" "BREACH" "over by $((total - budget)) proxy tokens ($detail) — raise .$table[\"$key\"] in the same PR (one-line note) or trim it"
    breaches=$((breaches + 1))
    exit_code=1
  else
    printf "%-22s %8s %8s  %-6s  %s\n" "$key" "$total" "$budget" "OK" "$((budget - total)) headroom ($detail)"
  fi
}

# check_orphans TABLE SEEN-LIST WHAT -> ERROR for every .<TABLE> key that is not
# in SEEN-LIST (the newline-delimited names this run actually enumerated and
# measured). Membership is checked against what was measured, not against the
# filesystem, so a key naming a hidden or nested path can never count as present.
check_orphans() {
  local table="$1" seen="$2" what="$3" key nl='
'
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case "$nl$seen$nl" in
      *"$nl$key$nl"*) ;;
      *)
        printf "%-22s %8s %8s  %-6s  %s\n" "$key" "-" "-" "ERROR" "orphaned budget in $BUDGET_JSON — no $what for .$table[\"$key\"] (remove the stale entry)"
        errors=$((errors + 1))
        exit_code=1 ;;
    esac
  done <<EOF
$(jq -r --arg t "$table" '.[$t] | keys[]' "$BUDGET_JSON" 2>/dev/null)
EOF
}

# skill_weight DIR -> "<proxy tokens> <md files>" summed over EVERY *.md under
# DIR, recursively (floor per file, then summed — the same per-file proxy the
# agent rows use). Returns 1 when `find` fails, so an unreadable subtree is an
# ERROR rather than a silent under-count. Returns 2 (and prints the symlinks)
# when the subtree holds ANY symlink: `find -type f` neither counts a symlinked
# file nor descends a symlinked dir, so measuring past one would silently
# under-count. Fail CLOSED rather than follow (`find -L` risks link loops).
skill_weight() {
  local list links f t=0 n=0
  links="$(find "$1" -type l 2>/dev/null)" || return 1
  if [ -n "$links" ]; then
    printf '%s\n' "$links"
    return 2
  fi
  list="$(find "$1" -type f -name '*.md' 2>/dev/null)" || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    t=$((t + $(proxy_tokens "$f")))
    n=$((n + 1))
  done <<EOF
$list
EOF
  echo "$t $n"
}

# --- Skill dirs: .skills[<dir>] -------------------------------------------------
# Every non-hidden directory directly under the skills dir is a skill dir; loose
# files at the root (SKILLS_INDEX.md, SKILL_TEMPLATE.md) are not, need no entry
# and are not measured. A .skills key naming anything else is an orphan.
printf "%-22s %8s %8s  %-6s  %s\n" "SKILL DIR" "PROXY" "BUDGET" "STATUS" "DETAIL"
skill_count=0
seen_skills=""
for skill_dir in "$SKILLS_DIR"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_dir="${skill_dir%/}"
  skill_count=$((skill_count + 1))
  name="$(basename "$skill_dir")"
  seen_skills="$seen_skills
$name"
  # A symlinked skill dir is never walked by `find` (a start-path symlink is not
  # followed), so it would measure 0 .md files — fail CLOSED instead.
  if [ -L "$skill_dir" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$name" "-" "-" "ERROR" "skill dir is a symlink ($skill_dir) — it cannot be measured; replace it with a real dir"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi
  weight="$(skill_weight "$skill_dir")"; wrc=$?
  if [ "$wrc" -eq 2 ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$name" "-" "-" "ERROR" "symlink under $skill_dir cannot be measured (would be silently skipped): $(printf '%s' "$weight" | tr '\n' ' ')"
    errors=$((errors + 1))
    exit_code=1
    continue
  elif [ "$wrc" -ne 0 ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "$name" "-" "-" "ERROR" "could not list the *.md files under $skill_dir"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi
  check_ceiling skills "$name" "${weight% *}" "${weight#* } .md files"
done

# Anti-drift: a missing or empty skills dir must fail LOUDLY — a 0-skill run of a
# fail-closed ratchet is a false green. Runs after the zero-agent guard above.
if [ "$skill_count" -eq 0 ]; then
  echo "check-token-budget: no skill dirs found in $SKILLS_DIR (missing or empty) — refusing to pass a 0-skill ratchet" >&2
  exit 1
fi
check_orphans skills "$seen_skills" "skill dir under $SKILLS_DIR/"

# --- Command docs: .commands[<stem>] --------------------------------------------
printf "%-22s %8s %8s  %-6s  %s\n" "COMMAND DOC" "PROXY" "BUDGET" "STATUS" "DETAIL"
command_count=0
seen_commands=""
for cmd_file in "$COMMANDS_DIR"/*.md; do
  # A dangling symlinked command doc fails `-f` and would be silently skipped —
  # fail CLOSED. A live symlink is measured through `wc -c` (target bytes).
  if [ -L "$cmd_file" ] && [ ! -f "$cmd_file" ]; then
    command_count=$((command_count + 1))
    seen_commands="$seen_commands
$(basename "$cmd_file" .md)"
    printf "%-22s %8s %8s  %-6s  %s\n" "$(basename "$cmd_file" .md)" "-" "-" "ERROR" "command doc $cmd_file is a dangling symlink — it cannot be measured"
    errors=$((errors + 1))
    exit_code=1
    continue
  fi
  [ -f "$cmd_file" ] || continue
  command_count=$((command_count + 1))
  stem="$(basename "$cmd_file" .md)"
  seen_commands="$seen_commands
$stem"
  check_ceiling commands "$stem" "$(proxy_tokens "$cmd_file")" "$cmd_file"
done

if [ "$command_count" -eq 0 ]; then
  echo "check-token-budget: no command .md files found in $COMMANDS_DIR (missing or empty) — refusing to pass a 0-command ratchet" >&2
  exit 1
fi
check_orphans commands "$seen_commands" "command doc $COMMANDS_DIR/<stem>.md"

# Mirror-table sync (mechanized — the ARCHITECTURE_CONTRACTS human mirror was
# the one unguarded drift surface left; same move as check-skills-index-sync.sh
# for SKILLS_INDEX version cells). For each JSON table (agents, skills,
# commands) every entry must have a row in ITS mirror table whose budget cell
# equals .<table>[<key>].budget (and whose measured cell, when both sides record
# one, equals .measured), and every table row must have a JSON entry (no ghost
# rows). TOKEN_BUDGET_CONTRACTS_MD set-but-EMPTY skips the check (hermetic
# self-test fixtures only); unset uses the real file; a missing file fails
# CLOSED.
CONTRACTS_MD="${TOKEN_BUDGET_CONTRACTS_MD-loomwright/docs/ARCHITECTURE_CONTRACTS.md}"
SKILLS_MIRROR_HEADING="Skill size ceilings"
COMMANDS_MIRROR_HEADING="Command size ceilings"

# mirror_rows [SUBHEADING] -> body rows ("| `key` | budget | measured | ...") of
# ONE mirror table, each bounded to its own block inside §Prompt Token Budgets:
# no SUBHEADING = the agent table, i.e. the rows BEFORE the section's first
# "### " heading; SUBHEADING = the rows under "### <SUBHEADING>" only, up to the
# next "### " or "## ". So a skill/command row is never read as an agent row.
mirror_rows() {
  awk -v want="$1" '
    /^## Prompt Token Budgets/ { insec=1; s=(want==""); next }
    insec && /^## /            { exit }
    insec && /^### /           { s=(want!="" && index($0, "### " want)==1); next }
    insec && s && /^\| `/      { print }
  ' "$CONTRACTS_MD"
}

# check_mirror TABLE NOUN [SUBHEADING] -> drift / missing-row / ghost-row ERRORs
# for one JSON table against its mirror table.
check_mirror() {
  local table="$1" noun="$2" want="${3-}" rows where key jbudget row mbudget jmeasured mmeasured rstem
  rows="$(mirror_rows "$want")"
  where="§'Prompt Token Budgets'"
  [ -z "$want" ] || where="§'Prompt Token Budgets' / '### $want'"

  # (a) every JSON entry has a row with an equal budget cell
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    jbudget="$(jq -r --arg t "$table" --arg k "$key" '.[$t][$k].budget' "$BUDGET_JSON")"
    row="$(printf '%s\n' "$rows" | awk -F'|' -v k="$key" '{s=$2; gsub(/[` ]/,"",s); if (s==k) {print; exit}}')"
    if [ -z "$row" ]; then
      printf "%-22s %8s %8s  %-6s  %s\n" "$key" "-" "$jbudget" "ERROR" "no row in $CONTRACTS_MD $where — add the mirror row in the same edit"
      errors=$((errors + 1))
      exit_code=1
    else
      mbudget="$(printf '%s\n' "$row" | awk -F'|' '{b=$3; gsub(/[[:space:]]/,"",b); print b}')"
      if [ "$mbudget" != "$jbudget" ]; then
        printf "%-22s %8s %8s  %-6s  %s\n" "$key" "-" "$jbudget" "ERROR" "mirror drift: table budget cell '$mbudget' != JSON budget '$jbudget' in $CONTRACTS_MD — update both in the same edit"
        errors=$((errors + 1))
        exit_code=1
      fi
      # ALSO sync the MEASURED column (v15.20.0). Previously only the budget cell was
      # checked, so a raise that also overwrote the frozen `Measured` cell — with the OLD
      # BUDGET value, contradicting both the authoritative JSON `.measured` and the footnote
      # that owns the cell — passed CI silently. A falsified historical measurement is worse
      # than a stale one: it is the baseline every future raise argues from. Footnote markers
      # (`26357¹`) are stripped before comparison; an EMPTY measured cell is tolerated (some
      # rows legitimately carry no baseline yet), a MISMATCHED one is not.
      jmeasured="$(jq -r --arg t "$table" --arg k "$key" '.[$t][$k].measured // ""' "$BUDGET_JSON")"
      mmeasured="$(printf '%s\n' "$row" | awk -F'|' '{m=$4; gsub(/[[:space:]]/,"",m); print m}' | sed 's/[^0-9]//g')"
      # `0` (and empty) mean NO BASELINE RECORDED, not "measured zero" — a real agent always
      # measures > 0. Skipping them keeps the check off rows that have no baseline yet.
      if [ -n "$jmeasured" ] && [ "$jmeasured" != "0" ] \
         && [ -n "$mmeasured" ] && [ "$mmeasured" != "0" ] \
         && [ "$mmeasured" != "$jmeasured" ]; then
        printf "%-22s %8s %8s  %-6s  %s\n" "$key" "-" "$jbudget" "ERROR" "mirror drift: table MEASURED cell '$mmeasured' != JSON measured '$jmeasured' in $CONTRACTS_MD — the measured column is a FROZEN baseline; a raise changes only the budget column"
        errors=$((errors + 1))
        exit_code=1
      fi
    fi
  done <<EOF
$(jq -r --arg t "$table" '.[$t] | keys[]' "$BUDGET_JSON" 2>/dev/null)
EOF

  # (b) no ghost rows (a table row whose key has no JSON entry)
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rstem="$(printf '%s\n' "$row" | awk -F'|' '{s=$2; gsub(/[` ]/,"",s); print s}')"
    [ -n "$rstem" ] || continue
    if ! jq -e --arg t "$table" --arg k "$rstem" '.[$t] | has($k)' "$BUDGET_JSON" >/dev/null 2>&1; then
      printf "%-22s %8s %8s  %-6s  %s\n" "$rstem" "-" "-" "ERROR" "ghost mirror row: table lists $noun with no .$table entry in $BUDGET_JSON"
      errors=$((errors + 1))
      exit_code=1
    fi
  done <<EOF
$rows
EOF
}

if [ -n "$CONTRACTS_MD" ]; then
  if [ ! -f "$CONTRACTS_MD" ]; then
    printf "%-22s %8s %8s  %-6s  %s\n" "(mirror)" "-" "-" "ERROR" "contracts mirror file not found: $CONTRACTS_MD"
    errors=$((errors + 1))
    exit_code=1
  else
    check_mirror agents "an agent"
    check_mirror skills "a skill dir" "$SKILLS_MIRROR_HEADING"
    check_mirror commands "a command doc" "$COMMANDS_MIRROR_HEADING"
  fi
fi

echo "------------------------------------------------------------------------------"
echo "agents checked: $agent_count | skill dirs checked: $skill_count | command docs checked: $command_count | breaches: $breaches | errors: $errors | proxy tokens = bytes/$DIVISOR (NOT exact Anthropic counts)"

if [ "$exit_code" -ne 0 ]; then
  echo "check-token-budget: FAILED — prompt inventory ratchet tripped (see BREACH/ERROR rows above)." >&2
else
  echo "check-token-budget: OK — every agent, skill dir and command doc within its declared prompt-inventory budget."
fi
exit "$exit_code"
