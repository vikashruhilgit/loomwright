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
#   P6 automate-loop §10 carries condition 7 and its named PARK reason
#   P7 review-heal's rules read is ALLOW-LISTED: everything unaffirmed ⇒ unreadable ⇒ ESCALATED
#   P8 self-heal-advisory's rules read is ALLOW-LISTED the same way, and Part 2 escalates on the
#      allow-list complement (never a deny-list of bad verdicts)
#   P9 self-heal-advisory remembers countable fails across iterations (rules_failed_seen) and a later
#      `unstamped` escalates `rules_fail_then_unstamped` (automate-followups/18)
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
AL="loomwright/skills/automate-loop/SKILL.md"
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
         'if i.category == "new" and i.severity in (BLOCKING, HIGH)] + rule_findings' ;;
    5) printf '%s\n' "$CM" \
         'A human-stamped, gate-countable `must`-rule check is a correctness gate, not an advisory emitter' ;;
    6) printf '%s\n' "$AL" 'PARK: rules_check_failed (' 'rules-gate-verdict.sh' ;;
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
         'record_decision(phase: SELF_HEAL, decision: "rules_fail_then_unstamped"' ;;
    10) printf '%s\n' "$RH" \
         'rules_failed_seen |= { id for id in rules.failing if id in rules.countable }' \
         'rules.verdict != "fail" or (rules.verdict == "unstamped" and rules_failed_seen)' \
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
