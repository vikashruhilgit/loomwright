# automate-speed/16 — Prompt diet: what remains of automate-loop loads by mode and carries no stories

## Status: pending

## Problem
After items 06–09 the automate-loop skill is a coordinator loop plus global rules, intake and the lane coordinator. `commands/automate.md` still tells the main thread to read every split file "in full, in this order" (the parallel-automate/22 split was move-only, so it saved nothing), and `lanes.md` (54KB) is read even on a sequential run (plan doc §Why now).

## Goal
<!-- bump: minor -->
The automate-loop prompts carry only what the executing model needs at the moment it needs it: instructions and short rules.
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
- **Part C — load by mode.** Drop the "read each split file in full" instruction. `lanes.md` and `command-lanes.md` load only with `--parallel`; `resume.md` only on `--resume`; `branch-mode.md` only in branch mode; `intake.md` only when building a Queue.

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
- Given a sequential `/automate` run without `--resume`, then `lanes.md`, `command-lanes.md` and `resume.md` are not read (asserted from the coordinator transcript).

## Validation (must pass before merge)
1. `test-loop-inventory.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh`, plus the
   group's own suites; report `<passed>/<total>`.
2. Mutation control: delete a `global` rule's line from a scratch copy ⇒ `test-loop-inventory.sh` goes red.
3. Running system: one real item that exercises this group after the change; paste the phase's result block.

## Depends on
09

## Touches
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
loomwright/docs/rationale/automate-loop.md
loomwright/docs/loop-inventory/automate-loop.md
changelog.d/as16-diet-automate-loop.md
