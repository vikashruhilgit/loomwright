#!/usr/bin/env bash
# test-check-token-budget.sh — self-test for scripts/check-token-budget.sh.
#
# Fully offline, deterministic, macOS bash 3.2 safe. Uses hermetic temp fixture
# dirs (agents/, skills/, commands/, budgets.json) via the gate's TOKEN_BUDGET_* env
# overrides — the real repo is never touched. No GNU-only stat/sed/date flags
# (memory: stat-flavor set-u trap; macOS-green != CI-green).
#
# Cases (by category — assertion counts are intentionally not restated in docs,
# to avoid the very count-drift this repo gates against):
#   1.  PASS   — agent (+ preloaded skill) under budget -> exit 0
#   2.  BREACH — agent over budget -> exit 1 + a readable BREACH row
#   3.  MISSING-PRELOADED-SKILL — frontmatter names a skill whose SKILL.md is
#       absent -> exit 1 + an ERROR row (broken preload reference)
#   4.  NO-BUDGET — agent with no JSON budget entry -> exit 1 + ERROR row
#   5.  FRONTMATTER-BOUNDED PARSING — a body `- ` bullet is NOT counted as a skill
#   5b. EMPTY-AGENTS-DIR — a 0-agent run fails CLOSED (no false-green ratchet)
#   5c. INLINE/FLOW-STYLE skills: — unsupported form ERRORs (would under-count)
#   5d. ORPHANED-BUDGET — a budget key with no matching agent .md ERRORs
#   5e. COMMENT-TRAILING skills: opener still counts its block items
#   5f. MIRROR-TABLE SYNC — contracts table drift / missing row / ghost row /
#       missing file all fail CLOSED; matching mirror passes
#   7.  SKILL / COMMAND CEILINGS (.skills[<dir>] / .commands[<stem>]) — skill
#       breach, a nested *.md only a recursive walk sees, missing skill/command
#       entry, skill/command orphan, non-integer skill/command budget, missing or
#       empty skills dir, missing or empty commands dir — all fail CLOSED; loose
#       files at the skills root are not skill dirs
#   8.  THREE-TABLE MIRROR — skill/command budget drift, measured drift, missing
#       row and ghost row each fail CLOSED; a valid agents+skills+commands mirror
#       passes together (the agent-table parse is bounded, so skill/command rows
#       are never read as agent ghost rows)
#   6.  LIVE REPO — the real gate passes against the checked-in repo (this run
#       also exercises the REAL mirror tables, since no override is set)
#
# Every fixture carries the minimum .skills/.commands entries the gate requires
# (one `shared` skill dir and the shared one-command `noop` dir, $CMDS).

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$repo_root/scripts/check-token-budget.sh"
[ -f "$GATE" ] || { echo "FAIL: gate not found at $GATE" >&2; exit 1; }

pass=0
fail=0
check() { # check "name" expected_exit actual_exit
  if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "ok   - $1 (exit $3)"; else
    fail=$((fail+1)); echo "FAIL - $1 (expected exit $2, got $3)"; fi
}
contains() { # contains "name" haystack needle
  case "$2" in *"$3"*) pass=$((pass+1)); echo "ok   - $1";; *) fail=$((fail+1)); echo "FAIL - $1 (missing: $3)";; esac
}
contains_line() { # contains_line "name" haystack needle1 needle2 -> ONE line holds both
  # No producer pipes into grep -q (pipefail EPIPE race — test-no-pipefail-grep-q.sh).
  if grep -qF -- "$4" < <(grep -F -- "$3" <<<"$2"); then pass=$((pass+1)); echo "ok   - $1"; else
    fail=$((fail+1)); echo "FAIL - $1 (no single line holds both '$3' and '$4')"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/token-budget-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mk_agent() { # mk_agent <dir> <stem> <skills-block-or-empty> <body-bytes>
  local dir="$1" stem="$2" skills="$3" body_bytes="$4" f
  f="$dir/$stem.md"
  {
    echo "---"
    echo "name: loomwright:$stem"
    echo "tools: Read"
    [ -n "$skills" ] && printf '%s\n' "$skills"
    echo "---"
    echo "# $stem body"
    echo "- a body bullet that must NOT be parsed as a skill"
    # pad the body to a deterministic size
    local i=0
    while [ "$i" -lt "$body_bytes" ]; do printf 'x'; i=$((i+1)); done
    echo
  } > "$f"
}

mk_skill() { # mk_skill <dir> <name> <bytes>
  local dir="$1" name="$2" bytes="$3" i=0
  mkdir -p "$dir/$name"
  { while [ "$i" -lt "$bytes" ]; do printf 'y'; i=$((i+1)); done; echo; } > "$dir/$name/SKILL.md"
}

# Shared one-command commands dir: every fixture needs >= 1 command doc with a
# .commands entry, or the zero-command guard fails it before its own assertion.
CMDS="$TMP/cmds"; mkdir -p "$CMDS"
printf '# noop command doc fixture\n' > "$CMDS/noop.md"
# Minimum .skills/.commands tables for a fixture whose skills dir holds `shared`.
MIN_TABLES='"skills": { "shared": { "budget": 9999, "measured": 0 } }, "commands": { "noop": { "budget": 9999, "measured": 0 } }'

run_gate() { # run_gate <agents> <skills> <json> [contracts-md] [commands-dir]  -> sets OUT, RC
  # 4th arg omitted (or "") => TOKEN_BUDGET_CONTRACTS_MD set EMPTY, which skips the
  # mirror-table check (hermetic fixtures). Pass a fixture path to exercise it.
  # 5th arg omitted => the shared one-command dir $CMDS.
  OUT="$(TOKEN_BUDGET_AGENTS_DIR="$1" TOKEN_BUDGET_SKILLS_DIR="$2" TOKEN_BUDGET_JSON="$3" TOKEN_BUDGET_CONTRACTS_MD="${4-}" TOKEN_BUDGET_COMMANDS_DIR="${5-$CMDS}" bash "$GATE" 2>&1)"
  RC=$?
}

# ---------------------------------------------------------------------------
# Case 1 — PASS: agent (400B) + 1 preloaded skill (400B) => proxy 200, budget 250
# ---------------------------------------------------------------------------
A="$TMP/c1/agents"; S="$TMP/c1/skills"; mkdir -p "$A" "$S"
mk_agent "$A" "alpha" "$(printf 'skills:\n  - shared')" 400
mk_skill "$S" "shared" 400
cat > "$TMP/c1/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "alpha": { "budget": 250, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A" "$S" "$TMP/c1/budgets.json"
check "case1 pass exits 0" 0 "$RC"
contains "case1 shows OK row" "$OUT" "alpha"
contains "case1 status OK" "$OUT" "OK"

# ---------------------------------------------------------------------------
# Case 2 — BREACH: same weight, budget lowered to 100 => breach
# ---------------------------------------------------------------------------
cat > "$TMP/c1/budgets-breach.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "alpha": { "budget": 100, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A" "$S" "$TMP/c1/budgets-breach.json"
check "case2 breach exits 1" 1 "$RC"
contains "case2 shows BREACH row" "$OUT" "BREACH"
contains "case2 breach mentions over-by" "$OUT" "over by"

# ---------------------------------------------------------------------------
# Case 3 — MISSING preloaded SKILL.md (broken frontmatter reference)
# ---------------------------------------------------------------------------
A3="$TMP/c3/agents"; S3="$TMP/c3/skills"; mkdir -p "$A3" "$S3"
mk_skill "$S3" "shared" 400   # minimum skill dir (+ .skills entry) the skill table needs
mk_agent "$A3" "beta" "$(printf 'skills:\n  - ghost')" 400   # skills/ghost/SKILL.md absent
cat > "$TMP/c3/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "beta": { "budget": 9999, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A3" "$S3" "$TMP/c3/budgets.json"
check "case3 missing-skill exits 1" 1 "$RC"
contains "case3 shows ERROR row" "$OUT" "ERROR"
contains "case3 names the missing skill" "$OUT" "ghost"

# ---------------------------------------------------------------------------
# Case 4 — NO budget declared for the agent
# ---------------------------------------------------------------------------
A4="$TMP/c4/agents"; S4="$TMP/c4/skills"; mkdir -p "$A4" "$S4"
mk_skill "$S4" "shared" 400   # minimum skill dir (+ .skills entry) the skill table needs
mk_agent "$A4" "gamma" "" 400
cat > "$TMP/c4/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "someone-else": { "budget": 100, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A4" "$S4" "$TMP/c4/budgets.json"
check "case4 no-budget exits 1" 1 "$RC"
contains "case4 ERROR names no-budget" "$OUT" "no budget declared"

# ---------------------------------------------------------------------------
# Case 4b — NON-INTEGER budget (float / hand-edit typo) must fail CLOSED, not
# fall into the OK branch via an errored -gt test (false green).
# ---------------------------------------------------------------------------
A4B="$TMP/c4b/agents"; S4B="$TMP/c4b/skills"; mkdir -p "$A4B" "$S4B"
mk_skill "$S4B" "shared" 400   # minimum skill dir (+ .skills entry) the skill table needs
mk_agent "$A4B" "delta" "" 400
cat > "$TMP/c4b/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "delta": { "budget": "12.5", "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A4B" "$S4B" "$TMP/c4b/budgets.json"
check "case4b non-integer budget exits 1" 1 "$RC"
contains "case4b ERROR names non-integer" "$OUT" "non-integer budget"

# ---------------------------------------------------------------------------
# Case 5 — FRONTMATTER-BOUNDED: a NO-skills agent must count 0 preloaded skills,
# proving the body `- bullet` is not mistaken for a skill (would 404 otherwise).
# ---------------------------------------------------------------------------
A5="$TMP/c5/agents"; S5="$TMP/c5/skills"; mkdir -p "$A5" "$S5"
mk_skill "$S5" "shared" 400   # minimum skill dir (+ .skills entry) the skill table needs
mk_agent "$A5" "delta" "" 400
cat > "$TMP/c5/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "delta": { "budget": 9999, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A5" "$S5" "$TMP/c5/budgets.json"
check "case5 body-bullet not parsed as skill (exits 0)" 0 "$RC"
contains "case5 reports 0 preloaded skills" "$OUT" "0 preloaded skills"

# ---------------------------------------------------------------------------
# Case 5b — EMPTY agents dir must fail LOUDLY (no false-green 0-agent ratchet)
# ---------------------------------------------------------------------------
A5b="$TMP/c5b/agents"; S5b="$TMP/c5b/skills"; mkdir -p "$A5b" "$S5b"
cat > "$TMP/c5b/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": {} }
JSON
run_gate "$A5b" "$S5b" "$TMP/c5b/budgets.json"
check "case5b empty agents dir exits 1" 1 "$RC"
contains "case5b names the empty dir" "$OUT" "no agent .md files found"

# ---------------------------------------------------------------------------
# Case 5c — INLINE/FLOW-STYLE skills: list must ERROR (would silently under-count)
# ---------------------------------------------------------------------------
A5c="$TMP/c5c/agents"; S5c="$TMP/c5c/skills"; mkdir -p "$A5c" "$S5c"
mk_skill "$S5c" "shared" 400   # minimum skill dir (+ .skills entry) the skill table needs
mk_agent "$A5c" "epsilon" "skills: [shared, other]" 400   # flow style — unsupported
cat > "$TMP/c5c/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "epsilon": { "budget": 9999, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A5c" "$S5c" "$TMP/c5c/budgets.json"
check "case5c inline skills exits 1" 1 "$RC"
contains "case5c ERROR names inline/flow-style" "$OUT" "inline/flow-style"

# ---------------------------------------------------------------------------
# Case 5d — ORPHANED budget entry (no matching agent .md) must ERROR
# ---------------------------------------------------------------------------
A5d="$TMP/c5d/agents"; S5d="$TMP/c5d/skills"; mkdir -p "$A5d" "$S5d"
mk_skill "$S5d" "shared" 400   # minimum skill dir (+ .skills entry) the skill table needs
mk_agent "$A5d" "zeta" "" 400
cat > "$TMP/c5d/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "zeta": { "budget": 9999, "measured": 0 }, "ghost-agent": { "budget": 100, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A5d" "$S5d" "$TMP/c5d/budgets.json"
check "case5d orphaned budget exits 1" 1 "$RC"
contains "case5d ERROR names orphaned" "$OUT" "orphaned budget"

# ---------------------------------------------------------------------------
# Case 5e — `skills:  # trailing comment` opener followed by block items must
# still be counted (both parser + inline-check must agree it is block-form).
# ---------------------------------------------------------------------------
A5e="$TMP/c5e/agents"; S5e="$TMP/c5e/skills"; mkdir -p "$A5e" "$S5e"
mk_agent "$A5e" "eta" "$(printf 'skills:   # preloaded\n  - shared')" 400
mk_skill "$S5e" "shared" 400
cat > "$TMP/c5e/budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "eta": { "budget": 9999, "measured": 0 } }, $MIN_TABLES }
JSON
run_gate "$A5e" "$S5e" "$TMP/c5e/budgets.json"
check "case5e comment-trailing skills opener exits 0" 0 "$RC"
contains "case5e counts the block skill (not 0)" "$OUT" "1 preloaded skills"

# ---------------------------------------------------------------------------
# Case 5f — MIRROR-TABLE SYNC: the ARCHITECTURE_CONTRACTS human mirror must
# match the JSON budgets (machine-synced; drift/missing/ghost rows fail CLOSED).
# Reuses the c1 fixtures (alpha, budget 250).
# ---------------------------------------------------------------------------
# mk_contracts <file> <agent rows...> — the agent table, then the skill and
# command mirror tables under their own `###` sub-headings. Their body rows come
# from SKILL_ROWS / CMD_ROWS (newline-separated; default = the MIN_TABLES entries,
# set EMPTY for a table with no rows).
SKILL_ROWS_DEFAULT='| `shared` | 9999 | 0 |'
CMD_ROWS_DEFAULT='| `noop` | 9999 | 0 |'
mk_contracts() {
  local f="$1"; shift
  { echo "## Prompt Token Budgets"
    echo ""
    echo "| Agent | Budget (proxy tokens) | Measured | Preloaded skills |"
    echo "|---|---|---|---|"
    for r in "$@"; do echo "$r"; done
    echo ""
    echo "### Skill size ceilings"
    echo ""
    echo "| Skill dir | Budget (proxy tokens) | Measured |"
    echo "|---|---|---|"
    [ -z "${SKILL_ROWS-$SKILL_ROWS_DEFAULT}" ] || printf '%s\n' "${SKILL_ROWS-$SKILL_ROWS_DEFAULT}"
    echo ""
    echo "### Command size ceilings"
    echo ""
    echo "| Command doc | Budget (proxy tokens) | Measured |"
    echo "|---|---|---|"
    [ -z "${CMD_ROWS-$CMD_ROWS_DEFAULT}" ] || printf '%s\n' "${CMD_ROWS-$CMD_ROWS_DEFAULT}"
    echo ""
    echo "## Next Section"
  } > "$f"
}

mk_contracts "$TMP/c5f-ok.md"      '| `alpha` | 250 | 200 | 1 |'
run_gate "$A" "$S" "$TMP/c1/budgets.json" "$TMP/c5f-ok.md"
check "case5f matching mirror passes" 0 "$RC"

mk_contracts "$TMP/c5f-drift.md"   '| `alpha` | 999 | 200 | 1 |'
run_gate "$A" "$S" "$TMP/c1/budgets.json" "$TMP/c5f-drift.md"
check "case5f drifted budget cell exits 1" 1 "$RC"
contains "case5f names mirror drift" "$OUT" "mirror drift"

# case5g — the MEASURED column is mirrored too (v15.20.0). A budget RAISE that also
# overwrites the frozen Measured cell previously passed CI silently, leaving a falsified
# historical baseline — the number every future raise argues from. `measured: 0` means NO
# BASELINE RECORDED (a real agent always measures > 0), so those rows are skipped, not compared.
cat > "$TMP/c5g-budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "alpha": { "budget": 250, "measured": 200 } }, $MIN_TABLES }
JSON
mk_contracts "$TMP/c5g-ok.md"       '| `alpha` | 250 | 200 | 1 |'
run_gate "$A" "$S" "$TMP/c5g-budgets.json" "$TMP/c5g-ok.md"
check "case5g matching measured cell passes" 0 "$RC"

mk_contracts "$TMP/c5g-drift.md"    '| `alpha` | 250 | 999 | 1 |'
run_gate "$A" "$S" "$TMP/c5g-budgets.json" "$TMP/c5g-drift.md"
check "case5g drifted MEASURED cell exits 1" 1 "$RC"
contains "case5g names the measured drift" "$OUT" "MEASURED cell"

# a footnote marker on the measured cell must not be read as drift
mk_contracts "$TMP/c5g-footnote.md" '| `alpha` | 250 | 200¹ | 1 |'
run_gate "$A" "$S" "$TMP/c5g-budgets.json" "$TMP/c5g-footnote.md"
check "case5g footnote-marked measured cell still passes" 0 "$RC"

mk_contracts "$TMP/c5f-missing.md" '| `someone-else` | 250 | 200 | 1 |'
run_gate "$A" "$S" "$TMP/c1/budgets.json" "$TMP/c5f-missing.md"
check "case5f missing row exits 1" 1 "$RC"
contains "case5f names missing mirror row" "$OUT" "no row in"
contains "case5f flags the ghost row too" "$OUT" "ghost mirror row"

run_gate "$A" "$S" "$TMP/c1/budgets.json" "$TMP/c5f-does-not-exist.md"
check "case5f missing contracts file exits 1" 1 "$RC"
contains "case5f names missing contracts file" "$OUT" "contracts mirror file not found"

# ---------------------------------------------------------------------------
# Case 7 — SKILL DIR / COMMAND DOC CEILINGS (.skills[<dir>] / .commands[<stem>]).
# One agent (`omega`, no preloads, generous budget) so only the new tables can
# trip. mk_tables writes a fixture JSON from a .skills and a .commands body.
# ---------------------------------------------------------------------------
A7="$TMP/c7/agents"; mkdir -p "$A7"
mk_agent "$A7" "omega" "" 400
mk_tables() { # mk_tables <file> <skills-object-body> <commands-object-body>
  printf '{ "proxy_bytes_per_token": 4, "agents": { "omega": { "budget": 9999, "measured": 0 } }, "skills": { %s }, "commands": { %s } }\n' "$2" "$3" > "$1"
}
NOOP_CMD='"noop": { "budget": 9999, "measured": 0 }'

# 7a — skill-dir BREACH: `big` is 4000B => 1000 proxy, budget 500.
S7a="$TMP/c7a/skills"; mkdir -p "$S7a"
mk_skill "$S7a" "big" 4000
mk_tables "$TMP/c7a.json" '"big": { "budget": 500, "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7a" "$TMP/c7a.json"
check "case7a skill-dir breach exits 1" 1 "$RC"
contains_line "case7a BREACH row names the skill dir" "$OUT" "big" "BREACH"
contains "case7a breach mentions over-by" "$OUT" "over by"
mk_tables "$TMP/c7a-ok.json" '"big": { "budget": 1001, "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7a" "$TMP/c7a-ok.json"
check "case7a skill dir under its ceiling passes" 0 "$RC"

# 7b — RECURSIVE: SKILL.md is 400B (100 proxy) but references/deep.md adds 2000B
# (500 proxy). Only a recursive walk sees 600 > 300; a top-level glob sees 100.
S7b="$TMP/c7b/skills"; mkdir -p "$S7b"
mk_skill "$S7b" "nested" 400
mkdir -p "$S7b/nested/references"
{ i=0; while [ "$i" -lt 2000 ]; do printf 'z'; i=$((i+1)); done; echo; } > "$S7b/nested/references/deep.md"
mk_tables "$TMP/c7b.json" '"nested": { "budget": 300, "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7b" "$TMP/c7b.json"
check "case7b nested *.md pushes the skill over its ceiling (exits 1)" 1 "$RC"
contains_line "case7b BREACH row names the nested skill" "$OUT" "nested" "BREACH"
contains "case7b counts both .md files" "$OUT" "2 .md files"

# 7c — skill dir with NO .skills entry.
S7c="$TMP/c7c/skills"; mkdir -p "$S7c"
mk_skill "$S7c" "shared" 400
mk_skill "$S7c" "extra" 400
mk_tables "$TMP/c7c.json" '"shared": { "budget": 9999, "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7c" "$TMP/c7c.json"
check "case7c skill dir with no entry exits 1" 1 "$RC"
contains_line "case7c ERROR names the missing .skills entry" "$OUT" '.skills["extra"]' "no budget declared"

# 7d — command doc with NO .commands entry.
S7="$TMP/c7/skills"; mkdir -p "$S7"
mk_skill "$S7" "shared" 400
C7d="$TMP/c7d/commands"; mkdir -p "$C7d"
printf '# noop\n' > "$C7d/noop.md"
printf '# extra\n' > "$C7d/extra-cmd.md"
mk_tables "$TMP/c7d.json" '"shared": { "budget": 9999, "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7" "$TMP/c7d.json" "" "$C7d"
check "case7d command doc with no entry exits 1" 1 "$RC"
contains_line "case7d ERROR names the missing .commands entry" "$OUT" '.commands["extra-cmd"]' "no budget declared"

# 7e — ORPHANED .skills entry (no such skill dir).
mk_tables "$TMP/c7e.json" '"shared": { "budget": 9999, "measured": 0 }, "gone": { "budget": 10, "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7" "$TMP/c7e.json"
check "case7e orphaned skill entry exits 1" 1 "$RC"
contains_line "case7e ERROR names the skill orphan" "$OUT" '.skills["gone"]' "orphaned budget"

# 7f — ORPHANED .commands entry (no such command doc).
mk_tables "$TMP/c7f.json" '"shared": { "budget": 9999, "measured": 0 }' "$NOOP_CMD"', "gone-cmd": { "budget": 10, "measured": 0 }'
run_gate "$A7" "$S7" "$TMP/c7f.json"
check "case7f orphaned command entry exits 1" 1 "$RC"
contains_line "case7f ERROR names the command orphan" "$OUT" '.commands["gone-cmd"]' "orphaned budget"

# 7g / 7h — NON-INTEGER skill / command budget must fail CLOSED (never a false green).
mk_tables "$TMP/c7g.json" '"shared": { "budget": "12.5", "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7" "$TMP/c7g.json"
check "case7g non-integer skill budget exits 1" 1 "$RC"
contains_line "case7g ERROR names non-integer skill budget" "$OUT" "shared" "non-integer budget"
mk_tables "$TMP/c7h.json" '"shared": { "budget": 9999, "measured": 0 }' '"noop": { "budget": "lots", "measured": 0 }'
run_gate "$A7" "$S7" "$TMP/c7h.json"
check "case7h non-integer command budget exits 1" 1 "$RC"
contains_line "case7h ERROR names non-integer command budget" "$OUT" "noop" "non-integer budget"

# 7i / 7j — EMPTY or MISSING commands dir (with an empty .commands table, so only
# the zero-command guard can catch it).
mkdir -p "$TMP/c7i/commands"
mk_tables "$TMP/c7i.json" '"shared": { "budget": 9999, "measured": 0 }' ''
run_gate "$A7" "$S7" "$TMP/c7i.json" "" "$TMP/c7i/commands"
check "case7i empty commands dir exits 1" 1 "$RC"
contains "case7i names the empty commands dir" "$OUT" "no command .md files found"
run_gate "$A7" "$S7" "$TMP/c7i.json" "" "$TMP/c7j-no-such-commands-dir"
check "case7j missing commands dir exits 1" 1 "$RC"
contains "case7j names the missing commands dir" "$OUT" "no command .md files found"

# 7k / 7l — EMPTY (loose root files only) or MISSING skills dir, with an empty
# .skills table: only the zero-skill-dir guard can catch it.
mkdir -p "$TMP/c7k/skills"
printf '# index\n' > "$TMP/c7k/skills/SKILLS_INDEX.md"
mk_tables "$TMP/c7k.json" '' "$NOOP_CMD"
run_gate "$A7" "$TMP/c7k/skills" "$TMP/c7k.json"
check "case7k skills dir with no skill dirs exits 1" 1 "$RC"
contains "case7k names the empty skills dir" "$OUT" "no skill dirs found"
run_gate "$A7" "$TMP/c7l-no-such-skills-dir" "$TMP/c7k.json"
check "case7l missing skills dir exits 1" 1 "$RC"
contains "case7l names the missing skills dir" "$OUT" "no skill dirs found"

# 7m — LOOSE root files (SKILLS_INDEX.md, SKILL_TEMPLATE.md) are not skill dirs:
# no entry needed, not measured.
S7m="$TMP/c7m/skills"; mkdir -p "$S7m"
mk_skill "$S7m" "shared" 400
printf '# index\n' > "$S7m/SKILLS_INDEX.md"
printf '# template\n' > "$S7m/SKILL_TEMPLATE.md"
mk_tables "$TMP/c7m.json" '"shared": { "budget": 9999, "measured": 0 }' "$NOOP_CMD"
run_gate "$A7" "$S7m" "$TMP/c7m.json"
check "case7m loose skills-root files need no entry (exits 0)" 0 "$RC"

# ---------------------------------------------------------------------------
# Case 8 — THREE-TABLE MIRROR. Fixture: c1's alpha (250 / 200) and `shared`
# skill (400B => 100 proxy) plus the shared `noop` command (26B => 6 proxy).
# ---------------------------------------------------------------------------
cat > "$TMP/c8.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "alpha": { "budget": 250, "measured": 200 } }, "skills": { "shared": { "budget": 150, "measured": 100 } }, "commands": { "noop": { "budget": 20, "measured": 6 } } }
JSON
AGENT_ROW='| `alpha` | 250 | 200 | 1 |'
OK_SKILL='| `shared` | 150 | 100 |'
OK_CMD='| `noop` | 20 | 6 |'

SKILL_ROWS="$OK_SKILL" CMD_ROWS="$OK_CMD" mk_contracts "$TMP/c8-ok.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-ok.md"
check "case8 valid agents+skills+commands mirror passes together" 0 "$RC"

# skill table: budget drift / measured drift / missing row / ghost row
SKILL_ROWS='| `shared` | 999 | 100 |' CMD_ROWS="$OK_CMD" mk_contracts "$TMP/c8-sdrift.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-sdrift.md"
check "case8 skill budget-cell drift exits 1" 1 "$RC"
contains_line "case8 names the skill mirror drift" "$OUT" "shared" "mirror drift: table budget cell"

SKILL_ROWS='| `shared` | 150 | 999 |' CMD_ROWS="$OK_CMD" mk_contracts "$TMP/c8-smeas.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-smeas.md"
check "case8 skill measured-cell drift exits 1" 1 "$RC"
contains_line "case8 names the skill MEASURED drift" "$OUT" "shared" "MEASURED cell"

SKILL_ROWS='' CMD_ROWS="$OK_CMD" mk_contracts "$TMP/c8-smiss.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-smiss.md"
check "case8 missing skill mirror row exits 1" 1 "$RC"
contains_line "case8 names the missing skill row" "$OUT" "no row in" "Skill size ceilings"

SKILL_ROWS="$OK_SKILL
| \`phantom-skill\` | 1 | 1 |" CMD_ROWS="$OK_CMD" mk_contracts "$TMP/c8-sghost.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-sghost.md"
check "case8 skill ghost row exits 1" 1 "$RC"
contains_line "case8 names the skill ghost row" "$OUT" "phantom-skill" "ghost mirror row"

# command table: budget drift / measured drift / missing row / ghost row
SKILL_ROWS="$OK_SKILL" CMD_ROWS='| `noop` | 999 | 6 |' mk_contracts "$TMP/c8-cdrift.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-cdrift.md"
check "case8 command budget-cell drift exits 1" 1 "$RC"
contains_line "case8 names the command mirror drift" "$OUT" "noop" "mirror drift: table budget cell"

SKILL_ROWS="$OK_SKILL" CMD_ROWS='| `noop` | 20 | 999 |' mk_contracts "$TMP/c8-cmeas.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-cmeas.md"
check "case8 command measured-cell drift exits 1" 1 "$RC"
contains_line "case8 names the command MEASURED drift" "$OUT" "noop" "MEASURED cell"

SKILL_ROWS="$OK_SKILL" CMD_ROWS='' mk_contracts "$TMP/c8-cmiss.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-cmiss.md"
check "case8 missing command mirror row exits 1" 1 "$RC"
contains_line "case8 names the missing command row" "$OUT" "no row in" "Command size ceilings"

SKILL_ROWS="$OK_SKILL" CMD_ROWS="$OK_CMD
| \`phantom-cmd\` | 1 | 1 |" mk_contracts "$TMP/c8-cghost.md" "$AGENT_ROW"
run_gate "$A" "$S" "$TMP/c8.json" "$TMP/c8-cghost.md"
check "case8 command ghost row exits 1" 1 "$RC"
contains_line "case8 names the command ghost row" "$OUT" "phantom-cmd" "ghost mirror row"

# ---------------------------------------------------------------------------
# Case 6 — LIVE REPO: the real gate passes against the checked-in budgets
# ---------------------------------------------------------------------------
OUT="$(bash "$GATE" 2>&1)"; RC=$?
check "case6 live repo passes" 0 "$RC"
contains "case6 live output labels proxy" "$OUT" "proxy"

echo "------------------------------------------------------------------------------"
echo "check-token-budget self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "check-token-budget self-test: OK"
