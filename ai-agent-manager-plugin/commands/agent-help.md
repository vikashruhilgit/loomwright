---
description: List all available agent commands and usage examples
---

# Command: /agent-help

## Usage

```
/agent-help
```

## What This Does

Shows all available agent commands and quick usage examples.

---

# Agent Help Reference

## Quick Start

The AI Agent Manager plugin provides 4 main agents that work together to manage your development workflow:

```
1. Plan (Orchestrator)  →  2. Review (Code Reviewer)  →  3. Commit (Repo Steward)  →  4. Summary (Summarizer)
```

---

## Command Reference

### 1️⃣ /orchestrator — Plan Your Work

**Purpose:** Break a goal into minimal, actionable tasks

**Usage:**
```
/orchestrator goal: "add dark mode to UI"
/orchestrator goal: "fix login bug" --project /path/to/project
```

**What it does:**
- Understands your goal
- Reads project context (CLAUDE.md, TODO.md, memory files)
- Breaks goal into 3-7 specific tasks
- Assigns tasks to agents or you
- Identifies dependencies and blockers
- Provides clear acceptance criteria

**Example Output:**
- Task 1: [Code Reviewer] Review existing theme patterns
- Task 2: [You] Implement dark mode toggle
- Task 3: [Code Reviewer] Review your implementation
- Task 4: [Repo Steward] Commit changes
- Task 5: [Summarizer] Update memory files

**When to Use:**
- Start of new work
- When goal is unclear or large
- When you need task breakdown
- When planning feature work

**Learn More:** `/orchestrator --help`

---

### 2️⃣ /code-reviewer — Review Code Changes

**Purpose:** Review code against patterns, flag issues, detect new patterns

**Usage:**
```
/code-reviewer                              # Review git changes
/code-reviewer src/components/Dark.tsx      # Review specific file
/code-reviewer src/components/              # Review folder
/code-reviewer --project /path/to/project   # Auto-detect files
```

**What it does:**
- Reads project patterns (CLAUDE.md)
- Reviews your code for:
  - Type safety issues
  - Security problems
  - Performance issues
  - Pattern violations
  - Test coverage
- Flags issues with severity (HIGH, MEDIUM, LOW)
- Detects new patterns worth documenting
- Provides specific fixes

**Example Feedback:**
- ✅ Good: 87% test coverage (above 80% threshold)
- ⚠️ HIGH: Missing type annotation on theme parameter
- 📋 PATTERN: New dark mode pattern detected, ready for CLAUDE.md

**When to Use:**
- After writing code
- Before committing
- To learn project patterns
- To catch bugs early

**Learn More:** `/code-reviewer --help`

---

### 3️⃣ /repo-steward — Create Commits

**Purpose:** Stage changes and create conventional commit messages

**Usage:**
```
/repo-steward                    # Stage and commit (no push)
/repo-steward --project /path    # Explicit project path
/repo-steward --push             # Stage, commit, and push to remote
```

**What it does:**
- Groups changes into logical commits
- Writes conventional commit messages (feat, fix, test, etc)
- Updates TODO.md to mark tasks complete
- Verifies repo cleanliness (no debug code, secrets, etc)
- Optionally pushes to remote

**Example Commits:**
```
feat(theme): add dark mode toggle to Settings
test(theme): add dark mode tests (89% coverage)
security(hooks): validate localStorage input
```

**When to Use:**
- When you're done coding (after code review)
- At the end of each task
- When you want to organize commits
- Before pushing to remote

**Learn More:** `/repo-steward --help`

---

### 4️⃣ /summarizer — Summarize Work

**Purpose:** Update memory files, create session logs, propose patterns

**Usage:**
```
/summarizer                      # Summarize today's work
/summarizer --project /path      # Explicit project path
```

**What it does:**
- Reads git history since last session
- Summarizes what was accomplished
- Updates memory/context.md with current state
- Creates immutable session log (memory/session/YYYY-MM-DD.md)
- Detects new patterns worth documenting
- Proposes CLAUDE.md updates (user approves)

**Example Output:**
- Work Completed: Added dark mode, fixed security bug, 89% coverage
- Files Changed: 4 files, 300 insertions, 14 deletions
- Session Log: Created memory/session/2025-01-15.md
- Pattern Proposal: "Dark Mode via Context + localStorage"

**When to Use:**
- End of workday
- Before handing off to teammate
- Before long break
- Weekly review

**Learn More:** `/summarizer --help`

---

## Daily Workflow Example

### Morning: Plan Your Work
```bash
cd /path/to/my-app
/orchestrator goal: "Add dark mode UI to settings page"
```
→ Agent breaks it into tasks with acceptance criteria

### During Work: Code & Review
```bash
# 1. Implement feature...

# 2. Review your code
/code-reviewer src/components/Settings.tsx
```
→ Agent flags issues and detects patterns

### Before Committing: Stage Changes
```bash
git add src/components/Settings.tsx src/hooks/useDarkMode.ts
/repo-steward
```
→ Agent groups and commits with clear messages

### End of Day: Summarize
```bash
/summarizer
```
→ Agent updates memory, logs session, proposes pattern

---

## Common Scenarios

### Scenario 1: Fix a Bug
```
/orchestrator goal: "Fix login button not working on mobile"
→ Follow suggested tasks
→ Use /code-reviewer to verify fix
→ Use /repo-steward to commit
→ Use /summarizer to log work
```

### Scenario 2: Add a Feature
```
/orchestrator goal: "Add dark mode to application"
→ Orchestrator breaks into 5-6 tasks
→ Task 1: Code Reviewer checks existing theme patterns
→ Task 2: You implement dark mode
→ Task 3: Code Reviewer checks your code
→ Task 4: Repo Steward commits changes
→ Task 5: Summarizer logs the work and proposes pattern
```

### Scenario 3: Refactor Code
```
/orchestrator goal: "Refactor Settings component to use hooks"
→ Follow breakdown
→ Code Reviewer checks pattern consistency
→ Repo Steward creates refactor commit
→ Summarizer logs and updates patterns
```

### Scenario 4: Review Someone Else's Code
```
cd /path/to/pull-request-repo
/code-reviewer src/  # Review the changes
```
→ Agent flags issues and improvements

---

## Key Concepts

### Project Context
Each agent automatically finds your project by looking for `CLAUDE.md`:
- Starts in current directory
- Searches parent directories
- Uses `/path/to/project` if you provide it

### Memory Files
Agents read and update these files in your project:
- **CLAUDE.md** — Codebase knowledge, patterns, conventions
- **TODO.md** — Today's tasks (updated by Repo Steward)
- **memory/context.md** — Current state, blockers (updated by Summarizer)
- **memory/session/YYYY-MM-DD.md** — Immutable daily logs (created by Summarizer)

### Approval Workflow
- ✅ File Changes: Agent suggests, you approve
- ✅ CLAUDE.md Updates: Agent proposes, you approve
- ✅ Commits: Agent creates, you review with `git log`
- ✅ Pushes: Only with `--push` flag

---

## Tips & Tricks

### Tip 1: Use Agents in Any Order
You don't have to follow the sequential order. For example:
- Run `/code-reviewer` first to understand patterns before coding
- Skip `/summarizer` if you prefer manual memory updates
- Run `/repo-steward` multiple times during the day

### Tip 2: Combine with Git
```bash
# Review changes before code-reviewer
git diff src/

# See commits after repo-steward
git log --oneline -5

# Push after repo-steward
git push
```

### Tip 3: Multi-Project Workflows
```bash
# Work on project A
cd /path/to/project-a
/orchestrator goal: "Fix bug in A"

# Switch to project B
cd /path/to/project-b
/orchestrator goal: "Add feature to B"  # Auto-detects B's context
```

### Tip 4: Review Before Committing
```bash
# Code first
/code-reviewer src/

# Fix issues
/code-reviewer src/  # Re-review

# When satisfied, commit
/repo-steward
```

### Tip 5: Daily Routine
```bash
# Morning: Plan
/orchestrator goal: "Today's goal"

# During: Code and review
/code-reviewer (as needed)

# End of day: Commit and summarize
/repo-steward
/summarizer
```

---

## Files & Directories

### Plugin Files
```
.claude-plugin/
├── plugin.json              # Plugin metadata
├── commands/                # Slash commands
│   ├── orchestrator.md
│   ├── code-reviewer.md
│   ├── summarizer.md
│   ├── repo-steward.md
│   └── agent-help.md
└── agents/                  # Agent implementations
    ├── orchestrator.md
    ├── code-reviewer.md
    ├── summarizer.md
    ├── repo-steward.md
    └── utils.md
```

### Project Files (Created/Updated by Agents)
```
your-project/
├── CLAUDE.md                # Codebase knowledge
├── TODO.md                  # Today's tasks
└── memory/
    ├── context.md           # Current state
    └── session/
        ├── 2025-01-14.md    # Session logs
        ├── 2025-01-15.md
        └── ...
```

---

## Getting Help

### Need Help with a Specific Agent?
```
/orchestrator --help    # Help for Orchestrator
/code-reviewer --help   # Help for Code Reviewer
/summarizer --help      # Help for Summarizer
/repo-steward --help    # Help for Repo Steward
```

### Questions About the Plugin?
Check the plugin README:
```
cat /path/to/ai-agent-manager/.claude-plugin/README.md
```

### Issues or Suggestions?
Contribute to the AI Agent Manager project:
```
https://github.com/your-org/ai-agent-manager
```

---

## Keyboard Shortcuts

These are Claude Code slash commands, so you can type them directly:
- Type `/orchestr` + Tab → Auto-completes to `/orchestrator`
- Type `/code-r` + Tab → Auto-completes to `/code-reviewer`
- Type `/summar` + Tab → Auto-completes to `/summarizer`
- Type `/repo-s` + Tab → Auto-completes to `/repo-steward`

---

## Summary

| Agent | Purpose | When | Input | Output |
|-------|---------|------|-------|--------|
| **Orchestrator** | Plan work | Start of task | Goal | Task breakdown |
| **Code Reviewer** | Review code | During development | Files/diff | Issues & suggestions |
| **Repo Steward** | Create commits | When done coding | Staged changes | Commits + TODO update |
| **Summarizer** | Log work | End of day | Git history | Session log + memory update |

---

**Ready to get started?** Run `/orchestrator goal: "your goal here"` to begin!
