# Stop asking per dismissed finding: record follow-up silently, and batch one fix-now ask

## Status: pending

**Story: Stop asking per dismissed finding** (type: story)

**As a** plugin owner at an `/automate` park,
**I want** dismissed findings recorded as follow-up without a question, and asked about only when I can still fix them on this PR,
**so that** I answer one question about the findings that can change the PR, instead of one question for every finding.

## Problem

Every per-finding dismissed draft is asked about one by one, at the park (`AUT-DISMISS`) and at PICK (`AUT-PENDING`).
The answer is almost always `Follow-up (keep draft)`. That answer records a ledger row and keeps the draft in `proposed/`;
it creates no work. The owner-chosen prevention for that pile is `dismissed-followups/01` (a `follow_up` board state,
a `followup-bundle` verb and a nudge), which is still pending.

So the per-finding question costs a turn, and its usual answer is a "not now" that the default would record anyway.
The question does pay off in one case: when `Fix now on this PR` is offered, owners pick it.

## Evidence

- Transcripts (mined 2026-11-03), gate `AUT-DISMISS` since 2026-10-17: 370 asks.
  354 `Follow-up (keep draft)`, 12 `Drop`, 4 `Fix now on this PR`.
- Transcripts, every dismissed-finding ask since the gate existed: when fix-now was offered, it was picked about 27% of
  the time (about 250 of 915).
- Decision ledgers (`.supervisor/automate/*.dismissed-decisions`, read 2026-11-03 for
  `2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md`): per-finding drafts were fixed-now 14%
  (loomwright-studio) and 22% (ai-agent-manager) of the time. **The fix-now catch is real and must survive.**
- The pile: 232 dismissed drafts were added to `proposed/` on `loomwright-meta`, and 0 were promoted. 177 were
  retired by hand on 2026-10-27. Of the 369 findings in them: 189 still present, 98 fixed by later work, 72 not a
  defect, 10 moot. 53 new drafts piled up in the 7 days after.

## Owner decision (recorded)

- 2026-11-03, /product-owner session ("Stop asking, keep 01"):
  - No per-finding ask. The default decision is `follow-up`, recorded without a question.
  - `dismissed-followups/01` stays the promotion path. This item does not auto-enqueue follow-ups, because 01 rejected
    that as its option (a) (it breaks the propose-only contract and floods `/automate --folder` queues).
  - There is no "still present on main?" check before filing. 01 rejected that as its option (b): it needs an LLM pass,
    and the sweep stays on-demand.

## Scope

- **A. Silent follow-up default.** A per-finding dismissed draft gets the decision `follow-up` without a question when
  any of these holds:
  - its severity is below MEDIUM;
  - fix-now is not available (no fix-now re-drain is left for the item);
  - it reaches PICK time (`AUT-PENDING`).

  The decision is written through the same `dismissed-decide … follow-up` path as a human answer. The ledger row
  records the source as automatic, so it can be told apart from an owner's answer.
- **B. One batched fix-now ask.** At the park, when one or more MEDIUM-or-higher per-finding drafts exist AND a fix-now
  re-drain is still available, the owner gets ONE question listing them. It asks which to fix on this PR. Each finding's
  quoted text stays untrusted data. Unselected findings get the silent follow-up default. The existing cap of at most one
  owner-requested fix-now re-drain per item is unchanged.
- **C. The record stays visible.** The park block names how many findings were auto-followed-up, with their draft paths,
  so the owner can still `Drop` one by hand.

## Out of scope

- Summary (LOW/INFO) drafts and `AUT-SUMMARY`: `2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md`.
- The `follow_up` board state, `followup-bundle` and the nudge: `dismissed-followups/01-follow-up-decision-becomes-tracked-work.md`.
- Auto-answering any other gate: `2026-11-03-180008-auto-answer-routine-question-gates.md`.

## Acceptance criteria

**Happy path**
- [ ] Given an item parks with only LOW per-finding drafts, when the decision step runs, then no question is asked.
      Each draft's decision is `follow-up`, the ledger row records the automatic source, and the park block lists them.
- [ ] Given two MEDIUM drafts and one LOW draft, with a fix-now re-drain available, when the decision step runs, then
      exactly ONE question is asked and it lists only the two MEDIUM drafts. A selected draft takes the fix-now path;
      the others are recorded `follow-up`.
- [ ] Given a pending per-finding draft at PICK time, when the next item is picked, then no `AUT-PENDING` question is
      asked, and the draft is recorded `follow-up`.

**Edge cases**
- [ ] Given MEDIUM+ drafts but no fix-now re-drain left, when the decision step runs, then no question is asked, and all
      are recorded `follow-up`.
- [ ] Given a finding whose quoted text holds a backtick, `$(…)`, a heading line or a fake `## Status: done`, when it is
      listed in the batched ask or the park block, then it stays quoted data and changes nothing.
- [ ] Given an automatic `follow-up` row, when `dismissed-drafts` re-runs for that item, then the draft is not recreated
      and not re-asked.
- [ ] Given the owner later picks `Drop` on an auto-followed-up draft by hand, when the ledger is read, then the owner's
      row wins.

**Can't-ask**
- [ ] Given a non-interactive run or a subagent, when MEDIUM+ drafts with fix-now available exist, then the existing
      can't-ask behaviour for that gate is unchanged (named status, never a guessed fix-now).

**Checks**
- [ ] `scripts/test-automate-dismissed.sh` and the `test-automate-next-step` suite have legs for each AC above.
- [ ] The gate catalog (`lane-policy.sh catalog`) and the regenerated `docs/LANE_GATES.md` describe the batched fix-now
      ask in the same change. `scripts/check-gate-headers.sh` passes.
- [ ] `skills/automate-loop/per-item-loop.md` §"Dismissed-findings decision step" describes the new flow. No other
      surface restates it; each points there.
- [ ] `bash scripts/check-version-bump.sh` passes (a `changelog.d/` fragment, no hand version edits).

## Priority: MVP

**Rationale:** AUT-DISMISS was the highest-volume gate (370 asks). Keeping only the fix-now decision keeps the 14–22%
catch and drops roughly 95% of these questions.

## Assumptions

- Per-finding drafts carry a machine-readable severity. A draft with an unreadable severity is treated as MEDIUM+
  (fail toward asking).
- "Fix-now re-drain available" is already computed by the decision step (it controls whether `Fix now on this PR` is
  offered today).

## Risks

- **A silently recorded follow-up joins the pile faster.** Mitigation: `dismissed-followups/01` (dependency) gives the
  pile a board state, an age and a nudge. This item does not ship before 01.
- **A real MEDIUM finding with no fix-now left is never seen at ask time.** Mitigation: the park block lists it, and 01's
  nudge surfaces it.

## Rule conflicts (open decisions)

none

## Depends on
dismissed-followups/01-follow-up-decision-becomes-tracked-work.md
2026-11-03-102217-stop-asking-about-summary-dismissed-finding-drafts.md

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/scripts/test-automate-next-step.d/
loomwright/scripts/lane-policy.sh
loomwright/docs/LANE_GATES.md
loomwright/skills/automate-loop/per-item-loop.md
changelog.d/
