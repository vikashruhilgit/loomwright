## §3 — The single run file (`.supervisor/automate/<run_id>.md`)

**The single-file principle (this design's core):** there is **no manifest, no registry, no `progress.jsonl`, no dashboard file**. ONE markdown run file holds everything — it IS the manifest, registry, progress log, and dashboard. **"Find prior runs" = glob `.supervisor/automate/*.md` for run files — those carrying the `# Automate Run:` title line (`is_run_file`) — not marked `## Status: done`** (§4). The only other artifacts are sidecars, never runs: a *transient* config-backup sidecar that exists only during a tick (§7), and the two per-run result sidecars `<run_id>.supervisor-result.md` / `<run_id>.review-heal-result.md` written verbatim at §6 steps 2–3 (overwritten per item; they carry no `# Automate Run:` title, so RESUME never lists them).

### Run-file template (reproduce exactly)

```md
# Automate Run: <title>
## Status: running          # running | paused | done   (paused = stopped, work remains; done only when the Queue is fully resolved)
## Source
- <user prompt text | folder <dir> | backlog <_BACKLOG.md> | ...>     # folder/backlog path repo-relative; every run-file write rewrites an absolute one under the checkout root
## Run Config
- mode: safe|auto-merge | limit: 5 | trust_unprotected: false
- auto_review_original: <true|false|absent> | config_backup: <run_id>.config-backup.json
- max_tokens: <N|absent>          # ONLY present when --max-tokens was passed; opt-in, PERSISTED (unlike --notify) so a bare --resume still enforces it
- parallel: <N|absent>            # present on any --parallel parent run, 1 included (N = 1 = single-lane mode, §14); absent on every sequential run and inside every lane
- auto_gates: off                 # ONLY present when --no-auto-gates or config.json {"auto_gates": false} turned the `auto` gate tier off; PERSISTED so a bare --resume keeps it; lane-create carries it into lane.json as auto_gates: false
- cheap: true                     # ONLY present while --cheap is on (written with --cheap, removed by --no-cheap); PERSISTED so a bare --resume keeps the Sonnet profile; any other value reads as off; never inside a lane (lane.json is its record) nor on a --parallel coordinator's run (re-pass --cheap on its --resume)
## Queue                    # `- [ ]` queued · `- [x]` done (merged) · `- [x] … # skipped|abandoned:` excluded; order = processing order
- [ ] <requirement path or generated file>
- [x] <... merged ...>
- [x] <... path ...>  # skipped: <reason>     # checked-off so "next unchecked" never re-picks it; reason also in ## Progress
## Current
- item: <path> | status: running|awaiting_merge|ready_for_release|escalated|failed|rate_limit|drain_died|done | pr: <url> | branch: <name>
- pause_reason: awaiting_merge|ready_for_release|awaiting_go|escalated|limit_reached|resume_ambiguous|rate_limit|drain_died|token_ceiling|run_lock_held|meta_unreachable|trail_pr_open|closeout_leftover|scope_hold|live_lane|phase_relay_unavailable|no_pr_stop|null
- wave: <k> | items: <i1>, <i2>     # present ONLY on a --parallel N>1 parent run; written only by `current-wave` (§14)
- owned_drain_started: <ts> | owned_drain_result: READY|ESCALATED|died|superseded_by_merge | suppressed_default_dispatch: true     # each value's meaning: docs/result-schemas/automate-run.md §"`## Current` fields" (`sub_floor_converged` READY is NOT merge-eligible, §10 cond 1)
- escalation_cause: check_pending|check_red_unrelated|check_red|findings|validation_unrun|other | check: <c|null> | run_id: <id|null> | attempt: <n|null> | sha: <sha|null>     # present ONLY at an `escalated` park; written only by `current-escalation`
- pending_decisions: <n> | fix_now_reentered: <true|false>     # present ONLY when this item produced dismissed-finding drafts (§6 "Dismissed-findings decision step")
- ready_sha: <sha> | ready_at: <ISO-8601 Z> | termination_reason: <tr>     # present ONLY after a READY drain whose report carried ready_sha; read by --merge-parked (§4 "Merging one parked item")
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <item>
- <ts> session_id <id> (<item>)     # one per session RUN used (fresh phases: `session_id <id> (<item>) phase=launch-pad|supervisor|drain`, plus `launch-pad saved <brief>` and the coordinator's own `phase=driver` line); read-token-ledger.sh --run-id sums them
- <ts> ran /autonomous → PR <url>
- <ts> drain READY → awaiting_merge
```

**Inside a lane (§14):** when `automate-helpers.sh lane-info` exits 0, the run id AND the title come from `.supervisor/lane.json` verbatim — `<run_id>` is its `run_id` (`<parent_run_id>-L<n>`) and the title line is `# Automate Run: <parent_run_id>-L<n> — <item path>`. The lane never mints its own id (no helper mints run ids — this rule is the engine's), and its `## Run Config` carries no `parallel:` line.

### Item lifecycle

```
queued (- [ ]) → running → rate_limit (parks, no PR yet) | pr-open → awaiting_merge → merged (- [x]) | ready_for_release (an N>1 lane's READY park, §14; a single lane — `--parallel 1` — parks awaiting_merge: `lane-park`) | escalated (parks) | failed | skipped
```

### `## Status` semantics

- **`running`** — the loop is actively processing (or is the freshly-created run).
- **`paused`** — stopped with work remaining; always paired with a `pause_reason` from the template's list. `ready_for_release` is an N>1 lane's terminal READY park, inside such a lane only; the RUN-level parks are written with `current-set`'s run-level form (the table below).
- **After a close-out — `paused` + `awaiting_go`.** `closeout` leaves `## Status: paused`, the `## Current` item `status: done` and `pause_reason: awaiting_go` (never `null` on a paused run, and never `done`, even after checking off the last item). Inside a live loop (RECONCILE, `## Status: running`) it writes `pause_reason: null` and PICK goes on. A `--resume` of an `awaiting_go` run falls straight through to PICK.
- **`done`** — set **only** when the Queue is **fully resolved** (no `- [ ]` items remain), with the `--reason done` trail, by the §6 "Termination" exit of a live loop or by `finalize-empty` (§4 step 1, via `resume-glob --finalize`) for a `paused` + `awaiting_go` run with `remaining` 0. `remaining` is COMPUTED (`automate-helpers.sh remaining`), never a stored run-file field.

### Crash-safety contract (HIGH-risk mitigation — run-file is the ONLY copy of resume state)

> **Execute via the helper, not a re-implementation:** `automate-helpers.sh runfile-write <runfile>` (full atomic write, content on stdin), `progress-append <runfile> <line>`, `queue-checkoff <runfile> <item> [reason] [mark]` (`mark` = `skipped` (default) or `abandoned`, §5), `current-set <runfile> …` and `remaining <runfile>` (§1.5). The contract below is the SPEC those subcommands implement.

- **Atomic write (temp + rename):** every run-file update is written to a temp file and `mv`-renamed into place; a crash mid-write leaves the prior intact version.
- **Validate before rename (fail CLOSED on the payload):** `runfile-write` stages stdin and refuses (exit 1, temp removed, run file **byte-unchanged**) content that is empty, lacks the `# Automate Run:` title, a `## Status:` line or a `## Queue` heading, or — replacing a run file — does not begin its `## Progress` block with the existing one line-for-line. `progress-append` and `queue-checkoff` refuse a target with no `# Automate Run:` title and validate their output the same way. **Recovery is a human act:** never "fix" a refusal by writing the file another way.
- **`## Progress` is APPEND-ONLY** — it is **never rewritten**.
- **Rewrites are confined** to `## Queue` checkboxes and the `## Current` block; `## Status`/`## Source`/`## Run Config` change rarely and atomically.
- **A gate input a later session needs lives in the run file, never only in the sidecar.** The driver's `<run_id>.next-step.json` sidecar is wiped by every `--resume`, so it holds only this pass's working state. The durable READY record is the `- ready_sha:` line: `drain-result` writes it through `runfile-write` when a drain (the first one or the fix-now re-drain, which replaces it in place) ends `READY` and its report carries `ready_sha`, with `ready_at` set to the time the report was recorded. A READY report with no `ready_sha` writes no line. `--merge-parked` reads `ready_sha` and `termination_reason` from this line and `drain_result` from `owned_drain_result`.
- **Optional secondary breadcrumb:** ONE terminal line per run **appended** to `.supervisor/logs/<run_id>.jsonl` — **never the source of truth**.

### `## Current` moves only through `current-set`

Every write of `## Current`'s `- item: … | status: … | pr: … | branch: …` line and its `- pause_reason:` line is ONE `automate-helpers.sh current-set` call (§1.5); the `owned_drain_*` / `pending_decisions` / `reason_hint` lines are left to the steps that own them. The calls, in loop order:

| Transition | Call |
|---|---|
| §6 step 1 PICK (BEFORE its `picked` Progress line) | `current-set <rf> --item <path> --status running --pr null --branch null --pause-reason null` |
| §6 step 2 RUN produced a PR (BEFORE its `ran /autonomous → PR` line) — driver step `run-record` | `current-set <rf> --item <path> --status running --pr <url> --branch <b>` |
| §6 step 3 DRAIN start — driver step `drain-result` | none — item `status` stays `running`; `owned_drain_started` stays its own line |
| Rate-limit park (§6 step 2 — driver step `rate-limit`) | `current-set <rf> --item <path> --status rate_limit --pause-reason rate_limit` |
| `drain_died` park (§4) | `current-set <rf> --item <path> --status drain_died --pause-reason drain_died` |
| Lane READY park (§14 — inside an N>1 lane only; a single lane writes the `awaiting_merge` park, and `current-set` refuses `ready_for_release` there) | `current-set <rf> --item <path> --status ready_for_release --pause-reason ready_for_release` |
| GATE `awaiting_merge` park (§9) | `current-set <rf> --item <path> --status awaiting_merge --pause-reason awaiting_merge` |
| GATE `escalated` park (§9) | `current-set <rf> --item <path> --status escalated --pause-reason escalated` |
| Close-out of the `## Current` item (§6 "Post-merge close-out") | `closeout` itself: `current-set <rf> --item <stored item> --status done --pause-reason awaiting_go\|null` |
| RUN-level parks — `run_lock_held`, `token_ceiling`, `phase_relay_unavailable`, `trail_pr_open`, `limit_reached`, `resume_ambiguous`, `scope_hold`, `meta_unreachable`, `closeout_leftover`, `live_lane`, `no_pr_stop` | `current-set <rf> --pause-reason <reason>` (the run-level form — the item line is never touched; `ready_for_release` is never run-level — the lane row above) |
| `finalize-empty` (§4 step 1) | `current-set <staged copy> --pause-reason null` (run-level form) on the copy whose `## Status` it already rewrote to `done`, then ONE `runfile-write` of that copy — so the run file still changes atomically and a refusal leaves it byte-unchanged and still eligible |

`current-set` validates every value against the enums above, refuses a half-null item form, an item form missing `--item` or `--status`, a run-level form missing `--pause-reason`, and any value carrying `|`, a newline or any other control character (exit 1, file byte-unchanged). When `--item` changes, an omitted `--pr`/`--branch` resets to `null`, and the item's `- ready_sha:` line is dropped so it never rides into the next item (a same-item write keeps it). A refusal is never "fixed" by writing the file another way.

**The guard.** A `picked `, `ran /autonomous` or `owned drain started` line appended while `## Current`'s item is unset — or a `picked <X>` while `## Current` names a different item whose status is not `done` — makes `progress-append` exit **3** with `current_not_set: <line>` (the line is still appended); the engine stops and runs the missing `current-set` before going on. A RUN-level park's `## Progress` line must not start with one of those three prefixes. **Honest limit:** a `picked <X>` while `## Current` still names the previous, `done` item exits 0 — a closed-out item does not prove the next PICK set `## Current`. §4 step 2's `current-rebuild` repairs that stale `## Current` at RESUME only.
