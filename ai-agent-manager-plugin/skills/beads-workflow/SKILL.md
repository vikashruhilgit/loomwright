---
name: beads-workflow
description: Beads CLI commands for task lifecycle management. Use when creating tasks, updating status, or syncing team visibility.
allowed-tools: Bash
version: "1.0.0"
lastUpdated: "2026-03"
---

# Beads Workflow Skill

Beads issue tracker commands for task creation, status updates, and team synchronization.

## Quick Commands

- `bd create "Task title" --type [epic|task|subtask]` - Create task
- `bd dep BD-XX BD-YY` - Set dependency (XX blocks YY)
- `bd claim BD-XX` - Start working (marks in-progress)
- `bd comment BD-XX "note"` - Add note
- `bd close BD-XX` - Mark complete
- `bd sync` - Sync to remote (team visibility)

---

## Task Creation Pattern

```bash
# 1. Create parent EPIC
bd create "Feature name (EPIC)" --type epic
# Output: Created BD-47

# 2. Create child implementation tasks
bd create "Implementation" --type task --depends-on BD-47
# Output: Created BD-48

bd create "Code Review" --type subtask --depends-on BD-48
# Output: Created BD-49

# 3. Set blocking relationships
bd dep BD-49 BD-50  # BD-49 blocks BD-50

# 4. Sync to remote so team sees tasks
bd sync
```

---

## Agent Responsibilities

### Orchestrator

**Full workflow:**
1. Creates all tasks via `bd create`
2. Sets up dependencies
3. **Claims FIRST task** via `bd claim BD-XX`
4. **Starts working immediately**
5. Syncs progress: `bd sync`
6. Completes work
7. Closes task: `bd close BD-XX`
8. Syncs completion: `bd sync`

### Code Reviewer

**Two scenarios:**

**A. No Beads task exists for current work:**
1. Reviews unstaged/staged files
2. Suggests creating task to track review
3. Asks user if should continue

**B. Review task exists:**
1. Claims task: `bd claim BD-XX`
2. Syncs: `bd sync`
3. Performs review
4. Comments decision: `bd comment BD-XX "Decision: PASS - criteria met"`
5. Closes: `bd close BD-XX`
6. Syncs: `bd sync`

### All Agents

- **Before reading state:** `bd sync` then `bd list`
- **After making changes:** `bd sync`

---

## Examples

### Orchestrator Creating Tasks

```bash
# User runs: /orchestrator goal: "add JWT auth"

# Agent creates task structure:
bd create "JWT Authentication (EPIC)" --type epic
# Output: Created BD-50

bd create "Implement JwtGuard" --type task --depends-on BD-50
# Output: Created BD-51

bd create "Code Review - JwtGuard" --type subtask --depends-on BD-51
# Output: Created BD-52

bd create "Add JWT tests" --type task --depends-on BD-52
# Output: Created BD-53

# Set dependencies
bd dep BD-52 BD-53  # Review blocks tests

# Sync to remote
bd sync

# Claim first task and start working
bd claim BD-51
bd sync

# Agent outputs:
## Beads Task Structure Created
- BD-50: JWT Authentication (EPIC)
- BD-51: Implement JwtGuard (TASK) - **CLAIMED, starting work**
- BD-52: Code Review - JwtGuard (SUBTASK) - blocks BD-53
- BD-53: Add JWT tests (TASK)

Now starting work on BD-51...
```

### Code Reviewer with Existing Task

```bash
# User runs: /code-reviewer src/auth/jwt.guard.ts

# Agent checks for task
bd list | grep "Code Review"
# Output: BD-52 [open] Code Review - JwtGuard

# Claim and sync
bd claim BD-52
bd sync

# Perform review...

# Add decision comment
bd comment BD-52 "Decision: PASS - All criteria met. Type safety ✓, Tests ≥80% ✓, Pattern match ✓"

# Close and sync
bd close BD-52
bd sync

# Agent outputs:
## Code Review Decision: PASS

BD-52 marked complete. BD-53 (Add JWT tests) is now unblocked.
```

### Code Reviewer with No Task

```bash
# User runs: /code-reviewer src/components/Button.tsx

# Agent checks
bd list
# No matching task found

# Agent outputs:
⚠️ No Beads task found for this review.

**Recommendation:** Create task to track this work:
`bd create "Code review - Button component" --type subtask`

Continue with review? (Y/n)
```

---

## Common Patterns

### Claiming Next Task After Review Passes

```bash
# Review completed and passed
bd close BD-52
bd sync

# Check what unblocked
bd list | grep "open"
# Output: BD-53 [open] Add JWT tests

# Claim next task
bd claim BD-53
bd sync
```

### Syncing Before Planning

```bash
# Always sync before checking state
bd sync
bd list

# Now plan based on current state
```

### Team Visibility

```bash
# After any status change
bd sync

# Team members can now see:
# - Who's working on what (claimed tasks)
# - What's blocked (dependencies)
# - What's completed (closed tasks)
```

---

## Error Handling

### Task Not Found

```bash
bd claim BD-999
# Error: Task BD-999 does not exist

# Fix: Check available tasks
bd list
```

### Already Claimed

```bash
bd claim BD-51
# Error: BD-51 already claimed by user@example.com

# Fix: Check who has it
bd show BD-51
```

### Sync Conflicts

```bash
bd sync
# Conflict: Remote has newer version

# Fix: Pull first
bd sync --pull
```

---

## Quality Gates

Use this skill to ensure:
- [ ] All created tasks have clear titles
- [ ] Dependencies properly set (review blocks next task)
- [ ] Tasks claimed before starting work
- [ ] Status synced after every change
- [ ] Comments include decision rationale
- [ ] Closed tasks have completion notes

---

## See Also

- `skills/commit/SKILL.md` - Conventional commits with Beads linking
- `skills/quality-checklist/SKILL.md` - Review criteria for subtasks
