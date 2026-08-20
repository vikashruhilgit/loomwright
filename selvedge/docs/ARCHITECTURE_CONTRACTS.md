# Selvedge Architecture Contracts

Machine-checked contracts for the **selvedge** plugin (the QA companion to `loomwright@atelier`).

Selvedge does not restate loomwright's contracts. The shared agent contract, result schemas, failure-escalation policy and hook conventions all remain single-copy in `loomwright/docs/` and `AGENT_GUIDELINES.md` — forking them here would create a second copy no gate compares. This file exists for the contracts that are **per plugin** by construction.

---

## Prompt Token Budgets

`scripts/check-token-budget.sh` budgets **each plugin against its own** `docs/prompt-token-budgets.json`, and this table is that file's human mirror. The gate is fail-closed on **both** columns: every JSON agent needs a row whose **Budget** cell equals `.agents[<stem>].budget` and whose **Measured** cell equals `.agents[<stem>].measured`, and a row with no JSON entry is a ghost row. So this table cannot go stale silently — but it also **cannot be omitted**: the discovery loop always passes this file's path, and a missing file is an `ERROR contracts mirror file not found`, not a skip.

Weight is an **offline proxy** (bytes / 4) over the agent `.md` plus every skill preloaded via its frontmatter `skills:` list. It measures prompt-inventory growth, not live tokenizer counts.

| Agent (`selvedge/agents/<stem>.md`) | Budget (proxy tokens) | Measured (proxy tokens) | Preloaded skills |
|---|---|---|---|
| `qa-executor`   | 48222 | 43838 | 5 |
| `qa-strategist` | 23540 | 21400 | 3 |

**Both figures are LIVE re-measures taken after the relocation, not values carried over from loomwright.** The same change renames each prompt's frontmatter `name:`, both internal debate-loop spawn targets, and the agent-memory writer sentence, so a weight measured before those edits would be stale by construction. The `Measured` column is a frozen baseline: a later raise moves the Budget cell only.

**One preloaded skill per agent resolves CROSS-PLUGIN.** `quality-checklist` stays loomwright-owned in a single copy — the cross-plugin-resolution spike declined every alternative, including dropping the preload — so it is counted here but lives in `loomwright/skills/`. The gate attributes it in its DETAIL column as `quality-checklist@loomwright`; a skill found in **no** plugin is still a hard error.

---

## Namespace forms

Selvedge's two agents are addressed by **two different name forms**, and they are not interchangeable:

| Slot | Form | Value |
|---|---|---|
| `hooks.json` **matcher** (either plugin's) | **single**-prefix — matches the agent's frontmatter `name:` | `selvedge:qa-executor` |
| `Task(subagent_type:)` **spawn** | **doubled** | `selvedge:selvedge:qa-executor`, `selvedge:selvedge:qa-strategist` |

A wrong spawn form fails at runtime, not in CI. A wrong matcher form is worse: the QA telemetry fan-out simply stops firing, silently, because every hook command ends in `|| true`.
