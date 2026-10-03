# Supervisor Job: v14.0.0 — `/autonomous` Continuous Mode (Multi-Iter Default + Stacked Branches + Notification Gates)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-05-13, 3 days ago)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
  - **W1:** stale brief from 2026-04-27 (`2026-04-27-v11.2.1-platform-leverage.md`) sits in `.supervisor/jobs/pending/`. The autonomous-loop's `ls`-diff brief-save detection would see this as a pre-existing file. Move it to `.supervisor/jobs/failed/` or `done/` before running any verification step that invokes `/autonomous`.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown agents + bash scripts + jq + gh CLI — all already in use across v11/v12/v13. No new dependencies. |
| 2 | Dependency Availability | GO | `gh`, `jq`, `curl` all present in existing scripts. `Context-Keeper` already runs on Haiku with the proven atomic-write pattern. |
| 3 | Architecture Fit | GO | v13's `/autonomous` skeleton already exists; this revision extends it. Reuses Context-Keeper sole-writer pattern (per CLAUDE.md §"Persistent Memory" and `agents/context-keeper.md`). |
| 4 | Scope vs Supervisor | CAUTION | 16 files across 6 logical groups; total scope is at the upper end of what fits one Supervisor session. Mitigated by 6 well-bounded subtasks with explicit `provides`/`requires` contracts and clean file-overlap separation. |
| 5 | Hard Blockers | GO | None. Stale-brief warning (above) is a one-line `mv` cleanup, not a blocker. |

**Overall Verdict:** GO (with one CAUTION carried into Risk Assessment)

## Task

**Goal:** Implement v14.0.0 of the ai-agent-manager plugin: flip `/autonomous` default from single-iteration to multi-iteration with stacked branches, opt-in webhook notification on gates, Context-Keeper-mediated base-branch mismatch detection with PR cleanup, and CI/non-TTY safety via `--non-interactive-fallback`.

**Problem Statement:**

ai-agent-manager users running `/autonomous` today get one PR per invocation and must manually re-run `/autonomous` for each subsequent iteration, with mandatory merge-and-wait between iterations (the rubric gate requires user merge before iter N+1 because Supervisor branches from `main`). Plus, every interactive gate (Phase 6 save, rubric gate, adjudication) requires the user sit at the terminal — there is no notification path. The user wanted `/autonomous` to behave as "supervised autopilot": loop by default, stack PRs without intermediate merges, and ping via the existing webhook when a gate fires.

This is a v14.0.0 major bump because the default behavior flips. Currently `/autonomous "..."` exits after one PR; in v14 it loops up to `--max-iterations` (default 3, cap 10). Anyone scripting against the v13 single-PR semantics needs to migrate to `--single-iteration`. The change has been red-teamed through four audit rounds; the design is settled (see `~/.claude/plans/review-this-plan-fluffy-pike.md` and conversation rounds 2–5 for the audit trail).

Success looks like: a clean v14.0.0 PR that passes Code Reviewer and Rubric Grader, version manifests match, all 12 file sections from the plan are landed, the W-NEW-3 spike is run before merge to verify Code Reviewer + Rubric Grader honor inline diff-scope directives, and the verification suite (steps 1–14) all pass on smoke tests.

## Acceptance Criteria

- [ ] **AC-1:** Given `/autonomous "..."` is invoked with no mode flags, when INIT runs, then it logs a one-line migration hint about the v14 default change and proceeds in multi-iter mode (default `max_iterations: 3`, capped at 10).
- [ ] **AC-2:** Given `/autonomous "..."` is invoked with `--single-iteration`, when EXECUTE completes, then the loop exits without entering EVALUATE (preserves v13 one-PR behavior).
- [ ] **AC-3:** Given multi-iter mode and a rubric, when iter N+1 starts, then its feature branch is created from `iterations[N].branch` (not `main`) and `gh pr view <iter N+1 PR> --json baseRefName` reports the iter-N branch as the base.
- [ ] **AC-4:** Given Supervisor's Phase 4.5 spawns Code Reviewer + Rubric Grader, when the brief specifies `Base Branch: feature/...`, then both spawned agents receive an explicit prompt directive to use `git diff <BASE_BRANCH>...HEAD` and the iteration-scoped diff is what gets reviewed/scored.
- [ ] **AC-5:** Given `/autonomous "..." --notify` with `AI_AGENT_MANAGER_WEBHOOK_URL` set, when a gate (Phase 6 save, rubric gate, no-rubric gate, adjudication) is about to fire, then a JSON `{event_type: "gate", ...}` payload is POSTed to the webhook URL fire-and-forget, constructed via `jq --arg` (no shell-templated JSON). **Injection-safety sub-test (must pass):** given a requirement containing a single quote, backslash, and embedded newline (e.g., `fix user's "auth" bug\nstep two`), when the gate webhook fires, then the receiver sees a valid JSON document with the `context` field round-tripping the exact input (no truncation, no parse error, no shell-quoting artifacts). All payload-construction sites (autonomous-loop body AND `send-webhook.sh`) use `jq --arg`; no `echo '{…}'` template anywhere in the firing path.
- [ ] **AC-6:** Given `[ ! -t 0 ]` OR `$CI` is set AND multi-iter mode is active AND no `--non-interactive-fallback` flag is passed, when INIT runs, then the loop aborts immediately with `status_reason: "non_interactive_without_fallback"` and a verbose error naming the trigger + two ready-to-paste recovery commands.
- [ ] **AC-7:** Given Supervisor's Phase 4 creates a PR with a base that does not match the `Base Branch` declared in Phase 0, when Phase 4 runs `gh pr view --json baseRefName`, then it invokes `Context-Keeper(operation: set_flag, key: "base_mismatch_detected", ...)` and continues to Phase 4.5; Phase 4.5's completion tail reads the flag, invokes `gh pr close <pr_url>` with an explanatory comment (best-effort, `|| true`), emits a single SUPERVISOR_RESULT with `status: failed, error: "base_branch_mismatch: ...", pr_state: "closed_by_loop"`, and invokes `Context-Keeper(operation: clear_flag, ...)` before returning.
- [ ] **AC-8:** Given Context-Keeper is invoked with `set_flag`/`get_flag`/`clear_flag` operations, when the operation completes, then `.supervisor/state.md` has a `## Phase Flags` section (after `## Checkpoint`) reflecting the requested mutation. `clear_flag` of a key absent → no-op; clearing the last flag removes the section entirely.
- [ ] **AC-9:** Given any existing v13 `SUPERVISOR_RESULT` block (without `branch_base` or `pr_state`), when the existing SubagentStop hook validates it, then validation passes (additive optional fields, schema_version remains 1).
- [ ] **AC-10:** Given `/autonomous "..." --max-iterations 11`, when INIT validates, then it aborts with `status_reason: "invalid_max_iterations"` and an error message documenting the cap rationale.
- [ ] **AC-11:** Given `/autonomous "..." --allow-multi-iteration` is passed, when INIT validates, then a deprecation warning is logged but execution proceeds in multi-iter mode (the default). Given `--allow-multi-iteration --single-iteration` are both passed, then INIT aborts with `status_reason: "conflicting_mode_flags"`.
- [ ] **AC-12:** Given the W-NEW-3 spike runs before merge, when Code Reviewer + Rubric Grader are spawned with a `BASE_BRANCH=feature/spike-test` directive against a stacked fixture, then their transcripts show they invoked `git diff feature/spike-test...HEAD` (NOT `git diff origin/main...HEAD`). If either agent ignores the directive, document the override-resistance in `agents/supervisor.md` Phase 4.5 spawn-prompt section and harden the prompt before merging.
- [ ] **AC-13:** Given `bash scripts/validate-version.sh && bash scripts/check-command-sync.sh` runs after the change, when both scripts exit, then validate-version reports marketplace + plugin manifests at `14.0.0` with the marketplace description mentioning "continuous autonomous mode with stacked PRs", AND check-command-sync exits 0 (no drift between command files and registered slash-commands).

- [ ] **AC-14:** Given Supervisor's Phase 4 calls `gh pr view --json baseRefName` and the first call exits non-zero, when Phase 4 retries, then it sleeps 5s and retries once. On second non-zero exit AND `--non-interactive` flag is set, then Phase 4 invokes `Context-Keeper(operation: set_flag, key: "base_mismatch_detected", value: {expected: <X>, actual: "unknown", reason: "gh_unavailable_non_interactive"})` and continues to Phase 4.5 (no AskUserQuestion fires). On second non-zero exit AND `--non-interactive` is unset (interactive), then Phase 4 fires `AskUserQuestion(retry / skip-verify-once / abort)`: `retry` re-runs `gh pr view` (manual third attempt); `skip-verify-once` records `{phase: "FINALIZE", decision: "user_skipped_base_verify", reason: "gh_unavailable"}` and continues as if verified; `abort` sets `base_mismatch_detected={…, reason: "user_aborted_gh_retry"}` and falls through to Phase 4.5. The identical retry-and-fallback policy applies at the autonomous-loop's EVALUATE PR-base verification site (the second-line-of-defense check).

- [ ] **AC-15:** Given the autonomous-loop reaches EVALUATE with `iteration > 1`, `stacked_branches=true`, AND `pr_url == null` (Supervisor failed before creating a PR, e.g., merge conflict in Phase 4), when EVALUATE's PR-base verification step runs, then the verification is **skipped** (no `gh pr view "null"` call is attempted) and EVALUATE falls through to Signal evaluation, which handles `status: failed` via the default-termination branch with `status_reason: "supervisor_failed_other"`.

## Outcomes Rubric

- The new `set_flag`, `get_flag`, and `clear_flag` operations are documented in `ai-agent-manager-plugin/agents/context-keeper.md` with explicit Parameters / Return / Behavior columns matching the existing operations-table format.
- `ai-agent-manager-plugin/commands/autonomous.md` Parameters table lists `--single-iteration`, `--no-stacked-branches`, `--notify`, `--non-interactive-fallback`, and `--max-iterations` (cap 10); `--allow-multi-iteration` is marked deprecated; `--gate-timeout-minutes` is explicitly NOT shipped in v14 with rationale.
- `ai-agent-manager-plugin/scripts/send-webhook.sh` accepts a `--event-type` flag and the gate path uses `jq` (not shell concatenation) for payload construction.
- `ai-agent-manager-plugin/agents/supervisor.md` Phase 4 FINALIZE contains a `gh pr view --json baseRefName` self-verify block that calls `Context-Keeper(operation: set_flag, key: "base_mismatch_detected", ...)` on mismatch.
- `ai-agent-manager-plugin/agents/supervisor.md` Phase 4.5 SELF_HEAL completion tail invokes `gh pr close $PR_URL` before emitting `SUPERVISOR_RESULT` when `base_mismatch_detected` is set, and emits a `pr_state` field with one of `"closed_by_loop" | "close_attempt_failed"`.
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` shows AUTONOMOUS_RUN at `schema_version: 2` with the new closed `status_reason` values; SUPERVISOR_RESULT documents optional additive `branch_base` and `pr_state` fields at `schema_version: 1`.
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` both show version `14.0.0`.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Context-Keeper flag operations + state-management cross-reference | AC-8 | 2 modify, 0 create | state-management | LAUNCHABLE |
| 2 | `send-webhook.sh` `--event-type gate` support + jq-only construction | AC-5 (partial) | 1 modify, 0 create | error-handling, monitoring-observability | LAUNCHABLE |
| 3 | Supervisor: `--base-branch` + `--non-interactive` + Phase 0 preamble + Phase 4 self-verify + Phase 4.5 cleanup + brief Configuration field | AC-3, AC-4, AC-7, AC-12, AC-14 | 4 modify, 0 create | workflow-management, state-management, async-orchestration | BLOCKED (by #1) |
| 4 | Autonomous-loop protocol updates + `/autonomous` command surface | AC-1, AC-2, AC-5, AC-6, AC-10, AC-11, AC-15 | 2 modify, 0 create | workflow-management, async-orchestration, state-management | BLOCKED (by #1, #2) |
| 5 | Schema bumps + integration docs (RESULT_SCHEMAS, TELEMETRY, ARCHITECTURE_CONTRACTS) | AC-9 | 3 modify, 0 create | (none — doc work) | BLOCKED (by #3, #4) |
| 6 | Top-level docs + version bump + manifests + validate-version run | AC-13 | 4 modify, 0 create | ci-cd | BLOCKED (by #3, #4, #5) |

### Provides / Requires Schema

```yaml
# Subtask 1 — Context-Keeper flag operations (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/agents/context-keeper.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/context-keeper.md", name: "operation: set_flag"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/context-keeper.md", name: "operation: get_flag"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/context-keeper.md", name: "operation: clear_flag"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/state-management/SKILL.md", name: "## Phase Flags"}
requires: []
external_requires: []

# Subtask 2 — send-webhook.sh --event-type gate (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/send-webhook.sh"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/send-webhook.sh", name: "--event-type gate path"}
requires: []
external_requires:
  - "jq >= 1.6 (already a project dependency)"
  - "curl (already a project dependency)"

# Subtask 3 — Supervisor base-branch + non-interactive + Phase 4.5 PR cleanup (BLOCKED by #1)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/commands/supervisor.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/supervisor.md", name: "--base-branch"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/supervisor.md", name: "--non-interactive"}
  - {kind: "file", path: "ai-agent-manager-plugin/agents/supervisor.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "Phase 0 (NEW preamble)"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "Phase 4.5 base-mismatch cleanup"}
  - {kind: "file", path: "ai-agent-manager-plugin/agents/plan-reviewer.md"}
  - {kind: "file", path: "ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md", name: "Base Branch:"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/context-keeper.md", name: "operation: set_flag"}
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/context-keeper.md", name: "operation: get_flag"}
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/context-keeper.md", name: "operation: clear_flag"}
external_requires: []

# Subtask 4 — Autonomous-loop protocol + autonomous.md (BLOCKED by #1, #2)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "INIT step 0 non-interactive detection"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "EVALUATE PR-base verification"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "Signal 1 stacked rubric gate"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "no-rubric gate"}
  - {kind: "file", path: "ai-agent-manager-plugin/commands/autonomous.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "--single-iteration"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "--no-stacked-branches"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "--notify"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "--non-interactive-fallback"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/context-keeper.md", name: "operation: set_flag"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/scripts/send-webhook.sh", name: "--event-type gate path"}
external_requires: []

# Subtask 5 — Schemas + integration docs (BLOCKED by #3, #4)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "AUTONOMOUS_RUN schema_version: 2"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "SUPERVISOR_RESULT.branch_base"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "SUPERVISOR_RESULT.pr_state"}
  - {kind: "file", path: "ai-agent-manager-plugin/docs/TELEMETRY.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/TELEMETRY.md", name: "Gate events (v14+)"}
  - {kind: "file", path: "ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md", name: "Stacked Branches (autonomous loop)"}
requires:
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "Phase 4.5 base-mismatch cleanup"}
  - {from: "4", kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "EVALUATE PR-base verification"}
external_requires: []

# Subtask 6 — Top-level docs + version bump + manifests (BLOCKED by #3, #4, #5)
provides:
  - {kind: "file", path: "CLAUDE.md"}
  - {kind: "symbol", path: "CLAUDE.md", name: "v14.0.0 overview paragraph"}
  - {kind: "file", path: "README.md"}
  - {kind: "symbol", path: "README.md", name: "Stacked PR workflow"}
  - {kind: "symbol", path: "README.md", name: "Running /autonomous in CI / unattended"}
  - {kind: "file", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json"}
  - {kind: "file", path: ".claude-plugin/marketplace.json"}
requires:
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "Phase 0 (NEW preamble)"}
  - {from: "4", kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "--non-interactive-fallback"}
  - {from: "5", kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "AUTONOMOUS_RUN schema_version: 2"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph

```
Subtask 1 (CK flag ops) ─┬─→ Subtask 3 (Supervisor) ──┬─→ Subtask 5 (schemas/docs) ──→ Subtask 6 (top-level docs + manifests)
                         ├─→ Subtask 4 (Autonomous) ──┤
Subtask 2 (webhook) ─────┘                            │
                                                      └─────────────────────────────────────────────────────┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none (Subtask 3 USES Subtask 1's CK ops but does not modify `agents/context-keeper.md`) | NO (Subtask 3 BLOCKED by `requires`, not by file overlap) |
| Subtask 1 | Subtask 4 | none | NO (Subtask 4 BLOCKED by `requires`, not by overlap) |
| Subtask 2 | Subtask 4 | none | NO (Subtask 4 BLOCKED by `requires`, not by overlap) |
| Subtask 3 | Subtask 4 | none — `commands/supervisor.md` vs `commands/autonomous.md` are separate; `agents/supervisor.md` vs `skills/autonomous-loop/SKILL.md` are separate | NO |
| Subtask 3 | Subtask 5 | none | NO (Subtask 5 BLOCKED by `requires`, not by overlap) |
| Subtask 4 | Subtask 5 | none | NO (Subtask 5 BLOCKED by `requires`, not by overlap) |
| Subtask 5 | Subtask 6 | none | NO (Subtask 6 BLOCKED by `requires`, not by overlap) |

### Batch Plan

- **Batch 1:** Subtask 1, Subtask 2 (parallel — both LAUNCHABLE, no deps)
- **Batch 2:** Subtask 3, Subtask 4 (parallel — both unblocked once Batch 1 completes; no file overlap)
- **Batch 3:** Subtask 5 (after Batch 2 — schemas/integration docs must reflect settled Supervisor + autonomous-loop behavior)
- **Batch 4:** Subtask 6 (after Subtask 5 — top-level docs + version bump finalize)
- **Recommended workers:** 2
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/state-management/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md`, `skills/monitoring-observability/SKILL.md` |
| 3 | `skills/workflow-management/SKILL.md`, `skills/state-management/SKILL.md`, `skills/async-orchestration/SKILL.md` |
| 4 | `skills/workflow-management/SKILL.md`, `skills/async-orchestration/SKILL.md`, `skills/state-management/SKILL.md` |
| 5 | (none — documentation-only) |
| 6 | `skills/ci-cd/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **W-NEW-3** spike (Code Reviewer + Rubric Grader honoring inline diff-scope directive) MUST run before merge. **Definition:** spawn Code Reviewer and Rubric Grader against a stacked fixture with the inline directive "compute diffs as `git diff <BASE_BRANCH>...HEAD`, not `git diff origin/main...HEAD`"; inspect each agent's transcript to confirm the literal command line they emit. If either agent ignores the directive (e.g., Code Reviewer's `consistency_audit` auto-expand overrides scope), F1 mitigation re-emerges silently — rubric_score becomes meaningless in stacked mode because Phase 4.5 sees the cumulative stacked diff, not iter N's incremental work. | HIGH | Subtask 3 includes the spike as a hard pre-merge gate (AC-12). If spike fails, harden the spawn prompt with a stronger directive (or downgrade stacked-branch mode to opt-in) BEFORE merging. Do not skip the spike. |
| Stale brief `2026-04-27-v11.2.1-platform-leverage.md` in `.supervisor/jobs/pending/`. The autonomous-loop `ls`-diff brief-save detection in verification step 2 will trip `concurrent_session_detected` if not cleaned up. | HIGH | First action of Subtask 6 (before verification): `mv .supervisor/jobs/pending/2026-04-27-v11.2.1-platform-leverage.md .supervisor/jobs/done/` (or `failed/` if it represents abandoned work). Document the move in the commit message. |
| `state-management/SKILL.md` schema section-ordering is documented but `## Phase Flags` placement (after `## Checkpoint`) is asserted without verifying. If state-management's parser assumes Checkpoint is always last, the new section may break positional reads. | MEDIUM | Subtask 1 verifies during implementation: grep for any code/script that reads state.md by section position. If none found, accept the placement. If positional reads exist, place `## Phase Flags` immediately before `## Checkpoint` (canonical "live state" tail). |
| **W-NEW-10** — LLM-recall residual for BASE_BRANCH and non_interactive across Supervisor phases. **Definition:** Supervisor is a prompt-driven LLM; "remember the base branch / non-interactive context across phases" is not a deterministic guarantee. If the LLM forgets, Phase 4 falls back to interactive prompt behavior (graceful in interactive mode; potential hang in CI mode). **Defense in depth:** (a) Phase 0 preamble echoes both values prominently; (b) Context-Keeper persistence per W-NEW-15; (c) Phase 4 re-reads from Context-Keeper if context is lost. | MEDIUM | Subtask 3 implements the Phase 0 preamble echo lines AND the Context-Keeper-backed `non_interactive` flag (**W-NEW-15** read-once or session-scoped pattern — see next row). Verification 2d asserts the behavior. |
| Stacked PR out-of-order merge corrupts main (C4). Cannot be prevented in the plugin. | MEDIUM | Documented in README "Stacked PR workflow" + AUTONOMOUS_RUN summary lists `merge_order`. Verification 2b exercises this hazard explicitly so the warning matches observed behavior. |
| **W-NEW-14** — Phase 4 emits no SUPERVISOR_RESULT in the base-mismatch path; Phase 4.5's completion tail emits it (preserves one-block-per-task contract that telemetry/webhook hooks at `hooks.json:54-69` depend on). **Crash-recovery defect:** if Supervisor crashes between Phase 4 `set_flag base_mismatch_detected` and Phase 4.5 `clear_flag`, the flag persists in `.supervisor/state.md` into the next session. The next Supervisor task reads the stale flag at Phase 4.5 entry and falsely emits `status: failed, error: "base_branch_mismatch"` for an unrelated task — plus the C-NEW-5 cleanup path closes that task's PR. | MEDIUM | Subtask 3 implements Phase 0 of EVERY session to clear any pre-existing `base_mismatch_detected` flag at session start (read-on-start-clear-on-start pattern): `Context-Keeper(operation: clear_flag, key: "base_mismatch_detected")` is the first state-touching call in Phase 0. Verification 2c includes a "kill mid-Phase-4 then re-run fresh Supervisor" test: the new task must NOT inherit the stale flag. |
| **W-NEW-15** — `non_interactive` flag persisted by the autonomous loop survives an autonomous-loop crash and poisons subsequent standalone `/supervisor` runs. **Symptom:** user invokes `/supervisor` manually in a normal terminal after a crashed `/autonomous` session; Phase 0 reads stale `non_interactive: true`; Phase 4 silently skips the gh-failure user prompt, treating an interactive user as non-interactive and emitting `status: failed` for a recoverable network blip. | MEDIUM | Subtask 3 implements one of two patterns at Supervisor Phase 0: **(option A — read-once semantics)** Phase 0 always invokes `Context-Keeper(operation: clear_flag, key: "non_interactive")` after reading the flag value; the flag is deleted by design after every Phase 0 evaluation. **(option B — session-scoped value)** the autonomous loop stores `{"reason": ..., "set_at": ..., "session_id": "<auto-...>"}` and Phase 0 verifies session_id matches the current loop's session_id (passed via inline prompt); on mismatch the flag is ignored. Recommend option A for simplicity. Verification: kill autonomous loop mid-EVALUATE, run plain `/supervisor` afterward, confirm Phase 0 treats it as interactive. |
| `gh pr close` best-effort failure leaves stale wrong-base PR (C-NEW-5 negative path). | LOW | `pr_state: "close_attempt_failed"` field in SUPERVISOR_RESULT documents the failure for downstream consumers. User-facing impact: one open wrong-base PR per occurrence; user can close manually. Acceptable for v14. |
| `--gate-timeout-minutes` is dropped from v14 (F-NEW-1). CI hangs are prevented only by INIT-time non-interactive detection; once a gate fires in an unattended terminal, the only escape is killing the session externally (corrupts state). | LOW | Documented as a known limitation in `commands/autonomous.md` and the SKILL.md. Users running unattended MUST pass `--non-interactive-fallback`. Future v15 plan addresses the wrapper-process question. |
| Scope vs Supervisor capability — 16 files / 6 subtasks is at the upper end. Risk of Supervisor running out of tool-call budget in EXECUTE if a single subtask balloons. (Phase 2.5 CAUTION). | LOW (mitigated) | Subtask boundaries are pre-chosen for cohesion + minimal file overlap. Recommended workers = 2 (not 3) keeps context overhead bounded. Each subtask's `provides` is bounded to ≤ 4 files. |

## Configuration
- **Base Branch:** main (this is a fresh feature branch from `main`, not a stacked iteration on a prior feature branch)
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 4
- **Note for Phase 4.5:** the F1 mitigation directive ("Code Reviewer + Rubric Grader use `git diff <BASE_BRANCH>...HEAD`") applies once Subtask 3 ships. For this brief's OWN Phase 4.5 (running BEFORE Subtask 3 has fully landed), `BASE_BRANCH=main` and the standard `git diff origin/main...HEAD` applies — equivalent results.
- **Predicted `outputs_gap` site:** Subtask 3 is the heaviest subtask in this brief — it covers Phase 0 preamble + Phase 1 ACQUIRE rewrite + Phase 4 FINALIZE (gh pr create + retry policy + self-verify + Context-Keeper set_flag) + Phase 4.5 SELF_HEAL cleanup (gh pr close + emission) + plan-reviewer Base Branch validation + supervisor-readiness brief field + W-NEW-3 spike execution + AC-12 verification across 4 files. If Phase 3 adjudication fires anywhere in this run, Subtask 3 is the predictable trigger. The brief is structured so Option C ("Exit to Launch Pad") is the right adjudication choice — Subtask 3 can be split into 3a (Phase 0 + Phase 1 + brief field) and 3b (Phase 4 + Phase 4.5 + plan-reviewer + spike) in a re-planned brief. Subtasks 1, 2, 4, 5, 6 should not require splitting.

## Handoff

```
/supervisor job: .supervisor/jobs/pending/2026-05-16-v14-autonomous-continuous-mode.md
```

**Note for the next session (clean context):** before running the Supervisor command above, move the stale `2026-04-27-v11.2.1-platform-leverage.md` brief out of `.supervisor/jobs/pending/`:

```bash
mv .supervisor/jobs/pending/2026-04-27-v11.2.1-platform-leverage.md .supervisor/jobs/done/  # or failed/
```

**Authoritative design source:** the four-round-audited revision-5 plan is referenced via the user's conversation messages. Round 1 findings are persisted at `~/.claude/plans/review-this-plan-fluffy-pike.md`. The plan's verification suite (steps 1–14) is the implementation's acceptance test. Run verification step 2c (Context-Keeper flag flow + `gh pr close` cleanup) and step 9 (CI non-interactive abort) as smoke tests immediately after each subtask completes; defer the full suite to post-Subtask-6 integration testing.

---

## Outcome

- **status:** completed
- **session_id:** v14-20260516-221852
- **branch:** feature/v14-autonomous-continuous-mode
- **pr_url:** https://github.com/vikashruhilgit/ai-agent-manager/pull/12
- **branch_base:** main
- **pr_state:** open
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1 (review-only; no fix loop needed)
- **heal_remaining_issues:** 0 BLOCKING/HIGH `new` (2 LOW advisory drift notes left for follow-up doc PR — see Phase 4.5 review)
- **rubric_score:** 7/7
- **subtasks_completed:**
  - S1 — Context-Keeper flag operations + state-management `## Phase Flags` schema
  - S2 — `send-webhook.sh --event-type gate` with jq-only construction
  - S3 — Supervisor `--base-branch` + `--non-interactive` + Phase 0/4/4.5 stacked-iteration support (W-NEW-3 spike PASS pre-merge)
  - S4 — `/autonomous` multi-iter default + stacked branches + notification gates (worker emitted-design / inline-applied due to permission denial; full design preserved in `.worker-summary.md`)
  - S5 — RESULT_SCHEMAS AUTONOMOUS_RUN v2 + SUPERVISOR_RESULT additive fields + TELEMETRY gate-events + ARCHITECTURE_CONTRACTS stacked-branches
  - S6 — CLAUDE.md / README.md / plugin.json (14.0.0) / marketplace.json (14.0.0)
- **per-subtask review outcomes (all PASS post-fix):**
  - S1: NEEDS_HUMAN → fixed inline (1 MED + 2 LOW)
  - S2: NEEDS_HUMAN → fixed inline (1 HIGH trailing-flag-hang + 1 LOW regex revert)
  - S3: PASS + 1 MED cross-ref fix
  - S4: PASS + 2 LOW doc nits
  - S5: NEEDS_HUMAN → fixed inline (1 MED merge_order misattribution)
  - S6: FAIL → fixed inline (3 BLOCKING + 1 HIGH fabricated status_reason values)
- **W-NEW-3 spike outcome:** PASS — Code Reviewer + Rubric Grader both honored DIFF-SCOPE OVERRIDE on stacked fixture (`feature/spike-test...feature/spike-test-child`); neither fell back to `origin/main`. Fixture cleaned up post-verification.
- **AC-13 final:** `validate-version.sh` EXIT=0 ("Versions match: 14.0.0"); `check-command-sync.sh` EXIT=0.
