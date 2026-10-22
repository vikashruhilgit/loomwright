# 08 — Session segmentation: fresh contexts per unit of work instead of one endless session

## Status: done (closed 2026-10-22 after a read-only re-verification against main 7b7cb08: items 2–3 shipped in #487; items 1 and 4 shipped as `08b-single-lane-sequential.md` in PR #548 (`--parallel 1` = one fresh lane per item); automate-speed/09 (#628) made a fresh headless session per phase the default, `--inline-phases` the rollback; the `/autonomous` multi-iteration half of item 1 was dropped by the owner, recorded in 08b)

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

## Re-scope (2026-10-12, validated read-only against main cee4e94; owner-requested)
- **Item 1 partial precedent only:** `--parallel N` lanes (2026-10-07) run one item per headless session, but only for N ≥ 2 in a separate clone; the sequential loop and /autonomous still run inline. Lane resume reuses the LAST session (the opposite of segmenting).
- **In flight (direct):** items 2 (per-session context size in /insights, advisory threshold + remedy line) and 3 (docs) — branch `feat/tr08a-insights-session-size`.
- **Refine before running items 1 and 4:** (a) segmented mode = reuse lanes with N=1 in the primary, or a new sequential dispatch; (b) how `run.lock` hands over between segments (it is re-entrant only for the same session id); (c) threshold and opt-in vs default — item 07, cited as the trigger, is ABANDONED.
- **Proposed Touches** for the rest: `loomwright/skills/automate-loop/{SKILL.md,lanes.md}`, `loomwright/skills/autonomous-loop/SKILL.md`, `loomwright/scripts/automate-lanes.sh` or `automate-helpers.sh`, `loomwright/scripts/run-lock.sh`, `README.md`, `AGENT_GUIDELINES.md`. Depends on: none.
- **Shipped 2026-10-12 in v15.133.0** (integration PR #493, merge b6e1100): items 2–3 (/insights per-session context size, 3 MB advisory threshold; README tip) — PR #487. **Remaining:** items 1 and 4 (owner decisions). Requirement stays open.

- **2026-10-13:** items 1 and 4 rewritten as `twin-remediation/08b-single-lane-sequential.md` (the `/autonomous` half of item 1 dropped). Nothing left to run in this file.
