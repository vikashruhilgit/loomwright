# Corpus item: what calls `reservationCreate`?

- **Type:** structural question
- **Mode:** baseline (grep-first) — compare against graph-first after Phase 1
- **Target repo / graph:** sports-management (`graphify-out/graph.json`)

## Question

What are all the call sites of `reservationCreate`? Enumerate the functions/modules that invoke it.

## Expected answer / rubric

Correct iff the answer enumerates the actual call sites (booking flow controller, any scheduled job,
and tests that exercise the create path) with no fabricated callers. Score `correct=true` only when
every real caller is found and none are invented.

## What to capture

- `tool_calls`: number of Grep/Read calls needed to answer grep-first.
- `missed_context`: true if a real caller was missed (would have been surfaced by a graph "what calls
  Z" query).
