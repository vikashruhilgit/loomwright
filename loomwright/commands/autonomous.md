---
description: Continuous autonomous mode — chain Launch Pad → Supervisor and loop by default with stacked PRs; rubric / Option-C signals drive re-planning, gate firings can ping a webhook
---

> **Execute this workflow inline as the main thread.** Do not delegate to any `autonomous-*-runner` via the Agent tool — `/autonomous` runs the entire Launch Pad and Supervisor workflows inline, and both of those require Task descendants (`plan-reviewer`, `orchestrator`, `execute-manager`, `code-reviewer`, etc.). An extra delegation layer would run them as a subagent: it has no ask tool, so every question gate takes its can't-ask branch, and each Task descendant sits one nesting layer deeper (`docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting"). `/autonomous` is a thin orchestration shell over Launch Pad's and Supervisor's inline workflows; it introduces no delegated agent.

> **Foreground-assisted automation, not fire-and-forget.** The loop prompts you in-session at:
> - Launch Pad **Phase 6**: save / refine / discard the brief
> - Launch Pad **NO-GO** or **Plan Review FAIL × 3** (rare): override / revise / abort
> - Supervisor **adjudication 4-option** (if outputs_gap triggers it during EXECUTE): re-queue / remediate / exit-to-Launch-Pad / update-consumer
> - **Autonomous rubric gate** (multi-iteration, after rubric N<M): continue-to-next-iteration / stop-here / force-continue — in stacked-branch mode (the default) no merge is required between iterations
> - **No-rubric gate** (multi-iteration, when the brief had no `## Outcomes Rubric`): continue / stop
>
> You must be at the terminal to answer these unless you pass `--non-interactive-fallback` (required for CI / non-TTY environments — gates fail closed instead of prompting). `--notify` also POSTs a gate-event payload to the webhook from `LOOMWRIGHT_WEBHOOK_URL` or the user-scope egress entry for this repo (a repo-relative `.webhook_url` is an informational request, never a grant); if no URL is resolvable, `--notify` warns once at INIT rather than silently doing nothing.

# Command: /autonomous

## Purpose

`/autonomous` chains Launch Pad → Supervisor for one requirement so you do not run `/launch-pad "..."` then `/supervisor job: <path>` by hand. The default is multi-iteration (cap 10, default 3) with stacked branches: iter N+1's feature branch is created from iter N's, so the loop produces a stack of PRs merged in order. `--single-iteration` runs one Launch Pad → Supervisor pass (what `/automate` passes for every item). EVALUATE re-plans on two `SUPERVISOR_RESULT` signals — `completed` with `rubric_score N/M, N<M` (Signal 1) and `failed` with `inter_subtask_gap` anchored by `.supervisor/jobs/failed/{basename(current_brief_path)}` (Signal 2).

**Post-PR until-mergeable drain — runs in BOTH single- and multi-iteration mode:** EXECUTE runs the entire inline Supervisor workflow, including its default-on Phase 4.5 step 5.5 drain dispatch, so a single-iteration run reaches the drain exactly like a direct `/supervisor` run. EVALUATE's chained review-and-heal is an additional, multi-iteration-only, diff-only gate — never the drain (`skills/autonomous-loop/SKILL.md` EXECUTE step 2).

## Usage

```bash
/autonomous "<requirement string>"                  # default — multi-iter, stacked branches, max 3 iterations
/autonomous "<...>" --max-iterations 5              # multi-iter, cap 5 (hard cap: 10)
/autonomous "<...>" --single-iteration              # one Launch Pad → Supervisor pass
/autonomous "<...>" --no-stacked-branches           # multi-iter, each iteration's branch from main
/autonomous "<...>" --notify                        # POST gate-event payloads to the resolved webhook
/autonomous "<...>" --non-interactive-fallback      # required for CI / non-TTY runs (gates fail closed)
/autonomous "<...>" --cheap                         # forward the Sonnet cost profile to every inlined /supervisor run
/autonomous "<...>" --max-tokens N                  # opt-in spend ceiling — aborts rather than overspend
/autonomous --requirement <path>                    # use an existing requirement file
```

> **CI / non-interactive note:** if `[ ! -t 0 ]` OR `$CI` is set AND multi-iter mode is active AND `--non-interactive-fallback` is NOT passed, INIT aborts immediately with `status_reason: "non_interactive_without_fallback"` and an error naming the trigger and two ready-to-paste recovery commands. A gate that fires in an unattended terminal can only be escaped by killing the session, so unattended runs MUST pass `--non-interactive-fallback`.

> **`--cheap` interaction note (and the complete `/supervisor` forward set):** `--cheap` **is forwarded** to the inlined `/supervisor` call. The loop forwards **exactly four** flags to that invocation, each under its own condition (mirrors `skills/autonomous-loop/SKILL.md` EXECUTE step 1 §"Auto-forwarded flags" — the authority; keep the two in sync): `--base-branch "$expected_base"` (only on a stacked multi-iter run when `iteration > 1` — `--no-stacked-branches` NOT active), `--non-interactive` (only when `--non-interactive-fallback` was passed at INIT), `--cheap` (unconditional-when-present, every iteration — single- and multi-iteration, stacked and non-stacked alike), and `--max-tokens N` (unconditional-when-present — passthrough only, `/supervisor`'s own Phase 3 poll loop re-checks it per-iteration against its OWN ledger sum). **No other flag is forwarded to `/supervisor`.** The loop's one other forward is to Launch Pad, not `/supervisor`: `--non-interactive`, only when `--non-interactive-fallback` was passed at INIT (`skills/autonomous-loop/SKILL.md` PLAN step 1 §"Launch Pad forward"); an interactive run passes Launch Pad the requirement path alone. `--base-branch` and `--non-interactive` are `/supervisor` flags the loop derives or forwards internally — they are **not** `/autonomous` flags. `/automate` passes `--cheap`/`--max-tokens` through to its inner `/autonomous` call, completing the `/automate → /autonomous → /supervisor` chain. Semantics: `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" and §"Token ceiling".

> **`--skip-preflight-sync` interaction note:** `--skip-preflight-sync` is **not forwarded** to the inlined `/supervisor` call, so Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate runs in **every** iteration; under `--non-interactive-fallback` an OVERLAP/SUPERSEDED classification fails the iteration closed with `status_reason: "preflight_overlap_detected"`. To skip the gate for a one-off, run `/supervisor --skip-preflight-sync` by hand.

> **Quoting paths with spaces:** if the `--requirement <path>` value contains spaces, enclose the whole path in double quotes — `/autonomous --requirement ".supervisor/requirements/My Feature.md"`. Unquoted, the path is split on the first space and the loop errors or reads the wrong file.

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `"<requirement>"` | One of | Inline requirement string. Loop writes it to `.supervisor/requirements/{session_id}-{slug}.md` (`session_id` is `auto-{YYYY-MM-DD}-{HHMMSS}`) with a non-header `## Outcomes Rubric` placeholder hint. |
| `--requirement <path>` | One of | Use an existing requirement file. An existing `## Outcomes Rubric` is preserved. With none, in multi-iteration mode, the loop auto-authors one; **in that auto-author case the loop appends the human-approved rubric back into this file in place** (the freeze step), so pass a copy if you need the original untouched. |
| `--single-iteration` | No | Disable multi-iter mode; run Launch Pad + Supervisor once and exit. Default: off. |
| `--no-stacked-branches` | No | Iter N+1 branches from `main` instead of `iterations[N].branch`; each iteration produces an independent PR off `main` (pair with Signal 1's `merge-and-continue`). Only meaningful in multi-iteration mode. Default: off (stacked). |
| `--notify` | No | Enable webhook gate-event notifications via `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh --event-type gate ...` (fire-and-forget; the question fires immediately after). The URL resolves from `LOOMWRIGHT_WEBHOOK_URL` or the user-scope egress entry for this repo's slug (a repo-relative `.webhook_url` is informational only); if neither resolves, `--notify` **fails loud** with one warning at INIT step 0 (it does NOT silently no-op) — desktop banners are unaffected. Default: off. |
| `--non-interactive-fallback` | No | Permit multi-iter execution in non-interactive (CI / stdin-not-tty) environments. Gates fail closed (abort with a clear status_reason) instead of firing AskUserQuestion. Required when running unattended; the INIT-time non-interactive check refuses to start multi-iter without it. **Auto-forwards `--non-interactive` to the inlined `/supervisor`** so Supervisor's Phase 4 `gh` retry path and adjudication gates fail closed consistently, **and separately to the inlined Launch Pad** (PLAN step 1 §"Launch Pad forward") so its clarification / NO-GO / Phase 6 / FAIL × 3 gates take their named can't-ask branches — a single `--non-interactive-fallback` is sufficient for CI; no need to also pass `--non-interactive` to `/autonomous` (see `skills/autonomous-loop/SKILL.md` EXECUTE step 1, "Auto-forwarded flags"). Default: off (interactive gates). |
| `--max-iterations N` | No | Maximum iterations in multi-iter mode, integer `1 <= N <= 10`, default `3`. `N=0` or `N>10` rejected at INIT with `status: aborted, status_reason: "invalid_max_iterations"`. **Edge case `N=1`:** valid but degenerate — one iteration with full EVALUATE / rubric-gate reporting; if Signal 1 or Signal 2 would fire, the cap-check exits with `status: paused_max_iterations, status_reason: "max_iterations_reached"`. |
| `--allow-multi-iteration` | No | **Deprecated** — multi-iter is the default. Accepted as a no-op when alone (a one-line deprecation warning is logged). Combining with `--single-iteration` aborts at INIT with `status_reason: "conflicting_mode_flags"`. |
| `--cheap` | No | **Forward the Sonnet cost profile.** Parsed at INIT and appended to **every** inlined `/supervisor job:` invocation — unconditionally-when-present, in every iteration, NOT gated on `--non-interactive-fallback`. Default: off (every role keeps `inherit`). |
| `--max-tokens N` | No | **Opt-in token-spend ceiling.** Persisted into `state.json` and forwarded to every inlined `/supervisor job:`. Before each further iteration EVALUATE sums the run's own session ledger via `scripts/read-token-ledger.sh`; a breach OR a `LEDGER_UNREADABLE=1` answer ⇒ `status: aborted`, `status_reason: "token_ceiling_reached"`. INIT also acquires `.supervisor/run.lock` (`skills/autonomous-loop/SKILL.md` INIT step 0); a `run_lock_reentrant owner=<outer> …` line (exit 0) is NOT an abort — an enclosing `/automate` in the same session holds the lock; a `run_lock_degraded` line (exit 0) is NOT an abort either. **Honest limit:** the ledger counts only what a SubagentStop hook saw — never the main thread's own tokens, never CI-side spend. |

## What This Does

### Step 0 — Load Canonical Workflow Bodies + Protocol Skill (always)

Before anything else, the main thread reads the canonical inline workflows and the autonomous-loop protocol so it executes the current versions, not remembered shapes. **All reads use `${CLAUDE_PLUGIN_ROOT}`** — never `loomwright/...`, which resolves only for the plugin maintainer:

```
Read ${CLAUDE_PLUGIN_ROOT}/commands/launch-pad.md
Read ${CLAUDE_PLUGIN_ROOT}/commands/supervisor.md
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/SKILL.md
# ONLY when the arguments do NOT include --single-iteration:
Read ${CLAUDE_PLUGIN_ROOT}/skills/autonomous-loop/multi-iteration.md
```

A `--single-iteration` run never reads `multi-iteration.md`.

### Multi-Iteration Mode (default)

```
INIT → PLAN → EXECUTE → EVALUATE → (loop back to PLAN with refined requirement, OR DONE)
```

INIT emits the migration hint when neither `--single-iteration` nor `--allow-multi-iteration` is passed. EVALUATE runs PR-base verification, then the chained review-and-heal step, then applies the signal / gate / termination branches — all in `skills/autonomous-loop/multi-iteration.md`.

### Single-Iteration Mode (`--single-iteration`)

```
INIT → PLAN → EXECUTE → DONE
```

The loop runs Launch Pad inline, then Supervisor inline on the saved brief, then emits an AUTONOMOUS_RUN summary and exits. EVALUATE is short-circuited: its very first step in single-iter mode is `exit with status: done`.

### Stacked-branch behavior (default)

Multi-iteration only — `skills/autonomous-loop/multi-iteration.md` §"Stacked branches".

### What runs inline (Launch Pad's existing AskUserQuestion gates bubble up)

Phase 2.5 NO-GO override, Phase 5.5 Plan Reviewer FAIL × 3, Phase 6 save/refine/discard fire in-session. Under `--non-interactive-fallback` the loop passes Launch Pad `--non-interactive`, so none of them asks — each takes its named branch from Launch Pad's Can't-ask rule.

### What runs inline (Supervisor's existing AskUserQuestion gates bubble up)

Adjudication 4-option escalation (when a Worker's `outputs_gap` triggers it) fires in-session; the loop never auto-picks. If the user picks Option C "Exit to Launch Pad", Supervisor marks the job `failed` with `inter_subtask_gap` and EVALUATE re-plans.

### Inline instruction to Launch Pad (rubric preservation + auto-authoring)

PLAN step 2 adds a preserve-verbatim directive for an existing `## Outcomes Rubric`; after Phase 6 the loop checks it with `has_rubric` (`skills/autonomous-loop/SKILL.md` PLAN §"Rubric-presence test"). If a real rubric is missing from the saved brief, the iteration aborts cleanly with `status_reason: "rubric_dropped_from_brief"`. In multi-iteration mode with no rubric at intake, a second directive asks Launch Pad to auto-author one, approved at Phase 6 and frozen into the requirement body (`multi-iteration.md` §"PLAN — multi-iteration additions"; authoring rules: `skills/supervisor-readiness/SKILL.md` §"Auto-Authoring (multi-iteration)"). **Single-iteration mode and the already-has-a-rubric case are unchanged — preserve-only, never auto-authored.**

## Flow Diagram

```
Step 0: Read commands/launch-pad.md + commands/supervisor.md + skills/autonomous-loop/SKILL.md
        (+ multi-iteration.md unless --single-iteration)
INIT step 0 ▶ multi-iter without --non-interactive-fallback in CI / non-TTY ▶ abort
            ▶ validate --max-iterations 1..10, deprecated --allow-multi-iteration, migration hint
INIT    ▶ write requirement, init .supervisor/autonomous/{sid}/, acquire run lock
PLAN    ▶ Launch Pad inline (Phase 6 save AskUserQuestion)
        ▶ + --non-interactive under --non-interactive-fallback
EXECUTE ▶ Supervisor inline (+ --base-branch <iter N branch> when stacked, iteration > 1)
--single-iteration? ── yes ──▶ DONE
EVALUATE ▶ PR-base verification ▶ chained review-and-heal ▶ token ceiling
         ▶ rubric gate / Option-C re-plan / no-rubric gate ▶ loop to PLAN, or DONE / failed / aborted
         ▶ iteration ≥ max ▶ paused_max_iterations
DONE    ▶ write .supervisor/autonomous/{sid}/summary.md + state.json; echo AUTONOMOUS_RUN (iterations[] is merge order)
```

`.supervisor/` must stay ignored (a bare line, or `/setup memory`'s managed block; the `state-management` skill ensures it at session start); if you stripped that rule, restore it before running `/autonomous`.

Examples, limitations, troubleshooting and related commands: `docs/rationale/launch-pad-autonomous.md` §"/autonomous — usage notes".
