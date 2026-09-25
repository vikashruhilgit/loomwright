---
name: automate-loop
description: Protocol authority for `/automate` — the generic automation engine that converts ANY source (a prompt via /product-owner, a requirements folder, or a backlog-doc) into a FULL Queue with a per-run processing cap inside ONE markdown run file (`.supervisor/automate/<run_id>.md` — the contract, dashboard, and resume state), then drives each Queue item through the per-item loop (`/autonomous --single-iteration` → owned inline `/review-pr --until-mergeable` → trusted-merge-or-park → pull main → check off + append `## Progress`). Smart resume = glob `*.md` for not-done + reconcile-vs-ground-truth. Use when implementing or invoking `/automate`.
allowed-tools: [Read, Write, Edit, Bash, Task, AskUserQuestion]
version: "1.6.0"
lastUpdated: "2026-09-25"
---

# Automate Loop Skill

The **single source of truth** for the `/automate` generic automation engine — the protocol that walks **arbitrary work from any starting point** through to a reviewed PR (and, opt-in, a trusted merge). This skill is the **authority**; the `/automate` command body (`${CLAUDE_PLUGIN_ROOT}/commands/automate.md`), the `AUTOMATE_RUN` run-file layout in `docs/RESULT_SCHEMAS.md`, and the helper scripts under `scripts/` all **reference** the names and contracts coined here and must not re-coin or rename them.

> This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/review-heal/SKILL.md` and `skills/autonomous-loop/SKILL.md`. There is **no `-runner` agent** — `/automate` is inline-only (agents stay 14).

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
- Parallel / multi-item execution.
- **Multiple concurrent open PRs** — BOTH modes keep a **single-open-PR invariant** (§8); `escalated` parks the run, it never opens a second PR.
- A separate registry / manifest / `progress.jsonl` / dashboard file — the **single run file is enough** (§3).

---

## §1.5 — Reference implementation (the loop shells out to these)

The scriptable, security-critical steps of this protocol are **NOT re-implemented in prose each run** — the inline `/automate` loop **executes them by shelling out to a single self-tested helper**:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/automate-helpers.sh <subcommand> [args…]"
```

so **the tested code IS the executed code** (one implementation, guarded by `scripts/test-automate-helpers.sh`). **The SKILL section prose is the SPEC each subcommand implements — single source of truth; the helper conforms to it, never the reverse.** When a contract changes, change the prose here first, then make the helper conform.

| Subcommand | SKILL § | Purpose |
|------------|---------|---------|
| `config-suppress` | §7 | Backup `config.json` byte-for-byte, set `auto_review=false` (malformed ⇒ abort exit 2). |
| `config-restore` | §7 | Overwrite-from-backup OR delete-if-originally-absent; deletes the transient backup. |
| `config-orig` | §7 | Print the ORIGINAL `auto_review` to record as `auto_review_original` (`true`/`false`/`absent`). Signature `config-orig <config_path> [<backup_path>]` — **pass `<backup_path>` whenever `config-suppress` has already run**, which makes the answer call-order-independent. |
| `runfile-write` | §3 | Atomic temp+rename write of the run file (content on stdin). |
| `progress-append` | §3 | Append-only `## Progress` line (never rewrites a prior line). |
| `queue-checkoff` | §3 | Flip `- [ ]` → `- [x]` (optional `# skipped:`/`# abandoned: <reason>` form via the `mark` arg, default `skipped`, §5). |
| `remaining` | §3 | Count of `- [ ]` Queue items (COMPUTED — not a stored run-file field). |
| `resolve-folder` | §2 | List `*.md` in a folder not stamped `## Status: done` and not `## Status: proposed\|parked` (harness-port/02). |
| `resolve-backlog` | §2 | Dependency-ordered items honoring `done`/✅ markers; dir-scan fallback also skips `## Status: proposed\|parked` (harness-port/02) — a checklist line naming a file directly is unaffected (by design). |
| `resume-glob` | §4 | List run files not stamped `## Status: done`. |
| `reconcile-item` | §4 | Reconcile one item's belief vs `gh` ground truth ⇒ `merged`/`awaiting_merge`/`gone`. |
| `gate-eval` | §10 | The 6-condition fail-CLOSED trusted auto-merge gate — the **only** executor of `gh pr merge --squash`. **SELF-RESOLVING (red-team-hardening item 03):** the gate re-derives conditions 2–6 itself from live `gh`/GraphQL/`scripts/classify-risk.sh` reads and two artifact-file reads — the loop passes only what it alone knows (`drain_result`, `termination_reason`, `ready_sha`, `trust_unprotected`, `review_heal_result_path`, `supervisor_result_path`). A ctx carrying any gate-owned key (`high_risk`, `risk_reasons`, `head_sha`, `base`, `review_decision`, `unresolved_human_thread`, `protection_enforceable`, `checks_green`, `rubric_satisfied`) is refused (`PARK: ctx_carries_gate_owned_key`), never trusted. Condition 6 (`high_risk`) is computed by the gate itself via `scripts/classify-risk.sh`; nothing overrides it. |
| `learning-emit` | §6 step 3 | Fail-SAFE (always exit 0) engine-native ground-truth line: appends ONE full valid `schema_version: 1` POSTMORTEM_RESULT (`source: "automate_drain"` + `automate_key`) per processed PR from `REVIEW_HEAL_RESULT` + `SUPERVISOR_RESULT` data already in hand; idempotent on `run_id`+item+`pr_url`+`source`+completeness (a `changed_paths: []` degraded line never blocks a later complete one — §6 "Learning-emit at end-of-DRAIN"). |
| `brief-repair` | §6 steps 1 & 5 | Fail-SAFE (always exit 0) evidence-positive brief lifecycle repair: `brief-repair <item> <pr_url>` re-reads merge state (`gh pr view`), and ONLY on `MERGED` (or a non-empty `mergedAt`) hands the evidence to the sibling `reconcile-jobs.sh --repair --evidence <item>=<pr_url>` — the one mover, scoped to that item, refusing an ambiguous match. Prints ONE line (`repaired …` / `skipped — <reason>`) for `## Progress` (§6 "Brief-repair at RECONCILE and SYNC"). |
| `reconcile-status` | §4 step 7 | Dry-run-default `reconcile-status <requirements_root> [--apply]` (queue-hygiene/01): stamps a `pending`/absent-status requirement's `## Status:` from a merged PR (state via `reconcile-item`; body-citation or done/-brief branch-slug evidence) or an owner `# abandoned:` Queue row, byte-for-byte in the §6 stamp shape; NEVER downgrades an existing `done`/`done_with_escalation`; `brief-shipped` files are only LISTED, never promoted. Prints `plan\t…`/`stamped\t…`/`info\t…` rows; writes nothing without `--apply`. |
| `ceiling-check` | §6 step 1 | PICK-time token-ceiling check (red-team-hardening/06): `ceiling-check <runfile> <max_tokens> [--root <checkout>]` sums the run's ledger via `scripts/read-token-ledger.sh --run-id <runfile>` and compares TOTAL against `<max_tokens>`; prints `OK total=<n> max=<n>`, `PARK: token_ceiling total=<n> max=<n>`, or `PARK: ledger_unreadable` — always exits 0 (a PARK is a normal outcome, same convention as `gate-eval`). |

`scripts/read-token-ledger.sh --session <id> | --run-id <run_id> [--root <checkout>]` and `scripts/run-lock.sh acquire|release|status --owner <label> [--session-id <id>] [--root <checkout>] [--force-unlock]` are **standalone scripts, not `automate-helpers.sh` subcommands** (they are shared with `/autonomous` and `/supervisor`, so they live at the top level of `scripts/` rather than inside this engine's own helper). `read-token-ledger.sh` is the fail-SAFE reader `ceiling-check` shells out to (row above) — `--session <id>` and `--run-id <id>` both print `INPUT=<n> OUTPUT=<n> CACHE_READ=<n> CACHE_CREATE=<n> TOTAL=<n> EVENTS=<n>` (plus `LEDGER_UNREADABLE=1` when nothing could be read); see the script's own header for the proxy-line honest limit. `run-lock.sh` is the single-run-per-repo lock (§11) acquired at PICK below, released at item completion/park.

> `automate-helpers.sh` is READ-ONLY toward the work it drives (no source-repo edits, no git mutations; the sole exception is `gate-eval`'s explicit `gh pr merge --squash` — and `brief-repair`, whose only write is the brief lifecycle move performed by `reconcile-jobs.sh --repair` under `.supervisor/jobs/`, never a source-repo or git mutation). It is an **uncounted plain script** (not an agent/command/skill/hook).

---

## §2 — Intake: any source → the Queue (convert once, NO adapter framework)

Exactly **one** source is resolved per run. Resolution produces the **FULL** ordered list of items, which is written to `## Queue` and **shown to the user for confirmation before processing** (a prompt that explodes into 40 files never runs silently). Under `--non-interactive-fallback` the confirmation prompt is skipped and the `--limit` cap is enforced without asking.

### Prompt source — `/automate "X"`

- Runs **`/product-owner`** on the prompt text. This is a **REUSE**, not a new code path: Product Owner already writes `.supervisor/requirements/*.md` story files (and, in Beads-absent mode, an optional `_BACKLOG.md`).
- The **generated file paths become the `## Queue`** (in PO's emitted order; if PO also wrote a `_BACKLOG.md`, prefer its documented dependency order per the backlog-doc rules below).
- **1 generated file ⇒ single-item run; N files ⇒ loop.**
- **Bare `/automate`** (no prompt, no source flag): **attempt RESUME first** (§4); if no incomplete run exists, `AskUserQuestion` *"What do you want to automate?"* and then proceed as a prompt source.
- **0 generated files ⇒ report + stop** (never wedge) — the run file records `## Status: done`, `remaining: 0` with a `## Progress` note that the prompt produced no items.

### Folder source — `/automate --folder <dir>`

- Enqueues **every `.md` in `<dir>`** as a Queue item, **skipping any already marked `## Status: done`** (read each file's `## Status:` stamp; a done file is excluded from the Queue, not enqueued-then-checked).
- Order = directory order unless a sibling `_BACKLOG.md` documents a build order (then defer to backlog-doc ordering).

**Two independent not-ready skips exist for the folder / backlog-dir-fallback sources (harness-port/02):** (1) the pre-existing `proposed/` **subfolder** convention — `"$dir"/*.md` does not recurse, so a file kept inside a `proposed/` subfolder (as `/propose` writes, and `commands/propose.md` documents) is simply never scanned; and (2) a `## Status:` heading stamp of `proposed|parked` on a file that IS scanned — this file is read, its stamp checked (`is_not_ready()` in `automate-helpers.sh`), and it is then skipped (excluded from the Queue), the same way a `## Status: done` file is excluded. Either way, a skipped file is **not checked off** in `## Queue` and does **not** count toward the run's own `## Status: done` — it simply never entered the Queue in the first place. (Run-file resume semantics — `resume-glob` over `.supervisor/automate/*.md`, whose `## Status:` vocabulary is `running|paused|done` — are untouched by this `proposed|parked` stamp; see §4.)

### Backlog-doc source — `/automate --backlog <_BACKLOG.md>`

- Enqueues in the doc's **documented dependency order** — the doc's build order plus `## Status: done` / ✅ markers are treated as **ground truth** (done items excluded).
- **`_BACKLOG.md`-absent fallback:** if the passed path does not exist (or has no documented order), fall back to `## Status:`-stamp ordering over the directory the path points into; if there are no stampable items, the Queue is empty ⇒ `remaining: 0`.

### `--limit N` — caps PROCESSED items, NOT Queue size

- The run file's `## Queue` **always holds the FULL resolved list**. `--limit N` (recorded in `## Run Config`, **default 5** — "pull 5–10 and start") caps how many items are **completed** this run.
- After **N items are processed** with items still unchecked ⇒ `## Status: paused`, `pause_reason: limit_reached`, report `remaining: <unchecked count>`. Raise `limit` or `--resume` to continue.
- The **full resolved Queue (count + ordered items) is shown to the user for confirmation before processing.** Under `--non-interactive-fallback` the cap is enforced without the prompt.

---

## §3 — The single run file (`.supervisor/automate/<run_id>.md`)

**The single-file principle (this design's core):** there is **no manifest, no registry, no `progress.jsonl`, no dashboard file**. ONE markdown run file holds everything — it IS the manifest, registry, progress log, and dashboard. **"Find prior runs" = glob `.supervisor/automate/*.md` for files not marked `## Status: done`** (§4). The only other artifact is a *transient* config-backup sidecar that exists only during a tick (§7).

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
## Queue                    # `- [ ]` queued · `- [x]` done (merged) · `- [x] … # skipped|abandoned:` excluded; order = processing order
- [ ] <requirement path or generated file>
- [x] <... merged ...>
- [x] <... path ...>  # skipped: <reason>     # checked-off so "next unchecked" never re-picks it; reason also in ## Progress
## Current
- item: <path> | status: running|awaiting_merge|escalated|failed|rate_limit|drain_died|done | pr: <url> | branch: <name>
- pause_reason: awaiting_merge|escalated|limit_reached|resume_ambiguous|rate_limit|drain_died|token_ceiling|run_lock_held|null
- owned_drain_started: <ts> | owned_drain_result: READY|ESCALATED|died | suppressed_default_dispatch: true (`READY`'s `termination_reason` — `converged` or `sub_floor_converged`, mechanized bound via `scripts/drain-rounds.sh` — is read straight through from `REVIEW_HEAL_RESULT`; `sub_floor_converged` is NOT merge-eligible, §10 cond 1. `died` — red-team-hardening item 04 — is NOT a `REVIEW_HEAL_RESULT` decision at all; it means a DETACHED `dispatch-pr-review.sh` drain for this item's PR exited without ever producing one, discovered via a `.supervisor/review-dispatch/<hash>.died` marker at RECONCILE, §4 — see that section for the full contract)
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <item>
- <ts> session_id <id> (<item>)     # red-team-hardening/06 — the Supervisor session RUN just used; read-token-ledger.sh --run-id sums every session_id line in this file
- <ts> ran /autonomous → PR <url>
- <ts> drain READY → awaiting_merge
```

### Item lifecycle

```
queued (- [ ]) → running → rate_limit (parks, no PR yet) | pr-open → awaiting_merge → merged (- [x]) | escalated (parks) | failed | skipped
```

### `## Status` semantics

- **`running`** — the loop is actively processing (or is the freshly-created run).
- **`paused`** — stopped with work remaining; always paired with a `pause_reason` (`awaiting_merge` | `escalated` | `limit_reached` | `resume_ambiguous` | `rate_limit` | `drain_died` | `token_ceiling` | `run_lock_held`).
- **`done`** — set **only** when the Queue is **fully resolved** (no `- [ ]` items remain), i.e. `remaining: 0`. `remaining` is **COMPUTED/REPORTED** (the count of `- [ ]` Queue items, via `automate-helpers.sh remaining`) — it is **NOT a persisted run-file field**; the template stores no `remaining:` line.

### Crash-safety contract (HIGH-risk mitigation — run-file is the ONLY copy of resume state)

> **Execute via the helper, not a re-implementation:** the run-file mutations are done by shelling out — `automate-helpers.sh runfile-write <runfile>` (full atomic write, content on stdin), `automate-helpers.sh progress-append <runfile> <line>` (append-only `## Progress`), `automate-helpers.sh queue-checkoff <runfile> <item> [reason] [mark]` (flip `- [ ]` → `- [x]`; `mark` = `skipped` (default) or `abandoned`, §5), and `automate-helpers.sh remaining <runfile>` (COMPUTED `- [ ]` count) (§1.5). The contract below is the SPEC those subcommands implement.

- **Atomic write (temp + rename):** every run-file update is written to a temp file and `mv`-renamed into place. A crash mid-write never leaves a half-written file — the prior intact version remains.
- **`## Progress` is APPEND-ONLY** — it is **never rewritten**. New lines are appended; existing lines are immutable.
- **Rewrites are confined** to `## Queue` checkboxes and the `## Current` block. `## Status`/`## Source`/`## Run Config` change rarely and atomically; `## Progress` only grows.
- **Optional secondary breadcrumb:** ONE terminal line per run **appended** to the existing `.supervisor/logs/<run_id>.jsonl` (the shared session-log convention) for trend tooling — **never the source of truth**.

---

## §4 — RESUME = glob + reconcile (run-file is BELIEF; git/gh is TRUTH)

> **Execute via the helper, not a re-implementation:** glob with `automate-helpers.sh resume-glob <automate_dir>` and reconcile each in-flight item's belief vs `gh` ground truth with `automate-helpers.sh reconcile-item <pr_url> <belief>` ⇒ `merged` / `awaiting_merge` / `gone` (§1.5). (`reconcile-item` resolves the `gh`-PR-state half; the complementary `git branch --contains <sha>` corroboration below is done by the loop.) The protocol below is the SPEC those subcommands implement.

**On every start** (including bare `/automate` and any `--resume`):

1. **Glob** `.supervisor/automate/*.md` for runs **NOT** marked `## Status: done`.
2. The run file is the loop's **belief**. **Reconcile each in-flight item against GROUND TRUTH before trusting a checkbox** — a crash between merge and check-off makes belief and reality disagree:
   - **PR merged?** `gh pr view <url> --json state,mergedAt` — a merged PR ⇒ the item is `- [x]` (merged) even if the file still shows it `- [ ]`/`awaiting_merge`; a merge found here is also the evidence §6 step 1's `brief-repair` call hands to the reconciler, so the item's stranded brief is repaired before the next item is picked.
   - **PR open?** an `OPEN` PR ⇒ the item stays `awaiting_merge` (resumed on merge per §8).
   - **PR closed-unmerged or vanished?** a `CLOSED` (never-merged) or otherwise gone PR ⇒ the item is `gone` — neither merged nor live. Treat it like an `escalated` park requiring human resolution (§9): the run stays paused until the human re-opens/redoes the work or marks the item `skipped`/`abandoned` in `## Queue` (§5). Never silently re-pick or auto-check a `gone` item.
   - **Branch landed?** `git log origin/main --oneline` / `git branch --contains <sha>` — verify the branch actually reached `main` (never assert "merged" from memory).
   - **Requirement stamped?** the requirement file's `## Status: done` stamp.
   - **No PR yet (`pr: null`, `pause_reason: rate_limit`)?** RUN failed before a PR ever existed (see "Rate-limit park" under §6 below), so there is nothing for `gh` to reconcile — this item is left exactly as parked (still `- [ ]`, still the `## Current` in-flight item) and falls straight through to step 4/6 below: resuming just re-picks it and retries RUN.
   - **A DETACHED drain died for this item's PR (`drain_died`, red-team-hardening item 04)?** Check `.supervisor/review-dispatch/*.died` for a marker whose `pr_url` field equals this item's `## Current` `pr:` URL. This is a SEPARATE fact from the `owned_drain_result` this loop's OWN inline `/review-pr --until-mergeable` drain records (§7, §6 step 3) — a `.died` marker only ever comes from the DETACHED `dispatch-pr-review.sh` dispatcher (Supervisor's step 5.5 or the `PostToolUse[Bash]` hook backstop), which this engine's owned drain never goes through. If a matching `.died` marker exists, treat it as `owned_drain_result: died` in `## Current` and `## Status: paused` / `pause_reason: drain_died` — **explicitly NEVER `awaiting_merge`**, because a died drain never reached a `READY`/`ESCALATED` verdict to park on in the normal sense; there is no `REVIEW_HEAL_RESULT` to trust either way, and the PR's true readiness is simply unknown. This check runs BEFORE the merged/open/closed reconcile above would otherwise re-pick or resume the item as if a normal drain outcome existed.
   - Reconcile each item, then rewrite `## Queue` checkboxes + `## Current` atomically (§3) so belief matches truth.
3. **RECONCILE also restores a crash-stranded config backup** (§7) — if `## Run Config`'s `config_backup` sidecar still exists on disk, the prior tick died with `.auto_review` suppressed; restore it (or delete `config.json` if originally absent) before proceeding.
4. **If an incomplete run exists**, `AskUserQuestion`: **continue / start new / archive**.
   - `--resume [<run_id>]` targets one explicitly; with the id omitted it targets the **most-recent incomplete** run.
   - Under **`--non-interactive-fallback`**, an **ambiguous** resume (more than one incomplete run and no explicit id) **fails closed**. In `AUTOMATE_RUN` this is persisted as **`pause_reason: resume_ambiguous`** in `## Current` (the run file has no `status_reason` field — that identifier belongs to the inner `/autonomous` layer's `AUTONOMOUS_RUN`, which surfaces it as `status_reason: "resume_ambiguous_non_interactive"` when the loop forwards the fallback).
5. **Re-pass non-persisted passthrough flags.** `## Run Config` does NOT store `--notify` / `--non-interactive-fallback` / `--cheap` (§11) — a resume or `/loop` tick that omits them silently reverts to defaults. This matters most for **`--cheap`**: omitting it reverts the remaining queue to the full-cost profile with cumulative dollar impact, so re-pass `--cheap` on **every** `/automate --resume` invocation and `/loop` tick of a cheap run.
6. **Resuming a `rate_limit` park.** This round-trips through the EXACT SAME RESUME flow above — no second reconcile code path, no second park vocabulary. The only difference from resuming `awaiting_merge` is *what* step 2 finds: an `awaiting_merge` item has a `pr` to reconcile against `gh`; a `rate_limit` item has `pr: null` and nothing to check (the "No PR yet" bullet above), so reconcile is a no-op for it. Either way, `continue` (step 4) re-enters the per-item loop at §6 step 1 RECONCILE and proceeds from there — for a `rate_limit` item that means falling straight through to §6 step 2 RUN, retrying the SAME item (the rate-limit window has presumably passed by the time a human or `/loop` resumes).
7. **RECONCILE also runs reconcile-status** — the `reconcile-status` dry-run pass (queue-hygiene/01) — **BEFORE step 4's PICK**: `automate-helpers.sh reconcile-status .supervisor/requirements` (no `--apply` — this is the engine's own RESUME reading ground truth back for requirement files OUTSIDE this run's own `## Queue`, the same "read it back, never infer it" posture as steps 1–2 above, kept dry-run because promoting a requirement's `## Status:` is a standing human-owned act, not an engine side-effect). For each `plan\t<file>\t…` row it prints, `automate-helpers.sh progress-append <runfile> "reconcile-status: would stamp <file> (<status>)"` — ONE `## Progress` line per row, appended before PICK runs. An `info\t…` (brief-shipped) row is NOT progress-appended — it is advisory-only and never actionable from inside a run. Zero `plan` rows ⇒ no line, no-op. This never writes to a requirement file itself; promoting the plan to a real stamp is `automate-helpers.sh reconcile-status .supervisor/requirements --apply`, run by a human (or a dedicated queue-hygiene pass), never by `/automate` itself.

---

## §5 — Skipped / abandoned items

An item the human (or the loop) abandons is written in `## Queue` as:

```md
- [x] <path>  # skipped: <reason>
- [x] <path>  # abandoned: <reason>
```

- **Checked-off ⇒ never re-picked** ("next unchecked item" skips it). The reason is ALSO logged in `## Progress`.
- **`remaining` counts only `- [ ]` items**, so a skipped/abandoned item does **not** block `## Status: done`.
- This is the **documented way to unblock an `escalated`-parked run without merging** (§9): mark the parked item `skipped`/`abandoned`, then `--resume`.

---

## §6 — The per-item loop

For each `- [ ]` Queue item (top-down, single-open-PR invariant permitting — §8):

1. **RECONCILE** — re-check ground truth for any in-flight item before picking (§4); never pick a new item while one has an open unmerged PR (§8). When `reconcile-item` returns `merged` for an item previously parked `awaiting_merge` (or `escalated`), the loop calls `automate-helpers.sh brief-repair <item> <pr_url>` BEFORE picking the next item and appends its one output line to `## Progress` — advisory, fail-SAFE, its result never changes the reconcile verdict (see "Brief-repair at RECONCILE and SYNC" below).

   **PICK-time run-lock acquire (red-team-hardening/06 — BEFORE anything else at PICK, including RECONCILE above).** The very first action of every PICK is `scripts/run-lock.sh acquire --owner "automate:<run_id>" --session-id "<session_id>"` (see §1.5's `run-lock.sh` row for the full path convention) — a lock already held by another run/process in this checkout PARKS the run immediately (`## Status: paused`, `pause_reason: run_lock_held`, one `## Progress` line naming the `run_lock_held owner=<label> pid=<pid> age=<s>` output) and the loop stops WITHOUT touching `## Queue`/`## Current`/`.auto_review` — it never proceeds silently. On success the lock is held for the rest of this item's loop and released at CHECK OFF (step 6) or any park below (step 2's rate-limit park, DRAIN's `drain_died`, or GATE's `awaiting_merge`/`escalated`) — see §11 for the human-only `--force-unlock` escape hatch on a stranded lock.

   **PICK-time token-ceiling check (red-team-hardening/06 — when `--max-tokens N` was passed).** Immediately after the lock acquire succeeds, and BEFORE RECONCILE above: `automate-helpers.sh ceiling-check <runfile> <N>`. A `PARK: token_ceiling …` or `PARK: ledger_unreadable` answer PARKs the run right here — `## Status: paused`, `pause_reason: token_ceiling`, one `## Progress` line — releasing the lock just acquired before stopping (never left held on a park). An `OK …` answer proceeds to RECONCILE as normal. Skipped entirely (no check, no `## Run Config` field) when `--max-tokens` was not passed — opt-in, byte-for-byte unchanged behavior otherwise.
2. **RUN** — set `.supervisor/config.json {"auto_review": false}` (the suppress contract, §7) **then** run `/autonomous --single-iteration --requirement <path>`, appending `--cheap` when it was passed to `/automate` (pure passthrough, v15.2.0+ — the engine never interprets the flag itself and does NOT store it in `## Run Config`; the inner `/autonomous` forwards it on to `/supervisor`, §11) and appending `--max-tokens N` when it was passed to `/automate` (red-team-hardening/06 — UNLIKE `--cheap`, this one IS recorded in `## Run Config` as `max_tokens: N` so a bare `--resume` still enforces it; the inner `/autonomous` forwards it on to `/supervisor` exactly like `--cheap`, §11). The suppress MUST wrap the RUN phase: both default dispatches fire *during* `/autonomous` (Supervisor step 5.5 + the `PostToolUse[Bash]` `gh pr create` hook), so toggling at DRAIN is too late. Capture the emitted `SUPERVISOR_RESULT` (status, `pr_url`, `branch`, `rubric_score`, `heal_decision`) and **write its raw text VERBATIM to `.supervisor/automate/<run_id>.supervisor-result.md`** (transient, overwritten per item, same convention as the DRAIN-step artifact below) — this is the file `gate-eval`'s condition-5 rubric check (§10) parses a `rubric_score: N/M` line from itself; the gate never trusts a caller-asserted rubric verdict. **Restore `.auto_review` in a finally-style cleanup immediately after `/autonomous` returns *or fails* — i.e. BEFORE the owned DRAIN below** (§7). The owned drain is inline and NOT gated by `.auto_review`, so restoring before it both keeps the suppression window tight and is safe. **Then, before proceeding to step 3 DRAIN, check for a rate-limit park** — see "Rate-limit park" below; a parked item stops the run right here and never reaches DRAIN/GATE.

   **Session-id recording for the token ledger (red-team-hardening/06).** Immediately after `/autonomous` returns (successfully or not), read `.supervisor/state.md`'s `- session_id:` field — the Supervisor session this RUN invocation just used — and `automate-helpers.sh progress-append <runfile> "session_id <id> (<item>)"`. This is what lets `read-token-ledger.sh --run-id <runfile>` (§1.5) find every session's ledger for this run, including for `--max-tokens` runs that never set a ceiling this time but might on a future `--resume`. Recorded UNCONDITIONALLY (not gated on `--max-tokens` being set) so a later `--max-tokens`-bearing `--resume` of an UN-ceilinged run still has a complete session-id trail to sum.
3. **DRAIN** — own **exactly ONE** inline `/review-pr --until-mergeable --no-auto-postmortem` on the PR (§7). Read its terminal `REVIEW_HEAL_RESULT` synchronously; record `owned_drain_started` / `owned_drain_result` / `suppressed_default_dispatch: true` in `## Current`. **Also write the terminal `REVIEW_HEAL_RESULT` block's raw text VERBATIM to `.supervisor/automate/<run_id>.review-heal-result.md`** (transient, overwritten per item — same convention as the `<run_id>.config-backup.json` sidecar, §7) — this is the artifact `gate-eval`'s condition-1 cross-check (§10) reads back and compares against the loop's own `drain_result`/`termination_reason` claim, so the drain's self-report can never merge on a bare, uncorroborated assertion. **Then, at the END of DRAIN (BEFORE step 4 GATE), emit the engine-native learning line** — see "Learning-emit at end-of-DRAIN" below. This runs for EVERY item that produced a PR (merged OR parked); emitting here (not at step 6 CHECK OFF) covers parked items, which stop at the GATE and never reach CHECK OFF.
4. **GATE** — apply the per-mode decision (§9): safe mode parks `awaiting_merge`; `--auto-merge` runs the 6-condition trusted-merge gate (§10), which is now **SELF-RESOLVING** (red-team-hardening item 03) — the gate itself re-derives conditions 2–6 from live `gh`/GraphQL/`classify-risk.sh` reads rather than trusting loop-supplied values; the loop's `ctx.json` shrinks to exactly `{drain_result, termination_reason, ready_sha, trust_unprotected, review_heal_result_path, supervisor_result_path}` (§10). `ESCALATED` always parks (§9).
5. **SYNC** — after a successful merge (auto-merge mode), `git checkout main && git pull` so the next item branches off **fresh `main`** (no stale-base / PR-tower). After `gate-eval` printed `MERGE`, call `automate-helpers.sh brief-repair <item> <pr_url>` (before the `git pull`; order is immaterial, the brief is gitignored) and append its line to `## Progress`.
6. **CHECK OFF + PROGRESS** — mark the item `- [x]` in `## Queue` and **append** a `## Progress` line, via **one atomic write** (§3). Report `remaining: N` (count of `- [ ]` items). **Release the run-lock** (red-team-hardening/06) — `run-lock.sh release --owner "automate:<run_id>"` — as the LAST action of this step, whether the item just merged or was checked off `skipped`/`abandoned`. The SAME release fires on every OTHER path this item's loop can stop on (rate-limit park, `drain_died`, `awaiting_merge`/`escalated` GATE parks, `limit_reached` termination) — the lock is held for at most one item's worth of loop, NEVER carried across a park that stops the whole run, so a human resuming a parked `/automate` run is never blocked by its own prior lock.

### Rate-limit park (end of RUN, before DRAIN)

Immediately after step 2 RUN captures `SUPERVISOR_RESULT` and restores `.auto_review`, and **before** proceeding to step 3 DRAIN, the loop checks its own session's JSONL log — `.supervisor/logs/{session_id}.jsonl`, the SAME file `scripts/emit-lifecycle.sh` appends to (`docs/RESULT_SCHEMAS.md` §"`agent_lifecycle` JSONL event records") — for an `agent_lifecycle` row with `state: "failed"`, `agent_scope: "main"` (no `agent_id` — for `/automate` the main thread IS this loop, so a main-scope failure is the loop's own turn dying, matching the source requirement's honest limit that every observed rate-limit `StopFailure` in this repo has been main-thread), and `reason: "rate_limit"`, timestamped AFTER this item's own `## Progress` "picked" line (never a stale hit carried over from an earlier item in the same run file). **No new script is needed for this read** — the loop reads its own session log directly, exactly the way it already reads its own `## Progress` lines; there is no PR yet at this point for a `gh`-keyed helper like `reconcile-item` to key on.

- **Classified hit (`reason: "rate_limit"`):** park immediately, following the EXISTING park shape exactly (never a new `status: parked` placeholder) — `## Current` gets `status: rate_limit` AND `pause_reason: rate_limit` (item-level `status` mirrors `pause_reason`, the same way `awaiting_merge`/`escalated` already do), `## Status: paused`, one `## Progress` line naming the rate-limit fact (e.g. `<ts> rate-limited — parking, resume once the window clears`), and the run **STOPS (exit 0)**. It does NOT proceed to DRAIN/GATE and does NOT retry RUN into the same wall.
- **Unknown hit with a `429` hint (fallback, `reason: "unknown"`):** the `agent_lifecycle` row itself carries no message text, so before falling through to today's unchanged handling, check the sibling `STOP_FAILURE` line in `.supervisor/logs/failures.log` for the SAME session (matched by `session_id`, the line closest-preceding the `agent_lifecycle` row's own `ts`) and read its `last_assistant_message` field for a `429` substring. A hit there records a SEPARATE `reason_hint: rate_limit` line in `## Current` — additive, **never** written into `reason` (the `agent_lifecycle` row stays `"unknown"`, untouched) and **never** promoted into `status`/`pause_reason` as if it were a classified certainty — **and** the item still parks the SAME way a classified `rate_limit` would (`status: rate_limit`, `pause_reason: rate_limit`, same `## Progress`/stop behavior above): a hint is enough to stop retrying into a wall, not enough to relabel the underlying fact as certain.
- **Every other classified reason — UNCHANGED.** `server_error` / `authentication_failed` / `model_not_found`, or `unknown` with no `429` hint, take today's existing failure/error path exactly as before (whatever `SUPERVISOR_RESULT`'s own failure status already drives, and the `/autonomous` correctness gates that bubble up per §11). This item adds exactly ONE new branch; it does not restructure any other reason's handling.

### Termination (two exits)

- **Queue fully resolved** (no `- [ ]` left) ⇒ `## Status: done`, `remaining: 0`, the `/loop` driver stops.
- **`limit` items processed** with the queue NOT empty ⇒ `## Status: paused`, `pause_reason: limit_reached`, `remaining: <unchecked count>`, loop stops.

(A park on `awaiting_merge`, `escalated` — §8/§9 — or `rate_limit` — the "Rate-limit park" subsection above — or `drain_died` — §4 RECONCILE, a DETACHED drain that exited without a result, red-team-hardening item 04 — also stops the loop with the corresponding `pause_reason`.)

All `/autonomous` correctness gates still bubble up (NO-GO, Plan Review FAIL×3, adjudication, rubric gate); `--notify`, `--non-interactive-fallback`, and `--cheap` pass through to the inner `/autonomous` (§11).

### Learning-emit at end-of-DRAIN (engine-native ground-truth signal)

At the END of §6 step 3 (DRAIN), AFTER reading the terminal `REVIEW_HEAL_RESULT` and BEFORE step 4 (GATE), append **ONE** ground-truth learning line per processed PR (merged OR parked). This replaces the GitHub-blind `/pr-postmortem` for automate'd PRs: the engine already holds the real churn, so it builds an honest line instead of reading a false `review_rounds: 0` off GitHub.

> **Execute via the helper, not a re-implementation (reference-don't-restate, to avoid mirror drift):** call `automate-helpers.sh learning-emit` (§1.5). The helper owns all the record-building logic (the `effective_review_rounds` rule, the `categories[]` zero-rule, `self_heal_misses` derivation, idempotency-skip, jq-only injection-safe construction, always-exit-0). Do NOT restate that logic here — the authoritative field mapping lives in `docs/RESULT_SCHEMAS.md` POSTMORTEM_RESULT §"`source: \"automate_drain\"` variant".

- **Inputs the engine already holds:** from the step-3 `REVIEW_HEAL_RESULT` read `fix_cycles`, `repeat_check_failure`, `unresolved_bot_feedback`, and `decision` (the drain result `READY|ESCALATED`); from the step-2 `SUPERVISOR_RESULT` read `pr_url`, `branch` (and `heal_decision`/`rubric_score` for the summary). **Derive `repo` (`owner/repo`) and `number` from `pr_url`** (parse `…/<owner>/<repo>/pull/<n>`) — `SUPERVISOR_RESULT` does not carry them as bare fields, and a correct `--repo` is **load-bearing for visibility** (next bullet).
- **The ONE added fetch** (the only data not already in hand): a single `gh pr view "<pr_url>" --json files,additions,deletions,changedFiles`, where `changed_paths = [.files[].path]`. On ANY fetch failure, degrade to `--changed-paths-json '[]'` and `--additions 0 --deletions 0 --changed-files 0` (integers, never `null`) — the line is still emitted, just invisible to `read-postmortem.sh` (**and correctable — see the degraded-emit bullet below**).
- **A degraded emit is INVISIBLE but no longer PERMANENT (second half of the same trap as `--repo`).** A line emitted with `changed_paths: []` — because the fetch above failed, or because the caller omitted the fetch args entirely — can never overlap a queried path, so `read-postmortem.sh` can never return it. The `--repo` bullet above covers one half of that silent-invisibility trap; this is the other half. Historically it was also *permanent*: the `automate_key` was keyed on `run_id`+item+`pr_url`+`source` alone, so the degraded line poisoned the key and **every** later emit carrying the real data was silently skipped (observed 2026-08-06 on PR #126). The key now carries a `complete`\|`degraded` discriminator, so **a degraded line does NOT block a later complete one** — re-running `learning-emit` for the same run/item/PR with the fetch data appends the corrective line, and the inert degraded line is left in place (append-only; `curate-postmortem.sh` remains the sole curator writer). The helper still writes **at most one complete line** per run/item/pr/source, and a degraded retry *after* a complete line is skipped, so the correction cannot run backwards or duplicate. **Prefer passing real fetch data on the first call** — the correction is a safety net, not a licence to skip the fetch.
- **Visibility is gated by BOTH `changed_paths` AND `repo` (load-bearing — pass a real `--repo`).** `read-postmortem.sh` returns a corpus line as a prior-churn hit only when its `changed_paths` overlaps the queried paths **AND** (when the current repo is determinable) its `repo` matches the reader's repo case-insensitively (`read-postmortem.sh:159` [pins: `changed_paths overlap the query set`]). The helper defaults `repo` to `""` (emitted as `repo: ""`, **not** `null`), which the reader filters out whenever its own repo resolves — so an empty `--repo` produces a **silently-invisible** line, exactly the failure this feature exists to prevent. Always pass `--repo <owner/repo>` (derived above). Also pass `--plugin-version` (from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`) so engine-native lines carry the real version, not `"unknown"`.
- **Idempotency:** pass `--run-id <run_id> --item <item> --pr-url <pr_url> --source automate_drain` so the helper's `automate_key` skip yields exactly ONE line across a crash between emit and check-off, or a `--resume` re-entry. The key is **degradation-aware** (previous bullet): exactly-once holds per (run/item/pr/source, `complete`\|`degraded`) state, which is what lets a re-entry that *recovers* the fetch data correct an earlier degraded line while a plain re-entry still writes nothing.
- **Ledger:** `.supervisor/postmortem/results.jsonl` (the same unified corpus `/pr-postmortem` appends to; the `source` field discriminates the two).
- **Advisory / fail-SAFE — NEVER gating.** `learning-emit` ALWAYS exits 0; the loop **ignores its exit status entirely**. A `learning-emit` failure (jq absent, unwritable ledger, fetch fail, bad arg) NEVER changes `owned_drain_result`, the step-4 GATE / merge-or-park decision, `## Status`, `## Current`, or any inner `/autonomous` gate — exactly like the `postmortem_dispatched`-is-informational invariant.
- *(Optional, advisory)* the `AUTOMATE_RUN` summary MAY carry a `learning_lines_emitted` counter; skip it if it adds risk.

### Brief-repair at RECONCILE and SYNC (merge-evidenced lifecycle repair)

The engine is the one caller that holds ONLINE evidence that a Queue item's PR merged — it merged it (step 5 SYNC), or its RESUME reconcile just found an item parked `awaiting_merge` now merged (step 1 RECONCILE). At both seams the loop calls `automate-helpers.sh brief-repair <item> <pr_url>` (§1.5) and appends its single output line to `## Progress` verbatim, so a reader can falsify the repair from the run file. The helper re-reads merge state from the forge (evidence-POSITIVE: only `MERGED` proceeds; an unreadable or non-merged answer is a `skipped`, never a repair) and hands the evidence to the sibling `reconcile-jobs.sh --repair --evidence <item>=<pr_url>`, which stays the ONE mover: the repair is scoped to that item's brief, an ambiguous match (two in-progress briefs with the same pointer) repairs nothing, and `unknown` is still never repaired. The `--evidence` key is compared EXACTLY against the brief's `- **Source requirement:**` token — a Queue item spelled `./…` or as an absolute path (`--folder /abs/dir`) never matches Launch Pad's repo-root-relative pointer and lands on a `skipped` line.

- **Advisory / fail-SAFE — NEVER gating.** `brief-repair` ALWAYS exits 0; the loop **ignores its exit status entirely**. A `brief-repair` failure (gh absent or erroring, unparseable output, brief unreadable, reconciler absent, no matching brief, malformed arguments, ambiguous match) NEVER changes `owned_drain_result`, the step-4 GATE / merge-or-park decision, `## Status`, `## Current`, or any inner `/autonomous` gate — exactly like `learning-emit`. It never reads or writes the run file, never touches `## Queue`/`## Current`, and never calls `gh pr merge` (the sole executor stays `gate-eval`, §11).
- **Idempotent.** A second call for the same item finds no in-progress brief and prints `skipped — no in-progress brief matches …`; the moved brief is never re-stamped.
- **Honest limit.** Only items the engine processed have engine-held evidence. A `/supervisor` or `/autonomous` run **outside the engine** still has no online repair: its stranded brief is classified offline by `session-resume.sh` (unchanged — still no forge call) and remains a manual `reconcile-jobs.sh --repair` (or a SessionStart classification), exactly as before.

---

## §7 — Single drain (no double-dispatch) + the config-toggle contract

`/autonomous` already triggers Supervisor's **default detached until-mergeable drain** (Phase 4.5 step 5.5 **and** the `PostToolUse[Bash]` `gh pr create` hook backstop). If the engine *also* drains, two until-mergeable loops race the branch (HIGH risk). The engine therefore **suppresses the default dispatch and owns exactly ONE inline drain**.

### Suppress window (wrap the RUN phase)

- Set `.supervisor/config.json {"auto_review": false}` **BEFORE** invoking `/autonomous` and restore it in a **finally-style cleanup** immediately after `/autonomous` returns *or fails* — i.e. **BEFORE the engine's own inline `/review-pr --until-mergeable` drain** (§6 step 3). Both default dispatches fire *during* `/autonomous`, so setting it at DRAIN is too late; the owned drain is inline and not gated by `.auto_review`, so restoring before it is correct and keeps the suppression window tight.

### Config-toggle contract (byte-for-byte; absent-delete; malformed-abort)

> **Execute via the helper, not a re-implementation:** suppress with `automate-helpers.sh config-suppress <config_path> <backup_path>`, restore with `automate-helpers.sh config-restore <config_path> <backup_path>`, and read the original with `automate-helpers.sh config-orig <config_path> [<backup_path>]` (§1.5) — **pass the backup path whenever suppress has already run** (next bullet). The prose below is the SPEC those subcommands implement.

- **Backup:** byte-for-byte copy the existing `.supervisor/config.json` to a **transient** `<run_id>.config-backup.json`. Record its path + the original `.auto_review` value in `## Run Config` (`auto_review_original: <true|false|absent>`, `config_backup: <run_id>.config-backup.json`). **Record absence** (`auto_review_original: absent`) if there was no prior config.
- **Read the original from the BACKUP once suppress has run (call-order hazard).** The sequence above is backup → suppress → record, so the value is read *after* the live `config.json` has already been rewritten to `auto_review: false` — at that point the live file reports `false` for EVERY original, and only the byte-for-byte backup (or its `__ABSENT__` marker) still holds the truth. **`config-orig <config_path> <backup_path>` prefers the backup when it exists and falls back to the live config when it does not**, so it returns the true original in either call order; a corrupted backup ABORTS (exit 2) rather than fabricate a value. Calling the one-arg form after suppress records a WRONG original — observed 2026-09-04 on a real run, where a config with no `auto_review` key was recorded as `false` instead of `absent`. This matters because RECONCILE (§4 step 3) is the consumer of that recorded value; the *restore* path itself is unaffected (it is byte-for-byte from the backup and never consults `config-orig`). Guarded by `scripts/test-automate-helpers.sh` §A7. A backup path that is **given but missing** falls back to the live config rather than aborting — missing is the normal state of a correct *pre*-suppress call, so aborting on it would re-introduce call-order dependence in the other direction (a *malformed* backup still aborts; it can never be legitimate). **The caller must therefore record `auto_review_original` before the backup is deleted** — a backup lost after suppress puts the reader back on the live config and back on the wrong answer. Both arms pinned in test §A7f.
- **Restore:** overwrite `config.json` from the backup **OR delete `config.json` if it was originally absent** — **never leave a partial `config.json` shadowing the legacy `notify-config.json`** (the new path wins when both exist, so a stray empty `config.json` would mask `notify-config.json`).
- **Malformed pre-existing config ⇒ ABORT.** If the existing `config.json` is not parseable JSON, do not blindly overwrite it — abort the tick (the user has a hand-edited config we must not clobber).
- **Crash-restore:** RECONCILE (§4) restores a crash-stranded backup on the next start.
- On clean restore, **delete** the transient backup sidecar.

### Own ONE inline drain

After suppression, DRAIN owns **exactly ONE** inline `/review-pr --until-mergeable --no-auto-postmortem` (the standalone review-and-heal drain — authority is `skills/review-heal/SKILL.md` §"Until-Mergeable Mode"). The **`--no-auto-postmortem`** flag suppresses the owned drain's churn-gated Postmortem Dispatch Tail: inside `/automate` the engine emits its OWN honest engine-native learning line (§6 step 3 "Learning-emit at end-of-DRAIN"), so the owned drain must NOT also append a GitHub-blind false-0 postmortem line for the same PR — one honest line, not honest + false-0. (Outside `/automate`, a standalone `/review-pr --until-mergeable` keeps its Postmortem Dispatch Tail unchanged.) Its **terminal `REVIEW_HEAL_RESULT` is read synchronously** and written to `## Current`:

- `owned_drain_started: <ts>`
- `owned_drain_result: READY | ESCALATED`  (the `--until-mergeable` terminal decision — `READY` is "ready, left open for a human"; it **never merges**. `READY`'s bound is now **mechanized** via `scripts/drain-rounds.sh`, the same shared ledger both `/review-pr` entry paths call — `review-heal/SKILL.md` §U4 — and `READY` carries a `termination_reason` of `converged` or `sub_floor_converged`; ONLY `sub_floor_converged` is excluded from the §10 trusted-merge gate, condition 1, below)
- `suppressed_default_dispatch: true`

**Verifiable** via those `## Current` fields **plus the absence of any detached `dispatch-pr-review.sh` artifact for the PR** (no `.supervisor/review-dispatch/` marker for the PR URL, no `pgrep -lf review-pr-runner` for it).

> The drain is inline (`/review-pr`), not the detached `--agent` form — the engine runs on the main thread and reads the result synchronously to gate on it. `/review-pr --until-mergeable` **NEVER merges** (it is `READY`-terminal); the ONLY place that executes `gh pr merge --squash` is this engine's `--auto-merge` gate (§10/§11).

---

## §8 — Single-open-PR invariant (BOTH modes)

**While ANY item has an OPEN unmerged PR — status `awaiting_merge` OR `escalated` — the loop MUST NOT PICK a new item.** At most ONE open PR exists at any time.

- **`awaiting_merge`:** RECONCILE (§4) re-checks the PR each tick and **resumes once it merges** — the next item then branches off **fresh `main`** (§6 SYNC). (`--auto-merge` skips this park by merging at the gate — §10 — but still parks on `escalated`.)
- **`escalated`:** the run stays **paused** (`## Status: paused`, `pause_reason: escalated`) until a human resolves it (§9). An escalated PR is open + unresolved; stacking a second PR would violate this invariant.

---

## §9 — Two modes + READY / ESCALATED semantics

**`READY` = "ready, left open for a human" — NOTHING in the plugin merges.** `/review-pr` / `review-heal` and Supervisor Phase 4.5 all terminate at `READY`/`PASS` and leave the PR open. But without a merge the engine would **stale-base** the next item or build a **PR tower**, so the merge is the engine's OWN step:

- **Safe mode (default):** at the GATE, a `READY` drain ⇒ `## Current` status `awaiting_merge`, `## Status: paused`, `pause_reason: awaiting_merge`. The loop parks (single-open-PR invariant) and RECONCILE resumes once a human merges. **Nothing is merged automatically.**
- **`--auto-merge` mode (opt-in, default OFF, gated):** at the GATE, `gh pr merge --squash` fires **only** when the 6-condition trusted gate (§10) holds; otherwise fail **CLOSED** → park + notify.

**`ESCALATED` never merges and PARKS the run** in BOTH modes: `## Status: paused`, `pause_reason: escalated`, notify (best-effort desktop + webhook) — it does **NOT** pick a new item. To proceed:

- **resolve the PR** (fix + merge, or close), **OR**
- **mark the item `skipped`/`abandoned`** in `## Queue` (§5),

then `--resume`.

---

## §10 — Trusted auto-merge gate (6 conditions, fail CLOSED, SELF-RESOLVING)

> **Execute via the helper, not a re-implementation:** the loop hands `automate-helpers.sh gate-eval <pr_url> <ctx.json> [--root <checkout>]` (§1.5) — the **single** implementation of this gate and the **only** code path that executes `gh pr merge --squash` — a SHRUNK `ctx.json` carrying only what the loop alone knows. It prints `MERGE` (after merging) or `PARK: <reason>` and is self-tested for fail-closed behaviour on every condition. The conditions below are the SPEC `gate-eval` implements.

**SELF-RESOLVING (red-team-hardening item 03).** Before this hardening, every condition below validated only the SHAPE of a value the model-authored loop wrote into `ctx.json` (`has()` + `type == "boolean"`, exact-string checks) — none of them re-derived the value from reality, so a `ctx.json` claiming `"high_risk": false` with no `classify-risk.sh` run at all would merge a genuinely high-risk diff. **The gate now computes every condition it can from LIVE ground truth itself** (`gh`, GraphQL, `classify-risk.sh`, and two artifact-file reads) — a caller can no longer hand the gate a fabricated verdict for any of conditions 2 through 6.

**`ctx.json` shape — SHRUNK to exactly what only the drain/loop can know:**

```json
{
  "drain_result": "READY|ESCALATED",
  "termination_reason": "converged|bound_hit|sub_floor_converged|ci_untrusted",
  "ready_sha": "<sha>",
  "trust_unprotected": true|false,
  "review_heal_result_path": "<path to the verbatim REVIEW_HEAL_RESULT artifact>",
  "supervisor_result_path": "<path to the verbatim SUPERVISOR_RESULT artifact>"
}
```

**GATE-OWNED KEYS — REFUSED, NEVER TRUSTED.** Every other former key now names a condition the gate computes itself: `high_risk`, `risk_reasons`, `head_sha`, `base`, `review_decision`, `unresolved_human_thread`, `protection_enforceable`, `checks_green`, `rubric_satisfied`. **If a `ctx.json` carries ANY of these keys — regardless of the value — the gate PARKs with `PARK: ctx_carries_gate_owned_key` before evaluating anything else.** A caller attempting to hand the gate a pre-computed verdict for a gate-owned condition is refused outright, never silently accepted. This is checked FIRST, ahead of every condition below.

`gh pr merge --squash` fires **ONLY** when **ALL 6** conditions hold. If any fails or is **unreadable** ⇒ fail **CLOSED** → park (`pause_reason: awaiting_merge`/`escalated`) + notify. (Two values are NOT automatic parks — they have explicit per-condition semantics below: a **reviews-not-required `reviewDecision`** is deferred to cond 4, and an **absent rubric** is N/A — see cond 3 and cond 5.) This gate — implemented in `automate-helpers.sh gate-eval` — is the **only** sanctioned, EXECUTED `gh pr merge --squash` in the plugin (§11).

1. **Owned drain == `READY`, AND its `termination_reason` is NOT `sub_floor_converged`.** The engine's own inline `/review-pr --until-mergeable` (§7) returned `READY` (not `ESCALATED`). **A `sub_floor_converged` READY is NOT auto-merge-eligible** (AC9, drain-bounding-earned-checks): its final round skipped the all-channel bot-finding re-scan (`review-heal/SKILL.md` §"Termination-only severity floor"), so it must PARK exactly like a non-`READY` drain result. `automate-helpers.sh gate-eval` reads `termination_reason` with the same explicit `has()`/`!= null` fail-CLOSED form as cond 3's `unresolved_human_thread` — missing/unreadable ⇒ PARK, never a silent merge. **`termination_reason: ci_untrusted` (ci-trust-probe-01):** a `ci_untrusted` termination always pairs with `drain_result: ESCALATED`, never `READY` (`scripts/ci-run-probe.sh` classifying a required check `untrusted_infra` still blocks READY, `review-heal/SKILL.md` §"READY redefinition"), so a well-formed ctx already fails CLOSED through this SAME condition's `drain_result != "READY"` check. `gate_eval()` (`automate-helpers.sh`) ALSO carries a separate, deliberate defense-in-depth PARK for this value specifically (its condition 1c, immediately after the `sub_floor_converged` check) — mirroring that guard's shape — so a hypothetically-corrupted ctx claiming `drain_result: READY` alongside `termination_reason: ci_untrusted` still cannot merge.
   - **Cross-checked against the artifact, never trusted as a bare assertion.** The gate ALSO reads `ctx.json`'s `review_heal_result_path` — the file the DRAIN step (§6) wrote the terminal `REVIEW_HEAL_RESULT` block to VERBATIM — and parses that file's OWN `decision`/`termination_reason` fields (a bounded grep/awk extraction; `result_block_parser.py` is a library with no CLI). The ctx's `drain_result`/`termination_reason` MUST match what the artifact actually says, or the gate PARKs (`PARK: review_heal_result_unreadable` if the file is missing/unreadable, `PARK: drain_result_mismatch` if the two disagree). The drain's self-report about its own outcome is corroborated against the artifact it actually produced, never trusted blind.

2. **Head SHA still == the `READY` SHA AND base == `main`.** The gate itself re-reads `gh pr view <url> --json headRefOid,baseRefName,statusCheckRollup`; if the live head moved since the drain declared `READY` (a new commit landed), or the base is not `main`, **do not merge** (the approved state is stale). `ready_sha` stays a ctx input (the drain's claim) — but it is now CROSS-CHECKED against the live read, never trusted alone.

3. **`reviewDecision` not blocking AND no unresolved thread from an actor outside the trusted-actor set.**
   - The gate reads `gh pr view <url> --json reviewDecision` ITSELF (a separate call from condition 2's, so a reviewDecision-specific read failure PARKs on its own reason rather than being masked by condition 2's) ⇒ **NOT** in `{CHANGES_REQUESTED, REVIEW_REQUIRED}` (those park). A **`null` `reviewDecision` means the branch does not require approving reviews** (an unprotected branch, or **checks-only protection**) — this is **NOT** a cond-3 blocker; whether such a branch may merge is decided by **cond 4** (enforceable protection OR `--trust-unprotected`). Only a **genuinely unreadable** read (the `gh` call failed) parks here (fail closed) as `PARK: review_decision_unreadable`.
   - **No unresolved thread from an actor outside the trusted-actor set.** Threads are **GraphQL-only** (there is **no** `gh pr view --json reviewThreads` flag — see `review-heal/SKILL.md` §"Step U1 — All-Channel Read" GraphQL block, and its Anti-Pattern "Inventing a `gh pr view --json reviewThreads` flag"). The gate runs the query itself, VERBATIM from `review-heal/SKILL.md` §"Step U1" (b) (never re-derived):
     ```
     gh api graphql -f query='
       query($owner:String!,$repo:String!,$number:Int!){
         repository(owner:$owner,name:$repo){
           pullRequest(number:$number){
             reviewThreads(first:100){
               pageInfo{ hasNextPage }
               nodes{ isResolved comments(first:1){ nodes{ author{ login __typename } } } }
             }
           }
         }
       }' -F owner=<owner> -F repo=<repo> -F number=<number>
     ```
     For each `isResolved == false` thread, the gate checks the first comment's author login against the **trusted-actor set** (`${HOME}/.claude/loomwright/trusted-actors.json`, red-team-hardening item 01 — the SAME user-scope allowlist `classify-bot-review.sh --trusted-actors` and `wrap-external-text.sh` resolve): an actor **NOT** in the set ⇒ BLOCK. This is a stricter, merge-time-only rule than §U3's drain-readiness bot-vs-human split (which lets ANY bot-authored thread through) — the FINAL merge gate trusts only the explicitly-named allowlist, not a login-shape heuristic. `hasNextPage == true` (truncated >100 threads) or ANY GraphQL read error ⇒ fail CLOSED (treated as a blocking thread) — same "absent file ⇒ nobody trusted" resolution as `wrap-external-text.sh`, no `bot_author_re` fallback here.

4. **Enforceable branch protection (OR explicit `--trust-unprotected`).** The gate itself calls `gh api repos/<owner>/<repo>/branches/main/protection` ⇒ protection is **enforceable** when `required_approving_review_count >= 1` **OR** there are required status checks. A **404** ⇒ genuinely unprotected (`false`); **ANY OTHER error** ⇒ `PARK: protection_unreadable` (never silently treated as either protected or unprotected). **GitHub rulesets are out of scope in v1** (only classic branch protection is read). This condition is what actually decides a **reviews-not-required** branch (cond 3 `null`/"none"): a **checks-only-protected** branch (required status checks, `required_approving_review_count == 0`) is enforceable and may merge; a **truly unprotected** branch merges ONLY with `--trust-unprotected`. **Scope of the flag: `--trust-unprotected` overrides condition 4 ONLY** — it does not touch condition 6 (a high-risk diff parks with or without it), and there is no flag, config key, or project file that overrides condition 6. `trust_unprotected` stays a ctx input — it is a legitimate operator flag, not a fact the gate can observe.

5. **Required checks green AND rubric satisfied.**
   - Required checks: the gate discovers the required-context list from the SAME branch-protection payload condition 4 already fetched (the discovery recipe is `review-heal/SKILL.md` §"Step U2 — Required-check discovery") and cross-references it against `statusCheckRollup` from condition 2's combined read — all green, or there are no required contexts (vacuously green).
   - **Rubric satisfied — now a FILE READ, never a caller-asserted value.** `ctx.json`'s `supervisor_result_path` names the file the RUN step (§6) wrote the terminal `SUPERVISOR_RESULT` block to VERBATIM; the gate parses a `rubric_score: N/M` line from that file ITSELF. `N == M` ⇒ satisfied; no such line ⇒ **N/A — NOT a blocker** (the item had no `## Outcomes Rubric`); the file missing/unreadable ⇒ `PARK: supervisor_result_unreadable`.

6. **NOT a high-risk diff — the gate ITSELF invokes `classify-risk.sh`, NO override of any kind (owner decision R5).** The gate runs `"$(dirname "$0")/classify-risk.sh" main <live head_sha> --root <checkout>` (the plugin's `scripts/classify-risk.sh`) on the **live head SHA condition 2 just confirmed** and reads `.high_risk`/`.reasons` from its own output — **no `ctx.json` input feeds this condition any more** (`high_risk`/`risk_reasons` are gate-owned keys, refused if present — see above). The script is the ONE implementation of the high-risk heuristic (branches a/b/c — security/financial/migration surfaces, workflow/orchestration surfaces, sheer size — plus the add-only `.agent/risk.json` project extension; `classify-risk.sh --kind-table` prints the rules and `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT carries the one committed copy — not restated here). `gate-eval` reads `high_risk` in EXACTLY cond 3's fail-CLOSED shape (`has()` + `type == "boolean"`, MERGE only on the JSON boolean `false`): `true`, `null` (unclassifiable — bad ref, git or jq failure), a missing key, or ANY string — including `"false"` — all park as `PARK: high_risk_diff (<first 3 reasons; "; ">)`. **Nothing overrides this condition** — not `--trust-unprotected` (cond 4 only), not a config key, not an `exclude` list (`.agent/risk.json` has none; projects may only ADD surfaces).
   - **Honest limit:** the heuristic is pattern-based, not semantic — a comment containing `token` trips it, and in an agent-orchestration repo nearly every PR touches `agents/`/`commands/`/`skills/`, so nearly every PR parks here by construction. That is the intent: high-risk stays behind a human.

On all 6 holding: `gh pr merge --squash <url>`. Then SYNC (`git checkout main && git pull`) so the next item branches fresh (§6).

---

## §11 — Invariant preservation

- **`review-heal` / `/review-pr` / Supervisor Phase 4.5 still NEVER merge.** They terminate at `PASS` / `READY` / `ESCALATED` and leave the PR open. The **invariant — the ONLY place in the plugin that EXECUTES `gh pr merge --squash` is this `automate-loop` `--auto-merge` gate, implemented in `automate-helpers.sh gate-eval`** (§10) — holds regardless of how many docs *describe* it. As a check, a positive-form grep — `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` — must resolve to ONLY these sanctioned surfaces (the executor + the docs/tests that describe it; the negative-assertion mentions in `review-heal`/`review-pr`/`RESULT_SCHEMAS` are correctly excluded by the filter, and `commands/automate.md`'s two mentions are also excluded because both sit beside "NOT"/"NEVER"):
  - `skills/automate-loop/SKILL.md` — this contract (§10/§11).
  - `scripts/automate-helpers.sh` — the **actual executor** (`gate-eval`, the only code path that runs the command). Condition 6 (v15.72.0) lives INSIDE this same executor — it adds a park condition, never a second merge path, so the surface list stays at these five while the gate has six conditions. `scripts/classify-risk.sh` is a read-only classifier and never merges.
  - `scripts/test-automate-helpers.sh` — the self-test that exercises the gate.
  - `commands/agent-help.md` — describes the `--auto-merge` gate as the one place the squash-merge runs.
  - `scripts/result_block_parser.py` — a **comment only** (`result_block_parser.py:1379` [pins: `convention CLAUDE.md already uses`]), citing this grep's `no |never |not ` negation filter as the precedent for the worker destructive-command tripwire's own negation filter. The file has no `subprocess`/`os.system`/`popen` call and no other `gh` reference; it parses result blocks and executes nothing.
- **All `/autonomous` correctness gates bubble up** — NO-GO, Plan Review FAIL×3, Supervisor adjudication, the rubric gate — exactly as they do for a direct `/autonomous` run. The engine never auto-picks an adjudication option.
- **`--notify` / `--non-interactive-fallback` / `--cheap` pass through** to the inner `/autonomous` invocation (forwarded on the RUN step). `--non-interactive-fallback` also governs the engine's own gates (queue-confirm skipped, ambiguous resume fails closed — §2/§4). `--cheap` (v15.2.0+) is a **pure passthrough** — the engine never interprets it and does NOT persist it in the run file's `## Run Config` (same flag-persistence convention as `--notify` / `--non-interactive-fallback`): re-pass it on each `/automate --resume` or `/loop` tick. The inner `/autonomous` forwards it on to every inlined `/supervisor` (its EXECUTE step 1 §"Auto-forwarded flags"), completing the `/automate → /autonomous → /supervisor` cost-profile chain; profile semantics + Haiku-session caveat live in `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" (not restated here). No interaction with the `.auto_review` suppress contract, the owned drain, or the trusted-merge gate.
- **Concurrent-run constraint (ENFORCED, red-team-hardening/06):** the `.auto_review:false` window (§7) is **repo-global** while set — two `/automate` loops in one repo would collide on the toggle, `git checkout`, and `state.md`. This is no longer merely documented: PICK (§6 step 1) acquires `.supervisor/run.lock` (`scripts/run-lock.sh acquire --owner automate:<run_id> --session-id <session_id>`) before touching anything, and a second `/automate`/`/autonomous`/`/supervisor` run in the SAME checkout is refused with `run_lock_held owner=<label> pid=<pid> age=<s>` — it never proceeds silently. See the `run-lock.sh` row in §1.5 and the PICK step below.

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
/automate ... --auto-merge                   # opt-in trusted-merge at the gate (gated; default OFF)
/automate ... --trust-unprotected            # allow auto-merge onto a branch without enforceable protection (§10 cond. 4 ONLY — never overrides cond. 6, the high-risk park; nothing does)
/automate ... --notify                       # passthrough to inner /autonomous (gate webhooks)
/automate ... --non-interactive-fallback     # passthrough to inner /autonomous + engine gates fail closed
/automate ... --cheap                        # passthrough to inner /autonomous (Sonnet cost profile → /supervisor; not persisted — re-pass on --resume)
/automate ... --max-tokens N                 # opt-in spend ceiling (red-team-hardening/06) — PARKS before PICK on breach; PERSISTED in ## Run Config (unlike --cheap/--notify)
```

### `/loop` driver (namespaced form required headless)

The engine is designed to be driven continuously by Claude's `/loop`. Use the **namespaced** form (bare `/automate` is "Unknown command" under detached `claude -p`):

```
/loop /loomwright:automate [...]
```

`/loop` re-invokes `/automate` each tick; the run file's `## Status` is the stop signal — `done` (Queue fully resolved) or `paused` (limit / awaiting_merge / escalated) both stop the driver.

---

## Anti-Patterns

- **Building an adapter framework for sources.** Intake is "convert the source into the Queue, once" (§2) — three concrete resolvers (prompt/folder/backlog-doc), not a pluggable plugin system.
- **Creating a manifest / registry / `progress.jsonl` / dashboard file.** The ONE run file is the only persistent tracking artifact (§3); the only sidecar is the transient config-backup (§7).
- **Rewriting `## Progress`.** It is append-only (§3) — rewriting it loses crash-recovery breadcrumbs.
- **Non-atomic run-file writes.** A crash mid-write would lose the ONLY copy of resume state — always temp + rename (§3).
- **Trusting a checkbox without reconciling.** The run file is *belief*; reconcile vs `gh`/`git`/`## Status: done` before trusting it (§4). A crash between merge and check-off makes them disagree.
- **Asserting "merged"/"on main" from memory.** Always verify via `gh pr view --json state,mergedAt` / `git branch --contains` (§4) — this is the stale-branch incident discipline.
- **Double until-mergeable drain.** Suppress `.auto_review` around the RUN phase and own exactly ONE inline drain (§7); never let `/autonomous`'s detached drain race the engine's.
- **Toggling `.auto_review` at DRAIN instead of around RUN.** Both default dispatches fire *during* `/autonomous` — DRAIN is too late (§7).
- **Leaving a partial `config.json` on restore.** Restore byte-for-byte OR delete-if-originally-absent; a stray empty `config.json` shadows the legacy `notify-config.json` (§7).
- **Overwriting a malformed pre-existing `config.json`.** Abort the tick instead — never clobber a hand-edited config (§7).
- **Picking a new item while a PR is open.** Single-open-PR invariant — `awaiting_merge` and `escalated` both block PICK (§8).
- **Retrying RUN into a rate-limit wall, or misreporting it as a dead worker.** A `reason: "rate_limit"` (or an `"unknown"` reason with a `429` hint) on the loop's OWN `agent_lifecycle: failed` row parks the item (`status`/`pause_reason: rate_limit`) and stops — it never re-invokes `/autonomous` for the same item in the same tick (§6 "Rate-limit park").
- **Promoting a `429` text hint into the classified `reason`.** The string-table fallback only ever writes a SEPARATE `reason_hint: rate_limit` field; the underlying `agent_lifecycle` row's `reason` stays whatever was actually classified (§6 "Rate-limit park").
- **Merging on bare `READY`.** `READY` ignores `REVIEW_REQUIRED`, human threads and diff risk; `--auto-merge` must pass ALL 6 conditions of the trusted gate (§10) — fail CLOSED otherwise.
- **Reusing the Supervisor's `risk_classification` at the gate, or inventing an override for condition 6.** The loop re-runs `classify-risk.sh` on the SHA it judges (§10 cond 6); `--trust-unprotected` is cond 4 only; `.agent/risk.json` has no `exclude` key and no flag/config key lowers a classification.
- **Inventing a `gh pr view --json reviewThreads` flag.** Unresolved threads + author type are GraphQL-only (§10 cond. 3; `review-heal/SKILL.md` §"Step U1 — All-Channel Read").
- **Gating rubric on the autonomous EVALUATE loop.** Single-iteration short-circuits EVALUATE; read the rubric from `SUPERVISOR_RESULT.rubric_score` (Phase 4.5 Rubric Grader), which runs under single-iteration (§10 cond. 5).
- **Stacking a second PR on `escalated`.** An escalated PR parks the run; resolve it or mark the item `skipped`/`abandoned`, then `--resume` (§5/§9).
- **Running two `/automate` loops in one repo.** The `.auto_review:false` window is repo-global; single-run-per-repo — ENFORCED by `run-lock.sh` at PICK, not merely documented (§6 step 1 / §11).
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

- Exactly **one** source resolved per run; the FULL resolved Queue is materialized in `## Queue` and human-confirmed before processing (skipped under `--non-interactive-fallback`).
- `--limit N` caps **PROCESSED** items (default 5), never Queue size; the run file always stores the full list.
- Exactly ONE `.supervisor/automate/<run_id>.md` per run — NO `manifest.json` / `runs.jsonl` / `progress.jsonl` / dashboard created.
- Run-file writes are atomic (temp + rename); `## Progress` is append-only; rewrites confined to `## Queue` + `## Current`.
- RESUME globs `*.md` for not-done and reconciles each in-flight item vs `gh`/`git`/`## Status: done` BEFORE trusting a checkbox; continue/new/archive (ambiguous resume fails closed under `--non-interactive-fallback`).
- Single drain: `.auto_review:false` set before `/autonomous`, restored finally-style (config-backup deleted on clean restore, crash-restored by RECONCILE); ONE inline `/review-pr --until-mergeable`; `## Current` records `owned_drain_started`/`owned_drain_result`/`suppressed_default_dispatch:true`; no detached `dispatch-pr-review.sh` artifact for the PR.
- Single-open-PR invariant holds in BOTH modes: `awaiting_merge` resumes on merge, `escalated` parks until human-resolved or the item is `skipped`/`abandoned`.
- `--auto-merge` executes `gh pr merge --squash` ONLY when ALL 6 trusted-gate conditions hold; fails CLOSED (park + notify) on any blocker (unprotected/toothless, moved SHA, `CHANGES_REQUESTED`/`REVIEW_REQUIRED`, null/unreadable `reviewDecision`, unresolved human thread, high-risk or unclassifiable diff per `classify-risk.sh` — no override).
- `READY`/`PASS` from `review-heal`/`review-pr`/Supervisor Phase 4.5 NEVER merge; the ONLY executed `gh pr merge --squash` is the §10 gate implemented in `automate-helpers.sh gate-eval`.
- All `/autonomous` correctness gates bubble up; `--notify` / `--non-interactive-fallback` / `--cheap` pass through to the inner `/autonomous` (`--cheap` is passthrough-only — never interpreted by the engine, never stored in `## Run Config`).
- Termination: Queue fully resolved ⇒ `## Status: done` / `remaining: 0`; `limit` reached ⇒ `## Status: paused` / `pause_reason: limit_reached` / `remaining: <unchecked>`.
- Rate-limit park: a main-scope `agent_lifecycle: failed` row with `reason: rate_limit` (or `reason: unknown` plus a `429` hint, recorded separately as `reason_hint`, never promoted into `reason`) — found in the loop's own session log, post-dating this item's "picked" line — parks the item (`status`/`pause_reason: rate_limit`) and stops BEFORE DRAIN/GATE without retrying; every other classified reason is unchanged (§6 "Rate-limit park"). Resuming it round-trips through the SAME RESUME reconcile as `awaiting_merge` (§4) — no second park vocabulary, no second reconcile path.
