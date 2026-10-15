# automate-speed/14 — Prompt diet: review-heal carries rules, not stories

## Status: pending

## Problem
`skills/review-heal/SKILL.md` is 133KB with ~59 history references; it is read on every drain round. Item 12 moves its control flow into a driver; what remains still mixes instructions with incident history (plan doc §Why now).

## Goal
<!-- bump: minor -->
The review-heal prompts carry only what the executing model needs at the moment it needs it: instructions and short rules.
Stories move to a rationale doc, rules move to the home that enforces them, and files load only in the mode that uses
them.

## Scope
- **Part A — rule homes.** Walk every `rule` row of the group inventory. Enforced by an existing script or hook ⇒
  delete the prose (keep one line only if the model would otherwise attempt the blocked action). Applies at one step
  ⇒ mark `step-scoped` and move it next to that step (or into the step's instruction text if a next-step driver owns
  it). Applies everywhere ⇒ `global`, rewritten short. A rule that needs a NEW hook is not added here: file it to
  `.supervisor/requirements/proposed/` and keep the prose.
- **Part B — stories out.** Every `story` row moves to its rationale doc, linked by anchor; keep a one-line
  "because" only where it blocks a tempting wrong shortcut. A story paragraph that contains a rule is split first:
  the rule gets its own row and home, then the story moves.
- **Part C — load per round.** Sections used only by the Earned Fallback Review, only by `--until-mergeable`, or only on escalation load when that path runs.

## Invariants
- No rule is dropped: every rule row in the group inventory has a home (`script:` / `hook:` existing leaf /
  `step-scoped` / `global`) before its prose is deleted; `test-loop-inventory.sh` enforces it.
- Wording a gate greps for (a heading, a pinned sentence) is an interface (house rule, advisory): renaming it moves its
  consumers in the same change.
- No count or version claim is added to moved text; rationale citations of `file:line` are pinned or replaced by
  descriptive anchors (`test-citation-drift.sh`).
- Every invariant in CLAUDE.md §"Failure-Mode Invariants" that appears in this group stays in the runtime prompt or
  in an enforcing script/hook.

## Non-goals
- Editing `agents/review-pr.md` (any agent-prompt edit pulls in the budget and contract companion files and would
  serialise this item against Supervisor's items).
- Changing behaviour. A behaviour question found while moving text is recorded in the PR body, not fixed here.
- Adding hooks (proposed items only).

## Owner decisions (from _BACKLOG.md)
- D1: Moving prose never drops a rule; every rule gets one of three homes — enforced by an existing script or hook
  (remove from the prompt), step-scoped (handed over only at its step), or global (kept, short).
- D2: Stories and history move to a rationale doc; a one-line "because" stays only where it stops a tempting wrong
  shortcut.

## Acceptance criteria
- Given the group inventory after this item, then no row of kind `story` has home `prose`, and every `rule` row has
  a non-prose home or `global`.
- The group's runtime read set (`wc -c` of every file in Touches except the rationale and inventory docs) is at least
  30% smaller; before and after are in the PR body.
- The history-reference count (`#NNN`, `queue/NN`, dates, `item NN`) in the group's runtime files is recorded before
  and after and is lower.
- Given a drain round that does not run the Earned Fallback Review, then the fallback section is not read (asserted from the drain transcript in the running-system step).

## Validation (must pass before merge)
1. `test-loop-inventory.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh`, plus the
   group's own suites; report `<passed>/<total>`.
2. Mutation control: delete a `global` rule's line from a scratch copy ⇒ `test-loop-inventory.sh` goes red.
3. Running system: one real item that exercises this group after the change; paste the phase's result block.

## Depends on
12

## Touches
loomwright/skills/review-heal/SKILL.md
loomwright/commands/review-pr.md
loomwright/docs/rationale/review-heal.md
loomwright/docs/loop-inventory/review-heal.md
changelog.d/as14-diet-review-heal.md
