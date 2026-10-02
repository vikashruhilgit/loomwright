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
#   (f) REPO-WIDE AUDIT vs the reader's PATH ROUTING — a rule whose `applies_to` routes it OUT of the
#         reader's advisory emission for a given path set is STILL selected and executed here (the
#         premise is proven first, so the assertion cannot be vacuous), and a stray path argument is
#         warned-and-ignored rather than narrowing the audit. Routing is an emission filter; /rules
#         check is a repo-wide audit — see rules-check.sh's header near the parity comment.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
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

# FAKE_HOME — every (a)-(f) case below runs the checker with HOME overridden to an isolated temp dir,
# so rules-check.sh's new user-scope stamp read/write (STAMP_REL below, resolved under $HOME)
# NEVER touches the real developer's home directory during a test run. The (g)-(j) stamp-specific
# cases below use their OWN per-case HOME dirs (mirroring test-resolve-egress-config.sh's convention)
# so each can control exactly what stamp state it starts from.
# STAMP_REL — the stamp's path RELATIVE to $HOME, spelled out ONCE here (it must match rules-check.sh's
# own RULES_CHECK_STAMP_FILE); every per-case stamp path below is derived from it.
STAMP_REL=".claude/loomwright/rules-check-stamp.json"
FAKE_HOME="$ROOT/home"
mkdir -p "$FAKE_HOME"

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
# HOME is always overridden (FAKE_HOME by default) so no case here can touch the real user scope.
run_checker() { local repo="$1"; shift; ( cd "$repo" && HOME="$FAKE_HOME" bash "$CHECKER" "$@" </dev/null ); }

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
grep -qF "cmd execution disabled" < <(echo "$out_a1") \
  && ok "(a1) --no-cmd reports 'cmd execution disabled'" || no "(a1) missing 'cmd execution disabled' notice"

# (a2) default non-interactive (no flag) → not created
rm -f "$MARKER_A" 2>/dev/null
out_a2="$(run_checker "$RA")"; rc_a2=$?
[ "$rc_a2" -eq 0 ] && ok "(a2 default) exits 0" || no "(a2) expected exit 0, got $rc_a2"
[ ! -e "$MARKER_A" ] && ok "(a2) default non-interactive did NOT execute the check (marker absent)" \
  || no "(a2) SECURITY REGRESSION: default executed the check without confirmation"
grep -qF "needs confirmation" < <(echo "$out_a2") \
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
grep -qF "Checks passed: 1/1" < <(echo "$out_b1") \
  && ok "(b1) executed check counted in aggregate (1/1)" || no "(b1) aggregate not 1/1"

# (b2) RULES_CHECK_CONFIRM=1 env → also creates it
MARKER_B2="$ROOT/confirmed_env_marker_$$"
rm -f "$MARKER_B2" 2>/dev/null
RB2="$(new_repo)"
seed_rules_file "$RB2" "safety.json" "[
  {\"id\":\"b2-run\",\"category\":\"safety\",\"statement\":\"env-confirmed check runs\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_B2\",\"provenance\":{\"source\":\"test\"}}
]"
( cd "$RB2" && HOME="$FAKE_HOME" RULES_CHECK_CONFIRM=1 bash "$CHECKER" </dev/null ) >/dev/null 2>&1; rc_b2=$?
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
grep -qF "Checks passed: 0/1" < <(echo "$out_b3") \
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
grep -qF "Checks passed: 0/0" < <(echo "$out_c") \
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
grep -qF "Checks passed: 1/1" < <(echo "$out_d1") \
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
grep -qF "Checks passed: 1/1" < <(echo "$out_d3") \
  && ok "(d3) exactly the one valid must-rule selected (1/1)" || no "(d3) expected 1/1, got: $out_d3"

# ============================================================================
echo "== (e) unknown arg WARNS on stderr (fail-safe) and does NOT change the gate =="
# A typo'd safety flag (e.g. --no-cmnd for --no-cmd) must be a LOUD no-op, not silent —
# else combined with --confirm/TTY the checks would execute against the caller's intent.
RE="$(new_repo)"
MARKER_E="$ROOT/e_unknownarg_marker_$$"
rm -f "$MARKER_E" 2>/dev/null
seed_rules_file "$RE" "e.json" "[
  {\"id\":\"e-run\",\"category\":\"safety\",\"statement\":\"unknown arg must not silently drop the gate\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_E\",\"provenance\":{\"source\":\"test\"}}
]"
# (e1) a typo'd --no-cmd (`--no-cmnd`) is NOT honored as --no-cmd, but ALSO must not silently
#      execute: with no valid confirmation it stays in the default need-confirm skip. Capture stderr.
err_e1="$( cd "$RE" && HOME="$FAKE_HOME" bash "$CHECKER" --no-cmnd </dev/null 2>&1 >/dev/null )"; rc_e1=$?
[ "$rc_e1" -eq 0 ] && ok "(e1) unknown arg still exits 0 (fail-safe)" || no "(e1) expected exit 0, got $rc_e1"
grep -qF -- "--no-cmnd" < <(printf '%s\n' "$err_e1") \
  && ok "(e1) unknown arg produces a stderr warning naming it" \
  || no "(e1) expected a stderr warning naming --no-cmnd, got: $err_e1"
[ ! -e "$MARKER_E" ] && ok "(e1) typo'd flag left the default skip in place — check NOT executed" \
  || no "(e1) REGRESSION: a typo'd flag let the check execute unconfirmed"
# (e2) the warning does not perturb a legitimate gate: unknown arg + --no-cmd still SKIPS execution.
rm -f "$MARKER_E" 2>/dev/null
run_checker "$RE" --frobnicate --no-cmd >/dev/null 2>&1
[ ! -e "$MARKER_E" ] && ok "(e2) unknown arg alongside --no-cmd preserves the --no-cmd skip" \
  || no "(e2) REGRESSION: unknown arg defeated --no-cmd"

# ============================================================================
echo "== (f) REPO-WIDE AUDIT — a rule ROUTED OUT of the reader is STILL selected by the checker =="
# `applies_to` path routing is an EMISSION FILTER for advisory injection; `/rules check` is a
# repo-wide AUDIT. Different axes: a rule the reader routes out of some worker's advisory block has
# not stopped being true. This checker takes NO path scope at all, so routing has no input here — and
# that is a DECISION, documented in rules-check.sh's header near the parity comment. This case pins it
# both ways so a future "make the checker follow routing" change cannot land silently.
RF="$(new_repo)"
MARKER_F="$ROOT/f_routed_out_marker_$$"
rm -f "$MARKER_F" 2>/dev/null
seed_rules_file "$RF" "f.json" "[
  {\"id\":\"f-scoped\",\"category\":\"safety\",\"statement\":\"Scoped to src, still audited repo-wide\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_F\",\"provenance\":{\"source\":\"test\"},\"applies_to\":[\"src/*\"]}
]"
# (f1) PREMISE — prove the rule really IS routed out by the reader for an unrelated path set. Without
#      this the (f2) assertion could pass simply because routing does nothing (a vacuous test).
READER_F="$SCRIPT_DIR/read-rules.sh"
if [ -r "$READER_F" ]; then
  routed_out="$( cd "$RF" && bash "$READER_F" docs/readme.md 2>/dev/null )"
  routed_in="$( cd "$RF" && bash "$READER_F" src/main.ts 2>/dev/null )"
  if ! grep -qF "Scoped to src, still audited repo-wide" < <(printf '%s\n' "$routed_out") \
     && grep -qF -- "- [MUST] Scoped to src, still audited repo-wide" < <(printf '%s\n' "$routed_in"); then
    ok "(f1 premise) the reader DOES route this rule out for an unrelated path set (premise is real)"
  else
    no "(f1 premise) the reader did not route the rule out — (f2) would be vacuous. out:[$routed_out]"
  fi
else
  no "(f1 premise) read-rules.sh not readable at $READER_F — cannot establish the premise"
fi
# (f2) THE ASSERTION — the checker still SELECTS and RUNS it under --confirm (marker-proven).
run_checker "$RF" --confirm >/dev/null 2>&1
[ -e "$MARKER_F" ] \
  && ok "(f2) a routed-out rule is STILL selected + executed by the repo-wide checker (marker created)" \
  || no "(f2) REGRESSION: the checker skipped a rule merely because applies_to would route it out"
# (f3) ...and the checker still takes NO path scope: passing one is warned-and-ignored, never a filter.
rm -f "$MARKER_F" 2>/dev/null
err_f3="$( cd "$RF" && HOME="$FAKE_HOME" bash "$CHECKER" docs/readme.md --confirm </dev/null 2>&1 >/dev/null )"; rc_f3=$?
[ "$rc_f3" -eq 0 ] && ok "(f3) a stray path argument still exits 0 (fail-safe)" \
                   || no "(f3) expected exit 0 with a stray path arg, got $rc_f3"
grep -qF -- "docs/readme.md" < <(printf '%s\n' "$err_f3") \
  && ok "(f3) a path argument is WARNED-and-ignored (the checker accepts no path scope)" \
  || no "(f3) expected a stderr warning naming the ignored path arg, got: $err_f3"
[ -e "$MARKER_F" ] \
  && ok "(f3) the stray path arg did NOT narrow the audit — the check still ran" \
  || no "(f3) a stray path arg silently narrowed the audit"

# ---------------------------------------------------------------------------
# sha256 helper for the STAMP cases below — mirrors rules-check.sh's OWN fallback chain
# (shasum -a 256 -> sha256sum -> openssl dgst), but kept SEPARATE (never sourcing the script) so
# these assertions are an INDEPENDENT recomputation, not an echo of the script's own output.
# ---------------------------------------------------------------------------
_t_sha256_file() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}'
  fi
}

# ============================================================================
echo "== (g) STAMP WRITE on --confirm — user-scope file, hash matches an INDEPENDENT computation =="
# ============================================================================
RG="$(new_repo)"
HG="$ROOT/home_g"; mkdir -p "$HG"
MARKER_G1="$ROOT/g1_marker_$$"; MARKER_G2="$ROOT/g2_marker_$$"; MARKER_G_ADV="$ROOT/g_adv_marker_$$"
rm -f "$MARKER_G1" "$MARKER_G2" "$MARKER_G_ADV" 2>/dev/null
seed_rules_file "$RG" "g.json" "[
  {\"id\":\"g-one\",\"category\":\"safety\",\"statement\":\"first\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_G1\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"g-two\",\"category\":\"safety\",\"statement\":\"second\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_G2\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"g-adv\",\"category\":\"safety\",\"statement\":\"advisory excluded\",\"enforcement\":\"advisory\",\"check\":\"touch $MARKER_G_ADV\",\"provenance\":{\"source\":\"test\"}}
]"
STAMP_FILE_G="$HG/$STAMP_REL"
[ ! -e "$STAMP_FILE_G" ] && ok "(g0) no stamp file exists before the run" \
  || no "(g0) stamp file already exists — fixture contaminated"
out_g="$( cd "$RG" && HOME="$HG" bash "$CHECKER" --confirm </dev/null )"; rc_g=$?
[ "$rc_g" -eq 0 ] && ok "(g1) --confirm run exits 0" || no "(g1) expected exit 0, got $rc_g"
[ -f "$STAMP_FILE_G" ] && ok "(g2) the stamp file was WRITTEN to user scope ($STAMP_FILE_G)" \
  || no "(g2) no stamp file written at $STAMP_FILE_G"
[ -e "$MARKER_G1" ] && [ -e "$MARKER_G2" ] \
  && ok "(g2b) both must-rule checks actually ran under --confirm" \
  || no "(g2b) expected both markers created"
[ ! -e "$MARKER_G_ADV" ] && ok "(g2c) the advisory rule's check was NOT run (excluded from the set)" \
  || no "(g2c) REGRESSION: advisory rule's check ran"
# The stamp is keyed by the PHYSICAL git-common-dir (PR #267 Phase 4.5 finding 5), resolved here
# the same way rules-check.sh resolves it (`cd <git-common-dir> && pwd -P` — physical, because on
# macOS mktemp's /var/folders/... is a symlink to /private/var/folders/...).
REPO_G="$(cd "$RG" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
stamped_hash_g="$(jq -r --arg rr "$REPO_G" '.[$rr].hash // "MISSING"' "$STAMP_FILE_G" 2>/dev/null)"
[ "$stamped_hash_g" != "MISSING" ] && [ -n "$stamped_hash_g" ] \
  && ok "(g3) the stamp record carries a non-empty hash keyed by this repository's physical git-common-dir" \
  || no "(g3) no hash recorded for key $REPO_G: $(cat "$STAMP_FILE_G" 2>/dev/null)"
# INDEPENDENT recomputation — jq+sha256 in THIS test, never the script's own code path. Only
# g-one/g-two are must-rules with non-null checks; g-adv (advisory) must be excluded from the set.
TMP_G="$ROOT/g_hash_input"
jq -nr --arg id1 "g-one" --arg c1 "touch $MARKER_G1" --arg id2 "g-two" --arg c2 "touch $MARKER_G2" \
  '[{id:$id1,check:$c1},{id:$id2,check:$c2}] | .[] | [.id, .check] | @tsv' \
  | env LC_ALL=C sort > "$TMP_G"
expected_hash_g="$(_t_sha256_file "$TMP_G")"
[ -n "$expected_hash_g" ] && [ "$expected_hash_g" = "$stamped_hash_g" ] \
  && ok "(g4) the written stamp's hash MATCHES an independently jq+sha256-computed hash of the sorted id/check set — not just echoing the script's own output back at itself" \
  || no "(g4) hash mismatch: written=$stamped_hash_g independent=$expected_hash_g"

# ============================================================================
echo "== (h) --if-stamped REPLAYS a valid stamp with NO PROMPT — same output shape as --confirm =="
# ============================================================================
out_h="$( cd "$RG" && HOME="$HG" bash "$CHECKER" --if-stamped </dev/null )"; rc_h=$?
[ "$rc_h" -eq 0 ] && ok "(h1) --if-stamped exits 0 (both stamped checks pass again)" \
  || no "(h1) expected exit 0, got $rc_h"
grep -qF "Checks passed: 2/2" < <(printf '%s\n' "$out_h") \
  && ok "(h2) --if-stamped ran without a prompt and reported n/m with n/m > 0/0 (2/2)" \
  || no "(h2) expected 'Checks passed: 2/2', got: $out_h"
grep -qE '^  \[RUN \]' < <(printf '%s\n' "$out_h") \
  && ok "(h3) the output shape matches --confirm ([RUN] lines present, no prompt)" \
  || no "(h3) expected [RUN] lines in --if-stamped output, got: $out_h"

# ============================================================================
echo "== (i) editing ONE byte after stamping ⇒ --if-stamped reports [SKIP] all (unstamped) =="
# ============================================================================
seed_rules_file "$RG" "g.json" "[
  {\"id\":\"g-one\",\"category\":\"safety\",\"statement\":\"first\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_G1 \",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"g-two\",\"category\":\"safety\",\"statement\":\"second\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_G2\",\"provenance\":{\"source\":\"test\"}}
]"
out_i="$( cd "$RG" && HOME="$HG" bash "$CHECKER" --if-stamped </dev/null )"; rc_i=$?
[ "$rc_i" -eq 0 ] && ok "(i1) --if-stamped after a byte-edited check still exits 0" \
  || no "(i1) expected exit 0, got $rc_i"
grep -qF "[SKIP] all (unstamped)" < <(printf '%s\n' "$out_i") \
  && ok "(i2) a single-byte edit invalidates the stamp — '[SKIP] all (unstamped)'" \
  || no "(i2) expected '[SKIP] all (unstamped)', got: $out_i"
grep -qF "Checks passed: 0/0" < <(printf '%s\n' "$out_i") \
  && ok "(i3) unstamped reports Checks passed: 0/0" || no "(i3) expected 'Checks passed: 0/0', got: $out_i"

# --no-cmd + --if-stamped together: cmd-disabled WINS regardless of stamp validity. Restore the
# originally-stamped content first so the stamp WOULD be valid, to prove --no-cmd still wins over it.
seed_rules_file "$RG" "g.json" "[
  {\"id\":\"g-one\",\"category\":\"safety\",\"statement\":\"first\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_G1\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"g-two\",\"category\":\"safety\",\"statement\":\"second\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_G2\",\"provenance\":{\"source\":\"test\"}}
]"
out_i2="$( cd "$RG" && HOME="$HG" bash "$CHECKER" --no-cmd --if-stamped </dev/null )"; rc_i2=$?
[ "$rc_i2" -eq 0 ] && ok "(i4) --no-cmd --if-stamped exits 0" || no "(i4) expected exit 0, got $rc_i2"
grep -qF "cmd execution disabled" < <(printf '%s\n' "$out_i2") \
  && ok "(i5) --no-cmd --if-stamped together -> 'cmd execution disabled' WINS regardless of stamp validity (the stamp here is VALID again — restored above — yet --no-cmd still blocks)" \
  || no "(i5) expected 'cmd execution disabled', got: $out_i2"

# ============================================================================
echo "== (j) git status --porcelain shows NO new/modified file after a --confirm stamp-writing run =="
# ============================================================================
RJ="$(new_repo)"
HJ="$ROOT/home_j"; mkdir -p "$HJ"
MARKER_J="$ROOT/j_marker_$$"; rm -f "$MARKER_J" 2>/dev/null
seed_rules_file "$RJ" "j.json" "[
  {\"id\":\"j-one\",\"category\":\"safety\",\"statement\":\"j\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_J\",\"provenance\":{\"source\":\"test\"}}
]"
( cd "$RJ" && git add .agent/rules/j.json && git commit -qm "seed rule" ) >/dev/null 2>&1
before_status="$( cd "$RJ" && git status --porcelain )"
[ -z "$before_status" ] && ok "(j0) the repo is CLEAN before the run (premise for the porcelain assertion)" \
  || no "(j0) repo not clean before the run — fixture contaminated: $before_status"
( cd "$RJ" && HOME="$HJ" bash "$CHECKER" --confirm </dev/null ) >/dev/null 2>&1
after_status="$( cd "$RJ" && git status --porcelain )"
[ -z "$after_status" ] \
  && ok "(j1) git status --porcelain is EMPTY after a --confirm stamp-writing run — the stamp genuinely never lands under the repo root (the load-bearing security property of the whole design)" \
  || no "(j1) SECURITY REGRESSION: git status is dirty after --confirm: $after_status"
[ -f "$HJ/$STAMP_REL" ] \
  && ok "(j2) …while the stamp WAS written, just to user scope outside the repo — (j1) is not vacuous" \
  || no "(j2) the stamp was not written at all — (j1) would be vacuous without this"

# ============================================================================
echo "== (k) MUTATION CONTROL — deleting the hash-comparison line breaks (i2)/(i3) =="
# ============================================================================
MUT_K="$ROOT/mut-rules-check.sh"
sed 's/if \[ -n "\$_rc_stamped_hash" \] && \[ "\$_rc_stamped_hash" = "\$LIVE_HASH" \]; then/if true; then/' \
  "$CHECKER" > "$MUT_K"
if ! cmp -s "$CHECKER" "$MUT_K" && grep -qF 'if true; then' "$MUT_K" && bash -n "$MUT_K" 2>/dev/null; then
  RK="$(new_repo)"
  HK="$ROOT/home_k"; mkdir -p "$HK"
  MARKER_K="$ROOT/k_marker_$$"; rm -f "$MARKER_K" 2>/dev/null
  seed_rules_file "$RK" "k.json" "[
    {\"id\":\"k-one\",\"category\":\"safety\",\"statement\":\"k\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_K\",\"provenance\":{\"source\":\"test\"}}
  ]"
  # Stamp with the ORIGINAL (unmutated) checker, so the stamp itself is genuine.
  ( cd "$RK" && HOME="$HK" bash "$CHECKER" --confirm </dev/null ) >/dev/null 2>&1
  rm -f "$MARKER_K" 2>/dev/null
  # Invalidate the stamp with a one-byte edit, then rerun --if-stamped under the MUTANT checker.
  seed_rules_file "$RK" "k.json" "[
    {\"id\":\"k-one\",\"category\":\"safety\",\"statement\":\"k\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_K \",\"provenance\":{\"source\":\"test\"}}
  ]"
  out_k="$( cd "$RK" && HOME="$HK" bash "$MUT_K" --if-stamped </dev/null )"; rc_k=$?
  if [ -e "$MARKER_K" ] && grep -qF "Checks passed: 1/1" < <(printf '%s\n' "$out_k"); then
    ok "(k) CONFIRMED: with the hash-comparison line removed, a byte-edited (genuinely unstamped) check set is incorrectly treated as stamped and RUNS — the comparison is load-bearing, not vacuous"
  else
    no "(k) REFUTED: the mutant still correctly reported unstamped — (i2)/(i3) may be vacuous. out: $out_k"
  fi
else
  no "(k) the hash-comparison mutation did not land cleanly"
fi

# ============================================================================
echo "== (l) ANTI-LAUNDERING — RULES_CHECK_CONFIRM=1 + --if-stamped with NO stamp runs nothing, writes nothing =="
# ============================================================================
# PR #267 Phase 4.5 finding 1. Old code: the env confirm beat --if-stamped, so this ran every
# must-check with no stamp at all AND wrote the stamp — laundering the set into "confirmed".
RL="$(new_repo)"
HL="$ROOT/home_l"; mkdir -p "$HL"
MARKER_L="$ROOT/l_marker_$$"; rm -f "$MARKER_L" 2>/dev/null
seed_rules_file "$RL" "l.json" "[
  {\"id\":\"l-one\",\"category\":\"safety\",\"statement\":\"l\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_L\",\"provenance\":{\"source\":\"test\"}}
]"
out_l="$( cd "$RL" && HOME="$HL" RULES_CHECK_CONFIRM=1 bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"; rc_l=$?
[ "$rc_l" -eq 0 ] && ok "(l1) exits 0" || no "(l1) expected exit 0, got $rc_l"
grep -qF "[SKIP] all (unstamped)" < <(printf '%s\n' "$out_l") \
  && ok "(l2) env confirm + --if-stamped with no stamp reports '[SKIP] all (unstamped)' — the env var does not count under --if-stamped" \
  || no "(l2) expected '[SKIP] all (unstamped)', got: $out_l"
[ ! -e "$MARKER_L" ] && ok "(l3) the must-check did NOT run (no marker)" \
  || no "(l3) SECURITY REGRESSION: env confirm laundered an unstamped --if-stamped run into execution"
[ ! -e "$HL/$STAMP_REL" ] && ok "(l4) NO stamp file was written — the unconfirmed set was not laundered into a stamp" \
  || no "(l4) SECURITY REGRESSION: a stamp was written: $(cat "$HL/$STAMP_REL" 2>/dev/null)"
# (l5) the env confirm still works WITHOUT --if-stamped (b2's behaviour is not collateral damage),
# and an explicit ARGV --confirm alongside --if-stamped still confirms.
( cd "$RL" && HOME="$HL" bash "$CHECKER" --if-stamped --confirm </dev/null ) >/dev/null 2>&1
[ -e "$MARKER_L" ] && [ -f "$HL/$STAMP_REL" ] \
  && ok "(l5) an explicit ARGV --confirm alongside --if-stamped still confirms (runs + stamps)" \
  || no "(l5) argv --confirm with --if-stamped did not confirm"

# ============================================================================
echo "== (m) --if-stamped under a pseudo-TTY NEVER prompts =="
# ============================================================================
# PR #267 Phase 4.5 finding 7. Old code evaluated the TTY branch BEFORE --if-stamped, so on a
# terminal an unattended replay prompted. `script` allocates a pty; BSD and util-linux differ in
# syntax, so probe each and skip gracefully when neither works.
RM="$(new_repo)"
HM="$ROOT/home_m"; mkdir -p "$HM"
MARKER_M="$ROOT/m_marker_$$"; rm -f "$MARKER_M" 2>/dev/null
seed_rules_file "$RM" "m.json" "[
  {\"id\":\"m-one\",\"category\":\"safety\",\"statement\":\"m\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_M\",\"provenance\":{\"source\":\"test\"}}
]"
M_RUNNER="$ROOT/m_runner.sh"
printf 'cd %q && [ -t 0 ] && [ -t 1 ] && echo PTY_OK; HOME=%q bash %q --if-stamped 2>&1\n' "$RM" "$HM" "$CHECKER" > "$M_RUNNER"
out_m=""
if command -v script >/dev/null 2>&1; then
  out_m="$(script -q /dev/null bash "$M_RUNNER" </dev/null 2>/dev/null)"
  case "$out_m" in *PTY_OK*) : ;; *) out_m="$(script -q -c "bash $M_RUNNER" /dev/null </dev/null 2>/dev/null)" ;; esac
fi
case "$out_m" in
  *PTY_OK*)
    case "$out_m" in
      *"check commands from"*) no "(m1) --if-stamped PROMPTED on a TTY: $out_m" ;;
      *) ok "(m1) --if-stamped on a pseudo-TTY does not prompt" ;;
    esac
    case "$out_m" in
      *"[SKIP] all (unstamped)"*) ok "(m2) …and resolves to '[SKIP] all (unstamped)' with no stamp" ;;
      *) no "(m2) expected '[SKIP] all (unstamped)' under a pty, got: $out_m" ;;
    esac
    [ ! -e "$MARKER_M" ] && ok "(m3) …and nothing ran" || no "(m3) a check ran under a pty --if-stamped"
    ;;
  *) echo "  skip: (m) no usable \`script\` pseudo-TTY on this host — case skipped" ;;
esac

# ============================================================================
echo "== (n) the stamp is per REPOSITORY: --confirm in the main checkout ⇒ --if-stamped replays in a linked worktree =="
# ============================================================================
# PR #267 Phase 4.5 finding 5. Old code keyed by --show-toplevel, so every linked worktree (what
# /automate runs in) was a different key and always replayed `unstamped`.
RN="$(new_repo)"
HN="$ROOT/home_n"; mkdir -p "$HN"
seed_rules_file "$RN" "n.json" "[
  {\"id\":\"n-one\",\"category\":\"safety\",\"statement\":\"n\",\"enforcement\":\"must\",\"check\":\"true\",\"provenance\":{\"source\":\"test\"}}
]"
( cd "$RN" && git add .agent/rules/n.json && git commit -qm "seed rule" ) >/dev/null 2>&1
( cd "$RN" && HOME="$HN" bash "$CHECKER" --confirm </dev/null ) >/dev/null 2>&1
WT_N="$ROOT/wt_n_$$"
( cd "$RN" && git worktree add -q "$WT_N" >/dev/null 2>&1 )
if [ -f "$WT_N/.agent/rules/n.json" ]; then
  out_n="$( cd "$WT_N" && HOME="$HN" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
  grep -qF "Checks passed: 1/1" < <(printf '%s\n' "$out_n") \
    && ok "(n1) a set confirmed in the main checkout replays stamped (1/1) in a linked worktree of the same repository" \
    || no "(n1) expected 'Checks passed: 1/1' in the linked worktree, got: $out_n"
  wt_status="$( cd "$WT_N" && git status --porcelain )"
  main_status="$( cd "$RN" && git status --porcelain )"
  [ -z "$wt_status" ] && [ -z "$main_status" ] \
    && ok "(n2) git status --porcelain is EMPTY in both checkouts — the stamp never lands in the repo" \
    || no "(n2) a checkout went dirty: wt=[$wt_status] main=[$main_status]"
  # (n3) a SEPARATE clone (its own .git) is a different key and stays unstamped.
  CL_N="$ROOT/clone_n_$$"
  git clone -q "$RN" "$CL_N" >/dev/null 2>&1
  out_n3="$( cd "$CL_N" && HOME="$HN" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
  grep -qF "[SKIP] all (unstamped)" < <(printf '%s\n' "$out_n3") \
    && ok "(n3) a separate clone of the same content stays unstamped (its own git-common-dir)" \
    || no "(n3) a separate clone replayed the other clone's stamp: $out_n3"
else
  no "(n0) git worktree add failed — case could not run"
fi

# ============================================================================
echo "== (o) a stdin-reading check cannot swallow the loop's remaining records =="
# ============================================================================
# PR #267 Phase 4.5 finding 9. Old code ran `bash -c "$check"` with the loop's record stream as
# stdin, so a `cat` check consumed the remaining records and the run silently shrank.
RO="$(new_repo)"
HO="$ROOT/home_o"; mkdir -p "$HO"
MARKER_OA="$ROOT/oa_marker_$$"; MARKER_OB="$ROOT/ob_marker_$$"; rm -f "$MARKER_OA" "$MARKER_OB" 2>/dev/null
seed_rules_file "$RO" "o.json" "[
  {\"id\":\"o-1\",\"category\":\"safety\",\"statement\":\"a\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_OA\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"o-2\",\"category\":\"safety\",\"statement\":\"cat\",\"enforcement\":\"must\",\"check\":\"cat >/dev/null\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"o-3\",\"category\":\"safety\",\"statement\":\"b\",\"enforcement\":\"must\",\"check\":\"touch $MARKER_OB\",\"provenance\":{\"source\":\"test\"}}
]"
out_o="$( cd "$RO" && HOME="$HO" bash "$CHECKER" --confirm </dev/null 2>/dev/null )"
[ -e "$MARKER_OA" ] && [ -e "$MARKER_OB" ] \
  && ok "(o1) both markers exist — the check after the stdin-reading one still ran" \
  || no "(o1) a stdin-reading check swallowed later records (A=$([ -e "$MARKER_OA" ] && echo y || echo n) B=$([ -e "$MARKER_OB" ] && echo y || echo n))"
grep -qF "Checks passed: 3/3" < <(printf '%s\n' "$out_o") \
  && ok "(o2) Checks passed: 3/3" || no "(o2) expected 'Checks passed: 3/3', got: $out_o"

# ============================================================================
echo "== (p) stamp-write warnings — a non-object stamp file is warned about and never clobbered =="
# ============================================================================
RP="$(new_repo)"
HP="$ROOT/home_p"; mkdir -p "$(dirname "$ROOT/home_p/$STAMP_REL")"
printf '[1,2]' > "$HP/$STAMP_REL"
seed_rules_file "$RP" "p.json" "[
  {\"id\":\"p-one\",\"category\":\"safety\",\"statement\":\"p\",\"enforcement\":\"must\",\"check\":\"true\",\"provenance\":{\"source\":\"test\"}}
]"
err_p="$( cd "$RP" && HOME="$HP" bash "$CHECKER" --confirm </dev/null 2>&1 >/dev/null )"; rc_p=$?
[ "$rc_p" -eq 0 ] && ok "(p1) a non-object stamp file does not change the exit code" || no "(p1) exit $rc_p"
grep -qF "not an object" < <(printf '%s\n' "$err_p") \
  && ok "(p2) a valid-JSON non-object stamp file is WARNED about on stderr" \
  || no "(p2) no warning for a non-object stamp file; stderr: $err_p"
[ "$(cat "$HP/$STAMP_REL")" = "[1,2]" ] && ok "(p3) the non-object stamp file was NOT clobbered" \
  || no "(p3) the non-object stamp file was overwritten: $(cat "$HP/$STAMP_REL")"

# ---------------------------------------------------------------------------------------------------
# (ls) --list-selected (plan-time-rule-routing AC6 + Plan Review advisory A1): prints EXACTLY the
#      must+checkable ids (sorted, after validation + first-seen dedup), executes NOTHING (canary),
#      writes NO stamp (sentinel stamp file content + mtime unchanged), exits 0, and WINS over
#      --confirm / --if-stamped / --no-cmd. Every early-exit path prints NOTHING on stdout.
# ---------------------------------------------------------------------------------------------------
echo "== (ls) --list-selected: read-only enumeration of the must+checkable ids =="
RLS="$(new_repo)"
HLS="$ROOT/home-ls"; mkdir -p "$(dirname "$HLS/$STAMP_REL")"
CANARY_LS="$ROOT/ls_canary_$$"
rm -f "$CANARY_LS"
seed_rules_file "$RLS" "a.json" "[
  {\"id\":\"zz-must\",\"category\":\"a\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"touch $CANARY_LS\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"aa-must\",\"category\":\"z\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"touch $CANARY_LS\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"null-must\",\"category\":\"a\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":null,\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"adv-check\",\"category\":\"a\",\"statement\":\"s\",\"enforcement\":\"advisory\",\"check\":\"touch $CANARY_LS\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"bad-enf\",\"category\":\"a\",\"statement\":\"s\",\"enforcement\":\"MUST\",\"check\":\"true\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"nl\\nforged\",\"category\":\"a\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"true\",\"provenance\":{\"source\":\"test\"}}
]"
# A later file re-declaring aa-must as ADVISORY loses to first-seen (still listed); a new must id is listed.
seed_rules_file "$RLS" "b.json" "[
  {\"id\":\"aa-must\",\"category\":\"a\",\"statement\":\"dup\",\"enforcement\":\"advisory\",\"check\":null,\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"mm-must\",\"category\":\"a\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"false\",\"provenance\":{\"source\":\"test\"}}
]"
# Sentinel stamp: fixed content + an old mtime; any rewrite changes the content AND bumps the mtime.
STAMP_LS="$HLS/$STAMP_REL"
printf '%s\n' '{"sentinel":{"git_common_dir":"x","repo_root":"x","hash":"x","ts":"2000-01-01T00:00:00Z"}}' > "$STAMP_LS"
touch -t 200001010000 "$STAMP_LS"
STAMP_REF="$ROOT/ls-stamp-ref"; cp "$STAMP_LS" "$STAMP_REF"; touch -t 200001010000 "$STAMP_REF"
EXPECT_LS="$(printf 'aa-must\nmm-must\nzz-must')"
ls_run() { ( cd "$RLS" && HOME="$HLS" bash "$CHECKER" "$@" </dev/null 2>/dev/null ); }
out_ls="$(ls_run --list-selected)"; rc_ls=$?
[ "$rc_ls" -eq 0 ] && ok "(ls1) --list-selected exits 0 (even though mm-must's check would FAIL)" || no "(ls1) rc=$rc_ls"
[ "$out_ls" = "$EXPECT_LS" ] \
  && ok "(ls2) prints EXACTLY the must+checkable ids, sorted (null-check / advisory / invalid / dup-advisory / newline-id excluded)" \
  || no "(ls2) wrong id list: '$out_ls'"
[ ! -e "$CANARY_LS" ] && ok "(ls3) executes NOTHING (the canary check did not run)" || no "(ls3) a check RAN under --list-selected"
for combo in "--list-selected --confirm" "--confirm --list-selected" "--list-selected --if-stamped" \
             "--list-selected --no-cmd" "--no-cmd --if-stamped --confirm --list-selected"; do
  # shellcheck disable=SC2086 — word-splitting the combo into argv is the point.
  out_c="$(ls_run $combo)"; rc_c=$?
  if [ "$rc_c" -eq 0 ] && [ "$out_c" = "$EXPECT_LS" ] && [ ! -e "$CANARY_LS" ]; then
    ok "(ls4) '$combo' ⇒ same id list, exit 0, nothing executed (--list-selected wins)"
  else
    no "(ls4) '$combo' rc=$rc_c out='$out_c' canary=$([ -e "$CANARY_LS" ] && echo PRESENT || echo absent)"
  fi
  rm -f "$CANARY_LS"
done
out_env="$( cd "$RLS" && HOME="$HLS" RULES_CHECK_CONFIRM=1 bash "$CHECKER" --list-selected </dev/null 2>/dev/null )"
[ "$out_env" = "$EXPECT_LS" ] && [ ! -e "$CANARY_LS" ] \
  && ok "(ls5) an ambient RULES_CHECK_CONFIRM=1 cannot turn --list-selected into an execute run" \
  || no "(ls5) env confirm changed --list-selected: '$out_env'"
if cmp -s "$STAMP_LS" "$STAMP_REF" && ! [ "$STAMP_LS" -nt "$STAMP_REF" ]; then
  ok "(ls6) writes NO stamp: the sentinel stamp file's content AND mtime are unchanged after every --list-selected run"
else
  no "(ls6) the stamp file was rewritten under --list-selected: $(cat "$STAMP_LS")"
fi
# A1: every early-exit path prints NOTHING on stdout (no 'Checks passed: 0/0').
RLS0="$(new_repo)"
o0a="$( cd "$RLS0" && HOME="$HLS" bash "$CHECKER" --list-selected </dev/null 2>/dev/null )"; r0a=$?
mkdir -p "$RLS0/.agent/rules"
o0b="$( cd "$RLS0" && HOME="$HLS" bash "$CHECKER" --list-selected </dev/null 2>/dev/null )"; r0b=$?
printf 'not json' > "$RLS0/.agent/rules/x.json"
o0c="$( cd "$RLS0" && HOME="$HLS" bash "$CHECKER" --list-selected </dev/null 2>/dev/null )"; r0c=$?
printf '%s' '[{"id":"only-adv","category":"a","statement":"s","enforcement":"advisory","check":"true","provenance":{}}]' > "$RLS0/.agent/rules/x.json"
o0d="$( cd "$RLS0" && HOME="$HLS" bash "$CHECKER" --list-selected </dev/null 2>/dev/null )"; r0d=$?
if [ -z "$o0a$o0b$o0c$o0d" ] && [ "$r0a$r0b$r0c$r0d" = "0000" ]; then
  ok "(ls7) A1: absent store / empty dir / unparseable file / advisory-only store ⇒ EMPTY stdout, exit 0"
else
  no "(ls7) A1 early-exit leaked stdout: a='$o0a' b='$o0b' c='$o0c' d='$o0d' rcs=$r0a$r0b$r0c$r0d"
fi
# ...while the NON-list mode keeps its existing early-exit summary line (the change is list-mode-only).
o0e="$( cd "$RLS0" && rm -f .agent/rules/x.json && HOME="$HLS" bash "$CHECKER" --no-cmd </dev/null 2>/dev/null )"
[ "$o0e" = "Checks passed: 0/0" ] && ok "(ls8) without --list-selected the empty-store path still prints 'Checks passed: 0/0'" \
  || no "(ls8) non-list early exit changed: '$o0e'"
# POSITIVE CONTROL for (ls3)/(ls4)/(ls5): the SAME store under a plain --confirm (no --list-selected)
# DOES run the canary check — so "canary absent" above is a real observation, not a broken fixture.
rm -f "$CANARY_LS"
ls_run --confirm >/dev/null
[ -e "$CANARY_LS" ] && ok "(ls9) positive control: plain --confirm on the same store DOES create the canary (ls3/ls4 non-vacuous)" \
  || no "(ls9) positive control broken: --confirm did not create the canary — (ls3)/(ls4) are VACUOUS"
rm -f "$CANARY_LS"

# ============================================================================
echo "== (lg) --list-gateable: read-only countable/advisory classification per selected id =="
# (rule-enforcement-at-review-and-merge, D-a). The deep fixture matrix lives in
# test-rules-gate-verdict.sh (ac6); this section pins the flag's contract INSIDE the checker's own
# suite: exact lines for the four canonical fixtures, the same early-exit tier as --list-selected
# (nothing executed, no stamp written, empty stdout on an empty store), exit 0.
RLG="$(new_repo)"
HLG="$ROOT/home-lg"; mkdir -p "$HLG"
CANARY_LG="$ROOT/lg_canary_$$"; rm -f "$CANARY_LG"
mkdir -p "$RLG/scripts"
printf '#!/bin/sh\nexit 1\n' > "$RLG/scripts/lint.sh"; chmod +x "$RLG/scripts/lint.sh"
( cd "$RLG" && git add scripts && git commit -qm scripts ) >/dev/null 2>&1
seed_rules_file "$RLG" "lg.json" "[
  {\"id\":\"a1\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"grep -q init f\",\"binds\":[],\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"a2\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"grep -q init f\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"b\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"bash scripts/lint.sh\",\"binds\":[],\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"c\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"bash scripts/lint.sh\",\"binds\":[\"scripts/lint.sh\"],\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"canary\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"touch $CANARY_LG\",\"binds\":[],\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"adv\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"advisory\",\"check\":\"touch $CANARY_LG\",\"binds\":[],\"provenance\":{\"source\":\"test\"}}
]"
EXPECT_LG="$(printf 'a1\tcountable\tno_invocations\na2\tadvisory\tbinds_undeclared\nb\tadvisory\tunbound:scripts/lint.sh\nc\tcountable\tbound:1\ncanary\tcountable\tno_invocations')"
out_lg="$( cd "$RLG" && HOME="$HLG" bash "$CHECKER" --list-gateable </dev/null 2>/dev/null )"; rc_lg=$?
[ "$rc_lg" -eq 0 ] && ok "(lg1) --list-gateable exits 0" || no "(lg1) rc=$rc_lg"
[ "$out_lg" = "$EXPECT_LG" ] \
  && ok "(lg2) exactly one id<TAB>class<TAB>reason line per SELECTED id, sorted (advisory rule excluded)" \
  || no "(lg2) wrong listing: '$out_lg'"
[ ! -e "$CANARY_LG" ] && [ ! -e "$HLG/$STAMP_REL" ] && ok "(lg3) executes NOTHING and writes NO stamp" \
  || no "(lg3) canary=$([ -e "$CANARY_LG" ] && echo PRESENT || echo absent) stamp=$([ -e "$HLG/$STAMP_REL" ] && echo PRESENT || echo absent)"
out_lgc="$( cd "$RLG" && HOME="$HLG" RULES_CHECK_CONFIRM=1 bash "$CHECKER" --confirm --list-gateable </dev/null 2>/dev/null )"
[ "$out_lgc" = "$EXPECT_LG" ] && [ ! -e "$CANARY_LG" ] && [ ! -e "$HLG/$STAMP_REL" ] \
  && ok "(lg4) --confirm + ambient confirm cannot turn --list-gateable into an execute run" || no "(lg4) '$out_lgc'"
RLG0="$(new_repo)"
o_lg0="$( cd "$RLG0" && HOME="$HLG" bash "$CHECKER" --list-gateable </dev/null 2>/dev/null )"; r_lg0=$?
[ -z "$o_lg0" ] && [ "$r_lg0" -eq 0 ] && ok "(lg5) empty store ⇒ EMPTY stdout, exit 0 (no 'Checks passed: 0/0' leak)" || no "(lg5) rc=$r_lg0 out='$o_lg0'"
( cd "$RLG" && HOME="$HLG" bash "$CHECKER" --confirm </dev/null >/dev/null 2>&1 )
[ -e "$CANARY_LG" ] && ok "(lg6) positive control: plain --confirm on the same store DOES create the canary (lg3/lg4 non-vacuous)" \
  || no "(lg6) positive control broken — (lg3)/(lg4) are VACUOUS"
rm -f "$CANARY_LG"

# ============================================================================
echo "== (bh) binds hash-binding: a bound file's content is in the stamp; binds-free rules hash as before =="
# (bh1) binds absent / null / [] ⇒ the stamp hash equals the INDEPENDENT id/check-only computation
# case (g4) already pins — i.e. exactly the pre-`binds` hash (existing stamps stay valid).
RBH="$(new_repo)"
HBH="$ROOT/home-bh"; mkdir -p "$HBH"
seed_rules_file "$RBH" "bh.json" "[
  {\"id\":\"h-absent\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"true\",\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"h-null\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"true\",\"binds\":null,\"provenance\":{\"source\":\"test\"}},
  {\"id\":\"h-empty\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"false\",\"binds\":[],\"provenance\":{\"source\":\"test\"}}
]"
( cd "$RBH" && HOME="$HBH" bash "$CHECKER" --confirm </dev/null >/dev/null 2>&1 )
KEY_BH="$(cd "$RBH" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
hash_bh="$(jq -r --arg k "$KEY_BH" '.[$k].hash // ""' "$HBH/$STAMP_REL" 2>/dev/null)"
TMP_BH="$ROOT/bh_hash_input"
jq -nr '[{id:"h-absent",check:"true"},{id:"h-null",check:"true"},{id:"h-empty",check:"false"}] | .[] | [.id, .check] | @tsv' \
  | env LC_ALL=C sort > "$TMP_BH"
exp_bh="$(_t_sha256_file "$TMP_BH")"
[ -n "$hash_bh" ] && [ "$hash_bh" = "$exp_bh" ] \
  && ok "(bh1) binds absent / null / [] ⇒ the stamp hash equals the independent id/check-only hash (no binds term — pre-binds stamps stay valid)" \
  || no "(bh1) written=$hash_bh independent=$exp_bh"
# (bh2) a NON-EMPTY binds ⇒ `id\tcheck\t<path>=<sha256 of content>` — independently recomputed here.
RBB="$(new_repo)"
HBB="$ROOT/home-bb"; mkdir -p "$HBB"
mkdir -p "$RBB/scripts"
printf '#!/bin/sh\nexit 1\n' > "$RBB/scripts/lint.sh"; chmod +x "$RBB/scripts/lint.sh"
( cd "$RBB" && git add scripts && git commit -qm scripts ) >/dev/null 2>&1
seed_rules_file "$RBB" "bb.json" "[
  {\"id\":\"bound\",\"category\":\"t\",\"statement\":\"s\",\"enforcement\":\"must\",\"check\":\"bash scripts/lint.sh\",\"binds\":[\"scripts/lint.sh\"],\"provenance\":{\"source\":\"test\"}}
]"
( cd "$RBB" && HOME="$HBB" bash "$CHECKER" --confirm </dev/null >/dev/null 2>&1 )
KEY_BB="$(cd "$RBB" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
hash_bb="$(jq -r --arg k "$KEY_BB" '.[$k].hash // ""' "$HBB/$STAMP_REL" 2>/dev/null)"
sha_lint="$(_t_sha256_file "$RBB/scripts/lint.sh")"
TMP_BB="$ROOT/bb_hash_input"
{ jq -nr '{id:"bound",check:"bash scripts/lint.sh"} | [.id, .check] | @tsv' | tr -d '\n'; printf '\tscripts/lint.sh=%s\n' "$sha_lint"; } > "$TMP_BB"
exp_bb="$(_t_sha256_file "$TMP_BB")"
[ -n "$hash_bb" ] && [ "$hash_bb" = "$exp_bb" ] \
  && ok "(bh2) a bound rule's stamp hash equals the independent 'id<TAB>check<TAB>scripts/lint.sh=<sha256>' computation" \
  || no "(bh2) written=$hash_bb independent=$exp_bb"
[ -n "$hash_bb" ] && [ "$hash_bb" != "$(_t_sha256_file <(jq -nr '{id:"bound",check:"bash scripts/lint.sh"} | [.id, .check] | @tsv'))" ] \
  && ok "(bh2b) ...and differs from the id/check-only hash (the bound content really is in it)" || no "(bh2b) bound hash equals the unbound hash"
out_bb1="$( cd "$RBB" && HOME="$HBB" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
[ "$(printf '%s\n' "$out_bb1" | tail -n 1)" = "Checks passed: 0/1" ] \
  && ok "(bh3) before any edit, --if-stamped replays the bound rule (0/1 — it fails)" || no "(bh3) replay=[$out_bb1]"
( cd "$RBB" && printf '#!/bin/sh\nexit 0\n' > scripts/lint.sh && git commit -qam "edit the bound file" ) >/dev/null 2>&1
out_bb2="$( cd "$RBB" && HOME="$HBB" bash "$CHECKER" --if-stamped </dev/null 2>/dev/null )"
[ "$out_bb2" = "$(printf '  [SKIP] all (unstamped)\nChecks passed: 0/0')" ] \
  && ok "(bh4) editing the BOUND file after stamping ⇒ '[SKIP] all (unstamped)' — the check text alone did not change" \
  || no "(bh4) replay after the bound edit: [$out_bb2]"
( cd "$RBB" && git rm -q --cached scripts/lint.sh && git commit -qm untrack ) >/dev/null 2>&1
out_bb3="$( cd "$RBB" && HOME="$HBB" bash "$CHECKER" --list-gateable </dev/null 2>/dev/null )"
[ "$out_bb3" = "$(printf 'bound\tadvisory\tbinds_invalid')" ] \
  && ok "(bh5) untracking the bound file ⇒ --list-gateable demotes the rule to advisory/binds_invalid (tracked-ness is checked with git, not [ -e ])" \
  || no "(bh5) listing after untracking: [$out_bb3]"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
