---
name: memory-tool
description: When to use Anthropic's Memory Tool vs the plugin's file-based agent memory; both are persistent stores — choice depends on runtime (direct API vs Claude Code plugin) and access model
version: "1.0.0"
lastUpdated: "2026-05-10"
---

# Memory Tool vs File-Based Agent Memory Skill

Guidance for choosing between Anthropic's **Memory Tool** (server-defined protocol with client-side storage, accessed via tool calls) and the plugin's existing **`.claude/agent-memory/`** convention (markdown files pre-loaded into agent context). Both are **persistent across sessions** — the choice is about runtime and access model, not durability.

## Overview

Anthropic's **Memory Tool** (tool type `memory_20250818`) is a server-defined protocol that lets Claude store and retrieve information across conversations through a memory file directory rooted at `/memories`. Claude issues tool calls (`view`, `create`, `str_replace`, `insert`, `delete`, `rename`) and the application executes them against a backend the developer controls (local filesystem, database, encrypted store, cloud storage). The system prompt instructs Claude to view the memory directory before any task and to record progress as it works, treating the context window as interruptible. Anthropic's docs frame the use cases as "Maintain project context across multiple agent executions," "Build knowledge bases over time," and cross-conversation learning. See the official reference: `https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/memory-tool`.

The plugin's **file-based memory** lives at `.claude/agent-memory/{agent-id}/` (typically a `MEMORY.md` plus sibling notes), is markdown-only, and is **pre-loaded into the agent's context at spawn time** via the `memory: project` frontmatter field. Six agents in this plugin already use it — Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor — see `CLAUDE.md` §"Persistent Memory". The agent does not issue tool calls to read or write; the plugin loader pulls the directory into the prompt automatically and the agent edits the file with normal `Edit`/`Write`.

Both are durable on disk. Both survive crashes. The real differences are **runtime** (where the agent is running) and **access pattern** (tool calls vs pre-loaded context).

## When to Use Memory Tool vs File-Based Memory

| Need | Use Memory Tool (`memory_20250818`) | Use File-Based `.claude/agent-memory/` |
|------|-------------------------------------|------------------------------------------|
| Runtime | Direct Anthropic API / SDK builds (Python, TypeScript, etc.) outside Claude Code | Inside the Claude Code plugin host (any agent in this plugin) |
| Access model | Claude issues tool calls; client executes against its chosen backend | Pre-injected into prompt at agent spawn via `memory: project` frontmatter |
| Storage location | Wherever the client implements (local FS, DB, S3, encrypted file, etc.); rooted logically at `/memories` | Fixed: `.claude/agent-memory/{agent-id}/` on the project disk |
| Format | Up to client; Anthropic's commands assume text files with line-numbered reads | Markdown |
| Granularity | Path-based, hierarchical (`/memories/customer_service/refunds.xml`) | One `MEMORY.md` per agent (plus sibling notes by convention) |
| Bootstrap | System prompt auto-instructs Claude to `view /memories` first | Whole directory loaded into prompt; nothing to bootstrap |
| Compaction safety | Designed to outlive context-window resets — Anthropic recommends pairing with compaction | N/A in plugin (no compaction yet — see `docs/SPIKES/compaction.md`) |
| Best-fit data shape | Many small files, structured paths, mid-run updates | Append-on-discovery markdown, narrative knowledge, cross-run accumulation |
| Lifetime | Until the client deletes it | Until the project directory is deleted or the file is edited away |
| Survives crash | Yes (file is on disk; Memory Tool is explicitly designed for "ASSUME INTERRUPTION") | Yes (file is on disk in the project) |
| Reviewable by user | Yes (whatever backend the client picks; likely visible files) | Yes (markdown files in the project) |

**Rule of thumb (decision):**

- Building on the Anthropic API / SDK directly? Add `memory_20250818` to the `tools` array and implement a backend (use `BetaAbstractMemoryTool` in Python or `betaMemoryTool` in TypeScript — both ship with the SDK).
- Building inside this Claude Code plugin? Use `memory: project` in the agent frontmatter and write markdown to `.claude/agent-memory/{agent-id}/MEMORY.md`. Don't add the Memory Tool — the plugin host doesn't propagate it to subagents anyway, and the pre-loaded markdown convention is the established path for the six memory-using agents.

The two stores are **alternatives, not tiers**. Don't try to use both for the same agent in the same project — pick the one that matches your runtime.

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

When using the Memory Tool from a direct-API build, prefer **path-based namespacing** over filename tags — the tool is designed around hierarchical paths, e.g. `/memories/redteam/audits/2026-05-10.md`, `/memories/qa/infra-confirmed/mailpit.md`, `/memories/po/decisions/auth-rewrite.md`. Each file's content can still be tagged with the prefixes above for in-file scanning.

## Lifecycle

**Create on discovery.** Write a memory entry the moment a fact is confirmed — not "I'll write it later." Late writes are the most common cause of memory drift.

**Update on contradiction.** If a new run contradicts a stored fact, the existing entry MUST be updated or deleted. Never leave two contradictory `infra-confirmed:` lines — pick one and annotate the change with a date.

**Delete on expiry.** Entries tied to a specific environment, version, or deploy that no longer exists should be removed, not retained as "history." History belongs in git, not in agent memory.

**Snapshot vs append.**
- **Append** for discoveries (each new `vuln:` is a new line — preserve the audit trail).
- **Snapshot** for state (current product roadmap, current infra topology — overwrite the prior snapshot, don't append).
- A file can mix both: append-only sections at the top, snapshot sections below, separated by a `---`.

**Memory Tool–specific lifecycle.** The Memory Tool is built around long-running agentic workflows where the context window may be reset at any time. The system-injected protocol tells Claude:

> ASSUME INTERRUPTION: Your context window might be reset at any moment, so you risk losing any progress that is not recorded in your memory directory.

So the same "create on discovery / update on contradiction / delete on expiry" rules apply, but with extra emphasis on **writing through to memory continuously**, not at end-of-run. Anthropic recommends pairing Memory Tool with compaction so important state survives server-side summarization. (For this plugin, compaction is deferred — see `docs/SPIKES/compaction.md`.)

## Per-Agent Guidance

The plugin's six memory-using agents all run inside Claude Code, so **the Memory Tool is not directly available to them as a `tools` entry** — Claude Code does not currently propagate that tool to plugin subagents. For these agents the file-based memory is the only practical path. Below: detailed guidance for the **three agents** that ship with `memory-tool` listed as a reference skill in `SKILLS_INDEX.md` (Red Team Reviewer, QA Executor, Product Owner). The other three memory-using agents (Launch Pad, Code Reviewer, QA Strategist) follow the same general patterns — pick tags by content type, append for discoveries, snapshot for current-state — and don't need agent-specific guidance here. Memory Tool guidance is included for completeness in case you mirror any of these agents' prompts into a direct-API SDK harness.

### Red Team Reviewer

- **File-based memory (in plugin):** confirmed vulnerabilities and past audit verdicts MUST be persisted across sessions — that's the whole point of the persistent memory feature for this agent.
- Use `vuln:` for confirmed findings, `audit:` for past audit summaries (date, scope, verdict), `pattern:` for recurring attack-vector exposures.
- **Memory Tool (in a direct-API mirror):** organize as `/memories/redteam/findings/<id>.md` and `/memories/redteam/audits/<date>.md`. Tell Claude in the system prompt to `view /memories/redteam/audits` before scoring a new audit so verdicts stay consistent.

### QA Executor

- **File-based memory (in plugin):** persist `infra-confirmed:` (Mailpit/MailHog endpoints, test DB credentials path, seed data conventions) and `triage:` (pre-existing failures already known and accepted, so they're not re-reported).
- **Memory Tool (in a direct-API mirror):** organize as `/memories/qa/infra/<service>.md` and `/memories/qa/triage/<test-id>.md`. The Memory Tool's "view directory first" protocol is a good fit for the 13-phase run — let Phase 1.5 infrastructure discovery cache results to `/memories/qa/infra/` and have subsequent phases read them back.
- Never store secrets in either layer. Endpoints and ports yes; credentials no.

### Product Owner

- **File-based memory (in plugin):** persist `decision:` (product decisions with rationale), `pattern:` (recurring user-research signals), and brainstorm history (past 5-lens scores, surviving recommendations).
- **Memory Tool (in a direct-API mirror):** organize as `/memories/po/decisions/<topic>.md` and `/memories/po/brainstorms/<date>.md`. The five lenses can each have their own subdirectory if the product organization is large enough to warrant it.

## Coexistence with `.claude/agent-memory/`

The two memory layers serve **different runtimes**, not different storage tiers — they are mutually exclusive in practice. Pick by where the agent runs:

- `.claude/agent-memory/` — the convention for **Claude Code plugin agents**. Pre-loaded into the prompt, edited via `Edit`/`Write`, lives at `.claude/agent-memory/{agent-id}/` in the project. This is the path for any agent in this plugin.
- Memory Tool (`memory_20250818`) — the convention for **direct Anthropic API / SDK builds**. Tool-call-based, with a client-implemented backend. This is the path for SDK harnesses outside Claude Code.

Don't mix the two for the same agent. If you mirror a plugin agent into a direct-API harness, port its memory contract over to the Memory Tool and pick one place to keep it canonical (the SDK build) — running both side-by-side will produce drift between the two stores.

The historical claim that Memory Tool is "ephemeral" or "in-conversation only" is incorrect. The Memory Tool is explicitly designed to survive context resets and conversation boundaries; that is its core use case. The relevant reason to prefer file-based memory inside this plugin is **availability** (the plugin host already pre-loads it), not durability (both are equally durable).

## References

- Anthropic Memory Tool docs: `https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/memory-tool`
- Tool type identifier: `memory_20250818`
- SDK helpers: `BetaAbstractMemoryTool` (Python), `betaMemoryTool` (TypeScript)
- Plugin file-based memory: `CLAUDE.md` §"Persistent Memory"
- Six agents using file-based memory: Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor
- Compaction deferral context: `loomwright/docs/SPIKES/compaction.md`
