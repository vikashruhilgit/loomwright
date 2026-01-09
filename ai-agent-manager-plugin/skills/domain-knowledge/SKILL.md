---
name: domain-knowledge
description: Template for documenting domain expertise in CLAUDE.md. Use when setting up domain context for a project.
allowed-tools: [Read]
---

# Domain Knowledge Skill

Template and guidance for adding domain expertise to a project's CLAUDE.md file. Domain knowledge is **configurable per project**, not hardcoded in agent prompts.

## Quick Rules

- Domain knowledge lives in project's CLAUDE.md
- Agents read domain context at session start
- Include roles, workflows, terminology, and business rules
- Update domain section as understanding grows
- Keep it concise but complete

## When to Use This Skill

- Use when setting up a new project
- Use when onboarding agents to domain-specific work
- Use when Product Owner needs domain context for stories
- Use when Code Reviewer needs to validate business logic

## CLAUDE.md Domain Section Template

Add this section to your project's `CLAUDE.md`:

```markdown
## Domain Knowledge

### Industry Context
- **Industry:** [Industry name]
- **Business model:** [How the business operates]
- **Key workflows:** [Primary business processes]
- **Regulatory constraints:** [Compliance requirements, if any]

### User Roles

| Role | Description | Primary Goals | Key Workflows |
|------|-------------|---------------|---------------|
| [Role 1] | [Who they are] | [What they need] | [What they do] |
| [Role 2] | [Who they are] | [What they need] | [What they do] |

### Business Rules

| Rule | Description | Rationale | Exceptions |
|------|-------------|-----------|------------|
| [Rule 1] | [What must happen] | [Why it exists] | [When it doesn't apply] |
| [Rule 2] | [What must happen] | [Why it exists] | [When it doesn't apply] |

### Domain Terminology

| Term | Definition | Context |
|------|------------|---------|
| [Term 1] | [What it means] | [When it's used] |
| [Term 2] | [What it means] | [When it's used] |

### Common Workflows

#### [Workflow Name 1]
- **Trigger:** [What starts this workflow]
- **Actor:** [Who performs it]
- **Steps:**
  1. [Step 1]
  2. [Step 2]
  3. [Step 3]
- **Outcome:** [Expected result]
- **Variations:** [Alternative paths]

#### [Workflow Name 2]
[Same structure]

### Integration Points

| System | Purpose | Data Flow |
|--------|---------|-----------|
| [System 1] | [What it does] | [In/Out data] |
| [System 2] | [What it does] | [In/Out data] |

### Known Constraints

- [Constraint 1]: [Description and impact on design]
- [Constraint 2]: [Description and impact on design]
```

## Example: Sports Venue Management Domain

```markdown
## Domain Knowledge

### Industry Context
- **Industry:** Sports venue management
- **Business model:** Venue operators host events, manage staff, sell concessions
- **Key workflows:** Event scheduling, staff assignment, access control, POS operations
- **Regulatory constraints:** Capacity limits, alcohol service hours, safety compliance, labor laws

### User Roles

| Role | Description | Primary Goals | Key Workflows |
|------|-------------|---------------|---------------|
| Venue Manager | Oversees all venue operations | Maximize revenue, ensure safety | Reporting, approvals, escalations |
| Event Coordinator | Plans and executes events | Smooth event delivery | Event setup, vendor coordination |
| Staff Supervisor | Manages front-line workers | Adequate coverage, labor compliance | Shift scheduling, attendance |
| Concession Manager | Runs food/beverage operations | Sales targets, inventory control | Menu management, POS config |
| Security Lead | Manages venue security | Safe environment, access control | Credential management, incident response |

### Business Rules

| Rule | Description | Rationale | Exceptions |
|------|-------------|-----------|------------|
| No double-booking | Same space can't host two events | Physical impossibility | Setup/teardown overlap allowed with approval |
| Minimum staffing | Events require minimum staff per capacity | Safety regulations | Private events may have reduced requirements |
| Alcohol cutoff | No sales 30 min before event end | Liability management | Extended events with approval |
| Break compliance | Staff get 30 min break per 6 hours | Labor law | Emergency situations only |

### Domain Terminology

| Term | Definition | Context |
|------|------------|---------|
| Gate time | When venue doors open to public | Typically 60-90 min before event start |
| Turnover | Time between back-to-back events | Minimum 2 hours for cleaning/setup |
| Call time | When staff must arrive | Usually 30 min before gate time |
| Per cap | Revenue per attendee | Key performance metric |
| Load-in | When equipment/performers arrive | Separate from gate time |

### Common Workflows

#### Event Scheduling
- **Trigger:** Client requests event date
- **Actor:** Event Coordinator
- **Steps:**
  1. Check venue availability
  2. Verify no conflicts (setup, teardown buffer)
  3. Create event record with details
  4. Generate staffing requirements
  5. Notify relevant departments
- **Outcome:** Confirmed event on calendar
- **Variations:** Tentative hold (48hr expiry), multi-day events

#### Staff Shift Assignment
- **Trigger:** Event created with staffing needs
- **Actor:** Staff Supervisor
- **Steps:**
  1. View open shifts for event
  2. Check staff availability
  3. Assign staff to shifts (skill match)
  4. Send notifications
  5. Handle confirmations/declines
- **Outcome:** Fully staffed event
- **Variations:** On-call backup, cross-training assignments

#### Game Day POS Operations
- **Trigger:** Gate time reached
- **Actor:** Concession Manager
- **Steps:**
  1. Open registers with starting cash
  2. Monitor sales in real-time
  3. Handle price overrides (manager approval)
  4. Process refunds if needed
  5. Close out registers, reconcile
- **Outcome:** Accurate sales record, cash balanced
- **Variations:** Mobile POS, premium suite service

### Integration Points

| System | Purpose | Data Flow |
|--------|---------|-----------|
| Payroll (ADP) | Staff compensation | Shifts out, hours in |
| Ticketing (Ticketmaster) | Event attendance | Capacity limits, attendance data |
| Inventory (Oracle) | Stock management | Usage out, reorder triggers in |
| Access Control (Lenel) | Credential management | Staff credentials out, access logs in |

### Known Constraints

- **Legacy POS:** Current POS is 10 years old, no API, only CSV export
- **Union rules:** Some staff have seniority-based shift selection
- **Multi-tenant:** Some venues host multiple teams/organizations
- **Seasonal:** Staff availability varies dramatically by season
```

## Example: Restaurant/Hospitality Domain

```markdown
## Domain Knowledge

### Industry Context
- **Industry:** Restaurant and hospitality
- **Business model:** Food service, dine-in/takeout/delivery
- **Key workflows:** Order taking, kitchen production, payment, inventory
- **Regulatory constraints:** Health codes, food safety (HACCP), tip regulations, allergen disclosure

### User Roles

| Role | Description | Primary Goals | Key Workflows |
|------|-------------|---------------|---------------|
| General Manager | Overall restaurant operations | Profitability, guest satisfaction | Reporting, staffing, vendor management |
| Server | Front-of-house guest service | Tips, table turnover | Order entry, payment, guest interaction |
| Kitchen Manager | Back-of-house operations | Food quality, ticket times | Production, inventory, food safety |
| Host | Guest seating management | Table optimization | Reservations, waitlist, seating |
| Bartender | Bar operations | Sales, drink quality | Drink prep, tab management |

### Business Rules

| Rule | Description | Rationale | Exceptions |
|------|-------------|-----------|------------|
| Allergy protocol | All allergen requests require manager confirmation | Liability | None |
| Comp limits | Servers can comp up to $20, manager above | Cost control | VIP guests with GM approval |
| Tip pooling | Tips split by hours worked | Fair distribution | Private events may differ |
| Waste tracking | All waste logged with reason | Cost control, theft prevention | None |

### Domain Terminology

| Term | Definition | Context |
|------|------------|---------|
| Cover | One guest served | "200 covers tonight" |
| Ticket time | Order to delivery duration | Target varies by dish type |
| 86'd | Item unavailable | "86 the salmon" |
| Turn | Table cycle (seat to clear) | Target 45-60 min for dinner |
| Comp | Complimentary item/discount | For service recovery |

### Common Workflows

#### Table Service Order
- **Trigger:** Guest seated
- **Actor:** Server
- **Steps:**
  1. Greet within 60 seconds
  2. Take drink order
  3. Deliver drinks, take food order
  4. Enter order to POS (send to kitchen)
  5. Deliver food, check back
  6. Process payment, close table
- **Outcome:** Satisfied guest, payment collected
- **Variations:** Split checks, special requests, allergy modifications

### Integration Points

| System | Purpose | Data Flow |
|--------|---------|-----------|
| Reservation (OpenTable) | Table bookings | Reservations in, confirmations out |
| Delivery (DoorDash/UberEats) | Third-party orders | Orders in, status out |
| Accounting (QuickBooks) | Financial records | Sales summary out |
| Inventory (MarketMan) | Stock levels | Usage out, orders in |
```

## How Agents Use Domain Knowledge

| Agent | Uses Domain For |
|-------|-----------------|
| Product Owner | Writing stories with correct roles and terminology |
| Orchestrator | Understanding constraints when planning tasks |
| Code Reviewer | Validating business rule implementation |
| Red Team Reviewer | Testing domain-specific edge cases |

## Quality Checklist

Before finalizing domain section:
- [ ] All user roles documented with goals
- [ ] Key business rules explicit with rationale
- [ ] Domain terms defined (avoid jargon confusion)
- [ ] Primary workflows documented
- [ ] Integration points identified
- [ ] Constraints that affect design noted
- [ ] Examples are concrete and realistic

## See Also

- `skills/product-discovery/SKILL.md` - Discovering domain during research
- `skills/user-story-writing/SKILL.md` - Using domain context in stories

