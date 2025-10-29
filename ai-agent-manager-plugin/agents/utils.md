# Utilities: Project Discovery & File Operations

## Project Discovery Algorithm

When an agent command is invoked, follow this algorithm to locate the target project:

### 1. Auto-Detect Project Path
```
1. Check current working directory (cwd) for CLAUDE.md
2. If not found, check parent directories up to root
3. Return first CLAUDE.md found (breadth-first, nearest project wins)
4. If multiple projects found at same level, prompt user to choose
```

### 2. Handle No Project Found
If CLAUDE.md cannot be located:
```
Return error to user:
"Error: No project context found.
Please run this command from within a project that has a CLAUDE.md file.

Searched: [cwd] and parent directories up to root.

To initialize a project, copy the template:
  cp -r /path/to/ai-agent-manager/templates/project-template /your/project"
```

### 3. Accept Explicit Project Path (Optional)
Agents can accept `--project /path/to/project` override:
```
User runs: /orchestrator goal: "add feature" --project /path/to/other/project

Agent:
1. Check if /path/to/other/project/CLAUDE.md exists
2. If yes, use it (override auto-detect)
3. If no, error and list nearest projects
```

---

## File Read Operations

Agents must read these files from the detected project:

### CLAUDE.md (Project Knowledge)
```
Purpose: Understand codebase patterns, existing conventions, tech stack
Read: Full file at start of agent session
Cache: Keep in memory during agent run
Fallback: If not found, warn but continue (new project)

Format to expect:
- Sections: Overview, Tech Stack, Architecture, Key Patterns, Conventions, Commands
- Use to: Inform code style, detect pattern violations, understand project structure
```

### TODO.md (Today's Tasks)
```
Purpose: Know what's in scope for today
Read: Full file at start
Cache: Keep in memory
Fallback: If not found, warn but continue (empty task list)

Format to expect:
- Checklist of tasks: [x] done task, [ ] pending task
- Use to: Inform task breakdown, avoid duplicate work, track progress
```

### memory/context.md (Current State)
```
Purpose: Know what's been done recently, blockers, next steps
Read: Full file at start
Cache: Keep in memory
Fallback: If not found, proceed (first agent run)

Format to expect:
- Last Session Summary: What was accomplished
- Current Blockers: What's stuck
- Dependencies: What needs to complete first
- Next Steps: What agent should focus on
```

### memory/session/YYYY-MM-DD.md (Session Log)
```
Purpose: Immutable record of today's work (if summarizer has already run)
Read: For reference only (don't modify)
Fallback: If not found, this is first agent run of the day

Format to expect:
- Agent outputs from this session
- Time-stamped entries
- File changes made
```

---

## File Write Operations

When agents suggest file changes, format them as structured suggestions:

### CLAUDE.md Updates
```markdown
## Suggested CLAUDE.md Update

**Section to Update:** [Architecture / Conventions / Patterns / etc]

**Proposal:**
[Clear text of what should be added/changed]

**Rationale:** Why this pattern matters

**Status:** Awaiting user approval before write
```

### TODO.md Updates
```markdown
## Suggested TODO.md Changes

**To Add:**
- [ ] New task name (context: why)
- [ ] Another task

**To Mark Complete:**
- [x] Completed task (or via Repo Steward)

**Status:** Will be updated by Repo Steward or Summarizer
```

### memory/context.md Updates
```markdown
## Suggested memory/context.md Update

**Current Blockers:** [List any]
**Last Progress:** [What was just accomplished]
**Next Steps for Other Agents:** [What they should focus on]

**Status:** Will be updated by Summarizer at EOD
```

### memory/session/YYYY-MM-DD.md Creation
```markdown
## Session Log Entry for [DATE]

**Agent:** [Which agent]
**Goal:** [What was asked]
**Work Summary:** [What happened]
**Files Changed:** [List]
**Next Agent:** [Who should work next]

**Status:** Created by Summarizer at EOD
```

---

## Safe File Operations Principles

1. **Never Delete:** Don't remove existing content
2. **Always Append:** Add to memory files (never truncate)
3. **Preserve Structure:** Keep markdown formatting intact
4. **Suggest, Don't Decide:** Agent suggests changes, user approves
5. **Date-Stamp Entries:** Use YYYY-MM-DD format for session logs
6. **Clear Handoffs:** Each agent output should tell next agent what to do

---

## Error Handling

If a file read fails:
```
ERROR: Could not read [filename]
Path attempted: [full path]
Possible causes:
- File was deleted
- Permission denied
- Project path incorrect

Next steps:
- Verify project path is correct
- Check file permissions
- Restore file from git if accidentally deleted
```

If writing to a file would be unsafe (e.g., file is locked):
```
WARNING: Cannot write to [filename] safely
Reason: [file is locked / permission denied / etc]

Suggestion: User should manually update or check file status

Changes I would make:
[Show suggested content as code block]
```

---

## Usage in Agent Prompts

At the **START** of each agent prompt, add this section:

```markdown
## Context Setup

1. **Locate Project:** Use the project discovery algorithm above
   - Auto-detect CLAUDE.md in cwd and parent directories
   - Ask user if ambiguous
   - Accept --project override if provided

2. **Load Context Files:**
   - Read CLAUDE.md (understand patterns)
   - Read TODO.md (understand today's scope)
   - Read memory/context.md (understand current state)

3. **Report Project:**
   - Tell user: "Working on project at: [path]"
   - Show brief summary of what you found

4. **Proceed with Agent's Core Work**
```

Then at the **END** of agent output, format file suggestions clearly so user can approve/copy.

---

## Example: Full Project Discovery Flow

**User runs:** `/orchestrator goal: "add dark mode"`

**Agent (orchestrator) executes:**
```
1. Search cwd for CLAUDE.md → found at /Users/name/my-project/CLAUDE.md
2. Read full CLAUDE.md → understand React + Next.js + Tailwind + Jest
3. Read TODO.md → see 3 tasks in progress, dark mode in scope
4. Read memory/context.md → see "blocked on database schema"
5. Report: "Working on my-project | React app | Dark mode is in scope"
6. Proceed: Break dark mode into tasks considering existing blockers
7. Output: Clear task breakdown with acceptance criteria
8. Suggest: Update TODO.md to reflect new subtasks
```

**User reviews** output and decides:
- Approve CLAUDE.md suggestions? (none in this case)
- Approve TODO.md suggestions? (add subtasks)
- Proceed with orchestrator plan? (yes)

---

## Integration Notes

- All 5 agents use these utilities
- Shared project discovery prevents conflicts
- Consistent file read/write patterns
- Safe defaults (suggest, don't auto-write)
- Clear handoff format for next agent
