# Supervisor Job: Orientation memos + owned flat repo-map (advisory memos-first orientation)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — v15.11.0 banner matches plugin.json)
- **Git:** clean, branch: main (synced at bb9b699)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (orchestrator prompt-token budget headroom ~788 proxy tokens — raise budget in same PR if breached)
- **Source requirement:** .supervisor/requirements/token-economy/04-orientation-memos-and-repo-map.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash/jq/markdown, matches every existing plugin script; bash-3.2 + Linux-CI constraints already codified |
| 2 | Dependency Availability | GO | All substrates exist: `.agent/rules/` store + read-rules.sh/add-rule.sh (v14.51.0), brain-context skill, self-heal-advisory Part 2 completion tail, emit-token-ledger.sh (job-01, PR #100 MERGED — hard precondition satisfied) |
| 3 | Architecture Fit | CAUTION | Requirement text says `scripts/build-repo-map.sh` (repo-root), but runtime helpers MUST live in `loomwright/scripts/` for `${CLAUDE_PLUGIN_ROOT}` resolution — this brief locks `loomwright/scripts/` for reader + builder (repo-root scripts/ is CI-validators-only) |
| 4 | Scope vs Supervisor Capability | GO | Decomposes into 4 subtasks of 30-60 min |
| 5 | Hard Blockers | CAUTION | Spike Tier-A PageRank ranker FAILED validation (CODE_GRAPH_OWNERSHIP.md:174-216) — reuse ONLY the signature-extraction approach + exclusion list; Tier A ships as probe-and-degrade, Tier B is the deliverable floor |

**Overall Verdict:** GO (2 CAUTIONs fed into Risk Assessment)

## Task
**Goal:** Agents orient from ~1-2k tokens of accumulated per-area orientation memos (committed `.agent/orientation/`, staleness-annotated) with a zero-dep flat repo-map as cold-start fallback — advisory at every seam, attributable via the job-01 token ledger.

**Problem Statement:**
Launch Pad Phase 2/3 and Orchestrator planning burn tens of thousands of tokens on raw grep/read exploration every run because nothing accumulates "where to look" knowledge. Currently each run re-explores from scratch; cost per run is flat over the life of a repo. Success looks like: memos-first advisory reads at both orientation seams, a `read-orientation.sh` reader with staleness provenance, a `build-repo-map.sh` Tier-B zero-dep fallback, a success-only gitignored write-proposal seam, and an `orientation_source` field on the session-JSONL ledger — with byte-equivalent behavior when nothing exists.

## Acceptance Criteria
- [ ] AC1 Given no memos/map/graph exist, when Launch Pad Phase 3 or Orchestrator Context Setup runs, then behavior is byte-equivalent to today (explicit fail-safe-skip branch in both prompts).
- [ ] AC2 Given memos exist, when `read-orientation.sh` runs, then it emits a bounded (≤3k chars total) block; over-cap and hostile-content memos are skipped per-object (test proving it).
- [ ] AC3 Given a memo header with `written_at` + head-commit SHA, when the area changed since that SHA, then the reader annotates/demotes it as stale (fixture tests: fresh, stale, git-error⇒fresh-unknown); staleness never blocks.
- [ ] AC4 Given a successful run, when the completion tail fires, then memo proposals land ONLY in gitignored `.supervisor/orientation-proposals/`; a write failure is silent (test or trace); committed `.agent/orientation/` changes only via the per-item-approval promote flow (add-orientation.sh sole writer, add-rule.sh REJECT + path-containment discipline).
- [ ] AC5 Given a bare macOS/Linux box with zero deps, when `build-repo-map.sh` runs, then Tier B produces a capped (~2k-token proxy) map under `.supervisor/`; Tier A degrades to Tier B when tree-sitter tooling is absent (probe test, never installs).
- [ ] AC6 Given the rewrite, when brain-context SKILL.md is read, then it documents the memos → repo-map → graphify-if-present → nothing ladder, keeps the never-gates contract authoritative, and states the ≤3k-char injection bound.
- [ ] AC7 Given a run that consulted orientation, when the token-ledger line is emitted, then it carries an additive `orientation_source: memos|repo_map|graphify|none` field (same JSONL namespace, no second emitter; test updated).
- [ ] AC8 Given the PR, then its description contains the seven-state dynamic trace table (memos present / stale memo / empty / hostile-content memo / map-present-no-memos / nothing / fresh-worktree).
- [ ] AC9 Given the change, when CI runs, then check-doc-currency.sh, check-command-sync.sh, check-skills-index-sync.sh, validate-version.sh, check-token-budget.sh pass; all new self-tests pass offline (bash-3.2 safe, no GNU-only stat/sed/date flags); minor version bump + CHANGELOG entry; agent↔command mirror prose synced in the same commit.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Memo substrate: `.agent/orientation/` store + read-orientation.sh + add-orientation.sh + tests | AC2, AC3, AC4(writer) | 0 modify, 5 create | rules, state-management | LAUNCHABLE |
| 2 | build-repo-map.sh Tier A/B + test + fixtures | AC5 | 0 modify, 3 create | quality-checklist | LAUNCHABLE |
| 3 | Read seams: launch-pad.md + orchestrator.md memos-first step + brain-context ladder rewrite + token budgets | AC1, AC6 | 5 modify, 0 create | brain-context, quality-checklist | BLOCKED (by #1, #2) |
| 4 | Write seam + ledger + dreaming promote + docs/version | AC4(seam), AC7, AC9 | 7 modify, 0 create | self-heal-advisory, commit | BLOCKED (by #1) |

**Subtask 1 — Memo substrate (LAUNCHABLE)**
Create the committed store `.agent/orientation/` (README.md documenting: one `.md` file per area, header lines `<!-- written_at: ISO-8601 | head_sha: <sha> -->` + one-line summary, ≤1000-char hard cap per memo). Create `loomwright/scripts/read-orientation.sh` cloned from read-rules.sh's fail-safe pattern: always exit 0, EMPTY output when store absent/empty, per-object skip of over-cap or hostile-content memos (same REJECT categories as add-rule.sh path/field discipline, plus prose scan for instruction-injection markers), total output bounded ≤3000 chars, staleness check per memo (`git log --oneline <sha>.. -- <area paths> | head` bounded; any git error ⇒ fresh-unknown, never block) annotating `[stale — area changed since <date>, verify before trusting]` and demoting stale below fresh. Create `loomwright/scripts/add-orientation.sh` cloned from add-rule.sh (slug path-containment single `[a-z0-9-]` segment, REJECT `/`,`..`,leading-dot,metachars, temp+atomic-mv, read-back verify, confirm-only). Create `loomwright/scripts/test-read-orientation.sh` (fixtures: fresh/stale/git-error/over-cap/hostile/empty/absent) and `loomwright/scripts/test-add-orientation.sh` (REJECT + traversal cases). Memos are DATA not instructions — reader banner states subordinate-to-CLAUDE.md like read-rules.sh:232.
```yaml
provides:
  - {kind: "file", path: ".agent/orientation/README.md"}
  - {kind: "file", path: "loomwright/scripts/read-orientation.sh"}
  - {kind: "file", path: "loomwright/scripts/add-orientation.sh"}
  - {kind: "file", path: "loomwright/scripts/test-read-orientation.sh"}
  - {kind: "file", path: "loomwright/scripts/test-add-orientation.sh"}
requires: []
external_requires:
  - "jq >= 1.6 (already a plugin runtime dependency)"
```

**Subtask 2 — Flat repo-map builder (LAUNCHABLE)**
Create `loomwright/scripts/build-repo-map.sh`: Tier A = IF tree-sitter CLI present (probe `command -v tree-sitter`, NEVER install) emit ranked signature map reusing the spike's signature-extraction + exclusion list (CODE_GRAPH_OWNERSHIP.md:138-148) but NOT its failed PageRank ranker; Tier B zero-dep fallback = directory skeleton (bounded depth) + exported-symbol grep (`grep -E 'export |^function |^def |^class '` style, language-agnostic patterns). Output capped ~8000 chars (~2k-token proxy), written to `.supervisor/repo-map.md` (gitignored via existing `.supervisor/` rule), regenerated on demand, always exit 0. Create `loomwright/scripts/test-build-repo-map.sh` (Tier-B-on-bare-box, Tier-A-degrade probe, cap enforcement, empty-repo) + fixtures dir `loomwright/scripts/repo-map-fixtures/`. bash-3.2 safe; no network.
```yaml
provides:
  - {kind: "file", path: "loomwright/scripts/build-repo-map.sh"}
  - {kind: "file", path: "loomwright/scripts/test-build-repo-map.sh"}
  - {kind: "file", path: "loomwright/scripts/repo-map-fixtures/README.md"}
requires: []
external_requires: []
```

**Subtask 3 — Read seams + ladder (BLOCKED by #1, #2)**
Modify `loomwright/agents/launch-pad.md` Phase 3 (model on the existing line-261 brain-consult phrasing): advisory memos-first step — run `${CLAUDE_PLUGIN_ROOT}/scripts/read-orientation.sh`; if EMPTY and `${CLAUDE_PLUGIN_ROOT}/scripts/build-repo-map.sh` available, generate/read the flat map; scope subsequent raw exploration to task-relevant areas; explicit fail-safe-skip branch (nothing available ⇒ today's behavior, verbatim). Modify `loomwright/agents/orchestrator.md` Context Setup block (lines ~81-104) with the same advisory step. Rewrite `loomwright/skills/brain-context/SKILL.md` ladder to memos → repo-map → graphify-if-present → nothing; keep HARD ADVISORY CONTRACT authoritative; document the ≤3k-char injection bound; version bump. Update `loomwright/docs/prompt-token-budgets.json` (+ the mirrored `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" row) IF launch-pad/orchestrator additions breach budget (orchestrator headroom ~788 — likely; raise with one-line note per the ratchet rule). Sync `loomwright/commands/launch-pad.md` / `loomwright/commands/orchestrator.md` mirror prose in the same commit (agent↔command mirror-drift lesson).
```yaml
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "Memos-first orientation"}
  - {kind: "symbol", path: "loomwright/agents/orchestrator.md", name: "Memos-first orientation"}
  - {kind: "symbol", path: "loomwright/skills/brain-context/SKILL.md", name: "Enrichment ladder"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/read-orientation.sh"}
  - {from: "2", kind: "file", path: "loomwright/scripts/build-repo-map.sh"}
external_requires: []
```

**Subtask 4 — Write seam + ledger + docs/version (BLOCKED by #1)**
Modify `loomwright/skills/self-heal-advisory/SKILL.md` Part 2 completion tail: add a success-only, fail-safe, additive memo-proposal step (modeled on step 2.5 requirement close-out) writing proposals ONLY to gitignored `.supervisor/orientation-proposals/` (never the committed store; never blocks; write failure silent). Modify `loomwright/commands/dreaming.md`: extend the per-item-approval accept flow to promote orientation proposals → `.agent/orientation/` via `add-orientation.sh` (literal argv, never interpolated — same as write-lessons.sh handling). Modify `loomwright/scripts/emit-token-ledger.sh`: additive `orientation_source` field (env-var-fed, additive-if-present style, values memos|repo_map|graphify|none) + update `loomwright/scripts/test-token-ledger.sh`. Version/docs: `loomwright/.claude-plugin/plugin.json` 15.11.0 → 15.12.0 (+ marketplace.json description version-string in place), CHANGELOG.md entry, CLAUDE.md banner (two-most-recent rule — demote v15.10.0 note to CHANGELOG), CODE_GRAPH_OWNERSHIP.md status note (parked reposcan resumed as Tier B). Counts UNCHANGED (scripts are uncounted) — no skills-index/command-sync churn expected.
```yaml
provides:
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "Orientation memo proposals"}
  - {kind: "symbol", path: "loomwright/scripts/emit-token-ledger.sh", name: "orientation_source"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "version"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/add-orientation.sh"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 1 ──→ Subtask 4
Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 3 | Subtask 4 | none (3: agents/skills-brain-context/budgets+ARCHITECTURE_CONTRACTS; 4: self-heal-advisory/dreaming/ledger/plugin.json/CHANGELOG/CLAUDE.md) | NO |
| Subtask 1 | Subtask 4 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel)
- **Batch 2:** Subtask 3, Subtask 4 (parallel, after batch 1)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/rules/SKILL.md`, `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |
| 3 | `skills/brain-context/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 4 | `skills/self-heal-advisory/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Orchestrator prompt-budget breach (~788 headroom) — source: Feasibility (Phase 2.5) | MEDIUM | Subtask 3 keeps the orchestrator addition ≤~600 proxy tokens OR raises the budget in prompt-token-budgets.json + ARCHITECTURE_CONTRACTS mirror in the same PR with a one-line note (the sanctioned ratchet path) |
| Requirement's repo-root `scripts/` location would break `${CLAUDE_PLUGIN_ROOT}` callers — source: Feasibility (Phase 2.5) | HIGH | Locked in this brief: runtime helpers go in `loomwright/scripts/`; record the deviation from the requirement text in the PR description |
| Spike Tier-A ranker failed validation — source: Feasibility (Phase 2.5) | MEDIUM | Reuse only signature extraction + exclusion list; Tier B is the deliverable floor; Tier A is probe-and-degrade best-effort |
| Stale memos trusted as prose | HIGH | AC3 staleness provenance is REQUIRED (written_at + head SHA, annotate/demote, fixture-tested) |
| Hostile-content memo injected into agent context | HIGH | Reader treats memos as DATA: per-object REJECT/skip + subordinate-to-CLAUDE.md banner; writer enforces add-rule.sh REJECT categories; both tested |
| macOS-green ≠ Linux-CI-green (stat/date/sed) | MEDIUM | No GNU-only flags; follow stat-flavor lesson (try `-c %Y` first, validate numeric); tests hermetic/offline |
| Uncommitted completion-tail edits swept by concurrent loop | HIGH | Automatic writes confined to gitignored `.supervisor/orientation-proposals/` (locked by AC4); committed store only via deliberate promote flow |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-07-20-orientation-memos-repo-map.md
```

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/103 (base main)
- **heal_loop_ran:** true | **heal_decision:** PASS | **heal_iterations:** 1 | **heal_remaining_issues:** 0
- **rubric_score:** null (no Outcomes Rubric in brief)
- **Until-mergeable dispatched:** false (auto_review suppressed by /automate; engine owns the drain)
- **Subtasks:** 4/4 completed (st1 fix round 1; st3/st4 review LOW/MEDIUM folded pre-merge)
