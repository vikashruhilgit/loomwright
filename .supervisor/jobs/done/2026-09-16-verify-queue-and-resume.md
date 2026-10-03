# Supervisor Job: Multi-ticket `/verify` queue with its own run file, resume by reconcile

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/verify-walkthrough/07-verify-queue-and-resume.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq, same toolchain as `automate-helpers.sh`/`verify-helpers.sh`, both already in-repo and tested |
| 2 | Dependency Availability | GO | reuses `automate-helpers.sh resolve-folder` verbatim (no new dependency); `verify-helpers.sh`'s atomic-write pattern and `verify-run.sh`'s per-ticket preflight/executor plumbing already exist |
| 3 | Architecture Fit | GO | mirrors `skills/automate-loop/SKILL.md` §3-4's single-run-file + reconcile discipline, explicitly required by the source requirement; `/verify`'s own evidence-store discipline (`verify-helpers.sh`, sole-writer + derived summary) is the pattern to extend, not replace |
| 4 | Scope vs Supervisor Capability | GO | one cohesive feature across two existing scripts + one command file + two doc surfaces + one new test file — fits the single-agent default (no file-conflict/context-bound/genuine-parallelism split reason) |
| 5 | Hard Blockers | GO | no migration framework, no new credentials, no missing modules — `jq`/`git`/`python3`/`node`/`npx` are already required by `/verify` |

**Overall Verdict:** GO

## Task
**Goal:** Give `/verify --folder <dir>` a queue engine — one markdown run file per queue, reconciled from evidence not `gh`, that walks every not-done ticket in a folder through a single-ticket verify run and resumes exactly where the evidence says it stopped.

**Scope note:** `--resume <run_id>` is overloaded across two shapes — a queue-mode resume is only valid when `<run_id>` resolves under `.supervisor/verify/queue-*.md`; the command probes for that queue file first and falls back to the existing single-ticket `.supervisor/verify/<run_id>/` resume when it does not match. This does not introduce a new flag, only a dispatch rule on the existing one.

**Problem Statement:**
The owner wants `/verify` to work on multiple tickets from requirement files, the same operational shape as `/automate`, but its own state must never mix with `/automate`'s or Supervisor's. `automate-loop` §3-4 already has the right discipline — single run file, `## Progress` append-only, atomic writes, resume = glob + reconcile belief vs truth — but its truth source (`gh pr view`) says nothing about whether the app still starts, the session is still valid, or the branch under test moved. A verify-specific reconcile must read `evidence.jsonl` and `git rev-parse` instead. Currently `/verify` only accepts one ticket path at a time and has no folder intake, no queue file, and no resume-by-reconcile for a multi-ticket run. This causes the owner to hand-drive `/verify` once per ticket with no crash recovery or stale-branch detection across a batch. Success looks like `/verify --folder <dir>` walking a folder's tickets to completion, pausing correctly on `needs_auth`, and resuming from a crash or pause without re-running any ticket that already has a verdict or re-using a run whose branch moved.

## Acceptance Criteria
- [ ] Given a folder with 3 ticket files where one is already `## Status: done`, when `/verify --folder <dir>` runs, then it creates exactly one queue file `.supervisor/verify/queue-<UTC ts>-<slug>.md` with 2 `- [ ]` items and processes them in `LC_ALL=C` sort order.
- [ ] Given a ticket whose verify run pauses `needs_auth`, when the queue reaches that item, then the queue file is written `## Status: paused` with `pause_reason: needs_auth`, later queue items are left untouched, and `--resume` after sign-in finishes both tickets without re-running any AC that already has a verdict.
- [ ] Given a queue mid-item crashes (process killed) after the first AC of an item has a verdict, when the queue is resumed, then it resumes at the first AC without a verdict and does not re-run the finished item.
- [ ] Given a ticket's branch head moves between queue runs, when the queue reconciles that item, then it is marked `- [x] … # stale: head moved <old>→<new>`, a fresh item is re-queued for it, and the stale run's own verdict counts never appear in the new item's summary.
- [ ] Given a full verify queue run completes, when `.supervisor/automate` and `.supervisor/state.md` are checked, then `find .supervisor/automate .supervisor/state.md -newer <marker>` (a marker file touched immediately before the run) is empty — no read or write of `/automate`'s or Supervisor's state.
- [ ] Given `.supervisor/verify/queue-*.md` is written or rewritten, when the write happens, then it goes ONLY through `verify-helpers.sh queue-write` (atomic temp+rename, with a line-count guard before every rewrite so an empty/short stdin never overwrites a longer file) and `verify-helpers.sh queue-progress-append` (append-only `## Progress`) — never a direct file write elsewhere.
- [ ] Given `--limit N` is passed to `/verify --folder <dir>`, when N items have been processed with items still unchecked, then the queue is `## Status: paused` with `pause_reason: limit_reached`, matching `automate-loop` §2's "caps PROCESSED items, not queue size" semantics.
- [ ] Given two incomplete queue files exist and no explicit `--resume <run_id>` was passed, when `/verify` starts, then it asks the user which to resume (or fails closed with `pause_reason: resume_ambiguous` under `--non-interactive-fallback`), matching `automate`'s exact convention.

## Outcomes Rubric
- `/verify --folder <dir>` intake resolves via `automate-helpers.sh resolve-folder` verbatim — no re-implementation of folder scanning or the `## Status: done` skip.
- The queue file (`.supervisor/verify/queue-*.md`) is written only via `verify-helpers.sh queue-write` (atomic temp+rename, line-count guarded) and `queue-progress-append` (append-only `## Progress`) — no other write site touches it.
- Resume position is derived from `evidence.jsonl` (run_end / pause / crash-mid-AC), and staleness is derived from a `git rev-parse <branch>` vs the recorded `run_start` head SHA comparison — never inferred from belief alone.
- `.supervisor/automate/` and `.supervisor/state.md` are untouched by a verify queue run, proven by an `-newer <marker>` mtime check in the test suite.
- The per-item loop is sequential (one ticket at a time), bounded by `--limit`, and re-passes non-persisted passthrough flags (`--notify`/`--cheap`) on every `--resume`, exactly as `/automate`'s equivalent flags behave.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `/verify --folder` queue engine: intake, atomic queue file, per-item loop, evidence-based reconcile, resume | all 8 | 8 modify, 1 create | `skills/verify-walkthrough/SKILL.md`, `skills/automate-loop/SKILL.md` (reference pattern, read-only) | LAUNCHABLE |

### Provides / Requires Schema (v12.0.0+)

```yaml
# Subtask 1 — queue engine (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/verify-helpers.sh", name: "queue_write"}
  - {kind: "symbol", path: "loomwright/scripts/verify-helpers.sh", name: "queue_progress_append"}
  - {kind: "symbol", path: "loomwright/scripts/verify-helpers.sh", name: "queue_checkoff"}
  - {kind: "symbol", path: "loomwright/scripts/verify-run.sh", name: "queue_reconcile_item"}
  - {kind: "file", path: "loomwright/scripts/test-verify-queue.sh"}
  - {kind: "symbol", path: "loomwright/skills/verify-walkthrough/SKILL.md", name: "Multi-ticket queue"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "VERIFY_QUEUE"}
requires: []
lanes:
  - "loomwright/scripts/verify-helpers.sh"
  - "loomwright/scripts/verify-run.sh"
  - "loomwright/commands/verify.md"
  - "loomwright/skills/verify-walkthrough/SKILL.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/test-verify-queue.sh"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single subtask — no fan-out)
```

### File Overlap Matrix
_n/a — single subtask, no sibling to overlap with._

### Batch Plan
- **Batch 1:** Subtask 1 (single-agent)
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/verify-walkthrough/SKILL.md`, `skills/automate-loop/SKILL.md` (read-only reference for the §3-4 pattern) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Reconcile logic could accidentally read/write `.supervisor/automate/` or `.supervisor/state.md`, violating the "never shares state" requirement | MEDIUM | AC5's `find … -newer <marker>` mtime test is a mechanical, mutation-testable proof; code review checks for any path literal under those two locations in the new/changed code |
| The `queue-write` empty-stdin footgun (memory: `runfile-write-accepts-empty-stdin` — a piped rewrite that errors can atomically empty a run file) | HIGH if unguarded | AC6 requires a line-count guard before every rewrite, mirrored from `automate-helpers.sh runfile-write`'s own fix for the same class of bug; test suite pipes an empty rewrite and asserts the file is byte-unchanged with a non-zero exit |
| Stale-branch detection (comparing `git rev-parse <branch>` to a recorded SHA) could false-positive on a branch that was rebased without content changes, discarding valid verdicts | LOW | scoped to this ticket's acceptance criteria (AC4) exactly as the source requirement specifies; documented as an accepted limitation if it surfaces, not silently worked around |
| `--resume <run_id>` is already used by single-ticket `/verify` to mean a ticket run dir; a queue run's id shares the same flag name | MEDIUM | resolved by the probe-then-fallback dispatch rule in the Scope note above (queue-file match first, ticket-dir fallback second) — no new flag, existing `--resume` semantics for a single ticket are unchanged |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-16-verify-queue-and-resume.md
```

## Outcome
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0 (PASS on first pass; 1 MEDIUM non-blocking doc-completeness finding fixed directly, commit 185e936)
- **heal_remaining_issues:** 0
- **rubric_score:** 5/5
- **risk_classification:** high_risk=true (auth/security/token keyword matches, commands/+skills/ paths, 974 changed lines/11 files)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/230
- **branch:** feature/verify-queue-and-resume
