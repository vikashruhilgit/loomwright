# Supervisor Job: Shared local services declared, not assumed (host CLAUDE.md → brief → spawn paste)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ 63ec5e3)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/harness-port/06-shared-local-services.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown agent/skill prompt edits only (`launch-pad.md`, `supervisor-readiness/SKILL.md`, `async-orchestration/SKILL.md`, `plan-reviewer.md`, `POINTER_AUDIT.md`) — matches the plugin's existing prompt-engineering tech stack exactly. |
| 2 | Dependency Availability | GO | No new dependency; the extraction/bounding rule (strip fences, ≤10 non-empty lines, `(truncated)`) is prose the LLM agent executes itself, mirroring the existing Cited-line premise check's bounding style already in `launch-pad.md`. |
| 3 | Architecture Fit | GO | Extends the EXISTING pointer-vs-paste transport discipline (`async-orchestration/SKILL.md` §"Pointers, not payloads") with a documented, enumerated paste exception in `docs/POINTER_AUDIT.md` — precedent-following, not novel plumbing (rows 6/6b already establish the "bounded, producer-side, worktree-workers-can't-read-the-brief" justification this item reuses). |
| 4 | Scope vs Supervisor Capability | GO | 5-file, single cohesive transport-chain change (one optional line flowing from host `CLAUDE.md` through Launch Pad Phase 1/Phase 5 into every worker spawn site) plus one independent doc-drift fix (`Base commit` row). Every file depends on the same `shared_local_services` value/shape — splitting would only add coordination overhead. |
| 5 | Hard Blockers | GO | No migration, no credentials, no missing modules. Depends on item 01 (worker rule (c), already merged — PR #259) which this item's spawn-line consumer wiring assumes exists. |

**Overall Verdict:** GO

## Task
**Goal:** An optional `## Shared local services` section in the host project's `CLAUDE.md` is read once at Launch Pad Phase 1, bounded, copied into the brief's `## Environment`, and pasted verbatim into every worker spawn prompt as one `Shared local services:` line — so item 01's already-merged worker rule (c) (shared local services are read-only under parallel execution) has something to actually consume. Section absent ⇒ no brief line, no spawn line, byte-identical to today.

**Problem Statement:**
Parallel workers in worktrees can reset or write the same local `<service>` (database, cache, a dev server on a shared port) and corrupt a sibling's run. Nothing in the brief, the spawn contract, or the worker prompt names the services a project shares — that information exists only in the operator's head or in a host `CLAUDE.md` paragraph no agent is told to look for. Because `.supervisor/` is absent inside worktrees and the spawn contract is pointers-not-payloads, a line written only into the brief's `## Environment` would never reach the worker that needs it without an explicit paste step.

## Acceptance Criteria
- [ ] `loomwright/agents/launch-pad.md` Phase 1 VALIDATE (the `### Phase 1: VALIDATE (Environment Readiness)` section, ~line 99) gains a new action **8**, appended after the existing action 7 "Source-doc provenance check" (no renumber of 1–7): read the host `CLAUDE.md` for a heading matching `^## Shared local services\b` (case-insensitive on the words, exact level 2); take the body up to the next `^## ` heading; **bound it** — strip fenced code blocks entirely, keep at most 10 non-empty lines, append `(truncated)` when more existed; collapse to one line joined by ` · `. Hold as `shared_local_services` in session memory for Phase 5. Absent heading or empty body ⇒ unset (never emit `shared_local_services: ""`).
- [ ] `launch-pad.md` Phase 5 PACKAGE step 3a (~line 493, beside the existing `- **Source requirement:**` line): when `shared_local_services` is set, emit `- **Shared local services:** <line>` in the brief's `## Environment`; when unset, emit nothing — copy the existing "do NOT emit an empty or 'none' placeholder" sentence verbatim (the same sentence already governing the `Source requirement` line at that spot).
- [ ] `loomwright/skills/supervisor-readiness/SKILL.md` brief template `## Environment` (~line 123-129): add the optional `- **Shared local services:** {…, OPTIONAL — omitted entirely when the host CLAUDE.md has no matching section}` row directly after the existing `Source requirement` row. **Also fix a pre-existing, independent doc-drift bug found during Launch Pad's own Phase 5 step 3a reading:** `launch-pad.md` already unconditionally emits a `- **Base commit:** {sha}` line (v15.19.0, 4g(a)) but the brief-template doc never documents it — add `- **Base commit:** {sha — full commit SHA the brief was planned against, unconditional}` to the same `## Environment` template block, right after `Source requirement`/before `Shared local services`. Note this fix explicitly in the CHANGELOG paragraph as a doc-only correction, distinct from this item's new feature.
- [ ] `loomwright/skills/async-orchestration/SKILL.md` Part 2 spawn contract: when the brief's `## Environment` carries the `Shared local services` line, paste it verbatim into the Sequential-path and Single-Agent-path worker `Task()` blocks (lines ~728-774) as `Shared local services: <line>`. **Separately, `loomwright/agents/execute-manager.md` Step 3's own worker `Task()` prompt template (~line 184 — a SEPARATE, independently-authored prose block, NOT inherited from async-orchestration.md; confirmed distinct per `docs/POINTER_AUDIT.md` row 5) is the actual Parallel-path spawn site and MUST independently gain the same `Shared local services: <line>` paste** — the two files' worker-spawn prompts are maintained separately in this repo (POINTER_AUDIT.md rows 1-4/6-6b vs row 5) and neither inherits from the other; both need the edit. This is a deliberate PASTE exception (small, bounded, producer-side) — add a new row to `loomwright/docs/POINTER_AUDIT.md`'s table (after the existing row 6b, numbered 6c) with rationale text: "worktree workers cannot read the brief; ≤10 lines, fences stripped, bounded at the producer" (mirror rows 6/6b's justification style), and its site column should name BOTH files. Re-measure `execute-manager`'s token budget live (`loomwright/docs/prompt-token-budgets.json`) — do not trust the source requirement's cited "3216" figure; independently re-read the CURRENT measured/budget/headroom at implementation time (live figures at brief-authoring time: budget 38646, measured 35132, headroom 3514 — already stale relative to the requirement's citation) and raise + mirror in `ARCHITECTURE_CONTRACTS.md` only if breached by the added prose.
- [ ] `loomwright/agents/plan-reviewer.md` Criterion 9 (Completeness, ~line 162-179): add one sentence to its existing `Note:` block — the `Shared local services` line is optional and its absence is not evaluated (mirror the EXACT existing `## Feasibility` optional-note sentence pattern at line 179: `"The `## X` section … is **optional** — its absence is not BLOCKING and is not evaluated here."`). Criterion count stays 16 (no new criterion, no renumber).
- [ ] **Portability guard (this repo's own CLAUDE.md is a host too):** the plugin's new prose in all touched files names only `<service>`, `<how to reach it>`, `<PORT_ENV>` as placeholders — the worked example is `- <service>: <how to reach it> (<PORT_ENV> if any)` — no real product name, host name, or literal port number anywhere in the new text.
- [ ] Fixture: a host `CLAUDE.md` WITH a 3-line `## Shared local services` section ⇒ the assembled brief differs from the same run WITHOUT that section by exactly one `- **Shared local services:** …` line (a fixture diff test; record the exact command used in the PR body per the AC's own instruction).
- [ ] Fixture: a host `CLAUDE.md` with 14 body lines under the heading, including one fenced code block ⇒ the resulting line has exactly 10 items (the fence's lines excluded from the count), no fence content leaks into the line, and it ends with `(truncated)`.
- [ ] Fixture: a host `CLAUDE.md` with the `## Shared local services` heading present but an empty body (immediately followed by the next `^## ` heading or EOF) ⇒ no `Shared local services` line emitted anywhere (brief, spawn prompts) — byte-identical to the section-absent case.
- [ ] `grep -c 'Shared local services' loomwright/skills/async-orchestration/SKILL.md` ≥ 1 AND `grep -c 'Shared local services' loomwright/agents/execute-manager.md` ≥ 1 (the paste-rule text is actually present at BOTH independent worker-spawn sites, not just described in the brief — Plan Review caught that the brief's original AC only asserted the async-orchestration.md side, silently missing the parallel-path site).
- [ ] `grep -n 'Base commit' loomwright/skills/supervisor-readiness/SKILL.md` ≥ 1 (the independent doc-drift fix landed).
- [ ] Plan Reviewer Criterion 9's existing body (the "Check:"/"How:"/numbered-list/"Severity if failed:" content) is UNCHANGED except for the one added `Note:` sentence; criteria count stays 16 (grep-verify against `origin/main`'s Criterion count).
- [ ] `grep -nE 'localhost|127\.0\.0\.1|:[0-9]{4}\b|postgres|mysql|redis|docker' <every file this item touches>` → 0 new hits vs `origin/main` on the same files (the portability guard is mechanically checkable, not just self-reported).
- [ ] `scripts/check-token-budget.sh` green (execute-manager re-measured, raised only if breached); full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh`) green; `scripts/check-doc-currency.sh` green; CHANGELOG paragraph + `plugin.json` + `marketplace.json` version bump (patch — additive, non-breaking; current version 15.99.0 → 15.100.0, re-verify live at implementation time in case another item merged first).

## Non-goals (from the source requirement — do not implement)
No parsing of the service list into structure — it stays free text for the worker to read as-is. No enforcement mechanism — the plugin cannot stop a worker's `<service-cli>` call; the rule stays advisory, and item 01's honest-limits mechanism carries what a worker admits it skipped. No port-allocation service — the `<PORT_ENV>` ordinal-offset convention is something the host app may or may not honor, and item 01's rule already says so; this item does not change that.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Parallelism Analysis
- **Mode:** single-agent (no fan-out) — one LAUNCHABLE subtask, no dependents, no file-conflict/context-bound/genuine-parallelism reason to split (see Feasibility #4).
- **Recommended workers:** 1

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation quality gates for any worker task. |
| supervisor-readiness | Authority for the Supervisor-Ready Brief template this item adds two rows to (`Shared local services`, `Base commit`). |
| async-orchestration | Authority for the spawn contract's "Pointers, not payloads" discipline and the `docs/POINTER_AUDIT.md` exception register this item's paste rule extends. |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Shared local services: host CLAUDE.md read → bounded → brief Environment line → worker spawn paste (all 3 paths) + Base-commit doc fix + POINTER_AUDIT row + Plan Reviewer note | all | 10 modify, 0 create | quality-checklist, supervisor-readiness, async-orchestration | LAUNCHABLE |

```yaml
# Subtask 1 — shared local services, end-to-end transport (LAUNCHABLE)
subtask_id: shared-local-services-01
title: "Shared local services: host CLAUDE.md read + bound → brief Environment → worker spawn paste (all 3 paths) + Base-commit doc fix"
lanes:
  - loomwright/agents/launch-pad.md
  - loomwright/skills/supervisor-readiness/SKILL.md
  - loomwright/skills/async-orchestration/SKILL.md
  - loomwright/agents/execute-manager.md
  - loomwright/agents/plan-reviewer.md
  - loomwright/docs/POINTER_AUDIT.md
  - loomwright/docs/prompt-token-budgets.json
  - loomwright/docs/ARCHITECTURE_CONTRACTS.md
  - CHANGELOG.md
  - loomwright/.claude-plugin/plugin.json
  - .claude-plugin/marketplace.json
requires: []
external_requires: []
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "shared_local_services"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "Shared local services"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "Base commit"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "Shared local services"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "Shared local services"}
  - {kind: "symbol", path: "loomwright/docs/POINTER_AUDIT.md", name: "6c"}
out_of_lane: []
```

## File Impact Map
- **Modify:** launch-pad.md, supervisor-readiness/SKILL.md, async-orchestration/SKILL.md, execute-manager.md (the actual Parallel-path worker `Task()` template — Plan Review caught this missing from the original File Impact Map, per `docs/POINTER_AUDIT.md` row 5), plan-reviewer.md, POINTER_AUDIT.md, prompt-token-budgets.json (+ possibly ARCHITECTURE_CONTRACTS.md), CHANGELOG.md, plugin.json, marketplace.json.
- **Create:** none.

## Risk Assessment
- **Portability leak into this plugin's own committed text.** Risk: a worked example accidentally names a real service/host/port, defeating the portability guard this item exists to model. Mitigation: the mechanized `grep -nE 'localhost|127\.0\.0\.1|:[0-9]{4}\b|postgres|mysql|redis|docker'` AC is a hard gate, not a self-report.
- **Three independent spawn call sites (parallel/sequential/single-agent) must paste the SAME line consistently.** Risk: one path drifts from the other two. Mitigation: `async-orchestration/SKILL.md`'s existing "Pointers, not payloads" precedent already threads three near-identical spawn-contract blocks (see the `Context digest pointer` example already doing this for `CONTEXT_DIGEST`) — worker should follow that exact structural pattern rather than re-deriving one.
- **Bounding logic (strip fences, ≤10 lines, `(truncated)`) is prose the LLM executes, not a script** — same honest limit as the Cited-line premise check and the dismissed-findings marker-comment logic (harness-port/03, /05): no executable test harness for Launch Pad's own Phase-1 prose exists in this repo, so the three fixture ACs are read-through-and-hand-trace verifications, not automated script tests. Document this as an honest limit if no suitable harness is found, rather than inventing a false claim of automated coverage.

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## Handoff
Run: `/supervisor job: .supervisor/jobs/pending/2026-09-24-shared-local-services.md`

## Environment Validation
- ✓ `gh` authenticated, ✓ `git` clean, ✓ item 01 (worker rule (c)) already merged to `main` (PR #259) — this item's spawn-line consumer dependency is satisfied.
