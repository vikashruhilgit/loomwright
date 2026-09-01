# Architecture Contracts

> Single source of truth for agent capabilities, budgets, hooks, state ownership, and performance targets.
> Referenced by all agents and hooks. Consolidates rules currently spread across multiple files.

---

## Agent Capability Matrix

| Agent | Spawn | Write | Bash | Review | Tests | State | Model |
|-------|-------|-------|------|--------|-------|-------|-------|
| Supervisor | yes | yes | yes | no | no | via Context-Keeper | inherit |
| Execute Manager | yes | no | yes | no | no | via Context-Keeper | inherit |
| Worker | no | yes | yes (+ LSP) | no | yes | no | inherit |
| Code Reviewer | no | no | yes (+ LSP) | yes | no | no | inherit (effort: high, permissionMode: plan) |
| Context-Keeper | no | yes | no | no | no | sole writer (parallel path) | haiku |
| Launch Pad | yes (plan-reviewer only) | yes | yes (+ LSP) | no | no | jobs/pending/ | inherit |
| Product Owner | no | yes (observed effective — `memory: project` grant, not blocked) | yes | no | no | no | inherit |
| Orchestrator | no | no (control case — no `memory:`, so no grant; see `disallowedTools` section) | yes | no | no | no | inherit |
| Red Team Reviewer | no | yes (observed effective — `memory: project` grant, not blocked) | yes | no | no | no | inherit |
| QA Strategist | no | yes (observed effective — `memory: project` grant, not blocked) | yes | no | no | no | inherit |
| Plan Reviewer | no | no | no | yes | no | no | inherit (effort: high) |
| Rubric Grader | no | no | yes (read-only git only) | yes (rubric scoring) | no | no | haiku |
| QA Executor | yes | yes | yes (+ LSP) | no | yes | no | inherit |
| review-pr-runner | yes (code-reviewer + general-purpose fix worker) | yes (fix worker pushes the PR branch) | yes (`gh`/`git`) | yes (via code-reviewer) | no | no | inherit |

> **review-pr-runner is NEVER `Task`-spawned (AC9).** It must run only as the **main agent of its own session** (`claude --agent loomwright:review-pr-runner`, launched fresh from the plain-`/supervisor` completion tail) or **inline on the main thread** via `/review-pr <pr-url>`. Because it spawns its own children (`code-reviewer` for review, `general-purpose` for the bounded fix), `Task`-spawning the runner would land it one spawn-level too deep and its child `Task` calls would fail (subagents cannot spawn subagents). In the `/autonomous` EVALUATE sense, the review-heal *loop body* runs as a Task step that performs review-and-fix inline — it does NOT `Task`-spawn the `-runner` agent. Canonical contract: `skills/review-heal/SKILL.md`.

## disallowedTools (Defense-in-Depth)

These are **defense-in-depth** restrictions for accidental misuse, NOT security boundaries against adversarial scenarios.

**Since `.supervisor/requirements/final-state/12-4c-unified-tools-lists.md` (unified `tools:` superset across
all 14 agents), every agent below carries a `tools:` allowlist that is byte-identical across the
plugin (`Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch`). Each
agent's per-row `disallowedTools` below is derived as `superset − observed effective toolset`, NOT
`superset − previously-declared tools` — four agents (Launch Pad, Product Owner, QA Strategist, Red
Team Reviewer) deliberately omit `Write`/`Edit` from their denylist because the harness's
`memory: project` grant gave them that capability effectively even though their prior declared
`tools:` never listed it; blocking it there would have removed a capability they actually have
today, not merely tidied a list.

> ⚠️ **PROVISIONAL — this row-set carries the weakest evidence in the table, and the hedge belongs
> here too.** The four `memory: project` rows below that leave `Write`/`Edit` **unblocked**
> (`launch-pad`, `product-owner`, `qa-strategist`, `red-team-reviewer`) rest on an **environment
> observation, not a CI-verifiable fact** — see `POINTER_AUDIT.md` §"The effective-toolset model, and
> the evidence for it" for the 14-row table and its method. `shared-agent-prefix.md` and
> `POINTER_AUDIT.md` both hedge this; **this table previously did not, and that inconsistency was the
> finding** — the unhedged version is what actually drives three agents' shipped `disallowedTools`.
> Two things remain genuinely open: (a) whether the grant is a *scoped memory-directory* capability
> rather than the general-purpose `Write`/`Edit` tools — different blast radii, and the observation
> of registered tool *names* does not settle it; and (b) whether the repo's fail-closed posture
> argues for blocking these three regardless, accepting a memory-write break as an observable
> regression to fix explicitly. **Treat the permissive choice as provisional pending real
> verification**, not as settled. `red-team-reviewer` audits untrusted input, which is what makes
> (a) worth resolving rather than assuming.

| Agent | disallowedTools | Rationale |
|-------|----------------|-----------|
| Code Reviewer | Write, Edit, NotebookEdit, Task, TaskOutput, WebSearch, WebFetch | Read-only diagnostic reviewer; keeps its pre-existing 3-item denylist, adds the newly-allowlisted spawn/network tools it never used |
| Context-Keeper | Task, TaskOutput, Bash, Glob, Grep, LSP, WebSearch, WebFetch | Sole state writer on the parallel path (inline main-thread Supervisor writes the `## Session` block directly); must never spawn agents or explore |
| Execute Manager | Write, Edit, LSP, WebSearch, WebFetch | First denylist for this agent; non-memory agent, no observed Write/Edit grant |
| Launch Pad | TaskOutput, WebSearch, WebFetch | **`Write`/`Edit` deliberately NOT blocked** — observed effective (see box above) |
| Orchestrator | Write, Edit, Task, TaskOutput, LSP, WebSearch, WebFetch | Read-only planner; no `memory:` declared, so no Write/Edit grant — the control case that shows the grant is tied to `memory: project`, not to plugin agents generally |
| Plan Reviewer | Write, Edit, NotebookEdit, Task, Bash, TaskOutput, LSP, WebSearch, WebFetch | Read-only; no mutation via any path; keeps its pre-existing 5-item denylist |
| Product Owner | Task, TaskOutput, LSP | **`Write`/`Edit` deliberately NOT blocked** — observed effective (see box above) |
| QA Executor | TaskOutput, WebSearch, WebFetch | Already declared `Write`/`Edit`/`Task`/`LSP` directly; only the newly-allowlisted items need blocking |
| QA Strategist | Task, TaskOutput, LSP, WebSearch, WebFetch | Keeps its pre-existing `Task` block; **`Write`/`Edit` deliberately NOT blocked** — observed effective (see box above) |
| Red Team Reviewer | Task, TaskOutput, LSP | **`Write`/`Edit` deliberately NOT blocked** — observed effective (see box above) |
| review-pr-runner | Write, Edit, TaskOutput, LSP, WebSearch, WebFetch | Non-memory; delegates edits to its `Task`-spawned `general-purpose` fix worker rather than writing itself |
| Rubric Grader | Write, Edit, NotebookEdit, Task, TaskOutput, LSP, WebSearch, WebFetch | Read-only Phase 4.5 grader; advisory only — must never mutate the diff it scores or spawn sub-agents; keeps its pre-existing 4-item denylist |
| Supervisor | LSP, WebSearch, WebFetch | Already declares `Write`/`Edit`/`Task`/`TaskOutput` directly; only the newly-allowlisted items need blocking |
| Worker | Task, TaskOutput, WebSearch, WebFetch | Keeps its pre-existing `Task` block — must never spawn subagents |

**Enforcement-model downgrade — recorded, not shipped silently (accepted for consistency and
canonical ordering, cost stated below).** Both this doc and `AGENT_GUIDELINES.md` describe
`disallowedTools` as defense-in-depth, NOT a security boundary — the `tools:` allowlist was meant to
be the real restriction. Unifying `tools:` to one superset across all 14 agents moves the allowlist
half of enforcement to uniform-by-construction and leaves the denylist carrying the *entire*
restriction for every agent, not just the six that already relied on it. The honest scope split:

- **No change in enforcement strength:** `plan-reviewer`, `rubric-grader` — the denylist was already
  their surviving mechanism before this change (each already carried one, and each already denied
  `Task`). `code-reviewer` belongs here for `Write`/`Edit` (its pre-existing denylist covered them)
  but **not** for `Task`: its old denylist was `Write, Edit, NotebookEdit` only, so its
  subagent-spawn block was 100% allowlist-enforced before this change and is denylist-only after.
  Functionally a no-op — it could not spawn either way — but it is a real transition, and this
  paragraph exists to not understate scope.
- **A genuine reduction:** `orchestrator` and `execute-manager` had **no denylist at all** before this
  change and were 100% allowlist-enforced (both `Write: no` in the Capability Matrix above) — this is
  their first reliance on the denylist. `orchestrator` is the case where the tempting
  "`permissionMode` was already ignored for plugin agents, so the denylist was already the surviving
  mechanism" rationale does **not** even apply: it declares no `permissionMode` at all, so there was
  no dead mechanism to point to — the allowlist itself was live and is what changes here. `review-pr`
  is the same shape but a weaker case (effective `Write: yes` only via its delegated fix worker).
- **Wider than the three read-only roles above, but not uniformly 14-wide:** the downgrade also
  covers tools that were allowlist-excluded on *most*, not all, agents — `TaskOutput` moves from
  allowlist-exclusion to denylist on 12 agents (`supervisor` and `execute-manager` already declared
  it); `LSP` on 10 (`launch-pad`, `code-reviewer`, `qa-executor`, `worker` already declared it);
  `WebSearch`/`WebFetch` on 12 (`product-owner` and `red-team-reviewer` already declared them); and
  **`Task` on 9** — the five agents that already declared it (`supervisor`, `execute-manager`,
  `launch-pad`, `qa-executor`, `review-pr`) are unaffected. `Task` is the most consequential of the
  five, since it governs subagent-spawn capability: of those 9, four (`code-reviewer`, `orchestrator`,
  `product-owner`, `red-team-reviewer`) carried **no prior `Task` denylist**, so their spawn block
  moves from allowlist to denylist here; the other five (`context-keeper`, `plan-reviewer`,
  `qa-strategist`, `rubric-grader`, `worker`) already denied it explicitly. The per-agent table above
  is the check: a row omits one of these five exactly when that agent already declared it before this
  change.

---

## Agent Invariants

> Relocated from `CLAUDE.md` §"The 14 Agent Roles" in the v15.21.0 CLAUDE.md diet (content moved,
> never deleted — see `.supervisor/requirements/final-state/09-claude-md-diet-dreaming.md`). This is
> now the authoritative home for the full per-agent invariants, the `/autonomous` orchestration
> shell, the Shared Agent Contract, and the Parallel Execution Model; `CLAUDE.md` keeps only a
> compact 14-row name/type/one-line-purpose list plus a pointer here.

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

## Context Budget Guidelines

| Agent | Max Context | Rationale |
|-------|-------------|-----------|
| Supervisor | ~400 tokens | Pure orchestrator, everything else in state file |
| Execute Manager | ~2k tokens | Poll loop + worker tracking |
| Worker | ~6k tokens | Focused implementation |
| Code Reviewer | ~4k tokens | Read-only analysis |
| Context-Keeper | ~200 tokens | Atomic state ops, < 50 token responses |
| QA Executor | ~8k tokens | Discovery + generation + execution |
| QA Strategist | ~3k tokens | Risk classification |
| Launch Pad | ~5-7k tokens | Discovery + analysis + brief assembly + plan review (~5k typical, ~7k worst-case with 3 review cycles) |
| Product Owner | ~4k tokens | Domain analysis + story writing |
| Orchestrator | ~3k tokens | Task decomposition |
| Plan Reviewer | ~3k tokens | Focused brief validation |
| Rubric Grader | ~2k tokens output; input window scales with diff size (typically 5–50k tokens for a v12.x-style feature branch; larger PRs may need more) | One-shot diff read + per-item scoring; budget is intentionally output-side because the agent emits only N×short justifications plus a single `rubric_score: N/M` line. Input is `git diff origin/main...{branch}` — sized by the feature, not the grader. |
| Red Team Reviewer | ~6k tokens | Deep adversarial analysis |

---

## Hook Performance Rules

- **Prompt hooks:** Execution < 5 seconds, timeout 30 seconds. As of v15.17.0 only three remain (`SubagentStop[loomwright:code-reviewer]`, `Stop`, `TaskCompleted`) — reserve them for genuine judgement; a mechanical check (presence, type, enum membership, cross-field invariants) belongs in a `type: command` script.
- **Command hooks:** the default (21 of 24). Deterministic, zero model tokens. Every one is **exit-0-by-contract** — it signals via stdout JSON, never via exit status — which is what makes the `|| true` convention safe. A *blocking* gate must therefore never be written as a `type: command` hook carrying `|| true`.
- **Agent-based hooks:** Execution < 30 seconds (future)
- No network calls in prompt hooks
- No long file parsing — validate structure, not semantics
- Hooks validate output format, not code correctness

---

## Schema Validation

- **Location:** Per-agent SubagentStop hooks (hook execution layer)
- **Reference:** `docs/RESULT_SCHEMAS.md`
- **Per-agent hooks:** Worker, Execute Manager (SubagentStop in agent frontmatter), Code Reviewer (Stop in agent frontmatter)
- **Cross-cutting hooks:** Code Reviewer, QA Executor, Plan Reviewer (SubagentStop in `hooks.json`)
- **Dual-hook note:** Code Reviewer intentionally has both a per-agent `Stop` hook (validates CODE_REVIEW_RESULT block exists before finishing — completeness gate) AND a cross-cutting `SubagentStop` hook (validates output schema after completion — format gate). These are complementary: Stop catches incomplete reviews, SubagentStop validates structure.
- **Never duplicated** in Supervisor or plugin runtime

---

## State Ownership

| Resource | Owner | Access |
|----------|-------|--------|
| `.supervisor/state.md` | Context-Keeper (sole writer on the parallel path; inline Supervisor writes `## Session` directly) | Supervisor, Execute Manager (read via CK query) |
| `.supervisor/jobs/pending/` | Launch Pad (create) | Supervisor (move to in-progress) |
| `.supervisor/jobs/in-progress/` | Supervisor (move from pending) | Supervisor (move to done/failed); `scripts/reconcile-jobs.sh --repair` (v15.39.0) as a **second, evidence-gated mover** — the completion tail's move is prompt-instructed, so an agent that dies before it strands the brief; the reconciler finishes only a `stranded_merged` / `stranded_closed` brief and never an `unknown` one |
| `.supervisor/jobs/done/` | Supervisor (move from in-progress); `scripts/reconcile-jobs.sh --repair` (v15.39.0) | Read-only after move. `scripts/stamp-requirement-status.sh` READS this dir exclusively to close out the source requirement — which is why a brief stranded in `in-progress/` structurally blocks that reconciler too |
| `.supervisor/jobs/failed/` | Supervisor (move from in-progress) | Read-only after move |
| `.supervisor/logs/` | Supervisor, Execute Manager, Worker | Append-only JSONL |
| `.supervisor/history/` | Supervisor (create) | Read-only after creation |
| `.supervisor/worker-summaries/` | Worker (inline mode) | Execute Manager (read) |
| `.worker-summary.md` (in worktree) | Worker (parallel mode) | Execute Manager (read) |
| `.qa-summary.md` | QA Executor (write) | QA Strategist (read in audit mode) |
| `.supervisor/twin/` | `scripts/write-system-contract.sh` (sole writer) | Readers via `scripts/read-system-contract.sh`; Context-Keeper is OUT of this path |

---

## System Twin homing contract

The **System Twin** maintains a persistent, per-subsystem **System Contract** artifact store under
`.supervisor/twin/`. It is an advisory artifact store in the same family as `.supervisor/memory/`:
**subordinate to the human-authored CLAUDE.md**, propose-only, and NEVER an enforcement boundary.

| Property | Contract |
|----------|----------|
| Store layout | `.supervisor/twin/contracts/<subsystem-id>.md` (one SYSTEM_CONTRACT artifact per subsystem; see `docs/RESULT_SCHEMAS.md` §"SYSTEM_CONTRACT") + `.supervisor/twin/.provenance.jsonl` (hash-chained provenance ledger). |
| **Sole writer** | `scripts/write-system-contract.sh` is the **ONLY** writer of `.supervisor/twin/`. No agent writes the store directly. |
| Builder/reader split | An ephemeral, Bash-capable **builder** writes contracts via `write-system-contract.sh` from a **pinned repo-root CWD — never worktree-relative**. **Readers** (ST2 read-path, ST3 conformance) use `read-system-contract.sh`, the read-side provenance gate that drops un-provenanced / post-chain-break contracts and logs drops to `.supervisor/logs/twin.log`. |
| Context-Keeper is OUT | Context-Keeper is **explicitly NOT in this path**. It remains the sole writer of `state.md` on the parallel path only; it neither writes nor gates `.supervisor/twin/`. |
| Worktree-guard = enforcement | The **real enforcement** of the sole-writer / pinned-CWD contract is the writer's worktree-guard: `write-system-contract.sh` refuses to run from a linked git worktree (where the top-level `.git` is a FILE, not a dir) with **exit 3**. A twin write inside a worktree would diverge and be lost on `git worktree remove`. This mirrors `write-project-memory.sh` (red-team F1). |
| Advisory-subordinate-to-CLAUDE.md | Contracts are propose-only. Any conformance check against them (`SUPERVISOR_RESULT.contract_conformance`) is **advisory only** — it NEVER changes `heal_decision` and NEVER blocks a PR; on conflict, CLAUDE.md wins. |
| Fail-safe | The writer is a safe no-op (exit 0) when no sha256 tool is available; the reader emits nothing and exits 0 in the same case. Writes are atomic (temp + same-filesystem rename inside the twin dir), bounded by a contract-file cap (`SYSTEM_TWIN_MAX_CONTRACTS`, default 200) with write-time eviction, and de-duplicate identical contract bodies. |

`.supervisor/twin/` is covered by the repo's existing `.supervisor/` `.gitignore` entry (the store is
session-local state, not committed). Self-tests live in `scripts/test-system-contract.sh`.

---

## Agent Timeout Rules

| Agent | maxTurns | On timeout |
|-------|----------|------------|
| Supervisor | `maxTurns: 60` (harness ceiling) + internal 50 tool-call budget | Checkpoint and halt |
| Execute Manager | 80 | Return EXECUTE_CHECKPOINT |
| Worker | 40 | Return WORKER_RESULT status=failed |
| Code Reviewer | 40 | Return partial review |
| Context-Keeper | 3 | Fail (caller retries once) |
| Launch Pad | 55 | Return partial brief with LOW confidence |
| Plan Reviewer | 20 | Return partial review |
| Product Owner | 40 | Return partial stories |
| Orchestrator | 40 | Return partial task plan |
| Red Team Reviewer | 60 | Return partial audit |
| QA Strategist | 40 | Return partial risk classification |
| QA Executor | 80 | Return partial QA_RESULT |
| review-pr-runner | 60 | Emit REVIEW_HEAL_RESULT with `decision: ESCALATED` (loop incomplete → escalate, never merge) |

### Standalone review-and-heal loop budget

The standalone PR review-and-heal loop (`/review-pr` + `loomwright:review-pr-runner`) mirrors Supervisor **Phase 4.5** semantics, so its budgets are sized against the existing self-heal / code-reviewer conventions:

| Bound | Value | Rationale |
|-------|-------|-----------|
| Iteration bound | ≤ 3 review→fix→re-review cycles (default) | The `--heal-iterations` analogue; identical default to Supervisor Phase 4.5's `--heal-iterations 3`. On exhaustion with issues remaining, the loop emits `decision: ESCALATED` (never auto-fixes past the bound, never merges). |
| Runner `maxTurns` | 60 | Sized above the code-reviewer's 40 because the runner additionally hosts up to 3 `code-reviewer` reviews plus up to 3 `general-purpose` fix workers in its own session; on timeout it emits `REVIEW_HEAL_RESULT` with `decision: ESCALATED`. |
| Per child `code-reviewer` | inherits the code-reviewer's 40-turn budget | Each review iteration is an ordinary `Task(code-reviewer)` with `review_mode: diff_review`, unchanged from Phase 4.5. |
| Per child `general-purpose` fix worker | bounded fix scope (new+BLOCKING/HIGH only) | Allowlist Read / Write / Edit / Bash / Glob / Grep, **NO Task** (a fix worker may not dispatch further subagents). |
| Per `gh`/`git` invocation | short (~20s soft) | SOFT guideline (same convention as the Phase 1.5 gate below); branch resolution (`gh pr view`), PR comments (`gh pr comment`), and regular pushes (**never `--force`**). |

The loop **NEVER merges a PR** — its terminal `decision` values are `PASS` (clean diff, PR left open for a human), `ESCALATED` (findings posted + best-effort notify, PR left open), and — under `--until-mergeable` only — `READY` (merge-identical to `PASS`/`ESCALATED`; distinguished in the run record by `termination_reason: converged | bound_hit | sub_floor_converged`, none of which are auto-merge-eligible for `sub_floor_converged` — see `automate-loop/SKILL.md` §10 condition 1). Authoritative loop semantics live in `skills/review-heal/SKILL.md`; the `REVIEW_HEAL_RESULT` block is defined in `docs/RESULT_SCHEMAS.md`.

### Fresh-process dispatch contract (post-`/supervisor` auto-review)

The plain-`/supervisor` completion tail hands off to the review-and-heal loop via a fresh OS process **by default** (the AC7 until-mergeable default), opt-out below:

| Property | Value |
|----------|-------|
| Dispatcher | `loomwright/scripts/dispatch-pr-review.sh` (runtime path `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-pr-review.sh`). |
| Dispatch shape | Launches a brand-new detached **headless** `claude -p --agent loomwright:review-pr-runner <pr-url>` operating-system process — a true fresh session where the runner is the main agent and can therefore spawn `code-reviewer` / `general-purpose` children (sidesteps the subagents-cannot-spawn-subagents limit). `-p`/`--print` is required: `--agent` only selects the agent, it does NOT imply headless, and the no-`-p` interactive form can hang when detached with no TTY (mirrors `dispatch-pr-postmortem.sh`). No `--permission-mode` / `--dangerously-skip-permissions` by design — best-effort, relies on the project's existing permission settings. |
| Gating | **Default-ON** after a PASS/normal completion that produced a PR (the AC7 until-mergeable default). Suppressed by `--no-auto-review` OR `.auto_review == false` in `.supervisor/config.json` (legacy `.supervisor/notify-config.json` still read as a fallback; the new path wins when both exist). `auto_review: true` / `--auto-review` are now **redundant legacy explicit-enable signals** (honored, no-op-equivalent). The until-mergeable drain signal itself is opt-out via `--no-until-mergeable` / `.auto_until_mergeable == false` (when opted out the runner runs the plain diff-only `/review-pr`). Cost/runaway-guarded by the dispatcher's per-PR idempotency marker. |
| Failure policy | Fire-and-forget; **always exits 0** — a dispatch failure never fails or blocks the completing `/supervisor` run. |
| `/autonomous` contrast | The `/autonomous` EVALUATE path does NOT use the dispatcher — it chains the review-heal loop body as a Task-spawned step (fresh isolated context, not a nested `claude` process). |
| No-recursion invariant | `/review-pr` operates only on an existing PR URL and never creates a PR, so the auto-dispatch cannot retrigger itself on a PR it just produced. |

### Supervisor Phase 1.5 PRE-FLIGHT SYNC budget

The Phase 1.5 PRE-FLIGHT SYNC gate (remote-state reconciliation, runs after Phase 1 ACQUIRE and before Phase 2 PLAN) is itself a bounded sub-phase inside the Supervisor's 50-tool-call budget:

| Bound | Value | Rationale |
|-------|-------|-----------|
| Tool-call budget | ≤ 6 tool calls | Hard ceiling for the whole gate (`git log`, `gh pr list` + per-PR file listing, classification reads). |
| Marginal cost (common path) | ~2–3 tool calls | Reuses the `git fetch origin "$BASE_BRANCH"` already performed in Phase 1 ACQUIRE, so the CLEAR path adds little; the `unverified` / `--skip-preflight-sync` paths cost less. |
| Per-invocation soft budget | short (~20s per `gh`/`git` invocation) | SOFT design guideline — no native shell-level enforcement; the agent self-limits (or abandons the call) by judgment, e.g. via an explicit Bash `timeout`. On any tooling unavailability, error, or timeout the gate records "pre-flight unverified", emits one warning, sets `preflight_sync = unverified`, and continues — it NEVER hard-blocks on a tooling failure. |

Authoritative gate semantics live in `agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC"; the `preflight_sync` SUPERVISOR_RESULT field and the `preflight_overlap_detected` AUTONOMOUS_RUN status_reason are defined in `docs/RESULT_SCHEMAS.md`.

---

## Stacked Branches (autonomous loop)

**New in v14.0.0** — the `/autonomous` orchestration shell now defaults to
**stacked branches** within multi-iteration runs. This subsection documents
the contract, the two-line-of-defense PR-base verification, and the
out-of-order merge hazard.

### Default semantics (stacked-branches mode)

- **Multi-iteration is the default** in v14 (v13's "default single, opt-in
  multi" flipped). Iter N+1's feature branch is created from
  `iterations[N].branch` (the branch the previous iteration's Supervisor
  produced) rather than from `main`. No merge is required between
  iterations — the next iteration just builds on top.
- The opt-out is `--no-stacked-branches`, which reverts to v13 cadence:
  each iteration branches from `main` and the user must merge the prior
  iteration's PR before the next iteration can run safely.
- The declared base for each iteration is recorded in
  `SUPERVISOR_RESULT.branch_base` (v14.0.0 additive field; see
  `docs/RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT"). When absent OR `null`,
  consumers treat the base as `"main"`.

### Two-line-of-defense PR-base verification

Stacked branches make base-branch correctness load-bearing — if iter N+1
opens its PR against `main` instead of `iterations[N].branch`, the diff
appears to contain iter N's work too, and reviewers will be confused at
best and self-heal will fix the wrong things at worst. v14 verifies the
base at two independent sites with identical retry policy:

1. **Supervisor — Phase 4 self-verify** (first line of defense). After the
   PR is created, Supervisor reads back the PR's actual base via `gh pr view`
   and compares it to the declared `branch_base` from the brief. Mismatch
   triggers Phase 4.5's base-mismatch cleanup (close-and-redo path; surfaced
   via `SUPERVISOR_RESULT.pr_state`). See `agents/supervisor.md` §"Phase 4
   self-verify" and §"Phase 4.5 base-mismatch cleanup".
2. **Autonomous loop — EVALUATE PR-base verification** (second line of
   defense). After Supervisor returns, the loop independently re-reads the
   PR's base via `gh pr view` and compares it against the expected stacked
   parent (`iterations[N-1].branch`). Mismatch triggers the user-prompt-
   and-retry policy (AC-14); terminal abort uses
   `status_reason: "iter_pr_base_mismatch"`. See
   `skills/autonomous-loop/SKILL.md` §"EVALUATE PR-base verification"
   (AC-3 + AC-15).

Both sites use the same `gh` retry policy: transient failures prompt the
user before aborting; explicit user abort surfaces as
`status_reason: "user_aborted_gh_retry"`.

### Out-of-order merge hazard

Stacked PRs MUST be merged **bottom-of-stack first**. Merging iter N+1's PR
before iter N's PR is merged (or rebased onto `main`) silently rewrites
history for downstream tooling and can produce a merge commit that contains
work the user did not intend to ship.

The hazard is **documented, not preventable from inside the plugin** —
GitHub's PR UI does not enforce stack ordering, and the plugin cannot block
a merge that happens out-of-band. Two mitigations are in place:

- **`AUTONOMOUS_RUN.iterations[]` ordering** surfaces the intended merge
  sequence. Reviewers MUST follow this order. The `iterations[]` array is
  ordered by `n` — iter 1, iter 2, ... — and that order IS the merge order;
  there is no separate `merge_order` field on the autonomous-run block.
  See `docs/RESULT_SCHEMAS.md` §"AUTONOMOUS_RUN" for the field shape.
- **`SUPERVISOR_RESULT.pr_state`** (v14.0.0 additive field) records the
  per-iteration PR state after Phase 4.5's base-mismatch cleanup. Downstream
  tooling watching for `"closed_by_loop"` or `"close_attempt_failed"` can
  detect iterations whose PRs were retired and avoid trying to merge them.

### Cross-references

- `agents/supervisor.md` §"Phase 4 self-verify" — first-line PR-base check.
- `agents/supervisor.md` §"Phase 4.5 base-mismatch cleanup" — close-and-redo
  path that populates `pr_state`.
- `skills/autonomous-loop/SKILL.md` §"EVALUATE PR-base verification" and
  §"Signal 1" — second-line PR-base check and the stacked-branch rubric gate.
- `docs/RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT" — `branch_base` + `pr_state`
  field documentation.
- `docs/RESULT_SCHEMAS.md` §"AUTONOMOUS_RUN" — v14 `status_reason` values
  associated with the verification paths.

---

## Worktree Naming Convention

Prevents collisions between parallel workers.

```
Path:    ../{repo}-{task_id}-{slug}
Branch:  feature/{task_id}-{slug}
Example: ../myapp-42-add-auth, branch feature/42-add-auth
```

- WorktreeCreate hook (hooks.json, type: command) logs worktree creation to `.supervisor/logs/worktrees.log`
- Sibling directory (not nested) prevents git issues
- Branch matches worktree slug for traceability

---

## Worker File Change Limits

| Metric | Limit | On exceed |
|--------|-------|-----------|
| Files modified | 25 | Worker must split task, return WORKER_RESULT status=partial |
| Files created | 10 | Worker must split task, return WORKER_RESULT status=partial |

Prevents runaway refactors and reviewer context explosion.

---

## Result Schema Versioning

All result schemas include a `schema_version` field. Current versions: CODE_REVIEW_RESULT at `schema_version: 3` (review modes + consistency audit; v2 accepted for legacy); WORKER_RESULT at `schema_version: 2` (outputs_verified contract; v1 accepted for the v12.0.0 transition window); AUTONOMOUS_RUN at `schema_version: 2` (v14.0.0 status_reason extension; v1 accepted, no hook validation); LAUNCH_PAD_RESULT at `schema_version: 1` (added v14.2.0, validated by `scripts/validate-launch-pad-result.py`); all others at `schema_version: 1`.

1. Hooks verify `schema_version` is supported before validating fields
2. If `schema_version` is unrecognized, hook warns but does not block
3. New fields can be added without breaking existing validation
4. Breaking changes require incrementing `schema_version`

---

## Quantitative Performance Targets

| Metric | Target | Source |
|--------|--------|--------|
| Task pass rate | ≥90% | WORKER_RESULT status=completed |
| First-pass review rate | ≥80% | CODE_REVIEW_RESULT decision=PASS |
| QA coverage | ≥70% routes | QA_RESULT coverage_estimate |
| Worker retry rate | ≤10% | Logs (retry count / total spawns) |
| Merge success rate | ≥95% | Supervisor FINALIZE outcomes |

Tracked in `.supervisor/observations/metrics.jsonl` when learning system is active (v7.0.0+).

---

## Prompt Token Budgets

A CI ratchet on **spawn-time prompt inventory**. Each agent's effective weight is its `.md` prompt **plus every skill preloaded via its frontmatter `skills:` list** (those skills are injected at spawn time). `scripts/check-token-budget.sh` measures that weight and fails the build (exit 1) when it exceeds the agent's declared budget.

> **Proxy, not an exact token count.** The weight is an **offline proxy** — `bytes / 4`, never a call to Anthropic's `count_tokens` API (CI has no network). It therefore controls **prompt inventory growth** (how many words we ship per spawn), **not live tokenizer inflation** (e.g. Opus vs pre-4.7 token ratios) — a byte proxy cannot track tokenizer changes. Every number the gate and this table surface is **proxy tokens**, never an exact Anthropic count.

**Authoritative source:** `loomwright/docs/prompt-token-budgets.json` — the gate reads that JSON; the table below **mirrors** it for humans. On any change, edit the JSON (the table is a doc mirror, like the CLAUDE.md Skills Preloading table).

**Raise rule:** to raise a budget, edit `.agents[<stem>].budget` in `prompt-token-budgets.json` **in the same PR that breaches it** and add a one-line justification to that agent's `note`. Because the gate reads the JSON, every raise shows up in the PR diff and is reviewable. Budgets are a **ratchet against unmeasured growth, not a diet** — shrinking prompts is separate follow-up. Initial budgets (v15.10.0) = measured proxy value + ~10% headroom, so nothing fails at introduction.

| Agent (`loomwright/agents/<stem>.md`) | Budget (proxy tokens) | Measured (proxy tokens — see ¹) | Preloaded skills |
|---|---|---|---|
| `code-reviewer`     | 25131 | 22846¹ | 5 |
| `context-keeper`    | 3818  | 3471¹ | 0 |
| `execute-manager`   | 31400 | 29197¹ | 3 |
| `launch-pad`        | 40254 | 36594¹ | 7 |
| `orchestrator`      | 9558  | 8688¹ | 1 |
| `plan-reviewer`     | 9180  | 6392  | 0 |
| `product-owner`     | 14405 | 13095¹ | 3 |
| `qa-executor`       | 48165 | 43786¹ | 5 |
| `qa-strategist`     | 23488 | 21352¹ | 3 |
| `red-team-reviewer` | 6666  | 6060¹ | 1 |
| `review-pr`         | 31453 | 28875¹ | 2 |
| `rubric-grader`     | 2330  | 1896  | 0 |
| `supervisor`        | 24900 | 22606¹ | 0 |
| `worker`            | 5905  | 4158  | 0 |

¹ **Marks a LIVE re-measure, not the frozen v15.10.0 baseline.** Every ¹-marked cell in the table above carries a figure re-measured at the event named for it below (the unmarked rows — `plan-reviewer`, `rubric-grader`, `worker` — are still the frozen v15.10.0 baseline; the authoritative enumeration of the marked set is the bold paragraph at the end of this section, and the column header deliberately no longer asserts a single version, because most cells are no longer that version's measurement). The marked set has grown several times since this footnote was first written, so it is described here rather than counted. **The first such event, the one-writer-derived-state change (v15.16.0 in progress)** — three cells (`context-keeper`, `execute-manager`, `supervisor`) were re-measured because Subtask 2 of that change deleted prompt-instructed progress-state prose from these agents' `.md`/preloaded skills. Deltas (pre-deletion → post-deletion, both live re-measures, git `36c39de` → `e644d9f`): `context-keeper` 2995 → 2780 (−215); `execute-manager` 25934 → 26357 (**+423, an increase** — a bundled bug fix in the same commit added more prose than the deletion removed); `supervisor` 50459 → 50040 (−419). Budgets for `context-keeper` and `supervisor` were tightened by the same delta (preserving each row's existing safety margin, not reset to a fresh measured+10%); `execute-manager`'s budget was deliberately left unchanged at 28550 since its measured value increased. Full reasoning in each agent's `note` in `prompt-token-budgets.json`. **`context-keeper` re-measured a second time** (PR #116 bot-review fixes, same v15.16.0 in-progress version): reconciling the `initialize`-vs-Session-derivation contradiction added explanatory prose, moving measured 2780 → 3166 (breaching the 2837 budget); raised to 3483 (measured + ~10%) per the raise rule. The `measured` cell/field above reflects this second live re-measure, not the −215 figure from the paragraph above. **`context-keeper` re-measured a third time** (Fix 7 heal iteration 3): marking `record_review` retained-but-uncalled (operations-table row, the `record_review` Details paragraph, and the Unknown-operation error string) added annotation prose, moving measured 3166 → 3471 (leaving only 12 proxy tokens of headroom against the 3483 budget); raised to 3818 (measured + ~10%) per the initial-budget convention, matching the `plan-reviewer` v15.15.0 precedent rather than the compressed-margin convention used for this row's first two re-measures. The `measured` cell/field above reflects this third live re-measure. **`supervisor` re-measured a second time** (PR #116 review-round follow-up, Finding 1): the Phase 1 ACQUIRE idempotent-branch-creation guard (existing-branch detection + safe-reuse-vs-stop decision) plus Finding 2's falsified-claim rewrites moved measured 50040 → 50959 (+919, a real fix, not bloat); budget raised 50802 → 51700 to restore the ~1.5% margin the pre-Finding-1 state held. Full reasoning in `prompt-token-budgets.json`'s `supervisor.note`. **`orchestrator` and `review-pr` are now live re-measures too** (Fix 7, v15.18.0): `orchestrator` re-measured 7877 → 8688 and `review-pr` re-measured 22027 → 25413; `supervisor`'s third re-measure moved 50959 → 51814. **`supervisor` re-measured a fourth time (4f, v15.19.0)** — routing all 7 frontmatter-preloaded skills out of `loomwright:supervisor-runner`'s `skills:` list (see `agents/supervisor.md` §"Preloaded Skill Routing (4f)") moved measured 51814 → 20591, a structural drop rather than an incremental change. **That 20591 was the mid-PR figure**; two later edits in the same PR (the Phase 4.5 heal commit, and a paragraph clarifying that this re-baseline is spawn-time frontmatter weight and NOT a session total) moved it again to **21029**, which is what the `measured` cell/field above now reflects — an end-of-PR live re-measure, deliberately taken after the last prose edit so it could not go stale within its own PR. The 22651 budget is **not** re-raised for that drift (realized margin ~7.7% rather than the ~10% used to derive it): the gate is not breached, 1622 proxy tokens of headroom remain, and re-raising to chase each in-PR edit is the treadmill this frozen-metadata convention exists to prevent.

**Known trade-off, not a benefit — de-batching costs Execute Manager tool-call budget.** The same Subtask 2 deletion retired `record_batch` (alongside `queue_ck_update`/`flush_ck_batch`), converting the Phase 3 poll loop's Context-Keeper updates from one batched call covering N events to a direct per-event `Task(Context-Keeper, …)` call each (`skills/async-orchestration/SKILL.md` §"Poll Loop" — "direct call — de-batched, one call per event"), consuming ≥2 calls per subtask instead of ~1 for the whole batch against Execute Manager's 60-call budget documented above. This is **orthogonal** to the progress-state fix: `record_batch` only ever batched `worker_result`/`review`/`decision`/`error` writes — none of which are `## Session` writes — so retiring it did nothing to address the prompt-instructed-bookkeeping miss rate this change exists to fix, and restoring it would not reopen that gap. Restoring a batch operation scoped to the non-`## Session` sections (`record_worker_result`/`record_review`/`record_decision`/`record_error`) is a reasonable follow-up, but is a larger change than this fix's scope and was not made unilaterally here.

> **Raise log (bot-review round 3, same v15.20.0 PR):** `supervisor` 22651 → 24900 — rewriting §"Adjudication Handling" for the TWO adjudication raisers (the `requires_gap`-vs-`lane_collision` dispatch table, the lane-specific A–D option set, and both apply-the-option branches) moved measured 21029 → 22606, leaving only **45 proxy tokens of headroom**. A real new contract — without it the lane-collision gate was unemittable and would have been adjudicated with the wrong options and the wrong Option-C failure reason — so restored to measured + ~10% per the initial-budget convention rather than a compressed margin, since 45 tokens would strand the next unrelated PR. **Also reconciled in this round:** `execute-manager`'s `measured` field/cell had been left at the v15.16.0 value **26357** while its own note prose asserted **28550** and the live gate computed **29197** — three different numbers for one row. This is a LIVE re-measure row (footnote 1), not a frozen-baseline row, so the cell now carries the end-of-PR live figure 29197; its 31400 budget is NOT re-raised to chase in-PR drift (2203 headroom), per the same anti-treadmill rule applied to `supervisor` in v15.19.0. Note the MEASURED-mirror check added earlier in this PR could not catch this: it compares the JSON field against the table cell, and both were consistently stale.
>
> **Raise log:** `execute-manager` 28550 → 31400 — v15.20.0 (D6) grows both `execute-manager.md` and its preloaded `async-orchestration/SKILL.md` (new §"Context digest pointer" + the `lanes:` paste). The prior value left **0 proxy tokens of headroom** — measured exactly at budget — so any further byte in the agent or any of its 3 preloaded skills would have breached CI. Raised in the same PR that grew them, per CLAUDE.md's rule. (Note: this row was NOT breaching before the raise — the gate takes `floor(bytes/4)` PER FILE then sums (28550); summing bytes first and dividing gives 28551 and falsely reads as a 1-token breach.)
>
> **Raise log:** `rubric-grader` 2086 → 2330 — the shared-agent-prefix block (`loomwright/docs/shared-agent-prefix.md`) added to every agent `.md`; measured 2118 + ~10% headroom per the raise rule. `worker` 4574 → 5045 — same shared block plus the pointer-contract consumer text (bounded-summary + pinned-brief Inputs/Step-1 additions); measured 4586 + ~10% headroom per the raise rule (v15.13.0). `execute-manager` 25941 -> 28550 — the Single-Agent Path pre-merge-gate carve-out grew the preloaded `async-orchestration/SKILL.md`, cutting headroom to 22 proxy tokens; restored to a current re-measure of 25919 + ~10% so this change does not strand the next unrelated PR (v15.15.0). `plan-reviewer` 7032 -> 7750 — the inverted Criterion 4 and its split-reason predicate cross-check; current re-measure 6990 + ~10% (v15.15.0). **Note for both v15.15.0 rows:** the figures above are live re-measures taken at raise time; the `measured` COLUMN in the table and the `measured` field in the JSON remain the frozen v15.10.0 authoring baselines (23582 / 6392) per the frozen-metadata convention, so `budget - measured` is NOT the real headroom **for those two rows** — `execute-manager`'s measured cell/field was subsequently updated to a live value by the v15.16.0 re-measure above; `plan-reviewer`'s (6392) remains frozen. **Four more raises for Fix 7 / item 4 (v15.18.0):** `context-keeper` 3483 → 3818 — marking `record_review` retained-but-uncalled (operations-table row, `record_review` Details paragraph, Unknown-operation error string, all annotated to say the Phase 3 per-subtask reviewer this served was retired); measured 3166 → 3471, leaving only 12 proxy tokens of headroom against the 3483 budget; restored to measured + ~10% per the raise rule (full reasoning in `context-keeper`'s `note` in `prompt-token-budgets.json`, footnote 1 above). `orchestrator` 8665 → 9558 — `agents/orchestrator.md` §"Review Gate Policy" rewritten so no threshold spawns a paired per-subtask LLM review subtask (deterministic `outputs_verified` gate + integrated Phase 4.5 review on both sides) plus a Review Counter-Pressure Rule citation; measured 7877 → 8688 (+811), breaching by 23; restored the same ~10% margin this row has held since authoring (never previously raised). `review-pr` 24230 → 27955 — the new "Earned Fallback Review" subsection (`no_review_lens_posted` trigger, fail-CLOSED-to-running-the-review contract, and the reachability argument for the drain's first-ever `Task(loomwright:code-reviewer)` spawn); measured 22027 → 25413 (+3386, a real new contract, not bloat), breaching by 1183; restored the same ~10% authoring margin. `supervisor` 51700 → 52568 — syncing the Phase 4.5 step 5.5 dispatch prose, the `auto_until_mergeable` default-ON description, and Phase-3 prose to heal-only + the earned fallback; measured 50959 → 51814 (+855), breaching by 114; restored the same ~1.454% margin this row has held since the v15.16.0 restore (741/50959) rather than resetting to a fresh measured+10% (~56995). Full reasoning in each agent's `note` in `prompt-token-budgets.json`. **Three more raises for D6 (v15.20.0, worker shared-context digest + explicit file lanes):** `launch-pad` 34478 → 38673 — Phase 5 PACKAGE gained the unconditional "Context digest emission" step (Subtask 1); current re-measure 35157 + ~10%. `plan-reviewer` 7750 → 9180 — NEW Criterion 16 (Lane Declaration Validation) plus its criteria-count updates across the file (Subtask 4); current re-measure 8345 + ~10%. `worker` 5045 → 5905 — `out_of_lane` reporting + lane-collision semantics text (Subtask 2); current re-measure 5368 + ~10%. All three restore the initial-budget (measured + ~10%) convention rather than a compressed margin; per the frozen-metadata convention, the `measured` column/field for these three rows stays their v15.10.0 authoring baselines — the live re-measure figures above are recorded here and in each agent's `note` in `prompt-token-budgets.json`, not in the `measured` field itself.
>
> **Raise log (write-time-validation, v15.33.0) — the six `memory: project` prompts re-measured together.** The shared `### Agent memory write permission` block landed in ALL SIX `memory: project` prompts, but only `red-team-reviewer` was re-measured at the time (6065 → 6666 budget, measured 5513 → 6060); the other five kept pre-block figures, so five rows advertised a "Measured" number that no longer described the file. Re-measured the same way (the gate's own `bytes / 4` proxy over the agent `.md` plus every frontmatter-preloaded `SKILL.md`), each restored to measured + ~10% per the initial-budget convention: `code-reviewer` 24330 → 25131 (measured 22118 → 22846), `launch-pad` 38673 → 40254 (31343 → 36594), `product-owner` 13807 → 14405 (12551 → 13095), `qa-executor` 47559 → 48165 (43235 → 43786), `qa-strategist` 22877 → 23488 (20797 → 21352). **None of the five was breaching before this raise** — the raise restores the ~10% margin against the current file rather than clearing a failure. All five (and `red-team-reviewer`) are consequently now ¹-marked LIVE re-measure rows rather than frozen v15.10.0 baselines; `launch-pad`'s live figure moved out of its `note` and into the `measured` field, retiring the split that had it recorded in two places. `launch-pad`'s jump is the largest because its 7 preloaded skills also grew since v15.10.0, so its delta is not the memory-permission block alone.
>
> **Raise log (drain-bounding-earned-checks, v15.22.0):** `review-pr` 27955 → 31453 — the preloaded `review-heal` skill's §U4 loop body grew the mechanized shared drain bound (`scripts/drain-rounds.sh` ledger calls replacing the prose-only `rounds`/`while rounds < max_rounds` counter, AC1/AC2) plus the termination-only severity floor (`--severity-floor`, the `sub_floor_converged` terminal state, the SHA-bound confirming required-check pass and its full pseudocode, AC9/AC11/AC12/AC13) — a real new contract, not bloat; measured 25413 → 28593 mid-PR, then 28875 on the end-of-PR live re-measure after syncing `agents/review-pr.md`'s outcome-model restatements (+3462 total), breaching by 638 at the mid-PR figure; the table cell above carries the end-of-PR value. Restored the same ~10% authoring margin per the raise rule.

Self-test: `bash scripts/test-check-token-budget.sh` (offline; pass / breach / missing-preloaded-skill / no-budget / frontmatter-bounded-parsing / empty-agents-dir / inline-flow-style-skills / orphaned-budget / live-repo cases). Wired into CI alongside the other repo-root validators. Skills counted are **frontmatter-preloaded only** — command docs and on-demand skills are not spawn-time weight and are out of scope. The gate also fails CLOSED on an unsupported inline/flow-style `skills:` list (would silently under-count) and on an orphaned budget entry (a budget key with no matching agent `.md`).

**`measured` and the "Preloaded skills" column are frozen, decorative authoring-time metadata, not enforced values, EXCEPT the ¹-marked rows above** (`code-reviewer`, `context-keeper`, `execute-manager`, `launch-pad`, `orchestrator`, `product-owner`, `qa-executor`, `qa-strategist`, `red-team-reviewer`, `review-pr`, `supervisor` — the unmarked rows are `plan-reviewer`, `rubric-grader` and `worker`) — the gate compares live weight only against `budget`; the `measured` column here and in the JSON are authoring snapshots (v15.10.0, or the noted live re-measure for the ¹-marked rows) that the gate never re-derives, and the preloaded-skill counts (also in each JSON `note`) are decorative (the gate computes the live count per run but does not assert it against them). The proxy also sizes the whole `.md`/`SKILL.md` **including frontmatter** — a deliberate, safe over-count for a fail-closed ratchet, not the literal injected system prompt. Do **not** chase or re-bump them each release (same spirit as CLAUDE.md's frozen-example-value convention) — the ¹-marked rows are exceptions tied to specific prompt-change events (v15.16.0's progress-state deletion, and Fix 7's v15.18.0 raises), not a new routine. **`supervisor`'s "Preloaded skills" cell is a second, independently-sanctioned carve-out (4f, v15.19.0): 7 → 0.** Unlike the routine drift this column is normally frozen against, this is a genuine change of the column's *subject matter* — `agents/supervisor.md`'s frontmatter `skills:` list itself was edited (all 7 entries removed; see §"Preloaded Skill Routing (4f)" in that file) — not incidental staleness, so the cell is updated rather than left frozen. **When you raise a budget in `prompt-token-budgets.json`, update this table row in the same edit** — this is machine-enforced: `check-token-budget.sh` asserts every budget cell in this table equals its `.agents[<stem>].budget` in the JSON (drifted, missing, or ghost rows fail CI closed).

---

## Failure Escalation Summary

See `docs/FAILURE_ESCALATION.md` for full paths.

| Agent | Max Retries | Escalation Target |
|-------|-------------|-------------------|
| Worker | 1 | Execute Manager → Supervisor |
| Execute Manager | 1 (fresh spawn) | Supervisor → Human |
| Code Reviewer (FAIL) | 3 | Supervisor → Human |
| Code Reviewer (NEEDS_HUMAN) | 0 | Supervisor → Human (3x = halt) |
| QA Executor | 0 | Partial result (non-blocking) |
| Supervisor | 0 | Human (checkpoint + exit) |
| Context-Keeper | 1 | Degraded mode |
| Plan Reviewer | 0 | Returns result to Launch Pad |
| Launch Pad (Plan Review FAIL) | 3 | Block save, user refines |
| Launch Pad (Plan Review NEEDS_HUMAN) | 0 | User override or refine |

---

## Cost Profiles

Single source of truth for cost-profile model overrides. Referenced by Supervisor and Execute Manager.

### `--cheap` Profile

Applies when `/supervisor --cheap` is passed. Supervisor and Execute Manager apply `model: "sonnet"` at spawn time for the roles marked **sonnet** in the table below. Default behavior (`inherit` for all) is unchanged when the flag is absent.

| Role | Default | `--cheap` override |
|---|---|---|
| worker | inherit | **sonnet** |
| code-reviewer | inherit | **sonnet** |
| execute-manager | inherit | **sonnet** |
| orchestrator | inherit | **sonnet** |
| phase45-fix-task (general-purpose) | inherit | **sonnet** |
| phase45-multi-voter-verification (code-reviewer + red-team-reviewer voter) | inherit | **sonnet** (both voter spawns follow the code-reviewer override; the refute spawn too) |
| supervisor | inherit | inherit (main thread; uses session model) |
| context-keeper | haiku | haiku (already minimal) |
| launch-pad | inherit | inherit (out of v1 scope) |
| product-owner | inherit | inherit (judgment) |
| plan-reviewer | inherit | inherit (gating) |
| qa-strategist | inherit | inherit (gating) |
| red-team-reviewer | inherit | inherit (adversarial creativity; as multi-voter VOTER see the phase45-multi-voter-verification row) |
| qa-executor | inherit | future — not spawned by `/supervisor`; deferred to v2 when `/qa-executor --cheap` ships |

The `phase45-multi-voter-verification` stage exists only when `--multi-voter-heal` is ON (authority: `skills/self-heal-advisory/SKILL.md` Part 2 §Multi-voter verification); when NOT in `--cheap`, Phase 4.5 verification spawns should route at the strongest available session tier — `model: inherit` stays the default everywhere, and no model IDs are hardcoded (Fable-class models are only available when the session itself runs on them).

**Semantics:** `--cheap` overrides roles marked **sonnet** in the table to Sonnet, full stop. No runtime session detection. Consequences:
- Opus session + `--cheap` → roles marked **sonnet** run on Sonnet (intended saving)
- Sonnet session + `--cheap` → roles marked **sonnet** already match; behavior identical to no-flag path
- Haiku session + `--cheap` → roles marked **sonnet** **upgrade** to Sonnet (costs more). Haiku users should not pass `--cheap`.

**Propagation:** `cost_profile` is a session attribute. Supervisor records it in `.supervisor/state.md` (via Context-Keeper `initialize`) and passes it to Execute Manager via the Task prompt. Supervisor applies overrides for Orchestrator, Execute Manager, Phase 4.5 Code Reviewer, and Phase 4.5 fix tasks. Execute Manager reads `cost_profile` from its incoming prompt and applies the override to Worker spawns within the poll loop — Execute Manager no longer spawns a per-subtask Code Reviewer at all; the `--cheap` profile's Code Reviewer override applies only at the Phase 4.5 integrated-review spawn (Supervisor-owned, above), not inside the poll loop.

**Frontmatter unchanged:** No agent's `model:` frontmatter is modified. The override is applied at spawn time via the Task tool's `model` parameter. If the Task `model` override is ever removed in a future Claude Code release, the profile degrades gracefully to `inherit`.

### Async analysis surfaces (v15.13.0)

Default model routing for plugin-invoked **async analysis** spawns — backward-looking, read-only, advisory work where quality tolerance allows a cheaper tier. Verified surfaces only; scope is strictly the REFLECTION-mode spawns listed below.

| Surface | Spawned role (mode) | Default | Override |
|---|---|---|---|
| `/dreaming` Phase 2 | code-reviewer (REFLECTION mode — read-only log analysis) | **sonnet** (spawn-time Task `model` param) | `/dreaming --full-model` → `inherit` |
| `/dreaming` Phase 2 | red-team-reviewer (REFLECTION mode — read-only log analysis) | **sonnet** (spawn-time Task `model` param) | `/dreaming --full-model` → `inherit` |
| `/dreaming` Phase 2 | qa-executor (REFLECTION mode — read-only log analysis) | **sonnet** (spawn-time Task `model` param) | `/dreaming --full-model` → `inherit` |

**Scope guard — reflection-mode rows only:** these rows apply EXCLUSIVELY to the `/dreaming` reflection spawns (backward log analysis that proposes, never gates). They do **not** downgrade code-reviewer in its forward diff-review/gating role, red-team-reviewer as an adversarial auditor or multi-voter VOTER, or qa-executor in forward test execution — those keep the `--cheap` table above as their only routing surface. rubric-grader is already Haiku by frontmatter and needs no row.

**Surfaces verified to spawn NO models today (recorded, no rows):** `/pr-postmortem` is an inline main-thread workflow (script-gathered evidence, no Task spawns) and `/insights` is script-driven (`build-insights.sh`) — neither makes a model spawn, so neither gets a routing row. Re-audit if either ever gains a Task spawn. Batch-API routing remains a documented roadmap note only (`docs/POINTER_AUDIT.md` §Roadmap) — no code path exists on the subscription runtime.

**Mechanism:** `commands/dreaming.md` applies `model: "sonnet"` on each reflection Task spawn unless `--full-model` is passed (then the `model` param is omitted → `inherit`). Same spawn-time mechanism as `--cheap`; no agent frontmatter changes; degrades gracefully to `inherit` if the Task `model` override is ever removed.

---

## Color Legend (Status Line)

| Agent | Color | Hex |
|-------|-------|-----|
| Launch Pad | Gold | `#FFD700` |
| Supervisor | Dodger Blue | `#1E90FF` |
| Execute Manager | Royal Blue | `#4169E1` |
| Context-Keeper | Slate Gray | `#708090` |
| Worker | Lime Green | `#32CD32` |
| Product Owner | Dark Orange | `#FF8C00` |
| Orchestrator | Medium Purple | `#9370DB` |
| Code Reviewer | Light Sea Green | `#20B2AA` |
| Red Team Reviewer | Crimson | `#DC143C` |
| QA Strategist | Tomato | `#FF6347` |
| Plan Reviewer | Medium Turquoise | `#48D1CC` |
| QA Executor | Orange Red | `#FF4500` |

---

## Effort Tier

The `effort:` frontmatter field on each agent maps to an adaptive thinking tier. Tiers communicate intent — Opus 4.7 manages the actual thinking budget adaptively, so explicit `budget_tokens` are no longer required.

| Tier | Agents | Rationale |
|------|--------|-----------|
| `xhigh` | red-team-reviewer | Adversarial deep analysis with persistent memory across audits |
| `high` | code-reviewer, launch-pad, worker, qa-executor, qa-strategist, plan-reviewer | Implementation, exhaustive analysis, or cross-file validation |
| `medium` | supervisor, execute-manager, orchestrator | Pure orchestration / coordination |
| omitted | context-keeper, product-owner | Haiku model (context-keeper) or no thinking budget needed (product-owner) |

### Opus 4.7 Migration Note

- **Adaptive thinking replaces explicit `budget_tokens`.** Earlier configs that pinned an exact thinking budget per agent are now expressed as a tier; the model expands or contracts thinking on its own within that tier.
- **`xhigh` is a new top-level tier above `high`.** Reserve it for agents whose value comes from going deeper than a normal high-effort review — currently red-team-reviewer is the only one in this tier.
- **Tokenizer change — 4.7 uses 1.0–1.35× more tokens than 4.6 for the same input.** Tool-call budgets and `tool_call_count` thresholds in this document were sized against 4.6. Sessions on 4.7 may hit the same RED thresholds earlier in real wall time. **Recommendation:** monitor `tool_call_count` against the thresholds documented in this file and adjust downward if you observe RED triggering earlier than expected. No automatic rescaling is applied.
