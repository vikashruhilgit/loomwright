# Loomwright talks to the owner in plain words: one shared rule, one glossary, and a way to measure it

## Status: pending

**As the** owner running Loomwright commands (`/automate`, `/review-pr`, `/supervisor`, `/backlog`, …),
**I want** every report and question written for me to lead with the outcome and what I must decide, in everyday words,
**so that** I can follow what happened without having memorized the plugin's internal vocabulary.

### Problem (verified 2026-11-13 on main 97fcdbe)

- No plain-language rule exists anywhere under `loomwright/`: a search for plain language, jargon or glossary finds nothing in agents, commands or skills.
- The shared report format `loomwright/skills/agent-output/SKILL.md` asks for the technical parts first: absolute paths, file:line references and Beads IDs in a "Context Read" section.
- Prompts are written in internal terms (drain, heal, park, lane, fragment, Phase 4.5, gate-eval condition 7), so the model repeats those words to the owner.

## Acceptance Criteria

**Happy path**
- [ ] Given one of the most-used commands (`/automate`, `/review-pr`, `/supervisor`, `/autonomous`, `/backlog`, `/janitor`), when it finishes, then the report opens with a short plain-words summary (what happened, what is not done, what the owner must decide) before any technical detail.
- [ ] Given an internal term that the glossary lists, when a report or question shows it to the owner, then the term is either replaced by its plain phrase or explained in a few words the first time it appears.
- [ ] Given the glossary, when anyone looks up an internal term, then one file gives its plain phrase. That file is the only place the mapping lives, and both prompts and scripts read it.
- [ ] Given `skills/agent-output/SKILL.md`, when an agent follows it, then the owner-facing summary comes first and file:line, IDs and status codes go in a details section underneath.

**Edge cases**
- [ ] Given a result block, run file, log line or any other text a script or hook parses, when this change lands, then it is byte-identical: only text written for a human changes.
- [ ] Given an exact-wording rule elsewhere (for example the `/setup` memory disclosure that must be shown verbatim), when the plain-language rule applies, then the exact-wording rule wins and the text is not paraphrased.
- [ ] Given every prompt that gains the rule, when `check-token-budget.sh` runs, then each stays within its declared budget, or the budget is raised in the same change following the budget file's raise rule.

**Part B — measure it (folded in from the readability-eval story)**
- [ ] Given a fixed set of sample final reports from the most-used commands, when the readability eval runs, then each gets a score on fixed criteria: outcome stated first, decision stated, internal terms explained or absent, needed details kept below the summary.
- [ ] Given a report that is plain but drops a needed detail (the PR link, the failing check's name), when it is scored, then it loses points, so plainness never rewards hiding facts.
- [ ] Given the eval run on reports captured before and after this change, when the scores are compared, then both are recorded as evidence in the PR.
- [ ] Given a sample the grader cannot run, when the eval runs, then that sample is reported as not scored, never as passing.

**Error scenarios**
- [ ] Given a new skill directory, when CI runs, then `check-token-budget.sh` and `check-doc-currency.sh` pass, because the budget entry and its mirror row ship in the same change and no count is restated in prose.

## Non-goals

- Changing any machine-read format: result blocks, run files, `PARK: <code>` lines, logs, telemetry.
- Rewriting the start-of-session messages or park notices themselves (separate stories in this set).
- A `--technical` or verbose switch (considered, not queued).
- Translating into other languages.
- Gating merges on the eval score (advisory only, at least at first).
- Wiring the rule into the remaining commands and agents (the follow-on story in this set).

## Owner decisions

- 2026-11-13, this session: the owner said Loomwright, and AI generally, is "too technical" and wants plain language so the user understands clearly.
- 2026-11-13, this session: an eval was proposed for model-written text, because a CI check cannot read text the model writes at run time. It is folded into this story so the same PR measures before and after.
- 2026-11-13, this session: the owner chose to run this through `/product-owner` as small stories that ship separately. The first slice is the shared rule and glossary.

## Priority: MVP

Every other story in this set uses the glossary's wording. Without the rule, model-written reports stay as technical as they are now.

## Assumptions

- The cheapest place to load the rule is decided at planning time: a frontmatter `skills:` preload on user-facing agents, a one-line pointer in each user-facing command, or both. Each option has a different token cost per prompt.
- Sample reports can be captured from real or recorded runs without project-private content leaving the machine. The eval follows the existing suites under `loomwright/evals/` (`coordinator-model`, `phase45-reviewer`).
- Plugin manifests here carry no output-style key (`plugin.json` keys: author, description, keywords, license, name, version), so this story does not depend on a plugin-shipped output style. If Claude Code supports plugin output styles, that is an alternative worth checking at planning time, but it is not assumed.

## Dependencies

- Depends on: none
- Blocks: start-of-session messages, park notices, the remaining commands, the CI jargon check

## Risks

- Models drift back to jargon in long sessions. A rule in a prompt reduces this but does not remove it (Part B measures it).
- Each prompt that loads the rule grows slightly, against token budgets.
- LLM-graded scores are noisy. Fixed samples and repeated runs are needed before trusting a trend.
- Over-correction: hiding a detail the owner needs (for example, the PR link or exact error). The details section has to keep these.

## Validation (must pass before merge)

1. **Static — CI gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`, `check-doc-currency.sh` and `check-prompt-history-refs.sh`.
2. **Static — glossary is complete for the named terms:** the glossary has a plain phrase for at least drain, heal, park, lane, fragment, Phase 4.5, READY, ESCALATED, worktree, run file and follow-up draft.
3. **Running system — one real report reads plain:** run `/review-pr` (or `/backlog`) in a live session with the change installed. The first lines of its final report state the outcome and any decision in everyday words, and internal terms appear only with a short explanation. Quote the excerpt in the PR.
4. **Running system — before/after scores:** run the readability eval on reports captured before and after the change, and record both scores in the PR. A sample that cannot run is listed as not scored.

## Depends on

none

## Touches

loomwright/skills/plain-language/SKILL.md
loomwright/skills/plain-language/glossary.json
loomwright/evals/plain-language-reports
loomwright/skills/agent-output/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/commands/automate.md
loomwright/commands/review-pr.md
loomwright/commands/supervisor.md
loomwright/commands/autonomous.md
loomwright/commands/backlog.md
loomwright/commands/janitor.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/.claude-plugin/plugin.json
.claude-plugin/marketplace.json
changelog.d/plain-language-rule-and-glossary.md
