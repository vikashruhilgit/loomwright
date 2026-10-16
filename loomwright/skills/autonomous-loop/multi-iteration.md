# Autonomous Loop — multi-iteration protocol

Step 0 reads this file only when the run is NOT `--single-iteration`; `/automate` always passes `--single-iteration`, so its items never load it. `SKILL.md` stays the protocol for INIT, PLAN, EXECUTE and DONE; this file adds the multi-iteration-only parts, and each section keeps the heading `SKILL.md` points to. Why the rules read as they do: `docs/rationale/launch-pad-autonomous.md` §"/autonomous — why the rules read as they do".

## PLAN — multi-iteration additions

**Conditional auto-authoring directive (multi-iteration only, no rubric at intake):** when the run is in **multi-iteration mode** (`mode == "multi"`, i.e. NOT `--single-iteration`) AND `! has_rubric "$requirement_path"` (no real rubric per the canonical test in `SKILL.md` PLAN — an empty/placeholder header counts as absent) AND `--non-interactive-fallback` was NOT passed at INIT, the inlined directive ALSO instructs Launch Pad to **auto-author** a rubric via its guarded Phase 5 step: *"This requirement has no `## Outcomes Rubric` and the caller is running in multi-iteration mode. During Phase 5, auto-author a rubric — derive 3–7 diff-checkable bullets from the brief's Acceptance Criteria and the Phase 3 analysis, following `agents/launch-pad.md` Phase 5 step 7 and the authoring rules in `skills/supervisor-readiness/SKILL.md` §\"Auto-Authoring (multi-iteration)\". Do not restate those rules here — defer to them as the single source of truth."* (Those producers own the authoring contract; this directive only triggers it.) This is PLAN step 2's multi-iteration half.

**Never under `--non-interactive-fallback`:** an auto-authored rubric's only approval is the human approve/edit at Launch Pad Phase 6 (`skills/supervisor-readiness/SKILL.md` §"Auto-Authoring (multi-iteration)" — never blind-written), and under the Launch Pad forward (PLAN step 1) Phase 6 saves on PASS with nobody to approve it. So a `--non-interactive-fallback` run requests NO authoring, even in multi-iteration mode with no rubric: only the preserve-verbatim directive applies, the brief is saved without a rubric, step 7's freeze cannot fire (the saved brief fails its `has_rubric "$current_brief_path"` condition), and the iteration ends at EVALUATE's no-rubric gate with `status: done, status_reason: "no_rubric_in_non_interactive"`. A requirement that already carries a human-written rubric is unaffected.

**Degenerate-rubric fallback:** if Launch Pad cannot derive ≥3 diff-checkable bullets, it emits NO `## Outcomes Rubric` section and the loop proceeds under its no-rubric gate (Signal 1 is skipped). Auto-authoring is best-effort, never a hard precondition.

**PLAN step 7 — persist + freeze an authored rubric:** an AUTHORED rubric lives only in the saved brief at this point, but **every refined-requirement template** (Signal 1's stacked-mode and merge-and-continue templates AND Signal 2's Option-C template) copies the original requirement body from `<requirement_path>` — NOT from the brief — into iteration N+1. So the authored rubric is written back into the requirement body now, and every later iteration inherits it.

- **Fires ONLY when ALL of:** `mode == "multi"` AND the **current** requirement file at `<requirement_path>` has no real rubric yet (`! has_rubric "$requirement_path"`) AND the saved brief now has one (`has_rubric "$current_brief_path"` — Launch Pad auto-authored it and the human approved it at Phase 6). The has_rubric-on-the-current-file guard makes the step idempotent: it fires once, on the iteration that authored the rubric, and is a no-op afterwards. **Do NOT gate on a run-global "had rubric at intake" flag** — it never changes across iterations, so it would re-fire the append every iteration and accumulate duplicate rubric sections.
- **Extract + append + verify (all inside one idempotency guard),** so the verification (and its warning) runs only when a freeze was actually attempted:
  ```bash
  if [ "$mode" = "multi" ] \
     && ! has_rubric "$requirement_path" \
     && has_rubric "$current_brief_path"; then
    rubric_section="$(awk '/^## Outcomes Rubric/{f=1} f&&/^## /&&!/^## Outcomes Rubric/{exit} f' "$current_brief_path")"
    printf '\n\n%s\n' "$rubric_section" >> "$requirement_path"
    if ! has_rubric "$requirement_path"; then
      echo "WARNING: rubric freeze failed — '## Outcomes Rubric' not found in $requirement_path after append. Later iterations will run under the no-rubric gate." >&2
    fi
  fi
  ```
- **Non-interactive no-op:** under `--non-interactive-fallback` PLAN step 2 requests no authoring, so this step never freezes a rubric that no human approved: if the saved brief nonetheless carries a rubric the requirement lacked (unrequested), skip this step — do not append it.
- **Degenerate-case no-op:** if Launch Pad authored no rubric, the guard's third condition is false and the whole block (append AND verification) is skipped — no misleading "freeze failed" warning.

## EXECUTE — multi-iteration additions

### `--base-branch` passthrough (stacked mode)

When this iteration is iter N+1 of a stacked-mode run (`iteration > 1` AND `--no-stacked-branches` NOT active), EXECUTE step 1 MUST pass `--base-branch "$expected_base"` to Supervisor on top of the `job:` argument:

```text
expected_base = iterations[-2].branch   # parent iter's branch — same value EVALUATE's PR-base verification uses
/supervisor job: <current_brief_path> --base-branch "$expected_base"
```

The brief also carries a `Base Branch:` field under `## Configuration` (the stacked-mode refined-requirement template writes it). The CLI flag is the **authoritative source** — Supervisor's Phase 0 reads `--base-branch` first; the brief field is the fallback, and Plan Reviewer Criterion 13 FAILs a brief whose field disagrees with it. In `--no-stacked-branches` mode and on iter 1, do NOT pass `--base-branch`: Supervisor's Phase 0 defaults to `main`.

### `review_heal` field

When EVALUATE runs the chained review-and-heal step, it attaches the parsed `REVIEW_HEAL_RESULT` to this iteration's `iterations[]` entry under `review_heal`. The field is **null** when the step was skipped (no `pr_url`, or `supervisor_status == failed`); otherwise it holds the `skills/review-heal/SKILL.md` shape — `decision` (`PASS|ESCALATED`; `READY` is `--until-mergeable`-only and never emitted here), `iterations`, `issues_fixed`, `remaining_issues`, `pr_url`, `notified`:

```yaml
iterations:
  - n: 1
    brief_path: .supervisor/jobs/done/auto-...-add-jwt-auth.md
    supervisor_status: completed
    pr_url: "https://github.com/.../pull/42"
    rubric_score: "3/5"
    branch: feature/jwt-auth
    summary: "..."
    heal_decision: PASS
    review_heal:                       # null if skipped
      decision: PASS                   # PASS | ESCALATED
      iterations: 1
      issues_fixed: 0
      remaining_issues: 0
      pr_url: "https://github.com/.../pull/42"
      notified: false
```

## Stacked branches

- **Stacked (default):** iter N+1's feature branch is created from `iterations[N].branch` (`git checkout <iter N branch> && git checkout -b feature/<name>-iter{N+1}`), and its PR is opened with `--base <iter N branch>`. EVALUATE verifies the PR's base after Supervisor returns.
- **`--no-stacked-branches`:** iter N+1's feature branch is created from `main`; merge iter N's PR first (Signal 1's `merge-and-continue`), or each PR is independent and may conflict.
- **Out-of-order merge of a stacked PR corrupts the stack:** the bottom of the stack merges first. `iterations[]` is ordered by `n`, and that order IS the merge order.

## EVALUATE (multi-iteration mode only)

`SKILL.md` §"EVALUATE" runs the single-iteration short-circuit first; this body runs only in multi-iteration mode. It reads `SUPERVISOR_RESULT` (status, pr_url, error, summary, rubric_score, branch, heal_decision, branch_base, pr_state) plus iteration-scoped artifacts (`.supervisor/jobs/failed/{basename(current_brief_path)}` and that failed brief's contents). Order: PR-base verification → chained review-and-heal → token-ceiling check (`SKILL.md` INIT §`--max-tokens`) → Signal 1 / Signal 2 / no-rubric gate / default termination → max-iterations cap.

Implementations keep `current_brief_path` and the `iterations[].branch` values in memory; the `jq` reads of `state.json` below are illustrative stand-ins for that lookup.

### EVALUATE PR-base verification (AC-3 + AC-15)

Before evaluating signals, verify the iteration's PR was opened against the expected base. **Skip** (no verification) when:

- `iteration == 1` — no parent iter; base is `main`.
- `--no-stacked-branches` is active — every iter branches from `main`.
- `pr_url` is null — Supervisor failed before creating a PR. Do not call `gh pr view "null"`; fall through to Signal evaluation (`status: failed` takes default termination with `status_reason: "supervisor_failed_other"`).

Otherwise (`iteration > 1` AND stacked AND `pr_url` non-null):

```bash
expected_base="$(jq -r '.iterations[-2].branch' .supervisor/autonomous/${session_id}/state.json)"
# iterations[-1] is the CURRENT iteration; iterations[-2] is the parent whose branch is the expected base.

actual_base="$(gh pr view "$pr_url" --json baseRefName -q .baseRefName 2>/dev/null)"
if [ $? -ne 0 ]; then
  sleep 5
  actual_base="$(gh pr view "$pr_url" --json baseRefName -q .baseRefName 2>/dev/null)"  # retry once (AC-14)
  if [ $? -ne 0 ]; then
    if [ "$non_interactive" = "true" ]; then
      # AC-14 non-interactive fall-through: log and skip verify
      log "gh pr view --json baseRefName failed twice; non-interactive — skipping PR-base verification."
      record policy_decisions[] += {iteration: N, phase: EVALUATE, decision: "pr_base_verify_skipped_non_interactive", source: "autonomous_pr_base_verify"}
      goto signal_evaluation
    else
      # AC-14 interactive fallback: AskUserQuestion(retry / skip-verify-once / abort)
      AskUserQuestion(
        "gh pr view --json baseRefName failed twice for PR ${pr_url}. Pick one:",
        ["retry", "skip-verify-once", "abort"]
      )
      # retry: re-run gh once more; on failure re-prompt this same question once more (max one
      #        re-prompt). A second failed retry auto-aborts with status_reason="user_aborted_gh_retry".
      # skip-verify-once: record policy_decisions entry, continue as if verified.
      # abort: emit AUTONOMOUS_RUN.status=aborted, status_reason="user_aborted_gh_retry", exit.
    fi
  fi
fi

if [ "$actual_base" != "$expected_base" ]; then
  emit AUTONOMOUS_RUN.status="aborted", status_reason="iter_pr_base_mismatch"
  log "Iter $iteration PR opened against $actual_base, expected $expected_base. Aborting."
  exit
fi
```

This is the **second line of defense** — Supervisor's own Phase 4 self-verify is the first; both sites use the identical retry policy.

### EVALUATE review-heal step (chained PR review-and-heal — fresh isolated Task context)

After PR-base verification and **before** any Signal evaluation, run the standalone PR **review-and-heal** workflow as a chained step. `${CLAUDE_PLUGIN_ROOT}/skills/review-heal/SKILL.md` is the authority for its loop semantics; this section covers only how the loop invokes it and records the outcome. It is an **additional, multi-iteration-only gate** that informs the stacking decision; it is diff-only (it does NOT pass `--until-mergeable`) and is never a substitute for Supervisor step 5.5's post-PR drain.

**Skip** (fall straight through to Signal evaluation) when `pr_url` is null, or `SUPERVISOR_RESULT.status == failed`. It runs only after a successful iteration (`completed` / `completed_with_escalation`) with a non-null `pr_url`.

**Execution form (AC6 — Task step, NOT a nested `claude` process):** a **`Task`-spawned step with fresh isolated context** — entry sense **(b)** in `skills/review-heal/SKILL.md` §"Two entry senses of 'fresh'". It is NOT a nested `claude --agent loomwright:review-pr-runner` process (entry sense (a)), and per AC9 it does NOT `Task`-spawn the `review-pr-runner` agent (`docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting"). The Task body runs the review-heal **loop body inline**:

```text
review_heal = Task(
  subagent_type: "general-purpose",
  # Fresh isolated context; runs skills/review-heal/SKILL.md Step 1 + Step 2 inline.
  # It does NOT Task-spawn loomwright:review-pr-runner (AC9).
  prompt: "Run the PR review-and-heal loop on PR <pr_url> exactly per
           skills/review-heal/SKILL.md (resolve the head branch, bounded
           review→fix→re-review, default 3 iterations, NEVER --force, NEVER
           auto-merge). Emit a REVIEW_HEAL_RESULT block (schema_version 1) with
           decision (PASS|ESCALATED), iterations, issues_fixed, remaining_issues,
           pr_url, notified."
  # No --until-mergeable: schema_version 1, never decision: READY.
)
```

**Record the outcome** under this iteration's `review_heal` field (§"`review_heal` field" above).

**Branch on `decision`:**

- **`PASS`** → continue normally to Signal evaluation; PASS does not itself change the iterate-or-stop decision.
- **`ESCALATED`** → review-heal exhausted its bound or the reviewer returned `NEEDS_HUMAN`; findings were posted to the PR. Surface it through the loop's **existing `AskUserQuestion` escalation surface** — **do NOT invent a new gate or prompt mechanism**: name `remaining_issues` and `pr_url`, offer the existing continue / stop choices, and record `{iteration: N, phase: EVALUATE, decision: "review_heal_escalated", source: "autonomous_review_heal"}` in `policy_decisions`. Under `--non-interactive-fallback` (no TTY) it asks nothing and fails closed: `status: aborted, status_reason: "review_heal_escalated_non_interactive"` (the PR stays open with its posted findings).
- **`READY` / any unrecognized decision** → treat as a **terminal, non-re-iterate** state: do NOT loop back to PLAN and do NOT fire the escalation `AskUserQuestion`; fall through to Signal evaluation exactly as for `PASS`.
- **Additive v2 drain fields** (`channels_scanned`, `findings_validated`, `findings_dismissed`, `checks_waited`, the postmortem fields) → ignored: EVALUATE keys **only** off `decision` and the v1 core fields it records, so an extra field never changes its behavior.

Review-heal **never merges** the PR (`skills/review-heal/SKILL.md` §"No auto-merge ever").

### Signal 1 — `status: completed` AND `rubric_score N/M` with N<M (stacked rubric gate)

Loop pauses. **AC-5 webhook gate POST (when `--notify` AND `$LOOMWRIGHT_WEBHOOK_URL` are set)** — fired BEFORE the `AskUserQuestion` so the receiver knows a gate is imminent:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh" \
  --event-type gate \
  --gate-type rubric \
  --iteration "$iteration" \
  --session-id "$session_id" \
  --context "iter $iteration completed PR $pr_url with rubric $rubric_score; awaiting user decision" &
# Backgrounded, fire-and-forget (exit 0 always); the question below does not wait on delivery.
```

Main-thread `AskUserQuestion` then fires. The prompt branches on stacked vs non-stacked:

**Stacked-branch mode (default):**

> *"Iteration {N} completed with PR #{X} (rubric score {N/M}). Iteration {N+1} will branch from `iterations[{N}].branch` directly — no merge is required between iterations. Options:*
> - *(a) continue-to-next-iteration (proceed with iter N+1 stacked on top of iter N's branch — the typical v14 path),*
> - *(b) stop-here (accept the current rubric score, exit),*
> - *(c) force-continue-anyway (here, equivalent to continue-to-next-iteration; preserved for v13-compat scripting that expects this option)."*

**`--no-stacked-branches` mode:**

> *"Iteration {N} completed with PR #{X} (rubric score {N/M}). `--no-stacked-branches` is active, so iteration {N+1} will branch from `main` — PR #{X} should be merged first. Options:*
> - *(a) merge-and-continue (merge PR #{X} manually now, then pick this to proceed),*
> - *(b) stop-here (accept the current rubric score, exit),*
> - *(c) force-continue-anyway (proceed without merge; risk: iteration {N+1}'s branch won't include iteration {N}'s changes, likely producing conflicting PRs)."*

**Non-interactive fallback:** when `--non-interactive-fallback` is set AND no TTY, the gate does NOT call `AskUserQuestion`; the loop exits with `status: aborted, status_reason: "rubric_gate_closed_non_interactive"` (fail closed — never silently `continue`, never silently `stop`).

**Stacked mode — `continue-to-next-iteration` (no merge verification):** iter N+1's branch is created from `iterations[N].branch` at the start of the next EXECUTE; no `gh pr view` merge check. Write the stacked-mode refined requirement at `.supervisor/requirements/{session_id}-iter{N+1}.md`:

```
{session_id}-iter{N+1}.md
---
<original requirement body, including `## Outcomes Rubric` verbatim>

---

## Iteration Note (autonomous loop, stacked-mode auto-generated <ISO timestamp>)

Prior iteration {N} scored **{N/M}** on the Outcomes Rubric. PR #{X} (`<pr_url>`) is **unmerged** and is the stacking parent for this iteration — iteration {N+1}'s feature branch MUST be created from `iterations[N].branch` (`<iter_N_branch_name>`), NOT from `main`.

**Inline directive to Launch Pad (mandatory for this iteration):**
- The saved brief's `## Configuration` block MUST contain the line `Base Branch: <iter_N_branch_name>` verbatim. Plan Reviewer Criterion 13 will FAIL the brief if this is missing or refers to a branch that does not locally resolve.
- Re-discovery (Phase 1) MUST compare the current state of `<iter_N_branch_name>` against the rubric (NOT against `main` / `<default_branch>`) when scoping remaining work. Iteration {N}'s changes are present on `<iter_N_branch_name>` but NOT on `main`.
- The full rubric is preserved above; this iteration must satisfy all items, including any not satisfied by iteration {N}.
- Out-of-order merge of stacked PRs corrupts the stack. Reviewers must merge iter 1 first, then iter 2, etc. The AUTONOMOUS_RUN summary's `iterations[]` array preserves the merge order.
```

EXECUTE then also passes `--base-branch "<iter_N_branch_name>"` (§"`--base-branch` passthrough (stacked mode)").

**`--no-stacked-branches` mode — `merge-and-continue` (verified):** the loop verifies the merge before re-planning. The branch is `iterations[N].branch` (captured from `SUPERVISOR_RESULT.branch` in EXECUTE); the SHA is resolved from the **local** ref first:

```bash
iter_N_branch="$(jq -r ".iterations[-1].branch" .supervisor/autonomous/${session_id}/state.json)"
iter_N_branch_sha="$(git rev-parse "refs/heads/$iter_N_branch" 2>/dev/null \
                     || git rev-parse "origin/$iter_N_branch" 2>/dev/null)"
[ -z "$iter_N_branch_sha" ] && iter_N_branch_sha=""   # unresolvable: never auto-confirm

# Primary: gh CLI on the PR URL
merged=
state=$(gh pr view "$pr_url" --json state -q .state 2>/dev/null)
if [ "$state" = "MERGED" ]; then merged=true; fi

# Fallback: local ancestry check (only meaningful if we resolved a SHA)
if [ -z "$merged" ] && [ -n "$iter_N_branch_sha" ]; then
  default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)
  git fetch origin "$default_branch" 2>/dev/null
  if git merge-base --is-ancestor "$iter_N_branch_sha" "origin/$default_branch" 2>/dev/null; then merged=true; fi
fi

if [ -z "$merged" ]; then
  # Reached only after an INTERACTIVE merge-and-continue pick: a run that cannot ask
  # already stopped at the rubric gate (rubric_gate_closed_non_interactive).
  AskUserQuestion "PR #$X is not yet showing as merged (gh: ${state:-unknown}; local ancestry: $( [ -n "$iter_N_branch_sha" ] && echo "checked" || echo "branch SHA unresolvable" )). Refresh and pick merge-and-continue again, or pick stop-here / force-continue-anyway."
fi
```

**If both `gh` is unavailable AND `iter_N_branch_sha` is unresolvable**, the loop cannot verify the merge — it re-prompts rather than proceeding (re-run after fetching, stop-here, or force-continue-anyway, which records the bypass in `policy_decisions`). The loop **never** advances to iteration N+1 on `merge-and-continue` until one of the two checks confirms the merge.

**If `merge-and-continue` (verified):** create the refined requirement:

```
{session_id}-iter{N+1}.md
---
<original requirement body, including `## Outcomes Rubric` verbatim>

---

## Iteration Note (autonomous loop, auto-generated <ISO timestamp>)

Prior iteration {N} scored **{N/M}** on the Outcomes Rubric. PR #{X} (`<pr_url>`) was merged before this iteration started.

The full rubric is preserved above; the next iteration must satisfy all items, including any not satisfied by the previously merged PR. Launch Pad's re-discovery (Phase 1) should compare the current `<default_branch>` state against the rubric and scope the new brief around the remaining gaps.
```

Loop back to PLAN with this file. Record `{iteration: N, phase: EVALUATE, decision: "user_picked_merge_and_continue", source: "autonomous_rubric_gate"}`.

**If `stop-here`:** summary status=done, record `rubric_final_score: N/M`, last_phase=EVALUATE. Exit.

**If `force-continue-anyway`:** create the refined requirement as above; merge is NOT verified; record `decision: "user_picked_force_continue_anyway"`, same source. Loop back to PLAN.

### Signal 2 — `status: failed` AND Option C triggered this iteration

**Iteration-scoping anchor — anchor by filename, not by global grep:** when Supervisor picks Option C it moves the brief from `.supervisor/jobs/in-progress/` to `.supervisor/jobs/failed/` (`agents/supervisor.md` Phase 3 adjudication Option-C handler; `docs/FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion"). So **`.supervisor/jobs/failed/{basename(current_brief_path)}` existence is the current-iteration anchor**; prior runs have different filenames. Do not grep `.supervisor/state.md` for the gap.

**Detection (after Supervisor returns `status: failed`)** — illustrative, not literal bash; `EXIT_TO_DEFAULT_TERMINATION` is a structured-flow marker and `RESULT_*` are fields already extracted from the captured `SUPERVISOR_RESULT`:

```text
failed_path = ".supervisor/jobs/failed/" + basename(current_brief_path)

if not file_exists(failed_path):
    # Supervisor failed without moving this brief to failed/ (merge conflict, env blocker,
    # hard error before adjudication). NOT an Option C trigger.
    EXIT_TO_DEFAULT_TERMINATION

# Three iteration-scoped sources for the grep-stable substring "inter_subtask_gap" (any match =
# Option C): RESULT_ERROR and RESULT_SUMMARY are the primary signals; the failed brief's
# contents are belt-and-suspenders only. .supervisor/state.md is never consulted.
gap_detected = (
    file_contains_substring(failed_path,  "inter_subtask_gap")
 or string_contains_substring(RESULT_ERROR,   "inter_subtask_gap")
 or string_contains_substring(RESULT_SUMMARY, "inter_subtask_gap")
)

if not gap_detected:
    # Failed brief exists but no gap signal — a non-Option-C failure.
    EXIT_TO_DEFAULT_TERMINATION

# Signal 2 fired. Continue with Option-C re-plan.
```

If `gap_detected=true`: Option C was the trigger. **No merge prompt** — the job was abandoned and no PR was created. Create the refined requirement:

```
{session_id}-iter{N+1}.md
---
<original requirement body, including `## Outcomes Rubric` verbatim (if one was authored/frozen)>

---

## Iteration Note (autonomous loop, auto-generated <timestamp>)

Prior iteration {N} was abandoned via adjudication Option C ("Exit to Launch Pad") due to inter-subtask gap. (The "original requirement body" copied above is the current `<requirement_path>` file body, which carries the frozen `## Outcomes Rubric` verbatim if one was authored — same as the Signal-1 templates.) The brief at `<current_brief_path>` had unresolvable producer-consumer mismatches that required re-planning from scratch.

The new iteration should re-discover dependencies and produce a fresh Subtask Structure with stricter `provides` / `requires` contracts.

(Note for Launch Pad re-discovery: the failed brief is preserved at `<failed_path>` for reference if helpful.)
```

Loop back to PLAN with this file. Record `{iteration: N, phase: EVALUATE, decision: "supervisor_option_c_detected", source: "supervisor_adjudication"}`. The `_detected` suffix is a deliberate naming convention: this entry is inferred from filesystem evidence after Supervisor's own adjudication, not a user choice at a loop-level gate.

### No-rubric gate (`status: completed` AND `rubric_score` is null)

When the iteration's brief had no `## Outcomes Rubric` AND multi-iter is active, the loop fires the no-rubric gate. **AC-5 webhook gate POST first (when `--notify` set):**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh" \
  --event-type gate \
  --gate-type no_rubric \
  --iteration "$iteration" \
  --session-id "$session_id" \
  --context "iter $iteration completed PR $pr_url without rubric; awaiting continue/stop decision" &
```

Then `AskUserQuestion`:

> *"Iteration {N} completed with PR #{X}. The brief had no `## Outcomes Rubric`, so there is no per-item score to evaluate. Continue to iteration {N+1} (re-plan to refine or extend), or stop here? Options:*
> - *(a) continue (loop to PLAN with a refined-requirement note appended),*
> - *(b) stop (accept and exit with `status: done`)."*

**Non-interactive fallback:** when `--non-interactive-fallback` is set AND no TTY, the gate exits with `status: done, status_reason: "no_rubric_in_non_interactive"` — the loop accepts the iteration cleanly (does NOT abort): with no rubric there is no quality signal to gate on.

**`continue`:** create a refined requirement (same template shape as Signal 1's, minus the rubric reference), loop to PLAN. Record `{iteration: N, phase: EVALUATE, decision: "user_continued_no_rubric", source: "autonomous_no_rubric_gate"}`.

**`stop`:** emit AUTONOMOUS_RUN.status=done, status_reason="user_stopped_at_no_rubric_gate", exit.

### Default termination — any other SUPERVISOR_RESULT outcome ends the loop

The catch-all when neither Signal 1, Signal 2 nor the no-rubric gate fires. The loop emits the AUTONOMOUS_RUN summary and exits:

| `SUPERVISOR_RESULT.status` | Other condition | Loop action | summary status | status_reason |
|---|---|---|---|---|
| `completed` | rubric_score = `N/N` (perfect score) | terminate | `done` | null |
| `completed` | rubric_score = `N/M` with N<M, user picks `stop-here` at rubric gate | terminate | `done` | `user_stopped_at_rubric_gate` |
| `completed` | rubric_score is null, user picks `stop` at no-rubric gate | terminate | `done` | `user_stopped_at_no_rubric_gate` |
| `completed` | rubric_score is null, non-interactive fallback | terminate | `done` | `no_rubric_in_non_interactive` |
| `completed_with_escalation` | any | terminate; populate `escalations_seen` | `done` | null (caveat in escalations_seen) |
| `failed` | `pr_url == null` (Supervisor pre-PR failure, AC-15) | terminate | `failed` | `supervisor_failed_other` |
| `failed` | inter_subtask_gap NOT detected, `pr_url` non-null | terminate | `failed` | `supervisor_failed_other` |
| `failed` | `base_branch_mismatch` from Supervisor Phase 4.5 cleanup | terminate | `failed` | `supervisor_base_branch_mismatch` |
| `failed` | `error`/`status_reason` = `preflight_overlap_detected` (Supervisor Phase 1.5 pre-flight fail-closed abort — CI / non-TTY OVERLAP or SUPERSEDED) | terminate (loop stops; do NOT re-iterate) | `failed` | `preflight_overlap_detected` |
| `checkpoint` | any | terminate (no auto-resume) | `aborted` | `supervisor_checkpoint` |

### Phase 1.5 pre-flight gate — CI fail-closed termination

The loop meets Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate only through `SUPERVISOR_RESULT`. Under the forwarded `--non-interactive` (or a non-TTY session) an `OVERLAP` / `SUPERSEDED` classification cannot be escalated, so Supervisor fails closed with `status: failed` and `error`/`status_reason` = `preflight_overlap_detected`; the loop terminates on it (Default-termination row above) and surfaces `AUTONOMOUS_RUN.status_reason: "preflight_overlap_detected"` — never a re-iteration: the overlap is a precondition the user resolves (revise scope, or run `/supervisor --skip-preflight-sync` by hand).

- `--skip-preflight-sync` is not in the loop's `/supervisor` forward set (`SKILL.md` EXECUTE step 1 §"Auto-forwarded flags"), so the gate runs in every iteration.
- It complements, and never double-fires with, EVALUATE PR-base verification: the pre-flight gate checks *work overlap* on `$BASE_BRANCH` before decomposition; PR-base verification checks the stacked PR's `baseRefName` after FINALIZE. `preflight_overlap_detected` and `iter_pr_base_mismatch` / `supervisor_base_branch_mismatch` are distinct status reasons.

### Max-iterations cap

If Signal 1 or Signal 2 would re-plan AND `iteration + 1 > max_iterations`: terminate with summary status=`paused_max_iterations`, status_reason=`max_iterations_reached`. Record the unprocessed iteration intent in `policy_decisions` for audit.
