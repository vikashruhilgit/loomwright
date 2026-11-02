# Review trust from the EGM comparison — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
From the 2026-11-02 comparison of Google's open-source Elephant-Goldfish Model (EGM) with Loomwright. Loomwright is strong where a check can be mechanical, but two judgments are taken on the author's
word: a drain dismissal needs only a free-text reason (280 dismissals over the last 60 merged PRs), and Plan Review
never sees the requirement it is meant to protect, so nothing compares what was asked with what the brief plans.

## Owner decisions
- 2026-11-02 (owner, in chat): an `extra` subtask in the Plan Review requirement-fit check is MEDIUM (Launch Pad refines it; the run continues), not NEEDS_HUMAN. Copied into that item's Owner decisions (2026-11-02-124022, Part A).
- 2026-11-02 (owner, in chat): run the set in one wave. 120033 and 121401 were merged into 2026-11-02-124022-requirement-to-plan-checks.md (Parts A and B) with `merge-items`; the originals are parked.

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 2026-11-02-120032 | Every drain dismissal names checkable proof, shown in the owner's draft | none | 2026-11-02-124022 |
| 2026-11-02-124022 | Part A: Plan Review maps the brief to the source requirement (fulfils / under / over). Part B: Product Owner stories carry Non-goals, Owner decisions and Validation | none | 2026-11-02-120032 |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-02-120034-review-trust-from-egm.md --parallel 2
Safe mode (no --auto-merge). N = 2: two items with disjoint Touches (8 and 16 files), so one wave.
wave 1: 2026-11-02-120032-drain-dismissals-carry-checkable-evidence.md 2026-11-02-124022-requirement-to-plan-checks.md
Serialisations: none inside this set. Outside it, 2026-11-02-120032 shares loomwright/scripts/review-heal-next-step.sh with dismissed-followups/12-bundle-04ab-drivers-and-gate-tooling.md and loomwright/scripts/automate-dismissed.sh with dismissed-followups/01-follow-up-decision-becomes-tracked-work.md; do not run it in the same wave as either.
Hotspots: loomwright/docs/prompt-token-budgets.json and its mirror rows in loomwright/docs/ARCHITECTURE_CONTRACTS.md, owned by 2026-11-02-124022 alone. Each item writes its own changelog.d fragment.
Companions rule: none proposed.

## Considered and not queued
- An ESCALATE verdict for dismissals whose proof is outside the repo: the owner already decides drafted dismissals at the park.
- Remembering dismissals across drain rounds: 12 of 280 dismissals were repeats, all re-dismissed consistently.
- Two consecutive clean reviews before Phase 4.5 ends: each item already gets worker self-review, Phase 4.5 and the CI review bot on the final code.
- A separate paraphrase agent before Plan Review: replaced by the requirement mapping inside the existing Plan Reviewer.
- EGM's five-stage, nine-reviewer pipeline: conflicts with the two-review-lens contract and multiplies cost.
- Problem and Measurements sections in Product Owner's template: As-a/so-that already carries the why, and Success Metrics already covers after-merge measurement.

## Revisit when
- Dismissal refusals for missing evidence are frequent in the first drains (the accepted forms are too strict).
- Most `extra` flags from the requirement mapping are judged noise by the owner.
- Phase 4.5's catch rate drops (the reviewer-replay suite, 2026-11-01-092115, would show it).

## Checklist
- [ ] .supervisor/requirements/2026-11-02-120032-drain-dismissals-carry-checkable-evidence.md
- [ ] .supervisor/requirements/2026-11-02-124022-requirement-to-plan-checks.md
