---
description: Reflect on past session logs + worker summaries, collect memory candidates, propose bounded LESSONS, harvest convention findings into proposed .agent/rules/, and write accepted items on per-item approval (read-only until you Accept; nothing reaches the remote without a separate Pre-push confirmation)
---

> **Read-only-until-Accept contract — and the TWO remote-affecting actions.** `/dreaming` is strictly read-only on code, on agent memory, and on `CLAUDE.md` while it gathers and proposes. **It is not, however, read-only on the *remote* once you accept a harvested rule or a memory write.** It can take two remote-affecting actions, each its own branch and its own pull request: the **rules PR** — create `dreaming/rules-<session_id>`, commit `.agent/rules/*.json` to it, **push** it, and open a **pull request**; and the **memory PR** — create `dreaming/memory-<session_id>`, commit the project-memory and agent-memory changes this run's Accepts already wrote in place, **push** it, and open a **pull request**. Each is reached only through **two distinct human gates** — the per-item **Accept**, which authorises the *content*, and a separate **Pre-push confirmation**, which authorises the *push*. Neither implies the other. For the rules PR both gates are per-item; for the memory PR the Pre-push confirmation is **one question per run**, asked after every memory Accept (see "Memory PR (delivery queue)" for why it cannot be per-item). If nothing survives both gates for a PR, **no branch is created for it at all**. `/dreaming` **never merges** anything: `gh pr create` and stop. Everything else below remains read-only-until-Accept exactly as before. The command **proposes** project-memory facts (incl. collected worker candidates), bounded LESSONS, per-agent memory entries, and `CLAUDE.md` updates derived from past session logs and worker summaries. The contract change in v14.5.0: on per-item **Accept**, `/dreaming` itself performs the write for **project-memory facts** and **LESSONS** by invoking the repo-root sole writers (`scripts/write-project-memory.sh`, `scripts/write-lessons.sh`) — both of which are **confirm-gated** (their store `.supervisor/memory/` is committed, so every invocation must pass `--confirm`; see `AGENT_GUIDELINES.md` §"Sole-writer confirm gates"). Every write is still HUMAN-GATED per-item via `AskUserQuestion`; there is **no auto-write**, no bulk-accept, and Reject/Edit never writes. **CLAUDE.md proposals remain paste-to-apply** (the user, or a follow-up turn, performs those writes — CLAUDE.md is not a sole writer's domain); `.claude/agent-memory/` proposals are not — since v15.33.0 they are promoted through that store's confirm-gated sole writer `write-agent-memory.sh` (see Phase 4). Since v15.12.0, per-item Accept also promotes pending **orientation-memo proposals** (files under the gitignored `.supervisor/orientation-proposals/`) into the committed `.agent/orientation/` store via that store's confirm-gated sole writer `add-orientation.sh` — same per-item human gate; Reject deletes the proposal without writing. `/dreaming` runs at the repo root so the sole writers' worktree-guard is satisfied.

> **What the PR paths may and may not touch.** The rules delivery branch carries **only** `.agent/rules/*.json` objects authored by that store's confirm-gated sole writer `add-rule.sh`. The memory delivery branch carries **only** the files in the two memory stores that this run's successful sole-writer calls **recorded** at Accept time (see "Memory PR (delivery queue)", Step 1) — never the harness-memory pointer, and never another file under those prefixes. Neither stages a source file, a doc, `CLAUDE.md` (a hand PR), the `.agent/orientation/` store, or any other store. `/dreaming` stages **explicitly** (`git add .agent/rules`; `git add -- <recorded, changed memory files>`), never `git add -A`, so an unrelated *unstaged* dirty file in your working tree is not swept into either PR. **Neither PR sweeps an entry you had already staged either:** both commits are pathspec-limited (`git commit … -- .agent/rules`; `git commit … -- <recorded, changed memory files>`), so a pre-staged unrelated entry stays staged and stays out of the commit, and each commit's file list is verified before any push — the rules commit must list only paths under `.agent/rules/`, the memory commit must equal its record (no stray path, no missing one). Each PR **refuses to deliver at all** if its paths already carried uncommitted changes `/dreaming` did not author — `.agent/rules/` at delivery time, the two memory stores (the harness-memory pointer's file excepted) at a snapshot taken before the first Phase 4 write — rather than committing edits it did not author. Harvesting is a **dry run by default** — `harvest-conventions.sh` has no write mode at all — and the only escalation out of it is the two gates above. A refused, rejected, or unconfirmed rule proposal leaves the store, the branch list, and the remote exactly as they were; an accepted memory write whose memory PR is refused or unconfirmed stays in place, uncommitted, with the branch list and the remote untouched.

# Command: /dreaming

<!-- split:begin ../docs/command-parts/dreaming/overview.md -->
## Purpose

See [../docs/command-parts/dreaming/overview.md](../docs/command-parts/dreaming/overview.md).

## Usage

See [../docs/command-parts/dreaming/overview.md](../docs/command-parts/dreaming/overview.md).

## Parameters

See [../docs/command-parts/dreaming/overview.md](../docs/command-parts/dreaming/overview.md).
<!-- split:end ../docs/command-parts/dreaming/overview.md -->
## Curation cadence (readiness check + the one stored last-run record)

`/dreaming` is the **only** one of the three curation commands whose last run is *stored* rather than derived — `/insights` is derived from `.supervisor/insights/dashboard.md`'s mtime and `/pr-postmortem` from the findings ledger, but `/dreaming` writes only through the memory writers, so `.supervisor/memory/` mtime reports the last run *that accepted something* and is structurally blind to the ran-but-accepted-nothing case. That case is exactly what this record exists to capture.

### Step 0 — readiness (runs BEFORE Phase 1 GATHER)

```bash
LOOMWRIGHT_CURATION_REMOTE=0 bash "${CLAUDE_PLUGIN_ROOT}/scripts/curation-status.sh" status
```

`LOOMWRIGHT_CURATION_REMOTE=0` is **load-bearing, not decoration**: without it, `status` makes ONE `gh pr list` round-trip to compute `/pr-postmortem`'s `pending` — a value *this* command never reads (only the `/dreaming` row feeds the decision below). Measured, that call is the difference between ~0.3 s and ~1.1 s on every `/dreaming` invocation. Only `/pr-postmortem`, which actually consumes the count, leaves the valve unset.

Read the `/dreaming` row. If `ready=no` **and `--force` was not passed**, print the probe's `decline(/dreaming)` message **verbatim** and stop — writing nothing, spawning nothing, and **exiting 0**. The decline is advisory: it is never an error, never a hook failure, and never blocks a session. With `--force`, ignore `ready` entirely and proceed.

**`pending` is a BACKLOG; `window=` is how much of it this run will read.** The row carries both, and they are different numbers: `pending` counts session logs that have never been fed to reflection, while a default run consumes the `--sessions N` most recent (`5`). When `pending` exceeds the window the probe adds a `note(/dreaming)` line saying so. **Surface both in the run report** — reporting readiness alone is how v15.29.0 came to answer `pending=61 ready=yes` about a run that would read 5 and, at the time, silently retire the other 56. If the backlog matters, pass `--sessions N` to take a bigger bite in one run; otherwise **repeated default runs walk backwards through the backlog, five at a time, because each run selects the newest logs it has *not already read*** (GATHER step 1 obtains them from `curation-status.sh unconsumed <N>`, never from a plain by-mtime listing). That is what makes the remainder genuinely reachable: selecting the most recent files *unconditionally* left anything that fell out of the newest-N window permanently unread — measured on 8 signal-carrying logs with a window of 5, pending went 8 → 3 → 3 → 3 forever. Selecting the most recent **unconsumed** files gives 8 → 3 → 0.

**`pending` counts logs carrying reflection signal, not raw files.** Logs whose every line is a `token_ledger` or `subtask_complete` event contribute nothing to reflection and are excluded. On this repo (measured 2026-08-09, 62 logs) that is 29 of them — ~96% of the corpus bytes. The filter fails open: anything unrecognisable or unreadable is counted, never silently dropped.

**The threshold is an UNVALIDATED starting guess.** The in-script default is `15` unreflected session logs; it is a guess, not a measured value. Override it at `.curation.thresholds.dreaming` in `.supervisor/config.json` (the probe READS that file and never rewrites it). An absent or malformed config falls back to the default and still exits 0. A configured `0` is **honoured, not rejected** — `readiness` compares `pending >= threshold`, so `0` means "always ready: report the cadence, never decline", the standing counterpart to the per-run `--force`. Negative and non-integer values express no coherent threshold and fall back to the default.

If the probe reports `pending=unknown` (an input it could not read), **do not decline** — `unknown` means "do not suppress, but do not claim a number", never a fabricated zero.

<!-- index-only:begin -->

> **Split layout (move-only).** This file is the `/dreaming` index: a section that carries only a `See [<part>](<part>).` line was moved verbatim to that part, heading unchanged. Read a part with the Read tool from `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/dreaming/`, one Read call per file, only at the step named below, and read no other part. Moved text that says "below" or "above" may point into another part; this list names it.

- **Readiness declined** (Step 0: `ready=no`, no `--force`) — read **no part**: print the decline, end with the `### Run report` lines below, exit 0.
- `overview.md`, `workflow.md` and `read-only.md` — once readiness passes (or `--force`), before Phase 1 GATHER: the purpose, usage and flags, the workflow, and the read-only contract the whole run keeps.
- `reflection-prompt.md` — Phase 2 REFLECT, before the first reflection spawn.
- `report.md`, `report-notes.md` and `reference.md` — Phase 3 AGGREGATE, before composing the report (sections and promotion queues; pointer, empty-state and APPLY notes; example output, and when to use `/dreaming`).
- `approval.md` — Phase 4 APPROVE, before the first approval question.
- `rules-pr.md` — only when GATHER's `harvest-conventions.sh` printed a rule batch (DEFERRED or DISTILLATION FAILURE included), before that queue is shown: how it is offered and, once a harvested proposal is accepted, its Pre-push gate and PR delivery.
- `memory-pr.md` — only when Phase 4 is about to make its first write (Accept, Supersede, Retract or promotion): its Step 0 snapshot precedes that write; its delivery runs once memory writes were recorded. A Phase 4 that writes nothing never reads it.
- `record.md` — after Phase 4 APPROVE completes on every run that did not decline (also when all was rejected or nothing proposed): the mandatory `curation-status.sh record dreaming` step, before the run report.
<!-- index-only:end -->
<!-- split:begin ../docs/command-parts/dreaming/record.md -->
### Final step — record this run (mandatory, even when nothing was accepted)

See [../docs/command-parts/dreaming/record.md](../docs/command-parts/dreaming/record.md).
<!-- split:end ../docs/command-parts/dreaming/record.md -->
### Run report (four mandatory lines)

Every `/dreaming` run — declined or completed — ends with these four lines, so the run explains itself rather than leaving the user to infer value:

- **When it last ran** — the `last_run` / `age_days` the probe reported (`never` when there is no record yet).
- **What changed since** — the pending count the probe reported (unreflected session logs carrying reflection signal) **and the window this run actually read**, e.g. "33 unreflected; this run read 5". Never the backlog alone: a reader who sees only the backlog will assume the run cleared it.
- **What it produced this time** — accepted memory facts / LESSONS / orientation promotions / agent-memory promotions, and the harvested rules outcome: either the PR URL, or explicitly **no branch and no PR** (with the reason: nothing accepted, nothing pre-push-confirmed, an empty batch, or a harvest that could not run) — and, separately, the memory PR outcome: either its PR URL (plus the note that the accepted memory files now read the original branch's content until that PR merges and is pulled), or explicitly **no memory PR** with the reason (nothing written, not offered because of pre-existing uncommitted changes, because the Step 0 dirt snapshot itself could not run (`memory PR not offered: dirt snapshot could not run (exit <n>)` — never reported as pre-existing changes), an ignored/unstageable recorded file, or the pointer's target being a recorded file, Pre-push declined, or a pre-flight abort), in which case the accepted writes are still in place, uncommitted. Whatever the memory PR outcome, also list any **unrecorded changes** the Step 1 re-scan found (or say it could not list them). State "nothing accepted" explicitly when that is the truth — a silent rules or memory section reads as a delivered PR to anyone skimming.
- **What that will improve** — the concrete downstream effect (e.g. "Supervisor Phase 1 ACQUIRE now reads this lesson before task selection").

<!-- split:begin ../docs/command-parts/dreaming/workflow.md -->
### Where the cadence surfaces

See [../docs/command-parts/dreaming/workflow.md](../docs/command-parts/dreaming/workflow.md).

## What This Does / Workflow

See [../docs/command-parts/dreaming/workflow.md](../docs/command-parts/dreaming/workflow.md).
<!-- split:end ../docs/command-parts/dreaming/workflow.md -->
<!-- split:begin ../docs/command-parts/dreaming/reflection-prompt.md -->
## Reflection-Mode Task Prompt

See [../docs/command-parts/dreaming/reflection-prompt.md](../docs/command-parts/dreaming/reflection-prompt.md).
<!-- split:end ../docs/command-parts/dreaming/reflection-prompt.md -->
**Seat routing.** The Phase 2 reflection pass is the `dreaming_analysis` seat: run `resolve-routing.sh seat dreaming_analysis` and follow `docs/PROVIDER_ROUTING.md` §"Routed seat protocol". On `PROVIDER=claude` the reflection spawn runs as written, unchanged. On another provider only the reflection analysis goes out (the reflection prompt in, the report back, checked for the role marker); GATHER, every question gate, the sole-writer calls and the PR deliveries stay on the Claude main thread. On a non-`ok` result or failed check, the reflection spawn runs as written and one `seat_routing dreaming_analysis provider=<p> reason=<r>` line is logged.

<!-- split:begin ../docs/command-parts/dreaming/report.md -->
## Reflection Report Sections

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### 1. Recurring Patterns

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### 2. Distilled Insights

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### 3. Proposed Memory Updates

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### 4. Proposed CLAUDE.md Updates

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### 5. Collected Memory Candidates

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### 6. Proposed LESSONS

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

#### Curating existing LESSONS (Supersede / Retract)

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### Pending orientation proposals (promotion queue)

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).

### Pending agent-memory proposals (promotion queue)

See [../docs/command-parts/dreaming/report.md](../docs/command-parts/dreaming/report.md).
<!-- split:end ../docs/command-parts/dreaming/report.md -->
<!-- split:begin ../docs/command-parts/dreaming/rules-pr.md -->
### Harvested `.agent/rules/` proposals (PR delivery queue)

See [../docs/command-parts/dreaming/rules-pr.md](../docs/command-parts/dreaming/rules-pr.md).
<!-- split:end ../docs/command-parts/dreaming/rules-pr.md -->
<!-- split:begin ../docs/command-parts/dreaming/memory-pr.md -->
### Memory PR (delivery queue)

See [../docs/command-parts/dreaming/memory-pr.md](../docs/command-parts/dreaming/memory-pr.md).
<!-- split:end ../docs/command-parts/dreaming/memory-pr.md -->
<!-- split:begin ../docs/command-parts/dreaming/report-notes.md -->
### Harness-memory pointer (on LESSONS Accept)

See [../docs/command-parts/dreaming/report-notes.md](../docs/command-parts/dreaming/report-notes.md).

### Empty-state suppression

See [../docs/command-parts/dreaming/report-notes.md](../docs/command-parts/dreaming/report-notes.md).

### APPLY deferral (v14.5.0 scope)

See [../docs/command-parts/dreaming/report-notes.md](../docs/command-parts/dreaming/report-notes.md).
<!-- split:end ../docs/command-parts/dreaming/report-notes.md -->
<!-- split:begin ../docs/command-parts/dreaming/approval.md -->
## Approval Option Contract

See [../docs/command-parts/dreaming/approval.md](../docs/command-parts/dreaming/approval.md).

### Payload shape (all gates)

See [../docs/command-parts/dreaming/approval.md](../docs/command-parts/dreaming/approval.md).

### Per-class option sets (fixed; in this order unless a recommendation reorders them)

See [../docs/command-parts/dreaming/approval.md](../docs/command-parts/dreaming/approval.md).

### Recommendation

See [../docs/command-parts/dreaming/approval.md](../docs/command-parts/dreaming/approval.md).

### The one exclusion that is load-bearing

See [../docs/command-parts/dreaming/approval.md](../docs/command-parts/dreaming/approval.md).
<!-- split:end ../docs/command-parts/dreaming/approval.md -->
<!-- split:begin ../docs/command-parts/dreaming/read-only.md -->
## Read-Only Contract

See [../docs/command-parts/dreaming/read-only.md](../docs/command-parts/dreaming/read-only.md).

### Enforcement boundary (honest disclosure)

See [../docs/command-parts/dreaming/read-only.md](../docs/command-parts/dreaming/read-only.md).
<!-- split:end ../docs/command-parts/dreaming/read-only.md -->
<!-- split:begin ../docs/command-parts/dreaming/reference.md -->
## Example Output

See [../docs/command-parts/dreaming/reference.md](../docs/command-parts/dreaming/reference.md).

## Workflow Positioning

See [../docs/command-parts/dreaming/reference.md](../docs/command-parts/dreaming/reference.md).

## When to Use

See [../docs/command-parts/dreaming/reference.md](../docs/command-parts/dreaming/reference.md).

## When NOT to Use

See [../docs/command-parts/dreaming/reference.md](../docs/command-parts/dreaming/reference.md).

## See Also

See [../docs/command-parts/dreaming/reference.md](../docs/command-parts/dreaming/reference.md).
<!-- split:end ../docs/command-parts/dreaming/reference.md -->
