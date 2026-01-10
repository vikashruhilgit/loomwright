---
name: workflow-management
description: Patterns for managing autonomous workflows including context, checkpoints, and permissions. Use when orchestrating multi-stage agent workflows.
allowed-tools: [Read, Bash]
---

# Workflow Management Skill

Patterns for autonomous workflow execution with context management, checkpoints, and permission handling.

## Quick Rules

- Keep supervisor context < 2000 tokens
- Save checkpoint after each stage completion
- Summarize subagent outputs (< 200 tokens each)
- Pause on NEEDS_HUMAN, retry on FAIL (max 3x), continue on PASS
- Exit gracefully at > 85% context usage

## When to Use This Skill

- Managing multi-stage autonomous workflows
- Coordinating multiple agents
- Handling context limits and checkpoints
- Implementing permission batching
- Error recovery and escalation

## Context Budget

| Component | Token Budget |
|-----------|--------------|
| Supervisor state | < 2000 tokens |
| Subagent summaries | < 200 tokens each |
| Checkpoint data | < 500 tokens |
| Error context | < 300 tokens |
| **Total overhead** | < 3000 tokens |

**Subagents run in isolation** with their own context. Only summaries return to supervisor.

## Checkpoint Format

Save checkpoint to Beads after each stage:

```bash
bd comment BD-XX "## Supervisor Checkpoint
- Stage: [N]/9 ([stage name])
- Progress: [X]/[Y] subtasks complete
- Branch: feature/BD-XX-[description]
- Files modified: [file1], [file2]
- Last review: [PASS/FAIL/NEEDS_HUMAN]
- Resume: /supervisor --continue task: BD-XX"
```

**Example:**

```bash
bd comment BD-15 "## Supervisor Checkpoint
- Stage: 5/9 (Implementation Loop)
- Progress: 2/3 subtasks complete
- Branch: feature/BD-15-user-auth
- Files modified: src/auth/jwt.guard.ts, src/auth/jwt.guard.spec.ts
- Last review: PASS
- Resume: /supervisor --continue task: BD-15"
```

## Context Monitoring

```
┌─────────────────────────────────────────────────────────┐
│ CONTEXT THRESHOLDS                                      │
├─────────────────────────────────────────────────────────┤
│  < 70%  │ Normal operation                             │
│  70-85% │ Warning: Force checkpoint, compress context  │
│  > 85%  │ Critical: Checkpoint + graceful exit         │
│         │ Output: "Run /supervisor --continue"         │
└─────────────────────────────────────────────────────────┘
```

**At > 85% context:**
1. Save checkpoint immediately
2. Output resume command
3. Exit gracefully with status summary
4. User runs `/supervisor --continue task: BD-XX` in new session

## Resume Protocol

When resuming from checkpoint:

```
1. Read checkpoint from Beads task comments
2. Parse: stage, progress, branch, files
3. Switch to saved branch: git checkout [branch]
4. Skip completed stages
5. Continue from checkpoint stage
```

**Checkpoint Parsing:**

```
Stage: 5/9 (Implementation Loop)
         │ └─ Stage name (informational)
         └─ Current stage number

Progress: 2/3 subtasks complete
          │ └─ Total subtasks
          └─ Completed count
```

## Permission Batching

### Layer 1: Auto-Approve Safe Commands

These commands execute without permission prompts:

| Category | Commands |
|----------|----------|
| Git (read) | `status`, `branch`, `log`, `diff` |
| Git (write) | `checkout`, `add`, `commit`, `push`, `pull` |
| Beads | All `bd` commands |
| GitHub | `gh pr create`, `gh pr view`, `gh pr list` |
| Build | `npm test`, `npm run lint`, `npm run build` |
| Read | `ls`, `cat`, `head`, `tail` |

### Layer 2: Batch by Stage

Group related actions for single approval:

```markdown
## Supervisor: Stage 2 - Branch Setup

**Actions to perform:**
1. git checkout main
2. git pull
3. git checkout -b feature/BD-15-user-auth
4. bd claim BD-15

[Approve All] [Review Each] [Cancel]
```

### Layer 3: Approval Checkpoints

Strategic pause points for human review:

| Stage | Approval Needed |
|-------|-----------------|
| 1. Task Selection | Auto (read-only) |
| 2. Branch Setup | **[APPROVAL NEEDED]** |
| 3. Requirements | Auto (subagent) |
| 4. Task Planning | Auto (subagent) |
| 5. Implementation | **[APPROVAL NEEDED - batch]** |
| 6. Commits | **[APPROVAL NEEDED]** |
| 7. Pull Request | **[APPROVAL NEEDED]** |
| 8. Task Completion | Auto (read-only) |
| 9. Next Task | Loops to 1 |

## Error Recovery

| Error | Max Retries | Action |
|-------|-------------|--------|
| Code review FAIL | 3 | Fix issues, re-review |
| Code review FAIL (3x) | - | Escalate to human |
| NEEDS_HUMAN decision | - | Pause, notify, await input |
| Git conflict | - | Pause, show conflict, await resolution |
| Agent timeout | 1 | Retry once, then escalate |
| No ready tasks | - | Report and exit gracefully |
| Context > 85% | - | Checkpoint + graceful exit |

**Escalation Format:**

```markdown
## ESCALATION REQUIRED

**Task:** BD-15 (User Authentication)
**Stage:** 5/9 (Implementation Loop)
**Error:** Code review FAIL after 3 attempts

**Last Review Issues:**
- Type safety: Found 2 `any` types in jwt.guard.ts:45, :67
- Tests: Missing edge case for expired token

**Options:**
1. Fix issues manually and run `/supervisor --continue`
2. Reassign task: `bd update BD-15 --assignee [user]`
3. Cancel workflow and revert: `git checkout main`
```

## Subagent Orchestration

### Spawning Pattern

```
Supervisor spawns subagent → Subagent works (isolated) → Returns summary → Supervisor continues
```

**Spawn via Task tool:**

```
Task(prompt="...", subagent_type="orchestrator")
Task(prompt="...", subagent_type="code-reviewer")
```

### Summary Extraction

After each subagent, extract minimal summary:

| Agent | Summary Template |
|-------|------------------|
| Product Owner | "Story BD-XX: [title]. Criteria: [count] items." |
| Orchestrator | "Created [N] subtasks: [IDs]. First: [ID] - [title]" |
| Implementer | "Modified: [files]. Added: [N] lines. Tests: [pass/fail]" |
| Code Reviewer | "Decision: [PASS/FAIL/NEEDS_HUMAN]. Issues: [count]" |
| Repo Steward | "Commits: [SHAs]. Message: [summary]" |

## Workflow State Machine

```
START → TASK_SELECTION → BRANCH_SETUP → REQUIREMENTS_CHECK → TASK_PLANNING
                                                                    ↓
NEXT_TASK ← TASK_COMPLETION ← PR_CREATION ← COMMIT_CREATION ← IMPLEMENTATION_LOOP
    ↓                                                               ↓
   END                                                          (loop subtasks)
```

**Transitions:**

```
TASK_SELECTION:
  - ready_tasks_exist → BRANCH_SETUP
  - no_ready_tasks → END

IMPLEMENTATION_LOOP:
  - PASS → next_subtask or COMMIT_CREATION
  - FAIL (< 3x) → fix_and_retry
  - FAIL (3x) → ESCALATION
  - NEEDS_HUMAN → PAUSED

TASK_COMPLETION:
  - more_tasks → NEXT_TASK → TASK_SELECTION
  - no_more_tasks → END
```

## Quality Checklist

Before completing workflow management:
- [ ] Checkpoint saved after each stage
- [ ] Context budget respected (< 3000 tokens overhead)
- [ ] Subagent outputs summarized (< 200 tokens each)
- [ ] Error handling covers all failure modes
- [ ] Resume command provided at pause points
- [ ] Permission batching applied to reduce friction
- [ ] Escalation format includes context for human

## See Also

- `skills/context-summarization/SKILL.md` - Output compression patterns
- `skills/commit/SKILL.md` - Conventional commit format
- `skills/quality-checklist/SKILL.md` - Review gate criteria

