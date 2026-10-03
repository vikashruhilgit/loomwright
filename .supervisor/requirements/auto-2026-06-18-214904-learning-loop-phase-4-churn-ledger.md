<!-- Outcomes Rubric: leave blank for multi-iteration auto-authoring, or add a "## Outcomes Rubric" section with diff-checkable bullets -->

# Requirement: Learning Loop Phase 4 — Churn Loop (Postmortem as Ledger)

## Source

Derived from `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` §"Phase 4 — Churn Loop: Postmortem as Ledger". Phases 0–3 + 2B are already shipped (verified against the tree at v14.35.0); Phase 4 is the next pending slice and its gate is unblocked (it was gated on "Phase 2 measurement observable", satisfied by v14.33.0 / #66). The *write* side of the postmortem corpus already shipped in v14.30.0 / #63 (`dispatch-pr-postmortem.sh` churn-gated auto-dispatch + `pr-postmortem-gather.sh`); the unclosed loop is **read-back + provenance enrichment**.

## Goal

Close the PR-churn learning loop: turn the append-only postmortem corpus (`.supervisor/postmortem/results.jsonl`) into an actionable **ledger** by (1) enriching `POSTMORTEM_RESULT` with provenance and (2) building a read-back path that feeds prior-churn patterns into planning (Launch Pad) and self-heal (Supervisor Phase 4.5). Strictly **advisory, fail-safe, non-gating** — never changes `heal_decision`, review verdicts, or any gate, and subordinate to `CLAUDE.md`.

## Current State (verified against the tree)

- `POSTMORTEM_RESULT` (schema_version 1, `skills/pr-postmortem/SKILL.md` Step 5 + `docs/RESULT_SCHEMAS.md`) currently carries: `schema_version, ts, repo, number, agent_generated_guess, review_rounds, additions, deletions, changed_files (count), categories[] (per-round class + self_heal_miss + flow_stage + evidence), self_heal_misses, flow_stages{}, summary, plugin_version`.
- The corpus is explicitly **write-only today** — `skills/pr-postmortem/SKILL.md:172`: "It is never read back by this skill (write-only trend)." No consumer reads it back.
- Provenance is thin: only `number` (PR number) is present — no `pr_url`, `brief_path`, `job_path`, `branch`, or the list of changed paths.

## Scope (Full Phase 4)

### 1. Provenance enrichment (additive, backward-compatible)
- Enrich `POSTMORTEM_RESULT` with provenance fields the roadmap names: `pr_url`, `brief_path`, `job_path`, `branch`, and `changed_paths` (the **list** of changed file paths — distinct from the existing `changed_files` count).
- `pr-postmortem-gather.sh` emits the new raw signals where it can derive them read-only (`pr_url`, `branch`/`headRefName`, `changed_paths` via `gh pr view --json files`); `brief_path`/`job_path` are best-effort (often unknowable for an arbitrary external PR — emit `null`/empty when not derivable, never invent).
- Fields are **additive and optional**; old corpus lines remain valid (follow the `plugin_version` precedent — keep `schema_version` at 1 with new optional fields unless a bump is clearly warranted, in which case keep v1 lines accepted).
- Update `docs/RESULT_SCHEMAS.md` POSTMORTEM_RESULT schema + the `skills/pr-postmortem/SKILL.md` trend-line schema table to document the new fields.

### 2. Read-back path (new helper script)
- Add a fail-safe read-back helper (e.g. `scripts/read-postmortem.sh`) mirroring the existing `read-lessons.sh` / `read-project-memory.sh` conventions: given a set of changed paths / an area, it summarizes prior churn from `.supervisor/postmortem/results.jsonl` (e.g. which root-cause classes / flow_stages recurred for overlapping paths, how many prior churn rounds).
- **Fail-safe:** exits 0 with empty/quiet output when the corpus is absent, empty, or `jq` is missing; bounded output; jq-only parsing (no untrusted PR text string-interpolated). Never blocks a run.
- Ship a self-test (`test-read-postmortem.sh`) + a fixture corpus, following the existing `test-*` / fixture conventions.

### 3. Wire read-back into Launch Pad (planning)
- Launch Pad consults the read-back helper during codebase analysis / risk assessment to surface **prior churn risk for the touched areas** as advisory Risk Assessment rows (so future planning can answer "have similar PRs churned before, and why?").
- Advisory only — never blocks the brief, never changes feasibility GO/CAUTION/NO-GO by itself.

### 4. Wire read-back into Supervisor Phase 4.5 (self-heal)
- Supervisor Phase 4.5 enriches its review/fix prompt with **known prior churn miss-classes for the touched files** (so self-heal can apply known miss-classes from prior churn), routed through the existing advisory machinery (`self-heal-advisory` skill).
- Advisory only — never changes `heal_decision`, never drives the fix task on its own, never gates or blocks the PR.

## Acceptance Criteria

- [ ] Given an enriched postmortem run, when `POSTMORTEM_RESULT` is appended, then it carries `pr_url`, `brief_path`, `job_path`, `branch`, `changed_paths` (additive); and given an OLD corpus line without these fields, when any consumer parses it, then it still parses cleanly.
- [ ] Given `.supervisor/postmortem/results.jsonl` is absent/empty or `jq` is missing, when the read-back helper runs, then it exits 0 with quiet/empty output and never errors.
- [ ] Given prior churn entries whose `changed_paths` overlap the current touched area, when Launch Pad runs, then it surfaces a prior-churn advisory Risk Assessment row (and produces no such row when there is no overlap).
- [ ] Given prior churn miss-classes for files in the integrated diff, when Supervisor Phase 4.5 runs, then its review/fix prompt is enriched with those classes — and `heal_decision` and gating behavior are demonstrably unchanged by the enrichment.
- [ ] The postmortem corpus is NOT passed to workers (workers stay focused — roadmap §5 non-goal).
- [ ] New/updated self-tests pass; `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` pass.
- [ ] Plugin version bumped; CLAUDE.md release banner + `CHANGELOG.md` entry added; doc counts (agents/commands/skills/hooks) updated in the same change if any surface count changes.

## Non-Goals (roadmap §5 + Phase 4 boundaries)

- No `/setup brain`, no brain write-back, no trusted wiki writes (those are Phases 5–6).
- No new memory **directory** (reuse `.supervisor/postmortem/`).
- No gating changes anywhere — advisory only.
- No worker memory/postmortem reads.
- No vector/RAG store, no CI-reviewer convergence project.
- Do not change `heal_decision`, review verdicts, or feasibility verdicts based on ledger content.

## Constraints

- Every new artifact needs a named consumer + a read path (roadmap §1 requirement 4).
- Advisory machinery only; subordinate to `CLAUDE.md` (roadmap §1 requirements 2, 6).
- Use structured, scoped reads (only relevant churn entries), not blanket context (roadmap §1 requirement 7).
- Fail-safe side-effect emitters always `exit 0` (the plugin's bimodal failure philosophy — runtime emitters fail SAFE).

<!-- ai-agent-manager:requirement-closeout -->
## Status
- **Status:** done
- **Completed:** 2026-06-18T17:27:37Z
- **Brief:** .supervisor/jobs/done/auto-2026-06-18-214904-learning-loop-phase-4-churn-ledger.md
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/69
