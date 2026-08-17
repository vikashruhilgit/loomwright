# Corpus item: blast radius of changing `read-bridge.sh`

> **Note (2026-08-17):** authored against the retired graphify tier (its whole subject, `read-bridge.sh`, was deleted with the tier); retained as evaluation-corpus evidence, content otherwise intact.

- **Type:** structural question
- **Mode:** baseline (grep-first) — compare against graph-first after Phase 1
- **Target repo / graph:** this plugin repo (`graphify-out/graph.json`)

## Question

If I change the public output surface of `loomwright/scripts/read-bridge.sh`, what is the blast radius?
List the modules and features that depend (directly or transitively) on it.

## Expected answer / rubric

Correct iff the answer identifies the direct callers AND the transitively-affected areas (the agent
prompts that consume the reader's output, the sibling readers that mirror its fail-safe contract, and the
docs that pin that contract) without inventing dependents. Score `correct=true` only when the dependency
closure is materially complete.

## What to capture

- `tool_calls`: number of Grep/Read calls needed to trace the dependency closure grep-first.
- `missed_context`: true if a transitive dependent was missed (a graph blast-radius traversal would
  have surfaced it).

> **Why a self-hosted subject.** The question shape — *trace a transitive dependency closure across module
> boundaries without inventing dependents* — is what this item measures, not the specific module. Asking it
> against this repo keeps the item reproducible and needs no access to a private codebase.
