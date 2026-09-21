# Supervisor Job: Learning Loop Phase 4 — Churn Loop (Postmortem as Ledger)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — documents v14.35.0, matches plugin.json)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/auto-2026-06-18-214904-learning-loop-phase-4-churn-ledger.md

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + markdown agent prompts + jq; matches existing scripts/ and agents/ conventions |
| 2 | Dependency Availability | GO | jq, gh, git all present and authenticated |
| 3 | Architecture Fit | GO | Advisory/fail-safe/non-gating routing mirrors existing self-heal-advisory + read-lessons.sh machinery; bimodal failure philosophy preserved |
| 4 | Scope vs Supervisor Capability | GO | Decomposes into 5 subtasks of 30–60 min each |
| 5 | Hard Blockers | GO | None — no migrations, credentials present, target script absent (clean create) |

**Overall Verdict:** GO

## Task
**Goal:** Close the PR-churn learning loop — enrich `POSTMORTEM_RESULT` with provenance and feed prior-churn patterns back into Launch Pad planning and Supervisor Phase 4.5 self-heal, strictly advisory / fail-safe / non-gating.

**Problem Statement:**
Maintainers of this plugin need the accumulated postmortem corpus (`.supervisor/postmortem/results.jsonl`) to inform future planning and self-heal, because today it is **write-only** (`skills/pr-postmortem/SKILL.md`: "never read back by this skill") and carries thin provenance (only the PR number). Currently, prior churn lessons are recorded but never routed back to the next decision. This causes the same miss-classes to recur PR after PR. Success looks like: future planning can answer "have similar PRs churned before, and why?" and self-heal can prioritize known prior miss-classes for the touched files — without any gating or verdict change.

## Acceptance Criteria
- [ ] Given an enriched postmortem run, when `POSTMORTEM_RESULT` is appended, then it carries `pr_url`, `brief_path`, `job_path`, `branch`, and `changed_paths` (the list); and given an OLD corpus line lacking these, when any consumer parses it, then it still parses cleanly (additive, backward-compatible).
- [ ] Given `.supervisor/postmortem/results.jsonl` absent/empty OR `jq` missing, when `read-postmortem.sh` runs, then it exits 0 with quiet/empty output and never errors.
- [ ] Given prior churn entries whose `changed_paths` overlap a set of touched paths, when `read-postmortem.sh` is invoked with those paths, then it emits a bounded advisory summary of recurring root-cause classes / flow_stages; and given no overlap, then it emits nothing actionable.
- [ ] Given the read-back helper exists, when Launch Pad runs Phase 3/Phase 5, then it consults the helper and surfaces a prior-churn advisory Risk Assessment row for overlapping touched areas — advisory only, never blocking feasibility or save.
- [ ] Given prior churn miss-classes for files in the integrated diff, when Supervisor Phase 4.5 runs, then its review/fix prompt is enriched with those classes via the existing advisory machinery — and `heal_decision` + gating behavior are demonstrably unchanged by the enrichment.
- [ ] The postmortem corpus is NOT passed to workers.
- [ ] New/updated self-tests pass; `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` pass; plugin version bumped; CLAUDE.md banner + `CHANGELOG.md` entry added.

## Outcomes Rubric
- `pr-postmortem-gather.sh` success JSON emits `pr_url`, `branch`, and `changed_paths` (array) keys, and its `gh pr view --json` argument includes `url`, `headRefName`, and `files`.
- `skills/pr-postmortem/SKILL.md` Step 5 jq build and the trend-line schema table both list `pr_url`, `brief_path`, `job_path`, `branch`, `changed_paths`; and `docs/RESULT_SCHEMAS.md` POSTMORTEM_RESULT documents them as additive/optional (old lines remain valid).
- `scripts/read-postmortem.sh` exists, is executable, always exits 0, and emits an advisory markdown header subordinate-to-CLAUDE.md (mirroring `read-lessons.sh`).
- `scripts/test-read-postmortem.sh` exists with a fixture corpus and prints a `RESULT: N passed, M failed` line.
- `agents/launch-pad.md` references `read-postmortem.sh` with advisory/fail-safe wording, and `agents/supervisor.md` Phase 4.5 references prior-churn enrichment as non-gating.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions match and are bumped above 14.35.0; `CLAUDE.md` carries a new release banner.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Provenance enrichment (gather + schema + gather test) | AC1 | 4 modify, 0 create | pr-postmortem, monitoring-observability | LAUNCHABLE |
| 2 | Read-back helper `read-postmortem.sh` + self-test + fixture | AC2, AC3 | 0 modify, 3 create | error-handling, unit-testing | BLOCKED (by #1) |
| 3 | Wire read-back into Launch Pad planning/risk | AC4 | 1 modify, 0 create | supervisor-readiness | BLOCKED (by #2) |
| 4 | Wire read-back into Supervisor Phase 4.5 self-heal | AC5, AC6 | 2 modify, 0 create | self-heal-advisory | BLOCKED (by #2) |
| 5 | Docs + version bump + CHANGELOG + currency sweep | AC7 | ~6 modify, 0 create | quality-checklist | BLOCKED (by #1,#2,#3,#4) |

### Provides / Requires Contracts

```yaml
# Subtask 1 — Provenance enrichment (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh", name: "pr_url"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh", name: "branch"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh", name: "changed_paths"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md", name: "## POSTMORTEM_RESULT trend-line schema"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md", name: "POSTMORTEM_RESULT"}
requires: []
external_requires:
  - "gh CLI (read-only PR queries)"
  - "jq"

# Subtask 2 — Read-back helper + test + fixture (BLOCKED by #1)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/read-postmortem.sh"}
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-read-postmortem.sh"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh", name: "changed_paths"}
external_requires:
  - "jq"

# Subtask 3 — Launch Pad wiring (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "read-postmortem.sh"}
requires:
  - {from: "2", kind: "file", path: "ai-agent-manager-plugin/scripts/read-postmortem.sh"}
external_requires: []

# Subtask 4 — Supervisor Phase 4.5 wiring (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "read-postmortem.sh"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/self-heal-advisory/SKILL.md", name: "prior_churn"}
requires:
  - {from: "2", kind: "file", path: "ai-agent-manager-plugin/scripts/read-postmortem.sh"}
external_requires: []

# Subtask 5 — Docs + version bump (BLOCKED by #1,#2,#3,#4)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CLAUDE.md", name: "release banner"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "Phase 4 entry"}
requires:
  - {from: "1", kind: "symbol", path: "ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh", name: "changed_paths"}
  - {from: "2", kind: "file", path: "ai-agent-manager-plugin/scripts/read-postmortem.sh"}
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/agents/launch-pad.md", name: "read-postmortem.sh"}
  - {from: "4", kind: "symbol", path: "ai-agent-manager-plugin/agents/supervisor.md", name: "read-postmortem.sh"}
external_requires: []
```

### Subtask Detail Notes

**Subtask 1 — Provenance enrichment.** In `pr-postmortem-gather.sh`, add `url`, `headRefName`, and `files` to the load-bearing `gh pr view ... --json` argument, and emit three new success-JSON keys: `pr_url` (`.url`), `branch` (`.headRefName`), `changed_paths` (`[.files[].path]`). Keep all jq-built (no string interpolation), keep the unavailable-shape + fail-safe-exit-0 contract intact. In `skills/pr-postmortem/SKILL.md` Step 5, add `pr_url`, `brief_path`, `job_path`, `branch`, `changed_paths` to the jq object (sourcing `pr_url`/`branch`/`changed_paths` from the gathered JSON via `.field`; `brief_path`/`job_path` are best-effort — emit `null`/empty when not derivable for an arbitrary external PR, never invent) and document them in the trend-line schema table. Update `docs/RESULT_SCHEMAS.md` POSTMORTEM_RESULT (additive/optional, old lines valid; follow the `plugin_version` precedent — keep `schema_version: 1` unless a bump is clearly warranted, in which case keep v1 lines accepted). Extend `test-pr-postmortem-gather.sh` to assert the new keys appear (and round-trip safely under injection fixtures).

**Subtask 2 — Read-back helper.** Create `scripts/read-postmortem.sh` mirroring `read-lessons.sh`/`read-project-memory.sh` conventions: takes the touched paths as input (argv or stdin — pick the simplest fail-safe contract and document it), reads `.supervisor/postmortem/results.jsonl`, and emits a bounded advisory markdown summary of prior churn whose `changed_paths` overlap the input (recurring root-cause `class`/`flow_stage`, count of prior churn rounds, `self_heal_miss` lean). Tolerate OLD lines without `changed_paths` (skip them silently). Fail-safe: exit 0 + quiet when corpus absent/empty or `jq` missing; jq-only parsing, no untrusted PR text interpolated. Emit an advisory "subordinate to CLAUDE.md" header like the other readers. Create `test-read-postmortem.sh` + a fixture corpus (mirror `test-read-lessons.sh` structure: isolated temp dir, write-read round-trip, overlap/no-overlap/empty/old-line cases, `RESULT: N passed, M failed`).

**Subtask 3 — Launch Pad wiring.** In `agents/launch-pad.md`, add a `read-postmortem.sh` consult near the existing `read-lessons.sh`/`read-project-memory.sh` memory-consult step (Phase 3 ANALYZE), and a prior-churn advisory Risk Assessment row in Phase 5 (mirror the "Feasibility (Phase 2.5)" risk-row convention). Advisory only — never blocks the brief or changes the feasibility verdict. Use the same subordinate-to-CLAUDE.md / fail-safe wording as the other readers.

**Subtask 4 — Supervisor Phase 4.5 wiring.** In `skills/self-heal-advisory/SKILL.md`, add a fail-safe `read-postmortem.sh` advisory block (mirror the contract-conformance block shape) that summarizes prior churn miss-classes for the integrated diff's touched files. In `agents/supervisor.md` Phase 4.5, reference that block so the Code Reviewer review/fix prompt is enriched with prior-churn miss-classes for touched files. Strictly advisory — never changes `heal_decision`, never drives the fix task on its own, never gates. Do NOT route the corpus to workers.

**Subtask 5 — Docs + version.** Bump `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (keep versions equal — `validate-version.sh`), update the `marketplace.json`/`plugin.json` `description` version string in place (do NOT append a version clause). Add a CLAUDE.md release banner (keep only the two most recent; move the oldest displaced banner to CHANGELOG). Add a `CHANGELOG.md` entry. Sweep every current-claim version string the doc-currency gate scans (README headline, AGENT_GUIDELINES, docs/ARCHITECTURE*.md, .claude-plugin/README.md) to the new version. Counts (agents/commands/skills/hooks) are UNCHANGED — new `.sh`/test/fixture scripts are uncounted. Run `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` and confirm green.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3 ──┐
                        └──→ Subtask 4 ──┼──→ Subtask 5
Subtask 1 ───────────────────────────────┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (S2 creates new files) | YES (logical: S2 reads S1's `changed_paths` field) |
| Subtask 2 | Subtask 3 | none | YES (S3 references S2's new script) |
| Subtask 2 | Subtask 4 | none | YES (S4 references S2's new script) |
| Subtask 3 | Subtask 4 | none (launch-pad.md vs supervisor.md/self-heal-advisory) | NO (parallel-safe) |
| Subtask 5 | all | none (manifests + version-bearing docs are disjoint from S1–S4 targets) | YES (finalize after all) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2
- **Batch 3:** Subtask 3, Subtask 4 (parallel — disjoint files)
- **Batch 4:** Subtask 5
- **Recommended workers:** 2
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/pr-postmortem/SKILL.md`, `skills/monitoring-observability/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 3 | `skills/supervisor-readiness/SKILL.md` |
| 4 | `skills/self-heal-advisory/SKILL.md` |
| 5 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Producer→consumer coupling across worktrees (S2 reads S1's field; S3/S4 reference S2's script) | MEDIUM | Strict `requires` chain serializes S1→S2→{S3,S4}→S5; merged Phase 4.5 holistic review validates the cross-file contract (known worktree-isolation false-positive resolved at integration review, not per-subtask) |
| Accidentally introducing a gate / verdict change from ledger content | HIGH | AC explicitly requires advisory-only; every reader fail-safe exit 0; reviewers must confirm `heal_decision`/feasibility unchanged |
| Untrusted PR text injected via `changed_paths`/summary into jq or prompts | HIGH | jq-only construction (`--arg`/`--argjson`), no string interpolation — mirror `pr-postmortem-gather.sh` injection-safety pattern |
| Doc-currency / version-consistency CI failure from incomplete version sweep | MEDIUM | S5 runs `check-doc-currency.sh` + `validate-version.sh` to green; `## Executable Acceptance` declares both invariants for Phase 4.5 ground-truth |
| Schema bump breaking old corpus lines | MEDIUM | Additive/optional fields, keep `schema_version: 1` (plugin_version precedent); read-back helper tolerates missing `changed_paths` |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 4
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-06-18-214904-learning-loop-phase-4-churn-ledger.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-18T17:27:37Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/69
- **Branch:** feature/phase4-churn-ledger
- **Files changed:** 15
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (holistic Code Reviewer PASS on first pass; no fix iterations needed)
- **Rubric score:** 6/6
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false (foreground session; holistic review clean — offered to user instead)
- **Summary:** Learning Loop Phase 4 churn ledger — POSTMORTEM_RESULT provenance enrichment + fail-safe read-postmortem.sh wired advisory-only into Launch Pad + Supervisor Phase 4.5. v14.36.0. 45 tests pass; doc-currency + validate-version green.
