---
name: context-setup
description: Standard procedure for agents to establish project context. Use when starting a new task to load CLAUDE.md, Beads state, and git history.
allowed-tools: Read, Bash, Grep
version: "1.0.0"
lastUpdated: "2026-03"
---

# Context Setup Skill

Standard procedure for all agents to establish project context before proceeding with work.

## Quick Rules

- Locate project (auto-detect CLAUDE.md)
- Load CLAUDE.md + validate freshness
- Check Beads state (`bd list`) — **only if `.beads/` is present AND `bd --version` succeeds**
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

### 4. Check Beads State (conditional)

**Run detection first:**
```bash
test -d .beads && bd --version >/dev/null 2>&1
```

**If detection succeeds (Beads is active):**
```bash
# Sync with remote first
bd sync

# View current tasks
bd list
```

Understand:
- Open tasks (not started)
- In-progress tasks (currently being worked on)
- Recent completed tasks (last 3-5)
- Any blockers or dependencies

**If detection fails (Beads is not active):**
- Skip this step entirely. Do NOT synthesize a fake Beads section.
- Task source is the invocation argument, Supervisor-Ready Brief, or equivalent.

### 4.5. Detect Brain (optional, on-demand)

Detect whether a knowledge brain is reachable for graph-backed structural context:

```bash
# Either signal counts; neither present is the common case.
test -e graphify-out/graph.json && echo "GRAPH_PRESENT"
[ -n "$AI_AGENT_MANAGER_BRAIN_ROOT" ] && test -d "$AI_AGENT_MANAGER_BRAIN_ROOT/wiki" && echo "BRAIN_ROOT_PRESENT"
```

If a brain is detected, agents **MAY** read `${CLAUDE_PLUGIN_ROOT}/skills/brain-context/SKILL.md` on-demand to enrich
codebase/blast-radius understanding from the Graphify graph + brain wiki. This is **advisory and
fails SAFE** — it never blocks, gates, or changes a decision, and (per that skill's staleness rule)
the graph is authoritative only for committed code, never for files this session will edit. Absent a
brain (neither signal present — the default), **skip this step silently**; behave exactly as today.
The skill is deliberately **not** preloaded into any agent's `skills:` list (mirrors `self-heal-advisory`).

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
**Task Source:** Beads | Supervisor-Ready Brief | Invocation argument

**Current Beads Tasks:** (include this block only if Beads is active)
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
- [ ] Task source identified (Beads state if available, otherwise invocation scope)
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

- `skills/brain-context/SKILL.md` - Read-on-demand brain-aware context enrichment (consulted when a brain is detected)
- `skills/claude-md-validation/SKILL.md` - Validate CLAUDE.md freshness
- `skills/beads-workflow/SKILL.md` - Beads CLI commands
- `skills/agent-output/SKILL.md` - Standard output format
