#!/usr/bin/env bash
# test-rules-check.sh — self-tests for rules-check.sh, the SOLE EXECUTION path for the committed
# .agent/rules/ house-rules substrate (Subtask 2 of the rules-enforcement job #3b-ii). Runs the checker
# inside ISOLATED temp git repos via `mktemp -d` + `git init` so it NEVER touches the real .agent/rules/.
# The checker does `git rev-parse --show-toplevel` then cd's there and globs .agent/rules/*.json, so we
# `cd` into each temp repo. Markers proving execution live UNDER the single $ROOT so one trap cleans all.
# Mirrors the test-read-rules.sh harness convention. Exit 0 = all pass, 1 = any failure
# (auto-registered by ci.yml's test-*.sh glob).
#
# Covers cases (a)-(d):
#   (a) GATED — a `must` rule whose check is `touch <MARKER>`:
#         - under --no-cmd                 → MARKER NOT created
#         - under default non-interactive  → MARKER NOT created (needs confirmation)
#         - under BOTH --no-cmd + --confirm → MARKER NOT created (--no-cmd WINS over --confirm)
#   (b) CONFIRMED-EXECUTE (marker-proven) — a `must` rule whose check is `touch <CONFIRMED_MARKER>`:
#         - under --confirm                 → CONFIRMED_MARKER IS created (execution proven by the file)
#         - under RULES_CHECK_CONFIRM=1      → also creates it
#         and the executed check is counted in the aggregate pass/fail summary.
#   (c) SKIPPED KINDS — advisory rules and null-check `must` rules are never run (their side-effecting
#         checks leave no marker even under --confirm).
#   (d) PARSER PARITY with read-rules.sh — duplicate-id (first-seen wins, later dup's check NOT run),
#         malformed / non-array JSON files, and invalid objects (missing field / bad enforcement) are
#         SKIPPED — their checks NEVER execute, even under --confirm.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/rules-check.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# All temp dirs + markers live under ONE root so a single trap reliably cleans everything.
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# Write a *.json rule file under a repo's .agent/rules/. $1 repo  $2 filename  $3 JSON content.
seed_rules_file() {
  local repo="$1" fname="$2" content="$3"
  mkdir -p "$repo/.agent/rules"
  printf '%s' "$content" > "$repo/.agent/rules/$fname"
}

# Run the checker inside a temp repo (cd so --show-toplevel = the temp repo). Extra args forwarded.
# stdin redirected from /dev/null so `[ -t 0 ]` is false (deterministic non-interactive default).
run_checker() { local repo="$1"; shift; ( cd "$repo" && bash "$CHECKER" "$@" </dev/null ); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-rules-check: jq absent on this host — rules-check.sh no-ops. Skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ============================================================================
echo "== (a) GATED — a must-rule check must NOT run under --no-cmd / default / --no-cmd+--confirm =="
RA="$(new_repo)"
MARKER_A="$ROOT/gated_marker_$$"
rm -f "$MARKER_A" 2>/dev/null
seed_rules_file "$RA" "safety.json" "[
  {\"id\":\"a-gated\",\"category\":\"safety\",\"statement\":\"gated check must not run unconfirmed\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_A\",\"provenance\":{\"source\":\"test\"}}
]"

# (a1) --no-cmd → not created
out_a1="$(run_checker "$RA" --no-cmd)"; rc_a1=$?
[ "$rc_a1" -eq 0 ] && ok "(a1 --no-cmd) exits 0" || no "(a1) expected exit 0, got $rc_a1"
[ ! -e "$MARKER_A" ] && ok "(a1) --no-cmd did NOT execute the check (marker absent)" \
  || no "(a1) SECURITY REGRESSION: --no-cmd executed the check (marker created)"
echo "$out_a1" | grep -qF "cmd execution disabled" \
  && ok "(a1) --no-cmd reports 'cmd execution disabled'" || no "(a1) missing 'cmd execution disabled' notice"

# (a2) default non-interactive (no flag) → not created
rm -f "$MARKER_A" 2>/dev/null
out_a2="$(run_checker "$RA")"; rc_a2=$?
[ "$rc_a2" -eq 0 ] && ok "(a2 default) exits 0" || no "(a2) expected exit 0, got $rc_a2"
[ ! -e "$MARKER_A" ] && ok "(a2) default non-interactive did NOT execute the check (marker absent)" \
  || no "(a2) SECURITY REGRESSION: default executed the check without confirmation"
echo "$out_a2" | grep -qF "needs confirmation" \
  && ok "(a2) default reports 'needs confirmation'" || no "(a2) missing 'needs confirmation' notice"

# (a3) --no-cmd + --confirm BOTH → --no-cmd WINS → not created
rm -f "$MARKER_A" 2>/dev/null
out_a3="$(run_checker "$RA" --confirm --no-cmd)"; rc_a3=$?
[ "$rc_a3" -eq 0 ] && ok "(a3 both) exits 0" || no "(a3) expected exit 0, got $rc_a3"
[ ! -e "$MARKER_A" ] && ok "(a3) --no-cmd WINS over --confirm (marker absent)" \
  || no "(a3) SECURITY REGRESSION: --confirm overrode --no-cmd (marker created)"
# also assert order-independence: --confirm before --no-cmd already tested; try reverse order too.
rm -f "$MARKER_A" 2>/dev/null
run_checker "$RA" --no-cmd --confirm >/dev/null 2>&1
[ ! -e "$MARKER_A" ] && ok "(a3b) --no-cmd WINS regardless of arg order (marker absent)" \
  || no "(a3b) SECURITY REGRESSION: arg order let --confirm win over --no-cmd"

# ============================================================================
echo "== (b) CONFIRMED-EXECUTE (marker-proven) — --confirm / RULES_CHECK_CONFIRM=1 actually runs =="
RB="$(new_repo)"
MARKER_B="$ROOT/confirmed_marker_$$"        # DISTINCT path from the gated marker
rm -f "$MARKER_B" 2>/dev/null
seed_rules_file "$RB" "safety.json" "[
  {\"id\":\"b-run\",\"category\":\"safety\",\"statement\":\"confirmed check runs\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_B\",\"provenance\":{\"source\":\"test\"}}
]"

# (b1) --confirm → marker IS created (execution proven by the FILE, not merely by exit code)
out_b1="$(run_checker "$RB" --confirm)"; rc_b1=$?
[ "$rc_b1" -eq 0 ] && ok "(b1 --confirm) exits 0 (check passed)" || no "(b1) expected exit 0, got $rc_b1"
[ -e "$MARKER_B" ] && ok "(b1) --confirm EXECUTED the check (marker CREATED)" \
  || no "(b1) --confirm did not execute the check (marker absent) — execution broken"
echo "$out_b1" | grep -qF "Checks passed: 1/1" \
  && ok "(b1) executed check counted in aggregate (1/1)" || no "(b1) aggregate not 1/1"

# (b2) RULES_CHECK_CONFIRM=1 env → also creates it
MARKER_B2="$ROOT/confirmed_env_marker_$$"
rm -f "$MARKER_B2" 2>/dev/null
RB2="$(new_repo)"
seed_rules_file "$RB2" "safety.json" "[
  {\"id\":\"b2-run\",\"category\":\"safety\",\"statement\":\"env-confirmed check runs\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_B2\",\"provenance\":{\"source\":\"test\"}}
]"
( cd "$RB2" && RULES_CHECK_CONFIRM=1 bash "$CHECKER" </dev/null ) >/dev/null 2>&1; rc_b2=$?
[ "$rc_b2" -eq 0 ] && ok "(b2 env-confirm) exits 0" || no "(b2) expected exit 0, got $rc_b2"
[ -e "$MARKER_B2" ] && ok "(b2) RULES_CHECK_CONFIRM=1 EXECUTED the check (marker CREATED)" \
  || no "(b2) env confirm did not execute the check"

# (b3) a FAILING confirmed check → exit 1, counted as a failure
RB3="$(new_repo)"
seed_rules_file "$RB3" "safety.json" '[
  {"id":"b3-fail","category":"safety","statement":"failing check","enforcement":"must","check":"exit 3","provenance":{"source":"test"}}
]'
out_b3="$(run_checker "$RB3" --confirm)"; rc_b3=$?
[ "$rc_b3" -eq 1 ] && ok "(b3 failing check) exits 1" || no "(b3) expected exit 1, got $rc_b3"
echo "$out_b3" | grep -qF "Checks passed: 0/1" \
  && ok "(b3) failing check reflected in aggregate (0/1)" || no "(b3) aggregate not 0/1"

# ============================================================================
echo "== (c) SKIPPED KINDS — advisory + null-check must-rules are never run =="
RC="$(new_repo)"
MARKER_ADV="$ROOT/adv_marker_$$"
MARKER_NULLONLY="$ROOT/nullonly_marker_$$"   # a null-check must rule can't carry a side effect anyway;
rm -f "$MARKER_ADV" "$MARKER_NULLONLY" 2>/dev/null
# advisory rule WITH a side-effecting check (must be ignored — only `must` rules run);
# null-check must rule (no command to run at all).
seed_rules_file "$RC" "mix.json" "[
  {\"id\":\"c-adv\",\"category\":\"safety\",\"statement\":\"advisory with a check is NOT run\",\"enforcement\":\"advisory\",\"check\":\"touch $MARKER_ADV\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"c-null\",\"category\":\"safety\",\"statement\":\"must rule with null check is skipped\",\"enforcement\":\"must\",\"check\":null,\"provenance\":{\"source\":\"test\"}}
]"
out_c="$(run_checker "$RC" --confirm)"; rc_c=$?
[ "$rc_c" -eq 0 ] && ok "(c) exits 0" || no "(c) expected exit 0, got $rc_c"
[ ! -e "$MARKER_ADV" ] && ok "(c) advisory rule's check NOT executed (marker absent)" \
  || no "(c) REGRESSION: advisory rule's check was executed"
echo "$out_c" | grep -qF "Checks passed: 0/0" \
  && ok "(c) no must+non-null-check rules selected (0/0)" || no "(c) expected 0/0 selected, got: $out_c"

# ============================================================================
echo "== (d) PARSER PARITY — dup id / malformed / invalid objects are SKIPPED, checks never run =="

# (d1) duplicate id: first-seen wins; the LATER duplicate's side-effecting check must NOT run.
RD1="$(new_repo)"
MARKER_DUP_FIRST="$ROOT/dup_first_marker_$$"
MARKER_DUP_SECOND="$ROOT/dup_second_marker_$$"
rm -f "$MARKER_DUP_FIRST" "$MARKER_DUP_SECOND" 2>/dev/null
seed_rules_file "$RD1" "dup.json" "[
  {\"id\":\"dup\",\"category\":\"safety\",\"statement\":\"first-seen wins\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_DUP_FIRST\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"dup\",\"category\":\"safety\",\"statement\":\"later dup dropped\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_DUP_SECOND\",\"provenance\":{\"source\":\"test\"}}
]"
out_d1="$(run_checker "$RD1" --confirm)"; rc_d1=$?
[ "$rc_d1" -eq 0 ] && ok "(d1 dup) exits 0" || no "(d1) expected exit 0, got $rc_d1"
[ -e "$MARKER_DUP_FIRST" ] && ok "(d1) first-seen dup's check ran (marker created)" \
  || no "(d1) first-seen dup's check did not run"
[ ! -e "$MARKER_DUP_SECOND" ] && ok "(d1) later dup's check NOT run (dedup parity)" \
  || no "(d1) REGRESSION: later duplicate-id check was executed"
echo "$out_d1" | grep -qF "Checks passed: 1/1" \
  && ok "(d1) exactly one (deduped) check selected (1/1)" || no "(d1) expected 1/1, got: $out_d1"

# (d2) malformed / non-array JSON file alongside a valid one: malformed is skipped, valid still runs.
RD2="$(new_repo)"
MARKER_D2_GOOD="$ROOT/d2_good_marker_$$"
MARKER_D2_OBJ="$ROOT/d2_obj_marker_$$"       # inside a bare-object (non-array) file → must be skipped
rm -f "$MARKER_D2_GOOD" "$MARKER_D2_OBJ" 2>/dev/null
seed_rules_file "$RD2" "good.json" "[
  {\"id\":\"d2-good\",\"category\":\"safety\",\"statement\":\"valid array survives\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_D2_GOOD\",\"provenance\":{\"source\":\"test\"}}
]"
seed_rules_file "$RD2" "broken.json" '{ not valid json ]['
seed_rules_file "$RD2" "object.json" "{\"id\":\"d2-obj\",\"category\":\"safety\",\"statement\":\"bare object not array\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_D2_OBJ\",\"provenance\":{\"source\":\"test\"}}"
out_d2="$(run_checker "$RD2" --confirm)"; rc_d2=$?
[ "$rc_d2" -eq 0 ] && ok "(d2 malformed sibling) exits 0" || no "(d2) expected exit 0, got $rc_d2"
[ -e "$MARKER_D2_GOOD" ] && ok "(d2) valid array file's check ran despite malformed sibling" \
  || no "(d2) valid file's check did not run"
[ ! -e "$MARKER_D2_OBJ" ] && ok "(d2) non-array (bare object) file SKIPPED — its check not run" \
  || no "(d2) REGRESSION: non-array file's check was executed"

# (d3) invalid objects (missing required field / bad enforcement) skipped; valid sibling runs.
RD3="$(new_repo)"
MARKER_D3_BADENF="$ROOT/d3_badenf_marker_$$"
MARKER_D3_MISSING="$ROOT/d3_missing_marker_$$"
MARKER_D3_GOOD="$ROOT/d3_good_marker_$$"
rm -f "$MARKER_D3_BADENF" "$MARKER_D3_MISSING" "$MARKER_D3_GOOD" 2>/dev/null
seed_rules_file "$RD3" "g.json" "[
  {\"id\":\"d3-badenf\",\"category\":\"safety\",\"statement\":\"unknown enforcement\",\"enforcement\":\"mandatory\",\"check\":\"touch $MARKER_D3_BADENF\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"d3-missing\",\"category\":\"safety\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_D3_MISSING\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"d3-good\",\"category\":\"safety\",\"statement\":\"valid must survives\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_D3_GOOD\",\"provenance\":{\"source\":\"test\"}}
]"
out_d3="$(run_checker "$RD3" --confirm)"; rc_d3=$?
[ "$rc_d3" -eq 0 ] && ok "(d3 invalid objects) exits 0" || no "(d3) expected exit 0, got $rc_d3"
[ ! -e "$MARKER_D3_BADENF" ] && ok "(d3) bad-enforcement object SKIPPED — check not run" \
  || no "(d3) REGRESSION: bad-enforcement object's check ran"
[ ! -e "$MARKER_D3_MISSING" ] && ok "(d3) missing-statement object SKIPPED — check not run" \
  || no "(d3) REGRESSION: missing-field object's check ran"
[ -e "$MARKER_D3_GOOD" ] && ok "(d3) valid must-rule sibling's check ran" \
  || no "(d3) valid must-rule sibling's check did not run"
echo "$out_d3" | grep -qF "Checks passed: 1/1" \
  && ok "(d3) exactly the one valid must-rule selected (1/1)" || no "(d3) expected 1/1, got: $out_d3"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
