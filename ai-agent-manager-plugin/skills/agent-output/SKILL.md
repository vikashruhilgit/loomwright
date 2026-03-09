---
name: agent-output
description: Standard output format for all agents. Use to ensure consistent, structured communication with clear sections.
allowed-tools: None
version: "1.0.0"
lastUpdated: "2026-03"
---

# Agent Output Format Skill

All agents use this 5-section structure for consistent, structured output.

## Quick Rules

- Always use 5 sections: Context Read → Current State → Plan → Work/Results → Risks & Next Steps
- Use Markdown formatting with clear headers
- Include file:line references for code
- Keep sections concise but informative
- Report Beads task IDs (BD-XX) when applicable

---

## The 5-Section Structure

### 1. Context Read

**Purpose:** Show what you learned about the project

**Format:**
```markdown
## Context Read

**Project Location:** /absolute/path/to/project
**CLAUDE.md Status:** ✓ Found | ✗ Missing

**Architecture:** [Tech stack from CLAUDE.md]
**Key Patterns:**
- [Pattern 1]
- [Pattern 2]
- [Pattern 3]

**Current Beads Tasks:**
- Open: BD-X, BD-Y
- In Progress: BD-Z
- Recent: BD-W (completed 2 days ago)

**Goal:** [User's objective]
**Refined Understanding:** [What you understand needs to be done]
**Clarifications:** [Any questions? Ask now]
```

### 2. Current State

**Purpose:** Describe the starting point before work begins

**Format:**
```markdown
## Current State

**Project Status:** [Ready for work | Has blockers | Needs clarification]
**Related Work:** [Recent commits, existing Beads tasks]
**Tech Stack Relevant:** [Technologies involved in this task]
**Blockers:** [Any issues preventing progress]
```

### 3. Plan

**Purpose:** Outline the approach before executing

**Format:**
```markdown
## Plan

### Step 1: [Action]
- [Details]
- [Rationale]
- [Skill references]

### Step 2: [Action]
- [Details]
- [Dependencies]

[Continue for all steps...]

### Task Sequence
```
BD-X (Implement) → BD-Y (Review) ⇒ BD-Z (Next)
```

### Dependencies
- [What blocks what]
- [External dependencies]
```

### 4. Work/Results

**Purpose:** Report what was done (or for planning agents: "Planning only. No code changes.")

**Format:**
```markdown
## Work/Results

[For implementation agents:]
**Files Modified:**
- src/auth/jwt.guard.ts - Implemented JwtGuard (127 lines)
- src/auth/jwt.guard.test.ts - Added tests (85% coverage)

**Changes:**
- Added JwtGuard with Bearer token validation
- Extracts user payload to request.user
- Returns 401 on invalid/missing token

**Tests:** ✓ All pass | ✗ 2 failing (see details)

[For planning agents:]
This agent's work: Planning only. No code changes.
```

### 5. Risks & Next Steps

**Purpose:** Identify potential issues and provide handoff instructions

**Format:**
```markdown
## Risks & Next Steps

### Risks

| Risk | Mitigation |
|------|------------|
| [Risk 1] | [How to mitigate] |
| [Risk 2] | [How to mitigate] |

### Next Actions

**To start work:**
```bash
bd claim BD-XX  # Start next task
```

**Then follow workflow:**
1. Implement BD-XX
2. Run `/code-reviewer src/path/`
3. If PASS: `bd claim BD-YY`
4. If FAIL: Fix issues, re-review
5. Continue through chain...

### Skill References

- [Relevant skill 1]: `skills/skill-name/SKILL.md`
- [Relevant skill 2]: `skills/skill-name/SKILL.md`
```

---

## Agent-Specific Variations

### Orchestrator
- Plan section is largest (detailed Beads task structure)
- Work/Results: "Planning only. No code changes."
- Risks include external blockers

### Code Reviewer
- Plan section is review approach
- Work/Results includes decision (PASS/FAIL/NEEDS_HUMAN) and issues found
- Risks include what blocks PASS decision

### Red Team Reviewer
- Plan section is attack vectors
- Work/Results includes findings by severity (FATAL/CRITICAL/WARNING/WEAKNESS)
- Risks include false positives/negatives

---

## Quality Checklist

Before outputting:
- [ ] All 5 sections present
- [ ] File:line references for code mentions
- [ ] Beads task IDs included (BD-XX format)
- [ ] Clear next actions (which command to run next)
- [ ] Skill references for guidance
- [ ] Markdown formatting correct

---

## Examples

### Orchestrator Output (Abbreviated)

```markdown
## Context Read
**Project:** /Users/name/my-app
**Architecture:** NestJS + PostgreSQL

## Current State
**Project Status:** Ready for new task

## Plan
### BD-48: Implement JwtGuard (TASK)
- Description: Create authentication guard
- Acceptance: Token validated, 401 on invalid

### BD-49: Code Review - JwtGuard (SUBTASK)
- Decision: PASS/FAIL/NEEDS_HUMAN

## Work/Results
This agent's work: Planning only. No code changes.

## Risks & Next Steps
**To start work:**
```bash
bd claim BD-48
```
```

### Code Reviewer Output (Abbreviated)

```markdown
## Context Read
**Review Scope:** src/auth/jwt.guard.ts

## Current State
**Beads Task:** BD-49 (Code Review - JwtGuard)

## Plan
Check type safety, security, tests, patterns

## Work/Results
**Decision:** PASS

**Issues Found:** None

**Strengths:**
- Proper error handling
- Type safety with JWTPayload
- 85% test coverage

## Risks & Next Steps
**Next task:** BD-50 (Add JWT tests) now unblocked
```

---

## See Also

- `skills/context-setup/SKILL.md` - Standard context establishment
- `skills/beads-workflow/SKILL.md` - Beads CLI commands
