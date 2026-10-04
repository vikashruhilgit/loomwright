# S2 — Five-lane spike (OPERATOR-RUN — not an `/automate` item; no plugin change)

## Status: parked (operator-run: lives in `operator-run/` so folder intake never enqueues it; run after 08, 09, 10 and the item-10 backfill are merged and the plugin is reinstalled)

## Depends on
- 08 (shared CI slots), 09 (fewer full runs), 10 (+ its backlog backfill) merged, plugin reinstalled.
- 12 (policy answers) is optional: run S2 once without it if it is not ready, and record the question load.
- The S1 v2 harness `ai-agent-manager-lanes-v2/s1h.sh` (generalise its lane list; it already takes any lane name).

## Purpose
Owner goal (2026-10-04): **5 to 10 lanes at once.** S1 proved two lanes are isolated and that "A + relay" holds
every human gate. S2 measures what changes at five, so the default lane count (decision P2) is set from evidence,
and so 10 is attempted only if five is clean.

## Setup
1. `plan-waves --max 5 --explain` over the backfilled backlog: pick ONE wave of 5 file-disjoint items. If no wave of
   5 exists, stop and record the `--explain` output (that is item 11's input), do not force it.
2. `snapshot before` (as S1). Five clones via the harness (`setup s2-a … s2-e`, one `--seed` on a fresh throwaway
   branch `loomwright-meta-s2`). Launch all five within one minute.
3. Relay every question (the `/lanes` pane for some lanes, the main session for others — finish S1's visibility
   test here). Record each answer's latency.

## Measure
1. **CI:** `ci-slot.sh status` sampled every 10 s — slot occupancy, queue length, longest wait, per-run wall-clock
   against S1's solo 190–380 s. Full `ci-local` runs per push (item 09's target: one).
2. **Machine:** RSS of every `claude` process per lane and in total, load average, swap use, free memory — every
   60 s. (24 GB on this Mac; unmeasured until now.)
3. **Owner load:** questions per lane, human vs policy, answer latency, longest time a lane sat waiting.
4. **Merges:** merge the PRs one by one in planner order; after each, `mergeable` / `mergeStateStatus` of every
   other PR and `main`'s `ci` (item 13's input).
5. **Cost and time:** final `total_cost_usd` per session, wall-clock launch → park per lane, and the subscription
   headroom (does anything hit the weekly cap? the CI `claude-review` runs share it).
6. **Leaks:** `s1h.sh leaks` after teardown must be empty; `snapshot after` identical.

## Decide
- **P2 (default lane count):** 5 if every measure above is clean; else the largest N the data supports, with the
  limiting resource named.
- **Go/no-go for a 10-lane run (S3):** only if five was clean AND the limiting resource has headroom for double.
- **P10 (usage budget):** cost per wave against the owner's budget; record whether lanes need their own billing.

## Done when
The measures are recorded in this file's run record, P2 is set in `00-overview.md`, the five PRs are merged or
closed by the owner, and the clones and throwaway branch are removed with `leaks` empty.
