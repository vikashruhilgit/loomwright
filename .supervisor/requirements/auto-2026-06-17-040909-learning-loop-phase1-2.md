# Requirement: Learning Loop — Phase 1 + Phase 2 (Memory APPLY path + usage telemetry)

> **Source:** `ai-agent-manager-plugin/docs/SPIKES/LEARNING_LOOP_ROADMAP.md` §3 Phase 1, §3 Phase 2, and §4 "Recommended First Launch Pad Brief".
> **Autonomous session:** `auto-2026-06-17-040909` (single-iteration).
> Phase 0 ("Finish Brain Read-Path Cleanup") is already complete (all ACs green) — this requirement is the roadmap's recommended *first* actionable slice.

## Goal

Make existing Agent Manager memory **actionable** before adding more storage. Implement a scoped memory **APPLY** path and additive usage **telemetry**:

- Code Reviewer explicitly consults its per-agent memory and shared project memory before reviewing.
- Launch Pad and Supervisor consult verified/fresh **LESSONS** through `read-lessons.sh` at planning / task-acquisition time.
- All memory is **advisory** and **subordinate to `CLAUDE.md`**.
- Add additive `knowledge_sources_used` markers so future `/insights` can measure whether memory was actually applied.
- Do **not** add new storage surfaces. Do **not** change review verdicts, `heal_decision`, or any gating behavior.

## Background (what already exists — wire it, don't rebuild it)

- Readers present: `ai-agent-manager-plugin/scripts/read-lessons.sh`, `ai-agent-manager-plugin/scripts/read-project-memory.sh`.
- Stores present: `.supervisor/memory/LESSONS.md`, `.supervisor/memory/PROJECT_MEMORY.md` (+ `.provenance.jsonl`).
- Per-agent memory dirs: `.claude/agent-memory/ai-agent-manager-plugin:<agent>/` (Code Reviewer is `…:code-reviewer`).
- `knowledge_sources_used` currently appears ONLY in the roadmap — it is net-new to result/session schemas.
- Result schemas live in `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`.

## Scope

### Phase 1 — Internal Memory APPLY Path
1. **Code Reviewer memory consult** (`agents/code-reviewer.md`): add an explicit, bounded, read-only memory-consult step that
   - reads its own `.claude/agent-memory/ai-agent-manager-plugin:code-reviewer/` directory in read-only mode,
   - reads shared project memory via `read-project-memory.sh`,
   - treats all memory as advisory and subordinate to `CLAUDE.md`,
   - explicitly ignores stale/unrelated entries.
2. **Scoped LESSONS apply path:**
   - Launch Pad (`agents/launch-pad.md`) reads verified/fresh lessons through `read-lessons.sh` during planning.
   - Supervisor (`agents/supervisor.md`) reads verified/fresh lessons at task acquisition / planning.
   - Include only relevant categories; skip stale/unverified lessons; **fail safe** when the reader is absent or emits nothing (a read miss is a logged no-op, never a run failure).
3. **Document the memory hierarchy** (precedence, most-authoritative first): `CLAUDE.md` → `PROJECT_MEMORY` → `LESSONS` → per-agent memory → brain/wiki hints. Place it where agents and contributors will find it (e.g. `AGENT_GUIDELINES.md` and/or a shared skill).

### Phase 2 — Knowledge Usage Telemetry
4. Add an **additive, optional** `knowledge_sources_used` array marker to the relevant session/result output (e.g. `SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, and/or the session JSONL), documented in `RESULT_SCHEMAS.md`. Example values:
   `["project_memory", "lessons:testing", "agent_memory:code-reviewer", "twin:scripts/build-insights.sh", "brain_context"]`
5. Keep the field optional and additive — **do not gate on it**; a missing field remains valid for old logs.

## Acceptance Criteria
- [ ] Given a Code Reviewer run, when it starts a review, then it performs an explicit bounded read-only memory-consult step (own agent-memory + project memory) before producing findings.
- [ ] Given Launch Pad / Supervisor at planning time, when verified/fresh lessons exist, then they are read via `read-lessons.sh` and the agent can **cite which verified lessons were considered**.
- [ ] Given the reader is absent or emits nothing, when an agent attempts a memory read, then the run continues unaffected (fail-safe, logged no-op) — no memory read can block a run or change a verdict by itself.
- [ ] Given any run, the memory hierarchy (CLAUDE.md > PROJECT_MEMORY > LESSONS > per-agent > brain/wiki) is documented in a discoverable location.
- [ ] Given a run that consulted memory, when it emits its result/session block, then a `knowledge_sources_used` array can record which sources were used; runs can distinguish "memory existed" from "memory was actually used."
- [ ] Given an old log without the field, when validated, then it remains schema-valid (field is optional/additive).
- [ ] `check-doc-currency.sh` and `validate-version.sh` pass; any version/count bump is reflected across doc surfaces in the same change.

## Non-Goals (roadmap §5 — do NOT do any of these)
- No `/setup brain`. No brain write-back. No trusted wiki writes.
- No worker memory reads (memory context flows through Launch Pad / Supervisor / reviewers only — workers execute richer briefs).
- **No gating changes** — never change `heal_decision`, review verdicts, or block a run on a memory signal.
- No new memory directories / storage surfaces. No vector/RAG store. No CI-reviewer convergence project.

## Constraints (roadmap §1 non-negotiables)
- Agent Manager remains standalone; `personal-brain` stays optional/advisory/fail-safe.
- `CLAUDE.md` remains the human authority; memory/lessons are subordinate.
- No self-trusting memory — machine-written memory is provenance-gated / advisory-only.
- Use structured, scoped facts read only when relevant — not blanket context injection.

## Outcomes Rubric
- Code Reviewer prompt (`agents/code-reviewer.md`) contains an explicit read-only memory-consult step naming both `.claude/agent-memory/…:code-reviewer/` and `read-project-memory.sh`, marked advisory/subordinate-to-CLAUDE.md.
- Launch Pad prompt (`agents/launch-pad.md`) invokes `read-lessons.sh` at planning and states lessons are advisory + can be cited.
- Supervisor prompt (`agents/supervisor.md`) invokes `read-lessons.sh` at task acquisition/planning with the same fail-safe + advisory framing.
- Every new memory read is explicitly fail-safe (absent reader / empty output → logged no-op, never a run failure or verdict change).
- A memory-hierarchy precedence list (CLAUDE.md > PROJECT_MEMORY > LESSONS > per-agent > brain/wiki) is added to a discoverable doc.
- `RESULT_SCHEMAS.md` documents an optional, additive `knowledge_sources_used` array with the field marked non-gating and backward-compatible.
- `check-doc-currency.sh` and `validate-version.sh` both exit 0 after the change.

## Status
**Status:** done
**Completed:** 2026-06-17T05:19:07Z
**Brief:** .supervisor/jobs/done/auto-2026-06-17-040909-learning-loop-phase1-2.md
**PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/61
