# Native overlap map

Where a native Claude Code capability overlaps something Loomwright built itself, this file records the decision
and its evidence, so the overlap is not re-analysed from scratch on every scan.

**Rules for this file.**

- Every claim about the platform cites a `known_not_adopted` entry of `loomwright/docs/CAPABILITY_BASELINE.json` by
  its `feature` name, or is marked **unverified**. The baseline owns the platform facts. This file quotes only the
  phrases a verdict rests on and never copies the baseline's lists.
- A verdict is one of `KEEP OURS | ADOPT NATIVE | HYBRID | BLOCKED`.
- A native primitive belongs in the Claude Code adapter layer, never in the core. Each entry names the
  `loomwright/docs/CORE_CONTRACT.md` §3 capability port it maps to.

The source requirement mapped 2b to §3.3. §3.3 is *isolate-a-workspace*, and the poll loop consumes §3.2
*run-in-background*, so 2b maps to §3.2 below and 2d to §3.3.

## 2b — Execute Manager poll loop ↔ native background completion notification

**Verdict: KEEP OURS.**

**What ours does.** `loomwright/agents/execute-manager.md` §"Step 4: Poll Loop" starts every worker in the
background and then polls them for a bounded number of passes. On each pass it checks every running worker with
the host's background-output poll call, without blocking. Every idle pass then blocks on the earliest pending
worker; after three idle passes in a row the interval doubles, up to a cap, and any completion resets it. The
starting interval, the cap and the pass budget are that section's constants and are not copied here. When a
worker finishes, it reads that worker's `.worker-summary.md` and runs the per-subtask gate on the
worktree itself (`verify-provides.sh` against the tree, not the worker's claim). A missing result block fails that
gate, because `absence is NOT a pass`. The inline Supervisor's step driver leaves this loop alone. The header of
`loomwright/scripts/supervisor-next-step.sh` says `The Execute Manager's own poll loop is its own`.

**What the native side is, from the baseline only.** The baseline's `known_not_adopted` entry
`Nested subagents (spawn depth default 3, env-configurable), background completion notifications, Workflow tool`
records the capability by name and says it overlaps "the Execute Manager poll loop and Supervisor spawn
choreography". The baseline states nothing else about it. These properties are all **unverified**:

- whether a completion notification reaches a subagent such as Execute Manager, or only the main session;
- what a notification carries (the worker's result block, or only the fact that it finished);
- whether one fires for a worker that crashed or hit its turn limit;
- how several near-simultaneous completions are delivered, and in what order.

**Reason.** The baseline records only the capability's name, and the property this overlap depends on, delivery
to a subagent, is unverified. Execute Manager is a subagent, so a notification it never receives would replace
nothing. A notification would also replace only the waiting, not what the loop does when a worker finishes. The
per-subtask gate, the dead-worker check (absence is not a pass) and the backoff budget would all stay. Even if the
notification works, it is an optimisation of the wait inside the adapter, not a new core design. Revisit when a
probe in a real session shows a background-completion notification reaching a spawned subagent with the worker's
report attached.

**Port:** `loomwright/docs/CORE_CONTRACT.md` §3.2 *run-in-background*. Its consuming seams name "Execute Manager
Step 3–4 (background workers + poll loop)". Any native notification would bind at that port's Claude Code adapter,
and the core's foreground-polling fallback would stay.

## 2d — Supervisor worker worktrees ↔ native `isolation: worktree`

**Verdict: BLOCKED.**

**What ours does.** Execute Manager creates each parallel worker's worktree with `git worktree add`, under
`loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Worktree Naming Convention". The worktree branches from the run's
feature branch and its path is handed to the worker in the spawn prompt.

**Evidence.**

- The baseline's `known_not_adopted` entry `isolation: worktree frontmatter` records doc evidence against a
  drop-in swap: "the native worktree branches from the default branch, not the parent session's HEAD". Supervisor
  workers must branch from the run's feature branch, so a native worktree would start from the wrong base.
- The same entry records why the earlier empirical probe failed. The plugin's own WorktreeCreate hook returned no
  worktree path. "That blocking hook was REMOVED", so the probe's cause is gone. The entry also says adoption is
  "a SEPARATE decision", not an automatic consequence of that removal.
- `loomwright/docs/CORE_CONTRACT.md` §3.3 *isolate-a-workspace* binds "none of the harness's own isolation
  features". The core creates the worktree itself with `git` and only needs the harness to let a subagent work in
  a given directory.

**Trigger to revisit:** an owner-run, manual empirical re-probe in a session with the plugin reinstalled, as the
baseline entry asks ("Re-probe in a reinstalled-plugin session before re-flagging"). Until that probe shows the
native worktree can start from the parent session's HEAD, this stays BLOCKED.

**Port:** `loomwright/docs/CORE_CONTRACT.md` §3.3 *isolate-a-workspace*.

## 2c — Workflow tool / nested spawning

**Verdict: KEEP OURS.** The baseline names the Workflow tool and nested spawning only in the same entry as 2b,
which leaves everything about their behaviour unverified, and Supervisor's spawn choreography already runs on the
§3.1 *run-a-subagent* port without them.

## 2e — Agent Teams

**Verdict: KEEP OURS.** The baseline's Agent Teams entry still records it as experimental, and no scan has
re-checked the unmet graduation criteria that `loomwright/skills/agent-teams/SKILL.md` lists. So it stays a
complementary research tool, never a replacement for Supervisor's worktrees.

## What this file does not change

The baseline's other 2026-10-12 CANDIDATE entries are untouched here. They stay owner decisions recorded in the
baseline, which owns that list. The Nested-subagents entry is answered by 2b and 2c above, and it stays
byte-unchanged in the baseline.

## Scan cadence

`/capability-check` refreshes the baseline. Nothing else prompts a re-scan, so `bash scripts/bump-version.sh` now
prints a one-line `/capability-check` reminder on a minor or major bump. It reads `plugin_version_at_last_scan`
from the baseline when it runs, so it never carries a second copy of that version. The exact line, and which
modes and failure cases print nothing, are owned by the script's header comment §"SCAN REMINDER".

**Honest limit:** the reminder reaches whoever runs the script directly. A `--parallel` wave's release step
(`loomwright/scripts/automate-wave.sh`) captures the bump output to a log that is shown only on failure, so on that
path the reminder is not seen. Surfacing it in the wave report would be a follow-up. This change does not touch
`automate-wave.sh`.
