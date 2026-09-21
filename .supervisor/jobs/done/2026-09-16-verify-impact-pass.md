# Supervisor Job: Impact pass for /verify — surfaces the diff plausibly affects, scored separately from the ticket

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/verify-walkthrough/06-verify-impact-pass.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash/jq/python3 — the same runtime already used by `verify-run.sh`/`verify-helpers.sh`/`validate-verify-evidence.py`. No new dependency. |
| 2 | Dependency Availability | GO | `git diff --name-only`, `jq`, `python3` are already in use throughout this script family. |
| 3 | Architecture Fit | GO | Extends the existing event-sourced `evidence.jsonl` model. The `scope` field (`ticket`\|`impact`) already exists in the schema and is already required on every `ac` line (`validate-verify-evidence.py` `AC_SCOPES`) — items 01-03 already anticipated this split; only a new event type (`impact_surfaces`) and one new optional `ac` field (`surfaces`) are added. |
| 4 | Scope vs Supervisor Capability | CAUTION | The requirement doc cites "qa-executor Phase 9" for route-handler detection, but Phase 9 is actually "MISSING FUNCTIONALITY ANALYSIS" (unrelated). The real route/topology detection lives in Phase 4 "APP TOPOLOGY DETECTION" (`agents/qa-executor.md`) and is pure agent-prose — there is no shared script to call. This brief scopes the file→surface **classification** as agent-judgment work inside a new qa-executor VERIFY MODE step (reusing Phase 4's detection prose as instructed guidance), and scopes only the raw `git diff --name-only` file listing as mechanical script work. See Risk Assessment. |
| 5 | Hard Blockers | GO | No migration framework, no new credentials. `.supervisor/verify/` being fully gitignored (fresh clone/worktree/CI has zero prior runs) is a disclosed, accepted limitation — not a blocker (see Risk Assessment). |

**Overall Verdict:** CAUTION (proceeding — finding folded into Risk Assessment below, no override needed)

## Task
**Goal:** `/verify` walks, in addition to the ticket's own ACs, a bounded set of surfaces the diff plausibly affects, and records those verdicts with `scope: "impact"` so they never inflate or deflate the ticket's own score.

**Problem Statement:**
Loomwright operators need to know what else a change could have broken, not just whether the ticket's own ACs pass, because a ticket's ACs say nothing about the neighbour the diff touched. Currently, three sources of "impacted surface" already exist in the plugin — the diff itself, Launch Pad's File Impact Map + blast-radius section (computed per brief and then thrown away), and (since item 03 shipped) prior verify runs' `ac` lines tied to the routes they exercised — and none of them are consumed after the run. This causes reviewers to have no signal about collateral damage from a change beyond what the ticket itself tests. Success looks like: `/verify` emits a separate, bounded "impact" verdict set — sourced from the diff, the brief (when populated), and prior passing ACs on the same routes — that never changes the ticket's own score, and states the bound it used.

## Acceptance Criteria
- [ ] Given a verify run whose diff touches N files, when the impact pass runs, then `evidence.jsonl` has exactly one `impact_surfaces` event line naming every changed file with either a classified `surface` or `unmapped` — unmapped files are listed, never guessed.
- [ ] Given impact-scope verdicts (prior-AC re-runs and per-surface smoke checks) are written to `evidence.jsonl`, then each carries `scope: "impact"`, and `summary_build`'s ticket PASS/FAIL/BLOCKED/NOT_VERIFIABLE counts line is computed only from `scope: "ticket"` `ac` lines — an impact FAIL never changes the ticket's counts, rendered in a separate impact table/line.
- [ ] Given a brief in `.supervisor/jobs/done/` matching the ticket's requirement path (via its header back-reference) with a populated File Impact Map, when the impact pass runs, then its subsystem names are added to `impact_surfaces` tagged `source: "brief"`; given no matching brief, or a brief whose Blast-Radius subsection is omitted (the common case in this repo today — verified zero populated examples across all done briefs), then this source contributes nothing and the run does not fail or warn.
- [ ] Given prior verify runs under `.supervisor/verify/*/evidence.jsonl` with PASS `ac` lines whose (new, optional) `surfaces` field intersects `impact_surfaces`, when the impact pass runs, then up to `--impact-limit N` (default 10) of them are re-run, most-recent-first, recorded `scope: "impact", source: "prior_ac:<run_id>/<ac_id>"`; given no prior runs exist (fresh clone, worktree, or CI — `.supervisor/verify/` is gitignored), then this source silently contributes zero and the run does not fail.
- [ ] Given a surface in `impact_surfaces` with zero matched prior ACs, when the impact pass runs, then exactly one shallow smoke check executes for it (navigate, assert 2xx + no console/network 5xx, one primary form submission with seed values if the surface is a form) and records a `scope: "impact", source: "smoke"` verdict using the same classification taxonomy as ticket ACs (item 03).
- [ ] Given `summary.md` is rendered, then it states the bound in the form "impact pass: N surfaces from diff, M from brief, K prior ACs (limit L)".
- [ ] Given `--no-impact` is passed to the verify run, then the impact pass is skipped entirely and the ticket's PASS/FAIL/BLOCKED/NOT_VERIFIABLE counts in `summary.md` are byte-identical to an otherwise-identical run with the impact pass enabled.
- [ ] Given the test fixture (two routes sharing one component), when the diff touches the shared component, then `impact_surfaces` names both routes; a seeded prior PASS `ac` line for route B (carrying `surfaces`) is re-run and recorded `source: "prior_ac"`; an unmappable file (`README.md`) lands in `unmapped`; `--impact-limit 1` re-runs exactly one prior AC.
- [ ] Given the mutation-control fixture where route B is broken, then the impact-scope verdict for route B flips to FAIL while the ticket's own score is unchanged.
- [ ] `docs/RESULT_SCHEMAS.md` documents the new `impact_surfaces` event and the new optional `surfaces: string[]` field on `ac` lines; `validate-verify-evidence.py`'s `EVENTS` enum includes `impact_surfaces` with a dedicated `check_impact_surfaces` validator function; `test-verify-evidence.sh` has new arms covering both the new event and the new `ac` field.
- [ ] `skills/verify-walkthrough/SKILL.md` has a new `## 9. Impact pass` section (inserted between the current `## 8. Auth pause and resume` and the closing "Checklist before `finish`") and one new checklist bullet asserting the ticket-score-isolation invariant.

## Outcomes Rubric
- Diff mapped to surfaces; unmapped named, never guessed
- Brief impact map consumed advisorily
- Prior PASS ACs on touched routes re-run, bounded
- Impact never inflates or deflates the ticket score
- Bound stated in the summary

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Impact pass: diff→surfaces, scope split, prior-AC regression, smoke checks, schema + docs + tests | all | 9 modify, 0 create | `skills/verify-walkthrough/SKILL.md`, `skills/qa-test-patterns/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — Impact pass (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "impact_cmd"}
  - {kind: "symbol", path: "loomwright/scripts/verify-helpers.sh", name: "impact_summary_render"}
  - {kind: "symbol", path: "loomwright/scripts/validate-verify-evidence.py", name: "check_impact_surfaces"}
  - {kind: "symbol", path: "loomwright/agents/qa-executor.md", name: "Impact Pass"}
  - {kind: "symbol", path: "loomwright/skills/verify-walkthrough/SKILL.md", name: "9. Impact pass"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "impact_surfaces"}
  - {kind: "file", path: "loomwright/scripts/test-verify-walkthrough.sh"}
  - {kind: "file", path: "loomwright/scripts/test-verify-evidence.sh"}
  - {kind: "file", path: "loomwright/commands/verify.md"}
requires: []
lanes:
  - "loomwright/scripts/verify-run.sh"
  - "loomwright/scripts/verify-helpers.sh"
  - "loomwright/scripts/validate-verify-evidence.py"
  - "loomwright/scripts/test-verify-walkthrough.sh"
  - "loomwright/scripts/test-verify-evidence.sh"
  - "loomwright/agents/qa-executor.md"
  - "loomwright/skills/verify-walkthrough/SKILL.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/commands/verify.md"
external_requires: []
```

**Authoring rules applied:** single subtask (Decomposition Threshold default — the feature is cohesive and sequential end-to-end: schema → mechanical diff listing → scope split → agent-side classification/regression/smoke → docs/tests; no file-conflict, context-bound, or genuine-parallelism reason found for a split). `requires: []` and empty lanes-collision surface since there is only one subtask.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single-agent, no fan-out)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| — | — | n/a (single subtask) | n/a |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/verify-walkthrough/SKILL.md`, `skills/qa-test-patterns/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Route/surface classification has no shared script — it is agent-prose in qa-executor Phase 4 "APP TOPOLOGY DETECTION", not a mechanized helper as the requirement doc's "Phase 9" citation implied (Feasibility check 4, CAUTION) | MEDIUM | Scope the classification as a new qa-executor VERIFY MODE step (between the existing `walk` step and `reset`/`stop`) that reuses Phase 4's detection prose verbatim as instructed guidance; keep only the raw `git diff --name-only` file listing as mechanical script work; unmapped files are explicit, never guessed. |
| `.supervisor/verify/` is fully gitignored — prior-AC regression (source 3) is local-machine-only scratch, absent on a fresh clone, in any git worktree, or in CI | LOW | Degrade silently to 0 prior ACs found — same fail-safe-skip pattern as `brain-context`; never block or warn. Disclosed as an accepted limitation, not fixed by this brief. |
| Real `.supervisor/jobs/done/` briefs almost never populate the Blast-Radius subsection (repo-wide check: zero populated examples found; the one brief that has the heading says "Omitted") | LOW | Source 2 (brief impact map) will rarely contribute in practice today. State the bound honestly in `summary.md` rather than implying meaningful brief-derived coverage. |
| `propose-from-verify.sh`, `commands/verify.md`'s auto-dispatch FAIL/issue trigger, and the notify `ac`-FAIL dispatch are all scope-blind (`select(.event=="ac")` with no `scope` filter) and will now also fire on impact-scope FAIL/REAL_BUG lines | LOW (intentional — named decision) | Leave these three consumers unchanged. An impact-scope regression (something else the change broke) is exactly as actionable as a ticket-scope one for both auto-proposal and immediate notification. The acceptance criteria require scope-filtering ONLY `summary_build`'s ticket counts — that is the sole ticket-score-isolation invariant being protected. |
| The new optional `surfaces` field on `ac` lines only exists going forward — prior-AC regression cannot match any run recorded before this ships | LOW | Cold-start/bootstrap gap, disclosed here rather than silently assumed away; item 06's own fixture tests seed a prior run with the field already present to prove the matching logic itself works. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-16-verify-impact-pass.md
```

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/228
- **Branch:** feature/verify-impact-pass
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 1 (review 1: PASS with 5 non-blocking findings — 2 MEDIUM behavioral/completeness, 1 MEDIUM workflow-doc drift, 2 LOW nits — fixed directly, not via a fix-worker cycle, since decision was already PASS)
- **heal_remaining_issues:** 0
- **rubric_score:** 5/5
- **risk_classification:** {"high_risk": true, "reasons": ["content: 16 changed line(s) matched *auth*", "content: 1 changed line(s) matched *payment*", "path: loomwright/agents/qa-executor.md matched agents/", "path: loomwright/commands/qa-executor.md matched commands/", "path: loomwright/commands/verify.md matched commands/", "path: loomwright/skills/skills_index.md matched skills/", "path: loomwright/skills/verify-walkthrough/skill.md matched skills/", "size: changed_lines 962 > 400"], "changed_files": 11, "changed_lines": 962}
- **until_mergeable_dispatched:** false (auto_review suppressed by the owning /automate engine — this PR's drain is owned inline by that engine, not Supervisor's default detached dispatch)
- **Completed at:** 2026-09-16T04:05:07Z
