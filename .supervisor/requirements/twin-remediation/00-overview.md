# Twin Remediation — overview

**Date:** 2026-07-20
**Provenance:** Full-harness audit against `loomwright/docs/SPIKES/NORTH_STAR_DIRECTION.md`. Finding: the WRITE side of the learning loop is ~5 releases ahead of the MEASURE/CURATE side. Six memory substrates with no anti-rot; Bet 5 (prove the loop) has zero shipped progress; enforcement teeth (Bet 6 Tier 1) least built; CLAUDE.md is the largest fixed context tax; orchestration machinery is generating the churn the Twin should be learning away.

## Standing policy (applies to ALL items and all future work until 01 + 02 land)

**Advisory-surface freeze:** no NEW advisory readers/stores/emitters (memos, ledgers, lenses, bridges) may ship until (a) at least one real before/after measurement has run (item 01) and (b) supersession/decay/unlearning exists for the existing stores (item 02). Bugfixes and consumers of EXISTING signals are exempt. Item 02 should encode this as a committed `.agent/rules/` entry so it survives sessions.

## Sequencing (dependency-ordered — run 01 first; 03–05 independent after)

1. `01-prove-the-loop.md` — Bet 5. Read-only measurement over data already collected. Cheapest, unblocks the freeze.
2. `02-curation-anti-rot.md` — Bet 4. Supersession/decay/unlearning + whole-stack advisory token budget.
3. `03-mechanize-rules-tier1.md` — Bet 6 Tier 1. Executable checks > advisory prose; the non-gating-compatible teeth.
4. `04-claude-md-diet.md` — shrink the per-session fixed context tax; reduce the doc-maintenance treadmill.
5. `05-orchestration-simplification-audit.md` — propose-only prune of dispatch/drain complexity. Human-gated.
6. `06-derived-artifact-freshness.md` — Bet 3 refresh half: basis-stamp + staleness probe + advisory refresh nudges for DERIVED artifacts (graphify graph, bridge, agent-memory dirs). Coordinate its agent-memory decay piece with 02's mechanism.
7. `08-session-segmentation.md` — 2026-07-23 audit: ~89% of token spend is unsegmented long sessions; fresh-context-per-iteration via the EXISTING resume/handoff machinery + context-size visibility in /insights. Independent; can run anytime.
8. `09-native-flow-adoption.md` — 2026-07-23: no backlog item asked which plugin machinery now duplicates a Claude Code primitive (review, background Agent execution, Workflow orchestration, worktree isolation), and `/capability-check`'s baseline is stale (2026-06-01 / v14.6.0 vs v15.13.0). Refresh the detector, map the overlaps, propose-only. Pairs with 07's per-release ritual.
9. `10-harness-portability.md` — 2026-07-23 strategic: run everywhere (Cursor/Codex/…), not just Claude Code. Measured: 82% of scripts (71/87, ~26k lines) are already vendor-neutral; coupling = 150 CLAUDE_PLUGIN_ROOT + 58 Task-spawn refs + 199-line hooks.json. Ports-and-adapters; ONE adapter spike before any wholesale port. **Governs 09:** native adoptions land in the Claude adapter, never the core.
10. `07-parity-ablation-eval.md` — execute the pre-registered (empty-results) FABLE_PARITY_EVAL + single-lever ablation arms; per-layer keep/cut verdicts feed 03–05. Experimental complement to 01's observational study (2026-07-20 Bitter Lesson audit reconciliation: its Phase 1–3 deletions are HYPOTHESES for these arms, not conclusions; incident-derived guards tested, not presumed dead).

## Invariants (all items)

Advisory/non-gating/fail-safe throughout per NORTH_STAR_DIRECTION.md §Invariants. Correctness gates fail CLOSED; emitters fail SAFE. Nothing here may change a `heal_decision`, block a PR, or add a new gating path — item 03's executable checks run at the EXISTING worker Step-5 verify + Phase 4.5 seams only.
