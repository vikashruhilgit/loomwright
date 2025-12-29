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

This format applies to ALL agent outputs (Orchestrator, Code Reviewer, Repo Steward, Red Team Reviewer).

---

### Agent Roles & Responsibility Matrix

| Agent | Reads | Writes | Primary Responsibility |
|-------|-------|--------|------------------------|
| **Orchestrator** | CLAUDE.md, Beads state, git history | Beads tasks (proposes) | Planning, task breakdown with review gates |
| **Code Reviewer** | CLAUDE.md, code files, Beads task | Beads comments (review decisions) | Code quality, security, PASS/FAIL/NEEDS_HUMAN |
| **Repo Steward** | git status, Beads task | Commits (git operations) | Git operations, linking commits to Beads |
| **Red Team Reviewer** | CLAUDE.md, code files, Context7 docs | Audit report | Adversarial review, find production failures |

---

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

#### **Repo Steward** (Git Agent)
- **Objective:** Keep repository clean with organized, conventional commits
- **Reads:** git status, Beads task context
- **Writes:** Commits (git operations) with Beads linking
- **Responsibilities:**
  - Check git status (what's changed, unstaged files)
  - Stage minimal, cohesive changes (focused on one task)
  - Write conventional commit messages: `<type>(<scope>): <message>`
  - Link commits to Beads tasks: `Closes BD-XX` or `Refs BD-XX`
  - Focus only on git operations; don't rewrite code
- **Output (follows standard format):**
  - Context Read: git status, Beads task context
  - Current State: What changed, what's staged
  - Plan: Commits to create
  - Work/Results: Commit messages with Beads links
  - Risks & Next Steps: Remaining changes, task completion

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
| `skills/commit/SKILL.md` | Conventional commits with Beads linking |
| `skills/quality-checklist/SKILL.md` | Review gate criteria |
| `skills/pattern-detector/SKILL.md` | CLAUDE.md pattern proposals |
| `skills/nestjs-*/SKILL.md` | NestJS implementation patterns |
| `skills/nextjs-*/SKILL.md` | Next.js implementation patterns |
| `skills/gateway-*/SKILL.md` | API Gateway patterns |
| `skills/context7-lookup/SKILL.md` | External library docs lookup |

---

## See Also

- **Project setup:** `README.md`
- **Project details:** `CLAUDE.md` (in your project)
- **Agent prompts:** `ai-agent-manager-plugin/agents/` directory
- **Skills:** `ai-agent-manager-plugin/skills/` directory
