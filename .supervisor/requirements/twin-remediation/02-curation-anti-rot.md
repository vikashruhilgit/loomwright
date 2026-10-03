# 02 — Curation / anti-rot (Bet 4): supersession, decay, unlearning, whole-stack budget

## Problem
Judgment now lives in six stores — agent memory dirs, LESSONS (`/dreaming`), `.agent/rules/`, `.agent/orientation/`, findings→community bridge, postmortem/churn JSONL — with no supersession, decay, or unlearning. North star Bet 4: "without these the advisory signal degrades and the Twin gets *worse* than none." Each reader is individually bounded but nothing budgets the SUM of advisory tokens injected per run.

## Goal
Give the existing stores (no new ones) a curation lifecycle and a whole-stack token budget.

## Scope
1. **Supersession:** a common optional header/field (`supersedes: <id|slug>`) recognized by the readers of lessons, rules, and orientation memos — a superseded entry is skipped at read time (demote-never-crash), and `/dreaming` gains a per-item "supersede X" action alongside Accept/Reject.
2. **Unlearning:** a mechanized delete/correct path — `/dreaming` (or `/rules`) per-item Retract that removes/marks-retracted an entry in any of the three committed/curated stores, with a one-line provenance record of why. Human-gated per item, mirroring existing Accept semantics.
3. **Decay flagging (advisory):** readers already demote stale entries; add a periodic surface (a `## Stale knowledge` section in `/insights` or `/dreaming` intake) listing entries whose `head_sha`/basis no longer resolves or whose age exceeds a threshold — candidates for human retire/refresh. Flag only; never auto-delete.
4. **Whole-stack advisory budget:** `emit-token-ledger.sh` (or a sibling) records per-run TOTAL advisory-context chars/tokens across memos+rules+bridge+brain-context via the existing `orientation_source`-style plumbing; `/insights` reports it against a documented target so item 01's cost side stays measured. Advisory reporting only — never truncates or gates at runtime beyond existing per-reader caps.
5. **Cross-harness visibility bridge (2026-07-21 memory-audit reconciliation):** when `/dreaming` Accepts a LESSON, also ensure ONE pointer line exists in the repo's Claude-harness memory (a `reference`-type memory pointing at `.supervisor/memory/LESSONS.md`) so ordinary non-plugin sessions can find the deep store. One line per repo, idempotent — not a sync, a signpost.
6. **Freeze rule:** add the standing advisory-surface freeze (see 00-overview) as a committed `.agent/rules/` entry via `add-rule.sh --confirm` (category: process, enforcement: advisory, provenance: this remediation).

## Non-goals
No new stores, no store merging/migration (consolidating six→fewer stores is a possible follow-up informed by item 01's verdicts), no cross-repo transfer, nothing gating.

## Acceptance criteria
- A superseded lesson/rule/memo demonstrably disappears from reader output (test per store, mechanical).
- Retract path exercised end-to-end on a fixture entry in each store; falsify with a malformed `supersedes` value (fail-safe skip, per the acceptance-check-vs-adversarial-review lesson).
- Whole-stack advisory total visible in `/insights` for a real run.
- All readers remain always-exit-0 fail-safe; counts/doc-currency gates green.

## Outcomes Rubric
- Supersession honored by all three curated-store readers
- Human-gated retract path exists and is tested
- Per-run whole-stack advisory token total is recorded and reported
- Freeze rule committed to .agent/rules/

## Status: done

Shipped v15.14.0 via PR #106 (feature/curation-anti-rot). Phase 4.5 heal_decision PASS (1 iteration), rubric 4/4, 594 tests, 7/7 CI gates. Scope reconciled against merged PR #98 (v15.7.0) — lessons retraction and the postmortem-corpus curation tool already existed and were not rebuilt.
