# CLAUDE.md

Guidance for Claude Code when working in this repository.

- User-facing docs (install, quick start, commands, troubleshooting): `README.md`
- Development standards & shared agent contract: `AGENT_GUIDELINES.md`
- This file captures what's *not* obvious from those — invariants, schemas, hooks, and incident-derived gotchas

---

## Project Overview

**AI Agent Manager** is a Claude Code plugin with 14 agent roles (9 user-facing + 5 internal) for plan-first readiness, parallel execution, requirements, planning, code review, commits, adversarial audits, standalone PR review-and-heal, and dual-agent QA. Supervisor and Launch Pad use `.supervisor/` exclusively for state; Orchestrator and Product Owner can optionally use Beads.

**v14.44.0 — `/automate` emits an honest engine-native ground-truth churn line (no more GitHub-blind false-0 postmortem) (additive):** Fixes `/automate` reading `review_rounds: 0` on exactly the flow it produces (inline `/review-pr --until-mergeable` drain + CI-check review + squash-merge) — the `/pr-postmortem` gather is GitHub-surface and the drain's review never reaches GitHub, so all three of its signals read 0. Instead of patching the generic postmortem, the engine now emits its OWN truthful line from data it ALREADY holds. **(1) Fail-safe `learning-emit` helper (`scripts/automate-helpers.sh` + self-test):** a new `learning-emit` subcommand builds ONE full valid `schema_version: 1` POSTMORTEM_RESULT (jq-only / injection-safe, `set +e` always-exit-0 like `send-webhook.sh`) from the owned drain's `REVIEW_HEAL_RESULT` (`fix_cycles`/`repeat_check_failure`/`unresolved_bot_feedback`/`decision`) + the inner `SUPERVISOR_RESULT` (`repo`/`number`/`pr_url`/`branch`) plus a single `gh pr view --json files,additions,deletions,changedFiles`. `review_rounds` = `effective_review_rounds` (= drain `fix_cycles`, or `1` for a zero-cycle escalation); a single honestly-labeled synthetic `categories[]` entry (`drain_churn` / `drain_escalation`) honors the **zero-rule** (`categories: []` only when `effective_review_rounds == 0`, so the live `read-postmortem.sh` reader never sees fake churn); `changed_paths` is populated (load-bearing — the reader matches ONLY on `changed_paths` overlap); a deterministic `automate_key` (`run_id`+item+`pr_url`+`source`) makes a crash/`--resume` re-entry idempotent (exactly one line). **(2) Wired at end-of-DRAIN (`skills/automate-loop/SKILL.md` §6 step 3):** emitted AFTER the terminal `REVIEW_HEAL_RESULT` read and BEFORE the GATE, so PARKED items (which stop at the GATE and never reach CHECK OFF) are covered too — one line per PR, merged OR parked. The emit is **advisory / fail-SAFE — its exit status is ignored and it NEVER changes `owned_drain_result`, the GATE, `## Status`, `## Current`, or any `/autonomous` gate** (mirrors `postmortem_dispatched`-is-informational). **(3) `--no-auto-postmortem` on the owned drain (§7):** the engine's owned `/review-pr --until-mergeable` now runs with `--no-auto-postmortem` so the corpus gets ONE honest engine-native line, not one honest + one GitHub-blind false-0 (the standalone `/review-pr` tail OUTSIDE automate is unchanged). **(4) Additive schema (`docs/RESULT_SCHEMAS.md`):** two optional additive POSTMORTEM_RESULT fields — `source` (`"github_postmortem"` implicit default \| `"automate_drain"`) and `automate_key` — with a worked `automate_drain` variant note; **no `schema_version` bump** (same precedent as `pr_url`/`changed_paths`). **Invariants intact:** `pr-postmortem-gather.sh` is untouched (stays a generic GitHub-surface analyzer; no consumer-specific log parsing leaked in); the sole `gh pr merge --squash` executor and `/automate` single-drain ownership are unchanged; runtime emitters fail-SAFE (exit 0) while correctness gates fail-CLOSED. **No new agent / command / skill / hook (counts unchanged at 14 agents / 19 commands / 56 skills / 20 hooks); no `schema_version` bump.** Additive on top of v14.43.0.

**v14.43.0 — first-line review rigor (quality, not pass-the-PR): adversarial-input + execution-grounded lens in the shared reviewer, a correctness⇒HIGH/BLOCKING severity rule, and observable anticipatory fix-worker self-review (additive):** Makes the plugin's first-line code review actually *catch real defects* (negative-amount exploits, idempotency holes, run-once violations) instead of reading a checklist — measured by defects caught early / escaped to `main`, **not** reviewer agreement or gate-pass rate — without homogenizing the two independent review lenses or weakening the **#64** lesson. **(1) Rigor in the shared `code-reviewer` brain (`agents/code-reviewer.md` + the preloaded `skills/quality-checklist/SKILL.md` Self-Heal Miss-Class Checklist):** two new Review-Process steps — an **Adversarial-Input Lens** (interrogate every changed code path for negative/zero/overflow/empty, replay-idempotency, and concurrency) and an **Execution-Grounded Verification** step that runs ONLY non-mutating checks (type-check; the specific tests covering the diff) and NEVER runs update/fix/format/snapshot-update/coverage/migration/seed commands. When behavior can't be verified it is reported **`unverified` (never a silent pass)**; a **load-bearing** unverified correctness/security behavior returns `NEEDS_HUMAN`/blocking (a non-load-bearing one is reported but non-blocking). Because the reviewer is a **shared brain**, Phase 4.5 self-heal, the `/review-pr` drain, and standalone `/code-reviewer` all inherit the rigor with no per-caller duplication. **(2) Severity-assignment rule (closes the inert-lens gap):** any confirmed correctness/security/behavior regression introduced by the diff MUST be labeled **HIGH or BLOCKING** (never MEDIUM/LOW) so the diff-review fix floor (`new` + BLOCKING/HIGH) actually fixes it — MEDIUM/LOW stay for maintainability/polish. This is **NOT** a drain severity floor (the #64 anti-pattern stays pinned) and does **NOT** touch the `drift` severity caps. **(3) Observable anticipatory fix-worker self-review (`agents/supervisor.md` Phase 4.5 fixer + both `skills/review-heal/SKILL.md` fix prompts):** before pushing, every fix worker re-reads its OWN diff for downstream regressions (persistence/state/lifecycle/idempotency/concurrency — the class behind combo-split→double-`Save` and earn-counter→dedup-collision) and emits an observable `self_review:` note; a push with no note is treated as incomplete by a co-located gate on all three fixer sites. **(4) Drain cosmetic-defer DEFERRED by evidence:** the original problem also aimed to stop the `--until-mergeable` drain grinding on cosmetic noise, but the BetterBlocks #31/#32 postmortems showed the churn was a *real self-heal miss* (#31 `self_heal_misses=1`), not cosmetic noise — so **no drain cosmetic-defer semantics ship this run** (READY / remaining_issues / findings_* untouched; no `findings_deferred` field); parked for a follow-up brief. **Invariants intact:** the two review lenses stay independent (no rubric-mirroring); `/review-pr` & Phase 4.5 still NEVER merge; the sole `gh pr merge --squash` executor is unchanged; runtime emitters fail-SAFE (exit 0) while correctness gates fail-CLOSED. **No new agent / command / skill / hook (counts unchanged at 14 agents / 19 commands / 56 skills / 20 hooks); no `schema_version` bump.** Additive on top of v14.42.0.

> 📜 **Full release history** (v14.42.0 → v14.0.0 and earlier) lives in [`CHANGELOG.md`](CHANGELOG.md). CLAUDE.md keeps only the two most recent release notes.

---

## Plugin Layout

The repo is a **marketplace wrapper** containing one nested plugin:

- Marketplace manifest: `.claude-plugin/marketplace.json` (root)
- Plugin manifest: `ai-agent-manager-plugin/.claude-plugin/plugin.json` (v14.44.0)
- Agents: `ai-agent-manager-plugin/agents/` (14 markdown prompts)
- Commands: `ai-agent-manager-plugin/commands/` (19 entry points)
- Skills: `ai-agent-manager-plugin/skills/` (56 skills, see `SKILLS_INDEX.md`)
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
│   ├── commands/                              # 19 slash commands
│   ├── hooks/hooks.json                       # cross-cutting hooks
│   ├── skills/                                # 56 skills + SKILLS_INDEX.md
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

20 hooks centralized in `hooks.json` (the v12.2.0 webhook hook brought the count 13 → 14; v13.0.0 / v14.0.0 added none — v14's `--notify` gate-event webhooks are emitted inline by the autonomous-loop, not by a hook; **v14.1.0 added 2 events / 3 entries** — `PreToolUse[AskUserQuestion]` (notify-desktop + send-webhook) and `Notification` (notify-desktop) — bringing the count 14 → 17; **v14.2.0 added 2 entries** — a `SessionStart` → `session-resume.sh` and a `launch-pad-runner` SubagentStop → `validate-launch-pad-result.py` — bringing the count 17 → 19; **v14.34.0 added 1 entry** — a `PostToolUse[Bash]` → `hook-dispatch-on-pr-create.sh` backstop — bringing the count 19 → 20). Prompt-based validation uses fast haiku model with 30s timeout. WorktreeCreate / StopFailure / telemetry / webhook / notification / resume / launch-pad-result hooks use `type: command` for zero-latency.

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
| SessionStart — v14.2.0 | Session resume / clear / compact | hooks.json | type:command — `session-resume.sh`; injects bounded (≤10k) recovery context; silent on startup; since v14.24.0 also runs the observability health probe (env-block-gated 1s curl, 24h debounce, never starts Docker — adds no new hook entry); exits 0 |
| PostToolUse (Bash) — v14.34.0 | A Bash tool call completes (e.g. `gh pr create`) | hooks.json | type:command — `hook-dispatch-on-pr-create.sh`; backstops the until-mergeable review drain on PR creation. Session-scope gated (in-progress job + a coherent active-session source: non-terminal branch-matching state.md OR a unique active autonomous state.json; stale terminal state.md no longer short-circuits); fail-safe, always exits 0 |

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

**`gh pr merge --squash` has exactly ONE sanctioned executor (invariant — do not break):** the **only** place in the plugin that EXECUTES `gh pr merge --squash` is the `automate-loop` `--auto-merge` gate (`skills/automate-loop/SKILL.md` §10, implemented by `scripts/automate-helpers.sh`'s `gate-eval`). It is **opt-in, default-OFF**, and fires only when ALL FIVE trusted-merge conditions hold; any failed / null / unreadable condition fails **CLOSED** (park + notify). `review-heal` (`/review-pr`) and Supervisor Phase 4.5 **NEVER merge** — they review-and-heal only and leave the PR open for a human (`READY`/`PASS`/`ESCALATED` are all terminal-stop, merge-identical). The positive-form invariant check is `grep -rn "gh pr merge --squash" ai-agent-manager-plugin/ | grep -viE "no |never |not "` — it resolves to exactly four surfaces: `skills/automate-loop/SKILL.md`, `scripts/automate-helpers.sh` (the executor), `scripts/test-automate-helpers.sh`, and `commands/agent-help.md` (which describes the sanctioned gate). (`commands/automate.md`'s own two mentions are correctly EXCLUDED by the `no|never|not` filter; review-heal / review-pr / RESULT_SCHEMAS likewise keep only their negative-assertion "never merges" mentions.) See `skills/automate-loop/SKILL.md` §11 for the authoritative enumeration. Adding a second executor anywhere else is a regression.

**`/automate` single-drain ownership (invariant — do not break):** when the `automate-loop` engine runs an item it sets `.supervisor/config.json {"auto_review": false}` **around** the inner `/autonomous` RUN phase (both of Supervisor's default detached until-mergeable dispatch paths — step 5.5 and the `PostToolUse[Bash]` `gh pr create` hook — fire *during* `/autonomous`, so the toggle must wrap RUN, not DRAIN), then owns **exactly ONE** inline `/review-pr --until-mergeable` drain. The toggle is a byte-for-byte backup to a transient `<run_id>.config-backup.json` restored in a finally-style cleanup (overwrite, or **delete if originally absent**; **malformed pre-existing config ⇒ abort**; RECONCILE restores a crash-stranded backup). This prevents a double until-mergeable drain racing the PR branch. Verifiable via `## Current`'s `suppressed_default_dispatch: true` + `owned_drain_started`/`owned_drain_result` and the absence of any detached `dispatch-pr-review.sh` artifact for the PR.

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
`git worktree list`; `git worktree remove ../project-BD-XXa`; `git branch -d feature/BD-XXa`. The detached until-mergeable review drain also creates a sibling worktree (`../{project}-review-{pr_hash}`, detached-HEAD at the PR head SHA) owned by `dispatch-pr-review.sh`'s `trap cleanup EXIT` wrapper, which removes it on the wrapper's normal/error exit. A **hard** kill (SIGKILL / power-loss) skips the trap, so that worktree can linger on disk — `git worktree prune` only reclaims an entry once its directory is *already gone*, and the durable per-PR marker blocks the same-PR re-dispatch whose pre-add cleanup would otherwise force-remove it. Remove a stray one manually: `git worktree remove --force ../{project}-review-{pr_hash}` (the leak is cosmetic — the marker preserves idempotency).

### Detached review drain colliding with inline self-heal? (fixed in v14.42.0 — drain is now worktree-isolated)
**Do NOT write `.supervisor/config.json {"auto_review": false}` to suppress the until-mergeable drain for the self-heal race** — that practice is **retired** as of v14.42.0. The detached dispatched drain (`review-pr-runner`, launched by `dispatch-pr-review.sh`) now runs in its OWN sibling git worktree (detached-HEAD at the PR head SHA), so it no longer shares a working tree/index with the inline Phase 4.5 self-heal and cannot sweep its uncommitted edits — the collision the suppress kill-switch existed to dodge is gone. The `auto_review` flag **remains** as a legitimate general opt-out (turn the drain off entirely), but it is no longer the recommended fix for the concurrency hazard, and suppressing it for the race risks the exact silent-drop it used to cause (a suppressed drain with no safe restore = no dispatch; cf. PR #74). A markerless heal-outcome PR now surfaces in `/insights` under `## Missing-drain reconciliation` as the signal to investigate.

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
