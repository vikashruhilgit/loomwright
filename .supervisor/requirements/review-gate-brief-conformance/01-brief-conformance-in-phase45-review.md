# 01 — Brief conformance in the Phase 4.5 gating review

## Problem
The Phase 4.5 Code Reviewer is the only LLM lens whose verdict gates the PR (`heal_decision` derives solely
from its `CODE_REVIEW_RESULT`), and its spawn prompt in `skills/self-heal-advisory/SKILL.md` §"Review-and-fix
loop" carries `BASE_BRANCH`, the diff target, and two advisory enrichment lines (PRIOR-CHURN, HOUSE-RULES) —
**no brief path and no acceptance criteria**. It answers "is this well-built?", never "is this what was asked
for?". The brief-vs-diff comparison that does exist (Rubric Grader, ground truth) is advisory on `/supervisor`,
so a diff that cleanly implements the wrong or partial thing reaches the human as `heal_decision: PASS` with a
low `rubric_score` nobody acts on. Surfaced by an external review on 2026-09-13 (see 00-overview §Origin).

## Goal
The gating reviewer receives the brief's acceptance criteria (and rubric bullets when present) as one bounded
enrichment line, and an acceptance criterion the integrated diff does not address becomes an ordinary
finding that the existing fix loop already consumes. No new gate, no new schema field.

## Scope
1. **Pre-review enrichment step 1f — `brief_conformance`** in `skills/self-heal-advisory/SKILL.md` Part 2,
   sibling to 1c (prior_churn) and 1e (house_rules), run at Phase 4.5 entry BEFORE the first reviewer spawn:
   - Source = the in-progress brief at `brief_path` (the same path `run-ground-truth.sh --brief` and
     `parse_rubric` already use). Collect every leading-`-` bullet under `## Acceptance Criteria`, plus every
     bullet under `## Outcomes Rubric` when that section exists (parse each section up to the next `## `
     heading — the rubric parser's existing rule).
   - **Bounded:** cap at 25 bullets total, criteria first; when truncated, append one line
     `(+N criteria omitted — see brief)` so the reviewer knows the list is partial.
   - **Skip silently** when there is no brief (`direct /supervisor task:` without Launch Pad — the same
     back-compat case the completion tail already handles), when the brief has no `## Acceptance Criteria`
     section, or when zero bullets parse. Empty `brief_conformance` ⇒ the prompt line is omitted entirely,
     exactly like the two existing enrichments.
2. **BRIEF-CONFORMANCE prompt line** in the reviewer spawn prompt, placed directly after HOUSE-RULES ADVISORY
   and shaped like it (`include this line ONLY when brief_conformance is non-empty; omit entirely when empty`):
   the reviewer must, for each listed criterion, decide `addressed | not_addressed | cannot_determine` from
   the diff, and emit one finding per `not_addressed` criterion with `category: new`, severity **HIGH**,
   the criterion text quoted verbatim in `description`, and in `suggestion` what is missing. `cannot_determine`
   (criterion is runtime-only, e.g. "p95 latency < 200ms") is reported in a one-line summary, NOT as a finding
   — this keeps the fix loop from chasing unfalsifiable bullets. **Rubric bullets never produce findings**
   (they stay the Rubric Grader's lane, R1); they are passed as orientation only, labelled as such in the line.
3. **Fix-loop consumption — no change required, but VERIFY:** the fix task already selects
   `category=new + severity>=HIGH`, so a `not_addressed` finding is picked up as-is. Confirm the fix prompt's
   step 5 ("Do NOT address findings outside the listed classes") does not exclude it, and that "Fix the
   CLASS" (step 1a) reads sensibly for a conformance finding (the class is the criterion; document that in
   one sentence in the fix prompt).
4. **Mirror in `agents/code-reviewer.md`:** add the conformance rule to the reviewer's own method section
   (the agent must know the three-way verdict and the HIGH/`new` mapping even when spawned outside Phase 4.5
   with a criteria list pasted in). Keep the spawn prompt in the skill the authoritative wording; the agent
   file describes the behaviour, not a second copy of the list.
5. **Self-Heal Miss-Class Checklist:** add `brief_conformance` (the diff does not address a stated criterion)
   as a miss-class in the DIFFERENT-LENS DIRECTIVE, so repeated iterations do not drop it.
6. **Seam test — `loomwright/scripts/test-brief-conformance-seam.sh`:** grep-gate that (a) the skill's spawn
   prompt contains the BRIEF-CONFORMANCE line adjacent to HOUSE-RULES, (b) step 1f exists with the 25-bullet
   cap and the three skip conditions spelled out, (c) `agents/code-reviewer.md` names `not_addressed` and the
   HIGH/`new` mapping, (d) the miss-class checklist names `brief_conformance`. Mutation control: delete the
   prompt line → (a) must fail. Register the new suite wherever the CI loop enumerates `test-*.sh`.
7. **Budgets + docs:** `check-token-budget.sh` — the code-reviewer prompt grows by the criteria list; re-measure
   and bump `docs/prompt-token-budgets.json` + the `ARCHITECTURE_CONTRACTS.md` mirror row in the same change.
   One CHANGELOG bullet under the release entry; `docs/HOOKS.md` untouched (no hook changes).

## Non-goals
- No change to `heal_decision` derivation; rubric / ground_truth / contract_conformance stay advisory (R1).
- Standalone `/review-pr` / `review-heal` gets nothing here — no brief exists for a bare PR URL (R4).
- No `RESULT_SCHEMAS.md` change: findings reuse the v3 `category`/severity fields; no new block field.
- Not a replacement for the Rubric Grader; rubric bullets are orientation only in this line.

## Acceptance criteria
- Given an in-progress brief with 3 acceptance criteria and a feature branch whose diff addresses two of them,
  the Phase 4.5 reviewer's `CODE_REVIEW_RESULT` contains exactly one `category: new`, severity HIGH finding
  quoting the third criterion verbatim, and the first fix iteration's prompt lists it.
- Given a brief with a runtime-only criterion, no finding is emitted for it; the reviewer output names it
  under `cannot_determine`.
- Given `/supervisor task:"..."` with no brief, the reviewer spawn prompt contains no BRIEF-CONFORMANCE line
  (state-trace this path — it must not error on a missing `brief_path`).
- Given a brief with 40 criteria, the line carries 25 and the `(+15 criteria omitted — see brief)` marker.
- `test-brief-conformance-seam.sh` passes; deleting the BRIEF-CONFORMANCE line from the skill fails it.
- `check-token-budget.sh` and `check-doc-currency.sh` green; full `test-*.sh` loop green before push
  (memory `run-full-ci-suite-loop-before-push`).

## Evidence to record on close-out
Paste the first real Phase 4.5 `CODE_REVIEW_RESULT` (or the fixture run) showing a `not_addressed` finding, and
the fix-iteration commit that addressed it.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-13T04:51:04Z
- **Brief:** .supervisor/jobs/done/2026-09-13-brief-conformance-phase45-review.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/215
