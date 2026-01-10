# AI Agent Manager

A system for AI agents to collaborate on software projects. Six specialized agents (Supervisor, Product Owner, Orchestrator, Code Reviewer, Repo Steward, Red Team Reviewer) automate workflows, requirements, planning, review, commits, and adversarial audits.

**Key Idea:** Agents use **Beads issue tracker** for task management. Your projects need only a `CLAUDE.md` file for codebase knowledge. Agents read context, do work, create Beads tasks. Repeatable across any project.

> **Install the plugin and run slash commands instead of manually managing agents.**
>
> **NEW:** Use `/supervisor` for fully autonomous workflow — picks up tasks, runs agents, creates PRs automatically.

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

# Initialize Beads issue tracker
bd init

# Create CLAUDE.md with your project patterns
# (See CLAUDE.md Structure section below)
```

This creates:
```
your-project/
├── CLAUDE.md              # Codebase knowledge (you maintain)
├── .beads/                # Beads issue tracker (auto-managed)
│   └── issues/
└── src/ (your code)
```

### 3. Run Your First Command

```bash
/orchestrator goal: "what you want to accomplish"
```

Orchestrator will:
1. Read your CLAUDE.md
2. Understand your goal
3. Create Beads tasks with review gates
4. Output task structure and skill references

---

## The 6 Agents

| Agent | Command | Purpose | When |
|-------|---------|---------|------|
| **Supervisor** | `/supervisor` | Autonomous workflow → task pickup → agents → PR → next task | Full automation |
| **Product Owner** | `/product-owner feature: "..."` | Define requirements → create user stories with acceptance criteria | New feature, vague requirements |
| **Orchestrator** | `/orchestrator goal: "..."` | Plan work → create Beads tasks with review gates | Starting implementation |
| **Code Reviewer** | `/code-reviewer src/` | Review code → output PASS/FAIL/NEEDS_HUMAN | After writing code |
| **Repo Steward** | `/repo-steward` | Stage changes → create commits → link to Beads | Ready to commit |
| **Red Team Reviewer** | `/red-team-reviewer` | Adversarial audit → find production failures | Pre-launch, security |

**Autonomous Workflow (Supervisor):**
```
/supervisor
    ↓
Task Pickup (bd ready) → Branch Creation → Agent Orchestration → PR Creation → Next Task
    ↓
Loops until no more ready tasks
```

**Manual Workflow:**
```
Product Owner → Create Beads stories (user requirements)
    ↓
Orchestrator → Break stories into tasks (EPIC → TASK → SUBTASK)
    ↓
bd claim BD-XX → Start task
    ↓
You code
    ↓
Code Reviewer → PASS/FAIL/NEEDS_HUMAN (review gate)
    ↓
You fix issues (if needed)
    ↓
Repo Steward → Commits linked to Beads
    ↓
bd close BD-XX → Complete task, next task unblocked
```

---

## Beads Task Management

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

---

## Project Setup

### For New Projects

1. Initialize Beads: `bd init`
2. Create CLAUDE.md with your project structure and patterns
3. Run `/orchestrator goal: "first task"`

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

1. **Use Supervisor for automation:** Run `/supervisor` for fully autonomous task completion
2. **Or start with Orchestrator:** Run `/orchestrator goal: "..."` for manual control
3. **Claim tasks:** Use `bd claim BD-XX` before starting work (manual workflow)
4. **Review iteratively:** Run `/code-reviewer` multiple times as you fix issues
5. **Review gates:** Wait for PASS before moving to next task
6. **Close tasks:** Use `bd close BD-XX` when complete

### CLAUDE.md Proposal Workflow

When Code Reviewer discovers a new pattern:

1. **Flag in Beads task comment:** Pattern flagged with rationale
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
- **ai-agent-manager-plugin/skills/*.md:** Skill files for guidance

---

## For Developers

To modify or extend agents:

1. Agents are Markdown prompts in `ai-agent-manager-plugin/agents/`
2. Commands are in `ai-agent-manager-plugin/commands/`
3. Skills are in `ai-agent-manager-plugin/skills/`
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

**Beads tasks not appearing?**
- Run `bd list` to check current state
- Ensure `bd init` was run in project

**Agents suggesting wrong patterns?**
- Update CLAUDE.md with approved patterns
- Review and reject unwanted proposals

**Need help?**
- Run `/agent-help` for command reference
- Check AGENT_GUIDELINES.md for quality standards
- Check .claude-plugin/README.md for detailed command documentation
- Review agent prompts in ai-agent-manager-plugin/agents/

**Skills not showing after plugin update?**

Claude Code caches plugin contents. After restructuring skills (e.g., from `skills/core/commit.md` to `skills/commit/SKILL.md`), force a refresh:

1. Remove plugin and marketplace:
   ```
   /plugin marketplace remove ai-agent-manager-marketplace
   /plugin uninstall ai-agent-manager-plugin
   ```

2. Re-add marketplace:
   ```
   /plugin marketplace add /path/to/ai-agent-manager
   ```

3. Reinstall plugin:
   ```
   /plugin install ai-agent-manager-plugin
   ```

4. Restart Claude Code (close and reopen entirely)

5. Verify with `/skills` — should show all 30 skills under "Plugin skills"

---

## Known Limitations

### Agent Behavior
- **LLM limitations:** Agents may occasionally reference non-existent files despite validation steps. Always verify before following plans.
- **Context7 dependency:** External library lookups depend on Context7 MCP. If unavailable, agents fall back to CLAUDE.md patterns.

### Scale
- **Token usage:** Each agent invocation loads prompts (potentially 5,000-10,000 tokens overhead). Consider this for high-frequency usage.

### Git Operations
- **Main branch protection:** Repo Steward refuses commits on main/master without explicit flag.
- **No rollback:** Git operations are not automatically reversible. Use `git reflog` for manual recovery.

---

## License

MIT — See LICENSE file

---

**Happy shipping!**
