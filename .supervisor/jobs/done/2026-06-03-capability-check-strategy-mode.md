# Supervisor Job: Evolve /capability-check into a Product-Evolution Strategist

> Plan Review: **PASS** (attempt 1/1) · Date: 2026-06-03 · Slug: capability-check-strategy-mode

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager (the plugin's own repo)
- **CLAUDE.md:** ✓ Found, fresh (v14.7.0)
- **Git:** branch `main`, **1 commit behind `origin/main`** (fast-forwardable). No staged/modified tracked files, but
  **untracked:** `.claude/` and `ai-agent-manager-plugin/docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`.
- **GitHub CLI:** ✓ Authenticated (`vikashruhilgit`)
- **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 2
- **legacy_brief:** false

### ⚠️ Pre-run requirements (do BEFORE `/supervisor`)
1. **`git pull`** — fast-forward `main` to `origin/main` so the run builds on the latest base.
2. **Commit `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`** — this brief references it, and untracked files do NOT propagate
   into git worktrees where workers run.

## Vision (North Star)
`/capability-check` today only diffs what is NEW in Claude Code against a tracked baseline and reports **adoption** candidates
(platform features to adopt). That is reactive — it keeps the plugin **current**, never **unique**. Evolve it to ALSO think
like a senior product strategist: propose net-new, **differentiated product directions** (how to make the plugin uniquely
better than stateless task-runners, leveraging what is newly feasible in AI) — exactly like the System-Twin reframe produced
in this session — while preserving the command's existing red-teamed discipline (bounded, rare, actionable, propose-only,
suppress-when-nothing-new, never self-applies).

## Task
**Goal:** Add a `--strategy` mode (plus supporting tracked state) to `/capability-check` that performs a **grounded**
product-evolution pass. It reads the product's real surface (`agents/`, `commands/`, the flywheel/insights state,
`docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`) + the existing platform diff + a **bounded** frontier-AI signal, and emits
**scored direction candidates** — each citing the specific gap/asset it addresses, why it is differentiating (moat), what is
newly feasible (platform or frontier-AI enabler), rough effort/risk, and a concrete wedge — deduped against directions already
tracked in the baseline. **Propose-only:** a direction becomes work only via a human-chosen `/launch-pad`. Default (no flag)
behavior is **unchanged**.

## Acceptance Criteria
- [ ] **Mode:** `/capability-check --strategy` runs the product-evolution pass; default behavior with no flag is UNCHANGED
  (pure adoption diff). The two report types (adoption candidates vs product directions) are distinct.
- [ ] **Grounding mandate:** every DIRECTION cites ≥1 concrete product asset (named agent/command/gap) AND ≥1 newly-feasible
  enabler (platform capability or frontier-AI trend). Directions that cannot ground both are dropped — no generic advice.
- [ ] **Scoring + suppression:** directions are scored (differentiation/moat × feasibility × effort) and ranked; if none clear
  the bar, emit exactly one suppression line and stop (no padding) — mirroring the existing no-change suppression contract.
- [ ] **Dedup:** directions already present in the baseline's new `product_directions` section (status adopted/proposed/deferred)
  are NOT re-proposed.
- [ ] **Propose-only / bounded / human-gated:** never self-applies any plugin change; honors `--max-fetches`; `--update-baseline`
  remains the only write path and only with that explicit flag (records direction status, never edits plugin code).
- [ ] **Anti-rebloat:** zero new commands (a mode of the existing command); no new agent/skill/hook; doc-currency gate passes.

## Subtask Structure

### ST1 — Strategy mode in the command spec  [foundation]
**Files:** `commands/capability-check.md` (modify).
**Work:** Add the `--strategy` workflow section — grounding inputs (which product files/state it reads), the bounded frontier-AI
signal step (WebSearch/Context7 within `--max-fetches`, optional), the scoring rubric, the DIRECTION candidate output format
(gap/asset, moat, newly-feasible enabler, effort-risk, wedge), the suppression rule, dedup against `product_directions`, and the
propose-only/never-self-apply guardrails. Reuse the **brainstorming** skill's 5-lens scored-debate discipline as the (bounded)
ideation engine. Define the `product_directions` baseline contract that ST2 instantiates.
```yaml
provides:
  - {kind: capability, path: commands/capability-check.md, name: strategy_mode}
  - {kind: contract, path: commands/capability-check.md, name: product_directions_schema}
requires: []
```

### ST2 — Baseline product-direction state  [dep ST1]
**Files:** `docs/CAPABILITY_BASELINE.json` (modify).
**Work:** Add a `product_directions` section (entries with `id`, `title`, `status` adopted|proposed|deferred, provenance/date,
one-line rationale) following the schema defined in ST1; seed it with the directions already surfaced this session (e.g. System
Twin = proposed, with its three pillars) so the next `--strategy` run does not re-flag them; document the new fields in the JSON
`_comment`.
```yaml
provides:
  - {kind: data, path: docs/CAPABILITY_BASELINE.json, name: product_directions_state}
requires:
  - {kind: contract, name: product_directions_schema, from: ST1}
```

### ST3 — Docs, version, currency  [dep ST1-2]
**Files:** `CLAUDE.md` (modify), `README.md` (modify), `ai-agent-manager-plugin/.claude-plugin/plugin.json` (modify),
`.claude-plugin/marketplace.json` (modify), `CHANGELOG.md` (modify).
**Work:** CLAUDE.md banner; README note under `/capability-check`; version bump + in-place description refresh on both manifests
(**no** command-count increase — it is a mode, not a command); CHANGELOG entry; ensure `scripts/check-doc-currency.sh` passes.
```yaml
provides:
  - {kind: capability, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: capability, name: strategy_mode, from: ST1}
  - {kind: data, name: product_directions_state, from: ST2}
```

## Parallelism Analysis
- **Batch 1:** ST1
- **Batch 2:** ST2 (after ST1 — instantiates ST1's contract)
- **Batch 3:** ST3 (after ST1-2)
- **Mode:** sequential. **Recommended workers:** 1. (Genuinely sequential — each subtask consumes the prior's contract; no parallelism claimed.)

## Skill References
- **ST1:** `skills/brainstorming/SKILL.md` (5-lens scored ideation/debate — the bounded strategic engine), `skills/mvp-scoping/SKILL.md` (effort/feasibility prioritization), `skills/quality-checklist/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`
- **ST3:** `skills/claude-md-validation/SKILL.md` (doc currency), `skills/quality-checklist/SKILL.md`

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| Strategic output degrades into generic hype → maintainer learns to ignore it | HIGH | red-team W3 analog | Grounding mandate (cite real asset + enabler or drop), scoring, one-line suppression, dedup against tracked directions; reuse brainstorming skill's scored-debate discipline |
| Unbounded fetch/cost from "research frontier AI" | MED | scope | Reuse existing `--max-fetches` cap; frontier signal is a bounded, optional WebSearch/Context7 step |
| Mode creep / overlap with existing adoption report | MED | design | `--strategy` is additive; default unchanged; directions are a distinct report type from adoption candidates |
| Self-applying product changes | MED | guardrails | Propose-only; never self-applies; `--update-baseline` writes only tracking state, never plugin code |
| Anti-rebloat | LOW | CLAUDE.md discipline | A mode flag, not a new command; no new agent/skill/hook |

## Configuration
- **Mode:** sequential · **Workers:** 1 · **Branch:** `feature/capability-check-strategy-mode` · **Cost profile:** default
- **References:** `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`; `commands/capability-check.md` (the command being evolved); this session's System-Twin reframe as the worked example of the thinking to productize.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-03-capability-check-strategy-mode.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-03T19:03:17Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/25
- **Branch:** feature/capability-check-strategy-mode
- **Files changed:** 10 (ST1 command spec, ST2 baseline seed, ST3 docs/version across 7 surfaces, + grounding draft)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (integration review PASSed on first pass)
- **Heal remaining issues:** 0
- **Rubric:** null (brief has no ## Outcomes Rubric section)
- **Preflight sync:** clear
- **Summary:** Added /capability-check --strategy mode (Workflow B) with brainstorming-engine ideation, moat×feasibility×effort scoring, grounding mandate, one-line suppression, dedup, and propose-only guardrails; seeded product_directions with System Twin=proposed; bumped to v14.9.0 with both doc gates green. Default behavior unchanged; no new command/agent/skill/hook (13/14/50/19). One advisory MEDIUM CHANGELOG wording nit (dropped→deferred) fixed post-review.
