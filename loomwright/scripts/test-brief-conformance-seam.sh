#!/usr/bin/env bash
# test-brief-conformance-seam.sh — static wiring test for the BRIEF-CONFORMANCE enrichment of the
# Supervisor Phase 4.5 gating Code Reviewer (skills/self-heal-advisory/SKILL.md Part 1
# §"Brief-conformance advisory", Part 2 step 1f + the BRIEF-CONFORMANCE ADVISORY spawn-prompt line)
# and its two mirrors (agents/code-reviewer.md, skills/quality-checklist/SKILL.md).
#
# Every surface here is MARKDOWN — prompt text that an agent executes — so there is nothing to run;
# a grep is the only thing that can hold the wiring. Modelled on test-rules-seams.sh: pass/fail
# counters, ok()/no() helpers DEFINED here (test-suite-helpers-defined.sh scans every suite), a
# "RESULT: N passed, M failed" tail, exit 1 on any failure, paths from $BASH_SOURCE so it runs
# from any CWD under ci.yml's `loomwright/scripts/test-*.sh` glob. bash 3.2 / BSD userland safe.
#
# Asserts:
#   (a) the reviewer spawn prompt carries the BRIEF-CONFORMANCE ADVISORY line DIRECTLY AFTER the
#       HOUSE-RULES ADVISORY line (anchored on the `**HOUSE-RULES ADVISORY (non-gating` prompt-line
#       literal, NOT the bare token — Part 1 prose also mentions HOUSE-RULES), gated on non-empty
#       `brief_conformance`, and carrying the three-way verdict + the `category: new` / HIGH mapping,
#       the `{brief_path}` pointer for criteria past the cap, and the `file:` / sentinel `brief` convention.
#   (b) the bounded cap is stated ONCE: the token `25 bullets` (a phrase, not a bare digit — an
#       unrelated future `25` must not turn this red) appears exactly once in the skill, INSIDE the
#       Part 1 `## Brief-conformance advisory` section; step 1f refers to "the cap in Part 1" and
#       names all three skip conditions (no `brief_path` / no `## Acceptance Criteria` / zero bullets).
#   (c) agents/code-reviewer.md names `not_addressed` with the HIGH / `category: new` mapping and
#       mirrors the sentinel `brief` convention (one sentence, no second copy of the rules).
#   (d) the Self-Heal Miss-Class Checklist names `brief_conformance`.
#   (e) the DIFFERENT-LENS DIRECTIVE parenthetical class list names `brief_conformance`.
#   (m) MUTATION CONTROL: delete the prompt line from a COPY of the skill; gate the mutant on
#       non-empty + differs-from-original; (a) against the mutant MUST fail. Without this, (a) could
#       be green while asserting nothing.
#
# EXPLICIT LIMIT: this pins the WIRING (the line exists, sits where the skill says, says what the
# mirrors say). It cannot prove a reviewer emits the finding — that is prompt behaviour, observable
# only on the NEXT job's Phase 4.5 run.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

SKILL="$PLUGIN_ROOT/skills/self-heal-advisory/SKILL.md"
REVIEWER="$PLUGIN_ROOT/agents/code-reviewer.md"
CHECKLIST="$PLUGIN_ROOT/skills/quality-checklist/SKILL.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

HOUSE_LINE_RE='^[[:space:]]*\*\*HOUSE-RULES ADVISORY \(non-gating'
BRIEF_LINE_RE='^[[:space:]]*\*\*BRIEF-CONFORMANCE ADVISORY \('

# prompt_line_adjacent <file> — exit 0 iff the first non-blank line after the HOUSE-RULES ADVISORY
# prompt line is the BRIEF-CONFORMANCE ADVISORY prompt line. Silent; used on the real skill AND on
# the mutant, so it must carry no ok/no side effects of its own.
prompt_line_adjacent() {
  # Literal prefix matching via index() on the whitespace-trimmed line — deliberately NOT a regex
  # handed in through `awk -v` (which escape-processes `\*` into `*` and breaks the pattern).
  awk '
    { t = $0; sub(/^[[:space:]]+/, "", t) }
    found_house && t != "" {
      if (index(t, "**BRIEF-CONFORMANCE ADVISORY (") == 1) { hit = 1 }
      found_house = 0
    }
    index(t, "**HOUSE-RULES ADVISORY (non-gating") == 1 { found_house = 1 }
    END { exit (hit ? 0 : 1) }
  ' "$1"
}

# brief_prompt_line <file> — prints the BRIEF-CONFORMANCE ADVISORY prompt line (empty if absent)
brief_prompt_line() { grep -E "$BRIEF_LINE_RE" "$1" 2>/dev/null | head -1; }

for f in "$SKILL" "$REVIEWER" "$CHECKLIST"; do
  if [ ! -f "$f" ]; then
    no "MISSING surface: $f"
  fi
done
if [ "$fail" -ne 0 ]; then
  echo
  echo "RESULT: $pass passed, $fail failed"
  exit 1
fi

# ---- (a) the spawn-prompt line, directly after HOUSE-RULES ----------------------------------------
if grep -qE "$HOUSE_LINE_RE" "$SKILL"; then
  ok "(a) HOUSE-RULES ADVISORY prompt-line anchor present"
else
  no "(a) HOUSE-RULES ADVISORY prompt-line anchor MISSING — the adjacency assertion has nothing to anchor on"
fi
if prompt_line_adjacent "$SKILL"; then
  ok "(a) BRIEF-CONFORMANCE ADVISORY line sits directly after the HOUSE-RULES ADVISORY line"
else
  no "(a) BRIEF-CONFORMANCE ADVISORY line is not the next non-blank line after HOUSE-RULES ADVISORY"
fi
line="$(brief_prompt_line "$SKILL")"
case "$line" in
  *'include this line ONLY when `brief_conformance` is non-empty'*) ok "(a) prompt line is gated on non-empty brief_conformance" ;;
  *) no "(a) prompt line lacks the 'include ONLY when non-empty' gate" ;;
esac
case "$line" in
  *'`addressed`'*'`not_addressed`'*'`cannot_determine`'*) ok "(a) prompt line carries the three-way verdict" ;;
  *) no "(a) prompt line lacks the addressed | not_addressed | cannot_determine verdict" ;;
esac
case "$line" in
  *'`category: new`'*'HIGH'*) ok "(a) prompt line maps not_addressed to category: new / HIGH" ;;
  *) no "(a) prompt line lacks the category: new / HIGH mapping" ;;
esac
case "$line" in
  *'orientation'*'NEVER produce findings'*) ok "(a) prompt line labels rubric bullets orientation-only (never findings)" ;;
  *) no "(a) prompt line does not label rubric bullets as orientation-only" ;;
esac
case "$line" in
  *'the cap in Part 1'*) ok "(a) prompt line refers to the cap in Part 1 (does not restate it)" ;;
  *) no "(a) prompt line does not refer to the cap in Part 1" ;;
esac
# The over-cap instruction ("read it if you need them") needs an operand: the brief pointer, in the
# pointer-not-payload shape every other Supervisor spawn uses ({brief_path}).
case "$line" in
  *'{brief_path}'*) ok "(a) prompt line carries the {brief_path} pointer for criteria past the cap" ;;
  *) no "(a) prompt line lacks the {brief_path} pointer — the over-cap 'read it' instruction has no operand" ;;
esac
# `file` is a required non-empty string in the SubagentStop validator (hooks.json); a not_addressed
# criterion may target no file, so the line must state the `brief` sentinel ONCE (mirrored, not
# restated, in agents/code-reviewer.md step 5a).
case "$line" in
  *'`file:`'*'sentinel `brief`'*) ok "(a) prompt line states the file: convention with the brief sentinel" ;;
  *) no "(a) prompt line lacks the file: / sentinel brief convention" ;;
esac

# ---- (b) the cap stated ONCE, inside Part 1; step 1f references it + names the skip conditions ----
cap_total="$(grep -c -- '25 bullets' "$SKILL" || true)"
cap_in_section="$(awk '
  /^## Brief-conformance advisory/ { in_sec = 1; next }
  in_sec && /^## / { in_sec = 0 }
  in_sec && /25 bullets/ { n++ }
  END { print n + 0 }
' "$SKILL")"
if [ "$cap_total" -eq 1 ] && [ "$cap_in_section" -eq 1 ]; then
  ok "(b) cap token '25 bullets' appears exactly once, inside ## Brief-conformance advisory"
else
  no "(b) cap token '25 bullets' count: total=$cap_total in-section=$cap_in_section (expected 1 / 1)"
fi
step1f="$(grep -E '^1f\. ' "$SKILL" | head -1)"
if [ -n "$step1f" ]; then
  ok "(b) Part 2 on-entry step 1f. exists"
else
  no "(b) Part 2 on-entry step 1f. MISSING"
fi
case "$step1f" in
  *'the cap in Part 1'*) ok "(b) step 1f refers to the cap in Part 1" ;;
  *) no "(b) step 1f does not refer to the cap in Part 1" ;;
esac
case "$step1f" in
  *'brief_path'*) ok "(b) step 1f names skip condition: no brief_path" ;;
  *) no "(b) step 1f lacks the no-brief_path skip condition" ;;
esac
case "$step1f" in
  *'## Acceptance Criteria'*) ok "(b) step 1f names skip condition: no ## Acceptance Criteria section" ;;
  *) no "(b) step 1f lacks the no-## Acceptance Criteria skip condition" ;;
esac
case "$step1f" in
  *'zero bullets'*) ok "(b) step 1f names skip condition: zero bullets parse" ;;
  *) no "(b) step 1f lacks the zero-bullets skip condition" ;;
esac
case "$step1f" in
  *'25 bullets'*) no "(b) step 1f RESTATES the cap (house rule: one authoritative place)" ;;
  *) ok "(b) step 1f does not restate the cap number" ;;
esac

# ---- (c) agents/code-reviewer.md mirror: three-way verdict + HIGH / new mapping ------------------
rev_line="$(grep -F 'not_addressed' "$REVIEWER" | grep -F 'category: new' | grep -F 'HIGH' | head -1 || true)"
if [ -n "$rev_line" ]; then
  ok "(c) agents/code-reviewer.md names not_addressed with the category: new / HIGH mapping"
else
  no "(c) agents/code-reviewer.md lacks a not_addressed line carrying category: new + HIGH"
fi
if grep -qF 'cannot_determine' "$REVIEWER"; then
  ok "(c) agents/code-reviewer.md names cannot_determine"
else
  no "(c) agents/code-reviewer.md lacks cannot_determine"
fi
case "$rev_line" in
  *'sentinel `brief`'*) ok "(c) agents/code-reviewer.md mirrors the brief sentinel for file:" ;;
  *) no "(c) agents/code-reviewer.md not_addressed line does not mirror the sentinel brief convention" ;;
esac

# ---- (d) the miss-class checklist names brief_conformance --------------------------------------
cl_hits="$(awk '
  /^## Self-Heal Miss-Class Checklist/ { in_sec = 1; next }
  in_sec && /^## / { in_sec = 0 }
  in_sec && /brief_conformance/ { n++ }
  END { print n + 0 }
' "$CHECKLIST")"
if [ "$cl_hits" -ge 1 ]; then
  ok "(d) Self-Heal Miss-Class Checklist names brief_conformance"
else
  no "(d) Self-Heal Miss-Class Checklist does not name brief_conformance"
fi

# ---- (e) the DIFFERENT-LENS DIRECTIVE parenthetical class list names brief_conformance ----------
lens_line="$(grep -F 'Self-Heal Miss-Class Checklist regardless of repo' "$SKILL" | head -1 || true)"
case "$lens_line" in
  *'brief_conformance'*) ok "(e) DIFFERENT-LENS DIRECTIVE class list names brief_conformance" ;;
  *) no "(e) DIFFERENT-LENS DIRECTIVE class list does not name brief_conformance" ;;
esac

# ---- (m) MUTATION CONTROL: (a) must go RED when the prompt line is deleted ----------------------
MUT="$(mktemp)"
trap 'rm -f "$MUT" 2>/dev/null' EXIT
sed -E "/${BRIEF_LINE_RE}/d" "$SKILL" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$SKILL" "$MUT"; then
  ok "(m) mutant is non-empty and differs from the original (a valid mutant)"
  if prompt_line_adjacent "$MUT"; then
    no "(m) adjacency assertion (a) PASSED against the mutant — the assertion is vacuous"
  else
    ok "(m) adjacency assertion (a) fails against the mutant (the assertion is load-bearing)"
  fi
  if [ -z "$(brief_prompt_line "$MUT")" ]; then
    ok "(m) the prompt line is absent from the mutant"
  else
    no "(m) the prompt line survived the mutation — the mutant did not mutate what it claims"
  fi
else
  no "(m) mutant invalid (empty, or identical to the original) — the mutation control cannot be trusted"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
