## Reflection-Mode Task Prompt

The agents `/dreaming` spawns (Code Reviewer, Red Team Reviewer, QA Executor) all have system prompts tuned for **forward** work — reviewing diffs, attacking running systems, generating tests. To put them into reflection mode, `/dreaming` MUST pass a task prompt that overrides their default behavior. The prompt below is the canonical template — `/dreaming` constructs an instance of it for each spawned agent and substitutes the placeholders.

```
You are running in REFLECTION MODE for the /dreaming command, not your normal forward-execution mode.

DO NOT review code, attack systems, generate tests, or take any action against the current working tree. Your job for this turn is to look BACKWARD at the supplied session logs and propose durable lessons.

INPUTS (read-only):
- Session logs (the N most recent **unconsumed** /supervisor sessions for this project — NOT necessarily the newest N in absolute terms: sessions already reflected on are excluded, so this list can contain an older log while a more recent, already-reflected one is absent):
{numbered list of absolute paths to .supervisor/logs/<session_id>.jsonl files}
- Worker summaries and completed/failed briefs for the same window:
{numbered list of absolute paths to .supervisor/worker-summaries/*.md and .supervisor/jobs/done/*, .supervisor/jobs/failed/* briefs}
- System Twin contract drift (OPTIONAL — present only when this project uses the System Twin):
{the contract_conformance_status / contract_violations trend across the loaded session_end events, and/or per-subsystem contract drift read-only from .supervisor/twin/ via read-system-contract.sh. ABSENT when no twin data exists — treat its absence as "not reported" and reflect normally.}
- Your own existing persistent memory directory (read-only for this turn):
.claude/agent-memory/loomwright-loomwright-{agent-id}/

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
  - Target file/tag under .claude/agent-memory/loomwright-loomwright-{agent-id}/
  - Change type (add / edit / delete)
  - Proposed text (verbatim, ready to paste)
  - Linked Insight number
  - Evidence: N distinct sessions (ids) — copied from that Insight's evidence count
  Do NOT write to the memory directory. Propose only.

  ## 4. Proposed CLAUDE.md Updates
  Each proposal MUST be labeled "PENDING USER APPROVAL" and include:
  - Target section (existing heading or proposed new heading)
  - Proposed text (verbatim, in the same prose style as the surrounding doc)
  - Linked Insight number
  - Evidence: N distinct sessions (ids) — copied from that Insight's evidence count
  A proposal MAY instead be a CURATION candidate — prune (a section no longer earns
  its context cost), merge (two sections restate each other), or supersede (a claim's
  authoritative home moved elsewhere) — labeled the same way, naming the target
  section(s) and, for merge/supersede, the replacement text. Do NOT edit CLAUDE.md.
  Propose only.

  ## 5. Collected Memory Candidates
  Scan the gathered sources for worker WORKER_RESULT.memory_candidates[] strings
  (the optional field workers emit since v14.4.0; workers also echo them into their
  .worker-summary.md). Dedup the collected candidates against the existing project
  memory and against each other. List each UNIQUE candidate verbatim, labeled
  "PENDING USER APPROVAL", with its source session ID / subtask AND an
  "Evidence: N distinct sessions (ids)" line counting how many analyzed sessions
  independently produced it. Do NOT write memory. Propose only.

  ## 6. Proposed LESSONS
  Distilled, CATEGORY-TAGGED lessons, BOUNDED ≤3 active per category. List each as
  "category: <cat> — <lesson text>", labeled "PENDING USER APPROVAL", with a score and
  a Linked Insight number. If a category already holds 3 active lessons, frame the
  proposal as REPLACING the oldest in that category. Do NOT write LESSONS. Propose only.

If a section has no candidates, write "(no proposals — N/M sessions reviewed)" rather than padding. Empty proposals are honest; fabricated ones are a defect.
```

Per-agent customization: `/dreaming` may prepend a one-line role hint (e.g., "Focus on review-finding patterns" for Code Reviewer, "Focus on attack-vector patterns" for Red Team Reviewer, "Focus on test-coverage and infrastructure-discovery patterns" for QA Executor) but MUST NOT remove or weaken any of the HARD RULES above.

