# automate-speed/17 — Size ceilings for skills and commands, not just agents

## Status: pending

## Problem
`scripts/check-token-budget.sh` measures only the 14 agents plus the skills they PRELOAD; its own header says command
docs and on-demand skills are out of scope. Those are exactly the files that grew: automate-loop 316KB across its
split files, self-heal-advisory 176KB, review-heal 133KB, autonomous-loop 102KB, `commands/dreaming.md` 138KB,
`commands/setup.md` 94KB, `commands/agent-help.md` 84KB (plan doc §Why now). Each fix PR adds a paragraph and nothing
pushes back. `loomwright/docs/prompt-token-budgets.json` is itself 37KB, mostly 1–5K-char `note` fields that retell
history the CHANGELOG already holds.

## Goal
<!-- bump: minor -->
Every skill directory and every command doc has a declared ceiling, checked fail-CLOSED in CI, so no runtime prompt
grows unnoticed. This item lands early to stop growth while the diet items (13–16) shrink the files; item 18 lowers
the ceilings afterwards.

## Scope
- Extend `check-token-budget.sh` (same proxy: bytes / 4, labeled proxy) with two new tables in
  `prompt-token-budgets.json`: `.skills[<dir>]` (sum of every `*.md` in the skill dir) and `.commands[<stem>]`.
  Ceiling = today's measure + ~10%. Missing entry for an existing dir/command ⇒ ERROR (fail-CLOSED), orphaned entry ⇒
  ERROR, same as agents.
- Raising a ceiling keeps the existing raise rule (same PR, with a reason) but the reason is ONE line; history goes to
  the CHANGELOG. Shrink every existing `note` to one line.
- Mirror table in `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" covers the new tables (the gate already
  checks the mirror for agents; extend the check).
- `CLAUDE.md` §"Adding or Modifying Agents": a new skill or command declares its ceiling (one sentence, pointing at
  the json; no counts restated).

## Invariants
- Fail-CLOSED on any breach, missing entry, orphan or non-integer ceiling (bimodal failure philosophy: this is a gate).
- No count or version claim restated (house rule, advisory).

## Non-goals
- Lowering ceilings (item 18). Measuring real tokenizer counts.

## Owner decisions (from _BACKLOG.md)
- D2 (stories out of runtime text applies to the budget notes too).

## Acceptance criteria
- Given a skill dir whose `*.md` total exceeds its ceiling, then `check-token-budget.sh` exits 1 naming it.
- Given a new command doc with no `.commands` entry, then it exits 1 with an ERROR naming the missing entry.
- Given a `.skills` entry for a deleted dir, then it exits 1 (orphan).
- Every `note` in `prompt-token-budgets.json` is a single line under 200 chars; the file is at least 50% smaller.
- The ARCHITECTURE_CONTRACTS mirror check covers skills and commands.

## Validation (must pass before merge)
1. `scripts/test-check-token-budget.sh`, `check-doc-currency.sh`; report `<passed>/<total>`.
2. Mutation controls: append 10KB to a scratch skill ⇒ red; delete a `.commands` entry ⇒ red.

## Depends on
none

## Touches
scripts/check-token-budget.sh
scripts/test-check-token-budget.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
CLAUDE.md
changelog.d/as17-prompt-size-ratchet.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-16T01:41:51Z
- **Brief:** .supervisor/jobs/done/2026-10-15-as17-prompt-size-ratchet.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/565
