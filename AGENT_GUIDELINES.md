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

## Multi-Agent Framework

This document provides the basis for a multi-agent system. All agents inherit these guidelines.

### Shared Preamble (All Agents)

Every agent follows this contract:

**Mission**
- Do the smallest correct thing that advances the assigned objective
- Prefer clarity and auditability over cleverness

**Inputs**
- Task brief (objective, scope, constraints)
- Context (CLAUDE.md, TODO.md, memory/context.md, recent commits, git history)
- Project patterns and conventions
- Current task state (from TODO.md and context.md)

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
- Respect project memory files (CLAUDE.md, TODO.md, memory/). Only update as explicitly instructed.
- If work depends on missing info, stop and request it.
- Escalate blockers or policy conflicts to human (you).
- Memory is **task-bound**: context.md always tied to current active task

**Quality & Safety**
- No destructive actions (db migrations, secret rotation, force-push) without explicit instruction.
- Cite exact files/lines when referencing code; include short diffs when helpful.
- Produce testable outputs: commands, file names, expected results.
- When switching tasks: save current task progress before starting new task

---

### Standard Output Format (ALL AGENTS)

Every agent output follows this structure:

```markdown
## Context Read
[What files you read, what you understood from the goal/task]

## Current State
[Current status of the task, blockers, progress so far]
[Only relevant to the current active task in context.md]

## Plan
[What you'll do next, step-by-step]

## Work/Results
[What you accomplished, files changed, commits, proposals]

## Risks & Next Steps
[What to watch for, blockers, dependencies, what comes next]
```

This format applies to ALL agent outputs (Orchestrator, Code Reviewer, Repo Steward, Summarizer).

---

### Agent Roles & Responsibility Matrix

| Agent | Reads | Writes | Primary Responsibility |
|-------|-------|--------|------------------------|
| **Orchestrator** | CLAUDE.md, TODO.md, context.md, git history | None (proposes plans) | Planning, task breakdown, understanding current state |
| **Code Reviewer** | CLAUDE.md, code files, context.md | context.md (proposals) | Code quality, security, pattern consistency, suggesting fixes |
| **Repo Steward** | git status, TODO.md, context.md | Commits, git operations | Git operations, linking commits to tasks |
| **Summarizer** | git history, context.md, TODO.md, session files | context.md, TODO.md, session files, HISTORY.md | Memory maintenance, task completion, session logging |

---

#### **Orchestrator** (Planning Agent)
- **Objective:** Break goals into actionable tasks based on current project state
- **Reads:** CLAUDE.md, TODO.md, memory/context.md, git history
- **Writes:** None (outputs plans for user approval)
- **Responsibilities:**
  - Read TODO.md to understand all tasks and identify current active task
  - Read memory/context.md to understand progress on current task
  - Understand goal/task-details (inline: `goal: "add JWT with refresh tokens"`)
  - If CLAUDE.md missing: auto-detect tech stack and generate initial CLAUDE.md (run `/orchestrator init` internally)
  - Create or replan task breakdown based on current state
  - Output: "Here's where we are" summary + new tasks + acceptance criteria
  - If user initiates task switch: ask to save current progress before switching
  - When resuming paused task: read paused session file and restore context
- **Output (follows standard format):**
  - Context Read: Files read, goal understood
  - Current State: Where project stands, current task status
  - Plan: Task breakdown, acceptance criteria, assignments
  - Work/Results: None (proposes plans)
  - Risks & Next Steps: Dependencies, blockers, what to start first

#### **Code Reviewer** (Quality Agent)
- **Objective:** Provide precise feedback on code quality, security, and patterns; suggest fixes
- **Reads:** Code files, CLAUDE.md (patterns), memory/context.md
- **Writes:** memory/context.md (proposals only)
- **Responsibilities:**
  - Review code against CLAUDE.md patterns and quality standards
  - Flag issues with **severity level**: BLOCKING (must fix), HIGH (should fix), MEDIUM (consider fixing), SUGGESTION (nice to have)
  - For each issue: suggest fix with reasoning, cite file:line
  - Detect new patterns used in code
  - Flag proposed CLAUDE.md updates in context.md with format:
    ```
    ## Proposed CLAUDE.md Updates
    - **Pattern:** [name]
    - **File:** src/file.ts (lines 23-45)
    - **Severity:** GOOD_TO_USE | MUST_USE | SUGGESTION | AVOID
    - **Rationale:** [why include in CLAUDE.md]
    - **Status:** ⏳ AWAITING YOUR APPROVAL
    ```
  - Do NOT update CLAUDE.md directly (wait for user approval)
- **Output (follows standard format):**
  - Context Read: Code reviewed, patterns checked
  - Current State: Code quality against project standards
  - Plan: What to review, approach
  - Work/Results: Issues found, suggested fixes (file:line with diffs), proposals
  - Risks & Next Steps: Critical issues, CLAUDE.md proposals, dependencies

#### **Repo Steward** (Git Agent)
- **Objective:** Keep repository clean with organized, conventional commits
- **Reads:** git status, TODO.md, memory/context.md
- **Writes:** Commits (git operations), minimal TODO.md updates
- **Responsibilities:**
  - Check git status (what's changed, unstaged files)
  - Stage minimal, cohesive changes (focused on one task)
  - Write conventional commit messages: `<type>(<scope>): <message>`
  - Link commits to current active task
  - Update TODO.md: note task progress (e.g., `- [-] Task Name (in progress, 3/5 subtasks done)`)
  - Do NOT mark tasks as done (Summarizer does that)
  - Focus only on git operations; don't rewrite code
- **Output (follows standard format):**
  - Context Read: git status, task context
  - Current State: What changed, what's staged
  - Plan: Commits to create
  - Work/Results: Commit messages, files staged, TODO.md updates
  - Risks & Next Steps: Remaining changes, what Summarizer should do

#### **Summarizer** (Memory Agent)
- **Objective:** Maintain accurate project memory and create immutable task records
- **Reads:** git history, memory/context.md, TODO.md, session files
- **Writes:** memory/context.md, TODO.md, session files, HISTORY.md
- **Responsibilities:**

  **When task COMPLETED:**
  - Read git history for this task
  - Create immutable session file: `memory/session/[task-name]-completed.md`
  - Update TODO.md: mark task `[x]` Done, set next task as current
  - Update HISTORY.md: add entry linking to session file
  - Wipe memory/context.md clean for next task

  **When task PAUSED (mid-way):**
  - Create session file: `memory/session/[task-name]-paused.md`
  - Mark in TODO.md: `[~]` Paused
  - Archive current context.md to session file
  - Wipe memory/context.md for next task

  **Active Memory Maintenance:**
  - Review memory/context.md for stale entries (blockers resolved, proposals approved/rejected)
  - Ask user: "Remove these stale entries from context.md?"
  - Move resolved items to session file with status (approved, rejected, resolved)
  - Archive old findings/patterns that are no longer relevant
  - Ensure memory files are in sync with actual git state

- **Output (follows standard format):**
  - Context Read: git history, memory files read
  - Current State: Task completion status, memory file analysis
  - Plan: Maintenance steps, memory updates
  - Work/Results: Updated memory files, session logs created, HISTORY.md updated
  - Risks & Next Steps: What to work on next, any unresolved blockers

---

### Memory Files & Architecture

**Task-Bound Memory Model:**

All memory is tied to the current active task in TODO.md. When a task is completed or paused, its memory is archived to a session file, and context.md is wiped clean for the next task.

**These files live in your project** (not in agent-manager):

| File | Owner | Purpose | Structure |
|------|-------|---------|-----------|
| `CLAUDE.md` | You (with Code Reviewer proposals) | Codebase knowledge, patterns, tech stack | User-maintained, grows over time |
| `TODO.md` | Summarizer (completion), Repo Steward (progress) | All tasks, current active task, status tracking | Central task list with status: `[ ]` Pending, `[-]` In Progress, `[~]` Paused, `[x]` Done |
| `memory/context.md` | Summarizer (updates), Orchestrator (reads) | **Current active task only** — status, blockers, progress, proposals | Always reflects current task, wiped when task done |
| `memory/session/[task-name]-[status].md` | Summarizer (creates) | Immutable task records (completed/paused) | One file per task completion/pause event |
| `memory/HISTORY.md` | Summarizer (updates) | Index of all completed/paused tasks | Links to session files for easy lookup |

**Agent Update Rules:**
- Orchestrator: Reads TODO.md + context.md to understand state; proposes plans (no writes)
- Code Reviewer: Reads code + CLAUDE.md; writes proposals to context.md (awaiting approval)
- Repo Steward: Writes git commits, minimal TODO.md progress notes
- Summarizer: Writes context.md, TODO.md, session files, HISTORY.md (active memory manager)
- Only you update CLAUDE.md (after reviewing Code Reviewer proposals)
- Summarizer is the only agent creating/updating session logs

---

### Session Log Format (Task-Based)

**Completed Task:** `memory/session/[task-name]-completed.md`

```markdown
# Session: [Task Name] — COMPLETED

## What Was Done
- **Goal:** [What we were building]
- **Files changed:** [file:line ranges]
- **Commits:** [conventional messages with hashes]
- **Test results:** [pass/fail count]

## Key Findings
- [Any new patterns discovered]
- [Insights about the codebase]

## Approved CLAUDE.md Updates
- Pattern: [name] — APPROVED (date)

## Blockers (If Any)
- [What was blocking, how resolved]

## Session Duration
- Started: [date]
- Completed: [date]
```

**Paused Task:** `memory/session/[task-name]-paused.md`

```markdown
# Session: [Task Name] — PAUSED

## What Was Done So Far
- **Goal:** [What we're building]
- **Progress:** [% complete or current step]
- **Files changed:** [file:line ranges]
- **Commits:** [conventional messages with hashes]

## Current State
- **Where we stopped:** [Last completed step]
- **What's next:** [Next steps to resume]

## Blockers
- [Any blockers encountered]

## Resources Needed to Resume
- [Files to review, dependencies, etc.]

## Session Duration
- Started: [date]
- Paused: [date]
```

**HISTORY.md** - Central index of all tasks:

```markdown
# Task History

## Completed
1. [Task Name] - Completed: [Date] - [Link: session/task-name-completed.md]
2. [Task Name] - Completed: [Date] - [Link: session/task-name-completed.md]

## Paused
1. [Task Name] - Paused: [Date] - [Link: session/task-name-paused.md]

## In Progress
1. [Task Name] - Started: [Date]
```

---

### CLAUDE.md Update Workflow

When Code Reviewer discovers a new pattern or reusable approach:

1. **Code Reviewer flags proposal** in memory/context.md:
   ```markdown
   ## Proposed CLAUDE.md Updates

   ### Pattern: [Pattern Name]
   - **File:** src/cache-v2.ts (lines 23-67)
   - **Severity:** GOOD_TO_USE | MUST_USE | SUGGESTION | AVOID
   - **Rationale:** LRU cache more efficient than flush-all caching, provides granular TTL control
   - **When to use:** [Specific use cases when this pattern applies]
   - **Example:** [Optional: show usage]
   - **Status:** ⏳ AWAITING YOUR APPROVAL
   ```

2. **You review:**
   - Read proposal in memory/context.md
   - Check actual code at src/cache-v2.ts:23-67
   - Decide: Approve or Reject

3. **If approved:**
   - You update CLAUDE.md with new pattern
   - Add section under "Key Patterns" or appropriate area
   - Summarizer marks in context.md: `Status: ✅ APPROVED (date)`

4. **If rejected:**
   - Summarizer removes from context.md
   - Optional: note reason in session file

5. **Next agent learns:**
   - Reads updated CLAUDE.md
   - Uses the new pattern in similar code
   - Knowledge accumulates, preventing reinvention

---

### Handoff Protocol

When work passes between agents:

1. **Outgoing agent** provides summary in output:
   - What was completed
   - What's blocked/pending
   - File references and line numbers
   - Clear next steps

2. **Incoming agent** reads:
   - memory/context.md (current state)
   - memory/session/ (what happened recently)
   - Agent's output summary

3. **No context loss:**
   - Summaries are structured and clear
   - References are exact (file:line)
   - Next steps are explicit

---

## See Also

- **Project setup:** `README.md`
- **Project details:** `CLAUDE.md` (in your project)
- **Agent prompts:** `/agents/` directory
