# Supervisor Job: Pre-Flight Remote-Sync Gate (State-Aware Supervisor)

> Prepared by Launch Pad on 2026-06-02. Implements the v15 "State-Aware Supervisor With Pre-Flight Sync" item (ENHANCEMENT_PLAN_v15_DRAFT.md), a top "On the Horizon" recommendation in **both** 2026-06-02 Claude Code Insights regenerations (the 13:32 "State-Aware Supervisor With Pre-Flight Sync" card and the 15:24 "Pre-Flight Git State Reconciliation Agent" card), and the root cause of the v13.1.0-vs-v14.0.0 stale-branch incident. Ships as **v14.8.0**.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-06-02)
- **Git:** clean working tree (only untracked `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`), branch: `main`
- **Worktrees:** 1 (main checkout only — no orphans)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Current version:** 14.7.0 → target 14.8.0
- **Blockers:** 0 | **Warnings:** 0

## Task
**Goal:** Add a mandatory **Phase 1.5 PRE-FLIGHT SYNC** gate to the Supervisor that runs *after* task acquisition and *before* Phase 3 spawns any worker. The gate fetches remote state, inspects recent `origin/$BASE_BRANCH` commits and open PRs — flagging recent/in-flight work that **touches the same files** the task will touch and **already-merged equivalents** of the requested work — derives the canonical version/base branch, and classifies the requested work as **CLEAR / OVERLAP / SUPERSEDED** — surfacing overlapping or already-landed work to the human (or failing closed in CI) before tokens are spent on decomposition and execution.

**What this is NOT (scope guard):** Phase 1 ACQUIRE *already* does `git fetch origin "$BASE_BRANCH"` + `git pull` so the feature branch starts fresh (`agents/supervisor.md:211-212`). The existing `supervisor_base_branch_mismatch` path (Phase 4 self-verify → Phase 4.5 cleanup) only checks the *PR's `baseRefName`* against the declared `BASE_BRANCH` — a stacked-iteration mechanic. **Neither detects that the requested *work* overlaps with or is superseded by recent commits / open PRs.** That semantic work-overlap reconciliation is the new behavior; this brief must not duplicate or weaken the existing fetch/pull or the post-hoc base-mismatch path.

## Acceptance Criteria
- [ ] **AC1 (gate runs in the right place + defined signals):** Given a `/supervisor` run completes Phase 1 ACQUIRE with a task and a fresh feature branch, when Phase 1.5 PRE-FLIGHT SYNC runs, then it executes bounded reads — `git fetch origin "$BASE_BRANCH"`, `git log --oneline origin/$BASE_BRANCH -N`, `gh pr list --state open` (with `--json files` or per-PR file listing for the overlap check) — derives the canonical version/base branch, and classifies the task as CLEAR / OVERLAP / SUPERSEDED **before** Phase 2 PLAN spawns the Orchestrator or any worker. The OVERLAP/SUPERSEDED signals MUST include: (a) **same-file overlap** — a recent commit or open PR whose changed files intersect the task's anticipated file set (from the job brief's File Impact Map when present, else the task description); and (b) **already-merged equivalent** — recent `origin/$BASE_BRANCH` history that already implements the requested work (a SUPERSEDED case, e.g. the v13.1.0→v14.0.0 scenario).
- [ ] **AC2 (CLEAR is silent):** Given the gate classifies the task CLEAR, when it completes, then Supervisor proceeds to Phase 2 with no extra prompt and records a one-line pre-flight summary via Context-Keeper (canonical version, base tip SHA, "no overlap").
- [ ] **AC3 (interactive escalation):** Given an OVERLAP or SUPERSEDED classification in an interactive session, when the gate fires, then Supervisor presents an `AskUserQuestion` (proceed-anyway / revise-scope / abort) that cites the specific overlapping commits/PR numbers **and the intersecting file paths**, and does NOT spawn any worker until the user decides. Mirrors the Phase 2.5 feasibility soft-gate pattern.
- [ ] **AC4 (CI fail-closed):** Given `--non-interactive` (or stdin-not-a-TTY) and an OVERLAP/SUPERSEDED classification, when the gate fires, then Supervisor fails closed — aborts with a diagnostic and a dedicated `status_reason` rather than silently proceeding — unless `--skip-preflight-sync` was explicitly passed.
- [ ] **AC5 (escape hatch):** Given `--skip-preflight-sync`, when Phase 1 completes, then Phase 1.5 is short-circuited, the skip is recorded as a deliberate choice (Context-Keeper `record_decision`), and Supervisor proceeds directly to Phase 2.
- [ ] **AC6 (stacked-iteration safe):** Given a stacked-iteration run where `--base-branch` ≠ `main`, when the gate scans for overlap, then it scopes the comparison to `$BASE_BRANCH` and does NOT flag the parent iteration's own commits or PR as overlap (no false positive against the autonomous-loop stacked-PR chain).
- [ ] **AC7 (graceful tooling degradation):** Given `gh` or `git fetch` is unavailable or errors, when the gate runs, then it records "pre-flight unverified", emits one warning, and continues (never hard-blocks on a tooling failure), bounded by an explicit tool-call/timeout budget.
- [ ] **AC8 (CI green + no count drift):** Given the change ships, when CI runs, then `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` pass — version bumped consistently to 14.8.0 across `plugin.json` + `marketplace.json`, and the agent/command/skill/hook counts are unchanged at **13 / 14 / 50 / 19** (no new agent, command, skill, or hook; `--skip-preflight-sync` is a flag, not a command).

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Phase 1.5 PRE-FLIGHT SYNC gate + `--skip-preflight-sync` flag (core) | 2 modify | LAUNCHABLE |
| 2 | Schema + contracts: SUPERVISOR_RESULT field, AUTONOMOUS_RUN status_reason, budgets | 2 modify | BLOCKED (by #1) |
| 3 | Autonomous-loop CI fail-closed + stacked-mode interaction + skill docs | 2 modify | BLOCKED (by #1) |
| 4 | Top-level docs + version bump (CLAUDE.md, README, CHANGELOG, manifests) | 5 modify | BLOCKED (by #1,#2,#3) |

## Subtask Contracts (v12.0.0)

> **Pinned canonical names — defined by Subtask 1 (the gate-semantics owner). Every other subtask consumes these *verbatim* and MUST NOT re-coin them.** This pinning is what lets Subtask 2 and Subtask 3 edit disjoint files in parallel without an enum-string mismatch (RESULT_SCHEMAS.md:~744 mandates that a new `status_reason` updates *both* the schema and `autonomous-loop/SKILL.md` — a shared, fixed name satisfies that rule across two workers):
> - **SUPERVISOR_RESULT field:** `preflight_sync` — enum `clear | overlap_proceed | superseded_proceed | skipped | unverified` | `null` (optional, additive, `schema_version` stays 1).
> - **status_reason (CI fail-closed abort):** `preflight_overlap_detected` — paired with `SUPERVISOR_RESULT.status: failed` and surfaced by the autonomous loop as `AUTONOMOUS_RUN.status_reason: "preflight_overlap_detected"`.

```yaml
subtask_1:   # Core gate
  provides:
    - {kind: symbol, path: ai-agent-manager-plugin/agents/supervisor.md,  name: "Phase 1.5: PRE-FLIGHT SYNC"}
    - {kind: flag,   path: ai-agent-manager-plugin/agents/supervisor.md,  name: "--skip-preflight-sync"}
    - {kind: contract, name: "preflight classification CLEAR|OVERLAP|SUPERSEDED + the two pinned canonical names above"}
  requires: []
subtask_2:   # Schema + contracts
  provides:
    - {kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md,         name: "SUPERVISOR_RESULT.preflight_sync field"}
    - {kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md,         name: "AUTONOMOUS_RUN status_reason: preflight_overlap_detected"}
    - {kind: symbol, path: ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md, name: "Phase 1.5 tool-call budget + timeout"}
  requires:
    - subtask_1   # gate semantics + pinned names
subtask_3:   # Autonomous-loop + skills
  provides:
    - {kind: symbol, path: ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md, name: "EVALUATE termination row for preflight_overlap_detected + CI fail-closed doc"}
    - {kind: symbol, path: ai-agent-manager-plugin/skills/state-management/SKILL.md, name: "Phase 1.5 pre-flight summary recorded in state.md"}
  requires:
    - subtask_1   # gate semantics + pinned names (consumes the pinned status_reason; does NOT coin it)
subtask_4:   # Top-level docs + version
  provides:
    - {kind: artifact, name: "v14.8.0 docs + version bump (CLAUDE.md, README, CHANGELOG, plugin.json, marketplace.json)"}
  requires:
    - subtask_1
    - subtask_2
    - subtask_3
```

## File Impact Map

**Subtask 1 — Core gate (LAUNCHABLE)**
- `ai-agent-manager-plugin/agents/supervisor.md` — MODIFY (HIGH): insert "Phase 1.5: PRE-FLIGHT SYNC" between Phase 1 ACQUIRE (`:188`) and Phase 2 PLAN (`:236`); define bounded actions, CLEAR/OVERLAP/SUPERSEDED classification, soft-gate decision flow, stacked-mode scoping, graceful degradation; add `--skip-preflight-sync` parse in Phase 0 (`:134` area, near the `--base-branch` flag list at `:49`); update the inline phase-list recap (`:911`+).
- `ai-agent-manager-plugin/commands/supervisor.md` — MODIFY (HIGH): add `--skip-preflight-sync` to the flags/parameters table and the ASCII phase diagram.

**Subtask 2 — Schema + contracts (BLOCKED by #1)**
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` — MODIFY (HIGH): add the optional additive `preflight_sync` field to SUPERVISOR_RESULT (`~:210-256`), keeping `schema_version: 1` (additive, hook does not enumerate it — follow the `branch_base`/`pr_state` precedent at `:232-256`); add the **pinned** `preflight_overlap_detected` value to the closed AUTONOMOUS_RUN `status_reason` enum and its narrative block (`~:744-783`; the EVALUATE status table the autonomous-loop worker also extends in Subtask 3 is at `:767-783`). Use the pinned canonical strings verbatim — do not coin new names.
- `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md` — MODIFY (MEDIUM): record the gate's bounded tool-call budget + timeout in the capability/budget tables.

**Subtask 3 — Autonomous-loop + skills (BLOCKED by #1)**
- `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md` — MODIFY (HIGH): **add a row** to the EVALUATE `SUPERVISOR_RESULT.status` → loop-action termination table (`:563-577`) mapping the Supervisor pre-flight fail-closed abort (`status: failed`) to the pinned `status_reason: preflight_overlap_detected` with a defined loop action (terminate) — this is a table-row edit, not prose only. Also document the CI fail-closed behavior and that the pre-flight gate complements (does not double-fire with) the existing EVALUATE PR-base verification + stacked `--base-branch` passthrough (`:209`, `:572`).
- `ai-agent-manager-plugin/skills/state-management/SKILL.md` — MODIFY (MEDIUM): document the Phase 1.5 pre-flight summary that Context-Keeper records in `state.md`. *(Confidence MEDIUM: if the phase-flow is better homed in `supervisor-readiness/SKILL.md`, the worker may relocate — both verified to exist.)*

**Subtask 4 — Top-level docs + version (BLOCKED by #1,#2,#3)**
- `CLAUDE.md` — MODIFY (HIGH): two-most-recent-release banner (move v14.6.0 note to CHANGELOG per the existing rotation rule), Supervisor invariant-row update, phase description. **Also bump the `Plugin manifest: … (v14.7.0)` annotation at `CLAUDE.md:28` → `(v14.8.0)`** — a distinct doc-currency target (the gate checks this prose form; see fix 286bf3e). **Add one line** (Common Pitfalls or the Supervisor invariant row): *never assert git merge/PR state ("on main", "in the PR", "already merged") without verifying via `git log` / `git branch --contains`* — the twice-wrong-merge-claim friction called out in both Insights reports' "fun ending". Keep it to a single line (anti-rebloat); this complements the Phase 1.5 gate (which verifies *before* work) by covering *claims made during* work.
- `README.md` — MODIFY (HIGH): Supervisor phase list / "13 Agents" section.
- `CHANGELOG.md` — MODIFY (HIGH): v14.8.0 entry (+ rotated-out v14.6.0 banner).
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` — MODIFY (HIGH): version `14.7.0` → `14.8.0`; update the `(vX.Y.Z)` string in `description` **in place** (no new clause — anti-rebloat rule); counts unchanged.
- `.claude-plugin/marketplace.json` — MODIFY (HIGH): version `14.7.0` → `14.8.0`; same in-place description rule.

## Parallelism Analysis
- **Batch 1:** Subtask 1 (core gate — establishes the gate semantics every other subtask references)
- **Batch 2:** Subtask 2 ‖ Subtask 3 (parallel — disjoint file sets: RESULT_SCHEMAS+ARCHITECTURE_CONTRACTS vs autonomous-loop+state-management; both depend only on #1)
- **Batch 3:** Subtask 4 (top-level docs + version — depends on final semantics from #1/#2/#3; touches the doc-currency-checked surfaces last so counts/version are consistent)
- **Recommended workers:** 2
- **Overlap note:** Batch 2 is free of *literal* file overlap — Subtask 2 owns `RESULT_SCHEMAS.md` (the canonical enum + field definition) and `ARCHITECTURE_CONTRACTS.md`; Subtask 3 owns `autonomous-loop/SKILL.md` (the consuming EVALUATE table row) and `state-management/SKILL.md`. The one cross-file hazard — both files must agree on the `status_reason` string per RESULT_SCHEMAS.md:~744's "update both files" rule — is removed by **pinning the canonical name in Subtask 1's contract** (see Subtask Contracts). Both Batch-2 workers consume `preflight_overlap_detected` verbatim rather than each coining it, so they stay safely parallel.

## Configuration
- **Base Branch:** main
- **Max workers:** 2
- **Self-heal:** enabled (Phase 4.5 default — strongly recommended; this change touches the Supervisor's own prompt, so the integration review is valuable)
- **Cost profile:** default (inherit) — markdown/prompt-engineering work benefits from the stronger model
- **Suggested command:** `/supervisor job: .supervisor/jobs/pending/2026-06-02-preflight-sync-gate.md`

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Behavioral change to a load-bearing core agent (Supervisor phase flow) | MEDIUM (Feasibility, Phase 2.5 CAUTION) | Soft-gate: "proceed-anyway" always available interactively; `--skip-preflight-sync` escape hatch; CLEAR path is silent so the common case is unchanged. |
| Gate false-positives (flags legitimate non-overlapping work as superseded) → user annoyance | MEDIUM | Classification is advisory; cite specific commits/PRs so the human can judge; never auto-abort interactively. |
| Added latency / tool-call cost per run (`git fetch` + `gh pr list`) | LOW | Bounded budget + timeout (AC7); reuses fetch already done in Phase 1; degrades gracefully on tooling failure. |
| Double-firing or conflict with the existing stacked `--base-branch` / PR-base verification | MEDIUM | AC6 scopes overlap to `$BASE_BRANCH` and excludes the parent iter; Subtask 3 explicitly documents non-overlap with EVALUATE. |
| Doc-currency / version CI gate failure | LOW | AC8 + Subtask 4 bump version consistently and keep counts at 13/14/50/19; no new agent/command/skill/hook. |
| Schema regression for legacy SUPERVISOR_RESULT consumers | LOW | `preflight_sync` is optional + additive; `schema_version` stays 1 (follows the `branch_base`/`pr_state` v14.0.0 precedent). |

## Feasibility (Phase 2.5)
- **Verdict:** GO (1 CAUTION)
- Tech stack: GO — change is markdown agent-prompt/doc engineering, the native medium of this repo.
- Dependencies: GO — uses `git` + `gh`, already pervasive in Supervisor; no new deps.
- Architecture fit: GO — inline Supervisor phase (no new agent/hook), additive schema, soft-gate mirroring Phase 2.5; consistent with CLAUDE.md invariants and the v15 "less-babysitting, don't-weaken-a-gate" principle.
- Scope: GO — 4 subtasks, ~30-60 min each.
- CAUTION: edits the Supervisor's core phase flow → see MEDIUM risk rows above (mitigated by soft-gate + skip flag + silent CLEAR path).

## Handoff
Start a **fresh** Claude Code session (clean context) and run:

```
/supervisor job: .supervisor/jobs/pending/2026-06-02-preflight-sync-gate.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-02
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/24
- **Branch:** feature/preflight-sync-gate (base: main, verified)
- **Files changed:** 13 (+218/-21)
- **Subtasks:** 4/4 completed, 4/4 per-subtask reviews PASS
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1 (integration review NEEDS_HUMAN → auto-fixed 3 drift findings → re-review PASS; + 1 follow-on 7/8-phase label consistency fix)
- **Heal remaining issues:** 0
- **CI:** check-doc-currency ✓ (14.8.0, counts 13/14/50/19), validate-version ✓, check-command-sync ✓
- **Summary:** Added Phase 1.5 PRE-FLIGHT SYNC gate (v14.8.0) across 4 disjoint-file subtasks via inline Supervisor (Execute Manager delegation hit the documented spawn-depth limit, so Phase 3 ran inline on the main thread). Pinned canonical names (preflight_sync, preflight_overlap_detected) consistent across all 13 files. Self-heal (run before PR per operator choice) caught cross-file phase-list/decision-string drift and fixed it.
