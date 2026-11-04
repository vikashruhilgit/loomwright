# Stop asking about summary dismissed-finding drafts

## Status: pending

**Story: Stop asking about summary dismissed-finding drafts** (type: story)

**As a** plugin owner answering `/automate` questions at PICK and at the park,
**I want** to be asked only about dismissed findings that might change the PR,
**so that** I spend turns and attention only on questions where my answer changes something.

## Problem

Every item's below-threshold dismissed findings (LOW severity, nits) go into one summary draft
(`…--dismissed-summary*.md`). The owner is asked about it with gate `AUT-SUMMARY` (Keep summary / Drop summary), both
in the PICK-time pending ask and in the park decision step. Fix-now is never offered for a summary. In practice the
answer is nearly always Keep, so the question costs a turn of an already large session and changes nothing.

## Evidence (decision ledgers `.supervisor/automate/*.dismissed-decisions`, read 2026-11-03)

| Repo | Draft kind | follow-up | drop | fix-now |
|---|---|---|---|---|
| loomwright-studio | summary | 115 | 5 | 0 |
| loomwright-studio | per-finding | 132 | 38 | 27 (14%) |
| ai-agent-manager | summary | 70 | 4 | 0 |
| ai-agent-manager | per-finding | 147 | 35 | 52 (22%) |

Summary drafts were kept 185 of 194 times. In loomwright-studio summary questions were 120 of 317 asks. Per-finding
questions do change outcomes (14–22% fix-now) and must stay.

## Goal

A summary draft is recorded `follow-up` by the script when it is written, with no question, so it never reaches
the PICK-time pending ask or the park decision step. Per-finding drafts are asked exactly as today.

## Scope

- When `automate-helpers.sh dismissed-drafts` (`scripts/automate-dismissed.sh`) writes or rewrites a summary draft,
  it also records that draft `follow-up` in `<run_id>.dismissed-decisions` (the same ledger row and draft rewrite
  `dismissed-decide … follow-up` produces) and writes one `## Progress` line saying the summary was kept
  automatically.
- `dismissed-pending` no longer counts a summary draft, so neither the PICK-time ask nor the park decision step
  emits an `AUT-SUMMARY` question.
- The summary-slot rules stay correct: a decided summary still covers exactly the entries its `summary-member` rows
  name, and below-threshold entries a later drain adds go into the next slot and are themselves kept automatically.
- Dropping stays possible without a question: the owner deletes the draft from `proposed/` (state that in
  `per-item-loop.md`'s decision-step text and in `proposed/README.md` if it describes the summary ask).
- Every surface that describes the `AUT-SUMMARY` ask is updated in the same change: `skills/automate-loop/per-item-loop.md`,
  `docs/result-schemas/automate-run.md`, the driver header comment in `scripts/automate-next-step.sh`,
  `docs/LANE_GATES.md` if it lists the gate.

## Non-goals

- Changing the drafting threshold (which findings get their own draft vs go into the summary).
- Changing the per-finding ask (`AUT-DISMISS`), its options, or fix-now handling.
- Changing `--non-interactive-fallback` behaviour beyond the summary now being decided rather than left undecided.
- Changing CI `claude-review` triggers, the `fix_floor` default, or the Phase 4.5 executing-lens scope.

## Owner decisions (2026-11-03)

- Summary drafts default to keep without a question. Per-finding drafts keep the full fix-now / follow-up / drop
  decision.

## Acceptance criteria

**Happy path:**
- [ ] Given a drain whose dismissed findings include below-threshold items, when `dismissed-drafts` runs, then the
      summary draft exists in `proposed/` with `Decision: follow-up`, the ledger has a `follow-up` row for it, and
      `## Progress` has one line naming it (test in the automate-dismissed tests).
- [ ] Given that state, when the driver reaches the park decision step and the next PICK, then no `AUT-SUMMARY` ask
      is emitted (driver test in `scripts/test-automate-next-step*.sh`).
- [ ] Given a per-finding draft over the threshold in the same item, when the decision step runs, then the
      `AUT-DISMISS` ask is still emitted with its options unchanged.

**Edge cases:**
- [ ] Given an item with only below-threshold findings, when the decision step runs, then no question is asked and
      `dismissed-pending` reports zero for that item.
- [ ] Given a second drain on the same item that adds new below-threshold findings, when `dismissed-drafts` runs,
      then they land in the next summary slot, which is also kept automatically, and the earlier summary's members
      are unchanged.
- [ ] Given a run started before this change with an undecided summary draft already in `proposed/`, when the next
      PICK runs, then that draft is recorded `follow-up` without a question (no orphaned AUT-SUMMARY ask on resume).
- [ ] Given the owner deletes a kept summary draft from `proposed/`, when the next `dismissed-drafts` runs, then it
      does not recreate it (decisions are never reset; the existing rule).

**Error scenarios:**
- [ ] Given the ledger write fails, when `dismissed-drafts` runs, then it still exits 0 (its fail-safe contract) and
      the summary stays undecided, so the existing `AUT-SUMMARY` ask is the fallback rather than a lost draft.

## Validation (must pass before merge)

- `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh` (budget entries updated if
  `skills/automate-loop/` changes size), `check-doc-currency.sh` and `check-prompt-history-refs.sh`.
- `bash scripts/check-version-bump.sh` passes; the PR carries a `changelog.d/` fragment and no hand-edited version.

### Priority
- [x] Phase 2 - Important but not blocking launch

**Rationale:** it removes roughly a third of dismissed-finding questions, but each question is cheap next to a
full item run (about 80M tokens per item at the fix floor MEDIUM baseline).

### Assumptions
- An earlier owner rule says each dismissed finding goes to the owner as fix-now / follow-up / drop. This story keeps
  that for every per-finding draft and changes only summary drafts, where fix-now was never offered. The owner
  confirmed this on 2026-11-03.

### Dependencies
- Depends on: none (it shares `scripts/automate-next-step.sh` and `docs/result-schemas/automate-run.md` with the
  `--cheap` stories, so `## Touches` keeps them in separate waves)
- Blocks: none

### Risks
- An auto-kept summary is easy to ignore, so `proposed/` keeps growing. This is the existing state for 185 of 194
  summaries, not a new one.

### Success Metrics
- Zero `AUT-SUMMARY` asks in the next run's session logs; per-finding ask count unchanged.

### Handoff
Ready for: `/automate --backlog .supervisor/requirements/2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md`

## Depends on
none

## Touches
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/skills/automate-loop/per-item-loop.md
loomwright/docs/result-schemas/automate-run.md
loomwright/docs/LANE_GATES.md
changelog.d/

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-04T11:33:27Z
- **Brief:** .supervisor/jobs/done/2026-11-04-auto-keep-summary-dismissed-drafts.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/818
