---
description: Autonomously manage development workflow with parallel execution from task pickup to PR creation
---

> **Execute this workflow inline as the main thread.** Do not delegate to `ai-agent-manager-plugin:supervisor-runner` via the Agent tool — a delegated subagent cannot spawn further subagents ([docs](https://code.claude.com/docs/en/sub-agents)) and the workflow will silently abort with "Task/Agent tool unavailable". To run the agent in its own session instead, launch with `claude --agent ai-agent-manager-plugin:supervisor-runner`.

> **Execution contract:** Inline main-thread execution replaces only the top-level `supervisor-runner`. You MUST still spawn first-level child agents via the Task tool for every phase that requires them: `orchestrator` (Phase 2), `execute-manager` or fast-path worker/reviewer (Phase 3), and the Phase 4.5 `code-reviewer` + fix-task loop. Do NOT collapse the workflow into direct main-thread implementation. Phase 4.5 is mandatory unless `--skip-self-heal` was explicitly passed — reaching the completion tail without invoking `code-reviewer` and without the flag is an internal workflow error (enforced by the Phase 4.5 completion-tail guard in `agents/supervisor.md`).

# Command: /supervisor

## Purpose

The Supervisor agent v4 autonomously manages the complete development workflow. It picks up tasks, delegates Phase 3 execution to the Execute Manager, orchestrates parallel workers via git worktrees, manages quality gates, and creates Pull Requests. Uses `.supervisor/` for all state management.

## Usage

```bash
/supervisor                                    # Auto-select next ready task
/supervisor task: BD-XX                        # Work on specific task
/supervisor --max-workers 3                    # Up to 3 parallel workers
/supervisor --sequential                       # Force sequential (no worktrees)
/supervisor --continue                         # Resume from last checkpoint
/supervisor --continue task: BD-XX             # Resume specific task
/supervisor --dry-run                          # Preview workflow without executing
/supervisor job: .supervisor/jobs/2026-02-08-jwt-auth.md   # Execute from Launch Pad brief
/supervisor --skip-self-heal                   # Skip Phase 4.5 review+fix loop (emergency bypass)
/supervisor --heal-iterations 5                # Allow up to 5 fix iterations before escalating (default 3)
/supervisor --cheap                            # Cost-optimized: orchestrator, execute-manager, workers, code-reviewer, fix tasks run on Sonnet
/supervisor --base-branch feature/v14-iter1    # Stack PR on a non-main base (v14 autonomous-loop multi-iter)
/supervisor --non-interactive                  # Fail closed instead of prompting on gh/adjudication gates (set by /autonomous loop)
/supervisor --skip-preflight-sync              # Short-circuit the Phase 1.5 remote-overlap reconciliation gate (escape hatch)
/supervisor --auto-review                      # Opt in: dispatch standalone /review-pr review-and-heal on the PR after completion
/supervisor --no-auto-review                   # Suppress the post-completion auto-review dispatch (overrides notify-config)
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task:` | No | Specific task ID to work on (e.g., `task: BD-15` or `task: user-auth`) |
| `--max-workers N` | No | Maximum parallel worktrees (default: 2) |
| `--sequential` | No | Force sequential execution — no worktrees or parallelism |
| `--continue` | No | Resume workflow from last checkpoint |
| `--dry-run` | No | Preview the workflow phases without executing any actions |
| `job:` | No | Path to Supervisor-Ready Brief from Launch Pad (e.g., `.supervisor/jobs/pending/{file}.md`) — skips Phases 0-2, moves brief through lifecycle (pending → in-progress → done/failed) |
| `--skip-self-heal` | No | Bypass the Phase 4.5 integration review + fix loop. Phase 4.5 still transitions in state and runs the completion tail, but no review is performed. Use for emergency merges; the heal fields in SUPERVISOR_RESULT will show `heal_loop_ran: false`. **Absence of this flag makes Phase 4.5 mandatory** — reaching the completion tail without having invoked the `code-reviewer` Task is an internal workflow error (the completion-tail guard will emit `status: failed` and leave the job in `in-progress/`). |
| `--heal-iterations N` | No | Maximum self-heal fix iterations before escalating (default: 3). Each iteration is: integration review → fix task → re-review. Lower values escalate sooner; higher values attempt more fixes but risk never passing. |
| `--cheap` | No | Cost-optimized profile: spawns orchestrator, execute-manager, workers, code-reviewer, and Phase 4.5 fix tasks with `model: "sonnet"` override at spawn time. Default behavior (`inherit` for all) is unchanged when flag is absent. **Caution:** on Haiku sessions, listed roles upgrade to Sonnet (costs more). See `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles". |
| `--base-branch <name>` | No | Override default base branch for FINALIZE PR creation. Default: `main`. Set by the `/autonomous` loop's multi-iteration mode so iteration N+1 stacks on iteration N's feature branch (v14.0.0). The brief's `## Configuration` block may also carry a `Base Branch:` field — when present it MUST match this flag (Plan Reviewer validates the brief field independently). Phase 4 FINALIZE self-verifies the created PR's `baseRefName` matches this value and aborts via Phase 4.5 cleanup on mismatch. |
| `--non-interactive` | No | Suppress `AskUserQuestion` fallbacks; on `gh` failures and ambiguous gates, fail closed with a diagnostic instead of prompting. Set automatically by the `/autonomous` loop when chaining iterations; rarely passed by humans. Recorded as a Phase Flag at Phase 0 so later phases can re-read after context loss (W-NEW-10 mitigation). |
| `--skip-preflight-sync` | No | Short-circuit the Phase 1.5 PRE-FLIGHT SYNC gate, which reconciles the requested work against recent `origin/$BASE_BRANCH` commits and open PRs (same-file overlap + already-merged equivalents) and classifies the task CLEAR / OVERLAP / SUPERSEDED. The skip is recorded as a deliberate choice (`record_decision`) and `preflight_sync` is set to `skipped`. Escape hatch for when remote-overlap reconciliation is known-unnecessary or when intentionally re-doing landed work. Under `--non-interactive` / CI this is also the only way to proceed past an OVERLAP/SUPERSEDED classification (which otherwise fails closed). |
| `--auto-review` | No | Opt in to the post-completion auto-review dispatch: on a PASS/normal completion that produced a PR, Phase 4.5's completion tail launches a fresh, detached standalone review-and-heal run (`/review-pr` via `ai-agent-manager-plugin:review-pr-runner`) against the PR. **OFF by default.** Equivalent to setting `.auto_review: true` in `.supervisor/notify-config.json`. Best-effort and fire-and-forget — the dispatcher always exits 0 and never affects the Supervisor result, the PR, or control flow. Because `/review-pr` never creates a PR, there is no review→review recursion. |
| `--no-auto-review` | No | Suppress the post-completion auto-review dispatch even when `.supervisor/notify-config.json` has `.auto_review: true`. Wins over `--auto-review` if both are passed. |

## What This Does

The Supervisor executes a **7-phase parallel workflow**:

```
┌─────────────────────────────────────────────────────────────────┐
│              SUPERVISOR v4 — PARALLEL WORKFLOW                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 0: INIT (Interactive Configuration)                      │
│     └─> Detect env, ask preferences, create .supervisor/        │
│                                                                 │
│  Phase 1: ACQUIRE (Task Selection + Branch — MANDATORY)         │
│     └─> Select task → Create feature branch (NON-NEGOTIABLE)    │
│                                                                 │
│  Phase 1.5: PRE-FLIGHT SYNC (Remote-State Reconciliation) [NEW] │
│     └─> Fetch + scan recent commits/open PRs → classify         │
│         CLEAR/OVERLAP/SUPERSEDED → silent | ask | fail-closed   │
│                                                                 │
│  Phase 2: PLAN (Decompose + Parallelism Analysis)               │
│     └─> Orchestrator → Subtasks → Parallelism graph             │
│                                                                 │
│  Phase 3: EXECUTE (Delegated to Execute Manager)                │
│     └─> Execute Manager → Worktrees → Workers → Reviews         │
│                                                                 │
│  Phase 4: FINALIZE (Merge + Commit + PR)                        │
│     └─> Sequential merge → Commit → Push → PR → exit            │
│                                                                 │
│  Phase 4.5: SELF_HEAL (Integration Review + Fix Loop)  [NEW]    │
│     └─> Holistic Code Reviewer → bounded auto-fix loop →        │
│         completion tail (job → done/, state completed)          │
│                                                                 │
│  Phase 5: LOOP (Next Task or Exit)                              │
│     └─> More tasks? → Phase 1 | No tasks → Done                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Phase 1.5 (v14.8.0):** After ACQUIRE produces a task and a fresh feature branch, and before PLAN spawns the Orchestrator or any worker, Supervisor reconciles the *requested work* against remote state. It fetches `origin/$BASE_BRANCH`, scans recent commits and open PRs (bounded: ≤ 6 tool calls + a short timeout), derives the canonical version + base tip, and classifies the task **CLEAR / OVERLAP / SUPERSEDED** — flagging (a) recent/in-flight work touching the **same files** and (b) an **already-merged equivalent** of the requested work (the v13.1.0→v14.0.0 stale-branch case). CLEAR proceeds silently. OVERLAP/SUPERSEDED prompts the human (proceed-anyway / revise-scope / abort) citing the specific commits/PRs + intersecting paths interactively, or **fails closed** under `--non-interactive`/CI with `status_reason: preflight_overlap_detected`. Degrades gracefully (one warning, `preflight_sync: unverified`, continue) if `gh`/`git fetch` is unavailable, and is short-circuited by `--skip-preflight-sync`. It does **not** duplicate ACQUIRE's fetch/pull or the Phase 4 base-mismatch check — it adds semantic work-overlap reconciliation. See `agents/supervisor.md` "Phase 1.5: PRE-FLIGHT SYNC".

**Phase 4.5 (v11.0.0):** After the PR is created, Supervisor runs a holistic Code Reviewer on the full feature-branch diff. If it finds BLOCKING/HIGH severity `new` issues, Supervisor spawns a fix task that addresses them and pushes updates to the PR. The loop retries up to `--heal-iterations` times (default 3). On PASS the task is marked `completed`; on NEEDS_HUMAN or max iterations the task is marked `completed_with_escalation` with findings posted as a PR comment. Eliminates the manual review-and-fix cycle. The phase always runs (unless `--skip-self-heal` short-circuits the loop); it owns the completion tail (job-file move, state marked completed) so the record captures the heal outcome.

### Architecture

```
SUPERVISOR (pure orchestrator, budget: 30 tool calls)
    ├─> Context-Keeper (blocking, state mutations)
    ├─> Product Owner (blocking, if vague requirements)
    ├─> Orchestrator (blocking, task decomposition)
    └─> Execute Manager (blocking, Phase 3, budget: 60 tool calls)
        ├─> Worker A (background, git worktree A)
        ├─> Worker B (background, git worktree B)
        ├─> Reviewer A (background, after Worker A)
        └─> Reviewer B (background, after Worker B)
```

### Parallel Execution via Git Worktree

```
project/                    ← main worktree (feature branch)
project-BD-15a/             ← worktree for worker A
project-BD-15c/             ← worktree for worker C
```

Each parallel worker operates in its own worktree — no file conflicts, no git stash dance. After review passes, subtask branches merge sequentially into the feature branch.

## Prerequisites

1. **Git repository:** Project must be a git repo
2. **Clean git state:** No uncommitted changes (or approve stashing)
3. **GitHub CLI:** `gh` installed and authenticated (for PR creation)

## Example Session

```bash
$ /supervisor

## SUPERVISOR v4: Starting Parallel Workflow

## ENVIRONMENT
**Path:** /Users/name/my-project
**CLAUDE.md:** ✓ Found
**Git:** clean
**Branch:** main
**Config:** workers=2, mode=parallel

---

### Phase 1: ACQUIRE
- Task: BD-15 (high)
- Title: User authentication with JWT
- Criteria: 5 items
- Branch: feature/BD-15-user-auth ← CREATED

### Phase 1.5: PRE-FLIGHT SYNC (abbreviated — full output adds "Open PRs scanned", "Recent commits scanned", "PRs file-inspected" lines; see `agents/supervisor.md`)
- Canonical version: 14.8.0 | Base tip: a1b2c3d
- Classification: CLEAR (no same-file overlap, no superseding merge)
- Decision: proceed (silent)

### Phase 2: PLAN
- Subtasks: 3 (BD-15a, BD-15b, BD-15c)
- Parallelism: 2 launchable, 1 blocked
- First batch: [BD-15a, BD-15c]

### Phase 3: EXECUTE — BD-15a
- Worker: parallel
- Files: src/auth/jwt.guard.ts
- Review: PASS ✓

### Phase 3: EXECUTE — BD-15c
- Worker: parallel
- Files: src/auth/cookie.service.ts
- Review: PASS ✓

### Phase 3: EXECUTE — BD-15b (unblocked)
- Worker: parallel
- Files: src/auth/refresh.controller.ts
- Review: PASS ✓

### Phase 4: FINALIZE
- Merges: 3 branches → feature/BD-15-user-auth
- Commit: a1b2c3d — feat(auth): implement JWT auth
- PR: #42 — https://github.com/org/repo/pull/42
- Task: BD-15 [MERGED — pending self-heal]

### Phase 4.5: SELF_HEAL
- Heal loop ran: true
- Iterations: 1 (review: FAIL → fix task fixed 2 issues → review: PASS)
- Decision: PASS
- Fixable issues fixed: 2
- Remaining issues: 0
- Task: BD-15 [COMPLETED]

### Phase 5: LOOP
- Outcome: completed (heal_decision=PASS, iterations=1, remaining=0)
- Continuing with BD-18...
```

The `SUPERVISOR_RESULT` block (schema v1, validated by the SubagentStop hook) is emitted from Phase 4.5's completion tail — one block per task. Phase 5 LOOP emits nothing. In multi-task sessions, multiple blocks appear in order; the hook validates the last one. See `docs/RESULT_SCHEMAS.md` for the full schema.

## Review Gates

The Supervisor handles review decisions:

| Decision | Action |
|----------|--------|
| **PASS** | Continue; launch newly unblocked subtasks |
| **FAIL** (< 3 attempts) | Spawn fix worker with retry context |
| **FAIL** (3 attempts) | Checkpoint, escalate to human |
| **NEEDS_HUMAN** | Checkpoint, pause, exit with resume command |

## State Persistence

```
Active session:   {scratchpad}/supervisor-state.md
Persistent:       {project}/.supervisor/state.md
History:          {project}/.supervisor/history/{date}-{task}.md
Jobs lifecycle:   {project}/.supervisor/jobs/
  ├── pending/      ← Launch Pad saves briefs here
  ├── in-progress/  ← Supervisor moves brief here on ACQUIRE
  ├── done/         ← Phase 4.5 SELF_HEAL completion tail moves here (on PASS, loop-skipped, OR ESCALATED — in all cases, with an `## Outcome` block that records heal_loop_ran, heal_decision, heal_iterations, heal_remaining_issues)
  └── failed/       ← Supervisor moves here on hard failure (merge conflict, fix-task crash after retries) before 4.5 completion tail could run
Logs:             {project}/.supervisor/logs/{session_id}.jsonl
```

The `.supervisor/` directory is auto-created and gitignored.

## Checkpoints and Resume

The Supervisor saves checkpoints after every phase transition:

```bash
# If workflow pauses (NEEDS_HUMAN, merge conflict, or context limit):
# State is saved automatically

# Resume from checkpoint:
/supervisor --continue                   # Resume last task
/supervisor --continue task: BD-15       # Resume specific task
```

**Checkpoint data includes:**
- Current phase (e.g., EXECUTE)
- Subtask progress (e.g., 2/3 complete)
- Branch name and worktree state
- Worker/reviewer tracking
- All decisions and results

**Resume priority:**
1. Scratchpad state (same session)
2. `.supervisor/state.md` (cross-session)

## Context Management

The Supervisor uses externalized state and tool call budgets:

- **Supervisor:** 30 tool call budget (~400 tokens context)
- **Execute Manager:** 60 tool call budget (isolated context for Phase 3)
- **State file:** Full session state managed by Context-Keeper
- **Workers:** Run in background with their own isolated context
- **Reviewers:** Run in background with their own isolated context

**Tool call thresholds (Supervisor):**
- 0-18 (60%): GREEN — normal operation
- 18-24 (80%): YELLOW — aggressive compression, force checkpoint
- 24-28 (93%): RED — checkpoint + exit with resume command

## Parallel vs Sequential

### Parallel Mode (default)
- Independent subtasks run concurrently in git worktrees
- Max `--max-workers` concurrent workers (default: 2)
- Subtasks with dependencies wait for predecessors
- Sequential merge into feature branch after completion

### Sequential Mode (`--sequential`)
- All subtasks execute one at a time
- No git worktrees created
- Simpler but slower
- Useful for debugging or constrained environments

### Fast-Path (automatic)
- If only 1 subtask: executes inline (no worktree overhead)
- Automatic, no flag needed

## Permissions

| Phase | Approval |
|-------|----------|
| INIT (config) | Interactive (AskUserQuestion) |
| ACQUIRE (branch) | **[APPROVAL NEEDED]** |
| PRE-FLIGHT SYNC (overlap recon) | Auto on CLEAR; **[APPROVAL NEEDED]** on OVERLAP/SUPERSEDED (AskUserQuestion); fail-closed under `--non-interactive` |
| PLAN (decompose) | Auto (subagent) |
| EXECUTE (implement) | **[APPROVAL NEEDED - batch]** |
| FINALIZE (commit+PR) | **[APPROVAL NEEDED]** |
| LOOP (next) | Auto |

## Error Handling

| Error | Supervisor Action |
|-------|-------------------|
| Review FAIL (3x) | Checkpoint, escalate to human |
| NEEDS_HUMAN | Checkpoint, pause, exit with resume |
| Merge conflict | STOP, report files, exit with resume |
| No ready tasks | Exit gracefully |
| Tool budget exceeded | Checkpoint, exit with resume |
| Worker crash | Retry once, then escalate |
| Worktree fails | Fall back to sequential mode |

## Dry Run Mode

Preview without executing:

```bash
$ /supervisor --dry-run

## SUPERVISOR v4: Dry Run Mode

**Would execute:**
Phase 0: INIT — Detect env, configure session
Phase 1: ACQUIRE — Task BD-15, branch feature/BD-15-user-auth
Phase 2: PLAN — Orchestrator decompose, parallelism analysis
Phase 3: EXECUTE — 3 subtasks (2 parallel, 1 sequential)
Phase 4: FINALIZE — Merge, commit, PR
Phase 5: LOOP — Check for next task

**Estimated parallel batches:** 2 (batch 1: BD-15a,BD-15c; batch 2: BD-15b)

**No changes made.** Run `/supervisor` to execute.
```

## Plan-First Workflow (with Launch Pad)

For complex tasks, use Launch Pad to plan and Supervisor to execute:

```bash
# 1. Prepare the brief (analyzes codebase, decomposes subtasks)
/launch-pad goal: "add JWT authentication"

# 2. Review the brief
# Launch Pad presents the brief for your review
# Choose: Save / Refine / Edit / Discard

# 3. Execute in a fresh session (clean context, ~500 tokens freed)
/supervisor job: .supervisor/jobs/2026-02-08-jwt-auth.md
```

**Benefits:**
- **~500 tokens freed** for execution (Supervisor skips Phases 0-2)
- **Plan review** before any code is written
- **File impact analysis** prevents parallelism mistakes
- **Clean context** — fresh session for Supervisor

**When to use Plan-First:**
- Complex tasks (>3 expected subtasks)
- Want to review plan before workers start
- Need accurate file overlap detection
- Working on unfamiliar codebase

## Workflow Comparison

| Feature | Manual Workflow | Supervisor v3 | Supervisor v4 |
|---------|-----------------|---------------|---------------|
| Task pickup | Manual | Auto (Beads optional) | Auto (`.supervisor/` only) |
| Branch creation | Manual | **MANDATORY** | **MANDATORY** |
| Agent coordination | Run each manually | Parallel (inline poll) | **Parallel (Execute Manager)** |
| State management | In-context only | Externalized | **Externalized + tool call budget** |
| Cross-session resume | Not possible | `.supervisor/` + Beads | **`.supervisor/` only** |
| Parallel workers | Not possible | Git worktrees | **Git worktrees** |
| Context growth | Unbounded | Unbounded in Phase 3 | **Bounded via Execute Manager** |

## Tips

1. **Start with dry-run:** Use `--dry-run` to preview before executing
2. **Use sequential for debugging:** `--sequential` simplifies troubleshooting
3. **Monitor .supervisor/:** Check `.supervisor/state.md` for current state
4. **Resume after pause:** `/supervisor --continue` picks up exactly where it left off
5. **Limit workers:** Use `--max-workers 1` for resource-constrained environments
6. **Plan first for complex tasks:** Use `/launch-pad` to prepare a brief, then `/supervisor job:` for clean-context execution

## Related Commands

| Command | Purpose |
|---------|---------|
| `/launch-pad` | Prepare brief for clean-context execution |
| `/orchestrator` | Plan tasks without executing |
| `/code-reviewer` | Review specific files |
| `/commit` | Create commits manually |
| `/product-owner` | Refine requirements |
| `/red-team-reviewer` | Adversarial audit |

## Troubleshooting

**"No tasks provided"**
- Provide task description directly with `task:` parameter
- Or run interactively and describe the task when prompted

**"Dirty working tree"**
- Commit or stash changes before running Supervisor
- Supervisor will warn and ask for approval

**"Context limit reached"**
- Supervisor saves checkpoint automatically
- Resume with: `/supervisor --continue task: BD-XX`

**"NEEDS_HUMAN escalation"**
- Read the escalation message for context
- Fix the issue manually
- Resume with: `/supervisor --continue`

**"Merge conflict in FINALIZE"**
- Supervisor reports conflicting files
- Resolve manually in the feature branch
- Resume with: `/supervisor --continue`

**"Worktree creation failed"**
- Supervisor automatically falls back to sequential mode
- Check disk space and git worktree state: `git worktree list`

## See Also

- `agents/supervisor.md` - Full agent prompt (7-phase model with Phase 4.5 self-heal)
- `agents/execute-manager.md` - Phase 3 execution agent
- `agents/context-keeper.md` - State management agent
- `agents/worker.md` - Implementation worker agent
- `skills/async-orchestration/SKILL.md` - Parallel dispatch patterns
- `skills/state-management/SKILL.md` - State file schema
- `skills/workflow-management/SKILL.md` - Workflow patterns
- `skills/supervisor-readiness/SKILL.md` - Pre-flight checklist and brief template
- `skills/context-summarization/SKILL.md` - Output compression
