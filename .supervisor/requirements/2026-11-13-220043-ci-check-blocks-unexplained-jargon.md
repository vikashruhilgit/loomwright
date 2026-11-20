# CI stops new unexplained jargon in fixed owner-facing messages

## Status: pending

**As the** owner,
**I want** CI to fail when a change adds an internal term to a fixed message I will read, with no explanation,
**so that** messages don't drift back to jargon after they are cleaned up.

### Problem

The rule and glossary make messages plain once, but nothing stops a later change from adding jargon again. The repo already has a working pattern for this: `scripts/check-prompt-history-refs.sh` counts history references per file against a baseline that may only go down.

## Acceptance Criteria

**Happy path**
- [ ] Given fixed owner-facing text (the strings scripts print for a human, and hook messages), when a change adds a glossary term to it with no explanation, then CI fails and names the file, the term and its plain phrase.
- [ ] Given existing unexplained terms on the day this lands, when CI runs, then it passes against a per-file baseline that may only go down, the same ratchet model as the history-refs check.
- [ ] Given a file brought under its baseline, when the baseline is regenerated, then the count can only decrease.

**Edge cases**
- [ ] Given machine-read text (result blocks, `PARK: <code>` lines, run-file keys, log records, comments), when the check runs, then it does not count it. Only text shown to the owner is in scope, and the check states how it tells the two apart.
- [ ] Given a term followed by its explanation (the glossary phrase or a short explanation in brackets), when the check runs, then it does not count that use.

**Error scenarios**
- [ ] Given a missing or unreadable glossary, when the check runs in CI, then it fails closed with a clear message, never a silent pass.

## Non-goals

- Checking text the model writes at run time (covered by the readability eval story).
- Checking agent and command prompts themselves, which are written for the model.

## Owner decisions

- 2026-11-13, this session: the owner asked how to make sure jargon doesn't come back. A CI check was proposed for fixed strings, with an eval for model-written text.

## Priority: Phase 2

The first cleanup (start-of-session messages, park notices) lands first; this check then keeps it from regressing.

## Assumptions

- Owner-facing strings can be told apart from machine-read ones well enough to keep false positives low. Planning picks the method (a marker, an allowlist of emitting functions, or a list of surfaces).

## Dependencies

- Depends on: the plain-language rule and glossary story
- Blocks: none

## Risks

- False positives annoy contributors. The baseline ratchet keeps the first run green.

## Validation (must pass before merge)

1. **Static — the check's own tests:** `bash scripts/test-check-plain-language.sh` (or the name chosen) passes. It covers: a new unexplained term fails, an explained term passes, machine-read text is ignored, a missing glossary fails closed.
2. **Static — wired into CI:** `bash scripts/ci-local.sh --affected` runs the new check and passes on the change.

## Depends on

2026-11-13-220040-plain-language-rule-and-glossary.md

## Touches

scripts/check-plain-language.sh
scripts/test-check-plain-language.sh
loomwright/docs/plain-language-baseline.json
.github/workflows/ci.yml
scripts/ci-local.sh
changelog.d/ci-check-blocks-unexplained-jargon.md
