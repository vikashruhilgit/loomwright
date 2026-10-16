## AUTOMATE_RUN

The on-disk layout of the `/automate` engine's run file, `.supervisor/automate/<run_id>.md` (v14.41.0+; `schema_version: 1`). It is the contract, the dashboard, and the resume state for a `/automate` run — one markdown file per run holds the Source, the resolved Queue, the current item, and an append-only Progress log. Its sections, the item-status enum, and the item lifecycle are coined in `skills/automate-loop/SKILL.md` (the single source of truth — §3 the single run file, §4 resume, §6 the per-item loop); this section documents that layout verbatim and **must not re-coin or rename** any of it.

> ⚠️ **This is a markdown STATE-FILE contract, NOT a hook-validated emitted result block.** Unlike `SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, `WORKER_RESULT`, and `REVIEW_HEAL_RESULT` — each of which a `SubagentStop` hook in `hooks.json` enumerates and validates — **NOTHING validates `AUTOMATE_RUN`.** No hook enumerates it; there is no SubagentStop validator. It is the persisted state of an inline main-thread workflow (`/automate` is inline-only, no `-runner` agent), written and re-read directly by the engine on each `/loop` tick. The closest precedent in this file is `AUTONOMOUS_RUN` (another inline-workflow state artifact that is "Not subject to hook validation"); `AUTOMATE_RUN` differs in that it is the live, rewritten-in-place run file rather than a terminal summary.

**Single-file principle.** There is **no manifest, no registry, no `progress.jsonl`, no dashboard file** — this ONE markdown file holds everything. "Find prior runs" = glob `.supervisor/automate/*.md` for run files — those carrying the `# Automate Run:` title line (`is_run_file` in `automate-helpers.sh`; rule owned by `skills/automate-loop/SKILL.md` §4) — not marked `## Status: done`. The only other on-disk artifacts are sidecars, never runs: a *transient* config-backup sidecar (`<run_id>.config-backup.json`) that exists only during a tick (see `skills/automate-loop/SKILL.md` §7), and the per-run result sidecars `<run_id>.supervisor-result.md` / `<run_id>.review-heal-result.md` written verbatim at §6 steps 2–3; they carry no `# Automate Run:` title, so RESUME never lists them.
<!-- index-only:begin -->

> **Split layout (parallel-automate/22, move-only).** A `###` section below that carries only a `See [<file>](<file>).` line was moved verbatim to that file under `automate-run/`; read it there. The run-file layout and the `## Current` fields stay in this file. `scripts/test-automate-loop-split.sh` keeps this index and the files in step.
<!-- index-only:end -->

### Run-file layout (`.supervisor/automate/<run_id>.md`)

```md
# Automate Run: <title>
## Status: running          # running | paused | done   (paused = stopped, work remains; done only when the Queue is fully resolved)
## Source
- <user prompt text | folder <dir> | backlog <_BACKLOG.md> | ...>
## Run Config
- mode: safe|auto-merge | limit: 5 | trust_unprotected: false
- auto_review_original: <true|false|absent> | config_backup: <run_id>.config-backup.json
- max_tokens: <N|absent>          # red-team-hardening/06 — ONLY present when --max-tokens was passed; PERSISTED (unlike --cheap/--notify) so a bare --resume still enforces it
- parallel: <N|absent>            # parallel-automate/05 — present on any --parallel parent run, 1 included (N = 1 = single-lane mode, skills/automate-loop/lanes.md)
## Queue                    # `- [ ]` queued · `- [x]` done (merged) · `- [x] … # skipped|abandoned:` excluded; order = processing order
- [ ] <requirement path or generated file>
- [x] <... merged ...>
- [x] <... path ...>  # skipped: <reason>     # checked-off so "next unchecked" never re-picks it; reason also in ## Progress
## Current
- item: <path> | status: running|awaiting_merge|ready_for_release|escalated|failed|rate_limit|drain_died|done | pr: <url> | branch: <name>
- pause_reason: awaiting_merge|ready_for_release|awaiting_go|escalated|limit_reached|resume_ambiguous|rate_limit|drain_died|token_ceiling|run_lock_held|meta_unreachable|trail_pr_open|closeout_leftover|live_lane|null
- wave: <k> | items: <i1>, <i2>     # parallel-automate/05 — present ONLY on a --parallel N>1 parent run; written only by `automate-helpers.sh current-wave`
- escalation_cause: check_pending|check_red_unrelated|check_red|findings|validation_unrun|other | check: <name|null> | run_id: <id|null> | attempt: <n|null> | sha: <sha|null>     # automate-followups/31 — present ONLY at an `escalated` park; written only by `current-escalation`
- owned_drain_started: <ts> | owned_drain_result: READY|ESCALATED|died|superseded_by_merge | suppressed_default_dispatch: true
- pending_decisions: <n> | fix_now_reentered: <true|false>     # automate-followups/12 — present ONLY when this item produced dismissed-finding drafts
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <item>
- <ts> session_id <id> (<item>)     # red-team-hardening/06 — read-token-ledger.sh --run-id sums every session_id line in this file
- <ts> ran /autonomous → PR <url>
- <ts> drain READY → awaiting_merge
```

<!-- split:begin automate-run/sections-status-queue.md -->
### Section reference

See [automate-run/sections-status-queue.md](automate-run/sections-status-queue.md).

### `## Status` enum (run-level)

See [automate-run/sections-status-queue.md](automate-run/sections-status-queue.md).

### `## Queue` checklist convention

See [automate-run/sections-status-queue.md](automate-run/sections-status-queue.md).
<!-- split:end automate-run/sections-status-queue.md -->

### `## Current` fields

| Field | Values | Notes |
|---|---|---|
| `status` (item-level) | `running` \| `awaiting_merge` \| `ready_for_release` \| `escalated` \| `failed` \| `rate_limit` \| `drain_died` \| `done` | The state of the in-flight item. Distinct from the run-level `## Status` enum above. `rate_limit`/`drain_died` mirror `pause_reason` exactly the way `awaiting_merge`/`escalated` already do — never a separate `parked` placeholder. |
| `pause_reason` | `awaiting_merge` \| `ready_for_release` \| `awaiting_go` \| `escalated` \| `limit_reached` \| `resume_ambiguous` \| `rate_limit` \| `drain_died` \| `token_ceiling` \| `run_lock_held` \| `meta_unreachable` \| `trail_pr_open` \| `closeout_leftover` \| `live_lane` \| `null` | Non-null whenever `## Status: paused`; `null` while `running`/`done`. `awaiting_go`: the `## Current` item was closed out by `closeout` (its PR merged; item `status: done`) and the next item waits for the owner's explicit `--resume` — written ONLY by `closeout`, ONLY when `## Current` names that item and PR and `## Status` is `paused` (a `running` run gets `null`) — see `skills/automate-loop/SKILL.md` §3 "After a close-out". `rate_limit`: the loop's own `agent_lifecycle: failed` row (main-scope, `reason: rate_limit`) fired during RUN, before a PR existed — see `skills/automate-loop/SKILL.md` §6 "Rate-limit park". `drain_died`: RECONCILE (§4) found a `.supervisor/review-dispatch/*.died` marker for this item's PR — a DETACHED `dispatch-pr-review.sh` drain exited without ever producing a `REVIEW_HEAL_RESULT` — see `skills/automate-loop/SKILL.md` §4. `token_ceiling` (red-team-hardening/06): PICK-time `automate-helpers.sh ceiling-check` found the run's summed ledger over `## Run Config`'s `max_tokens`, or the reader answered `LEDGER_UNREADABLE=1` (fail CLOSED) — see §6 step 1. `run_lock_held`: PICK-time `run-lock.sh acquire` found `.supervisor/run.lock` held by another run/process — see §6 step 1 / §11. Both new values are RUN-level-only parks fired BEFORE an item is picked, so — like `limit_reached`/`resume_ambiguous` — they have no item-level `status` counterpart in the enum above. `meta_unreachable`: branch mode's `automate-helpers.sh meta-entry` failed on a `--resume <id>` of an existing local run file (pull exit non-zero or mode `unknown`) — the `## Progress` line names the reason (a conflict names its path); a RUN-level park with no item-level `status` counterpart, like `limit_reached` / `resume_ambiguous` — see `skills/automate-loop/SKILL.md` §13. `trail_pr_open`: the PICK-time `automate-helpers.sh trail-gate` found this run's own trail PR (`chore/<run_id>-trail-<n>`) open, or could not read its state (fail CLOSED) — the single-open-PR invariant counts the trail PR, because its merge would move the base under the next item's PR (`BEHIND` under `strict` required checks); the `## Progress` line names the PR. Written after RECONCILE, with the run-lock held and released at the park; no item-level `status` counterpart (the `## Current` item is the previous, closed-out one) — see `skills/automate-loop/SKILL.md` §6 step 1 / §8. `closeout_leftover` (automate-followups/32): a close-out could not safely finish one of its steps (a kept worktree or branch, a refused sync, a result line nobody classified) and the owner chose Stop — or the run is non-interactive, which never proceeds past a leftover silently; a RUN-level park with no item-level `status` counterpart, written with `automate-helpers.sh current-set`'s run-level form. The verdict comes from `automate-helpers.sh closeout-classify` (one `closeout` invocation at a time; anything but `complete` is a leftover); each leftover gets one `closeout leftover: <run_id> <step> <detail>` `## Progress` line — see `skills/automate-loop/SKILL.md` §6 step 1 "Close-out leftover gate". `live_lane` (parallel-automate/05): the PICK-time lane guard `automate-helpers.sh pick-guard .supervisor/automate` printed `refuse: live_lane <lane_run_id> <lane>` (a lane of an open `--parallel` wave is verifiably live, or holds an unanswered question) right after the run lock was acquired — the case where the coordinator's `automate-lanes:<run_id>` lock was reclaimed while its lanes run on; a RUN-level park with no item-level `status` counterpart, written with `current-set`'s run-level form, the run lock released at the park; the `## Progress` line quotes the refusal — see `skills/automate-loop/SKILL.md` §6 step 1 / §14. |
| `pr` / `branch` | string / `null` | The in-flight item's PR URL and feature branch. When the item changes, `current-set` resets an omitted `pr`/`branch` to `null`, so the previous item's PR never rides into the next item. |
| `wave` / `items` | `<k>` / comma-separated item paths | parallel-automate/05 — OPTIONAL, present only on a `--parallel N>1` parent run while a wave is planned. Written only by `automate-helpers.sh current-wave <rf> --wave <k> --items <i1,i2,…>` (replaced if present; `--wave null` clears it). Never present inside a lane or on a sequential run. |
| `owned_drain_started` | `<ts>` | Timestamp the engine's OWNED inline `/review-pr --until-mergeable` drain started (the latest pass's — an owner-requested fix-now re-drain overwrites it, together with `owned_drain_result`). A fix-now re-drain's `## Progress` lines are pinned (Part T02): start `<ts> owned drain started (fix-now re-drain) — <drain invocation> @ <head sha>` (still prefixed `owned drain started`, so the `current_not_set` guard is unchanged) and terminal `<ts> fix-now re-drain <READY\|ESCALATED> (<termination_reason>, <n> rounds, <k> fix cycles)`; `automate-helpers.sh dismissed-cost` derives the fix-now cost from them (legacy wordings matched tolerantly). Authority: `skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)" step 3. |
| `owned_drain_result` | `READY` \| `ESCALATED` \| `died` \| `superseded_by_merge` | The drain's terminal `REVIEW_HEAL_RESULT.decision`, read synchronously. `READY` is "ready, left open for a human" — the drain **never merges**. `died` is not a `REVIEW_HEAL_RESULT` decision at all — it records a DETACHED drain's `.died` marker found at RECONCILE (see `pause_reason: drain_died` above), never this engine's own inline drain (which cannot die silently — it runs in this same turn). `superseded_by_merge` (automate-followups/20) is not a `REVIEW_HEAL_RESULT` decision either: the owned drain for this item started but ended WITHOUT a terminal `REVIEW_HEAL_RESULT` — in practice the owner merged the PR mid-drain and the drain was stopped — and `automate-helpers.sh reconcile-item <pr>` reads `merged`. The engine writes it, never a script, at one of two points: §6 step 3 DRAIN, when the drain returns without a terminal block; or §4 RECONCILE, when a resumed run's `## Current` item has an `owned drain started` `## Progress` line after its last `picked` line, no terminal drain line after it, and a merged PR. Either way no `<run_id>.review-heal-result.md` sidecar is written, GATE never runs for the pass, the item goes to `closeout` exactly as a RECONCILE-merged item does, and the `## Progress` line names the value (`<ts> drain superseded_by_merge — PR merged before a terminal REVIEW_HEAL_RESULT`). It is never merge-eligible: `gate-eval` condition 1 parks any `drain_result` other than `READY` (`drain_not_ready`). Never `null`, and never omitted while the line is present: the line is absent only while no owned drain has run in this run file. |
| `suppressed_default_dispatch` | `true` | Records that the engine suppressed `/autonomous`'s default detached until-mergeable drain (`.auto_review:false` around the RUN phase) so exactly ONE owned inline drain runs per pass — at most one owner-requested fix-now re-drain per item, strictly sequential (never concurrent; `skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)"). Verifiable via these fields **plus** the absence of any detached `dispatch-pr-review.sh` artifact for the PR (`skills/automate-loop/SKILL.md` §7). |
| `escalation_cause` | `check_pending` \| `check_red_unrelated` \| `check_red` \| `findings` \| `validation_unrun` \| `other` | automate-followups/31 — OPTIONAL, present only at an `escalated` park (mirrors the `pending_decisions` OPTIONAL-line precedent). Its line also carries `check`, `run_id`, `attempt` and `sha` (each `null` when not check-driven or unreadable) — the drain's `REVIEW_HEAL_RESULT` `escalation_*` fields (`docs/result-schemas/review-heal-result.md`). `validation_unrun` (af36-remainder/01) is ENGINE-SIDE, never a `REVIEW_HEAL_RESULT` value: the drain said `READY`, but `automate-helpers.sh validation-gate` found a "Running system" step of the item's `## Validation` section with no pasted evidence in the PR body (or could not read it — fail CLOSED) and the owner did not waive it (`AUT-WAIVE`, human-only); its `check` is `V<n> <title>` (the step), `sha` the PR head, `run_id`/`attempt` `null`. The merge watcher never re-checks it; `--resume`'s RECONCILE re-runs the gate and, on `ok`/`waived`, writes the READY park (`skills/automate-loop/SKILL.md` §6 step 4 "Validation gate"). The ONLY writer is `automate-helpers.sh current-escalation <runfile> --cause <c> [--check … --run-id … --attempt … --sha …]` (enum-checked, `\|`/newline refused, file byte-unchanged on refusal; placed after `- pause_reason:`, else at the end of the block; `--cause null` removes it). An item-form `current-set` that leaves `escalated` or changes the item removes it (per-item state: closeout's `done`, PICK's `running` and every non-escalated park clear it). Informational only — no gate reads it and it never permits a merge. |
| `pending_decisions` | `<n>` (integer ≥ 0) | automate-followups/12 — OPTIONAL, present only when this item's GATE produced dismissed-finding drafts in `.supervisor/requirements/proposed/` (`automate-helpers.sh dismissed-drafts`). The count of this run's drafts still `undecided` after the gate's decision step (always the full count under `--non-interactive-fallback` and at a successful `--auto-merge` MERGE, where nothing is asked). At a sequential interactive READY park (automate-speed/01, park first) it is written WITH the park, before any question — the full undecided count — and rewritten after the asks under a re-acquired run lock; drafts still unanswered when the PR merges mid-question (the watcher's `closeout` ran) or when `park-ask-gate` refused stay counted. The next interactive PICK asks them (Follow-up / Drop) before RECONCILE's `closeout`. Never a new `pause_reason` value. Authority: `skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)". |
| `fix_now_reentered` | `true` \| `false` | automate-followups/12 — OPTIONAL, same line as `pending_decisions`. `true` once the owner answered `Fix now on this PR` and the item ran its ONE fix-now DRAIN → GATE re-pass; fix-now is never offered again for this item, and the loop passes `--after-fix-now` to `dismissed-drafts` only on that post-re-pass run. |

<!-- split:begin automate-run/item-lifecycle.md -->
### Item lifecycle

See [automate-run/item-lifecycle.md](automate-run/item-lifecycle.md).
<!-- split:end automate-run/item-lifecycle.md -->

<!-- split:begin automate-run/parallel-lanes.md -->
### `--parallel` `## Progress` lines (parallel-automate/21)

See [automate-run/parallel-lanes.md](automate-run/parallel-lanes.md).

### Lane inbox answer file (`<lane>/.supervisor/inbox/answers/<tool_use_id>.json`)

See [automate-run/parallel-lanes.md](automate-run/parallel-lanes.md).
<!-- split:end automate-run/parallel-lanes.md -->

<!-- split:begin automate-run/crash-safety.md -->
### Crash-safety contract

See [automate-run/crash-safety.md](automate-run/crash-safety.md).

### Optional terminal JSONL breadcrumb (secondary — never the source of truth)

See [automate-run/crash-safety.md](automate-run/crash-safety.md).
<!-- split:end automate-run/crash-safety.md -->

### next-step instruction (`automate-next-step.sh`)

`loomwright/scripts/automate-next-step.sh <runfile> [--result <json> | --result-file <f>] [--mode safe|auto-merge] [--non-interactive] [--trust-unprotected] [--root <checkout>] [--session-id <sid>]` (automate-speed/06) is the single reader and writer of the run file for the per-item loop's TAIL — GATE, the dismissed-findings decision step, the park writes and the close-out (`skills/automate-loop/` §6 steps 4–6, §9, §10). Each call runs every deterministic tail step it can and prints **exactly ONE** instruction: one compact JSON object on stdout. The model does what it says and reports back with `--result`. The protocol stays the skill's. This section owns only the instruction's shape, and the driver emits nothing outside it.

**`do` — a CLOSED enum** (the driver's emitter and `scripts/test-automate-next-step.sh` mirror it; no other value is ever printed):

| `do` value | Meaning | The model's next call |
|---|---|---|
| `spawn` | Spawn the named work, then report its result: `what: "fix-now re-drain"` — ONE fix worker on the PR branch (`skills/review-heal/SKILL.md` §U3.5, the findings inside the EXTERNAL_TEXT envelope), then a full DRAIN with the pinned fix-now re-drain lines | `--result <the re-drain's drain report>` (below) |
| `ask` | Ask the owner. Each instruction is ONE ask-tool call | `--result {"answers": [<label>, …], "note": "<free text>"}`, or `--result {"cant_ask": true}` when the ask tool is unavailable |
| `park` | The run is parked: the park state, merge watcher, notify and run-lock release are already done. Stop the loop | none — the next start's RECONCILE / `--resume` takes over |
| `done` | The item's tail is finished. `status: "done"` = the Queue is resolved (`trail-pr --reason done` and the dry sweep line are written); `status: "running"` = go to the next PICK | the next item's drain report starts its tail |

**Common fields:** `do`, `step` (the driver step that printed it — one of the driver's `case` arms: `gate`, `validation`, `gate-eval`, `dismissed`, `decide`, `fix-now`, `park`, `sync`, `leftover`, `checkoff`, `terminate`), `run_id`, `item`, `pr`.
- **`ask` also carries:** `gate` (the `docs/LANE_GATES.md` catalog code: `AUT-WAIVE`, `AUT-DISMISS`, `AUT-SUMMARY`, `AUT-LEFTOVER`), `question`, `header`, `options`, `cant_ask` and `questions` (≤4 entries, each `{question, header, options, option_notes?, draft?}`). The top-level `question`/`header`/`options` mirror `questions[0]`. `header` is the catalog code only for an `allowed` gate (`AUT-SUMMARY`). It is `""` for a human-only gate, never a code. `options` are the catalog labels. `cant_ask` names the outcome the driver takes on `{"cant_ask": true}`: the same branch `--non-interactive` takes (`escalated (escalation_cause: validation_unrun)`; `pending_decisions recorded …`; `closeout_leftover park`). A summary draft is always asked in a call of its own.
- **`park` also carries:** `status: "paused"`, `pause_reason` (read back from `## Current`), `escalation_cause` when one is set, `pending_decisions` when this item produced drafts, and `message`.
- **`done` also carries:** `status` (`done` | `running`) and `remaining`.

**`--result` shapes.**
- **Drain report** (the tail's entry point, and a `spawn`'s answer): `drain_result` (required; `ESCALATED` routes to the escalated park; any other value takes the READY path, where under `--auto-merge` `gate-eval` condition 1 parks a non-`READY` value as `drain_not_ready`), `termination_reason`, `ready_sha`, and for an `ESCALATED` drain `escalation_cause` / `escalation_check` / `escalation_run_id` / `escalation_attempt` / `escalation_sha`. These default to the review-heal sidecar's `escalation_*` fields, and to `other` when it has none. Two optional fields: `items_processed` (overrides the processed count `terminate` derives from the merged `- [x]` Queue rows) and **`progress_note`**.
- **`progress_note`**: a model-authored free-text `## Progress` line, written as `<ts> <progress_note>` in place of the driver's own park line (e.g. `owned drain ESCALATED (pause_reason: escalated) — required check ci cannot execute (runner starvation); merge watcher armed`). It is the one channel for prose the driver cannot derive. Everything else the driver writes is a pinned line, byte for byte: `<ts> parked awaiting_merge <pr> — <n> dismissed decision(s) pending`, `<ts> gate-eval: MERGE`, `dismissed-drafts`' own summary line, `<ts> dismissed decisions asked after the park — <gate line>`, the decision-batch line, `<ts> closeout leftover: <run_id> <step> <detail>`, `<ts> checked off <item> — merged <pr>; remaining: <n>`, `<ts> limit_reached — <n> item(s) processed; remaining: <m>`, `<ts> sweep (dry run): <summary>`.
- **Answers** to an `ask`: `answers` holds one label per question, in order (`answer` for a single question). `note` is the free-text note: AUT-WAIVE's waiver words, passed verbatim to `validation-gate --waive`. A label that is not one of that question's options, or the wrong number of answers, exits 2 with nothing written.

**Idempotency.** The driver keeps the instruction it last printed, verbatim, in the gitignored sidecar `.supervisor/automate/<run_id>.next-step.json`, together with the step it waits on and the tail's context. A call with no `--result` while an instruction is pending re-prints it byte for byte and writes nothing. A replayed drain report (the same report for the same item and PR, sent again after a terminal `park` / `done`) also re-prints that instruction and writes nothing. `--session-id` is the loop's session id: SYNC's `closeout` re-enters the PICK's run lock with it, and the post-park lock windows acquire with it. Other state is read back from the run file: `## Current`, `## Run Config`, and the tail segment of `## Progress` after the last drain line (so a `validation-gate: none|ok|waived` line already there is not re-appended). `<run_id>.gate-ctx.json` is the ctx handed to `gate-eval`. It carries exactly the six loop-owned keys of §10's ctx shape, never a gate-owned key.

**Writers and failures.** The run file is written only through `automate-helpers.sh` `runfile-write` / `progress-append` / `current-set` / `current-escalation` / `queue-checkoff`, plus the helpers that write it themselves (`dismissed-decide`, `validation-gate --waive`, `closeout`, `closeout-classify --record`). A non-zero writer exit is surfaced: stderr names it, no instruction is printed, the exit code is non-zero (1, or the helper's own — `progress-append`'s 3), and the next call retries that step. Exit 2 means a usage error or a `--result` that does not answer what is pending.

**Side effects and test seams.** The merge-watcher launch, the notify and `run-lock.sh` run through `NEXT_STEP_WATCH_CMD` / `NEXT_STEP_NOTIFY_CMD` / `NEXT_STEP_LOCK_CMD` (the defaults are the §6 detached `automate-merge-watch.sh` launch, which unsets the host session identity itself, a desktop notification or a lane's `lane-park-notify`, and `run-lock.sh`). Tests point them at recorders. Tests alone set `NEXT_STEP_FROM=<step>` / `NEXT_STEP_UNTIL=<step>` (start or stop at a step) and `NEXT_STEP_CLOSEOUT_OUT=<file>` (closeout's output as fixed input). These seams let a golden case that begins or ends mid-tail run through the same steps.

**Shapes the driver reproduces from the recorded runs (honest notes).**
- A lane run's `dismissed-drafts` summary line carries a leading `<ts>`; a sequential run appends it verbatim. A lane is a checkout with `.supervisor/lane.json`, `lane-park`'s own criterion.
- An `--auto-merge` fail-closed park's line is `<ts> parked awaiting_merge <pr> — gate-eval PARK: <reason>`, with `; <n> dismissed decision(s) pending` appended only when drafts are pending. The `PARK:` line is not appended on its own.
- At a park-first READY park with no undecided draft, `park-ask-gate` is not called: there is nothing to ask.
- The default notifier is desktop-only, because no webhook gate type is defined for a sequential park.

**Cross-references:**
- `loomwright/skills/automate-loop/SKILL.md` — the **authority** for the run-file layout, the item lifecycle, resume/reconcile, the single-drain contract, and the two modes. This section documents §3/§4/§5/§6/§7 of that skill; do NOT change names here without updating the skill first.
- `loomwright/commands/automate.md` — the `/automate` command body.
- `AUTONOMOUS_RUN` schema (above) — the sibling inline-workflow state artifact (`/autonomous`), likewise not hook-validated; the `/automate` per-item RUN step drives `/autonomous --single-iteration`.

---

