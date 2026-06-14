# CLAUDE.md

Guidance for Claude Code when working in this repository.

- User-facing docs (install, quick start, commands, troubleshooting): `README.md`
- Development standards & shared agent contract: `AGENT_GUIDELINES.md`
- This file captures what's *not* obvious from those — invariants, schemas, hooks, and incident-derived gotchas

---

## Project Overview

**AI Agent Manager** is a Claude Code plugin with 14 agent roles (9 user-facing + 5 internal) for plan-first readiness, parallel execution, requirements, planning, code review, commits, adversarial audits, standalone PR review-and-heal, and dual-agent QA. Supervisor and Launch Pad use `.supervisor/` exclusively for state; Orchestrator and Product Owner can optionally use Beads.

**v14.26.0 — Requirement→brief→done close-out loop (Beads-optional):** Closes the Beads-absent requirement lifecycle so a `.supervisor/requirements/*.md` story is marked done when its work lands. Launch Pad (the producer) records `source_requirement` provenance at Phase 2 step 0 and stamps a `- **Source requirement:** {path}` line under the brief's `## Environment` (Phase 5 step 3a) — emitted only for `.supervisor/requirements/*.md` inputs, omitted otherwise. Supervisor's Phase 4.5 SELF_HEAL completion tail (the consumer) reads that pointer and stamps an idempotent `## Status` block (`**Status:** done`, `Completed`, `Brief`, `PR`) on the originating requirement file: **Beads-absent only** (`bd close` owns state when Beads is active), **success-only** (PASS / loop-skipped / ESCALATED — never on a failed run), path-guarded (under `.supervisor/requirements/` + `test -f`), **fail-safe** (any error is a logged no-op, never fails the run), and **idempotent** (replace-not-duplicate). Documented in `docs/RESULT_SCHEMAS.md` as two additive brief/requirement file conventions mirroring the brief `## Outcome` pattern. Prompt/doc-only: `agents/launch-pad.md`, `agents/supervisor.md`, `skills/supervisor-readiness/SKILL.md`, `docs/RESULT_SCHEMAS.md`. **No new agent/command/skill/hook; counts unchanged at 14 agents / 18 commands / 54 skills / 19 hooks; no schema_version bumps.** Additive on top of v14.25.1.

**v14.25.1 — Codify illustrative example values as version-agnostic (patch):** Stale-looking `plugin_version` values in *illustrative* example blocks (sample `session_end` / `POSTMORTEM_RESULT` JSONL records + `e.g. "X.Y.Z"` prose placeholders in `docs/RESULT_SCHEMAS.md` and `agents/supervisor.md`) read as drift in review, but they have no currency requirement — the real value is read at runtime from `plugin.json` via jq, and `check-doc-currency.sh` deliberately does not scan them; bumping them per-release is a drift-treadmill the gate cannot enforce. Rather than chase them, this patch **codifies the convention** that illustrative example values are version-agnostic and frozen (documented in §"Doc currency is CI-enforced" and beside the `plugin_version` field spec in `docs/RESULT_SCHEMAS.md`) so future reviews don't re-flag them; genuine current-claims still track the live version and advance to 14.25.1. **No example values bumped. Documentation-only; no schema_version bumps; counts unchanged at 14 agents / 18 commands / 54 skills / 19 hooks.** Additive patch on top of v14.25.0.

> 📜 **Full release history** (v14.25.0 → v14.0.0 and earlier) lives in [`CHANGELOG.md`](CHANGELOG.md). CLAUDE.md keeps only the two most recent release notes.

---

## Plugin Layout

The repo is a **marketplace wrapper** containing one nested plugin:

- Marketplace manifest: `.claude-plugin/marketplace.json` (root)
- Plugin manifest: `ai-agent-manager-plugin/.claude-plugin/plugin.json` (v14.26.0)
- Agents: `ai-agent-manager-plugin/agents/` (14 markdown prompts)
- Commands: `ai-agent-manager-plugin/commands/` (18 entry points)
- Skills: `ai-agent-manager-plugin/skills/` (54 skills, see `SKILLS_INDEX.md`)
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
│   ├── agents/                                # 14 markdown prompts
│   ├── commands/                              # 18 slash commands
│   ├── hooks/hooks.json                       # cross-cutting hooks
│   ├── skills/                                # 54 skills + SKILLS_INDEX.md
│   ├── scripts/                               # runtime helpers: telemetry, webhook, notify, resume, memory, lessons, insights, otel stack assets (+ self-tests, fixtures)
│   └── docs/                                  # RESULT_SCHEMAS, FAILURE_ESCALATION, ARCHITECTURE_CONTRACTS, ARCHITECTURE, QA_SYSTEM_BLUEPRINT, TELEMETRY, OBSERVABILITY
│       └── SPIKES/                            # Capability spike investigations + deferral records
├── scripts/                                   # validate-version.sh, check-command-sync.sh
├── README.md                                  # user-facing docs
├── AGENT_GUIDELINES.md                        # standards, agent contract
└── CLAUDE.md                                  # this file
```

---

## The 14 Agent Roles

Detailed per-agent purpose, command syntax, and workflow diagrams live in `README.md` §"The 14 Agents" and the agent prompts (`ai-agent-manager-plugin/agents/*.md`). Quick map of what matters for in-codebase work:

| Agent | Type | Spawned by | Codebase-relevant invariants |
|---|---|---|---|
| Launch Pad | user-facing | user | Phase 2.5 feasibility (GO/CAUTION/NO-GO); Phase 5.5 mandatory Plan Review (max 3 spawns per session); writes briefs to `.supervisor/jobs/pending/`. **Requirement-file input:** Phase 2 step 0 — when the `goal:`/`feature:`/`problem:` value is a path **under `.supervisor/requirements/`** to an existing `.md` (resolves via `test -f` against the project root, the Beads-absent Product Owner story target), Launch Pad reads it as the requirement source; any other value (including a bare repo file like `README.md`) stays a literal-string goal. Closes the PO→Launch Pad handoff gap in Beads-optional mode. Also stamps `source_requirement` provenance (`- **Source requirement:** {path}` under the brief `## Environment`) for requirement-file inputs |
| Supervisor | user-facing | user | v4 + **Phase 1.5 PRE-FLIGHT SYNC** (remote-state reconciliation between ACQUIRE and PLAN — classifies the requested work CLEAR/OVERLAP/SUPERSEDED, silent on CLEAR, soft-gate `AskUserQuestion` interactively, fails closed under `--non-interactive` with `error: "preflight_overlap_detected"`; bounded ≤6 calls; `--skip-preflight-sync` escape hatch) + Phase 4.5 self-heal — self-heal phase **always** runs; `--skip-self-heal` only short-circuits the loop; completion-tail relocates job-move + state-completed from FINALIZE; completion-tail also stamps an idempotent `## Status: done` close-out on the originating requirement file in **Beads-absent** mode (success-only, fail-safe). **Never assert git merge/PR state ("on main", "in the PR", "already merged") without verifying via `git log` / `git branch --contains`.** |
| Product Owner | user-facing | user | Assumption Check (standard) + Reality Check (`--brainstorm`) cap Feasibility for NEEDS_FOUNDATION/BLOCKED ideas. **Beads-optional** (see Orchestrator row): when `beads_active` is false, stories persist as `.supervisor/requirements/*.md` and handoff is by file path, not `BD-XX` |
| Orchestrator | user-facing | user | Reads CLAUDE.md (+ Beads when active) → EPIC / TASK / SUBTASK with skill references. **Beads-optional:** a `## Persistence Mode` block branches on `beads_active` (probe `test -d .beads && bd --version`); when absent, skips all `bd` and writes the task tree to `.supervisor/requirements/{slug}-plan.md` — review gates stay mandatory in both modes. Detection logic already lived in the shared `context-setup` skill; this wires output to it (matching Code Reviewer's long-standing Beads-optional pattern) |
| Code Reviewer | user-facing | user | LSP, read-only mode, schema_v3 (adds `drift` category, severity caps via hook). **Auto-expands to consistency audit** when diff touches `agents/`, `commands/`, `skills/`, `docs/`, or plugin metadata |
| Red Team Reviewer | user-facing | user | 6 attack vectors; persistent memory of past audits |
| QA Strategist | user-facing | user | Three modes (Strategy / Gate Audit / Post-Execution Audit); spawned twice (gate audit Phase 11, results audit Phase 13) |
| QA Executor | user-facing | user | Multi-phase Level 1 protocol (phases 1–13, non-monotonic order), `--depth smoke|functional`, `--plan/--scope/--continue`, infrastructure-aware (Mailpit/MailHog), 80/110/60 budget (default/scoped/plan) with 60/80/92% zones |
| Review-PR (`review-pr-runner`) | user-facing | user / Supervisor completion-tail / autonomous EVALUATE | `/review-pr <pr-url>` standalone review→fix→re-review loop against an existing PR; resolves PR-URL → head branch, spawns `code-reviewer` + `general-purpose` fix worker; **never auto-merges**; emits `REVIEW_HEAL_RESULT`. NEVER Task-spawned (subagents-cannot-spawn-subagents) — run inline via `/review-pr` or as `claude --agent …:review-pr-runner`. Authority is the `review-heal` skill. |
| Execute Manager | internal | Supervisor (Phase 3) | Owns poll loop in isolated context, 60 tool-call budget |
| Context-Keeper | internal | Supervisor / Execute Manager | **Sole writer** of state file; haiku model, batch updates, atomic writes |
| Worker | internal | Execute Manager / Supervisor | One subtask per worktree, no git ops, emits WORKER_RESULT + `.worker-summary.md` |
| Plan Reviewer | internal | Launch Pad | PLAN_REVIEW_RESULT decision gates the brief save — PASS saves; NEEDS_HUMAN saves only on explicit user override; FAIL never saves |
| Rubric Grader | internal | Supervisor (Phase 4.5, only when brief has `## Outcomes Rubric` and `heal_decision == PASS`) | Read-only Haiku scorer; runtime read-only enforcement comes from `disallowedTools: Write, Edit, Task, NotebookEdit` (the frontmatter-level enforcement that survives plugin distribution — `permissionMode: plan` is preserved for `~/.claude/agents/` compatibility but is silently ignored by Claude Code for plugin agents); emits per-item `ITEM N: PASS\|FAIL` lines + `rubric_score: N/M`; advisory only — never changes `heal_decision` or blocks the PR |

### `/autonomous` orchestration shell (v14.0.0)

`/autonomous` is **not a new agent.** It is an inline main-thread slash command (`ai-agent-manager-plugin/commands/autonomous.md`) governed by `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md`. The same execution model as `/launch-pad` and `/supervisor`: the slash command body is workflow instructions executed inline on the main thread. The main thread reads `commands/launch-pad.md` and `commands/supervisor.md` at Step 0 (to avoid prompt drift), then runs Launch Pad inline (which still Task-spawns `plan-reviewer`), then runs Supervisor inline (which still Task-spawns `orchestrator` / `execute-manager` / `code-reviewer` / `rubric-grader`).

**Default mode is now multi-iteration** (cap 10, default `--max-iterations 3`) with **stacked PRs**: iteration N+1 branches from `iterations[N].branch` so the chain is reviewable bottom-up. Reviewers MUST merge the bottom of the stack first; out-of-order merges leave higher iterations rebased against the wrong base. `--no-stacked-branches` opts out and restores v13's branch-from-integration-base cadence. `--max-iterations 1` reproduces v13's single-iteration default. `--notify` opts in to gate-event webhooks (rubric / adjudication / NO-GO / Plan Review FAIL × 3) — payloads built with **jq only** for injection safety, fire-and-forget POST, gated on `AI_AGENT_MANAGER_WEBHOOK_URL`. `--non-interactive-fallback` enables a per-gate fail-closed policy for CI / stdin-not-tty: rubric gate aborts (`rubric_gate_closed_non_interactive`); no-rubric `completed` returns `done` with `no_rubric_in_non_interactive`; adjudication gate inherits Supervisor's `--non-interactive` policy if forwarded.

Re-iteration signals are the same as v13 (rubric_score N<M with user-merge confirmation; `failed + inter_subtask_gap` from Option C adjudication, anchored by `.supervisor/jobs/failed/{basename(current_brief_path)}` existence + `inter_subtask_gap` found in any of the failed brief / `SUPERVISOR_RESULT.error` / `SUPERVISOR_RESULT.summary`; `.supervisor/state.md` intentionally NOT consulted to avoid pre-rewrite stale-content false positives). The loop never auto-picks on adjudication — Supervisor's existing 4-option `AskUserQuestion` surfaces in-session as it does today; foreground-assisted automation, not fire-and-forget.

State writes are confined to `.supervisor/autonomous/{session_id}/` (the loop's own state), `.supervisor/requirements/` (the requirement files), and one append-only JSONL session log at `.supervisor/logs/{session_id}.jsonl` (matches the existing per-session log convention shared with `/supervisor`). Supervisor remains the sole writer of `.supervisor/jobs/` and `.supervisor/state.md` per existing contracts — autonomous-loop reads but never directly writes them. Context-Keeper gains atomic `set_flag` / `get_flag` / `clear_flag` operations writing under a new `## Phase Flags` section in `state.md` (consumed by autonomous-loop for stacked-branch handoff). `AUTONOMOUS_RUN` is at **schema_version 2** with nine new closed `status_reason` values; the autonomous-layer status enum (`done | paused_max_iterations | aborted | failed`) remains distinct from `SUPERVISOR_RESULT.status` to avoid schema collision; the summary is plain markdown plus a JSON sidecar (no hook validation, no resume contract in v1 of this loop — those remain future work).

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
- Context-Keeper externalizes state; Supervisor uses tool-call budgets (50, including Phase 4.5) instead of percentage thresholds; Execute Manager has its own 60-call budget in isolated context
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

**Doc currency is CI-enforced:** `scripts/check-doc-currency.sh` (a CI gate alongside `validate-version.sh`) mechanically verifies that version/count claims across the doc surfaces — agent/command/skill/hook counts, `plugin.json (vX.Y.Z)` annotations, and the `AI agents vX.Y.Z` headline — match the authoritative source (`plugin.json`, `hooks.json`, the `agents/`/`commands/`/`skills/` dirs). When you add/remove an agent, command, skill, or hook, or bump the version, **update the doc claims in the same change or CI fails.** It scans only high-confidence current-claim phrasings (never bare numbers), so dated changelog entries don't false-positive. The authoritative, always-current hook table lives in this file (§"Plugin Hooks (Quality Gates)"). **Surfaces the gate does NOT scan (recurring drift, integration-review-only):** Supervisor phase enumerations (agent-help.md, command docs), per-row skill `version:` cells in `SKILLS_INDEX.md`, per-run YAML frontmatter field lists in `build-insights.sh`, budget/zone numbers, and `/insights` dashboard section enumerations. On any phase/version/budget/section change, grep the OLD value repo-wide — a green doc-currency run is necessary but not sufficient. **Conversely, do NOT "fix" illustrative example values to the current version:** sample `session_end` / `POSTMORTEM_RESULT` JSONL records and `e.g. "X.Y.Z"` `plugin_version` placeholders (in `docs/RESULT_SCHEMAS.md`, `agents/supervisor.md`, and similar) illustrate *format* only — the real value is read at runtime from `plugin.json` via jq, so they are NOT current-claims, carry no currency requirement, and are deliberately unscanned. Bumping them every release is a drift-treadmill the gate cannot enforce (they re-stale at the next version), so leave them **frozen and version-agnostic** — a stale-looking version inside an example block is intended, not drift, and should not be re-flagged in review. (v14.25.1 codified this after a review round chased the placeholders.)

**Plugin `description` is a summary, not a changelog (anti-rebloat):** the `description` field in `plugin.json` and `.claude-plugin/marketplace.json` is the crisp card shown in the plugin-manager UI. On a version bump, update the `vX.Y.Z` string and the four counts **in place** and keep it short; put the per-release narrative in `CHANGELOG.md` (and, if notable, a single CLAUDE.md banner) — **never append another version clause to the description.**

**Hook gotcha:** Claude Code silently ignores `hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter — only `hooks.json` hooks fire for plugin-distributed agents. Per-agent frontmatter hooks are kept for `~/.claude/agents/` compatibility.

---

## Structured Contracts (v9.0.0)

- **Result Schemas** — `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`. CODE_REVIEW_RESULT at `schema_version: 3` (adds `review_mode` (`diff_review` | `consistency_audit`), `audit_focus[]`, `trigger_paths_detected[]`, `scope_expanded[]`, `files_checked[]`, `consistency_checks`, `consistency_summary`, and the `drift` issue category with `drift_kind` + severity caps; v2 accepted for legacy artifacts). WORKER_RESULT at `schema_version: 2` (adds `outputs_verified[]` + `outputs_gap`; v1 accepted for the v12.0.0 transition window). AUTONOMOUS_RUN at `schema_version: 2` (v14 — adds nine new closed `status_reason` values for stacked-branch / non-interactive-fallback / webhook-notify failure modes; v1 accepted for the v13 transition window). SUPERVISOR_RESULT remains at `schema_version: 1` with two new optional additive fields in v14 (`branch_base`, `pr_state`). All others at `schema_version: 1`.
- **Failure Escalation** — `…/FAILURE_ESCALATION.md` (retry limits, escalation paths)
- **Architecture Contracts** — `…/ARCHITECTURE_CONTRACTS.md` (capability matrix, context budgets, timeouts, worktree naming)
- **Job Lifecycle** — briefs flow `pending/` → `in-progress/` → `done/` / `failed/` in `.supervisor/jobs/`
- **Session Logging** — JSONL in `.supervisor/logs/{session_id}.jsonl`
- **Merge Safety Gate** — pre-merge checklist in FINALIZE prevents corrupted partial merges

---

## Plugin Hooks (Quality Gates)

19 hooks centralized in `hooks.json` (the v12.2.0 webhook hook brought the count 13 → 14; v13.0.0 / v14.0.0 added none — v14's `--notify` gate-event webhooks are emitted inline by the autonomous-loop, not by a hook; **v14.1.0 added 2 events / 3 entries** — `PreToolUse[AskUserQuestion]` (notify-desktop + send-webhook) and `Notification` (notify-desktop) — bringing the count 14 → 17; **v14.2.0 added 2 entries** — a `SessionStart` → `session-resume.sh` and a `launch-pad-runner` SubagentStop → `validate-launch-pad-result.py` — bringing the count 17 → 19). Prompt-based validation uses fast haiku model with 30s timeout. WorktreeCreate / StopFailure / telemetry / webhook / notification / resume / launch-pad-result hooks use `type: command` for zero-latency.

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
| PreToolUse (AskUserQuestion) — v14.1.0 | Plugin about to block on a user question | hooks.json | type:command — `notify-desktop.sh` (OS banner) + `send-webhook.sh` (paused-event POST); scope-gated; always exits 0 |
| Notification — v14.1.0 | Claude Code signals attention (permission_prompt / idle_prompt / elicitation_*) | hooks.json | type:command — `notify-desktop.sh` (OS banner); matched to exclude `auth_success`; always exits 0 |
| SubagentStop (launch-pad-runner) — v14.2.0 | Launch Pad `-runner` completes | hooks.json | type:command — `validate-launch-pad-result.py`; validates LAUNCH_PAD_RESULT (schema_version, status, saved_brief_path, summary); exits 0 |
| SessionStart — v14.2.0 | Session resume / clear / compact | hooks.json | type:command — `session-resume.sh`; injects bounded (≤10k) recovery context; silent on startup; since v14.24.0 also runs the observability health probe (env-block-gated 1s curl, 24h debounce, never starts Docker — count stays 19); exits 0 |

---

## Telemetry System (opt-in, v11.2.0 — preserved in v14.0.0)

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
| Supervisor | workflow-management, async-orchestration, state-management, context-summarization, supervisor-readiness, commit, quality-checklist |
| Orchestrator | quality-checklist |
| Code Reviewer | quality-checklist, context7-lookup, unit-testing, error-handling, monitoring-observability |
| Red Team Reviewer | context7-lookup |
| QA Strategist | qa-strategy, qa-gates, quality-checklist |
| QA Executor | qa-strategy, qa-test-patterns, qa-gates, playwright-e2e, quality-checklist |
| Product Owner | brainstorming, product-discovery, mvp-scoping |

## Agent Teams (Recommended for 3 Use Cases, Experimental for the Rest)

Native Claude Code multi-agent coordination — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Best for research, competing hypotheses, cross-layer changes; not for sequential tasks or same-file edits (use Supervisor with worktrees). Patterns + decision matrix: `ai-agent-manager-plugin/skills/agent-teams/SKILL.md`. Complementary to Supervisor v4, not a replacement.

---

## Cost Profile

`/supervisor --cheap` — opt-in flag that overrides execution-shaped roles (orchestrator, execute-manager, worker, code-reviewer, Phase 4.5 fix tasks) to Sonnet at spawn time. Default behavior (`inherit` for all) unchanged. Profile table, semantics, and Haiku-session caveat: `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles".

---

## Failure-Mode Invariants

**Bimodal failure philosophy (invariant — do not break):** correctness gates fail **CLOSED** under `--non-interactive` / CI / stdin-not-tty (`preflight_overlap_detected`, `non_interactive_without_fallback`, `rubric_gate_closed_non_interactive`); runtime side-effect emitters (telemetry wrapper, `send-webhook.sh`, the session-resume observability probe) fail **SAFE** and ALWAYS `exit 0`. Inverting either — a gate that silently proceeds without an explicit `--skip-*`, or an emitter that exits non-zero on a normal failure path — is a security regression, not a bug fix. Corollary for advisory signals: `contract_conformance_status: skipped` means UNVERIFIED, not clean (it only runs when a brief authored an `## Executable Acceptance` ground-truth surface), and a green `heal_decision: PASS` does NOT mean the PR is reviewer-clean.

## Common Pitfalls

### Claimed work is "already merged" / "on main" but isn't (stale-branch trap)?
- Never assert git merge/PR state from memory or in-context summary — verify with `git log origin/$BASE_BRANCH` and `git branch --contains <sha>` before claiming work landed.
- This is the **v13.1.0→v14.0.0 stale-branch incident** (work branched from a stale base and re-implemented something already merged) that motivated the Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate (see `ai-agent-manager-plugin/agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC"). The Supervisor-table row above keeps the quick reference.

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

### `/autonomous` brief-save detection (fixed in v14.2.0 — `ls`-diff is now fallback-only)
**Fixed in v14.2.0.** The PLAN phase now reads `LAUNCH_PAD_RESULT.saved_brief_path` (emitted by Launch Pad Phase 7, validated by `scripts/validate-launch-pad-result.py`) as the **primary** brief-save signal — each Launch Pad invocation emits exactly one result block and the loop consults only the block from its own inlined call, so a concurrent `/launch-pad` can no longer be mistaken for this loop's save. The legacy `ls`-diff of `.supervisor/jobs/pending/` remains a **pre-v14.2.0 fallback** (used only when the result block is absent or fails validation); it keeps the original single-session-only constraint and still aborts the multi-file case with `status_reason="concurrent_session_detected"`. For pre-v14.2.0 plugins the safe operating rule remains: one autonomous / launch-pad invocation at a time per repo.

### `/autonomous --cheap` is unsupported in v1
The loop does not forward unknown flags into the inlined `/supervisor` call. Run `/launch-pad` and `/supervisor --cheap` manually if you need the Sonnet cost profile for a one-off requirement. See `commands/autonomous.md` "Parameters" → `--cheap interaction note` for details.

---

## References

- User-facing: `README.md`, `.claude-plugin/README.md`
- Standards: `AGENT_GUIDELINES.md`
- Manifests: `.claude-plugin/marketplace.json`, `ai-agent-manager-plugin/.claude-plugin/plugin.json`
- Schemas / contracts / failure modes: `ai-agent-manager-plugin/docs/{RESULT_SCHEMAS,ARCHITECTURE_CONTRACTS,FAILURE_ESCALATION,ARCHITECTURE,QA_SYSTEM_BLUEPRINT,TELEMETRY,OBSERVABILITY}.md`
- Skills index: `ai-agent-manager-plugin/skills/SKILLS_INDEX.md`
