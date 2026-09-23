#!/usr/bin/env bash
# test-deviations-advisory-seam.sh — static wiring test for the DEVIATIONS ADVISORY enrichment of
# the Supervisor Phase 4.5 gating Code Reviewer (skills/self-heal-advisory/SKILL.md Part 1
# §"Deviations advisory (worker- and fixer-recorded plan drift)", Part 2 step 1g + the DEVIATIONS
# ADVISORY spawn-prompt line) and its mirrors (agents/code-reviewer.md, quality-checklist/SKILL.md).
#
# Every surface here is MARKDOWN — prompt text that an agent executes — so there is nothing to run;
# a grep is the only thing that can hold the wiring. Modelled on test-brief-conformance-seam.sh:
# pass/fail counters, ok()/no() helpers DEFINED here (test-suite-helpers-defined.sh scans every
# suite), a "RESULT: N passed, M failed" tail, exit 1 on any failure, paths from $BASH_SOURCE so it
# runs from any CWD under ci.yml's `loomwright/scripts/test-*.sh` glob. bash 3.2 / BSD userland safe.
#
# Asserts:
#   (a) the reviewer spawn prompt carries the DEVIATIONS ADVISORY line DIRECTLY AFTER the
#       BRIEF-CONFORMANCE ADVISORY line (anchored on the `**BRIEF-CONFORMANCE ADVISORY (` prompt-line
#       literal, NOT the bare token — Part 1 prose also mentions BRIEF-CONFORMANCE), gated on
#       non-empty `deviations_advisory`, and carrying the prefix convention (plan:/edge:/open:/test:,
#       unprefixed reads as other:), the "contradicts a stated criterion" question (not "would I have
#       done it differently"), and the `category: new` finding shape quoting both deviation + criterion.
#   (b) step 1g exists, is a sibling to 1c/1e/1f, runs on EVERY iteration (not only the first — the
#       "RUNS ON EVERY ITERATION" / "not only the first" wording), and reads `fixer_deviations`.
#   (c) agents/code-reviewer.md names `deviations` in the Self-heal lens paragraph AND carries a
#       dedicated "Deviations conformance" Review Process subsection (5b).
#   (d) the Self-Heal Miss-Class Checklist (quality-checklist/SKILL.md) names `deviations`.
#   (e) the DIFFERENT-LENS DIRECTIVE parenthetical class list names `deviations`.
#   (f) the fixer FIX_RESULT spawn prompt (Part 2 review-and-fix loop) carries `deviations` in its
#       output shape with the conditional-mandatory wording (a FIX_RESULT editing a test assertion
#       with no `test:` entry is incomplete).
#   (m) MUTATION CONTROL: delete the DEVIATIONS ADVISORY prompt line from a COPY of the skill; gate
#       the mutant on non-empty + differs-from-original; (a) against the mutant MUST fail. Without
#       this, (a) could be green while asserting nothing.
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

BRIEF_LINE_RE='^[[:space:]]*\*\*BRIEF-CONFORMANCE ADVISORY \('
DEVIATIONS_LINE_RE='^[[:space:]]*\*\*DEVIATIONS ADVISORY \('

# prompt_line_adjacent <file> — exit 0 iff the first non-blank line after the BRIEF-CONFORMANCE
# ADVISORY prompt line is the DEVIATIONS ADVISORY prompt line. Silent; used on the real skill AND
# on the mutant, so it must carry no ok/no side effects of its own.
prompt_line_adjacent() {
  # Literal prefix matching via index() on the whitespace-trimmed line — deliberately NOT a regex
  # handed in through `awk -v` (which escape-processes `\*` into `*` and breaks the pattern).
  awk '
    { t = $0; sub(/^[[:space:]]+/, "", t) }
    found_brief && t != "" {
      if (index(t, "**DEVIATIONS ADVISORY (") == 1) { hit = 1 }
      found_brief = 0
    }
    index(t, "**BRIEF-CONFORMANCE ADVISORY (") == 1 { found_brief = 1 }
    END { exit (hit ? 0 : 1) }
  ' "$1"
}

# deviations_prompt_line <file> — prints the DEVIATIONS ADVISORY prompt line (empty if absent)
deviations_prompt_line() { grep -E "$DEVIATIONS_LINE_RE" "$1" 2>/dev/null | head -1; }

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

# ---- (a) the spawn-prompt line, directly after BRIEF-CONFORMANCE ADVISORY --------------------------
if grep -qE "$BRIEF_LINE_RE" "$SKILL"; then
  ok "(a) BRIEF-CONFORMANCE ADVISORY prompt-line anchor present"
else
  no "(a) BRIEF-CONFORMANCE ADVISORY prompt-line anchor MISSING — the adjacency assertion has nothing to anchor on"
fi
if prompt_line_adjacent "$SKILL"; then
  ok "(a) DEVIATIONS ADVISORY line sits directly after the BRIEF-CONFORMANCE ADVISORY line"
else
  no "(a) DEVIATIONS ADVISORY line is not the next non-blank line after BRIEF-CONFORMANCE ADVISORY"
fi
line="$(deviations_prompt_line "$SKILL")"
case "$line" in
  *'include this line ONLY when `deviations_advisory` is non-empty'*) ok "(a) prompt line is gated on non-empty deviations_advisory" ;;
  *) no "(a) prompt line lacks the 'include ONLY when non-empty' gate" ;;
esac
case "$line" in
  *'`plan:`'*'`edge:`'*'`open:`'*'`test:`'*'`other:`'*) ok "(a) prompt line carries the plan:/edge:/open:/test: convention with the other: reading" ;;
  *) no "(a) prompt line lacks the four-prefix / other: convention" ;;
esac
case "$line" in
  *'contradicts a stated acceptance criterion'*) ok "(a) prompt line asks whether the deviation contradicts a stated criterion" ;;
  *) no "(a) prompt line does not ask the contradicts-a-criterion question" ;;
esac
case "$line" in
  *'NOT a finding'*) ok "(a) prompt line states a merely-unexpected deviation is NOT a finding" ;;
  *) no "(a) prompt line does not state the merely-unexpected carve-out" ;;
esac
case "$line" in
  *'`category: new`'*) ok "(a) prompt line names the category: new finding shape" ;;
  *) no "(a) prompt line lacks the category: new finding shape" ;;
esac
case "$line" in
  *'quoting BOTH the deviation and the contradicted criterion'*) ok "(a) prompt line requires quoting both the deviation and the contradicted criterion" ;;
  *) no "(a) prompt line does not require quoting both the deviation and the criterion" ;;
esac
case "$line" in
  *'never to a worker or fixer as an instruction'*) ok "(a) prompt line states the review-lens-only contract" ;;
  *) no "(a) prompt line does not state the review-lens-only contract" ;;
esac

# ---- (b) step 1g: sibling of 1c/1e/1f, per-iteration, reads fixer_deviations -----------------------
step1g="$(grep -E '^1g\. ' "$SKILL" | head -1)"
if [ -n "$step1g" ]; then
  ok "(b) Part 2 on-entry step 1g. exists"
else
  no "(b) Part 2 on-entry step 1g. MISSING"
fi
case "$step1g" in
  *'sibling to steps 1c/1e/1f'*) ok "(b) step 1g names itself a sibling of 1c/1e/1f" ;;
  *) no "(b) step 1g does not name itself a sibling of 1c/1e/1f" ;;
esac
case "$step1g" in
  *'RUNS ON EVERY ITERATION'*'not only the first'*) ok "(b) step 1g states it runs on every iteration, not only the first" ;;
  *) no "(b) step 1g does not state the per-iteration (not first-only) contract" ;;
esac
case "$step1g" in
  *'fixer_deviations'*) ok "(b) step 1g reads fixer_deviations" ;;
  *) no "(b) step 1g does not mention fixer_deviations" ;;
esac
case "$step1g" in
  *'## Worker Results'*) ok "(b) step 1g reads state.md's ## Worker Results" ;;
  *) no "(b) step 1g does not reference ## Worker Results" ;;
esac
case "$step1g" in
  *'the same cap Part 1 uses for `brief_conformance`'*) ok "(b) step 1g refers to the shared cap (does not restate the number)" ;;
  *) no "(b) step 1g does not refer to the shared brief_conformance cap" ;;
esac
case "$step1g" in
  *'VISIBLE'*'omitted-count marker'*) ok "(b) step 1g requires a VISIBLE truncation marker" ;;
  *) no "(b) step 1g does not require a visible truncation marker" ;;
esac

# Part 1's own "Deviations advisory" section exists and states the fail-safe skip conditions.
if grep -qF '## Deviations advisory (worker- and fixer-recorded plan drift)' "$SKILL"; then
  ok "(b) Part 1 §Deviations advisory section exists"
else
  no "(b) Part 1 §Deviations advisory section MISSING"
fi

# ---- (c) agents/code-reviewer.md mirror: Self-heal lens + dedicated Review Process subsection -----
if grep -qF 'deviations' "$REVIEWER" && grep -qF 'Self-heal lens' "$REVIEWER"; then
  selfheal_line="$(grep -F 'Self-heal lens' "$REVIEWER" | head -1)"
  case "$selfheal_line" in
    *'deviations'*) ok "(c) agents/code-reviewer.md Self-heal lens paragraph names deviations" ;;
    *) no "(c) agents/code-reviewer.md Self-heal lens paragraph does not name deviations" ;;
  esac
else
  no "(c) agents/code-reviewer.md lacks a Self-heal lens paragraph mentioning deviations"
fi
if grep -qE '^5b\. .*Deviations conformance' "$REVIEWER"; then
  ok "(c) agents/code-reviewer.md carries a dedicated 5b. Deviations conformance subsection"
else
  no "(c) agents/code-reviewer.md lacks a 5b. Deviations conformance subsection"
fi
devsec="$(awk '/^5b\. \*\*Deviations conformance/{flag=1} flag{print; if (/^6\. /) exit}' "$REVIEWER")"
case "$devsec" in
  *'DEVIATIONS ADVISORY'*) ok "(c) 5b. subsection names the DEVIATIONS ADVISORY line" ;;
  *) no "(c) 5b. subsection does not name the DEVIATIONS ADVISORY line" ;;
esac
case "$devsec" in
  *'other:'*) ok "(c) 5b. subsection mirrors the other: reading for unprefixed entries" ;;
  *) no "(c) 5b. subsection does not mirror the other: reading for unprefixed entries" ;;
esac

# ---- (d) the miss-class checklist names deviations ------------------------------------------------
cl_hits="$(awk '
  /^## Self-Heal Miss-Class Checklist/ { in_sec = 1; next }
  in_sec && /^## / { in_sec = 0 }
  in_sec && /`deviations`/ { n++ }
  END { print n + 0 }
' "$CHECKLIST")"
if [ "$cl_hits" -ge 1 ]; then
  ok "(d) Self-Heal Miss-Class Checklist names deviations"
else
  no "(d) Self-Heal Miss-Class Checklist does not name deviations"
fi

# ---- (e) the DIFFERENT-LENS DIRECTIVE parenthetical class list names deviations --------------------
lens_line="$(grep -F 'Self-Heal Miss-Class Checklist regardless of repo' "$SKILL" | head -1 || true)"
case "$lens_line" in
  *'`deviations`'*) ok "(e) DIFFERENT-LENS DIRECTIVE class list names deviations" ;;
  *) no "(e) DIFFERENT-LENS DIRECTIVE class list does not name deviations" ;;
esac

# ---- (f) the fixer FIX_RESULT spawn prompt carries deviations + the conditional-mandatory rule ----
fix_prompt="$(awk '/Emit FIX_RESULT block:/{print; exit}' "$SKILL")"
case "$fix_prompt" in
  *'deviations'*) ok "(f) fixer spawn prompt's FIX_RESULT output shape includes deviations" ;;
  *) no "(f) fixer spawn prompt's FIX_RESULT output shape does not include deviations" ;;
esac
case "$fix_prompt" in
  *'CONDITIONAL-MANDATORY'*) ok "(f) fixer spawn prompt states deviations is conditional-mandatory" ;;
  *) no "(f) fixer spawn prompt does not state the conditional-mandatory rule" ;;
esac
case "$fix_prompt" in
  *'edits a test assertion'*'no `test:` entry is incomplete'*) ok "(f) fixer spawn prompt states the test-assertion-edit-needs-a-test:-entry rule" ;;
  *) no "(f) fixer spawn prompt does not state the test-assertion-edit rule" ;;
esac
if grep -qF 'fixer_deviations += ' "$SKILL"; then
  ok "(f) the review-and-fix loop appends FIX_RESULT.deviations into fixer_deviations"
else
  no "(f) the review-and-fix loop does not append FIX_RESULT.deviations into fixer_deviations"
fi

# ---- (m) MUTATION CONTROL: (a) must go RED when the prompt line is deleted ------------------------
MUT="$(mktemp)"
trap 'rm -f "$MUT" 2>/dev/null' EXIT
sed -E "/${DEVIATIONS_LINE_RE}/d" "$SKILL" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$SKILL" "$MUT"; then
  ok "(m) mutant is non-empty and differs from the original (a valid mutant)"
  if prompt_line_adjacent "$MUT"; then
    no "(m) adjacency assertion (a) PASSED against the mutant — the assertion is vacuous"
  else
    ok "(m) adjacency assertion (a) fails against the mutant (the assertion is load-bearing)"
  fi
  if [ -z "$(deviations_prompt_line "$MUT")" ]; then
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
