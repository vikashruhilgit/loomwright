---
description: Reflect on past session logs + worker summaries, collect memory candidates, propose bounded LESSONS, and write accepted items on per-item approval (read-only until you Accept)
---

> **Read-only-until-Accept contract.** `/dreaming` is strictly read-only on code, on agent memory, and on `CLAUDE.md` while it gathers and proposes. The command **proposes** project-memory facts (incl. collected worker candidates), bounded LESSONS, per-agent memory entries, and `CLAUDE.md` updates derived from past session logs and worker summaries. The contract change in v14.5.0: on per-item **Accept**, `/dreaming` itself performs the write for **project-memory facts** and **LESSONS** by invoking the repo-root sole writers (`scripts/write-project-memory.sh`, `scripts/write-lessons.sh`) — every write is still HUMAN-GATED per-item via `AskUserQuestion`; there is **no auto-write**, no bulk-accept, and Reject/Edit never writes. **CLAUDE.md and legacy `.claude/agent-memory/` proposals remain paste-to-apply** (the user, or a follow-up turn, performs those writes — they are not the sole writers' domain). `/dreaming` runs at the repo root so the sole writers' worktree-guard is satisfied.

# Command: /dreaming

## Purpose

The Dreaming command runs target agents in **reflection mode** over recent session logs **and worker summaries** to surface recurring patterns, distill insights, **collect durable memory candidates that workers proposed**, and **propose** bounded project LESSONS, agent persistent-memory entries, and project `CLAUDE.md` updates. It mirrors how human teams retrospectively review past work to extract durable lessons. Each proposed update requires explicit **per-item** user approval; on Accept, `/dreaming` writes **project-memory facts** and **LESSONS** via the repo-root sole writers, while **CLAUDE.md** and **legacy agent-memory** proposals stay paste-to-apply. There is no auto-write and no bulk-accept — Reject/Edit never writes.

This makes `/dreaming` the safe, auditable counterpart to live execution: read past logs and worker summaries, think out loud, and present a structured reflection report that the user can accept, reject, or edit item-by-item — with accepted memory/LESSONS persisted through the guarded sole writers, never by hand.

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

`/dreaming` is a four-phase reflection workflow — read-only while it gathers and proposes, and write-on-Accept (through the guarded sole writers) only for project-memory facts and LESSONS:

```
┌─────────────────────────────────────────────────────────────────┐
│              /dreaming — REFLECTION WORKFLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: GATHER (Read-only source discovery)                   │
│     └─> List `.supervisor/logs/*.jsonl` (N most recent by       │
│         mtime), plus `.supervisor/worker-summaries/*.md` and    │
│         the briefs in `.supervisor/jobs/done/` + `failed/`,     │
│         plus (optional) System Twin contract drift from the     │
│         `session_end` conformance trend + `.supervisor/twin/`   │
│         (read-system-contract.sh). All read-only. No mutation.  │
│                                                                 │
│  Phase 2: REFLECT (Per-target agent invocation)                 │
│     └─> For each target agent, spawn it with a reflection       │
│         prompt + the gathered sources. Agent reads sources +    │
│         its own existing memory in `.claude/agent-memory/`,     │
│         and emits a proposal block. Memory directory is         │
│         opened READ-ONLY; agent must not write.                 │
│                                                                 │
│  Phase 3: AGGREGATE (Compose reflection report)                 │
│     └─> Merge per-agent proposals + collected worker memory     │
│         candidates + distilled LESSONS into a single report     │
│         with the six mandatory sections below.                  │
│                                                                 │
│  Phase 4: APPROVE (Per-item user gate — write-on-Accept)        │
│     └─> User reviews each proposed item and chooses             │
│         Accept / Reject / Edit. On Accept, /dreaming writes     │
│         project-memory facts + LESSONS via the repo-root sole   │
│         writers; CLAUDE.md + legacy agent-memory stay           │
│         paste-to-apply. No auto-write, no bulk-accept.          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

1. **Read N most recent session logs + worker summaries + completed/failed briefs + System Twin contract drift** — `/dreaming` lists `.supervisor/logs/*.jsonl`, sorts by modification time, and selects the `--sessions N` most recent files (default 5). It also reads (read-only) the **N most recent** (by mtime) `.supervisor/worker-summaries/*.md` files and the **N most recent** briefs across `.supervisor/jobs/done/` + `.supervisor/jobs/failed/` — bounded by the same `--sessions N` cap so a repo with many completed jobs does not load them all — since those carry the worker `memory_candidates` and the per-subtask outcomes reflection needs. **Additionally, when System Twin data exists, `/dreaming` reads (read-only) the contract-drift signal**: the `contract_conformance_status` / `contract_violations` trend across the same `session_end` events it already loaded, and/or the per-subsystem contract drift from the twin store under `.supervisor/twin/` via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-system-contract.sh"` (the provenance-gated read-side reader — never the writer). This drift signal is folded into reflection as another input (e.g. "contracts drifting / repeated conformance violations in subsystem X"). It is **strictly read-only and advisory** and entirely **optional** — when no twin data exists (no `contract_conformance_status` on any loaded `session_end`, and no `.supervisor/twin/` store) it is silently skipped and reflection proceeds exactly as before. All sources are opened read-only. **Empty-input path:** if there is genuinely nothing to reflect on — `.supervisor/logs/` is missing or contains no `*.jsonl` files **and** there are no worker summaries or done/failed briefs — `/dreaming` exits immediately with the existing single message — `No session logs found in .supervisor/logs/. Run /supervisor first, then re-run /dreaming.` — and writes nothing. (The twin signal alone never makes a repo non-empty; it only enriches reflection when other sources already exist.)
2. **Spawn target agent(s) in reflection mode** — Each target agent (per `--agent`) is invoked with a reflection-mode system prompt. The prompt instructs the agent to:
   - Read the provided sources and the agent's own existing memory directory under `.claude/agent-memory/`
   - Identify recurring patterns, repeated mistakes, and unstated invariants
   - Distill those into candidate insights
   - **Propose** memory entries and `CLAUDE.md` paragraphs **without writing anything**
3. **Output a structured reflection report** — `/dreaming` aggregates per-agent proposals, collected worker memory candidates, and distilled LESSONS into a single report with the six mandatory sections listed below.
4. **Per-item user approval (write-on-Accept for memory/LESSONS)** — The user is presented with each proposal in turn. The approval mechanism is the harness `AskUserQuestion` tool (or, when unavailable, a numbered list with typed responses): each proposal is displayed with its target and verbatim text and the user picks `Accept`, `Reject`, or `Edit`. There is no bulk-accept; each item is gated individually. On `Accept`:
   - **PROJECT_MEMORY facts** (including accepted collected worker candidates) are written by `/dreaming` itself via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-project-memory.sh" --fact "<text>" --source "dreaming"`.
   - **LESSONS** are written by `/dreaming` itself via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" --category "<cat>" --lesson "<text>" --source "dreaming"`.
   - **Pass `<text>` / `<cat>` as literal argv values, never by interpolating them into a shell string** — approved proposal text may contain quotes, `$`, backticks, or other shell metacharacters. Supply each as a single argument (the writers slugify `--category`, sanitize `--source`, and treat `--fact`/`--lesson` as opaque text), so a lesson like `He said "run $PATH"` is stored verbatim and cannot break or inject the command.
   - **CLAUDE.md** and **legacy `.claude/agent-memory/`** proposals remain **paste-to-apply** — the user (or a follow-up turn) performs those writes; `/dreaming` does not.

   `Reject` and `Edit` never write (an `Edit` only revises the proposed text, which can then be re-offered for Accept). Because `/dreaming` runs at the repo root, the sole writers' worktree-guard is satisfied; both writers also enforce their own bounds/provenance, so even an accepted item is subject to their caps. There is still **no auto-write** — every persisted item requires an explicit per-item Accept.

   **Applying paste-to-apply items.** Each CLAUDE.md / legacy-memory proposal lists its target path (e.g., `.claude/agent-memory/ai-agent-manager-plugin:code-reviewer/patterns.md`) and the verbatim text to write. After `/dreaming` exits, the user — or a follow-up turn in the same session — applies an accepted proposal directly with the `Write` tool (for new files) or `Edit` tool (for in-place additions). The proposal text is already in the form that should be written, so the apply step is a verbatim paste at the cited path. The per-item review-and-apply pattern keeps the user in the loop and forces them to read each proposal before it lands.

## Reflection-Mode Task Prompt

The agents `/dreaming` spawns (Code Reviewer, Red Team Reviewer, QA Executor) all have system prompts tuned for **forward** work — reviewing diffs, attacking running systems, generating tests. To put them into reflection mode, `/dreaming` MUST pass a task prompt that overrides their default behavior. The prompt below is the canonical template — `/dreaming` constructs an instance of it for each spawned agent and substitutes the placeholders.

```
You are running in REFLECTION MODE for the /dreaming command, not your normal forward-execution mode.

DO NOT review code, attack systems, generate tests, or take any action against the current working tree. Your job for this turn is to look BACKWARD at the supplied session logs and propose durable lessons.

INPUTS (read-only):
- Session logs (the N most recent /supervisor sessions for this project):
{numbered list of absolute paths to .supervisor/logs/<session_id>.jsonl files}
- Worker summaries and completed/failed briefs for the same window:
{numbered list of absolute paths to .supervisor/worker-summaries/*.md and .supervisor/jobs/done/*, .supervisor/jobs/failed/* briefs}
- System Twin contract drift (OPTIONAL — present only when this project uses the System Twin):
{the contract_conformance_status / contract_violations trend across the loaded session_end events, and/or per-subsystem contract drift read-only from .supervisor/twin/ via read-system-contract.sh. ABSENT when no twin data exists — treat its absence as "not reported" and reflect normally.}
- Your own existing persistent memory directory (read-only for this turn):
.claude/agent-memory/ai-agent-manager-plugin:{agent-id}/

HARD RULES:
- READ-ONLY for this turn. Do NOT call Write, Edit, NotebookEdit, or any Bash command that mutates files, the git index, branches, the working tree, or your own memory directory. /dreaming will refuse to persist anything you propose without explicit per-item user approval — your job is to propose, not to write.
- Stay scoped to the supplied logs and your own existing memory. Do not crawl unrelated parts of the repository.
- Do not run tests, format code, or open the application.

OUTPUT (mandatory six-section report, in this order):

  ## 1. Recurring Patterns
  Concrete patterns you observed across the supplied logs. For each:
  - Name and one-line description
  - Evidence count and citing session IDs (e.g., "3/5 sessions: 2026-05-03, 2026-05-06, 2026-05-09")

  ## 2. Distilled Insights
  Short, falsifiable claims that interpret the patterns. For each:
  - The claim
  - Linked Pattern letter
  - Evidence count
  When the OPTIONAL System Twin contract-drift input is present, fold it in here as
  one more evidence stream — e.g. "contracts drifting / repeated conformance violations
  in subsystem X" (cite the contract_conformance_status trend or the drifting subsystem).
  When it is absent, do not mention it; reflect on the other inputs as before.

  ## 3. Proposed Memory Updates
  Each proposal MUST be labeled "PENDING USER APPROVAL" and include:
  - Target file/tag under .claude/agent-memory/ai-agent-manager-plugin:{agent-id}/
  - Change type (add / edit / delete)
  - Proposed text (verbatim, ready to paste)
  - Linked Insight number
  Do NOT write to the memory directory. Propose only.

  ## 4. Proposed CLAUDE.md Updates
  Each proposal MUST be labeled "PENDING USER APPROVAL" and include:
  - Target section (existing heading or proposed new heading)
  - Proposed text (verbatim, in the same prose style as the surrounding doc)
  - Linked Insight number
  Do NOT edit CLAUDE.md. Propose only.

  ## 5. Collected Memory Candidates
  Scan the gathered sources for worker WORKER_RESULT.memory_candidates[] strings
  (the optional field workers emit since v14.4.0; workers also echo them into their
  .worker-summary.md). Dedup the collected candidates against the existing project
  memory and against each other. List each UNIQUE candidate verbatim, labeled
  "PENDING USER APPROVAL", with its source session ID / subtask. Do NOT write memory.
  Propose only.

  ## 6. Proposed LESSONS
  Distilled, CATEGORY-TAGGED lessons, BOUNDED ≤3 active per category. List each as
  "category: <cat> — <lesson text>", labeled "PENDING USER APPROVAL", with a score and
  a Linked Insight number. If a category already holds 3 active lessons, frame the
  proposal as REPLACING the oldest in that category. Do NOT write LESSONS. Propose only.

If a section has no candidates, write "(no proposals — N/M sessions reviewed)" rather than padding. Empty proposals are honest; fabricated ones are a defect.
```

Per-agent customization: `/dreaming` may prepend a one-line role hint (e.g., "Focus on review-finding patterns" for Code Reviewer, "Focus on attack-vector patterns" for Red Team Reviewer, "Focus on test-coverage and infrastructure-discovery patterns" for QA Executor) but MUST NOT remove or weaken any of the HARD RULES above.

## Reflection Report Sections

Every `/dreaming` report **must** include all six of the following sections, in this order:

### 1. Recurring Patterns

Concrete patterns observed across the analyzed sessions: repeated failure modes, repeated review findings, repeated decisions, repeated blockers. Each entry cites the originating session IDs so the user can cross-check.

### 2. Distilled Insights

The interpretation layer: what the recurring patterns *mean*. Each insight is a short, falsifiable claim — e.g., "Workers consistently miss boundary tests when subtasks lack explicit `provides:` entries" — paired with the evidence count. When the **System Twin contract-drift** input is present (the `contract_conformance_status`/`contract_violations` trend from `session_end`, and/or per-subsystem drift read read-only from `.supervisor/twin/`), it is folded in here as an additional evidence stream — e.g. "contract conformance in subsystem X has regressed across the last 3 sessions." This input is read-only and **advisory**, optional, and silently omitted when no twin data exists (backward-compatible with repos that have never run the System Twin).

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

### 5. Collected Memory Candidates

The worker-proposed durable facts harvested from the gathered sources. `/dreaming` collects candidates from two concrete, unambiguous shapes: (a) the `memory_candidates:` array inside a `WORKER_RESULT` block in the session logs, and (b) a `## memory_candidates` section in a `.worker-summary.md` file — one `- ` bullet per candidate string (the format workers write into the summary). Workers have emitted the optional `WORKER_RESULT.memory_candidates[]` field since v14.4.0 and echo the same strings under the `## memory_candidates` summary heading, which is why both shapes are scanned. The collected strings are **deduped** against the existing project memory — `/dreaming` reads the verified facts via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-project-memory.sh"` first and drops any candidate already present (and dedups duplicates among the candidates themselves). Each surviving unique candidate is listed:
- Candidate text (verbatim, one line)
- Source session ID / subtask it came from
- Approval status: **PENDING USER APPROVAL** (always)

On Accept, a candidate is written as a PROJECT_MEMORY fact via `write-project-memory.sh` (see Phase 4 / APPROVE).

### 6. Proposed LESSONS

Distilled, **category-tagged** lessons, **bounded ≤3 active per category**. Before proposing, `/dreaming` reads the existing `.supervisor/memory/LESSONS.md` to respect the bound; if a category already holds 3 active lessons, the proposal is framed as **replacing the oldest** lesson in that category (the bound is also enforced independently by `write-lessons.sh` at write time). Each lesson is scored by a simple heuristic — **recall-frequency × outcome × diversity** — where *recall-frequency* is how often the underlying pattern recurred across the analyzed sources, *outcome* weights lessons tied to failures/regressions higher than cosmetic ones, and *diversity* rewards patterns seen across multiple distinct subtasks/sessions rather than one noisy run; the product orders which lessons are worth the scarce ≤3 slots. Each proposal lists:
- Category tag and lesson text (verbatim)
- Heuristic score (and, when a category is full, which existing lesson it would replace)
- Justification linked to a Distilled Insight
- Approval status: **PENDING USER APPROVAL** (always)

On Accept, a lesson is written via `write-lessons.sh` (see Phase 4 / APPROVE).

### Empty-state suppression

If, after dedup against existing project memory and after bounding LESSONS per category, there are **no new candidates and no new lessons**, `/dreaming` says so in a single line (e.g., "No new memory candidates or lessons after dedup/bounding — nothing to propose.") and **writes nothing**. This keeps reports rare and actionable rather than padding every run with already-known facts.

### APPLY deferral (v14.5.0 scope)

`/dreaming` v14.5.0 closes the **collect → distill → persist** loop only. **Reading LESSONS back into planning/execution** — injecting accepted lessons at Launch Pad / Supervisor decision time so they actually steer future runs — is intentionally **deferred to a follow-up**. v14.5.0 makes lessons durable and human-approved; wiring them into the forward pipeline is out of scope here.

## Read-Only Contract

`/dreaming` operates under a **read-only-until-Accept contract** that is enforced end-to-end:

- **Code is read-only.** `/dreaming` does not modify, create, or delete source files. It does not run formatters, linters, codegen, or any tool that mutates the working tree. It does not create commits, branches, or worktrees.
- **Agent memory is read-only during reflection.** `.claude/agent-memory/` is opened only for reading. The reflection-mode prompt explicitly forbids writes to that directory. Reflection agents that would normally append to memory must instead emit proposals into the report.
- **`CLAUDE.md` is read-only.** The project `CLAUDE.md` (and any files it references) are opened only for reading.
- **`/dreaming` only PROPOSES until you Accept.** Every memory, LESSONS, and `CLAUDE.md` update appears in the report as a proposal labeled **PENDING USER APPROVAL**. Nothing is written during GATHER, REFLECT, or AGGREGATE.
- **User must explicitly approve each proposed item.** Approval is **per-item**, not bulk. The user chooses Accept, Reject, or Edit for each proposal. Acceptance is required before any persistence. There is **no auto-write**.
- **On Accept, `/dreaming` writes only PROJECT_MEMORY facts and LESSONS — and only through the repo-root sole writers.** Accepted facts go through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-project-memory.sh" --fact "<text>" --source "dreaming"`; accepted lessons through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" --category "<cat>" --lesson "<text>" --source "dreaming"`. `/dreaming` runs at the repo root, satisfying the sole writers' worktree-guard. Reject/Edit never writes.
- **`CLAUDE.md` and legacy `.claude/agent-memory/` proposals stay paste-to-apply.** `/dreaming` never writes those directly — they are not the sole writers' domain; after approval the user (or a follow-up turn) performs those writes.
- **Aborting before Accept is always safe.** Until you Accept an item, the command has written nothing; cancelling at any point during GATHER/REFLECT/AGGREGATE — including mid-report — leaves the project, agent memory, LESSONS, and `CLAUDE.md` exactly as they were when `/dreaming` started.

This contract is non-negotiable: a `/dreaming` invocation that mutates code, agent memory, LESSONS, or `CLAUDE.md` **without an explicit per-item Accept** — or that auto-writes, bulk-accepts, or writes memory/LESSONS by any path other than the repo-root sole writers — is a defect, not a feature request.

### Enforcement boundary (honest disclosure)

The agents `/dreaming` spawns in reflection mode — Code Reviewer, Red Team Reviewer, QA Executor — have **full write tools** in their normal forward-execution mode. When `/dreaming` spawns them via `Task(subagent_type: ...)`, they inherit the tool permissions declared in their registered frontmatter; the Task tool does NOT support overriding `disallowedTools` per-call. That means the read-only constraint for reflection-spawned agents is **prompt-level**, not tool-level: enforced by the HARD RULES block in the reflection-mode task prompt template above and by the agents' own training to follow explicit instructions, NOT by the harness blocking Write/Edit calls.

In practice, a well-functioning agent honors the HARD RULES. The mitigation against drift is:

1. The HARD RULES block in the reflection-mode prompt is explicit and short.
2. `/dreaming` re-states the read-only contract at the top of every per-agent invocation.
3. The output contract (six sections with PENDING USER APPROVAL labels) leaves no productive path for the reflection-spawned agent to write — it proposes only; `/dreaming` (the main thread, at the repo root) is the sole party that writes accepted memory/LESSONS, and only via the guarded sole writers.
4. Any write that does land must still pass the user's per-item approval gate before becoming persistent on the user's behalf.

A future improvement is dedicated reflection-mode agent variants with `disallowedTools: Write, Edit, NotebookEdit` baked into their frontmatter — that would move enforcement from prompt-level to tool-level. For now, the prompt-level contract is the design.

## Example Output

```markdown
## /dreaming — Reflection Report

**Sessions analyzed:** 5 (2026-05-03 → 2026-05-09)
**Agents reflecting:** code-reviewer, red-team, qa-executor
**Contract:** read-only until per-item Accept. Memory/LESSONS writes go through the repo-root sole writers; CLAUDE.md + legacy agent-memory stay paste-to-apply.

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

### 5. Collected Memory Candidates

- Candidate: "Worker summaries live in .supervisor/worker-summaries/ and are the cheap result-extraction path, not the full TaskOutput."
  Source: session 2026-05-06, subtask BD-22a
  Status: **PENDING USER APPROVAL**
  (deduped against existing project memory: not already present)

### 6. Proposed LESSONS

- category: testing — "When a subtask touches a CRUD endpoint with no boundary-test criterion, generate boundary tests anyway."
  Score: 0.72 (recall-frequency 3/5 × outcome 0.8 [QA-flagged gap] × diversity 3 distinct subtasks)
  Linked insight: 1
  Status: **PENDING USER APPROVAL**
- category: contracts — "Author `provides:` symbols from the actual diff, not from memory." (category full → replaces oldest: "Prefer interface-first contracts")
  Score: 0.64
  Linked insight: 2
  Status: **PENDING USER APPROVAL**

---

### Approval

For each item above, choose **Accept**, **Reject**, or **Edit** (per-item — there is no bulk-accept). On **Accept**: PROJECT_MEMORY facts (incl. accepted §5 candidates) are written by `/dreaming` via `write-project-memory.sh`, and §6 LESSONS via `write-lessons.sh` (both repo-root sole writers, run from the repo root). CLAUDE.md (§4) and legacy `.claude/agent-memory/` (§3) proposals are paste-to-apply by you. **Reject**/**Edit** never writes. There is no auto-write.
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
- When you need code changes — `/dreaming` never touches code (it only persists approved memory/LESSONS); use `/supervisor` or `/code-reviewer` for code changes
- For agents not currently supported — six agents have `memory: project` (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor), but v12.2.0's `--agent` flag covers only Code Reviewer, Red Team Reviewer, and QA Executor; the other three are out of scope until a follow-up release

## See Also

- `/supervisor` — Autonomous workflow whose logs are the input to `/dreaming`
- `/code-reviewer` — Live (forward) review counterpart
- `/red-team-reviewer` — Live (forward) adversarial counterpart
- `/qa-executor` — Live (forward) QA counterpart
- `/agent-help` — Full command list
- `ai-agent-manager-plugin/skills/memory-tool/SKILL.md` — Decision aid for what to write to agent memory directories (consulted on demand)
- `.supervisor/logs/{session_id}.jsonl` — Source data consumed by `/dreaming`
