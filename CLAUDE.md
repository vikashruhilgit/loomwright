# CLAUDE.md

Guidance for Claude Code when working in this repository.

- User-facing docs (install, quick start, commands, troubleshooting): `README.md`
- Development standards & shared agent contract: `AGENT_GUIDELINES.md`
- This file captures what's *not* obvious from those — invariants, schemas, hooks, and incident-derived gotchas

---

## Project Overview

**AI Agent Manager** is a Claude Code plugin with 14 agent roles (9 user-facing + 5 internal) for plan-first readiness, parallel execution, requirements, planning, code review, commits, adversarial audits, standalone PR review-and-heal, and dual-agent QA. Supervisor and Launch Pad use `.supervisor/` exclusively for state; Orchestrator and Product Owner can optionally use Beads.

**v14.20.0 — System Twin M2b part-2a: wire the fitness instruments + self-test suite into CI (advisory report + hard gates):** Makes Pillar 2's "provable-done" instruments **continuous in CI** — additive, advisory-first, no counted artifacts. **(1) Full self-test suite as a HARD gate:** `.github/workflows/ci.yml` now runs **all** `ai-agent-manager-plugin/scripts/test-*.sh` via a loop (echoing `== <test> ==`, fail-fast on first non-zero) instead of just `test-run-eval.sh`, so all 14 deterministic self-tests gate every push/PR to `main` and future `test-*.sh` are auto-included (anti-drift); the three existing version/doc gates (`validate-version.sh`, `check-command-sync.sh`, `check-doc-currency.sh`) still hard-gate. **(2) Advisory fitness report (NON-gating):** a new uncounted helper `scripts/ci-fitness-report.sh` runs the three fitness runners (`run-eval.sh`, `run-ground-truth.sh --check 'corpus-task: version-consistent'`, `run-benchmark.sh`), tolerantly parses each one-line JSON result with `jq`, and writes a markdown summary (eval `pass_rate`+`status`, ground-truth `status`+`checks_passed/total`, benchmark `metric`+`value`+`status`) to `$GITHUB_STEP_SUMMARY`. The step is wrapped (`continue-on-error: true` + `|| true` atop the runners' always-exit-0 contract + tolerant `jq` parsing) so a low/`unverified`/`skipped` fitness result can NEVER red the build — only the self-tests + version/doc gates can. **(3) Fitness-history artifact:** `.supervisor/eval/results.jsonl` is uploaded best-effort (`if-no-files-found: ignore`). **(4) Docs:** the eval-corpus `README.md` and `SYSTEM_TWIN_ROADMAP.md` now record part-2a shipped (advisory CI fitness instruments + self-test hard gate) with **part-2b** (headless `claude` generation / the full agent loop in CI — needs `ANTHROPIC_API_KEY`, a token budget, a circuit-breaker) and **M3** (advisory→gating flip) still deferred. `claude-code-review.yml` / `claude.yml` untouched; **NO new secrets**. **No new agent / command / hook / skill (still 14 / 16 / 51 / 19); 1 new uncounted helper script.** Additive on top of v14.19.0.

**v14.19.0 — System Twin M2b slice 1a: an advisory ground-truth execution step in Supervisor Phase 4.5:** Lands the **ground-truth execution muscle** slice of M2b (Pillar 2 "provable-done") — **advisory, additive, no counted artifacts.** **(1) `scripts/run-ground-truth.sh`** — a deterministic, fail-safe, always-exit-0 runner that resolves a project's declared **executable acceptance** checks (from a brief's `## Executable Acceptance` section / `.supervisor/twin/ground-truth.json`) and runs each — `cmd:` (arbitrary shell check) and `corpus-task:` (an eval-corpus task) kinds; `qa-executor:` is recognized but **DEFERRED to slice 1b** — emitting exactly one machine-readable `GROUND_TRUTH_JSON` line (jq-built); missing declaration or absent `jq` → `status:"unverified"`, always exits 0. **(2) `scripts/test-run-ground-truth.sh`** self-test (14 assertions). A `--no-cmd` / `GROUND_TRUTH_NO_CMD=1` safety valve skips `cmd:`/bare checks (recorded `cmd_disabled`; `corpus-task:` still runs); Supervisor Phase 4.5 passes it on the unattended `--non-interactive`/`/autonomous` path so machine-authored `cmd:` bullets never run arbitrary shell unattended (interim guard until the slice-1b Plan Reviewer control). **(3) Supervisor Phase 4.5** invokes it **after** the Code Reviewer loop and folds the result into a new additive `ground_truth` SUPERVISOR_RESULT object + flat `session_end` JSONL fields — **advisory only: it NEVER changes `heal_decision`, NEVER triggers a fix, NEVER blocks the PR** (mirrors the contract-conformance / benchmark precedent). **(4) New `GROUND_TRUTH_JSON` schema** (`schema_version 1`) + the `## Executable Acceptance` brief convention in `docs/RESULT_SCHEMAS.md`; SUPERVISOR_RESULT stays `schema_version 1`. The ground-truth runner is **distinct from** the eval harness (`run-eval.sh` / `EVAL_RESULT`) and the canary benchmark (`run-benchmark.sh` / `BENCHMARK_JSON`). **M2b slice 1b** (auto-dispatch QA Executor for web-app repos) and **M2b part-2** (the CI agent loop) remain deferred. **No new agent/command/hook/skill (still 14 / 16 / 51 / 19); new scripts uncounted; additive (SUPERVISOR_RESULT stays schema_version 1).** Additive on top of v14.18.0.

> 📜 **Full release history** (v14.15.0 → v14.0.0 and earlier) lives in [`CHANGELOG.md`](CHANGELOG.md). CLAUDE.md keeps only the two most recent release notes.

---

## Plugin Layout

The repo is a **marketplace wrapper** containing one nested plugin:

- Marketplace manifest: `.claude-plugin/marketplace.json` (root)
- Plugin manifest: `ai-agent-manager-plugin/.claude-plugin/plugin.json` (v14.20.0)
- Agents: `ai-agent-manager-plugin/agents/` (14 markdown prompts)
- Commands: `ai-agent-manager-plugin/commands/` (16 entry points)
- Skills: `ai-agent-manager-plugin/skills/` (51 skills, see `SKILLS_INDEX.md`)
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
│   ├── commands/                              # 16 slash commands
│   ├── hooks/hooks.json                       # cross-cutting hooks
│   ├── skills/                                # 51 skills + SKILLS_INDEX.md
│   ├── scripts/                               # runtime helpers: telemetry, webhook, notify, resume, memory, lessons, insights (+ self-tests, fixtures)
│   └── docs/                                  # RESULT_SCHEMAS, FAILURE_ESCALATION, ARCHITECTURE_CONTRACTS, ARCHITECTURE, QA_SYSTEM_BLUEPRINT, TELEMETRY
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
| Launch Pad | user-facing | user | Phase 2.5 feasibility (GO/CAUTION/NO-GO); Phase 5.5 mandatory Plan Review (max 3 retries); writes briefs to `.supervisor/jobs/pending/` |
| Supervisor | user-facing | user | v4 + **Phase 1.5 PRE-FLIGHT SYNC** (remote-state reconciliation between ACQUIRE and PLAN — classifies the requested work CLEAR/OVERLAP/SUPERSEDED, silent on CLEAR, soft-gate `AskUserQuestion` interactively, fails closed under `--non-interactive` with `error: "preflight_overlap_detected"`; bounded ≤6 calls; `--skip-preflight-sync` escape hatch) + Phase 4.5 self-heal — self-heal phase **always** runs; `--skip-self-heal` only short-circuits the loop; completion-tail relocates job-move + state-completed from FINALIZE. **Never assert git merge/PR state ("on main", "in the PR", "already merged") without verifying via `git log` / `git branch --contains`.** |
| Product Owner | user-facing | user | Assumption Check (standard) + Reality Check (`--brainstorm`) cap Feasibility for NEEDS_FOUNDATION/BLOCKED ideas |
| Orchestrator | user-facing | user | Reads CLAUDE.md + Beads → EPIC / TASK / SUBTASK with skill references |
| Code Reviewer | user-facing | user | LSP, read-only mode, schema_v3 (adds `drift` category, severity caps via hook). **Auto-expands to consistency audit** when diff touches `agents/`, `commands/`, `skills/`, `docs/`, or plugin metadata |
| Red Team Reviewer | user-facing | user | 6 attack vectors; persistent memory of past audits |
| QA Strategist | user-facing | user | Strategy mode + Audit mode; spawned twice (gate audit Phase 11, results audit Phase 13) |
| QA Executor | user-facing | user | 13-phase, `--depth smoke|functional`, `--plan/--scope/--continue`, infrastructure-aware (Mailpit/MailHog), 80/90 budget |
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

**Doc currency is CI-enforced:** `scripts/check-doc-currency.sh` (a CI gate alongside `validate-version.sh`) mechanically verifies that version/count claims across the doc surfaces — agent/command/skill/hook counts, `plugin.json (vX.Y.Z)` annotations, and the `AI agents vX.Y.Z` headline — match the authoritative source (`plugin.json`, `hooks.json`, the `agents/`/`commands/`/`skills/` dirs). When you add/remove an agent, command, skill, or hook, or bump the version, **update the doc claims in the same change or CI fails.** It scans only high-confidence current-claim phrasings (never bare numbers), so dated changelog entries don't false-positive. The authoritative, always-current hook table lives in this file (§"Plugin Hooks (Quality Gates)").

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
| SessionStart — v14.2.0 | Session resume / clear / compact | hooks.json | type:command — `session-resume.sh`; injects bounded (≤10k) recovery context; silent on startup; exits 0 |

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
- Schemas / contracts / failure modes: `ai-agent-manager-plugin/docs/{RESULT_SCHEMAS,ARCHITECTURE_CONTRACTS,FAILURE_ESCALATION,ARCHITECTURE,QA_SYSTEM_BLUEPRINT,TELEMETRY}.md`
- Skills index: `ai-agent-manager-plugin/skills/SKILLS_INDEX.md`
