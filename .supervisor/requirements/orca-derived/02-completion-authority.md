# 02 — Completion authority (Orca: "done alone is not enough while children are attached")

## Problem
A subtask is "complete" when the worker SAYS so (`WORKER_RESULT` + `outputs_verified`), and a run is
"done" when the lead reaches FINALIZE. Orca's two rules are stricter and mechanical: a completion must
name the task AND the dispatch it settles, and a parent is never done while any child dispatch is
unsettled. We have the raw material after item 01 (per-`agent_id` lifecycle rows) but no consumer.

## Goal
Completion is decided by two independent facts — a terminal lifecycle event AND the `provides` artefacts
on disk — never by the worker's own report; FINALIZE refuses (fails CLOSED, named reason) while any
spawned child has no terminal event.

## Scope
1. **Per-subtask:** the Execute Manager / inline Phase 3 poll loop marks a subtask complete only when
   (a) the log holds a terminal row for that `agent_id` — `subtask_complete` with `result_block_present: true`
   (item 01 §3b), or `agent_lifecycle: failed` (corrected 2026-09-12: there is no `agent_result` event) —
   AND (b) every `provides` path exists on disk in the worktree (the "re-verify on disk" lesson, mechanized).
   **What is new vs today:** `agents/execute-manager.md` already has a disk check — Step 2b verifies the
   subtask's `requires` were materialized, and the v12 poll-loop gate reads the worker's `outputs_verified`
   entries. Neither verifies `provides` ON DISK from the manager's side; both trust the worker's report for
   that. This item adds exactly that manager-side check and nothing else — do not re-implement Step 2b.
   A worker whose result block claims `outputs_verified: true` with a missing `provides` path is recorded
   as `outputs_verified_contradicted` — logged, subtask NOT complete.
2. **Per-run:** FINALIZE's pre-merge safety gate gains one check: no `agent_identity` in this session
   without a terminal event → `error: "children_unsettled"`, list the ids, stop (interactive: ask;
   `--non-interactive`: fail closed, same shape as `preflight_overlap_detected`). Per CLAUDE.md
   §"Failure-Mode Invariants" a fail-closed gate needs an EXPLICIT escape: add `--skip-children-check`
   (recorded in the run summary when used); silent proceed is the regression that section names.
   The join is `agent_identity` ↔ end rows by `agent_id`; identity lines exist only since 2026-09-07, so a
   session with zero `agent_identity` rows has nothing to check and the gate is a no-op there — say so in
   the gate's reason text rather than reporting "settled".
3. **Resume, don't respawn:** an `ended_without_result` child (item 01 §4) is surfaced with its `agentId`
   so the operator/Supervisor can `SendMessage` it (memory `subagents-hit-turn-limit-resume-via-sendmessage`)
   instead of re-running the subtask cold.

## Non-goals
No new review pass (D4). No change to what counts as a `provides` name (that is the brief's job). Does not
touch `/automate`'s own reconcile — it already reads git ground truth.

## Acceptance criteria
- Fixture: worker log with `outputs_verified: true` and a missing `provides` file → subtask stays
  incomplete and `outputs_verified_contradicted` is logged. Mutation control: remove the disk check, test fails.
- Fixture: one `agent_identity` with no terminal event → FINALIZE emits `children_unsettled` and does not
  merge; with `--non-interactive` the exit is the fail-closed path; with `--skip-children-check` it proceeds
  and the skip is recorded. A session with no `agent_identity` rows reports `children_check: no_identity_rows`,
  not `settled`.
- A healthy run (all children settled, all `provides` present) is byte-identical in behavior to today.

## Outcomes Rubric
- Completion = terminal event AND disk artefact, never self-report
- FINALIZE fails closed on unsettled children with named ids; explicit `--skip-children-check` only escape
- Resume path surfaced for ended-without-result children
- Healthy-run behavior unchanged (existing tests green)

## Status: done (PR #232, merge a6a8221, v15.80.0)
