# AGENT_GUIDELINES.md

Comprehensive guidance for AI agents working on any project. Apply these standards before coding.

---

## Core Principles (Priority Order)

1. **Quality First** - Thorough, well-tested, correct solutions; proven approaches over shortcuts
2. **Surgical Changes** - Only modify what's necessary; fix one thing at a time
3. **Pattern Consistency** - Use existing patterns; learn codebase before implementing
4. **Type Safety** - Strictest checking; no implicit `any`; equivalent rigor per language
5. **Security** - No secrets/PII in code/logs; validate inputs; clear, auditable decisions
6. **Performance** - Profile before/after; document tradeoffs; optimize bottlenecks

---

## Pre-Task Analysis (REQUIRED)

### Assessment
- [ ] Understand project structure, exact framework versions, build/test/lint tools
- [ ] Framework conventions, version-specific features, deprecations
- [ ] Existing patterns for similar problems, reusable components, utilities
- [ ] What depends on changes; breaking changes; backward compatibility
- [ ] Exact requirements, acceptance criteria, performance/security needs

---

## Implementation Standards

### Type Safety & Code Style
- Use strictest type checking; explicit types for all functions
- Follow codebase naming, import patterns, error handling, logging
- Framework-specific conventions (routing, components, state management)
- For non-typed languages: enable all linting rules, use validators

### Testing & Coverage
- Unit tests for new functionality, edge cases, error scenarios
- ≥ 80% line coverage (or repo-defined threshold)
- Integration tests for dependencies; no implementation-detail tests
- Pre-commit: format, lint, type-check pass locally

### Documentation
- Comments explain "why" not "what"; JSDoc for public APIs
- Update README/architecture docs for features
- Document breaking changes separately

### Security & Logging
- No secrets, tokens, PII in code/commits/logs; use environment variables
- Validate all inputs; sanitize per context (SQL, HTML, shell)
- Log with context (user ID, request ID) without sensitive data
- Error messages: user-facing (clear) and internal (detailed)

### Performance
- Profile; use appropriate data structures; cache expensive computations
- Avoid unnecessary re-evaluations; document tradeoffs
- Identify and test critical paths

---

## Verification Checklist (Before Completion)

- [ ] Tests pass; no linting/type errors
- [ ] Code follows patterns; changes minimal and focused
- [ ] Coverage ≥ 80%; no regressions
- [ ] No secrets, debug code, console.logs, commented lines
- [ ] Docs/comments updated; breaking changes documented
- [ ] `git status` clean; commit message follows conventions
- [ ] Input validation in place; no performance regressions

---

## Language-Specific Standards

| Language | Type Safety | Testing | Linting |
|----------|-------------|---------|---------|
| **TypeScript** | `strict: true`, no `any` | Jest/Vitest | ESLint |
| **JavaScript** | JSDoc types or TypeScript | Jest/Vitest | ESLint |
| **Python** | Type hints (mypy strict) | pytest | pylint/flake8 |
| **Go** | Static typing | go test | golangci-lint |
| **Rust** | Strict type system | cargo test | clippy |
| **Java** | Static typing | JUnit | checkstyle |

**Apply equivalent strictness—type safety, linting, testing, build checks—for all languages.**

---

## Conventional Commits

`<type>(<scope>): <message>` — `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `security`

- Minimal, cohesive changes; one logical change per commit
- Clear intent; reference issue/PR when applicable
- No secrets or sensitive data

**Examples:**
```
feat(auth): add JWT refresh token rotation
fix(api): handle null response in user service
refactor(components): extract reusable Button
```

---

## Common Anti-Patterns ❌

**Code:** Don't refactor unrelated code; invent new patterns; ignore type errors; leave debug code/console.logs; commit secrets

**Testing:** Don't skip tests; test implementation details; lower coverage to pass checks

**Scope:** Don't upgrade dependencies unnecessarily; make breaking changes without migration; modify unrelated code

**Docs/Logging:** Don't skip API docs; add noisy logging; log secrets; leave obscure comments

---

## Task-Specific Guidance

### Bug Fixes
1. Reproduce and understand the bug (root cause, not symptom)
2. Implement minimal fix; add test; verify no regressions
3. Document the fix if non-obvious

### New Features
1. Analyze requirements and existing patterns
2. Design to fit architecture; implement using established patterns
3. Write comprehensive tests; document APIs and breaking changes

### Code Review
1. Run static analysis; check type safety, patterns, coverage
2. Review security implications; suggest improvements with rationale

### Refactoring
- Only when solving a specific problem; maintain backward compatibility
- Keep changes small; verify tests pass after each change

### Security Fixes
- Patch immediately for critical issues; add verification tests
- Document vulnerability and fix; verify no regressions

---

## Escalation Triggers

Stop work and escalate if:
- Requirements ambiguous or context missing
- Version conflicts or breaking changes affect scope
- Security or compliance concerns arise
- Scope significantly exceeds budget

**Action:** Propose minimal viable slice; request approval; include risk assessment.

---

## Questions to Ask Before Starting

1. Exact problem and requirement?
2. Scope—fix X only or improve related code?
3. Performance or security considerations?
4. Backward compatibility required?
5. Specific existing pattern to follow?
6. Success criteria?
7. Version constraints?
8. Who reviews/approves?

---

## Common Commands (Fill In Per Project)

```bash
# Build
[command]

# Test (all / single file)
[command] / [command]

# Lint / Type check
[command] / [command]

# Develop / Pre-commit check
[command] / [command]
```

---

## Multi-Agent Framework (Beads-Integrated)

This document provides the basis for a multi-agent system. All agents inherit these guidelines and use **Beads issue tracker** for task management.

### Agent Frontmatter Conventions

Every agent markdown file includes YAML frontmatter that configures Claude Code native behavior:

```yaml
---
name: ai-agent-manager-plugin:{role}    # Unique agent identifier
description: {1-2 sentence purpose}      # Shown in /agents menu
tools: Read, Write, Edit, Bash, ...      # Tool restrictions (security)
model: opus | haiku | inherit            # Model selection (cost/capability)
maxTurns: N                              # API round-trip limit (optional)
memory: project                          # Persistent memory (optional)
skills:                                  # Pre-loaded skill content (optional)
  - skill-name
---
```

**Frontmatter Principles:**
- **Tool restrictions enforce safety:** Workers can't spawn subagents (no Task tool), Context-Keeper can't run Bash
- **Model selection matches task complexity:** haiku for simple state writes, opus for orchestration, inherit for user's choice
- **Memory accumulates knowledge:** Code Reviewer and Red Team build institutional memory across sessions
- **Skills preloading eliminates latency:** Referenced skills are injected at spawn time (no file reads needed)

### Persistent Memory Patterns

Agents with `memory: project` store knowledge in `.claude/agent-memory/{agent-name}/`:

**What to store:**
- Recurring code patterns discovered during reviews
- Domain terminology and conventions learned
- Past vulnerabilities and attack patterns found
- Stakeholder preferences and project-specific rules

**What NOT to store:**
- Session-specific state (use `.supervisor/` for that)
- Secrets, tokens, or PII
- Temporary debugging notes
- Information already in CLAUDE.md

**Agents with persistent memory:**
| Agent | What It Remembers |
|-------|-------------------|
| Code Reviewer | Review patterns, recurring issues, codebase conventions |
| Red Team Reviewer | Past vulnerabilities, attack patterns, what was already audited |
| Product Owner | Domain context, terminology, stakeholder preferences |

### Plugin Hooks (Quality Gates)

The `hooks/hooks.json` file defines automatic quality gates:

| Hook | Trigger | Validation |
|------|---------|------------|
| SubagentStop (worker) | Worker agent completes | WORKER_RESULT block present, files modified, no unresolved errors |
| TaskCompleted | Task marked complete | Task genuinely done, not abandoned or skipped |

Hooks use prompt-based validation (fast haiku model, 30s timeout). They enforce quality without spawning extra subagents.

### Shared Preamble (All Agents)

Every agent follows this contract:

**Mission**
- Do the smallest correct thing that advances the assigned objective
- Prefer clarity and auditability over cleverness

**Inputs**
- Task brief (objective, scope, constraints)
- Context (CLAUDE.md, Beads issue tracker state, recent commits, git history)
- Project patterns and conventions
- Current task state (from Beads issue tracker)

**Outputs**
- Deterministic, structured Markdown output following standard format:
  1. **Context Read** — What you understood from files/goal
  2. **Current State** — Where we are, what's relevant to this task
  3. **Plan** — What you'll do, step-by-step
  4. **Work/Results** — What you did, files changed, commits, proposals
  5. **Risks & Next Steps** — What to watch for, blockers, what comes next
- Never output secrets or tokens
- Always cite exact file:line(s) when referencing code

**Rules**
- Do not invent files, paths, APIs, or results. If unknown, ask explicit questions.
- Keep changes minimal; follow existing patterns and versions.
- Use Beads issue tracker for task management (no TODO.md or memory files)
- If work depends on missing info, stop and request it.
- Escalate blockers or policy conflicts to human (you).

**Quality & Safety**
- No destructive actions (db migrations, secret rotation, force-push) without explicit instruction.
- Cite exact files/lines when referencing code; include short diffs when helpful.
- Produce testable outputs: commands, file names, expected results.

**Git Worktree Safety**
- Workers operate ONLY within their assigned worktree path.
- Never modify files in the main worktree from a worker worktree.
- Worktrees are created as sibling directories: `../{project}-{subtask_id}`.
- All worktrees MUST be cleaned up in FINALIZE phase (no orphans).
- If worktree creation fails, fall back to sequential execution.
- Never force-resolve merge conflicts — escalate to human.

---

### Standard Output Format (ALL AGENTS)

Every agent output follows this structure:

```markdown
## Context Read
[What files you read, what you understood from the goal/task]

## Current State
[Current Beads tasks: open, in-progress, blocked]
[Current task being worked on]

## Plan
[What you'll do next, step-by-step]

## Work/Results
[What you accomplished, files changed, commits, proposals]

## Risks & Next Steps
[What to watch for, blockers, dependencies, what comes next]
```

This format applies to ALL agent outputs (Orchestrator, Code Reviewer, Red Team Reviewer).

---

### Agent Roles & Responsibility Matrix

| Agent | Reads | Writes | Primary Responsibility |
|-------|-------|--------|------------------------|
| **Supervisor** | CLAUDE.md, state file, git state | Worker dispatch, PR creation | Parallel orchestration, 6-phase workflow |
| **Context-Keeper** | State file | State file (sole writer) | Externalized state management |
| **Worker** | Code files in worktree | Code files in worktree | Isolated implementation in git worktrees |
| **Orchestrator** | CLAUDE.md, Beads state, git history | Beads tasks (proposes) | Planning, task breakdown with review gates |
| **Code Reviewer** | CLAUDE.md, code files, Beads task | Beads comments (review decisions) | Code quality, security, PASS/FAIL/NEEDS_HUMAN |
| **Red Team Reviewer** | CLAUDE.md, code files, Context7 docs | Audit report | Adversarial review, find production failures |

---

#### **Supervisor** (Parallel Orchestrator — v3)
- **Objective:** Autonomously manage complete workflow with parallel execution
- **Reads:** CLAUDE.md, `.supervisor/state.md`, git state, Beads state (optional)
- **Writes:** Worker dispatches, PR creation, `.supervisor/` directory
- **Responsibilities:**
  - Run 6-phase workflow: INIT → ACQUIRE → PLAN → EXECUTE → FINALIZE → LOOP
  - Create feature branch BEFORE any code work (mandatory)
  - Analyze parallelism and dispatch workers via git worktrees
  - Poll background workers and reviewers (non-blocking)
  - Sequential merge of worktree branches into feature branch
  - Checkpoint state after every phase transition
  - Use `.supervisor/` for state management; delegate Phase 3 to Execute Manager
- **Safety:**
  - Never force-resolve merge conflicts — escalate to human
  - Never proceed to PLAN without confirmed feature branch
  - Clean up all worktrees in FINALIZE (no orphans)
  - Exit gracefully at tool call budget limit

#### **Context-Keeper** (State Management Agent)
- **Objective:** Manage externalized Supervisor state file
- **Reads:** `{scratchpad}/supervisor-state.md`, `.supervisor/state.md`
- **Writes:** State file (sole writer — no other agent mutates it)
- **Responsibilities:**
  - Initialize, update, and checkpoint state file
  - Record worker results, review decisions, errors
  - Maintain state file schema integrity
  - Return < 50 token confirmations
- **Safety:**
  - Never modify code files — only state file
  - Never spawn other agents
  - Validate state file before writing

#### **Worker** (Implementation Worker)
- **Objective:** Implement a single subtask in an isolated git worktree
- **Reads:** Code files within assigned worktree
- **Writes:** Code files within assigned worktree only
- **Responsibilities:**
  - Implement subtask meeting acceptance criteria
  - Run tests if infrastructure exists
  - Output structured WORKER_RESULT block
  - Handle retry context on re-dispatch
- **Safety:**
  - Never modify files outside assigned worktree path
  - Never perform git operations (Supervisor handles git)
  - Never spawn other agents
  - Never access the Supervisor state file

#### **Orchestrator** (Planning Agent)
- **Objective:** Break goals into Beads tasks with built-in review gates
- **Reads:** CLAUDE.md, Beads state (`bd list`), git history
- **Writes:** Beads tasks (EPIC → TASK → SUBTASK structure)
- **Responsibilities:**
  - Run `bd list` to understand current open/in-progress tasks
  - Understand goal/task-details (inline: `goal: "add JWT with refresh tokens"`)
  - If CLAUDE.md missing: auto-detect tech stack, suggest initial structure
  - Create Beads tasks with clear subtasks for implementation + review
  - Every implementation task gets a review subtask (quality gate)
  - Reference relevant skill files for guidance
  - Output: Context summary + Beads task structure + skill references
- **Output (follows standard format):**
  - Context Read: CLAUDE.md, Beads state, goal understood
  - Current State: Open/in-progress tasks, blockers
  - Plan: Beads task structure (EPIC → TASK → SUBTASK)
  - Work/Results: Tasks created with dependencies
  - Risks & Next Steps: What to claim first, blockers

#### **Code Reviewer** (Quality Agent)
- **Objective:** Provide precise feedback; output PASS/FAIL/NEEDS_HUMAN decision
- **Reads:** Code files, CLAUDE.md (patterns), Beads task context
- **Writes:** Beads comments (review decisions)
- **Responsibilities:**
  - Review code against CLAUDE.md patterns and quality standards
  - Flag issues with **severity level**: BLOCKING, HIGH, MEDIUM, LOW
  - For each issue: suggest fix with reasoning, cite file:line
  - Detect new patterns used in code
  - Output review decision: **PASS** / **FAIL** / **NEEDS_HUMAN**
  - NEEDS_HUMAN creates dependent bug issues in Beads
  - Propose CLAUDE.md updates via Beads task comments
- **Output (follows standard format):**
  - Context Read: Code reviewed, patterns checked
  - Current State: Code quality against project standards
  - Plan: What to review, approach
  - Work/Results: Issues found, decision (PASS/FAIL/NEEDS_HUMAN)
  - Risks & Next Steps: Critical issues, CLAUDE.md proposals

#### **Red Team Reviewer** (Adversarial Agent)
- **Objective:** Attack assumptions, find real-world failures before production
- **Reads:** CLAUDE.md, code files, Context7 docs
- **Writes:** Audit report (findings by severity)
- **Responsibilities:**
  - Identify attack surface (entry points, trust boundaries)
  - Reality-check claims using Context7 against current docs
  - Explore 6 attack vectors: core flaws, operational failures, security, scale, human factors, integration
  - Report findings by severity: FATAL, CRITICAL, WARNING, WEAKNESS
  - Provide prioritized fixes by real-world impact
- **Output:**
  - Attack Surface Analysis
  - Findings by Severity
  - Top 3 Fatal Issues
  - What Would Convince Hostile Expert
  - Prioritized Fixes

---

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

**Project Files:**
```
your-project/
├── CLAUDE.md           # Codebase knowledge, patterns (user-maintained)
└── .beads/             # Beads issue tracker (auto-managed)
    └── issues/         # Issue files
```

---

### CLAUDE.md Update Workflow

When Code Reviewer discovers a new pattern:

1. **Code Reviewer flags proposal** in Beads task comment:
   ```markdown
   ## Proposed CLAUDE.md Update
   - **Pattern:** [Pattern Name]
   - **File:** src/cache-v2.ts (lines 23-67)
   - **Rationale:** [Why include in CLAUDE.md]
   - **Status:** ⏳ AWAITING YOUR APPROVAL
   ```

2. **You review:**
   - Read proposal in Beads task
   - Check actual code at referenced file:line
   - Decide: Approve or Reject

3. **If approved:**
   - You update CLAUDE.md with new pattern
   - Add section under "Key Patterns" or appropriate area

4. **Next agent learns:**
   - Reads updated CLAUDE.md
   - Uses the new pattern in similar code
   - Knowledge accumulates, preventing reinvention

---

### Skill References

Agents reference skill files for guidance (don't embed content):

| Skill | Purpose |
|-------|---------|
| `skills/async-orchestration/SKILL.md` | Parallel dispatch and git worktree patterns |
| `skills/state-management/SKILL.md` | State file schema and checkpoint protocols |
| `skills/workflow-management/SKILL.md` | 6-phase workflow patterns |
| `skills/commit/SKILL.md` | Conventional commits with Beads linking |
| `skills/quality-checklist/SKILL.md` | Review gate criteria |
| `skills/context-summarization/SKILL.md` | Output compression patterns |
| `skills/pattern-detector/SKILL.md` | CLAUDE.md pattern proposals |
| `skills/nestjs-*/SKILL.md` | NestJS implementation patterns |
| `skills/nextjs-*/SKILL.md` | Next.js implementation patterns |
| `skills/gateway-*/SKILL.md` | API Gateway patterns |
| `skills/context7-lookup/SKILL.md` | External library docs lookup |
| `skills/agent-teams/SKILL.md` | Agent Teams patterns (experimental) |
| `hooks/hooks.json` | Plugin quality gate hooks |

---

## See Also

- **Project setup:** `README.md`
- **Project details:** `CLAUDE.md` (in your project)
- **Agent prompts:** `ai-agent-manager-plugin/agents/` directory
- **Skills:** `ai-agent-manager-plugin/skills/` directory
