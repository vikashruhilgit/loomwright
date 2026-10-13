---
name: user-story-writing
description: Write clear user stories with testable acceptance criteria. Use for requirements definition and feature scoping.
allowed-tools: [Read]
version: "1.3.0"
lastUpdated: "2026-10-12"
---

# User Story Writing Skill

Write clear, actionable user stories with testable acceptance criteria following the INVEST principles.

## Quick Rules

- Format: "As a [specific role], I want [capability], so that [business value]"
- Acceptance criteria use Given/When/Then format
- Include edge cases and error scenarios
- Stories must be Independent, Negotiable, Valuable, Estimable, Small, Testable (INVEST)
- **Small means "fits one PR"**, not "one finding": small enough to review in one PR, large enough to pay a run's fixed cost. When two stories touch the same files, prefer one story with Parts (§"Requirement Shape")
- One story = one user goal (not multiple unrelated features bundled)

## When to Use This Skill

- Use when defining new features or requirements
- Use when breaking down epics into stories
- Use when documenting acceptance criteria
- Do NOT use for technical tasks (use Beads tasks instead)

## Requirement Shape

Decide the shape **before writing any file**. Items written one finding at a time come out too small to pay a full run; ten findings merged into one come out too big to plan (a 10-Part item failed Plan Review three times on the 7-subtask cap, then its 4-Part subtask kept hitting the worker's turn limit).

### Shape decision

| Shape | Use when |
|---|---|
| **One item** | It fits one PR: about 30 files or fewer in `## Touches` (count a directory's files), at most 7 subtasks, at most 2 Parts per subtask |
| **One item with Parts** (`## Part A — …`, `## Part B — …`) | Same theme and shared files, and it still fits one PR |
| **A set of items plus a plan doc** | Anything bigger. Each item in the set fits one PR; the set gets one plan doc (template below) |

No mechanical size check ships yet: count by hand. Too small to pay a run ⇒ merge it into a sibling that touches the same files; too big for one PR ⇒ split it into a set.

### Item rules

- **Every item is self-contained.** A run receives only the item file, so the item carries everything the work needs. A hand-written item uses this shape (a Product Owner story uses the Story Template below, which carries the same machine-read sections):

  ```markdown
  # NN — <one-line outcome>

  ## Status: pending

  ## Problem
  ## Goal
  ## Scope
  ## Non-goals
  ## Owner decisions (from _BACKLOG.md)
  <!-- only when the plan doc records an owner decision this item's run must obey; see "Honest limit" below -->
  ## Acceptance criteria
  ## Validation (must pass before merge)
  ## Measurements
  <!-- only when a criterion needs repeated runs or timing; see the next rule -->
  ## Depends on
  ## Touches
  ```
- **Measurements are not acceptance.** A criterion that needs repeated runs (N×), wall-clock timing, or an idle or loaded machine goes under `## Measurements`, never `## Acceptance criteria`. It names the frozen commit it runs against (`git worktree add <tmp> <sha>`), so later edits cannot invalidate a run, and it runs after the code is complete — never inside a worker's turn budget. The worker's own acceptance for it is "the harness exists and passes once".
- **Evidence lives in a committed file, never the PR body.** A criterion that needs pasted commands, measured values or rejected alternatives names a committed evidence file as where they go: "then `docs/evidence/<slug>.md` contains …, and the PR body links to it" (Markdown, never `*.log`, which is commonly gitignored). The PR body is written before review and no fix task can edit it, so a criterion that only the body can satisfy is never healed (`skills/supervisor-readiness/SKILL.md` §"Acceptance Criteria"; Plan Reviewer Criterion 20 FAILs it on the Launch Pad path). `## Validation (must pass before merge)` running-system steps are different: their output is pasted into the PR body by whoever ran them, and the `/automate` validation gate reads it there and parks rather than looping a heal round.
- **New findings join an existing theme.** A new item, Part, or "considered and not queued" row goes into that theme's plan doc. Do not start a new `*-followups` folder.

### Plan-doc template

A requirement set has ONE plan doc, `<folder>/_BACKLOG.md` (the name `/automate --backlog` reads; Product Owner names its own `_BACKLOG-{YYYY-MM-DD-HHMMSS}-{slug}.md`). Sections in this order:

<!-- plan-doc-template:begin -->
```markdown
# <Theme> — plan doc (index document, not an implementable item)

## Status: done (index document — nothing to implement)

## Why now
<the problem this set solves, with the measured baseline when one exists>

## Owner decisions
<binding on every item; the owner's section — "none recorded" until the owner writes them>

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 01 | <outcome> | none | 02 |
| 02 | <outcome> | none | 01 |

## Run
/automate --backlog <path of this file>
<mode (safe / --auto-merge / --parallel N) and run rules, e.g. "no new follow-up items">

## Considered and not queued
<idea — why not, so nobody re-proposes it without new evidence>

## Revisit when
<the trigger that reopens this set>

## Checklist
- [ ] .supervisor/requirements/<folder>/01-<slug>.md
- [ ] .supervisor/requirements/<folder>/02-<slug>.md
```
<!-- plan-doc-template:end -->

- **The status stamp is load-bearing:** `/automate --folder` skips a file stamped `## Status: done`, so the plan doc is never enqueued as an item.
- **The checklist is the only machine-read part.** `/automate --backlog` reads every `- [ ] <path>` line in file order (repo-root-relative paths; an optional `  # note` after two spaces) and skips a line whose item file is stamped done. So keep `- [ ]` lines out of every other section, and keep the checklist last.
- **Honest limit:** each item's run receives only `--requirement <item>`, never the plan doc. An owner decision an item's run must obey is ALSO copied into that item under `## Owner decisions (from _BACKLOG.md)`.

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

## Depends on
none

## Touches
src/scheduling/
src/notifications/shift-assigned.ts
```

**Machine-read sections (`## Depends on`, `## Touches`).** Every persisted requirement file carries these two sections as **H2** headings — H2 in the file even though the template's own sections are H3 — so a planner can tell which stories may run at the same time. Grammar: one entry per line and nothing else on the line — no backticks, no bullets, no globs, no prose (blank lines are ignored):

- `## Depends on` — `none` as the sole line, or one dependency per line: a 1–3 digit id of a story in the same folder (`03`), or a relative path ending in `.md` (`../other-queue/02-x.md`). An id resolves only against `NN-*.md` siblings, so a timestamp-named story (`2026-10-03-101500-first-story.md`) must be referenced by its relative path, never by an id. A missing or unparseable section reads as "depends on every earlier story".
- `## Touches` — one repo-relative path per line (characters `A-Za-z0-9._/@+-` only, no leading `/`, no `.` or `..` segment, no `//`); a trailing `/` marks a directory; the sole line `unknown` when the touched set is not known. Any line that does not parse makes the whole section `unknown`, and an `unknown` story runs alone.

**Fill them; do not leave the defaults** (an undeclared story serialises the whole queue):

- **`## Touches` comes from your own file-impact reasoning.** List every path the story's Scope names or plainly implies — the files and directories the change will edit or create. Write the sole line `unknown` only when you truly cannot name the change site (e.g. a capability with no code yet to point at), never as a placeholder.
- **No prose inside the section, ever.** A condition ("only if a test exposes a defect"), a part label ("(part B)"), a comma list or a bullet makes the WHOLE section unknown. Put conditions in Scope; keep one bare path per line here.
- **Always write `## Depends on`** — `none` when the story depends on nothing. A missing section is not "none"; it makes the story wait for every earlier story.
- **Check before handing off:** `automate-helpers.sh plan-waves <file|dir> --lint` (the `/automate` engine's helper script) prints `ok` / `ok (declared unknown)` or the exact bad line, its number and the reason for both sections, and exits 1 when either is missing or unparsable.

Keep them as the story's last sections (or follow them with another `##` heading): an `###` heading does not end an H2 section, so its text would be read as a bad `Touches` line. The prose `### Dependencies` block stays for humans and is never parsed — `## Depends on` / `## Touches` are the machine-read declarations.

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

## Depends on
12-event-creation.md
14-staff-profile-management.md

## Touches
src/scheduling/shift-assignment/
src/notifications/
```

## Anti-Patterns

| Anti-Pattern | Problem | Better Approach |
|--------------|---------|-----------------|
| "As a user..." | Too vague, no context | "As a Staff Supervisor at a venue..." |
| Technical language | Not user-focused | Describe outcomes, not implementation |
| Unrelated features bundled | Not one goal; may not fit one PR | Split by goal; keep same-file work as one story with Parts (§"Requirement Shape") |
| Missing acceptance criteria | Untestable | Always include Given/When/Then |
| No business value | "...so that it works" | State measurable outcome |
| Implementation details | "...using React hooks" | Focus on what, not how |
| One finding per story | Too small to pay a run's fixed cost | Merge into the sibling that touches the same files |
| Timing / N× runs as acceptance | A worker waits on it inside its turn budget | Move it to `## Measurements` on a frozen commit |

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
- [ ] `## Depends on` written (`none` when none) and `## Touches` filled from Scope — `plan-waves --lint` says `ok`
- [ ] Risks identified
- [ ] Story is estimable (not too vague, not too large) and its shape was decided first — it fits one PR (§"Requirement Shape")

## See Also

- `skills/mvp-scoping/SKILL.md` - Prioritization framework
- `skills/product-discovery/SKILL.md` - Discovery before requirements
- `skills/domain-knowledge/SKILL.md` - Adding domain context to CLAUDE.md

