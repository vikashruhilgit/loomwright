---
name: product-discovery
description: Understand business problems before defining solutions. Use at start of feature work or when requirements are unclear.
allowed-tools: [Read]
---

# Product Discovery Skill

Framework for understanding business problems before jumping to solutions. Ensures we build the right thing.

## Quick Rules

- Ask "why" at least 3 times before "what"
- Identify the user and their actual goal
- Understand current state vs desired state
- Define success metrics before solutions
- Validate assumptions explicitly

## When to Use This Skill

- Use at the start of any new feature work
- Use when requirements feel vague or incomplete
- Use when stakeholders disagree on approach
- Use when you're not sure what problem you're solving
- Do NOT skip this to "move faster" (you'll move slower)

## Discovery Framework

### Phase 1: Problem Understanding

Ask these questions to understand the problem:

```markdown
## Problem Discovery

### What problem are we solving?
[Describe the problem in user terms, not solution terms]

### Who experiences this problem?
- Primary user: [Role and context]
- Secondary users: [Other affected parties]
- Frequency: [How often do they encounter this?]

### How do they solve it today?
- Current workaround: [What they do now]
- Pain points: [What's frustrating about current approach]
- Time/cost: [Effort spent on workaround]

### What's the cost of NOT solving it?
- User impact: [Frustration, lost time, errors]
- Business impact: [Lost revenue, churn, support costs]
- Urgency: [Why now vs later?]
```

### Phase 2: User Context

Understand the user deeply:

```markdown
## User Context

### Who is the primary user?
- Role: [Job title/function]
- Context: [Environment, constraints, pressures]
- Technical skill: [Novice/intermediate/expert]
- Frequency of use: [Daily/weekly/monthly]

### What is their goal?
- Immediate goal: [What they're trying to do right now]
- Underlying goal: [Why they're doing it]
- Ultimate goal: [What success looks like for them]

### What's their workflow today?
1. [Step 1 - trigger]
2. [Step 2 - action]
3. [Step 3 - current friction point]
4. [Step 4 - completion]

### What frustrates them most?
- Pain point 1: [Description and impact]
- Pain point 2: [Description and impact]
- "If only I could...": [User's wish]
```

### Phase 3: Success Definition

Define what success looks like before building:

```markdown
## Success Definition

### How will we know this is successful?
- Leading indicator: [Early signal of success]
- Lagging indicator: [Long-term measure]

### What metrics matter?
| Metric | Current | Target | Timeline |
|--------|---------|--------|----------|
| [Metric 1] | [Baseline] | [Goal] | [When] |
| [Metric 2] | [Baseline] | [Goal] | [When] |

### What does "done" look like?
- Minimum success: [Bare minimum outcome]
- Target success: [Expected outcome]
- Stretch success: [Best case outcome]

### What would make this a failure?
- [Scenario 1 that indicates failure]
- [Scenario 2 that indicates failure]
```

### Phase 4: Constraints

Understand what limits the solution space:

```markdown
## Constraints

### What can't change?
- Technical: [Legacy systems, integrations, performance requirements]
- Business: [Regulations, contracts, existing commitments]
- Organizational: [Team size, skills, priorities]

### What's the timeline pressure?
- Hard deadline: [Date and why it's hard]
- Soft deadline: [Preferred date]
- Dependencies: [What's waiting on this]

### What resources are available?
- Team: [Who's working on this]
- Budget: [If relevant]
- External dependencies: [Third parties, approvals needed]

### What are we NOT solving?
- Out of scope: [Explicitly excluded]
- Future consideration: [Deferred intentionally]
```

## Output: Problem Statement

Synthesize discovery into a clear problem statement:

```markdown
## Problem Statement

**Problem:** [Who] needs [what capability] because [why/pain point].

**Current State:** Today, they [current workaround], which causes [pain/cost].

**Desired State:** They should be able to [desired outcome] so that [business value].

**Success Metric:** We'll know we've solved this when [measurable outcome].

**Constraints:** We must [constraint 1] and cannot [constraint 2].

**Out of Scope:** This does NOT include [excluded items].
```

## Example: Staff Scheduling Discovery

```markdown
## Problem Statement

**Problem:** Staff Supervisors at sports venues need to assign workers to
event shifts because they're currently managing this in spreadsheets,
leading to double-bookings and last-minute scrambles.

**Current State:** Today, they email availability requests, manually check
calendars, and update a shared spreadsheet. This takes 3-4 hours per event
and results in ~15% of shifts having conflicts discovered day-of.

**Desired State:** They should be able to see staff availability, assign
shifts, and get automatic conflict detection so that they can complete
scheduling in under 30 minutes with zero conflicts.

**Success Metric:** We'll know we've solved this when:
- Average scheduling time drops from 3.5 hours to 30 minutes
- Day-of conflicts drop from 15% to <1%
- Supervisor satisfaction score increases from 2.3 to 4.0

**Constraints:**
- Must integrate with existing payroll export format
- Cannot change how staff submit availability (separate system)
- Must work on tablet devices (supervisors are mobile)

**Out of Scope:**
- Payroll calculation (handled by external system)
- Staff availability entry (separate project)
- Automated scheduling suggestions (Phase 2)
```

## Discovery Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| "Users want X feature" | Solution, not problem | "Users struggle with Y" |
| Skipping to solutions | May solve wrong problem | Complete discovery first |
| Assuming you know the user | Your assumptions may be wrong | Validate with real users |
| No success metrics | Can't measure impact | Define before building |
| Vague problem statement | Everyone interprets differently | Be specific and concrete |
| Scope creep during discovery | Discovery never ends | Time-box discovery phase |

## Discovery Questions Cheat Sheet

**For Problem:**
- What happens if we don't solve this?
- How long has this been a problem?
- Why hasn't it been solved before?

**For User:**
- Walk me through the last time you did this
- What's the worst part of the current process?
- If you could wave a magic wand, what would happen?

**For Success:**
- How will you know your life is better?
- What would you measure to prove it worked?
- What outcome would make you say "this was worth it"?

**For Constraints:**
- What definitely cannot change?
- What have you tried before that didn't work?
- Who else needs to approve this?

## Quality Checklist

Before moving to solution design:
- [ ] Problem is stated in user terms, not solution terms
- [ ] Primary user is identified with context
- [ ] Current state and pain points are documented
- [ ] Desired outcome is clear and specific
- [ ] Success metrics are defined and measurable
- [ ] Constraints are explicit
- [ ] Out of scope is defined
- [ ] Assumptions are listed for validation

## See Also

- `skills/user-story-writing/SKILL.md` - Writing stories after discovery
- `skills/mvp-scoping/SKILL.md` - Prioritizing discovered needs
- `skills/domain-knowledge/SKILL.md` - Understanding domain context

