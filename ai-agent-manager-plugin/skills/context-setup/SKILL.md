---
name: context-setup
description: Standard procedure for agents to establish project context. Use when starting a new task to load CLAUDE.md, Beads state, and git history.
allowed-tools: Read, Bash, Grep
---

# Context Setup Skill

Standard procedure for all agents to establish project context before proceeding with work.

## Quick Rules

- Locate project (auto-detect CLAUDE.md)
- Load CLAUDE.md + validate freshness
- Check Beads state (`bd list`)
- Read recent git history
- Cache for entire agent session

---

## Detailed Procedure

### 1. Locate Project

- User provides path or auto-detect `CLAUDE.md` in cwd and parent directories
- If none found, ask user: "Please provide project path"
- If multiple projects exist at same level, ask which one to use

### 2. Load CLAUDE.md

```bash
# Find CLAUDE.md in current or parent directories
find . -maxdepth 3 -name "CLAUDE.md" -type f

# Read project patterns
cat CLAUDE.md
```

**Extract from CLAUDE.md:**
- Tech stack (Node.js, Python, Go, Rust, etc.)
- Framework (React, Vue, NestJS, FastAPI, etc.)
- Key patterns (architecture, conventions, testing)
- Type safety level (strict, moderate, basic)
- Test coverage threshold (≥80%, ≥70%, etc.)

### 3. Validate CLAUDE.md Freshness

Use `skills/claude-md-validation/SKILL.md`:
- Check git last-modified date (warn if > 30 days old)
- Parse optional frontmatter timestamp
- Sample 2-3 documented patterns to verify they exist in code
- Non-blocking warnings (informational only)

### 4. Check Beads State

```bash
# Sync with remote first
bd sync

# View current tasks
bd list
```

**Understand:**
- Open tasks (not started)
- In-progress tasks (currently being worked on)
- Recent completed tasks (last 3-5)
- Any blockers or dependencies

### 5. Read Recent Git History

```bash
# Last 10 commits
git log --oneline -10

# Recent branches
git branch -a --sort=-committerdate | head -5
```

**Understand:**
- What work was recently completed
- Current branch and status
- Any uncommitted changes

### 6. Cache for Session

Store this context for the entire agent session. Avoid re-reading unless explicitly needed.

---

## Output Template

Always report discovery in this format:

```markdown
## PROJECT CONTEXT

**Path:** /absolute/path/to/project
**CLAUDE.md Status:** ✓ Found | ✗ Missing (auto-detect: [tech stack])
**Architecture:** [From CLAUDE.md: e.g., React+Next.js+Tailwind, or Node+Express+Postgres]
**Key Patterns:** [2-3 most important conventions from CLAUDE.md]

**Current Beads Tasks:**
- Open: [List open issues]
- In Progress: [List in-progress issues]
- Recent Completed: [List 3 most recent closed tasks]

**Goal:** [User's stated objective]
**Refined Understanding:** [Clarifications needed? Ask questions now]
```

---

## Quality Checklist

Before proceeding with agent work:
- [ ] Project path identified (ask if not found)
- [ ] CLAUDE.md read and understood
- [ ] CLAUDE.md freshness validated (see `skills/claude-md-validation/SKILL.md`)
- [ ] Beads state checked (`bd list`)
- [ ] Recent git history reviewed
- [ ] Context reported to user in standard format
- [ ] Any ambiguities clarified with user

---

## Integration with Agents

**All agents should:**
1. Reference this skill at start: "See `skills/context-setup/SKILL.md`"
2. Load context before proceeding with agent-specific work
3. Report discovery using output template
4. Cache context for session (avoid re-reading)

**Agent-specific additions:**
- Orchestrator: Add external dependency checks (Context7 lookups)
- Code Reviewer: Add review scope determination
- Red Team Reviewer: Identify attack surface and claims

---

## See Also

- `skills/claude-md-validation/SKILL.md` - Validate CLAUDE.md freshness
- `skills/beads-workflow/SKILL.md` - Beads CLI commands
- `skills/agent-output/SKILL.md` - Standard output format
