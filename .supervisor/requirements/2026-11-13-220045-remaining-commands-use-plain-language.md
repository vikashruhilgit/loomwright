# The remaining commands report to the owner in plain words

## Status: pending

**As the** owner using the less frequent Loomwright commands (`/verify`, `/handoff`, `/setup`, `/launch-pad`, `/product-owner`, `/pr-postmortem`, `/rules`, `/dreaming`, …),
**I want** their reports and questions to follow the same plain-language rule as the main commands,
**so that** the whole plugin speaks one way, not just the six commands I use most.

### Problem

The first story wires the shared rule into the six most-used commands only, to keep that PR small. The other user-facing commands still lead with technical detail. One example: `/product-owner`'s own output format opens with "Context Read" and absolute paths.

## Acceptance Criteria

**Happy path**
- [ ] Given any user-facing command not covered by the first story, when it finishes, then its report opens with a plain-words summary (outcome, what is not done, what the owner must decide) before technical detail.
- [ ] Given a question one of these commands asks the owner, when it is shown, then it uses the glossary's plain phrases and explains any internal term it keeps.

**Edge cases**
- [ ] Given a command whose output another tool parses (a result block or machine line), when this lands, then that output is byte-identical; only the human summary changes.
- [ ] Given each changed command, when `check-token-budget.sh` runs, then it stays within budget or its budget is raised in the same change, following the raise rule.

**Error scenarios**
- [ ] Given an exact-wording rule inside a command (for example a disclosure that must be shown verbatim), when the plain-language rule applies, then the exact-wording rule wins.

## Non-goals

- Commands that print no report to the owner.
- Agent prompts whose output only the Supervisor or other agents read.

## Owner decisions

- 2026-11-13, this session: the owner wants the whole plugin to speak plainly. The work was split so the first PR covers only the most-used commands.

## Priority: Phase 2

The most-used commands carry most of the benefit. This story finishes the job.

## Assumptions

- Planning decides which commands actually show a report to the owner. `/agent-help` and `/telemetry` may need only a light touch.

## Dependencies

- Depends on: the plain-language rule and glossary story
- Blocks: none

## Risks

- Many small prompt edits, each against its own token budget.

## Validation (must pass before merge)

1. **Static — CI gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh` and `check-prompt-history-refs.sh`.
2. **Running system — two reports read plain:** run `/handoff` and `/verify` (or two other covered commands) in a live session with the change installed, and quote the opening of each final report in the PR.

## Depends on

2026-11-13-220040-plain-language-rule-and-glossary.md

## Touches

loomwright/commands/verify.md
loomwright/commands/handoff.md
loomwright/commands/setup.md
loomwright/commands/launch-pad.md
loomwright/commands/product-owner.md
loomwright/commands/pr-postmortem.md
loomwright/commands/rules.md
loomwright/commands/dreaming.md
loomwright/commands/propose.md
loomwright/commands/insights.md
loomwright/commands/capability-check.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/remaining-commands-use-plain-language.md
