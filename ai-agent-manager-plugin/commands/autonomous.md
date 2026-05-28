---
description: Chain Launch Pad → Supervisor for a single requirement, with optional multi-iteration re-planning gated on existing SUPERVISOR_RESULT signals
---

> **Execute this workflow inline as the main thread.** Do not delegate to any `autonomous-*-runner` via the Agent tool — `/autonomous` runs the entire Launch Pad and Supervisor workflows inline, and both of those require Task descendants (`plan-reviewer`, `orchestrator`, `execute-manager`, `code-reviewer`, etc.). An extra delegation layer would hit the documented subagent-spawn trap and the inner workflows would silently abort. The `/autonomous` command is a thin orchestration shell that references Launch Pad and Supervisor's inline workflows; it does NOT introduce a new delegated agent.

> **Foreground-assisted automation, not fire-and-forget.** The loop will prompt you in-session at several points:
> - Launch Pad **Phase 6**: save / refine / discard the brief
> - Launch Pad **NO-GO** or **Plan Review FAIL × 3** (rare): override / revise / abort
> - Supervisor **adjudication 4-option** (if outputs_gap triggers it during EXECUTE): re-queue / remediate / exit-to-Launch-Pad / update-consumer
> - **Autonomous rubric gate** (multi-iteration mode only, after rubric N<M): merge-and-continue / stop-here / force-continue
>
> You must be at the terminal to answer these. The "autonomous" value is command chaining + automatic re-plan on two specific signals (defined below), not removing human gates.

# Command: /autonomous

## Purpose

`/autonomous` chains Launch Pad → Supervisor for one requirement so you do not have to manually run `/launch-pad "..."` then `/supervisor job: <path>`. In the default **single-iteration mode**, the command runs both workflows in sequence and exits. In opt-in **multi-iteration mode** (`--allow-multi-iteration`), the loop additionally evaluates `SUPERVISOR_RESULT` and may re-plan from a refined requirement when one of two specific signals fires.

This is a v13.0.0 addition. It introduces no new agent, no new hook, no behavioral change to any existing agent / hook / script / skill / command, and no change to the field types or validation rules of any existing schema. New artifacts only: this slash command, the `autonomous-loop` skill, and one additive `AUTONOMOUS_RUN` entry in `RESULT_SCHEMAS.md` (autonomous-layer-only, no hook validation). Metadata/docs surfaces are updated to reflect counts and the new entries.

## Usage

```bash
/autonomous "<requirement string>"                                       # single-iteration mode
/autonomous --requirement <path/to/file.md>                              # single-iteration mode, file-supplied
/autonomous "<...>" --allow-multi-iteration                              # multi-iteration with default max
/autonomous "<...>" --allow-multi-iteration --max-iterations N           # multi-iteration capped at N (default N=3)
```

> **Cost-profile note:** `--cheap` is **not forwarded** in v13. If you need the Sonnet cost profile, run `/launch-pad` and `/supervisor --cheap` manually (see Parameters → `--cheap interaction note` for details). The autonomous loop is genuinely expensive — each iteration is a full Launch Pad + full Supervisor run.

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `"<requirement>"` | One of | Inline requirement string. Loop writes it to `.supervisor/requirements/{session_id}-{slug}.md` (where `session_id` is `auto-{YYYY-MM-DD}-{HHMMSS}` — already date-prefixed, so the path is sortable without a redundant date) with an optional `## Outcomes Rubric` placeholder for the user to fill in. |
| `--requirement <path>` | One of | Use an existing requirement file. If the file already contains an `## Outcomes Rubric` section, it is preserved and used by multi-iteration mode. |
| `--allow-multi-iteration` | No | Enable multi-iteration mode. Default is single-iteration (no looping). |
| `--max-iterations N` | No | Maximum iterations in multi-iteration mode. Integer `N >= 1`; default `N=3`. **Ignored in single-iteration mode (the default)** — passing `--max-iterations` without also passing `--allow-multi-iteration` has no effect; multi-iteration must be explicitly enabled. The loop never silently upgrades single-iteration to multi-iteration based on this flag alone. **Edge case `N=1`:** valid but degenerate — the loop runs one iteration with full EVALUATE / rubric-gate reporting; if Signal 1 or Signal 2 fires the cap-check exits immediately with `status: paused_max_iterations, status_reason: "max_iterations_reached"`. Useful when you want multi-iteration's summary fields (rubric_final_score, escalations_seen) but not actual re-iteration. **Invalid `N=0` or `N<0`** rejected at INIT with `status: aborted` and a clear error message. |

**Not in v13.0.0** (each deferred to a future plan with its prerequisite): `--status`, `--continue`, `--abort`, `--stacked-branches`, `--cheap`, `--notify`, `--background`, `--auto-merge`.

> **`--cheap` interaction note:** Passing `--cheap` to `/autonomous` in v1 has **no effect** — the loop does not forward unknown flags to the inlined `/supervisor` call, and `/supervisor`'s `--cheap` cost-profile (Sonnet overrides for orchestrator / execute-manager / worker / code-reviewer / Phase 4.5 fix tasks) is not wired through here. If you want the cost-optimized profile for a single requirement, run the workflows manually instead: `/launch-pad "..."` then `/supervisor job: <brief-path> --cheap`. A future plan can add `--cheap` passthrough once the cost-profile semantics are clarified for multi-iteration cycles.

> **Quoting paths with spaces:** if the `--requirement <path>` value contains spaces, enclose the whole path in double quotes. Example: `/autonomous --requirement ".supervisor/requirements/My Feature.md"`. Without the quotes the path is split on the first space and the loop will error or read the wrong file.

## What This Does

### Step 0 — Load Canonical Workflow Bodies + Protocol Skill (always)

Before anything else, the main thread reads the canonical inline workflows and the autonomous-loop protocol skill so it executes the up-to-date versions rather than remembered shapes. **All three reads use `${CLAUDE_PLUGIN_ROOT}`**, which is the canonical Claude Code variable that resolves to the plugin install dir at runtime (works on both maintainer dev checkouts and marketplace installs). Never use `ai-agent-manager-plugin/...` here — that path only resolves for the plugin maintainer:

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md
Read ${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md
```

This guards against prompt drift on three fronts. If Launch Pad, Supervisor, or the autonomous-loop protocol evolves between releases, `/autonomous` picks up the changes automatically because it re-reads them every run.

### Single-Iteration Mode (default)

```
INIT → PLAN → EXECUTE → DONE
```

The loop runs Launch Pad inline, then Supervisor inline on the saved brief, then emits an AUTONOMOUS_RUN summary and exits. No re-iteration logic runs.

### Multi-Iteration Mode (`--allow-multi-iteration`)

```
INIT → PLAN → EXECUTE → EVALUATE → (loop back to PLAN with refined requirement, OR DONE)
```

After Supervisor returns, EVALUATE reads `SUPERVISOR_RESULT` and applies one of three branches:

| `SUPERVISOR_RESULT.status` | Other condition | Loop action |
|---|---|---|
| `completed` | `rubric_score` is `N/M` with N<M | Pause for **rubric-gate AskUserQuestion** (merge-and-continue / stop-here / force-continue). On `merge-and-continue`, verify merge via `gh pr view` or local `git merge-base --is-ancestor` before re-planning. |
| `failed` | `inter_subtask_gap` detected on this iteration's brief | Re-plan immediately (no merge needed; job was abandoned via adjudication Option C). |
| anything else | — | Terminate the loop. Specifically: `completed + no-rubric / N=M` → done; `completed_with_escalation` → done with escalations_seen; `failed (other)` → failed; `checkpoint` → aborted (no auto-resume in v1). |

The detailed protocol — including the `ls`-diff brief-save detection, the anchor-by-filename Option-C scoping, the merge-verification sequence, and the refined-requirement templates — lives in `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md`.

### What runs inline (Launch Pad's existing AskUserQuestion gates bubble up)

Phase 2.5 NO-GO override, Phase 5.5 Plan Reviewer FAIL × 3, Phase 6 save/refine/discard — all of Launch Pad's existing prompts fire in-session via Claude Code's native interaction model. The user answers, the workflow continues. No `/autonomous --continue` is needed for the normal interactive path.

### What runs inline (Supervisor's existing AskUserQuestion gates bubble up)

Adjudication 4-option escalation (when a Worker's `outputs_gap` triggers it) fires in-session. The autonomous loop never auto-picks. If the user picks Option C "Exit to Launch Pad", Supervisor marks the job `failed` with `inter_subtask_gap` recorded — the loop catches that signal in EVALUATE and re-plans.

### Inline instruction to Launch Pad (rubric preservation)

When `/autonomous` invokes Launch Pad inline, it adds one explicit directive to the inlined workflow body:

> *"If the requirement file at `<requirement_path>` has an `## Outcomes Rubric` section, copy it verbatim into the saved brief during Phase 4 (Brief Assembly). Do not paraphrase, do not drop items."*

After Phase 6 saves, the loop verifies this with `grep -F "## Outcomes Rubric" "$current_brief_path"`. If the section is missing from the saved brief, the iteration aborts cleanly with `status_reason: "rubric_dropped_from_brief"` (a graceful fallback that prevents multi-iteration from silently degrading to single-iteration).

## Example Sessions

### Single-iteration smoke test

```bash
$ /autonomous "add a /version command that prints plugin version"
```

The loop writes `.supervisor/requirements/auto-2026-05-11-143022-add-a-version-command.md`, runs Launch Pad inline (you confirm save at Phase 6), runs Supervisor inline (it produces PR #42), and emits:

```
# Autonomous Run Summary
- session_id: auto-2026-05-11-143022
- mode: single
- status: done
- total_iterations: 1
- iterations:
  - { n: 1, supervisor_status: completed, pr_url: "https://github.com/.../pull/42", rubric_score: null }
```

### Multi-iteration with rubric-driven re-planning

```bash
$ /autonomous --requirement .supervisor/requirements/jwt-auth-with-rubric.md --allow-multi-iteration
```

The requirement file already contains an `## Outcomes Rubric` with 5 items. Iteration 1 runs Launch Pad → Supervisor → produces PR #42 with `rubric_score: "3/5"`. The rubric gate fires:

> *"Iteration 1 completed with PR #42 (rubric score 3/5). To continue, merge PR #42 first. Options: merge-and-continue / stop-here / force-continue-anyway."*

You merge PR #42 manually, then pick `merge-and-continue`. The loop verifies the merge with `gh pr view #42 --json state` → `MERGED`. It writes `.supervisor/requirements/2026-05-11-...-iter2.md` referencing the rubric and the merged PR, then loops back to PLAN. Iteration 2: Launch Pad re-discovers (now sees PR #42's merged code), scopes the brief around the remaining 2 rubric items, Supervisor produces PR #43 with `rubric_score: "5/5"`. The loop terminates.

```
- session_id: auto-...
- mode: multi
- status: done
- total_iterations: 2
- iterations:
  - { n: 1, pr_url: ".../pull/42", rubric_score: "3/5" }
  - { n: 2, pr_url: ".../pull/43", rubric_score: "5/5" }
- policy_decisions: [user_picked_save, user_picked_merge_and_continue, user_picked_save]
```

### Multi-iteration with Option-C re-planning

```bash
$ /autonomous --requirement .supervisor/requirements/refactor-with-hidden-deps.md --allow-multi-iteration
```

Iteration 1: Launch Pad saves a brief; Supervisor's Worker emits `outputs_gap`; Execute Manager raises adjudication; Supervisor presents the 4 options via AskUserQuestion. You pick **Option C "Exit to Launch Pad"**. Supervisor marks the job failed with `inter_subtask_gap`. EVALUATE detects this via the anchor-by-filename check (`.supervisor/jobs/failed/{basename(brief)}` exists + `inter_subtask_gap` in one of three iteration-scoped locations: the failed brief's contents, `SUPERVISOR_RESULT.error`, or `SUPERVISOR_RESULT.summary`). Loop writes `.supervisor/requirements/...-iter2.md` with the gap context, loops back to PLAN (no merge prompt — no PR was created). Iteration 2 completes cleanly.

## Flow Diagram

```
┌───────────────────────────────────────────────────────────────────┐
│                  AUTONOMOUS LOOP (v13.0.0)                        │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Step 0: Read commands/launch-pad.md + commands/supervisor.md     │
│     │                                                             │
│     ▼                                                             │
│  INIT  ▶ write requirement, init .supervisor/autonomous/{sid}/    │
│     │                                                             │
│     ▼                                                             │
│  PLAN  ▶ Launch Pad inline (Phase 6 save AskUserQuestion)         │
│         ▶ Read LAUNCH_PAD_RESULT.saved_brief_path (v13.1.0+);     │
│           ls-diff fallback for pre-v13.1.0 plugins                │
│         ▶ grep verifies rubric preservation (if applicable)       │
│     │                                                             │
│     ▼                                                             │
│  EXECUTE ▶ Supervisor inline (orchestrator / execute-manager /    │
│            worker / code-reviewer / Phase 4.5 / rubric-grader)    │
│            ▶ adjudication AskUserQuestion if outputs_gap          │
│     │                                                             │
│     ▼                                                             │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ single-iteration mode? ─── yes ──▶ DONE                    │   │
│  │   no                                                       │   │
│  │   │                                                        │   │
│  │   ▼                                                        │   │
│  │ EVALUATE: read SUPERVISOR_RESULT                           │   │
│  │   • completed + rubric N<M → rubric gate AskUserQuestion   │   │
│  │       merge-and-continue (verified) ▶ loop to PLAN         │   │
│  │       stop-here ▶ DONE                                     │   │
│  │       force-continue ▶ loop to PLAN (risk recorded)        │   │
│  │   • failed + inter_subtask_gap (anchor-by-filename) ▶      │   │
│  │       loop to PLAN (no merge prompt)                       │   │
│  │   • anything else ▶ DONE / failed / aborted                │   │
│  │   • iteration ≥ max ▶ paused_max_iterations                │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                   │
│  DONE ▶ write .supervisor/autonomous/{sid}/summary.md + state.json│
│         ▶ echo AUTONOMOUS_RUN summary to main-thread output       │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## Risks and Limitations (v1)

- **Foreground-assisted, not fire-and-forget** — see the callout at the top. You must be at the terminal to answer in-session prompts.
- **Brief-save detection (v13.1.0+): primary path is `LAUNCH_PAD_RESULT.saved_brief_path` validated via `scripts/validate-launch-pad-result.py`; `ls`-diff is fallback-only.** When the result block is present and validates, the primary path consumes `saved_brief_path` directly — concurrent `/launch-pad` invocations are much less likely to confuse the autonomous loop because each Launch Pad invocation emits one result block and the loop reads only the block from its own inlined Launch Pad call. The `ls`-diff fallback retains the original v13.0.x single-session-only constraint and `status_reason: "concurrent_session_detected"` abort, and activates when the result block is absent, fails schema validation, or the saved path doesn't exist on disk (recorded as `policy_decisions[].decision = "launch_pad_result_malformed"` or `"launch_pad_result_fallback"`). For pre-v13.1.0 plugins, the safe operating rule remains: one autonomous / launch-pad invocation at a time per repo.
- **Multi-iteration requires user merge between iterations.** The rubric-gate AskUserQuestion makes this explicit; the loop verifies merge via `gh pr view` or local ancestry check. You can override with `force-continue-anyway`, but iteration N+1's branch then will not include iteration N's changes, likely producing conflicting PRs.
- **Rubric per-item PASS/FAIL is not available** — only the score `"N/M"` is in `SUPERVISOR_RESULT`. The refined requirement passes the full rubric back to Launch Pad and relies on its re-discovery (which sees the merged PR) to identify gaps.
- **Crash recovery is unsupported.** Re-running `/autonomous` on the same requirement after a crash may duplicate work — Launch Pad may re-create a similar brief, Supervisor may try to create a similar PR, merge conflicts likely. Manually clean up `.supervisor/jobs/in-progress/`, close any abandoned PRs, then restart. `/autonomous --continue` is deferred to a future plan that depends on Doc 4's state.json sidecar + resume reconciliation.
- **No QA integration in the loop.** The loop trusts Supervisor's Phase 4.5 self-heal + (v12.2's) Rubric Grader for in-PR quality. Auto-spawning QA Strategist / QA Executor after each PR is its own design surface; defer.
- **Cost: multi-iteration loops are genuinely expensive.** Each iteration runs full Launch Pad + full Supervisor (including Phase 4.5 + Rubric Grader). The only cap in v1 is `--max-iterations N` (default 3). Token/dollar budget caps are deferred.
- **`.gitignore` coverage.** The loop writes to `.supervisor/autonomous/{session_id}/`, `.supervisor/requirements/`, and `.supervisor/logs/{session_id}.jsonl` — all under `.supervisor/`. The `state-management` skill (consumed by Supervisor at session start) idempotently ensures `.supervisor/` is in `.gitignore`, so first-run users won't accidentally commit autonomous session artifacts. If you've moved the supervisor state directory or stripped that line from your `.gitignore` for some reason, re-add `.supervisor/` before running `/autonomous`.

## Troubleshooting

### Loop aborts with `status_reason: "rubric_dropped_from_brief"`
Launch Pad did not honor the inline-instruction to preserve the `## Outcomes Rubric`. The loop catches this and exits cleanly. **Cleanup before re-running:** the abort happens *after* Launch Pad's Phase 6 save, so the saved brief is still sitting in `.supervisor/jobs/pending/` (its filename starts with this run's `session_id`). Move it to `.supervisor/jobs/failed/` or delete it before re-running `/autonomous`, otherwise the next run's brief-save `ls`-diff will see the stale brief, count it as a "new" file, and either pick it up by accident (if the new run produces no brief of its own) or trip `status_reason: "concurrent_session_detected"` (if both old and new briefs appear). One-liner: `mv .supervisor/jobs/pending/<this-session-id>-*.md .supervisor/jobs/failed/` then re-run. **v1 fallback:** convert the rubric to inline acceptance criteria in the requirement body and re-run without rubric-driven re-iteration (single-iteration mode), or open a follow-up issue for a Launch Pad source change.

### Loop aborts with `status_reason: "concurrent_session_detected"`
The brief-save `ls`-diff found more than one new file in `pending/` after Phase 6. Likely cause: another `/launch-pad` or `/autonomous` session is mid-execution on the same repo. v1 fix: kill the other session, clean any stray pending briefs, restart.

### Iteration N reported `completed` but I don't see PR N's changes in iteration N+1
You picked `force-continue-anyway` on the rubric gate without merging PR N. Iteration N+1's Supervisor branched from `main` without PR N's code. v1 fix: merge PR N now and pick `merge-and-continue` on the next rubric gate (if one fires).

### `inter_subtask_gap` re-plan trigger doesn't fire even though I picked Option C
Two possibilities. (1) `.supervisor/jobs/failed/{basename(current_brief_path)}` doesn't exist — Supervisor didn't move the brief to `failed/` for some reason (e.g., the run aborted before adjudication resolution). Check `git status` and `ls .supervisor/jobs/in-progress/` to recover. (2) The `inter_subtask_gap` grep-stable string in FAILURE_ESCALATION.md changed and your version of the plugin hasn't been updated to match. v1 fix: inspect `.supervisor/state.md`, the failed brief, and SUPERVISOR_RESULT manually; manually re-run `/autonomous` on a refined requirement.

### Supervisor returned `checkpoint` and the loop aborted
v1 does not auto-resume from checkpoint (the state may be indeterminate). Run `/supervisor --continue task: <task_id>` manually to finish the in-flight task, then start a new `/autonomous` for the next requirement.

## Comparison to Claude Code's `/goal` (v13.1.0+)

Claude Code ships a built-in `/goal` command for autonomous task execution. It looks similar to `/autonomous` from the outside — both pursue a high-level objective across multiple iterations — but they target different problem shapes and should not be confused.

| Aspect | `/goal` (built-in) | `/autonomous` (this plugin) |
|---|---|---|
| **Loop type** | Open-ended observe-act-observe; Claude picks tools, runs them, reads results, repeats until done | Bounded chain of plugin workflows: Launch Pad → Supervisor (with optional re-plan via Outcomes Rubric / Option-C adjudication) |
| **Re-plan signals** | Implicit — the model decides when more work is needed | Explicit, two-signal contract: `rubric_score N<M` with user-merge verification, OR `failed + inter_subtask_gap` on this iteration's brief (`skills/autonomous-loop/SKILL.md` §"EVALUATE") |
| **Quality gates** | None inherent (relies on the model's judgment) | Inherits every plugin gate: Plan Reviewer (Phase 5.5), Supervisor Phase 4.5 self-heal, Rubric Grader, Code Reviewer, merge-safety gate |
| **State** | In-conversation; no persisted contract | `.supervisor/autonomous/{session_id}/state.json` + `.supervisor/requirements/` + per-session JSONL log |
| **Adjudication on ambiguity** | Model decides when to ask the user | Hard-coded 4-option `AskUserQuestion` on every outputs_gap (`FAILURE_ESCALATION.md`); the loop never auto-picks |
| **PR contract** | Whatever the model emits | Inherits Supervisor's `SUPERVISOR_RESULT` schema, mandatory `pr_url` on completion, branch-vs-main self-heal review |
| **Output** | Free-form chat | `AUTONOMOUS_RUN` schema in `RESULT_SCHEMAS.md` + audit-grade per-iteration history |

**When to use `/goal`:** open-ended exploratory or research-y work where the right approach isn't known up-front and the value is in the model figuring it out — e.g., "investigate the flaky test in `tests/auth/`", "audit our error handling and propose fixes". The looseness is a feature.

**When to use `/autonomous`:** you have a defined deliverable, you want the plugin's quality contract (Plan Reviewer + Phase 4.5 self-heal + Rubric Grader + Code Reviewer) on every iteration, and you want the re-plan to fire on **specific structured signals** rather than the model's judgment. The plugin's gates and schemas are the value.

**Can `/autonomous` wrap `/goal`?** No — it would re-introduce the subagent-spawn trap documented in `CLAUDE.md` "Common Pitfalls" §"`/supervisor` or `/launch-pad` aborted...". `/autonomous` runs Launch Pad and Supervisor **inline on the main thread** by design. Adding `/goal` as an outer wrapper would create an extra delegation layer that breaks both workflows.

**Can `/goal` invoke `/supervisor`?** Yes — `/goal` is a generic outer loop and can shell out to any tool the model decides to use, including `/supervisor`. But you'd lose the structured re-plan signal contract that `/autonomous` provides.

---

## Related Commands

- `/launch-pad` — the inner workflow `/autonomous` invokes during PLAN. Run standalone to produce a Supervisor-Ready Brief without invoking Supervisor.
- `/supervisor` — the inner workflow `/autonomous` invokes during EXECUTE. Run standalone to execute a brief without the outer loop.
- `/dreaming` — read-only post-hoc reflection on completed sessions, useful for inspecting `.supervisor/autonomous/{session_id}/summary.md` history.
- `/agent-help` — list of all plugin commands.

## See Also

- `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md` — full protocol, signal-extraction algorithm, refined-requirement templates
- `ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md` — adjudication 4-option contract (Option C is the loop's failed-iteration trigger)
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` — `SUPERVISOR_RESULT` schema (the loop reads `status`, `pr_url`, `error`, `summary`, `rubric_score`)
