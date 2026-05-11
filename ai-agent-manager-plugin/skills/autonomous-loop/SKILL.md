---
name: autonomous-loop
description: Outer-loop protocol for `/autonomous` — single-iteration and multi-iteration chaining of Launch Pad → Supervisor with EVALUATE phase, signal-extraction paths, refined-requirement templates, and the AUTONOMOUS_RUN summary format. Use when implementing or invoking the `/autonomous` command.
allowed-tools: [Read, Write, Bash, Grep, Task, AskUserQuestion]
version: "1.0.0"
lastUpdated: "2026-05-11"
---

# Autonomous Loop Skill

Protocol for the `/autonomous` outer loop. Owns the orchestration that chains Launch Pad → Supervisor, decides when to re-plan based on `SUPERVISOR_RESULT` signals, and emits an `AUTONOMOUS_RUN` summary. **Foreground-assisted automation, not fire-and-forget** — every interactive boundary in the inner workflows (Launch Pad Phase 6, NO-GO, Plan Review FAIL × 3, Supervisor adjudication, the loop's own rubric gate) bubbles `AskUserQuestion` to the user in-session via Claude Code's native interaction model.

<!-- v1 weakest implementation point: brief-save detection via ls-diff of `.supervisor/jobs/pending/`. This is single-session-only and fragile. The proper fix is a `LAUNCH_PAD_RESULT` schema with `saved_brief_path` field, which is a separate future plan and is the single biggest leverage point for hardening this work. -->

## Quick Rules

- The loop owns no schema, mutates no agent. It reads `SUPERVISOR_RESULT` and three file-system locations (`.supervisor/jobs/pending/`, `.supervisor/jobs/failed/`, `.supervisor/requirements/`); it writes only inside `.supervisor/autonomous/{session_id}/`, creates fresh requirement files in `.supervisor/requirements/`, and appends one JSONL log line per session to `.supervisor/logs/{session_id}.jsonl` (the session log).
- Single-iteration is the default mode. Multi-iteration requires explicit `--allow-multi-iteration`.
- Never auto-pick on adjudication. The 4 options surface to the user via Supervisor's existing `AskUserQuestion`.
- Two — and only two — signals trigger re-iteration: `rubric_score N<M` (gated by a user-merge confirmation) and `failed + inter_subtask_gap on this iteration's brief` (no merge needed; the job was abandoned).
- `current_brief_path` (captured at PLAN via `ls`-diff) is the iteration-scoping anchor. `.supervisor/jobs/failed/{basename(current_brief_path)}` existence is the unambiguous "this iteration failed" signal; prior runs have different filenames and can never collide.

## When to Use This Skill

- Implementing `/autonomous` (the slash command body references this skill).
- Diagnosing why an autonomous run ended in a particular state.
- Extending the loop with new signals (a follow-up plan reads this skill before adding behavior).

## Mode Selection

| Mode | Trigger | Behavior |
|---|---|---|
| **Single-iteration** | default — neither `--allow-multi-iteration` nor any iteration flag passed | INIT → PLAN → EXECUTE → DONE. No loop, no EVALUATE branching. Pure command chaining. |
| **Multi-iteration** | `--allow-multi-iteration` passed (with optional `--max-iterations N`, integer N ≥ 1, default `N=3`) | INIT → PLAN → EXECUTE → EVALUATE → (loop or DONE). EVALUATE may trigger re-plan on two signals. **N=1 is a degenerate but valid case:** the loop runs one iteration with full EVALUATE / rubric-gate reporting; if Signal 1 or Signal 2 would fire, the cap-check exits with `status: paused_max_iterations, status_reason: "max_iterations_reached"` instead of re-iterating. **N=0 or N<0** rejected at INIT with `status: aborted, status_reason: "invalid_max_iterations"`. |

Single-iteration is the safe default because (a) most user requirements complete in one cycle, (b) multi-iteration has real architectural caveats around PR merge cadence, (c) opt-in avoids surprising the user with multi-PR runs.

## Step 0 — Load Canonical Workflow Bodies + Protocol Skill (once per `/autonomous` invocation)

Before INIT, the main thread `Read`s the canonical command files **and this skill** end-to-end. **All paths use `${CLAUDE_PLUGIN_ROOT}`**, the canonical Claude Code variable that resolves to the plugin install dir on both maintainer dev checkouts and marketplace installs. Repo-relative `ai-agent-manager-plugin/...` paths only work in the maintainer checkout and **must not** be used at runtime (see CLAUDE.md "Repo path vs. runtime path"):

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md
Read ${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md   # this file — re-read at runtime so the protocol can't drift from what the command body assumes
```

This guards against prompt drift on three fronts. If Launch Pad, Supervisor, or this autonomous-loop protocol evolves between releases, `/autonomous` picks up the changes automatically. The "references, not duplicates" promise from the command body depends on this step. Without it, the autonomous body's references could become stale invocations of behaviors the main thread guesses at.

## INIT (once per invocation)

1. Read the requirement — slash command argument string OR `--requirement <path>`.
2. If string-argument: write `.supervisor/requirements/{session_id}-{slug}.md` (the `session_id` already carries the date — `auto-{YYYY-MM-DD}-{HHMMSS}` — so the path is sortable without a redundant date prefix). The file contains the requirement text and an optional `## Outcomes Rubric` placeholder. If `--requirement <path>` is used and the file already has `## Outcomes Rubric`, leave it intact.
3. Generate `session_id` of the form `auto-{YYYY-MM-DD}-{HHMMSS}` (or similar — must be unique enough that no two concurrent runs collide; per v1 single-session assumption, a timestamp suffices). **Collision risk in v1:** two sessions started in the same second would produce identical `session_id`s. Moot under the v1 single-session-only assumption (the loop also detects concurrent activity via the brief-save `ls`-diff and aborts with `status_reason: "concurrent_session_detected"`), but a v2 hardening can append a short random suffix (e.g., `auto-{YYYY-MM-DD}-{HHMMSS}-{4hex}`) once concurrent sessions become supported.
4. Initialize `.supervisor/autonomous/{session_id}/state.json` with the schema below.
5. Initialize `.supervisor/autonomous/{session_id}/summary.md` (running AUTONOMOUS_RUN summary; will be re-written as iterations complete).
6. Log session start to `.supervisor/logs/{session_id}.jsonl`.

### state.json schema

Example (concrete values shown — `mode` is one of the string literals `"single"` or `"multi"`, not a union annotation):

```json
{
  "_v1_note": "Advisory-only in v13.0.0 — this file is NOT AUTHORITATIVE for resume / recovery / cross-session state. It exists to seed future resume tooling (Doc 4 state.json sidecar work). The loop itself MAY read it for intra-session convenience inside the current run (e.g., the merge-verification step reads iterations[-1].branch), but external tools MUST NOT treat this file as authoritative; the markdown summary at .supervisor/autonomous/{session_id}/summary.md is the user-facing source of truth, and the SUPERVISOR_RESULT blocks in the transcript are the per-iteration source of truth.",
  "session_id": "auto-2026-05-11-143022",
  "requirement_path": ".supervisor/requirements/auto-2026-05-11-143022-add-jwt-auth.md",
  "mode": "single",
  "allow_multi_iteration": false,
  "iteration": 0,
  "max_iterations": 1,
  "current_brief_path": null,
  "iterations": [],
  "policy_decisions": [],
  "escalations_seen": [],
  "started_at": "2026-05-11T14:30:22Z",
  "last_updated": "2026-05-11T14:30:22Z"
}
```

Field types: `_v1_note: string` (advisory marker — see above); `mode: "single" | "multi"` (literal-union string); `iteration` and `max_iterations` are non-negative integers; `current_brief_path` is `string | null`; `iterations`, `policy_decisions`, `escalations_seen` are arrays; timestamps are ISO-8601 UTC. The `_v1_note` field is removable once a v2 plan defines a stable resume contract — its presence is the contract signal that tooling should not treat this file as authoritative.

## PLAN (per iteration)

1. Reference the loaded `commands/launch-pad.md` workflow. Invoke it inline on the main thread, passing the current requirement file path as input.
2. **Inline-instruction to Launch Pad (no source change):** before invoking Launch Pad, the main thread includes this directive in its inlined Launch Pad context: *"If the requirement file at `<requirement_path>` has an `## Outcomes Rubric` section, copy it verbatim into the saved brief during Phase 4 (Brief Assembly). Do not paraphrase, do not drop items, do not reformat."* Launch Pad will see this as part of the inlined workflow body.
3. Launch Pad runs Phases 1–6 inline including:
   - Phase 2.5 feasibility AskUserQuestion (NO-GO → override/revise/abort)
   - Phase 5.5 mandatory plan-reviewer Task spawn (max 3 FAIL retries → AskUserQuestion)
   - Phase 6 save/refine/discard AskUserQuestion
4. **Brief-save detection (v1 weakest point — `ls`-diff):**
   - **Pre-snapshot stale-session-id sanity check (catches the rubric_dropped_from_brief retry footgun):** before the `briefs_before` snapshot, check whether any file matching `<session_id>-*.md` already exists in `.supervisor/jobs/pending/`. The `session_id` is freshly minted in INIT (timestamp-based), so a pre-existing match is an invariant violation — almost always a stale brief left over from a prior aborted run of *this same `/autonomous` invocation pattern* (most commonly a previous `rubric_dropped_from_brief` abort whose stale brief the user didn't clean up). Surface this as a warning to the user with the explicit cleanup hint: `"Found stale brief(s) from a prior run with the same session-id shape: <files>. Move them to .supervisor/jobs/failed/ before continuing, or pick 'abort' below. Continuing now may produce a concurrent_session_detected error after Phase 6."` Then `AskUserQuestion` whether to (a) abort now, (b) move the stale files automatically and continue, or (c) continue anyway (force, recorded in policy_decisions for audit). Strictly speaking the timestamp-based session_id makes exact collisions impossible in v1, so this check fires only on the rubric_dropped_from_brief retry footgun and similar leftover-brief cases.
   - Before Phase 6's AskUserQuestion: `briefs_before = $(ls .supervisor/jobs/pending/*.md 2>/dev/null | sort)`
   - After Phase 6 (whether user picked save, refine-then-save, or discard): `briefs_after = $(ls .supervisor/jobs/pending/*.md 2>/dev/null | sort)`
   - `new_briefs = comm -13 <(echo "$briefs_before") <(echo "$briefs_after")`
   - If `new_briefs` is empty → user picked discard or refine failed. Mark `status: aborted, status_reason: "user_discarded_at_phase_6"`. Exit.
   - If `new_briefs` has exactly one entry → that path is `current_brief_path`. Record it in state.json. Proceed.
   - If `new_briefs` has >1 entries → ambiguity (concurrent run violated the single-session assumption). Abort with `status_reason: "concurrent_session_detected"`.
5. Handle Launch Pad's other abort paths:
   - User aborted at NO-GO → `status_reason: "user_aborted_at_no_go"`. Exit.
   - User aborted after Plan Review FAIL × 3 → `status_reason: "user_aborted_at_plan_review_fail"`. Exit.
6. **Rubric preservation verification (when applicable):** if the requirement file contained `## Outcomes Rubric`:
   ```bash
   if ! grep -qF "## Outcomes Rubric" "$current_brief_path"; then
     # Inline-instruction was not honored. Abort cleanly — the loop chose
     # to stop because a precondition for multi-iteration was violated,
     # not because the system itself failed. Pairs with status: aborted
     # per RESULT_SCHEMAS.md AUTONOMOUS_RUN status↔reason table.
     status=aborted; status_reason="rubric_dropped_from_brief"; exit
   fi
   ```
   This protects multi-iteration mode from silently degrading to single-iteration when Launch Pad ignores the inline instruction.
7. Update `current_brief_path` in state.json. Proceed to EXECUTE.

## EXECUTE (per iteration)

1. Reference the loaded `commands/supervisor.md` workflow. Invoke it inline on the main thread, passing `job: <current_brief_path>`.
2. Supervisor runs its existing 7-phase workflow inline (orchestrator → execute-manager → worker → code-reviewer → Phase 4.5 self-heal → Rubric Grader). Adjudication 4-option AskUserQuestion (when outputs_gap triggers it) bubbles to the user in-session per existing FAILURE_ESCALATION; the autonomous loop never auto-picks.
3. Supervisor moves the job through `pending/ → in-progress/ → done/ or failed/` per its existing lifecycle. The autonomous loop never touches the job lifecycle.
4. Capture the emitted `SUPERVISOR_RESULT` block (the last one in the transcript per `RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT" emission-cadence note) and record relevant fields into state.json's `iterations[]` array: `n`, `brief_path`, `supervisor_status`, `pr_url` (when present), `rubric_score`, `branch` (read directly from the `SUPERVISOR_RESULT.branch` field — a required v12.2-schema string), `summary`, `error` (when failed), `heal_decision`, `escalation_reason` (when completed_with_escalation). The `branch` field is what the merge-verification step (Signal 1 in EVALUATE) resolves to a SHA via `git rev-parse`.

5. **Fallback when Supervisor emits no `SUPERVISOR_RESULT`** (Supervisor crashed, terminal died mid-execute, network error before completion, Task spawn returned without a result block). Detect this by searching the transcript and finding zero `SUPERVISOR_RESULT` blocks for this iteration. The loop cannot infer Supervisor's actual state, but it CAN determine the loop-level outcome from filesystem evidence:
   - If `.supervisor/jobs/in-progress/{basename(current_brief_path)}` still exists → Supervisor never finished its lifecycle move. The job is in a half-state.
   - If `.supervisor/jobs/done/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted → likely a result-emission failure after the job moved; recoverable in principle but not in v1.
   - If `.supervisor/jobs/failed/{basename(current_brief_path)}` exists but no `SUPERVISOR_RESULT` was emitted → Supervisor moved it to `failed/` but crashed before emitting the result block.
   
   In all three cases, v1 terminates the loop with `AUTONOMOUS_RUN.status: failed`, `status_reason: "supervisor_failed_other"`, and **records a synthetic iteration entry** in `iterations[]` so the array length matches `total_iterations` per schema:
   
   ```yaml
   iterations:
     - n: <current iteration>
       brief_path: <current_brief_path>
       supervisor_status: failed              # synthesized — Supervisor didn't say
       pr_url: null
       rubric_score: null
       branch: ""                             # unknown; merge verification skipped
       summary: "Supervisor emitted no SUPERVISOR_RESULT block; loop synthesized this entry from filesystem evidence."
       error: "no_supervisor_result_emitted"
       heal_decision: null
       escalation_reason: null
   ```
   
   The user is expected to manually investigate `.supervisor/jobs/`, `.supervisor/state.md`, and `.supervisor/logs/{session_id}.jsonl` before re-running. The `error: "no_supervisor_result_emitted"` string is grep-stable for future tooling that may treat this case differently.

## EVALUATE (multi-iteration mode only)

Single-iteration mode skips EVALUATE entirely and jumps to DONE after EXECUTE.

Multi-iteration EVALUATE reads `SUPERVISOR_RESULT` (status, pr_url, error, summary, rubric_score, branch, heal_decision) plus iteration-scoped file-system artifacts (`.supervisor/jobs/pending/` for brief-save detection during PLAN, `.supervisor/jobs/failed/{basename(current_brief_path)}` for the Option-C iteration anchor, and that failed-brief's own contents for the `inter_subtask_gap` grep). **Two re-planning signals** drive loop continuation; a **default-termination branch** handles every other outcome:

### Signal 1 — `status: completed` AND `rubric_score N/M` with N<M

Loop pauses. Main-thread `AskUserQuestion` fires with the rubric gate:

> *"Iteration {N} completed with PR #{X} (rubric score {N/M}). To continue to iteration {N+1} (re-plan to address remaining rubric items), the prior PR should be merged first so the next iteration's Supervisor branches from updated `<default_branch>`. Options:*
> - *(a) merge-and-continue (you merge PR #{X} manually now, then pick this to proceed),*
> - *(b) stop-here (accept the current rubric score, exit),*
> - *(c) force-continue-anyway (proceed without merge; risk: iteration {N+1}'s branch won't include iteration {N}'s changes, likely producing conflicting PRs)."*

**If user picks `merge-and-continue`, the loop verifies the merge before re-planning.** The branch name comes from `SUPERVISOR_RESULT.branch` (an existing schema-1 field — see `docs/RESULT_SCHEMAS.md` §"SUPERVISOR_RESULT" for the field list); it was captured into `iterations[N].branch` during EXECUTE. The SHA is resolved from that branch name via `git rev-parse` on the **local** ref (not `origin/<branch>`, because we want the SHA the user pushed and we don't want a stale remote ref to hide the real tip):

> **Implementation note — `jq` is illustrative, not required.** The pseudocode below uses `jq` to extract `iterations[-1].branch` from `state.json` because it's the most concise way to write the example. In practice, **implementations should keep `current_brief_path` and the `iterations[].branch` values as in-memory state during the run**; reading state.json back at this point is wasteful and adds a `jq` (or equivalent JSON parser) dependency you don't need. The state.json writes are for persistence and future-recovery seed value (see "v1-only `_v1_note` field" later in this skill), NOT for intra-session lookups. Treat the `jq` line as a stand-in for "look up the most recent iteration's branch name from wherever your implementation stores it."

```bash
# PSEUDOCODE — see callout above. The `jq` extraction here illustrates
# the lookup; real implementations should use in-memory state.

# Read branch name from this iteration's recorded SUPERVISOR_RESULT
iter_N_branch="$(jq -r ".iterations[-1].branch" .supervisor/autonomous/${session_id}/state.json)"

# Resolve to a commit SHA — prefer the local ref the user pushed from
iter_N_branch_sha="$(git rev-parse "refs/heads/$iter_N_branch" 2>/dev/null \
                     || git rev-parse "origin/$iter_N_branch" 2>/dev/null)"
if [ -z "$iter_N_branch_sha" ]; then
  # Can't resolve a SHA for this branch at all. Treat merge as unverifiable —
  # do NOT auto-confirm. Re-prompt or fall through to gh-only verification.
  iter_N_branch_sha=""
fi

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
  # Re-prompt user — don't proceed on premature click or unverifiable merge
  AskUserQuestion "PR #$X is not yet showing as merged (gh: ${state:-unknown}; local ancestry: $( [ -n "$iter_N_branch_sha" ] && echo "checked" || echo "branch SHA unresolvable" )). Refresh and pick merge-and-continue again, or pick stop-here / force-continue-anyway."
fi
```

**If both `gh` is unavailable AND `iter_N_branch_sha` is unresolvable** (e.g., the branch has been deleted locally and never fetched from origin), the loop cannot positively verify the merge — it re-prompts the user rather than proceeding. The user can re-run after fetching, choose stop-here, or use force-continue-anyway (which records the bypass in `policy_decisions` for audit).

The loop **never** advances to iteration N+1 on `merge-and-continue` until one of the two checks confirms merge. This prevents premature re-iteration from a user who clicked too early.

**If `merge-and-continue` (verified):** create refined requirement:

```
{session_id}-iter{N+1}.md
---
<original requirement body, including `## Outcomes Rubric` verbatim>

---

## Iteration Note (autonomous loop, auto-generated 2026-05-11T14:55:00Z)

Prior iteration {N} scored **{N/M}** on the Outcomes Rubric. PR #{X} (`<pr_url>`) was merged before this iteration started.

The full rubric is preserved above; the next iteration must satisfy all items, including any not satisfied by the previously merged PR. Launch Pad's re-discovery (Phase 1) should compare the current `<default_branch>` state against the rubric and scope the new brief around the remaining gaps.
```

Loop back to PLAN with this new requirement file. Record `policy_decisions` entry: `{iteration: N, phase: EVALUATE, decision: "user_picked_merge_and_continue", source: "autonomous_rubric_gate"}`.

**If `stop-here`:** summary status=done, record `rubric_final_score: N/M`, last_phase=EVALUATE. Exit.

**If `force-continue-anyway`:** create refined requirement as above; merge is NOT verified; record `policy_decisions` entry with `decision: "user_picked_force_continue_anyway"`, source same. Loop back to PLAN.

### Signal 2 — `status: failed` AND Option C triggered this iteration

**Iteration-scoping anchor — anchor by filename, not by global grep:**

The autonomous loop already knows `current_brief_path` (set during PLAN). When Supervisor picks Option C, it moves the brief from `.supervisor/jobs/in-progress/` to `.supervisor/jobs/failed/` (per `agents/supervisor.md` Phase 3 adjudication-Option-C handler and `FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" Option C flow). So **the unambiguous current-iteration anchor is `.supervisor/jobs/failed/{basename(current_brief_path)}` existence**. Prior runs have different brief filenames (different date / session_id / slug), so this filename uniquely identifies this iteration's failed brief.

**Why not `grep "inter_subtask_gap" .supervisor/state.md` directly:** state.md is per-Supervisor-session and Context-Keeper rewrites it atomically (`agents/context-keeper.md:15`). A global grep MIGHT be naturally scoped, but the filename anchor is more robust against pathological cases (state.md not yet updated, concurrent inconsistency, etc.).

**Detection algorithm (after Supervisor returns `status: failed`):**

The pseudocode below is implementation-illustrative, not literally runnable bash. `EXIT_TO_DEFAULT_TERMINATION` is a structured-flow marker — a real implementation uses a function return, state-machine transition, or labeled break. The `RESULT_*` placeholders represent fields already extracted from the captured `SUPERVISOR_RESULT` block (see EXECUTE step 4); they are not shell environment variables and do not need to be exported.

```text
# Inputs available at this point:
#   current_brief_path           -- recorded in PLAN
#   RESULT_ERROR                 -- value of SUPERVISOR_RESULT.error   (string|null)
#   RESULT_SUMMARY               -- value of SUPERVISOR_RESULT.summary (string)
#
# Output:
#   gap_detected                 -- boolean; true = Signal 2 (Option C) fired

failed_path = ".supervisor/jobs/failed/" + basename(current_brief_path)

if not file_exists(failed_path):
    # Supervisor failed for some reason that didn't move this iteration's
    # brief to failed/ — merge conflict, env blocker, hard error before
    # adjudication, or any other crash path. NOT an Option C trigger.
    EXIT_TO_DEFAULT_TERMINATION   # see "Default termination" branch below

# Brief was marked failed. Check three iteration-scoped sources for
# the grep-stable substring "inter_subtask_gap" (any match = Option C).
# By load-bearing weight:
#   (b) SUPERVISOR_RESULT.error    -- PRIMARY signal. The gap reason is
#       Supervisor's own output, emitted by this iteration's
#       SUPERVISOR_RESULT block. This is where the string is reliably
#       present on Option C.
#   (c) SUPERVISOR_RESULT.summary  -- PRIMARY signal. Same Supervisor
#       block; the summary often reiterates the abort reason.
#   (a) the failed brief's contents -- BELT-AND-SUSPENDERS only. The
#       brief is a Launch Pad product (subtask specs, AC, rubric);
#       Supervisor moves the file to failed/ on Option C but in
#       current Supervisor versions does NOT necessarily append the
#       gap reason to the brief body. Keep this check in case a
#       future Supervisor version annotates the failed brief (a
#       reasonable hardening), but do not rely on it in v1 — sources
#       (b) and (c) are the real anchors.
#
# Filename is session_id-tagged so no other run can share it,
# eliminating cross-run false positives.
#
# .supervisor/state.md is intentionally NOT consulted — Context-Keeper
# rewrites it atomically (skills/state-management/SKILL.md), and pre-
# rewrite stale content from a prior session could survive briefly,
# producing a false positive. The three sources above are all inherently
# scoped to this iteration.
gap_detected = (
    file_contains_substring(failed_path,  "inter_subtask_gap")
 or string_contains_substring(RESULT_ERROR,   "inter_subtask_gap")
 or string_contains_substring(RESULT_SUMMARY, "inter_subtask_gap")
)

if not gap_detected:
    # Failed brief exists but no gap signal — Supervisor failed AND moved
    # the brief to failed/ for some non-Option-C reason.
    EXIT_TO_DEFAULT_TERMINATION   # see "Default termination" branch below

# Signal 2 fired. Continue with Option-C re-plan.
```

If `gap_detected=true`: Option C was the trigger. **No merge prompt** — the job was abandoned, no PR was created.

Create refined requirement:

```
{session_id}-iter{N+1}.md
---
<original requirement body>

---

## Iteration Note (autonomous loop, auto-generated <timestamp>)

Prior iteration {N} was abandoned via adjudication Option C ("Exit to Launch Pad") due to inter-subtask gap. The brief at `<current_brief_path>` had unresolvable producer-consumer mismatches that required re-planning from scratch.

The new iteration should re-discover dependencies and produce a fresh Subtask Structure with stricter `provides` / `requires` contracts.

(Note for Launch Pad re-discovery: the failed brief is preserved at `<failed_path>` for reference if helpful.)
```

Loop back to PLAN with this new requirement file. Record `policy_decisions` entry: `{iteration: N, phase: EVALUATE, decision: "supervisor_option_c_detected", source: "supervisor_adjudication"}`. **Note:** unlike the other entries in `policy_decisions` that capture a user choice at a *loop-level* `AskUserQuestion` gate, this one is **inferred by the loop from filesystem evidence** after Supervisor's own adjudication AskUserQuestion concluded inside Supervisor's session. The `_detected` suffix is a deliberate naming convention to flag this distinction for future tooling that parses `policy_decisions`.

### Default termination — any other SUPERVISOR_RESULT outcome ends the loop

Not a re-planning signal — this is the catch-all branch when neither Signal 1 nor Signal 2 fires. The loop emits the AUTONOMOUS_RUN summary and exits:

| `SUPERVISOR_RESULT.status` | Other condition | Loop action | summary status | status_reason |
|---|---|---|---|---|
| `completed` | rubric_score is null | terminate | `done` | null |
| `completed` | rubric_score = `N/N` | terminate | `done` | null |
| `completed` | rubric_score = `N/M` with N<M, user picks `stop-here` | terminate | `done` | `user_stopped_at_rubric_gate` |
| `completed_with_escalation` | any | terminate; populate `escalations_seen` | `done` | null (caveat in escalations_seen) |
| `failed` | inter_subtask_gap NOT detected | terminate | `failed` | `supervisor_failed_other` |
| `checkpoint` | any | terminate (no auto-resume in v1) | `aborted` | `supervisor_checkpoint` |

### Max-iterations cap

If signal 1 or 2 would re-plan AND `iteration + 1 > max_iterations`: terminate with summary status=`paused_max_iterations`, status_reason=`max_iterations_reached`. Record the unprocessed iteration intent in policy_decisions for audit.

## DONE — AUTONOMOUS_RUN Summary

Written to `.supervisor/autonomous/{session_id}/summary.md` (markdown for users) and `.supervisor/autonomous/{session_id}/state.json` (machine-readable sidecar). Echoed to main-thread output.

**Canonical schema:** see `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` § "AUTONOMOUS_RUN" for the formal `schema_version: 1` definition, the closed `status_reason` enum, validation rules, and a worked example. This skill describes the protocol that produces an `AUTONOMOUS_RUN` block; the schema doc is the source of truth for its shape.

The status enum is **autonomous-layer-only**: `done | paused_max_iterations | aborted | failed`. None of these values appear in `SUPERVISOR_RESULT.status` (which is `completed | completed_with_escalation | failed | checkpoint`). The two enums are intentionally distinct to prevent confusion and to keep the AUTONOMOUS_RUN summary out of scope for the Supervisor SubagentStop hook (which validates SUPERVISOR_RESULT, not AUTONOMOUS_RUN).

### summary.md format

```markdown
# Autonomous Run Summary

- **session_id:** auto-2026-05-11-143022
- **requirement_path:** `.supervisor/requirements/auto-2026-05-11-143022-add-jwt-auth.md`
- **mode:** single | multi
- **allow_multi_iteration:** true | false
- **max_iterations:** integer ≥ 1 (`1` for single-iteration runs — the implicit cap; the configured value for multi-iteration runs, default 3)
- **status:** done | paused_max_iterations | aborted | failed
- **status_reason:** null | "max_iterations_reached" | "user_discarded_at_phase_6" | "user_aborted_at_no_go" | "user_aborted_at_plan_review_fail" | "user_stopped_at_rubric_gate" | "supervisor_checkpoint" | "supervisor_failed_other" | "rubric_dropped_from_brief" | "concurrent_session_detected" | "invalid_max_iterations"
- **total_iterations:** 2
- **last_phase:** DONE | EVALUATE | PLAN | EXECUTE
- **started_at:** 2026-05-11T14:30:22Z
- **ended_at:** 2026-05-11T14:54:11Z
- **duration_seconds:** 1429

## Iterations

| n | Brief | Supervisor Status | PR | Rubric | Branch |
|---|---|---|---|---|---|
| 1 | `.supervisor/jobs/done/auto-...-add-jwt-auth.md` | completed | https://github.com/.../pull/42 | 3/5 | feature/jwt-auth |
| 2 | `.supervisor/jobs/done/auto-...-iter2.md` | completed | https://github.com/.../pull/43 | 5/5 | feature/jwt-auth-iter2 |

## Policy Decisions

| Iter | Phase | Decision | Source |
|---|---|---|---|
| 1 | PLAN | user_picked_save | launch_pad_phase_6 |
| 1 | EVALUATE | user_picked_merge_and_continue | autonomous_rubric_gate |
| 2 | PLAN | user_picked_save | launch_pad_phase_6 |

## Escalations Seen

(none) | heal_loop_max_retries (iteration N) | self_heal_resume_thrash (iteration N) | ...
```

### state.json (machine-readable sidecar)

Same fields as summary.md, structured as JSON. v1 writes it for two purposes: (a) intra-session convenience reads by the loop itself (the merge-verification step reads `iterations[-1].branch` from this file — see Signal 1 pseudocode above), and (b) seeding future Doc 4 state.json sidecar work. v1 explicitly does NOT use it for cross-session resume (no `--continue` flag exists), and no SubagentStop hook validates it. The file is **not authoritative for resume / recovery / cross-session state**.

**v1-only `_v1_note` field:** every state.json this loop writes begins with a `_v1_note` string field (see the schema example earlier in this skill). The field's contents explicitly mark the file as **advisory-only** in v1 and warn tooling against treating it as authoritative. The presence of `_v1_note` IS the v1 contract signal. A future v2 plan that defines a stable resume contract will remove this field; tooling that finds `_v1_note` MUST refuse to use the file for resume / recovery / state queries until a v2-compatible state.json (without `_v1_note`) is observed. The intent is to make accidental dependence on v1's advisory state impossible to do silently.

## Concurrency / Single-Session Assumption

**v1 assumes one autonomous session at a time per repo.** The brief-save `ls`-diff cannot distinguish a concurrent `/launch-pad` invocation's save from this loop's save. Session-id-tagged filenames in `.supervisor/requirements/` and `.supervisor/autonomous/{session_id}/` isolate the loop's own state, but the brief filename pattern in `.supervisor/jobs/pending/` is owned by Launch Pad's existing convention. A proper LAUNCH_PAD_RESULT schema (separate plan) closes this gap.

## Failure Modes & Recovery

| Failure | Detection | Recovery |
|---|---|---|
| User discards at Phase 6 | `new_briefs` empty after Phase 6 | Clean exit, summary status=aborted |
| Launch Pad ignores rubric-preservation inline instruction | `grep -F "## Outcomes Rubric" "$current_brief_path"` fails | Loop aborts with `status: aborted, status_reason: "rubric_dropped_from_brief"` (no iteration reaches EXECUTE; `total_iterations: 0`, `iterations: []`). **Cleanup required before re-running:** the abort fires *after* Launch Pad's Phase 6 save, so the saved brief is still sitting in `.supervisor/jobs/pending/` (filename starts with this run's `session_id`). The user must move or delete the stale brief before re-running `/autonomous`, otherwise the next run's brief-save `ls`-diff will see it as a "new" file and either pick it up by accident or trip `concurrent_session_detected`. One-liner: `mv .supervisor/jobs/pending/<this-session-id>-*.md .supervisor/jobs/failed/`. **Recovery paths:** re-run without `--allow-multi-iteration` (single-iteration ignores the rubric-preservation gate entirely), or pre-author the brief by hand with the rubric included. |
| Concurrent autonomous run or manual launch-pad | `new_briefs` has >1 entry after Phase 6 | Abort with status_reason="concurrent_session_detected" |
| Session terminated mid-loop | Process killed, terminal closed, machine restart | **v1: unsupported.** User must clean up `.supervisor/jobs/in-progress/`, close abandoned PRs, restart with `/autonomous`. Resume contract is its own plan (depends on Doc 4 state.json sidecar). |
| `gh` unavailable for merge check | `gh pr view` returns non-zero | Fallback to `git merge-base --is-ancestor`; if neither confirms, re-prompt user |
| `inter_subtask_gap` string drift (FAILURE_ESCALATION.md changes the grep-stable string) | Signal 2 detection silently fails | Loop falls through to the default-termination branch with `status_reason=supervisor_failed_other`; user inspects failed brief and re-runs. Promotion to typed enum is future work. |

## Hard Reuse Contract (no source changes)

- **Launch Pad inline workflow:** referenced via Step 0 + PLAN invocation. One inline instruction added (rubric preservation), delivered through the inlined prompt, not a Launch Pad source change.
- **Supervisor inline workflow:** referenced via Step 0 + EXECUTE invocation. No instruction modifications.
- **Adjudication 4-option escalation:** Supervisor surfaces existing options A/B/C/D via AskUserQuestion. The autonomous loop never auto-picks. Option C produces `failed + inter_subtask_gap` — the `inter_subtask_gap` substring is documented as grep-stable in `FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" (the doc explicitly promises grep-stability for telemetry / state.md consumers).
- **SUPERVISOR_RESULT schema (v12.2):** v1 reads existing fields only — `status`, `pr_url`, `error`, `summary`, `rubric_score`, `branch`. No schema change. `reason` does not exist on the block; v1 reads gap context from `SUPERVISOR_RESULT.error` / `SUPERVISOR_RESULT.summary` and from the failed brief's contents (see Signal 2 detection algorithm above).
- **`.supervisor/jobs/` lifecycle:** Supervisor remains sole writer/mover. The autonomous loop only reads `pending/` (for brief-save detection) and `failed/` (for Option-C anchor check).
- **`.supervisor/state.md`:** Context-Keeper remains sole writer per `agents/context-keeper.md`. The autonomous loop **does not** grep state.md for `inter_subtask_gap` — Signal 2 detection uses only the three iteration-scoped sources (failed-brief contents, `SUPERVISOR_RESULT.error`, `SUPERVISOR_RESULT.summary`) to avoid any false-positive risk from pre-rewrite stale content.

## Cross-References

- `${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md` — inline workflow Step 0 loads at runtime
- `${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md` — inline workflow Step 0 loads at runtime
- `${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md` — this skill; Step 0 loads at runtime
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` § "AUTONOMOUS_RUN" — canonical schema (`schema_version: 1`)
- `ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md` §"Inter-Subtask Gap / Scope Expansion" — adjudication 4 options and the `inter_subtask_gap` grep-stable string (documented as grep-stable for telemetry / `state.md` consumers, and re-used here as Signal 2's substring anchor)
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` — `SUPERVISOR_RESULT` schema including `rubric_score`
- `ai-agent-manager-plugin/skills/supervisor-readiness/SKILL.md` — brief format the autonomous loop relies on Launch Pad to produce
- `ai-agent-manager-plugin/skills/state-management/SKILL.md` — atomic-rewrite semantics of `.supervisor/state.md`
- `ai-agent-manager-plugin/agents/context-keeper.md` — sole-writer contract for state.md
- `ai-agent-manager-plugin/agents/supervisor.md` §"Phase 3 — Adjudication" / Option C handler — file-move behavior (brief moves from `in-progress/` to `failed/` when Option C is selected; reason `inter_subtask_gap` recorded in state.md)
