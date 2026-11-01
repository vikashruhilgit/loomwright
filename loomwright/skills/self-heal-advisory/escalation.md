# Self-Heal Protocol — escalation paths (base-mismatch cleanup, fix-task crash)

Read by the Supervisor only when on-entry step 5 (`on-entry.md`) finds the `base_mismatch_detected` flag set, or when a fix Task() returns an error or no FIX_RESULT block (a routed `heal_fix` edit failure included). Part of `skills/self-heal-advisory/` (index: `SKILL.md`).

## Phase 4.5 base-mismatch cleanup (step 5)

`mismatch` is the non-null `base_mismatch_detected` flag read at on-entry step 5:

   1. **Close the orphan PR best-effort** (do not abort on failure — the PR may already be closed, or `gh` may still be unavailable):
      ```bash
      gh pr close "$PR_URL" --comment "Automatically closed by /autonomous loop: base branch mismatch detected — expected ${mismatch.expected}, found ${mismatch.actual}. See SUPERVISOR_RESULT for details. Reason: ${mismatch.reason}." || true
      ```
      Capture the exit code:
      - `0` → `PR_STATE="closed_by_loop"`
      - non-zero → `PR_STATE="close_attempt_failed"`
   2. **Move brief to `failed/`:** if `job:` parameter was used, move the brief from `.supervisor/jobs/in-progress/` → `.supervisor/jobs/failed/` and append an `## Outcome` block with `**Status:** failed`, `**Reason:** base_branch_mismatch`, `**Expected:** ${mismatch.expected}`, `**Actual:** ${mismatch.actual}`, `**PR state:** ${PR_STATE}`.
   3. **Record the decision:** `record_decision(phase: SELF_HEAL, decision: "base_mismatch_cleanup", rationale: "expected=${mismatch.expected}, actual=${mismatch.actual}, pr_state=${PR_STATE}")`.
   4. Progress state is not written here — it is derived (on-entry step 1). This exit path returns without the standard completion tail and never emits a `session_end` event, so `state.md`'s `- status:` keeps its last derived value (`running`). No automated read-side check catches this residual: a KNOWN, accepted gap (`docs/rationale/supervisor.md` §"Base-mismatch cleanup residual") — do not reintroduce a "write your state" instruction for this path.
   5. **Clear the flag (REQUIRED before returning, even on `gh pr close` failure — read-on-start-clear-on-start invariant):**
      ```
      Context-Keeper(operation: clear_flag, key: "base_mismatch_detected")
      ```
   6. **Reset resume counter:** `Context-Keeper(operation: record_self_heal_resume, increment: false)`.
   7. **Emit single `SUPERVISOR_RESULT` block** with:
      ```yaml
      SUPERVISOR_RESULT:
        schema_version: 1
        task_id: {task_id}
        status: failed
        pr_url: {PR_URL}
        branch: {feature_branch}
        branch_base: {mismatch.expected}    # the BASE_BRANCH we expected
        subtasks_completed: {N}
        subtasks_failed: 0
        heal_loop_ran: false
        heal_iterations: null
        heal_decision: null
        heal_first_decision: null
        heal_new_findings: null
        heal_fixable_issues_fixed: 0
        heal_remaining_issues: 0
        error: "base_branch_mismatch: expected ${mismatch.expected}, found ${mismatch.actual} (reason: ${mismatch.reason})"
        pr_state: {PR_STATE}                # "closed_by_loop" | "close_attempt_failed"
        summary: "Phase 4 self-verify detected PR base-branch mismatch; Phase 4.5 closed PR best-effort and moved job to failed/. No code changes were merged."
        cost_profile: {default|cheap|null}
        rubric_score: null
      ```
   8. **Return** from Phase 4.5 — do NOT run the review-and-fix loop, do NOT run the standard completion tail. This is a single exit point that emits exactly one `SUPERVISOR_RESULT`.

   **Field semantics:**
   - `branch_base` = the BASE_BRANCH the PR was expected to target (lets the autonomous-loop EVALUATE phase detect this failure without parsing `error`). `pr_state` (optional): `"closed_by_loop"` | `"close_attempt_failed"` | absent (no PR action taken).
   - On absent `gh` (`actual: null`), report `actual` as `null` in the error message and rely on the `reason` field to disambiguate (`gh_unavailable_non_interactive` vs `user_aborted_gh_retry`).

## Fix task crash handling
- If the fix Task() returns an error or no FIX_RESULT block: pause the phase by emitting `SUPERVISOR_RESULT` with `status: checkpoint` (the schema has no `paused` status — `checkpoint` is the pause analogue) and exit with the resume command. Do NOT increment the resume counter now — the increment happens at Phase 4.5 entry of the next `--continue` run (on-entry step 3).

## Routed fix edit failure

When the `heal_fix` write seat is routed (`SKILL.md` §"Seat routing (`heal_fix`)"), the fix task reads `write_status` from `write-run.sh`'s `--out` JSON (the closed list is that script's header). The routed outcomes map like this:
- `ok`: the fix task runs steps 3–4. If a post-edit check fails, it first runs `write-run.sh --restore <pre-launch sha>`, then applies the next bullet with reason `post_edit_gate`.
- A pre-launch refusal, `write_timeout`, `write_failed` or `write_protected_path` (the tree is already restored): under `fallback_to_default` the fix task makes the fix itself on the clean tree and logs one `seat_routing heal_fix provider=<p> reason=<write_status|post_edit_gate>` line. Under `strict` it prints `WRITE_SEAT_FAILED: <status> — <notes>` with no FIX_RESULT, and you take §"Fix task crash handling" above.
- `write_git_tampered`, under either mode: the fix task prints `WRITE_SEAT_TAMPERED: <notes>`. This is never the crash path: the loop exits at once with `error: "write_seat_tampered"` and the brief moves to `failed/` (`SKILL.md`; `completion-tail.md` steps 1–2).
