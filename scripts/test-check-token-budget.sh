#!/usr/bin/env bash
# test-check-token-budget.sh — self-test for scripts/check-token-budget.sh.
#
# Fully offline, deterministic, macOS bash 3.2 safe. Uses hermetic temp fixture
# dirs (agents/, skills/, budgets.json) via the gate's TOKEN_BUDGET_* env
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
#   6.  LIVE REPO — the real gate passes against the checked-in repo (this run
#       also exercises the REAL mirror table, since no override is set)

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

run_gate() { # run_gate <agents> <skills> <json> [contracts-md]  -> sets OUT, RC
  # 4th arg omitted => TOKEN_BUDGET_CONTRACTS_MD set EMPTY, which skips the
  # mirror-table check (hermetic fixtures). Pass a fixture path to exercise it.
  OUT="$(TOKEN_BUDGET_AGENTS_DIR="$1" TOKEN_BUDGET_SKILLS_DIR="$2" TOKEN_BUDGET_JSON="$3" TOKEN_BUDGET_CONTRACTS_MD="${4-}" bash "$GATE" 2>&1)"
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
# Case 4b — NON-INTEGER budget (float / hand-edit typo) must fail CLOSED, not
# fall into the OK branch via an errored -gt test (false green).
# ---------------------------------------------------------------------------
A4B="$TMP/c4b/agents"; S4B="$TMP/c4b/skills"; mkdir -p "$A4B" "$S4B"
mk_agent "$A4B" "delta" "" 400
cat > "$TMP/c4b/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "delta": { "budget": "12.5", "measured": 0 } } }
JSON
run_gate "$A4B" "$S4B" "$TMP/c4b/budgets.json"
check "case4b non-integer budget exits 1" 1 "$RC"
contains "case4b ERROR names non-integer" "$OUT" "non-integer budget"

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
mk_agent "$A5c" "epsilon" "skills: [shared, other]" 400   # flow style — unsupported
cat > "$TMP/c5c/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "epsilon": { "budget": 9999, "measured": 0 } } }
JSON
run_gate "$A5c" "$S5c" "$TMP/c5c/budgets.json"
check "case5c inline skills exits 1" 1 "$RC"
contains "case5c ERROR names inline/flow-style" "$OUT" "inline/flow-style"

# ---------------------------------------------------------------------------
# Case 5d — ORPHANED budget entry (no matching agent .md) must ERROR
# ---------------------------------------------------------------------------
A5d="$TMP/c5d/agents"; S5d="$TMP/c5d/skills"; mkdir -p "$A5d" "$S5d"
mk_agent "$A5d" "zeta" "" 400
cat > "$TMP/c5d/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "zeta": { "budget": 9999, "measured": 0 }, "ghost-agent": { "budget": 100, "measured": 0 } } }
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
cat > "$TMP/c5e/budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "eta": { "budget": 9999, "measured": 0 } } }
JSON
run_gate "$A5e" "$S5e" "$TMP/c5e/budgets.json"
check "case5e comment-trailing skills opener exits 0" 0 "$RC"
contains "case5e counts the block skill (not 0)" "$OUT" "1 preloaded skills"

# ---------------------------------------------------------------------------
# Case 5f — MIRROR-TABLE SYNC: the ARCHITECTURE_CONTRACTS human mirror must
# match the JSON budgets (machine-synced; drift/missing/ghost rows fail CLOSED).
# Reuses the c1 fixtures (alpha, budget 250).
# ---------------------------------------------------------------------------
mk_contracts() { # mk_contracts <file> <rows...>
  local f="$1"; shift
  { echo "## Prompt Token Budgets"
    echo ""
    echo "| Agent | Budget (proxy tokens) | Measured | Preloaded skills |"
    echo "|---|---|---|---|"
    for r in "$@"; do echo "$r"; done
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
cat > "$TMP/c5g-budgets.json" <<'JSON'
{ "proxy_bytes_per_token": 4, "agents": { "alpha": { "budget": 250, "measured": 200 } } }
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
# Case 6 — LIVE REPO: the real gate passes against the checked-in budgets
# ---------------------------------------------------------------------------
OUT="$(bash "$GATE" 2>&1)"; RC=$?
check "case6 live repo passes" 0 "$RC"
contains "case6 live output labels proxy" "$OUT" "proxy"

# ---------------------------------------------------------------------------
# Case 7 — MULTI-PLUGIN DISCOVERY (v15.37.0).
#
# These cases run with EVERY TOKEN_BUDGET_* override UNSET, which is the whole
# point: the per-gate overrides are layered ABOVE discovery and return first, so
# a case that sets one proves nothing about the new loop. Only CHECK_MARKETPLACE_JSON
# is set, pointing at a fixture manifest listing TWO plugin sources.
#
# MUTATION CONTROL: delete the `while ... plugin_dirs ...` loop from the gate's
# run_gate() and 7a/7b/7c/7d all fail — 7a because the beta plugin is never
# named, 7b because a malformed second plugin is never seen, 7d because the
# tripwire never fires. (Performed and recorded in the PR.)
# ---------------------------------------------------------------------------

# mk_plugin <root> <name> <mode> — mode: full | no-budget | no-agents | no-mirror
mk_plugin() {
  local root="$1" name="$2" mode="$3" p="$1/$2"
  mkdir -p "$p/skills" "$p/docs"
  if [ "$mode" != "no-agents" ]; then
    mkdir -p "$p/agents"
    mk_agent "$p/agents" "$name-agent" "" 400
  fi
  if [ "$mode" != "no-budget" ]; then
    cat > "$p/docs/prompt-token-budgets.json" <<JSON
{ "proxy_bytes_per_token": 4, "agents": { "$name-agent": { "budget": 9999, "measured": 0 } } }
JSON
  fi
  if [ "$mode" != "no-mirror" ]; then
    {
      echo "## Prompt Token Budgets"
      echo ""
      echo "| Agent | Budget | Measured |"
      echo "|---|---|---|"
      echo "| \`$name-agent\` | 9999 | 0 |"
    } > "$p/docs/ARCHITECTURE_CONTRACTS.md"
  fi
}

# mk_manifest <root> <name>... — writes <root>/.claude-plugin/marketplace.json
mk_manifest() {
  local root="$1"; shift
  mkdir -p "$root/.claude-plugin"
  {
    printf '{ "name": "fixture", "plugins": ['
    local first=1 n
    for n in "$@"; do
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{ "name": "%s", "source": "./%s", "version": "1.0.0" }' "$n" "$n"
    done
    printf '] }\n'
  } > "$root/.claude-plugin/marketplace.json"
}

run_discovery() { # run_discovery <manifest-path> -> sets OUT, RC (all TOKEN_BUDGET_* unset)
  OUT="$(CHECK_MARKETPLACE_JSON="$1" bash "$GATE" 2>&1)"
  RC=$?
}

# mkroot <path> — create and echo the CANONICAL path. The gate resolves plugin
# dirs with `cd ... && pwd`, so a $TMPDIR with a trailing slash (macOS default)
# would make a literal "$TMP/..." substring assertion fail on a doubled slash
# while the gate is behaving correctly. Canonicalize on our side, not theirs.
mkroot() { mkdir -p "$1" && ( cd "$1" && pwd ); }

# --- 7a: two agent-bearing plugins are BOTH budgeted -----------------------
R7A="$(mkroot "$TMP/c7a")"
mk_plugin "$R7A" "alphaplug" full
mk_plugin "$R7A" "betaplug"  full
mk_manifest "$R7A" alphaplug betaplug
run_discovery "$R7A/.claude-plugin/marketplace.json"
check "case7a two-plugin discovery exits 0" 0 "$RC"
contains "case7a budgets plugin #1" "$OUT" "$R7A/alphaplug/agents"
contains "case7a budgets plugin #2 (fails if the discovery loop is deleted)" "$OUT" "$R7A/betaplug/agents"
contains "case7a names the second plugin" "$OUT" "plugin: betaplug"

# --- 7b: FAIL LOUDLY — agents/ present but no prompt-token-budgets.json ----
R7B="$(mkroot "$TMP/c7b")"
mk_plugin "$R7B" "alphaplug" full
mk_plugin "$R7B" "betaplug"  no-budget
mk_manifest "$R7B" alphaplug betaplug
run_discovery "$R7B/.claude-plugin/marketplace.json"
check "case7b agents-without-budgets exits 1 (malformed != absent)" 1 "$RC"
contains "case7b names the missing budget file" "$OUT" "MUST declare its own budgets"

# --- 7c: SKIP SILENTLY — plugin ships no agents/ tree at all ---------------
R7C="$(mkroot "$TMP/c7c")"
mk_plugin "$R7C" "alphaplug" full
mk_plugin "$R7C" "betaplug"  no-agents
mk_manifest "$R7C" alphaplug betaplug
run_discovery "$R7C/.claude-plugin/marketplace.json"
check "case7c agent-less plugin is skipped silently (exit 0)" 0 "$RC"
contains "case7c still budgets the agent-bearing plugin" "$OUT" "$R7C/alphaplug/agents"
case "$OUT" in
  *"plugin: betaplug"*) fail=$((fail+1)); echo "FAIL - case7c must not check the agent-less plugin";;
  *) pass=$((pass+1)); echo "ok   - case7c does not check the agent-less plugin";;
esac

# --- 7d: ANTI-DRIFT TRIPWIRE — zero agent-bearing plugins matched ----------
R7D="$(mkroot "$TMP/c7d")"
mk_plugin "$R7D" "alphaplug" no-agents
mk_plugin "$R7D" "betaplug"  no-agents
mk_manifest "$R7D" alphaplug betaplug
run_discovery "$R7D/.claude-plugin/marketplace.json"
check "case7d zero agent-bearing plugins exits 1 (tripwire)" 1 "$RC"
contains "case7d names the tripwire" "$OUT" "gate matched nothing"

# --- 7e: missing manifest fails CLOSED ------------------------------------
run_discovery "$TMP/c7e-does-not-exist/.claude-plugin/marketplace.json"
check "case7e missing manifest exits 1" 1 "$RC"
contains "case7e names the missing manifest" "$OUT" "marketplace manifest not found"

# --- 7f: per-plugin MIRROR is that plugin's own ARCHITECTURE_CONTRACTS.md ---
R7F="$(mkroot "$TMP/c7f")"
mk_plugin "$R7F" "alphaplug" full
mk_plugin "$R7F" "betaplug"  no-mirror
mk_manifest "$R7F" alphaplug betaplug
run_discovery "$R7F/.claude-plugin/marketplace.json"
check "case7f plugin without its own contracts mirror exits 1" 1 "$RC"
contains "case7f names the missing per-plugin mirror" "$OUT" "$R7F/betaplug/docs/ARCHITECTURE_CONTRACTS.md"

echo "------------------------------------------------------------------------------"
echo "check-token-budget self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "check-token-budget self-test: OK"
