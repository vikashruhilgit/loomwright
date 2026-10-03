# Supervisor Job: Fix the post-PR review-drain dispatch on the inline `/supervisor` & `/autonomous` paths

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — documents v14.36.0, matches plugin.json)
- **Git:** clean, branch: feature/phase4-churn-ledger (⚠ a feature branch — see Risk Assessment; this job targets `Base Branch: main`)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (planned on a non-main branch; co-touches `agents/supervisor.md` with open PR #69)

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash hook + markdown agent/skill prompts + jq; matches existing scripts/ + agents/ conventions |
| 2 | Dependency Availability | GO | jq, gh, git present |
| 3 | Architecture Fit | GO | Reuses existing hook / state-management / autonomous-loop machinery; preserves the bimodal fail-safe invariant (side-effect emitters always exit 0) |
| 4 | Scope vs Supervisor Capability | GO | 4 subtasks of 30–60 min each |
| 5 | Hard Blockers | GO | None. CAUTION: co-touches `supervisor.md` with the still-open PR #69 (Phase 4) — merge interaction, see Risk Assessment |

**Overall Verdict:** GO

## Task
**Goal:** Make the post-PR `until-mergeable` review drain reliably auto-dispatch on the inline `/supervisor` and `/autonomous` paths by fixing the two root causes diagnosed against PR #67 + the autonomous loop.

**Problem Statement:**
Plugin maintainers need the post-PR review drain to fire automatically when a plugin-orchestrated PR is created, because today it silently does not on the inline paths. Two independent root causes were diagnosed (with direct evidence + a faithful hook simulation) during PR #69's session:

1. **PR #67's `PostToolUse[Bash]` hook backstop is inert on the inline path it was built for.** Its session-scope gate term (iii) greps `.supervisor/state.md` for a lowercase `^- branch:` line, but the inline `/supervisor`/`/autonomous` path does not maintain canonical `state.md` (Context-Keeper, the canonical lowercase writer, is not spawned inline) — so on disk `state.md` is either **stale** (left from the prior session) or written in the **bold `- **Branch:**`** summary style, neither of which the hook can parse. Term (iii) fail-closes → the drain never dispatches. (The hook's own self-test masked this by synthesizing a canonical lowercase `## Session` fixture that the inline path never actually produces.) The same bold-vs-lowercase divergence also breaks `/supervisor --continue` resume on inline runs (resume reads lowercase `status: running`).
2. **`/autonomous --single-iteration` runs no post-PR drain at all.** The autonomous EXECUTE enumeration of Supervisor Phase 4.5 stops at "Rubric Grader" and **omits step 5.5** (the until-mergeable dispatch); the loop's own post-PR review-heal lives in **EVALUATE**, which is **short-circuited in single-iteration mode** (and is diff-only even in multi-iteration). Net: single-iteration `/autonomous` gets neither Supervisor's step-5.5 drain nor its own EVALUATE review-heal — whereas direct `/supervisor` dispatches step 5.5 unconditionally.

Currently, direct `/supervisor` "works" only because its agent runs step 5.5 in-prompt; the hook that is supposed to make this robust has, to date, never been observed to dispatch on a real run. Success looks like: an inline `/supervisor` or `/autonomous` PR creation reliably triggers the drain via the hook (format/staleness-robust) AND single-iteration `/autonomous` reaches a post-PR drain step.

## Acceptance Criteria
- [ ] Given an inline `/supervisor` (or `/autonomous`) run reaches Phase 1 ACQUIRE, when the feature branch is created, then `.supervisor/state.md` carries the **canonical lowercase `## Session` block** (`- status: running`, `- branch: <feature-branch>`) on disk — written on the inline path, not only via a Context-Keeper spawn — and the completion tail flips it to `- status: completed`.
- [ ] Given `.supervisor/state.md` in **either** the canonical lowercase (`- branch:`) **or** the bold (`- **Branch:**`) format, when `hook-dispatch-on-pr-create.sh` evaluates term (iii) and the branch matches the current branch, then it resolves the session branch and dispatches; given the branch does NOT match (or is genuinely unresolvable in both formats), it fail-closes and exits 0 (anti-hijack preserved).
- [ ] Given `hook-dispatch-on-pr-create.sh`'s self-test, when it runs, then it exercises a **bold-format** `state.md` fixture (the real inline-produced shape) AND a branch-mismatch case AND the existing stale-state cases — not only the synthetic canonical fixture — and all assertions pass.
- [ ] Given `/autonomous` in **single-iteration** mode produces a PR, when EXECUTE completes, then a post-PR until-mergeable drain is dispatched (via Supervisor Phase 4.5 step 5.5, which the autonomous EXECUTE no longer suppresses), reaching parity with direct `/supervisor`; the multi-iteration stacked-mode behavior (inline EVALUATE review-heal + the R9 wait-before-stacking note) is documented and unchanged.
- [ ] All fail-safe invariants preserved: the hook still ALWAYS exits 0; the state.md write and drain dispatch never gate, never change `heal_decision`, never block the PR/run.
- [ ] New/updated self-tests pass; `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` green; version bumped; CLAUDE.md banner + CHANGELOG entry added.

## Outcomes Rubric
- `hook-dispatch-on-pr-create.sh` term (iii) (and term (ii) status) match BOTH `^- branch:`/`^- status:` AND `^- \*\*Branch:\*\*`/`^- \*\*Status:\*\*` (bold) forms.
- `test-hook-dispatch-on-pr-create.sh` contains a fixture that writes `state.md` in the bold `- **Branch:**` format and asserts the gate resolves the branch from it.
- `agents/supervisor.md` Phase 1 ACQUIRE writes a canonical lowercase `## Session` `- branch:`/`- status:` block to `.supervisor/state.md` on the inline path (not only through Context-Keeper).
- `skills/autonomous-loop/SKILL.md` EXECUTE no longer omits Supervisor Phase 4.5 step 5.5 — it explicitly states step 5.5 runs in the inline Supervisor workflow and that single-iteration mode gets the post-PR drain through it.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions are equal and bumped above 14.36.0; CLAUDE.md carries a new banner; `check-doc-currency.sh` + `validate-version.sh` exit 0.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Inline canonical `state.md` write at ACQUIRE + completion | AC1, AC5 | 2 modify, 0 create | state-management, workflow-management | LAUNCHABLE |
| 2 | Hook format-tolerance (bold + lowercase) + realistic test | AC2, AC3, AC5 | 2 modify, 0 create | error-handling, unit-testing | LAUNCHABLE |
| 3 | `/autonomous` single-iteration drain parity (don't drop step 5.5) | AC4, AC5 | 2 modify, 0 create | autonomous-loop, review-heal | LAUNCHABLE |
| 4 | Docs + version bump + CHANGELOG + currency sweep | AC6 | ~6 modify, 0 create | quality-checklist | BLOCKED (by #1,#2,#3) |

### Provides / Requires Contracts

```yaml
# Subtask 1 — Inline canonical state.md write (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "ACQUIRE canonical state.md write"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/state-management/SKILL.md", name: "inline state.md write responsibility"}
requires: []
external_requires: []

# Subtask 2 — Hook format-tolerance + realistic test (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/hook-dispatch-on-pr-create.sh", name: "bold+lowercase state.md grep tolerance"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/test-hook-dispatch-on-pr-create.sh", name: "bold-format state.md fixture + branch-mismatch case"}
requires: []
external_requires:
  - "jq"

# Subtask 3 — /autonomous single-iteration drain parity (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "EXECUTE preserves Phase 4.5 step 5.5"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/autonomous.md", name: "single-iteration drain parity note"}
requires: []
external_requires: []

# Subtask 4 — Docs + version bump (BLOCKED by #1,#2,#3)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CLAUDE.md", name: "release banner"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "fix entry"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "ACQUIRE canonical state.md write"}
  - {from: "2", kind: "symbol", path: "ai-agent-manager-plugin/scripts/hook-dispatch-on-pr-create.sh", name: "bold+lowercase state.md grep tolerance"}
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md", name: "EXECUTE preserves Phase 4.5 step 5.5"}
external_requires: []
```

### Subtask Detail Notes

**Subtask 1 — Inline canonical `state.md` write.** In `agents/supervisor.md` Phase 1 ACQUIRE (the step that currently updates state via Context-Keeper), ensure the **canonical lowercase `## Session` block** (`- status: running`, `- branch: <feature-branch>`, per `skills/state-management/SKILL.md`'s schema) is written to `.supervisor/state.md` on the inline main-thread path — either by spawning Context-Keeper or by a direct write when Context-Keeper is not used inline — so the durable state the hook's gate consumes actually exists after ACQUIRE. Ensure the Phase 4.5 completion tail flips `- status: completed`. In `skills/state-management/SKILL.md`, make the inline-path write responsibility explicit (the canonical block must land regardless of whether Context-Keeper was spawned). **Do NOT** change the human-readable bold ENVIRONMENT/Outcome OUTPUT blocks — those are display, separate from the on-disk canonical state file. This also fixes `/supervisor --continue` resume on inline runs (resume reads lowercase `status: running`).

**Subtask 2 — Hook format-tolerance + realistic test.** In `scripts/hook-dispatch-on-pr-create.sh`, make term (iii) branch extraction and term (ii) status extraction match BOTH the canonical lowercase (`^- status:` / `^- branch:`) AND the bold (`^- \*\*Status:\*\*` / `^- \*\*Branch:\*\*`) forms (case-insensitive key), so a `state.md` in either shape is parseable. Keep the fail-closed-on-genuinely-missing-branch anti-hijack posture (only fall through to skip when NEITHER form yields a branch). Keep ALWAYS exit 0. In `scripts/test-hook-dispatch-on-pr-create.sh`, add fixture cases that write `state.md` in the **bold `- **Branch:**`** format (the real inline-produced shape) and assert the gate resolves the branch and dispatches on match; add a branch-MISMATCH case (bold format, wrong branch → no dispatch); keep the existing stale-state/absent/branchless cases. Run the test; confirm green.

**Subtask 3 — `/autonomous` single-iteration drain parity.** In `skills/autonomous-loop/SKILL.md` EXECUTE: change the Supervisor-phase enumeration so it no longer drops step 5.5 — explicitly state that when `/autonomous` runs Supervisor inline, Supervisor's Phase 4.5 **step 5.5 (until-mergeable drain dispatch, default-ON) runs as part of the inline Supervisor workflow**, so single-iteration mode reaches the post-PR drain (parity with direct `/supervisor`). Clarify that the loop's EVALUATE chained review-heal is an ADDITIONAL inline gate used for the multi-iteration stacking decision (unchanged), and document the multi-iteration interplay with the detached drain (the existing R9 "branch-dependent downstream waits for the drain" note). Mirror the clarification in `commands/autonomous.md`. **Scope guard:** this subtask is documentation/prompt-level (the autonomous loop is prompt-driven); do NOT redesign the multi-iteration review-heal mechanism — only stop single-iteration from silently having no drain.

**Subtask 4 — Docs + version.** Read the LIVE `plugin.json` version (14.36.0) and bump it (minor → 14.37.0 unless a different convention is warranted; never hardcode a stale target). Update `plugin.json` + `marketplace.json` (equal versions; description version string in place, no appended clause). Add a CLAUDE.md banner (keep the two most recent; displace the oldest into CHANGELOG), a CHANGELOG entry, and sweep every current-claim version string the doc-currency gate scans. **Counts are UNCHANGED** (no new agent/command/skill/hook — only edits to an existing hook script + prompts + a test). Run `scripts/check-doc-currency.sh` + `scripts/validate-version.sh`; confirm both green.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ─┐
Subtask 2 ─┼──→ Subtask 4
Subtask 3 ─┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (supervisor.md/state-management vs hook+test) | NO |
| Subtask 1 | Subtask 3 | none (supervisor.md vs autonomous-loop/command) | NO |
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 4 | all | none (manifests + version-bearing docs disjoint from S1–S3 targets) | YES (finalize after) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel — fully disjoint files)
- **Batch 2:** Subtask 4
- **Recommended workers:** 3
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/state-management/SKILL.md`, `skills/workflow-management/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 3 | `skills/autonomous-loop/SKILL.md`, `skills/review-heal/SKILL.md` |
| 4 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Co-touches `agents/supervisor.md` with the still-open PR #69 (Phase 4 added Phase 4.5 step 1c) | MEDIUM | This job touches DIFFERENT supervisor.md sections (Phase 1 ACQUIRE + step-5.5 note vs Phase 4.5 step 1c) → trivial merge. Prefer merging #69 first, then base this on `main`; or accept a small rebase. `Base Branch: main`. |
| Weakening the hook's anti-hijack gate while adding format tolerance | HIGH | Tolerance only widens the *parsing* of the branch line; the branch-MATCH requirement and fail-closed-on-unresolvable posture are unchanged. New test asserts a bold-format MISMATCH still skips. |
| Inline `state.md` write diverges from Context-Keeper's writes (double-writer hazard) | MEDIUM | Context-Keeper remains the canonical writer on the parallel path; the inline write must produce the SAME lowercase `## Session` schema. Document the single schema in state-management; do not introduce a second format. |
| Over-reaching into the multi-iteration review-heal redesign | MEDIUM | S3 is scoped to single-iteration parity + documentation only; the multi-iteration EVALUATE review-heal + R9 wait stay unchanged. |
| Changing a fail-safe emitter into something that can break a tool call | HIGH | The hook MUST still ALWAYS exit 0; the ACQUIRE state write must be best-effort/non-fatal. Reviewers verify no new non-zero exit path. |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-18-fix-inline-review-drain-dispatch.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-18T19:58:06Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/70
- **Branch:** feature/fix-inline-review-drain-dispatch
- **Files changed:** 12
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Heal remaining issues:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260618T195030Z-67da482bb100d3197671811914e81f56734a162f.log
- **Summary:** Fixed inline review-drain dispatch via 4 subtasks (inline canonical state.md write at ACQUIRE+completion; hook bold+lowercase state.md tolerance + 16→17 self-test; /autonomous single-iteration step-5.5 drain parity docs; v14.37.0 bump). Phase 4.5 holistic review PASS; one LOW stale-guard gap (completed_with_escalation) healed. Both CI gates green. The until-mergeable drain auto-dispatched on PR #70 via the PostToolUse hook — proving subtask 1's fix end-to-end.
