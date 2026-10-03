# 07 — Route-not-preload + staleness stamps + unified tools lists (4f, 4g, 4c; D7, D8)

Three related token/freshness fixes; 4c gets its own PR (plugin-wide frontmatter change).

> **UNBLOCKED (2026-07-29).** This previously read *"Strictly AFTER item 03 (4d split) — routing an
> unsplit 110k skill changes when it is paid, not how much."* **That dependency does not exist.**
> `self-heal-advisory` is not a 4f routing target: `agents/supervisor.md` frontmatter preloads
> exactly seven skills (`workflow-management`, `async-orchestration`, `state-management`,
> `context-summarization`, `supervisor-readiness`, `commit`, `quality-checklist`) and
> `self-heal-advisory` is **absent** — it is already read-on-demand at Phase 4.5 entry on both the
> agent and the inline path. 4f's actual double-pay is `async-orchestration` (9,078 proxy tokens),
> unaffected by the split. Separately, **the 4d split was evaluated and REJECTED** (Part 2 invokes
> all ten Part 1 sections; the Read is once at phase entry, not per heal iteration) — see
> `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4d and §4f. **Item 07 has no precondition and
> can start at any time.**

## Problem
- **4f:** supervisor-runner preloads 7 skills via frontmatter while the recommended inline
  `/supervisor` path preloads none and reads 5 at phase entry — the inline path is the existing
  proof preloading is not required. `async-orchestration` is paid twice on the agent path (9,078
  proxy tokens). CAVEAT (verified): the double-load is documented as an intentional "refresh
  guarantee for compressed contexts" (`agents/supervisor.md` Phase 4 §"Protocol authority (read at
  phase entry)"; cited by section name — the former `:336` pin had drifted to `:361`) — the change
  must argue that trade-off (route + re-Read-on-compaction) and win it, not treat it as a bug.
- **4g:** brief staleness is never checked — Launch Pad stamps no base commit, so preflight has no
  anchor. Churn, not elapsed time, is the right signal (a 3-week-old brief on an untouched
  subsystem is fine; a 2-hour-old brief on a just-refactored one is not).
- **4c:** 13 distinct `tools:` lists across 14 agents; render order is tools→system→messages, so
  agents diverge at byte 0 and share no cache prefix — which is why the v15.13.0 shared-prefix
  block cannot buy cross-agent sharing yet. (512-token minimum cacheable prefix: the unified tools
  block + shared prefix stacked is what clears the floor.)

## Scope
1. 4f: replace supervisor-runner's frontmatter `skills:` with the phase-entry Reads the inline path
   uses; preserve a compaction-refresh Read where the documented rationale holds. Budgets +
   contracts mirror updated (check-token-budget raise rule).
2. 4g: (a) Launch Pad Phase 5 PACKAGE stamps `- **Base commit:** {sha}` beside
   `- **Source requirement:**`; (b) preflight-sync gains a 4th signal:
   `git log --oneline $BRIEF_BASE_SHA..origin/$BASE_BRANCH -- $ANTICIPATED_PATHS | wc -l` over the
   file set it already computes. Order (a) then (b) — no value until the stamp exists. Reconcile
   with twin-remediation 06 (derived-artifact freshness) at PLAN — overlap, don't duplicate.
3. 4c (own PR): unify `tools:` to a superset across the 14 agents; verify no agent gains a tool its
   contract forbids (read-only roles keep enforcement via `disallowedTools`, the mechanism that
   survives plugin distribution).

## Non-goals
No skill content changes — **note (2026-07-29): this previously read "(03 did the split)", which is
false; item 03 did NOT split `self-heal-advisory`, the split was rejected.** The non-goal itself
still holds: 4f moves *when* a skill is read, not what is in it, and no split is a prerequisite for
that. No new gates.

## Acceptance criteria
- supervisor-runner routed; double-pay gone or explicitly retained with the argued rationale.
- Briefs carry base-commit stamps; preflight churn signal live and fail-safe.
- Tools superset landed; read-only enforcement verified per-agent; cache-prefix claim re-measured
  (honest framing: consistency win unless the 512-token floor is actually cleared).

## Outcomes Rubric
- 4f routed with trade-off argued in the PR
- 4g stamp + churn signal, in dependency order
- 4c superset + disallowedTools verification
- Token/budget gates green; measurements recorded

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-07-30-route-freshness-4f-4g.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
