## VERIFY_QUEUE

The on-disk layout of the `/verify --folder <dir>` queue engine's run file (item 07),
`.supervisor/verify/queue-<UTC ts>-<slug>.md` — mirroring `AUTOMATE_RUN`'s framing above almost
exactly, adapted for `/verify`'s own truth source. It is the contract, the dashboard, and the resume
state for a verify-queue run: one markdown file per queue holds the Source, the resolved Queue, the
current item, and an append-only Progress log. Its sections and the reconcile algorithm are coined in
`skills/verify-walkthrough/SKILL.md` §10 "Multi-ticket queue" (the single source of truth); this
section documents that layout verbatim and **must not re-coin or rename** any of it.

> ⚠️ **This is a markdown STATE-FILE contract, NOT a hook-validated emitted result block** — same
> precedent as `AUTOMATE_RUN` immediately above. No hook enumerates or validates `VERIFY_QUEUE`; it is
> persisted state of an inline main-thread workflow (`/verify --folder` is inline-only, like
> `/automate`), written and re-read directly by the queue loop on every start / `--resume`.

**Single-file principle.** There is **no manifest, no registry, no second dashboard file** — this ONE
markdown file holds everything. "Find prior queue runs" = glob `.supervisor/verify/queue-*.md` for
files not marked `## Status: done`. Each queue item's own single-ticket run keeps its OWN existing
`.supervisor/verify/<run_id>/` directory (§VERIFY_EVIDENCE) — the queue file only references those
directories by `run_id`, it never duplicates their contents.

### Run-file layout (`.supervisor/verify/queue-<UTC ts>-<slug>.md`)

```md
# Verify Queue: <title>
## Status: running          # running | paused | done   (done only when every Queue item is checked off)
## Source
- folder <dir>
## Run Config
- limit: 5 | impact_limit: 10
## Queue                    # `- [ ] <ticket>` queued (no run_id minted yet) · `- [ ] <ticket> -> <run_id>` picked, in flight ·
                             # `- [x] <ticket> -> <run_id>  verdict: PASS:n FAIL:n BLOCKED:n NOT_VERIFIABLE:n total:n` done ·
                             # `- [x] <ticket> -> <run_id>  # stale: head moved <old>-><new>` excluded, a FRESH `- [ ] <ticket>` is re-queued
## Current
- item: <ticket path or null> | run_id: <run_id or null> | status: running|paused|done|null
- pause_reason: needs_auth|session_expired|limit_reached|resume_ambiguous|null
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <ticket> -> run_id <run_id>
- <ts> <ticket> run_end status=completed PASS:n FAIL:n BLOCKED:n NOT_VERIFIABLE:n
```

### Section reference

| Section | Required | Notes |
|---|---|---|
| `# Verify Queue: <title>` | yes | The queue run title (H1). |
| `## Status` | yes | The queue-level status. Enum below. |
| `## Source` | yes | Always `folder <dir>` in this release (`--backlog` is Phase 2, not built). |
| `## Run Config` | yes | `limit` (PROCESSED-item cap this invocation, **default 5** — never Queue size) and `impact_limit` (the `--impact-limit` bound applied to every item's impact pass, **default 10**) — both PERSISTED (set once at queue creation, unlike `--notify`/`--cheap` below). |
| `## Queue` | yes | The **FULL** resolved item list from `resolve-folder`, in `LC_ALL=C sort` order (processing order). Checklist convention below. |
| `## Current` | yes | The in-flight item, its `run_id`, item-level status, and `pause_reason`. Enums below. |
| `## Progress` | yes | **APPEND-ONLY** event log — one timestamped line per event; never rewritten. |

### `## Status` enum (queue-level)

| Value | Meaning |
|---|---|
| `running` | The loop is actively processing (or this is the freshly-created queue). |
| `paused` | Stopped with **work remaining** — always paired with a `pause_reason` in `## Current` (`needs_auth` \| `session_expired` \| `limit_reached` \| `resume_ambiguous`). |
| `done` | Set **only** when every `## Queue` item is checked off (no `- [ ]` items remain) — `remaining` is **COMPUTED**, via `verify-helpers.sh queue-remaining`, never a persisted field. |

### `## Queue` checklist convention

- `- [ ] <ticket>` — **queued, unpicked** (no run dir minted yet).
- `- [ ] <ticket> -> <run_id>` — **picked, in flight**: `preflight` minted `.supervisor/verify/<run_id>/`
  for this ticket but the item has not reached `run_end` yet (still unchecked).
- `- [x] <ticket> -> <run_id>  verdict: PASS:n FAIL:n BLOCKED:n NOT_VERIFIABLE:n total:n` — **done**; the
  counts are COPIED from `verify-run.sh finish`'s printed counts row (§VERIFY_RESULT), never tallied by
  the queue loop.
- `- [x] <ticket> -> <run_id>  # stale: head moved <old>-><new>` — **excluded**: this run dir's verdicts
  no longer describe the ticket's current branch head (the reconcile below found a moved `git
  rev-parse`); a FRESH `- [ ] <ticket>` (no `run_id`) is inserted for the same ticket, and the stale run
  dir is **NEVER reused and NEVER deleted** — its counts must never appear in the new item's summary.
- **Order = `LC_ALL=C sort` order** from `resolve-folder` (processing order, top-down).

### `## Current` fields

| Field | Values | Notes |
|---|---|---|
| `item` | ticket path \| `null` | The in-flight item's ticket path. |
| `run_id` | string \| `null` | The in-flight item's OWN single-ticket `run_id` — `.supervisor/verify/<run_id>/` is the store this item's evidence lives in. |
| `status` (item-level) | `running` \| `paused` \| `done` \| `null` | The state of the in-flight item. Distinct from the queue-level `## Status` enum above. |
| `pause_reason` | `needs_auth` \| `session_expired` \| `limit_reached` \| `resume_ambiguous` \| `null` | Non-null whenever `## Status: paused`; `null` while `running`/`done`. **Deliberately a DIFFERENT enum from `AUTOMATE_RUN`'s `pause_reason`** (`awaiting_merge`/`escalated`/`limit_reached`/`resume_ambiguous`) — a verify pause is not an automate pause; the two engines' enums are never unified (see "Never shares state with `/automate`" below). |

### Reconcile (belief vs truth — `verify-run.sh queue-reconcile-item`)

On every start (bare `/verify --folder`, and every `--resume`), the `## Current` item is reconciled
against ground truth BEFORE trusting its checkbox — via `bash scripts/verify-run.sh
queue-reconcile-item <run_dir> --branch <name> --repo <dir>`, which prints one compact JSON object.
`<name>` is `run_start_field <run_dir> branch` — the SAME derivation the single-ticket Resume flow
already uses (`jq -r 'select(.event=="run_start") | .branch'`) — never the CLI's/repo's current
checked-out branch, since a queue's items may have been verified against different branches over time:

```json
{"status": "stale|done|paused|crashed|not_started", "pause_reason": "<string>|null", "resume_ac_id": "<AC id>|null", "old_sha": "<sha>|null", "new_sha": "<sha>|null"}
```

Two independent truths, checked in this order (a moved head always wins, no matter how the run
stopped):

1. **`git rev-parse <branch>` vs the run dir's OWN `run_start.head_sha`** (§VERIFY_EVIDENCE). A moved
   head ⇒ `status: "stale"` — the item is marked `# stale: head moved <old>-><new>` and re-queued fresh
   (checklist convention above); this run dir's verdicts are never trusted again.
2. **`evidence.jsonl`'s LAST line**, when the head has not moved: a `run_end` line ⇒ `status: "done"`
   (even if the queue checkbox is still unchecked — a crash between `finish` and check-off is never
   re-run); a `pause` line ⇒ `status: "paused"` (its `reason` echoed as `pause_reason`); anything else
   (or no evidence.jsonl at all yet) ⇒ `status: "crashed"` mid-AC, and `resume_ac_id` names the next
   unverdicted AC from `verify-helpers.sh first-unverdicted` — the ONE implementation of that
   derivation, never re-computed inline.
3. **Before resuming an authenticated item**, the queue loop calls the SAME `verify-run.sh auth-check`
   subcommand the single-ticket resume flow already uses (§VERIFY_RESULT / `commands/verify.md`
   "Resume flow") — there is no second auth-probe implementation for queue mode.

`queue-reconcile-item` is a **pure read** — it never mutates the queue file, the evidence store, or any
run dir; the queue loop acts on its printed JSON.

### `--resume <run_id>` — probe-then-fallback dispatch

`--resume` is a single overloaded flag, not two flags. The command PROBES `.supervisor/verify/
queue-<run_id>.md` first (does `<run_id>` name an existing queue file's own basename?); a match is a
**queue-mode resume** (reconcile + continue the per-item loop above). No match falls back to the
EXISTING single-ticket resume — `.supervisor/verify/<run_id>/` is treated as a single-ticket run dir,
byte-for-byte the pre-item-07 behavior (`commands/verify.md` "Resume flow"). Two incomplete queue files
and no explicit `--resume <run_id>` ⇒ `AskUserQuestion` (or `pause_reason: resume_ambiguous` under
`--non-interactive-fallback`) — the exact convention `AUTOMATE_RUN`'s own `resume_ambiguous` uses.

### Crash-safety contract

The queue file is the **only** copy of queue resume state, so (per `skills/verify-walkthrough/SKILL.md`
§10, mirroring `AUTOMATE_RUN`'s contract above):

- **Atomic write (temp + rename), LINE-COUNT GUARDED:** every update goes through `verify-helpers.sh
  queue-write`, which stages to a temp file FIRST (byte-exact stdin capture) and REFUSES the rewrite
  (exit 1, the queue file byte-unchanged) when the existing file is non-empty and the new content has
  FEWER lines — an empty or truncated rewrite (a crashed generator, a failed pipeline) must never
  silently shrink the ONLY copy of queue resume state (memory: `runfile-write-accepts-empty-stdin`).
  `AUTOMATE_RUN`'s `runfile-write` guards the same failure differently (shape + `## Progress`-prefix
  validation, not a line count — its `## Current` block legitimately shrinks; see its contract above).
- **`## Progress` is APPEND-ONLY** (`verify-helpers.sh queue-progress-append`) — never rewritten;
  existing lines are immutable, new lines are appended.
- **Rewrites are confined** to `## Queue` checkboxes/lines (`queue-checkoff`, or a full `queue-write`
  when inserting a re-queued item / recording a freshly-minted `run_id`) and the `## Current` block.
  `## Status`/`## Source`/`## Run Config` change rarely.
- **Resume = belief vs truth:** the queue file is the loop's *belief*; the Reconcile section above is
  performed **before** trusting any checkbox.

### Never shares state with `/automate` (invariant)

A verify queue reads and writes **`.supervisor/verify/` only** — it NEVER reads or writes
`.supervisor/automate/`, `.supervisor/config.json`, or `.supervisor/state.md`. The two engines'
`pause_reason` enums are deliberately DIFFERENT (see `## Current` fields above) and never unified.
Running a verify queue inside an `/automate` tick is out of scope for this item and forbidden by
omission — no code path added here reads or writes an `/automate` surface. Mechanically proven by
`test-verify-queue.sh`'s `find .supervisor/automate .supervisor/state.md -newer <marker>` check (empty
after a full queue run).

### Non-goals (explicit)

No auto-merge, no PR interaction, no `/automate` integration, no `--backlog` (Phase 2), no parallel
items (one app instance, one browser, sequential — same as the single-ticket walk this wraps), no
cross-project queues.

**Cross-references:**
- `loomwright/skills/verify-walkthrough/SKILL.md` §10 — the **authority** for the run-file layout, the
  per-item loop, the reconcile algorithm, and the probe-then-fallback resume dispatch. This section
  documents that protocol; do NOT change names here without updating the skill first.
- `loomwright/commands/verify.md` — the `/verify --folder`/`--resume`/`--limit` command surface.
- `AUTOMATE_RUN` (above) — the sibling engine this queue's run-file shape mirrors; the two engines
  never share state (see "Never shares state with `/automate`" above).
- `VERIFY_EVIDENCE` / `VERIFY_RESULT` (above) — each Queue item's OWN single-ticket run store and
  result block are unchanged by this section; the queue file only references them by `run_id`.

---

