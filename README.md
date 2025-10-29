# Agent Manager

A lightweight, reusable system for AI agents to collaborate on software projects.

**Key Idea:** Global agents live here. Your projects have simple memory/context files. Agents read context, do work, update files. Repeatable across any project.

> **🚀 New:** Use agents via Claude Code plugin with slash commands!
>
> Instead of manually copying prompts, install the plugin and run:
> ```bash
> /orchestrator goal: "your goal"
> /code-reviewer src/
> /repo-steward
> /summarizer
> ```
>
> See **Quick Start** below to get started, or check [Plugin Documentation](./.claude-plugin/README.md) for detailed info.

---

## Quick Start

### 1. Install the Plugin
Install the AI Agent Manager plugin in Claude Code:
```bash
# First, add the marketplace (from the ai-agent-manager directory)
/plugin marketplace add ./

# Then install the plugin
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Or manually copy the plugin to your Claude Code config directory:
- **macOS/Linux:** `cp -r ai-agent-manager-plugin ~/.claude/plugins/ai-agent-manager-plugin`
- **Windows:** Copy `ai-agent-manager-plugin` to `%APPDATA%\Claude\plugins\`

### 2. Setup Your Project
Initialize your project with the template:
```bash
cd /path/to/your-project
cp -r /path/to/ai-agent-manager/templates/project-template/* .
```

Your project now has:
```
your-project/
├── CLAUDE.md              ← Codebase knowledge
├── TODO.md                ← Today's tasks
├── memory/
│   ├── context.md         ← Current state
│   └── session/
│       └── YYYY-MM-DD.md  ← Session logs
└── src/ (your code)
```

### 3. Run Your First Command
```bash
/orchestrator goal: "what you want to accomplish"
```

The orchestrator will:
1. Find your project's CLAUDE.md
2. Understand your goal
3. Break it into tasks
4. Suggest task assignments

**That's it!** Use the agents via slash commands. See next section for all available commands.

---

## Agents Overview

### **Orchestrator** — Plan Your Work
```bash
/orchestrator goal: "what to accomplish"
```
- **When:** Starting a new task or need a plan
- **What it does:** Breaks your goal into 3-7 minimal, actionable tasks
- **Output:** Task breakdown with assignments + acceptance criteria
- **Example:** `/orchestrator goal: "add dark mode to settings"`

### **Code Reviewer** — Check Your Code
```bash
/code-reviewer src/
```
- **When:** After writing code, need feedback
- **What it does:** Reviews code against patterns, flags issues
- **Checks:** Type safety, security, performance, patterns, test coverage
- **Output:** Strengths + issues (HIGH/MEDIUM/LOW severity) + fixes
- **Example:** `/code-reviewer src/components/`

### **Repo Steward** — Commit Your Changes
```bash
/repo-steward
```
- **When:** Ready to commit work
- **What it does:** Stages changes, writes conventional commits, updates TODO.md
- **Output:** Organized commits with clear messages
- **Example:** `/repo-steward --push` (also pushes to remote)

### **Summarizer** — Log Your Work
```bash
/summarizer
```
- **When:** End of day, update memory
- **What it does:** Reads git history, summarizes work, proposes patterns
- **Output:** Updated memory/context.md + session log (immutable record)
- **Example:** `/summarizer` (auto-detects your project)

---

## File Structure Explained

### `CLAUDE.md` — Codebase Knowledge
**Your project's knowledge base.** Agent reads this to understand patterns.

```markdown
# Project Name

## Structure
- src/auth.ts — JWT validation
- src/middleware/ — Express middleware
- tests/ — Jest tests

## Tech Stack
- Node.js 18+, Express 4.x, JWT

## Key Patterns
- Cache invalidation: call CacheManager.flush() after changes
- Middleware at src/middleware/auth.ts (update when adding endpoints)
- Tests use Jest + custom matchers in test/helpers/

## Common Pitfalls
- Forgetting to invalidate cache
- Not checking JWT expiry before decode
```

**You update this when:**
- New patterns discovered by agents (after you approve)
- Codebase structure changes

### `TODO.md` — Today's Tasks
**What needs doing today.** Agents auto-update this.

```markdown
# TODO — 2025-10-29

## In Progress
- [ ] Fix JWT validation in src/auth.ts:45-67
- [ ] Add test for expired tokens

## Pending (Blocked/Next)
- [ ] Code review (awaiting security team)
- [ ] Deploy to staging (after review)

## Done
- [x] Identified root cause
```

**Agents update this:** Mark tasks done, track progress.

### `memory/context.md` — Current State
**What's happening right now.** Agent reads/updates this.

```markdown
# Current State

## What We're Working On
Fix JWT validation bug in src/auth.ts:45-67

## Proposed CLAUDE.md Updates
### 🔍 New Cache Pattern Discovered
- File: src/cache-v2.ts (lines 23-67)
- Why: LRU cache more efficient than flush-all
- Status: ⏳ AWAITING YOUR APPROVAL

## Blockers
- Code review required

## What's Next
1. Fix code ✓
2. Code review (in progress)
3. Staging deployment
```

**Agents update this:** State changes, blockers, proposals.

### `memory/session/YYYY-MM-DD.md` — Immutable Record
**What actually happened. Created EOD by Summarizer.**

```markdown
# Session 2025-10-29

## What Was Done
### Task: Fix JWT Validation
- Files: src/auth.ts:45-67, test/auth.spec.ts:120-145
- Commit: fix(auth): validate JWT expiry before decode [abc123]

## Test Results
- ✓ npm test: 15 pass, 0 fail
- ✓ No regressions

## Findings
- JWT expiry check was missing; added Date.now() comparison
- Tests pass; security team to review

## Next Session
- Awaiting code review
- Then: staging deployment + 24h monitoring
```

**You read this:** Understand what happened, approve CLAUDE.md changes.

---

## Daily Workflow

### **Morning**
1. Agent (Orchestrator or you) reads CLAUDE.md
   - "What patterns exist in this codebase?"
2. Agent reads TODO.md
   - "What's today's objective?"
3. Agent reads memory/context.md
   - "What's blocking us?"

### **During Work**
1. Agent makes changes to code
2. Agent updates TODO.md
   ```
   - [x] Read CLAUDE.md
   - [ ] Fix code
   - [ ] Test
   ```
3. Agent updates memory/context.md if state changes
4. Agent proposes CLAUDE.md updates if new pattern discovered
   ```
   ## Proposed CLAUDE.md Updates
   - File: src/cache-v2.ts
   - Pattern: LRU cache with TTL
   - Should we document this?
   ```

### **End of Day**
1. Summarizer reads git history + memory files
2. Creates memory/session/YYYY-MM-DD.md
   - What changed, commits, test results
3. Updates memory/context.md
   - What's next, blockers
4. You review:
   - Read memory/session/
   - Check CLAUDE.md proposals
   - Approve/reject proposals
5. You commit project (code + memory + TODO)

### **Next Morning**
1. New agent reads updated CLAUDE.md
   - Has learned from yesterday's discoveries

---

## How to Use Agents (Step-by-Step)

### Step 1: Prepare Your Project
```
your-project/
├── CLAUDE.md           ← Filled with project patterns
├── TODO.md             ← Has today's tasks
├── memory/context.md   ← Current state
└── src/                ← Your code
```

### Step 2: Open Claude Code
```bash
# In your project directory
claude-code
```

### Step 3: Run an Agent Command
Choose an agent and run the command. Agents auto-detect your project:

```bash
# Plan your work
/orchestrator goal: "add user authentication"

# Review your code
/code-reviewer src/

# Commit your changes
/repo-steward

# Log your work (end of day)
/summarizer
```

Each command:
1. Auto-finds CLAUDE.md in your project
2. Reads context (TODO.md, memory/context.md, git history)
3. Runs the agent logic
4. Suggests changes and updates

### Step 4: Review Suggestions
- Agent outputs structured results
- Agent suggests file updates (in markdown)
- You review and decide whether to apply changes

### Step 5: Apply Changes
- For code reviews: Use suggestions to fix your code
- For TODO.md updates: Agent shows what changed
- For CLAUDE.md proposals: Review in memory/context.md, approve when ready
- For commits: Review with `git log --oneline`

For more details, see [Plugin Documentation](./.claude-plugin/README.md)

---

## Onboard a New Project

### Checklist
- [ ] Copy `agent-manager/templates/project-template/` to your project
- [ ] Create/customize `CLAUDE.md` with your project's structure + patterns
- [ ] Fill `TODO.md` with today's tasks
- [ ] Done! Ready to use agents

### Example CLAUDE.md for New Project
```markdown
# [Your Project] Codebase

## Structure
- [key directories]

## Tech Stack
- [languages, frameworks]

## Key Patterns
- [how you do things]

## Common Pitfalls
- [what to watch for]

## Quick Commands
- [build, test, run]
```

---

## Example Session

### Before (Morning)
```
CLAUDE.md:
  - Basic structure documented
  - Missing cache invalidation pattern

TODO.md:
  - [ ] Fix JWT validation bug
  - [ ] Add test

memory/context.md:
  - Goal: Fix JWT validation
  - Blocker: None
```

### During (Agent Works)
```
Agent (Code Reviewer):
  1. Reads CLAUDE.md
  2. Reviews src/auth.ts changes
  3. Finds new cache pattern in src/cache-v2.ts
  4. Updates memory/context.md:

     ## Proposed CLAUDE.md Updates
     - File: src/cache-v2.ts
     - Pattern: LRU cache with TTL
     - Status: ⏳ AWAITING APPROVAL
```

### After (EOD, Summarizer)
```
Creates memory/session/2025-10-29.md:
  - Fixed src/auth.ts (JWT expiry check)
  - Added test (test/auth.spec.ts)
  - Commit: fix(auth): validate JWT expiry [abc123]
  - Tests: 15 pass, 0 fail

Updates memory/context.md:
  - Blocker: Awaiting code review
  - Next: Staging deployment + monitoring

You review:
  1. Read session/2025-10-29.md ✓
  2. See proposal: LRU cache pattern
  3. Approve + update CLAUDE.md:
     ## Patterns
     - Cache invalidation:
       - Old: CacheManager.flush() (clear all)
       - NEW: src/cache-v2.ts (LRU, more granular)
  4. Commit project
```

### Next Morning
```
New agent reads CLAUDE.md:
  - Sees cache-v2.ts pattern
  - Uses it in similar code
  - Doesn't reinvent the wheel
```

---

## Shared Rules (See AGENT_GUIDELINES.md)

All agents follow:
- **Do:** Smallest correct thing that advances the goal
- **Output:** Structured Markdown (Context Read, Plan, Work, Results, Risks)
- **Don't:** Invent files, paths, or APIs; ask if unsure
- **Safety:** No destructive actions (force-push, db migrations) without explicit approval

See `AGENT_GUIDELINES.md` for complete details.

---

## Key Insights

1. **Agents are prompts, not code** — Easy to modify, adapt
2. **Memory lives in projects** — Projects are self-contained
3. **One source of truth** — CLAUDE.md grows; agents learn
4. **Human approval gates** — You control CLAUDE.md changes
5. **Repeatable across projects** — Same agents work everywhere

---

## Troubleshooting

**Agent doesn't understand project structure?**
- Update CLAUDE.md with more detail
- Provide clearer examples

**Memory files getting out of sync?**
- Summarizer runs EOD to catch up
- You update them if agent misses something

**New pattern but unsure if it's important?**
- Agent flags in memory/context.md as proposal
- You review + decide

---

## Next Steps

1. Copy template to your project
2. Fill CLAUDE.md with your codebase knowledge
3. Pick an agent (start with Orchestrator or Code Reviewer)
4. Load agent prompt + context
5. Let agent work
6. Review memory files at EOD
7. Approve CLAUDE.md changes

Happy shipping! 🚀
