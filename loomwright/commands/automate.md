---
description: Generic automation engine — turn any source (prompt / folder / backlog-doc) into a Queue and drive each item through /autonomous + an owned /review-pr drain to a reviewed PR (opt-in trusted auto-merge)
---

> **Execute this workflow inline as the main thread.** `/automate` is **inline-only** — there is **NO `-runner` agent** for it (agents stay 14). Do not delegate it via the Agent tool. The command inlines `/autonomous` and `/review-pr`, both of which themselves require Task descendants (`plan-reviewer`, `orchestrator`, `execute-manager`, `code-reviewer`, the `general-purpose` fix worker, etc.); an extra delegation layer would hit the documented subagent-spawn trap and the inner workflows would silently abort. `/automate` is a thin orchestration shell over the **`automate-loop` skill** (`skills/automate-loop/SKILL.md`), which is the authoritative loop contract.

> **Execution contract:** Inline main-thread execution replaces only the top-level `/automate` shell. You MUST still let the inlined `/autonomous` and `/review-pr` workflows spawn their own first-level child agents via the Task tool exactly as they do when run directly — do NOT collapse the per-item loop into direct main-thread implementation. The intake (`/product-owner` / folder / backlog-doc resolution), the single run file, RESUME, the suppress-then-own-one-drain contract, the single-open-PR invariant, and the trusted auto-merge gate are all defined ONCE in `skills/automate-loop/SKILL.md` — this command body references them and does NOT re-coin or restate the loop semantics, the run-file layout, or the auto-merge gate.

# Command: /automate

## Purpose

`/automate` is the plugin's **generic automation engine**. The plugin can drive **one** requirement deep (`/autonomous`), but nothing walks **arbitrary** work from any starting point. `/automate` is the outermost loop, strictly nested:

```
/autonomous (one requirement)  ⊂  per-item loop  ⊂  /automate (source → Queue → loop)
```

It converts **any source** — a prompt (via `/product-owner`), a requirements folder, or a backlog/plan doc — into a **full Queue with a per-run processing cap** inside **ONE markdown run file** (`.supervisor/automate/<run_id>.md`, which is the contract, the dashboard, and the resume state), then drives each Queue item through the per-item loop (`/autonomous --single-iteration` → an owned inline `/review-pr --until-mergeable` drain → trusted-merge-or-park → pull `main` → check the item off + append to `## Progress`). It is **smart about resume**: on start it globs `.supervisor/automate/*.md` for incomplete runs, reconciles them against ground truth (`gh`/`git`/`## Status: done`), and offers continue / start-new / archive.

The intake is **source-agnostic** — only the *intake* differs, and intake is just "convert the source into the Queue, once" (NOT a pluggable adapter framework). **`/backlog` is NOT a separate command** — a folder or a backlog-doc is simply one *kind* of source.

> **The `automate-loop` skill is the authoritative loop contract.** All names and contracts — intake, the run-file model, RESUME, the per-item loop, the single drain + config-toggle, the single-open-PR invariant, the two modes, and the 5-condition trusted auto-merge gate — are coined in `skills/automate-loop/SKILL.md`. This command documents the *surface* only; it does not duplicate or restate those contracts.

## Usage

```bash
/automate "<what you want to automate>"      # prompt source (via /product-owner) → generated requirements → Queue
/automate                                    # bare → resume an incomplete run, else ASK "what do you want to automate?"
/automate --folder <dir>                     # folder source — each *.md becomes a Queue item
/automate --backlog <_BACKLOG.md>            # backlog-doc source — dependency-ordered Queue
/automate --limit N                          # cap PROCESSED items this run, full Queue still stored (default 5)
/automate --resume [<run_id>]                # reconcile + continue a prior incomplete run file
/automate ... --auto-merge                   # opt-in trusted-merge at the gate (gated; default OFF)
/automate ... --trust-unprotected            # allow auto-merge onto a branch without enforceable protection (gate escape hatch)
/automate ... --notify                       # passthrough to inner /autonomous (gate webhooks)
/automate ... --non-interactive-fallback     # passthrough to inner /autonomous + engine gates fail closed
/automate ... --cheap                        # passthrough to inner /autonomous (Sonnet cost profile → /supervisor; not persisted — re-pass on --resume)

# Driven continuously by Claude's /loop — use the NAMESPACED form headless (bare /automate is "Unknown command" under detached claude -p):
/loop /loomwright:automate [...]
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `"<prompt>"` | One of (else bare) | — | **Prompt source.** Runs `/product-owner` on the text (a REUSE — PO already writes `.supervisor/requirements/*.md` story files + an optional `_BACKLOG.md` in Beads-absent mode); the generated file paths become the `## Queue`. 1 file ⇒ single-item run; N files ⇒ loop. See `skills/automate-loop/SKILL.md` §2. |
| *(bare `/automate`)* | — | — | **Attempt RESUME first** (glob for an incomplete run); if none exists, `AskUserQuestion` *"What do you want to automate?"* then proceed as a prompt source. §2 / §4. |
| `--folder <dir>` | One source | — | **Folder source.** Enqueues every `.md` in `<dir>` (skipping ones already `## Status: done`). §2. |
| `--backlog <_BACKLOG.md>` | One source | — | **Backlog-doc source.** Enqueues in the doc's documented dependency order (`## Status: done`/✅ markers are ground truth); `_BACKLOG.md`-absent ⇒ fall back to `## Status:`-stamp ordering. §2. |
| `--limit N` | No | `5` | Caps **PROCESSED** items this run, **NOT** Queue size — the run file's `## Queue` always holds the FULL resolved list. After N processed with items unchecked ⇒ `## Status: paused` / `pause_reason: limit_reached` / `remaining: <unchecked>`. §2. |
| `--resume [<run_id>]` | No | most-recent incomplete | Reconcile + continue a prior incomplete run file. Id omitted ⇒ targets the most-recent incomplete run. RESUME reconciles belief vs ground truth before trusting any checkbox. **Re-pass non-persisted passthrough flags on every resume — especially `--cheap`: omitting it silently reverts the remaining queue to the full-cost profile (cumulative dollar impact).** §4. |
| `--auto-merge` | No | OFF (safe mode) | **Opt-in, default OFF.** At the GATE, executes `gh pr merge --squash` ONLY when the trusted-merge gate holds; otherwise fails **CLOSED** (park + notify). **Deep contract (the 5 conditions) is NOT restated here — see `skills/automate-loop/SKILL.md` §10.** |
| `--trust-unprotected` | No | off | The auto-merge gate escape hatch — allows merge onto a branch without enforceable branch protection. Meaningful only with `--auto-merge`. §10 condition 4. |
| `--notify` | No | off | Passthrough to the inner `/autonomous` — POSTs gate-event payloads to `LOOMWRIGHT_WEBHOOK_URL`. §11. |
| `--non-interactive-fallback` | No | off | Passthrough to the inner `/autonomous` AND governs the engine's own gates: the queue-confirm prompt is skipped and an ambiguous resume fails closed (`resume_ambiguous_non_interactive`). Required for CI / non-TTY. §2 / §4 / §11. |
| `--cheap` | No | off | **Passthrough to the inner `/autonomous` (v15.2.0+)** — forwarded on the per-item RUN step, and `/autonomous` in turn forwards it to every inlined `/supervisor`, completing the `/automate → /autonomous → /supervisor` Sonnet cost-profile chain. **Passthrough-only:** the engine never interprets it and it is NOT persisted in the run file's `## Run Config` (same convention as `--notify` / `--non-interactive-fallback`) — re-pass it on each `/automate --resume` or `/loop` tick. Profile table + Haiku-session caveat: `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles". §11. |

> **Run-file layout, the 5-condition trusted-merge gate, the suppress/restore config-toggle contract, and the single-open-PR invariant are defined ONCE in `skills/automate-loop/SKILL.md`** (and the run-file layout is documented as a markdown state-file contract in `docs/RESULT_SCHEMAS.md` §"AUTOMATE_RUN"). They are deliberately **not** restated in this table — reference the skill for the deep contract.

## What This Does

### Step 0 — Load Canonical Workflow Bodies + Protocol Skill (always)

Before anything else, the main thread reads the canonical inlined command bodies and the authoritative loop skill so it executes the up-to-date versions rather than remembered shapes. **All reads use `${CLAUDE_PLUGIN_ROOT}`** — the canonical Claude Code variable that resolves to the plugin install dir at runtime (works on both maintainer dev checkouts and marketplace installs). Never use `loomwright/...` here — that path only resolves for the plugin maintainer:

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/SKILL.md   # the AUTHORITY — intake, run file, RESUME, per-item loop, modes, gate
Read ${CLAUDE_PLUGIN_ROOT}/commands/autonomous.md          # the inner /autonomous workflow the per-item RUN step drives --single-iteration
Read ${CLAUDE_PLUGIN_ROOT}/commands/review-pr.md           # the owned /review-pr --until-mergeable drain the DRAIN step runs inline
```

This guards against prompt drift: if the loop protocol, `/autonomous`, or `/review-pr` evolves between releases, `/automate` picks up the changes automatically because it re-reads them every run.

### Short overview (detail deferred to the skill)

The scriptable steps — the config toggle, run-file atomic writes / append-only Progress / check-off, resume reconcile, and the 5-condition trusted-merge gate — are implemented + self-tested ONCE in `scripts/automate-helpers.sh`, which the loop **shells out to** (so the tested code is the executed code); the SKILL prose is the spec each subcommand conforms to (see `skills/automate-loop/SKILL.md` §1.5).

`/automate` then executes the protocol in `skills/automate-loop/SKILL.md` — the authority for every step below; this overview is a map, not the contract:

1. **RESUME first.** Glob `.supervisor/automate/*.md` for runs not marked `## Status: done`, reconcile each in-flight item vs ground truth, and offer continue / start-new / archive (fail-closed under `--non-interactive-fallback`). (§4)
2. **INTAKE → Queue.** Resolve exactly one source (prompt via `/product-owner` / folder / backlog-doc) into the FULL ordered `## Queue` inside one run file `.supervisor/automate/<run_id>.md`. (§2 / §3)
3. **CONFIRM the Queue.** Show the full resolved Queue (count + ordered items) for confirmation before processing; `--limit N` (default 5) caps how many are PROCESSED this run, never Queue size. (§2)
4. **Per-item loop.** For each `- [ ]` item: RECONCILE → suppress the default drain then run `/autonomous --single-iteration --requirement <path>` → own exactly ONE inline `/review-pr --until-mergeable` (restore the config toggle finally-style) → GATE (safe-mode park `awaiting_merge`, or `--auto-merge` 5-condition trusted gate) → SYNC `main` after merge → check the item off + append `## Progress` via one atomic write. The single-open-PR invariant blocks PICK while any PR is open. (§6–§10)
5. **TERMINATE.** Queue fully resolved ⇒ `## Status: done` / `remaining: 0` (the `/loop` driver stops); `limit` reached or a park (`awaiting_merge` / `escalated`) ⇒ `## Status: paused` with the matching `pause_reason`. (§6)

> **Invariant (durable):** `/review-pr` / `review-heal` / Supervisor Phase 4.5 still **NEVER merge** — they terminate at `READY` / `PASS` / `ESCALATED` and leave the PR open. The **only** place in the plugin that executes `gh pr merge --squash` is the `automate-loop` `--auto-merge` gate. See `skills/automate-loop/SKILL.md` §11.

## See Also

- `skills/automate-loop/SKILL.md` — **the authoritative loop contract** (intake, single run file, RESUME, per-item loop, single drain + config-toggle, single-open-PR invariant, two modes, the 5-condition trusted auto-merge gate, termination).
- `commands/autonomous.md` — the inner `/autonomous` workflow the per-item RUN step drives `--single-iteration`.
- `commands/review-pr.md` — the owned `/review-pr --until-mergeable` drain the DRAIN step runs inline.
- `docs/RESULT_SCHEMAS.md` §"AUTOMATE_RUN" — the `.supervisor/automate/<run_id>.md` run-file layout (a markdown state-file contract, NOT a hook-validated emitted result block).
