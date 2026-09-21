# 09 — Native-flow adoption: stop reimplementing what Claude Code now provides

## Problem
The plugin was built when the platform lacked most of what it hand-rolls. Claude Code has since shipped first-class primitives that overlap Loomwright's core machinery — built-in code review (`/code-review`, incl. the multi-agent `ultra` cloud review) and `/security-review`; the Agent tool with typed subagents and background execution + completion notification; the Workflow tool for deterministic multi-agent orchestration (fan-out, pipelines, judge panels, worktree isolation per agent); agent teams; native worktree isolation frontmatter. Loomwright still ships its own reviewer agent + review-heal drain, its own poll loop with backoff constants, its own spawn contracts, and its own phase machines.

The mechanism that should catch this exists and has gone dormant: `/capability-check` diffs live platform features against `loomwright/docs/CAPABILITY_BASELINE.json`, but the baseline is dated **2026-06-01 at plugin v14.6.0** while the plugin is at v15.13.0 — ~2 months and 7 minor releases unscanned, and `.supervisor/capability/` holds no saved reports. Self-evolution was built, then not run. This is the DELETE-over-gate pattern (item 04) in the platform dimension: reimplementation is duplication with the vendor, and it drifts the same way.

## Goal
A grounded overlap map between Loomwright machinery and current Claude Code primitives, with a keep / adopt / hybrid verdict per overlap — plus the baseline refreshed so the detector works again. Propose-only for the big migrations; execute only the trivially-safe adoptions.

## Scope
1. **Refresh the detector first (cheap, do this before analysis):** run `/capability-check` (and `--strategy` separately, never mixed), review, then `--update-baseline` + `--save`. This alone recovers ~2 months of drift and grounds everything below in the live changelog rather than recollection.
2. **Overlap map** — for each pair, document what the plugin does, what the platform now does, and what each uniquely provides:
   - `code-reviewer` agent + `review-heal` drain ↔ built-in `/code-review` / `/code-review ultra` / `/security-review`. **Constraint to state explicitly:** the built-in review is user-triggered and billed — an agent cannot launch it — so full replacement is likely impossible; the honest candidates are hybrid (plugin owns the unattended loop; native owns human-triggered deep review) or narrowing the plugin reviewer's scope to what native doesn't cover.
   - `execute-manager` poll loop + backoff constants ↔ background Agent execution with completion notification. Strongest deletion candidate (hand-rolled polling is legacy if notification is reliable) — verify empirically, don't presume.
   - Supervisor/Execute-Manager spawn choreography ↔ the Workflow tool's pipeline/parallel/judge-panel primitives with per-agent worktree isolation.
   - Worker worktree lifecycle ↔ `isolation: worktree`. **Known NO-GO (2026-06-06 empirical probe): native isolation aborts because the plugin's `WorktreeCreate` hook returns no worktree path.** Re-verify whether that still holds before re-flagging; if it does, record the hook rework as the actual prerequisite and stop.
   - Agent Teams ↔ the plugin's parallel model — the graduation criteria in `skills/agent-teams` were unmet; re-check against current behavior.
   - The other two standing deferrals (Remote Control, PreCompact hook) get a keep-deferred / adopt verdict with a reason.
3. **Verdicts + follow-ups:** per overlap — KEEP OURS (state what native lacks) / ADOPT NATIVE (follow-up requirement stub) / HYBRID (define the seam) / BLOCKED (name the prerequisite). Feed CUT verdicts into the same follow-up discipline as item 05.
4. **Execute only the safe subset here:** baseline refresh, doc corrections, and any adoption that is provably behavior-neutral and verified live. Everything touching orchestration or review flow is proposal-only.
5. **Make the detector durable:** a documented cadence — run `/capability-check` on every plugin minor bump or model release (pair it with item 07's per-release ablation ritual so both fire together), and record the last-scan pair where a human will see it.

## Portability constraint (2026-07-23 — added with item 10; both items must honor it)
Item 10 makes the engine vendor-neutral (ports-and-adapters). These items conflict unless every adoption obeys one rule: **native Claude primitives are adopted in the Claude ADAPTER layer, never in the vendor-neutral core.** Before recording an ADOPT/HYBRID verdict here, state which layer it lands in; an adoption that would make a core script or the file protocol require a Claude-only primitive is automatically HYBRID-at-the-adapter, not ADOPT-in-core.

## Non-goals
No orchestration rewrite in this item. No removal of the review-heal loop (it is the unattended path; native review is human-triggered). No re-litigating the agent-count critique — that was adjudicated in NORTH_STAR_DIRECTION and is item 07's arm, not this one. No speculative `model-capability` knob.

## Acceptance criteria
- Baseline refreshed with a real scan; `baseline_date` + `plugin_version_at_last_scan` reflect it; report saved.
- Overlap map covers all six pairs above with cited evidence — plugin behavior read from the actual files, platform behavior from the live docs/changelog fetched in the scan (read-before-write rule: no capability asserted from recollection).
- Each `known_not_adopted` entry re-verified or re-justified, especially the `isolation: worktree` NO-GO (empirical re-probe, not a doc read).
- Follow-up requirement stubs exist for every ADOPT/HYBRID verdict; zero orchestration behavior changed in this PR.

## Outcomes Rubric
- Capability baseline current, with a saved report
- Six-pair overlap map with keep/adopt/hybrid/blocked verdicts and cited evidence
- isolation:worktree NO-GO empirically re-verified (not assumed)
- Follow-up stubs written; no orchestration/review behavior changes in this PR
- Scan cadence documented alongside item 07's per-release ritual
