---
name: user-story-writing
description: Write clear user stories with testable acceptance criteria. Use for requirements definition and feature scoping.
allowed-tools: [Read]
version: "1.0.0"
lastUpdated: "2026-03"
---

# User Story Writing Skill

Write clear, actionable user stories with testable acceptance criteria following the INVEST principles.

## Quick Rules

- Format: "As a [specific role], I want [capability], so that [business value]"
- Acceptance criteria use Given/When/Then format
- Include edge cases and error scenarios
- Stories must be Independent, Negotiable, Valuable, Estimable, Small, Testable (INVEST)
- One story = one user goal (not multiple features bundled)

## When to Use This Skill

- Use when defining new features or requirements
- Use when breaking down epics into stories
- Use when documenting acceptance criteria
- Do NOT use for technical tasks (use Beads tasks instead)

## Story Template

```markdown
**BD-XX: [Story Title]** (type: story)

**As a** [specific role with context],
**I want** [specific capability or action],
**so that** [measurable business value or outcome].

### Acceptance Criteria

**Happy Path:**
- [ ] Given [precondition], when [action], then [expected outcome]
- [ ] Given [valid input], when [submitted], then [success response]

**Edge Cases:**
- [ ] Given [boundary condition], when [action], then [graceful handling]
- [ ] Given [empty/null input], when [submitted], then [appropriate validation]

**Error Scenarios:**
- [ ] Given [invalid state], when [action], then [clear error message]
- [ ] Given [system unavailable], when [action], then [fallback behavior]

### Priority
- [ ] MVP - Core functionality, must ship
- [ ] Phase 2 - Important but not blocking launch
- [ ] Nice-to-have - Future consideration

### Assumptions
- [Assumption 1 that needs validation]
- [Assumption 2 about user behavior or system state]

### Dependencies
- Depends on: [Other stories or systems]
- Blocks: [Stories that depend on this]

### Risks
- [What could go wrong or cause delays]

### Success Metrics
- [How we measure if this story delivered value]

### Handoff
Ready for: `/orchestrator goal: "BD-XX"`
```

## Example: Staff Scheduling Story

```markdown
**BD-15: Staff Shift Assignment** (type: story)

**As a** Staff Supervisor at a sports venue,
**I want** to assign staff members to shifts for upcoming events,
**so that** I have adequate coverage and can manage labor costs.

### Acceptance Criteria

**Happy Path:**
- [ ] Given an upcoming event, when I open shift assignment, then I see available staff and open shifts
- [ ] Given a staff member and open shift, when I assign them, then the shift shows as filled
- [ ] Given a completed assignment, when I save, then staff receives notification

**Edge Cases:**
- [ ] Given a staff member already assigned elsewhere, when I try to double-book, then I see a conflict warning
- [ ] Given no available staff, when I view shifts, then I see "understaffed" indicator

**Error Scenarios:**
- [ ] Given an event in the past, when I try to assign, then I see "cannot modify past events" error
- [ ] Given network failure during save, when assignment fails, then draft is preserved locally

### Priority
- [x] MVP - Core functionality, must ship

### Assumptions
- Staff availability is already entered in the system
- Events are created before shift assignment begins
- One staff member can work one shift per time slot

### Dependencies
- Depends on: BD-12 (Event Creation), BD-14 (Staff Profile Management)
- Blocks: BD-18 (Payroll Integration)

### Risks
- Complex conflict detection may need Phase 2 refinement
- Notification delivery depends on third-party service

### Success Metrics
- 90% of shifts filled 48 hours before event
- < 5% double-booking conflicts reported

### Handoff
Ready for: `/orchestrator goal: "BD-15"`
```

## Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| "As a user..." | Too vague, no context | "As a Staff Supervisor at a venue..." |
| Technical language | Not user-focused | Describe outcomes, not implementation |
| Multiple features | Violates "Small" principle | Split into separate stories |
| Missing acceptance criteria | Untestable | Always include Given/When/Then |
| No business value | "...so that it works" | State measurable outcome |
| Implementation details | "...using React hooks" | Focus on what, not how |

## Acceptance Criteria Patterns

### Form Validation
```markdown
- [ ] Given invalid email format, when submitted, then show "Please enter valid email"
- [ ] Given missing required field, when submitted, then highlight field with error
- [ ] Given all valid inputs, when submitted, then proceed to next step
```

### List/Search Features
```markdown
- [ ] Given matching results exist, when searching, then show paginated results
- [ ] Given no results, when searching, then show "No results found" with suggestions
- [ ] Given large result set (>100), when loading, then show first page with "Load more"
```

### CRUD Operations
```markdown
- [ ] Given valid data, when creating, then item appears in list immediately
- [ ] Given item exists, when updating, then changes persist after refresh
- [ ] Given item has dependencies, when deleting, then show confirmation with impact
```

## Quality Checklist

Before finalizing a story:
- [ ] Role is specific (not generic "user")
- [ ] Capability is one discrete action
- [ ] Business value is measurable
- [ ] Acceptance criteria cover happy path
- [ ] Edge cases identified
- [ ] Error scenarios defined
- [ ] Priority assigned (MVP/Phase 2/Nice-to-have)
- [ ] Assumptions made explicit
- [ ] Dependencies listed
- [ ] Risks identified
- [ ] Story is estimable (not too vague, not too large)

## See Also

- `skills/mvp-scoping/SKILL.md` - Prioritization framework
- `skills/product-discovery/SKILL.md` - Discovery before requirements
- `skills/domain-knowledge/SKILL.md` - Adding domain context to CLAUDE.md

