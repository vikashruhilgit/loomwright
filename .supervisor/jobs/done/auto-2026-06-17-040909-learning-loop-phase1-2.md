# Supervisor Job: Learning Loop Phase 1+2 — Memory APPLY path + usage telemetry

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/auto-2026-06-17-040909-learning-loop-phase1-2.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure markdown-prompt + docs edits; readers (`read-lessons.sh`, `read-project-memory.sh`) already exist and exit 0 fail-safe |
| 2 | Dependency Availability | GO | LESSONS.md / PROJECT_MEMORY.md stores present; corpus tasks `doc-currency-green` + `version-consistent` present |
| 3 | Architecture Fit | GO | Advisory / read-only / fail-safe / non-gating — matches CLAUDE.md "side-effect emitters fail SAFE" + "advisory signals never gate" invariants |
| 4 | Scope vs Supervisor Capability | GO | 6 subtasks, each a small bounded edit to one file |
| 5 | Hard Blockers | GO | None — additive optional fields, no schema_version bumps, counts unchanged |

**Overall Verdict:** GO

## Task
**Goal:** Wire existing Agent Manager memory (LESSONS + project memory + per-agent memory) into Code Reviewer / Launch Pad / Supervisor as an advisory, fail-safe, non-gating APPLY path, and add an additive `knowledge_sources_used` telemetry marker — without adding any new storage surface or changing any gate.

**Problem Statement:**
Agent Manager already *writes* memory (LESSONS.md, PROJECT_MEMORY.md, per-agent memory) but applies it inconsistently. Code Reviewer never explicitly consults memory; Launch Pad / Supervisor read project-memory but not verified LESSONS; and no run can report which knowledge it actually used. This causes accumulated knowledge to sit unused ("more memory is only more files") and makes the APPLY/MEASURE loop unmeasurable. Success looks like: every memory-bearing read path is explicit, advisory, fail-safe, and emits a `knowledge_sources_used` marker so `/insights` can later measure usage — with zero gating/verdict changes.

## Acceptance Criteria
- [ ] Given a Code Reviewer run, when it sets up context, then it performs an explicit bounded read-only memory-consult step (its own `.claude/agent-memory/…:code-reviewer/` + `read-project-memory.sh`) before producing findings, marked advisory + subordinate to CLAUDE.md.
- [ ] Given Launch Pad / Supervisor at planning/acquisition, when verified/fresh lessons exist, then they are read via `read-lessons.sh` and the agent can cite which verified lessons were considered.
- [ ] Given the reader is absent or emits nothing, when an agent attempts a memory read, then the run continues unaffected (logged no-op) — no memory read can block a run or change a verdict.
- [ ] Given any run, the memory hierarchy (CLAUDE.md > PROJECT_MEMORY > LESSONS > per-agent > brain/wiki) is documented in a discoverable location.
- [ ] Given a run that consulted memory, when it emits its result block, then an optional additive `knowledge_sources_used` array can record the sources used; old logs without the field stay schema-valid.
- [ ] `check-doc-currency.sh` and `validate-version.sh` both pass; version/count claims updated in the same change.

## Outcomes Rubric
- `agents/code-reviewer.md` contains an explicit read-only memory-consult step naming BOTH `.claude/agent-memory/` (its own `…:code-reviewer/`) and `read-project-memory.sh`, marked advisory + subordinate-to-CLAUDE.md.
- `agents/launch-pad.md` invokes `read-lessons.sh` at planning and states lessons are advisory and may be cited.
- `agents/supervisor.md` invokes `read-lessons.sh` at task acquisition/planning with the same fail-safe + advisory framing, AND emits `knowledge_sources_used` both on `SUPERVISOR_RESULT` and as a flat field on the `session_end` JSONL line.
- Every new memory read is explicitly fail-safe (absent reader / empty output → logged no-op; never a run failure or verdict change).
- A memory-hierarchy precedence list (CLAUDE.md > PROJECT_MEMORY > LESSONS > per-agent > brain/wiki) is added to `AGENT_GUIDELINES.md`.
- `docs/RESULT_SCHEMAS.md` documents an optional, additive `knowledge_sources_used` array on SUPERVISOR_RESULT and CODE_REVIEW_RESULT (and the `session_end` JSONL), explicitly non-gating and backward-compatible, with NO `schema_version` bump.
- `plugin.json` + `marketplace.json` show v14.28.0 and `check-doc-currency.sh` + `validate-version.sh` exit 0.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Shared Implementation Contract (READ FIRST — every subtask MUST copy these verbatim)

Workers run in isolated worktrees and cannot see each other. To prevent divergent wording, copy these blocks **verbatim** where your subtask applies. Do NOT paraphrase.

**(C1) Canonical telemetry field** — the additive, optional, non-gating marker. Field name is EXACTLY `knowledge_sources_used`. It is a JSON array of short source-tag strings. Canonical example value (use verbatim in docs/examples):
```json
"knowledge_sources_used": ["project_memory", "lessons:testing", "agent_memory:code-reviewer", "twin:scripts/build-insights.sh", "brain_context"]
```
Tag vocabulary (open set, lowercase): `project_memory`, `lessons:<category>`, `agent_memory:<agent>`, `twin:<path>`, `brain_context`. The field is OPTIONAL and ADDITIVE — absent ⇒ valid (old logs unaffected); NEVER gated on; does NOT bump `schema_version` (follows the `branch_base` / `pr_state` / `preflight_sync` additive precedent already documented in RESULT_SCHEMAS.md). **Two shapes, same data:** it appears BOTH as a nested array on the result block (SUPERVISOR_RESULT / CODE_REVIEW_RESULT) AND as a flat array field on the Supervisor `session_end` JSONL line (the surface `build-insights.sh` / `/insights` reads) — exactly the dual-shape pattern `contract_conformance` already uses.

**(C2) Advisory + fail-safe framing** — use this exact sentence pattern for every new memory read:
> These are **advisory and strictly subordinate to `CLAUDE.md`** — on any conflict, `CLAUDE.md` wins. The reader is fail-safe (it always exits 0 and emits only provenance-verified, non-stale entries); if it emits nothing or is absent, proceed normally. Reading memory MUST NEVER block the run or change a verdict / `heal_decision`.

**(C3) Reader interface facts** (do not re-derive): `read-lessons.sh` and `read-project-memory.sh` both take NO arguments, print verified entries to stdout (grouped by `## <category>` for lessons), always `exit 0`, and route diagnostics to stderr + `.supervisor/logs/memory.log`. `read-lessons.sh` honors `LESSON_STALE_DAYS` (default 90) and prints `(no verified lessons entries)` when empty. Invoke as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-lessons.sh"`.

**(C4) Memory hierarchy (precedence, most-authoritative first)** — canonical list to reuse:
`CLAUDE.md` > `PROJECT_MEMORY` > `LESSONS` > per-agent memory (`.claude/agent-memory/<agent>/`) > brain/wiki hints.

**(C5) Non-Goals (do NOT do any of these):** no `/setup brain`, no brain write-back, no trusted wiki writes, no worker memory reads, no gating/verdict/`heal_decision` changes, no new memory directories/storage, no vector/RAG, no CI-reviewer convergence, no `schema_version` bumps.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Code Reviewer memory consult + telemetry | AC1, AC3, AC5 | 1 modify, 0 create | quality-checklist | LAUNCHABLE |
| 2 | Launch Pad verified-lessons read | AC2, AC3 | 1 modify, 0 create | supervisor-readiness | LAUNCHABLE |
| 3 | Supervisor verified-lessons read + telemetry | AC2, AC3, AC5 | 1 modify, 0 create | workflow-management | LAUNCHABLE |
| 4 | Memory hierarchy doc | AC4 | 1 modify, 0 create | quality-checklist | LAUNCHABLE |
| 5 | knowledge_sources_used schema doc | AC5 | 1 modify, 0 create | quality-checklist | LAUNCHABLE |
| 6 | Release finalization (v14.28.0 + currency) | AC6 | 4 modify, 0 create | commit | BLOCKED (by #1,#2,#3,#4,#5) |

### Subtask Detail

**Subtask 1 — Code Reviewer memory consult + telemetry** (`ai-agent-manager-plugin/agents/code-reviewer.md`)
- In the **"Context Setup (REQUIRED)" → Code Reviewer-Specific Additions**, insert a new bounded read-only step between "Load Review Configuration" and "Determine Review Scope": "Consult memory (advisory, read-only)" that (a) **consults this agent's preloaded project memory** — Code Reviewer already declares `memory: project`, so its per-agent memory is injected at spawn; the step says to *use* it. If an explicit filesystem read is needed, resolve the matching `.claude/agent-memory/*code-reviewer*` directory **read-only via a glob** (the exact key may be host-sanitized — do NOT hard-code the `…:code-reviewer` colon form), (b) runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-project-memory.sh"`, (c) applies framing **(C2)**, (d) filters stale/unrelated entries. Anchor by section heading text, NOT line number.
- In the CODE_REVIEW_RESULT emission section, add the optional additive `knowledge_sources_used` field per **(C1)** so the reviewer records which memory it used. Do NOT bump CODE_REVIEW_RESULT `schema_version` (stays 3).
- The step is read-only — Code Reviewer already declares `disallowedTools: Write, Edit, NotebookEdit` and `memory: project`; do not change frontmatter tooling.

**Subtask 2 — Launch Pad verified-lessons read** (`ai-agent-manager-plugin/agents/launch-pad.md`)
- Immediately adjacent to the existing "Consult project memory (advisory, v14.3.0)" step (Phase 3 ANALYZE step 0 — anchor by that step's text), add a sibling "Consult verified lessons (advisory)" step that runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-lessons.sh"`, applies framing **(C2)**, includes only relevant categories, and states the considered lessons may be **cited** in the brief's Risk Assessment / analysis.
- Do not add a telemetry field to LAUNCH_PAD_RESULT (out of scope); citation-in-brief satisfies AC2 for Launch Pad.

**Subtask 3 — Supervisor verified-lessons read + telemetry** (`ai-agent-manager-plugin/agents/supervisor.md`)
- Extend the **executable** Phase 1 ACQUIRE "Consult project memory (advisory — read-only)" step 0 (the one with the `read-project-memory.sh` invocation inside the 7-phase workflow body — there are summary/reference duplicates of "Phase 1: ACQUIRE" later in the file; edit the executable step-0, not a summary) with a sibling `read-lessons.sh` consult using framing **(C2)**; state which verified lessons were considered may be cited.
- In the Phase 4.5 completion-tail SUPERVISOR_RESULT emission, add the optional additive `knowledge_sources_used` field per **(C1)**. Do NOT bump SUPERVISOR_RESULT `schema_version` (stays 1).
- **ALSO (required — this is the surface `/insights` reads):** stamp the SAME `knowledge_sources_used` value as a **flat field on the `session_end` JSONL line** that Supervisor writes (alongside `contract_conformance_status`, `heal_decision`, `rubric_score`, etc. — `build-insights.sh` reads the flat `session_end` fields, NOT the nested result block). Emit it as a flat JSON array; readers/`build-insights.sh` treat an absent field as "none used". The nested SUPERVISOR_RESULT object and the flat `session_end` field are the same data in two shapes (same dual-shape precedent as `contract_conformance`). Wiring `build-insights.sh` to *aggregate/display* it is an intentional later follow-up — this subtask only ensures the field is **emitted** to `session_end`.

**Subtask 4 — Memory hierarchy doc** (`AGENT_GUIDELINES.md`)
- After the existing top-level "## Memory Core Principle" section content (anchor by that heading), add a subsection "### Memory Hierarchy & APPLY Precedence" documenting list **(C4)** with a one-line rule that layers 2–5 are advisory and never override CLAUDE.md or any gate. Read scoped entries only; ignore stale/unrelated content.

**Subtask 5 — knowledge_sources_used schema doc** (`ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`)
- In the `## SUPERVISOR_RESULT` section and the `## CODE_REVIEW_RESULT` section, document an OPTIONAL ADDITIVE `knowledge_sources_used` array field per **(C1)**, following the additive-field precedent (`branch_base` / `pr_state` / `preflight_sync`). Explicitly state: optional, advisory, non-gating, NOT enumerated by the SubagentStop hook, no `schema_version` bump, absent ⇒ valid.
- Also add it to the `## `session_end` JSONL hard-signal fields` section as an optional flat field (readers treat absent as "none used").
- Add a one-line entry to the change-log/precedent list at the bottom of the file describing the additive field (v14.28.0), mirroring the `preflight_sync` / `branch_base` entries.

**Subtask 6 — Release finalization** (BLOCKED by 1–5) — files: `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `CHANGELOG.md`
- Bump version `14.27.0` → `14.28.0` in `plugin.json` and the marketplace manifest; update the in-place `vX.Y.Z` + four-count strings in both `description` fields (counts UNCHANGED: 14 agents / 18 commands / 55 skills / 19 hooks) — do NOT append a new version clause to descriptions.
- Add a CLAUDE.md release banner for v14.28.0 (memory APPLY path + `knowledge_sources_used` telemetry; additive; no new agent/command/skill/hook; no schema_version bumps) and move the now-third-oldest banner per the "keep only two most recent" rule (relocate older banner detail to CHANGELOG.md).
- Add a CHANGELOG.md entry for v14.28.0.
- Acceptance: run `bash scripts/check-doc-currency.sh` and `bash scripts/validate-version.sh` — BOTH must exit 0 on the integrated tree.

### Provides / Requires Schema (v12.0.0+)

```yaml
# Subtask 1 — Code Reviewer memory consult + telemetry (LAUNCHABLE)
provides:
  - {kind: "file",   path: "ai-agent-manager-plugin/agents/code-reviewer.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/code-reviewer.md", name: "Consult memory (advisory, read-only)"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/code-reviewer.md", name: "knowledge_sources_used"}
requires: []
external_requires: []

# Subtask 2 — Launch Pad verified-lessons read (LAUNCHABLE)
provides:
  - {kind: "file",   path: "ai-agent-manager-plugin/agents/launch-pad.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "Consult verified lessons (advisory)"}
requires: []
external_requires: []

# Subtask 3 — Supervisor verified-lessons read + telemetry (LAUNCHABLE)
provides:
  - {kind: "file",   path: "ai-agent-manager-plugin/agents/supervisor.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "read-lessons.sh"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "knowledge_sources_used"}
requires: []
external_requires: []

# Subtask 4 — Memory hierarchy doc (LAUNCHABLE)
provides:
  - {kind: "file",   path: "AGENT_GUIDELINES.md"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "Memory Hierarchy & APPLY Precedence"}
requires: []
external_requires: []

# Subtask 5 — knowledge_sources_used schema doc (LAUNCHABLE)
provides:
  - {kind: "file",   path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "knowledge_sources_used"}
requires: []
external_requires: []

# Subtask 6 — Release finalization (BLOCKED by #1–#5)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "14.28.0"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "14.28.0"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/code-reviewer.md", name: "knowledge_sources_used"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "Consult verified lessons (advisory)"}
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "knowledge_sources_used"}
  - {from: "4", kind: "symbol", path: "AGENT_GUIDELINES.md", name: "Memory Hierarchy & APPLY Precedence"}
  - {from: "5", kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "knowledge_sources_used"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
Subtask 2 ──┤
Subtask 3 ──┼──→ Subtask 6
Subtask 4 ──┤
Subtask 5 ──┘
(Subtasks 1–5 mutually independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtasks 2,3,4,5 | none | NO |
| Subtask 2 | Subtasks 3,4,5 | none | NO |
| Subtask 3 | Subtasks 4,5 | none | NO |
| Subtask 4 | Subtask 5 | none | NO |
| Subtasks 1–5 | Subtask 6 | none (different files) | YES — ordering only (6 describes/validates 1–5; runs on integrated tree) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3, Subtask 4, Subtask 5 (parallel)
- **Batch 2:** Subtask 6 (after Batch 1 merges — runs doc-currency + validate-version on integrated tree)
- **Recommended workers:** 3
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |
| 2 | `skills/supervisor-readiness/SKILL.md` |
| 3 | `skills/workflow-management/SKILL.md` |
| 4 | `skills/quality-checklist/SKILL.md` |
| 5 | `skills/quality-checklist/SKILL.md` |
| 6 | `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Isolated workers diverge on shared boilerplate (field name / advisory wording) | MEDIUM | Shared Implementation Contract (C1–C5) pins verbatim blocks; Phase 4.5 holistic review catches cross-file inconsistency post-merge |
| Worker edits a summary/reference copy of "Phase 1: ACQUIRE" instead of the executable step (supervisor.md has duplicates) | MEDIUM | Subtask 3 detail explicitly says edit the executable step-0 with the `read-project-memory.sh` invocation, not a summary |
| Accidental gating/verdict change (violates roadmap §5) | HIGH | (C2)+(C5) forbid it; Outcomes Rubric + Code Reviewer verify advisory/non-gating framing |
| Stale absolute line refs in prose edits | LOW | Subtasks anchor by heading text, never line number |
| Doc-currency / version drift after bump | MEDIUM | Subtask 6 runs `check-doc-currency.sh` + `validate-version.sh` as its acceptance check on the integrated tree; counts unchanged |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-06-17-040909-learning-loop-phase1-2.md
```

## Outcome
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1
- **heal_fixable_issues_fixed:** 0
- **heal_remaining_issues:** 0
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/61
- **rubric_score:** 7/7 (advisory)
- **ground_truth:** pass (2/2 — doc-currency-green, version-consistent)
- **Completed:** 2026-06-17T05:19:07Z
