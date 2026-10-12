#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-rules-gate-seams.sh — STATIC prompt-seam pins for the rules gate (rule-enforcement-at-review-and-
# merge, automate-followups/07, AC9(a) + R1). The skill/agent .md files ARE the program: the gating
# behaviour at Phase 4.5 and in the --until-mergeable drain lives in prose a model executes, so the
# only regression guard for "someone deleted the gate" is a pin on that prose. The code-side seam
# (gate-eval condition 7) is exercised behaviourally in test-automate-helpers.sh (section R).
#
# PINS (each a set of fixed-string needles that must ALL appear in one file):
#   P1 self-heal-advisory invokes rules-gate-verdict.sh (the Phase 4.5 gate replay)
#   P2 review-heal invokes rules-gate-verdict.sh (the drain's §U4 rules step)
#   P3 review-heal's READY redefinition carries the rules clause
#   P4 self-heal-advisory's BLOCKING finding synthesis + its routing into the fix loop
#   P5 CLAUDE.md carries the D4 invariant sentence
#   P6 automate-loop §10 carries condition 7, its named PARK reason, and the checkout pin's two
#      PARK reasons (automate-followups/16)
#   P7 review-heal's rules read is ALLOW-LISTED: everything unaffirmed ⇒ unreadable ⇒ ESCALATED
#   P8 self-heal-advisory's rules read is ALLOW-LISTED the same way, and Part 2 escalates on the
#      allow-list complement (never a deny-list of bad verdicts)
#   P9 self-heal-advisory remembers countable fails across iterations (rules_failed_seen) and a later
#      `unstamped` escalates `rules_fail_then_unstamped` (automate-followups/18) — including the
#      persistence record_decision and the leg's ESCALATED line (bound by its unique trailing comment)
#   P10 review-heal remembers countable fails across rounds, and the remembered set escalates an
#      `unstamped` in BOTH rules_escalates and the sub-floor rules_after re-read (automate-followups/18)
#   P1/P2 pin the invocation in its RUNTIME form — the quoted plugin-install-root variable prefix
#   ($INVOKE below) — never the developer-side repo-relative `scripts/…` path, which resolves neither
#   in a user project nor at this repo's root.
#
# MUTATION CONTROLS (gated — the mutant must be non-empty and differ from the original, and the
# UNMUTATED copy must pass first as a positive control; otherwise the control FAILS loudly):
#   M<n>  delete every line carrying pin n's first needle ⇒ pin n must FAIL on the mutant tree.
#   AC9a  delete the helper invocation + the READY clause from review-heal AND the synthesis block
#         from self-heal-advisory in one tree ⇒ the pin run must FAIL.
#   MROOT rewrite the runtime prefix to the repo-relative `scripts/…` form in BOTH skills ⇒ P1 and P2
#         must FAIL (the prefix itself is load-bearing, not just the script name).
#
# LINE LEGS (automate-followups/39 C.1 — the posted Phase 4.5 line must name the verdict Part 2 acts on):
#   The REAL rules-gate-verdict.sh runs against a fixture store with RULES_CHECK_NO_CMD=1 (what
#   $NO_CMD_FLAG exports), and its verdict is projected through self-heal-advisory's OWN
#   `rules_check_line =` block by project_line, a small evaluator of that block's branch grammar (first
#   match wins). An unknown condition, an unparseable branch or a missing block is an EVAL_ERROR, which
#   fails the leg — never a vacuous pass.
#     L1  corrupt store + --no-cmd ⇒ verdict unreadable ⇒ line `rules_check: unreadable`
#     L2  no store (empty selection) + --no-cmd ⇒ verdict none ⇒ line `rules_check: none`
#     L3  an unstamped countable store + --no-cmd ⇒ verdict cmd_disabled ⇒ line `rules_check: cmd_disabled`
#   ML1 (gated mutant) put back the pre-fix first branch (`$NO_CMD_FLAG is non-empty or … cmd_disabled`)
#       ⇒ L1 must FAIL on the mutant (it posts cmd_disabled over an escalating unreadable verdict).
#
# Portability: bash 3.2 (macOS) + Linux; no GNU-only flags, no mapfile, no sed -i.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }

SHA="loomwright/skills/self-heal-advisory/SKILL.md"
RH="loomwright/skills/review-heal/SKILL.md"
# automate-loop is a split index (parallel-automate/22); pin 6's needles are all §10 text, so AL names the
# split file that holds `## §10` (pins are root-relative files — check_pin/fresh_tree/mutate copy them).
# test-automate-loop-split.sh fails when the index stops naming this file for §10.
AL="loomwright/skills/automate-loop/modes-and-merge-gate.md"
CM="CLAUDE.md"
# The helper invocation in its RUNTIME form (the plugin install root variable, quoted).
INVOKE='bash "${CLAUDE_PLUGIN_ROOT}/scripts/rules-gate-verdict.sh" --root'

# pin <n> — prints "<file>" then one needle per line for pin n (first needle = the mutant's target).
pin() {
  case "$1" in
    1) printf '%s\n' "$SHA" "$INVOKE" ;;
    2) printf '%s\n' "$RH" "$INVOKE" ;;
    3) printf '%s\n' "$RH" \
         'no countable human-stamped must-rule check is failing (rules-gate-verdict.sh verdict ok or none)' ;;
    4) printf '%s\n' "$SHA" \
         'rule_findings.append({severity: BLOCKING, category: new, file: "rule"' \
         'iter_decision = FAIL' \
         'fixable_issues = [i for i in review.issues if at_floor(i)] + rule_findings' ;;
    5) printf '%s\n' "$CM" \
         'A human-stamped, gate-countable `must`-rule check is a correctness gate, not an advisory emitter' ;;
    6) printf '%s\n' "$AL" 'PARK: rules_check_failed (' 'rules-gate-verdict.sh' \
         'PARK: rules_gate_head_mismatch' 'PARK: rules_gate_dirty_tree' ;;
    7) printf '%s\n' "$RH" \
         'or an unrecognised verdict string — is treated as unreadable:' \
         'return {verdict: "unreadable"' \
         'and rules_after.verdict in RULES_PASSABLE:' \
         'rules_escalates = rules.verdict not in RULES_PASSABLE and rules.verdict != "fail"' ;;
    8) printf '%s\n' "$SHA" \
         'non-string verdict, or an unrecognised verdict string — is treated as unreadable' \
         'rules = {verdict: "unreadable"' \
         'if rules.verdict not in RULES_PASSABLE and rules.verdict != "fail":' ;;
    9) printf '%s\n' "$SHA" \
         'new_seen = {id for id in rules.failing if id in rules.countable} - rules_failed_seen' \
         'rules_failed_seen |= new_seen' \
         'if rules.verdict == "unstamped" and rules_failed_seen:' \
         'record_decision(phase: SELF_HEAL, decision: "rules_fail_then_unstamped"' \
         'record_decision(phase: SELF_HEAL, decision: "rules_failed_seen: added' \
         'heal_decision = ESCALATED   # rules_fail_then_unstamped' \
         '+ len(rules_failed_seen)' ;;
    10) printf '%s\n' "$RH" \
         'rules_failed_seen |= { id for id in rules.failing if id in rules.countable }' \
         'rules_escalates = rules_escalates or (rules.verdict == "unstamped" and rules_failed_seen)' \
         'and not (rules_after.verdict == "unstamped" and rules_failed_seen) and rules_after.verdict in RULES_PASSABLE:' \
         '"rules_fail_then_unstamped: <rules_failed_seen ids>' ;;
  esac
}
PINS="1 2 3 4 5 6 7 8 9 10"

# check_pin <root> <n> — 0 iff every needle of pin n is present in <root>/<file>.
check_pin() {
  local root="$1" n="$2" file needle first=1
  while IFS= read -r needle; do
    if [ "$first" -eq 1 ]; then file="$needle"; first=0; continue; fi
    [ -r "$root/$file" ] || return 1
    grep -qF -- "$needle" "$root/$file" || return 1
  done <<EOF
$(pin "$n")
EOF
  return 0
}

# run_pins <root> — 0 iff every pin holds under <root>.
run_pins() {
  local n rc=0
  for n in $PINS; do check_pin "$1" "$n" || rc=1; done
  return "$rc"
}

# ---- live pins ------------------------------------------------------------------------------------
for n in $PINS; do
  if check_pin "$REPO" "$n"; then ok "P$n pinned in $(pin "$n" | head -n 1)"; else no "P$n missing in $(pin "$n" | head -n 1)"; fi
done

# ---- gated mutants ----------------------------------------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rules-gate-seams.XXXXXX")" || { no "mktemp"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# fresh_tree <dir> — copy every pinned file into <dir> (same relative paths).
fresh_tree() {
  local d="$1" f
  for f in "$SHA" "$RH" "$AL" "$CM"; do
    mkdir -p "$d/$(dirname "$f")"
    cp "$REPO/$f" "$d/$f" || return 1
  done
}

# mutate <dir> <file> <needle> — delete every line of <dir>/<file> carrying <needle>; gated.
mutate() {
  local d="$1" f="$2" needle="$3"
  grep -vF -- "$needle" "$d/$f" > "$d/$f.mut"
  if [ ! -s "$d/$f.mut" ]; then no "mutant of $f is empty (gate)"; return 1; fi
  if cmp -s "$d/$f.mut" "$d/$f"; then no "mutant of $f does not differ (gate: needle not found)"; return 1; fi
  mv "$d/$f.mut" "$d/$f"
}

for n in $PINS; do
  d="$TMP/m$n"
  fresh_tree "$d" || { no "M$n tree copy"; continue; }
  if ! run_pins "$d"; then no "M$n positive control: unmutated copy fails the pins"; continue; fi
  file="$(pin "$n" | sed -n 1p)"
  needle="$(pin "$n" | sed -n 2p)"
  mutate "$d" "$file" "$needle" || continue
  if check_pin "$d" "$n"; then no "M$n deleting the pinned line left P$n passing"; else ok "M$n deleting the pinned line fails P$n"; fi
done

# AC9(a): revert the gate prose in both skills at once.
d="$TMP/ac9a"
if fresh_tree "$d" && run_pins "$d"; then
  mutate "$d" "$RH" "$INVOKE" \
  && mutate "$d" "$RH" 'no countable human-stamped must-rule check is failing' \
  && mutate "$d" "$SHA" 'rule_findings' \
  && { if run_pins "$d"; then no "AC9a reverting the gate prose left every pin passing"; else ok "AC9a reverting the gate prose fails the pin run"; fi; }
else
  no "AC9a positive control: tree copy or unmutated pin run failed"
fi

# MROOT: strip the runtime prefix (the developer-side path form) in both skills ⇒ P1 and P2 must fail.
d="$TMP/mroot"
if fresh_tree "$d" && run_pins "$d"; then
  for f in "$SHA" "$RH"; do
    sed 's|"${CLAUDE_PLUGIN_ROOT}/scripts/rules-gate-verdict.sh"|scripts/rules-gate-verdict.sh|' "$d/$f" > "$d/$f.mut"
    if [ ! -s "$d/$f.mut" ] || cmp -s "$d/$f.mut" "$d/$f"; then no "MROOT mutant of $f empty or unchanged (gate)"; continue; fi
    mv "$d/$f.mut" "$d/$f"
  done
  if check_pin "$d" 1 || check_pin "$d" 2; then no "MROOT a repo-relative helper path left P1 or P2 passing"
  else ok "MROOT the repo-relative helper path fails P1 and P2 (the runtime prefix is load-bearing)"; fi
else
  no "MROOT positive control: tree copy or unmutated pin run failed"
fi

# ---- line legs (C.1): the posted line names the helper's verdict, under --no-cmd -----------------
# project_line <skill-file> <no_cmd_flag> <verdict-json> — print the line the skill's `rules_check_line =`
# block yields (main projection only; the `+= rules_advisory` suffix is not evaluated), or
# `EVAL_ERROR: <why>`.
project_line() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, re, sys
path, flag, raw = sys.argv[1], sys.argv[2], sys.argv[3]
def err(m):
    print("EVAL_ERROR: " + m); sys.exit(0)
try:
    rules = json.loads(raw)
except Exception:
    err("verdict is not JSON")
lines = open(path, encoding="utf-8").read().split("\n")
start = [i for i, l in enumerate(lines) if re.match(r"rules_check_line =(\s|$)", l)]
if len(start) != 1:
    err("expected exactly one `rules_check_line =` block, found %d" % len(start))
branches = []
for l in lines[start[0] + 1:]:
    if l.startswith("rules_check_line +="):
        break
    m = re.match(r'\s*(if|elif)\s+(.*?):\s+"((?:[^"\\]|\\.)*)"', l) or re.match(r'\s*(else):()\s+"((?:[^"\\]|\\.)*)"', l)
    if not m:
        err("unparseable branch line: " + l)
    branches.append((m.group(1), m.group(2), m.group(3)))
if not branches or branches[0][0] != "if":
    err("block does not open with an `if` branch")
def atom(a):
    a = a.strip()
    if a == "$NO_CMD_FLAG is non-empty":
        return flag != ""
    if a == "rules.checks_passed is non-null":
        return rules.get("checks_passed") is not None
    m = re.fullmatch(r'rules\.verdict == "([a-z_]+)"', a)
    if m:
        return rules.get("verdict") == m.group(1)
    err("unknown condition atom: " + a)
for kind, cond, text in branches:
    if kind == "else" or any(atom(a) for a in cond.split(" or ")):
        print(text); sys.exit(0)
err("no branch matched and no else")
PY
}

if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "skip L1-L3/ML1: jq or python3 absent — the helper cannot compute a verdict here (vacuous)"
else
  GV="$REPO/loomwright/scripts/rules-gate-verdict.sh"
  LROOT="$TMP/lines"; mkdir -p "$LROOT/home"
  # line_repo <name> — a committed scratch git repo carrying a tracked data.txt; prints its path.
  line_repo() {
    local r="$LROOT/$1"
    mkdir -p "$r"
    ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
        && printf 'hello\n' > data.txt && git add data.txt && git commit -qm init ) >/dev/null 2>&1
    printf '%s' "$r"
  }
  # nocmd_verdict <repo> — the REAL helper's verdict JSON under RULES_CHECK_NO_CMD=1, sandboxed HOME.
  nocmd_verdict() {
    ( cd "$1" && env -u RULES_CHECK_CONFIRM HOME="$LROOT/home" RULES_CHECK_NO_CMD=1 \
        bash "$GV" --root "$1" </dev/null 2>/dev/null )
  }
  # line_leg <label> <skill-file> <repo> <expected-verdict> <expected-line> — 0 iff both hold.
  line_leg() {
    local v got
    v="$(nocmd_verdict "$3")"
    if [ "$(printf '%s' "$v" | jq -r '.verdict' 2>/dev/null)" != "$4" ]; then
      no "$1 precondition: helper verdict is not $4: [$v]"; return 1
    fi
    got="$(project_line "$2" "--no-cmd" "$v")"
    if [ "$got" = "$5" ]; then ok "$1 verdict $4 under --no-cmd posts \`$got\`"; return 0; fi
    no "$1 verdict $4 under --no-cmd posts \`$got\` (expected \`$5\`)"; return 1
  }
  RL1="$(line_repo corrupt)"; mkdir -p "$RL1/.agent/rules"; printf '[{"id": "x",\n' > "$RL1/.agent/rules/r.json"
  RL2="$(line_repo empty)"
  RL3="$(line_repo countable)"; mkdir -p "$RL3/.agent/rules"
  jq -n '[{id:"c1", category:"t", statement:"s", enforcement:"must", check:"grep -q hello data.txt", binds:[], provenance:{source:"t"}}]' \
    > "$RL3/.agent/rules/r.json"
  line_leg "L1 corrupt store:" "$REPO/$SHA" "$RL1" unreadable "rules_check: unreadable"
  line_leg "L2 empty selection:" "$REPO/$SHA" "$RL2" none "rules_check: none"
  line_leg "L3 countable, unstamped store:" "$REPO/$SHA" "$RL3" cmd_disabled "rules_check: cmd_disabled"

  # ML1 — the pre-fix order (a $NO_CMD_FLAG disjunct as the FIRST branch) must turn L1 red.
  d="$TMP/ml1"
  if fresh_tree "$d" && [ "$(project_line "$d/$SHA" "--no-cmd" "$(nocmd_verdict "$RL1")")" = "rules_check: unreadable" ]; then
    awk '!done && /^  if rules\.verdict == "unreadable":/ {
           print "  if $NO_CMD_FLAG is non-empty or rules.verdict == \"cmd_disabled\":  \"rules_check: cmd_disabled\""
           sub(/^  if /, "  elif "); done = 1 }
         { print }' "$d/$SHA" > "$d/$SHA.mut"
    if [ ! -s "$d/$SHA.mut" ] || cmp -s "$d/$SHA.mut" "$d/$SHA"; then
      no "ML1 mutant empty or unchanged (gate: the first branch was not found)"
    else
      mv "$d/$SHA.mut" "$d/$SHA"
      got="$(project_line "$d/$SHA" "--no-cmd" "$(nocmd_verdict "$RL1")")"
      if [ "$got" = "rules_check: unreadable" ]; then
        no "ML1 the pre-fix branch order still posts \`$got\` — L1 is not load-bearing"
      else
        ok "ML1 the pre-fix branch order posts \`$got\` over an unreadable verdict — L1 turns red"
      fi
    fi
  else
    no "ML1 positive control: tree copy or the unmutated L1 projection failed"
  fi
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
