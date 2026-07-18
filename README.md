# Loomwright

A Claude Code plugin for AI agents to collaborate on software projects. 14 specialized agents (Launch Pad, Supervisor v4, Execute Manager, Context-Keeper, Worker, Plan Reviewer, Rubric Grader, Product Owner, Orchestrator, Code Reviewer, Red Team Reviewer, Review-PR, QA Strategist, QA Executor) and the `/commit` skill automate plan-first readiness, parallel workflow execution, requirements, planning, review, commits, adversarial audits, standalone PR review-and-heal, and dual-agent QA automation.

**Key Idea:** Your projects need only a `CLAUDE.md` file for codebase knowledge. The Supervisor uses `.supervisor/` for state management. Orchestrator and Product Owner can optionally use [Beads issue tracker](https://github.com/anthropics/beads). Repeatable across any project.

> **Install the plugin and run slash commands instead of manually managing agents.**
>
> **NEW in v15.10.0 — CI-enforced per-agent prompt token budgets (`check-token-budget.sh`):** NEW repo-root CI ratchet on spawn-time prompt inventory — each agent's `.md` PLUS its frontmatter-preloaded SKILL.md files is weighed via an OFFLINE proxy (`bytes/4`, labeled "proxy tokens", never a live `count_tokens` call) and compared to the per-agent budget declared in `loomwright/docs/prompt-token-budgets.json` (human mirror: `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"); any breach, missing/non-integer budget, broken preloaded-skill reference, or inline flow-style `skills:` list fails CI CLOSED (exit 1). To raise a budget: edit the JSON in the same PR that breaches it, with a one-line note. Hermetic offline self-test (`scripts/test-check-token-budget.sh`). Counts unchanged: 14 agents / 21 commands / 41 skills / 22 hooks.
> **NEW in v15.9.0 — token ledger + insights Token economics + spawn-contract prompt-cache discipline:** fail-SAFE `token_ledger` SubagentStop emitter chained on existing telemetry hook lines (hooks stay 22); `/insights` advisory `## Token economics` rollup (real usage vs transcript-byte proxy); spawn contracts reordered stable-prefix-first + AGENT_GUIDELINES rule. Counts unchanged: 14 agents / 21 commands / 41 skills / 22 hooks.
> **NEW in v15.8.0 — Fable-parity: quarantined Agent SDK runner spike + opt-in `--sdk-runner` and `--multi-voter-heal` (both default OFF):** a quarantined, UNCOUNTED TypeScript spike (`loomwright/sdk-spike/`) ports ONLY Execute Manager's Phase 3 poll loop to `@anthropic-ai/claude-agent-sdk` with schema-forced WORKER_RESULT v2 / CODE_REVIEW_RESULT v3 results, worktree isolation with commit-before-remove, and an offline `--dry-run` self-test; `/supervisor --sdk-runner` (EXPERIMENTAL) shells Phase 3 out to it, failing CLOSED (`sdk_runner_unavailable`) if node or the built runner is absent; `/supervisor --multi-voter-heal` upgrades Phase 4.5 to two independent reviewers (code-reviewer + red-team-reviewer votes) with a second-opinion refute check before fixing — refuted findings logged, not fixed; gate shape unchanged. Provisional GO/NO-GO in `docs/SPIKES/SDK_RUNNER_SPIKE.md`; graduation gated on the pre-registered 5×3 protocol in `docs/SPIKES/FABLE_PARITY_EVAL.md`. Counts unchanged: 14 agents / 21 commands / 41 skills / 22 hooks.
> **NEW in v15.7.0 — knowledge-corpus curation + pre-registered advisory-loop eval:** the knowledge corpora can now forget, human-gated and auditable — NEW `curate-postmortem.sh` (`retract|supersede --target <key> --reason <text> --confirm`; dry-run exit 1 without `--confirm`, never writes unattended) hides retracted/superseded churn-ledger entries from the advisory reader, which also drops entries staler than `CHURN_STALE_DAYS` (default 180d; missing timestamp = fresh, fail-open); `write-lessons.sh retract` tombstones a lesson via a chain-valid provenance entry (last-action-wins, exit 4 on absent/untrusted target); `/insights` gains an advisory `## Corpus health` section; NEW pre-registered counterfactual-eval scaffold `docs/SPIKES/ADVISORY_LOOP_EVAL.md` (metrics + decision rule declared before any run; paired runs post-merge). Counts unchanged: 14 agents / 21 commands / 41 skills / 22 hooks.
> **NEW in v15.6.0 — stackpack + mysql-mcp spin-off (marketplace now lists 3 plugins):** the 18 generic tech-stack skills (Next.js ×5, NestJS ×5, API Gateway ×4, MySQL/PostgreSQL/Redis Caching, Docker) moved to the NEW sibling plugin **stackpack**, and the bundled read-only MySQL MCP server moved to the NEW sibling plugin **mysql-mcp**. **Migration note:** if your workflows relied on those skills or the MCP server, install them — `/plugin install stackpack@atelier` and `/plugin install mysql-mcp@atelier`. Loomwright keeps the orchestration core; no agents/commands/hooks change. Counts: 14 agents / 21 commands / 41 skills (59 → 41) / 22 hooks.
> **NEW in v15.5.0 — Script-test gap closure + WorktreeRemove hook + advisory LSP wiring:** `test-webhook.sh` gains hostile-string exact round-trip + format-branch cases (10–19); NEW PATH-sandboxed `test-notify-desktop.sh` (40 cases) proves `notify-desktop.sh`'s always-exit-0 fail-safe contract; NEW `WorktreeRemove` hook mirrors WorktreeCreate (hooks 21 → 22, closing the roadmap's last OPEN item #6) plus a `|| true` fail-safe sweep on the 11 command hooks that lacked it; advisory `LSP` wired into worker / qa-executor / launch-pad frontmatter (never-gating). Counts: 14 agents / 21 commands / 59 skills / 22 hooks.
> **NEW in v15.4.0 — Supervisor prompt refactor: phase protocol bodies extracted into 4 authority skills (structure-only, zero behavior change):** `agents/supervisor.md` shrinks 1652 → 748 lines (the per-session context win comes from the three on-demand skills; the FINALIZE/Session-Logging text moved into Supervisor-preloaded skills relocates rather than removes those lines). Phase 1.5 PRE-FLIGHT SYNC → NEW `skills/preflight-sync/SKILL.md` and Phase 0 INIT → NEW `skills/supervisor-config/SKILL.md` (both read at phase entry — deliberately NOT preloaded); the Phase 4.5 SELF_HEAL loop protocol → `skills/self-heal-advisory/SKILL.md` Part 2; Phase 4 FINALIZE mechanics + Subagent Spawn Contracts + Git Worktree Lifecycle → `skills/async-orchestration/SKILL.md` Part 2; the Session Logging event catalog → `skills/state-management/SKILL.md`. Every gate stays in the agent file (completion-tail guard verbatim; pre-merge safety gate; PR-base self-verify; budgets 50/60); `SUPERVISOR_RESULT` schema untouched. Counts: 14 agents / 21 commands / 59 skills (57 → 59) / 21 hooks; no `schema_version` bump.
>
> **NEW in v15.3.0 — fail-closed resume validation gate (`resume_state_invalid`):** `/supervisor --continue` now schema-validates the loaded `.supervisor/state.md` BEFORE consuming it: the `## Session` block must exist, `phase`/`status` must be in the closed enums, and any asserted `branch:` must `git rev-parse --verify` (authoritative contract: `skills/state-management/SKILL.md` §"Resume validation gate", skill 1.1.0 → 1.2.0). Any violation refuses the resume with `error: "resume_state_invalid"` and an inspect-or-delete instruction — never a silent fresh-start fallback, and no override flag (deleting the bad state file is the escape hatch). A missing state file still starts fresh unchanged; a valid file resumes identically. READ-side only — the Context-Keeper sole-writer contract is untouched. Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks; no `schema_version` bump.
>
> **NEW in v15.2.3 — SKILLS_INDEX version-cell CI parity gate + roadmap de-staling (doc-hygiene):** New repo-root validator `scripts/check-skills-index-sync.sh` mechanically enforces `SKILLS_INDEX.md` ↔ SKILL.md frontmatter version parity (rows keyed on the backticked dir-path cell; ghost/duplicate/malformed rows also fail) — a documented doc-currency blind spot, now a hard CI gate with a synthetic-fixture `--self-test` (every DRIFT branch proven to fail via synthetic fixtures). Fixes the one live drifted row (supervisor-readiness 1.1.1 → 1.1.2). `docs/IMPROVEMENTS_ROADMAP.md` gains a dated planning-snapshot banner + 18 re-verified inline `[VERDICT: …]` lines (10 RESOLVED / 7 DEFERRED / 1 OPEN — only the `WorktreeRemove` hook remains open). Both Quick Starts add a one-line `/setup` pointer. Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks.
>
> **NEW in v15.2.2 — direct deterministic self-test for the telemetry core (tests-only):** New `loomwright/scripts/test-send-telemetry-core.sh` unit-tests `send-telemetry-core.sh`'s privacy/consent/dedup pipeline directly (83 assertions across a 7-group matrix): all 9 `PRIVACY_PATTERNS` labels pinned to exit 2 + their exact `PRIVACY_BLOCKED` stderr line, the v11.2.0 privacy-before-consent ordering guarantee, the malformed-consent fail-closed path, nullable/missing-key discipline, seeded dedup determinism, and `[REDACTED:<label>]` markers exercised via the extracted production stage-1 code. `gh` is proven never-invoked (fail-loud PATH shim + dry-run-only would-send paths); everything runs in a mktemp sandbox. Zero behavior change. Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks.
>
> **NEW in v15.2.1 — "Which command?" decision table + flag-table completeness audit (docs-only):** README, the plugin README, and `/agent-help` now open their Commands sections with a consistent "Which command?" decision table (per-row notes on what each command does NOT do — none merge except `/automate --auto-merge`, opt-in). The Parameters tables in `commands/supervisor.md` / `autonomous.md` / `automate.md` were audited for completeness (defaults + "only meaningful when" preconditions; the forwarded-flag set in `autonomous.md` now mirrors the autonomous-loop skill exactly). No behavior change. Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks.
>
> **NEW in v15.2.0 — `--cheap` cost profile forwarded through `/automate → /autonomous → /supervisor` (additive):** `--cheap` is now a real, forwarded flag on `/autonomous` and `/automate` — the Sonnet cost profile propagates through the full nesting chain to the Supervisor's existing cost-profile engine (reused unchanged). Strictly opt-in; no-flag behavior is byte-for-byte unchanged. Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks; no `schema_version` bump.
>
> **NEW in v15.1.0 — advisory house-rules ENFORCEMENT wired at 3 seams + `/rules add`/`check` mechanized (slice #3b-ii, additive):** Completes the `.agent/rules/` House Rules slice. The fail-safe reader `read-rules.sh` is now consumed as ADVISORY, never-gating context at three seams — the worker DO-side (rules injected into worker prompts), the Phase 4.5 self-heal REVIEW lens (a HOUSE-RULES ADVISORY line threaded into the `code-reviewer` prompt), and a SessionStart nudge folded into `session-resume.sh` (hook-neutral) — mirroring the `prior_churn` advisory pattern, never changing a `heal_decision` or gating a PR. `/rules add` is mechanized into the sole-writer `add-rule.sh` (path-containment + traversal rejection, proven by `test-add-rule.sh`); `/rules check` is mechanized into `rules-check.sh` with a default-off `--no-cmd` unattended trust valve (which wins over `--confirm`); the reader still never executes a `check`. Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks; no `schema_version` bump. Additive on top of v15.0.0.
>
> **NEW in v15.0.0 — Loomwright / atelier naming baseline (mechanical):** Establishes the plugin id `loomwright`, the marketplace id `atelier`, and the `LOOMWRIGHT_*` environment-variable prefix (25 vars). No functional/behavioral change — mechanical release only. Counts unchanged: 14 agents / 21 commands / 57 skills / 21 hooks; no `schema_version` bump.
>
> **NEW in v14.51.0 — new `/rules` House Rules substrate command (advisory, additive):** Adds ONE new slash command (`commands/rules.md`) and ONE new skill (`skills/rules/`) that establish a committed, project-local **House Rules store** under `.agent/rules/` — durable team conventions that agents can surface but that never gate or execute. `/rules` supports **list / suggest / add / check** verbs over the store, backed by a fail-safe reader `scripts/read-rules.sh` (silently skips an absent store, always exits 0). Substrate only — enforcement is deferred to a later slice. Advisory / fail-safe / never-executes-a-check — it reads and reports conventions but never blocks a PR, changes a `heal_decision`, or runs anything. One new command (count 20 → 21) and one new skill (count 56 → 57); agent / hook counts unchanged at 14 agents / 21 hooks; no `schema_version` bump.
>
> **NEW in v14.13.0 — Clickable desktop notifications (opt-in, macOS):** Install [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) and the pause-event banner becomes **clickable** — clicking brings the **Claude desktop app to the foreground** (default). Set `LOOMWRIGHT_NOTIFY_CLICK=resume` to instead deep-link to the exact session via `claude://…/resume` — works on older macOS, but on **macOS 26** `terminal-notifier`'s click callback can't fire, so `activate` (focus the app) is the reliable default. Without `terminal-notifier` the existing `osascript` banner is unchanged — **zero regression**. Click logic lives in a **self-tested pure helper** (`scripts/notify-click-target.sh`, 15 cases incl. injection-safety). No new agent / command / skill / hook (still **13 / 15 / 50 / 19**), no schema change.
>
> **NEW in v14.10.0 — System Twin foundation slice (advisory, propose-only):** One thin, additive, reversible vertical that exercises all three System Twin pillars on the plugin's own repo while staying **advisory and strictly subordinate to `CLAUDE.md`**. A `.supervisor/twin/` per-subsystem **System Contract** store is written **only** by the repo-root sole writer `scripts/write-system-contract.sh` (worktree-guard + hash-chained provenance + atomic; read via `read-system-contract.sh`; self-tested). **Predict:** Launch Pad reads the contract's dependency graph for advisory **blast-radius** prediction (graceful fallback when absent). **Prove:** Supervisor Phase 4.5 runs an advisory **contract-conformance check** on the integrated diff plus a **deterministic benchmark**, then an ephemeral builder writes contracts from the pinned repo-root CWD and emits a hard signal to `SUPERVISOR_RESULT` + the session JSONL. **Compound:** `/insights` surfaces the conformance/benchmark trend, `/dreaming` reads contract drift, and the rubric-grader **reports** the signal as advisory lines that never gate. Propose-only, no self-applied writes without the existing human gate — no new agent/command/skill/hook (still 13 / 14 / 50 / 19).
>
> **NEW in v14.9.0 — `/capability-check --strategy`: product-direction strategist:** `--strategy` turns `/capability-check` from a pure platform-adoption diff into a grounded product-evolution pass that proposes **scored, deduped, differentiated product directions** (reusing the brainstorming skill), each grounded in a real product asset plus a newly-feasible enabler or an explicit drop. Default (no-flag) behavior is unchanged; the mode is propose-only, bounded, and human-gated — no new command/agent/skill/hook (still 13 / 14 / 50 / 19).
>
> **NEW in v14.3.0 — Advisory project memory (P2b):** Agent-writable, cross-session **project memory** under `.supervisor/memory/` so the plugin stops re-discovering your codebase each run. Built behind guardrails: a **sole writer** (`scripts/write-project-memory.sh`) that **refuses git-worktree CWDs** + hash-chains provenance + caps at 200 lines, and a **read-side gate** (`scripts/read-project-memory.sh`) that emits only chain-verified entries (poisoned lines dropped). Memory is **advisory, subordinate to `CLAUDE.md`, human-gated** — Launch Pad reads it during analysis and *proposes* new facts for your approval. Launch-Pad-only in v1; no new agent/skill/command/hook (still 19 hooks).
>
> **NEW in v14.2.2 — Notification polish (patch):** `notify-desktop.sh` now **debounces** rapid notification bursts into a single banner (`LOOMWRIGHT_NOTIFY_DEBOUNCE`, default 5s) and **detects the display** on Linux (skips `notify-send` on headless). `/autonomous --notify` **fails loud** if no webhook URL is resolvable (env var or `.supervisor/notify-config.json`) instead of silently doing nothing. No hook/schema/agent change (still 19 hooks).
>
> **NEW in v14.2.1 — Webhook + telemetry result-extraction fix (patch):** The supervisor-completion webhook (`send-webhook.sh`) and the opt-in telemetry post (`send-telemetry-core.sh`) read the finishing agent's output from the **real** `SubagentStop` payload field — `last_assistant_message` (with the legacy `result_block` / `output` / `agent_output` names and the `agent_transcript_path` / `transcript_path` JSONL as fallbacks) — instead of a top-level `result_block` field that Claude Code never actually sends. The pre-fix readers resolved to empty and **silently suppressed every supervisor-completion webhook and telemetry issue** since v14.1.0. No hook-count (still 19), schema, agent, command, or skill change. See `loomwright/docs/TELEMETRY.md` §"Result-text extraction".
>
> **NEW in v14.0.0 — Continuous autonomous mode with stacked PRs:** `/autonomous` flips to **multi-iteration by default** (cap 10, default `--max-iterations 3`) with **stacked-branch semantics** — iteration N+1 branches from `iterations[N].branch`, producing a reviewable PR stack. Out-of-order merge hazard: reviewers MUST merge the bottom of the stack first (follow `AUTONOMOUS_RUN.iterations[]` order). Restore v13 cadence with `--no-stacked-branches`; reproduce v13's single-iteration default with `--max-iterations 1`. New flags: **`--notify`** (opt-in gate-event webhooks for rubric / adjudication / NO-GO / Plan Review FAIL × 3, gated on `LOOMWRIGHT_WEBHOOK_URL`, jq-only payload construction for injection safety, fire-and-forget POST) and **`--non-interactive-fallback`** (per-gate fail-closed policy for CI / stdin-not-tty: rubric gate aborts, no-rubric `completed` returns `done`, adjudication inherits Supervisor's `--non-interactive` policy when forwarded). Supervisor gains `--base-branch <ref>` + `--non-interactive` + Phase 0/4/4.5 base-mismatch detection + cleanup, and emits optional additive `branch_base` + `pr_state` fields on `SUPERVISOR_RESULT` (schema_version still 1, optional). Context-Keeper gains atomic `set_flag` / `get_flag` / `clear_flag` operations writing under a new `## Phase Flags` section in `state.md`. `AUTONOMOUS_RUN` bumps to **schema_version 2** with nine new closed `status_reason` values. **W-NEW-3 spike PASSED pre-merge**: Code Reviewer + Rubric Grader both honor `DIFF-SCOPE OVERRIDE` inline directives on stacked-branch fixtures. v14 is additive on top of v13: no new agent, no hook count change in v14.0.0 (still 14). **v14.1.0** adds desktop + webhook pause notifications (`PreToolUse[AskUserQuestion]` + `Notification` hooks), bringing the hook count 14 → 17 — see "Enabling notifications" below. **v14.2.0** adds the concurrency/resume layer — a `LAUNCH_PAD_RESULT` schema (so `saved_brief_path` becomes the primary `/autonomous` brief-detection signal, retiring the fragile `ls`-diff) plus a `SessionStart` crash/compact resume hook — bringing the count 17 → 19. All v13.0.0 / v13.0.1 capabilities preserved (foreground-assisted gates, rubric-gate user-merge verification, Option C `inter_subtask_gap` re-plan, webhook empty-payload suppression). 14 agent roles, 21 slash commands, 41 skills, 22 quality gate hooks *(this totals sentence is rolling-current — it is scanned by the doc-currency CI gate and updated on every release, unlike the frozen dated prose around it)*. All v12.2.0 capabilities preserved (Agent Teams graduation, Outcomes Rubric, `/dreaming`, opt-in SubagentStop webhook hook) and v12.1.0 documentation increments preserved.
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
/plugin marketplace add /path/to/loomwright
/plugin install loomwright@atelier
```

The repo is a marketplace wrapper (`/.claude-plugin/marketplace.json`) with the plugin nested at `loomwright/`. The first command registers the marketplace, the second installs the plugin from it.

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

**Optional integrations in one place:** run `/setup` to configure optional integrations — observability (local Langfuse + OTel collector), telemetry, notifications, webhook, Beads, MySQL MCP, and Twin cold-start bootstrap (code graph + bridge + starter CLAUDE.md) — from a single status dashboard.

### 3. (Optional) Enable MySQL MCP

A read-only MySQL MCP server (schema inspection, query execution with impact analysis, multi-DB profile switching) ships as the sibling **mysql-mcp** plugin — it moved out of loomwright in v15.6.0. Install it first:

```
/plugin install mysql-mcp@atelier
```

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

The MCP server starts automatically via `uvx` when the mysql-mcp plugin is loaded — no extra steps needed.

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
/autonomous "what you want to accomplish" --notify                       # opt-in gate webhooks (LOOMWRIGHT_WEBHOOK_URL)
/autonomous "what you want to accomplish" --non-interactive-fallback     # CI / unattended: per-gate fail-closed policy
```

Optional next: run `/setup` for a status dashboard and guided configuration of optional capabilities (observability, telemetry, notifications, Twin bootstrap).

### Which command?

| I want to… | Run | What it does NOT do |
|---|---|---|
| Start a new task/goal | `/launch-pad goal: "..."` then `/supervisor job: <brief>` (or `/autonomous` for the chained loop) | Never merges — the PR is left open for a human |
| Multi-iteration on ONE goal, with stacked PRs | `/autonomous "<requirement>"` | Never merges — stacked PRs are merged bottom-up by a human |
| Work through a queue of independent goals (folder / backlog / prompt) | `/automate ...` | Default mode never merges; only the opt-in `--auto-merge` gate (default OFF) can merge |
| Review-and-heal an existing PR | `/review-pr <pr-url>` | Never merges — pushes fixes, leaves the PR open |
| Review-only of my diff, no fixes | `/code-reviewer` | Read-only — no fixes, no commits, never merges |

---

## The 14 Agents

### User-Facing Agents (9 + commit skill)


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
| **Review-PR**         | `/review-pr <pr-url>`           | Standalone review→fix→re-review loop against an existing PR; auto-heals the diff, never auto-merges → REVIEW_HEAL_RESULT | Review/heal any open PR         |
| **Setup** (command)   | `/setup [module]`               | Status dashboard + guided configuration for every optional capability — observability (local Langfuse + OTel collector), telemetry, notifications, webhook, Beads, MySQL MCP, Twin cold-start bootstrap | First install, enabling integrations |
| **Rules** (command)   | `/rules [list\|suggest\|add\|check]` | House Rules substrate — committed `.agent/rules/` conventions store + fail-safe reader; list/suggest/add/check | Capturing durable team conventions |


### Internal Agents (5)


| Agent               | Spawned By                   | Purpose                                                               |
| ------------------- | ---------------------------- | --------------------------------------------------------------------- |
| **Execute Manager** | Supervisor (Phase 3)         | Own poll loop, worker/reviewer lifecycle, Context-Keeper coordination |
| **Context-Keeper**  | Supervisor / Execute Manager | Manage externalized state file (sole writer)                          |
| **Worker**          | Execute Manager / Supervisor | Implement a single subtask in an isolated git worktree                |
| **Plan Reviewer**   | Launch Pad                   | Validate Supervisor-Ready Briefs before execution                     |
| **Rubric Grader**   | Supervisor (Phase 4.5)       | Read-only Haiku scorer for the optional Outcomes Rubric (advisory)    |


### Orchestration Shell: `/autonomous` (v14.0.0)

`/autonomous` is **not** a new agent — it is a slash command that chains the agents above. The command body (`loomwright/commands/autonomous.md`) is executed inline on the main thread: it reads `commands/launch-pad.md` and `commands/supervisor.md` at Step 0, then runs Launch Pad inline (which still Task-spawns `plan-reviewer`), then runs Supervisor inline (which still Task-spawns `orchestrator` / `execute-manager` / `code-reviewer` / `rubric-grader`). **Default mode is multi-iteration** (cap 10, default `--max-iterations 3`) with **stacked PRs**: iteration N+1 branches from `iterations[N].branch`. The loop re-plans on the same two existing `SUPERVISOR_RESULT` signals as v13 (rubric N<M with user-merge confirmation; `failed + inter_subtask_gap` from Option C adjudication). The protocol skill is at `loomwright/skills/autonomous-loop/SKILL.md`.

### Stacked PR workflow (v14.0.0+)

The v14 default flips `/autonomous` from "run once, return" to a continuous loop that produces a **stack of PRs**, one per iteration:

- **Branching:** Iteration 1 branches from the integration base (typically `origin/main`). Iteration N+1 branches from `iterations[N].branch` — the previous iteration's feature branch — so each iteration builds on top of the prior unmerged work. This produces a reviewable bottom-up stack rather than divergent siblings.
- **Out-of-order merge hazard:** Reviewers MUST merge the **bottom** of the stack first (the earliest iteration, listed first in `AUTONOMOUS_RUN.iterations[]`). Merging a higher iteration before its base leaves the remaining higher iterations rebased against the wrong base and produces phantom conflicts. The autonomous-loop preserves `iterations[N].branch` in the run summary precisely so reviewers can walk the stack in order. Use `gh pr list --base <iter-N-branch>` to confirm dependencies.
- **Base-mismatch detection:** Supervisor's Phase 0/4/4.5 base-mismatch detection (added in v14) catches the case where a stacked iteration is unintentionally run against the wrong base; it emits `branch_base` + `pr_state` on `SUPERVISOR_RESULT` (with `pr_state: "closed_by_loop"` when Phase 4.5 retired the wrong-base PR) and surfaces upward as `supervisor_base_branch_mismatch` on `AUTONOMOUS_RUN.status_reason`.
- **Opt-out (`--no-stacked-branches`):** Forces every iteration to branch from the integration base — restores v13's branch-from-base cadence. Use this when iterations are truly independent or when your review process can't handle stacks. Each iteration produces a standalone PR.
- **Single iteration (`--max-iterations 1`):** Reproduces v13's default behavior exactly — runs Launch Pad → Supervisor once and exits. Useful when you just want command chaining without re-planning.
- **AUTONOMOUS_RUN summary:** Always lists `iterations[]` with `branch`, `pr_url`, and `status`/`status_reason` per iteration. The schema (v2 in v14) is documented in `loomwright/docs/RESULT_SCHEMAS.md`.

### Running /autonomous in CI / unattended

`/autonomous` is designed as a foreground-assisted loop — most gates bubble `AskUserQuestion` in-session. For CI / cron / stdin-not-tty environments, opt in to a deterministic per-gate fail-closed policy:

- **`--non-interactive-fallback`** — engage the per-gate policy. Without this flag, an `AskUserQuestion` on a closed stdin will hang or error; with it, each gate has a defined non-interactive outcome:
  - **Rubric gate** (rubric_score N<M, multi-iter only): **aborts** with `status_reason: rubric_gate_closed_non_interactive` — the loop cannot verify a user merge, so it stops rather than guess. Inspect the PR manually and re-run if you want to continue.
  - **No-rubric `completed` run**: returns `done` with `status_reason: no_rubric_in_non_interactive` — without a rubric there's nothing to evaluate, so the iteration is treated as terminal.
  - **Adjudication gate** (Supervisor's 4-option scope-expansion question): when `--non-interactive-fallback` is set on `/autonomous`, the loop **auto-forwards `--non-interactive` to the inlined `/supervisor`**, so the adjudication gate (and Supervisor's Phase 4 `gh` retry path) fail closed consistently with the loop's own policy. A single `--non-interactive-fallback` on `/autonomous` is sufficient — you do NOT need to also pass `--non-interactive`. (Standalone `/supervisor` invocations still accept `--non-interactive` explicitly; the forwarding only applies inside `/autonomous`.)
  - **Launch Pad NO-GO override + Plan Review FAIL × 3**: with `--non-interactive-fallback` engaged, these gates abort the autonomous run rather than prompt for an override — fail-closed by design.
- **`--notify` + `LOOMWRIGHT_WEBHOOK_URL`** — opt in to gate-event webhooks for out-of-band notification. Each gate (rubric, adjudication, NO-GO, Plan Review FAIL × 3) emits a JSON event constructed with `jq` (no shell interpolation into the JSON payload, for injection safety). Fire-and-forget POST; failures are logged to the session log but don't abort the run. Combine with `--non-interactive-fallback` for an unattended run that still pings you when a gate triggers — useful for monitoring long-running CI loops.
- **Recommended CI shape:** `claude /autonomous "..." --non-interactive-fallback --notify --max-iterations 3` with `LOOMWRIGHT_WEBHOOK_URL` set in the CI environment. The loop auto-forwards `--non-interactive` to the inlined `/supervisor`, so you do not need to pass it separately. Examine the JSON sidecar at `.supervisor/autonomous/{session_id}/AUTONOMOUS_RUN.json` after the run; the `status_reason` will tell you exactly which gate (if any) closed the loop.

See `loomwright/skills/autonomous-loop/SKILL.md` for the full state machine and per-`status_reason` recovery actions.

### Automation Engine: `/automate` (v14.41.0)

`/automate` is **not** a new agent — it is an inline main-thread slash command (`loomwright/commands/automate.md`, governed by `loomwright/skills/automate-loop/SKILL.md`) that walks arbitrary work from any starting point. It converts any **source** — a prompt (via `/product-owner`), a requirements folder, or a backlog/plan doc — into a full Queue inside a **single run file** `.supervisor/automate/<run_id>.md` (the contract, dashboard, and resume state; no manifest/registry/JSONL ledger), then drives each Queue item through the per-item loop: `/autonomous --single-iteration` → **one owned inline `/review-pr --until-mergeable` drain** → trusted-merge-or-park → sync `main` → check the item off. Layering: `/autonomous` (one requirement) ⊂ per-item loop ⊂ `/automate` (source → Queue → loop).

```bash
/automate "<what you want to automate>"   # prompt source (via /product-owner) → Queue
/automate                                  # bare → resume an incomplete run, else ASK
/automate --folder <dir>                   # folder source — each *.md becomes a Queue item
/automate --backlog <_BACKLOG.md>          # backlog-doc source — dependency-ordered Queue
/automate --limit N                        # cap PROCESSED items this run (default 5; full Queue still stored)
/automate --resume [<run_id>]              # reconcile + continue a prior incomplete run
/automate ... --auto-merge                 # opt-in, default-OFF, 5-condition fail-closed merge gate
```

- **Single run file + smart resume:** on start it globs `.supervisor/automate/*.md` for runs not marked `## Status: done`, reconciles each in-flight item against ground truth (`gh`/`git`/`## Status:` stamps) before trusting a checkbox, then offers continue / start-fresh / archive. The run file is written atomically (temp + rename); `## Progress` is append-only.
- **Single drain, single open PR:** `/automate` suppresses the default detached until-mergeable drain (`.supervisor/config.json {"auto_review": false}` around the inner `/autonomous` RUN phase, restored finally-style) and owns exactly ONE inline `/review-pr --until-mergeable` drain — no double-dispatch. While any item has an open unmerged PR (awaiting_merge or escalated) the loop will not pick a new item.
- **Merge is opt-in and fail-closed:** default mode never merges (`READY` PRs are left open for a human). `--auto-merge` is the **only** place in the plugin that executes `gh pr merge --squash`, behind a 5-condition fail-closed gate; `review-heal` / Supervisor Phase 4.5 still never merge. `ESCALATED` never merges and parks the run.

See `loomwright/commands/automate.md` and the `automate-loop` skill for the full state machine; the run-file layout is documented as `AUTOMATE_RUN` in `loomwright/docs/RESULT_SCHEMAS.md`.

### Enabling notifications (desktop + phone) — v14.1.0

The plugin surfaces a notification the moment a run pauses for you (Supervisor adjudication, `/autonomous` rubric gate, Plan Reviewer NEEDS_HUMAN, Launch Pad Phase 6, merge-and-continue) and on Claude Code's own `permission_prompt` / `idle_prompt` / `elicitation_*` events.

- **Desktop banners — work out of the box, no setup.** macOS uses `osascript`, Linux uses `notify-send`. On the first macOS fire, grant your terminal (or "Script Editor") notification permission in **System Settings → Notifications**. Hard-disable with `LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0`. Windows (outside WSL) has no desktop banner yet — use the phone/webhook path below.
- **Clickable desktop banners (macOS, opt-in) — click the banner to jump straight to Claude.** The built-in `osascript` banner can't carry a click action (clicking it just opens *Script Editor*), so install [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) — when present, the banner becomes clickable. Click behaviour is set by `LOOMWRIGHT_NOTIFY_CLICK`:
  - `activate` (default) — click **brings the Claude desktop app to the foreground**. Reliable on modern macOS (incl. macOS 26); for a single active session, focusing the app lands you back on it.
  - `resume` — click opens `claude://claude.ai/resume?session=<id>` to jump back to the **exact** session. ⚠️ Works only where `terminal-notifier`'s `-open` click still fires (older macOS). On **macOS 26 the click callback is dead** (`terminal-notifier` 2.0.0 relies on the deprecated `NSUserNotification` delegate), so a clicked `resume` banner won't navigate — use `activate` there. The `claude://…/resume` route itself is valid (reachable via a direct `open`), it just can't be triggered from a notification click on macOS 26.
  - `auto` — focuses the app when you're already inside the desktop app; otherwise resumes. ⚠️ Its resume branch inherits the same macOS 26 click-callback caveat as `resume` above — so on macOS 26 a terminal/CLI session under `auto` gets the dead-click behaviour; prefer `activate` there.
  - `off` — non-clickable banner (the pre-`terminal-notifier` behaviour).

  Notes: do **not** expect the Claude icon on the banner — impersonating Claude's bundle id (`-sender`) is silently dropped by macOS 26, so the banner uses `terminal-notifier`'s own icon. The `claude://` resume route is an **undocumented desktop-app surface**; `resume` always degrades safely to focusing the app. Without `terminal-notifier` installed, everything behaves exactly as before (plain `osascript` banner).
- **Phone / chat push — set a webhook URL one of two ways:**
  - export `LOOMWRIGHT_WEBHOOK_URL=...`, **or**
  - (more robust) create `.supervisor/config.json` → `{"webhook_url":"https://ntfy.sh/your-topic"}`. The hook reads this file directly, so it works even when an env var set only in `~/.zshrc` doesn't propagate to the non-interactive hook shell. (The legacy `.supervisor/notify-config.json` is still read as a fallback; the new path wins when both exist.) Make sure `.supervisor/` is in your project's `.gitignore` (it is by default once `/supervisor` has run) so the URL is never committed. The path resolves relative to the directory Claude Code runs in, so launch from your repo root.

    > **Migration note (config file rename):** the run-behavior config file was renamed back-compatibly from `.supervisor/notify-config.json` → `.supervisor/config.json`. Readers prefer the new path and fall back to the legacy one, so **existing installs keep working with no action**. To migrate, either run `mv .supervisor/notify-config.json .supervisor/config.json`, or simply do nothing and let the fallback handle it. Migrate the *whole* file — don't split keys across both, since resolution selects one file (the new one when present), so legacy-only keys in `notify-config.json` would be ignored once `config.json` exists.
  - **ntfy.sh** URLs get a readable plain-text push (with `Title`/`Priority`/`Tags`) automatically; Slack/Discord/custom endpoints get a JSON payload. Self-hosted ntfy: set `LOOMWRIGHT_WEBHOOK_FORMAT=ntfy` to force the plain-text format.
- **Test it without a real run:** `LOOMWRIGHT_WEBHOOK_DRY_RUN=1` makes `send-webhook.sh` print the constructed payload instead of POSTing — use it to verify your URL/format before relying on it.
- **Scope:** `LOOMWRIGHT_NOTIFY_SCOPE=plugin` (default) only fires `AskUserQuestion` notifications when a plugin run is detected; `all` fires on every `AskUserQuestion` in any session.
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
repo) or set `LOOMWRIGHT_TELEMETRY_REPO=owner/repo`. See
[loomwright/docs/TELEMETRY.md](loomwright/docs/TELEMETRY.md)
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
- **loomwright/.claude-plugin/plugin.json:** Plugin manifest
- **loomwright/agents/*.md:** Individual agent prompts (14 roles)
- **loomwright/skills/*/SKILL.md:** 57 skill files for guidance
- **loomwright/docs/RESULT_SCHEMAS.md:** Structured result contracts
- **loomwright/docs/FAILURE_ESCALATION.md:** Agent failure paths
- **loomwright/docs/ARCHITECTURE_CONTRACTS.md:** Capability matrix, budgets, rules
- **loomwright/docs/ARCHITECTURE.md:** Visual agent topology
- **loomwright/docs/QA_SYSTEM_BLUEPRINT.md:** QA system architecture

---

## For Developers

To modify or extend agents:

1. Agents are Markdown prompts in `loomwright/agents/` (14 files)
2. Commands are in `loomwright/commands/` (21 commands)
3. Skills are in `loomwright/skills/` (41 skills, versioned with SKILLS_INDEX.md; 18 tech-stack skills live in the sibling `stackpack/` plugin)
4. Hooks: per-agent in frontmatter (Worker, Execute Manager) + cross-cutting in `loomwright/hooks/hooks.json` (Code Reviewer, QA Executor, TaskCompleted)
5. Docs: `loomwright/docs/RESULT_SCHEMAS.md`, `…/FAILURE_ESCALATION.md`, `…/ARCHITECTURE_CONTRACTS.md`, `…/ARCHITECTURE.md`
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
- Review agent prompts in loomwright/agents/

**Skills / agents / hooks not showing after plugin update?**

Claude Code caches plugin contents. After pulling new changes (e.g. a fresh `git pull` on main), force a full refresh:

1. **Minimal flow** — try this first:
   ```
   /plugin uninstall loomwright
   /plugin install loomwright@atelier
   /reload-plugins
   ```
2. **Full reset** — if the minimal flow doesn't pick up your changes, drop the marketplace cache too:
   ```
   /plugin uninstall loomwright
   /plugin marketplace remove atelier
   /plugin marketplace add ./
   /plugin install loomwright@atelier
   /reload-plugins
   ```
   Run from the repo root so `./` resolves to your local checkout.
3. Verify with `/skills` — should show all 41 skills under "Plugin skills". Use `/agent-help` to confirm all 21 slash commands are registered.

**Previously installed via `claude --plugin-dir` (flat layout)?** Older install instructions told you to launch Claude with `--plugin-dir` pointing at the repo root. That no longer works — the plugin is now nested under `loomwright/`. Switch to the marketplace flow shown in **Quick Start → 1. Install the Plugin**.

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