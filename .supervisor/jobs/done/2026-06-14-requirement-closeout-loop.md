# Supervisor Job: Close the requirement → brief → done loop (Beads-optional)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (only untracked `.claude/`), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Prompt/`.md`-only change to agent + skill + docs surfaces; no code |
| 2 | Dependency Availability | GO | No new deps; pure prompt logic |
| 3 | Architecture Fit | GO | Extends two established patterns: Beads-optional file-fallback (PO/Orchestrator/Launch Pad) + completion-tail ownership of job-lifecycle side-effects (Supervisor Phase 4.5) |
| 4 | Scope vs Supervisor Capability | GO | 3 subtasks, each a bounded edit to 1–2 prompt files |
| 5 | Hard Blockers | GO | None. No new agent/command/skill/hook → doc-currency counts unchanged (14/18/54/19) |

**Overall Verdict:** GO

## Task
**Goal:** In Beads-optional mode, close the requirement→brief→done loop so a Product Owner requirement file is marked done when the brief it spawned completes successfully — by (a) Launch Pad stamping a `source_requirement` provenance pointer into the brief, and (b) the Supervisor completion tail using that pointer to append a `## Status` block to the originating requirement file.

**Problem Statement:**
Operators running the Beads-absent flow (Product Owner → `.supervisor/requirements/*.md` → Launch Pad → Supervisor) needs a way to tell which requirements are done, because today the requirement `.md` is write-once with no close-out marker. Currently, done and not-done requirements look identical on disk; the only lifecycle lives one layer down on the brief (`.supervisor/jobs/{pending,in-progress,done}/`) and is never joined back to the requirement. This causes operators to hand-correlate slugs between `requirements/` and `jobs/done/`. Success looks like: a requirement that produced a successfully-completed brief carries a machine-readable `## Status: done` block written automatically by the completion tail, with Beads remaining the sole source of truth when it is active.

**Design decisions (settled with user in the originating session):**
- **Ownership split:** Launch Pad cannot do the close-out itself — it is a one-shot planning agent that has exited before the job runs. Launch Pad owns only the *provenance link* (it is the only agent that knows requirement→brief); the Supervisor completion tail (the only thing alive at done-time, already the sole writer of job lifecycle) owns the close-out.
- **Stamp, not move:** mark `## Status: done` in place rather than moving the file to `requirements/done/` — handles the multi-brief case (one requirement spawning several briefs) without prematurely retiring the requirement, and preserves history in place.
- **Beads-gated:** close-out runs only when Beads is inactive; `bd close BD-XX` already owns this when Beads is active (avoid two competing sources of truth).
- **done-not-failed:** close-out fires only on a successful outcome (PASS / loop-skipped / ESCALATED); failed runs must never mark a requirement done.

## Acceptance Criteria
- [ ] Given a brief Launch Pad created from a `.supervisor/requirements/*.md` file (resolved at Phase 2 step 0), when the brief is saved, then its `## Environment` section carries a `- **Source requirement:** {repo-root-relative path}` line.
- [ ] Given a `goal:` that is a literal string (or a repo file outside `.supervisor/requirements/`), when the brief is saved, then no `Source requirement` line is added.
- [ ] Given a brief with a `Source requirement` line AND Beads inactive, when the Supervisor completion tail runs on a PASS / loop-skipped / ESCALATED outcome, then the referenced requirement file gains (or has updated, idempotently) a `## Status` block recording `**Status:** done`, completion timestamp, brief path, and PR URL.
- [ ] Given a failed Supervisor run, when the failure/abort path runs, then the requirement file is NOT marked done.
- [ ] Given Beads is active, when the completion tail runs, then the requirement close-out is skipped (no file write).
- [ ] Given the `Source requirement` path no longer resolves (`test -f` fails), when close-out runs, then it is a logged no-op, never an error that fails the run (fail-safe).

## Outcomes Rubric
- `agents/launch-pad.md` Phase 2 step 0 and Phase 5 PACKAGE reference recording the resolved requirement path and writing a `Source requirement` line into the brief's `## Environment` section.
- `skills/supervisor-readiness/SKILL.md` Supervisor-Ready Brief Template `## Environment` block documents the optional `Source requirement` field.
- `agents/supervisor.md` completion tail (near the existing `in-progress/ → done/` job move, ~line 861) gains a requirement close-out step gated on Beads-absent and a successful outcome.
- The close-out step text explicitly states it SKIPS on a `failed` outcome and when Beads is active, and is a no-op when the requirement path does not resolve.
- No new agent/command/skill/hook is added; counts remain 14 agents / 18 commands / 54 skills / 19 hooks.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Launch Pad provenance stamp (producer) | `agents/launch-pad.md` (modify), `skills/supervisor-readiness/SKILL.md` (modify) | LAUNCHABLE |
| 2 | Supervisor completion-tail close-out (consumer) | `agents/supervisor.md` (modify) | LAUNCHABLE |
| 3 | Schema + docs + CLAUDE.md banner | `docs/RESULT_SCHEMAS.md` (modify), `CLAUDE.md` (modify) | BLOCKED (by #1, #2) |

**Subtask 1 — Launch Pad provenance stamp:**
- Phase 2 step 0: when the input resolves to a `.supervisor/requirements/*.md` file, record the repo-root-relative path as the brief's `source_requirement`.
- Phase 5 PACKAGE / brief assembly: emit `- **Source requirement:** {path}` under `## Environment` when (and only when) such a path was resolved.
- `supervisor-readiness/SKILL.md` brief template `## Environment`: document the optional `Source requirement` line.

```yaml
provides:
  - {kind: symbol, path: agents/launch-pad.md, name: 'source_requirement brief stamp'}
  - {kind: symbol, path: skills/supervisor-readiness/SKILL.md, name: 'Source requirement field'}
requires: []
```

**Subtask 2 — Supervisor completion-tail close-out:**
- Add a step in the completion tail (supervisor.md §"Job lifecycle completion", adjacent to the `in-progress/ → done/` move at ~line 861), AND on the ESCALATED branch.
- Logic: if Beads inactive (probe per existing `context-setup`/Persistence-Mode convention) AND the brief carries a `Source requirement` line that resolves via `test -f`, append/update a `## Status` block on the requirement file (`**Status:** done`, `**Completed:** {ISO 8601}`, `**Brief:** {brief path}`, `**PR:** {PR URL}`). Idempotent: replace an existing `## Status` block rather than duplicating.
- Explicitly no-op on: Beads active, failed/abort outcomes, unresolved path. Fail-safe — never fail the run on a close-out error.

```yaml
provides:
  - {kind: symbol, path: agents/supervisor.md, name: 'requirement close-out step'}
  - {kind: symbol, path: agents/supervisor.md, name: '## Status close-out block'}
requires: []
```

**Subtask 3 — Schema + docs:**
- `docs/RESULT_SCHEMAS.md`: document the brief `Source requirement` field and the requirement-file `## Status` close-out convention (note it is advisory/Beads-absent-only, mirrors the brief `## Outcome` pattern).
- `CLAUDE.md`: add a one-line banner for the feature; update the Launch Pad / Supervisor table rows if the invariant warrants. Confirm counts unchanged (no doc-currency drift).

```yaml
provides: []
requires:
  - {kind: symbol, path: skills/supervisor-readiness/SKILL.md, name: 'Source requirement field', from: 1}
  - {kind: symbol, path: agents/supervisor.md, name: '## Status close-out block', from: 2}
```

## Parallelism Analysis
- Batch 1: Subtask 1, Subtask 2 (parallel — disjoint file sets: launch-pad.md + supervisor-readiness/SKILL.md vs supervisor.md)
- Batch 2: Subtask 3 (after 1 & 2, so it documents the final field/block names without drift)
- Recommended workers: 2

## Skill References
- `skills/supervisor-readiness/SKILL.md` — brief template (where the `Source requirement` field is documented) + jobs convention
- `skills/context-setup/SKILL.md` — Beads-active probe (`test -d .beads && bd --version`) reused for the close-out gate
- `skills/state-management/SKILL.md` — completion-tail / job-lifecycle context
- `skills/claude-md-validation/SKILL.md` — keep CLAUDE.md claims current

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Multi-brief requirement (one requirement → several briefs, e.g. autonomous re-iteration off `auto-*.md`) marked done prematurely | MEDIUM | Stamp (not move) is idempotent and re-applied per completion; the autonomous loop remains authoritative for its own `auto-*.md` files. Document that close-out targets PO `.supervisor/requirements/` stories; consider treating `auto-*.md` as out of scope or advisory-only |
| Double bookkeeping if close-out runs while Beads active | HIGH | Hard Beads-absent gate; `bd close` is the sole truth when Beads active |
| Close-out write error fails an otherwise-successful run | HIGH | Fail-safe: wrap in no-op-on-error; never propagate to `SUPERVISOR_RESULT.status`. Mirrors the bimodal "side-effect emitters fail SAFE" invariant in CLAUDE.md |
| Requirement path injection / traversal via brief field | MEDIUM | Resolve relative to project root, require the path to be under `.supervisor/requirements/` and pass `test -f`; otherwise no-op |
| Backward-compat: briefs without `Source requirement` (direct `/supervisor task:`, pre-feature briefs) | LOW | Field is optional; absence → close-out step skipped silently (same as existing job-move backward-compat) |
| Doc-currency drift | LOW | No count changes; run `scripts/check-doc-currency.sh` mentally — only version banner + table rows change |

## Configuration
- **Heal iterations:** default (3)
- **Parallelism:** 2 workers
- **Cost profile:** inherit (default)
- **Beads:** assume inactive for the feature's primary path (the gate handles both)
- **Version bump:** minor (additive feature) — coordinate `plugin.json` + marketplace `description` count/version in Subtask 3 per the anti-rebloat rule

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-06-14-requirement-closeout-loop.md

## Outcome
- **Status:** completed
- **Completed:** 2026-06-14T18:02:54Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/59
- **Branch:** feature/requirement-closeout-loop
- **Files changed:** 9
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Requirement close-out:** noop_no_pointer (this brief predates the feature; backward-compat path — no requirement file stamped)
- **Summary:** Closed the requirement→brief→done loop in Beads-optional mode — Launch Pad source_requirement provenance stamp (ST1), Supervisor Phase 4.5 step 2.5 close-out (ST2), schema docs + v14.26.0 bump (ST3). All 3 subtasks PASS; doc-currency green.
