# Supervisor Job: Round out P2 — Supervisor reads project memory + Worker proposes memory candidates

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, 282 lines)
- **Git:** clean (only untracked `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md` — intentional), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (untracked design draft — intentional, leave alone)

## Task
**Goal:** Complete the deferred half of P2b (v14.3.0) advisory project memory: wire the **Supervisor to READ** verified project memory during Phase 1 ACQUIRE, and let **Workers PROPOSE** durable learnings via an optional, additive `WORKER_RESULT.memory_candidates[]` field. Memory writes remain human-gated and confined to the repo-root sole-writer (`${CLAUDE_PLUGIN_ROOT}/scripts/write-project-memory.sh`); **workers never write memory.**

**Problem Statement:** P2b shipped memory READ for Launch Pad (planning) only. During execution the Supervisor re-discovers context it could read from memory, and Workers that learn durable facts have no channel to surface them. This increment closes that gap without weakening any P2b safety invariant (advisory & subordinate to CLAUDE.md; human-gated promotion; worktree-write ban / red-team F1).

## Acceptance Criteria
- [ ] Given a repo with verified project-memory entries, when Supervisor enters Phase 1 ACQUIRE, then it runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-project-memory.sh"` and folds advisory facts into task context (subordinate to CLAUDE.md; on conflict CLAUDE.md wins), mirroring Launch Pad Phase 3 step 0.
- [ ] Given `read-project-memory.sh` emits nothing (empty / no sha tool), when Supervisor reads memory, then it proceeds normally (fail-safe, no error).
- [ ] Given a Worker learns a durable, reusable, decision-changing fact NOT already in CLAUDE.md/memory, when it emits WORKER_RESULT, then it MAY include an optional `memory_candidates: [<one-line strings>]` field (absent by default).
- [ ] Given a Worker runs in a git worktree, when it finishes, then it NEVER calls `write-project-memory.sh` — it only proposes candidate strings (preserves red-team F1; writer refuses worktree CWD as backstop).
- [ ] Given `memory_candidates` is absent, when the worker SubagentStop validator runs, then WORKER_RESULT still validates (optional/additive; NO `schema_version` bump — stays v2; validators unchanged; hook count stays 19).
- [ ] Given candidates may contain sensitive data, when documented, then `RESULT_SCHEMAS.md` states candidates are durable structural facts, NEVER secrets/PII/tokens.
- [ ] Given the change adds agent capability, when complete, then plugin version is v14.4.0 and `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` pass.

## Subtask Structure
| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Supervisor reads memory in ACQUIRE | 1 modify: `ai-agent-manager-plugin/agents/supervisor.md` | LAUNCHABLE |
| 2 | Worker proposes `memory_candidates[]` + schema doc | 2 modify: `ai-agent-manager-plugin/agents/worker.md`, `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` | LAUNCHABLE |
| 3 | Version bump v14.4.0 + doc currency | 4 modify: `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `AGENT_GUIDELINES.md` | BLOCKED (by #1, #2) |

## Subtask Contracts
```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "read-project-memory"}
requires: []
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/worker.md", name: "memory_candidates"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "memory_candidates"}
requires: []
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "14.4.0"}
  - {kind: "symbol", path: "CLAUDE.md", name: "v14.4.0"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "read-project-memory"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/agents/worker.md", name: "memory_candidates"}
external_requires: []
```

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 2 ──→ Subtask 3
```

### Parallelism Analysis
- **Batch 1:** Subtask 1, Subtask 2 (parallel — disjoint files, empty requires)
- **Batch 2:** Subtask 3 (after 1 & 2 — documents what they landed)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Implementation Notes (binding constraints for Workers)
- **Subtask 1 (supervisor.md):** Add a memory-read step to **Phase 1 ACQUIRE** mirroring Launch Pad Phase 3 step 0 (`agents/launch-pad.md:233`). Exact wording pattern: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-project-memory.sh"`, fold returned facts in as **advisory, subordinate to CLAUDE.md (on conflict CLAUDE.md wins)**; emits only provenance-verified entries; if it emits nothing, proceed normally. Do NOT add any write call. Do NOT change phase budgets.
- **Subtask 2 (worker.md + RESULT_SCHEMAS.md):** In worker.md "Output Format", add an **optional** `memory_candidates: [<one-line strings>]` line to the WORKER_RESULT block (keep `schema_version: 2` — additive optional field, no bump) and a short step describing WHEN to populate it (durable, reusable, decision-changing facts about *this codebase* not already in CLAUDE.md/memory). State explicitly: **Workers run in worktrees and MUST NEVER call `write-project-memory.sh` — they only PROPOSE candidate strings.** In RESULT_SCHEMAS.md WORKER_RESULT section, document the optional field + the "never secrets/PII/tokens" rule + "no schema_version bump (v2 optional-add pattern)".
- **Subtask 3 (version + docs):** Bump `plugin.json` and `marketplace.json` to `14.4.0` (+ a cumulative description clause). Add a v14.4.0 banner to CLAUDE.md and update the line-32 manifest annotation + any current-version claim. Note in CLAUDE.md that Supervisor now reads memory and Workers propose candidates (P2b's deferred half landed). **No** new agent/command/skill/hook → counts unchanged (hooks stay 19). Run `bash scripts/check-doc-currency.sh` and `bash scripts/validate-version.sh` — both MUST pass before finishing.
- **Do not auto-promote** worker candidates to memory in this increment — surfacing them in WORKER_RESULT is the whole deliverable; human/P4 promotion is out of scope.

## Skill References
- Subtask 1: `skills/state-management/SKILL.md`, `skills/workflow-management/SKILL.md`
- Subtask 2: `skills/error-handling/SKILL.md`
- Subtask 3: doc-currency gate (`scripts/check-doc-currency.sh`)

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Worker auto-writing memory from a worktree (red-team F1 regression) | HIGH | Brief mandates workers ONLY emit candidate strings, never invoke write-project-memory.sh; writer refuses worktree CWD as backstop. Code Reviewer MUST verify no write call added to worker.md. |
| Scope creep into auto-promotion of candidates | MEDIUM | v1 surfaces candidates only; human/P4 promotes. Auto-write explicitly deferred. |
| Secrets leaking into memory_candidates | MEDIUM | Document: durable structural facts only, never secrets/PII/tokens (Memory Core Principle). |
| Version-claim drift across docs | LOW | doc-currency gate is CI-enforced; Subtask 3 runs it before finishing. |

## Configuration
- **Workers:** 2 | **Mode:** parallel | **Estimated batches:** 2

## Feasibility (Phase 2.5)
| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown agent prompts + bash; no new deps |
| 2 | Dependency Availability | GO | read/write-project-memory.sh already shipped (v14.3.0) |
| 3 | Architecture Fit | GO | Extends the existing P2b memory contract; matches Launch Pad Phase 3 step 0 pattern |
| 4 | Scope vs Supervisor | GO | 3 bounded subtasks, ~30 min each |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** GO

## Plan Review
- **Decision:** PASS (attempt 1/3) — all 13 criteria.
- **Note (non-blocking):** dev-path-vs-runtime-path prose nuance only; load-bearing criteria use the runtime-correct `${CLAUDE_PLUGIN_ROOT}` form.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-05-31-round-out-p2-memory.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/19
- **Branch:** feature/v14.4.0-round-out-p2 (base: main)
- **Subtasks completed:** 3/3
- **Phase 4.5 self-heal:** heal_decision=PASS, heal_iterations=1, 0 new issues
- **Version:** 14.4.0
