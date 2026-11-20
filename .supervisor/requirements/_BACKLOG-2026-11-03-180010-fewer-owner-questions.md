# Fewer owner questions — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
Across 4,201 questions in every past transcript (mined 2026-11-03), the owner picked the `(Recommended)` option 92.7%
of the time. Four gates make up 82% of the 1,238 catalog-coded questions since 2026-10-10: AUT-DISMISS (370 asks),
AUT-SUMMARY (286), LP-SAVE-NOTE (273) and LP-CLARIFY (88). Each question costs a turn, and in a phase session a relay
round trip as well.

The existing pre-answer mechanism (`lane-policy.sh`) reaches only `allowed` gates inside `--parallel` lanes. The
`follow-up` answer files a draft that nothing picks up: 232 drafts were added and 0 were promoted, 177 were retired by
hand, and 53 have piled up since.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 2026-11-03-180008 | `auto` gate tier (LP-SAVE, LP-SAVE-NOTE, AUT-QUEUE, AUT-RESUME), escalation triggers, off switch, end-of-run list | none | none (shares `lane-policy.sh`, `LANE_GATES.md` and `per-item-loop.md` with 180009) |
| 2026-11-03-180009 | No per-finding dismissed ask; one batched fix-now ask for MEDIUM+ | dismissed-followups/01, 2026-11-03-102217 | none |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-03-180010-fewer-owner-questions.md

Safe mode, sequential (N = 1).
- wave 1: 180008.
- 180009 waits on two items outside this set: `dismissed-followups/01-follow-up-decision-becomes-tracked-work.md` and
  `2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md`, the last item of
  `_BACKLOG-2026-11-03-102216-automate-token-cost-fixes.md`. Run those first.
- Hotspots: `loomwright/scripts/lane-policy.sh` and `loomwright/docs/LANE_GATES.md` (both items), and
  `loomwright/scripts/automate-next-step.sh` (180009, 01 and 102217).

## Considered and not queued
- **Auto-select every recommended option.** It would lose the real decisions: the owner overrides SUP-CHILDREN,
  SUP-ADJ-GAP, LP-NO-GO and LP-RULE-OVR 33–43% of the time, and fix-now on per-finding drafts 14–22% of the time.
- **An LLM judge ("does the owner need this?").** It adds cost on every ask, and it is a second model guessing where the
  recommended label already is one. Deterministic triggers are cheaper and testable. A judge for the free-text
  LP-CLARIFY alone may be revisited.
- **SUP-OVERLAP `auto`.** It went 21 of 21 proceed, but it is the stale-branch incident guard. It may be revisited only
  for an overlap whose PR merged before the brief was planned.
- **Auto-bundling follow-ups into a pending item per run.** `dismissed-followups/01` rejected this as its option (a).
- **A "still on main?" check before filing a draft.** `dismissed-followups/01` rejected this as its option (b): it
  needs an LLM pass.
- **An "owner overrode this gate before" escalation trigger.** There is no durable per-gate override record yet.

## Revisit when
The end-of-run auto-answer lists show the owner reversing an auto-answer, or a re-mine of transcripts shows a
remaining gate with 50 or more asks and over 95% default acceptance.

## Checklist
- [ ] .supervisor/requirements/2026-11-03-180008-auto-answer-routine-question-gates.md
- [ ] .supervisor/requirements/dismissed-followups/01-follow-up-decision-becomes-tracked-work.md  # prerequisite of 180009
- [ ] .supervisor/requirements/2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md  # prerequisite of 180009
- [ ] .supervisor/requirements/2026-11-03-180009-stop-asking-per-dismissed-finding.md
