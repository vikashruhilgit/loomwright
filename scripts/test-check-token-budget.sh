#!/usr/bin/env bash
# test-check-token-budget.sh — self-test for scripts/check-token-budget.sh.
#
# Fully offline, deterministic, macOS bash 3.2 safe. Uses hermetic temp fixture
# dirs (agents/, skills/, budgets.json) via the gate's TOKEN_BUDGET_* env
# overrides — the real repo is never touched. No GNU-only stat/sed/date flags
# (memory: stat-flavor set-u trap; macOS-green != CI-green).
#
# Cases:
#   1. PASS   — agent (+ preloaded skill) under budget -> exit 0
#   2. BREACH — agent over budget -> exit 1 + a readable BREACH row
#   3. MISSING-FRONTMATTER-SKILL — frontmatter names a skill whose SKILL.md is
#      absent -> exit 1 + an ERROR row (broken preload reference)
#   4. NO-BUDGET — agent with no JSON budget entry -> exit 1 + ERROR row
#   5. FRONTMATTER-BOUNDED PARSING — a body `- ` bullet is NOT counted as a skill
#   6. LIVE REPO — the real gate passes against the checked-in repo

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

run_gate() { # run_gate <agents> <skills> <json>  -> sets OUT, RC
  OUT="$(TOKEN_BUDGET_AGENTS_DIR="$1" TOKEN_BUDGET_SKILLS_DIR="$2" TOKEN_BUDGET_JSON="$3" bash "$GATE" 2>&1)"
  RC=$?
}

# ---------------------------------------------------------------------------
# Case 1 — PASS: agent (400B) + 1 preloaded skill (400B) => proxy 200, budget 250
# ---------------------------------------------------------------------------
A="$TMP/c1/agents"; S="$TMP/c1/skills"; mkdir -p "$A" "$S"
mk_agent "$A" "alpha" "$(printf 'skills:\n  - shared')" 400
mk_skill "$S" "shared" 400
cat > "$TMP/c1/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "alpha": { "budget": 250, "measured": 0 } } }
JSON
run_gate "$A" "$S" "$TMP/c1/budgets.json"
check "case1 pass exits 0" 0 "$RC"
contains "case1 shows OK row" "$OUT" "alpha"
contains "case1 status OK" "$OUT" "OK"

# ---------------------------------------------------------------------------
# Case 2 — BREACH: same weight, budget lowered to 100 => breach
# ---------------------------------------------------------------------------
cat > "$TMP/c1/budgets-breach.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "alpha": { "budget": 100, "measured": 0 } } }
JSON
run_gate "$A" "$S" "$TMP/c1/budgets-breach.json"
check "case2 breach exits 1" 1 "$RC"
contains "case2 shows BREACH row" "$OUT" "BREACH"
contains "case2 breach mentions over-by" "$OUT" "over by"

# ---------------------------------------------------------------------------
# Case 3 — MISSING preloaded SKILL.md (broken frontmatter reference)
# ---------------------------------------------------------------------------
A3="$TMP/c3/agents"; S3="$TMP/c3/skills"; mkdir -p "$A3" "$S3"
mk_agent "$A3" "beta" "$(printf 'skills:\n  - ghost')" 400   # skills/ghost/SKILL.md absent
cat > "$TMP/c3/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "beta": { "budget": 9999, "measured": 0 } } }
JSON
run_gate "$A3" "$S3" "$TMP/c3/budgets.json"
check "case3 missing-skill exits 1" 1 "$RC"
contains "case3 shows ERROR row" "$OUT" "ERROR"
contains "case3 names the missing skill" "$OUT" "ghost"

# ---------------------------------------------------------------------------
# Case 4 — NO budget declared for the agent
# ---------------------------------------------------------------------------
A4="$TMP/c4/agents"; S4="$TMP/c4/skills"; mkdir -p "$A4" "$S4"
mk_agent "$A4" "gamma" "" 400
cat > "$TMP/c4/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "someone-else": { "budget": 100, "measured": 0 } } }
JSON
run_gate "$A4" "$S4" "$TMP/c4/budgets.json"
check "case4 no-budget exits 1" 1 "$RC"
contains "case4 ERROR names no-budget" "$OUT" "no budget declared"

# ---------------------------------------------------------------------------
# Case 5 — FRONTMATTER-BOUNDED: a NO-skills agent must count 0 preloaded skills,
# proving the body `- bullet` is not mistaken for a skill (would 404 otherwise).
# ---------------------------------------------------------------------------
A5="$TMP/c5/agents"; S5="$TMP/c5/skills"; mkdir -p "$A5" "$S5"
mk_agent "$A5" "delta" "" 400
cat > "$TMP/c5/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "delta": { "budget": 9999, "measured": 0 } } }
JSON
run_gate "$A5" "$S5" "$TMP/c5/budgets.json"
check "case5 body-bullet not parsed as skill (exits 0)" 0 "$RC"
contains "case5 reports 0 preloaded skills" "$OUT" "0 preloaded skills"

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
