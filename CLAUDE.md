# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**AI Agent Manager** is a reusable system that provides intelligent agents for software development workflows. It integrates with Claude Code as a plugin with 6 specialized agents that automate autonomous workflows, requirements definition, planning, code review, commit management, and adversarial security audits.

The system enables agents to collaborate on any project type using **Beads issue tracker** for task management and `CLAUDE.md` for codebase knowledge that persists between work sessions.

---

## Architecture & Key Concepts

### Plugin System

The project is structured as a **Claude Code plugin marketplace**:

1. **Plugin Package** (`ai-agent-manager-plugin/`)
   - Agent definitions: `agents/` (Markdown prompts)
   - Slash commands: `commands/` (entry points)
   - Skills: `skills/` (focused implementation guidance)

2. **Marketplace** (`.claude-plugin/`)
   - Plugin metadata and distribution
   - Installation via `/plugin install` command
   - Supports local and remote marketplaces

### Beads Task Management

**Beads replaces TODO.md and memory files:**

| Command | Purpose |
|---------|---------|
| `bd list` | View open/in-progress/completed tasks |
| `bd create` | Create new task |
| `bd claim BD-XX` | Start working on a task |
| `bd close BD-XX` | Mark task complete |
| `bd comment BD-XX "note"` | Add notes to task |
| `bd dep BD-XX BD-YY` | Set task dependencies |

**Task Structure:**
- **EPIC:** Large feature (contains multiple tasks)
- **TASK:** Implementation work (30-60 min)
- **SUBTASK:** Review gate (blocks next task)

**Review Gates:**
- Every implementation task has a review subtask
- Review subtask blocks next implementation task
- Review decisions: PASS (proceed), FAIL (fix and re-review), NEEDS_HUMAN (creates bug issues)

### The 6 Agents

Each agent is a Markdown prompt file (`agents/[name].md`):

#### **Supervisor** (`/supervisor`)
- **Purpose:** Autonomously manage complete development workflow from task pickup to PR creation
- **When to use:** Full automation of task completion
- **Command:** `/supervisor` or `/supervisor task: BD-XX`
- **Workflow:** Picks up ready tasks → orchestrates agents → creates PRs → loops
- **Outputs:** Completed tasks with PRs and Beads linking

#### **Product Owner** (`/product-owner`)
- **Purpose:** Translate business problems into user stories with acceptance criteria
- **When to use:** New feature, vague requirements
- **Command:** `/product-owner feature: "your feature"` or `/product-owner problem: "issue to solve"`
- **Workflow:** Reads domain context → runs discovery → writes user stories
- **Outputs:** Beads stories with acceptance criteria (Given/When/Then)

#### **Orchestrator** (`/orchestrator`)
- **Purpose:** Break goals into Beads tasks with review gates
- **When to use:** Starting new work or need a plan
- **Command:** `/orchestrator goal: "what you want to accomplish"`
- **Workflow:** Reads CLAUDE.md + Beads state → creates task structure
- **Outputs:** EPIC → TASK → SUBTASK structure with skill references

#### **Code Reviewer** (`/code-reviewer`)
- **Purpose:** Provide precise feedback; output PASS/FAIL/NEEDS_HUMAN decision
- **When to use:** After writing code, need review
- **Command:** `/code-reviewer src/` (specify files/dirs to review)
- **Checks:** Type safety, security, performance, pattern alignment, test coverage
- **Outputs:** Issues (BLOCKING/HIGH/MEDIUM/LOW) + decision + CLAUDE.md proposals

#### **Repo Steward** (`/repo-steward`)
- **Purpose:** Keep repository clean with organized, conventional commits
- **When to use:** Ready to commit work
- **Command:** `/repo-steward` or `/repo-steward --push`
- **Workflow:** Stages changes → writes conventional messages → links to Beads
- **Outputs:** Commit messages with Beads linking (e.g., "Closes BD-XX")

#### **Red Team Reviewer** (`/red-team-reviewer`)
- **Purpose:** Adversarial audit — find what breaks in production
- **When to use:** Pre-launch, security reviews, architecture decisions
- **Command:** `/red-team-reviewer [target] [--focus security|scale|cost|ops]`
- **Workflow:** Attacks assumptions → verifies claims against docs → explores 6 attack vectors
- **Outputs:** Findings by severity (FATAL/CRITICAL/WARNING/WEAKNESS), prioritized fixes

### Agent Design Principles

All agents follow a **shared contract** (see AGENT_GUIDELINES.md):

- **Mission:** Do the smallest correct thing that advances the objective
- **Input:** Context from CLAUDE.md + Beads state + recent git history
- **Output:** Structured Markdown with Context Read → Plan → Work → Results → Risks & Next Steps
- **Safety:** No destructive actions (db migrations, force-push) without explicit approval
- **Rules:** Never invent files/APIs/paths; ask if unsure; use Beads for task management

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
# Initialize project
cd /path/to/your-project
bd init

# Create CLAUDE.md with your project patterns
```

This creates:
```
your-project/
├── CLAUDE.md              # Your codebase knowledge
├── .beads/                # Beads issue tracker (auto-managed)
│   └── issues/
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

# Adversarial audit (pre-launch)
/red-team-reviewer --focus security
```

---

## High-Level Architecture

### Directory Structure

```
ai-agent-manager/
├── ai-agent-manager-plugin/          # The Claude Code plugin
│   ├── agents/                       # Agent markdown prompts (6 agents)
│   │   ├── supervisor.md             # Supervisor agent (autonomous workflow)
│   │   ├── product-owner.md          # Product Owner agent (requirements)
│   │   ├── orchestrator.md           # Orchestrator agent (task planning)
│   │   ├── code-reviewer.md          # Code Reviewer agent (quality gates)
│   │   ├── repo-steward.md           # Repo Steward agent (commits)
│   │   └── red-team-reviewer.md      # Red Team Reviewer agent (adversarial)
│   ├── commands/                     # Slash commands for Claude Code
│   │   ├── supervisor.md             # /supervisor command
│   │   ├── product-owner.md          # /product-owner command
│   │   ├── orchestrator.md           # /orchestrator command
│   │   ├── code-reviewer.md          # /code-reviewer command
│   │   ├── repo-steward.md           # /repo-steward command
│   │   ├── red-team-reviewer.md      # /red-team-reviewer command
│   │   └── agent-help.md             # /agent-help command
│   ├── skills/                       # Skill files for guidance (30 skills)
│   │   ├── workflow-management/      # Autonomous workflow patterns
│   │   ├── context-summarization/    # Output compression for context
│   │   ├── commit/                   # Conventional commits
│   │   ├── quality-checklist/        # Review gate criteria
│   │   ├── pattern-detector/         # CLAUDE.md proposals
│   │   ├── nestjs-*/                 # NestJS patterns (6 skills)
│   │   ├── nextjs-*/                 # Next.js patterns (5 skills)
│   │   ├── gateway-*/                # API Gateway patterns (4 skills)
│   │   ├── nestjs-typeorm/           # TypeORM integration
│   │   └── mysql/                    # MySQL patterns
│   └── .claude-plugin/
│       └── plugin.json               # Plugin metadata (v2.2.0)
│
├── .claude-plugin/
│   ├── marketplace.json              # Marketplace definition
│   └── README.md                     # Plugin usage documentation
│
├── README.md                         # User-facing documentation
├── AGENT_GUIDELINES.md               # Development standards & agent contract
└── CLAUDE.md                         # This file
```

### How Agents Work Together

```
User Goal
    ↓
/orchestrator → Beads tasks (EPIC → TASK → SUBTASK)
    ↓
bd claim BD-XX → Start task
    ↓
You code
    ↓
/code-reviewer → PASS/FAIL/NEEDS_HUMAN
    ↓
Fix issues (if FAIL)
    ↓
/repo-steward → Conventional commits + Beads linking
    ↓
bd close BD-XX → Task complete, next unblocked
    ↓
Next agent reads updated CLAUDE.md (knowledge grows)
```

### Beads Workflow

```
Session Start:
  1. Agent reads CLAUDE.md (codebase knowledge)
  2. Agent runs bd list (current task state)
  3. Agent reads git history (recent work)

During Work:
  4. Agent creates/updates Beads tasks
  5. Agent outputs review decisions (PASS/FAIL/NEEDS_HUMAN)
  6. Agent flags new patterns for CLAUDE.md

Task Complete:
  7. bd close BD-XX (marks complete, unblocks next)
  8. You review pattern proposals
  9. You update CLAUDE.md (approve/reject proposals)
  10. Knowledge accumulates; agents learn from discoveries
```

---

## Development Workflow

### Daily Pattern

**Morning:**
1. Run `/orchestrator goal: "today's objective"` to create Beads tasks
2. Review task structure and acceptance criteria

**During Work:**
1. `bd claim BD-XX` to start task
2. Implement code
3. Run `/code-reviewer` to check for issues
4. Fix identified problems, re-review until PASS

**Afternoon:**
1. Run `/repo-steward` to create conventional commits
2. `bd close BD-XX` to complete task

**Pre-Launch:**
1. Run `/red-team-reviewer` for adversarial audit
2. Address FATAL and CRITICAL findings

### Adding or Modifying Agents

Agents are Markdown files in `ai-agent-manager-plugin/agents/`:

1. **Create new agent:**
   - Write `.md` file in `agents/` directory
   - Follow structured output format (Context Read → Plan → Work → Results → Risks)

2. **Create slash command:**
   - Write `.md` file in `commands/` directory
   - Reference the agent prompt
   - Define command syntax and examples

3. **Create skill:**
   - Write `SKILL.md` in `skills/[skill-name]/` directory
   - Include quick rules, examples, and quality gates

4. **Test locally:**
   - Copy plugin to `~/.claude/plugins/` (or use `/plugin marketplace add ./`)
   - Run `/agent-help` to verify command is available
   - Test in a sample project

5. **Core principles:**
   - Do smallest correct thing that advances goal
   - Output structured Markdown
   - Never invent files/APIs/paths; ask if unsure
   - Use Beads for task management
   - Cite exact file:line numbers when referencing code

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
| `ai-agent-manager-plugin/skills/*/SKILL.md` | Skill files for implementation guidance |

### Plugin Metadata

- **Plugin Name:** `ai-agent-manager-plugin`
- **Version:** 2.2.0
- **Description:** Beads-integrated AI agents with focused skills architecture
- **Agents:** 6 (Supervisor, Product Owner, Orchestrator, Code Reviewer, Repo Steward, Red Team Reviewer)
- **Skills:** 30 reusable skill files
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
- Agents flag pattern proposals in Beads task comments
- Only humans update CLAUDE.md (after review)
- Agents never make destructive changes without explicit instruction

### Beads for Task Management

- Beads issue tracker replaces TODO.md and memory files
- Projects need only CLAUDE.md + .beads/ directory
- Same agents work across different projects

---

## Common Pitfalls

### Agents Don't Understand Project Structure?
- Update the project's CLAUDE.md with more detailed patterns
- Include concrete examples and file references
- Agents re-read CLAUDE.md at the start of each session

### Beads Tasks Not Appearing?
- Run `bd list` to check current state
- Ensure `bd init` was run in project

### New Pattern But Unsure If Important?
- Agent flags it in Beads task comment as a proposal
- Review code at specified file:line numbers
- Decide whether to add to CLAUDE.md
- Approval gates prevent noise

---

## Known Limitations

### Agent Behavior
- **File verification:** Agents verify file existence before referencing, but LLM hallucination is possible
- **Observability:** All agents output structured summary (status, files read/modified, errors)

### Scale Considerations
- **Token overhead:** ~5,000-10,000 tokens per invocation for prompts
- **Context7 dependency:** External library lookups require MCP; fallback to CLAUDE.md if unavailable

---

## Future Enhancements

Potential improvements:
- Additional specialized agents (e.g., Documentation Agent, Performance Analyzer)
- Deeper GitHub/GitLab integration
- Agent composition (multi-agent workflows)
- Metrics and analytics

---

## References

- **Main docs:** `README.md` (user guide, examples, troubleshooting)
- **Plugin docs:** `.claude-plugin/README.md` (installation, commands, project setup)
- **Development standards:** `AGENT_GUIDELINES.md` (quality checklist, agent contract, standards per language)
- **Agent prompts:** `ai-agent-manager-plugin/agents/*.md` (detailed agent definitions)
- **Skills:** `ai-agent-manager-plugin/skills/*/SKILL.md` (implementation guidance)
