## AUTOMATE_RUN

The on-disk layout of the `/automate` engine's run file, `.supervisor/automate/<run_id>.md` (v14.41.0+; `schema_version: 1`). It is the contract, the dashboard, and the resume state for a `/automate` run — one markdown file per run holds the Source, the resolved Queue, the current item, and an append-only Progress log. Its sections, the item-status enum, and the item lifecycle are coined in `skills/automate-loop/SKILL.md` (the single source of truth — §3 the single run file, §4 resume, §6 the per-item loop); this section documents that layout verbatim and **must not re-coin or rename** any of it.

> ⚠️ **This is a markdown STATE-FILE contract, NOT a hook-validated emitted result block.** Unlike `SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, `WORKER_RESULT`, and `REVIEW_HEAL_RESULT` — each of which a `SubagentStop` hook in `hooks.json` enumerates and validates — **NOTHING validates `AUTOMATE_RUN`.** No hook enumerates it; there is no SubagentStop validator. It is the persisted state of an inline main-thread workflow (`/automate` is inline-only, no `-runner` agent), written and re-read directly by the engine on each `/loop` tick. The closest precedent in this file is `AUTONOMOUS_RUN` (another inline-workflow state artifact that is "Not subject to hook validation"); `AUTOMATE_RUN` differs in that it is the live, rewritten-in-place run file rather than a terminal summary.

**Single-file principle.** There is **no manifest, no registry, no `progress.jsonl`, no dashboard file** — this ONE markdown file holds everything. "Find prior runs" = glob `.supervisor/automate/*.md` for run files — those carrying the `# Automate Run:` title line (`is_run_file` in `automate-helpers.sh`; rule owned by `skills/automate-loop/SKILL.md` §4) — not marked `## Status: done`. The only other on-disk artifacts are sidecars, never runs: a *transient* config-backup sidecar (`<run_id>.config-backup.json`) that exists only during a tick (see `skills/automate-loop/SKILL.md` §7), and the per-run result sidecars `<run_id>.supervisor-result.md` / `<run_id>.review-heal-result.md` written verbatim at §6 steps 2–3; they carry no `# Automate Run:` title, so RESUME never lists them.

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
## Queue                    # `- [ ]` queued · `- [x]` done (merged) · `- [x] … # skipped|abandoned:` excluded; order = processing order
- [ ] <requirement path or generated file>
- [x] <... merged ...>
- [x] <... path ...>  # skipped: <reason>     # checked-off so "next unchecked" never re-picks it; reason also in ## Progress
## Current
- item: <path> | status: running|awaiting_merge|escalated|failed|rate_limit|drain_died|done | pr: <url> | branch: <name>
- pause_reason: awaiting_merge|awaiting_go|escalated|limit_reached|resume_ambiguous|rate_limit|drain_died|token_ceiling|run_lock_held|meta_unreachable|trail_pr_open|closeout_leftover|null
- escalation_cause: check_pending|check_red_unrelated|check_red|findings|other | check: <name|null> | run_id: <id|null> | attempt: <n|null> | sha: <sha|null>     # automate-followups/31 — present ONLY at an `escalated` park; written only by `current-escalation`
- owned_drain_started: <ts> | owned_drain_result: READY|ESCALATED|died | suppressed_default_dispatch: true
- pending_decisions: <n> | fix_now_reentered: <true|false>     # automate-followups/12 — present ONLY when this item produced dismissed-finding drafts
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <item>
- <ts> session_id <id> (<item>)     # red-team-hardening/06 — read-token-ledger.sh --run-id sums every session_id line in this file
- <ts> ran /autonomous → PR <url>
- <ts> drain READY → awaiting_merge
```

### Section reference

| Section | Required | Notes |
|---|---|---|
| `# Automate Run: <title>` | yes | The run title (H1). **Load-bearing:** RESUME keys on this line (`is_run_file`, matched line-anchored anywhere in the file) to tell a run file from the §6 result sidecars in the same directory — a run file without it is never offered for resume. Writers emit the exact form above; readers also accept the tolerated title forms (a leading BOM, CommonMark-legal indentation, whitespace and letter case — never an H2 or an indented code block), owned by `skills/automate-loop/SKILL.md` §4 step 1 and implemented once as `RUN_TITLE_ERE` in `automate-helpers.sh`. |
| `## Status` | yes | The run-level status — the `/loop` stop signal. Enum below. |
| `## Source` | yes | The single resolved source for this run — the user's prompt text, `folder <dir>`, or `backlog <_BACKLOG.md>`. Exactly one source is resolved per run (`skills/automate-loop/SKILL.md` §2). |
| `## Run Config` | yes | `mode` (`safe` \| `auto-merge`), `limit` (PROCESSED-item cap, **default 5** — caps completed items this run, never Queue size), `trust_unprotected` (allows auto-merge onto a branch without enforceable protection — **condition 4 only**; nothing overrides condition 6, the `classify-risk.sh` high-risk park), `auto_review_original` (the original `.auto_review` value captured before the suppress window — `true`/`false`/`absent`), `config_backup` (path of the transient byte-for-byte config-backup sidecar), `max_tokens` (optional, red-team-hardening/06 — the `--max-tokens N` ceiling, present ONLY when passed; unlike `--cheap`/`--notify` this one IS persisted so a bare `--resume` still enforces it). The single-drain config-toggle contract is the skill's domain (`skills/automate-loop/SKILL.md` §7); the ceiling contract is §6 step 1 / §11. |
| `## Queue` | yes | The **FULL** resolved item list, in **processing order** (top-down). Checklist convention below. |
| `## Current` | yes | The in-flight item, its item-level status, `pause_reason`, and the owned-drain observability fields. Enums below. |
| `## Progress` | yes | **APPEND-ONLY** event log — one timestamped line per event; never rewritten. |

### `## Status` enum (run-level)

| Value | Meaning |
|---|---|
| `running` | The loop is actively processing (or this is the freshly-created run). |
| `paused` | Stopped with **work remaining** — always paired with a `pause_reason` in `## Current` (`awaiting_merge` \| `awaiting_go` \| `escalated` \| `limit_reached` \| `resume_ambiguous` \| `rate_limit` \| `drain_died` \| `token_ceiling` \| `run_lock_held` \| `meta_unreachable` \| `trail_pr_open` \| `closeout_leftover`). |
| `done` | Set **only** when the Queue is **fully resolved** (no `- [ ]` items remain), i.e. `remaining: 0`. (`remaining` is **COMPUTED/REPORTED** — the count of `- [ ]` Queue items, derived by `automate-helpers.sh remaining` — **not a persisted run-file field**; there is no `remaining:` line stored in the template.) |

### `## Queue` checklist convention

- `- [ ] <path>` — **queued** (unprocessed). `remaining` counts only `- [ ]` items.
- `- [x] <path>` — **done** (merged).
- `- [x] <path>  # skipped: <reason>` / `- [x] <path>  # abandoned: <reason>` — **excluded**: checked-off so "next unchecked" never re-picks it; the reason is also logged in `## Progress`. Because `remaining` counts only `- [ ]` items, a skipped/abandoned item does **not** block `## Status: done`. (This is the documented way to unblock an `escalated`-parked run without merging — see `skills/automate-loop/SKILL.md` §5/§9.)
- **Order = processing order** (top-down).

### `## Current` fields

| Field | Values | Notes |
|---|---|---|
| `status` (item-level) | `running` \| `awaiting_merge` \| `escalated` \| `failed` \| `rate_limit` \| `drain_died` \| `done` | The state of the in-flight item. Distinct from the run-level `## Status` enum above. `rate_limit`/`drain_died` mirror `pause_reason` exactly the way `awaiting_merge`/`escalated` already do — never a separate `parked` placeholder. |
| `pause_reason` | `awaiting_merge` \| `awaiting_go` \| `escalated` \| `limit_reached` \| `resume_ambiguous` \| `rate_limit` \| `drain_died` \| `token_ceiling` \| `run_lock_held` \| `meta_unreachable` \| `trail_pr_open` \| `closeout_leftover` \| `null` | Non-null whenever `## Status: paused`; `null` while `running`/`done`. `awaiting_go`: the `## Current` item was closed out by `closeout` (its PR merged; item `status: done`) and the next item waits for the owner's explicit `--resume` — written ONLY by `closeout`, ONLY when `## Current` names that item and PR and `## Status` is `paused` (a `running` run gets `null`) — see `skills/automate-loop/SKILL.md` §3 "After a close-out". `rate_limit`: the loop's own `agent_lifecycle: failed` row (main-scope, `reason: rate_limit`) fired during RUN, before a PR existed — see `skills/automate-loop/SKILL.md` §6 "Rate-limit park". `drain_died`: RECONCILE (§4) found a `.supervisor/review-dispatch/*.died` marker for this item's PR — a DETACHED `dispatch-pr-review.sh` drain exited without ever producing a `REVIEW_HEAL_RESULT` — see `skills/automate-loop/SKILL.md` §4. `token_ceiling` (red-team-hardening/06): PICK-time `automate-helpers.sh ceiling-check` found the run's summed ledger over `## Run Config`'s `max_tokens`, or the reader answered `LEDGER_UNREADABLE=1` (fail CLOSED) — see §6 step 1. `run_lock_held`: PICK-time `run-lock.sh acquire` found `.supervisor/run.lock` held by another run/process — see §6 step 1 / §11. Both new values are RUN-level-only parks fired BEFORE an item is picked, so — like `limit_reached`/`resume_ambiguous` — they have no item-level `status` counterpart in the enum above. `meta_unreachable`: branch mode's `automate-helpers.sh meta-entry` failed on a `--resume <id>` of an existing local run file (pull exit non-zero or mode `unknown`) — the `## Progress` line names the reason (a conflict names its path); a RUN-level park with no item-level `status` counterpart, like `limit_reached` / `resume_ambiguous` — see `skills/automate-loop/SKILL.md` §13. `trail_pr_open`: the PICK-time `automate-helpers.sh trail-gate` found this run's own trail PR (`chore/<run_id>-trail-<n>`) open, or could not read its state (fail CLOSED) — the single-open-PR invariant counts the trail PR, because its merge would move the base under the next item's PR (`BEHIND` under `strict` required checks); the `## Progress` line names the PR. Written after RECONCILE, with the run-lock held and released at the park; no item-level `status` counterpart (the `## Current` item is the previous, closed-out one) — see `skills/automate-loop/SKILL.md` §6 step 1 / §8. `closeout_leftover` (automate-followups/32): a close-out could not safely finish one of its steps (a kept worktree or branch, a refused sync, a result line nobody classified) and the owner chose Stop — or the run is non-interactive, which never proceeds past a leftover silently; a RUN-level park with no item-level `status` counterpart, written with `automate-helpers.sh current-set`'s run-level form. The verdict comes from `automate-helpers.sh closeout-classify` (one `closeout` invocation at a time; anything but `complete` is a leftover); each leftover gets one `closeout leftover: <run_id> <step> <detail>` `## Progress` line — see `skills/automate-loop/SKILL.md` §6 step 1 "Close-out leftover gate". |
| `pr` / `branch` | string / `null` | The in-flight item's PR URL and feature branch. When the item changes, `current-set` resets an omitted `pr`/`branch` to `null`, so the previous item's PR never rides into the next item. |
| `owned_drain_started` | `<ts>` | Timestamp the engine's OWNED inline `/review-pr --until-mergeable` drain started (the latest pass's — an owner-requested fix-now re-drain overwrites it, together with `owned_drain_result`). |
| `owned_drain_result` | `READY` \| `ESCALATED` \| `died` | The drain's terminal `REVIEW_HEAL_RESULT.decision`, read synchronously. `READY` is "ready, left open for a human" — the drain **never merges**. `died` is not a `REVIEW_HEAL_RESULT` decision at all — it records a DETACHED drain's `.died` marker found at RECONCILE (see `pause_reason: drain_died` above), never this engine's own inline drain (which cannot die silently — it runs in this same turn). |
| `suppressed_default_dispatch` | `true` | Records that the engine suppressed `/autonomous`'s default detached until-mergeable drain (`.auto_review:false` around the RUN phase) so exactly ONE owned inline drain runs per pass — at most one owner-requested fix-now re-drain per item, strictly sequential (never concurrent; `skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)"). Verifiable via these fields **plus** the absence of any detached `dispatch-pr-review.sh` artifact for the PR (`skills/automate-loop/SKILL.md` §7). |
| `escalation_cause` | `check_pending` \| `check_red_unrelated` \| `check_red` \| `findings` \| `other` | automate-followups/31 — OPTIONAL, present only at an `escalated` park (mirrors the `pending_decisions` OPTIONAL-line precedent). Its line also carries `check`, `run_id`, `attempt` and `sha` (each `null` when not check-driven or unreadable) — the drain's `REVIEW_HEAL_RESULT` `escalation_*` fields (`docs/result-schemas/review-heal-result.md`). The ONLY writer is `automate-helpers.sh current-escalation <runfile> --cause <c> [--check … --run-id … --attempt … --sha …]` (enum-checked, `\|`/newline refused, file byte-unchanged on refusal; placed after `- pause_reason:`, else at the end of the block; `--cause null` removes it). An item-form `current-set` that leaves `escalated` or changes the item removes it (per-item state: closeout's `done`, PICK's `running` and every non-escalated park clear it). Informational only — no gate reads it and it never permits a merge. |
| `pending_decisions` | `<n>` (integer ≥ 0) | automate-followups/12 — OPTIONAL, present only when this item's GATE produced dismissed-finding drafts in `.supervisor/requirements/proposed/` (`automate-helpers.sh dismissed-drafts`). The count of this run's drafts still `undecided` after the gate's decision step (always the full count under `--non-interactive-fallback` and at a successful `--auto-merge` MERGE, where nothing is asked); the next interactive PICK asks them (Follow-up / Drop) before RECONCILE's `closeout`. Never a new `pause_reason` value. Authority: `skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)". |
| `fix_now_reentered` | `true` \| `false` | automate-followups/12 — OPTIONAL, same line as `pending_decisions`. `true` once the owner answered `Fix now on this PR` and the item ran its ONE fix-now DRAIN → GATE re-pass; fix-now is never offered again for this item, and the loop passes `--after-fix-now` to `dismissed-drafts` only on that post-re-pass run. |

### Item lifecycle

```
queued (- [ ]) → running → rate_limit (parks, no PR yet) | pr-open → awaiting_merge → merged (- [x]) | escalated (parks) | drain_died (parks) | failed | skipped
```

- `escalated` **parks** the run (`## Status: paused`, `pause_reason: escalated`) and never opens a second PR (single-open-PR invariant — `skills/automate-loop/SKILL.md` §8/§9).
- `rate_limit` **parks** the run (`## Status: paused`, `pause_reason: rate_limit`) BEFORE a PR ever exists — RUN itself failed on a rate-limit `StopFailure` (`skills/automate-loop/SKILL.md` §6 "Rate-limit park"). It resumes through the SAME RESUME reconcile as `awaiting_merge`/`escalated` (§4) — no second park vocabulary, no second reconcile path.
- `drain_died` **parks** the run (`## Status: paused`, `pause_reason: drain_died`, `owned_drain_result: died`) when RECONCILE (§4) finds a `.died` marker for this item's PR from a DETACHED `dispatch-pr-review.sh` drain that exited without ever producing a `REVIEW_HEAL_RESULT` — **never `awaiting_merge`**, since a died drain never reached a real READY/ESCALATED verdict. Resolves through the same RESUME reconcile path as the other parks.
- `skipped`/`abandoned` items are written `- [x] <path>  # skipped|abandoned: <reason>` (above) so they are never re-picked and do not block `done`.

### Crash-safety contract

The run file is the **only** copy of resume state, so (per `skills/automate-loop/SKILL.md` §3):

- **Atomic write (temp + rename):** every update is written to a temp file and `mv`-renamed into place — a crash mid-write never leaves a half-written file; the prior intact version survives.
- **Validated before rename (fail CLOSED on the payload):** `automate-helpers.sh runfile-write` refuses (exit 1, temp removed, run file byte-unchanged, stderr tag `[runfile_write_refused]`) staged content that is empty, lacks the `# Automate Run:` title, a `## Status:` line or the `## Queue` heading, or — replacing an existing run file — does not keep its `## Progress` block as a prefix; `progress-append` / `queue-checkoff` refuse a target with no title instead of fabricating a `## Progress` stub on it. A shrinking line count is NOT a refusal reason (`## Current` legitimately loses lines) — the deliberate difference from `VERIFY_QUEUE`'s line-count guard below. Spec: `skills/automate-loop/SKILL.md` §3 "Validate before rename".
- **`## Progress` is APPEND-ONLY** — never rewritten; existing lines are immutable, new lines are appended.
- **Rewrites are confined** to `## Queue` checkboxes and the `## Current` block (`## Status` changes atomically and rarely; `## Source`/`## Run Config` change rarely).
- **`## Current` moves only through `automate-helpers.sh current-set`** (item form or run-level form, enum-validated, exit 1 with the file byte-unchanged on a refusal); `progress-append` exits 3 with `current_not_set: <line>` on stderr (the line still appended) when a `picked` / `ran /autonomous` / `owned drain started` line meets an unset `## Current`, and RESUME's `current-rebuild` repairs one that was never set, or a `done` one left naming the previous item after the next `picked` line (a `picked` line over a `done` `## Current` is exempt from the exit 3, so this RESUME repair is its only backstop). Spec: `skills/automate-loop/SKILL.md` §3 "`## Current` moves only through `current-set`".
- **Resume = belief vs truth:** the run file is the loop's *belief*; on every start the engine reconciles each in-flight item against ground truth (`gh pr view --json state,mergedAt` / `git branch --contains` / the requirement's `## Status: done` stamp) **before** trusting a checkbox (`skills/automate-loop/SKILL.md` §4).

### Optional terminal JSONL breadcrumb (secondary — never the source of truth)

The engine MAY append **ONE** terminal line per run to the existing `.supervisor/logs/<run_id>.jsonl` (the shared session-log convention) for trend tooling. This is a **secondary breadcrumb only** — the run file (`.supervisor/automate/<run_id>.md`) remains **authoritative** for all resume/state decisions; the JSONL line is never read as the source of truth.

**Cross-references:**
- `loomwright/skills/automate-loop/SKILL.md` — the **authority** for the run-file layout, the item lifecycle, resume/reconcile, the single-drain contract, and the two modes. This section documents §3/§4/§5/§6/§7 of that skill; do NOT change names here without updating the skill first.
- `loomwright/commands/automate.md` — the `/automate` command body.
- `AUTONOMOUS_RUN` schema (above) — the sibling inline-workflow state artifact (`/autonomous`), likewise not hook-validated; the `/automate` per-item RUN step drives `/autonomous --single-iteration`.

---

