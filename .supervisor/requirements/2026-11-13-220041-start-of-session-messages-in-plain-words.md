# Start-of-session messages say what is waiting in plain words

## Status: pending

**As the** owner opening a new Claude session in a Loomwright project,
**I want** the notices at the top of the session to say in everyday words what is waiting for me and what to run,
**so that** I can act on them without decoding them.

### Problem (verified 2026-11-13 on main 97fcdbe)

The SessionStart hook (`session-resume.sh`) builds these lines from its own functions and helper subcommands. Today one reads:
`automate: 113 follow-up drafts, oldest 17d — /backlog --state follow_up, then followup-bundle`
(built in `scripts/automate-helpers.d/followup.sh`). Others include "backlog items need a stamp", the background-processes line, the meta-branch hint, stranded briefs and orphaned worktrees. Tests pin the exact wording, for example the follow-up line in `test-session-resume.sh` and `test-automate-helpers.d/19-followup.sh`. Outside tests, no script or prompt parses these lines; the model reads them and relays them to the owner.

## Acceptance Criteria

**Happy path**
- [ ] Given waiting follow-up drafts, when a session starts, then the notice says in plain words what they are (for example, "113 small follow-up tasks from earlier reviews are waiting; the oldest is 17 days old") and the one command to see them.
- [ ] Given each other start-of-session notice `session-resume.sh` can emit, when it fires, then it names what is waiting and what to do in everyday words, using the glossary's phrases. The exact command stays, so the owner can still copy it.
- [ ] Given the tests that pin the old wording, when this change lands, then they pin the new wording in the same change.

**Edge cases**
- [ ] Given several notices at once, when the session starts, then the whole hook output still fits its existing size bound (≤10k characters), and the most important notice is not the one cut.
- [ ] Given a notice whose wording another script or prompt matches on, if the sweep finds one, then the matcher changes in the same change, or that notice keeps its wording and the story says why.

**Error scenarios**
- [ ] Given a helper that times out or fails, when the session starts, then behaviour is unchanged: no notice, exit 0 (the hook fails safe).

## Non-goals

- Changing what the notices detect, when they fire or their timeouts.
- Notices from other plugins or from Claude Code itself.
- Script output that is not shown at session start (park notices are a separate story).

## Owner decisions

- 2026-11-13, this session: the owner cited start-of-session notices as a main source of jargon. The follow-up nudge was the live example.

## Priority: MVP

The owner sees these at the start of every session, so the change is visible straight away.

## Assumptions

- Every start-of-session notice is produced inside `session-resume.sh` or a helper subcommand it calls (verified for the follow-up and backlog lines; the others are functions in `session-resume.sh`).

## Dependencies

- Depends on: the plain-language rule and glossary story (for consistent wording)
- Blocks: none

## Risks

- Longer sentences press against the hook's size bound.
- Golden fixtures (`scripts/fixtures/automate-helpers-help/followup.golden`) describe the old line and need updating.

## Validation (must pass before merge)

1. **Static — tests:** `bash scripts/ci-local.sh --affected` passes, including `test-session-resume.sh` and the follow-up helper tests with the new wording pinned.
2. **Running system — a fresh session shows the new notice:** in a project with follow-up drafts waiting, start a new session with the change installed and quote the start-of-session notice in the PR. It must read in everyday words and still name the command.

## Depends on

2026-11-13-220040-plain-language-rule-and-glossary.md

## Touches

loomwright/scripts/session-resume.sh
loomwright/scripts/automate-helpers.d/followup.sh
loomwright/scripts/test-session-resume.sh
loomwright/scripts/test-automate-helpers.d/19-followup.sh
loomwright/scripts/fixtures/automate-helpers-help/followup.golden
changelog.d/start-of-session-messages-in-plain-words.md
