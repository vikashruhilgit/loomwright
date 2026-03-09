---
name: mvp-scoping
description: Prioritize features into MVP, Phase 2, and Nice-to-have. Use when scoping work or making trade-off decisions.
allowed-tools: [Read]
version: "1.0.0"
lastUpdated: "2026-03"
---

# MVP Scoping Skill

Framework for prioritizing features into MVP (must ship), Phase 2 (next release), and Nice-to-have (future consideration).

## Quick Rules

- MVP = Minimum to deliver core value (not minimum features)
- Phase 2 = Important but can ship without
- Nice-to-have = Future consideration, not committed
- When in doubt, defer to Phase 2 (avoid scope creep)
- Re-evaluate priorities after each release

## When to Use This Skill

- Use when scoping a new feature or product
- Use when making trade-off decisions
- Use when stakeholders request "just one more thing"
- Use when timeline is at risk

## Prioritization Matrix

| Factor | MVP | Phase 2 | Nice-to-have |
|--------|:---:|:-------:|:------------:|
| User can't accomplish primary goal without it | X | | |
| Significant value but not blocking core goal | | X | |
| Enhancement, polish, or convenience | | | X |
| Core happy path | X | | |
| Critical error handling | X | | |
| Edge case error handling | | X | |
| Admin/power user features | | X | X |
| Reporting/analytics | | X | X |
| Performance optimization (unless blocking) | | X | |
| Accessibility (WCAG 2.1 AA basics) | X | | |
| Accessibility (AAA, advanced) | | X | |
| Mobile responsiveness (if web) | X | | |
| Internationalization | | | X |

## Decision Questions

Ask these questions to determine priority:

### 1. Is it blocking the core user goal?
```
"Can the user accomplish their primary task without this?"
- NO  → MVP
- YES → Phase 2 or Nice-to-have
```

### 2. What's the cost of adding later?
```
"Is this harder to add after initial release?"
- Architecture change needed later → Consider MVP
- Can be layered on cleanly → Phase 2
- Pure addition, no rework → Nice-to-have
```

### 3. Does it reduce risk or increase learning?
```
"Does shipping this early teach us something important?"
- Validates core assumption → MVP
- Nice validation but not critical → Phase 2
- Already confident → Nice-to-have
```

### 4. Is it a dependency?
```
"Do other MVP features depend on this?"
- Yes, MVP features blocked → MVP
- Only Phase 2 features blocked → Phase 2
- Nothing depends on it → Nice-to-have
```

### 5. What do users expect?
```
"Would users be surprised if this is missing?"
- Unacceptable without it → MVP
- Disappointed but understanding → Phase 2
- Pleasant surprise if included → Nice-to-have
```

## Output Format

When scoping work, organize features like this:

```markdown
## Scope Analysis: [Feature Name]

### MVP (Must Ship)
| Feature | Rationale |
|---------|-----------|
| [Feature 1] | [Why it's essential - ties to core goal] |
| [Feature 2] | [Why it's essential] |

### Phase 2 (Next Release)
| Feature | Rationale | Dependency |
|---------|-----------|------------|
| [Feature 3] | [Why it can wait] | Builds on [MVP feature] |
| [Feature 4] | [Why it can wait] | None |

### Nice-to-Have (Future)
| Feature | Rationale | Revisit When |
|---------|-----------|--------------|
| [Feature 5] | [Why it's deferred] | After user feedback |
| [Feature 6] | [Why it's deferred] | If adoption > X% |

### Trade-offs Made
- [Decision 1]: Chose [A] over [B] because [reason]
- [Decision 2]: Deferred [X] to reduce timeline by [Y]

### Risks of This Scope
- [Risk 1]: MVP might feel incomplete because [reason]
- [Mitigation]: [How we'll address user concerns]
```

## Example: Event Scheduling Feature

```markdown
## Scope Analysis: Event Scheduling for Venues

### MVP (Must Ship)
| Feature | Rationale |
|---------|-----------|
| Create single event | Core user goal - can't schedule without it |
| Set date/time/venue | Essential event attributes |
| Basic conflict detection | Prevents double-booking (critical error) |
| View events in list | Users need to see what's scheduled |

### Phase 2 (Next Release)
| Feature | Rationale | Dependency |
|---------|-----------|------------|
| Recurring events | Valuable but single events work | Create single event |
| Calendar view | Better UX but list view works | View events |
| Event templates | Time-saver but not blocking | Create single event |
| Bulk operations | Power user need | View events |

### Nice-to-Have (Future)
| Feature | Rationale | Revisit When |
|---------|-----------|--------------|
| Drag-drop rescheduling | Polish feature | After calendar view ships |
| Public event feed | Marketing use case | If requested by 3+ customers |
| iCal export | Integration feature | Phase 3 |

### Trade-offs Made
- Chose list view over calendar view to ship 2 weeks earlier
- Deferred recurring events to learn from single-event usage patterns

### Risks of This Scope
- Users may expect calendar view based on competitor products
- Mitigation: Prominent "Calendar view coming soon" message
```

## Common Mistakes

| Mistake | Why It's Wrong | Better Approach |
|---------|---------------|-----------------|
| Everything is MVP | Guarantees missed deadline | Force-rank ruthlessly |
| "It's just a small thing" | Small things add up | Apply same criteria |
| Deferring infrastructure | Creates tech debt | Include if blocking |
| Gold-plating MVP | Delays learning | Ship, then polish |
| No Phase 2 plan | Features get lost | Document for later |

## Stakeholder Pushback Responses

When stakeholders push for more in MVP:

```markdown
**"We need [feature] for launch"**
Response: "Let's check - can users accomplish [core goal] without it?
If yes, we can ship faster and add it in Phase 2 based on feedback."

**"Competitor has this"**
Response: "True, but our MVP tests whether [core value prop] resonates.
We can add parity features once we validate the foundation."

**"It's only [X] more days"**
Response: "Each addition has hidden costs (testing, docs, edge cases).
Let's ship, learn, then prioritize [feature] against what users actually need."

**"Users will be disappointed"**
Response: "Some will, but shipping late disappoints everyone.
We'll communicate the roadmap and ship [feature] in Phase 2."
```

## Quality Checklist

Before finalizing scope:
- [ ] MVP features tie directly to core user goal
- [ ] Phase 2 features have clear "why not MVP" rationale
- [ ] Dependencies are mapped correctly
- [ ] Trade-offs are documented
- [ ] Stakeholders understand what's deferred and why
- [ ] Phase 2 list is realistic (not a dumping ground)
- [ ] Risks of the scope are identified

## See Also

- `skills/user-story-writing/SKILL.md` - Writing stories for scoped features
- `skills/product-discovery/SKILL.md` - Understanding problem before scoping

