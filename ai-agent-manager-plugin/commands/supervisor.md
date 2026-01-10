---
description: Autonomously manage development workflow from task pickup to PR creation
---

# Command: /supervisor

## Purpose

The Supervisor agent autonomously manages the complete development workflow. It picks up ready tasks from Beads, orchestrates specialized agents (Product Owner, Orchestrator, Code Reviewer, Repo Steward), manages git operations, and creates Pull Requests.

## Usage

```bash
/supervisor                         # Pick up next ready task and run workflow
/supervisor task: BD-XX             # Work on specific task
/supervisor --dry-run               # Preview workflow without executing
/supervisor --continue              # Resume from last checkpoint
/supervisor --continue task: BD-XX  # Resume specific task from checkpoint
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `task:` | No | Specific Beads task ID to work on (e.g., `task: BD-15`) |
| `--dry-run` | No | Preview the workflow stages without executing any actions |
| `--continue` | No | Resume workflow from last checkpoint (after pause or context limit) |

## What This Does

The Supervisor executes a 9-stage workflow:

```
┌─────────────────────────────────────────────────────────────────┐
│                     SUPERVISOR WORKFLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. TASK SELECTION                                              │
│     └─> bd ready → Select highest priority unblocked task       │
│                                                                 │
│  2. BRANCH SETUP                                                │
│     └─> git checkout -b feature/BD-XX-description               │
│                                                                 │
│  3. REQUIREMENTS CHECK                                          │
│     └─> /product-owner (if story with unclear requirements)     │
│                                                                 │
│  4. TASK PLANNING                                               │
│     └─> /orchestrator goal: "BD-XX"                             │
│                                                                 │
│  5. IMPLEMENTATION LOOP                                         │
│     └─> For each subtask: implement → /code-reviewer → repeat   │
│                                                                 │
│  6. COMMIT CREATION                                             │
│     └─> /repo-steward → conventional commits                    │
│                                                                 │
│  7. PULL REQUEST                                                │
│     └─> gh pr create → link to Beads                            │
│                                                                 │
│  8. TASK COMPLETION                                             │
│     └─> bd close BD-XX → git checkout main                      │
│                                                                 │
│  9. NEXT TASK                                                   │
│     └─> Loop to step 1 or exit if no more tasks                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Beads initialized:** Run `bd init` in your project
2. **Ready tasks exist:** Create tasks with `bd create` or via Orchestrator
3. **Clean git state:** No uncommitted changes
4. **GitHub CLI:** `gh` installed and authenticated (for PR creation)

## Example Session

```bash
$ /supervisor

## SUPERVISOR: Starting Autonomous Workflow

## PROJECT CONTEXT
**Path:** /Users/name/my-project
**CLAUDE.md Status:** ✓ Found
**Git Status:** clean
**Current Branch:** main

**Ready Tasks:**
- BD-15 high - User authentication with JWT
- BD-18 medium - Add rate limiting

---

### Stage 1: Task Selection
- Ready tasks: 2
- Selected: BD-15 (high)
- Title: User authentication with JWT

### Stage 2: Branch Setup
- Branch: feature/BD-15-user-auth
- Status: Ready for work

### Stage 4: Task Planning
- Subtasks: 3 (BD-15a, BD-15b, BD-15c)
- First: BD-15a - Implement JwtGuard

### Stage 5: Implementation - BD-15a
- Files: src/auth/jwt.guard.ts
- Review: PASS ✓

### Stage 5: Implementation - BD-15b
- Files: src/auth/refresh.controller.ts
- Review: PASS ✓

### Stage 5: Implementation - BD-15c
- Files: src/auth/auth.module.ts
- Review: PASS ✓

### Stage 6: Commits
- Commits: 3
- Message: "feat(auth): implement JWT guard"

### Stage 7: Pull Request
- PR: #42
- URL: https://github.com/org/repo/pull/42

### Stage 8: Task Completion
- Task: BD-15 [CLOSED]

### Stage 9: Next Task
- Continuing with BD-18...
```

## Review Gates

The Supervisor handles review decisions:

| Decision | Action |
|----------|--------|
| **PASS** | Continue to next subtask or stage |
| **FAIL** | Fix issues, re-review (max 3 attempts) |
| **NEEDS_HUMAN** | Pause workflow, save checkpoint, exit with instructions |

After 3 failed review attempts, the Supervisor escalates to human.

## Checkpoints and Resume

The Supervisor saves checkpoints to Beads after each stage:

```bash
# If workflow pauses (NEEDS_HUMAN or context limit):
bd show BD-15  # View checkpoint in comments

# Resume from checkpoint:
/supervisor --continue task: BD-15
```

**Checkpoint data includes:**
- Current stage (e.g., 5/9)
- Subtask progress (e.g., 2/3 complete)
- Branch name
- Modified files
- Last review decision

## Context Management

The Supervisor uses a hybrid approach:
- **Subagents run in isolation** with their own context
- **Only summaries return** to supervisor (< 200 tokens each)
- **Checkpoints saved** to Beads for cross-session resume

**Context thresholds:**
- < 70%: Normal operation
- 70-85%: Warning, force checkpoint
- > 85%: Critical, checkpoint and exit with resume command

## Permissions

The Supervisor requests approval at strategic points:

| Stage | Approval |
|-------|----------|
| Task Selection | Auto |
| Branch Setup | **[APPROVAL NEEDED]** |
| Requirements | Auto (subagent) |
| Task Planning | Auto (subagent) |
| Implementation | **[APPROVAL NEEDED - batch]** |
| Commits | **[APPROVAL NEEDED]** |
| Pull Request | **[APPROVAL NEEDED]** |
| Task Completion | Auto |

## Error Handling

| Error | Supervisor Action |
|-------|-------------------|
| Code review FAIL (3x) | Escalate to human |
| NEEDS_HUMAN | Pause, checkpoint, exit |
| Git conflict | Pause, show conflict |
| No ready tasks | Exit gracefully |
| Context > 85% | Checkpoint, exit |

## Dry Run Mode

Preview without executing:

```bash
$ /supervisor --dry-run

## SUPERVISOR: Dry Run Mode

**Would execute:**
1. Task Selection: BD-15 (high priority)
2. Branch: feature/BD-15-user-auth
3. Planning: /orchestrator goal: "BD-15"
4. Implementation: [subtasks would be created]
5. Review: /code-reviewer on changes
6. Commits: /repo-steward
7. PR: gh pr create

**No changes made.** Run `/supervisor` to execute.
```

## Workflow Comparison

| Feature | Manual Workflow | With Supervisor |
|---------|-----------------|-----------------|
| Task pickup | `bd claim BD-XX` | Automatic |
| Branch creation | Manual git commands | Automatic |
| Agent coordination | Run each manually | Orchestrated |
| Review gates | Manual review | Automated with gates |
| Commits | Run `/repo-steward` | Automatic |
| PR creation | Manual `gh pr create` | Automatic |
| Next task | Manual selection | Automatic loop |

## Tips

1. **Start with dry-run:** Use `--dry-run` to preview before executing
2. **Check ready tasks:** Run `bd ready` to see available work
3. **Resume after pause:** Use `--continue` to resume from checkpoint
4. **Monitor progress:** Supervisor outputs stage-by-stage status
5. **Review PRs:** Supervisor creates PRs but doesn't merge them

## Related Commands

| Command | Purpose |
|---------|---------|
| `/orchestrator` | Plan tasks without executing |
| `/code-reviewer` | Review specific files |
| `/repo-steward` | Create commits manually |
| `/product-owner` | Refine requirements |
| `/red-team-reviewer` | Adversarial audit |

## Troubleshooting

**"No ready tasks found"**
- Check Beads: `bd list`
- Create tasks: `bd create` or `/orchestrator`
- Unblock tasks: Resolve dependencies

**"Dirty working tree"**
- Commit or stash changes: `git stash`
- Or let Supervisor handle: It will prompt for approval

**"Context limit reached"**
- Supervisor saves checkpoint automatically
- Resume with: `/supervisor --continue task: BD-XX`

**"NEEDS_HUMAN escalation"**
- Read the escalation message for context
- Fix the issue manually
- Resume with: `/supervisor --continue`

## See Also

- `agents/supervisor.md` - Full agent prompt
- `skills/workflow-management/SKILL.md` - Workflow patterns
- `skills/context-summarization/SKILL.md` - Output compression

