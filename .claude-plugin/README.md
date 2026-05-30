# AI Agent Manager Plugin for Claude Code

A Claude Code plugin with 13 agent roles (8 user-facing + 5 internal), 50 focused skills, and optional Beads issue tracker integration. Automates plan-first readiness, parallel workflow execution, requirements definition, code review, adversarial audits, and dual-agent QA testing. v13.0.0 adds the `/autonomous` orchestration shell that chains Launch Pad → Supervisor for a single requirement.

## Overview

The AI Agent Manager Plugin v13.0.0 includes:

- **Foreground-assisted goal-completion loop (v13.0.0)** — A new `/autonomous` slash command (`ai-agent-manager-plugin/commands/autonomous.md`) governed by a new `autonomous-loop` skill (`ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md`). The command is an inline main-thread workflow that chains Launch Pad → Supervisor for a single requirement. **Default mode is single-iteration** — pure command chaining, just so the user does not have to remember `/launch-pad "..."` then `/supervisor job: <path>`. **Multi-iteration mode** (opt-in via `--allow-multi-iteration --max-iterations N`, default N=3) adds an EVALUATE phase that reads `SUPERVISOR_RESULT` and re-plans on exactly two signals: (1) `status: completed` + `rubric_score N/M` with N<M (loop pauses for a rubric-gate AskUserQuestion — merge-and-continue verified via `gh pr view` / `git merge-base --is-ancestor`, stop-here, or force-continue-anyway); (2) `status: failed` + `inter_subtask_gap` on this iteration's brief, detected by anchor-by-filename (`.supervisor/jobs/failed/{basename(current_brief_path)}` existence + `inter_subtask_gap` found in any of three iteration-scoped sources: the failed brief's contents, `SUPERVISOR_RESULT.error`, or `SUPERVISOR_RESULT.summary`; `.supervisor/state.md` is intentionally NOT consulted because pre-rewrite stale content could false-positive). The loop **never auto-picks** on adjudication — Supervisor's existing 4-option `AskUserQuestion` (per `FAILURE_ESCALATION.md`) surfaces in-session as it does today. v13 is **purely additive**: no new agent, no new hook, no behavioral change to any existing agent / hook / script / skill / command, and no change to the field types or validation rules of any existing schema. The only new artifacts are the `/autonomous` command, the `autonomous-loop` skill, and one additive `AUTONOMOUS_RUN` entry in `RESULT_SCHEMAS.md` (autonomous-layer-only, no hook validation). Slash-command count: 11 → 12. Skill count: 49 → 50. Hook count: unchanged (14).

- **Previous capabilities increment (v12.2.0, preserved)** — (1) **Agent Teams graduation:** `ai-agent-manager-plugin/skills/agent-teams/SKILL.md` now ships per-pattern Recommended Use Cases plus a 3-of-6 graduation matrix (research/exploration, competing hypotheses, cross-layer changes graduate to *recommended*; sequential tasks, same-file edits, high-write-contention scenarios remain experimental — keep using Supervisor v4 + worktrees there). (2) **Outcomes Rubric:** every Supervisor run ends with a Haiku-graded rubric; `rubric_score` is an optional additive field in `SUPERVISOR_RESULT` (`"N/M" | null`; schema_version stays 1), owned by `ai-agent-manager-plugin/agents/supervisor.md`; the supervisor SubagentStop hook validates the format only when present and never rejects for presence or absence. (3) **`/dreaming` slash command:** read-only post-hoc reflection on completed sessions — does not write code, agent memory, or `CLAUDE.md`; persistence requires explicit user follow-up. (4) **Opt-in webhook hook:** a new SubagentStop `type: command` entry in `ai-agent-manager-plugin/hooks/hooks.json` invokes `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh` to POST structured agent results to a user-configured endpoint (disabled by default, fail-closed on errors, never blocks the agent).

- **Documentation + skills increment (v12.1.0, preserved)** — Memory Tool skill (`ai-agent-manager-plugin/skills/memory-tool/SKILL.md`) covering Anthropic's memory-tool pattern as a reference for long-running agents; "## Structured Outputs" section in `AGENT_GUIDELINES.md` documenting both enforcement paths for result blocks (Claude API direct via `output_config.format` JSON-Schema mode; plugin runtime via `SubagentStop` hooks); "## Advisor Tool (SDK-only pattern)" section in `AGENT_GUIDELINES.md` documenting the `advisor-tool-2026-03-01` beta / `advisor_20260301` server-tool as reachable only via direct `client.beta.messages.create(...)` calls (see `ai-agent-manager-plugin/docs/SPIKES/advisor.md` for the SDK-ONLY recommendation). Compaction-recovery hooks were spiked and deferred (NO-GO; see `ai-agent-manager-plugin/docs/SPIKES/compaction.md`).

- **Reliability primitives (v12.0.0, preserved)** — Inter-subtask output contracts via a `provides` / `requires` schema (planned by Launch Pad, validated by Plan Reviewer, materialized + verified by Execute Manager Step 2a/2b), scope-expansion adjudication (4-option AskUserQuestion escalation when a producer's outputs are missing or a worker emits `outputs_gap`), effort-tier discipline across the 10 execution-shaped agents (`xhigh` / `high` / `medium`; haiku-locked context-keeper and discovery-only product-owner intentionally exempt), and hardened SubagentStop validation that rejects `outputs_gap` / `toolset_gap` drift. WORKER_RESULT schema bumped to v2 with `outputs_verified[]` + `outputs_gap` fields. See `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md` (Effort Tiers) and `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` (provides/requires schema, WORKER_RESULT v2).

- **Opt-in GitHub Issues telemetry (v11.2.0, preserved)** — After qualifying agent runs (`supervisor-runner`, `code-reviewer`, `qa-executor`), an opt-in pipeline can post a structured GitHub issue with derived score, agent performance breakdown, and AI suggestions for longitudinal analysis. Wrapper always exits 0; core exits 0..5 (sent / generic_error / privacy_blocked / no_consent / no_repo_configured / filter_skipped); privacy fail-closes via a regex deny-list; **disabled by default** (no `origin` fallback) — the user must explicitly run `/telemetry enable` (which prompts for the target repo) or set `AI_AGENT_MANAGER_TELEMETRY_REPO=owner/repo`. New slash commands: `/telemetry status | enable | disable | test`. See `ai-agent-manager-plugin/docs/TELEMETRY.md` for the full design.

- **"Inline ≠ stop orchestrating" loophole closed (v11.1.2, preserved)** — The v11.1.1 main-thread guard accidentally licensed inline `/supervisor` runs to skip Phase 3 child agents and the Phase 4.5 `code-reviewer` integration review. v11.1.2 adds tailored execution-contract paragraphs to both slash commands, an inline-execution critical rule in `ai-agent-manager-plugin/agents/supervisor.md`, and a Phase 4.5 completion-tail runtime invariant that emits `status: failed` (and leaves the job in `in-progress/`) if `code-reviewer` was not invoked and `--skip-self-heal` was not explicitly passed.

- **Slash-command auto-delegation fix (v11.1.1, preserved)** — `/supervisor` and `/launch-pad` no longer silently auto-delegate to same-named registered subagents (which can't spawn their own children). Agents are now registered as `…:supervisor-runner` / `…:launch-pad-runner`; slash commands execute inline on the main thread; direct `claude --agent …-runner` sessions still work.

- **Code Reviewer as system integrity reviewer** — `diff_review` / `consistency_audit` modes, trigger-based auto-expand, always-included audit baseline (plugin.json + CLAUDE.md + README.md), repo consistency audit (mirrored prompts, version strings, counts, workflow alignment, hooks parity), `CODE_REVIEW_RESULT` schema v3 with `audit_focus` + `drift` category + `drift_kind` severity caps enforced by the plugin hook, CI-wired sync guard (`scripts/check-command-sync.sh`)

Plus all prior v11.0/v10.3/v10.2 capabilities:

- **Phase 4.5 self-heal** — Supervisor runs a holistic Code Reviewer pass on the integrated feature branch and auto-fixes bounded BLOCKING/HIGH `new` issues (up to `--heal-iterations`, default 3), eliminating the manual review-and-fix cycle per feature
- **Beads-optional Code Reviewer** — auto-detects `.beads/` + `bd` CLI; when absent, `CODE_REVIEW_RESULT` is the sole decision channel

### User-Facing Agents (8)

- **Launch Pad** (`/launch-pad`) — Prepare goals for autonomous Supervisor execution
- **Supervisor** (`/supervisor`) — Autonomous parallel workflow orchestrator with git worktrees
- **Product Owner** (`/product-owner`) — Translate business problems into user stories. Supports `--brainstorm` for multi-mind ideation
- **Orchestrator** (`/orchestrator`) — Break goals into tasks with review gates
- **Code Reviewer** (`/code-reviewer`) — Review code with PASS/FAIL/NEEDS_HUMAN decisions (LSP diagnostics, read-only)
- **Red Team Reviewer** (`/red-team-reviewer`) — Adversarial audits to break assumptions
- **QA Strategist** (`/qa-strategist`) — Risk-based test strategy and QA audit
- **QA Executor** (`/qa-executor`) — Discover app, generate Playwright tests, find gaps

### Orchestration Shells (slash commands, not agents)

- **`/autonomous` (v13.0.0)** — Chain Launch Pad → Supervisor for a single requirement; opt-in `--allow-multi-iteration` adds re-planning on existing SUPERVISOR_RESULT signals (rubric N<M with user-merge confirmation; failed + inter_subtask_gap). Inline main-thread workflow — does not register a new agent.

### Internal Agents (5)


- **Execute Manager** — Owns Phase 3 worker/reviewer lifecycle (spawned by Supervisor)
- **Context-Keeper** — Sole writer of externalized state file (spawned on-demand)
- **Worker** — Implements a single subtask in an isolated git worktree (spawned by Execute Manager)
- **Plan Reviewer** — Validates Supervisor-Ready Briefs before execution (spawned by Launch Pad)
- **Rubric Grader** (shipped in v12.2.0; the "Internal Agents (4) → (5)" count update is a v13.0.0 doc-consistency fix — not a new v13 agent) — Read-only Haiku scorer for the optional Outcomes Rubric (spawned by Supervisor in Phase 4.5 when the brief contains `## Outcomes Rubric` and `heal_decision == PASS`; advisory only — never blocks the PR)

### 50 Skills

Skills are loaded on-demand to keep context small:

- **Core:** Commits, Context7 lookups, Quality checklist, Pattern detection, Claude.md validation
- **Workflow:** Supervisor readiness, Async orchestration, State management, Context summarization, Workflow management, Agent teams
- **Product:** Brainstorming, Product discovery, MVP scoping, User story writing, Domain knowledge
- **QA:** QA strategy, QA orchestration, QA test patterns, QA gates, Playwright E2E, Unit testing
- **NestJS:** Guards, Controllers, Services, Drizzle ORM, TypeORM
- **Next.js:** Routing, Components, API routes, Data fetching, Authentication
- **Gateway:** Proxy patterns, Auth middleware, Rate limiting, Correlation ID
- **DevOps:** CI/CD, Docker, Monitoring/Observability, Error handling
- **Data:** MySQL, PostgreSQL, Redis caching
- **UI:** Frontend UI (design system, accessibility, responsive)

---

## Quick Start

### 1. Installation

```
# From a checkout of this repo
/plugin marketplace add /path/to/ai-agent-manager
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

The repo is a marketplace wrapper (`/.claude-plugin/marketplace.json`) with the plugin nested at `ai-agent-manager-plugin/`. Once published to the official Anthropic marketplace, installation becomes a single `/plugin install` command without needing a local checkout.

### 2. Setup Your Project

Your project needs only a `CLAUDE.md` file for agents to work:

```bash
cd /path/to/your/project

# Option A: With Beads (full task management)
bd init

# Option B: Without Beads (Supervisor creates .supervisor/ automatically)
# Just create CLAUDE.md with your project patterns
```

This creates:
```
your-project/
├── CLAUDE.md              # Codebase knowledge (required)
├── .supervisor/           # Supervisor state (auto-created, gitignored)
│   ├── state.md           # Current session state
│   ├── history/           # Completed session summaries
│   └── jobs/              # Supervisor-Ready Briefs from Launch Pad
├── .beads/                # Beads issue tracker (optional)
└── src/                   # Your code
```

### 3. Run Your First Command

```bash
# Plan-first autonomous workflow
/launch-pad goal: "add user authentication"
/supervisor job: .supervisor/jobs/pending/2026-02-08-user-auth.md

# Or run directly
/supervisor task: "add user authentication"

# Or plan manually
/orchestrator goal: "add dark mode to UI"
```

---

## Commands

### /launch-pad goal: "\<goal\>"

Prepare a goal for autonomous Supervisor execution. Analyzes codebase, estimates file impact, validates environment.

```bash
/launch-pad goal: "add user authentication"
/launch-pad goal: "refactor payment module" --discovery
```

**Output:** Supervisor-Ready Brief saved to `.supervisor/jobs/pending/`

---

### /supervisor [task: "\<description\>"] [job: \<path\>]

Autonomous workflow orchestrator. Creates feature branch, plans work, spawns parallel workers in git worktrees, reviews, merges, and creates PR.

```bash
/supervisor                                    # Pick up next Beads task
/supervisor task: "add dark mode"              # Direct task
/supervisor job: .supervisor/jobs/pending/...   # From Launch Pad brief
/supervisor --max-workers 3                    # Parallel workers
```

**Output:** Completed implementation with PR

---

### /autonomous "\<requirement\>" (orchestration shell, v13.0.0)

Chain Launch Pad → Supervisor for a single requirement. **Foreground-assisted automation, not fire-and-forget** — every in-session prompt (Launch Pad Phase 6, NO-GO, Plan Review FAIL × 3, Supervisor adjudication 4-option, and the loop's rubric gate) bubbles `AskUserQuestion` for you to answer.

```bash
/autonomous "add user authentication"                                    # single-iteration mode
/autonomous --requirement .supervisor/requirements/feature.md            # use existing file
/autonomous "..." --allow-multi-iteration                                # multi-iteration with default max=3
/autonomous "..." --allow-multi-iteration --max-iterations 5             # custom cap
```

**Default (single-iteration):** runs Launch Pad → Supervisor once and emits an `AUTONOMOUS_RUN` summary. Pure command chaining.

**Multi-iteration:** EVALUATE re-plans on exactly two signals — `completed + rubric_score N/M` with N<M (gated on user-merge verification via `gh pr view` / `git merge-base --is-ancestor`) and `failed + inter_subtask_gap on this iteration's brief` (Option C re-plan trigger, no merge needed). The loop never auto-picks on adjudication — Supervisor's existing 4-option AskUserQuestion surfaces in-session.

v13 is purely additive: no new agent, no new hook, no behavioral change to any existing agent / hook / script / skill / command, and no change to the field types or validation rules of any existing schema. The only new artifacts are the `/autonomous` command, the `autonomous-loop` skill, and the additive `AUTONOMOUS_RUN` entry in `RESULT_SCHEMAS.md`.

**Output:** `.supervisor/autonomous/{session_id}/summary.md` (and machine-readable sidecar `state.json`) plus the iteration-by-iteration PR list.

---

### /product-owner feature: "\<what\>" | problem: "\<issue\>"

Translate business problems into user stories with acceptance criteria.

```bash
/product-owner feature: "staff scheduling for venue events"
/product-owner problem: "we keep double-booking shifts"
/product-owner feature: "order history" --mvp-only
/product-owner problem: "low retention" --brainstorm
/product-owner feature: "new pricing model" --brainstorm deep
```

**Flags:**
- `--mvp-only` — Focus only on MVP scope
- `--discovery` — Run full discovery before writing stories
- `--brainstorm` — 5-lens multi-mind ideation (Creative, PM, Engineer, Business, Critic) with debate, scoring, and recommendation before writing stories
- `--brainstorm deep` — Deep ideation with 2 debate rounds and market research

**Output:** User stories with Given/When/Then acceptance criteria, scope analysis, handoff to Orchestrator

---

### /orchestrator goal: "\<what to do\>"

Break a goal into tasks with mandatory code review subtasks.

```bash
/orchestrator goal: "add dark mode to UI"
/orchestrator goal: "fix login bug" --project /path/to/project
```

**Output:** Beads task structure (EPIC -> TASK -> SUBTASK) with review gates

---

### /code-reviewer [files] [--project /path]

Review code against quality standards. Read-only (never modifies files).

```bash
/code-reviewer src/components/        # Review specific files
/code-reviewer                        # Review recent git changes
```

**Checks:** Type safety (LSP diagnostics), security, performance, pattern consistency, test coverage

**Output:** Issues by severity with category tags (`new`/`pre_existing`/`nit`) + PASS/FAIL/NEEDS_HUMAN decision

---

### /red-team-reviewer [target] [--focus security|scale|cost|ops]

Adversarial audit — find what breaks in production.

```bash
/red-team-reviewer                    # Full audit
/red-team-reviewer src/auth/          # Target specific area
/red-team-reviewer --focus security   # Focus on security vectors
```

**Output:** Findings by severity (FATAL/CRITICAL/WARNING/WEAKNESS) with prioritized fixes

---

### /qa-strategist [target] [--audit .qa-summary.md]

Plan risk-based test strategy or audit QA Executor results.

```bash
/qa-strategist src/                           # Strategy mode
/qa-strategist --audit .qa-summary.md         # Audit mode
/qa-strategist --focus auth                   # Focus area
```

**Output:** Risk classification, coverage targets, STRATEGIST_VERDICT

---

### /qa-executor [--url http://...] [--rounds 1|2|3]

Discover app structure, generate Playwright tests, find gaps, execute.

```bash
/qa-executor                                          # Auto-detect
/qa-executor --url http://localhost:3000               # Explicit URL
/qa-executor --url http://localhost:3000 --skip-strategy
```

**Requires:** `playwright.config.ts` and running application

**Output:** Playwright tests, .qa-summary.md, QA_RESULT block, MISSING_FUNCTIONALITY_REPORT

---

### /commit

Create conventional commits with Beads linking.

```bash
/commit
```

---

### /telemetry [status | enable | disable | test]

Opt-in GitHub Issues telemetry. After qualifying agent runs complete, the
hook can post a structured issue (derived score, agent breakdown, AI
suggestions) to a target repo of your choice for longitudinal analysis.
**Telemetry is disabled by default.**

```bash
/telemetry status     # Show consent state, target repo, last-sent timestamp
/telemetry enable     # Interactive — prompts for target repo, writes consent
/telemetry disable    # Mark consent as denied; no further sends
/telemetry test       # Dry-run latest payload through the core; never calls gh
```

**Configuration:**
- **Target repo:** set the `AI_AGENT_MANAGER_TELEMETRY_REPO=owner/repo`
  environment variable, OR run `/telemetry enable` (prompts for the
  repo). There is **no `origin`-remote fallback** — the plugin runs in
  arbitrary user projects, so `origin` would be the wrong place to post.
- **Consent file:** `.supervisor/telemetry-consent.json` (gitignored via
  `.supervisor/`). The hook NEVER prompts; `/telemetry enable` is the
  sole first-run consent path.

**Privacy guarantees:**
- Wrapper script always exits 0 — telemetry can never block an agent run.
- Core script exits 0..5; privacy fail-closes (exit 2) via a regex
  deny-list covering tokens (`sk-…`, `ghp_…`), API keys, bearer
  tokens, passwords, home-dir paths (`/Users/…`, `/home/…`), email
  addresses, and `.env`-style assignments. Matches abort the post and
  log the matched pattern label only, NEVER the matched content.
- Stderr from the core is redacted by the same whitelist before being
  appended to `.supervisor/logs/telemetry.log`.
- Healthy runs are filtered (no issue created) when score >= 5 AND
  status is in the success set.

See `ai-agent-manager-plugin/docs/TELEMETRY.md` for the scoring rubric,
issue-body schema, exit-code table, and wrapper-vs-core architecture.

---

### /agent-help

Show all commands and quick reference.

```bash
/agent-help
```

---

## Workflows

### Plan-First Autonomous (Recommended)

```
/launch-pad goal: "..."
    |
.supervisor/jobs/pending/{date}-{slug}.md  (Supervisor-Ready Brief)
    |
/supervisor job: .supervisor/jobs/pending/{file}.md  (clean context)
    |
INIT -> ACQUIRE -> PLAN -> EXECUTE (parallel workers) -> FINALIZE -> PR
```

### Manual

```
/orchestrator goal: "..."     # Plan tasks
    |
bd claim BD-XX                # Start task
    |
(implement code)
    |
/code-reviewer src/           # Review -> PASS/FAIL
    |
/commit                       # Conventional commits
    |
bd close BD-XX                # Complete, next unblocks
```

### QA Automation

```
/qa-strategist src/                    # Risk-based strategy
    |
/qa-executor --url http://localhost:3000  # Generate + run tests
    |
/qa-strategist --audit .qa-summary.md    # Audit results
```

---

## Project Structure

### Plugin Files

```
ai-agent-manager/                            # Marketplace wrapper repo
├── .claude-plugin/
│   ├── marketplace.json                     # Marketplace manifest (root)
│   └── README.md                            # This file
└── ai-agent-manager-plugin/                 # The nested plugin
    ├── .claude-plugin/
    │   └── plugin.json                      # Plugin manifest (v13.0.0)
    ├── .mcp.json                            # Bundled MCP servers
    ├── agents/                              # Agent prompts (13 roles)
    │   ├── launch-pad.md, supervisor.md, execute-manager.md, context-keeper.md
    │   ├── worker.md, plan-reviewer.md, product-owner.md, orchestrator.md
    │   └── code-reviewer.md, red-team-reviewer.md, qa-strategist.md, qa-executor.md
    ├── commands/                            # Slash commands (11)
    │   ├── launch-pad.md, supervisor.md, product-owner.md, orchestrator.md
    │   ├── code-reviewer.md, red-team-reviewer.md, qa-strategist.md, qa-executor.md
    │   ├── telemetry.md, dreaming.md
    │   └── agent-help.md
    ├── hooks/
    │   └── hooks.json                       # 17 quality gate hooks (centralized)
    ├── skills/                              # 50 focused skill modules
    │   ├── SKILLS_INDEX.md                  # Skill catalog with agent mapping
    │   └── [skill-name]/SKILL.md            # Individual skills
    └── docs/
        ├── RESULT_SCHEMAS.md                # Structured result contracts
        ├── FAILURE_ESCALATION.md            # Retry limits and escalation paths
        ├── ARCHITECTURE_CONTRACTS.md        # Capability matrix, budgets, rules
        ├── ARCHITECTURE.md                  # Visual agent topology
        ├── QA_SYSTEM_BLUEPRINT.md           # QA system architecture
        └── SPIKES/                          # Capability spike investigations + deferral records
```

---

## Key Concepts

### Project Auto-Detection

Agents automatically find your project:

1. Search current directory for CLAUDE.md
2. Search parent directories up to root
3. Use first CLAUDE.md found (nearest wins)
4. Accept `--project /path` override

### Approval Workflow

- **Code Issues:** Agent flags, you fix
- **File Updates:** Agent suggests, you review
- **CLAUDE.md Changes:** Agent proposes, you approve
- **Commits:** Agent creates, you review
- **Pushes:** Only with explicit instruction

### Beads Issue Tracking (Optional)

Agents can read and update Beads:

| Command | Purpose |
|---------|---------|
| `bd list` | View all tasks |
| `bd create` | Create new task |
| `bd claim BD-XX` | Start task |
| `bd close BD-XX` | Mark complete |
| `bd comment BD-XX "note"` | Add notes |
| `bd dep BD-XX BD-YY` | Set dependencies |

### Persistent Agent Memory

Agents with `memory: project` build knowledge across sessions:

| Agent | What It Remembers |
|-------|-------------------|
| Launch Pad | Commonly impacted files, project patterns |
| Code Reviewer | Review patterns, recurring issues, conventions |
| Red Team Reviewer | Past vulnerabilities, attack patterns |
| Product Owner | Domain context, terminology, preferences |
| QA Strategist | Risk patterns, which routes break |
| QA Executor | Flaky patterns, common failures |

### Quality Gate Hooks

17 hooks centralized in `hooks.json` validate agent output and surface notifications:
- **SubagentStop:** Worker, Execute Manager, Code Reviewer, Supervisor, QA Executor, Plan Reviewer (6 prompt validators) + 3 `type: command` telemetry hooks on Code Reviewer, QA Executor, Supervisor + 1 `type: command` opt-in webhook hook (v12.2.0)
- **PreToolUse (AskUserQuestion):** desktop banner + paused-event webhook (v14.1.0)
- **Notification:** desktop banner on permission/idle/elicitation prompts, `auth_success` excluded (v14.1.0)
- **Stop:** Code Reviewer (completeness gate)
- **TaskCompleted:** Verify task genuinely done
- **WorktreeCreate / StopFailure:** Logging

---

## Marketplace Setup

### Local Dev/Testing

```
/plugin marketplace add /path/to/ai-agent-manager
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

The repo ships as a marketplace wrapper (`/.claude-plugin/marketplace.json`) with the plugin nested at `ai-agent-manager-plugin/`. The first command registers the marketplace, the second installs the plugin from it.

### Official Marketplace (Distribution)

Once the plugin is accepted into the official Anthropic marketplace, users install with a single `/plugin install` command — no local checkout required. See `ai-agent-manager-plugin/.claude-plugin/plugin.json` for the plugin manifest and `.claude-plugin/marketplace.json` for the marketplace manifest.

---

## Troubleshooting

### "Error: No project context found"

Agent couldn't find CLAUDE.md. Create one in your project root or use `--project /path`.

### "No files to review" (Code Reviewer)

No git changes detected. Specify files: `/code-reviewer src/components/MyFile.tsx`

### Supervisor Workflow Interrupted

State is saved to `.supervisor/state.md` automatically. Resume with `/supervisor --continue task: BD-XX`.

### Orphaned Worktrees After Crash

```bash
git worktree list              # See all worktrees
git worktree remove ../path    # Clean up
```

---

## FAQ

### Do agents make changes automatically?

No. Agents suggest changes. You decide whether to apply them. Exception: Supervisor workers write code in isolated worktrees, but merging requires validation.

### Can I use agents on different languages?

Yes. The plugin works on any language (JavaScript, TypeScript, Python, Go, Rust, Java, etc). Customize patterns in CLAUDE.md.

### Do I need all 8 user-facing agents?

No. Use what helps:
- **Just need to plan?** `/orchestrator`
- **Just need code review?** `/code-reviewer`
- **Need full automation?** `/launch-pad` then `/supervisor`
- **Need requirements?** `/product-owner`
- **Need security audit?** `/red-team-reviewer`
- **Need QA tests?** `/qa-executor`

### Do agents need internet?

No. Everything runs locally. `WebSearch`/`WebFetch` are used only by Red Team Reviewer and Product Owner (for `--brainstorm deep` market research).

### Can agents work on private projects?

Yes. Your code stays local. Agent memory is stored in `.claude/agent-memory/` on your machine.

---

## License

MIT License

---

## Support

```bash
/agent-help          # Quick reference
```

Open an issue in the ai-agent-manager repository for bugs or feature requests.
