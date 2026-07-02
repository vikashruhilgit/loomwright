# Corpus item: blast radius of changing `lib/session.ts`

- **Type:** structural question
- **Mode:** baseline (grep-first) — compare against graph-first after Phase 1
- **Target repo / graph:** sports-management (`graphify-out/graph.json`)

## Question

If I change the public surface of `lib/session.ts`, what is the blast radius? List the modules and
features that depend (directly or transitively) on it.

## Expected answer / rubric

Correct iff the answer identifies the direct importers AND the transitively-affected feature areas
(auth middleware, any guard/session-checking layer, the affected pages/routes) without inventing
dependents. Score `correct=true` only when the dependency closure is materially complete.

## What to capture

- `tool_calls`: number of Grep/Read calls needed to trace the dependency closure grep-first.
- `missed_context`: true if a transitive dependent was missed (a graph blast-radius traversal would
  have surfaced it).
