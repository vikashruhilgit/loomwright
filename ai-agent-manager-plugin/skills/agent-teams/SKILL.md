---
name: agent-teams
description: Agent Teams patterns for parallel coordination using Claude Code native teams feature. Use when coordinating multiple agents on cross-layer changes, competing hypotheses, or research tasks.
allowed-tools: [Read, Bash]
---

# Agent Teams Skill

Patterns for using Claude Code Agent Teams as an alternative parallel execution strategy. Agent Teams is an experimental Claude Code feature that provides native multi-agent coordination without git worktrees.

## Quick Rules

- Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable
- Best for: research, competing hypotheses, cross-layer changes with different file sets
- NOT for: sequential tasks, same-file edits, tight dependency chains
- Size tasks for 5-6 actions per teammate (not too small, not too large)
- Avoid file conflicts — each teammate should own distinct files
- Use delegate mode for pure coordination (lead agent doesn't implement)

## When to Use Agent Teams

### Good Fit

| Scenario | Why Teams Work |
|----------|---------------|
| Research across multiple areas | Teammates explore in parallel, synthesize results |
| Competing hypotheses | Two teammates try different approaches, compare results |
| Cross-layer changes | Frontend teammate + backend teammate + test teammate |
| Large refactoring with clear boundaries | Each teammate owns a distinct set of files |
| Documentation + implementation | One writes docs while another implements |

### Bad Fit (Use Git Worktrees Instead)

| Scenario | Why Teams Don't Work |
|----------|---------------------|
| Sequential task chain | Tasks depend on previous results — no parallelism gain |
| Same-file edits | File conflicts between teammates cause failures |
| Tight dependency chains | Teammate B needs teammate A's output to start |
| Simple single-subtask work | Overhead of team setup not worth it |
| Tasks requiring git operations | Teammates share the same worktree — git conflicts |

## Setup

### Enable Agent Teams

```bash
# Set environment variable before starting Claude Code
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

### Team Composition

A team consists of a **lead** and one or more **teammates**:

```
Lead Agent (coordinator)
├── Teammate A (specialist)
├── Teammate B (specialist)
└── Teammate C (specialist)
```

**Lead responsibilities:**
- Define tasks for each teammate
- Coordinate file ownership (avoid conflicts)
- Synthesize results from teammates
- Handle failures and reassignment

**Teammate responsibilities:**
- Complete assigned task within file boundaries
- Report results back to lead
- Signal completion or failure

### Delegate Mode

For pure coordination (lead doesn't implement, only coordinates):

```
Lead Agent (delegate mode — coordination only)
├── Teammate A → implements feature X
├── Teammate B → implements feature Y
└── Teammate C → writes tests for X and Y
```

Use delegate mode when:
- Lead agent should focus on coordination, not implementation
- Tasks are well-defined with clear acceptance criteria
- You want the lead to stay focused on orchestration

## Task Sizing

### Right Size (5-6 Actions Per Teammate)

Each teammate should have enough work to justify the overhead but not so much that progress is hard to track:

```
Teammate A: "Implement user authentication endpoint"
  1. Read existing auth patterns
  2. Create auth controller
  3. Create auth service
  4. Add input validation
  5. Write unit tests
  6. Run tests
```

### Too Small (Overhead > Value)

```
Teammate A: "Add a type annotation to line 42"
→ Not worth team overhead. Do inline.
```

### Too Large (Hard to Track)

```
Teammate A: "Implement entire authentication system"
→ Break into multiple teammates or use Supervisor workflow.
```

## File Conflict Avoidance

The most critical constraint: **teammates must not edit the same files simultaneously**.

### Strategy 1: File Ownership

Assign explicit file sets to each teammate:

```
Teammate A owns: src/auth/controller.ts, src/auth/service.ts
Teammate B owns: src/auth/guard.ts, src/auth/decorator.ts
Teammate C owns: src/auth/__tests__/*.spec.ts
```

### Strategy 2: Layer Separation

Split by architectural layer:

```
Teammate A: API layer (controllers, routes)
Teammate B: Business logic (services, providers)
Teammate C: Data layer (repositories, entities)
```

### Strategy 3: Feature Separation

Split by feature area (for cross-cutting changes):

```
Teammate A: Authentication feature files
Teammate B: Authorization feature files
Teammate C: Shared utilities and types
```

### What Happens on Conflict

If two teammates edit the same file:
- One teammate's changes may be overwritten
- No merge — last write wins
- Lead must detect and reassign

**Prevention is better than recovery.** Always assign clear file boundaries.

## Hook Patterns for Agent Teams

### TeammateIdle Hook

Detect when a teammate finishes and reassign work:

```json
{
  "TeammateIdle": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "A teammate just became idle. Check if there are remaining tasks to assign or if all work is complete. Context: $ARGUMENTS. Respond with {\"ok\": true} to proceed.",
          "timeout": 30
        }
      ]
    }
  ]
}
```

### TaskCompleted Hook

Validate teammate output quality:

```json
{
  "TaskCompleted": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "A teammate task was marked complete. Verify the output meets acceptance criteria. Context: $ARGUMENTS. Respond with {\"ok\": true} if satisfactory, or {\"ok\": false, \"reason\": \"...\"} if issues found.",
          "timeout": 30
        }
      ]
    }
  ]
}
```

## Decision Matrix: Teams vs Worktrees vs Subagents

| Factor | Agent Teams | Git Worktrees (Supervisor) | Background Subagents |
|--------|------------|---------------------------|---------------------|
| **File isolation** | None (shared worktree) | Full (separate dirs) | None (shared) |
| **Git safety** | Risk of conflicts | Safe (separate branches) | Risk of conflicts |
| **Setup overhead** | Low (env var) | Medium (worktree create) | Low (Task tool) |
| **Coordination** | Native (lead/teammate) | Manual (poll loop) | Manual (TaskOutput) |
| **Best for** | Research, cross-layer | Implementation, CI-like | One-off tasks |
| **Experimental** | Yes | No (stable) | No (stable) |
| **Max parallelism** | Limited by context | Limited by disk/CPU | Limited by API |

### Recommendation

1. **Default:** Use Supervisor v3 with git worktrees (proven, safe, file-isolated)
2. **Research/exploration:** Consider Agent Teams (native coordination, no worktree overhead)
3. **One-off parallel tasks:** Use background subagents directly

## Limitations

### Current Limitations (Experimental)

- Requires environment variable flag (not enabled by default)
- No file-level isolation — conflicts are possible
- Teammates share git state — no independent branches
- Limited error recovery compared to Supervisor's checkpoint/resume
- Context sharing between teammates is limited

### Workarounds

| Limitation | Workaround |
|-----------|-----------|
| File conflicts | Strict file ownership assignment by lead |
| No git isolation | Avoid git operations in teammates; lead handles git |
| Limited error recovery | Lead tracks teammate status; manual retry on failure |
| Context limits | Keep teammate tasks focused (5-6 actions) |

## Integration with Supervisor

Agent Teams can complement (not replace) the Supervisor v3 workflow:

- **Supervisor** handles the 6-phase lifecycle (branch, merge, PR, close)
- **Agent Teams** could be used within the EXECUTE phase as an alternative to git worktrees
- This integration is not yet implemented — Supervisor v3 uses git worktrees by default
- Users can manually use Agent Teams for research phases or exploration tasks

## Quality Checklist

Before using Agent Teams:
- [ ] `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set
- [ ] Tasks are parallelizable (no tight dependencies)
- [ ] File ownership is clearly assigned (no overlap)
- [ ] Each teammate has 5-6 actions (right-sized)
- [ ] Lead agent has clear coordination plan
- [ ] Fallback plan if teammate fails (manual retry or reassign)
- [ ] Git operations are handled by lead only (not teammates)

## See Also

- `skills/async-orchestration/SKILL.md` - Git worktree parallel dispatch patterns
- `skills/workflow-management/SKILL.md` - 6-phase Supervisor workflow
- `agents/supervisor.md` - Supervisor v3 (default parallel execution)
- `agents/worker.md` - Worker agent (git worktree implementation)
