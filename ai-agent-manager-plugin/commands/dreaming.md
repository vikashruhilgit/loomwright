---
description: Reflect on past session logs and propose memory + CLAUDE.md updates (read-only, per-item approval required)
---

> **Read-only contract.** `/dreaming` is strictly read-only on code AND on agent memory. The command **proposes** memory and CLAUDE.md updates derived from past session logs; it **never** writes those updates. Persistence to `.claude/agent-memory/` or `CLAUDE.md` only happens after the user explicitly approves each proposed item, and even then the user (or the user's chosen tool) performs the write — `/dreaming` itself does not.

# Command: /dreaming

## Purpose

The Dreaming command runs target agents in **reflection mode** over recent session logs to surface recurring patterns, distill insights, and **propose** updates to agent persistent memory and to project `CLAUDE.md`. It mirrors how human teams retrospectively review past work to extract durable lessons — except `/dreaming` is purely a proposal engine. No code, no agent memory, and no `CLAUDE.md` content is mutated by this command. Each proposed update requires explicit per-item user approval before any write occurs.

This makes `/dreaming` the safe, auditable counterpart to live execution: read past logs, think out loud, and present a structured reflection report that the user can accept, reject, or edit item-by-item.

## Usage

```bash
/dreaming                                          # All agents, last 5 sessions
/dreaming --agent code-reviewer                    # Reflect with Code Reviewer only
/dreaming --agent red-team                         # Reflect with Red Team Reviewer only
/dreaming --agent qa-executor                      # Reflect with QA Executor only
/dreaming --sessions 10                            # All agents, last 10 sessions
/dreaming --agent code-reviewer --sessions 20      # Single agent, deeper history
/dreaming --agent all --sessions 3                 # Explicit all (default), last 3 sessions
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--agent` | No | `all` | Which agent(s) run reflection. Accepts `all`, `code-reviewer`, `red-team`, or `qa-executor`. `all` runs each supported agent in turn and aggregates their reports. Six agents have `memory: project` (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor); v12.2.0 supports the three review-shaped agents listed above because their session logs carry the structured findings reflection needs (CODE_REVIEW_RESULT issues, red-team attack outcomes, QA_RESULT gates). Launch Pad, Product Owner, and QA Strategist are intentionally out of scope for v12.2.0 and may be added in a follow-up. |
| `--sessions N` | No | `5` | How many of the most recent `.supervisor/logs/{session_id}.jsonl` files to feed into reflection. Values are clamped to the number of available log files. Higher values surface more durable patterns at higher token cost. |

## What This Does / Workflow

`/dreaming` is a four-phase, read-only reflection workflow:

```
┌─────────────────────────────────────────────────────────────────┐
│              /dreaming — REFLECTION WORKFLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: GATHER (Read-only log discovery)                      │
│     └─> List `.supervisor/logs/*.jsonl`, sort by mtime desc,    │
│         pick the N most recent (N = --sessions). No mutation.   │
│                                                                 │
│  Phase 2: REFLECT (Per-target agent invocation)                 │
│     └─> For each target agent, spawn it with a reflection       │
│         prompt + the gathered log paths. Agent reads logs +     │
│         its own existing memory in `.claude/agent-memory/`,     │
│         and emits a proposal block. Memory directory is         │
│         opened READ-ONLY; agent must not write.                 │
│                                                                 │
│  Phase 3: AGGREGATE (Compose reflection report)                 │
│     └─> Merge per-agent proposals into a single user-facing     │
│         report with the four mandatory sections below.          │
│                                                                 │
│  Phase 4: APPROVE (Per-item user gate — manual)                 │
│     └─> User reviews each proposed item and chooses             │
│         Accept / Reject / Edit. Only accepted items become      │
│         actual writes; the user (or follow-up command) is the   │
│         one performing the write. `/dreaming` ends here.        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

1. **Read N most recent session logs** — `/dreaming` lists `.supervisor/logs/*.jsonl`, sorts by modification time, and selects the `--sessions N` most recent files (default 5). Logs are opened read-only. **Empty-log path:** if `.supervisor/logs/` is missing or contains no `*.jsonl` files, `/dreaming` exits immediately with a single message — `No session logs found in .supervisor/logs/. Run /supervisor first, then re-run /dreaming.` — and writes nothing.
2. **Spawn target agent(s) in reflection mode** — Each target agent (per `--agent`) is invoked with a reflection-mode system prompt. The prompt instructs the agent to:
   - Read the provided log files and the agent's own existing memory directory under `.claude/agent-memory/`
   - Identify recurring patterns, repeated mistakes, and unstated invariants
   - Distill those into candidate insights
   - **Propose** memory entries and `CLAUDE.md` paragraphs **without writing anything**
3. **Output a structured reflection report** — `/dreaming` aggregates per-agent proposals into a single report with the four mandatory sections listed below.
4. **Per-item user approval** — The user is presented with each proposal in turn. The approval mechanism is the harness `AskUserQuestion` tool (or, when unavailable, a numbered list with typed responses): each proposal is displayed with its target file and verbatim text and the user picks `Accept`, `Reject`, or `Edit`. Only accepted items result in actual writes, and writing is performed by the user (or by a separate, explicit follow-up command they invoke). `/dreaming` itself never writes to `.claude/agent-memory/` or `CLAUDE.md`. There is no bulk-accept; each item is gated individually.

## Reflection Report Sections

Every `/dreaming` report **must** include all four of the following sections, in this order:

### 1. Recurring Patterns

Concrete patterns observed across the analyzed sessions: repeated failure modes, repeated review findings, repeated decisions, repeated blockers. Each entry cites the originating session IDs so the user can cross-check.

### 2. Distilled Insights

The interpretation layer: what the recurring patterns *mean*. Each insight is a short, falsifiable claim — e.g., "Workers consistently miss boundary tests when subtasks lack explicit `provides:` entries" — paired with the evidence count.

### 3. Proposed Memory Updates

Per-agent proposed additions, edits, or deletions for `.claude/agent-memory/{agent-id}/`. Each proposal lists:
- Target agent (must be one with `memory: project`)
- Proposed change type (add / edit / delete)
- Target file or tag within the memory directory
- Proposed text (verbatim)
- Justification linked to a Distilled Insight
- Approval status: **PENDING USER APPROVAL** (always — `/dreaming` does not auto-apply)

### 4. Proposed CLAUDE.md Updates

Proposed additions or revisions to project `CLAUDE.md` (or a sub-file it references). Each proposal lists:
- Target section (existing heading or proposed new heading)
- Proposed text (verbatim, in the same prose style as the surrounding doc)
- Justification linked to a Distilled Insight
- Approval status: **PENDING USER APPROVAL** (always — `/dreaming` does not auto-apply)

## Read-Only Contract

`/dreaming` operates under a **strict read-only contract** that is enforced end-to-end:

- **Code is read-only.** `/dreaming` does not modify, create, or delete source files. It does not run formatters, linters, codegen, or any tool that mutates the working tree. It does not create commits, branches, or worktrees.
- **Agent memory is read-only during reflection.** `.claude/agent-memory/` is opened only for reading. The reflection-mode prompt explicitly forbids writes to that directory. Reflection agents that would normally append to memory must instead emit proposals into the report.
- **`CLAUDE.md` is read-only.** The project `CLAUDE.md` (and any files it references) are opened only for reading.
- **`/dreaming` only PROPOSES.** Every memory and `CLAUDE.md` update appears in the report as a proposal labeled **PENDING USER APPROVAL**.
- **User must explicitly approve each proposed item.** Approval is **per-item**, not bulk. The user chooses Accept, Reject, or Edit for each proposal. Acceptance is required before any persistence.
- **`/dreaming` itself never writes** to `.claude/agent-memory/` or to `CLAUDE.md`. After approval, the user (or a separate follow-up command they invoke) performs the writes; `/dreaming` exits before any persistence occurs.
- **Aborting is always safe.** Because the command never writes, cancelling at any point — including mid-report — leaves the project, agent memory, and `CLAUDE.md` exactly as they were when `/dreaming` started.

This contract is non-negotiable: a `/dreaming` invocation that mutates code, agent memory, or `CLAUDE.md` without per-item user approval is a defect, not a feature request.

## Example Output

```markdown
## /dreaming — Reflection Report

**Sessions analyzed:** 5 (2026-05-03 → 2026-05-09)
**Agents reflecting:** code-reviewer, red-team, qa-executor
**Read-only contract:** ENFORCED. No writes performed.

---

### 1. Recurring Patterns

- **Pattern A — Missing boundary tests** (3/5 sessions: 2026-05-03, 2026-05-06, 2026-05-09)
  Workers shipped CRUD endpoints without negative-case tests; QA Executor flagged the gap each time.
- **Pattern B — `provides:` drift** (4/5 sessions)
  Subtask briefs declared `provides:` symbols that did not match the symbols actually emitted; outputs_gap was non-empty in each case.
- **Pattern C — Code Reviewer re-flagging stale TODOs** (5/5 sessions)
  Same TODO comments flagged review-after-review; nobody is closing them.

### 2. Distilled Insights

- **Insight 1:** When a subtask lacks an explicit boundary-test acceptance criterion, the worker omits boundary tests roughly 60% of the time. (Evidence: Pattern A.)
- **Insight 2:** `provides:` entries authored from memory rather than from the actual code drift within one session. (Evidence: Pattern B.)
- **Insight 3:** TODOs without an owning task ID accumulate indefinitely. (Evidence: Pattern C.)

### 3. Proposed Memory Updates

- **[code-reviewer]** _add_ → `.claude/agent-memory/.../patterns.md`
  Text: "Always check whether subtask `provides:` symbols actually exist in the modified files; flag drift as BLOCKING."
  Linked insight: 2
  Status: **PENDING USER APPROVAL**

- **[qa-executor]** _add_ → `.claude/agent-memory/.../boundary-tests.md`
  Text: "If a subtask touches a CRUD endpoint and the brief has no boundary-test criterion, generate boundary tests anyway and report the gap."
  Linked insight: 1
  Status: **PENDING USER APPROVAL**

### 4. Proposed CLAUDE.md Updates

- **Target section:** "## Common Pitfalls"
  Proposed text: "TODO comments without an owning task ID are forbidden. Either link a Beads/issue ID or remove the TODO before merging — Code Reviewer will block PRs that accumulate ownerless TODOs."
  Linked insight: 3
  Status: **PENDING USER APPROVAL**

---

### Approval

For each item above, choose **Accept**, **Reject**, or **Edit**. Only accepted items will be written, and writing is performed by you (or your chosen follow-up command) — `/dreaming` does not write.
```

## Workflow Positioning

`/dreaming` is a **post-hoc reflection** command. It does not replace any existing pipeline — it complements them.

| Command | Direction | When to use |
|---------|-----------|-------------|
| `/orchestrator` | Forward (plan) | Decompose a goal into tasks before execution |
| `/supervisor` | Forward (execute) | Autonomously execute tasks end-to-end |
| `/code-reviewer` | Lateral (live audit) | Review the current diff or files |
| `/red-team-reviewer` | Lateral (live audit) | Adversarially attack the current state |
| `/qa-executor` | Forward (test) | Generate and run tests against the running app |
| **`/dreaming`** | **Backward (reflect)** | **After several sessions, distill patterns into proposed memory + CLAUDE.md updates** |

Use `/dreaming` periodically — for example, weekly or after every N completed `/supervisor` runs — to harvest durable lessons from session logs and keep agent memory and project documentation aligned with how the team actually works.

## When to Use

- After a streak of completed `/supervisor` sessions, to surface recurring issues
- Before updating `CLAUDE.md` by hand, to discover what *the logs* say should change
- When onboarding a new pattern, to see whether the agents have been quietly learning it
- As a recurring "retrospective" cadence (weekly / per milestone)

## When NOT to Use

- During active execution — `/dreaming` reflects on past sessions, not the current one
- When you need code changes — `/dreaming` is read-only; use `/supervisor` or `/code-reviewer` for changes
- For agents not currently supported — six agents have `memory: project` (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor), but v12.2.0's `--agent` flag covers only Code Reviewer, Red Team Reviewer, and QA Executor; the other three are out of scope until a follow-up release

## See Also

- `/supervisor` — Autonomous workflow whose logs are the input to `/dreaming`
- `/code-reviewer` — Live (forward) review counterpart
- `/red-team-reviewer` — Live (forward) adversarial counterpart
- `/qa-executor` — Live (forward) QA counterpart
- `/agent-help` — Full command list
- `ai-agent-manager-plugin/skills/memory-tool/SKILL.md` — Decision aid for what to write to agent memory directories (consulted on demand)
- `.supervisor/logs/{session_id}.jsonl` — Source data consumed by `/dreaming`
