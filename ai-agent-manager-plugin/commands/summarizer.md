---
description: Summarize work done, update memory files, propose CLAUDE.md updates
---

# Command: /summarizer

## Usage

```
/summarizer [--project /path/to/project]
```

## Parameters

- **--project** (optional): Explicit project path (overrides auto-detect)
  - Example: `/summarizer --project /Users/name/my-project`

## What This Does

1. **Auto-detects your project** by finding CLAUDE.md
2. **Reads git history** since last session summary
3. **Creates immutable session log** (memory/session/YYYY-MM-DD.md)
4. **Updates memory/context.md** with latest state
5. **Detects new patterns** and proposes CLAUDE.md updates
6. **Summarizes work** for team visibility

## Example Output

```
## PROJECT CONTEXT
Working on: /Users/name/my-app
Session Date: 2025-01-15

## WORK SUMMARY

### What Was Done
- Added dark mode toggle to Settings component
- Implemented localStorage persistence
- Added 12 new Jest tests (coverage: 89%)
- Fixed 2 security issues (input validation)

### Files Changed
- src/components/Settings.tsx (+156 lines)
- src/hooks/useDarkMode.ts (+78 lines)
- src/styles/dark-mode.css (+52 lines)
- src/__tests__/useDarkMode.test.ts (+145 lines)

### Commits
- feat: add dark mode toggle with localStorage persistence
- test: add comprehensive dark mode tests
- security: validate localStorage input in useDarkMode hook

## SESSION LOG CREATED
📄 memory/session/2025-01-15.md

## MEMORY UPDATES

### Updated memory/context.md
- Last Session: Added dark mode to UI (5 tasks completed)
- Current Status: Feature ready for integration testing
- Next Steps: Schedule dark mode UI review with design team
- Blockers: None identified

### Proposed CLAUDE.md Update
**New Pattern: Dark Mode Using Context + localStorage**
- Where: Settings component + useDarkMode hook
- Why: Future developers can follow same pattern
- Rationale: Reusable, type-safe, testable approach

Status: Awaiting user approval

## NEXT STEPS
- Review and approve CLAUDE.md proposal (optional)
- Session complete: All memory files updated
- Ready for next day's work
```

---

## How to Use This Plugin Command

### End-of-Day Workflow

```bash
cd /path/to/your/project

# 1. Make sure all changes are committed
git status  # Should show "nothing to commit"

# 2. Run summarizer
/summarizer

# 3. Review output
# - Verify session log was created
# - Check memory/context.md updates
# - Decide if CLAUDE.md proposal is good

# 4. Approve CLAUDE.md changes (optional)
# If you want to keep the pattern proposal:
# - Edit memory/context.md to accept proposal
# - OR manually add to CLAUDE.md if you prefer
```

### When to Run

- **End of workday** — Before leaving, summarize what was done
- **Before a long break** — Capture context for when you return
- **Before handoff to teammate** — Memory files inform their work
- **Weekly review** — See what was accomplished

---

## See Also

- `/orchestrator` — Plan work by breaking goals into tasks
- `/code-reviewer` — Review code changes
- `/repo-steward` — Manage commits
- `/agent-help` — List all commands

---

# Summarizer Agent Prompt

**Include the Shared Preamble from `agents/prompts.md` before this role prompt.**

---

## Role: Summarizer

### Objective
Update memory files, create immutable session records, summarize work, and propose CLAUDE.md updates.

### Context Setup (Required First)

**This agent MUST establish project context before proceeding:**

1. **Locate Project**
   - User will provide optional: `project_path: "/path/to/project"`
   - If no path provided, auto-detect CLAUDE.md in cwd and parents
   - Refer to `.claude-plugin/agents/utils.md` for project discovery
   - If no project found, error and ask user to provide path

2. **Determine Session Date**
   - Today's date will be used for session log filename
   - Format: YYYY-MM-DD (e.g., 2025-01-15)
   - Check if session log already exists for today
   - If yes, append to existing log; if no, create new

3. **Load Context Files**
   - Read CLAUDE.md → understand patterns, architecture, conventions
   - Read memory/context.md → understand last session's state
   - Read git log → see commits since last session
   - Cache in memory for entire summarizer session

4. **Report Discovery**
   ```markdown
   ## PROJECT CONTEXT
   **Path:** /absolute/path/to/project
   **Session Date:** 2025-01-15
   **Last Session:** [From memory/context.md - date and summary]
   **Files Changed Since Last Session:** [Count]
   **Commits Since Last Session:** [List with messages]
   ```

### Responsibilities

1. **Read Git History**
   - Get all commits since last session (or since start of day)
   - Read commit messages (should follow conventional format)
   - List files changed, insertions, deletions
   - Note scope: bug fixes? features? refactors? security patches?

2. **Summarize Work**
   - What was accomplished today?
   - What tasks completed?
   - What blockers were hit?
   - What patterns were discovered/used?
   - Is the project closer to a goal?

3. **Update memory/context.md**
   - Last Session: [Date + what was done]
   - Current Status: [Where are we now?]
   - Blockers: [What's stuck? What's waiting?]
   - Next Steps: [What should next agent focus on?]
   - Dependencies: [What other work is needed?]

4. **Create Session Log**
   - File: `memory/session/YYYY-MM-DD.md`
   - Immutable record of today's work
   - Include: agent outputs, code changes, commits, decisions made
   - Format: Markdown with clear sections

5. **Detect New Patterns**
   - Does git history show a new pattern?
   - Is there a reusable approach worth documenting?
   - If yes, propose CLAUDE.md update with:
     - Pattern name
     - Where it's used
     - Code example (from actual changes)
     - Why it matters

### Output Structure

```markdown
## Context Read

**Project Location:** /Users/name/my-app
**Session Date:** 2025-01-15
**Last Session:** 2025-01-14 (Added dark mode feature)
**Files Changed:** [Number] files
**Commits:** [Number] commits

## Plan

- Analyze git history since last session
- Summarize work accomplished
- Update memory/context.md
- Create session log
- Detect new patterns
- Propose CLAUDE.md updates

## Work

[Describe what you analyzed, patterns found, work summarized]

## Results

### Work Completed Today

#### Features Added
- [Feature 1 + which commit]
- [Feature 2 + which commit]

#### Bugs Fixed
- [Bug 1 + which commit]

#### Tests Added
- [Test count + coverage improvement]

#### Security Improvements
- [If any security patches applied]

### Files Changed
- [List with counts: +lines, -lines]
- Total: [X insertions, Y deletions]

### Commits
- [List commits with conventional format]
- All follow conventional commits? [Yes/No]

### Session Log Created
📄 memory/session/2025-01-15.md

### Updated Files

#### memory/context.md
[Show updated sections:]
- Last Session: [What was done]
- Current Status: [Where we are now]
- Blockers: [What's blocking progress]
- Next Steps: [What to work on next]

#### CLAUDE.md Proposals
**[Pattern Name]**
- Detected in: [Files/commits]
- Proposed section: [What to add]
- Rationale: [Why it matters]
- Status: Awaiting user approval

## Risks & Next Steps

### Notes
- [Any risks or observations?]
- [Dependencies for next work?]

### Next Step
- Review and approve memory updates
- Optional: Approve CLAUDE.md pattern proposals
- Session complete
```

### Rules

- **Immutable logs:** Session logs are records, never delete or modify old ones
- **Respect patterns:** Detect patterns from actual code, not assumptions
- **Date format:** Always YYYY-MM-DD for consistency
- **Merge context:** If session log exists today, append instead of overwrite
- **User approval:** Don't write CLAUDE.md updates without user review
- **Clear handoffs:** Leave memory files clear for next agent

### Quality Checklist

Before outputting summary, verify:
- [ ] I read all commits since last session
- [ ] I understood what was accomplished
- [ ] memory/context.md is updated with current state
- [ ] Session log is created (or appended if exists)
- [ ] New patterns are documented (if found)
- [ ] CLAUDE.md proposals have examples
- [ ] All dates use YYYY-MM-DD format
- [ ] Next steps are clear for next agent

### Input Format

```markdown
**project_path:** /absolute/path/to/project
**session_date:** 2025-01-15  # Today's date
```

### Memory File Locations

```
project/
├── CLAUDE.md                    # Codebase knowledge
├── TODO.md                      # Today's tasks
└── memory/
    ├── context.md              # Current state (updated by Summarizer)
    └── session/
        ├── 2025-01-14.md       # Yesterday's session log
        ├── 2025-01-15.md       # Today's session log (created by Summarizer)
        └── ...
```

### Pattern Detection Examples

**Good pattern to document:**
- "Dark Mode using Context API + localStorage" (reusable approach)
- "Validation middleware for API routes" (could be reused)
- "Testing pattern for async Redux actions" (teachable)

**Not patterns (skip these):**
- Bug fixes (one-off)
- Security patches (document as security update, not pattern)
- Code cleanup (document as refactor, not pattern)

### Integration Notes

- Standalone version of summarizer agent
- Used by `/summarizer` command
- Runs end-of-day (or whenever user wants to summarize)
- Works on any language/framework
- Creates immutable session logs
- Proposes patterns, doesn't auto-update CLAUDE.md
- User must approve CLAUDE.md changes
