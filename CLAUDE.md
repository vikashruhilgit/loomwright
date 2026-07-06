# CLAUDE.md

Guidance for Claude Code when working in this repository.

- User-facing docs (install, quick start, commands, troubleshooting): `README.md`
- Development standards & shared agent contract: `AGENT_GUIDELINES.md`
- This file captures what's *not* obvious from those — invariants, schemas, hooks, and incident-derived gotchas

---

## Project Overview

**Loomwright** is a Claude Code plugin with 14 agent roles (9 user-facing + 5 internal) for plan-first readiness, parallel execution, requirements, planning, code review, commits, adversarial audits, standalone PR review-and-heal, and dual-agent QA. Supervisor and Launch Pad use `.supervisor/` exclusively for state; Orchestrator and Product Owner can optionally use Beads.

**v15.2.3 — SKILLS_INDEX version-cell CI parity gate + IMPROVEMENTS_ROADMAP de-staling (doc-hygiene, additive):** New repo-root validator `scripts/check-skills-index-sync.sh` (bash-3.2-safe, no network) closes the documented doc-currency blind spot for per-row skill `version:` cells: for every `loomwright/skills/*/SKILL.md` with a `version:` frontmatter field it asserts `SKILLS_INDEX.md` has exactly ONE row — keyed on the backticked dir-path cell, never the display name — whose version cell matches, and that no index row references a nonexistent skill dir (structural frontmatter-vs-table parse; never scans changelog prose). Wired into `ci.yml` as a hard gate next to the other 4 validators, with a synthetic-fixture `--self-test` (aligned / wrong-version / malformed-cell / ghost-row / missing-row / duplicate-row) run in CI before the live gate; the one live drifted row (supervisor-readiness 1.1.1 → 1.1.2) is fixed — index follows skill, never the reverse. `loomwright/docs/IMPROVEMENTS_ROADMAP.md` is de-staled: a dated planning-snapshot banner (current-state authority: CLAUDE.md + hooks.json + plugin.json) plus 18 inline re-verified `**[VERDICT: …]**` lines — **10 RESOLVED / 7 DEFERRED / 1 OPEN** (only the `WorktreeRemove`-hook half of item 6 remains open; re-verification flipped items 4, 13, 15 to RESOLVED vs the 2026-07-05 review's hypothesis). Both Quick Starts gain a one-line `/setup` pointer. A repo-root script is uncounted — **Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks; no `schema_version` bump.** Additive on top of v15.2.2.

**v15.2.2 — direct deterministic self-test for `send-telemetry-core.sh` (tests-only, additive):** New `loomwright/scripts/test-send-telemetry-core.sh` (auto-registered by CI's `test-*.sh` glob) unit-tests the telemetry core's privacy/consent/dedup pipeline directly — the one component whose regression could leak user data to a public GitHub issue. 7-group matrix, 83 assertions: privacy true-positives (one payload per `PRIVACY_PATTERNS` label ×9, each pinned to real exit 2 + the exact `PRIVACY_BLOCKED pattern=<label>` stderr line); true-negative near-misses; the v11.2.0 privacy-before-consent/interest ordering guarantee (secret + healthy score ⇒ 2 never 5, with a clean-twin counterfactual proving the same shape IS interest-skipped); the full consent matrix incl. malformed-JSON **fail-closed** (exit 3, `state=parse_error` — verified, no bug found) and env-var repo precedence; nullable/missing-key discipline for both consent fields (missing key AND explicit null both fail closed, PR #84 lesson); dedup determinism (seeded `telemetry-sent.log`, same `task_id::bucket::primary_error` sha256 within 6h ⇒ 5; different-error and stale->6h entries not deduped); and redaction `[REDACTED:<label>]` markers ×9 exercised via the **extracted production STAGE1_PY source** (a secret-bearing payload exits 2 before its body prints, so the harness `exec()`s the real stage-1 code, never a copy). `gh` proven never-invoked via a fail-loud PATH shim + dry-run `WOULD_EXIT` assertions; all state in a mktemp sandbox (core paths are `$PWD`-based), real `.supervisor/` snapshot-asserted untouched; bash-3.2-safe. Zero behavior change to the core; the email-regex over-match stays an accepted, documented trade-off. **Counts UNCHANGED: 14 agents / 21 commands / 57 skills / 21 hooks; no `schema_version` bump.** Additive on top of v15.2.1.

> 📜 **Full release history** (v15.2.1 → v14.0.0 and earlier) lives in [`CHANGELOG.md`](CHANGELOG.md). CLAUDE.md keeps only the two most recent release notes.

---

## Plugin Layout

The repo is a **marketplace wrapper** containing one nested plugin:

- Marketplace manifest: `.claude-plugin/marketplace.json` (root)
- Plugin manifest: `loomwright/.claude-plugin/plugin.json` (v15.2.3)
- Agents: `loomwright/agents/` (14 markdown prompts)
- Commands: `loomwright/commands/` (21 entry points)
- Skills: `loomwright/skills/` (57 skills, see `SKILLS_INDEX.md`)
- Hooks: `loomwright/hooks/hooks.json`
- Docs: `loomwright/docs/`
- Bundled MCP: read-only MySQL server (`vikashruhil-mysql-mcp`)

> **Repo path vs. runtime path:** `loomwright/...` is the developer-side path (this repo on disk). Anything invoked by hooks, skills, or agents at *runtime* must reference `${CLAUDE_PLUGIN_ROOT}/...` — that's the canonical Claude Code variable that resolves to the plugin install dir on both dev checkouts and marketplace installs. Never use `loomwright/...` paths from the user-project root; they only resolve for the plugin maintainer.

### Directory Structure

```
loomwright/                              # marketplace wrapper
├── .claude-plugin/
│   ├── marketplace.json                       # marketplace manifest (root)
│   └── README.md                              # plugin-facing usage guide
├── loomwright/                   # nested plugin
│   ├── .claude-plugin/plugin.json
│   ├── .mcp.json                              # bundled MCP servers
│   ├── agents/                                # 14 markdown prompts
│   ├── commands/                              # 21 slash commands
│   ├── hooks/hooks.json                       # cross-cutting hooks
│   ├── skills/                                # 57 skills + SKILLS_INDEX.md
│   ├── scripts/                               # runtime helpers: telemetry, webhook, notify, resume, memory, lessons, insights, handoff digest (build-handoff), findings→community bridge (build-bridge / read-bridge), otel stack assets (+ self-tests, fixtures)
│   └── docs/                                  # RESULT_SCHEMAS, FAILURE_ESCALATION, ARCHITECTURE_CONTRACTS, ARCHITECTURE, QA_SYSTEM_BLUEPRINT, TELEMETRY, OBSERVABILITY
│       └── SPIKES/                            # Capability spike investigations + deferral records
├── scripts/                                   # validate-version.sh, check-command-sync.sh
├── README.md                                  # user-facing docs
├── AGENT_GUIDELINES.md                        # standards, agent contract
└── CLAUDE.md                                  # this file
```

---

## The 14 Agent Roles

Detailed per-agent purpose, command syntax, and workflow diagrams live in `README.md` §"The 14 Agents" and the agent prompts (`loomwright/agents/*.md`). Quick map of what matters for in-codebase work:

| Agent | Type | Spawned by | Codebase-relevant invariants |
|---|---|---|---|
| Launch Pad | user-facing | user | Phase 2.5 feasibility (GO/CAUTION/NO-GO); Phase 5.5 mandatory Plan Review (max 3 spawns per session); writes briefs to `.supervisor/jobs/pending/`. **Requirement-file input:** Phase 2 step 0 — when the `goal:`/`feature:`/`problem:` value is a path **under `.supervisor/requirements/`** to an existing `.md` (resolves via `test -f` against the project root, the Beads-absent Product Owner story target), Launch Pad reads it as the requirement source; any other value (including a bare repo file like `README.md`) stays a literal-string goal. Closes the PO→Launch Pad handoff gap in Beads-optional mode. Also stamps `source_requirement` provenance (`- **Source requirement:** {path}` under the brief `## Environment`) for requirement-file inputs |
| Supervisor | user-facing | user | v4 + **Phase 1.5 PRE-FLIGHT SYNC** (remote-state reconciliation between ACQUIRE and PLAN — classifies the requested work CLEAR/OVERLAP/SUPERSEDED, silent on CLEAR, soft-gate `AskUserQuestion` interactively, fails closed under `--non-interactive` with `error: "preflight_overlap_detected"`; bounded ≤6 calls; `--skip-preflight-sync` escape hatch) + Phase 4.5 self-heal — self-heal phase **always** runs; `--skip-self-heal` only short-circuits the loop; completion-tail relocates job-move + state-completed from FINALIZE; completion-tail also stamps an idempotent `## Status: done` close-out on the originating requirement file in **Beads-absent** mode (success-only, fail-safe). **Phase 4.5 also offers an opt-in, default-OFF, NON-gating advisory red-team lens** (`--red-team` / `--no-red-team`, `.red_team_high_risk` config) that runs only on high-risk integrated diffs and records findings in `SUPERVISOR_RESULT.summary` + the job Outcome block — never blocks the PR or changes the `heal_decision`. **Never assert git merge/PR state ("on main", "in the PR", "already merged") without verifying via `git log` / `git branch --contains`.** |
| Product Owner | user-facing | user | Assumption Check (standard) + Reality Check (`--brainstorm`) cap Feasibility for NEEDS_FOUNDATION/BLOCKED ideas. **Beads-optional** (see Orchestrator row): when `beads_active` is false, stories persist as `.supervisor/requirements/*.md` and handoff is by file path, not `BD-XX` |
| Orchestrator | user-facing | user | Reads CLAUDE.md (+ Beads when active) → EPIC / TASK / SUBTASK with skill references. **Beads-optional:** a `## Persistence Mode` block branches on `beads_active` (probe `test -d .beads && bd --version`); when absent, skips all `bd` and writes the task tree to `.supervisor/requirements/{slug}-plan.md` — review gates stay mandatory in both modes. Detection logic already lived in the shared `context-setup` skill; this wires output to it (matching Code Reviewer's long-standing Beads-optional pattern) |
| Code Reviewer | user-facing | user | LSP, read-only mode, schema_v3 (adds `drift` category, severity caps via hook). **Auto-expands to consistency audit** when diff touches `agents/`, `commands/`, `skills/`, `docs/`, or plugin metadata |
| Red Team Reviewer | user-facing | user | 6 attack vectors; persistent memory of past audits |
| QA Strategist | user-facing | user | Three modes (Strategy / Gate Audit / Post-Execution Audit); spawned twice (gate audit Phase 11, results audit Phase 13) |
| QA Executor | user-facing | user | Multi-phase Level 1 protocol (phases 1–13, non-monotonic order), `--depth smoke|functional`, `--plan/--scope/--continue`, infrastructure-aware (Mailpit/MailHog), 80/110/60 budget (default/scoped/plan) with 60/80/92% zones |
| Review-PR (`review-pr-runner`) | user-facing | user / Supervisor completion-tail / autonomous EVALUATE | `/review-pr <pr-url>` standalone review→fix→re-review loop against an existing PR; resolves PR-URL → head branch, spawns `code-reviewer` + `general-purpose` fix worker; **never auto-merges**; emits `REVIEW_HEAL_RESULT`. NEVER Task-spawned (subagents-cannot-spawn-subagents) — run inline via `/review-pr` or as `claude --agent …:review-pr-runner`. Authority is the `review-heal` skill. |
| Execute Manager | internal | Supervisor (Phase 3) | Owns poll loop in isolated context, 60 tool-call budget |
| Context-Keeper | internal | Supervisor / Execute Manager | **Sole writer** of state file on the parallel path (the inline main-thread Supervisor may do an equivalent best-effort direct write of the `## Session` block); haiku model, batch updates, atomic writes |
| Worker | internal | Execute Manager / Supervisor | One subtask per worktree, no git ops, emits WORKER_RESULT + `.worker-summary.md` |
| Plan Reviewer | internal | Launch Pad | PLAN_REVIEW_RESULT decision gates the brief save — PASS saves; NEEDS_HUMAN saves only on explicit user override; FAIL never saves |
| Rubric Grader | internal | Supervisor (Phase 4.5, only when brief has `## Outcomes Rubric` and `heal_decision == PASS`) | Read-only Haiku scorer; runtime read-only enforcement comes from `disallowedTools: Write, Edit, Task, NotebookEdit` (the frontmatter-level enforcement that survives plugin distribution — `permissionMode: plan` is preserved for `~/.claude/agents/` compatibility but is silently ignored by Claude Code for plugin agents); emits per-item `ITEM N: PASS\|FAIL` lines + `rubric_score: N/M`; advisory only — never changes `heal_decision` or blocks the PR |

### `/autonomous` orchestration shell (v14.0.0)

`/autonomous` is **not a new agent.** It is an inline main-thread slash command (`loomwright/commands/autonomous.md`) governed by `loomwright/skills/autonomous-loop/SKILL.md`. The same execution model as `/launch-pad` and `/supervisor`: the slash command body is workflow instructions executed inline on the main thread. The main thread reads `commands/launch-pad.md` and `commands/supervisor.md` at Step 0 (to avoid prompt drift), then runs Launch Pad inline (which still Task-spawns `plan-reviewer`), then runs Supervisor inline (which still Task-spawns `orchestrator` / `execute-manager` / `code-reviewer` / `rubric-grader`).

**Default mode is now multi-iteration** (cap 10, default `--max-iterations 3`) with **stacked PRs**: iteration N+1 branches from `iterations[N].branch` so the chain is reviewable bottom-up. Reviewers MUST merge the bottom of the stack first; out-of-order merges leave higher iterations rebased against the wrong base. `--no-stacked-branches` opts out and restores v13's branch-from-integration-base cadence. `--max-iterations 1` reproduces v13's single-iteration default. `--notify` opts in to gate-event webhooks (rubric / adjudication / NO-GO / Plan Review FAIL × 3) — payloads built with **jq only** for injection safety, fire-and-forget POST, gated on `LOOMWRIGHT_WEBHOOK_URL`. `--non-interactive-fallback` enables a per-gate fail-closed policy for CI / stdin-not-tty: rubric gate aborts (`rubric_gate_closed_non_interactive`); no-rubric `completed` returns `done` with `no_rubric_in_non_interactive`; adjudication gate inherits Supervisor's `--non-interactive` policy if forwarded.

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

1. **New agent:** `.md` in `loomwright/agents/` with YAML frontmatter; output follows Context Read → Plan → Work → Results → Risks
2. **New slash command:** `.md` in `loomwright/commands/` referencing the agent prompt
3. **New skill:** `SKILL.md` in `loomwright/skills/[name]/` with version frontmatter; update `SKILLS_INDEX.md`
4. **Test locally:**
   ```
   /plugin uninstall loomwright
   /plugin install loomwright@atelier
   ```
   Verify with `/agent-help`
5. **Cite exact `file:line` numbers when referencing code**

**Doc currency is CI-enforced:** `scripts/check-doc-currency.sh` (a CI gate alongside `validate-version.sh`) mechanically verifies that version/count claims across the doc surfaces — agent/command/skill/hook counts, `plugin.json (vX.Y.Z)` annotations, and the `Loomwright vX.Y.Z` headline — match the authoritative source (`plugin.json`, `hooks.json`, the `agents/`/`commands/`/`skills/` dirs). When you add/remove an agent, command, skill, or hook, or bump the version, **update the doc claims in the same change or CI fails.** It scans only high-confidence current-claim phrasings (never bare numbers), so dated changelog entries don't false-positive. The authoritative, always-current hook table lives in this file (§"Plugin Hooks (Quality Gates)"). **Surfaces the gate does NOT scan (recurring drift, integration-review-only):** Supervisor phase enumerations (agent-help.md, command docs), per-run YAML frontmatter field lists in `build-insights.sh`, budget/zone numbers, and `/insights` dashboard section enumerations. (Per-row skill `version:` cells in `SKILLS_INDEX.md` were on this list until v15.2.3 — they are now mechanically enforced by `scripts/check-skills-index-sync.sh`.) On any phase/version/budget/section change, grep the OLD value repo-wide — a green doc-currency run is necessary but not sufficient. **Conversely, do NOT "fix" illustrative example values to the current version:** sample `session_end` / `POSTMORTEM_RESULT` JSONL records and `e.g. "X.Y.Z"` `plugin_version` placeholders (in `docs/RESULT_SCHEMAS.md`, `agents/supervisor.md`, and similar) illustrate *format* only — the real value is read at runtime from `plugin.json` via jq, so they are NOT current-claims, carry no currency requirement, and are deliberately unscanned. Bumping them every release is a drift-treadmill the gate cannot enforce (they re-stale at the next version), so leave them **frozen and version-agnostic** — a stale-looking version inside an example block is intended, not drift, and should not be re-flagged in review. (v14.25.1 codified this after a review round chased the placeholders.)

**Plugin `description` is a summary, not a changelog (anti-rebloat):** the `description` field in `plugin.json` and `.claude-plugin/marketplace.json` is the crisp card shown in the plugin-manager UI. On a version bump, update the `vX.Y.Z` string and the four counts **in place** and keep it short; put the per-release narrative in `CHANGELOG.md` (and, if notable, a single CLAUDE.md banner) — **never append another version clause to the description.**

**Hook gotcha:** Claude Code silently ignores `hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter — only `hooks.json` hooks fire for plugin-distributed agents. Per-agent frontmatter hooks are kept for `~/.claude/agents/` compatibility.

---

## Structured Contracts (v9.0.0)

- **Result Schemas** — `loomwright/docs/RESULT_SCHEMAS.md`. CODE_REVIEW_RESULT at `schema_version: 3` (adds `review_mode` (`diff_review` | `consistency_audit`), `audit_focus[]`, `trigger_paths_detected[]`, `scope_expanded[]`, `files_checked[]`, `consistency_checks`, `consistency_summary`, and the `drift` issue category with `drift_kind` + severity caps; v2 accepted for legacy artifacts). WORKER_RESULT at `schema_version: 2` (adds `outputs_verified[]` + `outputs_gap`; v1 accepted for the v12.0.0 transition window). AUTONOMOUS_RUN at `schema_version: 2` (v14 — adds nine new closed `status_reason` values for stacked-branch / non-interactive-fallback / webhook-notify failure modes; v1 accepted for the v13 transition window). SUPERVISOR_RESULT remains at `schema_version: 1` with two new optional additive fields in v14 (`branch_base`, `pr_state`). All others at `schema_version: 1`.
- **Failure Escalation** — `…/FAILURE_ESCALATION.md` (retry limits, escalation paths)
- **Architecture Contracts** — `…/ARCHITECTURE_CONTRACTS.md` (capability matrix, context budgets, timeouts, worktree naming)
- **Job Lifecycle** — briefs flow `pending/` → `in-progress/` → `done/` / `failed/` in `.supervisor/jobs/`
- **Session Logging** — JSONL in `.supervisor/logs/{session_id}.jsonl`
- **Merge Safety Gate** — pre-merge checklist in FINALIZE prevents corrupted partial merges

---

## Plugin Hooks (Quality Gates)

21 hooks centralized in `hooks.json` (the v12.2.0 webhook hook brought the count 13 → 14; v13.0.0 / v14.0.0 added none — v14's `--notify` gate-event webhooks are emitted inline by the autonomous-loop, not by a hook; **v14.1.0 added 2 events / 3 entries** — `PreToolUse[AskUserQuestion]` (notify-desktop + send-webhook) and `Notification` (notify-desktop) — bringing the count 14 → 17; **v14.2.0 added 2 entries** — a `SessionStart` → `session-resume.sh` and a `launch-pad-runner` SubagentStop → `validate-launch-pad-result.py` — bringing the count 17 → 19; **v14.34.0 added 1 entry** — a `PostToolUse[Bash]` → `hook-dispatch-on-pr-create.sh` backstop — bringing the count 19 → 20; **v14.47.0 added 1 entry** — a `SessionStart` → `set-otel-resource-attrs.sh` per-project OTel labeler — bringing the count 20 → 21). Prompt-based validation uses fast haiku model with 30s timeout. WorktreeCreate / StopFailure / telemetry / webhook / notification / resume / launch-pad-result hooks use `type: command` for zero-latency.

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
| SubagentStop webhook (supervisor-runner) | Supervisor completes | hooks.json | type:command — `send-webhook.sh`; gated on `LOOMWRIGHT_WEBHOOK_URL`; fire-and-forget POST; always exits 0 |
| PreToolUse (AskUserQuestion) — v14.1.0 | Plugin about to block on a user question | hooks.json | type:command — `notify-desktop.sh` (OS banner) + `send-webhook.sh` (paused-event POST); scope-gated; always exits 0 |
| Notification — v14.1.0 | Claude Code signals attention (permission_prompt / idle_prompt / elicitation_*) | hooks.json | type:command — `notify-desktop.sh` (OS banner); matched to exclude `auth_success`; always exits 0 |
| SubagentStop (launch-pad-runner) — v14.2.0 | Launch Pad `-runner` completes | hooks.json | type:command — `validate-launch-pad-result.py`; validates LAUNCH_PAD_RESULT (schema_version, status, saved_brief_path, summary); exits 0 |
| SessionStart — v14.2.0 | Session resume / clear / compact | hooks.json | type:command — `session-resume.sh`; injects bounded (≤10k) recovery context; silent on startup; since v14.24.0 also runs the observability health probe (env-block-gated 1s curl, 24h debounce, never starts Docker — adds no new hook entry); exits 0 |
| PostToolUse (Bash) — v14.34.0 | A Bash tool call completes (e.g. `gh pr create`) | hooks.json | type:command — `hook-dispatch-on-pr-create.sh`; backstops the until-mergeable review drain on PR creation. Session-scope gated (in-progress job + a coherent active-session source: non-terminal branch-matching state.md OR a unique active autonomous state.json; stale terminal state.md no longer short-circuits); fail-safe, always exits 0 |
| SessionStart — v14.47.0 | Session start (ANY source — startup / resume / clear / compact; unlike `session-resume.sh`, which skips `startup`) | hooks.json | type:command — `set-otel-resource-attrs.sh`; telemetry-gated, auto-maintains per-project `OTEL_RESOURCE_ATTRIBUTES` (`service.name=<repo>`, `service.version=<plugin version>`) in `<project>/.claude/settings.local.json`; no-ops when telemetry off; fail-safe, always exits 0 |

---

## Telemetry System (opt-in, v11.2.0 — preserved in v14.0.0)

After qualifying runs (`supervisor-runner`, `code-reviewer`, `qa-executor`), a SubagentStop `type: command` hook invokes `${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry.sh` (the wrapper — `${CLAUDE_PLUGIN_ROOT}` is the canonical Claude Code variable for plugin-bundled assets and resolves to the plugin install dir on both dev checkouts and marketplace installs; never use `loomwright/...` paths from the user-project root, those only resolve for the plugin maintainer). The wrapper is fire-and-forget and **always exits 0**; it pipes the hook payload to `send-telemetry-core.sh`, which parses the result block, derives a deterministic score, runs a regex-based privacy whitelist, and (when consent + target repo are configured) calls `gh issue create` with a structured body covering Task Summary, Agent Scores, Issues Detected, AI Suggestions, Tools Used, and a redacted JSON payload.

- **Privacy fail-closed:** any whitelist match aborts the post; core exits `2`
- **Core exit codes 0..5:** sent / generic_error / privacy_blocked / no_consent / no_repo_configured / filter_skipped
- **No origin-remote fallback** — the plugin runs in arbitrary user projects whose origin is the user's app repo, which is the wrong place for telemetry
- **Disabled by default.** Enable via `/telemetry enable` (interactive — pick target repo) or `LOOMWRIGHT_TELEMETRY_REPO=owner/repo`. Hooks **never** prompt — consent flows only through `/telemetry`.

| Command | Purpose |
|---------|---------|
| `/telemetry status` | consent state, resolved target repo + source, last-sent timestamp, retained per-session pending markers (~24h window) |
| `/telemetry enable` | interactive — collects target repo via `AskUserQuestion`, writes `{"telemetry":"always_allow","telemetry_repo":"<owner/repo>"}` to `.supervisor/telemetry-consent.json`. Sole first-run consent path. |
| `/telemetry disable` | writes `{"telemetry":"no"}` to the consent file; subsequent hook fires log a single "denied — skipped" line per session and never call `gh` |
| `/telemetry test` | dry-run a fixture or the latest log payload through `send-telemetry-core.sh --dry-run`; prints target repo, formatted body, and `WOULD_EXIT` without calling `gh` |

Full design (scoring rubric per result-block schema, privacy whitelist, exit-code table, wrapper-vs-core architecture, plugin-internal vs repo-root `scripts/` convention): `loomwright/docs/TELEMETRY.md`.

---

## Persistent Memory

Agents with `memory: project` in frontmatter accumulate knowledge across sessions:

| Agent | Storage |
|-------|---------|
| Launch Pad | `.claude/agent-memory/loomwright:launch-pad-runner/` |
| Code Reviewer | `.claude/agent-memory/loomwright:code-reviewer/` |
| Red Team Reviewer | `.claude/agent-memory/loomwright:red-team-reviewer/` |
| Product Owner | `.claude/agent-memory/loomwright:product-owner/` |
| QA Strategist | `.claude/agent-memory/loomwright:qa-strategist/` |
| QA Executor | `.claude/agent-memory/loomwright:qa-executor/` |

> Decision aid for *what* to write to those memory directories: `loomwright/skills/memory-tool/SKILL.md` (reference skill — not pre-loaded; consult on demand when tagging conventions or Memory-Tool-vs-file-based questions arise).

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

Native Claude Code multi-agent coordination — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Best for research, competing hypotheses, cross-layer changes; not for sequential tasks or same-file edits (use Supervisor with worktrees). Patterns + decision matrix: `loomwright/skills/agent-teams/SKILL.md`. Complementary to Supervisor v4, not a replacement.

---

## Cost Profile

`/supervisor --cheap` — opt-in flag that overrides execution-shaped roles (orchestrator, execute-manager, worker, code-reviewer, Phase 4.5 fix tasks) to Sonnet at spawn time. Default behavior (`inherit` for all) unchanged. Profile table, semantics, and Haiku-session caveat: `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles".

---

## Failure-Mode Invariants

**Bimodal failure philosophy (invariant — do not break):** correctness gates fail **CLOSED** under `--non-interactive` / CI / stdin-not-tty (`preflight_overlap_detected`, `non_interactive_without_fallback`, `rubric_gate_closed_non_interactive`); runtime side-effect emitters (telemetry wrapper, `send-webhook.sh`, the session-resume observability probe) fail **SAFE** and ALWAYS `exit 0`. Inverting either — a gate that silently proceeds without an explicit `--skip-*`, or an emitter that exits non-zero on a normal failure path — is a security regression, not a bug fix. Corollary for advisory signals: `contract_conformance_status: skipped` means UNVERIFIED, not clean (it only runs when a brief authored an `## Executable Acceptance` ground-truth surface), and a green `heal_decision: PASS` does NOT mean the PR is reviewer-clean.

**`gh pr merge --squash` has exactly ONE sanctioned executor (invariant — do not break):** the **only** place in the plugin that EXECUTES `gh pr merge --squash` is the `automate-loop` `--auto-merge` gate (`skills/automate-loop/SKILL.md` §10, implemented by `scripts/automate-helpers.sh`'s `gate-eval`). It is **opt-in, default-OFF**, and fires only when ALL FIVE trusted-merge conditions hold; any failed / null / unreadable condition fails **CLOSED** (park + notify). `review-heal` (`/review-pr`) and Supervisor Phase 4.5 **NEVER merge** — they review-and-heal only and leave the PR open for a human (`READY`/`PASS`/`ESCALATED` are all terminal-stop, merge-identical). The positive-form invariant check is `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` — it resolves to exactly four surfaces: `skills/automate-loop/SKILL.md`, `scripts/automate-helpers.sh` (the executor), `scripts/test-automate-helpers.sh`, and `commands/agent-help.md` (which describes the sanctioned gate). (`commands/automate.md`'s own two mentions are correctly EXCLUDED by the `no|never|not` filter; review-heal / review-pr / RESULT_SCHEMAS likewise keep only their negative-assertion "never merges" mentions.) See `skills/automate-loop/SKILL.md` §11 for the authoritative enumeration. Adding a second executor anywhere else is a regression.

**`/automate` single-drain ownership (invariant — do not break):** when the `automate-loop` engine runs an item it sets `.supervisor/config.json {"auto_review": false}` **around** the inner `/autonomous` RUN phase (both of Supervisor's default detached until-mergeable dispatch paths — step 5.5 and the `PostToolUse[Bash]` `gh pr create` hook — fire *during* `/autonomous`, so the toggle must wrap RUN, not DRAIN), then owns **exactly ONE** inline `/review-pr --until-mergeable` drain. The toggle is a byte-for-byte backup to a transient `<run_id>.config-backup.json` restored in a finally-style cleanup (overwrite, or **delete if originally absent**; **malformed pre-existing config ⇒ abort**; RECONCILE restores a crash-stranded backup). This prevents a double until-mergeable drain racing the PR branch. Verifiable via `## Current`'s `suppressed_default_dispatch: true` + `owned_drain_started`/`owned_drain_result` and the absence of any detached `dispatch-pr-review.sh` artifact for the PR.

## Common Pitfalls

### Claimed work is "already merged" / "on main" but isn't (stale-branch trap)?
- Never assert git merge/PR state from memory or in-context summary — verify with `git log origin/$BASE_BRANCH` and `git branch --contains <sha>` before claiming work landed.
- This is the **v13.1.0→v14.0.0 stale-branch incident** (work branched from a stale base and re-implemented something already merged) that motivated the Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate (see `loomwright/agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC"). The Supervisor-table row above keeps the quick reference.

### `/supervisor` or `/launch-pad` aborted with "Task/Agent tool unavailable"?
- Pre-11.1.1 name-collision trap: the slash command silently auto-delegated to a same-named registered subagent, which couldn't spawn its own children ([docs](https://code.claude.com/docs/en/sub-agents): *"Subagents cannot spawn other subagents"*).
- Fix in 11.1.1: registered agents are now `loomwright:supervisor-runner` and `loomwright:launch-pad-runner`. The slash commands are inline main-thread workflows; the `-runner` suffix lets `claude --agent loomwright:supervisor-runner` own a session without re-introducing auto-delegation.
- For an agent-owned session: `claude --agent …-runner`. Otherwise stay on the main thread via the slash command.

### `/supervisor` completed but skipped Phase 4.5 (or Phase 3 child agents)?
- **What this is:** inline main-thread execution misread as permission to stop orchestrating. "Don't delegate to `supervisor-runner`" does NOT mean "do everything yourself." Still spawn first-level children via Task — `orchestrator` (Phase 2), `execute-manager` or fast-path worker/reviewer (Phase 3), `code-reviewer` + fix loop (Phase 4.5).
- **Fix in 11.1.2:** Phase 4.5 completion-tail guard (`loomwright/agents/supervisor.md`) refuses a successful `SUPERVISOR_RESULT` when `skip_self_heal_requested=false` AND `phase45_review_invoked=false`. Run self-reports `status: failed`; job stays in `in-progress/`.
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
`git worktree list`; `git worktree remove ../project-BD-XXa`; `git branch -d feature/BD-XXa`. The detached until-mergeable review drain also creates a sibling worktree (`../{project}-review-{pr_hash}`, detached-HEAD at the PR head SHA) owned by `dispatch-pr-review.sh`'s `trap cleanup EXIT` wrapper, which removes it on the wrapper's normal/error exit. A **hard** kill (SIGKILL / power-loss) skips the trap, so that worktree can linger on disk — `git worktree prune` only reclaims an entry once its directory is *already gone*, and the durable per-PR marker blocks the same-PR re-dispatch whose pre-add cleanup would otherwise force-remove it. Remove a stray one manually: `git worktree remove --force ../{project}-review-{pr_hash}` (the leak is cosmetic — the marker preserves idempotency).

### Detached review drain colliding with inline self-heal? (fixed in v14.42.0 — drain is now worktree-isolated)
**Do NOT write `.supervisor/config.json {"auto_review": false}` to suppress the until-mergeable drain for the self-heal race** — that practice is **retired** as of v14.42.0. The detached dispatched drain (`review-pr-runner`, launched by `dispatch-pr-review.sh`) now runs in its OWN sibling git worktree (detached-HEAD at the PR head SHA), so it no longer shares a working tree/index with the inline Phase 4.5 self-heal and cannot sweep its uncommitted edits — the collision the suppress kill-switch existed to dodge is gone. The `auto_review` flag **remains** as a legitimate general opt-out (turn the drain off entirely), but it is no longer the recommended fix for the concurrency hazard, and suppressing it for the race risks the exact silent-drop it used to cause (a suppressed drain with no safe restore = no dispatch; cf. PR #74). A markerless heal-outcome PR now surfaces in `/insights` under `## Missing-drain reconciliation` as the signal to investigate.

### `/autonomous` brief-save detection (fixed in v14.2.0 — `ls`-diff is now fallback-only)
**Fixed in v14.2.0.** The PLAN phase now reads `LAUNCH_PAD_RESULT.saved_brief_path` (emitted by Launch Pad Phase 7, validated by `scripts/validate-launch-pad-result.py`) as the **primary** brief-save signal — each Launch Pad invocation emits exactly one result block and the loop consults only the block from its own inlined call, so a concurrent `/launch-pad` can no longer be mistaken for this loop's save. The legacy `ls`-diff of `.supervisor/jobs/pending/` remains a **pre-v14.2.0 fallback** (used only when the result block is absent or fails validation); it keeps the original single-session-only constraint and still aborts the multi-file case with `status_reason="concurrent_session_detected"`. For pre-v14.2.0 plugins the safe operating rule remains: one autonomous / launch-pad invocation at a time per repo.

### `/autonomous --cheap` (supported since v15.2.0 — forwarded to the inlined `/supervisor`)
Since v15.2.0, `--cheap` **is forwarded**: `/autonomous` parses it at INIT and appends it to every inlined `/supervisor job:` invocation (EXECUTE step 1 §"Auto-forwarded flags"), and `/automate` passes it through to its inner `/autonomous` call — the full `/automate → /autonomous → /supervisor` chain carries the Sonnet cost profile. Note the `/automate` passthrough is NOT persisted in the run file's `## Run Config`, so re-pass it on each `--resume` / `/loop` tick. `--skip-preflight-sync` remains unforwarded. On pre-v15.2.0 plugins the flag was an inert no-op — there, run `/launch-pad` and `/supervisor --cheap` manually. See `commands/autonomous.md` "Parameters" → `--cheap interaction note` for details.

---

## References

- User-facing: `README.md`, `.claude-plugin/README.md`
- Standards: `AGENT_GUIDELINES.md`
- Manifests: `.claude-plugin/marketplace.json`, `loomwright/.claude-plugin/plugin.json`
- Schemas / contracts / failure modes: `loomwright/docs/{RESULT_SCHEMAS,ARCHITECTURE_CONTRACTS,FAILURE_ESCALATION,ARCHITECTURE,QA_SYSTEM_BLUEPRINT,TELEMETRY,OBSERVABILITY}.md`
- Skills index: `loomwright/skills/SKILLS_INDEX.md`
