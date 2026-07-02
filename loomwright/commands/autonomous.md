---
description: Continuous autonomous mode — chain Launch Pad → Supervisor and loop by default with stacked PRs; rubric / Option-C signals drive re-planning, gate firings can ping a webhook
---

> **Execute this workflow inline as the main thread.** Do not delegate to any `autonomous-*-runner` via the Agent tool — `/autonomous` runs the entire Launch Pad and Supervisor workflows inline, and both of those require Task descendants (`plan-reviewer`, `orchestrator`, `execute-manager`, `code-reviewer`, etc.). An extra delegation layer would hit the documented subagent-spawn trap and the inner workflows would silently abort. The `/autonomous` command is a thin orchestration shell that references Launch Pad and Supervisor's inline workflows; it does NOT introduce a new delegated agent.

> **Foreground-assisted automation, not fire-and-forget.** The loop will prompt you in-session at several points:
> - Launch Pad **Phase 6**: save / refine / discard the brief
> - Launch Pad **NO-GO** or **Plan Review FAIL × 3** (rare): override / revise / abort
> - Supervisor **adjudication 4-option** (if outputs_gap triggers it during EXECUTE): re-queue / remediate / exit-to-Launch-Pad / update-consumer
> - **Autonomous rubric gate** (multi-iteration mode, after rubric N<M): continue-to-next-iteration / stop-here / force-continue. In **stacked-branch mode (the v14 default)** the gate is non-blocking on the prior PR's merge status — iter N+1 branches from iter N's feature branch directly, so user merge is not required between iterations.
> - **No-rubric gate** (multi-iteration, when the brief had no `## Outcomes Rubric`): continue / stop. New in v14.0.0 — multi-iter without a rubric used to be a degenerate single-shot; the gate now lets you decide explicitly.
>
> You must be at the terminal to answer these unless you pass `--non-interactive-fallback` (required for CI / non-TTY environments — gates fail closed instead of prompting). Pass `--notify` to also POST a gate-event payload to the webhook configured via `LOOMWRIGHT_WEBHOOK_URL` (or the `.supervisor/config.json` → `.webhook_url` fallback; the legacy `.supervisor/notify-config.json` is still read as a fallback, and the new path wins when both exist) so an out-of-band notifier (Slack relay, ntfy/push, etc.) can ping you when a gate fires; if no URL is resolvable, `--notify` warns once at INIT rather than silently doing nothing (v14.2.2).
>
> The "autonomous" value is command chaining + automatic re-plan on the rubric / Option-C signals + (v14) stacked PRs by default, not removing human gates.

# Command: /autonomous

## Purpose

`/autonomous` chains Launch Pad → Supervisor for one requirement so you do not have to manually run `/launch-pad "..."` then `/supervisor job: <path>`. **In v14.0.0 the default flipped to multi-iteration mode** (cap 10, default 3), with stacked branches: iter N+1's feature branch is created from iter N's feature branch directly, not from `main`, so the loop produces a stack of PRs that can be reviewed and merged in order without the prior intermediate-merge wait. Anyone scripting against v13's single-PR semantics should pass `--single-iteration` to preserve that behavior.

INIT prints a one-line migration hint when the v14 default path is taken (i.e., neither `--single-iteration` nor the deprecated `--allow-multi-iteration` is supplied) so existing scripts notice the default change.

EVALUATE re-plans on the same two `SUPERVISOR_RESULT` signals as v13: `completed` with `rubric_score N/M, N<M` (Signal 1) and `failed` with `inter_subtask_gap` anchored by `.supervisor/jobs/failed/{basename(current_brief_path)}` (Signal 2). What changed in v14 is the branch base and the gate semantics for Signal 1 — see "EVALUATE PR-base verification" and "Signal 1 stacked rubric gate" in `skills/autonomous-loop/SKILL.md`.

**Post-PR until-mergeable drain — runs in BOTH single- and multi-iteration mode (parity with direct `/supervisor`).** Because `/autonomous` runs the **entire** inline Supervisor workflow during EXECUTE, Supervisor's **Phase 4.5 step 5.5 — the until-mergeable review-drain dispatch, DEFAULT-ON after PR creation** — runs as part of that inline workflow. The autonomous EXECUTE step does NOT stop the Supervisor enumeration at Rubric Grader: step 5.5 is included. Therefore **single-iteration `/autonomous` reaches the post-PR until-mergeable drain via Supervisor step 5.5, exactly like a direct `/supervisor` run** — even though single-iteration mode short-circuits EVALUATE (and thus skips the loop's own chained review-heal below). The chained review-and-heal in EVALUATE is an **additional, multi-iteration-only** gate that informs the stacking decision; it is diff-only (never `--until-mergeable`) and is **not** the post-PR drain, so skipping EVALUATE in single-iteration mode no longer means "no drain." Step 5.5's drain is best-effort / fire-and-forget and **never gates or blocks** the run (the dispatcher always exits 0; it never changes the `heal_decision` or blocks the PR). **R9 (unchanged):** because step 5.5's drain is detached, branch-dependent downstream work — a stacked iteration N+1 or a human merge — should wait until the detached drain reaches a terminal `READY` / `ESCALATED` state before proceeding (the R9 downstream-ordering invariant in `commands/supervisor.md` §"R9 — downstream ordering" and `skills/review-heal/SKILL.md`; cross-linked, not redefined). See EXECUTE step 2 in `skills/autonomous-loop/SKILL.md` and `agents/supervisor.md` Phase 4.5 step 5.5.

**Chained review-and-heal (after PR-base verification, before Signal evaluation):** when an iteration completes successfully and produced a PR (`pr_url` non-null), EVALUATE runs the standalone PR **review-and-heal** workflow as a **`Task` step with fresh isolated context** — NOT a nested `claude` process, and NOT a Task-spawn of the `review-pr-runner` agent (the Task body runs the `review-heal` loop body inline per `skills/review-heal/SKILL.md` entry sense (b) / AC9). The step runs the bounded review→fix→re-review loop on the PR (default 3 iterations, never `--force`, never auto-merge) and emits a `REVIEW_HEAL_RESULT` block, which the loop records into that iteration's `iterations[]` entry under a `review_heal` field. **PASS** → the loop continues to its normal Signal evaluation (rubric gate / Option-C / no-rubric / termination); **ESCALATED** (review-heal exhausted its bound or the reviewer returned NEEDS_HUMAN) → the loop surfaces it through the **existing EVALUATE `AskUserQuestion`** escalation surface (no new gate is introduced), failing closed under `--non-interactive-fallback`. The step is skipped when `pr_url` is null or the iteration failed. **`READY` (REVIEW_HEAL_RESULT schema v2):** EVALUATE **never emits `READY`** — it does not pass `--until-mergeable` (that opt-in drain mode is `/review-pr`-only, the only path that emits `READY`). EVALUATE's parser treats an unrecognized decision (including `READY`) as a **terminal, non-re-iterate** state and degrades safely — it does NOT loop back to PLAN on it, mirroring the `PASS` "continue to Signal evaluation / let the cap-check terminate" path rather than triggering a re-plan. The parser is also **forward-compatible with the additive v2 `REVIEW_HEAL_RESULT` drain fields** (`channels_scanned`, `findings_validated`, `findings_dismissed`, `checks_waited`, and the postmortem fields): EVALUATE keys only off `decision` and the v1 core fields, so any unrecognized/extra fields are simply ignored — they never cause EVALUATE to choke or loop. (Those fields only ever appear under `--until-mergeable`, which EVALUATE does not use; the until-mergeable readiness semantics are NOT restated here — see the `review-heal` skill.) See "EVALUATE review-heal step" in `skills/autonomous-loop/SKILL.md` and the `review-heal` skill itself for the loop contract.

## Usage

```bash
/autonomous "<requirement string>"                                       # v14 default — multi-iter, stacked branches, max 3 iterations
/autonomous "<...>" --max-iterations 5                                   # multi-iter, cap 5 (hard cap: 10)
/autonomous "<...>" --single-iteration                                   # v13-compat one-PR behavior
/autonomous "<...>" --no-stacked-branches                                # multi-iter, but each iteration's branch from main (v13-style merge cadence)
/autonomous "<...>" --notify                                             # POST gate-event payloads to LOOMWRIGHT_WEBHOOK_URL
/autonomous "<...>" --non-interactive-fallback                           # required for CI / non-TTY runs (gates fail closed, no AskUserQuestion)
/autonomous --requirement <path>                                         # use existing requirement file
```

> **CI / non-interactive note:** if `[ ! -t 0 ]` OR `$CI` is set AND multi-iter mode is active AND `--non-interactive-fallback` is NOT passed, INIT aborts immediately with `status_reason: "non_interactive_without_fallback"` and a verbose error naming the trigger and listing two ready-to-paste recovery commands. This is the only escape from CI hangs in v14 (gate-timeout is deferred — see "Not shipped in v14").

> **Cost-profile note:** `--cheap` is **not forwarded** in v14 either. If you need the Sonnet cost profile, run `/launch-pad` and `/supervisor --cheap` manually (see Parameters → `--cheap interaction note` for details). The autonomous loop is genuinely expensive — each iteration is a full Launch Pad + full Supervisor run.

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `"<requirement>"` | One of | Inline requirement string. Loop writes it to `.supervisor/requirements/{session_id}-{slug}.md` (where `session_id` is `auto-{YYYY-MM-DD}-{HHMMSS}` — already date-prefixed, so the path is sortable without a redundant date) with an optional `## Outcomes Rubric` placeholder for the user to fill in. |
| `--requirement <path>` | One of | Use an existing requirement file. If the file already contains an `## Outcomes Rubric` section, it is preserved and used by multi-iteration mode. If it does NOT contain one and multi-iteration mode is active, the loop auto-authors one (see the inline-instruction section below). **Note:** in that auto-author case the loop appends the human-approved rubric back into this file in place (the freeze step), so a `--requirement` file may be modified on disk; pass a copy if you need the original untouched. |
| `--single-iteration` | No | Disable multi-iter mode; run Launch Pad + Supervisor once and exit (v13-compat behavior). Equivalent to v13's "no `--allow-multi-iteration` passed" default. |
| `--no-stacked-branches` | No | Iter N+1 branches from `main` instead of `iterations[N].branch`. Disables stacked-PR mode; each iteration produces an independent PR off `main`. Pair with the Signal-1 rubric gate's `merge-and-continue` option for the v13 cadence. |
| `--notify` | No | Enable webhook gate-event notifications. Requires the `LOOMWRIGHT_WEBHOOK_URL` env var. Fire-and-forget POST via `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh --event-type gate ...`; the AskUserQuestion fires immediately after backgrounding the POST (no wait on delivery). The webhook URL resolves from `LOOMWRIGHT_WEBHOOK_URL` **or** the `.supervisor/config.json` → `.webhook_url` fallback; if neither is set, `--notify` **fails loud** with one warning at INIT step 0 (it does NOT silently no-op) — desktop banners are unaffected (v14.2.2). |
| `--non-interactive-fallback` | No | Permit multi-iter execution in non-interactive (CI / stdin-not-tty) environments. Gates fail closed (abort with a clear status_reason) instead of firing AskUserQuestion. Required when running unattended; the INIT-time non-interactive check refuses to start multi-iter without it. **Auto-forwards `--non-interactive` to the inlined `/supervisor`** so Supervisor's Phase 4 `gh` retry path and adjudication gates fail closed consistently — a single `--non-interactive-fallback` is sufficient for CI; no need to also pass `--non-interactive` to `/autonomous` (see `skills/autonomous-loop/SKILL.md` EXECUTE step 1, "Auto-forwarded flags"). |
| `--max-iterations N` | No | Maximum iterations in multi-iter mode. Integer `1 <= N <= 10`; default `N=3`. **Hard cap: 10** (rationale: stacked-PR review burden becomes unmanageable beyond ~10 PRs in a stack; review velocity is the rate-limiting step, not the loop). `N=0` or `N>10` rejected at INIT with `status: aborted, status_reason: "invalid_max_iterations"`. **Edge case `N=1`:** valid but degenerate — runs one iteration with full EVALUATE / rubric-gate reporting; if Signal 1 or Signal 2 would fire the cap-check exits with `status: paused_max_iterations, status_reason: "max_iterations_reached"`. Equivalent to `--single-iteration` but keeps the multi-iter summary fields populated. |
| `--allow-multi-iteration` | No | **DEPRECATED in v14.0.0** — multi-iter is now the default. Flag is silently accepted as a no-op when alone (a one-line deprecation warning is logged). Combining with `--single-iteration` aborts at INIT with `status_reason: "conflicting_mode_flags"` and a clear error directing the user to pick one mode. |

> **`--cheap` interaction note:** Passing `--cheap` to `/autonomous` in v14 has **no effect** — the loop does not forward unknown flags to the inlined `/supervisor` call, and `/supervisor`'s `--cheap` cost-profile (Sonnet overrides for orchestrator / execute-manager / worker / code-reviewer / Phase 4.5 fix tasks) is not wired through here. If you want the cost-optimized profile for a single requirement, run the workflows manually instead: `/launch-pad "..."` then `/supervisor job: <brief-path> --cheap`. A future plan can add `--cheap` passthrough once the cost-profile semantics are clarified for multi-iteration cycles.

> **`--skip-preflight-sync` interaction note:** Like `--cheap`, `--skip-preflight-sync` is **not forwarded** to the inlined `/supervisor` call (the loop forwards only `--non-interactive`; see EXECUTE step 1 "Auto-forwarded flags"). The Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate therefore runs in **every** autonomous iteration — normally invisible because the CLEAR path is silent; under `--non-interactive-fallback` an OVERLAP/SUPERSEDED classification fails the iteration closed with `status_reason: "preflight_overlap_detected"`. To deliberately skip the gate for a one-off, run `/supervisor --skip-preflight-sync` manually.

### Not shipped in v14.0.0

- **`--gate-timeout-minutes`** — explicitly deferred. CI hangs are prevented only by the INIT-time non-interactive detection (`--non-interactive-fallback`); once a gate fires in an unattended terminal, the only escape is killing the session externally (corrupts state). A wrapper-process timeout is the right shape for this flag and is its own design surface (deferred to v15). Users running unattended MUST pass `--non-interactive-fallback`.
- **`--status` / `--continue` / `--abort` / `--background` / `--auto-merge`** — still deferred. Resume contract depends on Doc 4's state.json sidecar work; auto-merge needs trusted-PR enforcement that is its own design surface.

> **Quoting paths with spaces:** if the `--requirement <path>` value contains spaces, enclose the whole path in double quotes. Example: `/autonomous --requirement ".supervisor/requirements/My Feature.md"`. Without the quotes the path is split on the first space and the loop will error or read the wrong file.

## What This Does

### Step 0 — Load Canonical Workflow Bodies + Protocol Skill (always)

Before anything else, the main thread reads the canonical inline workflows and the autonomous-loop protocol skill so it executes the up-to-date versions rather than remembered shapes. **All three reads use `${CLAUDE_PLUGIN_ROOT}`**, which is the canonical Claude Code variable that resolves to the plugin install dir at runtime (works on both maintainer dev checkouts and marketplace installs). Never use `loomwright/...` here — that path only resolves for the plugin maintainer:

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md
Read ${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md
```

This guards against prompt drift on three fronts. If Launch Pad, Supervisor, or the autonomous-loop protocol evolves between releases, `/autonomous` picks up the changes automatically because it re-reads them every run.

### Multi-Iteration Mode (v14.0.0 default)

```
INIT → PLAN → EXECUTE → EVALUATE → (loop back to PLAN with refined requirement, OR DONE)
```

INIT emits the v14 migration hint when neither `--single-iteration` nor `--allow-multi-iteration` is passed:

```
⚠️ v14.0.0 — /autonomous default is now multi-iteration (max_iterations: 3, cap 10). Pass --single-iteration for v13 one-PR behavior.
```

After Supervisor returns, EVALUATE first runs PR-base verification, then the chained review-and-heal step (Task, fresh isolated context — see below), then reads `SUPERVISOR_RESULT` and applies one of these branches:

| `SUPERVISOR_RESULT.status` | Other condition | Loop action |
|---|---|---|
| `completed` / `completed_with_escalation` | `pr_url` non-null (iteration produced a PR) | Run **chained review-and-heal** as a `Task` step (fresh isolated context, NOT a nested `claude` process) before Signal evaluation. Records `REVIEW_HEAL_RESULT` into the iteration's `review_heal` field. PASS → continue to Signal evaluation; ESCALATED → surface via the **existing** EVALUATE `AskUserQuestion`. `READY` (v2, `--until-mergeable`-only) is **never emitted by EVALUATE** (it does not pass `--until-mergeable`); the parser treats an unrecognized/`READY` decision as **terminal, non-re-iterate** (degrades safely — no re-plan). |
| `completed` | `rubric_score` is `N/M` with N<M | Fire **Signal 1 rubric gate AskUserQuestion**. In **stacked-branch mode (default)** the gate is `continue-to-next-iteration / stop-here / force-continue` — no merge required because iter N+1 branches from iter N's branch directly. In `--no-stacked-branches` mode the gate falls back to v13 semantics (`merge-and-continue / stop-here / force-continue` with `gh pr view` verification). |
| `completed` | brief had no `## Outcomes Rubric` AND multi-iter is active | Fire **no-rubric gate** (new in v14): `continue / stop`. v13 silently terminated this case; v14 makes the decision explicit because multi-iter without a rubric is the common shape for refactor / cleanup goals. |
| `failed` | `inter_subtask_gap` detected on this iteration's brief | Re-plan immediately (no merge needed; job was abandoned via adjudication Option C). Same as v13. |
| `failed` | `pr_url` is null (Supervisor failed before creating PR — merge conflict, env error, etc.) | Skip PR-base verification entirely (AC-15) and fall through to default termination with `status_reason: "supervisor_failed_other"`. |
| anything else | — | Terminate the loop. Specifically: `completed_with_escalation` → done with escalations_seen; `failed (other)` → failed; `checkpoint` → aborted (no auto-resume in v1). |

### Single-Iteration Mode (`--single-iteration`)

```
INIT → PLAN → EXECUTE → DONE
```

v13-compat behavior. The loop runs Launch Pad inline, then Supervisor inline on the saved brief, then emits an AUTONOMOUS_RUN summary and exits. EVALUATE is short-circuited: the very first step of EVALUATE in single-iter mode is `exit with status: done`. Use when scripting against the v13 one-PR contract.

### Stacked-branch behavior (v14 default)

When iter N+1 is reached:

- v13-style (`--no-stacked-branches`): iter N+1's feature branch is created from `main` via `git checkout main && git checkout -b feature/<name>-iter2`. Requires merging iter N's PR first or `--no-stacked-branches`'s explicit out-of-stack semantics (each PR is independent, may conflict).
- v14 default (stacked): iter N+1's feature branch is created from `iterations[N].branch` via `git checkout <iter N branch> && git checkout -b feature/<name>-iter{N+1}`. The new PR is opened with `--base <iter N branch>` so review proceeds incrementally. The loop verifies the PR's base with `gh pr view <pr_url> --json baseRefName` after Supervisor's Phase 4 (with the AC-14 retry policy on `gh` failure).

Out-of-order merge of a stacked PR can corrupt `main` — the bottom of the stack must merge first. This hazard is documented; the AUTONOMOUS_RUN summary's `iterations[]` array is ordered by `n` (iter 1, iter 2, ...) and that order IS the intended merge order — reviewers must follow it.

The detailed protocol — including the `ls`-diff brief-save detection, the anchor-by-filename Option-C scoping, the merge-verification sequence, and the refined-requirement templates — lives in `loomwright/skills/autonomous-loop/SKILL.md`.

### What runs inline (Launch Pad's existing AskUserQuestion gates bubble up)

Phase 2.5 NO-GO override, Phase 5.5 Plan Reviewer FAIL × 3, Phase 6 save/refine/discard — all of Launch Pad's existing prompts fire in-session via Claude Code's native interaction model. The user answers, the workflow continues. No `/autonomous --continue` is needed for the normal interactive path.

### What runs inline (Supervisor's existing AskUserQuestion gates bubble up)

Adjudication 4-option escalation (when a Worker's `outputs_gap` triggers it) fires in-session. The autonomous loop never auto-picks. If the user picks Option C "Exit to Launch Pad", Supervisor marks the job `failed` with `inter_subtask_gap` recorded — the loop catches that signal in EVALUATE and re-plans.

### Inline instruction to Launch Pad (rubric preservation + auto-authoring)

When `/autonomous` invokes Launch Pad inline, it adds one explicit directive to the inlined workflow body:

> *"If the requirement file at `<requirement_path>` has an `## Outcomes Rubric` section, copy it verbatim into the saved brief during Phase 5 (PACKAGE — Brief Assembly). Do not paraphrase, do not drop items."*

After Phase 6 saves, the loop verifies this with the canonical rubric-presence test (a line-anchored `^## Outcomes Rubric` header **plus** ≥1 bullet — the `has_rubric` helper in `skills/autonomous-loop/SKILL.md` PLAN §"Rubric-presence test", not a bare `grep -F` substring). If a real rubric is missing from the saved brief, the iteration aborts cleanly with `status_reason: "rubric_dropped_from_brief"` (a graceful fallback that prevents multi-iteration from silently degrading to single-iteration).

Additionally, when **multi-iteration mode is active AND the requirement has no `## Outcomes Rubric`**, the loop adds a second, conditional directive instructing Launch Pad to **auto-author** one (3–7 diff-checkable bullets derived from the Acceptance Criteria + Phase 3 analysis), have the human approve or edit it at Phase 6, then persist it back into the requirement body so it is frozen for later iterations. The authoring rules are NOT restated here — they live in `skills/supervisor-readiness/SKILL.md` §"Auto-Authoring (multi-iteration)" (the single source of truth); the loop mechanics that *invoke* and *persist* the authored rubric are in `skills/autonomous-loop/SKILL.md` PLAN steps 2 & 7. Degenerate fallback: if fewer than 3 diff-checkable bullets are derivable, no rubric is authored and the loop uses its existing no-rubric gate. **Single-iteration mode and the already-has-a-rubric case are unchanged — preserve-only, never auto-authored.**

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
│              AUTONOMOUS LOOP (v14.0.0 — multi-iter default)       │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Step 0: Read commands/launch-pad.md + commands/supervisor.md     │
│         + skills/autonomous-loop/SKILL.md                         │
│     │                                                             │
│     ▼                                                             │
│  INIT step 0: non-interactive detection (CI / non-TTY)            │
│         ▶ multi-iter without --non-interactive-fallback ▶ abort   │
│         ▶ validate --max-iterations 1..10                         │
│         ▶ handle deprecated --allow-multi-iteration               │
│         ▶ emit v14 migration hint if default path                 │
│     │                                                             │
│     ▼                                                             │
│  INIT  ▶ write requirement, init .supervisor/autonomous/{sid}/    │
│     │                                                             │
│     ▼                                                             │
│  PLAN  ▶ Launch Pad inline (Phase 6 save AskUserQuestion)         │
│         ▶ optional --notify webhook gate POST                     │
│     │                                                             │
│     ▼                                                             │
│  EXECUTE ▶ stacked branch: checkout iter-N branch then -b iterN+1 │
│         ▶ Supervisor inline with --base-branch <iter N branch>    │
│         ▶ Phase 4 gh pr view --json baseRefName self-verify       │
│         ▶ optional --notify on adjudication gate                  │
│     │                                                             │
│     ▼                                                             │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │ --single-iteration? ─── yes ──▶ DONE                       │   │
│  │   no                                                       │   │
│  │   │                                                        │   │
│  │   ▼                                                        │   │
│  │ EVALUATE: PR-base verification (stacked mode, pr_url != ∅) │   │
│  │   then read SUPERVISOR_RESULT                              │   │
│  │   • completed + rubric N<M → stacked rubric gate           │   │
│  │       continue ▶ loop to PLAN (iter N's branch as base)    │   │
│  │       stop-here ▶ DONE                                     │   │
│  │       force-continue ▶ loop to PLAN (risk recorded)        │   │
│  │   • completed + no rubric → no-rubric gate                 │   │
│  │       continue ▶ loop to PLAN                              │   │
│  │       stop ▶ DONE                                          │   │
│  │   • failed + inter_subtask_gap ▶ loop to PLAN              │   │
│  │   • failed + pr_url null → skip base-verify, fail-other    │   │
│  │   • anything else ▶ DONE / failed / aborted                │   │
│  │   • iteration ≥ max ▶ paused_max_iterations                │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                   │
│  DONE ▶ write .supervisor/autonomous/{sid}/summary.md + state.json│
│         ▶ echo AUTONOMOUS_RUN summary (iterations[] is merge order)│
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## Risks and Limitations (v1)

- **Foreground-assisted, not fire-and-forget** — see the callout at the top. You must be at the terminal to answer in-session prompts.
- **Brief-save detection (v14.2.0+): primary path is `LAUNCH_PAD_RESULT.saved_brief_path` validated via `scripts/validate-launch-pad-result.py`; `ls`-diff is fallback-only.** When the result block is present and validates, the primary path consumes `saved_brief_path` directly — a concurrent `/launch-pad` invocation is much less likely to confuse the loop because each Launch Pad invocation emits exactly one result block and the loop reads only the block from its own inlined call. The `ls`-diff fallback retains the original single-session-only constraint and the `status_reason: "concurrent_session_detected"` abort, and activates only when the result block is absent, fails schema validation, or the saved path doesn't exist on disk (recorded as `policy_decisions[].decision = "launch_pad_result_malformed"` or `"launch_pad_result_fallback"`). For pre-v14.2.0 plugins, the safe rule remains: one autonomous / launch-pad invocation at a time per repo.
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

## Related Commands

- `/launch-pad` — the inner workflow `/autonomous` invokes during PLAN. Run standalone to produce a Supervisor-Ready Brief without invoking Supervisor.
- `/supervisor` — the inner workflow `/autonomous` invokes during EXECUTE. Run standalone to execute a brief without the outer loop.
- `/dreaming` — read-only post-hoc reflection on completed sessions, useful for inspecting `.supervisor/autonomous/{session_id}/summary.md` history.
- `/agent-help` — list of all plugin commands.

## See Also

- `loomwright/skills/autonomous-loop/SKILL.md` — full protocol, signal-extraction algorithm, refined-requirement templates
- `loomwright/docs/FAILURE_ESCALATION.md` — adjudication 4-option contract (Option C is the loop's failed-iteration trigger)
- `loomwright/docs/RESULT_SCHEMAS.md` — `SUPERVISOR_RESULT` schema (the loop reads `status`, `pr_url`, `error`, `summary`, `rubric_score`)
