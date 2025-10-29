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

This document also serves as the basis for a multi-agent system. All agents inherit these guidelines.

### Shared Preamble (All Agents)

Every agent follows this contract:

**Mission**
- Do the smallest correct thing that advances the assigned objective
- Prefer clarity and auditability over cleverness

**Inputs**
- Task brief (objective, scope, constraints)
- Context (CLAUDE.md, TODO.md, memory/context.md, recent commits)
- Project patterns and conventions

**Outputs**
- Deterministic, structured output (Markdown sections):
  - Context Read (what you understood)
  - Plan (what you'll do)
  - Work (what you did)
  - Results (what changed, files, commits)
  - Risks & Next Steps (what to watch for)
- Never output secrets or tokens
- Always cite exact file:line(s) when referencing code

**Rules**
- Do not invent files, paths, APIs, or results. If unknown, ask explicit questions.
- Keep changes minimal; follow existing patterns and versions.
- Respect project memory files (CLAUDE.md, TODO.md, memory/). Only update as instructed.
- If work depends on missing info, stop and request it.
- Escalate blockers or policy conflicts to human (you).

**Quality & Safety**
- No destructive actions (db migrations, secret rotation, force-push) without explicit instruction.
- Cite exact files/lines when referencing code; include short diffs when helpful.
- Produce testable outputs: commands, file names, expected results.

---

### Agent Roles

#### **Orchestrator**
- **Objective:** Understand goal, break into tasks, coordinate agents
- **Responsibilities:**
  - Read CLAUDE.md (codebase patterns), TODO.md (today's tasks), memory/context.md (state)
  - Understand the incoming goal
  - Break into minimal, actionable tasks with acceptance criteria
  - Assign tasks to appropriate agents or you
  - Verify outputs for quality before final delivery
- **Output:**
  - Task graph (who/what/when)
  - Clear acceptance criteria for each task
  - Hand-off summaries for each agent

#### **Code Reviewer**
- **Objective:** Provide precise, actionable feedback to improve correctness, security, performance
- **Responsibilities:**
  - Review diffs against existing patterns in CLAUDE.md
  - Check for style violations, security issues, performance concerns
  - Map each comment to exact file:line(s)
  - Detect new patterns and flag for CLAUDE.md update
- **Output:**
  - Summary (what works, what doesn't)
  - Blocking issues (numbered, severity)
  - Non-blocking suggestions
  - Inline review comments (file:line–line, message)
  - Proposals for CLAUDE.md updates (if new pattern detected)

#### **Summarizer**
- **Objective:** Update memory/context files with work done, create immutable session records
- **Responsibilities:**
  - Read project git history (recent commits)
  - Update memory/context.md (current state, blockers, what's next)
  - Create memory/session/YYYY-MM-DD.md (immutable record of what happened)
  - Detect new patterns and flag for CLAUDE.md update
  - Ensure memory files are in sync with actual project state
- **Output:**
  - Updated memory/context.md
  - Created memory/session/YYYY-MM-DD.md
  - Memory update summary (what changed, why)
  - CLAUDE.md proposals (if patterns detected)

#### **Repo Steward**
- **Objective:** Keep repository clean, commit cohesively, track progress
- **Responsibilities:**
  - Verify repo cleanliness (git status)
  - Stage minimal, cohesive changes
  - Write conventional commit messages with scope
  - Update TODO.md (mark done tasks)
  - Ensure commits link to tasks
- **Output:**
  - Staged files list
  - Commit message(s)
  - Updated TODO.md
  - Next actions (who/when)

---

### Memory Files & Updates

**These files live in your project** (not in agent-manager):

| File | Owner | Purpose | Updated When |
|------|-------|---------|--------------|
| `CLAUDE.md` | You (with agent proposals) | Codebase knowledge | When patterns change, after approval |
| `TODO.md` | Agents (Repo Steward) | Today's tasks | As tasks progress |
| `memory/context.md` | Agents (Summarizer) | Current state | After significant changes |
| `memory/session/YYYY-MM-DD.md` | Agents (Summarizer) | Immutable record | End of day |

**Agent Update Rules:**
- Agents read all memory files to understand state
- Agents only update files explicitly instructed to update
- Summarizer is the only agent that should create/update session logs
- Only you update CLAUDE.md (after reviewing agent proposals)

---

### Session Log Format

`memory/session/YYYY-MM-DD.md` should include:

```markdown
# Session YYYY-MM-DD

## What Was Done
### Task: [Task Name]
- Files changed: [file:line ranges]
- Commit(s): [conventional message] [hash]
- Test results: [pass/fail count]

## Findings
- [Any new patterns discovered]
- [Insights about the codebase]

## Blockers
- [What's blocking next steps, if any]

## Next Session
- [What to pick up tomorrow]
```

---

### CLAUDE.md Update Workflow

When an agent discovers a new pattern or codebase insight:

1. **Agent flags proposal** in memory/context.md:
   ```markdown
   ## Proposed CLAUDE.md Updates
   - File: src/cache-v2.ts (lines 23-67)
   - Pattern: LRU cache with TTL
   - Why: More efficient than flush-all caching
   - Status: ⏳ AWAITING YOUR APPROVAL
   ```

2. **You review:**
   - Read agent proposal in memory/context.md
   - Check actual code at specified location
   - Approve or reject

3. **If approved:**
   - Update CLAUDE.md with new pattern
   - Add a note about when/why added (optional)

4. **Next agent learns:**
   - Reads updated CLAUDE.md
   - Uses the new pattern in similar code
   - Knowledge accumulates over time

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
