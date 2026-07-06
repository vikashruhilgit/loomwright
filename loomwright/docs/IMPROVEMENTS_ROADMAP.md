# Improvements Roadmap

> **⚠️ Planning snapshot — pre-hooks.json-centralization (~v9 era). NOT current-state documentation.**
>
> **Re-verified 2026-07-06 against the live repo**, superseding the 2026-07-05 review pass; each of the 18 items below carries an inline re-verified `[VERDICT: …]` line. Summary:
>
> - **RESOLVED (10):** items 1, 2, 4, 7, 8, 13, 14, 15, 16, 17
> - **DEFERRED (7):** items 3, 5, 9, 10, 11, 12, 18
> - **OPEN (1):** item 6 — `WorktreeCreate` hook shipped, but a `WorktreeRemove` hook is still absent from `loomwright/hooks/hooks.json`
>
> (The 2026-07-05 review pass spoke of "19 items"; this document has 18 numbered items — the count discrepancy is noted, not a missing item. Items are globally numbered `### 1.`–`### 18.` under the `## P0`–`## P3` tier sections; there are no literal `P#-#` IDs.)
>
> **Current-state authority:** `CLAUDE.md` + `loomwright/hooks/hooks.json` + `loomwright/.claude-plugin/plugin.json`. When this document disagrees with those, they win — do not re-litigate RESOLVED/DEFERRED items from this snapshot's framing.

Detailed analysis of every proposed improvement, prioritized by criticality, with performance impact assessment and risk evaluation.

---

## P0 — Critical (Plugin May Be Broken Today)

### 1. Plugin Security Restriction — Per-Agent Hooks/PermissionMode Silently Ignored

**[VERDICT: RESOLVED — all validation hooks are centralized in `loomwright/hooks/hooks.json` (21 entries) since v10.0.0; the frontmatter-ignore gotcha is documented in CLAUDE.md §"Adding or Modifying Agents" ("Hook gotcha") and AGENT_GUIDELINES.md §hooks, with frontmatter copies kept only for `~/.claude/agents/` compatibility]**

**What's happening now:**
`code-reviewer.md` has `permissionMode: plan` (line 7) and a `Stop` hook (line 17-21). `worker.md` has a `SubagentStop` hook (line 9-13). `execute-manager.md` has a `SubagentStop` hook (line 12-16). These are all in agent frontmatter.

**The problem:**
Claude Code introduced a security restriction: when agents are loaded as plugin agents, the frontmatter fields `hooks`, `mcpServers`, and `permissionMode` are **silently ignored**. No error, no warning — they just don't fire. This means:

- Code Reviewer's `permissionMode: plan` (read-only mode) → **ignored**. The reviewer can accidentally edit files.
- Worker's `SubagentStop` destructive command check → **ignored**. A worker could `rm -rf` with no hook catching it.
- Execute Manager's `SubagentStop` schema validation → **ignored**. Malformed `EXECUTE_RESULT` passes through.
- Code Reviewer's `Stop` completeness check → **ignored**. Could finish without `CODE_REVIEW_RESULT` block.

Only `hooks.json` hooks still work because they're cross-cutting, not per-agent frontmatter.

**Performance impact:** IMPROVES safety, no performance cost. The hooks were supposed to run but aren't — this is a silent failure. Fixing it means your safety gates actually fire.

**How to fix (two options):**

- **Option A (recommended):** Move all per-agent hooks into `hooks.json` with matcher fields. This is where Claude Code enforces hooks for plugins.
- **Option B:** Document that users must copy agents to `~/.claude/agents/` (not plugins) if they want frontmatter hooks. Worse UX.

**Risk of degradation:** ZERO. You're restoring intended behavior that's currently silently broken.

---

### 2. Add Supervisor Validation Hook

**[VERDICT: RESOLVED — `loomwright/hooks/hooks.json` carries a `SubagentStop` validator for `loomwright:supervisor-runner` (prompt validation of the `SUPERVISOR_RESULT` block, plus telemetry + webhook `type: command` entries on the same matcher)]**

**What's happening now:**
The Supervisor (`supervisor.md`) has NO validation hook — not in frontmatter, not in `hooks.json`. It's the most critical agent (7-phase orchestrator, creates PRs, manages branches, manages worktrees) and it can finish with:

- Corrupted state file
- Unmerged worktrees left behind
- No PR created despite claiming success
- Partially merged branches

Meanwhile, less critical agents like Worker and Code Reviewer have validation hooks.

**Why this matters:**
The Supervisor can silently claim "done" without actually completing. Every other agent in the pipeline has validation, but the top-level orchestrator doesn't. It's like having quality checks at every assembly line station but not at the final shipping dock.

**Performance impact:** Adds ~2-5 seconds (one haiku prompt evaluation at 30s timeout). The Supervisor runs for minutes/hours — this is negligible. But it catches failures that would otherwise waste the entire pipeline's work.

**What to validate:**

- `SUPERVISOR_RESULT` block present with `session_id`, `tasks_completed`, `pr_url`
- If PR was planned, `pr_url` is non-empty
- No orphaned worktrees mentioned in output

**Risk of degradation:** VERY LOW. One additional prompt hook at completion. If the hook itself fails (timeout), Claude Code continues normally — hooks don't block on timeout.

---

## P1 — Leverage New Claude Code Features

### 3. Upgrade Hooks from `type: "prompt"` to `type: "agent"`

**[VERDICT: DEFERRED — no `type: "agent"` hooks exist in `loomwright/hooks/hooks.json`; the plugin instead pairs `type: "prompt"` (haiku, 30s) validators with zero-latency `type: "command"` scripts, which took the filesystem/git-verification niche this item proposed agent hooks for]**

**What's happening now:**
All hooks use `type: "prompt"` — a single-turn haiku evaluation that reads `$ARGUMENTS` (the agent's output text) and returns ok/not-ok. Example from `hooks.json` line 9-11: the Code Reviewer hook reads the output text and checks if `CODE_REVIEW_RESULT` has the right fields.

**The limitation:**
`type: "prompt"` can only read the text output. It can't:

- Check if files were actually modified (read the filesystem)
- Verify the git state (run git commands)
- Validate that test files actually exist
- Cross-reference output claims against reality

**What `type: "agent"` does:**
Spawns a subagent with tool access (Read, Bash, Glob, etc.). It can actually verify claims — not just parse text.

**Performance impact:** MIXED — this is where to be careful.

- `type: "prompt"` → ~2-3 seconds (fast haiku single-turn)
- `type: "agent"` → ~15-60 seconds (subagent with tools, multiple turns)

**Recommendation:** DON'T upgrade all hooks. Only upgrade hooks where text-only validation is insufficient:

- **Keep as `type: "prompt"`:** Code Reviewer (schema validation is text-based, works fine), TaskCompleted (simple check), Context-Keeper
- **Consider `type: "agent"` for:** Worker (could verify files actually exist on disk), Supervisor (could verify PR was created via `gh pr view`)

**Risk of degradation:** MODERATE if you upgrade everything. Each agent hook adds 15-60s. For the Worker hook that fires after every subtask in parallel execution, this compounds. Only upgrade the 1-2 hooks where filesystem/git verification matters.

---

### 4. Add `effort` to Agent Frontmatter

**[VERDICT: RESOLVED — `agents/red-team-reviewer.md:7` carries `effort: xhigh` (exceeding the proposed `high`), and effort tiering is now the canonical cost/quality knob across 11 of 14 agents (`loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Effort Tier", v12.0.0). Context-Keeper carries no `effort` field but runs `model: haiku` + `maxTurns: 3` (`agents/context-keeper.md`), which delivers this item's cheap-fast intent]**

**What's happening now:**
Only Code Reviewer has `effort: high` (line 6). All other agents use the default effort level (medium).

**What `effort` does:**
Controls how deeply the model thinks before responding. Options: `low`, `medium`, `high`, `max` (Opus only).

- `low` → faster, less thorough (good for simple operations)
- `high` → slower, more thorough (good for analysis)
- `max` → Opus-only, deepest reasoning

**Where this helps:**

| Agent | Current | Proposed | Why |
|-------|---------|----------|-----|
| Code Reviewer | `effort: high` | Keep high | Already correct |
| Red Team Reviewer | default | `effort: high` | Security analysis benefits from deep reasoning |
| Context-Keeper | default | `effort: low` | Trivial state read/write operations |
| Worker | default | Keep default | Implementation is medium-complexity |
| Supervisor | default | Keep default | Orchestration decisions are medium-complexity |

**Risk of degradation:**

- `effort: low` on Context-Keeper: LOW risk. Its task is trivial (read/write state files). Low effort is sufficient.
- `effort: high` on Red Team: LOW risk. It already takes 60 maxTurns — making each turn more thorough improves results.
- DON'T put `effort: high` on Worker or Supervisor — they run in loops and the slowdown compounds.

---

### 5. Add `initialPrompt` to Supervisor/Launch Pad

**[VERDICT: DEFERRED — skipped by design, exactly per this item's own "SKIP THIS" recommendation; no `initialPrompt` field exists in any `loomwright/agents/*.md` frontmatter (grep-clean 2026-07-06)]**

**What's happening now:**
When Supervisor spawns, its first turn is spent reading the context, understanding the task, and deciding what to do. This "cold start" turn consumes 1 of its tool-call budget reading CLAUDE.md, `.supervisor/state.md`, `git log`, etc.

**What `initialPrompt` does:**
Auto-submits a first turn when the agent spawns. Instead of the parent telling the agent "go read your state," the agent comes pre-loaded with a starting instruction.

**Example for Supervisor:**
```
initialPrompt: "Read .supervisor/state.md and git log --oneline -5 to determine current phase, then proceed."
```

**Performance impact:** SMALL IMPROVEMENT. Saves one round-trip of the parent agent telling the child what to do. The child starts working immediately.

**However — be careful:**

- If the `initialPrompt` assumes state that doesn't exist (e.g., `.supervisor/state.md` not yet created), the first turn is wasted on an error.
- The Supervisor already has good self-initialization logic in its prompt. Adding `initialPrompt` might conflict.

**Recommendation:** SKIP THIS for now. The benefit is marginal (saves ~5 seconds on a multi-minute workflow) and the risk of conflicting with existing initialization logic is real. Only add this if you refactor Supervisor's Phase 0 to depend on it.

**Risk of degradation:** MODERATE. If the initial prompt conflicts with the agent's own initialization, you get wasted turns. Not worth the small speedup.

---

### 6. Add WorktreeCreate/WorktreeRemove Hooks

**[VERDICT: OPEN (half-shipped) — the `WorktreeCreate` `type: "command"` hook exists in `loomwright/hooks/hooks.json` (logs to `.supervisor/logs/worktrees.log`), but a `WorktreeRemove` hook is still absent from `loomwright/hooks/hooks.json`, so cleanup verification remains manual (CLAUDE.md §"Orphaned worktrees after crash?")]**

**What's happening now:**
The Supervisor creates worktrees for parallel workers, but there's no hook tracking when worktrees are created or cleaned up. If a crash happens between creation and cleanup, orphaned worktrees accumulate. CLAUDE.md already documents this as a "Common Pitfall" with manual `git worktree remove` as the fix.

**What these hooks do:**

- `WorktreeCreate` fires when a git worktree is created → you can log it, track it
- `WorktreeRemove` fires when cleaned up → you can verify cleanup

**Performance impact:** NEGLIGIBLE. These are event hooks that fire on worktree lifecycle — they don't add latency to the agent's work. A `type: "prompt"` hook on `WorktreeCreate` that logs to `.supervisor/logs/` costs ~2 seconds.

**What this fixes:** Orphaned worktree tracking. Instead of manual cleanup after crashes, you'd have a log of all created worktrees and which were cleaned up.

**Recommendation:** GOOD addition. Low cost, solves a documented problem.

**Risk of degradation:** NEAR ZERO. These hooks fire on infrastructure events, not on agent turns. Even if the hook fails, worktree creation/removal proceeds.

---

### 7. Add StopFailure Hook for API Error Recovery

**[VERDICT: RESOLVED — a `StopFailure` `type: "command"` hook in `loomwright/hooks/hooks.json` appends to `.supervisor/logs/failures.log`, exactly the shape this item recommended]**

**What's happening now:**
If an agent's turn fails due to an API error (rate limit, timeout, server error), the agent just stops. No logging, no state save, no recovery. For the Supervisor in the middle of a 7-phase workflow, this means lost progress.

**What `StopFailure` does:**
Fires when an agent turn ends due to an API error. You can:

- Log the failure to `.supervisor/logs/`
- Save a checkpoint of current state
- Notify the user with context about what was in progress

**Performance impact:** ZERO during normal operation. Only fires on errors. When it does fire, it adds a few seconds to save state — which is exactly what you want during a failure.

**Recommendation:** GOOD addition. Use `type: "command"` (shell script) to append to a log file — fastest possible, no LLM call needed.

```json
{
  "type": "command",
  "command": "echo \"$(date -u +%Y-%m-%dT%H:%M:%SZ) STOP_FAILURE $ARGUMENTS\" >> .supervisor/logs/failures.log"
}
```

**Risk of degradation:** ZERO. Only fires on failure paths. No impact on success paths.

---

### 8. Ship a `bin/` Directory with Helper Scripts

**[VERDICT: RESOLVED (in substance) — the plugin ships `loomwright/scripts/` with 83 runtime helpers (telemetry, webhook, notify, resume, memory, lessons, rules, dispatch, insights, handoff, twin/otel assets + self-tests) invoked via `${CLAUDE_PLUGIN_ROOT}/scripts/…`; realized as `scripts/` rather than a PATH-exposed `bin/`, which fulfills this item's tool-call-efficiency intent]**

**What's happening now:**
Agents use Bash tool calls to run git commands, file operations, and state management. Each bash call is a separate tool invocation consuming the agent's tool-call budget.

**What `bin/` does:**
Plugin ships executables that agents can invoke as bare commands. Instead of 3 separate bash calls to check worktree state, you ship one `worktree-status` script.

**Performance impact:** IMPROVES tool-call efficiency. One script invocation instead of multiple bash calls. For Supervisor with a 50-call budget, this is meaningful.

**However — complexity tradeoff:**

- You now maintain shell scripts alongside markdown prompts
- Scripts need to be cross-platform (macOS/Linux, maybe Windows)
- Debugging gets harder (agent output vs script output)

**Recommendation:** DEFER. The benefit is real but the maintenance cost is high. Only add `bin/` scripts if you identify a specific hot path where multiple bash calls are eating the budget. The Supervisor's worktree management (create, list, remove, merge) is the best candidate.

**Risk of degradation:** LOW risk to agent performance, MODERATE risk to maintainability. Shell scripts are brittle.

---

## P2 — Strategic Improvements

### 9. Add `userConfig` for Install-Time Configuration

**[VERDICT: DEFERRED — no `userConfig` block exists in `loomwright/.claude-plugin/plugin.json`; guided configuration landed post-install instead, via the `/setup` status-dashboard command (`loomwright/commands/setup.md`: observability, telemetry, notifications, webhook, Beads, MySQL MCP, Twin modules)]**

**What's happening now:**
Users configure the plugin by editing CLAUDE.md, environment variables, and manually setting up `.supervisor/`. There's no standard way to set preferences like "max 2 workers" or "always use my-feature-branch naming".

**What `userConfig` does:**
Plugin prompts users at install time for configuration. Values stored in settings, sensitive ones in keychain.

**Performance impact:** NO runtime impact. This is install-time only. But it reduces misconfigurations that cause agents to fail and retry (which wastes budget).

**Recommendation:** GOOD for v10. Add configs for:

- `maxWorkers` (default: 3)
- `branchPrefix` (default: "feature/")
- `dbProfile` (for MySQL MCP, `sensitive: true`)

**Risk of degradation:** ZERO runtime impact. Only changes install experience.

---

### 10. Use `${CLAUDE_PLUGIN_DATA}` for Persistent Plugin State

**[VERDICT: DEFERRED — `${CLAUDE_PLUGIN_DATA}` is unused anywhere in the plugin (this roadmap is its only repo mention, grep 2026-07-06); `.supervisor/` intentionally stays project-local, per this item's own "don't move it" recommendation]**

**What's happening now:**
Plugin state lives in `.supervisor/` inside the project directory. This gets committed to git (or gitignored), varies per project, and can be accidentally deleted.

**What `${CLAUDE_PLUGIN_DATA}` does:**
Gives you a persistent directory that survives plugin updates, outside the project. Good for cross-project plugin config and history.

**Performance impact:** NEUTRAL. Same file read/write, different path.

**Recommendation:** DON'T replace `.supervisor/` with this. `.supervisor/` is project-specific state (current session, worktrees, branches) that belongs in the project. Use `${CLAUDE_PLUGIN_DATA}` only for cross-project data like global agent memory or usage statistics.

**Risk of degradation:** LOW if used for cross-project data only. HIGH if you move `.supervisor/` there — agents expect project-local state.

---

### 11. Evaluate Claude Agent SDK for Supervisor

**[VERDICT: DEFERRED — no SDK rewrite; orchestration remains markdown-prompt-based (inline slash commands + Task spawns, per CLAUDE.md §"`/autonomous` orchestration shell"). `AGENT_GUIDELINES.md` §"Advisor Tool (SDK-only pattern)" documents why deeper SDK/API integration is structurally blocked for plugin subagents today]**

**What's happening now:**
The Supervisor orchestrates via prompt-based coordination — it spawns agents using the Task tool, reads their output, and decides next steps. This is all LLM-mediated: every decision costs a tool call and tokens.

**What the Agent SDK offers:**
Programmatic Python/TypeScript orchestration with `query()` function, hooks as code callbacks, and deterministic control flow (if/else in code, not LLM decisions).

**Performance impact:** POTENTIALLY MUCH FASTER. Deterministic code for phase transitions, retry logic, worktree management. LLM only involved for actual code generation (Workers).

**However:**

- Complete architectural rewrite
- Loses the "everything is markdown prompts" simplicity
- Users need Python/TypeScript runtime
- Debugging shifts from "read the agent's output" to "debug a Python script"

**Recommendation:** DEFER to v11+. This is a fundamental architecture change. The current prompt-based approach works and is much simpler to understand/modify. Only consider this if you hit scale limits (e.g., Supervisor running out of budget on complex projects).

**Risk of degradation:** HIGH short-term (rewrite risk). POTENTIALLY BETTER long-term (deterministic orchestration).

---

### 12. Differentiate from `/batch`

**[VERDICT: DEFERRED — the literal ask (a README `/batch` comparison) was never implemented: neither `README.md` nor `.claude-plugin/README.md` mentions `/batch` (grep 2026-07-06). Positioning evolved differently — the v15.2.1 "Which command?" decision table covers intent-routing, and the north-star direction explicitly declines vendor-parity chasing (`loomwright/docs/SPIKES/NORTH_STAR_DIRECTION.md`), superseding a feature-comparison table]**

**What's happening now:**
Claude Code now ships `/batch` — a built-in command that does parallel work in isolated git worktrees, each opening a PR. This overlaps with the Supervisor's core value proposition.

**Where Supervisor is BETTER:**

- Review gates between tasks (Code Reviewer validation)
- 7-phase workflow with state management
- QA automation (QA Strategist + Executor)
- Sequential merge with conflict detection
- Plan-first approach (Launch Pad)
- Cross-task dependencies

**Where `/batch` is BETTER:**

- Zero setup (built-in)
- Simpler mental model for independent changes
- No plugin needed

**Recommendation:** Don't try to compete on simple parallel changes. Double down on what `/batch` can't do:

- **Review gates** — `/batch` doesn't validate output quality
- **Dependent tasks** — `/batch` is for independent changes only
- **QA integration** — `/batch` doesn't run tests
- **State management** — `/batch` doesn't checkpoint or resume

Update `README.md` to position Supervisor as "what you need when `/batch` isn't enough."

**Risk of degradation:** N/A — this is positioning, not code change.

---

### 13. Add Missing Output Schemas (Launch Pad, Red Team)

**[VERDICT: RESOLVED — both schemas now exist in `loomwright/docs/RESULT_SCHEMAS.md`: `RED_TEAM_RESULT` (schema_version 1, advisory audit tail) and `LAUNCH_PAD_RESULT` (schema_version 1, added v14.2.0, hook-validated by `scripts/validate-launch-pad-result.py`)]**

**What's happening now:**
`RESULT_SCHEMAS.md` defines schemas for `WORKER_RESULT`, `EXECUTE_RESULT`, `CODE_REVIEW_RESULT`, `QA_RESULT`, `QA_SESSION`, `MISSING_FUNCTIONALITY_REPORT`. But Launch Pad and Red Team Reviewer produce structured output with no formal schema.

**Performance impact:** NO runtime impact. Schemas are documentation that hooks validate against. Adding schemas enables future validation hooks for these agents.

**Risk of degradation:** ZERO. Documentation-only change.

---

### 14. Add QA Failure Escalation to Docs

**[VERDICT: RESOLVED — `loomwright/docs/FAILURE_ESCALATION.md` now documents both "QA Executor Failure" and "QA Strategist Failure" escalation paths, and its header lists QA Strategist + QA Executor among the referencing agents]**

**What's happening now:**
`FAILURE_ESCALATION.md` covers Worker, Execute Manager, and Supervisor failure paths. QA Strategist and QA Executor have no documented escalation — if QA Executor's Playwright tests fail to install, or QA Strategist's verdict is rejected, there's no documented recovery path.

**Performance impact:** NO runtime impact. Documentation enables better human decision-making when things go wrong, reducing wasted retry cycles.

**Risk of degradation:** ZERO. Documentation-only.

---

## P3 — Polish

### 15. Fix Version References in AGENT_GUIDELINES.md

**[VERDICT: RESOLVED — the stale references this item names ("Supervisor v3", "v5.x", "v7.x") no longer exist in `AGENT_GUIDELINES.md` (grep-clean 2026-07-06); the remaining version mentions there are dated historical notes, not stale current-state claims, and hook/count claims match the authoritative sources]**

**What:** Lines referencing "Supervisor v3" should say "v4". Multiple places say "v5.x", "v7.x" patterns.

**Performance impact:** ZERO. Documentation clarity. But stale version references confuse agents that read `AGENT_GUIDELINES.md` at startup — they might apply outdated patterns.

**Risk of degradation:** ZERO.

---

### 16. Add Supervisor `maxTurns`

**[VERDICT: RESOLVED — `agents/supervisor.md:6` carries `maxTurns: 60`; the item body below already records the resolution]**

**What's happening now:**
**Resolved — `supervisor.md` frontmatter now carries `maxTurns: 60`** (historically it had none and relied solely on its internal tool-call budget). But `maxTurns` is enforced by Claude Code infrastructure — without it, the Supervisor could theoretically run indefinitely if its self-tracking fails.

**Performance impact:** PREVENTS runaway agents. If Supervisor's internal budget tracking fails (LLM hallucination), `maxTurns` is the hard stop. Without it, a stuck Supervisor burns tokens indefinitely.

**What value to set:** The Supervisor delegates Phase 3 to Execute Manager. Its own work is phases 1-2 and 4-6 plus the Phase 4.5 self-heal orchestration (init, acquire, plan, finalize, self-heal, loop). 50 tool calls is right for this. But `maxTurns` counts LLM turns, not tool calls — set it slightly higher (e.g., 60) to account for turns that don't use tools.

**Risk of degradation:** LOW. If set too low, Supervisor gets cut off mid-workflow. 60 keeps the same headroom over the 50-call budget that 40 gave the old 30-call budget.

---

### 17. Fix Code Reviewer Hook Naming

**[VERDICT: RESOLVED — the Code Reviewer `Stop` completeness hook now lives in `loomwright/hooks/hooks.json` (alongside its `SubagentStop` validator), per this item's "keep both, move to hooks.json" recommendation; the frontmatter copy is retained only for `~/.claude/agents/` compatibility]**

**What's happening now:**
`code-reviewer.md` line 18 uses `Stop:` while Worker and Execute Manager use `SubagentStop:`. These are different hook events:

- `Stop` → fires when the agent itself finishes its session
- `SubagentStop` → fires when a parent observes its subagent finishing

The Code Reviewer has BOTH:

- `Stop:` in frontmatter (line 18) — validates before it finishes
- `SubagentStop` in `hooks.json` (line 6) — validates when parent sees result

This is actually **correct and intentional** — double validation. The naming isn't inconsistent, it's a different hook type.

**Updated recommendation:** DON'T change this. `Stop` and `SubagentStop` are different events serving different purposes. The Code Reviewer correctly uses both: self-validation before finishing (`Stop`) and external validation when parent reads output (`SubagentStop`).

**However:** Per P0 item #1, the `Stop` hook in frontmatter is silently ignored for plugin agents. So move it to `hooks.json`.

**Risk of degradation:** If you rename `Stop` to `SubagentStop`, you lose the self-validation gate. Keep both, but move them to `hooks.json`.

---

### 18. Consider Prisma/GraphQL/gRPC Skills

**[VERDICT: DEFERRED — on-demand as this item recommended; no `prisma`/`graphql`/`grpc` skill dirs exist among the 57 skills in `loomwright/skills/` (2026-07-06), and no user demand has materialized]**

**What's happening now:**
49 skills covering NestJS, Next.js, TypeORM, Drizzle, MySQL, PostgreSQL, Redis, Docker, etc. Missing: Prisma ORM, GraphQL, gRPC.

**Performance impact:** NONE for existing users. Skills are only loaded when referenced by agents. New skills don't slow anything down.

**Risk of degradation:** ZERO. Additive change. But each skill adds maintenance burden — only add if there's user demand.

---

## Summary: What to Actually Do

| # | Change | Performance Effect | Risk | Do It? |
|---|--------|-------------------|------|--------|
| 1 | Move per-agent hooks to `hooks.json` | Restores broken safety gates | Zero | **YES NOW** |
| 2 | Add Supervisor hook | +2-5s on completion, catches failures | Very low | **YES NOW** |
| 3 | Upgrade select hooks to `type: "agent"` | +15-60s per hook (only where needed) | Moderate | **SELECTIVE** |
| 4 | `effort: low` on Context-Keeper, `high` on Red Team | Faster state writes, deeper security analysis | Low | **YES** |
| 5 | `initialPrompt` on Supervisor | Saves ~5s, risk of conflicts | Moderate | **SKIP** |
| 6 | Worktree lifecycle hooks | Negligible cost, tracks orphans | Near zero | **YES** |
| 7 | `StopFailure` hook | Zero (only fires on error) | Zero | **YES** |
| 8 | `bin/` directory | Saves tool calls, adds maintenance | Moderate | **DEFER** |
| 9 | `userConfig` | Zero runtime | Zero | **v10** |
| 10 | `${CLAUDE_PLUGIN_DATA}` | Neutral | Low-High | **CROSS-PROJECT ONLY** |
| 11 | Agent SDK for Supervisor | Potentially much faster | High (rewrite) | **DEFER v11+** |
| 12 | Differentiate from `/batch` | N/A (positioning) | N/A | **YES (README)** |
| 13 | Launch Pad + Red Team schemas | Zero (docs only) | Zero | **YES** |
| 14 | QA failure escalation docs | Zero (docs only) | Zero | **YES** |
| 15 | Fix version references | Zero (docs only) | Zero | **YES** |
| 16 | Supervisor `maxTurns` (60 since the 50-call budget; was 40) | Prevents runaway agents | Low | **YES** |
| 17 | Move Code Reviewer `Stop` hook to `hooks.json` | Restores self-validation | Low | **YES (with P0 #1)** |
| 18 | Prisma/GraphQL/gRPC skills | None (additive) | Zero | **ON DEMAND** |

### Implementation Order

1. **Immediate (P0):** Items 1, 2, 16, 17 — fix broken safety gates and add missing guardrails
2. **Next sprint (P1):** Items 4, 6, 7 — leverage new features for better safety and performance
3. **v10 planning (P2):** Items 9, 12, 13, 14, 15 — strategic positioning and documentation
4. **Deferred:** Items 3, 5, 8, 10, 11, 18 — evaluate when specific pain points emerge
