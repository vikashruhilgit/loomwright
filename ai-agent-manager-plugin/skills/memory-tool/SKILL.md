---
name: memory-tool
description: When to use Anthropic's Memory Tool vs the plugin's file-based agent memory; tagging conventions and per-agent guidance for Red Team / QA Executor / Product Owner
version: "1.0"
lastUpdated: "2026-05-10"
---

# Memory Tool vs File-Based Agent Memory Skill

Guidance for choosing between Anthropic's structured **Memory Tool** API and the plugin's existing file-based **`.claude/agent-memory/`** pattern. The two are complementary — not competing — and each is optimal for a different memory shape.

## Overview

Anthropic's **Memory Tool** is a structured key-value memory accessed via tool calls in API/SDK contexts (e.g., `memory.set("key", "value")`, `memory.get("key")`, `memory.delete("key")`). It is in-conversation, programmatically queryable, and best suited for ephemeral or rapidly-mutating structured state — counters, partial results, working hypotheses, retry budgets, intermediate scoring tables — that the agent needs to read/write multiple times within a single run or short series of runs.

The plugin's **file-based memory** lives at `.claude/agent-memory/{agent}/MEMORY.md` (and sibling notes), is markdown-based, and persists across sessions on disk. It is the right home for cross-session, durable knowledge accumulation: confirmed vulnerabilities, infrastructure facts, recurring failure patterns, product decisions, audit history. Six agents in the plugin already use this pattern (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor) — see `CLAUDE.md` §"Persistent Memory".

## When to Use Memory Tool vs File-Based Memory

| Need | Use Memory Tool | Use File-Based `.claude/agent-memory/` |
|------|------------------|-----------------------------------------|
| Lifetime | Single conversation / short window | Across sessions, persistent on disk |
| Shape | Structured key-value, programmatic | Markdown narrative, human-readable |
| Mutation rate | High (many writes per run) | Low (append-on-discovery, occasional edit) |
| Audience | The agent itself, mid-run | Future runs, future agents, the user |
| Examples | Retry counters, partial scores, in-flight findings, dedup keys | Confirmed CVEs, infra topology, product decisions, prior audit verdicts |
| Survives crash | No (lost with conversation) | Yes (committed to filesystem) |
| Reviewable by user | No (opaque) | Yes (markdown files) |
| Best for | Working memory | Long-term memory |

**Rule of thumb:** if you'd want the next session to see it, write it to a file. If it's only useful for this run's bookkeeping, put it in the Memory Tool.

## Tagging Conventions

When writing to file-based memory, prefix entries with a tag so future agents can scan and filter quickly. Recommended tags:

- `vuln:` — confirmed vulnerability finding (Red Team)
- `infra-confirmed:` — verified infrastructure fact (Mailpit running on :8025, Redis on :6379, etc.)
- `infra-suspected:` — unverified infrastructure assumption; promote to `infra-confirmed:` after observation
- `decision:` — product or architectural decision with rationale
- `pattern:` — recurring code or failure pattern worth flagging on future review
- `triage:` — pre-existing failure already accepted/triaged; don't re-flag
- `audit:` — past audit outcome (date + verdict + scope)
- `debt:` — known technical debt deferred for a reason

Memory Tool keys (when used) should follow `{namespace}.{purpose}` style, e.g., `redteam.findings_count`, `qa.retry_budget`, `po.score.option_3`.

## Lifecycle

**Create on discovery.** Write a memory entry the moment a fact is confirmed — not "I'll write it later." Late writes are the most common cause of memory drift.

**Update on contradiction.** If a new run contradicts a stored fact, the existing entry MUST be updated or deleted. Never leave two contradictory `infra-confirmed:` lines — pick one and annotate the change with a date.

**Delete on expiry.** Entries tied to a specific environment, version, or deploy that no longer exists should be removed, not retained as "history." History belongs in git, not in agent memory.

**Snapshot vs append.**
- **Append** for discoveries (each new `vuln:` is a new line — preserve the audit trail).
- **Snapshot** for state (current product roadmap, current infra topology — overwrite the prior snapshot, don't append).
- A file can mix both: append-only sections at the top, snapshot sections below, separated by a `---`.

**Memory Tool entries** are auto-discarded at conversation end — no explicit lifecycle needed unless you're using a long-lived session.

## Per-Agent Guidance

### Red Team Reviewer

- **File-based memory primary.** Confirmed vulnerabilities and past audit verdicts MUST be persisted across sessions — that's the whole point of the persistent memory feature for this agent.
- Use `vuln:` for confirmed findings, `audit:` for past audit summaries (date, scope, verdict), `pattern:` for recurring attack-vector exposures.
- Memory Tool: optional, useful for in-run tracking of finding counts per attack vector or dedup keys when re-scanning a large diff.

### QA Executor

- **File-based memory primary** for `infra-confirmed:` (Mailpit/MailHog endpoints, test DB credentials, seed data conventions) and `triage:` (pre-existing failures already known and accepted, so they're not re-reported).
- Memory Tool: useful within a single 13-phase run for tracking per-phase gate-pass counts, retry budgets, and the in-flight gap report before it's emitted.
- Never store secrets in either layer. Endpoints and ports yes; credentials no.

### Product Owner

- **File-based memory primary** for `decision:` (product decisions with rationale), `pattern:` (recurring user-research signals), and brainstorm history (past 5-lens scores, surviving recommendations).
- Memory Tool: useful within a single brainstorm run for the working scoring table across the 5 lenses before consolidation, and for tracking which options have already been challenged by the Critic lens.

## Coexistence with `.claude/agent-memory/`

The two memory layers are **complementary, not competing**. Treat them as different storage tiers with different access patterns:

- `.claude/agent-memory/` is the **durable** layer — survives session end, reviewable by humans, lives in version control or local storage, accumulates knowledge over time.
- The Memory Tool is the **working** layer — fast, structured, in-conversation only, ideal for bookkeeping the agent needs but the user doesn't.

A well-instrumented agent run typically uses **both**: the Memory Tool for intra-run state, the file-based memory for inter-run knowledge. At session end, the agent should explicitly promote any Memory-Tool findings worth keeping to the file-based layer (this is the same "create on discovery" rule, just batched at the end of the run).

Do NOT replace one with the other. Replacing file-based memory with the Memory Tool loses cross-session continuity (the whole reason `memory: project` exists in the agent frontmatter). Replacing the Memory Tool with file-based memory turns transient bookkeeping into noisy markdown the user has to scroll past forever.

## References

- Anthropic Memory Tool docs: `https://docs.anthropic.com/en/docs/build-with-claude/memory`
- Plugin file-based memory: `CLAUDE.md` §"Persistent Memory"
- Six agents using file-based memory: Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor
