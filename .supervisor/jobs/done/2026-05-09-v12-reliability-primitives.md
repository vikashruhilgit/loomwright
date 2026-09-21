# Supervisor-Ready Brief: AI Agent Manager v12.0.0 — Reliability Primitives

## Environment

- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (current)
- **Git:** Clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Disk:** 133 GB free
- **Blockers:** 0
- **Warnings:** 1 — SubagentStart hook type unverified; subtask S4 handles this with a gated implementation note

---

## Task

**Goal:** Implement all v12.0.0 reliability primitives for the AI Agent Manager plugin, elevating it from v11.2.0 to v12.0.0. Four change sets: (1) inter-subtask output contracts with dependency materialization, (2) effort tiering across all agents, (3) hooks validation hardening, (4) docs and version bump.

**Source plan:** `~/.claude/plans/ok-now-you-have-vectorized-hopcroft.md`

**Plugin path (all relative to project root):**
- Agents: `ai-agent-manager-plugin/agents/`
- Hooks: `ai-agent-manager-plugin/hooks/hooks.json`
- Docs: `ai-agent-manager-plugin/docs/`
- Skills: `ai-agent-manager-plugin/skills/`
- Plugin manifest: `ai-agent-manager-plugin/.claude-plugin/plugin.json`

---

## Acceptance Criteria

- [ ] Given a multi-subtask Launch Pad brief, when subtasks have sequential dependencies, then each subtask includes `provides:` and `requires:` blocks using `{kind, path, name}` structured schema
- [ ] Given a brief with `requires` items, when Plan Reviewer validates, then it checks every `requires.from` traces to a real `provides` entry in the named subtask (criterion 12) and detects dependency cycles
- [ ] Given a BLOCKED subtask whose dependencies are complete, when Execute Manager prepares to spawn it, then it: (a) creates dependent branch from feature branch, (b) creates worktree, (c) merges each producer branch via `git -C <worktree_path> merge --no-ff`, (d) runs verification gate, (e) only spawns if all checks pass
- [ ] Given a pre-spawn verification failure, when Execute Manager emits EXECUTE_CHECKPOINT, then `adjudication_required: true`, `missing_outputs[]`, and `adjudication_options[]` are present
- [ ] Given a worker that failed to deliver a `provides` item, when it emits WORKER_RESULT, then `outputs_verified[]` lists each item with `status: present|missing`, `outputs_gap` is non-empty, and `status: partial`
- [ ] Given WORKER_RESULT with `outputs_gap` non-empty and `status: completed`, when SubagentStop hook validates, then hook returns `ok: false`
- [ ] Given EXECUTE_CHECKPOINT with toolset_gap as blocker, when SubagentStop hook validates, then hook returns `ok: false` and demands restatement without toolset_gap
- [ ] Given all 12 agent frontmatter files, when read, then effort values match tier table: xhigh (red-team-reviewer), high (code-reviewer, launch-pad, worker, qa-executor, qa-strategist, plan-reviewer), medium (supervisor, execute-manager, orchestrator), omitted (context-keeper and product-owner unchanged)
- [ ] Given `scripts/validate-version.sh` and `scripts/check-command-sync.sh`, when run after all changes, then both pass clean with v12.0.0

---

## Subtask Structure

### S1 — Effort Tiering + Architecture Docs
**Goal:** Add/correct `effort:` in frontmatter of 9 agent files; add consistency_audit depth note to code-reviewer prompt body; add Effort Tier table and Opus 4.7 migration note to ARCHITECTURE_CONTRACTS.md.

**Acceptance criteria:**
- `effort: xhigh` in `red-team-reviewer.md` frontmatter
- `effort: high` added to `worker.md`, `launch-pad.md`, `qa-executor.md`, `plan-reviewer.md` frontmatter
- `effort: medium` added to `supervisor.md`, `execute-manager.md`, `orchestrator.md` frontmatter
- `code-reviewer.md` keeps `effort: high`; add note in prompt: "In consistency_audit mode, treat this as exhaustive cross-file analysis — verify every reference, count, and mirrored prompt."
- `qa-strategist.md` already has `effort: high` — verify and leave unchanged
- `context-keeper.md` — no effort field (Haiku model)
- `ARCHITECTURE_CONTRACTS.md` — add Effort Tier table and Opus 4.7 migration note (adaptive thinking replaces budget_tokens; xhigh new top level; tokenizer uses 1–1.35x more tokens)

**Files to modify (11):**
- `ai-agent-manager-plugin/agents/red-team-reviewer.md`
- `ai-agent-manager-plugin/agents/worker.md`
- `ai-agent-manager-plugin/agents/launch-pad.md`
- `ai-agent-manager-plugin/agents/qa-executor.md`
- `ai-agent-manager-plugin/agents/plan-reviewer.md`
- `ai-agent-manager-plugin/agents/supervisor.md`
- `ai-agent-manager-plugin/agents/execute-manager.md`
- `ai-agent-manager-plugin/agents/orchestrator.md`
- `ai-agent-manager-plugin/agents/code-reviewer.md`
- `ai-agent-manager-plugin/agents/qa-strategist.md` (verify only)
- `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md`

**Skill references:** `quality-checklist`

```yaml
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/red-team-reviewer.md", name: "effort: xhigh"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/worker.md", name: "effort: high"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "effort: high"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/plan-reviewer.md", name: "effort: high"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/qa-executor.md", name: "effort: high"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "effort: medium"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/execute-manager.md", name: "effort: medium"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/orchestrator.md", name: "effort: medium"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md", name: "Effort Tier"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md", name: "Opus 4.7"}
requires: []
external_requires:
  - Claude Code frontmatter spec (effort field values: low/medium/high/xhigh/max)
```

---

### S2 — Brief Schema + Plan Reviewer Validation + Skills
**Goal:** Add `provides`/`requires` structured schema to Launch Pad's Phase 4 decomposition, Plan Reviewer's validation criteria, and the supervisor-readiness + async-orchestration skills.

**Acceptance criteria:**
- `launch-pad.md` Phase 4 DECOMPOSE section: generates `provides:` and `requires:` YAML blocks per subtask using `{kind, path, name, pattern?}` schema; rejects vague provides; separates `external_requires`
- `plan-reviewer.md` adds Criterion 12: validates every `requires.from` traces to a `provides` entry; checks for dependency cycles; verifies BLOCKED status for subtasks with requires
- `supervisor-readiness/SKILL.md` Subtask Structure section: adds `provides:` and `requires:` format example with schema description
- `async-orchestration/SKILL.md`: adds three new sections — "Dependency Materialization", "Pre-Spawn Verification Gate", "Scope Expansion Adjudication" with 4-option protocol

**Files to modify (4):**
- `ai-agent-manager-plugin/agents/launch-pad.md` (Phase 4 body only — frontmatter done by S1)
- `ai-agent-manager-plugin/agents/plan-reviewer.md` (criterion 12 addition — frontmatter done by S1)
- `ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md`
- `ai-agent-manager-plugin/skills/async-orchestration/SKILL.md`

**Skill references:** `supervisor-readiness`, `quality-checklist`

```yaml
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "provides:"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "external_requires"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/plan-reviewer.md", name: "Criterion 12"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md", name: "provides:"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/async-orchestration/SKILL.md", name: "Dependency Materialization"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/async-orchestration/SKILL.md", name: "Pre-Spawn Verification Gate"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/async-orchestration/SKILL.md", name: "Scope Expansion Adjudication"}
requires:
  - {from: "S1", kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "effort: high"}
  - {from: "S1", kind: "symbol", path: "ai-agent-manager-plugin/agents/plan-reviewer.md", name: "effort: high"}
external_requires:
  - provides/requires schema defined in source plan (plan file has the authoritative schema)
```

---

### S3 — Execute Manager + Worker Runtime Changes
**Goal:** Add dependency materialization (Step 2a) and pre-spawn verification gate (Step 2b) to Execute Manager; add outputs_verified + outputs_gap emission (Step 5.5 extension) to Worker; update Execute Manager's "no git merges" rule.

**Acceptance criteria:**
- `execute-manager.md` rule updated: "No code modification; dependency-materialization merges are the only permitted git merge operations, and only within a dependent worktree — never on the main repo's HEAD"
- `execute-manager.md` Step 2 replaced with Step 2a (dependency materialization: checkout -b dependent_branch from feature_branch, worktree add, merge each producer via `git -C <path> merge --no-ff`) + Step 2b (verification gate: test -f for files, grep -n for symbols/types)
- `execute-manager.md` adjudication_required CHECKPOINT format documented with 4 options
- `worker.md` Step 5.5 extended: after writing summary file, scan own provides list, emit `outputs_verified[]` and `outputs_gap`; set `status: partial` if gap non-empty
- `supervisor.md` EXECUTE phase: add handling for CHECKPOINT with `adjudication_required: true` — present 4 options to user with specific response for each option (A: re-queue producer, B: insert subtask, C: exit to Launch Pad, D: update consumer brief)

**Files to modify (3):**
- `ai-agent-manager-plugin/agents/execute-manager.md` (Step 2 replacement, rule update)
- `ai-agent-manager-plugin/agents/worker.md` (Step 5.5 extension)
- `ai-agent-manager-plugin/agents/supervisor.md` (EXECUTE phase adjudication handling)

**Skill references:** `async-orchestration`, `quality-checklist`

```yaml
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/execute-manager.md", name: "Step 2a: Dependency Materialization"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/execute-manager.md", name: "Step 2b: Pre-Spawn Verification Gate"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/execute-manager.md", name: "adjudication_required"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/worker.md", name: "outputs_verified"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/worker.md", name: "outputs_gap"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "adjudication_required"}
requires:
  - {from: "S1", kind: "symbol", path: "ai-agent-manager-plugin/agents/execute-manager.md", name: "effort: medium"}
  - {from: "S1", kind: "symbol", path: "ai-agent-manager-plugin/agents/worker.md", name: "effort: high"}
  - {from: "S1", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "effort: medium"}
external_requires:
  - git CLI (merge, worktree add, checkout -b)
```

---

### S4 — Hooks Hardening + Result Schema Normalization
**Goal:** Update hooks.json with 3 new validation rules; normalize drift in RESULT_SCHEMAS.md then add v2 fields.

**Acceptance criteria:**

**hooks.json changes:**
- Worker SubagentStop prompt: add rule rejecting WORKER_RESULT with `outputs_gap` non-empty + `status: completed` (returns ok:false)
- Execute Manager SubagentStop prompt: add rule rejecting EXECUTE_CHECKPOINT citing toolset_gap/Task unavailable (returns ok:false, demands restatement); add validation for adjudication_required fields
- SubagentStart hooks for execute-manager and worker: **implement only if SubagentStart supports `type: command` — verify first**; if not supported, add a comment-note documenting the spike result and defer; hook JSON output must use `{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}`

**RESULT_SCHEMAS.md changes:**
- Audit all result block examples against current hooks.json validation prompts — fix any field name mismatches or stale examples (normalize before extending)
- WORKER_RESULT: bump schema_version v1 → v2; add optional `outputs_verified: [{kind, path, name, status}]` and `outputs_gap: string` fields; add v1 backward compat note
- EXECUTE_CHECKPOINT: add optional `adjudication_required: bool`, `missing_outputs: [{item, producing_subtask, check_run}]`, `adjudication_options: [string]` fields

**Files to modify (2):**
- `ai-agent-manager-plugin/hooks/hooks.json`
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`

**Skill references:** `quality-checklist`

```yaml
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/hooks/hooks.json", name: "outputs_gap"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/hooks/hooks.json", name: "toolset_gap"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/hooks/hooks.json", name: "adjudication_required"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "outputs_verified"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "outputs_gap"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "schema_version: 2"}
requires:
  - {from: "S2", kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "provides:"}
  - {from: "S3", kind: "symbol", path: "ai-agent-manager-plugin/agents/worker.md", name: "outputs_verified"}
  - {from: "S3", kind: "symbol", path: "ai-agent-manager-plugin/agents/execute-manager.md", name: "adjudication_required"}
external_requires:
  - Claude Code hooks API (SubagentStart event support — must be verified before implementing SubagentStart hook)
```

---

### S5 — Failure Docs + Version Bump + Docs Completeness
**Goal:** Add 2 new failure modes to FAILURE_ESCALATION.md; bump version to 12.0.0 across all manifest and documentation files; update SKILLS_INDEX.md lastUpdated; run validation scripts.

**Acceptance criteria:**
- `FAILURE_ESCALATION.md`: add "Inter-Subtask Gap / Scope Expansion" failure mode (trigger: pre-spawn verification fails or outputs_gap non-empty; retry: none; escalation: 4-option adjudication) and "Dependency Merge Conflict" failure mode (trigger: merge conflict during dependency materialization; retry: none; escalate immediately)
- `plugin.json`: version `11.2.0` → `12.0.0`; update description to reflect v12.0.0 features
- `CLAUDE.md`: update version references; add note on inter-subtask contracts; add effort tier table reference
- `README.md`: version references updated to v12.0.0
- `.claude-plugin/README.md`: version references updated
- `.claude-plugin/marketplace.json`: version bump
- `commands/agent-help.md`: update hook count if changed
- `skills/SKILLS_INDEX.md`: update `lastUpdated` for all modified skills (supervisor-readiness, async-orchestration)
- Run `scripts/validate-version.sh` — exits 0
- Run `scripts/check-command-sync.sh` — exits 0

**Files to modify (7–8):**
- `ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md`
- `ai-agent-manager-plugin/.claude-plugin/plugin.json`
- `CLAUDE.md`
- `README.md`
- `.claude-plugin/README.md`
- `.claude-plugin/marketplace.json`
- `ai-agent-manager-plugin/commands/agent-help.md`
- `ai-agent-manager-plugin/skills/SKILLS_INDEX.md`

**Skill references:** `quality-checklist`

```yaml
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md", name: "Inter-Subtask Gap"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md", name: "Dependency Merge Conflict"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "12.0.0"}
  - {kind: "symbol", path: "CLAUDE.md", name: "v12.0.0"}
requires:
  - {from: "S4", kind: "symbol", path: "ai-agent-manager-plugin/hooks/hooks.json", name: "outputs_gap"}
  - {from: "S4", kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "schema_version: 2"}
external_requires: []
```

---

## Parallelism Analysis

```
Batch 1:  [S1]          — 1 worker  (all agent frontmatter; no deps)
Batch 2:  [S2] [S3]     — 2 workers (different files; both blocked by S1)
Batch 3:  [S4]          — 1 worker  (hooks + schemas; blocked by S2+S3)
Batch 4:  [S5]          — 1 worker  (version bump + docs; blocked by S4)
```

**LAUNCHABLE:** S1  
**BLOCKED by S1:** S2, S3  
**BLOCKED by S2+S3:** S4  
**BLOCKED by S4:** S5  

**Recommended workers:** 2  
**Estimated total wall time:** ~3–4 hrs (Batch 2 is the longest — 2 workers in parallel)

---

## Skill References

| Subtask | Skills |
|---|---|
| S1 | `quality-checklist` |
| S2 | `supervisor-readiness`, `quality-checklist` |
| S3 | `async-orchestration`, `quality-checklist` |
| S4 | `quality-checklist` |
| S5 | `quality-checklist` |

---

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| SubagentStart hook type unverified — may not support `type: command` | MEDIUM | Feasibility (Phase 2.5) | S4 gates implementation on spike verification; falls back to comment-note if unsupported |
| RESULT_SCHEMAS.md drift normalization may reveal more issues than expected | LOW | Codebase analysis | S4 normalize-first approach; document any additional drift found before extending |
| validate-version.sh or check-command-sync.sh may catch missed version references | LOW | Standard release risk | S5 runs both scripts and fixes any failures before completion |
| code-reviewer.md already has `effort: high` — verify no double-write | LOW | File analysis | S1 reads frontmatter first; adds only if absent |
| qa-strategist.md already has `effort: high` — no change needed | INFO | File analysis | S1 verifies and leaves unchanged |

---

## Configuration

```yaml
max_workers: 2
feature_branch: feature/v12-reliability-primitives
worktree_prefix: ai-agent-manager
cost_profile: inherit
```

---

## Handoff

```
/supervisor job: .supervisor/jobs/pending/2026-05-09-v12-reliability-primitives.md
```

Start a fresh Claude Code session with clean context and run the command above.

---

## Outcome

- **session_id:** 2026-05-09-v12-reliability-primitives
- **completed_at:** 2026-05-09T13:30:00Z (approx)
- **outcome:** completed
- **feature_branch:** feature/v12-reliability-primitives
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/8
- **subtasks_completed:** 5/5 (S1, S2, S3, S4, S5)
- **heal_loop_ran:** true
- **heal_decision:** PASS (iteration 2)
- **heal_iterations:** 1 fix iteration + 2 reviews
- **heal_remaining_issues:** 2 LOW (in new hooks/NOTES.md — duplicate paragraph + missing inbound link; non-blocking, deferred)
