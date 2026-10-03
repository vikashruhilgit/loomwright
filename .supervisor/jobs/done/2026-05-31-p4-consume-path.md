# Supervisor Job: P4 — Close the memory consume-path (/dreaming collects candidates + distills bounded LESSONS, writes on approval) [v14.5.0]

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh) | **Git:** clean (untracked ENHANCEMENT_PLAN_v15_DRAFT.md only), branch: main | **gh:** ✓ | **Blockers:** 0 | **Warnings:** 1 (untracked draft — leave alone)

## Task
**Goal:** Close the DISTILL→PROMOTE half of the flywheel. Extend the read-only `/dreaming` command to (1) **collect** worker `WORKER_RESULT.memory_candidates[]` (added v14.4.0, currently consumed by nothing), (2) **distill bounded `LESSONS.md`** (≤3 active per category, scored) and wire to `.supervisor/memory/`, and (3) **write accepted items on per-item approval** via the repo-root sole writers — evolving `/dreaming` from strict propose-only to propose-and-write-on-approval (consistent with Launch Pad Phase 6). Human-gated promotion preserved; no auto-write.

**Problem Statement:** v14.4.0 let Workers PROPOSE `memory_candidates[]`, but nothing collects or promotes them, and there is no reflection→LESSONS path. This closes that gap behind the existing human gate.

## Acceptance Criteria
- [ ] Given recent runs with worker `memory_candidates[]`, when `/dreaming` runs, then it collects those strings (from `.supervisor/worker-summaries/*.md`, `.supervisor/logs/*.jsonl`, `.supervisor/jobs/{done,failed}/` briefs) and surfaces them in a new report section.
- [ ] Given reflection finds durable lessons, when `/dreaming` aggregates, then it proposes `LESSONS.md` entries, category-tagged, **≤3 active per category** (oldest retired on overflow), each labeled PENDING USER APPROVAL.
- [ ] Given the user approves a PROJECT_MEMORY fact or LESSONS entry, when accepted, then `/dreaming` writes it via the repo-root sole writer (`write-project-memory.sh` / new `write-lessons.sh`) — human-gated, never auto. CLAUDE.md + legacy `.claude/agent-memory/` proposals stay paste-to-apply.
- [ ] Given `write-lessons.sh` is invoked from a git worktree, then it refuses (exit non-zero) and writes nothing (red-team F1).
- [ ] Given a category has 3 lessons, when a 4th is written, then the oldest in that category is evicted (≤3 maintained) and the write is atomic (temp + mv).
- [ ] Given no new candidates/lessons, when `/dreaming` runs, then it suppresses no-change output (reports rare + actionable; red-team W3) and writes nothing.
- [ ] Given the change adds capability, when complete, then plugin version is v14.5.0 and `check-doc-currency.sh` + `validate-version.sh` pass.
- [ ] `write-lessons.sh` has a `test-lessons.sh` self-test (worktree-guard, ≤3/category eviction, round-trip, gitignore) that passes.

## Subtask Structure
| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | `write-lessons.sh` bounded LESSONS writer + self-tests | 2 create: `ai-agent-manager-plugin/scripts/write-lessons.sh`, `…/scripts/test-lessons.sh` | LAUNCHABLE |
| 2 | Extend `/dreaming`: collect candidates + LESSONS proposals + write-on-approval | 2 modify: `…/commands/dreaming.md`, `…/agents/worker.md` | BLOCKED (by #1) |
| 3 | Version bump v14.5.0 + doc currency | 4 modify: `…/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `AGENT_GUIDELINES.md` | BLOCKED (by #1, #2) |

## Implementation Notes (binding)
**Subtask 1 — `write-lessons.sh` (new bounded sole writer; mirror `write-project-memory.sh`):**
- CLI: `write-lessons.sh --category "<cat>" --lesson "<text>" [--source "<id>"]`.
- **Worktree guard:** if `git rev-parse --show-toplevel`'s `.git` is a FILE (linked worktree), exit 3, write nothing (F1). Only repo-root callers write.
- Target `.supervisor/memory/LESSONS.md`: top banner, then `## <category>` sections each with `- [<id>] <lesson>` lines. `<id>` = first 8 chars of `sha256(category + " " + lesson)` (detect `sha256sum`/`shasum`; if neither → fail-safe no-op exit 0).
- **Bounding:** ≤3 active per category; on the 4th, evict the OLDEST in that category. Sanitize `--category` to a slug, `--source` of control chars/quotes. Dedup: skip if same `[id]` already under that category (exit 0).
- Atomic: build temp inside `.supervisor/memory/` then `mv`. Exit 0 on safe no-ops; non-zero only on would-corrupt/disallowed.
- **v1 note (comment in script):** LESSONS provenance (hash chain) intentionally NOT added in v1 — lessons are human-approved at write time + bounded; worktree-guard + atomic + per-category bound are the load-bearing safety properties. Provenance parity = possible P5 hardening.
- **`test-lessons.sh`** (mirror `test-project-memory.sh`, isolated temp git repo): (a) worktree-guard refuses + writes nothing [MERGE BLOCKER], (b) round-trip, (c) ≤3/category eviction (4 in one category → 3 remain, oldest gone), (d) two categories independent, (e) `.supervisor/memory/` gitignored. Exit 0 = all pass.

**Subtask 2 — extend `/dreaming` (`commands/dreaming.md`) + tiny `worker.md` note:**
- GATHER: also read `.supervisor/worker-summaries/*.md` and `.supervisor/jobs/{done,failed}/` briefs (read-only) alongside the logs.
- New section **"## 5. Collected Memory Candidates"**: extract worker `memory_candidates[]` from gathered sources; dedup vs existing `PROJECT_MEMORY.md` (via `read-project-memory.sh`); each PENDING USER APPROVAL.
- New section **"## 6. Proposed LESSONS"**: distilled, category-tagged, ≤3 active per category, scored (recall-freq × outcome × diversity — explain inline); read existing `LESSONS.md` to respect the bound; each PENDING USER APPROVAL.
- **Write-on-approval (contract change):** update the read-only contract language — on per-item Accept, `/dreaming` writes accepted PROJECT_MEMORY facts via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-project-memory.sh"` and accepted LESSONS via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh"` (both repo-root, human-gated). CLAUDE.md + `.claude/agent-memory/` proposals stay paste-to-apply. State clearly: still **no auto-write** — every write requires explicit per-item approval. Keep empty-state suppression (W3).
- **APPLY (reading LESSONS back at plan time) is explicitly DEFERRED** to a follow-up — say so; P4 v1 closes collect→distill→persist only.
- `worker.md` (tiny additive note in Step 5.6): "Also echo any `memory_candidates` into your `.worker-summary.md` so a later `/dreaming` pass can collect them." No other worker change; `WORKER_RESULT` schema stays v2.

**Subtask 3 — version + docs:** bump `plugin.json` + `marketplace.json` to `14.5.0` (+ cumulative description clause). CLAUDE.md v14.5.0 banner (collect candidates + bounded LESSONS + /dreaming write-on-approval; APPLY/auto-demote deferred P5; new `write-lessons.sh`; **no new command/agent/skill/hook — still 19 hooks**; WORKER_RESULT stays v2). AGENT_GUIDELINES Memory Core Principle: add LESSONS ≤3/category bound + the /dreaming write-on-approval note. Run `bash scripts/check-doc-currency.sh` + `bash scripts/validate-version.sh` until both pass (fix any extra flagged manifest-annotation files too).

## Subtask Contracts
```yaml
# Subtask 1
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/write-lessons.sh"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-lessons.sh"}
requires: []
external_requires: ["sha256sum or shasum (fail-safe no-op if absent)"]

# Subtask 2
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/dreaming.md", name: "write-lessons.sh"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/dreaming.md", name: "Collected Memory Candidates"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/write-lessons.sh"}
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "14.5.0"}
  - {kind: "symbol", path: "CLAUDE.md", name: "v14.5.0"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/write-lessons.sh"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/commands/dreaming.md", name: "write-lessons.sh"}
external_requires: []
```

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
Subtask 1 ──────────────────→ Subtask 3
```

### Parallelism Analysis
- **Batch 1:** Subtask 1 · **Batch 2:** Subtask 2 (after 1) · **Batch 3:** Subtask 3 (after 1 & 2)
- **Recommended workers:** 1 (fully sequential) · **Estimated batches:** 3

## Skill References
- S1: `skills/state-management/SKILL.md` · S2: `skills/context-summarization/SKILL.md`, `skills/workflow-management/SKILL.md` · S3: doc-currency gate

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| `write-lessons.sh` writing from a worktree (red-team F1) | HIGH | Worktree-guard exit 3 + MERGE-BLOCKER self-test, mirroring write-project-memory.sh. |
| `/dreaming` auto-writing without approval (contract regression) | HIGH | Every write behind explicit per-item Accept; empty-state suppressed; reviewer verifies no bulk/auto path. |
| Unbounded LESSONS growth (drift) | MEDIUM | ≤3 active per category, oldest-evicted, self-tested. |
| Secrets in candidates/lessons | MEDIUM | "Never secrets/PII/tokens" rule; durable structural facts only. |
| Scope creep into APPLY / auto-demote | MEDIUM | Explicitly deferred (follow-up / P5), documented. |
| Version-claim drift | LOW | doc-currency gate CI-enforced; Subtask 3 runs it. |

## Configuration
- **Workers:** 1 | **Mode:** sequential | **Estimated batches:** 3

## Feasibility (Phase 2.5)
| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash + markdown; no new deps |
| 2 | Dependency Availability | GO | read/write-project-memory.sh shipped; /dreaming exists |
| 3 | Architecture Fit | GO | Extends /dreaming per plan §4.3; reuses P2b sole-writer/worktree-guard pattern |
| 4 | Scope vs Supervisor | GO | 3 bounded subtasks |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** GO

## Plan Review
- **Decision:** PASS (attempt 1/3) — all 13 criteria, 0 issues.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-05-31-p4-consume-path.md

## Outcome
- **Status:** completed
- **PR:** #20
- **Branch:** feature/v14.5.0-consume-path (base: main)
- **Subtasks completed:** 3/3
- **Phase 4.5 self-heal:** heal_decision=PASS, 1 LOW (em-dash) fixed inline
- **Version:** 14.5.0
