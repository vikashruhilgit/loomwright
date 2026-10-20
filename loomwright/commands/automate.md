---
description: Generic automation engine — turn any source (prompt / folder / backlog-doc) into a Queue and drive each item through /autonomous + an owned /review-pr drain to a reviewed PR (opt-in trusted auto-merge)
---

> **Execute this workflow inline as the main thread.** The `/automate` coordinator is **inline-only** — there is **NO `-runner` agent** for it (agents stay 14). Do not delegate it via the Agent tool: a subagent has no ask tool, so every question gate takes its can't-ask branch, and each Task descendant sits one nesting layer deeper (`docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting"). By default each item's phases — Launch Pad, Supervisor, the owned drain — run as their own fresh headless sessions; `--inline-phases` runs `/autonomous` and `/review-pr` inline here instead. `/automate` is a thin orchestration shell over the **`automate-loop` skill** (`skills/automate-loop/SKILL.md`), which is the authoritative loop contract.

> **Execution contract:** Inline main-thread execution replaces only the top-level `/automate` shell. Under `--inline-phases` you MUST still let the inlined `/autonomous` and `/review-pr` workflows spawn their own first-level child agents via the Task tool exactly as they do when run directly — do NOT collapse the per-item loop into direct main-thread implementation. Every loop contract is defined ONCE in `skills/automate-loop/SKILL.md` — this command body references them and does NOT re-coin or restate the loop semantics, the run-file layout, or the auto-merge gate.

# Command: /automate

## Purpose

`/automate` is the plugin's **generic automation engine**: it converts one source — a prompt (via `/product-owner`), a requirements folder, or a backlog/plan doc — into a full `## Queue` inside ONE run file (`.supervisor/automate/<run_id>.md`), then drives each item through the per-item loop to a reviewed PR (opt-in: a trusted merge), resuming an incomplete run first. `/backlog` is not a separate command.

## Usage

```bash
/automate "<what you want to automate>"      # prompt source (via /product-owner) → generated requirements → Queue
/automate                                    # bare → resume an incomplete run, else ASK "what do you want to automate?"
/automate --folder <dir>                     # folder source — each *.md becomes a Queue item
/automate --backlog <_BACKLOG.md>            # backlog-doc source — dependency-ordered Queue
/automate --limit N                          # cap PROCESSED items this run, full Queue still stored (default 5)
/automate --resume [<run_id>]                # reconcile + continue a prior incomplete run file
/automate --sweep [--apply]                  # run ONLY the sweep of leftover plugin worktrees/branches (no RESUME, no PICK, no run file); dry run unless --apply; refused with a source or --resume
/automate ... --auto-merge                   # opt-in trusted-merge at the gate (gated; default OFF)
/automate ... --trust-unprotected            # allow auto-merge onto a branch without enforceable protection (condition 4 ONLY — never overrides condition 6, the high-risk park; nothing does)
/automate ... --notify                       # passthrough to inner /autonomous (gate webhooks; --inline-phases only)
/automate ... --inline-phases                # run each item's phases inline here (default: each its own fresh session)
/automate ... --non-interactive-fallback     # passthrough to the item's phases + engine gates fail closed
/automate ... --cheap                        # Sonnet cost profile → /supervisor (not persisted — re-pass on --resume)
/automate ... --max-tokens N                 # opt-in spend ceiling — parked BEFORE PICK when the run's summed ledger exceeds N (never a silent overspend)
/automate ... --parallel N                   # opt-in lanes: up to N independent items at once, each in its own local clone; absent ⇒ unchanged; N = 1 ⇒ single-lane mode (a fresh lane per item, parked awaiting_merge; needs branch mode); refused with --auto-merge

/loop /loomwright:automate [...]             # the /loop driver: namespaced form, --resume on a headless tick (skill §12)
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `"<prompt>"` | One of (else bare) | — | **Prompt source.** Runs `/product-owner` on the text; the generated story file paths become the `## Queue`. A `po_gate: needs_owner (<n> flags)` result persists nothing ⇒ report + stop like 0 generated files. §2. |
| *(bare `/automate`)* | — | — | **Attempt RESUME first** (glob for an incomplete run); if none exists, `AskUserQuestion` (`header: "AUT-SOURCE"`) *"What do you want to automate?"* then proceed as a prompt source. Cannot ask (`--non-interactive-fallback`) ⇒ no question, no run file, `automate: no_source_non_interactive`; an incomplete run is never continued without `--resume [<run_id>]` — one run ⇒ `automate: resume_requires_flag_non_interactive`, start nothing (a `"<prompt>"` / `--folder` / `--backlog` start likewise). §2 / §4. |
| `--folder <dir>` | One source | — | **Folder source.** Enqueues every `.md` in `<dir>` (skipping ones already `## Status: done` or `## Status: proposed\|parked`). §2. |
| `--backlog <_BACKLOG.md>` | One source | — | **Backlog-doc source.** Enqueues in the doc's documented dependency order. §2. |
| `--limit N` | No | `5` | Caps **PROCESSED** items this run, **NOT** Queue size. §2. |
| `--resume [<run_id>]` | No | most-recent incomplete | Reconcile + continue a prior incomplete run file (id omitted ⇒ the most recent). **Re-pass non-persisted passthrough flags on every resume — especially `--cheap`: omitting it silently reverts the remaining queue to the full-cost profile (cumulative dollar impact).** §4. |
| `--sweep [--apply]` | No | off | **Run ONLY the sweep** (af/39a) — `automate-helpers.sh sweep [--apply]` in this checkout, its output printed verbatim; no RESUME, no PICK, no run file, no lock, nothing else. Dry run unless `--apply` (what it removes: skill §1.5 `sweep`). **The owner's typed `--apply` is the authorization — no question gate;** nothing in the engine runs `--apply` unattended. Combined with a source (`"<prompt>"` / `--folder` / `--backlog`) or `--resume` ⇒ ONE refusal line (`automate: --sweep runs alone — drop the source / --resume`), nothing run. |
| `--auto-merge` | No | OFF (safe mode) | **Opt-in, default OFF.** At the GATE, executes `gh pr merge --squash` ONLY when the trusted-merge gate holds; otherwise fails **CLOSED** (park + notify). **Deep contract (the conditions) is NOT restated here — see `skills/automate-loop/SKILL.md` §10.** **The gate is SELF-RESOLVING: it computes every condition from 2 on itself — a caller cannot hand it a verdict** (a `ctx.json` carrying a gate-owned key, e.g. `high_risk`, is refused outright: `PARK: ctx_carries_gate_owned_key`). |
| `--trust-unprotected` | No | off | The auto-merge gate escape hatch — allows merge onto a branch without enforceable branch protection. Meaningful only with `--auto-merge`. §10 condition 4 **only** — no flag, config key, or project file overrides condition 6. |
| `--notify` | No | off | Passthrough to the inner `/autonomous` — POSTs gate-event payloads to `LOOMWRIGHT_WEBHOOK_URL`; `--inline-phases` only. §11. |
| `--inline-phases` | No | off (fresh phases) | Runs each item's phases inline in this session (`/autonomous --single-iteration`, then the inline drain) instead of as fresh headless sessions — the rollback, and the form for a host without the relay. Kept for the current item only (not in `## Run Config`): re-pass on every `--resume` / `/loop` tick. Skill "Coordinator loop". |
| `--non-interactive-fallback` | No | off | Passthrough to the item's phases AND governs the engine's own gates: the queue-confirm prompt is skipped, an ambiguous resume fails closed (`resume_ambiguous_non_interactive`), one incomplete run without `--resume` fails closed (`resume_requires_flag_non_interactive`), and prompt intake stops on `po_gate: needs_owner`. Required for CI / non-TTY. §2 / §4 / §11. |
| `--cheap` | No | off | Passthrough on the per-item RUN step (the Sonnet cost profile). **Passthrough-only:** the engine never interprets it and it is NOT persisted in the run file's `## Run Config` — re-pass it on each `/automate --resume` or `/loop` tick. §11. |
| `--max-tokens N` | No | unset (no ceiling) | **Opt-in token-spend ceiling (red-team-hardening/06).** Recorded in `## Run Config` (`max_tokens: N`) — unlike `--cheap`/`--notify`, this one IS persisted, so a bare `--resume` still enforces it. At every PICK (`automate-helpers.sh ceiling-check`) a breach (`TOTAL > N`) OR an unreadable ledger ⇒ `pause_reason: token_ceiling` — the run PARKS before picking, never a silent continue. **Honest limit:** the ledger counts only what a SubagentStop hook saw — never the main thread's own tokens, never CI-side (`claude-review`) spend. No dollar conversion (the plugin has no price table). §6 / §11. |
| `--parallel N` | No | unset (sequential) | **Opt-in lanes (parallel-automate/05).** N > 1 runs up to N independent Queue items at once, each in its own local clone (a lane) driven by one coordinator in this checkout; recorded as `parallel: N` in `## Run Config`. `init-check` refuses N < 1, N > 10, `--auto-merge` with any N, and N = 1 with branch mode off. **N = 1 is single-lane mode** (one fresh lane per item, parked `awaiting_merge`). Absent ⇒ no lane code path. Full contract: `skills/automate-loop/lanes.md` ("Single-lane mode" for N = 1). |

## What This Does

> **`--sweep [--apply]` is checked first, before Step 0:** it runs the helper's `sweep` subcommand (`scripts/automate-helpers.sh sweep` under the plugin root, invoked exactly like every helper call in the skill; plus `--apply` only when the owner typed it), prints the output and stops — no other step below runs (see `## Parameters`).

### Step 0 — Load Canonical Workflow Bodies + Protocol Skill (always)

Before anything else, the main thread reads the canonical inlined command bodies and the authoritative loop skill so it executes the up-to-date versions rather than remembered shapes. **All reads use `${CLAUDE_PLUGIN_ROOT}`** — the canonical Claude Code variable that resolves to the plugin install dir at runtime (works on both maintainer dev checkouts and marketplace installs). Never use `loomwright/...` here — that path only resolves for the plugin maintainer. What these reads drive is ONE loop — **run next-step; do the one instruction; report the result** (the skill's "Coordinator loop"); the main thread never writes the run file itself:

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/SKILL.md   # the AUTHORITY — the coordinator loop, the global rules, the split-file index
Read ${CLAUDE_PLUGIN_ROOT}/commands/autonomous.md          # ONLY under --inline-phases: the inline RUN (/autonomous --single-iteration)
Read ${CLAUDE_PLUGIN_ROOT}/commands/review-pr.md           # ONLY under --inline-phases: the inline owned drain
```

Without `--inline-phases` the coordinator reads neither, nor any phase's agent or skill: each phase reads its own in its own session.
<!-- index-only:begin -->

Then read the skill's split files — the `SKILL.md` above is their index (parallel-automate/22, move-only) — each in full, all under `${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/`. The list below keeps the documented order. An **Always** file is read now; an **Only when** file is read the first time its trigger is observed — before acting on the step that observed it — and never re-read once loaded. A run that never observes a trigger never reads that file:

- `helpers.md`, **Only when** a helper's behaviour is in question: a helper the main thread calls itself (the start steps below, `pick-guard` and the resolvers of a new run, `sweep`) prints a line its step does not explain, a `next-step` exit 1 names a helper subcommand, or a split file being followed cites a §1.5 row for a helper's contract.
- `intake.md`, **Only when** the start resolves to a NEW run: `resume-glob --finalize` lists no incomplete run, or the owner chose Start new at the resume offer. Never on a `--resume` continue. A NEW run then runs `mkdir -p .supervisor/automate` before `automate-helpers.sh pick-guard .supervisor/automate` and before intake — the one start-order step a fresh run needs from the resume split file's §4 (without the directory `pick-guard` refuses `automate_dir_missing`).
- `run-file.md`, **Only when** the start resolves to a NEW run (intake writes its first run file from the template), a run-file helper (`runfile-write`, `progress-append`, `queue-checkoff`, `current-set`) or a `next-step` call exits non-zero naming the run file, or the owner asks for a `# skipped:` / `# abandoned:` check-off. The driver writes the run file on every other path; this file is read to write a new run's first file or to diagnose, never to re-run a step.
- `resume.md`, **Only when** a `next-step --resume` call exits non-zero (1: a helper or writer failure named on stderr; 2: a refusal, nothing written), or the owner asks to archive a run or to check an item off `# skipped:` / `# abandoned:` by hand (§5). The driver runs the start's close-out, the glob, the continue / start new / archive choice, `current-rebuild` and RECONCILE itself; this file is read to diagnose that exit, never to re-run a step.
- `per-item-loop.md`, **Only when** a `--start pick|run|drain` or `--result` call exits non-zero (1: a helper or writer failure named on stderr; 2: a refusal, nothing written), an instruction's `then` / `message` does not say what to report or do, or the owner asks for a `# skipped:` / `# abandoned:` check-off (§6 step 6, the one check-off the main thread writes). The driver runs PICK, RECONCILE, RUN, DRAIN, the park and the close-out itself; this file is read to diagnose, never to re-run a step.
- `modes-and-merge-gate.md`, **Only when** a call answering a `gate`, `validation`, `gate-eval`, `dismissed`, `decide` or `fix-now` instruction exits non-zero, or the owner asks why the gate parked or merged. The driver runs GATE (the validation gate, safe mode's park, `--auto-merge`'s `gate-eval`) itself; this file is read to diagnose, never to re-run a step.
- `invariants.md`, **Always** (read now, with the reads in the code block above).
- `branch-mode.md`, **Only when** `meta-entry` prints anything but `meta-entry: off` (equivalently `setup-memory.sh mode` prints `on <branch>`), or a helper line names branch mode (`trail-unstage: skipped — branch mode`, `trail-pr: meta-pushed …`, `meta-push FAILED`).
- `lanes.md`, **Only when** `--parallel` was passed, or `automate-helpers.sh lane-info` exits 0 (this checkout is a lane), or a helper reports a lane (`pick-guard` prints `refuse: live_lane …`, or any `lane-*` subcommand's output is being acted on), or the run being resumed carries a `- parallel:` line in its `## Run Config` (a coordinator or single-lane parent — `--parallel` is not re-passed on its `--resume`; read as soon as the resume targets that run, before its RECONCILE or first PICK, since such a run continues through the lanes section's loop — per-wave, or one new lane per item in single-lane mode — never a sequential PICK).
- `command-lanes.md`, **Only when** the lanes trigger of the row above holds (`--parallel` was passed, `automate-helpers.sh lane-info` exits 0, a helper reports a lane, or the run being resumed carries a `- parallel:` line in its `## Run Config` — a coordinator or single-lane parent); this is the command's own lanes section, moved out of the body below.

Read each plugin file with the Read tool, one file per call — never `cat` several in one Bash call: an oversized Bash result is saved to a file and read back, which loads the same text twice.

Run `automate-helpers.sh lane-info` once at start: exit 0 means this checkout is a lane, so it reads the two lanes files above before its first PICK; exit 1 means not a lane.

Run `automate-helpers.sh meta-entry` once at start, before `closeout-others` and `resume-glob --finalize` (after `init-check` when `--parallel` was passed): it prints `meta-entry: off` when branch mode is off; any other line (`pulled <branch>` or `failed — <reason>`) loads the branch-mode split file before the next start step, and a `failed` line is handled there (abort, or park `meta_unreachable`) — never fall through to an empty `resume-glob`.
<!-- index-only:end -->

### Short overview (detail deferred to the skill)

A map, not the contract: `scripts/automate-next-step.sh` runs each step below through `scripts/automate-helpers.sh` (implemented and self-tested once, skill §1.5) — never run one by hand (skill "Coordinator loop").

> **Branch mode (opt-in, default OFF):** a repo switched on with `/setup memory` keeps run history on a metadata branch — `meta-entry` pulls it first on every entry and `trail-pr` pushes to it instead of opening a PR; see `skills/automate-loop/SKILL.md` §13.

1. **RESUME first.** With `--parallel`, `init-check` runs before anything else; then `closeout-others`, `resume-glob --finalize`, reconcile, and continue / start new / archive (§4).
2. **INTAKE → Queue.** A NEW run first runs `pick-guard`, then resolves exactly one source into the FULL `## Queue` of one run file (§2 / §3).
3. **CONFIRM the Queue.** Show the full resolved Queue (gate `AUT-QUEUE`) unless `queue-confirm` skips it; `--limit N` caps PROCESSED items, never Queue size (§2).
4. **Per-item loop.** For each `- [ ]` item: run lock + `pick-guard` → RECONCILE (+ `closeout`, `closeout-classify`) → `trail-gate` → `trail-unstage` → `current-set` + `picked` → RUN → own exactly ONE `/review-pr --until-mergeable` per pass (a phase session; exactly ONE inline under `--inline-phases`) — at most one owner-requested fix-now re-drain per item, strictly sequential (never concurrent) → GATE → SYNC (`closeout --no-trail`) → check off + `## Progress` (§6–§10).
5. **TERMINATE.** Queue fully resolved ⇒ `## Status: done` / `remaining: 0`; a limit or a park ⇒ `## Status: paused` + its `pause_reason` (§6).
   - **Trail PR:** only after merge (inside `closeout`), at a `# skipped:`/`# abandoned:` check-off, and at `## Status: done` — never at a park (§6 "Trail PR after merge and at run end").
   - **Merge watcher + `closeout`:** an `awaiting_merge` or `escalated` park arms a detached merge watcher; a human merge runs `closeout`; the next item waits for your go (§6 "Post-merge close-out").
   - **Dismissed findings:** dismissed review findings → propose-only drafts + an owner decision (fix-now / follow-up / drop) at the park (each fix-now option shows its derived wall-clock cost) (§6 "Dismissed-findings decision step (before the park)").

> **Invariant (durable):** `/review-pr` / `review-heal` / Supervisor Phase 4.5 still **NEVER merge** — they terminate at `READY` / `PASS` / `ESCALATED` and leave the PR open. The **only** place in the plugin that executes `gh pr merge --squash` is the `automate-loop` `--auto-merge` gate. See `skills/automate-loop/SKILL.md` §11.

<!-- split:begin ../skills/automate-loop/command-lanes.md -->
### Lanes (`--parallel N`) and launch authority

See [../skills/automate-loop/command-lanes.md](../skills/automate-loop/command-lanes.md).
<!-- split:end ../skills/automate-loop/command-lanes.md -->

## See Also

- `skills/automate-loop/SKILL.md` — **the authoritative loop contract**.
- `commands/autonomous.md` / `commands/review-pr.md` — the RUN and DRAIN workflows run inline under `--inline-phases`.
- `docs/RESULT_SCHEMAS.md` §"AUTOMATE_RUN" — the `.supervisor/automate/<run_id>.md` run-file layout (a markdown state-file contract, NOT a hook-validated emitted result block).
