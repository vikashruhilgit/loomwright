# automate-speed/09 — Each phase of an item runs in a fresh session; the coordinator stays small

## Status: pending

## Problem
`/automate` and `/autonomous` are inline-only (`docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting" and
§"Question-gate inventory"): only the main thread can ask the owner, so the whole item — Launch Pad, Supervisor,
Phase 4.5, the drain — runs in ONE growing context. Even after items 06–08 shrink the loop prose, each phase's own
prompts and outputs still pile into that context. #548 (`--parallel 1` single lane) gives each ITEM a fresh session
but explicitly does not help a single large item, which is about half the large-session bytes. Lanes are not cheaper
per item either: median lane item session 65M main-session tokens, 647K peak (plan doc §Why now).

## Goal
<!-- bump: minor -->
The coordinator runs each phase as its own fresh session that reads its state from disk: Launch Pad (brief),
Supervisor (implement + Phase 4.5), and the owned drain. Questions from a phase reach the owner through the existing
lane question relay (defer + resume). The coordinator's context per item stays under ~100K tokens.

## Scope
- `next-step`'s `spawn` instruction gains a `session: fresh` form. The coordinator launches it with the lane machinery
  that already exists (`claude -p` launch authority, the question relay, `lane-answer` resume) rather than inline.
- Each phase session receives only: its requirement or brief path, the run file path, and its phase. It writes its
  result block to the documented sidecar; `next-step --result` reads it.
- Update `docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting" and §"Question-gate inventory": every gate reached from
  a phase session moves from context MI to HP-with-relay, with its named can't-ask status unchanged when the relay is
  unavailable.
- Keep inline execution selectable (`--inline-phases`) for hosts without the relay.

## Invariants
- Every question gate keeps a named can't-ask branch; an unanswerable question never hangs a phase and is never
  answered by the coordinator on the owner's behalf.
- Single-drain ownership and the `auto_review` toggle around RUN are unchanged (driver-owned since item 07).
- `gh pr merge --squash` executor unchanged.

## Non-goals
- Choosing the coordinator's model (item 10).
- Changing what each phase does.

## Owner decisions (from _BACKLOG.md)
- D3: implementing, reviewing and brief writing stay on the strong model.
- Flag 4 (2026-10-15, owner chose Proceed): this item changes the documented inline-only rule; the contract doc is
  rewritten in the same PR.

## Acceptance criteria
- Given a Queue item, when `/automate` runs it, then Launch Pad, Supervisor and the drain each run in a separate
  session id, and the coordinator's session never reads `agents/launch-pad.md`, `agents/supervisor.md`,
  `skills/self-heal-advisory/` or `skills/review-heal/` (asserted from the coordinator transcript in the
  running-system step).
- Given a Launch Pad question in a phase session, then it reaches the owner through the relay and the phase resumes
  with the answer.
- Given no relay available and `--inline-phases` not set, then the run parks with a named status before spawning.
- `docs/ARCHITECTURE_CONTRACTS.md` question-gate rows match the new contexts; `check-doc-currency.sh` passes.

## Validation (must pass before merge)
1. `test-automate-next-step.sh`, `test-automate-lanes.sh`, `test-automate-golden.sh`; report `<passed>/<total>`.
2. Running system: one real item end to end; paste each phase's session id and the coordinator's peak context from
   item 03's report.

## Measurements
- Coordinator peak context and main-session tokens per item over the next 3 items vs the item 03 baseline. Frozen
  commit: this PR's merge commit.

## Depends on
08

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/automate-loop/branch-mode.md
loomwright/skills/automate-loop/command-lanes.md
loomwright/skills/automate-loop/intake.md
loomwright/skills/automate-loop/invariants.md
loomwright/skills/automate-loop/lanes.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/resume.md
loomwright/commands/automate.md
loomwright/commands/autonomous.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/loop-inventory/automate-loop.md
changelog.d/as09-fresh-session-per-phase.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-20T04:42:01Z
- **Brief:** .supervisor/jobs/done/2026-10-19-fresh-session-per-phase.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/628
