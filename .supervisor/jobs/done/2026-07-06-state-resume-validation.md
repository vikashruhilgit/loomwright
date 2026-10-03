# Supervisor Job: Fail-closed validation of .supervisor/state.md on resume (small)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.2.3)
- **Git:** clean, branch: main @ be1535c (up to date with origin)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **legacy_brief:** true (single-subtask — inter-subtask contracts vacuous)
- **Source requirement:** .supervisor/requirements/review-remediation/04-state-resume-validation.md

## Task
**Goal:** `/supervisor --continue` refuses to act on a `.supervisor/state.md` whose `## Session` block doesn't parse against the known schema — fail-closed with a new closed error `resume_state_invalid` — instead of steering the run from unvalidated local state. READ-side gate only; prompt-surface (agents/skills/docs) change, no scripts.

## Acceptance Criteria
- [ ] Given loomwright/agents/supervisor.md's two resume anchors — Phase 0 INIT step 2 ("Check for resume state", ~line 113, incl. cost_profile hydration) and Phase 1 ACQUIRE ("Or read from .supervisor/state.md (resume)", ~line 203); anchor on the prose, not line numbers — when `--continue` loads a state file, then a strict parse gate runs BEFORE any state is consumed: `## Session` block must exist; `phase` ∈ {INIT, ACQUIRE, PLAN, EXECUTE, FINALIZE, SELF_HEAL, LOOP} and `status` ∈ {running, paused, completed, completed_with_escalation, failed} (both sourced from skills/state-management/SKILL.md §"State File Schema", lines 76-77 — cite the section in the gate text); if a `branch` field is asserted it must verify via `git rev-parse --verify <branch>`. On ANY violation: refuse resume, emit `SUPERVISOR_RESULT.status: failed` with `error: "resume_state_invalid"` + a user instruction to inspect/delete state.md or start fresh. NEVER silently fall back to fresh-start. No `--skip-*`/`--force-resume` escape hatch in v1 (deleting the file IS the escape hatch).
- [ ] Given skills/state-management/SKILL.md, when read, then a new subsection "Resume validation gate" documents the closed phase/status enums as the authoritative validation contract; skill `version:` bumped 1.1.0 → 1.2.0 (+ lastUpdated) AND the SKILLS_INDEX.md row updated in the SAME change (the new check-skills-index-sync.sh CI gate enforces this).
- [ ] Given loomwright/docs/RESULT_SCHEMAS.md, when read, then `resume_state_invalid` is documented as an additive SUPERVISOR_RESULT `error` value (follow the `preflight_overlap_detected` documentation precedent — errors are discussed in prose/tables there, verify placement first); NO schema_version bump; do NOT add a row to AUTONOMOUS_RUN's failed-status_reason table (~1424) — the autonomous loop never invokes `/supervisor --continue` (no resume contract in v1), so `resume_state_invalid` cannot surface there and `supervisor_failed_other` case (a) at :1435 is the catch-all; document this rationale inline instead (Plan Review resolution).
- [ ] Given loomwright/commands/supervisor.md, when read, then a Troubleshooting entry (and/or `--continue` row note) explains what `resume_state_invalid` means and how to recover — mirrored with the agent prose in the same commit (check-command-sync.sh does not cover this; sweep manually).
- [ ] Given CLAUDE.md §Common Pitfalls "Supervisor workflow interrupted?", when read, then one added line mentions the resume validation gate.
- [ ] Prompt-is-program dynamic trace documented in the PR description for 5 cases: valid file (byte-identical happy-path behavior — no semantic drift), missing file (fresh start, unchanged), unknown phase, unknown status, valid-but-branch-gone. Valid-resume prose unchanged except the inserted gate.
- [ ] Minor version bump 15.2.3 → 15.3.0 + CHANGELOG + README/CLAUDE.md banner rotation; counts unchanged 14/21/57/21; all 5 CI validators (incl. check-skills-index-sync.sh) green.

## Verified Evidence (Phase 3)
- Authoritative enums live at skills/state-management/SKILL.md:76-77 (`phase: INIT | ACQUIRE | PLAN | EXECUTE | FINALIZE | SELF_HEAL | LOOP`; `status: running | paused | completed | completed_with_escalation | failed`). Note PRE_FLIGHT_SYNC exists only as a record_decision phase label (SKILL.md:199), NOT a state-file phase — the gate's closed set must NOT include it.
- agents/supervisor.md resume touchpoints: Phase 0 step 2 ("Check for resume state", ~line 113, incl. cost_profile hydration) and Phase 1 ("Or read from .supervisor/state.md (resume)", ~line 203). The gate belongs where state is first consumed; keep the cost_profile hydration behavior for valid files unchanged.
- RESULT_SCHEMAS.md documents SUPERVISOR_RESULT error values in prose (preflight_overlap_detected precedent at :263/:288/:1460) and maps supervisor errors into AUTONOMOUS_RUN status_reasons at :1424.
- commands/supervisor.md has a Troubleshooting-adjacent structure and the mirrored-prompt-pair discipline ("keep the two in sync" notes) — agent↔command mirror required in one commit.
- state-management SKILL.md is at version 1.1.0; SKILLS_INDEX parity now CI-enforced (v15.2.3 gate).

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Resume gate in agents/supervisor.md + state-management SKILL.md subsection/bump + SKILLS_INDEX row + RESULT_SCHEMAS + commands/supervisor.md + CLAUDE.md pitfall + version 15.3.0 | ~11 modify | LAUNCHABLE |

## Parallelism Analysis
- Single subtask, fast-path, 1 worker (agent↔command↔skill↔schema mirror must land atomically).

## Skills
- state-management (the contract being extended), quality-checklist. Memory lesson: prompt-is-program — dynamic-trace the resume path.

## Configuration
- base branch: main; heal iterations: default 3.

## Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| Semantic drift to the valid-resume happy path | HIGH | AC mandates byte-identical happy-path prose except the inserted gate; 5-case dynamic trace in PR |
| Gate enum includes non-state phases (PRE_FLIGHT_SYNC) or misses one | MEDIUM | Enums copied verbatim from SKILL.md:76-77; reviewer cross-checks |
| Agent↔command mirror drift | MEDIUM | Same-commit mirror + manual sweep (check-command-sync.sh gap) |
| SKILLS_INDEX parity gate failure on skill bump | LOW | Index row updated in same change; run the new validator locally |
| RESULT_SCHEMAS placement wrong (invented enum table) | MEDIUM | Follow the preflight_overlap_detected additive-error precedent exactly; verify before writing |

## Test Plan
- All 5 repo-root validators green (incl. check-skills-index-sync.sh after the skill bump).
- Manual mirror sweep of agent↔command prose; 5-case dynamic trace pasted into the PR description.

## Out of Scope
Automated state repair, structured recovery from job dirs, validating `## Phase Flags` beyond parseability, any script/hook change.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-06-state-resume-validation.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/94
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1
- **heal_remaining_issues:** 0
- **rubric_score:** null (no Outcomes Rubric)
- **Until-mergeable dispatched:** false (default dispatch suppressed by /automate engine; owned inline drain follows)
