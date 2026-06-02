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
| Launch Pad | yes (plan-reviewer only) | yes | yes | no | no | jobs/pending/ | inherit |
| Product Owner | no | no | yes | no | no | no | inherit |
| Orchestrator | no | no | yes | no | no | no | inherit |
| Red Team Reviewer | no | no | yes | no | no | no | inherit |
| QA Strategist | no | no | yes | no | no | no | inherit |
| Plan Reviewer | no | no | no | yes | no | no | inherit (effort: high) |
| Rubric Grader | no | no | yes (read-only git only) | yes (rubric scoring) | no | no | haiku |
| QA Executor | yes | yes | yes | no | yes | no | inherit |

## disallowedTools (Defense-in-Depth)

These are **defense-in-depth** restrictions for accidental misuse, NOT security boundaries against adversarial scenarios.

| Agent | disallowedTools | Rationale |
|-------|----------------|-----------|
| Context-Keeper | Task, Bash, Glob, Grep | Sole state writer; must never spawn agents or explore |
| Worker | Task | Must never spawn subagents |
| Plan Reviewer | Write, Edit, NotebookEdit, Task, Bash | Read-only; no mutation via any path |
| Rubric Grader | Write, Edit, Task, NotebookEdit | Read-only Phase 4.5 grader; advisory only — must never mutate the diff it scores or spawn sub-agents |
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
| Launch Pad | ~5-7k tokens | Discovery + analysis + brief assembly + plan review (~5k typical, ~7k worst-case with 3 review cycles) |
| Product Owner | ~4k tokens | Domain analysis + story writing |
| Orchestrator | ~3k tokens | Task decomposition |
| Plan Reviewer | ~3k tokens | Focused brief validation |
| Rubric Grader | ~2k tokens output; input window scales with diff size (typically 5–50k tokens for a v12.x-style feature branch; larger PRs may need more) | One-shot diff read + per-item scoring; budget is intentionally output-side because the agent emits only N×short justifications plus a single `rubric_score: N/M` line. Input is `git diff origin/main...{branch}` — sized by the feature, not the grader. |
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
- **Cross-cutting hooks:** Code Reviewer, QA Executor, Plan Reviewer (SubagentStop in `hooks.json`)
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
| Launch Pad | 55 | Return partial brief with LOW confidence |
| Plan Reviewer | 20 | Return partial review |
| Product Owner | 40 | Return partial stories |
| Orchestrator | 40 | Return partial task plan |
| Red Team Reviewer | 60 | Return partial audit |
| QA Strategist | 40 | Return partial risk classification |
| QA Executor | 80 | Return partial QA_RESULT |

### Supervisor Phase 1.5 PRE-FLIGHT SYNC budget

The Phase 1.5 PRE-FLIGHT SYNC gate (remote-state reconciliation, runs after Phase 1 ACQUIRE and before Phase 2 PLAN) is itself a bounded sub-phase inside the Supervisor's 30-tool-call budget:

| Bound | Value | Rationale |
|-------|-------|-----------|
| Tool-call budget | ≤ 6 tool calls | Hard ceiling for the whole gate (`git log`, `gh pr list` + per-PR file listing, classification reads). |
| Marginal cost (common path) | ~2–3 tool calls | Reuses the `git fetch origin "$BASE_BRANCH"` already performed in Phase 1 ACQUIRE, so the CLEAR path adds little; the `unverified` / `--skip-preflight-sync` paths cost less. |
| Per-invocation soft budget | short (~20s ceiling per `gh`/`git` invocation) — SOFT design guideline — no native shell-level enforcement; the agent self-limits or abandons the call by judgment. | On any tooling unavailability, error, or timeout the gate records "pre-flight unverified", emits one warning, sets `preflight_sync = unverified`, and continues — it NEVER hard-blocks on a tooling failure. |

Authoritative gate semantics live in `agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC"; the `preflight_sync` SUPERVISOR_RESULT field and the `preflight_overlap_detected` AUTONOMOUS_RUN status_reason are defined in `docs/RESULT_SCHEMAS.md`.

---

## Stacked Branches (autonomous loop)

**New in v14.0.0** — the `/autonomous` orchestration shell now defaults to
**stacked branches** within multi-iteration runs. This subsection documents
the contract, the two-line-of-defense PR-base verification, and the
out-of-order merge hazard.

### Default semantics (stacked-branches mode)

- **Multi-iteration is the default** in v14 (v13's "default single, opt-in
  multi" flipped). Iter N+1's feature branch is created from
  `iterations[N].branch` (the branch the previous iteration's Supervisor
  produced) rather than from `main`. No merge is required between
  iterations — the next iteration just builds on top.
- The opt-out is `--no-stacked-branches`, which reverts to v13 cadence:
  each iteration branches from `main` and the user must merge the prior
  iteration's PR before the next iteration can run safely.
- The declared base for each iteration is recorded in
  `SUPERVISOR_RESULT.branch_base` (v14.0.0 additive field; see
  `docs/RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT"). When absent OR `null`,
  consumers treat the base as `"main"`.

### Two-line-of-defense PR-base verification

Stacked branches make base-branch correctness load-bearing — if iter N+1
opens its PR against `main` instead of `iterations[N].branch`, the diff
appears to contain iter N's work too, and reviewers will be confused at
best and self-heal will fix the wrong things at worst. v14 verifies the
base at two independent sites with identical retry policy:

1. **Supervisor — Phase 4 self-verify** (first line of defense). After the
   PR is created, Supervisor reads back the PR's actual base via `gh pr view`
   and compares it to the declared `branch_base` from the brief. Mismatch
   triggers Phase 4.5's base-mismatch cleanup (close-and-redo path; surfaced
   via `SUPERVISOR_RESULT.pr_state`). See `agents/supervisor.md` §"Phase 4
   self-verify" and §"Phase 4.5 base-mismatch cleanup".
2. **Autonomous loop — EVALUATE PR-base verification** (second line of
   defense). After Supervisor returns, the loop independently re-reads the
   PR's base via `gh pr view` and compares it against the expected stacked
   parent (`iterations[N-1].branch`). Mismatch triggers the user-prompt-
   and-retry policy (AC-14); terminal abort uses
   `status_reason: "iter_pr_base_mismatch"`. See
   `skills/autonomous-loop/SKILL.md` §"EVALUATE PR-base verification"
   (AC-3 + AC-15).

Both sites use the same `gh` retry policy: transient failures prompt the
user before aborting; explicit user abort surfaces as
`status_reason: "user_aborted_gh_retry"`.

### Out-of-order merge hazard

Stacked PRs MUST be merged **bottom-of-stack first**. Merging iter N+1's PR
before iter N's PR is merged (or rebased onto `main`) silently rewrites
history for downstream tooling and can produce a merge commit that contains
work the user did not intend to ship.

The hazard is **documented, not preventable from inside the plugin** —
GitHub's PR UI does not enforce stack ordering, and the plugin cannot block
a merge that happens out-of-band. Two mitigations are in place:

- **`AUTONOMOUS_RUN.iterations[]` ordering** surfaces the intended merge
  sequence. Reviewers MUST follow this order. The `iterations[]` array is
  ordered by `n` — iter 1, iter 2, ... — and that order IS the merge order;
  there is no separate `merge_order` field on the autonomous-run block.
  See `docs/RESULT_SCHEMAS.md` §"AUTONOMOUS_RUN" for the field shape.
- **`SUPERVISOR_RESULT.pr_state`** (v14.0.0 additive field) records the
  per-iteration PR state after Phase 4.5's base-mismatch cleanup. Downstream
  tooling watching for `"closed_by_loop"` or `"close_attempt_failed"` can
  detect iterations whose PRs were retired and avoid trying to merge them.

### Cross-references

- `agents/supervisor.md` §"Phase 4 self-verify" — first-line PR-base check.
- `agents/supervisor.md` §"Phase 4.5 base-mismatch cleanup" — close-and-redo
  path that populates `pr_state`.
- `skills/autonomous-loop/SKILL.md` §"EVALUATE PR-base verification" and
  §"Signal 1" — second-line PR-base check and the stacked-branch rubric gate.
- `docs/RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT" — `branch_base` + `pr_state`
  field documentation.
- `docs/RESULT_SCHEMAS.md` §"AUTONOMOUS_RUN" — v14 `status_reason` values
  associated with the verification paths.

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

All result schemas include a `schema_version` field. Current versions: CODE_REVIEW_RESULT at `schema_version: 3` (review modes + consistency audit; v2 accepted for legacy); WORKER_RESULT at `schema_version: 2` (outputs_verified contract; v1 accepted for the v12.0.0 transition window); AUTONOMOUS_RUN at `schema_version: 2` (v14.0.0 status_reason extension; v1 accepted, no hook validation); LAUNCH_PAD_RESULT at `schema_version: 1` (added v14.2.0, validated by `scripts/validate-launch-pad-result.py`); all others at `schema_version: 1`.

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
| Plan Reviewer | 0 | Returns result to Launch Pad |
| Launch Pad (Plan Review FAIL) | 3 | Block save, user refines |
| Launch Pad (Plan Review NEEDS_HUMAN) | 0 | User override or refine |

---

## Cost Profiles

Single source of truth for cost-profile model overrides. Referenced by Supervisor and Execute Manager.

### `--cheap` Profile

Applies when `/supervisor --cheap` is passed. Supervisor and Execute Manager apply `model: "sonnet"` at spawn time for the roles marked **sonnet** in the table below. Default behavior (`inherit` for all) is unchanged when the flag is absent.

| Role | Default | `--cheap` override |
|---|---|---|
| worker | inherit | **sonnet** |
| code-reviewer | inherit | **sonnet** |
| execute-manager | inherit | **sonnet** |
| orchestrator | inherit | **sonnet** |
| phase45-fix-task (general-purpose) | inherit | **sonnet** |
| supervisor | inherit | inherit (main thread; uses session model) |
| context-keeper | haiku | haiku (already minimal) |
| launch-pad | inherit | inherit (out of v1 scope) |
| product-owner | inherit | inherit (judgment) |
| plan-reviewer | inherit | inherit (gating) |
| qa-strategist | inherit | inherit (gating) |
| red-team-reviewer | inherit | inherit (adversarial creativity) |
| qa-executor | inherit | future — not spawned by `/supervisor`; deferred to v2 when `/qa-executor --cheap` ships |

**Semantics:** `--cheap` overrides roles marked **sonnet** in the table to Sonnet, full stop. No runtime session detection. Consequences:
- Opus session + `--cheap` → roles marked **sonnet** run on Sonnet (intended saving)
- Sonnet session + `--cheap` → roles marked **sonnet** already match; behavior identical to no-flag path
- Haiku session + `--cheap` → roles marked **sonnet** **upgrade** to Sonnet (costs more). Haiku users should not pass `--cheap`.

**Propagation:** `cost_profile` is a session attribute. Supervisor records it in `.supervisor/state.md` (via Context-Keeper `initialize`) and passes it to Execute Manager via the Task prompt. Supervisor applies overrides for Orchestrator, Execute Manager, Phase 4.5 Code Reviewer, and Phase 4.5 fix tasks. Execute Manager reads `cost_profile` from its incoming prompt and applies overrides for Worker and Code Reviewer spawns within the poll loop.

**Frontmatter unchanged:** No agent's `model:` frontmatter is modified. The override is applied at spawn time via the Task tool's `model` parameter. If the Task `model` override is ever removed in a future Claude Code release, the profile degrades gracefully to `inherit`.

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
| Plan Reviewer | Medium Turquoise | `#48D1CC` |
| QA Executor | Orange Red | `#FF4500` |

---

## Effort Tier

The `effort:` frontmatter field on each agent maps to an adaptive thinking tier. Tiers communicate intent — Opus 4.7 manages the actual thinking budget adaptively, so explicit `budget_tokens` are no longer required.

| Tier | Agents | Rationale |
|------|--------|-----------|
| `xhigh` | red-team-reviewer | Adversarial deep analysis with persistent memory across audits |
| `high` | code-reviewer, launch-pad, worker, qa-executor, qa-strategist, plan-reviewer | Implementation, exhaustive analysis, or cross-file validation |
| `medium` | supervisor, execute-manager, orchestrator | Pure orchestration / coordination |
| omitted | context-keeper, product-owner | Haiku model (context-keeper) or no thinking budget needed (product-owner) |

### Opus 4.7 Migration Note

- **Adaptive thinking replaces explicit `budget_tokens`.** Earlier configs that pinned an exact thinking budget per agent are now expressed as a tier; the model expands or contracts thinking on its own within that tier.
- **`xhigh` is a new top-level tier above `high`.** Reserve it for agents whose value comes from going deeper than a normal high-effort review — currently red-team-reviewer is the only one in this tier.
- **Tokenizer change — 4.7 uses 1.0–1.35× more tokens than 4.6 for the same input.** Tool-call budgets and `tool_call_count` thresholds in this document were sized against 4.6. Sessions on 4.7 may hit the same RED thresholds earlier in real wall time. **Recommendation:** monitor `tool_call_count` against the thresholds documented in this file and adjust downward if you observe RED triggering earlier than expected. No automatic rescaling is applied.
