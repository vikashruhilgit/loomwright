# Selvedge

The QA companion for [Loomwright](../loomwright) — risk-based test strategy, test
generation, and test execution.

> **Scaffold only.** Selvedge is registered and installable, but deliberately
> empty: it ships **no** agents, commands, skills, or hooks yet. The QA assets
> still live in Loomwright and move here in a later slice, populated rather than
> empty. See "Why it is empty on purpose" below.

## Companion, not a standalone install

Selvedge **requires `loomwright@atelier`** and is not useful on its own. It has
no orchestration of its own: its QA roles are spawned by Loomwright's Supervisor
and reviewed through Loomwright's gates, and it shares Loomwright's canonical
Shared Agent Contract rather than carrying a second copy of it.

```
/plugin install loomwright@atelier
/plugin install selvedge@atelier
```

Installing Selvedge without Loomwright gets you a registered plugin that
contributes nothing.

## Why it is empty on purpose

Creating `agents/`, `skills/`, or `hooks/` **empty** would be actively harmful,
because this repo's CI gates fail closed on exactly that shape:

- `check-shared-prefix.sh` treats an empty agents dir as a failure — a 0-agent
  run of a fail-closed gate is a false green, not a pass.
- `check-skills-index-sync.sh` fails loudly on a `skills/` dir with no
  `SKILLS_INDEX.md`.
- `check-token-budget.sh` fails loudly on an agents dir whose plugin declares no
  `prompt-token-budgets.json` of its own.

So the directories arrive **with their contents**, in one atomic move. Until
then the gates skip Selvedge silently — it ships no such tree, which is not a
defect — while still failing loudly the moment a tree exists but is malformed.
Those two behaviours are different on purpose.

## License

MIT
