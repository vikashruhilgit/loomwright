# Corpus item: what calls `read-lessons.sh`?

> **Note (2026-08-17):** authored against the retired graphify tier (the `graphify-out/graph.json` target below no longer exists); retained as evaluation-corpus evidence, content otherwise intact.

- **Type:** structural question
- **Mode:** baseline (grep-first) — compare against graph-first after Phase 1
- **Target repo / graph:** this plugin repo (`graphify-out/graph.json`)

## Question

What are all the call sites of `loomwright/scripts/read-lessons.sh`? Enumerate the agents, commands and
scripts that invoke it.

## Expected answer / rubric

Correct iff the answer enumerates the actual call sites (the agent prompts that shell out to the reader,
the sibling scripts that wrap or mirror it, and the tests that exercise it) with no fabricated callers.
Score `correct=true` only when every real caller is found and none are invented.

## What to capture

- `tool_calls`: number of Grep/Read calls needed to answer grep-first.
- `missed_context`: true if a real caller was missed (would have been surfaced by a graph "what calls
  Z" query).

> **Why a self-hosted subject.** The question shape — *enumerate every call site of one symbol, exhaustively,
> with no fabrication* — is what this item measures, not the specific symbol. Asking it against this repo keeps
> the item reproducible for anyone who clones the plugin and needs no access to a private codebase.
