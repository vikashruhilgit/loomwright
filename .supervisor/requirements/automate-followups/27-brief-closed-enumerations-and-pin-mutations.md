# 27 — Briefs name the closed enumerations they extend and prove each new test pin with a mutation

## Status: pending

## Problem
Item 18 (`automate-followups/18-fail-to-unstamped-escalates.md`) was implemented twice from the same base in S1
(v1 lane B → #371; v2 lane v2-b → #372, merged). **Both independent runs missed the same two things**, and both
times only the review lens caught them:
1. **A closed enumeration not extended.** The new escalation value `rules_fail_then_unstamped` (and the existing
   `rules_gate_unresolved`) was missing from the closed `**Heal reason:**` list in self-heal-advisory's brief Outcome,
   the requirement close-out and `RESULT_SCHEMAS.md`.
2. **Test pins that pass when the code is broken.** In scratch copies, deleting the `rules_failed_seen: added`
   decision line, or flipping ESCALATED to PASS in the new Phase 4.5 leg, still passed all 22 seam tests (v2); v1's
   P9/P10 pins likewise did not pin the `rules_fail_seen +=` lines.
Two runs missing the same things is a blind spot in the brief, not chance: nothing in the brief template asks
"which closed lists does this new value belong to?" or "show each new pin failing on a mutant".

## Goal
A brief that introduces a new enum value lists every closed enumeration that must carry it, and a brief that adds
test pins names, for each, the mutation that must make it fail. Plan Review checks both, and Phase 4.5 can verify them.

## Scope
1. **Brief template** (`skills/supervisor-readiness/SKILL.md`): two short sections, required only when they apply:
   - `## Closed enumerations touched`: each new enum or status value, plus every closed list that must name it, found
     by a repo-wide grep of a sibling value (the brief shows the grep and its hits);
   - `## Pin mutations`: for each new or changed test pin, the one-line mutation (delete line X / flip value Y) that
     must turn it red.
2. **Launch Pad** fills both from its codebase analysis; the grep for sibling values is mechanical.
3. **Plan Review** (`agents/plan-reviewer.md`): a brief that adds an enum value without the first section, or adds
   pins without the second, gets a MEDIUM finding; a listed closed list that the brief's Touches does not cover gets
   a MEDIUM finding.
4. **Phase 4.5** may run the listed mutations in a scratch copy (the executing lens already does scratch repros,
   `agents/code-reviewer.md` §5); a pin that stays green on its mutant is a BLOCKING finding.
5. **Tests / fixtures:** a fixture brief adding a value to a known closed list without the section ⇒ Plan Review
   fixture flags it; with the section ⇒ clean.

## Non-goals
- No automatic mutation testing framework; the mutations are the brief author's named one-liners.

## Acceptance criteria
- Replaying item 18's brief through Plan Review flags both blind spots before any code is written.

## Validation (must pass before merge)
1. Baseline full loop, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Unchanged path: a brief with no new enum values and no pins needs neither section (fixture).
3. Running system: paste Plan Review's findings on item 18's original brief with this change.
4. A failure this must catch: drop the Plan Review check ⇒ the fixture passes when it must flag.
5. Rollback: `git revert`.

## Evidence
S1 run record, relay 7 (v2) and relay 4 (v1); PRs #371 (closed) and #372 (merged).

## Depends on
none

## Touches
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/agents/plan-reviewer.md
loomwright/agents/launch-pad.md
loomwright/agents/code-reviewer.md
changelog.d/automate-followups-27-brief-closed-enumerations-and-pin-mutations.md
