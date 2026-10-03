# Supervisor Job: Worker checkpoints — one event type, one fail-safe helper, advisory-only

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (post-merge of PR #232, v15.80.0)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (non-main worktrees from other concurrent plugin activity — acknowledged, non-blocking)
- **Source requirement:** .supervisor/requirements/orca-derived/03-worker-checkpoints.md

## Task
**Goal:** A worker leaves a short, structured trail of what it concluded and why at the moments that matter (hypothesis confirmed/refuted, a blocker hit, an investigate→fix transition, a slice done) — one new event type, one tiny fail-safe helper, advisory-only, readable by `/handoff` and (later) the Floor lane.

**Problem Statement:**
`/handoff` and `/dreaming` mine end-of-run artefacts (worker summaries, `session_end`, postmortem) but nothing records a hypothesis a worker confirmed or refuted MID-run, a blocker it worked around, or an investigate→fix transition — that context is reconstructed from the final diff or lost entirely. This item gives a worker one advisory event type and a tiny, fail-safe emitter to record exactly those moments, without ever forcing chat or gating anything.

## Acceptance Criteria
- [ ] Given `checkpoint.sh` invoked with a missing or invalid ledger-path argument, when it runs, then it writes NOTHING and exits 0 (test both the missing-arg and the invalid/unwritable-path cases) — the ledger path is the FIRST POSITIONAL ARGUMENT (`checkpoint.sh <ledger_path> <kind> <text> [paths...]`), matching `automate-helpers.sh`'s `learning-emit <ledger_path> <flags...>` subcommand — the real in-repo precedent for an explicitly-passed, validated ledger path (memory `learning-emit-ledger-path-positional`: that exact positional argument was silently omitted twice, writing to a junk file both times — this script's own test suite must include a case that would have caught that exact mistake). Unlike the hook-triggered `emit-lifecycle.sh`/`emit-progress-event.sh` (stdin payload, self-resolving), `checkpoint.sh` is invoked DIRECTLY by the worker mid-task via Bash, so it needs an explicit caller-supplied path.
- [ ] Given a worker spawned on the PARALLEL path (`agents/execute-manager.md` Step 3's `Task()` template) into its own linked worktree, when it needs the session log path to call `checkpoint.sh`, then it has one: the spawn prompt now carries a SESSION-LOG POINTER — the MAIN-CHECKOUT ABSOLUTE path of `.supervisor/logs/{session_id}.jsonl` — added to that Task() template alongside the EXISTING brief-pointer and Context-digest-pointer (same established convention: `docs/POINTER_AUDIT.md`, "gitignored file absent inside worker worktrees, pin the main-checkout absolute path and say so"). This repo has exactly TWO physical worker spawn `Task()` templates, not three: `agents/execute-manager.md`'s (parallel path, each worker in its own worktree) and `loomwright/skills/async-orchestration/SKILL.md`'s "Sequential-path Worker" template (used for BOTH the Sequential path AND the Single-Agent path, which explicitly INHERITS it verbatim — `agents/supervisor.md` has no separate spawn template of its own, only a reference to this shared one, confirmed by its own text: "same shape as the Sequential-path Worker contract" / "inherits the Sequential-path spawn template"). The SAME session-log pointer is therefore added ONCE to `async-orchestration/SKILL.md`'s Sequential-path Worker template — this single edit covers both the Sequential and Single-Agent paths, exactly the way that template's existing `Brief:`/Context-digest lines already do for both paths (note: on this path the pointer is a repo-relative path since the worker's worktree path IS the project root, matching that template's existing `Brief:` line's own phrasing — "resolves on the sequential path because your worktree path IS the project root" — not the main-checkout-absolute form needed on the genuinely worktree-isolated parallel path). This is the SAME session_id `agent_identity`/terminal-event rows already use (v15.79.0/v15.80.0), so the path is fully derivable at spawn time — never guessed, never invented by the worker.
- [ ] Given a fixture worker run emitting three checkpoints (`hypothesis_confirmed`, `blocker`, `slice_done`) via `checkpoint.sh`, when `build-handoff.sh` renders that job's digest item, then the checkpoints appear under the "Tried / rejected" facet with the session id as provenance, in the SAME session JSONL `emit-progress-event.sh`/`emit-lifecycle.sh` already write to.
- [ ] Given the new `worker_checkpoint` event lines interleaved with existing event types in the SAME session `.supervisor/logs/{session_id}.jsonl` log, when the existing session-log consumers `build-state.sh` (filters `select(.event? == "session_end" or .event? == "subtask_complete")`) and `build-floor.sh` (its lane-event counting, which already excludes `agent_identity` lines by the same pattern) read that log, then both are UNAFFECTED by the new event type — verify their actual match/filter logic explicitly (memory `verify-consumer-contract-before-for-free`), not just "probably fine." (`read-postmortem.sh` reads a DIFFERENT file — `.supervisor/postmortem/results.jsonl`, keyed on `changed_paths` — and is not a session-log consumer; it is out of scope for this criterion.)
- [ ] Given `agents/worker.md`'s prompt after this change, when its token count is measured, then it stays within `loomwright/docs/prompt-token-budgets.json`'s declared budget for `worker`, OR the budget is bumped in the same PR (mirrors item 02's own proactive budget-bump precedent from the immediately-preceding merged PR).
- [ ] Given the worker prompt's new checkpoint guidance, when read, then it is explicitly advisory ("emit a checkpoint when...", never "must emit") — a worker that emits zero checkpoints is not penalized by any gate, and no existing gate (`outputs_verified`, `heal_decision`, the new v15.80.0 children-settled check) reads or is affected by checkpoint presence/absence.
- [ ] Given `build-floor.sh`'s existing JSON projection, when this PR lands, then it additively carries the LAST `worker_checkpoint` text per lane (a new field on the per-agent projection object) WITHOUT changing any existing field or rendering — item 05 (a separate, later work item) is the one that renders it in the UI; this item only needs the projector to carry the data through.

## Outcomes Rubric
- One event type (`worker_checkpoint`), one fail-safe helper (`checkpoint.sh`), ledger path positional and validated
- Worker prompt names the five moments advisorily — no gate reads checkpoint presence/absence
- `/handoff`'s `build-handoff.sh` renders checkpoints under "Tried / rejected" with session-id provenance
- Existing consumers keying on other event types/fields are verified unaffected, not merely assumed
- `build-floor.sh`'s projection additively carries the last checkpoint per lane (rendering is item 05's job)
- Worker prompt token budget stays within its declared budget (bumped in this PR if needed)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Worker checkpoints (helper, worker-prompt wiring, spawn-template session-log pointer, `/handoff` + Floor-projection consumers) | all | 8 modify, 2 create | `skills/state-management/SKILL.md`, `skills/agent-output/SKILL.md`, `skills/async-orchestration/SKILL.md` | LAUNCHABLE |

**Split reason:** none — single subtask. One new event type flowing through one new emitter into two existing readers is one cohesive, small change; below both the file-conflict and context-bound thresholds.

### Provides / Requires Schema

```yaml
# Subtask 1 — Worker checkpoints (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/checkpoint.sh"}
  - {kind: "file", path: "loomwright/scripts/test-checkpoint.sh"}
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "worker_checkpoint"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "session-log pointer"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "session-log pointer"}
  - {kind: "symbol", path: "loomwright/scripts/build-handoff.sh", name: "worker_checkpoint"}
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "last_checkpoint"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "worker_checkpoint"}
requires: []
lanes:
  - "loomwright/scripts/checkpoint.sh"
  - "loomwright/scripts/test-checkpoint.sh"
  - "loomwright/agents/worker.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/agents/supervisor.md"  # documentary note only (see AC2) — no functional spawn-template edit here
  - "loomwright/skills/async-orchestration/SKILL.md"  # the actual Sequential/Single-Agent spawn-template edit site
  - "loomwright/scripts/build-handoff.sh"
  - "loomwright/scripts/test-build-handoff.sh"
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"  # only touched if the worker prompt-token-budget bump fires (AC5)
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/state-management/SKILL.md` (session JSONL conventions), `skills/agent-output/SKILL.md` (worker output format the new advisory guidance sits alongside), `skills/async-orchestration/SKILL.md` (the Sequential-path Worker spawn template AC2 edits) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ledger-path-as-positional-arg has already bitten this codebase twice (memory `learning-emit-ledger-path-positional`) | HIGH if repeated a third time | Explicit acceptance criterion + test case requiring the positional arg and validating it; grep the signature line before emitting, per the memory's own stated mitigation |
| A worker prompt change that's read on EVERY worker spawn is a high-leverage file — a token-budget regression or a wording change that reads as mandatory rather than advisory affects every future Supervisor run | HIGH if regressed | Explicit acceptance criteria for both: advisory-only wording, and token budget within declared limits (bump if needed, in this same PR) |
| **Honest limit, cannot be closed by this PR alone:** the source requirement's own D11 pre-registration asks to "record, in this file, the rate over the first five real runs" — that data does not exist until five real runs happen AFTER this ships | MEDIUM (scope boundary, not a defect) | This PR implements the measurement capability (the event type + emitter) but the actual 5-run rate measurement is a necessarily-later observation, not part of this PR's Acceptance Criteria. Worker should note this honestly rather than fabricate a rate. |
| `build-floor.sh`'s existing lane/event-count logic already excludes certain event types from a lane's event count (e.g. `agent_identity`, per its own committed test cases) — a new event type must be classified correctly or it silently double-counts or gets miscounted | MEDIUM | Read `build-floor.sh`'s existing event-classification tests (search `test-build-floor.sh` for how `agent_identity` is excluded) before adding `worker_checkpoint` handling, and add an equivalent test |
| There are exactly TWO physical worker spawn `Task()` templates in this repo (`execute-manager.md` for the parallel path; `async-orchestration/SKILL.md`'s "Sequential-path Worker" template, inherited by BOTH Sequential and Single-Agent paths) — `agents/supervisor.md` has NO template of its own. Editing the wrong file (e.g. `agents/supervisor.md`) would be a silent no-op: the actual spawn still runs through the unedited shared template | HIGH if misattributed | Edit exactly these two physical template files; `agents/supervisor.md` gets, at most, a one-line documentary cross-reference, never a duplicate template |
| The session-log pointer added to both physical templates must reuse the EXISTING pointer-passing convention (main-checkout absolute path on the parallel path per `docs/POINTER_AUDIT.md`; repo-relative on the sequential/single-agent path, matching that template's own existing `Brief:`/Context-digest phrasing) — inventing a new convention would fragment a pattern this repo already applies uniformly | HIGH if inconsistent | Mirror the exact existing prose pattern for the brief pointer and Context-digest pointer verbatim in each template, changing only the artifact name/path |
| Feasibility (Phase 2.5) — Scope vs Supervisor Capability | LOW | Single-subtask, 1 new script + 1 new test + edits to worker.md/execute-manager.md/supervisor.md/async-orchestration SKILL.md/build-handoff.sh/build-floor.sh/RESULT_SCHEMAS.md/token-budgets.json; well within Single-Agent Path capacity |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-17-worker-checkpoints.md
```

## Outcome
- **Heal loop ran:** true
- **Heal iterations:** 0 code-review fix cycles for correctness (single PASS, zero findings on first holistic review); 2 review-comment follow-ups (token-budget headroom note, missing test case; then a version-bump omission) addressed via small follow-up commits/PR. Brief-authoring took 2 Plan Review cycles (cycle 1 FAILed 3x on a spawn-template misattribution; cycle 2 PASSed attempt 1).
- **Heal decision:** PASS (internal review PASS zero findings; external claude-review PASS across all 3 rounds, each with only minor/documentation findings, all addressed)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/233 (merged by the repo owner directly, mergedBy vikashruhilgit, merge commit 7732d89 — NOT by this automate run; reconciled from ground truth) + follow-up https://github.com/vikashruhilgit/loomwright/pull/234 (version-bump/doc-currency fix, merged 840cfc8 by repo owner)
- **Merge commit:** 7732d89ab8344c0db3332094bffeba22546e4d2a (+ follow-up 840cfc83)
- **Version:** 15.80.0 -> 15.81.0 (via PR #234)
