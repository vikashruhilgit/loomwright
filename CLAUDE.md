# CLAUDE.md

Guidance for Claude Code when working in this repository.

- User-facing docs (install, quick start, commands, troubleshooting): `README.md`
- Development standards & shared agent contract: `AGENT_GUIDELINES.md`
- This file captures what's *not* obvious from those — invariants, schemas, hooks, and incident-derived gotchas

---

## Project Overview

**AI Agent Manager** is a Claude Code plugin with 13 agent roles (8 user-facing + 5 internal) for plan-first readiness, parallel execution, requirements, planning, code review, commits, adversarial audits, and dual-agent QA. Supervisor and Launch Pad use `.supervisor/` exclusively for state; Orchestrator and Product Owner can optionally use Beads.

**v13.0.0 — Foreground-assisted goal-completion loop:** One new user-facing addition on top of v12.2.0 — the **`/autonomous` slash command** at `ai-agent-manager-plugin/commands/autonomous.md`, governed by `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md`. It is an inline main-thread workflow (same execution model as `/launch-pad` and `/supervisor` — no new delegated agent) that chains Launch Pad → Supervisor for a single requirement. In the **default single-iteration mode**, it just runs both inline and emits an `AUTONOMOUS_RUN` summary; this is command chaining, nothing more. In opt-in **multi-iteration mode** (`--allow-multi-iteration --max-iterations N`, default `N=3`), an EVALUATE phase reads `SUPERVISOR_RESULT` and re-plans on exactly two signals: (1) `status: completed` with `rubric_score N/M` where N<M (loop pauses for a **rubric-gate `AskUserQuestion`** — merge-and-continue verified via `gh pr view` / `git merge-base --is-ancestor` / stop-here / force-continue-anyway), (2) `status: failed` with `inter_subtask_gap` detected on this iteration's brief via anchor-by-filename (`.supervisor/jobs/failed/{basename(current_brief_path)}` existence + `inter_subtask_gap` found in any of three iteration-scoped sources: the failed brief's contents, `SUPERVISOR_RESULT.error`, or `SUPERVISOR_RESULT.summary`; `.supervisor/state.md` is intentionally NOT consulted because pre-rewrite stale content could false-positive — see `skills/autonomous-loop/SKILL.md` Signal 2 algorithm comment block). The loop **never auto-picks** on adjudication — Supervisor's existing 4-option `AskUserQuestion` surfaces in-session; the loop's value is automating the re-plan that Option C ("Exit to Launch Pad") already requires the user to do by hand. **Foreground-assisted automation, not fire-and-forget**: Launch Pad Phase 6, NO-GO, Plan Review FAIL × 3, Supervisor adjudication, and the rubric gate all bubble `AskUserQuestion` in-session. v13 is **purely additive** — no new agent, no new hook, no behavioral change to any existing agent / hook / script / skill / command, and no change to the field types or validation rules of any existing schema. New artifacts only: one new slash command (`/autonomous`), one new skill (`autonomous-loop`), one new schema entry in `RESULT_SCHEMAS.md` (the `AUTONOMOUS_RUN` summary block, autonomous-layer-only, no hook validation). Metadata/docs surfaces (`CLAUDE.md`, `README.md`, marketplace and plugin manifests, `agent-help.md`, `SKILLS_INDEX.md`) updated to reflect counts and the new entries. All v12.2.0 capabilities preserved (Agent Teams graduation matrix, Outcomes Rubric, `/dreaming`, opt-in webhook hook), v12.1.0 documentation increments preserved (Memory Tool, Structured Outputs, SDK-only Advisor note), v12.0.0 reliability primitives intact (`provides`/`requires` contracts, pre-spawn verification gate, 4-option adjudication, effort-tier discipline, WORKER_RESULT schema_version 2 with `outputs_verified[]` + `outputs_gap`).

---

## Plugin Layout

The repo is a **marketplace wrapper** containing one nested plugin:

- Marketplace manifest: `.claude-plugin/marketplace.json` (root)
- Plugin manifest: `ai-agent-manager-plugin/.claude-plugin/plugin.json` (v13.0.0)
- Agents: `ai-agent-manager-plugin/agents/` (13 markdown prompts)
- Commands: `ai-agent-manager-plugin/commands/` (12 entry points)
- Skills: `ai-agent-manager-plugin/skills/` (50 skills, see `SKILLS_INDEX.md`)
- Hooks: `ai-agent-manager-plugin/hooks/hooks.json`
- Docs: `ai-agent-manager-plugin/docs/`
- Bundled MCP: read-only MySQL server (`vikashruhil-mysql-mcp`)

> **Repo path vs. runtime path:** `ai-agent-manager-plugin/...` is the developer-side path (this repo on disk). Anything invoked by hooks, skills, or agents at *runtime* must reference `${CLAUDE_PLUGIN_ROOT}/...` — that's the canonical Claude Code variable that resolves to the plugin install dir on both dev checkouts and marketplace installs. Never use `ai-agent-manager-plugin/...` paths from the user-project root; they only resolve for the plugin maintainer.

### Directory Structure

```
ai-agent-manager/                              # marketplace wrapper
├── .claude-plugin/
│   ├── marketplace.json                       # marketplace manifest (root)
│   └── README.md                              # plugin-facing usage guide
├── ai-agent-manager-plugin/                   # nested plugin
│   ├── .claude-plugin/plugin.json
│   ├── .mcp.json                              # bundled MCP servers
│   ├── agents/                                # 13 markdown prompts
│   ├── commands/                              # 12 slash commands
│   ├── hooks/hooks.json                       # cross-cutting hooks
│   ├── skills/                                # 50 skills + SKILLS_INDEX.md
│   ├── scripts/                               # send-telemetry.sh, send-telemetry-core.sh, send-webhook.sh, telemetry-fixtures/
│   └── docs/                                  # RESULT_SCHEMAS, FAILURE_ESCALATION, ARCHITECTURE_CONTRACTS, ARCHITECTURE, QA_SYSTEM_BLUEPRINT, TELEMETRY
│       └── SPIKES/                            # Capability spike investigations + deferral records
├── scripts/                                   # validate-version.sh, check-command-sync.sh
├── README.md                                  # user-facing docs
├── AGENT_GUIDELINES.md                        # standards, agent contract
└── CLAUDE.md                                  # this file
```

---

## The 13 Agent Roles

Detailed per-agent purpose, command syntax, and workflow diagrams live in `README.md` §"The 13 Agents" and the agent prompts (`ai-agent-manager-plugin/agents/*.md`). Quick map of what matters for in-codebase work:

| Agent | Type | Spawned by | Codebase-relevant invariants |
|---|---|---|---|
| Launch Pad | user-facing | user | Phase 2.5 feasibility (GO/CAUTION/NO-GO); Phase 5.5 mandatory Plan Review (max 3 retries); writes briefs to `.supervisor/jobs/pending/` |
| Supervisor | user-facing | user | v4 + Phase 4.5 self-heal — phase **always** runs; `--skip-self-heal` only short-circuits the loop; completion-tail relocates job-move + state-completed from FINALIZE |
| Product Owner | user-facing | user | Assumption Check (standard) + Reality Check (`--brainstorm`) cap Feasibility for NEEDS_FOUNDATION/BLOCKED ideas |
| Orchestrator | user-facing | user | Reads CLAUDE.md + Beads → EPIC / TASK / SUBTASK with skill references |
| Code Reviewer | user-facing | user | LSP, read-only mode, schema_v3 (adds `drift` category, severity caps via hook). **Auto-expands to consistency audit** when diff touches `agents/`, `commands/`, `skills/`, `docs/`, or plugin metadata |
| Red Team Reviewer | user-facing | user | 6 attack vectors; persistent memory of past audits |
| QA Strategist | user-facing | user | Strategy mode + Audit mode; spawned twice (gate audit Phase 11, results audit Phase 13) |
| QA Executor | user-facing | user | 13-phase, `--depth smoke|functional`, `--plan/--scope/--continue`, infrastructure-aware (Mailpit/MailHog), 80/90 budget |
| Execute Manager | internal | Supervisor (Phase 3) | Owns poll loop in isolated context, 60 tool-call budget |
| Context-Keeper | internal | Supervisor / Execute Manager | **Sole writer** of state file; haiku model, batch updates, atomic writes |
| Worker | internal | Execute Manager / Supervisor | One subtask per worktree, no git ops, emits WORKER_RESULT + `.worker-summary.md` |
| Plan Reviewer | internal | Launch Pad | PLAN_REVIEW_RESULT decision gates the brief save — PASS saves; NEEDS_HUMAN saves only on explicit user override; FAIL never saves |
| Rubric Grader | internal | Supervisor (Phase 4.5, only when brief has `## Outcomes Rubric` and `heal_decision == PASS`) | Read-only Haiku scorer; runtime read-only enforcement comes from `disallowedTools: Write, Edit, Task, NotebookEdit` (the frontmatter-level enforcement that survives plugin distribution — `permissionMode: plan` is preserved for `~/.claude/agents/` compatibility but is silently ignored by Claude Code for plugin agents); emits per-item `ITEM N: PASS\|FAIL` lines + `rubric_score: N/M`; advisory only — never changes `heal_decision` or blocks the PR |

### `/autonomous` orchestration shell (v13.0.0)

`/autonomous` is **not a new agent.** It is an inline main-thread slash command (`ai-agent-manager-plugin/commands/autonomous.md`) governed by `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md`. The same execution model as `/launch-pad` and `/supervisor`: the slash command body is workflow instructions executed inline on the main thread. The main thread reads `commands/launch-pad.md` and `commands/supervisor.md` at Step 0 (to avoid prompt drift), then runs Launch Pad inline (which still Task-spawns `plan-reviewer`), then runs Supervisor inline (which still Task-spawns `orchestrator` / `execute-manager` / `code-reviewer` / `rubric-grader`).

**Default mode is single-iteration:** just runs Launch Pad → Supervisor once and emits an `AUTONOMOUS_RUN` summary. Multi-iteration mode (`--allow-multi-iteration`, opt-in) adds an EVALUATE phase that re-plans on two specific `SUPERVISOR_RESULT` signals (rubric_score N<M gated on user-merge verification; failed + inter_subtask_gap anchored by `.supervisor/jobs/failed/{basename(current_brief_path)}` existence). The loop never auto-picks on adjudication — Supervisor's existing 4-option `AskUserQuestion` surfaces in-session as it does today; the loop only automates the re-plan that Option C ("Exit to Launch Pad") already requires the user to do by hand.

State writes are confined to `.supervisor/autonomous/{session_id}/` (the loop's own state), `.supervisor/requirements/` (the requirement files), and one append-only JSONL session log at `.supervisor/logs/{session_id}.jsonl` (matches the existing per-session log convention shared with `/supervisor`). Supervisor remains the sole writer of `.supervisor/jobs/` and `.supervisor/state.md` per existing contracts. `AUTONOMOUS_RUN` uses an autonomous-layer-only status enum (`done | paused_max_iterations | aborted | failed`) intentionally distinct from `SUPERVISOR_RESULT.status` to avoid schema collision; the summary is plain markdown plus a JSON sidecar (no hook validation, no resume contract in v1 — those are future work).

### Shared Agent Contract

Every agent (full standard in `AGENT_GUIDELINES.md`):

- **Mission:** smallest correct thing that advances the objective
- **Output:** Context Read → Plan → Work → Results → Risks
- **Frontmatter:** `tools`, `model`, `maxTurns`, `color`, `disallowedTools`, `skills`, `memory`, per-agent `hooks`, `effort`, `permissionMode`
- **Safety:** no destructive actions without explicit approval; never invent files/APIs/paths; merge conflicts always escalate
- Language-agnostic; per-language standards in `AGENT_GUIDELINES.md`

**Self-heal pattern (v11.0.0):** Phase 4.5 SELF_HEAL runs Code Reviewer on the integrated feature-branch diff after FINALIZE creates the PR, then auto-fixes bounded BLOCKING/HIGH `new` issues (up to `--heal-iterations`, default 3). Job-file move and `state.md` "completed" marker live in SELF_HEAL's completion tail — not FINALIZE — so the record captures heal outcome. `SUPERVISOR_RESULT` is validated by SubagentStop hook.

### Parallel Execution Model

- Supervisor v4 delegates Phase 3 to Execute Manager for multi-subtask workflows
- Execute Manager owns the poll loop, worker/reviewer lifecycle, Context-Keeper coordination
- Each worker runs in its own git worktree (no file conflicts)
- Workers write `.worker-summary.md` for lightweight result extraction
- Context-Keeper externalizes state; Supervisor uses tool-call budgets (30) instead of percentage thresholds; Execute Manager has its own 60-call budget in isolated context
- Subtask branches merge sequentially into the feature branch with pre-merge validation
- Fast-path: single subtask skips worktrees and Execute Manager entirely

---

## Adding or Modifying Agents

1. **New agent:** `.md` in `ai-agent-manager-plugin/agents/` with YAML frontmatter; output follows Context Read → Plan → Work → Results → Risks
2. **New slash command:** `.md` in `ai-agent-manager-plugin/commands/` referencing the agent prompt
3. **New skill:** `SKILL.md` in `ai-agent-manager-plugin/skills/[name]/` with version frontmatter; update `SKILLS_INDEX.md`
4. **Test locally:**
   ```
   /plugin uninstall ai-agent-manager-plugin
   /plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
   ```
   Verify with `/agent-help`
5. **Cite exact `file:line` numbers when referencing code**

**Hook gotcha:** Claude Code silently ignores `hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter — only `hooks.json` hooks fire for plugin-distributed agents. Per-agent frontmatter hooks are kept for `~/.claude/agents/` compatibility.

---

## Structured Contracts (v9.0.0)

- **Result Schemas** — `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`. CODE_REVIEW_RESULT at `schema_version: 3` (adds `review_mode` (`diff_review` | `consistency_audit`), `audit_focus[]`, `trigger_paths_detected[]`, `scope_expanded[]`, `files_checked[]`, `consistency_checks`, `consistency_summary`, and the `drift` issue category with `drift_kind` + severity caps; v2 accepted for legacy artifacts). WORKER_RESULT at `schema_version: 2` (adds `outputs_verified[]` + `outputs_gap`; v1 accepted for the v12.0.0 transition window). All others at `schema_version: 1`.
- **Failure Escalation** — `…/FAILURE_ESCALATION.md` (retry limits, escalation paths)
- **Architecture Contracts** — `…/ARCHITECTURE_CONTRACTS.md` (capability matrix, context budgets, timeouts, worktree naming)
- **Job Lifecycle** — briefs flow `pending/` → `in-progress/` → `done/` / `failed/` in `.supervisor/jobs/`
- **Session Logging** — JSONL in `.supervisor/logs/{session_id}.jsonl`
- **Merge Safety Gate** — pre-merge checklist in FINALIZE prevents corrupted partial merges

---

## Plugin Hooks (Quality Gates)

14 hooks centralized in `hooks.json` since v10.0.0 (the v12.2.0 webhook hook brought the count from 13 → 14; v13.0.0 adds no new hooks). Prompt-based validation uses fast haiku model with 30s timeout. WorktreeCreate / StopFailure / telemetry / webhook hooks use `type: command` for zero-latency.

| Hook | Trigger | Location | Validation |
|------|---------|----------|------------|
| SubagentStop (worker) | Worker completes | hooks.json + frontmatter | WORKER_RESULT (schema_version, task_id, status, files_modified) |
| SubagentStop (execute-manager) | Execute Manager completes | hooks.json + frontmatter | EXECUTE_RESULT / EXECUTE_CHECKPOINT |
| SubagentStop (code-reviewer) | Code Reviewer completes | hooks.json | CODE_REVIEW_RESULT v3 with decision + issue categories |
| SubagentStop (supervisor) | Supervisor completes | hooks.json | Session outcome, subtask statuses, PR URL |
| SubagentStop (qa-executor) | QA Executor completes | hooks.json | QA_RESULT (tests_generated, tests_passed, summary) |
| SubagentStop (plan-reviewer) | Plan Reviewer completes | hooks.json | PLAN_REVIEW_RESULT (schema_version, decision, issues, summary) |
| SubagentStop telemetry × 3 | code-reviewer / qa-executor / supervisor-runner complete | hooks.json | type:command — wrapper exits 0 always; pipes payload to `send-telemetry-core.sh` |
| Stop (code-reviewer) | Code Reviewer finishing | hooks.json + frontmatter | CODE_REVIEW_RESULT block present |
| TaskCompleted | Task marked complete | hooks.json | Task genuinely done |
| WorktreeCreate | Worktree created | hooks.json | type:command, logs `.supervisor/logs/worktrees.log` |
| StopFailure | Agent API error | hooks.json | type:command, logs `.supervisor/logs/failures.log` |
| SubagentStop webhook (supervisor-runner) | Supervisor completes | hooks.json | type:command — `send-webhook.sh`; gated on `AI_AGENT_MANAGER_WEBHOOK_URL`; fire-and-forget POST; always exits 0 |

---

## Telemetry System (opt-in, v11.2.0 — preserved in v13.0.0)

After qualifying runs (`supervisor-runner`, `code-reviewer`, `qa-executor`), a SubagentStop `type: command` hook invokes `${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry.sh` (the wrapper — `${CLAUDE_PLUGIN_ROOT}` is the canonical Claude Code variable for plugin-bundled assets and resolves to the plugin install dir on both dev checkouts and marketplace installs; never use `ai-agent-manager-plugin/...` paths from the user-project root, those only resolve for the plugin maintainer). The wrapper is fire-and-forget and **always exits 0**; it pipes the hook payload to `send-telemetry-core.sh`, which parses the result block, derives a deterministic score, runs a regex-based privacy whitelist, and (when consent + target repo are configured) calls `gh issue create` with a structured body covering Task Summary, Agent Scores, Issues Detected, AI Suggestions, Tools Used, and a redacted JSON payload.

- **Privacy fail-closed:** any whitelist match aborts the post; core exits `2`
- **Core exit codes 0..5:** sent / generic_error / privacy_blocked / no_consent / no_repo_configured / filter_skipped
- **No origin-remote fallback** — the plugin runs in arbitrary user projects whose origin is the user's app repo, which is the wrong place for telemetry
- **Disabled by default.** Enable via `/telemetry enable` (interactive — pick target repo) or `AI_AGENT_MANAGER_TELEMETRY_REPO=owner/repo`. Hooks **never** prompt — consent flows only through `/telemetry`.

| Command | Purpose |
|---------|---------|
| `/telemetry status` | consent state, resolved target repo + source, last-sent timestamp, retained per-session pending markers (~24h window) |
| `/telemetry enable` | interactive — collects target repo via `AskUserQuestion`, writes `{"telemetry":"always_allow","telemetry_repo":"<owner/repo>"}` to `.supervisor/telemetry-consent.json`. Sole first-run consent path. |
| `/telemetry disable` | writes `{"telemetry":"no"}` to the consent file; subsequent hook fires log a single "denied — skipped" line per session and never call `gh` |
| `/telemetry test` | dry-run a fixture or the latest log payload through `send-telemetry-core.sh --dry-run`; prints target repo, formatted body, and `WOULD_EXIT` without calling `gh` |

Full design (scoring rubric per result-block schema, privacy whitelist, exit-code table, wrapper-vs-core architecture, plugin-internal vs repo-root `scripts/` convention): `ai-agent-manager-plugin/docs/TELEMETRY.md`.

---

## Persistent Memory

Agents with `memory: project` in frontmatter accumulate knowledge across sessions:

| Agent | Storage |
|-------|---------|
| Launch Pad | `.claude/agent-memory/ai-agent-manager-plugin:launch-pad-runner/` |
| Code Reviewer | `.claude/agent-memory/ai-agent-manager-plugin:code-reviewer/` |
| Red Team Reviewer | `.claude/agent-memory/ai-agent-manager-plugin:red-team-reviewer/` |
| Product Owner | `.claude/agent-memory/ai-agent-manager-plugin:product-owner/` |
| QA Strategist | `.claude/agent-memory/ai-agent-manager-plugin:qa-strategist/` |
| QA Executor | `.claude/agent-memory/ai-agent-manager-plugin:qa-executor/` |

> Decision aid for *what* to write to those memory directories: `ai-agent-manager-plugin/skills/memory-tool/SKILL.md` (reference skill — not pre-loaded; consult on demand when tagging conventions or Memory-Tool-vs-file-based questions arise).

## Skills Preloading

Agents with `skills` in frontmatter get content pre-injected at spawn time (no runtime file-read):

| Agent | Pre-loaded skills |
|-------|-------------------|
| Launch Pad | supervisor-readiness, context-setup, claude-md-validation, product-discovery, mvp-scoping, quality-checklist, context7-lookup |
| Supervisor | workflow-management, async-orchestration, state-management, context-summarization, supervisor-readiness |
| Orchestrator | quality-checklist |
| Code Reviewer | quality-checklist, context7-lookup, unit-testing, error-handling, monitoring-observability |
| Red Team Reviewer | context7-lookup |
| QA Strategist | qa-strategy, quality-checklist |
| QA Executor | qa-strategy, playwright-e2e, quality-checklist |
| Product Owner | brainstorming, product-discovery, mvp-scoping |

## Agent Teams (Recommended for 3 Use Cases, Experimental for the Rest)

Native Claude Code multi-agent coordination — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Best for research, competing hypotheses, cross-layer changes; not for sequential tasks or same-file edits (use Supervisor with worktrees). Patterns + decision matrix: `ai-agent-manager-plugin/skills/agent-teams/SKILL.md`. Complementary to Supervisor v4, not a replacement.

---

## Cost Profile

`/supervisor --cheap` — opt-in flag that overrides execution-shaped roles (orchestrator, execute-manager, worker, code-reviewer, Phase 4.5 fix tasks) to Sonnet at spawn time. Default behavior (`inherit` for all) unchanged. Profile table, semantics, and Haiku-session caveat: `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles".

---

## Common Pitfalls

### `/supervisor` or `/launch-pad` aborted with "Task/Agent tool unavailable"?
- Pre-11.1.1 name-collision trap: the slash command silently auto-delegated to a same-named registered subagent, which couldn't spawn its own children ([docs](https://code.claude.com/docs/en/sub-agents): *"Subagents cannot spawn other subagents"*).
- Fix in 11.1.1: registered agents are now `ai-agent-manager-plugin:supervisor-runner` and `ai-agent-manager-plugin:launch-pad-runner`. The slash commands are inline main-thread workflows; the `-runner` suffix lets `claude --agent ai-agent-manager-plugin:supervisor-runner` own a session without re-introducing auto-delegation.
- For an agent-owned session: `claude --agent …-runner`. Otherwise stay on the main thread via the slash command.

### `/supervisor` completed but skipped Phase 4.5 (or Phase 3 child agents)?
- **What this is:** inline main-thread execution misread as permission to stop orchestrating. "Don't delegate to `supervisor-runner`" does NOT mean "do everything yourself." Still spawn first-level children via Task — `orchestrator` (Phase 2), `execute-manager` or fast-path worker/reviewer (Phase 3), `code-reviewer` + fix loop (Phase 4.5).
- **Fix in 11.1.2:** Phase 4.5 completion-tail guard (`ai-agent-manager-plugin/agents/supervisor.md`) refuses a successful `SUPERVISOR_RESULT` when `skip_self_heal_requested=false` AND `phase45_review_invoked=false`. Run self-reports `status: failed`; job stays in `in-progress/`.
- **Recovery for pre-11.1.2 runs (operator workaround — unsupported, manual):**
  1. `/code-reviewer` has no first-class branch-vs-branch diff mode. Compute scope via `git diff --name-only origin/main...HEAD` and pass that file list to `/code-reviewer`, OR pipe `git diff origin/main...HEAD` into a manual review.
  2. Fix any new BLOCKING/HIGH issues; push to feature branch.
  3. Update `.supervisor/` state and the job file by hand. NOT supported — will become `/supervisor --recover-self-heal` in a follow-up PR.
- **Intentional skip:** re-run with `--skip-self-heal` (the guard accepts it as a recorded deliberate choice).

### Agents don't understand project structure?
Update the project's CLAUDE.md with concrete patterns and `file:line` references. Agents re-read at session start.

### Beads tasks not appearing?
`bd list` to check; ensure `bd init` ran. Beads is only used by Orchestrator/Product Owner — Supervisor/Launch Pad don't need it.

### Supervisor workflow interrupted?
State auto-saves to `.supervisor/state.md`. Resume with `/supervisor --continue task: BD-XX`. Check `.supervisor/history/` for completed sessions.

### Orphaned worktrees after crash?
`git worktree list`; `git worktree remove ../project-BD-XXa`; `git branch -d feature/BD-XXa`.

### `/autonomous` brief-save detection is single-session-only (v1)
The PLAN phase detects the saved brief via `ls`-diff of `.supervisor/jobs/pending/` (snapshot before Phase 6's save prompt, snapshot after, take the new file). This works for a single autonomous run but cannot distinguish a concurrent `/launch-pad` or second `/autonomous` session writing to the same `pending/` directory. v1 detects the multi-file case and aborts cleanly with `status_reason="concurrent_session_detected"`, but the safe operating rule is one autonomous / launch-pad invocation at a time per repo. The proper fix is a `LAUNCH_PAD_RESULT` schema with a `saved_brief_path` field emitted by Launch Pad — that lands in a separate follow-up plan and is the single biggest leverage point for hardening `/autonomous`.

### `/autonomous --cheap` is unsupported in v1
The loop does not forward unknown flags into the inlined `/supervisor` call. Run `/launch-pad` and `/supervisor --cheap` manually if you need the Sonnet cost profile for a one-off requirement. See `commands/autonomous.md` "Parameters" → `--cheap interaction note` for details.

---

## References

- User-facing: `README.md`, `.claude-plugin/README.md`
- Standards: `AGENT_GUIDELINES.md`
- Manifests: `.claude-plugin/marketplace.json`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`
- Schemas / contracts / failure modes: `ai-agent-manager-plugin/docs/{RESULT_SCHEMAS,ARCHITECTURE_CONTRACTS,FAILURE_ESCALATION,ARCHITECTURE,QA_SYSTEM_BLUEPRINT,TELEMETRY}.md`
- Skills index: `ai-agent-manager-plugin/skills/SKILLS_INDEX.md`
