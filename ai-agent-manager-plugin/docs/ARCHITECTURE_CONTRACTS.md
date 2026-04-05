# Architecture Contracts

> Single source of truth for agent capabilities, budgets, hooks, state ownership, and performance targets.
> Referenced by all agents and hooks. Consolidates rules currently spread across multiple files.

---

## Agent Capability Matrix

| Agent | Spawn | Write | Bash | Review | Tests | State | Model |
|-------|-------|-------|------|--------|-------|-------|-------|
| Supervisor | yes | yes | yes | no | no | via Context-Keeper | inherit |
| Execute Manager | yes | no | yes | no | no | via Context-Keeper | inherit |
| Worker | no | yes | yes | no | yes | no | inherit |
| Code Reviewer | no | no | yes (+ LSP) | yes | no | no | inherit (effort: high, permissionMode: plan) |
| Context-Keeper | no | yes | no | no | no | sole writer | haiku |
| Launch Pad | no | yes | yes | no | no | jobs/pending/ | inherit |
| Product Owner | no | no | yes | no | no | no | inherit |
| Orchestrator | no | no | yes | no | no | no | inherit |
| Red Team Reviewer | no | no | yes | no | no | no | inherit |
| QA Strategist | no | no | yes | no | no | no | inherit |
| QA Executor | yes | yes | yes | no | yes | no | inherit |

## disallowedTools (Defense-in-Depth)

These are **defense-in-depth** restrictions for accidental misuse, NOT security boundaries against adversarial scenarios.

| Agent | disallowedTools | Rationale |
|-------|----------------|-----------|
| Context-Keeper | Task, Bash, Glob, Grep | Sole state writer; must never spawn agents or explore |
| Worker | Task | Must never spawn subagents |
| QA Strategist | Task | Read-only analyzer |

---

## Context Budget Guidelines

| Agent | Max Context | Rationale |
|-------|-------------|-----------|
| Supervisor | ~800 tokens | Pure orchestrator, everything else in state file |
| Execute Manager | ~2k tokens | Poll loop + worker tracking |
| Worker | ~6k tokens | Focused implementation |
| Code Reviewer | ~4k tokens | Read-only analysis |
| Context-Keeper | ~200 tokens | Atomic state ops, < 50 token responses |
| QA Executor | ~8k tokens | Discovery + generation + execution |
| QA Strategist | ~3k tokens | Risk classification |
| Launch Pad | ~5k tokens | Discovery + analysis + brief assembly |
| Product Owner | ~4k tokens | Domain analysis + story writing |
| Orchestrator | ~3k tokens | Task decomposition |
| Red Team Reviewer | ~6k tokens | Deep adversarial analysis |

---

## Hook Performance Rules

- **Prompt hooks:** Execution < 5 seconds, timeout 30 seconds
- **Agent-based hooks:** Execution < 30 seconds (future)
- No network calls in prompt hooks
- No long file parsing — validate structure, not semantics
- Hooks validate output format, not code correctness

---

## Schema Validation

- **Location:** Per-agent SubagentStop hooks (hook execution layer)
- **Reference:** `docs/RESULT_SCHEMAS.md`
- **Per-agent hooks:** Worker, Execute Manager (SubagentStop in agent frontmatter), Code Reviewer (Stop in agent frontmatter)
- **Cross-cutting hooks:** Code Reviewer, QA Executor (SubagentStop in `hooks.json`)
- **Dual-hook note:** Code Reviewer intentionally has both a per-agent `Stop` hook (validates CODE_REVIEW_RESULT block exists before finishing — completeness gate) AND a cross-cutting `SubagentStop` hook (validates output schema after completion — format gate). These are complementary: Stop catches incomplete reviews, SubagentStop validates structure.
- **Never duplicated** in Supervisor or plugin runtime

---

## State Ownership

| Resource | Owner | Access |
|----------|-------|--------|
| `.supervisor/state.md` | Context-Keeper (sole writer) | Supervisor, Execute Manager (read via CK query) |
| `.supervisor/jobs/pending/` | Launch Pad (create) | Supervisor (move to in-progress) |
| `.supervisor/jobs/in-progress/` | Supervisor (move from pending) | Supervisor (move to done/failed) |
| `.supervisor/jobs/done/` | Supervisor (move from in-progress) | Read-only after move |
| `.supervisor/jobs/failed/` | Supervisor (move from in-progress) | Read-only after move |
| `.supervisor/logs/` | Supervisor, Execute Manager, Worker | Append-only JSONL |
| `.supervisor/history/` | Supervisor (create) | Read-only after creation |
| `.supervisor/worker-summaries/` | Worker (inline mode) | Execute Manager (read) |
| `.worker-summary.md` (in worktree) | Worker (parallel mode) | Execute Manager (read) |
| `.qa-summary.md` | QA Executor (write) | QA Strategist (read in audit mode) |

---

## Agent Timeout Rules

| Agent | maxTurns | On timeout |
|-------|----------|------------|
| Supervisor | — (uses 30 tool call budget) | Checkpoint and halt |
| Execute Manager | 80 | Return EXECUTE_CHECKPOINT |
| Worker | 40 | Return WORKER_RESULT status=failed |
| Code Reviewer | 40 | Return partial review |
| Context-Keeper | 3 | Fail (caller retries once) |
| Launch Pad | 40 | Return partial brief with LOW confidence |
| Product Owner | 40 | Return partial stories |
| Orchestrator | 40 | Return partial task plan |
| Red Team Reviewer | 60 | Return partial audit |
| QA Strategist | 40 | Return partial risk classification |
| QA Executor | 80 | Return partial QA_RESULT |

---

## Worktree Naming Convention

Prevents collisions between parallel workers.

```
Path:    ../{repo}-{task_id}-{slug}
Branch:  feature/{task_id}-{slug}
Example: ../myapp-42-add-auth, branch feature/42-add-auth
```

- WorktreeCreate hook (hooks.json, type: command) logs worktree creation to `.supervisor/logs/worktrees.log`
- Sibling directory (not nested) prevents git issues
- Branch matches worktree slug for traceability

---

## Worker File Change Limits

| Metric | Limit | On exceed |
|--------|-------|-----------|
| Files modified | 25 | Worker must split task, return WORKER_RESULT status=partial |
| Files created | 10 | Worker must split task, return WORKER_RESULT status=partial |

Prevents runaway refactors and reviewer context explosion.

---

## Result Schema Versioning

All result schemas include a `schema_version` field. CODE_REVIEW_RESULT is at v2 (with issue categories); all others remain at v1.

1. Hooks verify `schema_version` is supported before validating fields
2. If `schema_version` is unrecognized, hook warns but does not block
3. New fields can be added without breaking existing validation
4. Breaking changes require incrementing `schema_version`

---

## Quantitative Performance Targets

| Metric | Target | Source |
|--------|--------|--------|
| Task pass rate | ≥90% | WORKER_RESULT status=completed |
| First-pass review rate | ≥80% | CODE_REVIEW_RESULT decision=PASS |
| QA coverage | ≥70% routes | QA_RESULT coverage_estimate |
| Worker retry rate | ≤10% | Logs (retry count / total spawns) |
| Merge success rate | ≥95% | Supervisor FINALIZE outcomes |

Tracked in `.supervisor/observations/metrics.jsonl` when learning system is active (v7.0.0+).

---

## Failure Escalation Summary

See `docs/FAILURE_ESCALATION.md` for full paths.

| Agent | Max Retries | Escalation Target |
|-------|-------------|-------------------|
| Worker | 1 | Execute Manager → Supervisor |
| Execute Manager | 1 (fresh spawn) | Supervisor → Human |
| Code Reviewer (FAIL) | 3 | Supervisor → Human |
| Code Reviewer (NEEDS_HUMAN) | 0 | Supervisor → Human (3x = halt) |
| QA Executor | 0 | Partial result (non-blocking) |
| Supervisor | 0 | Human (checkpoint + exit) |
| Context-Keeper | 1 | Degraded mode |

---

## Color Legend (Status Line)

| Agent | Color | Hex |
|-------|-------|-----|
| Launch Pad | Gold | `#FFD700` |
| Supervisor | Dodger Blue | `#1E90FF` |
| Execute Manager | Royal Blue | `#4169E1` |
| Context-Keeper | Slate Gray | `#708090` |
| Worker | Lime Green | `#32CD32` |
| Product Owner | Dark Orange | `#FF8C00` |
| Orchestrator | Medium Purple | `#9370DB` |
| Code Reviewer | Light Sea Green | `#20B2AA` |
| Red Team Reviewer | Crimson | `#DC143C` |
| QA Strategist | Tomato | `#FF6347` |
| QA Executor | Orange Red | `#FF4500` |
