# AI Agent Manager Plugin for Claude Code

A powerful Claude Code plugin with 3 intelligent agents, 18 focused skills, and Beads issue tracker integration for modern development workflows. Replaces TODO.md with issue-driven task management and enforces quality gates on code reviews.

## Overview

The AI Agent Manager Plugin 2.0 includes:

- **🎯 Orchestrator Agent** — Break goals into Beads tasks with mandatory review gates
- **👀 Code Reviewer Agent** — Review code with PASS/FAIL/NEEDS_HUMAN decisions (blocks task progression)
- **🔴 Red Team Reviewer Agent** — Adversarial audits to break assumptions

**17 Focused Skills:**
- **Core:** Commits (Beads linking), Context7 library lookups, Quality checklist, Pattern detection
- **NestJS:** Guards, Controllers, Services, Drizzle ORM
- **Next.js:** Routing, Components, API routes, Data fetching, Authentication
- **Gateway:** Proxy patterns, Auth middleware, Rate limiting, Correlation ID

Skills are loaded on-demand to keep context small (70-80% token reduction vs. monolithic agents).

## Quick Start

### 1. Installation

**Option A: Install from Local Marketplace (Recommended for Testing)**

First, set up a local marketplace:

```bash
# From the ai-agent-manager root directory, create a marketplace
cd /path/to/ai-agent-manager

# In Claude Code, add the local marketplace
/plugin marketplace add ./
```

Then install the plugin:

```bash
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

**Option B: Create a Distributed Marketplace**

For sharing with your team, create a marketplace repository. See [Marketplace Setup Guide](#marketplace-setup-guide) below.

**Option C: Manual Installation**

Copy the `.claude-plugin/` folder to your Claude Code config directory:
- **macOS/Linux:** `~/.claude/plugins/ai-agent-manager/`
- **Windows:** `%APPDATA%\Claude\plugins\ai-agent-manager\`

### 2. Setup Beads Issue Tracker

Initialize Beads in your project (replaces TODO.md):

```bash
cd /path/to/your/project

# Install Beads (one-time)
# See: https://github.com/steveyegge/beads

# Initialize in your project
bd init
```

### 3. Initialize Your Project

Your project needs one file for agents to work:

```bash
cd /path/to/your/project

# Copy the template files
cp -r /path/to/ai-agent-manager/templates/project-template/* .

# Files created:
# - CLAUDE.md (Codebase knowledge - required)

# No more TODO.md or memory/ files - Beads tracks everything!
```

### 4. Run Your First Command

```bash
bd list  # See all Beads issues
/orchestrator goal: "add dark mode to UI"
```

The orchestrator will:
1. Find your project's CLAUDE.md
2. Check Beads for current work state
3. Break goal into tasks with built-in review gates
4. Create Beads tasks (BD-XXX) with subtasks

## Commands

### /orchestrator goal: "<what to do>"

Break a goal into minimal, actionable Beads tasks with mandatory code review subtasks.

```bash
/orchestrator goal: "add dark mode to UI"
/orchestrator goal: "fix login bug" --project /path/to/project
```

**Output:**
- Beads task structure (EPIC → TASK → SUBTASK)
- Each implementation task gets a review subtask (blocks progression)
- Acceptance criteria
- Skill references (not embedded content)
- Dependencies with blocking relationships

**Example Output:**
```
BD-45: Add Dark Mode (EPIC)
├── BD-46: Implement dark mode toggle (TASK)
├── BD-47: Code Review - Dark Mode Toggle (SUBTASK) [blocks BD-48]
├── BD-48: Add dark mode tests (TASK)
├── BD-49: Code Review - Tests (SUBTASK) [blocks BD-50]
├── BD-50: Commit & Link (TASK)
```

---

### /code-reviewer [files] [--project /path]

Review code against quality standards with PASS/FAIL/NEEDS_HUMAN decision gates.

```bash
bd claim BD-47                           # Claim review subtask
/code-reviewer src/components/DarkMode  # Review implementation
```

**Checks:**
- Type safety, security, performance
- Pattern consistency (vs CLAUDE.md)
- Test coverage (≥80% by default)
- Skills pattern alignment

**Decisions:**
- **PASS:** All criteria met → Next task unblocks automatically
- **FAIL:** Critical issues found → Must fix + re-review
- **NEEDS_HUMAN:** Non-critical issues → Creates bug issues (BD-XX) that block review

**Output:**
- Decision line: `## Code Review Decision: PASS | FAIL | NEEDS_HUMAN`
- Issues by severity (HIGH/MEDIUM/LOW) with file:line + fixes
- Bug issues created (if NEEDS_HUMAN)
- Pattern proposals for CLAUDE.md
- Strengths highlighted

---

### /commit

Create conventional commits with Beads linking (replaces /repo-steward).

```bash
/commit  # Stage changes and create commits referencing Beads tasks
```

**Commits Example:**
```
feat(theme): add dark mode toggle

Closes BD-46

- Implement DarkMode component
- Add theme provider
- Store preference in localStorage
```

---

### /agent-help

Show all commands and quick reference.

```bash
/agent-help
```

**Shows:**
- All available commands
- Usage examples
- When to use each agent
- Daily workflow
- Tips & tricks

---

## Daily Workflow

### Morning: Plan Your Work

```bash
cd /path/to/your/project
bd list                           # See current Beads tasks
/orchestrator goal: "add feature X"  # Creates BD-XXX tasks with review gates
```

→ Orchestrator creates task chain with mandatory review subtasks

### During Work: Implement & Review

```bash
# Implement BD-46
bd claim BD-46
# ... implement feature ...

# Review BD-47 (review subtask)
bd claim BD-47
/code-reviewer src/FeatureX
```

→ Code Reviewer posts PASS/FAIL/NEEDS_HUMAN decision to BD-47

### When Review Passes: Next Task Unblocks

```bash
# If PASS → BD-48 (next implementation) auto-unblocks
bd claim BD-48
# ... continue implementation ...
```

→ Task progression is automatic based on review decisions

### End: Commit with Beads Linking

```bash
/commit  # Creates conventional commits with "Closes BD-46" references
```

→ Commits link to Beads tasks for traceability

---

## Project Structure

### Required Files

Your project needs just ONE file for agents to work:

```
your-project/
├── CLAUDE.md                    # Codebase knowledge (required)
└── .beads/                      # Beads issue tracker (auto-created by bd init)
```

**That's it! No TODO.md, no memory/ directory needed.**

#### CLAUDE.md

Define your codebase knowledge:

```markdown
# CLAUDE.md — Project Knowledge

## Overview
[Brief project description]

## Tech Stack
- Frontend: React 18, TypeScript, Tailwind CSS
- Backend: Node.js 18, Express 4, PostgreSQL
- Testing: Jest, React Testing Library

## Architecture
[Describe folder structure, patterns, conventions]

## Key Patterns
- State management: Context API
- API calls: Custom hooks (useFetch)
- Error handling: [Your approach]
- Testing: Unit + integration tests, ≥80% coverage

## Conventions
- Naming: camelCase for variables, PascalCase for components
- Commits: Conventional commits (feat, fix, test, etc)
- Types: TypeScript strict mode required
- Code style: Prettier, ESLint

## Commands
```
npm run dev      # Start dev server
npm test         # Run tests
npm run type-check
npm run lint
npm run format
```

## Important Notes
[Any gotchas, setup details, or team conventions]
```

### No More TODO.md or Memory Files

**Beads replaces all task tracking:**

```bash
# See tasks
bd list

# See task details
bd show BD-46

# Update task status
bd update BD-46 --status in_progress

# Check blockers and dependencies
bd show BD-46 --depends-on
```

All task state, blockers, and dependencies are tracked in Beads issue system.

### Plugin Files

The plugin is organized with the marketplace at the root and the actual plugin in a subdirectory:

```
ai-agent-manager/                (marketplace root)
├── .claude-plugin/
│   ├── marketplace.json         # Marketplace manifest
│   └── README.md                # This file
│
└── ai-agent-manager-plugin/     (plugin directory)
    ├── .claude-plugin/
    │   └── plugin.json          # Plugin metadata
    ├── commands/                # Slash commands
    │   ├── orchestrator.md
    │   ├── code-reviewer.md
    │   ├── red-team-reviewer.md
    │   └── agent-help.md
    ├── agents/                  # Agent implementations
    │   ├── orchestrator.md
    │   ├── code-reviewer.md
    │   └── red-team-reviewer.md
    └── skills/                  # Focused skill modules (loaded on-demand)
        ├── core/                # Core skills
        │   ├── commit.md
        │   ├── context7-lookup.md
        │   ├── quality-checklist.md
        │   └── pattern-detector.md
        ├── frontend/            # Frontend UI patterns
        │   └── frontend-ui.md   # Design-system, accessibility (WCAG 2.1 AA), responsive design
        ├── nestjs/              # NestJS patterns
        │   ├── guards.md
        │   ├── controllers.md
        │   ├── services.md
        │   └── drizzle.md
        ├── nextjs/              # Next.js patterns
        │   ├── routing.md
        │   ├── components.md
        │   ├── api-routes.md
        │   ├── data-fetching.md
        │   └── auth.md
        └── gateway/             # API Gateway patterns
            ├── proxy-patterns.md
            ├── auth-middleware.md
            ├── rate-limiting.md
            └── correlation.md
```

**Skills Architecture:**
- Skills are loaded on-demand based on project context
- Agents reference skills instead of embedding content
- Reduces per-task context by 70-80% vs monolithic agents
- Easy to add new skills without modifying agents

---

## Key Concepts

### Project Auto-Detection

Agents automatically find your project:

1. Search current directory for CLAUDE.md
2. Search parent directories up to root
3. Use first CLAUDE.md found (nearest wins)
4. Accept `--project /path` override

This means agents work from any directory in your project:

```bash
cd /path/to/project
/orchestrator goal: "add feature"     # Works

cd /path/to/project/src/components
/orchestrator goal: "add feature"     # Still works (auto-finds parent CLAUDE.md)

cd /elsewhere
/orchestrator goal: "add feature" --project /path/to/project  # Works with explicit path
```

### Approval Workflow

Agents suggest changes, you approve:

- **Code Issues:** Agent flags, you fix
- **File Updates:** Agent suggests format, you review
- **CLAUDE.md Changes:** Agent proposes (shows example text), you approve
- **Commits:** Agent creates, you review with `git log`
- **Pushes:** Only with explicit `--push` flag

### Beads Issue Tracking

Agents read and update Beads:

| Command | Purpose | Updated By | When |
|---------|---------|-----------|------|
| `bd list` | View all tasks | Orchestrator | Task creation |
| `bd show BD-XX` | View task details | You | Anytime |
| `bd claim BD-XX` | Start task | You | When ready to work |
| `bd update BD-XX` | Mark complete/blocked | Code Reviewer | After reviews |
| `bd comments BD-XX` | Review decisions | Code Reviewer | After review |

### Conventional Commits with Beads Linking

The `/commit` command uses standardized commit format with Beads references:

```
<type>(<scope>): <message>

<optional body>

Closes BD-XX
```

**Types:** `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `security`

**Examples:**
```
feat(theme): add dark mode toggle
Closes BD-46

- Implement DarkMode component
- Add theme context provider

---

fix(login): correct mobile button spacing
Closes BD-47

---

test(settings): add dark mode tests
Closes BD-48

security(hooks): validate localStorage input
refactor(components): extract DarkMode logic
docs(README): update setup instructions
chore(deps): upgrade React to 18.2.0
```

---

## Architecture

### How Agents Work Together

```
YOU: Set a goal
  ↓
ORCHESTRATOR: Break into tasks → Assign to agents
  ↓
CODE REVIEWER: Check patterns, flag issues
  ↓
YOU: Fix issues from review
  ↓
REPO STEWARD: Create commits, update TODO
  ↓
SUMMARIZER: Log work, propose patterns
  ↓
YOU: Approve pattern proposals
  ↓
DONE: Ready for next work
```

### Agent Independence

Agents are self-contained:

- **Orchestrator** → Reads CLAUDE.md, TODO.md, memory/context.md
- **Code Reviewer** → Reads CLAUDE.md, git diff, your code
- **Repo Steward** → Reads git staging, CLAUDE.md, TODO.md
- **Summarizer** → Reads git log, CLAUDE.md, memory/context.md

Each agent:
- Auto-detects project
- Loads needed context
- Does its work
- Suggests changes (no auto-writes)
- Hands off to next agent

### File Operations

Agents read files openly, suggest writes:

```markdown
## Suggested TODO.md Update

[Show what should be added/changed]

Status: Awaiting user approval before write
```

You then manually apply or approve changes.

---

## Marketplace Setup Guide

### Create a Local Marketplace (For Testing)

Set up a local marketplace to test the plugin before distributing it:

#### 1. Create the Marketplace Manifest

In the ai-agent-manager root directory, create `.claude-plugin/marketplace.json`:

```json
{
  "name": "ai-agent-manager-marketplace",
  "owner": {
    "name": "Your Name or Organization"
  },
  "plugins": [
    {
      "name": "ai-agent-manager-plugin",
      "source": "./ai-agent-manager-plugin",
      "description": "Global agents for orchestrating, reviewing, summarizing, and managing git workflow",
      "version": "1.0.0",
      "author": {
        "name": "Your Name"
      }
    }
  ]
}
```

**Note:** The marketplace.json already exists in this repository with the correct source path, so you can skip this step.

#### 2. Add the Marketplace to Claude Code

From the ai-agent-manager directory:

```bash
cd /path/to/ai-agent-manager

# In Claude Code:
/plugin marketplace add ./
```

This tells Claude Code: "Look in this directory for a marketplace.json file"

#### 3. List Available Marketplaces

Verify the marketplace was added:

```bash
/plugin marketplace list
```

You should see `ai-agent-manager-marketplace` in the output.

#### 4. Install the Plugin

```bash
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

Claude Code will:
- Download the plugin from `./`
- Register all 5 commands
- Make agents available globally

#### 5. Test the Plugin

```bash
# Navigate to a project with CLAUDE.md
cd /path/to/your-project

# Test a command
/orchestrator goal: "test the orchestrator agent"

# Or test help
/agent-help
```

### Create a Distributed Marketplace (For Sharing)

When ready to share with your team:

#### 1. Create a GitHub Repository

Create a new GitHub repo (e.g., `your-org/claude-plugins`)

#### 2. Add Marketplace Files

In the repo root, create:

```
your-org/claude-plugins/
├── .claude-plugin/
│   └── marketplace.json
└── ai-agent-manager-plugin/
    ├── .claude-plugin/
    │   └── plugin.json
    ├── agents/
    ├── commands/
    └── hooks/
```

**marketplace.json:**

```json
{
  "name": "your-org-plugins",
  "owner": {
    "name": "Your Organization"
  },
  "plugins": [
    {
      "name": "ai-agent-manager-plugin",
      "source": {
        "source": "github",
        "repo": "your-org/claude-plugins",
        "path": "ai-agent-manager-plugin"
      },
      "description": "Global agents for orchestrating, reviewing, summarizing, and managing git workflow",
      "version": "1.0.0"
    }
  ]
}
```

#### 3. Share with Your Team

Team members can add your marketplace:

```bash
/plugin marketplace add your-org/claude-plugins
/plugin install ai-agent-manager-plugin@your-org-plugins
```

### Troubleshooting Marketplace Issues

**Marketplace not loading:**
- Verify `.claude-plugin/marketplace.json` exists
- Check JSON syntax: `claude plugin validate .`
- Ensure paths are correct (relative or absolute)

**Plugin installation fails:**
- Verify plugin source path exists
- Check file permissions
- For GitHub sources: ensure repo is public or you have access

---

## Troubleshooting

### "Error: No project context found"

**Cause:** Agent couldn't find CLAUDE.md

**Solution:**
```bash
# Initialize project with template
cp -r /path/to/ai-agent-manager/templates/project-template /your/project

# Or specify explicit path
/orchestrator goal: "add feature" --project /path/to/project
```

### "No files to review" (Code Reviewer)

**Cause:** No git changes detected

**Solution:**
```bash
# Option 1: Specify files
/code-reviewer src/components/MyFile.tsx

# Option 2: Stage changes first
git add src/
/code-reviewer
```

### "No commits created" (Repo Steward)

**Cause:** No staged changes

**Solution:**
```bash
# Stage files first
git add src/components/DarkMode.tsx
/repo-steward
```

### "Session log not created" (Summarizer)

**Cause:** No commits since last session

**Solution:**
- Make commits first
- Then run summarizer
- Or check memory/session/ to see if log exists

### Agent gives incorrect patterns

**Cause:** CLAUDE.md outdated or incomplete

**Solution:**
1. Update CLAUDE.md with current patterns
2. Run agent again
3. Agent will learn from updated CLAUDE.md

---

## Advanced Usage

### Running Agents Out of Order

You don't need to follow the sequential workflow:

```bash
# Review before coding (to learn patterns)
/code-reviewer src/

# Plan before coding
/orchestrator goal: "add feature"

# Multiple reviews during development
/code-reviewer src/
# Make changes
/code-reviewer src/
# Repeat

# Commit when ready (no summarizer needed yet)
/repo-steward
```

### Multi-Project Workflows

Work across projects seamlessly:

```bash
# Project A
cd /path/to/project-a
/orchestrator goal: "fix bug"
# ... do work, commit ...

# Switch to Project B
cd /path/to/project-b
/orchestrator goal: "add feature"  # Auto-detects project-b context
# ... do work, commit ...
```

### Custom Project Templates

Create your own template if projects have different structures:

```bash
# Your custom template
my-project-template/
├── CLAUDE.md             # Your standard CLAUDE.md
├── TODO.md
└── memory/
    ├── context.md
    └── session/

# Use when creating new projects
cp -r my-project-template /path/to/new-project
```

### Integration with Git Hooks

Use agents with git hooks for automation:

```bash
# .githooks/pre-commit
#!/bin/bash
/code-reviewer src/
# Fails if HIGH severity issues found
```

### CI/CD Integration

Use agents in your CI/CD pipeline:

```bash
# .github/workflows/review.yml
- name: Code Review
  run: /code-reviewer src/

- name: Check Commits
  run: git log --oneline
```

---

## Configuration

### Plugin Settings

The plugin uses Claude Code's built-in settings:

- Project detection: Auto (current dir + parents)
- Memory files: Project-based (not cloud)
- Approval workflow: Manual (agent suggests, you approve)
- Push safety: Explicit --push flag required

### Project Settings (in CLAUDE.md)

Define project-specific settings in CLAUDE.md:

```markdown
## Configuration

### Type Safety Level
- TypeScript: strict mode required
- Python: mypy with strict config

### Testing Threshold
- Coverage: ≥80% for all code
- Exception: UI components ≥70% (hard to test)

### Code Quality
- Linting: ESLint with strict config
- Formatting: Prettier (auto-format)
- Imports: Organized, no unused

### Security
- Secrets: Never in code (use .env)
- Dependencies: No known vulnerabilities
- Input validation: Always required
```

---

## FAQ

### Q: Do agents make changes automatically?

**A:** No. Agents suggest changes and describe them. You decide whether to apply them. This keeps you in control.

### Q: Can I use agents on different languages?

**A:** Yes. The plugin works on any language (JavaScript, Python, Go, Rust, Java, etc). Customize patterns in CLAUDE.md for your language.

### Q: What if my project doesn't follow conventional commits?

**A:** Repo Steward uses conventional commits by default. If you prefer a different format, edit your project's CLAUDE.md to specify.

### Q: Can I customize agent behavior?

**A:** Yes. Edit the agent prompts in `ai-agent-manager-plugin/agents/*.md` to match your needs. Share improvements back to the main project.

### Q: Do agents need internet?

**A:** No. Everything runs locally. Agents read your local files and git history only.

### Q: Can I use agents on old projects?

**A:** Yes. Just add CLAUDE.md, TODO.md, and memory/ directory. Use the template as reference.

### Q: What if CLAUDE.md gets out of sync?

**A:** Agents learn from current CLAUDE.md. Update it when patterns change. Summarizer proposes updates automatically.

### Q: Can agents access remote repositories?

**A:** Agents can't directly access remote repos, but `/repo-steward --push` can push commits using your git credentials.

### Q: Do I need all 3 agents?

**A:** No. Use which ones help you:
- Just need to plan? Use Orchestrator (creates Beads tasks)
- Just need to review code? Use Code Reviewer (PASS/FAIL/NEEDS_HUMAN)
- Just need to audit assumptions? Use Red Team Reviewer (adversarial)

### Q: Can agents work on private projects?

**A:** Yes. Everything stays local. Your code and memory files never leave your machine.

### Q: What's the best way to learn?

**A:** Run `/agent-help` for quick reference, then try each agent:
1. `/orchestrator goal: "simple task"` — See task breakdown
2. `/code-reviewer src/` — See code feedback
3. `/repo-steward` — See commit organization
4. `/summarizer` — See work summary

---

## Contributing

Found a bug? Want to improve an agent? Contribute:

```bash
git clone https://github.com/your-org/ai-agent-manager
cd ai-agent-manager

# Make changes to ai-agent-manager-plugin/agents/* or ai-agent-manager-plugin/commands/*
# Test with your project
# Submit PR

# See main project repo for contribution guidelines
```

---

## License

MIT License — See LICENSE file in ai-agent-manager repo

---

## Support

### Need Help?

```bash
# Show help for specific agent
/orchestrator --help
/code-reviewer --help
/summarizer --help
/repo-steward --help

# General help
/agent-help

# Read plugin docs
cat /path/to/plugin/README.md
```

### Report Issues

Open an issue in the main ai-agent-manager repository with:
- What command you ran
- What happened
- What you expected
- Your project type (e.g., React, Node.js, Python)

### Suggest Improvements

Have an idea for a new agent or feature? Open a discussion in the repository.

---

## Roadmap

Planned features:

- [ ] Git conflict resolution agent
- [ ] Documentation generation agent
- [ ] Performance profiling agent
- [ ] Dependency update agent
- [ ] Test generation agent
- [ ] API specification generator
- [ ] Security scanning integration
- [ ] Team collaboration features

---

## Acknowledgments

Built on the foundational work of the AI Agent Manager framework.

Special thanks to the Claude Code team for the excellent plugin system.

---

**Ready to start?** Run `/orchestrator goal: "your goal"` now!

For more information, check the main [AI Agent Manager repository](https://github.com/your-org/ai-agent-manager).
