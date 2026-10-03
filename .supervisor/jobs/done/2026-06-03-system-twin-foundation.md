# Supervisor Job: System Twin — Foundation Slice (all 3 pillars, thin vertical)

> Plan Review: **PASS (v2)**, then **revised v3** after an external second-opinion review (5 findings, all valid).
> Date: 2026-06-03 · Slug: system-twin-foundation
> **v3 changes:** (F1) accurate git state + commit-draft-before-run gate; (F2) `.supervisor/twin/` is written by a
> **script** (`write-system-contract.sh`, mirroring the shipped `write-project-memory.sh`), NOT Context-Keeper —
> Context-Keeper owns `state.md` only and is removed from this path; (F3) read path depends on a read helper, not a
> write op; (F4) hard-signal fields bound to exact `SUPERVISOR_RESULT` + JSONL log schemas; (F5) trigger anchored to the
> SELF_HEAL completion tail on the integrated feature-branch diff.
> Path-convention note: ST1–ST4 use plugin-relative paths under `ai-agent-manager-plugin/`; ST5 spans the wrapper root
> and the nested plugin manifest.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager (the plugin's own repo)
- **CLAUDE.md:** ✓ Found, fresh (v14.7.0)
- **Git:** branch `main`, **1 commit behind `origin/main`** (fast-forwardable). No staged/modified tracked files, but
  **untracked:** `.claude/` and `ai-agent-manager-plugin/docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`.
- **GitHub CLI:** ✓ Authenticated (`vikashruhilgit`)
- **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 2
- **legacy_brief:** false

### ⚠️ Pre-run requirements (do BEFORE `/supervisor`)
1. **`git pull`** — fast-forward `main` to `origin/main`; both briefs branch from `main` and must build on the latest base.
2. **Commit `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md`** — this brief references it, and **untracked files do NOT propagate
   into git worktrees** where workers run (v15 draft §3.1 divergence). A worker would otherwise fail to find it.
3. **Decide `.claude/`** — gitignore `settings.local.json` (machine-local, contains `Bash(*)`); commit-or-ignore
   `agent-memory/` per your call. Not required for this run, but keeps the tree honest.

## Vision (North Star — context, not executable scope)
Evolve the plugin from a stateless task-runner into a **System Twin**: a persistent, agent-maintained, executable model of
the user's codebase, delivering **three integrated pillars** — (1) **Predict-before-touch**, (2) **Provable-done**,
(3) **Compounding-expertise**. The moat is the accumulated, project-specific model the platform structurally won't build and a
competitor can't copy. This brief delivers the **foundation slice**: one thin vertical exercising *all three pillars at once*,
on the plugin's own repo, additive and reversible. Full pillar build-out is a documented multi-increment roadmap, **out of scope** here.

## Task
**Goal:** Seed the System Twin with a per-subsystem **System Contract** artifact and thread it through all three pillars in
miniature: Launch Pad reads it to *predict* blast radius; Supervisor Phase 4.5 *verifies* the integrated feature-branch diff
against it and a minimal benchmark provides a *hard* outcome signal; the flywheel's MEASURE (via `/insights` and `/dreaming`)
consumes contract-conformance + benchmark delta instead of relying only on the soft `rubric_score`.

**Writer ownership (the sole-writer contract):** `.supervisor/twin/` is an artifact store like `.supervisor/memory/`. It is
written **exclusively** by `scripts/write-system-contract.sh` (atomic temp+rename, bounded, provenance — mirroring the shipped
`scripts/write-project-memory.sh`), invoked **only** by an ephemeral Bash-capable **builder** Task from a **pinned repo-root CWD**
(never worktree-relative). **Context-Keeper is NOT in this path** — it remains the sole writer of `state.md` only; the twin store
is owned by the writer script. Reads go through `scripts/read-system-contract.sh` (or direct Read). Everything **propose-only /
advisory-subordinate-to-CLAUDE.md**; nothing self-applies.

## Acceptance Criteria
- [ ] **Foundation:** Given the SELF_HEAL completion tail runs after Phase 4.5 on the **integrated feature-branch diff**
  (`git diff origin/main...HEAD`), then an ephemeral Bash-capable builder derives a structured System Contract (invariants,
  dependencies, behavioral specs, provenance) for each touched subsystem and writes it via `scripts/write-system-contract.sh`
  to `.supervisor/twin/` from the pinned repo-root CWD. The script is the **sole writer**; Context-Keeper is uninvolved.
- [ ] **Pillar 1 (Predict):** Given a System Contract exists for a subsystem, when Launch Pad runs Phase 3 ANALYZE on a goal
  touching it (reading via `scripts/read-system-contract.sh`), then the brief includes a **blast-radius/impact prediction**
  from the contract's dependency graph (advisory; absent contract → graceful fallback to today's behavior).
- [ ] **Pillar 2 (Prove):** Given an integrated feature-branch diff in Phase 4.5, when self-heal runs, then the change is
  checked for **contract-conformance** (violations → advisory findings) AND a **minimal benchmark harness** runs; both results
  are written as the additive `SUPERVISOR_RESULT.contract_conformance` + `SUPERVISOR_RESULT.benchmark_result` fields **and**
  emitted to `.supervisor/logs/{session}.jsonl` in the field shape defined by ST1.
- [ ] **Pillar 3 (Compound):** Given those fields in `SUPERVISOR_RESULT` and the JSONL log, when MEASURE runs, then
  `build-insights.sh` aggregates them deterministically, `/insights` surfaces the hard-signal trend, and `/dreaming` reads
  contract drift as a DISTILL input. **rubric-grader is extended ONLY to REPORT** contract-conformance/benchmark delta as
  advisory lines — it never changes `heal_decision` and never blocks the PR. The flywheel keys on the hard signal *in addition
  to* `rubric_score`, never replacing the human gate.
- [ ] **Guardrails:** No Twin write is self-applied without the existing human gate; `write-system-contract.sh` is the sole
  writer of `.supervisor/twin/` (run only by the builder, pinned repo-root CWD); all new scripts ship a self-test; doc-currency passes.

## Subtask Structure

### ST1 — Twin foundation  [blocks all]
**Files:** `docs/RESULT_SCHEMAS.md` (modify), `docs/ARCHITECTURE_CONTRACTS.md` (modify),
`scripts/write-system-contract.sh` (create), `scripts/read-system-contract.sh` (create), `scripts/test-system-contract.sh` (create).
**Work:** In RESULT_SCHEMAS.md add (a) the `SYSTEM_CONTRACT` artifact schema, (b) the additive `SUPERVISOR_RESULT.contract_conformance`
+ `SUPERVISOR_RESULT.benchmark_result` field definitions, and (c) the matching `.supervisor/logs/{session}.jsonl` event/field shape
that `build-insights.sh` reads (so the hard signal is deterministic end-to-end). In ARCHITECTURE_CONTRACTS.md add the Twin homing
contract: `.supervisor/twin/` artifact store, **`write-system-contract.sh` = sole writer**, builder/reader split, pinned repo-root
CWD (never worktree-relative), Context-Keeper explicitly out of scope. Create `write-system-contract.sh` (mirrors
`write-project-memory.sh`: atomic, bounded, provenance), `read-system-contract.sh` (read helper for ST2/ST3), and
`test-system-contract.sh` (round-trip write+read self-test, mirrors `test-project-memory.sh`).
```yaml
provides:
  - {kind: file, path: docs/RESULT_SCHEMAS.md, name: SYSTEM_CONTRACT_schema}        # SYSTEM_CONTRACT artifact schema
  - {kind: contract, path: docs/RESULT_SCHEMAS.md, name: hard_signal_field_contract} # SUPERVISOR_RESULT.contract_conformance + .benchmark_result + JSONL log fields
  - {kind: file, path: docs/ARCHITECTURE_CONTRACTS.md, name: twin_homing_contract}
  - {kind: file, path: scripts/write-system-contract.sh, name: twin_writer}
  - {kind: file, path: scripts/read-system-contract.sh, name: twin_reader}
  - {kind: file, path: scripts/test-system-contract.sh, name: twin_selftest}
requires: []
```

### ST2 — Pillar 1 read-path  [dep ST1]
**Files:** `agents/launch-pad.md` (modify).
**Work:** Launch Pad Phase 3 ANALYZE reads the relevant System Contract via `read-system-contract.sh` (if present) and emits a
blast-radius/impact prediction section; graceful fallback when absent.
```yaml
provides:
  - {kind: capability, path: agents/launch-pad.md, name: blast_radius_prediction}
requires:
  - {kind: file, name: SYSTEM_CONTRACT_schema, from: ST1}
  - {kind: file, name: twin_reader, from: ST1}
```

### ST3 — Pillar 2 prove + hard signal  [dep ST1]
**Files:** `agents/supervisor.md` (modify), `agents/execute-manager.md` (modify), `scripts/run-benchmark.sh` (create),
`scripts/test-benchmark.sh` (create), small benchmark corpus dir under `scripts/` (create).
**Work:** In Phase 4.5, contract-conformance check on the **integrated feature-branch diff** (`git diff origin/main...HEAD`) →
advisory findings. In the **SELF_HEAL completion tail** (not GitHub-PR-merge), spawn the ephemeral Bash-capable builder that
derives the contract and runs `write-system-contract.sh` from the pinned repo-root CWD. Add the minimal deterministic benchmark
harness + self-test. Write `contract_conformance` + `benchmark_result` into both `SUPERVISOR_RESULT` and the JSONL log per ST1's
`hard_signal_field_contract`.
```yaml
provides:
  - {kind: capability, path: agents/supervisor.md, name: phase45_contract_verify}
  - {kind: capability, path: agents/supervisor.md, name: completion_tail_twin_update}
  - {kind: file, path: scripts/run-benchmark.sh, name: benchmark_harness}
  - {kind: file, path: scripts/test-benchmark.sh, name: benchmark_selftest}
requires:
  - {kind: file, name: SYSTEM_CONTRACT_schema, from: ST1}
  - {kind: contract, name: hard_signal_field_contract, from: ST1}
  - {kind: file, name: twin_writer, from: ST1}
```

### ST4 — Pillar 3 measure-path  [dep ST1]
**Files:** `agents/rubric-grader.md` (modify), `commands/insights.md` (modify), `scripts/build-insights.sh` (modify),
`commands/dreaming.md` (modify).
**Work:** rubric-grader **REPORTS** `contract_conformance` + `benchmark_result` as advisory lines (no gate change);
`build-insights.sh` aggregates the hard-signal JSONL fields defined by ST1; `/insights` surfaces the trend; `/dreaming` reads
contract drift as a DISTILL input. Consumes ST1's `hard_signal_field_contract` — does NOT depend on ST3's runtime, so it runs in
parallel with ST3.
```yaml
provides:
  - {kind: capability, path: commands/insights.md, name: hard_signal_trend}
  - {kind: capability, path: commands/dreaming.md, name: contract_drift_distill}
  - {kind: capability, path: agents/rubric-grader.md, name: contract_conformance_report}
requires:
  - {kind: contract, name: hard_signal_field_contract, from: ST1}   # exact SUPERVISOR_RESULT + JSONL fields to aggregate
```

### ST5 — Docs, version, currency  [dep ST1-4]
**Files:** `CLAUDE.md` (modify), `README.md` (modify), `ai-agent-manager-plugin/.claude-plugin/plugin.json` (modify),
`.claude-plugin/marketplace.json` (modify), `CHANGELOG.md` (modify).
**Work:** CLAUDE.md banner; README section; version bump + in-place description count refresh on both manifests; CHANGELOG entry;
ensure the **repo-root** `scripts/check-doc-currency.sh` passes — note this gate lives at the wrapper repo-root `scripts/`, NOT the plugin's `ai-agent-manager-plugin/scripts/` (new Twin scripts are self-tested and excluded from the gate per existing convention).
```yaml
provides:
  - {kind: capability, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: capability, name: blast_radius_prediction, from: ST2}
  - {kind: capability, name: phase45_contract_verify, from: ST3}
  - {kind: capability, name: hard_signal_trend, from: ST4}
  - {kind: file, name: twin_writer, from: ST1}
```

## Parallelism Analysis
- **Batch 1:** ST1 (foundation — everything depends on it)
- **Batch 2:** ST2 ∥ ST3 ∥ ST4 (disjoint files; ST4 requires only ST1's field contract, not ST3's runtime)
- **Batch 3:** ST5 (docs/version — after all)
- **Recommended workers:** 3

## Skill References
- **ST1:** `skills/state-management/SKILL.md` (artifact/store conventions), `skills/quality-checklist/SKILL.md` (self-test gate)
- **ST2:** `skills/supervisor-readiness/SKILL.md` (brief/impact estimation), `skills/quality-checklist/SKILL.md`
- **ST3:** `skills/quality-checklist/SKILL.md`, `skills/playwright-e2e/SKILL.md` (benchmark execution reference), `skills/async-orchestration/SKILL.md` (completion-tail handoff)
- **ST4:** `skills/quality-checklist/SKILL.md`
- **ST5:** `skills/claude-md-validation/SKILL.md` (doc currency), `skills/quality-checklist/SKILL.md`

## Risk Assessment

| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| Full 3-pillar vision exceeds one Supervisor run | HIGH | Feasibility 2.5 | Scope is the foundation slice only; vision fenced as North Star |
| "Verify against running app" has no running app in *this* repo | HIGH | Feasibility 2.5 | Provable-done = script self-tests + minimal benchmark + doc-currency; generic user-project app-execution deferred |
| Referenced v15 draft is untracked → invisible in worktrees | HIGH | External review F1 | Pre-run gate: commit the draft before running (untracked files don't reach worktrees) |
| Writer-ownership ambiguity (script vs Context-Keeper) | HIGH | External review F2 | `write-system-contract.sh` is the sole writer (mirrors `write-project-memory.sh`); Context-Keeper removed from this path |
| Hard signal not deterministically readable by insights | MED | External review F4 | ST1 binds `contract_conformance`/`benchmark_result` to exact `SUPERVISOR_RESULT` + JSONL fields |
| "post-merge" ambiguity | MED | External review F5 | Anchored to SELF_HEAL completion tail on integrated feature-branch diff (`git diff origin/main...HEAD`) |
| Compounding payoff hard to prove in one PR | MED | Feasibility 2.5 | Benchmark harness makes the hard signal observable from day one |
| Twin artifact poisoning / self-trust | MED | v15 draft §7 | Propose-only, provenance, advisory-subordinate-to-CLAUDE.md, never self-applies gates/agents |
| Anti-rebloat (new commands/agents) | LOW | CLAUDE.md discipline | Zero new commands; no new permanent agent (builder is an ephemeral Task) |

## Configuration
- **Mode:** parallel (3 workers) · **Cost profile:** default · **Branch:** `feature/system-twin-foundation`
- **References:** `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md` (knowledge-axis plan this extends — §0d flywheel, §3 memory homing, §3.1 worktree-divergence/script-writer precedent); `docs/IMPROVEMENTS_ROADMAP.md` → "P2 — Strategic Improvements" → "Differentiate from `/batch`".

## Handoff
```
# After: git pull  AND  committing the v15 draft
/supervisor job: .supervisor/jobs/pending/2026-06-03-system-twin-foundation.md --base-branch main
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-04T07:15:04Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/26
- **Branch:** feature/system-twin-foundation
- **Files changed:** 30
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Rubric:** null (no Outcomes Rubric in brief)
- **Summary:** System Twin foundation (ST1-ST5) merged into feature branch; v14.10.0. Integration review PASSED first-pass; all 4 self-tests + 3 CI gates green. Bootstrapping run — Twin builder/benchmark/conformance take effect on future runs.
