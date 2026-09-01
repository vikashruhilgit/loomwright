---
description: Reflect on past session logs + worker summaries, collect memory candidates, propose bounded LESSONS, harvest convention findings into proposed .agent/rules/, and write accepted items on per-item approval (read-only until you Accept; nothing reaches the remote without a separate Pre-push confirmation)
---

> **Read-only-until-Accept contract — and the ONE remote-affecting action.** `/dreaming` is strictly read-only on code, on agent memory, and on `CLAUDE.md` while it gathers and proposes. **It is not, however, read-only on the *remote* once you accept a harvested rule.** The single remote-affecting action `/dreaming` can take is: create a local branch, commit `.agent/rules/*.json` to it, **push** it, and open a **pull request**. It reaches that only through **two distinct per-item human gates** — the per-item **Accept**, which authorises the rule's *content*, and a separate **Pre-push confirmation**, which authorises the *push*. Neither implies the other, both are per-item, and if no proposal survives both then **no branch is created at all**. `/dreaming` **never merges** anything: `gh pr create` and stop. Everything else below remains read-only-until-Accept exactly as before. The command **proposes** project-memory facts (incl. collected worker candidates), bounded LESSONS, per-agent memory entries, and `CLAUDE.md` updates derived from past session logs and worker summaries. The contract change in v14.5.0: on per-item **Accept**, `/dreaming` itself performs the write for **project-memory facts** and **LESSONS** by invoking the repo-root sole writers (`scripts/write-project-memory.sh`, `scripts/write-lessons.sh`) — both of which are **confirm-gated** (their store `.supervisor/memory/` is committed, so every invocation must pass `--confirm`; see `AGENT_GUIDELINES.md` §"Sole-writer confirm gates"). Every write is still HUMAN-GATED per-item via `AskUserQuestion`; there is **no auto-write**, no bulk-accept, and Reject/Edit never writes. **CLAUDE.md and legacy `.claude/agent-memory/` proposals remain paste-to-apply** (the user, or a follow-up turn, performs those writes — they are not the sole writers' domain). Since v15.12.0, per-item Accept also promotes pending **orientation-memo proposals** (files under the gitignored `.supervisor/orientation-proposals/`) into the committed `.agent/orientation/` store via that store's confirm-gated sole writer `add-orientation.sh` — same per-item human gate; Reject deletes the proposal without writing. `/dreaming` runs at the repo root so the sole writers' worktree-guard is satisfied.

> **What the PR path may and may not touch.** The delivery branch carries **only** `.agent/rules/*.json` objects authored by that store's confirm-gated sole writer `add-rule.sh` — never a source file, never a doc, never `CLAUDE.md`, and never any other store. `/dreaming` stages those paths **explicitly** (`git add .agent/rules`), never `git add -A`, so an unrelated dirty file in your working tree can never be swept into the PR; and it **refuses to deliver at all** if `.agent/rules/` already carries uncommitted changes, rather than committing edits it did not author. Harvesting is a **dry run by default** — `harvest-conventions.sh` has no write mode at all — and the only escalation out of it is the two gates above. A refused, rejected, or unconfirmed proposal leaves the store, the branch list, and the remote exactly as they were.

# Command: /dreaming

## Purpose

The Dreaming command runs target agents in **reflection mode** over recent session logs **and worker summaries** to surface recurring patterns, distill insights, **collect durable memory candidates that workers proposed**, and **propose** bounded project LESSONS, agent persistent-memory entries, and project `CLAUDE.md` updates. It mirrors how human teams retrospectively review past work to extract durable lessons. It also **harvests recorded `convention_mismatch` findings into proposed `.agent/rules/` entries** and delivers accepted ones as a **pull request** rather than an in-place write. Each proposed update requires explicit **per-item** user approval; on Accept, `/dreaming` writes **project-memory facts** and **LESSONS** via the repo-root sole writers and promotes pending **orientation** and **agent-memory** proposals through their own sole writers, while **CLAUDE.md** proposals stay paste-to-apply. Harvested rules take a second gate — a **Pre-push confirmation** — before any branch, push, or PR exists, and `/dreaming` never merges. There is no auto-write and no bulk-accept — Reject/Edit never writes.

This makes `/dreaming` the safe, auditable counterpart to live execution: read past logs and worker summaries, think out loud, and present a structured reflection report that the user can accept, reject, or edit item-by-item — with accepted memory/LESSONS persisted through the guarded sole writers, never by hand.

## Usage

```bash
/dreaming                                          # All agents, last 5 sessions
/dreaming --agent code-reviewer                    # Reflect with Code Reviewer only
/dreaming --agent red-team                         # Reflect with Red Team Reviewer only
/dreaming --agent qa-executor                      # Reflect with QA Executor only
/dreaming --sessions 10                            # All agents, last 10 sessions
/dreaming --agent code-reviewer --sessions 20      # Single agent, deeper history
/dreaming --agent all --sessions 3                 # Explicit all (default), last 3 sessions
/dreaming --full-model                             # Reflection spawns inherit the session model (skip the sonnet default)
/dreaming --force                                  # Skip the curation-readiness check and reflect anyway
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--agent` | No | `all` | Which agent(s) run reflection. Accepts `all`, `code-reviewer`, `red-team`, or `qa-executor`. `all` runs each supported agent in turn and aggregates their reports. Six agents have `memory: project` (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor); v12.2.0 supports the three review-shaped agents listed above because their session logs carry the structured findings reflection needs (CODE_REVIEW_RESULT issues, red-team attack outcomes, QA_RESULT gates). Launch Pad, Product Owner, and QA Strategist are intentionally out of scope for v12.2.0 and may be added in a follow-up. |
| `--sessions N` | No | `5` | How many of the most recent **unconsumed** `.supervisor/logs/{session_id}.jsonl` files to feed into reflection (obtained from `curation-status.sh unconsumed N` — see GATHER step 1; a plain "N most recent" selection can never reach the tail). Values are clamped to the number of available unconsumed log files. Higher values surface more durable patterns at higher token cost. **This is the consumption window, and it is independent of the readiness `pending` count** — the readiness gate can report a backlog of 60 and a default run will still read 5 of them, leaving the rest for later runs, which then read the next-newest 5. The probe states both numbers (`pending=` and `window=`); raise this deliberately when you want a run to bite off more. The `5` here is the authoritative default — `curation-status.sh` mirrors it in `DREAMING_DEFAULT_WINDOW` and `test-curation-status.sh` group (o) fails if the two drift. |
| `--force` | No | off | Skips the **curation-readiness check** (see "Curation cadence" below) and reflects regardless of how little has accumulated. Without it, `/dreaming` declines — advisory, exit 0, never an error — when fewer than `threshold` **unreflected** session logs remain (logs never fed to reflection that carry reflection signal — *not* "logs newer than the last run"; see the cadence section for why that distinction is load-bearing). **The threshold is an UNVALIDATED starting guess** (in-script default `15`, override at `.curation.thresholds.dreaming` in `.supervisor/config.json`), so `--force` is the expected escape hatch, not an emergency one. |
| `--full-model` | No | off | Skips the default spawn-time model routing. By default (flag absent), each reflection spawn passes `model: "sonnet"` on its Task call — reflection is read-only, backward-looking analysis where the cheaper tier is adequate (authority: `docs/ARCHITECTURE_CONTRACTS.md` §Cost Profiles → "Async analysis surfaces"). With `--full-model`, the `model` param is omitted so reflection spawns `inherit` the session model. This routing applies ONLY to `/dreaming` reflection spawns; the same agents' forward roles (diff review, adversarial audit, voter, test execution) are never downgraded by it. |

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

### Final step — record this run (mandatory, even when nothing was accepted)

After Phase 4 APPROVE completes — **including a run where every item was Rejected, or where there was nothing to propose at all** — `/dreaming` stamps its own last-run value **and names the session logs it actually read in Phase 1 GATHER**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/curation-status.sh" record dreaming <session_id> [<session_id> ...]
```

Each `<session_id>` is a log's basename minus `.jsonl` — exactly the `--sessions N` files selected in step 1 of GATHER. Pass **every** one that was fed to reflection, and **only** those.

**Naming them is the whole point of this call, not a detail.** The stored record is a *consumed set*, so `pending` falls by precisely the logs this run read and the unread remainder stays counted for the next one. A bare `record dreaming` with no ids still stamps `last_run` — a run that genuinely read nothing is a real run, and capturing it is why this record exists — but the probe will WARN that `pending` will not fall, because a run that read logs and forgot to name them looks exactly like a stuck probe.

> **Why a set and not a timestamp.** `/dreaming` reads the *most recent* N logs, so what it leaves behind is *older* than any stamp it could write. v15.29.0 stored wall-clock `now` and computed `pending` as "logs newer than that", which meant one run retired the entire unread backlog — on this repo, 56 logs — with no way to target them later. No single timestamp can express "the newest 5 are done, the older 57 are not"; only set membership can.

`dreaming` is the **only** legal `record` target; any other argument is rejected with a message and still exits 0. An id naming a log that is not on disk is reported and not stored. Skipping this call entirely leaves the stored value at `never` forever, which silently keeps the SessionStart curation nudge firing and makes every readiness answer wrong — it is not an optional flourish.

### Run report (four mandatory lines)

Every `/dreaming` run — declined or completed — ends with these four lines, so the run explains itself rather than leaving the user to infer value:

- **When it last ran** — the `last_run` / `age_days` the probe reported (`never` when there is no record yet).
- **What changed since** — the pending count the probe reported (unreflected session logs carrying reflection signal) **and the window this run actually read**, e.g. "33 unreflected; this run read 5". Never the backlog alone: a reader who sees only the backlog will assume the run cleared it.
- **What it produced this time** — accepted memory facts / LESSONS / orientation promotions / agent-memory promotions, and the harvested rules outcome: either the PR URL, or explicitly **no branch and no PR** (with the reason: nothing accepted, nothing pre-push-confirmed, an empty batch, or a harvest that could not run). State "nothing accepted" explicitly when that is the truth — a silent rules section reads as a delivered PR to anyone skimming.
- **What that will improve** — the concrete downstream effect (e.g. "Supervisor Phase 1 ACQUIRE now reads this lesson before task selection").

### Where the cadence surfaces

The same probe backs the **SessionStart curation nudge** in `scripts/session-resume.sh`: ONE advisory line carrying a real count, debounced by a 24h marker (`.supervisor/.curation-nudge-shown`) and silenced permanently by `LOOMWRIGHT_CURATION_NUDGE=0|off|false|no`. The nudge is **local-only** (no `gh`, no `curl` — it runs inside a hook) and reaches the session as `hookSpecificOutput.additionalContext`, i.e. **model-context injection that the agent then surfaces** — not a directly-rendered desktop notification. That is a deliberate choice: `notify-desktop.sh` is reserved for exceptional faults, and a recurring cadence reminder is not a fault.

## What This Does / Workflow

`/dreaming` is a four-phase reflection workflow — read-only while it gathers and proposes, write-on-Accept (through the guarded sole writers) for project-memory facts, LESSONS and the two promotion queues, and PR-delivery-on-Pre-push-confirmation for harvested `.agent/rules/` proposals:

```
┌─────────────────────────────────────────────────────────────────┐
│              /dreaming — REFLECTION WORKFLOW                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: GATHER (Read-only source discovery)                   │
│     └─> Select logs via `curation-status.sh unconsumed N` (the  │
│         N most recent UNCONSUMED, newest mtime first — never a  │
│         plain by-mtime listing, which never drains the tail),   │
│         plus `.supervisor/worker-summaries/*.md` and            │
│         the briefs in `.supervisor/jobs/done/` + `failed/`,     │
│         plus (optional) System Twin contract drift from the     │
│         `session_end` conformance trend + `.supervisor/twin/`   │
│         (read-system-contract.sh), plus the two promotion       │
│         queues (`.supervisor/orientation-proposals/` and        │
│         `.supervisor/agent-memory-proposals/`), plus the        │
│         read-only convention harvest (harvest-conventions.sh).  │
│         All read-only. No mutation.                             │
│                                                                 │
│  Phase 2: REFLECT (Per-target agent invocation)                 │
│     └─> For each target agent, spawn it with a reflection       │
│         prompt + the gathered sources. Agent reads sources +    │
│         its own existing memory in `.claude/agent-memory/`,     │
│         and emits a proposal block. Memory directory is         │
│         opened READ-ONLY; agent must not write.                 │
│                                                                 │
│  Phase 3: AGGREGATE (Compose reflection report)                 │
│     └─> Merge per-agent proposals + collected worker memory     │
│         candidates + distilled LESSONS into a single report     │
│         with the six mandatory sections below.                  │
│                                                                 │
│  Phase 4: APPROVE (Per-item user gate — write-on-Accept)        │
│     └─> User reviews each proposed item and chooses             │
│         Accept / Reject / Edit / Supersede / Retract.           │
│         On Accept, /dreaming writes project-memory facts +      │
│         LESSONS via the repo-root sole writers; CLAUDE.md +     │
│         agent-memory goes through write-agent-memory.sh.        │
│         Pending orientation proposals promote via               │
│         add-orientation.sh (Reject deletes, never writes).      │
│         Pending agent-memory proposals promote via              │
│         write-agent-memory.sh --proposal (same per-item gate).  │
│         Harvested .agent/rules/ proposals take TWO gates —      │
│         Accept (content), then Pre-push confirmation (push);    │
│         only then branch + add-rule.sh --confirm + gh pr        │
│         create. Never a merge. Empty confirmed set = no branch. │
│         Supersede/Retract curate an EXISTING corpus entry       │
│         (composing the store's own supersede/retract verb)      │
│         instead of adding a new one. No auto-write, no          │
│         bulk-accept.                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

1. **Read the N most recent UNCONSUMED session logs + worker summaries + completed/failed briefs + System Twin contract drift** — `/dreaming` obtains the log selection from the probe, which returns the `--sessions N` most recent **unconsumed** session ids (signal-carrying logs not already in the consumed set), newest mtime first:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/curation-status.sh" unconsumed <N>
   ```

   **Select these ids, not "the N most recent files".** Sorting the whole directory by mtime and taking the newest N is the shape that made the backlog unreachable: new sessions are always newer, so a log that fell out of the window could never re-enter it and `pending` stalled (measured: 8 → 3 → 3 → 3 with a window of 5). Taking the newest *unconsumed* ids keeps the recency bias and lets successive runs walk backwards through the tail (8 → 3 → 0). **If that command prints nothing, every signal-carrying log has already been reflected on — say so and stop, rather than silently re-reading the newest N.** (It exits 0 on every path; if the consumed record is unreadable it prints a note on stderr and returns the unfiltered list, so a run still has something to read.) **Keep the selected basenames (minus `.jsonl`) — the mandatory final `record dreaming <session_id>…` call must name exactly these, and it is the only thing that makes the readiness backlog fall.** Do not reconstruct the list at the end from a fresh directory listing: by then newer logs (including this session's own) may have appeared, and naming an unread log would retire it silently. It also reads (read-only) the **N most recent** (by mtime) `.supervisor/worker-summaries/*.md` files and the **N most recent** briefs across `.supervisor/jobs/done/` + `.supervisor/jobs/failed/` — bounded by the same `--sessions N` cap so a repo with many completed jobs does not load them all — since those carry the worker `memory_candidates` and the per-subtask outcomes reflection needs. **Additionally, when System Twin data exists, `/dreaming` reads (read-only) the contract-drift signal**: the `contract_conformance_status` / `contract_violations` trend across the same `session_end` events it already loaded, and/or the per-subsystem contract drift from the twin store under `.supervisor/twin/` via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-system-contract.sh"` (the provenance-gated read-side reader — never the writer). This drift signal is folded into reflection as another input (e.g. "contracts drifting / repeated conformance violations in subsystem X"). It is **strictly read-only and advisory** and entirely **optional** — when no twin data exists (no `contract_conformance_status` on any loaded `session_end`, and no `.supervisor/twin/` store) it is silently skipped and reflection proceeds exactly as before. **One state is NOT the silent-skip case:** if the reader prints `twin_store_status: dark`, contracts are stored but every one failed provenance verification and was withheld, so the drift signal is *missing*, not *empty* — report that (with the reader's `!!` repair line) as a reflection finding instead of skipping, and never route around it by reading `.supervisor/twin/contracts/` directly. **Pending orientation proposals:** `/dreaming` also lists (read-only during GATHER) any proposal files under the gitignored `.supervisor/orientation-proposals/*.md` — per-area orientation-memo proposals written by the Supervisor Phase 4.5 completion tail — and offers each for per-item promotion in Phase 4. **Pending agent-memory proposals:** identically, it lists (read-only) any `.supervisor/agent-memory-proposals/*.md` — the surprise-only proposals agents write per `AGENT_GUIDELINES.md` — and offers each for per-item promotion in Phase 4 (see "Pending agent-memory proposals (promotion queue)" below). Both directories are gitignored, and **an absent directory is the normal empty case, never an error.** **Convention harvest (read-only):** `/dreaming` also runs the read-only distiller

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/harvest-conventions.sh" --session-id "<session_id>"
   ```

   which triages `convention_mismatch` findings from `.supervisor/postmortem/results.jsonl` plus the `.claude/agent-memory/**` corpus into three buckets (`agent-memory` / `rules` / `project-memory`) and prints a bounded, traceable batch of proposed `.agent/rules/` entries with its own coverage / dedupe-rate / scope-fidelity numbers. **Pass the bare session id, NOT a `dreaming:`-prefixed one** — the harvester composes `--source dreaming:<session_id>` itself, so pre-prefixing it would author `dreaming:dreaming:…`. **This runs on the main thread, never inside a reflection spawn** (reflection agents are read-only and must not shell out to it). The script **has no write mode at all** — it never creates a branch, a commit, a PR, or a rule — so this step cannot escalate on its own; delivery is Phase 4's business and takes the two gates. Its exit contract is `0` on every legitimately-empty case, `2` on a usage error and `3` on could-not-examine (absent `jq`, unreadable ledger); **a non-zero harvest is treated as "no batch to offer" and is reported, never fatal** — it does not block reflection, and it is not a gate. All sources are opened read-only. **Empty-input path:** if there is genuinely nothing to reflect on — `.supervisor/logs/` is missing or contains no `*.jsonl` files **and** there are no worker summaries, done/failed briefs, pending orientation proposals, pending agent-memory proposals, or a non-empty harvested rule batch — `/dreaming` exits immediately with the existing single message — `No session logs found in .supervisor/logs/. Run /supervisor first, then re-run /dreaming.` — and writes nothing. (The twin signal alone never makes a repo non-empty; it only enriches reflection when other sources already exist.)
2. **Spawn target agent(s) in reflection mode** — Each target agent (per `--agent`) is invoked with a reflection-mode system prompt. **Model routing (spawn-time):** unless `--full-model` was passed, each reflection Task spawn sets `model: "sonnet"` — the async-analysis default from `docs/ARCHITECTURE_CONTRACTS.md` §Cost Profiles → "Async analysis surfaces" (reflection-mode only; the agents' forward/gating roles are untouched). The prompt instructs the agent to:
   - Read the provided sources and the agent's own existing memory directory under `.claude/agent-memory/`
   - Identify recurring patterns, repeated mistakes, and unstated invariants
   - Distill those into candidate insights
   - **Propose** memory entries and `CLAUDE.md` paragraphs **without writing anything**
3. **Output a structured reflection report** — `/dreaming` aggregates per-agent proposals, collected worker memory candidates, and distilled LESSONS into a single report with the six mandatory sections listed below.
4. **Per-item user approval (write-on-Accept for memory/LESSONS)** — The user is presented with each proposal in turn. The approval mechanism is the harness `AskUserQuestion` tool (or, when unavailable, a numbered list with typed responses): each proposal is displayed with its target and verbatim text and the user picks `Accept`, `Reject`, `Edit`, `Supersede`, or `Retract`. **The exact question payload — per-class option sets, the 4-option cap, option descriptions, and the narrow conditions under which one option may be marked `(Recommended)` — is specified in "Approval Option Contract" below; it is a contract, not a per-run improvisation.** There is no bulk-accept; each item is gated individually. `Accept` / `Reject` / `Edit` are as before (see below). **`Supersede` and `Retract` are curation actions that target an EXISTING corpus entry** (a live LESSONS entry, or — for the orientation promotion queue — a live committed memo) instead of writing a brand-new one; each composes the target store's own curation verb through its sole writer, per-item, human-gated exactly like `Accept`:
   - **`Supersede`** — offered when a proposed LESSON (§6) or promoted orientation memo would replace an existing corpus entry. Instead of a plain `Accept`, the user picks `Supersede` and confirms which existing entry it replaces; `/dreaming` then invokes the target store's `supersede`/`--supersedes` verb (see the §6 and promotion-queue subsections below) rather than a bare add.
   - **`Retract`** — offered on an EXISTING corpus entry that reflection determined is simply wrong, stale, or no longer applicable, with **no replacement**. The user picks `Retract`, confirms, and `/dreaming` invokes the target store's `retract` action through its sole writer. `Retract` never adds anything.
   - Both actions are **per-item and human-gated** exactly like `Accept` — no bulk-supersede, no bulk-retract, and both still route through the store's own sole writer (never a direct file edit by `/dreaming`).

   On `Accept`:
   - **PROJECT_MEMORY facts** (including accepted collected worker candidates) are written by `/dreaming` itself via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-project-memory.sh" --fact "<text>" --source "dreaming:<session_id>" --confirm`.
   - **LESSONS** are written by `/dreaming` itself via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" --category "<cat>" --lesson "<text>" --source "dreaming:<session_id>" --confirm`. Lessons now carry machine-readable freshness metadata — `last_verified` (optional `--last-verified`, defaults to write time) and `confidence` (optional `--confidence`, defaults to `medium`) — appended as a parseable HTML-comment trailer (the existing invocation above is unchanged since both flags are optional with safe defaults). These lessons are read back through the provenance-gated, stale-linting `read-lessons.sh`, which **has a live consumer**: Supervisor Phase 1 ACQUIRE (`agents/supervisor.md`, the "Consult verified lessons" step) runs it as an advisory, read-only, strictly-subordinate-to-CLAUDE.md context read before task selection.
   - **`--confirm` is REQUIRED on both writers above, not optional.** `.supervisor/memory/` is a **committed** store (`.gitignore` carries a `!.supervisor/memory/` negation, and `LESSONS.md` / `PROJECT_MEMORY.md` are tracked files), so both writers sit on the gated side of the committed-vs-gitignored rule in `AGENT_GUIDELINES.md` §"Sole-writer confirm gates". Omitting the flag is a refusal, not a silent write. Do not read "the writer validates the entry" as "the writer is gated" — validation says the entry is well-formed, `--confirm` says a human asked for it to land in the repo's history.
   - **Pass `<text>` / `<cat>` as literal argv values, never by interpolating them into a shell string** — approved proposal text may contain quotes, `$`, backticks, or other shell metacharacters. Supply each as a single argument (the writers slugify `--category`, sanitize `--source`, and treat `--fact`/`--lesson` as opaque text), so a lesson like `He said "run $PATH"` is stored verbatim and cannot break or inject the command.
   - **Orientation-memo proposals** (files under `.supervisor/orientation-proposals/`, written by the Supervisor Phase 4.5 completion tail) are promoted by `/dreaming` itself on per-item Accept via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-orientation.sh" <area-slug> <summary-line> <body-file> --source "dreaming:<session_id>" --confirm` — the committed `.agent/orientation/` store's confirm-gated sole writer. Derive `<area-slug>` from the proposal filename, `<summary-line>` from the proposal's line-2 summary, and `<body-file>` from a temp file holding the proposal body (the header comment is re-stamped by the writer, never copied; optionally forward the header's `areas:` value via `--areas`). **`--source` is REQUIRED in practice, not decorative:** the writer validates the memo BODY + SUMMARY only — never the `head_sha:` header it stamps itself — so a proposal whose prose cites nothing is REFUSED for provenance unless a real `--source` is supplied. Pass the same `dreaming:<session_id>` value already used for the `write-lessons.sh` call above; a refused promotion leaves the proposal file in place for editing. Pass every value as a **literal argv argument, never interpolated into a shell string** — the writer itself REJECTS hostile slugs, over-cap memos, and instruction-injection markers, and a rejected promotion is reported with the proposal file left in place for editing. On a successful promotion the proposal file is **deleted**; on **Reject** the proposal file is deleted **without writing**.
   - **CLAUDE.md** proposals remain **paste-to-apply** — the user (or a follow-up turn) performs those writes; `/dreaming` does not.
   - **`.claude/agent-memory/` proposals are NO LONGER paste-to-apply (v15.33.0).** That store has a sole writer; a hand-applied entry bypasses all five write-time checks, and `MEMORY.md` is writer-owned and regenerated on every write, so a hand-written index is silently replaced. Promote through the writer instead:
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-agent-memory.sh" --proposal <proposal-file> --confirm`
     **The `.supervisor/agent-memory-proposals/` queue is surfaced automatically**, exactly the way the orientation queue below is: GATHER lists the pending `*.md` files, and Phase 4 offers each one for **per-item promotion** labeled **PROMOTE PENDING PROPOSAL** (see "Pending agent-memory proposals (promotion queue)" below for the per-item actions and the file-deletion contract). A human no longer has to list that directory by hand.
   - **Harvested `.agent/rules/` proposals** are **not** written in place. They are delivered as a **pull request**, and they are the one path in this command that takes **two** per-item gates — Accept for the content, then a separate **Pre-push confirmation** for the push. See "Harvested `.agent/rules/` proposals (PR delivery queue)" below for the ordering, which is load-bearing: every gate is collected *before* any branch exists.
   - **Idempotent harness-memory pointer (LESSONS only):** whenever this Accept persists a LESSON (a plain new lesson, or the replacement half of a `Supersede`), `/dreaming` additionally ensures **ONE** idempotent pointer line exists in the repo's Claude-harness memory naming `.supervisor/memory/LESSONS.md` as the durable lessons store — see "Harness-memory pointer" below for the exact contract.

   `Reject` and `Edit` never write (an `Edit` only revises the proposed text, which can then be re-offered for Accept). `Supersede` and `Retract` write ONLY through the target store's own curation verb (see §6 / the promotion-queue subsection below for the exact invocations) — never a direct file edit. Because `/dreaming` runs at the repo root, the sole writers' worktree-guard is satisfied; every writer also enforces its own bounds/provenance, so even an accepted/superseded/retracted item is subject to its caps. There is still **no auto-write** — every persisted, superseded, or retracted item requires an explicit per-item user choice.

   **Applying paste-to-apply items.** This path is for **`CLAUDE.md` proposals only**. Each lists its target path and the verbatim text to write; after `/dreaming` exits, the user — or a follow-up turn in the same session — applies an accepted proposal directly with the `Write` tool (for new files) or `Edit` tool (for in-place additions). **`.claude/agent-memory/` proposals are NOT applied this way** — since v15.33.0 that store has a sole writer and a hand-applied entry bypasses every write-time check; promote it with `write-agent-memory.sh --proposal <file> --confirm` instead. The proposal text is already in the form that should be written, so the apply step is a verbatim paste at the cited path. The per-item review-and-apply pattern keeps the user in the loop and forces them to read each proposal before it lands.

## Reflection-Mode Task Prompt

The agents `/dreaming` spawns (Code Reviewer, Red Team Reviewer, QA Executor) all have system prompts tuned for **forward** work — reviewing diffs, attacking running systems, generating tests. To put them into reflection mode, `/dreaming` MUST pass a task prompt that overrides their default behavior. The prompt below is the canonical template — `/dreaming` constructs an instance of it for each spawned agent and substitutes the placeholders.

```
You are running in REFLECTION MODE for the /dreaming command, not your normal forward-execution mode.

DO NOT review code, attack systems, generate tests, or take any action against the current working tree. Your job for this turn is to look BACKWARD at the supplied session logs and propose durable lessons.

INPUTS (read-only):
- Session logs (the N most recent **unconsumed** /supervisor sessions for this project — NOT necessarily the newest N in absolute terms: sessions already reflected on are excluded, so this list can contain an older log while a more recent, already-reflected one is absent):
{numbered list of absolute paths to .supervisor/logs/<session_id>.jsonl files}
- Worker summaries and completed/failed briefs for the same window:
{numbered list of absolute paths to .supervisor/worker-summaries/*.md and .supervisor/jobs/done/*, .supervisor/jobs/failed/* briefs}
- System Twin contract drift (OPTIONAL — present only when this project uses the System Twin):
{the contract_conformance_status / contract_violations trend across the loaded session_end events, and/or per-subsystem contract drift read-only from .supervisor/twin/ via read-system-contract.sh. ABSENT when no twin data exists — treat its absence as "not reported" and reflect normally.}
- Your own existing persistent memory directory (read-only for this turn):
.claude/agent-memory/loomwright:{agent-id}/

HARD RULES:
- READ-ONLY for this turn. Do NOT call Write, Edit, NotebookEdit, or any Bash command that mutates files, the git index, branches, the working tree, or your own memory directory. /dreaming will refuse to persist anything you propose without explicit per-item user approval — your job is to propose, not to write.
- Stay scoped to the supplied logs and your own existing memory. Do not crawl unrelated parts of the repository.
- Do not run tests, format code, or open the application.

OUTPUT (mandatory six-section report, in this order):

  ## 1. Recurring Patterns
  Concrete patterns you observed across the supplied logs. For each:
  - Name and one-line description
  - Evidence count and citing session IDs (e.g., "3/5 sessions: 2026-05-03, 2026-05-06, 2026-05-09")

  ## 2. Distilled Insights
  Short, falsifiable claims that interpret the patterns. For each:
  - The claim
  - Linked Pattern letter
  - Evidence count
  When the OPTIONAL System Twin contract-drift input is present, fold it in here as
  one more evidence stream — e.g. "contracts drifting / repeated conformance violations
  in subsystem X" (cite the contract_conformance_status trend or the drifting subsystem).
  When it is absent, do not mention it; reflect on the other inputs as before.

  ## 3. Proposed Memory Updates
  Each proposal MUST be labeled "PENDING USER APPROVAL" and include:
  - Target file/tag under .claude/agent-memory/loomwright:{agent-id}/
  - Change type (add / edit / delete)
  - Proposed text (verbatim, ready to paste)
  - Linked Insight number
  - Evidence: N distinct sessions (ids) — copied from that Insight's evidence count
  Do NOT write to the memory directory. Propose only.

  ## 4. Proposed CLAUDE.md Updates
  Each proposal MUST be labeled "PENDING USER APPROVAL" and include:
  - Target section (existing heading or proposed new heading)
  - Proposed text (verbatim, in the same prose style as the surrounding doc)
  - Linked Insight number
  - Evidence: N distinct sessions (ids) — copied from that Insight's evidence count
  A proposal MAY instead be a CURATION candidate — prune (a section no longer earns
  its context cost), merge (two sections restate each other), or supersede (a claim's
  authoritative home moved elsewhere) — labeled the same way, naming the target
  section(s) and, for merge/supersede, the replacement text. Do NOT edit CLAUDE.md.
  Propose only.

  ## 5. Collected Memory Candidates
  Scan the gathered sources for worker WORKER_RESULT.memory_candidates[] strings
  (the optional field workers emit since v14.4.0; workers also echo them into their
  .worker-summary.md). Dedup the collected candidates against the existing project
  memory and against each other. List each UNIQUE candidate verbatim, labeled
  "PENDING USER APPROVAL", with its source session ID / subtask AND an
  "Evidence: N distinct sessions (ids)" line counting how many analyzed sessions
  independently produced it. Do NOT write memory. Propose only.

  ## 6. Proposed LESSONS
  Distilled, CATEGORY-TAGGED lessons, BOUNDED ≤3 active per category. List each as
  "category: <cat> — <lesson text>", labeled "PENDING USER APPROVAL", with a score and
  a Linked Insight number. If a category already holds 3 active lessons, frame the
  proposal as REPLACING the oldest in that category. Do NOT write LESSONS. Propose only.

If a section has no candidates, write "(no proposals — N/M sessions reviewed)" rather than padding. Empty proposals are honest; fabricated ones are a defect.
```

Per-agent customization: `/dreaming` may prepend a one-line role hint (e.g., "Focus on review-finding patterns" for Code Reviewer, "Focus on attack-vector patterns" for Red Team Reviewer, "Focus on test-coverage and infrastructure-discovery patterns" for QA Executor) but MUST NOT remove or weaken any of the HARD RULES above.

## Reflection Report Sections

Every `/dreaming` report **must** include all six of the following sections, in this order:

### 1. Recurring Patterns

Concrete patterns observed across the analyzed sessions: repeated failure modes, repeated review findings, repeated decisions, repeated blockers. Each entry cites the originating session IDs so the user can cross-check.

### 2. Distilled Insights

The interpretation layer: what the recurring patterns *mean*. Each insight is a short, falsifiable claim — e.g., "Workers consistently miss boundary tests when subtasks lack explicit `provides:` entries" — paired with the evidence count. When the **System Twin contract-drift** input is present (the `contract_conformance_status`/`contract_violations` trend from `session_end`, and/or per-subsystem drift read read-only from `.supervisor/twin/`), it is folded in here as an additional evidence stream — e.g. "contract conformance in subsystem X has regressed across the last 3 sessions." This input is read-only and **advisory**, optional, and silently omitted when no twin data exists (backward-compatible with repos that have never run the System Twin).

### 3. Proposed Memory Updates

Per-agent proposed additions, edits, or deletions for `.claude/agent-memory/{agent-id}/`. Each proposal lists:
- Target agent (must be one with `memory: project`)
- Proposed change type (add / edit / delete)
- Target file or tag within the memory directory
- Proposed text (verbatim)
- Justification linked to a Distilled Insight
- **Evidence: N distinct sessions (ids)** — carried down verbatim from that Insight's own evidence count. It is not decoration: it is the field the §3 recommendation rule is computed from (see "Approval Option Contract" below), and a proposal that omits it can never be recommended
- Approval status: **PENDING USER APPROVAL** (always — `/dreaming` does not auto-apply)

### 4. Proposed CLAUDE.md Updates

Proposed additions or revisions to project `CLAUDE.md` (or a sub-file it references). Each proposal lists:
- Target section (existing heading or proposed new heading)
- Proposed text (verbatim, in the same prose style as the surrounding doc)
- Justification linked to a Distilled Insight
- **Evidence: N distinct sessions (ids)** — carried down from that Insight, same role as in §3: it is what the §4-additive recommendation rule reads, and its absence means no recommendation. A **curation** candidate (below) carries it too, but is never recommended regardless
- Approval status: **PENDING USER APPROVAL** (always — `/dreaming` does not auto-apply)

**Curation candidates (prune / merge / supersede) — same section, same gate, no new writer.** Alongside additive proposals, `/dreaming` may also surface a **curation** candidate when reflection determines that CLAUDE.md (or a sub-file it references, e.g. a relocated section in `loomwright/docs/`) has drifted from what a fresh session actually needs. A curation candidate is still just a §4 proposal — labeled **PENDING USER APPROVAL**, applied by the user (or a follow-up turn) via the existing paste-to-apply mechanism, never written by `/dreaming` itself. Three shapes:
- **Prune** — an existing section (or sub-file section) no longer earns its context cost (e.g. it describes a retired behavior, or duplicates something now authoritative elsewhere). The proposal names the section to remove and the justification (linked Insight).
- **Merge** — two sections restate the same fact and should collapse into one. The proposal names both sections, which one survives, and the merged text (verbatim, ready to paste).
- **Supersede** — a claim's authoritative home has moved (e.g. a count or version claim that should now read "see `plugin.json`" instead of restating a number — see `AGENT_GUIDELINES.md` §"Claim Duplication Rule"). The proposal names the stale claim, its new authoritative source, and the replacement text.

Each curation proposal carries the same **Accept / Reject / Edit** gate as every other §4 item (there is no CLAUDE.md writer, so `Supersede`/`Retract` as *actions* — the composed store-verb calls used elsewhere in this command for LESSONS/orientation memos — do not apply here; a curation candidate that *recommends* a prune/merge/supersede is still just accepted, rejected, or edited as **prose to paste**). This is UX parity with the v15.14.0 store-curation shape (per-item gating, never bulk) — not a claim that CLAUDE.md gained a mechanized sole writer; it explicitly did not (see the Read-Only Contract below).

### 5. Collected Memory Candidates

The worker-proposed durable facts harvested from the gathered sources. `/dreaming` collects candidates from two concrete, unambiguous shapes: (a) the `memory_candidates:` array inside a `WORKER_RESULT` block in the session logs, and (b) a `## memory_candidates` section in a `.worker-summary.md` file — one `- ` bullet per candidate string (the format workers write into the summary). Workers have emitted the optional `WORKER_RESULT.memory_candidates[]` field since v14.4.0 and echo the same strings under the `## memory_candidates` summary heading, which is why both shapes are scanned. The collected strings are **deduped** against the existing project memory — `/dreaming` reads the verified facts via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-project-memory.sh"` first and drops any candidate already present (and dedups duplicates among the candidates themselves). Each surviving unique candidate is listed:
- Candidate text (verbatim, one line)
- Source session ID / subtask it came from
- **Evidence: N distinct sessions (ids)** — how many of the analyzed sessions independently produced this candidate (1 for a single-session candidate, which is the common case). Same role as in §3: it is what the recommendation rule reads, and its absence means no recommendation
- Approval status: **PENDING USER APPROVAL** (always)

On Accept, a candidate is written as a PROJECT_MEMORY fact via `write-project-memory.sh` (see Phase 4 / APPROVE).

### 6. Proposed LESSONS

Distilled, **category-tagged** lessons, **bounded ≤3 active per category**. Before proposing, `/dreaming` reads the existing `.supervisor/memory/LESSONS.md` to respect the bound; if a category already holds 3 active lessons, the proposal is framed as **replacing the oldest** lesson in that category (the bound is also enforced independently by `write-lessons.sh` at write time). Each lesson is scored by a simple heuristic — **recall-frequency × outcome × diversity** — where *recall-frequency* is how often the underlying pattern recurred across the analyzed sources, *outcome* weights lessons tied to failures/regressions higher than cosmetic ones, and *diversity* rewards patterns seen across multiple distinct subtasks/sessions rather than one noisy run; the product orders which lessons are worth the scarce ≤3 slots. Each proposal lists:
- Category tag and lesson text (verbatim)
- Heuristic score (and, when a category is full, which existing lesson it would replace)
- Justification linked to a Distilled Insight
- Approval status: **PENDING USER APPROVAL** (always)

On Accept, a lesson is written via `write-lessons.sh` (see Phase 4 / APPROVE).

#### Curating existing LESSONS (Supersede / Retract)

Reflection may also surface that an **existing** `LESSONS.md` entry (not just a newly-distilled §6 candidate) is now wrong, contradicted by a more recent pattern, or simply stale. When it does, `/dreaming` offers that existing entry for **`Supersede`** or **`Retract`** alongside the normal §6 proposals — same per-item `AskUserQuestion` gate, no bulk action:

- **`Supersede`** — offered when a §6 proposal is framed as replacing a *specific* existing lesson (not merely "the oldest in a full category" — see the ≤3-bound note above, which is a capacity eviction, distinct from this explicit curation action). On the user picking `Supersede` (instead of a plain `Accept`), `/dreaming` invokes the target's own `supersede` verb, composing PRE-CHECK → RETRACT → ADD in one call (this ordering is enforced inside `write-lessons.sh`, never by `/dreaming` sequencing two separate calls):

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" supersede "<category>" "<old lesson text>" \
    --replacement "<new lesson text>" --source "dreaming:<session_id>" --confirm
  ```

  `--replacement` is **required** (a supersede without one is indistinguishable from a `Retract`). On success the new lesson carries `supersedes=<hash-of-old>` in its trailer and the old entry is gone; on a pre-check failure (target absent or not chain-trusted) the verb fails loud (exit 4) and `LESSONS.md` is left byte-identical — `/dreaming` surfaces that failure to the user rather than silently dropping the item.

- **`Retract`** — offered on an existing lesson reflection determined is simply wrong or no longer applicable, **with no replacement**. On the user picking `Retract`, `/dreaming` invokes the already-shipped retract verb:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" retract "<category>" "<lesson text>" --source "dreaming:<session_id>" --confirm
  ```

  This is the same `retract` flow `write-lessons.sh` has shipped since the curation/anti-rot work landed (tombstoned via provenance, entry line removed, `read-lessons.sh` labels it `RETRACTED` if it's ever inspected historically) — `/dreaming` is simply a new per-item-gated CALLER of it, not a reimplementation.

Both actions pass `<category>` / `<lesson text>` / `<new lesson text>` as **literal argv values**, never interpolated into a shell string — matching the argv discipline already required for §6 Accept (see Phase 4 / APPROVE).

### Pending orientation proposals (promotion queue)

When the gitignored `.supervisor/orientation-proposals/` directory holds proposal `.md` files (written by the Supervisor Phase 4.5 completion tail — see `skills/self-heal-advisory/SKILL.md` Part 2), `/dreaming` appends a promotion queue after the six report sections, listing each proposal's area slug, one-line summary, and file path, labeled **PENDING USER APPROVAL**. This is a promotion queue, not a seventh mandatory report section — it appears only when proposals exist. Per-item **Accept** promotes the proposal into the committed `.agent/orientation/` store via `add-orientation.sh … --confirm` and deletes the promoted proposal file; **Reject** deletes the proposal file without writing; **Edit** revises the proposal text before a re-offered Accept (see Phase 4 / APPROVE for the exact invocation and argv discipline).

**Supersede / Retract for existing committed memos.** When a pending proposal's area-slug logically replaces a *different*, already-committed memo (e.g. an area was renamed or split), or when reflection independently determines an existing committed memo is stale with no proposal replacing it, `/dreaming` offers the same two curation actions on the existing `.agent/orientation/<slug>.md` entry, per-item-gated exactly like the proposal actions above:

- **`Supersede`** — promotes the pending proposal as the declared replacement of an existing memo (rather than a plain new/updated memo at its own slug):

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-orientation.sh" --supersedes \
    --target "<old-area-slug>" --replacement "<new-area-slug>" --reason "<text>" --confirm
  ```

  Both `<old-area-slug>` and `<new-area-slug>` must already exist as parseable memos (the replacement is normally the just-promoted proposal, so promote it first via the plain create path, then supersede). `--replacement` is required; the target memo file itself is left in place — `read-orientation.sh` is what hides a superseded memo from output (single-hop, non-transitive), not deletion.

- **`Retract`** — removes an existing committed memo outright, with no replacement:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-orientation.sh" --retract \
    --target "<area-slug>" --reason "<text>" --confirm
  ```

  There is no in-store home for the reason (no provenance sidecar for this store — adding one would violate the curation freeze), so the writer **prints** a one-line provenance record to stdout; the commit that lands the removal is the durable record. `/dreaming` surfaces that printed line to the user as confirmation.

### Pending agent-memory proposals (promotion queue)

When the gitignored `.supervisor/agent-memory-proposals/` directory holds proposal `.md` files (the surprise-only proposals agents are instructed to write rather than editing `.claude/agent-memory/` by hand), `/dreaming` appends a second promotion queue after the six report sections, listing each proposal's `agent:` slug, `name:` entry slug, one-line `description:`, and file path, labeled **PROMOTE PENDING PROPOSAL**. Like the orientation queue, this is a promotion queue and **not** a seventh mandatory report section — it appears only when proposals exist, and an **absent directory is the normal empty case** (it has never been populated in this repo), never an error.

Per item, human-gated, no bulk action:

- **Accept** — promotes the proposal into the store through its sole writer:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-agent-memory.sh" --proposal <proposal-file> --confirm
  ```

  The proposal file carries its own routing in frontmatter (`agent:` / `name:` / `description:`, optionally `title:` / `source:` / `type:`), so **pass the path and nothing else** — the writer refuses positional arguments alongside `--proposal`. It exits `0` on a verified write, `1` on a REFUSAL it examined (validation, hostile marker, cap, bad slug), `2` on could-not-examine, and `3` from a git worktree. **On success `/dreaming` deletes the promoted proposal file** — the writer does not delete it, so this deletion is `/dreaming`'s own step, exactly as for the orientation queue. **On any non-zero exit the proposal file is left in place** and the refusal is surfaced to the user for editing; a refused promotion is never silently dropped.
- **Reject** — deletes the proposal file **without writing**. The committed store is untouched.
- **Edit** — revises the proposal text, writes nothing, and re-offers it for Accept.

This closes the gap `write-agent-memory.sh` names in its own header. Nothing here creates a branch: agent-memory is an in-place store with a sole writer, and only the `.agent/rules/` queue below has a PR path.

### Harvested `.agent/rules/` proposals (PR delivery queue)

When the GATHER-time `harvest-conventions.sh` run produced a non-empty rule batch, `/dreaming` appends a third queue, showing for each proposed rule its category, statement, `enforcement`, `check` (always `null` — the harvester never synthesises shell into a rule, and rules stay **DATA, advisory, and subordinate to `CLAUDE.md`**; this adds no new gate), the derived `applies_to`, the **finding ids that motivated it**, its per-rule scope fidelity, and the exact `add-rule.sh` invocation the harvester composed. The batch's `coverage` / `dedupe rate` / `scope fidelity` / `store dedupe` numbers are shown with it — **and scope fidelity is quoted as BOTH figures or neither** (the checkable one *and* the lower all-motivating-findings one), because the whole point of the two-number design is that the first figure alone flatters the derivation by dropping its own unfalsifiable evidence (see `docs/HARVEST_DRYRUN_SAMPLE.md` §"Reviewer's note on the numbers").

**An ALREADY-COVERED deferral is never offered for Accept.** The harvester now dedupes every proposal against the live `.agent/rules/` store before composing it, and a proposal whose claim a stored rule already makes is printed as a `DEFERRED — ALREADY COVERED` block naming that rule's id and the measured overlap, with no `invocation:` line. Those blocks are **context for the reader, not queue items**: `/dreaming` is the only consumer of this batch, and Accepting one would put two differently-worded copies of one convention in one file — the duplication the store's own cross-surface rule prohibits. Offer per-item Accept for the **numbered** proposals only, and relay each deferral as "already covered by `<rule id>`" so the human can see what the store answered rather than being asked again. The check is **lexical and advisory** (a distinctive-term overlap, not a semantic one), so it can miss a duplicate written in wholly different vocabulary — treat a clean dedupe as "no duplicate this pass could see", never as a guarantee. Its numbers belong with the others when you quote them: `store dedupe`, `already covered by the live store`, and the `COMBINED convention coverage` figure — the last one matters because a low proposed-rule `coverage` beside a high combined figure means the store is already right, not that the harvest failed.

**A DISTILLATION FAILURE batch is not offered at all.** When the run reported **DISTILLATION FAILURE** (a batch approaching one rule per finding), `/dreaming` surfaces that verdict **above** the batch and **stops there for this queue**: no per-item Accept question, no Pre-push confirmation, no confirmed set, no branch, no PR. The engine's own output says `DO NOT DELIVER THIS BATCH — raise --min-support or merge themes first`, and its only consumer must not quietly downgrade the strongest verdict it can emit to a footnote above an offer — a reader of one surface would otherwise get a different contract than a reader of the other. Report the verdict, relay the remedy verbatim, and move on.

**This refusal is command flow, not a new gate**, and the distinction is load-bearing: it declines to *offer* one queue in one command. Reflection continues, the other promotion queues are unaffected, the run still exits 0, nothing is blocked anywhere else in the plugin, and rules remain DATA — advisory and subordinate to `CLAUDE.md`. A user who disagrees re-runs the harvest with a higher `--min-support`, which is the script's own stated remedy.

**Two distinct gates, and the ordering is the safety property.** Collect *both* gates for *every* item before touching git:

1. **Accept / Reject / Edit (per item)** — the ordinary content gate: "is this rule's statement and scope right?". Accepting **writes nothing** and creates nothing; it only marks the proposal as *content-approved*. `Reject` and `Edit` write nothing and never reach the branch, preserving the same per-item guarantee every other destination in this command already has.
2. **Pre-push confirmation (per item, only for content-approved rules)** — a separate, explicit question: "**push this rule to the remote and open a PR?**". This is *not* implied by Accept, and Accept is not implied by it. Only rules that clear **both** enter the *confirmed set*. Answering no to the Pre-push confirmation leaves that rule unwritten and unpushed, with no other effect. **Default to NOT pushing. If the answer is ambiguous, treat it as no** — the item stays out of the confirmed set, exactly as `/setup rules` treats an ambiguous seed Offer as Cancel (`commands/setup.md`, the rules-module Offer). This gate is the safety property the whole feature is described by, and a gate that resolves an unclear answer *toward* the remote-affecting action is not a gate. Ambiguity is a reason to ask again or to skip the item, never a reason to push; only an unambiguous yes advances it. For the same reason **neither rules gate may present a `(Recommended)` marker on the push-ward option** — see "The one exclusion that is load-bearing" under "Approval Option Contract" below.

Only after every item has passed through both gates does `/dreaming` look at the confirmed set:

- **Confirmed set empty** (nothing accepted, or nothing pre-push-confirmed) → **stop. No branch, no commit, no push, no PR** — and say so in the run report. There is no half-created branch to clean up because no git command ran at all.
- **Confirmed set non-empty** → run the delivery sequence below, once, for the whole confirmed set.

**Delivery sequence (runs at the repo root, on the main thread, never from a worktree):**

1. **Pre-flight, all FOUR of which abort delivery cleanly rather than proceeding:** `git status --porcelain -- .agent/rules` must be empty (otherwise `/dreaming` would commit edits it did not author — report and stop); the current branch is recorded so it can be restored; `gh` must be authenticated; and **HEAD must already be contained in the base branch** — resolved here, before any branch exists:

   ```bash
   BASE="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"   # empty/failed ⇒ abort
   git fetch --quiet origin "$BASE" || true                                   # freshness; failure is tolerated, see below
   git merge-base --is-ancestor HEAD "origin/$BASE"                           # non-zero ⇒ abort delivery
   ```

   **Resolve the base branch here, not at `gh pr create` time, and never assume `main`** — it is per-repo, and the *later* steps need the value the pre-flight actually tested. Step 5 uses this same `$BASE`; it does not re-resolve it. An empty or failed resolution aborts: a PR opened against a guessed base is a worse outcome than no PR.

   **Why the containment check exists, and why "the commit carries rules only" does not already cover it.** A pull request presents the **branch-versus-base diff, not the commit**. A clean, path-staged, rules-only commit sitting on top of a branch that carries commits the base does not have still opens a PR listing *every one of those commits and their files* — the rules-only claim about the commit stays true while the PR is full of unrelated changes. Note the direction carefully: **being *ahead of* (descended from) the base is the FAILING case**, not the passing one; the delivery branch is safe only when HEAD is *at* the base or an ancestor of it, which is exactly what `--is-ancestor HEAD "origin/$BASE"` tests. This is the repo's own documented stale-branch class — the incident that motivated Supervisor's Phase 1.5 PRE-FLIGHT SYNC and `/autonomous`'s EVALUATE PR-base verification (see `CLAUDE.md` §"Common Pitfalls" → the stale-branch trap). Neither human gate covers it: **Accept authorises content and Pre-push authorises the push; neither one reads the diff the PR will actually contain.**

   **Abort, rather than silently branching from `origin/$BASE`.** The abort message names the base, says HEAD is not contained in it, and tells the user what to do: re-run `/dreaming` from the base branch, or check the base out first. Branching from `origin/$BASE` instead would be more *useful* and less *honest*: it discards where the user was standing without asking, and it breaks step 2's deliberate "from the current HEAD, so no working-tree file changes on checkout" property — the cleanliness pre-flight is scoped to `.agent/rules` only, so an unrelated dirty file that differs between HEAD and the base would make that checkout fail (or carry local edits across) *after* the pre-flight had already passed, which is precisely the after-the-gate failure shape step 2's branch-name slugging note exists to avoid. Aborting is the conservative choice and matches this command's never-surprise posture; every gate here resolves an unclear situation *away* from the remote-affecting action.

   **Freshness, stated rather than assumed.** The fetch is best-effort: if it fails (offline, no remote), the check still runs against the local `origin/$BASE` ref, and that is acceptable **in this direction only** — a stale remote-tracking ref can only be *behind* the true one, and a ref that is behind makes this test **stricter**, never looser: if HEAD is an ancestor of a stale `origin/$BASE`, it is also an ancestor of everything that ref later grew into. The failure mode of staleness is therefore a spurious abort, never a spurious pass. A **missing** `origin/$BASE` ref is not a pass either — `--is-ancestor` fails, and delivery aborts.

   Nothing has changed yet at this point: an abort in this step leaves no branch, no commit and no checkout to undo (the fetch touches only remote-tracking refs), so there is nothing to clean up and step 6's `git checkout -` is not needed.
2. `git checkout -b dreaming/rules-<session_id>` from the **current HEAD**, so no working-tree file changes on checkout. **Slug `<session_id>` to `[A-Za-z0-9._-]` for the branch name** (replacing anything else with `-`): a session id is a log basename and is not guaranteed to be a legal git ref, and `git checkout -b` on an illegal name fails *after* the pre-flight has already passed. The `--source` passed to `add-rule.sh` still carries the **unslugged** `dreaming:<session_id>`, so provenance stays exact. **If that branch already exists (locally or on the remote), abort and report it** — `/dreaming` never force-creates, never resets, and never force-pushes. Re-running `/dreaming` in a new session yields a new session id and therefore a new branch; re-running it in the *same* session after a delivery is a no-op that reports the existing branch.
3. For each rule in the confirmed set, run the invocation the harvester already printed, **with `--confirm` appended and the stdin redirection kept**:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh" --category '<cat>' --statement '<text>' \
     --enforcement advisory --applies-to '<glob>' [--applies-to '<glob>' …] \
     --source 'dreaming:<session_id>' --confirm < /dev/null
   ```

   The `< /dev/null` stays even with `--confirm`: it costs nothing and it means **no writer call on this path can ever prompt at your terminal**. Pass every value as a **literal argv argument, never interpolated into a shell string** — the same argv discipline the other writers require. `add-rule.sh` is the store's confirm-gated sole writer, so its category containment, `applies_to` validation, array-only parse-gate, atomic write and read-back verify all apply. **A writer refusal is not fatal to the batch**: report it, skip that rule, and continue with the rest.
4. `git add .agent/rules` — **explicitly scoped, never `git add -A`** — then commit. If step 3 refused every rule, there is nothing staged: abort, restore the original branch, delete the empty local branch, and report.
5. `git push -u origin dreaming/rules-<session_id>`, then open the PR against the **`$BASE` resolved and tested in step 1** (never re-resolved here, and never assumed to be `main`):

   ```bash
   gh pr create --base "$BASE" --head dreaming/rules-<session_id> \
     --title 'dreaming: <N> harvested convention rule(s)' \
     --body '<harvest numbers (coverage / dedupe rate / BOTH scope-fidelity figures) + the motivating finding ids>'
   ```

   **`--title` and `--body` are part of the literal, not prose.** Non-interactively `gh pr create` errors without them — and it errors **after the push has already succeeded**, landing in exactly the "a pushed branch with no PR" state the paragraph below names as a failure mode. Pass both as literal argv values (same argv discipline as every writer call above); use `--body-file <path>` if the body is long enough to be awkward to quote.
6. `git checkout -` to restore the branch you started on, so `/dreaming` leaves the tree where it found it.
7. Report the PR URL in the run report. **`/dreaming` never merges the PR it opens** — it never runs `gh pr merge --squash` or any other merge verb, and the plugin's single sanctioned merge executor is unchanged by this command. Opening the PR is terminal for `/dreaming`; a human reviews and merges.

**If a step fails, restore the original branch before reporting, then say what state it left behind rather than retrying.** Step 6's `git checkout -` is only reached on the success path, so a failure after step 2 would otherwise leave you standing on the delivery branch; run it on the failure path too. The commits stay on the delivery branch — that is what makes them inspectable — and only the checkout is undone. A failed push leaves a *local* branch only — report its name so it can be inspected or deleted. A failed `gh pr create` after a successful push leaves a *pushed* branch with no PR — report the branch name so the PR can be opened by hand. `/dreaming` does not retry, does not force, and does not clean up a branch that already carries commits.

### Harness-memory pointer (on LESSONS Accept)

Whenever a per-item `Accept` (or the replacement half of a `Supersede`) persists a LESSON via `write-lessons.sh`, `/dreaming` additionally ensures **exactly ONE** idempotent pointer line exists in the repo's Claude-harness memory (the harness's own `MEMORY.md`/memory-index surface under `.claude/`), naming `.supervisor/memory/LESSONS.md` as the durable, machine-readable lessons store — for example, a line such as:

```
- [Verified project LESSONS](../../.supervisor/memory/LESSONS.md) — machine-readable, provenance-gated lessons written via /dreaming; read back by read-lessons.sh.
```

**This is a signpost, not a sync.** `/dreaming` is NOT copying lesson content into harness memory, NOT keeping the two in lockstep beyond this one line, and NOT writing one pointer line per lesson — it is a single, idempotent "look here" breadcrumb for the harness's own memory system, written once per repo and left alone on every subsequent Accept once it already exists (a plain string-presence check before writing, so re-running `/dreaming` many times never duplicates the line).

**Where and when this runs is load-bearing, not incidental:**

- It is documented here as executing **at `/dreaming` runtime, from the repo root** — `/dreaming` is an inline main-thread command (never Task-spawned into a worker), so it always runs at the repo root where `.claude/` actually exists and is writable.
- It must **never** be attempted from a worker worktree. Most of `.claude/` is **gitignored** — and the part that is not (`.claude/agent-memory/`, made committable by `/setup memory` since v15.25.0) is *still* the wrong target from a worktree, because the harness reads the store from the **repo root's** path. Either way a worktree's copy of it (if any) is not the real directory the user's harness reads, and a write there would be silently lost the moment `git worktree remove` runs. (Stated this way deliberately: the earlier phrasing rested on the unqualified claim that `.claude/` is gitignored, which stopped being true once the negation block landed — the conclusion survives, the old reason does not.) This is exactly the hazard `write-lessons.sh` itself guards against for `LESSONS.md`: it **hard-refuses to run from a git worktree, exiting 3** (see its own worktree-guard, closing red-team F1) — the harness-pointer write inherits the identical rationale even though it targets a different file, and `/dreaming`'s repo-root-only execution model is what keeps it consistent with that guard rather than fighting it.
- Because `/dreaming` never runs from a worktree in the first place, there is no separate flag or check needed here beyond stating the invariant plainly: this pointer write is a repo-root-only operation, full stop.

### Empty-state suppression

If, after dedup against existing project memory and after bounding LESSONS per category, there are **no new candidates and no new lessons**, `/dreaming` says so in a single line (e.g., "No new memory candidates or lessons after dedup/bounding — nothing to propose.") and **writes nothing**. This keeps reports rare and actionable rather than padding every run with already-known facts.

### APPLY deferral (v14.5.0 scope)

`/dreaming` v14.5.0 closes the **collect → distill → persist** loop only. **Reading LESSONS back into planning/execution** — injecting accepted lessons at Launch Pad / Supervisor decision time so they actually steer future runs — is intentionally **deferred to a follow-up**. v14.5.0 makes lessons durable and human-approved; wiring them into the forward pipeline is out of scope here.

## Approval Option Contract

Every per-item gate in this command is asked with `AskUserQuestion`, and this section is the authoritative shape of that call. Before it existed the command named only the *verbs* a user picks (`Accept` / `Reject` / `Edit` / `Supersede` / `Retract`) and never the payload, so labels, descriptions, order, and whether anything was recommended were improvised per run — two runs over the same proposal could present it differently, and **nothing was ever recommended even for the classes whose report entries already carry the evidence to justify one**. Every other `AskUserQuestion` caller in this plugin specifies its payload (see `commands/setup.md`, the observability / memory / rules module questions); this brings `/dreaming` in line.

### Payload shape (all gates)

- `multiSelect: false` — every gate is per-item and single-choice. There is no bulk-accept anywhere in this command, and a multi-select gate would be one.
- `header` — ≤12 chars naming the item class: `Memory` (§3 / §5), `CLAUDE.md` (§4), `Lesson` (§6), `Orientation`, `Rule`, `Push`.
- `question` — names the **target store** and the action, so the user can tell a paste-to-apply proposal from a sole-writer write without scrolling back to the report.
- `options` — from the fixed per-class sets below. **`AskUserQuestion` accepts at most 4 options**; the harness appends its own `Other` beyond them, so a fifth explicit option is an invalid call. The five verbs are consequently **never offered together**: `Supersede` and `Retract` act on an *existing* corpus entry and are mutually exclusive with the new-proposal set. That has always been true in practice — this states it as a constraint instead of leaving it to luck.
- Every option carries a one-line `description` saying what the choice does **mechanically** (which writer runs with which flags, or that nothing is written) — never a restatement of its label.

### Per-class option sets (fixed; in this order unless a recommendation reorders them)

| Item class | Options |
|---|---|
| §3 agent-memory proposal · §5 collected candidate · §4 additive CLAUDE.md proposal · orientation queue · agent-memory queue | `Accept` · `Reject` · `Edit` |
| §4 curation candidate (prune / merge / supersede as prose) | `Accept` · `Reject` · `Edit` |
| §6 new lesson (category not full) | `Accept` · `Reject` · `Edit` |
| §6 new lesson, category **full** — capacity eviction (plain `Accept`; `write-lessons.sh` enforces the ≤3 bound at write time and evicts the oldest). Distinct from the row below, per "Curating existing LESSONS" above | `Accept` · `Reject` · `Edit` |
| §6 proposal replacing a *specific* named lesson (explicit `Supersede`) | `Supersede` · `Reject` · `Edit` |
| existing corpus entry offered for curation (a live LESSON or committed memo) | `Retract` · `Keep as-is` · `Supersede instead` |
| harvested rule — gate 1 (content) | `Accept` · `Reject` · `Edit` |
| harvested rule — gate 2 (Pre-push confirmation) | `Do not push` · `Push and open a PR` |

Do not grow a set. A new destination folds into an existing row or gets its own row here.

**Having a row is not the same as being offered.** Two harvested-rule cases are never asked at all, and this table does not override either: a batch the harvester marked **DISTILLATION FAILURE** is not offered item-by-item (see that subsection above), and a proposal printed as a **`DEFERRED — ALREADY COVERED`** block is context for the reader, not a queue item — it carries no `invocation:` line and Accepting one would duplicate a convention the live `.agent/rules/` store already states. Gate 1's row applies to the **numbered** proposals only.

### Recommendation

When — and **only** when — one of the rules below fires, the recommended option is moved to **first position** and ` (Recommended)` is appended to its label (the harness convention). Its `description` MUST additionally state the **basis** in one clause — e.g. "3 sessions corroborate" — so the nudge is falsifiable against the report printed above it. **A recommendation with no citable basis in that report is a defect**, not a style lapse: an unfalsifiable nudge on a write gate is how a per-item gate degrades into a rubber stamp.

| Item class | Recommend `Accept` iff | Otherwise |
|---|---|---|
| §3 agent-memory proposal | the linked Distilled Insight's evidence spans **≥2 distinct sessions**. (No dedupe clause: §3 targets `.claude/agent-memory/`, which is never deduped against project memory — that step is §5's alone) | abstain |
| §5 collected candidate | evidence spans **≥2 distinct sessions**, **and** it survived the §5 dedupe against existing project memory | abstain |
| §4 additive proposal | the linked Distilled Insight's evidence spans **≥2 distinct sessions**, read from §4's own `Evidence:` field | abstain |
| §4 curation candidate (prune / merge / supersede) | **never** — a curation candidate rewrites or removes prose the user wrote; the judgment is theirs | abstain |
| §6 new lesson, category **not** full | evidence spans ≥2 distinct sessions/subtasks **and** it is the highest-scoring §6 proposal for its category in this batch | abstain |
| §6 lesson displacing an existing entry (category full, or an explicit `Supersede`) | **never** — the displacement is a judgment about the *existing* corpus, which reflection saw less of than the user did | abstain |
| existing entry offered for `Retract` | reflection found an observation that **contradicts** the entry (cite it). **Staleness or mere disuse is never a basis** | abstain |
| orientation / agent-memory promotion queue | **never** — a queued proposal is a single-run artifact written by one session's completion tail, so no cross-session corroboration exists for it to cite, and this contract does not compute one. Abstaining is the honest reading, not a gap to be filled later | abstain |
| harvested rule — **both** gates | **never** (see the exclusion below) | abstain |

**Abstain is the default and it is not a failure.** When no rule fires, emit the class's option set in its neutral order above with **no** `(Recommended)` marker anywhere. A run in which nothing is recommended is the expected shape for a thin window; manufacturing a recommendation to fill the slot is the failure mode this table exists to prevent.

### The one exclusion that is load-bearing

**Neither harvested-rule gate may ever carry a recommendation *toward* the remote-affecting action.** Gate 2's stated contract is *default to NOT pushing; an ambiguous answer is a no* (see "Two distinct gates, and the ordering is the safety property" above) — a `(Recommended)` on `Push and open a PR` would resolve a safety gate toward the action it exists to slow down. Gate 1 is excluded too, for a different reason: the whole point of the batch's two scope-fidelity figures is that the user reads **both**, and a recommendation substitutes for that reading. A recommendation on `Do not push` is the only marker either gate may carry, and it is optional — the safe direction, never the unsafe one.

## Read-Only Contract

`/dreaming` operates under a **read-only-until-Accept contract** that is enforced end-to-end:

- **Code is read-only.** `/dreaming` does not modify, create, or delete source files. It does not run formatters, linters, codegen, or any tool that mutates the working tree. It never creates a worktree.
- **Git and the remote have exactly ONE reachable action, behind two gates.** `/dreaming` creates a branch, a commit, a push and a pull request **only** for a harvested `.agent/rules/` batch, and only for proposals that cleared **both** the per-item Accept **and** the separate per-item **Pre-push confirmation**. That commit contains `.agent/rules/*.json` and nothing else — staged by path, never `git add -A` — and delivery is refused outright if `.agent/rules/` already carries uncommitted changes. **A rules-only commit is not by itself a rules-only pull request:** a PR presents the branch-versus-base diff, not the commit, so delivery is *additionally* refused unless HEAD is already contained in `origin/<base>` (at it, or an ancestor of it) — otherwise a clean commit cut from an unrelated feature branch would open a PR carrying that branch's commits too. See the delivery sequence's step-1 pre-flight. If the confirmed set is empty, **no git command runs at all**. `/dreaming` **never merges**, never force-pushes, and never resets or deletes a branch that carries commits.
- **Agent memory is read-only during reflection.** `.claude/agent-memory/` is opened only for reading. The reflection-mode prompt explicitly forbids writes to that directory. Reflection agents that would normally append to memory must instead emit proposals into the report.
- **`CLAUDE.md` is read-only.** The project `CLAUDE.md` (and any files it references) are opened only for reading.
- **`/dreaming` only PROPOSES until you Accept.** Every memory, LESSONS, and `CLAUDE.md` update appears in the report as a proposal labeled **PENDING USER APPROVAL**. Nothing is written during GATHER, REFLECT, or AGGREGATE.
- **User must explicitly approve each proposed item.** Approval is **per-item**, not bulk. The user chooses Accept, Reject, Edit, Supersede, or Retract for each proposal/entry. Acceptance (or a Supersede/Retract selection) is required before any persistence. There is **no auto-write**.
- **On Accept, `/dreaming` writes only PROJECT_MEMORY facts, LESSONS, and orientation-memo promotions — and only through the sole writers.** Accepted facts go through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-project-memory.sh" --fact "<text>" --source "dreaming:<session_id>" --confirm`; accepted lessons through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-lessons.sh" --category "<cat>" --lesson "<text>" --source "dreaming:<session_id>" --confirm`; accepted orientation proposals through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-orientation.sh" <area-slug> <summary-line> <body-file> --source "dreaming:<session_id>" --confirm` (the committed `.agent/orientation/` store's confirm-gated sole writer; `--source` is required in practice — see the promotion step above — because the writer validates the memo body and summary, never the `head_sha:` header it stamps itself, so a proposal whose prose cites nothing is refused without it; the promoted proposal file is then deleted). `/dreaming` runs at the repo root, satisfying the sole writers' worktree-guard. On a LESSON Accept/Supersede, `/dreaming` also ensures the idempotent harness-memory pointer line exists (see "Harness-memory pointer" above) — repo-root-only, never from a worktree. Accepted **agent-memory proposals** are promoted through `write-agent-memory.sh --proposal <file> --confirm` (that store's sole writer), and accepted **`.agent/rules/` proposals** through `add-rule.sh … --confirm < /dev/null` on the delivery branch — the latter additionally requiring the Pre-push confirmation. Reject/Edit never writes (a Reject on an orientation or agent-memory proposal deletes the proposal file — the committed store is untouched).
- **`Supersede` and `Retract` write only through the target store's own curation verb.** A `Supersede` on an existing LESSON invokes `write-lessons.sh supersede <category> <lesson-text> --replacement "<new text>" --source "dreaming:<session_id>" --confirm`; a `Retract` invokes `write-lessons.sh retract <category> <lesson-text> --source "dreaming:<session_id>" --confirm`. The equivalent orientation-store actions invoke `add-orientation.sh --supersedes --target <old-slug> --replacement <new-slug> --reason "<text>" --confirm` and `add-orientation.sh --retract --target <slug> --reason "<text>" --confirm`. Both are per-item, human-gated, and never bulk (see "Curating existing LESSONS" and the promotion-queue subsection above).
- **`CLAUDE.md` proposals stay paste-to-apply.** `/dreaming` never writes those directly — CLAUDE.md is not the sole writers' domain; `.claude/agent-memory/` HAS been the sole writers' domain since v15.33.0 and must be promoted via `write-agent-memory.sh --proposal … --confirm`, never hand-applied; after approval the user (or a follow-up turn) performs those writes.
- **Aborting before Accept is always safe — and for the rules PR, before the Pre-push confirmation.** Until you Accept, Supersede, or Retract an item, the command has written nothing; cancelling at any point during GATHER/REFLECT/AGGREGATE — including mid-report — leaves the project, agent memory, LESSONS, and `CLAUDE.md` exactly as they were when `/dreaming` started. For a harvested rule the safe window extends further: **Accept alone changes nothing**, because every gate is collected before any git command runs, so aborting between the Accept and the Pre-push confirmation leaves no branch, no commit, and no PR.

This contract is non-negotiable: a `/dreaming` invocation that mutates code, agent memory, LESSONS, the `.agent/orientation/` store, the `.agent/rules/` store, or `CLAUDE.md` **without an explicit per-item Accept** — or that creates a branch, pushes, or opens a PR **without the separate per-item Pre-push confirmation**, or that merges anything, or that auto-writes, bulk-accepts, or writes memory/LESSONS/orientation memos/rules by any path other than their sole writers — is a defect, not a feature request.

### Enforcement boundary (honest disclosure)

The agents `/dreaming` spawns in reflection mode — Code Reviewer, Red Team Reviewer, QA Executor — have **full write tools** in their normal forward-execution mode. When `/dreaming` spawns them via `Task(subagent_type: ...)`, they inherit the tool permissions declared in their registered frontmatter; the Task tool does NOT support overriding `disallowedTools` per-call. That means the read-only constraint for reflection-spawned agents is **prompt-level**, not tool-level: enforced by the HARD RULES block in the reflection-mode task prompt template above and by the agents' own training to follow explicit instructions, NOT by the harness blocking Write/Edit calls.

In practice, a well-functioning agent honors the HARD RULES. The mitigation against drift is:

1. The HARD RULES block in the reflection-mode prompt is explicit and short.
2. `/dreaming` re-states the read-only contract at the top of every per-agent invocation.
3. The output contract (six sections with PENDING USER APPROVAL labels) leaves no productive path for the reflection-spawned agent to write — it proposes only; `/dreaming` (the main thread, at the repo root) is the sole party that writes accepted memory/LESSONS, and only via the guarded sole writers.
4. Any write that does land must still pass the user's per-item approval gate before becoming persistent on the user's behalf.

A future improvement is dedicated reflection-mode agent variants with `disallowedTools: Write, Edit, NotebookEdit` baked into their frontmatter — that would move enforcement from prompt-level to tool-level. For now, the prompt-level contract is the design.

## Example Output

```markdown
## /dreaming — Reflection Report

**Sessions analyzed:** 5 (2026-05-03 → 2026-05-09)
**Agents reflecting:** code-reviewer, red-team, qa-executor
**Contract:** read-only until per-item Accept. Memory/LESSONS/agent-memory writes go through the repo-root sole writers; CLAUDE.md stays paste-to-apply.

---

### 1. Recurring Patterns

- **Pattern A — Missing boundary tests** (3/5 sessions: 2026-05-03, 2026-05-06, 2026-05-09)
  Workers shipped CRUD endpoints without negative-case tests; QA Executor flagged the gap each time.
- **Pattern B — `provides:` drift** (4/5 sessions)
  Subtask briefs declared `provides:` symbols that did not match the symbols actually emitted; outputs_gap was non-empty in each case.
- **Pattern C — Code Reviewer re-flagging stale TODOs** (5/5 sessions)
  Same TODO comments flagged review-after-review; nobody is closing them.

### 2. Distilled Insights

- **Insight 1:** When a subtask lacks an explicit boundary-test acceptance criterion, the worker omits boundary tests roughly 60% of the time. (Evidence: Pattern A.)
- **Insight 2:** `provides:` entries authored from memory rather than from the actual code drift within one session. (Evidence: Pattern B.)
- **Insight 3:** TODOs without an owning task ID accumulate indefinitely. (Evidence: Pattern C.)

### 3. Proposed Memory Updates

- **[code-reviewer]** _add_ → `.claude/agent-memory/.../patterns.md`
  Text: "Always check whether subtask `provides:` symbols actually exist in the modified files; flag drift as BLOCKING."
  Linked insight: 2
  Evidence: 3 distinct sessions (2026-05-03, 2026-05-06, 2026-05-09)
  Status: **PENDING USER APPROVAL**

- **[qa-executor]** _add_ → `.claude/agent-memory/.../boundary-tests.md`
  Text: "If a subtask touches a CRUD endpoint and the brief has no boundary-test criterion, generate boundary tests anyway and report the gap."
  Linked insight: 1
  Evidence: 1 session (2026-05-06)
  Status: **PENDING USER APPROVAL**

### 4. Proposed CLAUDE.md Updates

- **Target section:** "## Common Pitfalls"
  Proposed text: "TODO comments without an owning task ID are forbidden. Either link a Beads/issue ID or remove the TODO before merging — Code Reviewer will block PRs that accumulate ownerless TODOs."
  Linked insight: 3
  Evidence: 2 distinct sessions (2026-05-03, 2026-05-09)
  Status: **PENDING USER APPROVAL**

### 5. Collected Memory Candidates

- Candidate: "Worker summaries live in .supervisor/worker-summaries/ and are the cheap result-extraction path, not the full TaskOutput."
  Source: session 2026-05-06, subtask BD-22a
  Evidence: 1 session (2026-05-06)
  Status: **PENDING USER APPROVAL**
  (deduped against existing project memory: not already present)

### 6. Proposed LESSONS

- category: testing — "When a subtask touches a CRUD endpoint with no boundary-test criterion, generate boundary tests anyway."
  Score: 0.72 (recall-frequency 3/5 × outcome 0.8 [QA-flagged gap] × diversity 3 distinct subtasks)
  Linked insight: 1
  Status: **PENDING USER APPROVAL**
- category: contracts — "Author `provides:` symbols from the actual diff, not from memory." (category full → replaces oldest: "Prefer interface-first contracts")
  Score: 0.64
  Linked insight: 2
  Status: **PENDING USER APPROVAL**

---

### Approval

For each item above, choose **Accept**, **Reject**, or **Edit** (per-item — there is no bulk-accept). On **Accept**: PROJECT_MEMORY facts (incl. accepted §5 candidates) are written by `/dreaming` via `write-project-memory.sh`, and §6 LESSONS via `write-lessons.sh` (both repo-root sole writers, run from the repo root, both invoked with `--confirm` — their store is committed). CLAUDE.md (§4) proposals are paste-to-apply by you; agent-memory (§3) proposals are promoted through the sole writer with `write-agent-memory.sh --proposal <file> --confirm` and are never hand-applied. **Reject**/**Edit** never writes. There is no auto-write. Each item is asked with `AskUserQuestion` using the fixed option set for its class — see "Approval Option Contract" above.

Worked recommendation pass over the items above (the rules are in that section's table; the point of printing it is that every marker is checkable against the report):

- §3 `[code-reviewer]` — evidence 3 distinct sessions ⇒ `Accept (Recommended)` first, description citing "3 sessions corroborate".
- §3 `[qa-executor]` — evidence 1 session ⇒ **no recommendation**, neutral order.
- §4 additive — evidence 2 distinct sessions ⇒ `Accept (Recommended)`, header `CLAUDE.md`. Recommended even though it is paste-to-apply: the marker is about the evidence, not about who performs the write.
- §5 candidate — evidence 1 session ⇒ **no recommendation**, neutral order.
- §6 `testing` — highest-scoring proposal in its category and evidence spans 3 subtasks ⇒ `Accept (Recommended)`.
- §6 `contracts` — displaces the oldest lesson in a full category ⇒ **never recommended**, regardless of score.
- Harvested rules — **never recommended** on either gate.

Three of seven recommended is a normal-looking pass; zero is also normal. Abstain is the default, not a degraded outcome.

### Promotion queues (shown only when they are non-empty)

- **PROMOTE PENDING PROPOSAL** — `.supervisor/agent-memory-proposals/2026-05-09-jq-optional-chain.md`
  agent: `loomwright-loomwright-code-reviewer` · name: `jq-optional-chain-type-trap`
  Accept promotes via `write-agent-memory.sh --proposal … --confirm` and deletes the file; Reject deletes it without writing.
- **Harvested `.agent/rules/` batch** — 4 proposed rules (coverage 74/107, dedupe 18.50 findings/rule, scope fidelity 98% of the 55 CHECKABLE findings / 73% over all 74 motivating findings — both figures, never the flattering one alone).
  Each rule takes **two** gates: **Accept** (content), then a separate **Pre-push confirmation** (push). Only rules clearing both are committed to `dreaming/rules-<session_id>` and delivered by `gh pr create`. Nothing confirmed ⇒ no branch, no PR. `/dreaming` never merges the PR it opens.
```

## Workflow Positioning

`/dreaming` is a **post-hoc reflection** command. It does not replace any existing pipeline — it complements them.

| Command | Direction | When to use |
|---------|-----------|-------------|
| `/orchestrator` | Forward (plan) | Decompose a goal into tasks before execution |
| `/supervisor` | Forward (execute) | Autonomously execute tasks end-to-end |
| `/code-reviewer` | Lateral (live audit) | Review the current diff or files |
| `/red-team-reviewer` | Lateral (live audit) | Adversarially attack the current state |
| `/qa-executor` | Forward (test) | Generate and run tests against the running app |
| **`/dreaming`** | **Backward (reflect)** | **After several sessions, distill patterns into proposed memory + CLAUDE.md updates** |

Use `/dreaming` periodically — for example, weekly or after every N completed `/supervisor` runs — to harvest durable lessons from session logs and keep agent memory and project documentation aligned with how the team actually works.

## When to Use

- After a streak of completed `/supervisor` sessions, to surface recurring issues
- Before updating `CLAUDE.md` by hand, to discover what *the logs* say should change
- When onboarding a new pattern, to see whether the agents have been quietly learning it
- As a recurring "retrospective" cadence (weekly / per milestone)

## When NOT to Use

- During active execution — `/dreaming` reflects on past sessions, not the current one
- When you need code changes — `/dreaming` never touches code (it persists approved memory/LESSONS/promotions, and its only branch-and-PR path carries `.agent/rules/*.json` alone); use `/supervisor` or `/code-reviewer` for code changes
- For agents not currently supported — six agents have `memory: project` (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor), but v12.2.0's `--agent` flag covers only Code Reviewer, Red Team Reviewer, and QA Executor; the other three are out of scope until a follow-up release

## See Also

- `/supervisor` — Autonomous workflow whose logs are the input to `/dreaming`
- `/code-reviewer` — Live (forward) review counterpart
- `/red-team-reviewer` — Live (forward) adversarial counterpart
- `/qa-executor` — Live (forward) QA counterpart
- `/agent-help` — Full command list
- `loomwright/skills/memory-tool/SKILL.md` — Decision aid for what to write to agent memory directories (consulted on demand)
- `.supervisor/logs/{session_id}.jsonl` — Source data consumed by `/dreaming`
