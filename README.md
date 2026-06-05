# AI Agent Manager

A Claude Code plugin for AI agents to collaborate on software projects. 13 specialized agents (Launch Pad, Supervisor v4, Execute Manager, Context-Keeper, Worker, Plan Reviewer, Rubric Grader, Product Owner, Orchestrator, Code Reviewer, Red Team Reviewer, QA Strategist, QA Executor) and the `/commit` skill automate plan-first readiness, parallel workflow execution, requirements, planning, review, commits, adversarial audits, and dual-agent QA automation.

**Key Idea:** Your projects need only a `CLAUDE.md` file for codebase knowledge. The Supervisor uses `.supervisor/` for state management. Orchestrator and Product Owner can optionally use [Beads issue tracker](https://github.com/anthropics/beads). Repeatable across any project.

> **Install the plugin and run slash commands instead of manually managing agents.**
>
> **NEW in v14.12.0 — Twin inline-delta: *this run's* hard signal in the self-heal tail:** The Supervisor's Phase 4.5 SELF_HEAL completion tail now prints one **advisory** line summarizing *this run's* System Twin hard signal — contract-conformance (status + violation count) and benchmark (status + value + Δ) — e.g. `Twin: conformance PASS (0 violations) · benchmark system-twin-selftest 6 (Δ +1)`. It is **purely informational** (never changes `heal_decision`, never blocks the PR, never alters control flow — byte-identical gate behavior with or without it) and **graceful** (no Twin signal → `Twin: no signal this run`, always exits 0). Formatting lives in a **self-tested script** (`scripts/format-twin-delta.sh`); the engine change is a minimal call+echo in the completion tail. No new agent / command / skill / hook (still **13 / 15 / 50 / 19**), and no schema change (the hard-signal fields already exist from v14.10.0).
>
> **NEW in v14.10.0 — System Twin foundation slice (advisory, propose-only):** One thin, additive, reversible vertical that exercises all three System Twin pillars on the plugin's own repo while staying **advisory and strictly subordinate to `CLAUDE.md`**. A `.supervisor/twin/` per-subsystem **System Contract** store is written **only** by the repo-root sole writer `scripts/write-system-contract.sh` (worktree-guard + hash-chained provenance + atomic; read via `read-system-contract.sh`; self-tested). **Predict:** Launch Pad reads the contract's dependency graph for advisory **blast-radius** prediction (graceful fallback when absent). **Prove:** Supervisor Phase 4.5 runs an advisory **contract-conformance check** on the integrated diff plus a **deterministic benchmark**, then an ephemeral builder writes contracts from the pinned repo-root CWD and emits a hard signal to `SUPERVISOR_RESULT` + the session JSONL. **Compound:** `/insights` surfaces the conformance/benchmark trend, `/dreaming` reads contract drift, and the rubric-grader **reports** the signal as advisory lines that never gate. Propose-only, no self-applied writes without the existing human gate — no new agent/command/skill/hook (still 13 / 14 / 50 / 19).
>
> **NEW in v14.9.0 — `/capability-check --strategy`: product-direction strategist:** `--strategy` turns `/capability-check` from a pure platform-adoption diff into a grounded product-evolution pass that proposes **scored, deduped, differentiated product directions** (reusing the brainstorming skill), each grounded in a real product asset plus a newly-feasible enabler or an explicit drop. Default (no-flag) behavior is unchanged; the mode is propose-only, bounded, and human-gated — no new command/agent/skill/hook (still 13 / 14 / 50 / 19).
>
> **NEW in v14.3.0 — Advisory project memory (P2b):** Agent-writable, cross-session **project memory** under `.supervisor/memory/` so the plugin stops re-discovering your codebase each run. Built behind guardrails: a **sole writer** (`scripts/write-project-memory.sh`) that **refuses git-worktree CWDs** + hash-chains provenance + caps at 200 lines, and a **read-side gate** (`scripts/read-project-memory.sh`) that emits only chain-verified entries (poisoned lines dropped). Memory is **advisory, subordinate to `CLAUDE.md`, human-gated** — Launch Pad reads it during analysis and *proposes* new facts for your approval. Launch-Pad-only in v1; no new agent/skill/command/hook (still 19 hooks).
>
> **NEW in v14.2.2 — Notification polish (patch):** `notify-desktop.sh` now **debounces** rapid notification bursts into a single banner (`AI_AGENT_MANAGER_NOTIFY_DEBOUNCE`, default 5s) and **detects the display** on Linux (skips `notify-send` on headless). `/autonomous --notify` **fails loud** if no webhook URL is resolvable (env var or `.supervisor/notify-config.json`) instead of silently doing nothing. No hook/schema/agent change (still 19 hooks).
>
> **NEW in v14.2.1 — Webhook + telemetry result-extraction fix (patch):** The supervisor-completion webhook (`send-webhook.sh`) and the opt-in telemetry post (`send-telemetry-core.sh`) read the finishing agent's output from the **real** `SubagentStop` payload field — `last_assistant_message` (with the legacy `result_block` / `output` / `agent_output` names and the `agent_transcript_path` / `transcript_path` JSONL as fallbacks) — instead of a top-level `result_block` field that Claude Code never actually sends. The pre-fix readers resolved to empty and **silently suppressed every supervisor-completion webhook and telemetry issue** since v14.1.0. No hook-count (still 19), schema, agent, command, or skill change. See `ai-agent-manager-plugin/docs/TELEMETRY.md` §"Result-text extraction".
>
> **NEW in v14.0.0 — Continuous autonomous mode with stacked PRs:** `/autonomous` flips to **multi-iteration by default** (cap 10, default `--max-iterations 3`) with **stacked-branch semantics** — iteration N+1 branches from `iterations[N].branch`, producing a reviewable PR stack. Out-of-order merge hazard: reviewers MUST merge the bottom of the stack first (follow `AUTONOMOUS_RUN.iterations[]` order). Restore v13 cadence with `--no-stacked-branches`; reproduce v13's single-iteration default with `--max-iterations 1`. New flags: **`--notify`** (opt-in gate-event webhooks for rubric / adjudication / NO-GO / Plan Review FAIL × 3, gated on `AI_AGENT_MANAGER_WEBHOOK_URL`, jq-only payload construction for injection safety, fire-and-forget POST) and **`--non-interactive-fallback`** (per-gate fail-closed policy for CI / stdin-not-tty: rubric gate aborts, no-rubric `completed` returns `done`, adjudication inherits Supervisor's `--non-interactive` policy when forwarded). Supervisor gains `--base-branch <ref>` + `--non-interactive` + Phase 0/4/4.5 base-mismatch detection + cleanup, and emits optional additive `branch_base` + `pr_state` fields on `SUPERVISOR_RESULT` (schema_version still 1, optional). Context-Keeper gains atomic `set_flag` / `get_flag` / `clear_flag` operations writing under a new `## Phase Flags` section in `state.md`. `AUTONOMOUS_RUN` bumps to **schema_version 2** with nine new closed `status_reason` values. **W-NEW-3 spike PASSED pre-merge**: Code Reviewer + Rubric Grader both honor `DIFF-SCOPE OVERRIDE` inline directives on stacked-branch fixtures. v14 is additive on top of v13: no new agent, no hook count change in v14.0.0 (still 14). **v14.1.0** adds desktop + webhook pause notifications (`PreToolUse[AskUserQuestion]` + `Notification` hooks), bringing the hook count 14 → 17 — see "Enabling notifications" below. **v14.2.0** adds the concurrency/resume layer — a `LAUNCH_PAD_RESULT` schema (so `saved_brief_path` becomes the primary `/autonomous` brief-detection signal, retiring the fragile `ls`-diff) plus a `SessionStart` crash/compact resume hook — bringing the count 17 → 19. All v13.0.0 / v13.0.1 capabilities preserved (foreground-assisted gates, rubric-gate user-merge verification, Option C `inter_subtask_gap` re-plan, webhook empty-payload suppression). 13 agent roles, 15 slash commands, 50 skills, 19 quality gate hooks. All v12.2.0 capabilities preserved (Agent Teams graduation, Outcomes Rubric, `/dreaming`, opt-in SubagentStop webhook hook) and v12.1.0 documentation increments preserved.
>
> **v12.1.0 (preserved):** Documentation + skills increment — Memory Tool skill (Anthropic memory-tool pattern reference), "## Structured Outputs" section in `AGENT_GUIDELINES.md` documenting both enforcement paths (`output_config.format` for direct API agents, `SubagentStop` hooks for plugin agents), and the "## Advisor Tool (SDK-only pattern)" section noting the `advisor-tool-2026-03-01` beta is reachable only via direct `client.beta.messages.create(...)` calls.
>
> **v12.0.0 (preserved):** Reliability primitives — inter-subtask `provides` / `requires` contracts, pre-spawn dependency verification gate, scope-expansion adjudication (4-option escalation), effort-tier discipline across the 10 execution-shaped agents (haiku context-keeper and discovery-only product-owner exempt), and hardened SubagentStop validation rejecting `outputs_gap` / `toolset_gap` drift. WORKER_RESULT schema bumped to v2.
>
> **v7 baseline (preserved):** Enhanced Code Reviewer (LSP diagnostics, read-only mode, issue categorization: new/pre_existing/nit), senior-grade QA (strict assertions, negative testing, CRUD lifecycle, data integrity probes, security boundary tests, missing functionality detection with `MISSING_FUNCTIONALITY_REPORT`), session-based QA (`--plan`, `--scope`, `--continue`), Strategist assertion quality audit. Plus all v6 features: structured result schemas, failure escalation, merge safety gate, session logging, per-agent hooks, architecture contracts.

---

## Quick Start

### 1. Install the Plugin

**Local development (from a checkout of this repo):**

```
/plugin marketplace add /path/to/ai-agent-manager
/plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
```

The repo is a marketplace wrapper (`/.claude-plugin/marketplace.json`) with the plugin nested at `ai-agent-manager-plugin/`. The first command registers the marketplace, the second installs the plugin from it.

Once published to the official Anthropic marketplace, installation becomes a single `/plugin install` command without needing a local checkout.

### 2. Setup Your Project

```bash
cd /path/to/your-project

# Create CLAUDE.md with your project patterns
# (See CLAUDE.md Structure section below)

# Optional: Initialize Beads issue tracker (for Orchestrator/Product Owner)
bd init
```

This creates:

```
your-project/
├── CLAUDE.md              # Codebase knowledge (you maintain)
├── .supervisor/           # Supervisor state (auto-created, gitignored)
│   ├── state.md           # Current session state
│   ├── history/           # Completed session summaries
│   ├── jobs/              # Supervisor-Ready Briefs lifecycle
│   │   ├── pending/       # Launch Pad saves briefs here
│   │   ├── in-progress/   # Supervisor moves brief here on ACQUIRE
│   │   ├── done/          # Supervisor moves here on FINALIZE
│   │   └── failed/        # Supervisor moves here on failure
│   ├── logs/              # Structured JSONL session logs
│   └── worker-summaries/  # Worker summaries (inline mode)
├── .beads/                # Beads issue tracker (optional)
│   └── issues/
└── src/ (your code)
```

### 3. (Optional) Enable MySQL MCP

The plugin bundles a read-only MySQL MCP server that gives agents direct database access — schema inspection, query execution with impact analysis, and multi-DB profile switching.

**Set your DB credentials as environment variables** (add to `~/.zshrc` or `~/.bashrc`):

```bash
export DB_HOST=localhost
export DB_USER=myuser
export DB_PASS=mypassword
export DB_NAME=mydatabase
export DB_PORT=3306        # numeric string, defaults to 3306
```

> **Note:** Running `export` in your terminal takes effect **immediately in the current session only**. When you close that terminal or open a new one, the variables are gone. To persist across sessions, add these lines to `~/.zshrc` or `~/.bashrc`:
> ```bash
> echo 'export DB_HOST=localhost' >> ~/.zshrc
> echo 'export DB_USER=myuser' >> ~/.zshrc
> echo 'export DB_PASS=mypassword' >> ~/.zshrc
> echo 'export DB_NAME=mydatabase' >> ~/.zshrc
> echo 'export DB_PORT=3306' >> ~/.zshrc
> source ~/.zshrc
> ```

The MCP server starts automatically via `uvx` when the plugin is loaded — no extra steps needed.

**Multi-DB profiles** (optional) — connect to multiple databases by setting:

```bash
export DB_PROFILES_MYSQL_PROD='{"host":"prod.example.com","user":"ro","pass":"secret","db":"myapp"}'
export DB_PROFILES_MYSQL_STAGING='{"host":"staging.example.com","user":"ro","pass":"secret","db":"myapp"}'
```

Then call `switch_database(host="prod.example.com")` at runtime to switch between them.

> **Security:** Only `SELECT` queries are permitted. All write operations (`INSERT`, `UPDATE`, `DELETE`, `DROP`, etc.) are blocked.

---

### 4. Run Your First Command

```bash
# Plan-first autonomous workflow
/launch-pad goal: "what you want to accomplish"
/supervisor job: .supervisor/jobs/pending/{date}-{slug}.md

# Or run directly
/supervisor task: "what you want to accomplish"

# Or plan manually
/orchestrator goal: "what you want to accomplish"

# Or chain Launch Pad → Supervisor in one command (v14.0.0)
# Foreground-assisted automation: you stay at the terminal to answer
# in-session prompts (Phase 6 save, NO-GO, adjudication, etc.); the
# loop handles the chaining and the rubric-driven re-plan.
# Default is multi-iteration with stacked PRs (cap 10, default 3).
/autonomous "what you want to accomplish"                                # multi-iter default (3), stacked PRs
/autonomous "what you want to accomplish" --max-iterations 1             # reproduce v13's single-iter default
/autonomous "what you want to accomplish" --no-stacked-branches          # v13-style: branch from integration base
/autonomous "what you want to accomplish" --notify                       # opt-in gate webhooks (AI_AGENT_MANAGER_WEBHOOK_URL)
/autonomous "what you want to accomplish" --non-interactive-fallback     # CI / unattended: per-gate fail-closed policy
```

---

## The 13 Agents

### User-Facing Agents (8 + commit skill)


| Agent                 | Command                         | Purpose                                                            | When                            |
| --------------------- | ------------------------------- | ------------------------------------------------------------------ | ------------------------------- |
| **Launch Pad**        | `/launch-pad goal: "..."`       | Prepare goals for autonomous Supervisor execution with feasibility gate (Phase 2.5: GO/CAUTION/NO-GO) and mandatory Plan Review (Phase 5.5) | Before `/supervisor`, planning  |
| **Supervisor**        | `/supervisor task: "..."`       | Autonomous workflow → Phase 1.5 PRE-FLIGHT SYNC (remote-overlap gate) → parallel workers → PR creation | Full automation                 |
| **Product Owner**     | `/product-owner feature: "..."` | Define requirements → create user stories with acceptance criteria. Assumption Check (standard flow, user gate before `bd create` if flags) + Reality Check (brainstorm flow, VIABLE/NEEDS_FOUNDATION/BLOCKED with Feasibility score caps). Use `--brainstorm` for multi-mind ideation. | New feature, vague requirements, exploring directions |
| **Orchestrator**      | `/orchestrator goal: "..."`     | Plan work → create tasks with review gates                         | Starting implementation         |
| **Code Reviewer**     | `/code-reviewer src/`           | Review code → output PASS/FAIL/NEEDS_HUMAN                         | After writing code              |
| **Commit** (skill)    | `/commit`                       | Stage changes → create conventional commits                        | Ready to commit                 |
| **Red Team Reviewer** | `/red-team-reviewer`            | Adversarial audit → find production failures                       | Pre-launch, security            |
| **QA Strategist**     | `/qa-strategist src/`           | Risk-based test strategy → coverage targets → assertion quality audit | Before QA, strategy planning    |
| **QA Executor**       | `/qa-executor`                  | Discover → generate strict tests → find missing functionality → QA_RESULT | Automated QA                    |


### Internal Agents (5)


| Agent               | Spawned By                   | Purpose                                                               |
| ------------------- | ---------------------------- | --------------------------------------------------------------------- |
| **Execute Manager** | Supervisor (Phase 3)         | Own poll loop, worker/reviewer lifecycle, Context-Keeper coordination |
| **Context-Keeper**  | Supervisor / Execute Manager | Manage externalized state file (sole writer)                          |
| **Worker**          | Execute Manager / Supervisor | Implement a single subtask in an isolated git worktree                |
| **Plan Reviewer**   | Launch Pad                   | Validate Supervisor-Ready Briefs before execution                     |
| **Rubric Grader**   | Supervisor (Phase 4.5)       | Read-only Haiku scorer for the optional Outcomes Rubric (advisory)    |


### Orchestration Shell: `/autonomous` (v14.0.0)

`/autonomous` is **not** a new agent — it is a slash command that chains the agents above. The command body (`ai-agent-manager-plugin/commands/autonomous.md`) is executed inline on the main thread: it reads `commands/launch-pad.md` and `commands/supervisor.md` at Step 0, then runs Launch Pad inline (which still Task-spawns `plan-reviewer`), then runs Supervisor inline (which still Task-spawns `orchestrator` / `execute-manager` / `code-reviewer` / `rubric-grader`). **Default mode is multi-iteration** (cap 10, default `--max-iterations 3`) with **stacked PRs**: iteration N+1 branches from `iterations[N].branch`. The loop re-plans on the same two existing `SUPERVISOR_RESULT` signals as v13 (rubric N<M with user-merge confirmation; `failed + inter_subtask_gap` from Option C adjudication). The protocol skill is at `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md`.

### Stacked PR workflow (v14.0.0+)

The v14 default flips `/autonomous` from "run once, return" to a continuous loop that produces a **stack of PRs**, one per iteration:

- **Branching:** Iteration 1 branches from the integration base (typically `origin/main`). Iteration N+1 branches from `iterations[N].branch` — the previous iteration's feature branch — so each iteration builds on top of the prior unmerged work. This produces a reviewable bottom-up stack rather than divergent siblings.
- **Out-of-order merge hazard:** Reviewers MUST merge the **bottom** of the stack first (the earliest iteration, listed first in `AUTONOMOUS_RUN.iterations[]`). Merging a higher iteration before its base leaves the remaining higher iterations rebased against the wrong base and produces phantom conflicts. The autonomous-loop preserves `iterations[N].branch` in the run summary precisely so reviewers can walk the stack in order. Use `gh pr list --base <iter-N-branch>` to confirm dependencies.
- **Base-mismatch detection:** Supervisor's Phase 0/4/4.5 base-mismatch detection (added in v14) catches the case where a stacked iteration is unintentionally run against the wrong base; it emits `branch_base` + `pr_state` on `SUPERVISOR_RESULT` (with `pr_state: "closed_by_loop"` when Phase 4.5 retired the wrong-base PR) and surfaces upward as `supervisor_base_branch_mismatch` on `AUTONOMOUS_RUN.status_reason`.
- **Opt-out (`--no-stacked-branches`):** Forces every iteration to branch from the integration base — restores v13's branch-from-base cadence. Use this when iterations are truly independent or when your review process can't handle stacks. Each iteration produces a standalone PR.
- **Single iteration (`--max-iterations 1`):** Reproduces v13's default behavior exactly — runs Launch Pad → Supervisor once and exits. Useful when you just want command chaining without re-planning.
- **AUTONOMOUS_RUN summary:** Always lists `iterations[]` with `branch`, `pr_url`, and `status`/`status_reason` per iteration. The schema (v2 in v14) is documented in `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`.

### Running /autonomous in CI / unattended

`/autonomous` is designed as a foreground-assisted loop — most gates bubble `AskUserQuestion` in-session. For CI / cron / stdin-not-tty environments, opt in to a deterministic per-gate fail-closed policy:

- **`--non-interactive-fallback`** — engage the per-gate policy. Without this flag, an `AskUserQuestion` on a closed stdin will hang or error; with it, each gate has a defined non-interactive outcome:
  - **Rubric gate** (rubric_score N<M, multi-iter only): **aborts** with `status_reason: rubric_gate_closed_non_interactive` — the loop cannot verify a user merge, so it stops rather than guess. Inspect the PR manually and re-run if you want to continue.
  - **No-rubric `completed` run**: returns `done` with `status_reason: no_rubric_in_non_interactive` — without a rubric there's nothing to evaluate, so the iteration is treated as terminal.
  - **Adjudication gate** (Supervisor's 4-option scope-expansion question): when `--non-interactive-fallback` is set on `/autonomous`, the loop **auto-forwards `--non-interactive` to the inlined `/supervisor`**, so the adjudication gate (and Supervisor's Phase 4 `gh` retry path) fail closed consistently with the loop's own policy. A single `--non-interactive-fallback` on `/autonomous` is sufficient — you do NOT need to also pass `--non-interactive`. (Standalone `/supervisor` invocations still accept `--non-interactive` explicitly; the forwarding only applies inside `/autonomous`.)
  - **Launch Pad NO-GO override + Plan Review FAIL × 3**: with `--non-interactive-fallback` engaged, these gates abort the autonomous run rather than prompt for an override — fail-closed by design.
- **`--notify` + `AI_AGENT_MANAGER_WEBHOOK_URL`** — opt in to gate-event webhooks for out-of-band notification. Each gate (rubric, adjudication, NO-GO, Plan Review FAIL × 3) emits a JSON event constructed with `jq` (no shell interpolation into the JSON payload, for injection safety). Fire-and-forget POST; failures are logged to the session log but don't abort the run. Combine with `--non-interactive-fallback` for an unattended run that still pings you when a gate triggers — useful for monitoring long-running CI loops.
- **Recommended CI shape:** `claude /autonomous "..." --non-interactive-fallback --notify --max-iterations 3` with `AI_AGENT_MANAGER_WEBHOOK_URL` set in the CI environment. The loop auto-forwards `--non-interactive` to the inlined `/supervisor`, so you do not need to pass it separately. Examine the JSON sidecar at `.supervisor/autonomous/{session_id}/AUTONOMOUS_RUN.json` after the run; the `status_reason` will tell you exactly which gate (if any) closed the loop.

See `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md` for the full state machine and per-`status_reason` recovery actions.

### Enabling notifications (desktop + phone) — v14.1.0

The plugin surfaces a notification the moment a run pauses for you (Supervisor adjudication, `/autonomous` rubric gate, Plan Reviewer NEEDS_HUMAN, Launch Pad Phase 6, merge-and-continue) and on Claude Code's own `permission_prompt` / `idle_prompt` / `elicitation_*` events.

- **Desktop banners — work out of the box, no setup.** macOS uses `osascript`, Linux uses `notify-send`. On the first macOS fire, grant your terminal (or "Script Editor") notification permission in **System Settings → Notifications**. Hard-disable with `AI_AGENT_MANAGER_DESKTOP_NOTIFICATIONS=0`. Windows (outside WSL) has no desktop banner yet — use the phone/webhook path below.
- **Phone / chat push — set a webhook URL one of two ways:**
  - export `AI_AGENT_MANAGER_WEBHOOK_URL=...`, **or**
  - (more robust) create `.supervisor/notify-config.json` → `{"webhook_url":"https://ntfy.sh/your-topic"}`. The hook reads this file directly, so it works even when an env var set only in `~/.zshrc` doesn't propagate to the non-interactive hook shell. Make sure `.supervisor/` is in your project's `.gitignore` (it is by default once `/supervisor` has run) so the URL is never committed. The path resolves relative to the directory Claude Code runs in, so launch from your repo root.
  - **ntfy.sh** URLs get a readable plain-text push (with `Title`/`Priority`/`Tags`) automatically; Slack/Discord/custom endpoints get a JSON payload. Self-hosted ntfy: set `AI_AGENT_MANAGER_WEBHOOK_FORMAT=ntfy` to force the plain-text format.
- **Test it without a real run:** `AI_AGENT_MANAGER_WEBHOOK_DRY_RUN=1` makes `send-webhook.sh` print the constructed payload instead of POSTing — use it to verify your URL/format before relying on it.
- **Scope:** `AI_AGENT_MANAGER_NOTIFY_SCOPE=plugin` (default) only fires `AskUserQuestion` notifications when a plugin run is detected; `all` fires on every `AskUserQuestion` in any session.
- **Bidirectional (answer from anywhere):** the pause is a live, *same-session* wait — answering continues the run. To reply remotely (e.g. from your phone) so the session resumes without returning to the terminal, enable **Claude Code Remote Control**: the banner/push tells you to come back; Remote Control lets you answer.
- Notification stderr (e.g. revoked permissions) is logged to `.supervisor/logs/notifications.log`; webhook hooks always exit 0 (fire-and-forget).

### Plan-First Autonomous Workflow

```
/launch-pad goal: "add user authentication"
    ↓
Supervisor-Ready Brief saved to .supervisor/jobs/pending/
    ↓
/supervisor job: .supervisor/jobs/pending/{date}-{slug}.md   (fresh session)
    ↓
INIT → ACQUIRE → PRE-FLIGHT SYNC → PLAN → EXECUTE (via Execute Manager) → FINALIZE → SELF_HEAL → LOOP
    ↓
PR created, next task or exit
```

### Autonomous Workflow (Supervisor v4)

```
/supervisor task: "add user authentication"
    ↓
INIT: Detect env → Ask preferences → Create .supervisor/
    ↓
ACQUIRE: Select task → Create feature branch (MANDATORY)
    ↓
PRE-FLIGHT SYNC: Fetch remote → scan recent commits + open PRs → classify
                 CLEAR / OVERLAP / SUPERSEDED (silent on CLEAR; soft-gate or
                 fail-closed on overlap; --skip-preflight-sync escape hatch)
    ↓
PLAN: Orchestrator → Subtasks → Parallelism analysis
    ↓
EXECUTE: → Execute Manager (isolated context, 60 tool call budget)
         Worktree A ─→ Worker A ─→ Reviewer A ─→ PASS
         Worktree C ─→ Worker C ─→ Reviewer C ─→ PASS
         (unblocked) → Worktree B → Worker B → PASS
         ← EXECUTE_RESULT (merge_order, worktrees, branches)
    ↓
FINALIZE: Pre-merge validation → Commit in worktrees → Sequential merge → PR
    ↓
LOOP: Next task or exit
```

### Manual Workflow

```
Product Owner → Create user stories (requirements)
    ↓
Orchestrator → Break into tasks (EPIC → TASK → SUBTASK)
    ↓
You code
    ↓
Code Reviewer → PASS/FAIL/NEEDS_HUMAN (review gate)
    ↓
You fix issues (if needed)
    ↓
/commit → Conventional commits
    ↓
Next task
```

### QA Workflow

```
/qa-executor
    ↓
DETECT URL: playwright.config.ts → .env → ask user
    ↓
DISCOVER: Static analysis → Runtime crawl → Selective vision → Merge & gate
    ↓
STRATEGY: QA Strategist classifies routes (HIGH/MEDIUM/LOW risk)
    ↓
GENERATE: Strict tests (value assertions, negative tests, CRUD lifecycle,
          data integrity probes, security boundary tests)
    ↓
GAP ANALYSIS: Missing functionality detection → MISSING_FUNCTIONALITY_REPORT
    ↓
EXECUTE: npx playwright test --reporter=json
    ↓
COVERAGE: Routes discovered vs tested, APIs discovered vs tested
    ↓
AUDIT: QA Strategist reviews results + assertion quality + gaps → STRATEGIST_VERDICT
    ↓
QA_RESULT: passed | failed | needs_human
MISSING_FUNCTIONALITY_REPORT: gaps found in the app
```

**Requirements:**
- `playwright.config.ts` (or .js) must exist
- App must be running at the base URL
- `npx` available (Node.js installed)
- Playwright browsers installed (`npx playwright install`)

**Quick commands:**
```bash
/qa-executor                              # Full QA run (functional depth)
/qa-executor --skip-strategy              # Skip Strategist, use defaults
/qa-executor --url http://localhost:3000  # Override URL
/qa-executor --depth smoke                # Quick smoke tests only
/qa-executor --depth functional           # Deep tests (default)
/qa-strategist src/                       # Strategy only (no tests)
/qa-strategist --audit .qa-summary.md     # Audit existing QA results
```

### Session-Based QA (Large Apps)

For apps with many routes, use session-based QA to test in chunks:

```bash
# Step 1: Create a test plan (discovers all routes, groups into scopes)
/qa-executor --plan

# Step 2: Test one scope at a time
/qa-executor --scope auth            # Test auth scope
/qa-executor --scope tournaments     # Test tournaments scope
/qa-executor --scope billing         # Test billing scope

# Step 3: Continue with next unfinished scope
/qa-executor --continue              # Auto-picks next pending scope

# Step 4: Check cumulative coverage
# coverage.json tracks routes_tested/routes_total across sessions
```

**How it works:**
- `--plan` runs discovery and creates `.qa-session/plan.json` with scopes sorted by risk priority
- `--scope <name>` tests only routes in that scope, updates `.qa-session/coverage.json`
- `--continue` picks the next `pending` scope from the plan automatically
- Coverage accumulates across sessions — no retesting already-covered routes

### What the QA Agent Tests

**Assertion strictness (all modes):**
- Exact HTTP status assertions (`toBe(200)`, never `toContain([200, 500])`)
- Response body VALUE assertions (not just property existence)
- State verification after mutations (GET after POST/PUT/DELETE)
- 5xx responses are ALWAYS BLOCKING bugs — never accepted

**Negative testing (functional depth, HIGH/MEDIUM risk):**
- Empty body → expect 400
- Missing required fields → expect 400 with field name in error
- Wrong types → expect 400
- No auth / invalid auth → expect 401

**Multi-step flows (functional depth, HIGH risk):**
- CRUD lifecycle: create → read → update → verify → delete → verify gone
- Auth lifecycle: login → access protected → logout → verify session revoked

**Data integrity probes (functional depth, HIGH risk):**
- Concurrent creation race conditions (`Promise.all`)
- Duplicate creation → expect 409/400
- Cascade delete verification

**Security boundary tests (functional depth, HIGH risk):**
- Cross-resource access (IDOR) → expect 403/404
- Role escalation → expect 403
- Session invalidation after logout
- XSS/SQL injection probes (non-destructive)

**Missing functionality detection (all modes):**
- Missing CRUD operations (create exists but no edit/delete)
- Missing pagination on list endpoints
- Missing search/filter on data tables
- Missing input validation on forms
- Missing rate limiting on auth endpoints
- Missing confirmation dialogs on destructive actions
- Output: `MISSING_FUNCTIONALITY_REPORT` with severity + recommendations

---

## Telemetry (opt-in)

**New in v11.2.0 (preserved in v14.0.0)** — an optional GitHub Issues telemetry pipeline. After
qualifying agent runs (`/supervisor`, `/code-reviewer`, `/qa-executor`)
complete, the plugin can post a structured GitHub issue summarising the
result block, a derived score, agent performance breakdown, and AI
suggestions for longitudinal analysis. Telemetry is **disabled by
default** — there is no `origin`-remote fallback because the plugin runs
in arbitrary user projects.

```bash
/telemetry status     # Show consent state, target repo, last-sent timestamp
/telemetry enable     # Interactive — choose target repo, write consent file
/telemetry disable    # Mark consent denied; no further sends
/telemetry test       # Dry-run latest payload; never calls gh
```

**Privacy guarantees:** the wrapper script always exits 0 (telemetry
can never block an agent run); the core script fails closed on a regex
deny-list (tokens, API keys, bearer tokens, home-dir paths, emails,
`.env`-style assignments) and never emits matched content — only the
pattern label. To enable, run `/telemetry enable` (and pick a target
repo) or set `AI_AGENT_MANAGER_TELEMETRY_REPO=owner/repo`. See
[ai-agent-manager-plugin/docs/TELEMETRY.md](ai-agent-manager-plugin/docs/TELEMETRY.md)
for the scoring rubric, exit-code table, and wrapper-vs-core
architecture.

---

## System Twin (advisory foundation, v14.10.0)

The **System Twin** is an in-repo model of your own system that the agents
consult and update — entirely **advisory, propose-only, and strictly
subordinate to `CLAUDE.md`**. v14.10.0 ships its **foundation slice**: one thin,
additive, reversible vertical that exercises all three pillars on the plugin's
own repo. Nothing here gates a PR or self-applies a change.

- **Foundation — System Contracts.** A per-subsystem **System Contract** store
  under `.supervisor/twin/` (dependency graph, invariants, expectations) is
  written **exclusively** by the repo-root sole writer
  `scripts/write-system-contract.sh` — it refuses any git-worktree CWD,
  hash-chains provenance, and writes atomically. Contracts are read via
  `scripts/read-system-contract.sh` and self-tested by
  `scripts/test-system-contract.sh`. (Context-Keeper is deliberately not in this
  write path.)
- **Pillar 1 — Predict.** Launch Pad's analysis phase reads the contract's
  dependency graph to produce an advisory **blast-radius / impact prediction**
  for the requested work, degrading gracefully (no prediction, no error) when no
  contract exists yet.
- **Pillar 2 — Prove.** The Supervisor's post-merge self-heal phase runs an
  advisory **contract-conformance check** against the integrated diff plus a
  **deterministic benchmark**; an ephemeral builder then refreshes the contracts
  from the pinned repo-root CWD via the sole writer and emits a hard signal to
  both `SUPERVISOR_RESULT` and the session JSONL.
- **Pillar 3 — Compound.** `/insights` surfaces the conformance / benchmark
  trend over time, `/dreaming` reads contract drift as a distillation input, and
  the rubric-grader **reports** the signal as advisory lines — it never gates the
  PR.

**Guardrails:** propose-only (no self-applied Twin writes without the existing
human gate), advisory and subordinate to `CLAUDE.md`, sole-writer +
pinned-CWD enforcement, and every new script self-tested. The foundation added
**no new agent / command / skill / hook** — the builder is an ephemeral Task and
the helper scripts are not counted.

---

## Task Management

### Beads (Optional)

Beads is an optional issue tracker used by Orchestrator and Product Owner. The Supervisor and Launch Pad use `.supervisor/` exclusively.


| Command                   | Purpose                               |
| ------------------------- | ------------------------------------- |
| `bd list`                 | View open/in-progress/completed tasks |
| `bd create`               | Create new task                       |
| `bd claim BD-XX`          | Start working on a task               |
| `bd close BD-XX`          | Mark task complete                    |
| `bd comment BD-XX "note"` | Add notes to task                     |
| `bd dep BD-XX BD-YY`      | Set task dependencies                 |


**Task Structure:**

- **EPIC:** Large feature (contains multiple tasks)
- **TASK:** Implementation work (30-60 min)
- **SUBTASK:** Review gate (blocks next task)

**Review Gates:**

- Every implementation task has a review subtask
- Review subtask blocks next implementation task
- Review decisions: PASS (proceed), FAIL (fix and re-review), NEEDS_HUMAN (creates bug issues)

---

## Project Setup

### For New Projects

1. Create CLAUDE.md with your project structure and patterns
2. Run `/launch-pad goal: "first task"` (plan-first) or `/supervisor task: "first task"` (direct)
3. Optional: `bd init` if using Orchestrator/Product Owner with Beads

### CLAUDE.md Structure

Fill in once at the start:

```markdown
# [Your Project Name]

## Structure
- src/ — [what's here]
- test/ — [what's here]

## Tech Stack
- Node.js, Express, PostgreSQL
- Jest for testing

## Key Patterns
(Document as you discover them)

## Quick Commands
- Build: npm run build
- Test: npm test
- Lint: npm run lint
```

---

## Common Patterns & Best Practices

### Agents Follow These Rules

- **Quality First:** Thorough, well-tested solutions
- **Surgical Changes:** Only modify what's necessary
- **Pattern Consistency:** Use existing patterns
- **Type Safety:** Strict type checking
- **Security:** No secrets, validate inputs
- **Performance:** Profile and document tradeoffs

See `AGENT_GUIDELINES.md` for detailed standards per language.

### Workflow Tips

1. **Plan first:** Run `/launch-pad goal: "..."` to prepare a Supervisor-Ready Brief
2. **Use Supervisor for automation:** Run `/supervisor` for fully autonomous task completion
3. **Or start with Orchestrator:** Run `/orchestrator goal: "..."` for manual control
4. **Review iteratively:** Run `/code-reviewer` multiple times as you fix issues
5. **Review gates:** Wait for PASS before moving to next task
6. **Adversarial audit:** Run `/red-team-reviewer` before launch

### CLAUDE.md Proposal Workflow

When Code Reviewer discovers a new pattern:

1. **Flag in review output:** Pattern flagged with rationale and file:line references
2. **You review:** Check if worth documenting
3. **If approved:** You update CLAUDE.md manually
4. **Next agent learns:** Reads updated CLAUDE.md, uses the new pattern

This prevents knowledge loss and helps agents learn from discoveries.

---

## Documentation

- **This file (README.md):** Overview and quick start
- **CLAUDE.md (this repo):** Architecture and agent system
- **AGENT_GUIDELINES.md:** Development standards, quality checklist
- **.claude-plugin/marketplace.json:** Marketplace manifest (root)
- **.claude-plugin/README.md:** Detailed plugin documentation
- **ai-agent-manager-plugin/.claude-plugin/plugin.json:** Plugin manifest
- **ai-agent-manager-plugin/agents/*.md:** Individual agent prompts (13 roles)
- **ai-agent-manager-plugin/skills/*/SKILL.md:** 50 skill files for guidance
- **ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md:** Structured result contracts
- **ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md:** Agent failure paths
- **ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md:** Capability matrix, budgets, rules
- **ai-agent-manager-plugin/docs/ARCHITECTURE.md:** Visual agent topology
- **ai-agent-manager-plugin/docs/QA_SYSTEM_BLUEPRINT.md:** QA system architecture

---

## For Developers

To modify or extend agents:

1. Agents are Markdown prompts in `ai-agent-manager-plugin/agents/` (13 files)
2. Commands are in `ai-agent-manager-plugin/commands/` (12 commands)
3. Skills are in `ai-agent-manager-plugin/skills/` (50 skills, versioned with SKILLS_INDEX.md)
4. Hooks: per-agent in frontmatter (Worker, Execute Manager) + cross-cutting in `ai-agent-manager-plugin/hooks/hooks.json` (Code Reviewer, QA Executor, TaskCompleted)
5. Docs: `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md`, `…/FAILURE_ESCALATION.md`, `…/ARCHITECTURE_CONTRACTS.md`, `…/ARCHITECTURE.md`
6. All agents follow standard output format (see AGENT_GUIDELINES.md)

To test locally, install via the marketplace flow shown in **Quick Start → 1. Install the Plugin**, then run agents in a test project to verify changes. After pulling new changes, use the refresh flow under **Troubleshooting → Skills / agents / hooks not showing after plugin update**.

---

## Troubleshooting

**Agent doesn't understand my project?**

- Update CLAUDE.md with clearer patterns and examples
- Add more detailed structure documentation

**Supervisor workflow interrupted?**

- State is saved to `.supervisor/state.md` automatically
- Resume with: `/supervisor --continue`
- Check `.supervisor/history/` for completed sessions

**Orphaned worktrees after crash?**

- Run `git worktree list` to see all worktrees
- Remove with: `git worktree remove ../project-{subtask_id}`

**Beads tasks not appearing?**

- Run `bd list` to check current state
- Ensure `bd init` was run in project
- Beads is only used by Orchestrator/Product Owner (not Supervisor)

**Agents suggesting wrong patterns?**

- Update CLAUDE.md with approved patterns
- Review and reject unwanted proposals

**Need help?**

- Run `/agent-help` for command reference
- Check AGENT_GUIDELINES.md for quality standards
- Check .claude-plugin/README.md for detailed command documentation
- Review agent prompts in ai-agent-manager-plugin/agents/

**Skills / agents / hooks not showing after plugin update?**

Claude Code caches plugin contents. After pulling new changes (e.g. a fresh `git pull` on main), force a full refresh:

1. **Minimal flow** — try this first:
   ```
   /plugin uninstall ai-agent-manager-plugin
   /plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
   /reload-plugins
   ```
2. **Full reset** — if the minimal flow doesn't pick up your changes, drop the marketplace cache too:
   ```
   /plugin uninstall ai-agent-manager-plugin
   /plugin marketplace remove ai-agent-manager-marketplace
   /plugin marketplace add ./
   /plugin install ai-agent-manager-plugin@ai-agent-manager-marketplace
   /reload-plugins
   ```
   Run from the repo root so `./` resolves to your local checkout.
3. Verify with `/skills` — should show all 50 skills under "Plugin skills". Use `/agent-help` to confirm all 12 user-facing commands are registered.

**Previously installed via `claude --plugin-dir` (flat layout)?** Older install instructions told you to launch Claude with `--plugin-dir` pointing at the repo root. That no longer works — the plugin is now nested under `ai-agent-manager-plugin/`. Switch to the marketplace flow shown in **Quick Start → 1. Install the Plugin**.

---

## Known Limitations

### Agent Behavior

- **LLM limitations:** Agents may occasionally reference non-existent files despite validation steps. Always verify before following plans.
- **Context7 dependency:** External library lookups depend on Context7 MCP. If unavailable, agents fall back to CLAUDE.md patterns.

### Scale

- **Token usage:** Each agent invocation loads prompts (potentially 5,000-10,000 tokens overhead). Consider this for high-frequency usage.

### Git Operations

- **Main branch protection:** The `/commit` skill refuses commits on main/master without explicit flag.
- **No rollback:** Git operations are not automatically reversible. Use `git reflog` for manual recovery.

### QA System (Level 1)

- **Requires Playwright config:** `playwright.config.ts` must exist and app must be running
- **Crawl limits:** Max 30 pages, depth 3, same-origin only
- **Single debate round:** Strategist audits once (multi-round is Level 2+)
- **No state modeling or fuzz:** L1 tests happy paths + basic errors only
- **Coverage is inventory-level:** Tracks routes/APIs discovered vs tested, not behavioral

---

## License

MIT — See LICENSE file

---

**Happy shipping!**