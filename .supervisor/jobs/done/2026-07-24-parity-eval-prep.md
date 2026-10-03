# Prepare FABLE_PARITY_EVAL corpus + runbook

## Task

**Problem Statement:** The team needs the FABLE_PARITY_EVAL experiment corpus and runbook because the pre-registered protocol has an empty results table and no execution instructions. Currently, the 15+ eval sessions cannot begin without knowing which requirements to use, which base commits to branch from, or how to record metrics. Success looks like: 5 selected requirements with verified base commits and a step-by-step runbook that makes execution repeatable.

**Goal:** Prepare the FABLE_PARITY_EVAL experiment materials so the 15+ sessions can be executed manually in separate sessions. This item does NOT execute any eval runs — it selects the corpus, identifies base commits, and writes the execution runbook.

## Source requirement
- **Source requirement:** .supervisor/requirements/twin-remediation/07-parity-ablation-eval.md

## Environment
- Git: main @ 065f964 (clean)
- Plugin: v15.14.0
- SPIKE doc: `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` (112 lines, `## Results` table EMPTY)
- Done jobs: `.supervisor/jobs/done/` (~50 completed briefs available for corpus selection)

## Prior art
The SPIKE doc already contains the pre-registered protocol (§Protocol steps 1–7), decision rule, metrics table, and empty results table. The requirement file (07-parity-ablation-eval.md) adds ablation arms on top. This brief adds only the two missing pieces: (1) the concrete corpus with base commits, and (2) the runbook that makes execution repeatable.

## Scope (revised — deliverables only, NO eval execution)
1. **Corpus selection:** scan `.supervisor/jobs/done/` briefs and select 5 requirements matching the protocol criteria:
   - Small-to-medium, orchestration-shaped (multi-file with at least one dependency between subtasks so the Phase 3 loop is exercised)
   - At least ONE of the 5 MUST have a real cross-subtask file dependency (a dependent subtask that reads/imports a file the producer subtask creates) — this is a hard protocol requirement (§Protocol step 1)
   - Prefer recent requirements (v14+) so the eval tests the current stack, not a historical one
   - Prefer requirements that completed with measurable outcomes (PR merged, tests green) so arm-2 and arm-3 have a known-good reference
2. **Base-commit identification:** for each selected requirement, identify the SHA on main immediately BEFORE the requirement's PR merge commit — this is the base from which all 3 arms will branch (protocol: "same base commit for all 3 arms of a requirement")
3. **Corpus documentation:** add a `## Corpus` section to `FABLE_PARITY_EVAL.md` (between `## Protocol` and `## Results`) listing each requirement with: slug, brief path, base commit SHA, PR number, why it was selected (criteria match), and which cross-subtask dependency it exercises (if any)
4. **Eval runbook:** add a `## Execution Runbook` section to `FABLE_PARITY_EVAL.md` (between `## Corpus` and `## Results`) with step-by-step instructions for:
   - Per-requirement arm execution (arm 1: bare Claude Code, arm 2: Loomwright default, arm 3: Loomwright + extras) with exact commands
   - Scratch-branch naming convention (`eval/<req-slug>/arm-<N>`)
   - Recording protocol (how to fill a results-table row: which session artifacts to read for each metric)
   - Isolation protocol (no PRs to main, branch deletion after metric extraction)
   - Ablation arm instructions for at least 2 single-lever arms: (a) minus QA rule libraries (replace qa-test-patterns/qa-gates/qa-strategy with a ~50-line intent doc), (c) minus magic budgets (convert hardcoded caps to soft defaults)
   - Re-run protocol (the standing section the original requirement calls for: "re-run the ablation set on every major model release")

## Non-goals
- Running any of the 15+ eval sessions (the actual runs are done manually in separate sessions)
- Filling the results table or producing verdicts
- Creating the scratch branches (they're created per-arm at execution time by the runbook instructions)
- Building the `model-capability` knob (speculative per original requirement §Scope item 4)
- Agent consolidation ablation arm (deferred per original requirement §Non-goals)

## Acceptance criteria
- [ ] `## Corpus` section in FABLE_PARITY_EVAL.md lists exactly 5 requirements with base-commit SHA, PR#, selection rationale
- [ ] At least 1 of the 5 has a documented real cross-subtask file dependency
- [ ] All 5 base-commit SHAs are verified-reachable via `git cat-file -t <sha>`
- [ ] `## Execution Runbook` section has step-by-step arm instructions (3 base arms + ≥2 ablation arms)
- [ ] Recording protocol maps each pre-registered metric to its concrete session artifact source
- [ ] Original pre-registered protocol (above the new sections) is byte-unchanged
- [ ] No other files modified (SPIKE-doc-only change)

## Parallelism Analysis
Single subtask, no overlap, no dependency graph. Fast-path eligible.

## Skill References
| Skill | Subtask | Usage |
|-------|---------|-------|
| (none) | — | Single-file documentation task; no runtime skills required |

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Fewer than 5 qualifying done-briefs match protocol criteria | Low | Would block corpus completion | 62 done briefs available; early scan shows ≥10 multi-subtask candidates |
| Base commit unreachable after history rewrite | Very low | Would invalidate a corpus entry | Verify each SHA via `git cat-file -t`; substitute if unreachable |
| SDK spike build breaks on current main | Low | Arm-3 runbook instructions untestable | Reference the build step as-documented; note the spike is quarantined and build verification is a pre-run step |

## Configuration
- Workers: 1
- Mode: sequential (single subtask)
- Fast-path: YES

## Subtask Structure
| # | Description | Files | Status |
|---|-------------|-------|--------|
| 1 | Corpus selection + runbook authoring | 1 modify (`loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md`) | LAUNCHABLE |

- **Recommended workers:** 1
- **Fast-path eligible:** YES (single subtask, single file, no cross-subtask dependencies)

### Subtask contracts

# Subtask 1 — Corpus selection + runbook (LAUNCHABLE, fast-path)

```yaml
provides:
  - kind: file
    path: loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md
    sections: ["## Corpus", "## Execution Runbook"]
requires: []
external_requires: []
```

**Goal:** Add `## Corpus` and `## Execution Runbook` sections to `FABLE_PARITY_EVAL.md`.

**Inputs:**
- `.supervisor/jobs/done/*.md` — scan for corpus candidates (read only)
- `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` — the SPIKE doc to extend
- `git log --oneline --all` — for base-commit identification
- `loomwright/docs/SPIKES/SDK_RUNNER_SPIKE.md` — for arm-3 build instructions and known gaps

**Process:**
1. Scan done briefs for multi-subtask requirements matching protocol criteria
2. For each candidate, verify the originating PR and compute the parent commit of the merge (`git log --oneline --merges --grep="<brief-slug>" origin/main` → `git rev-parse <merge>^`)
3. Select 5, prioritizing diversity of subtask structure and at least 1 with cross-subtask file dependency
4. Write `## Corpus` section with the 5 selections + rationale
5. Write `## Execution Runbook` section with per-arm instructions, recording protocol, isolation protocol, and ablation arm instructions
6. Verify original protocol text is byte-unchanged (diff the pre-existing sections)

**Outputs:**
- Modified `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` with two new sections
- No other files modified

**Constraints:**
- Insert new sections between `## Protocol` and `## Results` (preserve document flow)
- The `## Results` table and `## Outcome` section must remain byte-unchanged
- Arm-3 instructions must reference the SDK spike build step (`cd loomwright/sdk-spike && npm install && npm run build`) and note the known dependency-materialization gap (residual divergence 3)
- Ablation arm instructions must include incident-class regression checks per original requirement §Scope item 3

## Handoff
`/supervisor job: .supervisor/jobs/pending/2026-07-24-parity-eval-prep.md`

## Outcomes Rubric
- Corpus: 5 requirements selected with verified base commits and documented rationale
- Runbook: executable step-by-step instructions for all 3 base arms + ≥2 ablation arms
- Recording: each metric mapped to its concrete artifact source
- Byte-preservation: original pre-registered protocol unchanged
