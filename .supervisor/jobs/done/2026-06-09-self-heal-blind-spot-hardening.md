# Supervisor Job: Harden Phase 4.5 self-heal against the post-PR review blind spot

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v14.20.0)
- **Git:** branch `main`; working tree dirty at brief-creation time (M `agents/supervisor.md`, M `skills/commit/SKILL.md`, untracked `.claude/`) — WARNING: branch from a clean `main` (commit/stash first).
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (dirty working tree)

## Feasibility (Phase 2.5)
**GO.** Deepens an existing phase (4.5) and reuses existing capabilities — the Code Reviewer's `consistency_audit` mode and the ground-truth runner both already exist and are already invoked. No new tech/deps. Aligns with System Twin Pillar 2 ("provable-done") and the advisory-first principle. CAUTION: `consistency_audit` triggers are plugin-path-specific and won't fire on external repos — addressed by Subtask 2's repo-agnostic checklist.

## Task
**Goal:** Make Phase 4.5 self-heal catch the issue classes that today only surface in post-PR review (the 3–6 round back-and-forth), via (a) a different review lens than a plain re-run of the same diff-scoped reviewer, (b) a repo-agnostic miss-class checklist, (c) an actually-running ground-truth step, and (d) class-level (not instance-level) fixes. **Advisory only — never gates, never blocks the PR.**

**Root-cause evidence:** Across otherhub PRs #146/#129/#133/#139 and this repo's #24/#26/#36/#41, 8/8 recent `session_end` records reported `heal_decision: PASS` (5 with `heal_iterations: 0` — heal found nothing) yet those PRs absorbed 3–6 review-fix rounds and spawned follow-up PRs (#36, #41). Phase 4.5 re-runs the SAME diff-scoped Code Reviewer (inherits its blind spots) and `ground_truth` was `skipped` everywhere. The miss-classes differ by repo (external: backend/frontend validation parity, null/zero falsy bugs, positional-arg call sites, coverage gaps; self: doc/count drift) but the mechanism is identical.

## Acceptance Criteria
- [ ] Given a heal run on the plugin's own repo whose diff touches a trigger surface, when Phase 4.5 reviews, then it runs in `consistency_audit` mode (not plain `diff_review`) for non-stacked (`main`-based) runs.
- [ ] Given a heal run on ANY repo (incl. external), when Phase 4.5 reviews, then the Code Reviewer applies the repo-agnostic "self-heal miss-class checklist" (backend-mirrors-frontend validation; no falsy coercion on numeric fields; no positional args to options-object functions; missing branch coverage; drift on counts/cross-refs).
- [ ] Given a heal fix iteration addressing a finding, when the fix is applied, then the fixer scans the diff for the same class and fixes all occurrences, not just the flagged one.
- [ ] Given a plugin-self brief that modifies the doc surface, when Phase 4.5 runs ground_truth, then `status != "skipped"` (it runs `corpus-task: doc-currency-green` / `version-consistent`).
- [ ] Advisory contract preserved: `heal_decision` semantics unchanged, PR never blocked, `SUPERVISOR_RESULT` stays `schema_version: 1`.
- [ ] All existing deterministic self-tests (`scripts/test-*.sh`) still pass; doc-currency counts updated if any agent/command/skill/hook count changes.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

### Subtask 1 — Phase 4.5 orchestration: different-lens review + fix-the-class (LAUNCHABLE)
- **Files (modify):** `ai-agent-manager-plugin/agents/supervisor.md` (Phase 4.5 SELF_HEAL, ~602–900)
- In the code-reviewer spawn (~685): for non-stacked (`BASE_BRANCH == main`) heal runs, explicitly direct the reviewer to run `consistency_audit` when self-repo trigger paths match AND to ALWAYS apply the Subtask-2 miss-class checklist regardless of repo. Leave the stacked-iteration DIFF-SCOPE OVERRIDE (non-`main` bases) intact.
- In the fix-iteration step (~739): add the "fix-the-class-not-the-instance" instruction.
- Preserve advisory-only semantics; no `heal_decision`/gate change.
- **provides:**
  - {kind: symbol, path: ai-agent-manager-plugin/agents/supervisor.md, name: "Phase 4.5 different-lens review + fix-the-class directive"}
- **requires:** []

### Subtask 2 — Repo-agnostic self-heal miss-class checklist (LAUNCHABLE)
- **Files (modify):** `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` (new "Self-Heal Miss-Class Checklist" section); `ai-agent-manager-plugin/agents/code-reviewer.md` (one-line pointer so the reviewer applies it during heal).
- Concrete classes: backend/API validation mirrors every frontend-schema rule; no `||`/falsy coercion on numeric fields; no positional args passed to options-object functions; missing branch test coverage; consistency/drift on count/cross-ref changes. Must be repo-agnostic (works on external repos where `consistency_audit` triggers don't fire).
- **provides:**
  - {kind: symbol, path: ai-agent-manager-plugin/skills/quality-checklist/SKILL.md, name: "Self-Heal Miss-Class Checklist"}
  - {kind: symbol, path: ai-agent-manager-plugin/agents/code-reviewer.md, name: "Self-Heal Miss-Class Checklist pointer"}
- **requires:** []

### Subtask 3 — Make ground_truth run via Executable-Acceptance authoring convention (LAUNCHABLE)
- **Files (modify):** `ai-agent-manager-plugin/agents/launch-pad.md` (Phase 5 — emit `## Executable Acceptance` with `corpus-task:` checks for plugin-self / doc-surface briefs); `ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md` (authoring-convention note).
- Machine-authored briefs touching the plugin's doc surface declare `corpus-task: doc-currency-green` (+ `version-consistent`) so Phase 4.5 ground_truth runs the invariant instead of skipping. `corpus-task:` only (no `cmd:`), honoring the `--no-cmd` machine-authored convention.
- **provides:**
  - {kind: symbol, path: ai-agent-manager-plugin/agents/launch-pad.md, name: "Phase 5 Executable-Acceptance emission for plugin-self briefs"}
  - {kind: symbol, path: ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md, name: "Executable Acceptance authoring convention"}
- **requires:** []

### Subtask 4 — Docs, version bump, advisory schema, counts (BLOCKED by 1,2,3)
- **Files (modify):** `CLAUDE.md` (banner), `CHANGELOG.md`, `ai-agent-manager-plugin/.claude-plugin/plugin.json` (version), `.claude-plugin/marketplace.json` (version + description), `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` (any additive advisory field; `schema_version` stays 1), `ai-agent-manager-plugin/docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` (record the self-heal hardening + the deferred ④ token-tracking constraint: the future synthetic eval harness defaults to `CLAUDE_CODE_OAUTH_TOKEN`, requires no paid credits, and must report per-run token usage).
- Update doc-currency counts ONLY if a count changes (target: no new command/agent; the checklist is a section in an existing skill, not a new skill — counts unchanged 14/16/51/19).
- **provides:**
  - {kind: file, path: ai-agent-manager-plugin/.claude-plugin/plugin.json, name: "version v14.21.0"}
  - {kind: file, path: CLAUDE.md, name: "v14.21.0 release banner"}
- **requires:**
  - {from: "1", kind: symbol, path: ai-agent-manager-plugin/agents/supervisor.md, name: "Phase 4.5 different-lens review + fix-the-class directive"}
  - {from: "2", kind: symbol, path: ai-agent-manager-plugin/skills/quality-checklist/SKILL.md, name: "Self-Heal Miss-Class Checklist"}
  - {from: "3", kind: symbol, path: ai-agent-manager-plugin/agents/launch-pad.md, name: "Phase 5 Executable-Acceptance emission for plugin-self briefs"}

## Parallelism Analysis
### Dependency Graph
- Subtasks 1, 2, 3 are independent → Subtask 4 depends on all three.
### File Overlap Matrix
- S1 `supervisor.md` · S2 `quality-checklist/SKILL.md` + `code-reviewer.md` · S3 `launch-pad.md` + `supervisor-readiness/SKILL.md` · S4 docs/manifests. **No overlap within Batch 1.**
### Batch Plan
- Batch 1 (parallel): Subtask 1, 2, 3. Batch 2: Subtask 4. **Recommended workers: 3.**

## Skill References
- `quality-checklist` (Subtask 2 home), `state-management` / `workflow-management` (Subtask 1 context), `supervisor-readiness` (Subtask 3), `claude-md-validation` + the doc-currency gate (Subtask 4).

## Risk Assessment
| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| consistency_audit never triggers on external repos (plugin-path triggers) | MEDIUM | Feasibility (Phase 2.5) | Subtask 2 repo-agnostic checklist is the cross-repo lever; consistency_audit is the self-repo lever only |
| Editing Phase 4.5 could disturb the advisory contract / completion-tail guard / schema_version | MEDIUM | Analysis | Advisory-only + schema_version 1 are explicit acceptance criteria; the self-test suite gates |
| "ground_truth runs" surfaces maintainer-side-only corpus tasks as a false signal on user projects | LOW | Analysis | Scope the authoring convention to plugin-self/doc-surface briefs; advisory-only |
| Anti-rebloat: accidental new command/agent/skill | LOW | Analysis | Checklist is a section in an existing skill; no new top-level artifact; counts asserted unchanged |
| Heal cost / iterations increase | LOW | Analysis | Bounded by `--heal-iterations` (default 3); advisory |

## Configuration
- **Base Branch:** main
- **Target version:** v14.21.0 (next minor)
- **Heal:** advisory-only; `--heal-iterations` default unchanged.

## Plan Review
- **Decision:** PASS (attempt 2/3). Attempt 1 FAILed on one HIGH `dep_graph` issue (free-text contract labels) — fixed by converting all `provides`/`requires` to structured `{kind, path, name?}` objects. Re-review confirmed all File Impact paths exist, corpus tasks present, Phase 4.5 facts match, no Batch-1 file overlap, advisory-only + schema_version 1 preserved.

## Handoff
`/supervisor job: .supervisor/jobs/pending/2026-06-09-self-heal-blind-spot-hardening.md`

## Outcome
- **Status:** completed
- **Completed:** 2026-06-09T16:35:00Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/43
- **Branch:** feature/self-heal-blind-spot-hardening
- **Files changed:** 12
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (consistency_audit review passed clean — no fixable new HIGH/BLOCKING issues)
- **Ground truth:** pass (2/2 — corpus-task: doc-currency-green, version-consistent)
- **Self-tests:** 14/14 pass
- **Rubric:** n/a (no ## Outcomes Rubric in brief)
- **Summary:** Hardened Phase 4.5 self-heal with four advisory-only levers (different-lens review, repo-agnostic miss-class checklist, fix-the-class fixer directive, ground_truth Executable-Acceptance emission); bumped to v14.21.0. Counts unchanged 14/16/51/19; SUPERVISOR_RESULT stays schema_version 1.
