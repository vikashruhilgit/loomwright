# 07 — Execute FABLE_PARITY_EVAL + extend to per-layer ablation arms

## Problem
`loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` pre-registers exactly the experiment both the north star (Bet 5) and a Bitter Lesson analysis of this harness demand — bare Claude Code vs Loomwright vs Loomwright+extras, 5 requirements × 3 arms, with the pre-committed rule "a layer that does not move its metric is removed, not defended. No third outcome." The results table is EMPTY. The discipline is declared, not exercised. Meanwhile a Bitter Lesson audit proposes large deletions (QA rule libraries ~1,900 lines, schema surface, phase machines, agent consolidation 14→4, magic-number budgets) as conclusions — but those are properly HYPOTHESES this eval must adjudicate. Complement to item 01: 01 is observational (existing churn data, cheap, correlational); this is experimental (causal, expensive).

## Goal
Run the pre-registered eval on the current model, extended with per-layer ablation arms, and honor the decision rule. Output: a filled results table + a per-layer keep/cut verdict that feeds items 03–05.

## Scope
1. **Run the base protocol as written** (5 requirements × 3 arms, 15-run hard cap, per-run rows filled at run time, no retroactive edits, refuted-finding surfacing checks). Do not weaken the pre-registration; amendments only additive and recorded.
2. **Add ablation arms (additive amendment, budgeted separately):** prioritize by suspected liability × cheapness to ablate — (a) minus QA rule libraries (qa-test-patterns/qa-gates/qa-strategy replaced by a ~50-line intent + existing ground-truth execution); (b) minus prompt-hook schema validators (outcome checks only: builds, tests pass, PR exists, files modified); (c) magic budgets/caps converted to soft defaults the model may override with stated reasoning; (d) minus phase-machine rigidity (phases as optional playbook: goal + tools + ground truth + state file). Each arm is ONE lever, not a bundle. If budget forces choosing, (a) and (c) first.
3. **Incident-derived guards are tested, not presumed:** completion-tail guard, PRE-FLIGHT SYNC, drift caps came from real incidents — an ablation that removes one must watch for the original incident class recurring, and a guard that still prevents it KEEPS (Bitter Lesson does not override empirical incident data).
4. **Institutionalize:** a short standing section in the SPIKE doc — re-run the ablation set on every major model release; a `model-capability` knob is a possible follow-up ONLY if ablation results show release-dependent verdicts (do not build it speculatively).
5. **Verdicts feed the backlog:** each CUT verdict becomes a follow-up requirement (aligning with item 05's propose-only discipline); each KEEP verdict is recorded with its metric so future audits stop re-litigating it.

## Non-goals
No deletions inside this item (verdicts only). No agent-consolidation arm in round 1 (highest blast radius, entangled with spawn-depth harness constraints — only justified if round-1 arms show large wins). No new metrics after the first run (pre-registration rule).

## Acceptance criteria
- Results table filled per protocol for all executed runs; hard cap respected (report partial if hit).
- Per-layer verdict table: KEEP (metric it moved) / CUT (follow-up stub written) / INSUFFICIENT DATA — no third outcome beyond the pre-registered rule.
- Incident-class regression check recorded for every ablated guard.
- Amendment history in the SPIKE doc; original protocol byte-preserved above it.

## Outcomes Rubric
- Base 3-arm eval executed and recorded
- ≥2 single-lever ablation arms executed
- Per-layer keep/cut verdicts with cited metrics
- Follow-up stubs for every CUT; no deletions performed here

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-07-24-parity-eval-prep.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
