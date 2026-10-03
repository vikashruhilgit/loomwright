# Supervisor Job: Completion authority — terminal-event join + FINALIZE children-unsettled gate

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (post-merge of PR #231, v15.79.0)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (4 non-main `git worktree` entries from other concurrent plugin activity in this repo — acknowledged, non-blocking, unrelated worktree names)
- **Source requirement:** .supervisor/requirements/orca-derived/02-completion-authority.md

## Task
**Goal:** A subtask is marked complete only when a terminal lifecycle event AND its `provides` artefacts on disk both agree — never the worker's own self-report alone — and FINALIZE fails closed (never merges) while any spawned child agent has no terminal lifecycle event, with a named `--skip-children-check` escape hatch.

**Problem Statement:**
Today a subtask is marked complete when `verify-provides.sh` finds every `provides` path present ON DISK (v15.71.0's "the gate's INPUT is the tree, not the worker's claim" — this is already disk-wins, already checkpoints on any missing item, already logs `provides_mismatch` when the worker's self-report disagrees, in BOTH `agents/execute-manager.md`'s poll loop AND `agents/supervisor.md`'s Single-Agent/Sequential Path step 3; **do not re-implement this — it exists and is correct**). What that check CANNOT see is whether the agent that was supposed to produce those files ever actually TERMINATED — a `provides` path can exist on disk from a partial/interrupted run, a stale artifact, or a still-running worker whose files happen to be written early, and today's disk-only check would mark it complete regardless. v15.79.0 (PR #231, merged) gave the plugin a per-agent lifecycle ledger: `agent_identity` at spawn, and a terminal row per agent (`subtask_complete` with `result_block_present`, or `agent_lifecycle: failed`). Nothing consumes that ledger yet. This item ADDS a second, independent condition alongside the existing disk check — completion requires BOTH `provides` present on disk AND a terminal lifecycle event recorded for that worker's `agent_id` — and separately adds a Phase 4 FINALIZE pre-merge checklist item: no `agent_identity` row in this session without a matching terminal event.

## Acceptance Criteria
- [ ] Given a subtask whose `provides` paths are ALL present on disk (the existing `verify-provides.sh` check already PASSES), but the session JSONL log has NO terminal lifecycle row (`subtask_complete`, `token_ledger`, or `agent_lifecycle: failed`) yet for that worker's `agent_id`, when the poll-loop (Execute Manager) or the Single-Agent/Sequential Path's inline gate evaluates completion, then the subtask is NOT marked complete — a new, named decision string (e.g. `provides_present_agent_unsettled`) is logged via `record_decision`, distinct from the existing `provides_mismatch` (which fires on a DISK/self-report disagreement, not on a missing terminal event). This is the ONE genuinely new per-subtask mechanism this item adds; the existing disk-vs-self-report check (`provides_mismatch`, checkpoint-on-missing) is UNCHANGED and must not be re-implemented or renamed.
- [ ] Given the same subtask once BOTH conditions hold (provides on disk present AND a terminal lifecycle row exists for that `agent_id`), when the gate re-evaluates, then the subtask IS marked complete exactly as today (byte-identical to pre-this-PR behavior for the common case where the terminal event and the disk state land together, which is the normal timing for a worker that finishes cleanly).
- [ ] Given a session where every `agent_identity` row has a matching terminal event (`subtask_complete`/`token_ledger`/`agent_lifecycle:failed` for that `agent_id`), when FINALIZE's pre-merge safety gate runs, then the new "children settled" check PASSES and the existing 4-point checklist is unaffected (byte-identical merge behavior to today for a healthy run).
- [ ] Given a session with at least one `agent_identity` row that has NO matching terminal event, when FINALIZE's pre-merge safety gate runs, then it emits `error: "children_unsettled"` listing the unsettled `agent_id`(s) and does NOT merge — interactively it asks the user; under `--non-interactive` it fails closed, same shape as the existing `preflight_overlap_detected` fail-closed path.
- [ ] Given the same unsettled-children scenario, when `--skip-children-check` is passed, then FINALIZE proceeds and the skip is recorded in the run summary (a named, explicit escape hatch per CLAUDE.md's fail-closed-needs-an-explicit-escape invariant).
- [ ] Given a session with ZERO `agent_identity` rows at all (pre-2026-09-07 logs, or a session that never spawned a Task), when the children-settled check runs, then it reports `children_check: no_identity_rows` in its reason text — NEVER `settled` — and does not block the merge (nothing to check).
- [ ] Given an `agent_lifecycle: failed` or absent-terminal-event child (`ended_without_result`, from the item-01 ledger), when it is surfaced by either gate, then the surfaced record includes that child's `agent_id` so an operator can `SendMessage` it to resume instead of re-running the subtask cold (memory `subagents-hit-turn-limit-resume-via-sendmessage`) — this item only needs to SURFACE the id, not implement the resume mechanics.

## Outcomes Rubric
- Completion = terminal lifecycle event AND on-disk `provides` artefact, never the worker's self-report alone
- FINALIZE fails closed on unsettled children with the specific unsettled `agent_id`(s) named; the only escape is the explicit `--skip-children-check` flag, and its use is recorded
- A session with zero `agent_identity` rows reports `no_identity_rows`, never a false `settled`
- A healthy run (all children settled, all `provides` present) is byte-identical in behavior to pre-this-PR
- The join key is `agent_identity.agent_id` against the terminal-event rows' `agent_id`/`agent_type` fields already committed in v15.79.0 — no new schema, no new writer

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Completion authority (terminal-event join, FINALIZE children-settled gate) | all | 6 modify, 0 create | `skills/async-orchestration/SKILL.md`, `skills/state-management/SKILL.md` | LAUNCHABLE |

**Split reason:** none — single subtask. The per-subtask check and the per-run FINALIZE gate are two call sites of the SAME join logic (agent_identity vs. terminal event, by `agent_id`), sharing one mental model and best implemented by one worker who keeps them consistent; splitting would risk exactly the kind of two-sites-drift bug PR #231's own heal loop had to fix twice.

### Provides / Requires Schema

```yaml
# Subtask 1 — Completion authority (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "outputs_verified_contradicted"}
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "children_unsettled"}
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "skip-children-check"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "children settled"}
requires: []
lanes:
  - "loomwright/agents/execute-manager.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/FAILURE_ESCALATION.md"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/async-orchestration/SKILL.md` (Phase 4 FINALIZE pre-merge safety gate, §"Phase 4 FINALIZE procedure"), `skills/state-management/SKILL.md` (session JSONL conventions the join reads) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The join must read the SAME session JSONL both the Execute Manager (delegated path) and the inline Supervisor (Single-Agent/Sequential path) write to — a wrong anchoring (bare `$PWD` instead of the main-worktree resolution) would silently see zero or the wrong session's rows | HIGH if regressed | Reuse the EXACT worktree-safe anchoring already established by `emit-progress-event.sh`/`emit-lifecycle.sh` (`git worktree list --porcelain` first entry) — read those files' anchoring comments, do not reinvent |
| `agent_identity` rows only exist since 2026-09-07 (per item 02's own problem statement) — an older log or a log from a pre-v15.79.0 run has none | MEDIUM | Explicit `no_identity_rows` reporting (see acceptance criteria) rather than a false `settled`; this is a documented, tested case, not an edge case to discover later |
| Adding a 5th pre-merge checklist item changes `skills/async-orchestration/SKILL.md`'s documented checklist AND `agents/supervisor.md`'s "Gates (stay here)" bullet 1 summary — these two must stay in sync (the file explicitly separates "protocol" in the skill from "gates stay here" in the agent prompt) | MEDIUM | Update both in the same change; do not add the new check to only one location |
| `--skip-children-check` must be recorded in the run summary per CLAUDE.md's fail-closed-needs-an-escape invariant, and also needs a `commands/supervisor.md` flag-table entry (Parameters table) to stay in sync with the agent prompt, per this repo's own "Agent↔command mirror drift" lesson | MEDIUM | Add the flag to `commands/supervisor.md`'s Parameters table in the same change, not as a follow-up |
| Feasibility (Phase 2.5) — Scope vs Supervisor Capability | LOW | Single-subtask, 6 file edits (2 agent prompts, 1 skill, 1 command doc, 2 docs), no new script; well within Single-Agent Path capacity |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-17-completion-authority.md
```

## Outcome
- **Heal loop ran:** true
- **Heal iterations:** 0 code-review fix cycles needed (single PASS on first holistic review; only MEDIUM/LOW documentation nits, non-blocking) — 2 Plan Review rounds during brief authoring (attempt 1 FAIL: mischaracterized existing behavior + missed the genuinely-new AC; attempt 2 PASS)
- **Heal decision:** PASS (internal review PASS + external claude-review PASS, both with only minor/cosmetic findings)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/232
- **Merge commit:** a6a8221f79a19f1d8c3e45e21c74bbf495ad4536 (merge commit, --admin — required 1 approving review, no human reviewer available; standing order)
- **Version:** 15.79.0 -> 15.80.0
