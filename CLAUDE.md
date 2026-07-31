# CLAUDE.md

Guidance for Claude Code when working in this repository.

- User-facing docs (install, quick start, commands, troubleshooting): `README.md`
- Development standards & shared agent contract: `AGENT_GUIDELINES.md`
- This file captures what's *not* obvious from those — invariants, schemas, hooks, and incident-derived gotchas

---

## Project Overview

**Loomwright** is a Claude Code plugin with 14 agent roles (9 user-facing + 5 internal) for plan-first readiness, parallel execution, requirements, planning, code review, commits, adversarial audits, standalone PR review-and-heal, and dual-agent QA. Supervisor and Launch Pad use `.supervisor/` exclusively for state; Orchestrator and Product Owner can optionally use Beads.

**Two review lenses, not four passes** (the current review-lane contract): the `--until-mergeable` drain is **heal-only by default**, with one Earned Fallback Review that runs when no review-producing lens verifiably posted (fails closed *toward* running it); and **no per-subtask LLM reviewer is spawned at any threshold** — the deterministic `outputs_verified` gate plus tests/lint is the per-subtask gate, and Phase 4.5's integrated review is the sole LLM gate. **Supervisor's frontmatter is skill-routed, not preloaded (4f, v15.19.0):** `loomwright:supervisor-runner`'s `skills:` list dropped from seven frontmatter-preloaded skills to zero — each protocol skill is Read on demand at its actual phase entry instead, matching the inline `/supervisor` path's long-standing zero-preload pattern (`agents/supervisor.md` §"Preloaded Skill Routing (4f)"); the Launch Pad brief also now stamps a `Base commit` freshness anchor that Phase 1.5 PRE-FLIGHT SYNC reads as a purely advisory churn signal (4g) — it degrades silently on older briefs and can never by itself flip a CLEAR classification to OVERLAP. **Workers get a shared context digest and explicit file lanes (D6, v15.20.0):** Launch Pad's Phase 5 PACKAGE now also produces a bounded (6000-byte default, truncation-marked) per-job `CONTEXT_DIGEST` artifact — File Impact Map, interfaces touched, conventions, sibling-subtask summary, cross-lane producer/consumer contracts — pointer-handed (path + ≤200-char summary + "Read only the sections you need") to every spawned worker on both the Task-spawn and SDK-runner carriers, with the main-checkout absolute path used whenever the worker is worktree-resident (`docs/POINTER_AUDIT.md` §"Context digest"). Every subtask contract in a multi-subtask brief additionally declares a `lanes:` list of owned path globs (`skills/supervisor-readiness/SKILL.md` §"Lane Declaration Schema"); a worker writing outside its own declared lane is recorded — report-only, never blocking — in a new `out_of_lane` `WORKER_RESULT` field (optional additive at `schema_version: 2`, no bump). A **same-wave** lane overlap (the `requires`-DAG reachability test — mutual unreachability, not the absence of a *direct* edge, which would falsely flag transitively-ordered pairs) is a genuine brief-authoring defect caught by Plan Reviewer's new **Criterion 16**. **Deferred by owner decision:** the worker re-read-volume cost measurement against the arm-2 baseline is an owed ~$60 operator-run eval, not shipped in this PR.

> 📜 **Full release history** (every version, including the current one) lives in [`CHANGELOG.md`](CHANGELOG.md). CLAUDE.md keeps only the one-paragraph current-version summary above — full release notes belong in the changelog, not here.

---

## Plugin Layout

The repo is a **marketplace wrapper** containing three sibling plugins (loomwright, stackpack, mysql-mcp):

- Marketplace manifest: `.claude-plugin/marketplace.json` (root)
- Plugin manifest: `loomwright/.claude-plugin/plugin.json` (v15.20.0)
- Agents: `loomwright/agents/` (14 markdown prompts)
- Commands: `loomwright/commands/` (21 entry points)
- Skills: `loomwright/skills/` (41 skills, see `SKILLS_INDEX.md`)
- Hooks: `loomwright/hooks/hooks.json`
- Docs: `loomwright/docs/`
- Sibling plugins: `stackpack/` (18 tech-stack reference skills, v1.0.0) and `mysql-mcp/` (read-only MySQL MCP server `vikashruhil-mysql-mcp`, v1.0.0)

> **Repo path vs. runtime path:** `loomwright/...` is the developer-side path (this repo on disk). Anything invoked by hooks, skills, or agents at *runtime* must reference `${CLAUDE_PLUGIN_ROOT}/...` — that's the canonical Claude Code variable that resolves to the plugin install dir on both dev checkouts and marketplace installs. Never use `loomwright/...` paths from the user-project root; they only resolve for the plugin maintainer.

---

## The 14 Agent Roles

Detailed per-agent purpose, command syntax, and workflow diagrams live in `README.md` §"The 14 Agents" and the agent prompts (`loomwright/agents/*.md`). Quick map of what matters for in-codebase work:

| Agent | Type | Spawned by | Codebase-relevant invariants |
|---|---|---|---|
| Launch Pad | user-facing | user | Phase 2.5 feasibility (GO/CAUTION/NO-GO); Phase 5.5 mandatory Plan Review (max 3 spawns per session); writes briefs to `.supervisor/jobs/pending/`. **Requirement-file input:** Phase 2 step 0 — when the `goal:`/`feature:`/`problem:` value is a path **under `.supervisor/requirements/`** to an existing `.md` (resolves via `test -f` against the project root, the Beads-absent Product Owner story target), Launch Pad reads it as the requirement source; any other value (including a bare repo file like `README.md`) stays a literal-string goal. Closes the PO→Launch Pad handoff gap in Beads-optional mode. Also stamps `source_requirement` provenance (`- **Source requirement:** {path}` under the brief `## Environment`) for requirement-file inputs |
| Supervisor | user-facing | user | v4 + **Phase 1.5 PRE-FLIGHT SYNC** (remote-state reconciliation between ACQUIRE and PLAN — classifies the requested work CLEAR/OVERLAP/SUPERSEDED, silent on CLEAR, soft-gate `AskUserQuestion` interactively, fails closed under `--non-interactive` with `error: "preflight_overlap_detected"`; bounded ≤6 calls; `--skip-preflight-sync` escape hatch) + Phase 4.5 self-heal — self-heal phase **always** runs; `--skip-self-heal` only short-circuits the loop; completion-tail relocates job-move + state-completed from FINALIZE; completion-tail also stamps an idempotent `## Status: done` close-out on the originating requirement file in **Beads-absent** mode (success-only, fail-safe). **Phase 4.5 also offers an opt-in, default-OFF, NON-gating advisory red-team lens** (`--red-team` / `--no-red-team`, `.red_team_high_risk` config) that runs only on high-risk integrated diffs and records findings in `SUPERVISOR_RESULT.summary` + the job Outcome block — never blocks the PR or changes the `heal_decision`. **v15.8.0 opt-ins (both default OFF):** `--sdk-runner` (EXPERIMENTAL — Phase 3 shells out to the quarantined `sdk-spike/` runner; fail-closed `sdk_runner_unavailable` if node/built runner absent) and `--multi-voter-heal` (`.multi_voter_heal` config; Phase 4.5 spawns an independent red-team-reviewer verification vote + refute check — refuted findings logged, not fixed; gate shape unchanged; authority: `skills/self-heal-advisory/SKILL.md` Part 2). **Phase protocol bodies live in skills (v15.4.0):** `preflight-sync` (Phase 1.5) / `supervisor-config` (Phase 0) / `self-heal-advisory` Part 2 (Phase 4.5) / `async-orchestration` Part 2 (Phase 4 FINALIZE + spawn contracts + worktree lifecycle) — Read at phase entry; gates and the completion-tail guard stay in `agents/supervisor.md`. **Never assert git merge/PR state ("on main", "in the PR", "already merged") without verifying via `git log` / `git branch --contains`.** |
| Product Owner | user-facing | user | Assumption Check (standard) + Reality Check (`--brainstorm`) cap Feasibility for NEEDS_FOUNDATION/BLOCKED ideas. **Beads-optional** (see Orchestrator row): when `beads_active` is false, stories persist as `.supervisor/requirements/*.md` and handoff is by file path, not `BD-XX` |
| Orchestrator | user-facing | user | Reads CLAUDE.md (+ Beads when active) → EPIC / TASK with skill references. Defaults to one task per `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold" (split only for a named reason); **no paired review subtask is generated at any threshold (Fix 7, v15.18.0)** — the deterministic `outputs_verified` gate plus tests/lint is the per-task gate throughout, and Phase 4.5's integrated review is the sole LLM gate — see `agents/orchestrator.md` §"Review Gate Policy". **Beads-optional:** a `## Persistence Mode` block branches on `beads_active` (probe `test -d .beads && bd --version`); when absent, skips all `bd` and writes the task tree to `.supervisor/requirements/{slug}-plan.md` — the no-per-subtask-review policy applies in both modes. Detection logic already lived in the shared `context-setup` skill; this wires output to it (matching Code Reviewer's long-standing Beads-optional pattern) |
| Code Reviewer | user-facing | user | LSP, read-only mode, schema_v3 (adds `drift` category, severity caps via hook). **Auto-expands to consistency audit** when diff touches `agents/`, `commands/`, `skills/`, `docs/`, or plugin metadata |
| Red Team Reviewer | user-facing | user | 6 attack vectors; persistent memory of past audits |
| QA Strategist | user-facing | user | Three modes (Strategy / Gate Audit / Post-Execution Audit); spawned twice (gate audit Phase 11, results audit Phase 13) |
| QA Executor | user-facing | user | Multi-phase Level 1 protocol (phases 1–13, non-monotonic order), `--depth smoke|functional`, `--plan/--scope/--continue`, infrastructure-aware (Mailpit/MailHog), 80/110/60 budget (default/scoped/plan) with 60/80/92% zones |
| Review-PR (`review-pr-runner`) | user-facing | user / Supervisor completion-tail / autonomous EVALUATE | `/review-pr <pr-url>` standalone review→fix→re-review loop against an existing PR; resolves PR-URL → head branch, spawns `code-reviewer` + `general-purpose` fix worker; **never auto-merges**; emits `REVIEW_HEAL_RESULT`. NEVER Task-spawned (subagents-cannot-spawn-subagents) — run inline via `/review-pr` or as `claude --agent …:review-pr-runner`. Authority is the `review-heal` skill. |
| Execute Manager | internal | Supervisor (Phase 3) | Owns poll loop in isolated context, 60 tool-call budget |
| Context-Keeper | internal | Supervisor / Execute Manager | **Sole writer** of state file on the parallel path (the inline main-thread Supervisor may do an equivalent best-effort direct write of the `## Session` block); haiku model, batch updates, atomic writes |
| Worker | internal | Execute Manager / Supervisor | Above threshold: one subtask per worktree. Single-Agent Path (below threshold, the default): one worker executes ALL acceptance criteria in the project root, no worktree. No git ops either way, emits WORKER_RESULT + `.worker-summary.md` |
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
- Execute Manager owns the poll loop and worker lifecycle, Context-Keeper coordination
- Each worker runs in its own git worktree (no file conflicts)
- Workers write `.worker-summary.md` for lightweight result extraction
- Context-Keeper externalizes state; Supervisor uses tool-call budgets (50, including Phase 4.5) instead of percentage thresholds; Execute Manager has its own 60-call budget in isolated context
- Subtask branches merge sequentially into the feature branch with pre-merge validation
- **No per-subtask LLM reviewer is spawned at any threshold (Fix 7, v15.18.0)** — each worker's own deterministic `outputs_verified` gate plus tests/lint is the per-subtask gate; Supervisor's Phase 4.5 integrated review, run once holistically after FINALIZE, is the sole LLM gate. See `agents/orchestrator.md` §"Review Gate Policy".
- Single-Agent Path (exactly 1 subtask, the default below `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold"): skips worktrees and Execute Manager entirely, one worker executes all acceptance criteria in one context — Phase 4.5's holistic review is the single review, same as above

---

## Adding or Modifying Agents

1. **New agent:** `.md` in `loomwright/agents/` with YAML frontmatter; output follows Context Read → Plan → Work → Results → Risks. **Also declare a token budget:** add an `.agents[<stem>]` entry to `loomwright/docs/prompt-token-budgets.json` (measured proxy weight + ~10% headroom) plus the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" — `check-token-budget.sh` fails CI CLOSED on an agent with no declared budget
2. **New slash command:** `.md` in `loomwright/commands/` referencing the agent prompt
3. **New skill:** `SKILL.md` in `loomwright/skills/[name]/` with version frontmatter; update `SKILLS_INDEX.md`
4. **Test locally:**
   ```
   /plugin uninstall loomwright
   /plugin install loomwright@atelier
   ```
   Verify with `/agent-help`
5. **Cite exact `file:line` numbers when referencing code**

**Doc currency is CI-enforced:** `scripts/check-doc-currency.sh` (a CI gate alongside `validate-version.sh`) mechanically verifies that version/count claims across the doc surfaces — agent/command/skill/hook counts, `plugin.json (vX.Y.Z)` annotations, and the `Loomwright vX.Y.Z` headline — match the authoritative source (`plugin.json`, `hooks.json`, the `agents/`/`commands/`/`skills/` dirs). When you add/remove an agent, command, skill, or hook, or bump the version, **update the doc claims in the same change or CI fails.** It scans only high-confidence current-claim phrasings (never bare numbers), so dated changelog entries don't false-positive. The authoritative, always-current hook table lives in this file (§"Plugin Hooks (Quality Gates)"). **Surfaces the gate does NOT scan (recurring drift, integration-review-only):** Supervisor phase enumerations (agent-help.md, command docs), per-run YAML frontmatter field lists in `build-insights.sh`, budget/zone numbers, and `/insights` dashboard section enumerations. (Per-row skill `version:` cells in `SKILLS_INDEX.md` were on this list until v15.2.3 — now mechanically enforced by `scripts/check-skills-index-sync.sh`; likewise the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" per-agent mirror table's budget cells are mechanically synced to the authoritative `prompt-token-budgets.json` by `check-token-budget.sh` — drifted, missing, or ghost rows fail CI closed.) On any phase/version/budget/section change, grep the OLD value repo-wide — a green doc-currency run is necessary but not sufficient. **Conversely, do NOT "fix" illustrative example values to the current version:** sample `session_end` / `POSTMORTEM_RESULT` JSONL records and `e.g. "X.Y.Z"` `plugin_version` placeholders (in `docs/RESULT_SCHEMAS.md`, `agents/supervisor.md`, and similar) illustrate *format* only — the real value is read at runtime from `plugin.json` via jq, so they are NOT current-claims, carry no currency requirement, and are deliberately unscanned. Bumping them every release is a drift-treadmill the gate cannot enforce (they re-stale at the next version), so leave them **frozen and version-agnostic** — a stale-looking version inside an example block is intended, not drift, and should not be re-flagged in review. (v14.25.1 codified this after a review round chased the placeholders.)

**Plugin `description` is a summary, not a changelog (anti-rebloat):** the `description` field in `plugin.json` and `.claude-plugin/marketplace.json` is the crisp card shown in the plugin-manager UI. On a version bump, update the `vX.Y.Z` string and the four counts **in place** and keep it short; put the per-release narrative in `CHANGELOG.md` (and, if notable, a single CLAUDE.md banner) — **never append another version clause to the description.**

**Hook gotcha:** Claude Code silently ignores `hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter — only `hooks.json` hooks fire for plugin-distributed agents. Per-agent frontmatter hooks are kept for `~/.claude/agents/` compatibility.

---

## Structured Contracts (v9.0.0)

- **Result Schemas** — `loomwright/docs/RESULT_SCHEMAS.md`. CODE_REVIEW_RESULT at `schema_version: 3` (adds `review_mode` (`diff_review` | `consistency_audit`), `audit_focus[]`, `trigger_paths_detected[]`, `scope_expanded[]`, `files_checked[]`, `consistency_checks`, `consistency_summary`, and the `drift` issue category with `drift_kind` + severity caps; v2 accepted for legacy artifacts). WORKER_RESULT at `schema_version: 2` (adds `outputs_verified[]` + `outputs_gap`; v1 accepted for the v12.0.0 transition window), plus the optional additive `out_of_lane[]` in v15.20.0 — report-only, **no** version bump (same non-bumping precedent as `memory_candidates`, but unlike it `out_of_lane` IS validated when present, by `validate-worker-result.py` rule 9). **CONTEXT_DIGEST** (v15.20.0) is a per-job **file artifact**, not an agent result block: no `schema_version`, no `SubagentStop` validation — correctness lives in `scripts/test-context-digest.sh`. AUTONOMOUS_RUN at `schema_version: 2` (v14 — adds nine new closed `status_reason` values for stacked-branch / non-interactive-fallback / webhook-notify failure modes; v1 accepted for the v13 transition window). SUPERVISOR_RESULT remains at `schema_version: 1` with two new optional additive fields in v14 (`branch_base`, `pr_state`). All others at `schema_version: 1`.
- **Failure Escalation** — `…/FAILURE_ESCALATION.md` (retry limits, escalation paths)
- **Architecture Contracts** — `…/ARCHITECTURE_CONTRACTS.md` (capability matrix, context budgets, timeouts, worktree naming)
- **Job Lifecycle** — briefs flow `pending/` → `in-progress/` → `done/` / `failed/` in `.supervisor/jobs/`
- **Session Logging** — JSONL in `.supervisor/logs/{session_id}.jsonl`
- **Merge Safety Gate** — pre-merge checklist in FINALIZE prevents corrupted partial merges

---

## Plugin Hooks (Quality Gates)

24 hooks centralized in `hooks.json`, **21 `type: command` + 3 `type: prompt`**. **Only three still use prompt-based validation** (fast haiku model, 30s timeout): `SubagentStop[loomwright:code-reviewer]`, `Stop`, and `TaskCompleted` — the `code-reviewer` validator is deliberately retained because its cross-field + severity-cap logic is richer than presence-checking, and it is the ONE remaining prompt validator on any `SubagentStop` matcher. Every other hook is `type: command` for zero-latency. **`|| true` convention:** every `type: command` hook string carries `|| true` as belt-and-suspenders for missing-interpreter/syntax-error edges — valid ONLY because all of them are always-exit-0 fail-safe emitters/validators (`validate-launch-pad-result.py` included: it decides via stdout JSON, exit-0-by-contract). A future blocking gate (non-zero-exit) added as a `type: command` hook must NOT carry `|| true` — that would silently neuter it (see §Failure-Mode Invariants). Per-hook version provenance lives in `CHANGELOG.md`; the authoritative current wiring is `hooks.json` itself, mirrored in the table below.

| Hook | Trigger | Location | Validation |
|------|---------|----------|------------|
| SubagentStop (worker) | Worker completes | hooks.json + frontmatter | type:command — `validate-worker-result.py` (v15.17.0, converted from a prompt hook); WORKER_RESULT (schema_version, task_id, status, files_modified) |
| SubagentStop (worker) progress event — v15.16.0 | Worker completes | hooks.json | type:command — `emit-progress-event.sh`; appends one `subtask_complete` JSONL event to the session log and invokes `build-state.sh` to project `.supervisor/state.md`'s `## Session` block; always exits 0 (fail-safe) |
| SubagentStop (execute-manager) | Execute Manager completes | hooks.json + frontmatter | type:command — `validate-execute-result.py` (v15.17.0, converted from a prompt hook); EXECUTE_RESULT / EXECUTE_CHECKPOINT |
| SubagentStop (code-reviewer) | Code Reviewer completes | hooks.json | **type:prompt (deliberately retained in v15.17.0 — the one remaining SubagentStop prompt validator; its cross-field + severity-cap logic is richer than presence-checking)**; CODE_REVIEW_RESULT v3 with decision + issue categories |
| SubagentStop (supervisor) | Supervisor completes | hooks.json | type:command — `validate-supervisor-result.py` (v15.17.0, converted from a prompt hook); session outcome, subtask statuses, PR URL |
| SubagentStop (qa-executor) | QA Executor completes | hooks.json | type:command — `validate-qa-result.py` (v15.17.0, converted from a prompt hook); QA_RESULT (tests_generated, tests_passed, summary) |
| SubagentStop (plan-reviewer) | Plan Reviewer completes | hooks.json | type:command — `validate-plan-review-result.py` (v15.17.0, converted from a prompt hook); PLAN_REVIEW_RESULT (schema_version, decision, issues, summary) |
| SubagentStop telemetry × 3 | code-reviewer / qa-executor / supervisor-runner complete | hooks.json | type:command — stdin fan-out (`payload=$(cat)`): `send-telemetry.sh` → `send-telemetry-core.sh` **and** `emit-token-ledger.sh` (session JSONL `token_ledger`); both always exit 0 |
| Stop (code-reviewer) | Code Reviewer finishing | hooks.json + frontmatter | CODE_REVIEW_RESULT block present |
| TaskCompleted | Task marked complete | hooks.json | Task genuinely done |
| WorktreeCreate | Worktree created | hooks.json | type:command, logs `.supervisor/logs/worktrees.log` |
| WorktreeRemove — v15.5.0 | Worktree removed | hooks.json | type:command, logs `.supervisor/logs/worktrees.log` (`WORKTREE_REMOVED` lines — closes roadmap item #6's cleanup-verification gap) |
| StopFailure | Agent API error | hooks.json | type:command, logs `.supervisor/logs/failures.log` |
| SubagentStop webhook (supervisor-runner) | Supervisor completes | hooks.json | type:command — `send-webhook.sh`; gated on `LOOMWRIGHT_WEBHOOK_URL`; fire-and-forget POST; always exits 0 |
| PreToolUse (AskUserQuestion) — v14.1.0 | Plugin about to block on a user question | hooks.json | type:command — `notify-desktop.sh` (OS banner) + `send-webhook.sh` (paused-event POST); scope-gated; always exits 0 |
| Notification — v14.1.0 | Claude Code signals attention (permission_prompt / idle_prompt / elicitation_*) | hooks.json | type:command — `notify-desktop.sh` (OS banner); matched to exclude `auth_success`; always exits 0 |
| SubagentStop (launch-pad-runner) — v14.2.0 | Launch Pad `-runner` completes | hooks.json | type:command — `validate-launch-pad-result.py`; validates LAUNCH_PAD_RESULT (schema_version, status, saved_brief_path, summary); exits 0 |
| SessionStart — v14.2.0 | Session resume / clear / compact | hooks.json | type:command — `session-resume.sh`; injects bounded (≤10k) recovery context; silent on startup; since v14.24.0 also runs the observability health probe (env-block-gated 1s curl, 24h debounce, never starts Docker — adds no new hook entry); exits 0 |
| PostToolUse (Bash) — v14.34.0 | A Bash tool call completes (e.g. `gh pr create`) | hooks.json | type:command — `hook-dispatch-on-pr-create.sh`; backstops the until-mergeable review drain on PR creation. Session-scope gated (in-progress job + a coherent active-session source: non-terminal branch-matching state.md OR a unique active autonomous state.json; stale terminal state.md no longer short-circuits); fail-safe, always exits 0 |
| PostToolUse (Bash) progress-state re-projection — PR #116 review (v15.16.0) | A Bash tool call completes (SECOND entry on the same matcher as the row above) | hooks.json | type:command — `reproject-state-on-terminal.sh`; cheap two-check guard (state.md not already terminal + the session log's tail carries `session_end`) before invoking `build-state.sh`, mechanically re-projecting `.supervisor/state.md`'s terminal status — the fix for the projector's terminal branch otherwise never firing (no `loomwright:worker` runs after Phase 4.5's completion tail); fail-safe, always exits 0 |
| SessionStart — v14.47.0 | Session start (ANY source — startup / resume / clear / compact; unlike `session-resume.sh`, which skips `startup`) | hooks.json | type:command — `set-otel-resource-attrs.sh`; telemetry-gated, auto-maintains per-project `OTEL_RESOURCE_ATTRIBUTES` (`service.name=<repo>`, `service.version=<plugin version>`) in `<project>/.claude/settings.local.json`; no-ops when telemetry off; fail-safe, always exits 0 |

---

## Telemetry System (opt-in)

**Disabled by default.** Opt in via `/telemetry enable` (interactive) or `LOOMWRIGHT_TELEMETRY_REPO=owner/repo`; `/telemetry status|disable|test` manage it. Hooks **never** prompt — consent flows only through `/telemetry`.

Two invariants worth knowing here: it **fails CLOSED on privacy** (any whitelist match aborts the post, core exits `2`), and there is **no origin-remote fallback** — the plugin runs in arbitrary user projects whose origin is the wrong place for telemetry.

Full design (wrapper-vs-core architecture, scoring rubric, privacy whitelist, exit-code table 0..5): `loomwright/docs/TELEMETRY.md`.

---

## Persistent Memory & Skills Preloading

Agents opt in via frontmatter: `memory: project` gives an agent a persistent store at `.claude/agent-memory/loomwright:<agent>/`; `skills:` pre-injects those skill bodies at spawn time (no runtime file-read). Both lists are authoritative in `loomwright/agents/*.md` frontmatter — read there, not from a table here.

> Decision aid for *what* to write to those memory directories: `loomwright/skills/memory-tool/SKILL.md` (reference skill — not pre-loaded; consult on demand when tagging conventions or Memory-Tool-vs-file-based questions arise).

## Agent Teams (Recommended for 3 Use Cases, Experimental for the Rest)

Native Claude Code multi-agent coordination — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Best for research, competing hypotheses, cross-layer changes; not for sequential tasks or same-file edits (use Supervisor with worktrees). Patterns + decision matrix: `loomwright/skills/agent-teams/SKILL.md`. Complementary to Supervisor v4, not a replacement.

---

## Cost Profile

`/supervisor --cheap` — opt-in flag that overrides execution-shaped roles (orchestrator, execute-manager, worker, code-reviewer, Phase 4.5 fix tasks, and — when `--multi-voter-heal` is ON — the multi-voter verification voters/refute spawn) to Sonnet at spawn time. Default behavior (`inherit` for all) unchanged. Profile table, semantics, and Haiku-session caveat: `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles".

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
- **What this is:** inline main-thread execution misread as permission to stop orchestrating. "Don't delegate to `supervisor-runner`" does NOT mean "do everything yourself." Still spawn first-level children via Task — `orchestrator` (Phase 2), `execute-manager` or Single-Agent/Sequential-path worker (Phase 3), `code-reviewer` + fix loop (Phase 4.5).
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
Resume is fail-closed (v15.3.0): `--continue` schema-validates the loaded state BEFORE consuming it (closed `phase`/`status` enums + branch-must-verify, per `skills/state-management/SKILL.md` §"Resume validation gate") and refuses with `error: "resume_state_invalid"` on any violation — inspect or delete the state file; there is no override flag.
**Schema-valid is NOT the same as true.** A state file can pass every schema check and still under-report reality: on 2026-07-27 all 5 subtasks were merged while `state.md` read `phase: ACQUIRE` / all `PENDING`, and `--continue` would have silently re-executed the whole job. Resume therefore also runs `scripts/reconcile-resume-state.sh`, which reconciles the `## Subtasks` rows against subtask + merge commits on the asserted branch and refuses with a **distinct** `error: "resume_state_stale"` (`UNKNOWN` fails closed too). Different error because the operator response differs — an *invalid* file is corrupt (delete it), a *stale* file is intact but behind, and the work it claims is pending already exists on the branch. **Root cause worth remembering: prompt-instructed bookkeeping is unreliable** (measured in this repo: 560 hook-written `token_ledger` events vs 6 agent-written `phase_transition` events across 11+ sessions), so the reconciler keys on commits — a byproduct of the work — never on anything an agent must remember to write. Do not patch a future gap here by adding another "write your state" instruction.

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
- Schemas / contracts / failure modes: `loomwright/docs/{RESULT_SCHEMAS,ARCHITECTURE_CONTRACTS,FAILURE_ESCALATION,ARCHITECTURE,QA_SYSTEM_BLUEPRINT,TELEMETRY,OBSERVABILITY,POINTER_AUDIT}.md`
- Skills index: `loomwright/skills/SKILLS_INDEX.md`
