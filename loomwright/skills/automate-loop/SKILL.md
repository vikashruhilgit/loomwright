---
name: automate-loop
description: Protocol authority for `/automate` — the generic automation engine that converts ANY source (a prompt via /product-owner, a requirements folder, or a backlog-doc) into a FULL Queue with a per-run processing cap inside ONE markdown run file (`.supervisor/automate/<run_id>.md` — the contract, dashboard, and resume state), then drives each Queue item through the per-item loop (`/autonomous --single-iteration` → owned inline `/review-pr --until-mergeable` → trusted-merge-or-park → pull main → check off + append `## Progress`). Smart resume = glob run files (`# Automate Run:` title, `is_run_file`) not stamped done + reconcile-vs-ground-truth. Use when implementing or invoking `/automate`.
allowed-tools: [Read, Write, Edit, Bash, Task, AskUserQuestion]
version: "1.17.0"
lastUpdated: "2026-10-11"
---

# Automate Loop Skill

The **single source of truth** for the `/automate` generic automation engine — the protocol that walks **arbitrary work from any starting point** through to a reviewed PR (and, opt-in, a trusted merge). This skill is the **authority**; the `/automate` command body (`${CLAUDE_PLUGIN_ROOT}/commands/automate.md`), the `AUTOMATE_RUN` run-file layout in `docs/RESULT_SCHEMAS.md`, and the helper scripts under `scripts/` all **reference** the names and contracts coined here and must not re-coin or rename them.

> This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/review-heal/SKILL.md` and `skills/autonomous-loop/SKILL.md`. There is **no `-runner` agent** — `/automate` is inline-only (agents stay 14).
<!-- index-only:begin -->

> **Split layout (parallel-automate/22, move-only).** This file is the skill's index. A section below that carries only a `See [<file>](<file>).` line was moved verbatim to that file in this directory — read the file for the section; every `§N` number and heading is unchanged. Which split file the inline engine reads, and when, is decided in one place: `commands/automate.md` Step 0. `scripts/test-automate-loop-split.sh` keeps this index and the files in step.
<!-- index-only:end -->

---

## §1 — Purpose & Layering

The plugin can drive **one** requirement deep (`/autonomous`), but nothing walks **arbitrary** work from any starting point. `/automate` is the outermost loop. The layering is strictly nested:

```
/autonomous (one requirement)  ⊂  per-item loop  ⊂  /automate (source → Queue → loop)
```

- **`/autonomous`** runs one requirement end-to-end to a PR (Launch Pad → Supervisor, with Phase 4.5 self-heal + Rubric Grader). The engine drives it `--single-iteration`.
- **The per-item loop** wraps a single `/autonomous` run with an OWNED until-mergeable drain, a trusted-merge-or-park gate, and a `main` re-sync — see §6.
- **`/automate`** resolves a SOURCE into a `## Queue` once, materializes ONE run file, and drives each Queue item through the per-item loop.

The per-item engine is **source-agnostic** — only the *intake* differs, and intake is just "convert the source into the run file's Queue, once" (§2). It is **NOT a pluggable adapter framework**. **`/backlog` is NOT a separate command** — a folder or a backlog-doc is simply one *kind* of source.

### Non-goals (v1)

- Sources beyond **prompt / folder / backlog-doc** (issues, Beads `bd ready`, Jira are additive later — each just populates the Queue, no framework).
- A `-runner` agent (inline-only; agent count stays 14).
- QA-in-loop.
- Parallel execution beyond `--parallel N` lanes (§14): one wave at a time, lanes on this machine only; merging the wave PR is the owner's — the engine builds the wave branch (lane merges, local CI, the release bump) and opens the wave PR (`wave-build`, §14 "Wave close"), never merging it.
- **Multiple concurrent open PRs in one run file** — BOTH modes keep a **single-open-PR invariant** (§8): one open PR per run file, so one per lane under `--parallel N`; `escalated` parks the run, it never opens a second PR.
- A separate registry / manifest / `progress.jsonl` / dashboard file — the **single run file is enough** (§3).

---

## Coordinator loop — run next-step; do the one instruction; report the result

The default path of every `/automate` run (automate-speed/06–08). `scripts/automate-next-step.sh`, invoked from the plugin root's `scripts/` like every helper, runs every deterministic step of resume, PICK, RECONCILE, RUN, DRAIN, GATE, the park and the close-out itself, writes the run file only through the helpers, and prints ONE JSON instruction per call. The main thread's whole job:

1. **Start.** After the start steps `commands/automate.md` Step 0 names (`lane-info`, `init-check` with `--parallel`, `meta-entry`), call `automate-next-step.sh --resume .supervisor/automate --session-id <sid>` — plus `--run latest` for `/automate --resume`, `--run <run_id>` for `/automate --resume <run_id>`. A `{"do":"done","status":"stopped","choice":"start_new"}` answer, or no incomplete run to resume, is a NEW run: intake (§2), then `automate-next-step.sh <runfile> --start pick --session-id <sid>`. A `--parallel` coordinator run (`## Run Config` carries `- parallel: N`) is never picked in the primary: on continue the driver answers `{"do":"done","status":"stopped","stop":"coordinator_run"}` (no write past the start steps), and the run continues through [lanes.md](lanes.md)'s per-wave loop (single-lane mode for `parallel: 1`).
2. **Do the one instruction, then report it.** `spawn` — run its `invocation` (`drain_invocation` for a fix-now re-drain; the pass owns one drain, at most one owner-requested fix-now re-drain per item, strictly sequential) and call again with the `--result` its `then` names, also when the work failed. `ask` — one ask-tool call with its `questions`; report `{"answers":[…]}`, or `{"cant_ask":true}` when the ask tool is unavailable. `park` — stop the loop: the park state, watcher, notify and run-lock release are already done. `done` — `running`: call `--start pick` for the next item; `done`: the Queue is resolved, stop; `stopped`: report its `message` and stop.
3. **Flags.** Pass `--mode safe|auto-merge`, `--non-interactive` (under `--non-interactive-fallback`), `--trust-unprotected`, `--notify`, `--cheap` and `--max-tokens N` as `/automate` received them, and re-pass the non-persisted ones (`--notify`, `--cheap`, `--non-interactive-fallback`) on every `--resume` and `/loop` tick.
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

## §3 — The single run file (`.supervisor/automate/<run_id>.md`)

**The single-file principle (this design's core):** there is **no manifest, no registry, no `progress.jsonl`, no dashboard file**. ONE markdown run file holds everything — it IS the manifest, registry, progress log, and dashboard. **"Find prior runs" = glob `.supervisor/automate/*.md` for run files — those carrying the `# Automate Run:` title line (`is_run_file`) — not marked `## Status: done`** (§4). The only other artifacts are sidecars, never runs: a *transient* config-backup sidecar that exists only during a tick (§7), and the two per-run result sidecars `<run_id>.supervisor-result.md` / `<run_id>.review-heal-result.md` written verbatim at §6 steps 2–3 (overwritten per item; they carry no `# Automate Run:` title, so RESUME never lists them).

### Run-file template (reproduce exactly)

```md
# Automate Run: <title>
## Status: running          # running | paused | done   (paused = stopped, work remains; done only when the Queue is fully resolved)
## Source
- <user prompt text | folder <dir> | backlog <_BACKLOG.md> | ...>
## Run Config
- mode: safe|auto-merge | limit: 5 | trust_unprotected: false
- auto_review_original: <true|false|absent> | config_backup: <run_id>.config-backup.json
- max_tokens: <N|absent>          # red-team-hardening/06 — ONLY present when --max-tokens was passed; opt-in, PERSISTED (unlike --cheap/--notify) so a bare --resume still enforces it
- parallel: <N|absent>            # parallel-automate/05 — present on any --parallel parent run, 1 included (N = 1 = single-lane mode, twin-remediation/08b, §14); absent on every sequential run and inside every lane
## Queue                    # `- [ ]` queued · `- [x]` done (merged) · `- [x] … # skipped|abandoned:` excluded; order = processing order
- [ ] <requirement path or generated file>
- [x] <... merged ...>
- [x] <... path ...>  # skipped: <reason>     # checked-off so "next unchecked" never re-picks it; reason also in ## Progress
## Current
- item: <path> | status: running|awaiting_merge|ready_for_release|escalated|failed|rate_limit|drain_died|done | pr: <url> | branch: <name>
- pause_reason: awaiting_merge|ready_for_release|awaiting_go|escalated|limit_reached|resume_ambiguous|rate_limit|drain_died|token_ceiling|run_lock_held|meta_unreachable|trail_pr_open|closeout_leftover|live_lane|null
- wave: <k> | items: <i1>, <i2>     # parallel-automate/05 — present ONLY on a --parallel N>1 parent run; written only by `current-wave` (§14)
- owned_drain_started: <ts> | owned_drain_result: READY|ESCALATED|died|superseded_by_merge | suppressed_default_dispatch: true (`READY`'s `termination_reason` — `converged` or `sub_floor_converged`, mechanized bound via `scripts/drain-rounds.sh` — is read straight through from `REVIEW_HEAL_RESULT`; `sub_floor_converged` is NOT merge-eligible, §10 cond 1. `died` — red-team-hardening item 04 — is NOT a `REVIEW_HEAL_RESULT` decision at all; it means a DETACHED `dispatch-pr-review.sh` drain for this item's PR exited without ever producing one, discovered via a `.supervisor/review-dispatch/<hash>.died` marker at RECONCILE, §4 — see that section for the full contract. `superseded_by_merge` — automate-followups/20 — is NOT a `REVIEW_HEAL_RESULT` decision either; it means the owned drain started but ended without a terminal `REVIEW_HEAL_RESULT` and the PR reads `merged` (the owner merged it mid-drain), written by the engine at §6 step 3 DRAIN or at §4 RECONCILE; it skips GATE, goes to `closeout`, and is never merge-eligible — `docs/result-schemas/automate-run.md` §"`## Current` fields")
- escalation_cause: check_pending|check_red_unrelated|check_red|findings|validation_unrun|other | check: <c|null> | run_id: <id|null> | attempt: <n|null> | sha: <sha|null>     # automate-followups/31 — present ONLY at an `escalated` park; written only by `current-escalation`, removed by an item-form `current-set` that leaves `escalated` or changes the item (docs/result-schemas/automate-run.md)
- pending_decisions: <n> | fix_now_reentered: <true|false>     # automate-followups/12 — present ONLY when this item produced dismissed-finding drafts (§6 "Dismissed-findings decision step (before the park)")
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <item>
- <ts> session_id <id> (<item>)     # red-team-hardening/06 — the Supervisor session RUN just used; read-token-ledger.sh --run-id sums every session_id line in this file
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
- **`paused`** — stopped with work remaining; always paired with a `pause_reason` (`awaiting_merge` | `ready_for_release` — an N>1 lane's terminal READY park, inside such a lane only (a single lane's READY park is `awaiting_merge` — the park `lane-park` prints), §14 | `awaiting_go` | `escalated` | `limit_reached` | `resume_ambiguous` | `rate_limit` | `drain_died` | `token_ceiling` | `run_lock_held` | `meta_unreachable` — branch mode's `meta-entry` failed on a `--resume` of an existing run, §13 | `trail_pr_open` — §6 step 1's trail gate | `closeout_leftover` — a close-out could not safely finish a step (a kept worktree/branch, a refused sync, an unknown result line) and the owner chose Stop or the run is non-interactive — §6 step 1 "Close-out leftover gate"; a RUN-level park written with `current-set`'s run-level form | `live_lane` — §6 step 1's lane guard (`pick-guard`) found a live lane of an open `--parallel` wave in this checkout, §14; a RUN-level park written with `current-set`'s run-level form).
- **After a close-out — `paused` + `awaiting_go`.** Once `closeout` has closed out the `## Current` item (its PR merged; §6 "Post-merge close-out"), nothing is in flight and nothing blocks the run, but the next item still waits for the owner's explicit go (`/automate --resume`; `closeout` never picks). That state reads: `## Status: paused` (unchanged — the run is stopped, and `done` is reserved for the Queue-resolved termination with its `--reason done` trail, which `closeout` never writes, even when it checked off the last item), `## Current` item `status: done`, `pause_reason: awaiting_go`. `null` is NOT used here: `null` means "not paused" (`running`/`done`), and a `paused` run with `pause_reason: null` would break the pairing rule above. When `closeout` runs inside a live loop (RECONCILE, `## Status: running`), it writes `pause_reason: null` instead — the loop is running and its PICK goes on. A `--resume` of an `awaiting_go` run needs no reconcile for that item (it is `- [x]` and `done`); it falls straight through to PICK.
- **`done`** — set **only** when the Queue is **fully resolved** (no `- [ ]` items remain), i.e. `remaining: 0`. Two writers, both with the `--reason done` trail: the §6 "Termination" exit of a live loop, and `finalize-empty` (§4 step 1, via `resume-glob --finalize`) for a run left `paused` + `awaiting_go` with `remaining` 0 and its `## Current` item `status: done` — the state `closeout` leaves after checking off the last item, since `closeout` itself never writes `done`. `remaining` is **COMPUTED/REPORTED** (the count of `- [ ]` Queue items, via `automate-helpers.sh remaining`) — it is **NOT a persisted run-file field**; the template stores no `remaining:` line.

### Crash-safety contract (HIGH-risk mitigation — run-file is the ONLY copy of resume state)

> **Execute via the helper, not a re-implementation:** the run-file mutations are done by shelling out — `automate-helpers.sh runfile-write <runfile>` (full atomic write, content on stdin), `automate-helpers.sh progress-append <runfile> <line>` (append-only `## Progress`), `automate-helpers.sh queue-checkoff <runfile> <item> [reason] [mark]` (flip `- [ ]` → `- [x]`; `mark` = `skipped` (default) or `abandoned`, §5), `automate-helpers.sh current-set <runfile> …` (the `## Current` item / `pause_reason` lines — the subsection below), and `automate-helpers.sh remaining <runfile>` (COMPUTED `- [ ]` count) (§1.5). The contract below is the SPEC those subcommands implement.

- **Atomic write (temp + rename):** every run-file update is written to a temp file and `mv`-renamed into place. A crash mid-write never leaves a half-written file — the prior intact version remains.
- **Validate before rename (fail CLOSED on the payload):** temp+rename protects against a crash *mid-write*, but it installs whatever the temp file holds — and the engine builds rewrites as `<generator> "$RF" | automate-helpers.sh runfile-write "$RF"`, where a generator that errors (BSD awk rejecting a newline in a `-v` value, an unescaped delimiter in a `sed`, a failed redirect) prints nothing and the helper cannot see its exit status. So `runfile-write` stages stdin to the temp file and validates it **before** the `mv`; any failure is exit 1 with the temp file removed and the run file **byte-unchanged**. It refuses when the staged content: (1) is empty; (2) lacks the `# Automate Run:` title line (`is_run_file` — without it `resume-glob` stops listing the run); (3) lacks a `## Status:` line (without it `is_done` can never fire and RESUME cannot tell `running`/`paused`/`done`); (4) lacks a `## Queue` heading (without it `remaining` computes `0` and the run looks finished); or (5) — when the file being replaced is already a run file — does not begin its `## Progress` block with the existing `## Progress` block line-for-line (the APPEND-ONLY rule below, enforced: a truncated generator keeps the header sections and silently drops the tail). A shrinking line count is deliberately **not** a refusal reason (unlike `/verify`'s `queue-write`): `## Current` legitimately loses lines (e.g. `pending_decisions:` disappears when the next item is picked). `progress-append` and `queue-checkoff` validate the same way: both refuse a target that is not a run file (no `# Automate Run:` title) instead of fabricating structure on it, and both put their own output through the same pre-rename check. **Recovery is a human act:** a refusal leaves the prior run file in place; never "fix" a refusal by writing the file another way.
- **`## Progress` is APPEND-ONLY** — it is **never rewritten**. New lines are appended; existing lines are immutable.
- **Rewrites are confined** to `## Queue` checkboxes and the `## Current` block. `## Status`/`## Source`/`## Run Config` change rarely and atomically; `## Progress` only grows.
- **Optional secondary breadcrumb:** ONE terminal line per run **appended** to the existing `.supervisor/logs/<run_id>.jsonl` (the shared session-log convention) for trend tooling — **never the source of truth**.

### `## Current` moves only through `current-set`

`## Current` is the resume state RESUME trusts first, so it is never left to prose: every write of its `- item: … | status: … | pr: … | branch: …` line and its `- pause_reason:` line is ONE `automate-helpers.sh current-set` call (§1.5), and the `owned_drain_*` / `pending_decisions` / `reason_hint` lines are left to the steps that own them. Lane w1-10 (run `automate-2026-10-04-103627`) wrote `## Current` once at creation and never again — every later event was a `progress-append` — so a RESUME mid-drain would have read "nothing in flight" while a PR was open. The calls, in loop order:

| Transition | Call |
|---|---|
| §6 step 1 PICK (BEFORE its `picked` Progress line) | `current-set <rf> --item <path> --status running --pr null --branch null --pause-reason null` |
| §6 step 2 RUN produced a PR (BEFORE its `ran /autonomous → PR` line) — driver step `run-record` | `current-set <rf> --item <path> --status running --pr <url> --branch <b>` |
| §6 step 3 DRAIN start — driver step `drain-result` | none — item `status` stays `running`; `owned_drain_started` stays its own line |
| Rate-limit park (§6 step 2 — driver step `rate-limit`) | `current-set <rf> --item <path> --status rate_limit --pause-reason rate_limit` |
| `drain_died` park (§4) | `current-set <rf> --item <path> --status drain_died --pause-reason drain_died` |
| Lane READY park (§14 — inside an N>1 lane only, replaces the `awaiting_merge` park; a single lane — `lane-park` prints `awaiting_merge` — writes the `awaiting_merge` park, and `current-set` refuses `ready_for_release` there) | `current-set <rf> --item <path> --status ready_for_release --pause-reason ready_for_release` |
| GATE `awaiting_merge` park (§9) | `current-set <rf> --item <path> --status awaiting_merge --pause-reason awaiting_merge` |
| GATE `escalated` park (§9) | `current-set <rf> --item <path> --status escalated --pause-reason escalated` |
| Close-out of the `## Current` item (§6 "Post-merge close-out") | `closeout` itself: `current-set <rf> --item <stored item> --status done --pause-reason awaiting_go\|null` |
| RUN-level parks — `run_lock_held`, `token_ceiling`, `trail_pr_open`, `limit_reached`, `resume_ambiguous`, `meta_unreachable`, `closeout_leftover`, `live_lane` | `current-set <rf> --pause-reason <reason>` (the run-level form — the item line is never touched; `ready_for_release` is never run-level — the lane row above) |
| `finalize-empty` (§4 step 1) | `current-set <staged copy> --pause-reason null` (run-level form) on the copy whose `## Status` it already rewrote to `done`, then ONE `runfile-write` of that copy — so the run file still changes atomically and a refusal leaves it byte-unchanged and still eligible |

`current-set` validates every value against the enums above (`pause_reason` incl. `closeout_leftover`, `ready_for_release` and `live_lane`), refuses a half-null item form, an item form missing `--item` or `--status`, a run-level form missing `--pause-reason`, and any value carrying `|` or a newline (exit 1, file byte-unchanged), and writes through the same `_runfile_install … full` validation as `runfile-write`. When `--item` changes, an omitted `--pr`/`--branch` resets to `null` — the previous item's PR never rides into the next item (`gate-eval` and `closeout` key on it). A refusal is never "fixed" by writing the file another way (the crash-safety rule above).

**The guard.** `progress-append` is where a skipped `current-set` shows: a `picked `, `ran /autonomous` or `owned drain started` line (after one optional timestamp token) appended while `## Current`'s item is `null`, empty or absent — or a `picked <X>` line while `## Current` names a different item whose status is not `done` (`<X>` = the first token after `picked `, trailing `;`/`,` stripped, both sides compared after a leading `./` strip) — exits **3** with `current_not_set: <line>` on stderr. The line is still appended (loud, not lossy); the engine stops and runs the missing `current-set` before going on. `parked ` is deliberately not a guarded prefix: a RUN-level park on a fresh run legitimately has a null item, so a run-level park's `## Progress` line must not start with `picked`, `ran /autonomous` or `owned drain started`. **Honest limit:** a `picked <X>` (and the `ran /autonomous` / `owned drain started` lines after it) while `## Current` still names the previous, `done` item exits 0 — a closed-out item does not prove the next PICK set `## Current`. The backstop is §4 step 2's `current-rebuild`: it treats a `done` `## Current` whose item differs from the LAST `picked` line's item as stale and rebuilds it from that line (status `running`, the PR from a later `ran /autonomous` line). It runs only at RESUME, so a live loop that skipped the PICK's `current-set` carries the stale `## Current` until the next start.

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

```
/automate "<what you want to automate>"      # prompt source (via /product-owner) → generated requirements → Queue
/automate                                    # bare → resume an incomplete run, else ASK "what do you want to automate?"
/automate --folder <dir>                     # folder source — each *.md becomes a Queue item
/automate --backlog <_BACKLOG.md>            # backlog-doc source — dependency-ordered Queue
/automate --limit N                          # cap PROCESSED items this run, full Queue still stored (default 5)
/automate --resume [<run_id>]                # reconcile + continue a prior incomplete run file
/automate --sweep [--apply]                  # run ONLY the §1.5 `sweep` (no RESUME, no PICK, no run file) and print its output; dry run unless --apply (the owner's typed flag is the authorization); refused with a source or --resume
/automate ... --auto-merge                   # opt-in trusted-merge at the gate (gated; default OFF)
/automate ... --trust-unprotected            # allow auto-merge onto a branch without enforceable protection (§10 cond. 4 ONLY — never overrides cond. 6, the high-risk park; nothing does)
/automate ... --notify                       # passthrough to inner /autonomous (gate webhooks)
/automate ... --non-interactive-fallback     # passthrough to inner /autonomous + engine gates fail closed
/automate ... --cheap                        # passthrough to inner /autonomous (Sonnet cost profile → /supervisor; not persisted — re-pass on --resume)
/automate ... --max-tokens N                 # opt-in spend ceiling (red-team-hardening/06) — PARKS before PICK on breach; PERSISTED in ## Run Config (unlike --cheap/--notify)
/automate ... --parallel N                   # opt-in lanes (§14): up to N independent items at once, each in its own local clone; absent ⇒ no lane code path; N = 1 ⇒ single-lane mode (one fresh lane per item, parked awaiting_merge; needs branch mode); refused with --auto-merge
```

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

- **Building an adapter framework for sources.** Intake is "convert the source into the Queue, once" (§2) — three concrete resolvers (prompt/folder/backlog-doc), not a pluggable plugin system.
- **Creating a manifest / registry / `progress.jsonl` / dashboard file.** The ONE run file is the only persistent tracking artifact (§3); everything else is a sidecar — the transient config-backup (§7), the §6 result sidecars (`<run_id>.review-heal-result.md` / `<run_id>.supervisor-result.md`), and the gitignored §6 trail/watcher files — the `<run_id>.trail-staged` record, the `<run_id>.merge-watch` marker and the `<run_id>.merge-watch.log` ("Trail PR after merge and at run end", "Post-merge close-out"), and the `<run_id>.dismissed-decisions` ledger ("Dismissed-findings decision step (before the park)").
- **Rewriting `## Progress`.** It is append-only (§3) — rewriting it loses crash-recovery breadcrumbs.
- **Moving `## Current` in prose, or only in `## Progress`.** Every `## Current` item / `pause_reason` write is a `current-set` call (§3 "`## Current` moves only through `current-set`"); a `picked`/`ran /autonomous`/`owned drain started` line over an unset `## Current` exits 3 (`current_not_set`) — run the missing `current-set`, never suppress the exit.
- **Non-atomic run-file writes.** A crash mid-write would lose the ONLY copy of resume state — always temp + rename (§3).
- **Feeding `runfile-write` from a generator that can fail silently — or routing around its refusal.** Never pass a multi-line value through `awk -v` (BSD awk dies "newline in string" and prints nothing; pass it through the environment and read `ENVIRON[...]`, as `progress-append` does), never pipe an unescaped-delimiter `sed` into it, and prefer `progress-append` / `queue-checkoff` over a whole-file rewrite. A `[runfile_write_refused]` exit means the payload was bad and the run file is intact — fix the generator and retry; never write the file another way (§3 "Validate before rename").
- **Trusting a checkbox without reconciling.** The run file is *belief*; reconcile vs `gh`/`git`/`## Status: done` before trusting it (§4). A crash between merge and check-off makes them disagree.
- **Asserting "merged"/"on main" from memory.** Always verify via `gh pr view --json state,mergedAt` / `git branch --contains` (§4) — this is the stale-branch incident discipline.
- **Double until-mergeable drain.** Suppress `.auto_review` around the RUN phase and own exactly ONE inline drain per pass — at most one owner-requested fix-now re-drain per item, strictly sequential (never concurrent) (§7); never let `/autonomous`'s detached drain race the engine's.
- **Parking with dismissed findings nobody decided on — or holding the park for them.** In an interactive run the §6 "Dismissed-findings decision step (before the park)" asks fix-now / follow-up / drop per drafted finding. At a sequential READY park it asks only AFTER the park is written, the merge watcher armed, the notify sent and the run lock released, and only when `park-ask-gate` answers `ask — …`; holding a mergeable PR un-parked on an unanswered question is the anti-pattern. Fix-now is offered only on the gate's `ask — fix-now allowed` line, runs only under a re-acquired run lock, and a fix-now answer the gate or the lock no longer allows becomes a follow-up, never a push after a merge. Offering fix-now at PICK (nothing re-reads the PR state there), or a second time for the same item, is the anti-pattern too.
- **Toggling `.auto_review` at DRAIN instead of around RUN.** Both default dispatches fire *during* `/autonomous` — DRAIN is too late (§7).
- **Leaving a partial `config.json` on restore.** Restore byte-for-byte OR delete-if-originally-absent; a stray empty `config.json` shadows the legacy `notify-config.json` (§7).
- **Overwriting a malformed pre-existing `config.json`.** Abort the tick instead — never clobber a hand-edited config (§7).
- **Picking a new item while a PR is open.** Single-open-PR invariant — `awaiting_merge`, `escalated` and this run's own open trail PR (`trail_pr_open`) all block PICK (§8).
- **Retrying RUN into a rate-limit wall, or misreporting it as a dead worker.** A `reason: "rate_limit"` (or an `"unknown"` reason with a `429` hint) on the loop's OWN `agent_lifecycle: failed` row parks the item (`status`/`pause_reason: rate_limit`) and stops — it never re-invokes `/autonomous` for the same item in the same tick (§6 "Rate-limit park").
- **Promoting a `429` text hint into the classified `reason`.** The string-table fallback only ever writes a SEPARATE `reason_hint: rate_limit` field; the underlying `agent_lifecycle` row's `reason` stays whatever was actually classified (§6 "Rate-limit park").
- **Merging on bare `READY`.** `READY` ignores `REVIEW_REQUIRED`, human threads and diff risk; `--auto-merge` must pass EVERY condition of the trusted gate (§10) — fail CLOSED otherwise.
- **Reusing the Supervisor's `risk_classification` at the gate, or inventing an override for condition 6.** The loop re-runs `classify-risk.sh` on the SHA it judges (§10 cond 6); `--trust-unprotected` is cond 4 only; `.agent/risk.json` has no `exclude` key and no flag/config key lowers a classification.
- **Inventing a `gh pr view --json reviewThreads` flag.** Unresolved threads + author type are GraphQL-only (§10 cond. 3; `review-heal/SKILL.md` §"Step U1 — All-Channel Read").
- **Gating rubric on the autonomous EVALUATE loop.** Single-iteration short-circuits EVALUATE; read the rubric from `SUPERVISOR_RESULT.rubric_score` (Phase 4.5 Rubric Grader), which runs under single-iteration (§10 cond. 5).
- **Stacking a second PR on `escalated`.** An escalated PR parks the run; resolve it or mark the item `skipped`/`abandoned`, then `--resume` (§5/§9).
- **Running two `/automate` loops in one repo.** The `.auto_review:false` window is repo-global; single-run-per-repo — ENFORCED by `run-lock.sh` at PICK, not merely documented (§6 step 1 / §11).
- **Committing a done stamp for unmerged work.** Before automate-followups/37, Phase 4.5 stamped the requirement `## Status: done`/`done_with_escalation` before any merge; it no longer does (`closeout` stamps only after `MERGED`), but a requirement can still carry such an early stamp (an older run, an older installed plugin, a hand edit). A trail PR that carries it ahead of the feature PR makes `main` claim the item is done (and `is_done` never re-queues it) even if the feature PR is then closed or reworked. Trail only after merge, at a skip/abandon check-off, or at run end — never at a park (§14's lane wave end / `lane-remove --abandon` are the gated lane calls) — and let `trail-pr`'s evidence gate exclude a stamp whose PR is not merged (§6 "Trail PR after merge and at run end").
- **Answering a lane question by judgement.** Only `lane-policy.sh decide`'s exact lookup answers a lane question without the owner, and only for a catalogued `allowed` gate with a stamped or owner-set policy answer (§14 "Policy answers"); a question that "looks routine" but carries no catalog code is relayed to the owner. Merging a lane PR or the wave branch from the engine is the same mistake in another place — `wave-plan` only prints the owner's commands (§14 "Wave close").
- **Letting the engine merge anywhere but the §10 gate.** `gh pr merge --squash` lives ONLY in the `--auto-merge` gate; `review-heal`/Supervisor Phase 4.5 never merge (§11).

---

## Related Skills

- `skills/autonomous-loop/SKILL.md` — the `/autonomous` inner loop the per-item RUN step drives `--single-iteration`; its Rubric Grader feeds §10 condition 5, and EVALUATE short-circuit is why we read `rubric_score` from `SUPERVISOR_RESULT`.
- `skills/review-heal/SKILL.md` — the authority for the OWNED `/review-pr --until-mergeable` drain (§7), the READY semantics (§9), the GraphQL review-thread query and bot-vs-human classification (§10 cond. 3), and the env-var dispatch signal contract (`LOOMWRIGHT_UNTIL_MERGEABLE` etc.).
- `skills/state-management/SKILL.md` — `.supervisor/` state-file conventions (atomic writes, append-only logs); the `.supervisor/logs/{session_id}.jsonl` per-session log shape the "Rate-limit park" subsection above reads directly.
- `commands/automate.md` — the user-facing `/automate` command body that references this skill at Step 0.
- `docs/RESULT_SCHEMAS.md` §"AUTOMATE_RUN" — the run-file layout documented as a markdown state-file contract (NOT a hook-validated emitted result block).

---

## Quality Gates

- Exactly **one** source resolved per run; the FULL resolved Queue is materialized in `## Queue` and human-confirmed before processing (gate `AUT-QUEUE`; skipped under `--non-interactive-fallback`, and — with the `skipped AUT-QUEUE: <reason>` `## Progress` line — inside a lane on its own `lane-create` backlog and for a `--backlog` doc whose Queue is not longer than `--limit`, as `queue-confirm` decides — §2).
- `--limit N` caps **PROCESSED** items (default 5), never Queue size; the run file always stores the full list.
- Exactly ONE `.supervisor/automate/<run_id>.md` per run — NO `manifest.json` / `runs.jsonl` / `progress.jsonl` / dashboard created.
- Run-file writes are atomic (temp + rename); `## Progress` is append-only; rewrites confined to `## Queue` + `## Current`.
- RESUME globs run files (`# Automate Run:` title, `is_run_file` — §6 result sidecars excluded) not stamped done and reconciles each in-flight item vs `gh`/`git`/`## Status: done` BEFORE trusting a checkbox; continue/new/archive (ambiguous resume fails closed under `--non-interactive-fallback`).
- Single drain: `.auto_review:false` set before `/autonomous`, restored finally-style (config-backup deleted on clean restore, crash-restored by RECONCILE); ONE inline `/review-pr --until-mergeable` per pass (at most one owner-requested fix-now re-drain per item, strictly sequential (never concurrent)); `## Current` records `owned_drain_started`/`owned_drain_result`/`suppressed_default_dispatch:true`; no detached `dispatch-pr-review.sh` artifact for the PR.
- Dismissed findings: at every park with an open PR, `dismissed-drafts` runs and (interactive) one decision per drafted finding is asked — at a sequential READY park only AFTER the park state is written, the merge watcher armed, the notify sent and the run lock released, and only on a `park-ask-gate` `ask — …` line (a `refuse` asks nothing); at an `escalated` park BEFORE the park state is written and the merge watcher is armed; `--non-interactive-fallback` asks nothing and records `pending_decisions`; fix-now is one DRAIN → GATE re-pass, at most once per item, and after a READY park only on the gate's `fix-now allowed` line under a re-acquired run lock (else it becomes a follow-up); the next interactive PICK asks the undecided set (Follow-up / Drop only) before RECONCILE's `closeout` (§6 "Dismissed-findings decision step (before the park)").
- Single-open-PR invariant holds in BOTH modes, this run's trail PR included (`trail-gate` parks `trail_pr_open` at PICK): `awaiting_merge` is closed out by the merge watcher (or `--resume` RECONCILE) after a human merge and the next item waits for the owner's go, `escalated` parks until human-resolved or the item is `skipped`/`abandoned`.
- `--auto-merge` executes `gh pr merge --squash` ONLY when EVERY trusted-gate condition (§10) holds; fails CLOSED (park + notify) on any blocker (unprotected/toothless, moved SHA, `CHANGES_REQUESTED`/`REVIEW_REQUIRED`, null/unreadable `reviewDecision`, unresolved human thread, high-risk or unclassifiable diff per `classify-risk.sh` — no override, a failing/unresolved/unstamped/cmd-disabled/unreadable countable `must`-rule check per `rules-gate-verdict.sh` — no override).
- `READY`/`PASS` from `review-heal`/`review-pr`/Supervisor Phase 4.5 NEVER merge; the ONLY executed `gh pr merge --squash` is the §10 gate implemented in `automate-helpers.sh gate-eval`.
- All `/autonomous` correctness gates bubble up; `--notify` / `--non-interactive-fallback` / `--cheap` pass through to the inner `/autonomous` (`--cheap` is passthrough-only — never interpreted by the engine, never stored in `## Run Config`).
- Termination: Queue fully resolved ⇒ `## Status: done` / `remaining: 0`; `limit` reached ⇒ `## Status: paused` / `pause_reason: limit_reached` / `remaining: <unchecked>`.
- Trail PR only after merge (`closeout`), at a skip/abandon check-off, and at `## Status: done` — never at a park (§14's lane wave end / `lane-remove --abandon` are the gated lane calls); `trail-pr` commits a done-stamped requirement or done/ brief only when its PR reads merged, and names every exclusion (§6 "Trail PR after merge and at run end").
- Rate-limit park: a main-scope `agent_lifecycle: failed` row with `reason: rate_limit` (or `reason: unknown` plus a `429` hint, recorded separately as `reason_hint`, never promoted into `reason`) — found in the loop's own session log, post-dating this item's "picked" line — parks the item (`status`/`pause_reason: rate_limit`) and stops BEFORE DRAIN/GATE without retrying; every other classified reason is unchanged (§6 "Rate-limit park"). Resuming it round-trips through the SAME RESUME reconcile as `awaiting_merge` (§4) — no second park vocabulary, no second reconcile path.
<!-- index-only:begin -->

## Cited sub-section anchors

Anchors that committed prose cites as a section of this skill but that are not headings — a bold bullet label inside a moved section. Each lives in the split file named here; open it and search for the anchor text. `scripts/test-automate-loop-split.sh` (citation check) derives the cited set from the tracked tree and fails when a cited anchor resolves to no heading here, no row here, or a file that does not hold it.

| Anchor | Split file |
|---|---|
| SessionStart surfacing | [per-item-loop.md](per-item-loop.md) |
<!-- index-only:end -->
