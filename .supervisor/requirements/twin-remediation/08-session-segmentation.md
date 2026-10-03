# 08 — Session segmentation: fresh contexts per unit of work instead of one endless session

## Problem
2026-07-23 outcome-data audit: ~89% of token spend traces to long-running sessions whose context never resets (autonomous/automate loops and interactive sessions pushed toward 1M tokens; token_ledger proxies show single agent transcripts at 0.9–1.5MB). The loop designs treat "never stops" as a virtue; the additive cost curve is invisible because nothing fails — it just costs more. The resume machinery (state.md, session-resume hook, `--continue`, single-iteration-safe re-runs) already makes segmentation nearly free; nothing exploits it.

## Goal
Make fresh-context-per-unit the default shape of long-running work, using ONLY existing resume/handoff machinery. No new stores (freeze-compatible).

## Scope
1. **Loop segmentation:** `/autonomous` multi-iteration and `/automate` per-item loops get an opt-in (then, if 07/ledger data supports, default) mode where each iteration/queue-item runs as a FRESH dispatched session (`claude -p` with the namespaced command, per the detached-dispatch lessons) that reads its inheritance from state.md + the handoff digest, instead of continuing inline in the parent context. The run file / state.json remains the contract across segments (it already is — this is using the design as designed).
2. **Context-size visibility:** `/insights` reports per-session transcript-byte distribution from existing token_ledger lines and flags sessions past a documented threshold with the one-line remedy ("segment: resume via /supervisor --continue in a fresh session"). Advisory only.
3. **Doc the habit:** a short section in README/AGENT_GUIDELINES — segment at natural checkpoints (post-PR, post-phase); `/handoff` is the catch-up; long-lived interactive sessions are a smell, not a badge.
4. **Guard:** segmented dispatch must respect the existing single-drain/marker invariants (no double-dispatch across segment boundaries — reconcile via markers, not control-flow belief).

## Non-goals
No new state formats, no scheduler, no forced kills of running sessions, no changes to the resume validation gate's fail-closed semantics.

## Acceptance criteria
- A multi-item `/automate` (or multi-iteration `/autonomous`) run demonstrably completes across ≥2 fresh sessions with correct state inheritance (traced end-to-end, not asserted).
- Per-session context distribution visible in `/insights` from real ledger data.
- Marker-based dispatch reconciliation verified across a segment boundary (falsify: simulate a stale marker).

## Outcomes Rubric
- Fresh-session-per-item mode works end-to-end on a real 2-item run
- Context-size section live in /insights with real numbers
- No invariant regressions (single-drain, resume fail-closed)
