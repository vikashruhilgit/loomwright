# Supervisor Job: /automate parks on rate-limit, not on a dead worker

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (v15.81.0)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (non-main worktrees from other concurrent plugin activity — acknowledged, non-blocking)
- **Source requirement:** .supervisor/requirements/orca-derived/04-rate-limit-park.md

## Task
**Goal:** When `/automate`'s own RUN step hits a rate-limit turn failure, the engine PARKS the queue with a named, machine-readable reason and a fail-closed stop — it never retries into the same rate-limit wall, and it never misreports the failure as a dead worker.

**Problem Statement:**
`/automate` runs unattended for hours via `/loop`. When the account hits a rate-limit window mid-run, today's behavior is indistinguishable from a genuinely dead/crashed subtask: the run file records a generic failure and, on resume, the loop may simply retry the same RUN step — hitting the same wall again. The plugin ALREADY records the fact: `StopFailure`'s payload carries a classified top-level `error` field (`rate_limit | server_error | authentication_failed | model_not_found | unknown` — no message-text parsing needed for the known classes), and since v15.79.0 (PR #231) this is additionally recorded as an `agent_lifecycle: failed` JSONL row with `reason` copied verbatim. **Nothing currently consumes it** — `automate-helpers.sh` and `skills/automate-loop/SKILL.md` have zero mentions of `rate_limit` or `StopFailure`. This item wires the ALREADY-RECORDED signal into `/automate`'s per-item loop so it parks correctly instead of retrying or misreporting.

**Honest limit (inherited from the source requirement, verified 2026-09-11):** there is no local rate-limit-*proximity* signal available (no usage-window file under `~/.claude`) — this item builds on the signal we HAVE (the classified `StopFailure`/`agent_lifecycle:failed` reason), not a predictive one. A second honest limit: every empirically-observed `StopFailure` capture in this repo's own `.supervisor/logs/failures.log` for a RATE-LIMIT class specifically has been a MAIN-session turn (no `agent_id`) — for `/automate`, the main thread IS the loop that drives `§6 RUN`, so the main-thread signal is exactly the one this item needs; a worker-subagent's own rate-limited turn firing this same hook is a named gap (item 01 already noted subagent `StopFailure`s DO happen for OTHER error classes — `server_error`/`unknown` — with `agent_id` present; whether `rate_limit` specifically follows that same pattern is unverified and out of scope here).

## Acceptance Criteria
- [ ] Given a fixture `agent_lifecycle: failed` line with `reason: rate_limit` (main-thread scope, post-dating the current item's "picked" timestamp), when `/automate`'s §6 RUN step evaluates its own `/autonomous --single-iteration` outcome, then the current Queue item is parked FOLLOWING THE EXISTING CONVENTION EXACTLY (item-level `status` mirrors `pause_reason`, the same way `awaiting_merge`/`escalated` already do — never a new, unprecedented `status: parked` placeholder): `## Current` records `status: rate_limit` AND `pause_reason: rate_limit` (joining the EXISTING `pause_reason` enum — `awaiting_merge|escalated|limit_reached|resume_ambiguous` — as a fifth value, not a second park mechanism), `## Status: paused`, a `## Progress` line is appended, and the run stops (exit 0) — the headline names the rate-limit fact, not a generic failure.
- [ ] Given the same scenario with `reason: server_error` (or any OTHER known classified reason) instead of `rate_limit`, when the same evaluation runs, then today's existing failure/error path is UNCHANGED — this item adds exactly one new branch, it does not alter handling for any other classified reason.
- [ ] Given a fixture `agent_lifecycle: failed` line with `reason: unknown` whose `last_assistant_message` (or the raw `failures.log` line) contains a `429` substring, when the RUN step evaluates it, then a STRING-TABLE FALLBACK records `reason_hint: rate_limit` (a new, separate field — never written into `reason` itself, never promoted to the classified value) AND the item still parks the same way a classified `rate_limit` would (a hint is enough to stop retrying into a wall, not enough to relabel the underlying fact as certain).
- [ ] Given a run parked with `pause_reason: rate_limit`, when `/automate --resume` (or the next `/loop` tick) runs, then it round-trips through the EXISTING smart-resume RESUME reconcile (§4) exactly as `awaiting_merge` does today — no second reconcile code path, no second park vocabulary (test both: resuming a `rate_limit` park and resuming an `awaiting_merge` park exercise the same reconcile logic, differing only in the stored `pause_reason` value).
- [ ] Given `docs/RESULT_SCHEMAS.md`'s `AUTOMATE_RUN` §"`## Current` fields" table and its two `pause_reason` enum listings (the template comment block AND the fields table), when this PR lands, then BOTH are updated to include `rate_limit` — this repo has a documented history of exactly this kind of two-listing drift within a single doc section; verify both, not just one. The item-level `status` enum (currently `running|awaiting_merge|escalated|failed|done`, in the SAME fields table) ALSO gains `rate_limit` in the SAME edit, matching AC1's status-mirrors-pause_reason convention — this is explicitly IN scope for this criterion, not a separate follow-up.
- [ ] Given `skills/automate-loop/SKILL.md`'s own §6 RUN step prose and its §9/§11 pause_reason references, when this PR lands, then the new rate_limit branch is documented at the SAME §6 RUN insertion point the loop already uses to capture `SUPERVISOR_RESULT` (the natural existing call site for evaluating the RUN step's outcome) — not a new, separate phase.

## Outcomes Rubric
- Park keyed on the payload's own classified `error`/`reason` field; text/`429` parsing only ever yields `reason_hint`, never promotes into `reason`
- Queue parks fail-closed with a named `rate_limit` reason, never retries into the wall
- One park vocabulary (`pause_reason` enum gains exactly one value), one RESUME reconcile — verified via the SAME code path as `awaiting_merge`, not a parallel one
- Both `RESULT_SCHEMAS.md` pause_reason listings updated in the same PR (no doc drift)
- Handling for every OTHER classified `StopFailure` reason (`server_error`/`authentication_failed`/`model_not_found`/`unknown`-without-a-429-hint) is provably unchanged

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Rate-limit park (pause_reason enum extension, §6 RUN-step check, resume reconcile reuse, docs) | all | 4 modify, 0 create | `skills/automate-loop/SKILL.md`, `skills/state-management/SKILL.md` | LAUNCHABLE |

**Split reason:** none — single subtask. One new pause_reason value flowing through one existing check-point (§6 RUN) and one existing reconcile path (§4) is a small, cohesive addition; below both the file-conflict and context-bound thresholds.

### Provides / Requires Schema

```yaml
# Subtask 1 — Rate-limit park (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/skills/automate-loop/SKILL.md"}
  - {kind: "file", path: "loomwright/docs/RESULT_SCHEMAS.md"}
requires: []
lanes:
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
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
| 1 | `skills/automate-loop/SKILL.md` (§4 RESUME reconcile, §6 the per-item loop RUN step — the two insertion points), `skills/state-management/SKILL.md` (session JSONL conventions this reads) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Whether the actual per-item loop mechanics (§6 RUN, §4 RESUME) live as PROSE in `automate-loop/SKILL.md` (executed by the orchestrating agent directly) or as BASH in `automate-helpers.sh` is not fully settled by this brief — confirm the exact split before writing new bash that duplicates existing prose-driven logic, or new prose that should have been a bash function | MEDIUM | Read `automate-helpers.sh`'s existing `reconcile-item`/`gate-eval` functions (bash, pure-logic, PR-URL-keyed) and the `automate-loop/SKILL.md` §6 RUN prose (agent-executed) before deciding where the rate_limit CHECK itself belongs — it may be pure prose (the orchestrating agent reads its own session log directly) rather than a new bash function, since there is no PR URL to key a bash helper on at this point in the loop |
| A worker-subagent's own `StopFailure`/`rate_limit` (as opposed to the main-thread's) is an explicitly named, unverified gap in the source requirement — do not silently claim broader coverage than the main-thread-only signal this item actually builds on | LOW | Acceptance criteria and docs scope this to the main-thread signal only, matching the source requirement's own stated honest limit |
| Feasibility (Phase 2.5) — Scope vs Supervisor Capability | LOW | Single-subtask, edits to 1 skill doc + 1 script (+ its test file) + 1 doc file; well within Single-Agent Path capacity |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-17-rate-limit-park.md
```

## Outcome
- **Heal loop ran:** true
- **Heal iterations:** 1 fix cycle (FAIL on first holistic review — a real HIGH finding: a mirrored park-cause enumeration in commands/automate.md wasn't synced — plus an advisory skill-version bump; both fixed in one round, PASS on second review). Brief-authoring took 2 Plan Review cycles (round 1 PASS w/ MEDIUM on status-field naming, corrected; round 2 clean PASS).
- **Heal decision:** PASS (external claude-review clean on final commit)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/235
- **Merge commit:** 2ce5f5c67073a6081dcff9cb383b3ba2b655102a (merge commit, --admin — required 1 approving review, no human reviewer available; standing order)
- **Version:** no bump (prose/skill-doc PR; automate-loop SKILL.md bumped 1.3.0->1.4.0 as its own artifact version, not the plugin version)
