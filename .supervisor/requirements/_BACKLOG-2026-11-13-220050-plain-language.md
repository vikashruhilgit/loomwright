# Plain language to the owner — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now

The owner finds Loomwright "too technical" in everything it shows them. Checked 2026-11-13 on main 97fcdbe:
- No plain-language rule exists anywhere under `loomwright/`.
- The shared report format (`skills/agent-output/SKILL.md`) puts paths, file:line and IDs first.
- Start-of-session notices read like `automate: 113 follow-up drafts, oldest 17d — /backlog --state follow_up, then followup-bundle`.
- About 30 distinct `PARK: <code>` stop reasons reach the owner as bare codes.

Measured surface: 25 commands, 14 agents, 94 hook entries and about 41 scripts that print status codes. This set changes only text written for a human. Every machine-read format stays byte-identical.

## Owner decisions

none recorded

## Order

| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 220040 rule + glossary + eval | Shared plain-language rule, one glossary, the six most-used commands wired, `agent-output` reordered, and a before/after readability score | none | none |
| 220041 start-of-session messages | Start-of-session notices in everyday words | 220040 | 220042, 220043 |
| 220042 park notices | A plain sentence for every stop reason, codes unchanged | 220040 | 220041, 220043 |
| 220043 CI jargon check | CI fails new unexplained jargon in fixed owner-facing text (ratchet baseline) | 220040 | 220041, 220042 |
| 220045 remaining commands | The other user-facing commands follow the rule | 220040 | none (waits for 220042) |

## Run

/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-13-220050-plain-language.md --parallel 3

- **Why N = 3:** wave 2 is the widest wave, and its three items touch separate files. The park item changes only the text shown to the owner, never a merge-gate condition. If one PR with three items is too much to review at once, run without `--parallel`.
- wave 1: 220040-plain-language-rule-and-glossary
- wave 2: 220041-start-of-session-messages-in-plain-words, 220042-park-notices-say-why-in-plain-words, 220043-ci-check-blocks-unexplained-jargon
- wave 3: 220045-remaining-commands-use-plain-language
- Waiting order: 220045 waits on 220042, because both edit `loomwright/docs/prompt-token-budgets.json` and `loomwright/docs/ARCHITECTURE_CONTRACTS.md`. Every wave-2 item waits on 220040 for the glossary.
- Shared-file owners: `loomwright/skills/plain-language/glossary.json` belongs to 220040. Wave-2 items read it and do not edit it; a missing term is a follow-up, not an in-wave edit. `loomwright/skills/plain-language/park-reasons.json` belongs to 220042. `loomwright/commands/automate.md` is edited by 220040, then 220042, in separate waves.
- No companions rule proposed.

## Considered and not queued

- **A `--technical` / verbose switch, or a config key for report style:** not needed until plain reports turn out to hide something. The details section under each summary keeps the facts.
- **Rewriting every script's human-facing output now (about 41 scripts):** too wide for one set. The CI ratchet (220043) fixes it file by file over time, and it can only go down.
- **A plugin-shipped output style:** the plugin manifest has no such key today. Reconsider only if Claude Code supports output styles from plugins.
- **A separate PR for the readability eval:** too small on its own. It is folded into 220040 so the same PR measures before and after.

## Revisit when

- The before/after readability score in 220040 shows little improvement, or reports drift back to jargon in later sessions.
- The owner still finds a specific message too technical after this set ships. Add that surface as a new item.

## Checklist
- [ ] .supervisor/requirements/2026-11-13-220040-plain-language-rule-and-glossary.md
- [ ] .supervisor/requirements/2026-11-13-220041-start-of-session-messages-in-plain-words.md
- [ ] .supervisor/requirements/2026-11-13-220042-park-notices-say-why-in-plain-words.md
- [ ] .supervisor/requirements/2026-11-13-220043-ci-check-blocks-unexplained-jargon.md
- [ ] .supervisor/requirements/2026-11-13-220045-remaining-commands-use-plain-language.md
