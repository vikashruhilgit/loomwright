# AI Agent Manager

A lightweight system for AI agents to collaborate on software projects. Four intelligent agents (Orchestrator, Code Reviewer, Repo Steward, Summarizer) automate planning, review, commits, and progress tracking.

**Key Idea:** Agents live here. Your projects have simple memory files (CLAUDE.md, TODO.md, memory/). Agents read context, do work, update files. Repeatable across any project.

> **Install the plugin and run slash commands instead of manually managing agents.**

---

## Quick Start

### 1. Install the Plugin

```bash
# Add marketplace
/plugin marketplace add ./

# Install plugin
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Or manually: `cp -r ai-agent-manager-plugin ~/.claude/plugins/`

### 2. Setup Your Project

```bash
cd /path/to/your-project
cp -r /path/to/ai-agent-manager/templates/project-template/* .
```

This creates:
```
your-project/
├── CLAUDE.md              # Codebase knowledge
├── TODO.md                # Tasks and progress
├── memory/
│   ├── context.md         # Current task state
│   ├── HISTORY.md         # Task index
│   └── session/           # Task records
└── src/ (your code)
```

### 3. Run Your First Command

```bash
/orchestrator goal: "what you want to accomplish"
```

Orchestrator will:
1. Read your CLAUDE.md
2. Understand your goal
3. Break it into tasks
4. Suggest task breakdown and acceptance criteria

---

## The 4 Agents

| Agent | Command | Purpose | When |
|-------|---------|---------|------|
| **Orchestrator** | `/orchestrator goal: "..."` | Plan work → break into tasks | Starting new work |
| **Code Reviewer** | `/code-reviewer src/` | Review code → flag issues → suggest fixes | After writing code |
| **Repo Steward** | `/repo-steward` | Stage changes → create commits → link to tasks | Ready to commit |
| **Summarizer** | `/summarizer` | Update memory → create session logs → clean context | End of task |

**How they work together:**
```
Orchestrator → Plan tasks
    ↓
You code
    ↓
Code Reviewer → Check quality
    ↓
You fix issues
    ↓
Repo Steward → Create commits
    ↓
Summarizer → Update memory, mark done
    ↓
Orchestrator reads updated context → plans next task
```

---

## Memory System (Task-Bound)

**Key Insight:** Memory tied to *current task only* (not per day). When task completes, memory is archived and wiped for next task.

| File | Purpose | Updated By |
|------|---------|-----------|
| `CLAUDE.md` | Codebase patterns & conventions | You (after reviewing agent proposals) |
| `TODO.md` | All tasks with status markers | Repo Steward (progress), Summarizer (completion) |
| `memory/context.md` | **Current active task only** — status, blockers, proposals | Summarizer (updates) |
| `memory/HISTORY.md` | Index of all completed/paused tasks | Summarizer (links to session files) |
| `memory/session/*.md` | Immutable task records (completed or paused) | Summarizer (creates) |

**Status Markers:**
- `[ ]` Pending
- `[-]` In Progress
- `[~]` Paused
- `[x]` Done

**Example Daily Flow:**

Morning: Orchestrator reads TODO.md (current task) + context.md (progress) → understands where you are

Work: You code → Code Reviewer checks → you fix → Repo Steward commits

Evening: Summarizer marks task done → creates session log → wipes context.md → ready for next task

Next day: Orchestrator reads updated TODO.md + clean context.md → plans next task

---

## Project Setup

### For New Projects

1. Copy template to your project: `cp -r templates/project-template/* .`
2. Edit CLAUDE.md with your project structure and patterns
3. Add initial tasks to TODO.md
4. Run `/orchestrator goal: "first task"`

### CLAUDE.md Structure

Fill in once at the start:

```markdown
# [Your Project Name]

## Structure
- src/ — [what's here]
- test/ — [what's here]

## Tech Stack
- Node.js, Express, PostgreSQL
- Jest for testing

## Key Patterns
(Document as you discover them)

## Quick Commands
- Build: npm run build
- Test: npm test
- Lint: npm run lint
```

### TODO.md Format

```markdown
# TODO

## Current Task
- [-] Task name (branch: feature-x)
  - [x] Subtask done
  - [ ] Subtask pending

## Pending
- [ ] Next task
```

---

## Common Patterns & Best Practices

### Agents Follow These Rules
- **Quality First:** Thorough, well-tested solutions
- **Surgical Changes:** Only modify what's necessary
- **Pattern Consistency:** Use existing patterns
- **Type Safety:** Strict type checking
- **Security:** No secrets, validate inputs
- **Performance:** Profile and document tradeoffs

See `AGENT_GUIDELINES.md` for detailed standards per language.

### Workflow Tips

1. **Start with Orchestrator:** Always run `/orchestrator goal: "..."` when starting new work
2. **Review code iteratively:** Run `/code-reviewer` multiple times as you fix issues
3. **Commit cohesively:** Use `/repo-steward` only when code is clean and reviewed
4. **Update memory at EOD:** Run `/summarizer` to archive task and prepare for next
5. **Trust the memory:** Orchestrator reads context to understand progress — keep it accurate

### CLAUDE.md Proposal Workflow

When Code Reviewer discovers a new pattern:

1. **Flag in context.md:** Pattern flagged with severity (GOOD_TO_USE, MUST_USE, etc)
2. **You review:** Check if worth documenting
3. **If approved:** You update CLAUDE.md manually
4. **Next agent learns:** Reads updated CLAUDE.md, uses the new pattern

This prevents knowledge loss and helps agents learn from discoveries.

---

## Documentation

- **This file (README.md):** Overview and quick start
- **CLAUDE.md (this repo):** Architecture and agent system
- **AGENT_GUIDELINES.md:** Development standards, quality checklist
- **.claude-plugin/README.md:** Detailed plugin documentation
- **ai-agent-manager-plugin/agents/*.md:** Individual agent prompts

---

## For Developers

To modify or extend agents:

1. Agents are Markdown prompts in `ai-agent-manager-plugin/agents/`
2. Commands are in `ai-agent-manager-plugin/commands/`
3. Shared preamble: `ai-agent-manager-plugin/agents/prompts.md`
4. All agents follow standard output format (see AGENT_GUIDELINES.md)

To test locally:

```bash
/plugin marketplace add ./
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Then run agents in a test project to verify changes.

---

## Troubleshooting

**Agent doesn't understand my project?**
- Update CLAUDE.md with clearer patterns and examples
- Add more detailed structure documentation

**Memory files out of sync?**
- Run `/summarizer` to sync memory with git state
- Check memory/context.md — should reflect current task only

**Agents suggesting wrong patterns?**
- Update CLAUDE.md with approved patterns
- Reject unwanted proposals in memory/context.md

**Need help?**
- Check AGENT_GUIDELINES.md for quality standards
- Check .claude-plugin/README.md for detailed command documentation
- Review agent prompts in ai-agent-manager-plugin/agents/

---

## License

MIT — See LICENSE file

---

**Happy shipping!** 🚀
