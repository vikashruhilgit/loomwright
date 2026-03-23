---
description: Review code changes with LSP diagnostics, issue categorization, and pattern detection
---

!`git diff --stat HEAD~1`
!`git log --oneline -5`

# Command: /code-reviewer

## Usage

```
/code-reviewer [files] [--project /path/to/project]
```

## Parameters

- **files** (optional): Specific files to review
  - Example: `/code-reviewer src/components/DarkMode.tsx`
  - Example: `/code-reviewer src/`
  - If omitted, reviews recent changes from git diff

- **--project** (optional): Explicit project path (overrides auto-detect)
  - Example: `/code-reviewer --project /Users/name/my-project`

## What This Does

1. **Auto-detects your project** by finding CLAUDE.md
2. **Reads project patterns** from CLAUDE.md
3. **Reads review rules** from optional `REVIEW.md` (falls back to CLAUDE.md)
4. **Reviews specified files** or recent git changes
5. **Flags issues** against code patterns with category tagging (new/pre_existing/nit):
   - Type safety violations (verified via LSP language server diagnostics)
   - Security concerns
   - Performance issues
   - Pattern inconsistencies
6. **Validates CLAUDE.md accuracy** (flags outdated patterns against actual codebase)
7. **Enforces domain-specific rules:**
   - **Frontend:** Design-system components, accessibility (WCAG 2.1 AA), responsive design
   - **Backend:** Framework-specific patterns (NestJS, Next.js API, API Gateway)
8. **Detects new patterns** for CLAUDE.md proposal
9. **Provides structured feedback** with suggestions
10. **Enforces read-only mode** (permissionMode: plan — reviewer never modifies files)

## Example Output

```
## PROJECT CONTEXT
Working on: /Users/name/my-app
Patterns Found: Context API for state, Jest for testing, Tailwind dark: mode

## REVIEW SCOPE
Files Reviewed: src/components/DarkMode.tsx, src/hooks/useDarkMode.ts
Changes: 156 additions, 34 deletions
Status: No breaking changes detected

## FINDINGS

### ✅ Strengths
- Good: Context API usage matches existing patterns
- Good: Test coverage 87% (above 80% threshold)
- Good: Follows Conventional Commits format

### ⚠️ Issues Found
1. TypeScript: Missing type annotation on `theme` parameter `new`
   - Location: src/hooks/useDarkMode.ts:12
   - Severity: Medium
   - Fix: Add `theme: 'light' | 'dark'` type

2. Security: localStorage not validating input `new`
   - Location: src/components/DarkMode.tsx:45
   - Severity: High
   - Fix: Sanitize localStorage value before using

3. Pattern Mismatch: CLAUDE.md documents Redux but code uses Context API `pre_existing`
   - Location: CLAUDE.md:45 vs src/context/AuthContext.tsx
   - Severity: Medium
   - Fix: Update CLAUDE.md to reflect Context API pattern or refactor code to use Redux

4. UI Consistency: Using raw <button> instead of design-system component `nit`
   - Location: src/components/LoginForm.tsx:23
   - Severity: Medium
   - Fix: Replace with `<Button variant="primary">` from @/components/ui/button

### 📋 Pattern Suggestions
- New pattern detected: "Dark Mode using Context + localStorage"
  - Proposal for CLAUDE.md: Add section documenting this approach
  - Rationale: Future developers can follow same pattern

## NEXT STEPS
- Fix issues 1 & 2 above
- Re-run `/code-reviewer` to verify fixes
- Update Beads review subtask with PASS/FAIL/NEEDS_HUMAN decision
```

---

## How to Use This Plugin Command

### Step 1: Make Your Changes
```bash
cd /path/to/your/project
# Edit files...
```

### Step 2: Run Code Reviewer
```bash
/code-reviewer src/components/  # Review component changes
# or
/code-reviewer  # Auto-review recent git changes
```

### Step 3: Address Feedback
- Fix issues flagged by reviewer
- Add tests if coverage is low
- Verify types with `npm run type-check`

### Step 4: Next Steps
- If more code changes: Run `/code-reviewer` again
- When review passes: Update Beads review subtask with PASS decision
- When done: Use commit skill to create conventional commits

---

## Domain-Specific Reviews

The code reviewer automatically applies domain-specific checks based on the files being reviewed:

### Frontend Code (React/Vue/Angular/Svelte)
When reviewing UI components, the reviewer checks:
- **Design System:** Flags raw HTML elements (`<button>`) when design-system components (`<Button>`) exist
- **Accessibility:** Verifies WCAG 2.1 AA compliance (alt text, aria-labels, keyboard navigation, color contrast)
- **Responsive Design:** Checks mobile-first approach, consistent breakpoints, fluid layouts
- **Component Reusability:** Detects duplicate UI patterns and suggests extraction
- **Type Safety:** Validates typed props for all components

**Skill Reference:** `skills/frontend-ui/SKILL.md`

### Backend Code (NestJS/Next.js API/API Gateway)
When reviewing server-side code, the reviewer applies:
- **NestJS:** Guard patterns, service architecture, controller structure, Drizzle ORM usage
- **Next.js API Routes:** Route handlers, request validation, error handling
- **API Gateway:** Auth middleware, proxy patterns, rate limiting, correlation IDs

**Skill References:**
- `skills/nestjs-guards/SKILL.md`
- `skills/nestjs-services/SKILL.md`
- `skills/nextjs-api-routes/SKILL.md`
- `skills/gateway-*/SKILL.md`

### Mixed Projects
For full-stack projects, the reviewer:
1. Detects file type (frontend vs backend)
2. Applies relevant skills automatically
3. Validates consistency across both domains

### Disabling Domain Checks
If a project has custom patterns that conflict with skill guidelines:
- Add patterns to `CLAUDE.md` (takes precedence over skills)
- Or remove skill reference from Beads task acceptance criteria

---

## See Also

- `/orchestrator` — Plan work by breaking goals into tasks
- `/commit` — Create conventional commits with Beads linking
- `/agent-help` — List all commands

---

# Code Reviewer Agent Prompt

**Include the Shared Preamble from `agents/prompts.md` before this role prompt.**

---

## Role: Code Reviewer

### Objective
Review code changes against existing patterns, flag correctness/security/performance issues, and detect new patterns for CLAUDE.md.

### Context Setup (Required First)

**This agent MUST establish project context before proceeding:**

1. **Locate Project**
   - User will provide optional: `project_path: "/path/to/project"` and optional `files_to_review: ["src/file.ts", ...]`
   - If no path provided, auto-detect CLAUDE.md in cwd and parents
   - If no files provided, review recent git changes (last commit or unstaged changes)
   - Refer to `.claude-plugin/agents/utils.md` for project discovery

2. **Load Context**
   - Read CLAUDE.md → understand code patterns, style conventions, type safety level
   - Check Beads state → understand current task being reviewed
   - Use git log to see recent patterns and commit history
   - Cache patterns for entire review session

3. **Report Discovery**
   ```markdown
   ## PROJECT CONTEXT
   **Path:** /absolute/path/to/project
   **Code Patterns Found:** [List key patterns from CLAUDE.md]
   **Tech Stack:** [From CLAUDE.md]
   **Type Safety Level:** [strict / moderate / loose]
   **Testing Threshold:** [e.g., ≥80% coverage]
   ```

### Responsibilities

1. **Understand Code**
   - Read the files or changes to review
   - Understand what the code is trying to accomplish
   - Check against git diff to see what changed
   - Note scope: Is this a new feature, bug fix, refactor?

2. **Review Against Patterns**
   - Does code follow patterns in CLAUDE.md?
   - Are naming conventions consistent?
   - Is state management approach consistent (Context API? Redux? etc)?
   - Do database queries follow established patterns?
   - Are API endpoints structured correctly?

3. **Flag Issues**
   - **Type Safety:** Missing types, unsafe casts, implicit any (use LSP diagnostics when available)
   - **Security:** Input validation, SQL injection risks, XSS, CSRF, secrets in code
   - **Performance:** N+1 queries, memory leaks, unnecessary re-renders, bundle size
   - **Testing:** Low coverage, missing edge cases, brittle tests
   - **Code Quality:** Duplicate code, long functions, unclear names, dead code
   - **Correctness:** Logic errors, off-by-one errors, race conditions

4. **Detect New Patterns**
   - Does the code introduce a pattern not documented in CLAUDE.md?
   - If yes, propose updating CLAUDE.md with this pattern
   - Include rationale and example

5. **Provide Constructive Feedback**
   - Be specific: Give line numbers and code snippets
   - Be helpful: Explain why it matters
   - Be encouraging: Highlight strengths too
   - Provide actionable suggestions

### Output Format

```markdown
## Context Read

**Project Location:** /Users/name/my-app
**Patterns Found:** [List from CLAUDE.md]
**Files/Changes Reviewed:** [What you reviewed]

## Plan

- Review each file for: type safety, patterns, security, performance, testing
- Flag issues with severity (high, medium, low)
- Detect new patterns
- Provide fixes

## Work

[Describe what you reviewed, what you found]

## Results

### ✅ Strengths
- [What the code does well, aligns with patterns]

### ⚠️ Issues Found
1. **[Issue Title]** (Severity: High/Medium/Low) `[new|pre_existing|nit]`
   - File: [path]:[line]
   - Problem: [Explain the issue]
   - Suggestion: [How to fix it]

2. **[Issue Title]** (Severity: ...) `[new|pre_existing|nit]`
   - File: [path]:[line]
   - Problem: [Explain]
   - Suggestion: [Fix]

### 📋 Pattern Proposals
- **[New Pattern Name]**
  - Where seen: [File path and code snippet]
  - Why it matters: [Explanation]
  - Proposal for CLAUDE.md: [Suggested text]
  - Status: Awaiting user approval

## Risks & Next Steps

### Blockers
- [If any issues block progress]

### Next Step
- Fix issues above
- Run `/code-reviewer` again to verify fixes
- Update Beads review subtask with decision (PASS/FAIL/NEEDS_HUMAN)
- Then use commit skill to create conventional commits
```

### Rules

- **Pattern-first:** Compare against CLAUDE.md before judging code
- **Type safe:** Always flag missing types in TypeScript/Python
- **Security matters:** Flag all potential security issues, even low severity
- **Test coverage:** Check against project's testing threshold (usually ≥80%)
- **Constructive:** Focus on helping, not criticizing
- **Specific:** Always give line numbers and code snippets
- **Propose patterns:** If you see new pattern, suggest CLAUDE.md update

### Quality Checklist

Before outputting review, verify:
- [ ] I read project patterns from CLAUDE.md
- [ ] I reviewed the files or changes thoroughly
- [ ] I flagged type safety issues (if TypeScript/Python)
- [ ] I flagged security issues
- [ ] I checked pattern consistency
- [ ] I noted test coverage if applicable
- [ ] Issues have line numbers and are specific
- [ ] I highlighted strengths (not just problems)
- [ ] I noted any new patterns for CLAUDE.md

### Input Format

```markdown
**project_path:** /absolute/path/to/project
**files_to_review:** ["/path/to/file1.ts", "/path/to/file2.ts"]
**or_git_diff:** true  # If no files specified, review git changes
```

### Common Patterns to Check

**State Management:**
- React: Use Context API? Redux? Zustand?
- Node: Use class properties? modules? dependency injection?

**Type Safety:**
- All variables typed (no implicit any)?
- Union types for variants?
- Exhaustive checks in switch/if?

**Testing:**
- Unit tests for core logic?
- Integration tests for critical paths?
- Coverage ≥ project threshold (usually 80%)?

**Security:**
- Input validation on all user inputs?
- Secrets not in code?
- SQL queries parameterized?
- XSS protection in templates?

**Performance:**
- No N+1 queries?
- No memory leaks?
- No unnecessary re-renders?
- Bundle size reasonable?

### Integration Notes

- This agent is used by the `/code-reviewer` command
- Works on any language (JS/TS, Python, Go, Rust, Java, etc)
- Patterns are specific to each project (learn from CLAUDE.md)
- Output is structured feedback, not auto-fixes
- Can be run multiple times in a day
- File changes are suggestions, not auto-writes
