# When an /automate item stops, the owner is told why in plain words

## Status: pending

**As the** owner whose `/automate` item has stopped and is waiting for me,
**I want** a plain sentence saying why it stopped and what I can do,
**so that** I don't have to look up codes like `PARK: ctx_carries_gate_owned_key` or `PARK: rules_gate_head_mismatch`.

### Problem (verified 2026-11-13 on main 97fcdbe)

The scripts emit about 30 distinct `PARK: <reason>` codes (`automate-helpers.sh`, `automate-next-step.sh`, `classify-risk.sh`). `automate-next-step.sh` matches these lines by the `PARK: ` prefix, and tests pin them. Only the code reaches the owner, with no explanation.

## Acceptance Criteria

**Happy path**
- [ ] Given any park reason a script can emit, when the item stops and the owner is told, then they see one plain sentence of why it stopped and what they can do, alongside the code.
- [ ] Given the list of plain sentences, when a script gains a new park reason without one, then a test fails. The list cannot silently fall behind the codes, because the codes stay the authority.

**Edge cases**
- [ ] Given the `PARK: <code>` line, the run file's `## Current` and every other machine-read field, when this change lands, then they are byte-identical. The plain sentence is added where the owner is told, never by changing the parsed line.
- [ ] Given a park whose reason has extra detail after the code (for example `PARK: token_ceiling — ceiling-check answered …`), when it is shown, then the plain sentence comes first and the detail stays available underneath.
- [ ] Given an unknown or malformed code, when it is shown, then the owner sees a generic plain sentence ("stopped for a reason Loomwright doesn't have a plain explanation for yet") plus the raw code, never nothing.

**Error scenarios**
- [ ] Given the sentence list is missing or unreadable, when a park is shown, then the raw code is still shown and the park itself is unaffected (fails safe).

## Non-goals

- Changing when or why items park, or any merge-gate condition.
- Changing the `--notify` webhook payload's machine fields (a human-readable field may be added).
- Plain sentences for non-park script output (left to the CI ratchet story).

## Owner decisions

- 2026-11-13, this session: the owner wants plain language. Script status codes were named as a source of jargon, with `PARK: ctx_carries_gate_owned_key` as the example.

## Priority: MVP

A park is exactly the moment the owner must act, and today it is the least readable message.

## Assumptions

- The owner sees a park through the `/automate` coordinator's message and, when enabled, the `--notify` webhook. Planning confirms every place a park reaches the owner.

## Dependencies

- Depends on: the plain-language rule and glossary story
- Blocks: none

## Risks

- About 30 sentences to write well. A vague sentence is no better than the code.
- A second list of codes could drift from the scripts; the completeness test covers this.

## Validation (must pass before merge)

1. **Static — tests:** `bash scripts/ci-local.sh --affected` passes. A new test fails when a `PARK: <reason>` code emitted under `loomwright/scripts/` has no plain sentence, and passes on the change.
2. **Static — machine lines unchanged:** the existing tests that pin `PARK: <code>` lines and run-file contents pass without edits to their expected values.
3. **Running system — one real park reads plain:** trigger a park in a scratch `/automate` run (for example, an unprotected branch), and quote the owner-facing message in the PR.

## Depends on

2026-11-13-220040-plain-language-rule-and-glossary.md

## Touches

loomwright/skills/plain-language/park-reasons.json
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/commands/automate.md
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/park-notices-say-why-in-plain-words.md
