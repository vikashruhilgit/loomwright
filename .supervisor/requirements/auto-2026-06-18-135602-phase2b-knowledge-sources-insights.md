# Requirement: Learning Loop Phase 2B — knowledge_sources_used measurement close-out

<!-- Outcomes Rubric: leave blank for multi-iteration auto-authoring, or add a "## Outcomes Rubric" section with diff-checkable bullets -->

## Source

`ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` §"Phase 2B — Measurement close-out".

Derived as the next pending phase by `/autonomous` after verifying against the tree (v14.32.0):
Phases 0/1/2(emit)/3 are shipped; Phase 2B is the roadmap's recommended-next slice AND the
explicit prerequisite for Phase 4 ("Phase 4+ — Start only after Phase 2 measurement is observable").

## Problem

The `knowledge_sources_used` telemetry shipped in v14.28.0 (Phase 1+2) is **emitted but never
consumed**. It is written to `SUPERVISOR_RESULT` / `CODE_REVIEW_RESULT` result blocks and the flat
`session_end` JSONL line, but `scripts/build-insights.sh` has **zero** references to it, so `/insights`
cannot answer "which knowledge sources did recent runs actually use?". The Phase 2 success signal —
*distinguish "memory existed" from "memory was actually used"* — is recorded but not observable.
Additionally, `LAUNCH_PAD_RESULT` carries no `knowledge_sources_used` field, so Launch Pad's
project-memory / lessons reads remain unmeasured while Supervisor and Code Reviewer are measurable.

## Goal

Close the Phase 2 measurement loop: make `knowledge_sources_used` observable in `/insights`, and add
the optional Launch Pad usage marker so all three APPLY-path agents are machine-measurable.

## Scope (additive, advisory, non-gating)

1. **Wire `build-insights.sh` to read the flat `session_end.knowledge_sources_used` array** from the
   `.supervisor/logs/*.jsonl` session logs (the surface Phase 1+2 already writes).
2. **Surface per-run knowledge sources** in the generated run notes and the dashboard summary.
3. **Add a small trend view:** count of runs with any knowledge source, top source tags, and per-version
   usage.
4. **Add optional `LAUNCH_PAD_RESULT.knowledge_sources_used`** so Launch Pad's project-memory / lessons
   reads are machine-measurable too — emitted in Launch Pad Phase 7, accepted by
   `scripts/validate-launch-pad-result.py`, documented in `docs/RESULT_SCHEMAS.md`.
5. **Update the self-test** (`scripts/test-insights.sh`) to cover the new aggregation, and any
   `validate-launch-pad-result` self-test if one exists.
6. **Mark Phase 2B done** in `LEARNING_LOOP_ROADMAP.md` and record residual/deferred items honestly.

## Acceptance Criteria

- [ ] Given session logs containing `session_end` lines with a `knowledge_sources_used` array, when
      `build-insights.sh` runs, then the generated dashboard reports which knowledge sources were claimed
      by recent runs (per-run list + a trend view: runs-with-any-source, top tags, per-version usage).
- [ ] Given a `session_end` line **without** the field (old logs), when `build-insights.sh` runs, then it
      parses cleanly with no error and simply reports zero/none for that run (backward compatible).
- [ ] Given a `LAUNCH_PAD_RESULT` block with an optional `knowledge_sources_used` array, when
      `validate-launch-pad-result.py` validates it, then it passes; and a block **without** the field still
      validates (additive/optional, no `schema_version` bump).
- [ ] Launch Pad, Supervisor, and Code Reviewer all have a machine-readable usage marker (or the Launch
      Pad gap is explicitly closed by this change).
- [ ] `scripts/test-insights.sh` covers the new aggregation and passes.
- [ ] `LEARNING_LOOP_ROADMAP.md` marks Phase 2B as shipped; deferred items recorded.

## Hard Constraints / Invariants (do not violate)

- **Additive + optional + self-reported + non-gating.** No `schema_version` bumps (the field is the
  `executable_acceptance` additive-field precedent). Missing field stays valid for old logs and old
  result blocks.
- **No new storage surfaces, no new gating, no new memory directories** (roadmap §5 non-goals).
- **Doc-currency is CI-enforced** (`scripts/check-doc-currency.sh` + `validate-version.sh`): if the change
  bumps the version or changes any agent/command/skill/hook count, the doc claims (plugin.json,
  marketplace.json description, CLAUDE.md headline/banner, counts) MUST be updated in the same change or
  CI fails. This change adds **no** new agent/command/skill/hook — counts stay 14/18/55/19.
- Use `${CLAUDE_PLUGIN_ROOT}` for any runtime asset paths, never `ai-agent-manager-plugin/...`.
- Keep the plugin `description` a crisp summary — bump only the `vX.Y.Z` string + counts in place; put the
  release narrative in `CHANGELOG.md` and (if notable) one CLAUDE.md banner. Do not append a version clause.

## Key Files (Launch Pad to verify/expand via codebase analysis)

- `ai-agent-manager-plugin/scripts/build-insights.sh` — aggregation/display (primary)
- `ai-agent-manager-plugin/scripts/test-insights.sh` — self-test
- `ai-agent-manager-plugin/commands/insights.md` — dashboard section docs
- `ai-agent-manager-plugin/scripts/validate-launch-pad-result.py` — accept optional field
- `ai-agent-manager-plugin/agents/launch-pad.md` — Phase 7 LAUNCH_PAD_RESULT emission
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` — document the additive field
- `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` — mark Phase 2B done
- `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`,
  `CHANGELOG.md` — version bump + doc-currency


## Status: done
- Shipped in 14.33.0 via PR https://github.com/vikashruhilgit/ai-agent-manager/pull/66 on 2026-06-18T09:04:58Z
