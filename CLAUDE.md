# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**AI Agent Manager** is a reusable system that provides intelligent agents for software development workflows. It integrates with Claude Code as a plugin with 5 specialized agents that automate planning, code review, commit management, progress tracking, and adversarial security audits.

The system enables agents to collaborate on any project type by maintaining a memory system (CLAUDE.md, TODO.md, memory/) that persists knowledge and context between work sessions.

---

## Architecture & Key Concepts

### Plugin System

The project is structured as a **Claude Code plugin marketplace**:

1. **Plugin Package** (`ai-agent-manager-plugin/`)
   - Agent definitions: `agents/` (Markdown prompts only, pure text)
   - Slash commands: `commands/` (entry points)
   - Shared preamble: `agents/prompts.md` (included in all agents)
   - **ONLY source of truth** (duplicate `/agents/` directory deleted)

2. **Marketplace** (`.claude-plugin/`)
   - Plugin metadata and distribution
   - Installation via `/plugin install` command
   - Supports local and remote marketplaces

### Task-Bound Memory Model

**Key Innovation:** Memory is tied to current active task, not per-day or per-project.

- **context.md:** Always reflects current task only (marked `[-]` in TODO.md)
- **session files:** Immutable task records (completed/paused)
- **HISTORY.md:** Index of all tasks (links to session files)
- **Workflow:** When task completes → Summarizer archives context → wipes clean → Orchestrator plans next task

This prevents memory bloat and keeps agents focused on current work.

### The 5 Agents

Each agent is a Markdown prompt file (`agents/[name].md`) that:

#### **Orchestrator** (`/orchestrator`)
- **Purpose:** Break goals into actionable tasks with clear acceptance criteria
- **When to use:** Starting new work or need a plan
- **Command:** `/orchestrator goal: "what you want to accomplish"`
- **Workflow:** Reads CLAUDE.md (patterns) → understands goal → outputs task breakdown
- **Outputs:** 3-7 minimal tasks, assignments, acceptance criteria, dependencies

#### **Code Reviewer** (`/code-reviewer`)
- **Purpose:** Provide precise feedback on code quality, security, and pattern consistency
- **When to use:** After writing code, need review
- **Command:** `/code-reviewer src/` (specify files/dirs to review)
- **Checks:** Type safety, security, performance, pattern alignment, test coverage
- **Outputs:** Strengths + blocking issues (HIGH/MEDIUM/LOW) + fixes + CLAUDE.md proposals

#### **Repo Steward** (`/repo-steward`)
- **Purpose:** Keep repository clean with organized, conventional commits
- **When to use:** Ready to commit work
- **Command:** `/repo-steward` or `/repo-steward --push` (also push to remote)
- **Workflow:** Stages changes → writes conventional messages → updates TODO.md
- **Outputs:** Commit messages, updated TODO.md, next actions

#### **Summarizer** (`/summarizer`)
- **Purpose:** Update memory files with work done, create immutable session records
- **When to use:** End of day, update project memory
- **Command:** `/summarizer` (auto-detects project)
- **Workflow:** Reads git history → updates context.md → creates session log → flags new patterns
- **Outputs:** Updated memory/, session log, CLAUDE.md proposals

#### **Red Team Reviewer** (`/red-team-reviewer`)
- **Purpose:** Adversarial audit — find what breaks in production
- **When to use:** Pre-launch, security reviews, architecture decisions
- **Command:** `/red-team-reviewer [target] [--focus security|scale|cost|ops]`
- **Workflow:** Attacks assumptions → verifies claims against docs → explores 6 attack vectors
- **Outputs:** Findings by severity (FATAL/CRITICAL/WARNING/WEAKNESS), prioritized fixes

### Memory System

Each project using agents maintains 4 files in its root directory:

| File | Purpose | Updated By |
|------|---------|-----------|
| **CLAUDE.md** | Codebase knowledge (patterns, tech stack, structure) | You (after reviewing agent proposals) |
| **TODO.md** | Today's tasks and progress | Repo Steward agent |
| **memory/context.md** | Current state, blockers, what's next, CLAUDE.md proposals | Summarizer agent |
| **memory/session/YYYY-MM-DD.md** | Immutable daily record (what was done, commits, findings) | Summarizer agent |

**Key insight:** Memory lives in projects, not in a central system. Projects are self-contained and repeatable.

### Agent Design Principles

All agents follow a **shared contract** (see AGENT_GUIDELINES.md):

- **Mission:** Do the smallest correct thing that advances the objective
- **Input:** Context from memory files + CLAUDE.md + recent git history
- **Output:** Structured Markdown with Context Read → Plan → Work → Results → Risks & Next Steps
- **Safety:** No destructive actions (db migrations, force-push) without explicit approval
- **Rules:** Never invent files/APIs/paths; ask if unsure; respect memory files

---

## Quick Start Commands

### Installation

```bash
# Add the marketplace (from ai-agent-manager directory)
/plugin marketplace add ./

# Install the plugin
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Or manually copy to Claude Code plugins directory:
- **macOS/Linux:** `cp -r ai-agent-manager-plugin ~/.claude/plugins/ai-agent-manager-plugin`
- **Windows:** Copy `ai-agent-manager-plugin` to `%APPDATA%\Claude\plugins\`

### Setup a Project

```bash
# Initialize project with template
cd /path/to/your-project
cp -r /path/to/ai-agent-manager/templates/project-template/* .
```

This creates:
```
your-project/
├── CLAUDE.md              # Your codebase knowledge
├── TODO.md                # Today's tasks
├── memory/
│   ├── context.md         # Current state
│   └── session/           # Daily logs
└── src/                   # Your code
```

### Run Agents

```bash
# Plan work
/orchestrator goal: "add user authentication"

# Review code
/code-reviewer src/components/

# Commit changes
/repo-steward

# Log work (end of day)
/summarizer
```

---

## High-Level Architecture

### Directory Structure

```
ai-agent-manager/
├── ai-agent-manager-plugin/          # The Claude Code plugin
│   ├── agents/                       # Agent markdown prompts
│   │   ├── orchestrator.md           # Orchestrator agent
│   │   ├── code-reviewer.md          # Code Reviewer agent
│   │   ├── repo-steward.md           # Repo Steward agent
│   │   ├── summarizer.md             # Summarizer agent
│   │   ├── prompts.md                # Shared preamble for all agents
│   │   └── utils.md                  # Utility functions/shared logic
│   ├── commands/                     # Slash commands for Claude Code
│   │   ├── orchestrator.md           # /orchestrator command
│   │   ├── code-reviewer.md          # /code-reviewer command
│   │   ├── repo-steward.md           # /repo-steward command
│   │   ├── summarizer.md             # /summarizer command
│   │   └── agent-help.md             # /agent-help command
│   └── .claude-plugin/
│       └── plugin.json               # Plugin metadata (name, version, author)
│
├── .claude-plugin/
│   ├── marketplace.json              # Marketplace definition
│   └── README.md                     # Plugin usage documentation
│
├── templates/project-template/       # Template for new projects
│   ├── CLAUDE.md                     # Codebase knowledge template
│   ├── TODO.md                       # Tasks template
│   └── memory/
│       ├── context.md                # Current state template
│       └── session/TEMPLATE.md       # Session log template
│
├── README.md                         # User-facing documentation
├── AGENT_GUIDELINES.md               # Development standards & agent contract
└── CLAUDE.md                         # This file (for the ai-agent-manager repo itself)
```

### How Agents Work Together

```
User Goal
    ↓
/orchestrator → Task breakdown
    ↓
You pick tasks
    ↓
/code-reviewer → Code quality feedback
    ↓
Fix issues
    ↓
/repo-steward → Conventional commits + update TODO.md
    ↓
/summarizer → Update memory, create session log
    ↓
Next agent reads updated CLAUDE.md (knowledge grows)
```

### Memory Flow

```
Session Start:
  1. Agent reads CLAUDE.md (codebase knowledge)
  2. Agent reads TODO.md (today's tasks)
  3. Agent reads memory/context.md (current state, blockers)
  4. Agent reads git history (recent work)

During Work:
  5. Agent makes changes, updates TODO.md
  6. Agent updates memory/context.md if state changes
  7. Agent flags new patterns for CLAUDE.md

End of Day:
  8. Summarizer creates memory/session/YYYY-MM-DD.md (immutable record)
  9. Summarizer updates memory/context.md
  10. You review proposals in memory/context.md
  11. You update CLAUDE.md (approve/reject proposals)
  12. You commit project (code + memory files)

Next Day:
  13. New agent reads updated CLAUDE.md
  14. Knowledge accumulates; agents learn from discoveries
```

---

## Development Workflow

### Daily Pattern

**Morning:**
1. Run `/orchestrator goal: "today's objective"` to break down work
2. Review task breakdown and acceptance criteria

**During Work:**
1. Implement code
2. Run `/code-reviewer` to check for issues
3. Fix identified problems
4. Re-review if needed

**Afternoon:**
1. Run `/repo-steward` to create conventional commits
2. Review commit messages and TODO.md updates

**End of Day:**
1. Run `/summarizer` to create session log
2. Review memory/context.md and session log
3. Check for CLAUDE.md proposals in memory/context.md
4. Approve/reject pattern proposals
5. Update CLAUDE.md if proposals approved
6. Commit project (code + memory files)

### Adding or Modifying Agents

Agents are Markdown files in `ai-agent-manager-plugin/agents/`:

1. **Create new agent:**
   - Write `.md` file in `agents/` directory
   - Inherit from shared preamble in `prompts.md`
   - Follow structured output format (Context Read → Plan → Work → Results → Risks)

2. **Create slash command:**
   - Write `.md` file in `commands/` directory
   - Reference the agent prompt
   - Define command syntax and examples

3. **Test locally:**
   - Copy plugin to `~/.claude/plugins/` (or use `/plugin marketplace add ./`)
   - Run `/agent-help` to verify command is available
   - Test in a sample project

4. **Core principles:**
   - Do smallest correct thing that advances goal
   - Output structured Markdown
   - Never invent files/APIs/paths; ask if unsure
   - Respect project memory files
   - Cite exact file:line numbers when referencing code

### Adding New Agents

When creating a new agent, ensure it:
- Reads appropriate context files (CLAUDE.md, TODO.md, memory/context.md)
- Updates only the files it's responsible for (Summarizer updates session logs; Repo Steward updates TODO.md, etc.)
- Flags new patterns for CLAUDE.md update (not direct updates)
- Follows conventional commit standards (when applicable)
- Produces deterministic, auditable output

---

## Core Principles (From AGENT_GUIDELINES.md)

All agents follow these standards:

1. **Quality First** - Thorough, well-tested, correct solutions; proven approaches
2. **Surgical Changes** - Only modify what's necessary; fix one thing at a time
3. **Pattern Consistency** - Use existing patterns; learn codebase before implementing
4. **Type Safety** - Strictest checking; no implicit `any`; equivalent rigor per language
5. **Security** - No secrets/PII in code/logs; validate inputs; clear decisions
6. **Performance** - Profile before/after; document tradeoffs; optimize bottlenecks

### Quality Checklist

Before an agent completes work:
- Tests pass; no linting/type errors
- Code follows patterns; changes minimal and focused
- Coverage ≥ 80%; no regressions
- No secrets, debug code, console.logs
- Docs/comments updated
- Input validation in place

---

## Project Structure

### Key Files

| File | Purpose |
|------|---------|
| `README.md` | User-facing guide (installation, quick start, workflow) |
| `AGENT_GUIDELINES.md` | Development standards, agent contract, quality checklist |
| `.claude-plugin/README.md` | Detailed plugin documentation |
| `ai-agent-manager-plugin/agents/prompts.md` | Shared preamble for all agents |
| `templates/project-template/CLAUDE.md` | Template for new projects |

### Plugin Metadata

- **Plugin Name:** `ai-agent-manager-plugin`
- **Version:** 1.0.0
- **Author:** vikash ruhil
- **License:** MIT

### Marketplace Configuration

- Defined in `.claude-plugin/marketplace.json`
- Supports local marketplace (`/plugin marketplace add ./`)
- Supports remote GitHub marketplaces for team distribution

---

## Important Notes

### This is a Plugin System

- Agents are distributed as a Claude Code plugin
- Users install via `/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace`
- Agents run within Claude Code (not standalone)

### Language-Agnostic

- Agents work with any programming language
- Follow language-specific standards per AGENT_GUIDELINES.md (TypeScript, Python, Go, Rust, Java, etc.)

### Human-in-Loop Design

- Agents suggest changes; humans approve
- Agents flag pattern proposals in memory/context.md
- Only humans update CLAUDE.md (after review)
- Agents never make destructive changes without explicit instruction

### Memory is Project-Local

- Memory files live in user projects, not in ai-agent-manager
- Projects are self-contained and portable
- Same agents work across different projects

---

## Common Pitfalls

### Agents Don't Understand Project Structure?
- Update the project's CLAUDE.md with more detailed patterns
- Include concrete examples and file references
- Agents re-read CLAUDE.md at the start of each session

### Memory Files Out of Sync?
- Run Summarizer at end of day to update memory
- Summarizer reads git history and syncs state
- You can manually update if agent misses something

### New Pattern But Unsure If Important?
- Agent flags it in memory/context.md as a proposal
- Review code at specified file:line numbers
- Decide whether to add to CLAUDE.md
- Approval gates prevent noise

---

## Known Limitations

This system has architectural constraints documented in `AUDIT-REPORT.md`:

### Memory System
- **Non-atomic writes:** Memory files update sequentially; interruptions may cause inconsistency
- **Retention policy:** Max 30 session files (older archived), max 50 HISTORY.md entries (paginated)
- **Backup on write:** Agents create `.backup` files before modifying memory files
- **Recovery:** See `utils.md § Memory Recovery` for restoration procedures

### Git Operations
- **Branch protection:** Repo Steward refuses main/master without `--allow-main` flag
- **Dry-run mode:** Use `--dry-run` to preview without executing
- **No auto-rollback:** Manual recovery via `git reflog` if needed

### Agent Behavior
- **File verification:** Agents verify file existence before referencing, but LLM hallucination is possible
- **Input validation:** Goals limited to 1000 chars, paths must be relative, memory files validated
- **Observability:** All agents output structured summary (status, files read/modified, errors)

### Scale Considerations
- **Token overhead:** ~5,000-10,000 tokens per invocation for prompts + memory loading
- **Context7 dependency:** External library lookups require MCP; fallback to CLAUDE.md if unavailable

For migration between versions, see `MIGRATION.md`.

---

## Future Enhancements

Potential improvements tracked by agents in memory/context.md:
- Additional specialized agents (e.g., Documentation Agent, Performance Analyzer)
- Deeper GitHub/GitLab integration
- Cloud-synced memory (opt-in)
- Agent composition (multi-agent workflows)
- Metrics and analytics

---

## References

- **Main docs:** `README.md` (user guide, examples, troubleshooting)
- **Plugin docs:** `.claude-plugin/README.md` (installation, commands, project setup)
- **Development standards:** `AGENT_GUIDELINES.md` (quality checklist, agent contract, standards per language)
- **Agent prompts:** `ai-agent-manager-plugin/agents/*.md` (detailed agent definitions)
- **Project template:** `templates/project-template/` (starter files for new projects)
