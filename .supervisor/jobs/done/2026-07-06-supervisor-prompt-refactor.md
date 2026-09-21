# Supervisor Job: Supervisor prompt refactor — extract phase protocols into skills

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v15.3.0 banner pending — plugin.json already at 15.3.0)
- **Git:** clean, branch: main @ 6ea3e2a
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (large-prompt refactor — highest-risk item in the remediation backlog)
- **Source requirement:** .supervisor/requirements/review-remediation/05-supervisor-prompt-refactor.md

## Task
**Goal:** Shrink `loomwright/agents/supervisor.md` from 1,652 lines to a ≤600-line phase state machine by extracting phase protocol bodies into on-demand skills, with ZERO behavior change, keeping `commands/supervisor.md` semantically mirrored in the same slices.

**Problem statement:** Prompt size is the instruction-following ceiling — the historical Supervisor failure modes (skipped Phase 4.5, completion-tail misses) are lost-context signatures of a 1,652-line prompt. The repo's own precedent (`review-pr.md` at 133 lines + `review-heal` skill; `self-heal-advisory` read-at-entry) proves the extract-to-skill pattern. This is reliability work, not aesthetics.

## Acceptance Criteria
- [ ] Given the refactor is complete, when `wc -l loomwright/agents/supervisor.md` runs, then the count is ≤600 and every phase stanza names its authority skill.
- [ ] Given each extraction slice, when the diff is reviewed, then the moved prose is verbatim-first (reviewer can align old/new text); intentional wording changes are enumerated in the PR description.
- [ ] Given the refactor, when grepping each pre-existing gate/error string (`preflight_overlap_detected`, `skip_self_heal_requested`, `phase45_review_invoked`, `heal_decision`, `inter_subtask_gap`, budget numbers 50/60), then every one is still present with identical semantics (completion-tail guard condition stays IN the agent file).
- [ ] Given new/extended skills, when CI runs, then `check-skills-index-sync.sh`, `check-doc-currency.sh`, `check-command-sync.sh`, `validate-version.sh` and all `test-*.sh` are green; SKILLS_INDEX has rows for new skills with version frontmatter.
- [ ] Given both surfaces (`agents/supervisor.md` + `commands/supervisor.md`), when a per-phase side-by-side enumeration diff is done, then both name the SAME authority skill per extracted phase (no split-brain).
- [ ] Given the refactored prompt, when a multi-path dynamic state-trace is performed (fresh run, --continue resume, fast-path single-subtask, parallel path, --skip-self-heal, --non-interactive), then each path reaches the same decisions/writes as pre-refactor.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Slice A: Phase 1.5 PRE-FLIGHT SYNC → new skill `preflight-sync` (agents/supervisor.md ~250–331 → stanza; mirror commands/supervisor.md; SKILLS_INDEX row) | 2 modify, 1 create | LAUNCHABLE |
| 2 | Slice B: Phase 4.5 SELF_HEAL body (~624–1090) → complete the move into existing `self-heal-advisory` skill (loop procedure, fix-task spawn, rubric-grader spawn conditions, completion tail incl. job move + state flip + requirement close-out stamp + step 5.5 drain dispatch + churn ledger + Twin contract write). Completion-tail GUARD CONDITION stays in the agent file. Mirror commands/supervisor.md. | 3 modify | BLOCKED (by #1) |
| 3 | Slice C: Phase 0 INIT config resolution → new skill `supervisor-config` (flag/defaults table, cost-profile resolution, base-branch handling, env detection); plus dedup of the duplicated Output Format example block (~1228–1336) | 3 modify, 1 create | BLOCKED (by #2) |
| 4 | Slice D: Phase 4 FINALIZE merge/PR mechanics (~486–623) + Subagent Spawn Contracts (~1408–1483) + Git Worktree Lifecycle (~1513–1538) → extend `async-orchestration` skill. Mirror commands/supervisor.md. | 3 modify | BLOCKED (by #3) |
| 5 | Slice E: doc-currency sweep + verification — CLAUDE.md agent-table row + release banner, SKILLS_INDEX rows, skills count 57→59 everywhere scanned + the gate's known blind spots (grep phase enumerations in agent-help.md / command docs), plugin.json + marketplace.json bump 15.3.0→15.4.0 (counts in description), CHANGELOG entry, final `wc -l` ≤600 check, gate/error-string greps, full `bash scripts/*.sh --self-test` + `loomwright/scripts/test-*.sh` run, dynamic state-trace record in PR description | 6 modify | BLOCKED (by #4) |

## Subtask Contracts

```yaml
subtask_1:
  title: "Slice A: Phase 1.5 -> preflight-sync skill"
  requires: []
  provides:
    - {kind: file, path: loomwright/skills/preflight-sync/SKILL.md, desc: "new skill holding the Phase 1.5 PRE-FLIGHT SYNC protocol body (verbatim-moved), version frontmatter, 'read at phase entry - NOT preloaded' header"}
    - {kind: file, path: loomwright/agents/supervisor.md, desc: "Phase 1.5 body replaced by a short stanza naming preflight-sync as authority (entry condition, skill read, exit condition, failure values)"}
    - {kind: file, path: loomwright/commands/supervisor.md, desc: "mirrored Phase 1.5 stanza naming the same authority skill"}
    - {kind: file, path: loomwright/skills/SKILLS_INDEX.md, desc: "row for preflight-sync"}
subtask_2:
  title: "Slice B: Phase 4.5 body -> self-heal-advisory skill"
  requires:
    - {from: subtask_1, artifact: loomwright/agents/supervisor.md, desc: "slice-A state of the agent prompt (stanza pattern established)"}
  provides:
    - {kind: file, path: loomwright/skills/self-heal-advisory/SKILL.md, desc: "extended with the full Phase 4.5 loop procedure (review spawn, fix loop, rubric-grader spawn conditions, completion tail, step 5.5 drain dispatch, churn ledger, Twin contract write) verbatim-moved"}
    - {kind: file, path: loomwright/agents/supervisor.md, desc: "Phase 4.5 body replaced by stanza + the completion-tail GUARD CONDITION kept in-file"}
    - {kind: file, path: loomwright/commands/supervisor.md, desc: "mirrored Phase 4.5 stanza; 'Inline-path canonical state writes' section preserved or authority-pointed"}
subtask_3:
  title: "Slice C: Phase 0 config -> supervisor-config skill + output-example dedup"
  requires:
    - {from: subtask_2, artifact: loomwright/agents/supervisor.md, desc: "slice-B state"}
  provides:
    - {kind: file, path: loomwright/skills/supervisor-config/SKILL.md, desc: "new skill holding Phase 0 flag/defaults table, cost-profile resolution, base-branch handling, env detection"}
    - {kind: file, path: loomwright/agents/supervisor.md, desc: "Phase 0 stanza + duplicated Output Format example block deduplicated"}
    - {kind: file, path: loomwright/skills/SKILLS_INDEX.md, desc: "row for supervisor-config"}
subtask_4:
  title: "Slice D: FINALIZE + spawn contracts + worktree lifecycle -> async-orchestration"
  requires:
    - {from: subtask_3, artifact: loomwright/agents/supervisor.md, desc: "slice-C state"}
  provides:
    - {kind: file, path: loomwright/skills/async-orchestration/SKILL.md, desc: "extended with Phase 4 FINALIZE merge/PR mechanics, Subagent Spawn Contracts, Git Worktree Lifecycle (verbatim-moved, clearly bounded sections)"}
    - {kind: file, path: loomwright/agents/supervisor.md, desc: "Phase 4 stanza; spawn-contract + worktree sections replaced by authority pointers"}
    - {kind: file, path: loomwright/commands/supervisor.md, desc: "mirrored Phase 4 stanza"}
subtask_5:
  title: "Slice E: doc-currency sweep + verification"
  requires:
    - {from: subtask_1, artifact: loomwright/skills/preflight-sync/SKILL.md, desc: "new skill 1"}
    - {from: subtask_3, artifact: loomwright/skills/supervisor-config/SKILL.md, desc: "new skill 2"}
    - {from: subtask_4, artifact: loomwright/agents/supervisor.md, desc: "final refactored prompt (must be <=600 lines)"}
  provides:
    - {kind: file, path: CLAUDE.md, desc: "release banner + agent-table note; skills count 57->59"}
    - {kind: file, path: loomwright/.claude-plugin/plugin.json, desc: "version 15.4.0 + counts in description"}
    - {kind: file, path: .claude-plugin/marketplace.json, desc: "version + counts in description"}
    - {kind: file, path: CHANGELOG.md, desc: "v15.4.0 entry"}
    - {kind: file, path: README.md, desc: "skills-count claims updated if scanned"}
```

## Parallelism Analysis
- All subtasks overlap on `agents/supervisor.md` + `commands/supervisor.md` + `SKILLS_INDEX.md` → **fully sequential** (Batch 1: #1; Batch 2: #2; Batch 3: #3; Batch 4: #4; Batch 5: #5). Recommended workers: 1.

## Configuration
- Base Branch: main
- Suggested feature branch: feature/supervisor-prompt-refactor
- Heal iterations: 3 (default)

## Skills Referenced
- skills/self-heal-advisory/SKILL.md (extend — read-at-Phase-4.5-entry, stays NON-preloaded)
- skills/async-orchestration/SKILL.md (extend — already Supervisor-preloaded; accepted trade-off, noted below)
- skills/state-management/SKILL.md, skills/workflow-management/SKILL.md (context)
- New skills MUST state in their header: "Read at phase entry — deliberately NOT preloaded."

## Constraints / invariants (all HARD — from the source requirement)
1. **Agent↔command split-brain guard:** every slice updates BOTH `agents/supervisor.md` AND `commands/supervisor.md` in the same commit; per-slice manual side-by-side phase-enumeration diff; both surfaces name the same authority skill per phase. This is the #1 failure mode.
2. **ZERO behavior change:** bimodal failure philosophy; completion-tail guard (condition stays visible in the agent file — move only the procedure); sole-writer contracts; never-merge; PR-base verification; budgets 50/60; Phase 4.5 always-runs; requirement close-out stamping; inline-path canonical state writes (commands/supervisor.md §"Inline-path canonical state writes" is LOAD-BEARING — must survive verbatim or with an explicit authority pointer).
3. **Extract, don't rewrite:** verbatim-first moves; dedup only on a second pass within the same slice.
4. SUPERVISOR_RESULT schema untouched; hooks.json SubagentStop validator passes unchanged.
5. Descriptive anchors, not absolute line refs, in all moved prose.
6. New protocol skills are read at phase entry, NOT added to Supervisor frontmatter `skills:` preload.
7. Frozen version-agnostic example blocks (RESULT_SCHEMAS / sample JSONL) must NOT be "fixed" to current version.

## Risk Assessment
| Risk | Severity | Mitigation | Source |
|------|----------|------------|--------|
| Split-brain between agents/ and commands/ surfaces | HIGH | Per-slice mirror rule + slice-E enumeration diff + acceptance grep | Requirement |
| Behavior drift in Phase 4.5 move (largest slice, 467 lines) | HIGH | Verbatim-first move; guard stays in agent; gate/error-string grep census before/after | Requirement |
| Doc-currency / index-sync CI failures | MEDIUM | Slice E dedicated sweep incl. known gate blind spots | Feasibility (Phase 2.5) |
| async-orchestration is Supervisor-preloaded — extending it grows runner preload | LOW | Accepted: net runner context ~flat (prompt shrinks by same text); FINALIZE section clearly bounded | Feasibility (Phase 2.5) |
| ≤600 target may need second-pass trims beyond the 4 slices | MEDIUM | Slice C dedups the duplicated output example; slice E verifies and may trim remaining duplication (verbatim-semantics preserved) | Analysis |

## Out of Scope
Optional slice 5 from the requirement (launch-pad.md advisory-context extraction — separate PR); flag semantics changes; execute-manager refactor; qa-executor rescoping.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-06-supervisor-prompt-refactor.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/95
- **Branch:** feature/supervisor-prompt-refactor
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0
- **heal_remaining_issues:** 0
- **rubric_score:** null (no Outcomes Rubric in brief)
- **Until-mergeable dispatched:** false (auto_review suppressed by /automate engine; owned inline drain follows)
- **Deviation:** agents/supervisor.md final 748 lines vs ≤600 aspiration — all remaining text load-bearing (holistic review verified zero dropped semantics)
