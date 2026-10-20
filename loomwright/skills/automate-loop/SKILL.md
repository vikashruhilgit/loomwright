---
name: automate-loop
description: Protocol authority for `/automate` — the generic automation engine that converts ANY source (a prompt via /product-owner, a requirements folder, or a backlog-doc) into a FULL Queue with a per-run processing cap inside ONE markdown run file (`.supervisor/automate/<run_id>.md` — the contract, dashboard, and resume state), then drives each Queue item through the per-item loop (Launch Pad → Supervisor → owned `/review-pr --until-mergeable`, each its own fresh session by default, or `/autonomous --single-iteration` + an inline drain under `--inline-phases` → trusted-merge-or-park → pull main → check off + append `## Progress`). Smart resume = glob run files (`# Automate Run:` title, `is_run_file`) not stamped done + reconcile-vs-ground-truth. Use when implementing or invoking `/automate`.
allowed-tools: [Read, Write, Edit, Bash, Task, AskUserQuestion]
version: "1.18.0"
lastUpdated: "2026-10-20"
---

# Automate Loop Skill

The **single source of truth** for the `/automate` generic automation engine — the protocol that walks **arbitrary work from any starting point** through to a reviewed PR (and, opt-in, a trusted merge). This skill is the **authority**; the `/automate` command body (`${CLAUDE_PLUGIN_ROOT}/commands/automate.md`), the `AUTOMATE_RUN` run-file layout in `docs/RESULT_SCHEMAS.md`, and the helper scripts under `scripts/` all **reference** the names and contracts coined here and must not re-coin or rename them.

> This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/review-heal/SKILL.md` and `skills/autonomous-loop/SKILL.md`. There is **no `-runner` agent** — the `/automate` coordinator is inline-only (agents stay 14); each item's phases run as their own sessions unless `--inline-phases`.
<!-- index-only:begin -->

> **Split layout (parallel-automate/22, move-only).** This file is the skill's index. A section below that carries only a `See [<file>](<file>).` line was moved verbatim to that file in this directory — read the file for the section; every `§N` number and heading is unchanged. Which split file the inline engine reads, and when, is decided in one place: `commands/automate.md` Step 0. `scripts/test-automate-loop-split.sh` keeps this index and the files in step.
<!-- index-only:end -->

---

## §1 — Purpose & Layering

`/autonomous` (one requirement) ⊂ the per-item loop (§6) ⊂ `/automate` (source → Queue → loop). Intake converts the source into the run file's Queue, once (§2). It is **NOT a pluggable adapter framework**; **`/backlog` is NOT a separate command** — a folder or a backlog-doc is one *kind* of source.

### Non-goals (v1)

- Sources beyond **prompt / folder / backlog-doc**.
- A `-runner` agent (inline-only; agent count stays 14).
- QA-in-loop.
- Parallel execution beyond `--parallel N` lanes (§14): one wave at a time, lanes on this machine only; merging the wave PR is the owner's — the engine opens the wave PR (`wave-build`, §14 "Wave close"), never merging it.
- **Multiple concurrent open PRs in one run file** — BOTH modes keep a **single-open-PR invariant** (§8): one open PR per run file (one per lane); `escalated` parks the run, it never opens a second PR.
- A separate registry / manifest / `progress.jsonl` / dashboard file — the **single run file is enough** (§3).

---

## Coordinator loop — run next-step; do the one instruction; report the result

The default path of every `/automate` run (automate-speed/06–08). `scripts/automate-next-step.sh`, invoked from the plugin root's `scripts/` like every helper, runs every deterministic step of resume, PICK, RECONCILE, RUN, DRAIN, GATE, the park and the close-out itself, writes the run file only through the helpers, and prints ONE JSON instruction per call. The main thread's whole job:

1. **Start.** After the start steps `commands/automate.md` Step 0 names (`lane-info`, `init-check` with `--parallel`, `meta-entry`), call `automate-next-step.sh --resume .supervisor/automate --session-id <sid>` — plus `--run latest` for `/automate --resume`, `--run <run_id>` for `/automate --resume <run_id>`. A `{"do":"done","status":"stopped","choice":"start_new"}` answer, or no incomplete run to resume, is a NEW run: intake (§2), then `automate-next-step.sh <runfile> --start pick --session-id <sid>`. A `--parallel` coordinator run (`## Run Config` carries `- parallel: N`) is never picked in the primary: on continue the driver answers `{"do":"done","status":"stopped","stop":"coordinator_run"}` (no write past the start steps), and the run continues through [lanes.md](lanes.md)'s per-wave loop (single-lane mode for `parallel: 1`).
2. **Do the one instruction, then report it.** `spawn` — run its `invocation` (`drain_invocation` for a fix-now re-drain; the pass owns one drain, at most one owner-requested fix-now re-drain per item, strictly sequential) and call again with the `--result` its `then` names, also when the work failed. A spawn carrying `"session":"fresh"` (the default for the item's three phases — `plan` Launch Pad, `run` Supervisor, `drain` the owned drain; automate-speed/09) is never run inline: run its `launch` line (a headless print-mode session in this checkout, through `phase-launch`), then `phase-wait` as its `then` says — exit 3 run it again; exit 5 a relayed question: ONE ask-tool call carrying the question file's `header`, text and option labels verbatim, then `phase-answer` (never answer a phase question yourself; ask tool unavailable ⇒ the gate's named can't-ask status); exit 6 report the phase as died; exit 0 report the sidecar path and the session id `phase-wait` printed. `ask` — one ask-tool call with its `questions`; report `{"answers":[…]}`, or `{"cant_ask":true}` when the ask tool is unavailable. `park` — stop the loop: the park state, watcher, notify and run-lock release are already done. `done` — `running`: call `--start pick` for the next item; `done`: the Queue is resolved, stop; `stopped`: report its `message` and stop.
3. **Flags.** Pass `--mode safe|auto-merge`, `--non-interactive` (under `--non-interactive-fallback`), `--trust-unprotected`, `--notify`, `--cheap`, `--max-tokens N` and `--inline-phases` as `/automate` received them, plus `--owner-command '<the /automate command the owner typed in this session>'` with `--session-id` (the launch authority every fresh `launch` line carries — never invent one), and re-pass the ones `## Run Config` does not keep (`--notify`, `--cheap`, `--non-interactive-fallback`, and `--inline-phases`, kept for the current item only) on every `--resume` and `/loop` tick.
4. **Never write the run file yourself**, and never re-run a step the driver runs; a free-text `## Progress` line goes in `progress_note` / `progress_notes`. Exit 1 is a helper or writer failure named on stderr (the next call retries that step); exit 2 is a refusal with nothing written. Either one is the trigger to read the split file that holds that step (Step 0) before acting — never to improvise the step.
5. **The one write that stays the main thread's:** an owner-requested `# skipped:` / `# abandoned:` check-off (§5, §6 step 6).

The instruction contract — the closed `do` enum, every field, the `--result` shapes — is `docs/result-schemas/automate-run.md` §"next-step instruction"; the driver's steps are its `case` arms.

---

<!-- split:begin helpers.md -->
## §1.5 — Reference implementation (the loop shells out to these)

See [helpers.md](helpers.md).
<!-- split:end helpers.md -->

---

<!-- split:begin intake.md -->
## §2 — Intake: any source → the Queue (convert once, NO adapter framework)

See [intake.md](intake.md).

### Prompt source — `/automate "X"`

See [intake.md](intake.md).

### Folder source — `/automate --folder <dir>`

See [intake.md](intake.md).

### Backlog-doc source — `/automate --backlog <_BACKLOG.md>`

See [intake.md](intake.md).

### `--parallel N>1` intake lint (§14)

See [intake.md](intake.md).

### `--limit N` — caps PROCESSED items, NOT Queue size

See [intake.md](intake.md).
<!-- split:end intake.md -->

---

<!-- split:begin run-file.md -->
## §3 — The single run file (`.supervisor/automate/<run_id>.md`)

See [run-file.md](run-file.md).

### Run-file template (reproduce exactly)

See [run-file.md](run-file.md).

### Item lifecycle

See [run-file.md](run-file.md).

### `## Status` semantics

See [run-file.md](run-file.md).

### Crash-safety contract (HIGH-risk mitigation — run-file is the ONLY copy of resume state)

See [run-file.md](run-file.md).

### `## Current` moves only through `current-set`

See [run-file.md](run-file.md).
<!-- split:end run-file.md -->

---

<!-- split:begin resume.md -->
## §4 — RESUME = glob + reconcile (run-file is BELIEF; git/gh is TRUTH)

See [resume.md](resume.md).

## §5 — Skipped / abandoned items

See [resume.md](resume.md).
<!-- split:end resume.md -->

---

<!-- split:begin per-item-loop.md -->
## §6 — The per-item loop

See [per-item-loop.md](per-item-loop.md).

### Termination (two exits)

See [per-item-loop.md](per-item-loop.md).

### Brief-repair at RECONCILE and SYNC (merge-evidenced lifecycle repair)

See [per-item-loop.md](per-item-loop.md).

### Trail PR after merge and at run end

See [per-item-loop.md](per-item-loop.md).

### Post-merge close-out (`closeout` + the merge watcher)

See [per-item-loop.md](per-item-loop.md).

### Rate-limit park (end of RUN, before DRAIN)

See [per-item-loop.md](per-item-loop.md).

### Dismissed-findings decision step (before the park)

See [per-item-loop.md](per-item-loop.md).

## §7 — Single drain (no double-dispatch) + the config-toggle contract

See [per-item-loop.md](per-item-loop.md).

## §8 — Single-open-PR invariant (BOTH modes)

See [per-item-loop.md](per-item-loop.md).
<!-- split:end per-item-loop.md -->

---

<!-- split:begin modes-and-merge-gate.md -->
## §9 — Two modes + READY / ESCALATED semantics

See [modes-and-merge-gate.md](modes-and-merge-gate.md).

## §10 — Trusted auto-merge gate (7 conditions, fail CLOSED, SELF-RESOLVING)

See [modes-and-merge-gate.md](modes-and-merge-gate.md).
<!-- split:end modes-and-merge-gate.md -->

---

<!-- split:begin invariants.md -->
## §11 — Invariant preservation

See [invariants.md](invariants.md).
<!-- split:end invariants.md -->
<!-- index-only:begin -->

> **§11's surface list after the split (parallel-automate/22).** The positive-form grep in §11 now hits this skill at `skills/automate-loop/per-item-loop.md` and `skills/automate-loop/modes-and-merge-gate.md` — the split files that hold the mentions formerly in this file — not at `SKILL.md` itself. Read the `skills/automate-loop/SKILL.md` entry in §11's list as the skill as a whole (this index + its split files). The list in [invariants.md](invariants.md) is moved text, kept byte-identical by design.
<!-- index-only:end -->

---

## §12 — Invocation surface & the `/loop` driver

### Flags

The flag list is `commands/automate.md` §"Usage" (read with this skill at Step 0); each flag's rule sits at the step that reads it.

### `/loop` driver (namespaced form required headless)

The engine is designed to be driven continuously by Claude's `/loop`. Use the **namespaced** form (bare `/automate` is "Unknown command" under detached `claude -p`):

```
/loop /loomwright:automate [...]
```

`/loop` re-invokes `/automate` each tick; the run file's `## Status` is the stop signal — `done` (Queue fully resolved) or `paused` (limit / awaiting_merge / escalated) both stop the driver. A headless tick that must continue an existing run carries `--resume [<run_id>]`: without it, a tick that cannot ask stops at `resume_requires_flag_non_interactive` (§4 step 4) rather than continuing on the owner's behalf. That stop — and a `resume_ambiguous` stop — also **stops the `/loop` driver**: the tick must not re-run (a re-tick meets the same unanswerable question); the owner re-invokes with `--resume [<run_id>]`.

---

<!-- split:begin branch-mode.md -->
## §13 — Branch mode (opt-in, default OFF)

See [branch-mode.md](branch-mode.md).
<!-- split:end branch-mode.md -->

---

<!-- split:begin lanes.md -->
## §14 — Lanes (--parallel N)

See [lanes.md](lanes.md).

### INIT (coordinator and lane)

See [lanes.md](lanes.md).

### The per-wave loop

See [lanes.md](lanes.md).

### Launch authority (a new stance — the plugin had none before)

See [lanes.md](lanes.md).

### Lane states and what the coordinator does

See [lanes.md](lanes.md).

### Terminal park — `ready_for_release`

See [lanes.md](lanes.md).

### Single-lane mode (`--parallel 1`)

See [lanes.md](lanes.md).

### Wave close — `wave-build`, then `fleet-closeout`

See [lanes.md](lanes.md).

### Policy answers

See [lanes.md](lanes.md).

### Dismissed findings, tokens, RESUME, removal

See [lanes.md](lanes.md).

### Fleet health

See [lanes.md](lanes.md).
<!-- split:end lanes.md -->

---

## Anti-Patterns

- **Building an adapter framework for sources.** Intake is "convert the source into the Queue, once" (§2) — three concrete resolvers, no plugin system.
- **Creating a manifest / registry / `progress.jsonl` / dashboard file.** The ONE run file is the only persistent tracking artifact (§3); everything else is a sidecar (§3, §6, §7).
- **Rewriting `## Progress`.** It is append-only (§3).
- **Moving `## Current` in prose, or only in `## Progress`.** Every `## Current` item / `pause_reason` write is a `current-set` call (§3); on a `current_not_set` exit 3, run the missing `current-set` — never suppress the exit.
- **Non-atomic run-file writes.** Always temp + rename (§3).
- **Feeding `runfile-write` from a generator that can fail silently — or routing around its refusal.** Never pass a multi-line value through `awk -v` (read `ENVIRON[...]`), never pipe an unescaped-delimiter `sed` into it, prefer `progress-append` / `queue-checkoff`; on `[runfile_write_refused]` fix the generator and retry — never write the file another way (§3).
- **Trusting a checkbox without reconciling.** The run file is *belief*; reconcile vs `gh`/`git`/`## Status: done` first (§4).
- **Asserting "merged"/"on main" from memory.** Verify via `gh pr view --json state,mergedAt` / `git branch --contains` (§4).
- **Double until-mergeable drain.** Suppress `.auto_review` around the RUN phase and own exactly ONE inline drain per pass — at most one owner-requested fix-now re-drain per item, strictly sequential (never concurrent) (§7); never let `/autonomous`'s detached drain race the engine's.
- **Parking with dismissed findings nobody decided on — or holding the park for them.** Ask only where §6 "Dismissed-findings decision step (before the park)" says — at a sequential READY park only after the park is written and on a `park-ask-gate` `ask — …` line; fix-now only on `ask — fix-now allowed`, under a re-acquired run lock, once per item, never at PICK.
- **Toggling `.auto_review` at DRAIN instead of around RUN.** Both default dispatches fire *during* `/autonomous` (§7).
- **Leaving a partial `config.json` on restore.** Restore byte-for-byte OR delete-if-originally-absent (§7).
- **Overwriting a malformed pre-existing `config.json`.** Abort the tick instead (§7).
- **Picking a new item while a PR is open.** `awaiting_merge`, `escalated` and this run's own open trail PR (`trail_pr_open`) all block PICK (§8).
- **Retrying RUN into a rate-limit wall, or misreporting it as a dead worker.** A rate-limit failure parks the item (`rate_limit`) and stops; never re-invoke `/autonomous` for it in the same tick (§6 "Rate-limit park").
- **Promoting a `429` text hint into the classified `reason`.** The hint goes only in a separate `reason_hint: rate_limit` field (§6 "Rate-limit park").
- **Merging on bare `READY`.** `--auto-merge` must pass EVERY condition of the trusted gate (§10) — fail CLOSED otherwise.
- **Reusing the Supervisor's `risk_classification` at the gate, or inventing an override for condition 6.** The gate re-runs `classify-risk.sh` on the SHA it judges; nothing lowers a classification (§10 cond 6).
- **Inventing a `gh pr view --json reviewThreads` flag.** Unresolved threads + author type are GraphQL-only (§10 cond. 3).
- **Gating rubric on the autonomous EVALUATE loop.** Read `SUPERVISOR_RESULT.rubric_score` (§10 cond. 5).
- **Stacking a second PR on `escalated`.** Resolve it or mark the item `skipped`/`abandoned`, then `--resume` (§5/§9).
- **Running two `/automate` loops in one repo.** Single-run-per-repo is ENFORCED by `run-lock.sh` at PICK (§6 step 1 / §11).
- **Committing a done stamp for unmerged work.** Trail only after merge, at a skip/abandon check-off, or at run end — never at a park — and let `trail-pr`'s evidence gate exclude a stamp whose PR is not merged (§6 "Trail PR after merge and at run end").
- **Answering a lane question by judgement.** Only `lane-policy.sh decide`'s exact lookup answers a lane question without the owner (§14 "Policy answers"); the engine never merges a lane PR or the wave branch (§14 "Wave close").
- **Letting the engine merge anywhere but the §10 gate.** `gh pr merge --squash` lives ONLY in the `--auto-merge` gate; `review-heal`/Supervisor Phase 4.5 never merge (§11).

---

## Related Skills

- `skills/autonomous-loop/SKILL.md` — the `/autonomous` inner loop (RUN under `--inline-phases`; its Rubric Grader feeds §10 condition 5).
- `skills/review-heal/SKILL.md` — the owned drain (§7), READY semantics (§9), the GraphQL review-thread read (§10 cond. 3).
- `skills/state-management/SKILL.md` — `.supervisor/` state-file conventions.
- `commands/automate.md` — the command body that reads this skill at Step 0.
- `docs/RESULT_SCHEMAS.md` §"AUTOMATE_RUN" — the run-file layout (a markdown state-file contract, not a hook-validated result block).

---

## Quality Gates

- Exactly **one** source resolved per run; the FULL resolved Queue is materialized in `## Queue` and confirmed before processing unless `queue-confirm` skips gate `AUT-QUEUE` (§2).
- `--limit N` caps **PROCESSED** items (default 5), never Queue size; the run file always stores the full list.
- Exactly ONE `.supervisor/automate/<run_id>.md` per run — NO `manifest.json` / `runs.jsonl` / `progress.jsonl` / dashboard created.
- Run-file writes are atomic (temp + rename); `## Progress` is append-only; rewrites confined to `## Queue` + `## Current`.
- RESUME globs run files (`# Automate Run:` title, `is_run_file` — §6 result sidecars excluded) not stamped done and reconciles each in-flight item vs `gh`/`git`/`## Status: done` BEFORE trusting a checkbox (§4).
- Single drain: `.auto_review:false` set before `/autonomous`, restored finally-style; ONE inline `/review-pr --until-mergeable` per pass (at most one owner-requested fix-now re-drain per item, strictly sequential (never concurrent)); `## Current` records `owned_drain_started`/`owned_drain_result`/`suppressed_default_dispatch:true` (§7).
- Dismissed findings: at every park with an open PR, `dismissed-drafts` runs and each drafted finding gets an owner decision where §6 "Dismissed-findings decision step (before the park)" says; `--non-interactive-fallback` asks nothing and records `pending_decisions`.
- Single-open-PR invariant holds in BOTH modes, this run's trail PR included (§8).
- `--auto-merge` executes `gh pr merge --squash` ONLY when EVERY trusted-gate condition (§10) holds; fails CLOSED (park + notify) on any blocker — no override for condition 6 or 7.
- `READY`/`PASS` from `review-heal`/`review-pr`/Supervisor Phase 4.5 NEVER merge; the ONLY executed `gh pr merge --squash` is the §10 gate implemented in `automate-helpers.sh gate-eval`.
- All `/autonomous` correctness gates bubble up; `--notify` / `--non-interactive-fallback` / `--cheap` pass through (§11).
- Termination: Queue fully resolved ⇒ `## Status: done` / `remaining: 0`; `limit` reached ⇒ `## Status: paused` / `pause_reason: limit_reached` / `remaining: <unchecked>`.
- Trail PR only after merge (`closeout`), at a skip/abandon check-off, and at `## Status: done` — never at a park (§6 "Trail PR after merge and at run end").
- Rate-limit park: a main-scope `agent_lifecycle: failed` row with `reason: rate_limit` (or `unknown` + a `429` hint, kept as `reason_hint`) parks the item before DRAIN/GATE without retrying (§6 "Rate-limit park").
<!-- index-only:begin -->

## Cited sub-section anchors

Anchors that committed prose cites as a section of this skill but that are not headings — a bold bullet label inside a moved section. Each lives in the split file named here; open it and search for the anchor text. `scripts/test-automate-loop-split.sh` (citation check) derives the cited set from the tracked tree and fails when a cited anchor resolves to no heading here, no row here, or a file that does not hold it.

| Anchor | Split file |
|---|---|
| SessionStart surfacing | [per-item-loop.md](per-item-loop.md) |
| After a close-out | [run-file.md](run-file.md) |
| Validate before rename | [run-file.md](run-file.md) |
<!-- index-only:end -->
