# Supervisor Job: Make plugin agents brain-aware (read path) + baseline eval harness

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — matches v14.26.0)
- **Git:** dirty (untracked only: `.claude/`, the SPIKE doc), branch: feature/requirement-closeout-loop
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit, repo scope)
- **Blockers:** 0 | **Warnings:** 1 (on a non-main branch — iter-1 feature branch MUST be cut from `origin/main`)
- **Source requirement:** .supervisor/requirements/auto-2026-06-17-001013-brain-integration-evolution.md

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | In-repo work is markdown skills, bash, Node ESM — exactly this repo's stack |
| 2 | Dependency Availability | CAUTION | Graphify / personal-brain wiki / BRAIN_ROOT are external & absent in this workspace; only the fail-safe fallback path is exercisable here |
| 3 | Architecture Fit | GO | Mirrors `self-heal-advisory` (read-on-demand), `/setup` module contract, advisory/fail-safe bimodal rule |
| 4 | Scope vs Supervisor Capability | NO-GO (user override) | Full doc is 6 phases / 2 repos; this brief is scoped to the in-repo Phase 0 + Phase 1 slice |
| 5 | Hard Blockers | NO-GO (user override) | Phases 3b/4 write into the `personal-brain` repo (not in this workspace) — excluded from this brief |

**Overall Verdict:** NO-GO (user override at Phase 2.5 — scoped to the buildable in-repo slice; cross-repo phases recorded as HIGH risks below)

## Task
**Goal:** Make plugin agents optionally brain-aware via a new read-on-demand `brain-context` skill (graph → wiki → raw fallback, fully advisory and fail-safe), and ship a baseline eval harness that measures grep-first behavior, all in-repo.

**Problem Statement:**
Plugin agents needing structural codebase context (blast radius, "what calls X", where a concept lives) today only grep/read — they cannot consult a pre-built knowledge graph even when one exists. This causes redundant search and missed cross-file context on structural questions. Success looks like: a detected `graphify-out/graph.json` or `AI_AGENT_MANAGER_BRAIN_ROOT` lets agents query structure first (advisory), with a fail-safe fall back to grep when absent/stale, plus a baseline measurement harness so a later graph-first iteration can be proven to help.

## Acceptance Criteria
- [ ] Given a repo with no graph/brain present, when any agent consults `brain-context`, then it silently falls back to grep/read and the run is unaffected (fail-safe).
- [ ] Given `graphify-out/graph.json` OR `AI_AGENT_MANAGER_BRAIN_ROOT` is present, when `brain-context` runs, then it follows the 3-step query order (graph → wiki → raw) and honors the staleness rule (committed-code-only; session-edited files read raw).
- [ ] Given the brain-context skill is added, when `check-doc-currency.sh` runs, then all skill-count claims read 55 and the version is bumped consistently across plugin.json/marketplace.json/CLAUDE.md/README.md/SKILLS_INDEX.md.
- [ ] Given the baseline eval harness is run with no graph, when it completes, then it writes to `.supervisor/eval/brain-baseline.jsonl` (distinct from `results.jsonl`), exits 0, and records `status: unverified` rather than failing.
- [ ] Given the wiring edits, when an agent reaches its context-setup / analysis point, then it has an on-demand instruction to consult `brain-context` if a brain is detected — and `brain-context` appears in NO agent's frontmatter `skills:` list.

## Outcomes Rubric
- A new skill file `ai-agent-manager-plugin/skills/brain-context/SKILL.md` exists with `name: brain-context` plus `version:` and `lastUpdated:` frontmatter fields.
- The brain-context skill body contains a Detection section naming both `graphify-out/graph.json` and `AI_AGENT_MANAGER_BRAIN_ROOT`, and an explicit fail-safe fallback statement (graph absent/low-confidence ⇒ grep/read, never blocks).
- The brain-context skill encodes the staleness rule in prose: the graph is authoritative only for committed code, and any file the session edits is read raw.
- `ai-agent-manager-plugin/skills/SKILLS_INDEX.md` contains a `brain-context` row AND its total-skill count reads 55 (not 54).
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` skill-count text reads 55 and both carry the same bumped `version`.
- A baseline eval harness script `ai-agent-manager-plugin/scripts/brain-baseline-eval.sh` exists, references the output path `.supervisor/eval/brain-baseline.jsonl`, and contains an `exit 0` on its fail-safe path.
- No agent prompt frontmatter adds `brain-context` to a `skills:` list (on-demand-only invariant): grep for `brain-context` under `agents/*.md` matches only body prose, never a frontmatter `skills:` entry.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Create `brain-context` read-on-demand skill | AC1, AC2 | 0 modify, 1 create | quality-checklist | LAUNCHABLE |
| 2 | Baseline eval harness + insights wiring | AC4 | 1 modify, 1-2 create | quality-checklist, monitoring-observability | LAUNCHABLE |
| 3 | Wire brain-context into agent prompts | AC5 | 4 modify, 0 create | quality-checklist | BLOCKED (by #1) |
| 4 | Doc-currency + metadata bump (54→55) | AC3 | 6 modify, 0 create | claude-md-validation | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1 — brain-context skill (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/skills/brain-context/SKILL.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/brain-context/SKILL.md", name: "name: brain-context"}
requires: []
external_requires:
  - "graphify CLI (optional, runtime-detected — never required)"
  - "personal-brain wiki at AI_AGENT_MANAGER_BRAIN_ROOT (optional, runtime-detected)"

# Subtask 2 — baseline eval harness + insights wiring (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/brain-baseline-eval.sh"}
  - {kind: "file", path: ".supervisor/eval/brain-baseline-corpus/README.md"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/build-insights.sh", name: "Brain Context Baseline"}
requires: []
external_requires:
  - "jq (already a plugin runtime dependency)"

# Subtask 3 — wire brain-context into agent prompts (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/context-setup/SKILL.md", name: "brain-context"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "brain-context"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/code-reviewer.md", name: "brain-context"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "brain-context"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/skills/brain-context/SKILL.md"}
external_requires: []

# Subtask 4 — doc-currency + metadata bump (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/SKILLS_INDEX.md", name: "Brain Context"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "brain-context"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/skills/brain-context/SKILL.md"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 1 ──→ Subtask 4
Subtask 2 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | NO (dependency only — skill must exist to reference) |
| Subtask 1 | Subtask 4 | none | NO (dependency only — skill dir must exist for count=55) |
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 4 | none | NO |
| Subtask 3 | Subtask 4 | none | NO (ST3=agents/*.md + context-setup; ST4=index/manifests/CLAUDE.md/README.md/CHANGELOG.md) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel)
- **Batch 2:** Subtask 3, Subtask 4 (parallel, after Subtask 1)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/self-heal-advisory/SKILL.md` (read as the mirror pattern — on-demand, NOT preloaded) |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/monitoring-observability/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |
| 4 | `skills/claude-md-validation/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope override — full 6-phase doc reduced to in-repo Phase 0+1 slice; cross-repo Phase 3b (harvest-plugin-runs.mjs) & Phase 4 (brain projection) NOT in this brief | HIGH | Documented as deliberate Phase 2.5 user override; follow-up per-phase briefs needed once `personal-brain` repo is co-located |
| Cross-repo writes to `personal-brain` are structurally impossible from this workspace | HIGH | Brief scoped to in-repo deliverables only; brain WRITE path (Phase 3a `/dreaming --target brain`) deferred |
| Graph/brain absent here ⇒ only the fail-safe fallback path is exercisable; the actual graph-query path is unverified in this repo | MEDIUM | Skill is advisory/fail-safe by contract; eval harness records `status: unverified` when no graph; real graph-first measurement happens in a configured-brain repo |
| Doc-currency count bump (54→55) must stay consistent across 6 files or CI fails | MEDIUM | `check-doc-currency.sh` gate + `corpus-task: doc-currency-green` in Executable Acceptance |
| Line anchors from Phase 3 analysis are approximate | LOW | Workers must use descriptive anchors (section/phase headings), never absolute line numbers (see CLAUDE.md memory: absolute-line-ref drift) |
| brain-context accidentally preloaded into agent frontmatter (token bloat) | MEDIUM | Rubric item + AC5 explicitly forbid a `skills:` frontmatter entry; ST3 edits prompt BODY only |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-06-17-001013-brain-readpath.md
```

---

## Outcome
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1 (holistic review PASS, no fix loop needed)
- **heal_remaining_issues:** 0 BLOCKING/HIGH (2 non-gating: 1 MEDIUM corpus-gitignore, 1 LOW path-drift)
- **rubric_score:** 7/7
- **pr_url:** https://github.com/vikashruhilgit/ai-agent-manager/pull/60
- **branch:** feature/brain-context-readpath
- **completed:** 2026-06-16T19:25:00Z
