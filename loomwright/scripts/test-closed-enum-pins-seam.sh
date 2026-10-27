#!/usr/bin/env bash
# test-closed-enum-pins-seam.sh — static seam test for brief-time closed-enumeration and pin-mutation
# coverage (automate-followups/27).
#
# Item 18 was implemented twice from one base, and both runs missed the same two things: a new
# escalation value left out of a CLOSED list that must name every value, and seam pins that stayed
# green when the code they pinned was deleted. The brief never asked for either. This change adds two
# conditional brief sections (`## Closed enumerations touched`, `## Pin mutations`), Launch Pad's
# Phase 3 action 12 that fills them, Plan Reviewer Criterion 19 that checks them, and a Phase 4.5
# code-reviewer step that runs the listed mutations in a scratch copy.
#
# Launch Pad, Plan Reviewer and the code reviewer are LLM prompts, so CI can only pin their TEXT; the
# behavioural proof is a LIVE Plan Reviewer probe on the committed fixtures under
# fixtures/closed-enum-pins/ (answer key: that directory's README.md). This test pins:
#   PART 1  the template: both sections, their "required only when they apply" rule, the sibling-grep
#           and the mutate-the-code-not-the-needle rules, and the Section Requirements line.
#   PART 2  Launch Pad Phase 3 action 12 + Phase 5 action 4d + the spawn's count-free criteria line, and
#           the command mirror (step 9, Phase 5 emission, count-free line, Criterion 19 and 21 gates).
#   PART 3  Plan Reviewer Criterion 19: gate, 19a/19b/19c, both categories, MEDIUM, the count at every
#           count surface, the output-format enum, and the schema doc; Criterion 21's skip clause,
#           MEDIUM severity and `module_layout` category.
#   PART 4  the code reviewer's pin-mutation step: EXECUTION DIRECTIVE gate, scratch copy, unmutated
#           run first, green-on-mutant => BLOCKING; since automate-speed/02 it reads the
#           run-pin-mutations.sh verdicts (PIN-MUTATION VERDICTS, DATA) and mutates by itself only for an
#           `unverified` row (the D1 fallback the scratch-copy needles now describe).
#   PART 5  fixture well-formedness: blind briefs (no verdict/label hints), section presence by role,
#           every anchor a section quotes is grep -F-findable in its file, the shown sibling grep's hit
#           FILES are exactly the files the complete brief lists, and the 19c condition holds in
#           brief-uncovered.md and nowhere else (decided mechanically here).
#   PART 6  mutation control: deleting Criterion 19's 19a sentence, the whole Criterion 19 block, or
#           Launch Pad's action 12 from a TEMP copy must make this test fail. Each mutant is gated on
#           non-empty + differs-from-original, and a positive control (unmutated temp copies) must
#           pass first, so a broken harness cannot report a false kill.
#
# EXPLICIT LIMIT: this pins WIRING and fixture shape. It cannot prove that a reviewer flags a brief, or
# that a Phase 4.5 reviewer runs a mutation — both are model behaviour, proven only by a live probe.
#
# Env overrides (PART 6's re-invocation only): SEAM_LP (agents/launch-pad.md), SEAM_PR
# (agents/plan-reviewer.md), SEAM_NO_MUTATION=1 (skip PART 6 in the child).
# bash 3.2 / BSD userland safe; paths from $BASH_SOURCE so it runs from any CWD.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
LP="${SEAM_LP:-$PLUGIN/agents/launch-pad.md}"
PR="${SEAM_PR:-$PLUGIN/agents/plan-reviewer.md}"
CR="$PLUGIN/agents/code-reviewer.md"
LPC="$PLUGIN/commands/launch-pad.md"
SKILL="$PLUGIN/skills/supervisor-readiness/SKILL.md"
SCHEMA="$PLUGIN/docs/result-schemas/plan-review-result.md"
FIX="$HERE/fixtures/closed-enum-pins"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
has()   { grep -qF -- "$2" "$1"; }                     # has <file> <literal>
lacks() { ! grep -qF -- "$2" "$1"; }
# block <file> <start-ERE> <stop-ERE> — lines from the first start match up to (not incl.) stop.
block() { BLK_A="$2" BLK_B="$3" awk 'f && $0 ~ ENVIRON["BLK_B"] {exit} $0 ~ ENVIRON["BLK_A"] {f=1} f' "$1"; }
bhas() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }   # bhas <text> <literal>

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

for f in "$LP" "$PR" "$CR" "$LPC" "$SKILL" "$SCHEMA"; do [ -s "$f" ] || no "missing or empty: $f"; done

echo "PART 1 — brief template (supervisor-readiness)"
CET="$(block "$SKILL" '^## Closed enumerations touched$' '^## Pin mutations$')"
PMT="$(block "$SKILL" '^## Pin mutations$' '^## Subtask Structure$')"
[ -n "$CET" ] && ok "template: ## Closed enumerations touched" || no "template: Closed enumerations section missing"
[ -n "$PMT" ] && ok "template: ## Pin mutations (before ## Subtask Structure)" || no "template: Pin mutations section missing"
TFI="$(block "$SKILL" '^## Touched-file invariants$' '^## Closed enumerations touched$')"
bhas "$TFI" '**Authoring rules (Launch Pad Phase 3 action 11' && ok "template: sections sit after Touched-file invariants" \
  || no "template: section order (Touched-file invariants -> Closed enumerations -> Pin mutations)"
bhas "$CET" '> Sibling grep at base `{sha}`: `grep -rnF' && ok "template: shows the sibling grep command" || no "template: sibling grep line"
bhas "$PMT" '**Authoring rules (Launch Pad Phase 3 action 12; Plan Reviewer Criterion 19):**' \
  && ok "template: rules tie action 12 + Criterion 19" || no "template: authoring-rules header"
bhas "$PMT" 'Neither applies → omit both — no heading, no "none" line.' && ok "template: required only when they apply" \
  || no "template: omit-when-not-applicable rule"
bhas "$PMT" '`grep -rnF` at least one existing sibling value repo-wide' && ok "template: sibling grep is mechanical" \
  || no "template: sibling grep rule"
bhas "$PMT" "never the pin's own needle" && ok "template: mutate the code, not the needle" || no "template: needle rule"
bhas "$PMT" 'a pin that stays green on its mutant is BLOCKING' && ok "template: green-on-mutant is BLOCKING" \
  || no "template: Phase 4.5 consequence"
has "$SKILL" '`Closed enumerations touched` and `Pin mutations` (conditionally required' \
  && ok "Section Requirements names both sections" || no "Section Requirements line"

echo "PART 2 — Launch Pad + command mirror"
A12="$(block "$LP" '^12\. \*\*Closed enumerations and pin mutations' '^\*\*Output:\*\*')"
[ -n "$A12" ] && ok "launch-pad: Phase 3 action 12 present" || no "launch-pad: action 12 block not found"
bhas "$A12" '`grep -rnF` an existing sibling value of the same kind repo-wide' && ok "action 12: sibling grep" \
  || no "action 12: sibling grep clause"
bhas "$A12" 'joins the File Impact Map' && ok "action 12: closed lists join the File Impact Map" || no "action 12: impact-map clause"
bhas "$A12" 'Plan Reviewer Criterion 19' && bhas "$A12" '§"Closed enumerations touched" and §"Pin mutations"' \
  && ok "action 12 ties template + Criterion 19" || no "action 12: template/criterion pointers"
bhas "$A12" 'Neither applies → skip silently and emit neither section.' && ok "action 12: skip when neither applies" \
  || no "action 12: skip clause"
has "$LP" '4d. **Closed enumerations / pin mutations (conditional, from Phase 3 action 12):**' \
  && ok "launch-pad: Phase 5 action 4d emits the sections" || no "launch-pad: Phase 5 emission"
SPAWN="$(block "$LP" '^\*\*Spawn contract:\*\*' '^\*\*Output:\*\*')"
bhas "$SPAWN" 'Check every review criterion.' && ok "spawn: count-free criteria line" || no "spawn criteria line"
lacks "$LP" 'Check all 19 review criteria' && lacks "$LP" 'Check all 20' && ok "launch-pad: no stale 'Check all 19/20'" \
  || no "stale 'Check all 19/20' in launch-pad"
has "$LPC" '9. Closed enumerations and pin mutations (conditional' && ok "command mirror: Phase 3 step 9" || no "command mirror step 9"
has "$LPC" 'When Phase 3 step 9 ran, emit' && ok "command mirror: Phase 5 emission" || no "command mirror Phase 5 emission"
has "$LPC" 'checks every review criterion' && lacks "$LPC" 'checks all 19 criteria' && lacks "$LPC" 'all 20 criteria' \
  && ok "command mirror: count-free criteria line" || no "command mirror criteria count"
has "$LPC" 'Criterion 21 runs only when a MODIFY path is at or past the §"Module layout" threshold' \
  && ok "command mirror: Criterion 21 gate" || no "command mirror Criterion 21 gate"
has "$LPC" 'Criterion 19 runs only when the brief adds an enum value or a test pin' && ok "command mirror: Criterion 19 gate" \
  || no "command mirror Criterion 19 gate"

echo "PART 3 — Plan Reviewer Criterion 19"
C19="$(block "$PR" '^### 19\. Closed Enumerations and Pin Mutations' '^(### 20\. |## Decision Matrix)')"
[ -n "$C19" ] && ok "### 19. Closed Enumerations and Pin Mutations present" || no "Criterion 19 block not found"
bhas "$C19" 'Neither → skip silently.' && ok "19: skip clause" || no "19 skip clause"
bhas "$C19" '**19a — enumerations.** A new value and no `## Closed enumerations touched` entry for it.' \
  && ok "19a: missing section/entry" || no "19a condition"
bhas "$C19" '`Grep` the entry'"'"'s sibling value yourself' && ok "19a: reviewer re-runs the sibling grep" || no "19a own-grep clause"
bhas "$C19" '**19b — pins.** A new or changed pin and no `## Pin mutations` row for it' && ok "19b: missing row" || no "19b condition"
bhas "$C19" "edits the pin's own needle" && ok "19b: needle-only mutation is a finding" || no "19b needle clause"
bhas "$C19" '**19c — coverage.**' && bhas "$C19" 'in neither the File Impact Map nor any `lanes:`' && ok "19c: coverage vs touch set" \
  || no "19c condition"
bhas "$C19" '**Issue category:** `closed_enumerations` for 19a and 19c; `pin_mutations` for 19b.' && ok "19: categories" \
  || no "19 categories"
bhas "$C19" '**Severity if failed:** MEDIUM for 19a, 19b and 19c' && ok "19: MEDIUM" || no "19 severity"
has "$PR" '## 21 Review Criteria' && lacks "$PR" '## 20 Review Criteria' && has "$PR" 'All 21 review criteria must be checked' \
  && has "$PR" '(21 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, and 21 conditional)' && has "$PR" 'All 21 criteria checked' \
  && ok "criteria count 21 at heading / never-skip / matrix / checklist" || no "criteria count surfaces"
C21="$(block "$PR" '^### 21\. Module Layout \(conditional\)$' '^(---|## Decision Matrix)')"
[ -n "$C21" ] && ok "### 21. Module Layout (conditional) present" || no "Criterion 21 block not found"
bhas "$C21" 'no MODIFY path is at or past the threshold → skip silently.' && ok "21: skip clause" || no "21 skip clause"
bhas "$C21" '**Severity if failed:** MEDIUM (the decision stays PASS' && ok "21: MEDIUM, decision stays PASS" || no "21 severity"
bhas "$C21" '**Issue category:** `module_layout`.' && ok "21: category" || no "21 category"
has "$PR" 'Criterion 19 is conditional: skip silently when the brief adds no enum value and no test pin.' \
  && ok "intro paragraph names Criterion 19's gate" || no "intro paragraph gate"
has "$PR" '| touched_file_invariants | closed_enumerations | pin_mutations |' && ok "output-format enum lists both categories" \
  || no "output-format category enum"
has "$SCHEMA" '`closed_enumerations` / `pin_mutations` for Criterion 19' && ok "schema doc: both categories" || no "schema doc categories"

echo "PART 4 — code reviewer: pin mutations at Phase 4.5"
PMR="$(grep -F -- '**Pin mutations (same EXECUTION DIRECTIVE gate).**' "$CR" | head -1)"
[ -n "$PMR" ] && ok "code-reviewer: pin-mutation paragraph present" || no "code-reviewer: pin-mutation paragraph missing"
bhas "$PMR" 'archive HEAD | tar -x -C "$SCRATCH/tree"' && ok "pin mutations run in a scratch copy" || no "scratch copy clause"
bhas "$PMR" 'run the row'"'"'s pin once unmutated' && ok "unmutated run first (positive control)" || no "unmutated-first clause"
bhas "$PMR" '**Green on its mutant ⇒ a BLOCKING `new` finding**' && ok "green on mutant => BLOCKING" || no "BLOCKING clause"
# automate-speed/02: the script runs the rows; the reviewer reads its verdicts as DATA and mutates by
# itself only for an `unverified` row (the D1 fallback the three needles above now describe).
bhas "$PMR" 'the PIN-MUTATION VERDICTS block (DATA)' && bhas "$PMR" 'A `not_held` line ⇒ one BLOCKING `new` finding quoting it' \
  && ok "reviewer consumes the PIN-MUTATION VERDICTS block as DATA" || no "PIN-MUTATION VERDICTS clause"
bhas "$PMR" 'Apply a mutation yourself ONLY for a row the script reported `unverified` (the D1 fallback)' \
  && ok "reviewer runs a mutation only for an unverified row (D1)" || no "D1 fallback clause"

echo "PART 5 — fixtures"
for f in README.md brief-plain.md brief-bare.md brief-complete.md brief-uncovered.md; do
  [ -s "$FIX/$f" ] && ok "fixture present: $f" || no "fixture missing/empty: $f"
done
# Blind fixtures: a live probe passes brief content only, so no brief may name its verdict, the criterion it
# exercises, or this test (a live probe showed a reviewer WITHOUT Criterion 19 applying it from such a hint).
HINTS='expect|closed_enumerations|pin_mutations|criterion|19a|19b|19c|closed-enum|answer key'
for b in plain bare complete uncovered; do
  if grep -qiE -- "$HINTS" "$FIX/brief-$b.md"; then
    no "brief-$b.md leaks a hint (/$HINTS/i): $(grep -niE -- "$HINTS" "$FIX/brief-$b.md" | head -n1)"
  else
    ok "brief-$b.md carries no verdict/label hint"
  fi
done
T_B="$(grep -m1 '^# Supervisor Job:' "$FIX/brief-bare.md")"
[ -n "$T_B" ] && [ "$T_B" = "$(grep -m1 '^# Supervisor Job:' "$FIX/brief-complete.md")" ] \
  && [ "$T_B" = "$(grep -m1 '^# Supervisor Job:' "$FIX/brief-uncovered.md")" ] \
  && ok "the three enum briefs share one title" || no "enum brief titles differ"
# Section presence by role.
for b in plain bare; do
  lacks "$FIX/brief-$b.md" '## Closed enumerations touched' && lacks "$FIX/brief-$b.md" '## Pin mutations' \
    && ok "brief-$b: neither section" || no "brief-$b carries a Criterion 19 section"
done
for b in complete uncovered; do
  has "$FIX/brief-$b.md" '## Closed enumerations touched' && has "$FIX/brief-$b.md" '## Pin mutations' \
    && ok "brief-$b: both sections" || no "brief-$b lacks a Criterion 19 section"
done
PFIM="$(block "$FIX/brief-plain.md" '^### File Impact Map$' '^## Subtask Contracts$')"
[ -n "$PFIM" ] && ! bhas "$PFIM" 'test-' && lacks "$FIX/brief-plain.md" 'rules_gate_' \
  && ok "brief-plain: no test file, no enum value (the unchanged path)" || no "brief-plain names a test or an enum value"
has "$FIX/brief-bare.md" '`rules_gate_unreadable`' && has "$FIX/brief-bare.md" '`loomwright/scripts/test-rules-gate-seams.sh`' \
  && ok "brief-bare: a new value and a pinned test (Criterion 19's gate fires)" || no "brief-bare does not trigger the gate"
# Every anchor the Criterion 19 fixtures quote must still be in the file they name (fixture rot guard).
SHA="$REPO/loomwright/skills/self-heal-advisory/SKILL.md"
SHA_TAIL="$REPO/loomwright/skills/self-heal-advisory/completion-tail.md"   # automate-speed/15: completion tail split out
has "$SHA_TAIL" '**Heal reason:** {needs_human|' && ok "anchor: Heal reason closed list" || no "anchor gone: Heal reason list"
has "$SHA" 'record_decision(phase: SELF_HEAL, decision: "rules_gate_unresolved"' && ok "anchor: sibling escalation leg" \
  || no "anchor gone: sibling record_decision"
for a in '**The verdict decides; the line reports.**' \
         'if rules.verdict not in RULES_PASSABLE and rules.verdict != "fail":'; do
  has "$SHA" "$a" && ok "anchor: $a" || no "anchor gone from self-heal-advisory: $a"
done
for a in 'also pre-increment' '**Rules-check replay line' 'already escalated with'; do
  has "$SHA_TAIL" "$a" && ok "anchor: $a" || no "anchor gone from self-heal-advisory completion-tail.md: $a"
done
has "$REPO/loomwright/scripts/test-rules-gate-seams.sh" 'PINS="' && ok "anchor: PINS line" || no "anchor gone: PINS line"
# The sibling grep the complete brief shows: its hit FILES must be exactly the files the entry lists.
SHOWN="$(grep -F -- '> Sibling grep at base' "$FIX/brief-complete.md" | head -1)"
bhas "$SHOWN" "grep -rnF 'rules_gate_unresolved' --exclude=CHANGELOG.md loomwright" && ok "complete: shows its sibling grep" \
  || no "complete: sibling grep line"
# The fixtures and this test name the sibling too; at the fixture's notional base they did not exist.
# docs/loop-inventory/ (AS-04) quotes the authoritative prose verbatim — a derived restatement, like
# CHANGELOG.md, not a site that implements the enum — and also post-dates the fixture's base.
HITS="$(cd "$REPO" && grep -rlF 'rules_gate_unresolved' --exclude=CHANGELOG.md --exclude-dir=closed-enum-pins \
  --exclude-dir=loop-inventory --exclude=test-closed-enum-pins-seam.sh loomwright 2>/dev/null | sort -u)"
LISTED="$(block "$FIX/brief-complete.md" '^## Closed enumerations touched$' '^## Pin mutations$' \
  | sed -n 's/^  - `\([^`]*\)` — .*/\1/p' | sort -u)"
[ -n "$HITS" ] && [ "$HITS" = "$LISTED" ] && ok "complete: listed files == the sibling grep's hit files" \
  || no "complete: listed files drifted from the grep (hits: $(echo $HITS) | listed: $(echo $LISTED))"
# 19c decided mechanically: every `— extend` row's path must be in the File Impact Map or a lanes: entry.
uncovered_rows() {
  sec="$(block "$1" '^## Closed enumerations touched$' '^## Pin mutations$')"
  touch="$(block "$1" '^### File Impact Map$' '^## Subtask Contracts$'; block "$1" '^lanes:$' '^external_requires:')"
  printf '%s\n' "$sec" | grep -F -- '— extend' | sed -n 's/^  - `\([^`]*\)` — .*/\1/p' | while IFS= read -r p; do
    case "$touch" in *"$p"*) ;; *) echo "$p" ;; esac
  done
}
[ -z "$(uncovered_rows "$FIX/brief-complete.md")" ] && ok "complete: every extend row is in its touch set" \
  || no "complete has an uncovered extend row: $(uncovered_rows "$FIX/brief-complete.md")"
U="$(uncovered_rows "$FIX/brief-uncovered.md")"
[ "$U" = "loomwright/skills/review-heal/SKILL.md" ] && ok "uncovered: exactly review-heal is outside its touch set (19c)" \
  || no "uncovered: expected exactly review-heal uncovered, got '$U'"
# Pin-mutation rows name the code, never the pin file itself, as the thing to mutate.
for b in complete uncovered; do
  bad="$(block "$FIX/brief-$b.md" '^## Pin mutations$' '^## Subtask Structure$' | grep -E '^\| `' | grep -E '\| [^|]*test-rules-gate-seams\.sh[^|]*\|$' || true)"
  [ -z "$bad" ] && ok "brief-$b: every mutation targets the code, not the pin file" || no "brief-$b mutates the pin file: $bad"
done
RM="$FIX/README.md"
row() { grep -F -- "| \`$1\` |" "$RM" 2>/dev/null; }
bhas "$(row brief-plain.md)" 'none: no `closed_enumerations` or `pin_mutations` issue' \
  && ok "README: plain => none" || no "README plain row"
bhas "$(row brief-bare.md)" '19a MEDIUM `closed_enumerations`' && bhas "$(row brief-bare.md)" '19b MEDIUM `pin_mutations`' \
  && ok "README: bare => 19a + 19b" || no "README bare row"
bhas "$(row brief-complete.md)" 'none: both sections present' && ok "README: complete => none" || no "README complete row"
bhas "$(row brief-uncovered.md)" '19c MEDIUM `closed_enumerations`' && ok "README: uncovered => 19c" || no "README uncovered row"

if [ "${SEAM_NO_MUTATION:-0}" != "1" ]; then
  echo "PART 6 — mutation control"
  cp "$LP" "$WORK/lp.md"; cp "$PR" "$WORK/pr.md"
  child() { SEAM_NO_MUTATION=1 SEAM_LP="$1" SEAM_PR="$2" bash "$HERE/test-closed-enum-pins-seam.sh" >/dev/null 2>&1; }
  if child "$WORK/lp.md" "$WORK/pr.md"; then ok "positive control: unmutated temp copies pass"
  else no "positive control failed — mutation results would be meaningless"; fi
  awk '!/^- \*\*19a — enumerations\.\*\*/' "$WORK/pr.md" > "$WORK/pr19a-m.md"
  awk 'f && /^(### 20\. |## Decision Matrix)/ {f=0} /^### 19\. / {f=1} !f' "$WORK/pr.md" > "$WORK/pr19-m.md"
  awk 'f && /^\*\*Output:\*\*/ {f=0} /^12\. \*\*Closed enumerations/ {f=1} !f' "$WORK/lp.md" > "$WORK/lp12-m.md"
  for m in pr19a-m pr19-m lp12-m; do
    case "$m" in pr*) src=pr ;; *) src=lp ;; esac
    if [ ! -s "$WORK/$m.md" ]; then no "mutant $m is empty"; continue; fi
    if cmp -s "$WORK/$m.md" "$WORK/$src.md"; then no "mutant $m is identical to its original"; continue; fi
    if [ "$src" = pr ]; then child "$WORK/lp.md" "$WORK/$m.md"; else child "$WORK/$m.md" "$WORK/pr.md"; fi
    [ $? -ne 0 ] && ok "mutant $m is killed" || no "mutant $m survived"
  done
fi

echo
echo "test-closed-enum-pins-seam.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
