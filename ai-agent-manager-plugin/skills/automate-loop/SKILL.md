---
name: automate-loop
description: Protocol authority for `/automate` — the generic automation engine that converts ANY source (a prompt via /product-owner, a requirements folder, or a backlog-doc) into a FULL Queue with a per-run processing cap inside ONE markdown run file (`.supervisor/automate/<run_id>.md` — the contract, dashboard, and resume state), then drives each Queue item through the per-item loop (`/autonomous --single-iteration` → owned inline `/review-pr --until-mergeable` → trusted-merge-or-park → pull main → check off + append `## Progress`). Smart resume = glob `*.md` for not-done + reconcile-vs-ground-truth. Use when implementing or invoking `/automate`.
allowed-tools: [Read, Write, Edit, Bash, Task, AskUserQuestion]
version: "1.0.0"
lastUpdated: "2026-06-20"
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
| `config-orig` | §7 | Print the recorded `auto_review_original` (`true`/`false`/`absent`). |
| `runfile-write` | §3 | Atomic temp+rename write of the run file (content on stdin). |
| `progress-append` | §3 | Append-only `## Progress` line (never rewrites a prior line). |
| `queue-checkoff` | §3 | Flip `- [ ]` → `- [x]` (optional `# skipped: <reason>` form, §5). |
| `remaining` | §3 | Count of `- [ ]` Queue items (COMPUTED — not a stored run-file field). |
| `resolve-folder` | §2 | List `*.md` in a folder not stamped `## Status: done`. |
| `resolve-backlog` | §2 | Dependency-ordered items honoring `done`/✅ markers (dir-scan fallback). |
| `resume-glob` | §4 | List run files not stamped `## Status: done`. |
| `reconcile-item` | §4 | Reconcile one item's belief vs `gh` ground truth ⇒ `merged`/`awaiting_merge`/`gone`. |
| `gate-eval` | §10 | The 5-condition fail-CLOSED trusted auto-merge gate — the **only** executor of `gh pr merge --squash`. |

> `automate-helpers.sh` is READ-ONLY toward the work it drives (no source-repo edits, no git mutations; the sole exception is `gate-eval`'s explicit `gh pr merge --squash`). It is an **uncounted plain script** (not an agent/command/skill/hook).

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
## Queue                    # `- [ ]` queued · `- [x]` done (merged) · `- [x] … # skipped|abandoned:` excluded; order = processing order
- [ ] <requirement path or generated file>
- [x] <... merged ...>
- [x] <... path ...>  # skipped: <reason>     # checked-off so "next unchecked" never re-picks it; reason also in ## Progress
## Current
- item: <path> | status: running|awaiting_merge|escalated|failed|done | pr: <url> | branch: <name>
- pause_reason: awaiting_merge|escalated|limit_reached|resume_ambiguous|null
- owned_drain_started: <ts> | owned_drain_result: READY|ESCALATED | suppressed_default_dispatch: true
## Progress                 # APPEND-ONLY (never rewritten)
- <ts> picked <item>
- <ts> ran /autonomous → PR <url>
- <ts> drain READY → awaiting_merge
```

### Item lifecycle

```
queued (- [ ]) → running → pr-open → awaiting_merge → merged (- [x]) | escalated (parks) | failed | skipped
```

### `## Status` semantics

- **`running`** — the loop is actively processing (or is the freshly-created run).
- **`paused`** — stopped with work remaining; always paired with a `pause_reason` (`awaiting_merge` | `escalated` | `limit_reached` | `resume_ambiguous`).
- **`done`** — set **only** when the Queue is **fully resolved** (no `- [ ]` items remain), i.e. `remaining: 0`. `remaining` is **COMPUTED/REPORTED** (the count of `- [ ]` Queue items, via `automate-helpers.sh remaining`) — it is **NOT a persisted run-file field**; the template stores no `remaining:` line.

### Crash-safety contract (HIGH-risk mitigation — run-file is the ONLY copy of resume state)

> **Execute via the helper, not a re-implementation:** the run-file mutations are done by shelling out — `automate-helpers.sh runfile-write <runfile>` (full atomic write, content on stdin), `automate-helpers.sh progress-append <runfile> <line>` (append-only `## Progress`), `automate-helpers.sh queue-checkoff <runfile> <item> [reason]` (flip `- [ ]` → `- [x]`, §5), and `automate-helpers.sh remaining <runfile>` (COMPUTED `- [ ]` count) (§1.5). The contract below is the SPEC those subcommands implement.

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
   - **PR merged?** `gh pr view <url> --json state,mergedAt` — a merged PR ⇒ the item is `- [x]` (merged) even if the file still shows it `- [ ]`/`awaiting_merge`.
   - **PR open?** an `OPEN` PR ⇒ the item stays `awaiting_merge` (resumed on merge per §8).
   - **PR closed-unmerged or vanished?** a `CLOSED` (never-merged) or otherwise gone PR ⇒ the item is `gone` — neither merged nor live. Treat it like an `escalated` park requiring human resolution (§9): the run stays paused until the human re-opens/redoes the work or marks the item `skipped`/`abandoned` in `## Queue` (§5). Never silently re-pick or auto-check a `gone` item.
   - **Branch landed?** `git log origin/main --oneline` / `git branch --contains <sha>` — verify the branch actually reached `main` (never assert "merged" from memory).
   - **Requirement stamped?** the requirement file's `## Status: done` stamp.
   - Reconcile each item, then rewrite `## Queue` checkboxes + `## Current` atomically (§3) so belief matches truth.
3. **RECONCILE also restores a crash-stranded config backup** (§7) — if `## Run Config`'s `config_backup` sidecar still exists on disk, the prior tick died with `.auto_review` suppressed; restore it (or delete `config.json` if originally absent) before proceeding.
4. **If an incomplete run exists**, `AskUserQuestion`: **continue / start new / archive**.
   - `--resume [<run_id>]` targets one explicitly; with the id omitted it targets the **most-recent incomplete** run.
   - Under **`--non-interactive-fallback`**, an **ambiguous** resume (more than one incomplete run and no explicit id) **fails closed** → `status_reason: "resume_ambiguous_non_interactive"`, recorded as `pause_reason: resume_ambiguous` in `## Current`.

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

1. **RECONCILE** — re-check ground truth for any in-flight item before picking (§4); never pick a new item while one has an open unmerged PR (§8).
2. **RUN** — set `.supervisor/config.json {"auto_review": false}` (the suppress contract, §7) **then** run `/autonomous --single-iteration --requirement <path>`. The suppress MUST wrap the RUN phase: both default dispatches fire *during* `/autonomous` (Supervisor step 5.5 + the `PostToolUse[Bash]` `gh pr create` hook), so toggling at DRAIN is too late. Capture the emitted `SUPERVISOR_RESULT` (status, `pr_url`, `branch`, `rubric_score`, `heal_decision`). **Restore `.auto_review` in a finally-style cleanup immediately after `/autonomous` returns *or fails* — i.e. BEFORE the owned DRAIN below** (§7). The owned drain is inline and NOT gated by `.auto_review`, so restoring before it both keeps the suppression window tight and is safe.
3. **DRAIN** — own **exactly ONE** inline `/review-pr --until-mergeable` on the PR (§7). Read its terminal `REVIEW_HEAL_RESULT` synchronously; record `owned_drain_started` / `owned_drain_result` / `suppressed_default_dispatch: true` in `## Current`.
4. **GATE** — apply the per-mode decision (§9): safe mode parks `awaiting_merge`; `--auto-merge` runs the 5-condition trusted-merge gate (§10). `ESCALATED` always parks (§9).
5. **SYNC** — after a successful merge (auto-merge mode), `git checkout main && git pull` so the next item branches off **fresh `main`** (no stale-base / PR-tower).
6. **CHECK OFF + PROGRESS** — mark the item `- [x]` in `## Queue` and **append** a `## Progress` line, via **one atomic write** (§3). Report `remaining: N` (count of `- [ ]` items).

### Termination (two exits)

- **Queue fully resolved** (no `- [ ]` left) ⇒ `## Status: done`, `remaining: 0`, the `/loop` driver stops.
- **`limit` items processed** with the queue NOT empty ⇒ `## Status: paused`, `pause_reason: limit_reached`, `remaining: <unchecked count>`, loop stops.

(A park on `awaiting_merge` or `escalated` — §8/§9 — also stops the loop with the corresponding `pause_reason`.)

All `/autonomous` correctness gates still bubble up (NO-GO, Plan Review FAIL×3, adjudication, rubric gate); `--notify` and `--non-interactive-fallback` pass through to the inner `/autonomous` (§11).

---

## §7 — Single drain (no double-dispatch) + the config-toggle contract

`/autonomous` already triggers Supervisor's **default detached until-mergeable drain** (Phase 4.5 step 5.5 **and** the `PostToolUse[Bash]` `gh pr create` hook backstop). If the engine *also* drains, two until-mergeable loops race the branch (HIGH risk). The engine therefore **suppresses the default dispatch and owns exactly ONE inline drain**.

### Suppress window (wrap the RUN phase)

- Set `.supervisor/config.json {"auto_review": false}` **BEFORE** invoking `/autonomous` and restore it in a **finally-style cleanup** immediately after `/autonomous` returns *or fails* — i.e. **BEFORE the engine's own inline `/review-pr --until-mergeable` drain** (§6 step 3). Both default dispatches fire *during* `/autonomous`, so setting it at DRAIN is too late; the owned drain is inline and not gated by `.auto_review`, so restoring before it is correct and keeps the suppression window tight.

### Config-toggle contract (byte-for-byte; absent-delete; malformed-abort)

> **Execute via the helper, not a re-implementation:** suppress with `automate-helpers.sh config-suppress <config_path> <backup_path>`, restore with `automate-helpers.sh config-restore <config_path> <backup_path>`, and read the recorded original with `automate-helpers.sh config-orig <config_path>` (§1.5). The prose below is the SPEC those subcommands implement.

- **Backup:** byte-for-byte copy the existing `.supervisor/config.json` to a **transient** `<run_id>.config-backup.json`. Record its path + the original `.auto_review` value in `## Run Config` (`auto_review_original: <true|false|absent>`, `config_backup: <run_id>.config-backup.json`). **Record absence** (`auto_review_original: absent`) if there was no prior config.
- **Restore:** overwrite `config.json` from the backup **OR delete `config.json` if it was originally absent** — **never leave a partial `config.json` shadowing the legacy `notify-config.json`** (the new path wins when both exist, so a stray empty `config.json` would mask `notify-config.json`).
- **Malformed pre-existing config ⇒ ABORT.** If the existing `config.json` is not parseable JSON, do not blindly overwrite it — abort the tick (the user has a hand-edited config we must not clobber).
- **Crash-restore:** RECONCILE (§4) restores a crash-stranded backup on the next start.
- On clean restore, **delete** the transient backup sidecar.

### Own ONE inline drain

After suppression, DRAIN owns **exactly ONE** inline `/review-pr --until-mergeable` (the standalone review-and-heal drain — authority is `skills/review-heal/SKILL.md` §"Until-Mergeable Mode"). Its **terminal `REVIEW_HEAL_RESULT` is read synchronously** and written to `## Current`:

- `owned_drain_started: <ts>`
- `owned_drain_result: READY | ESCALATED`  (the `--until-mergeable` terminal decision — `READY` is "ready, left open for a human"; it **never merges**)
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
- **`--auto-merge` mode (opt-in, default OFF, gated):** at the GATE, `gh pr merge --squash` fires **only** when the 5-condition trusted gate (§10) holds; otherwise fail **CLOSED** → park + notify.

**`ESCALATED` never merges and PARKS the run** in BOTH modes: `## Status: paused`, `pause_reason: escalated`, notify (best-effort desktop + webhook) — it does **NOT** pick a new item. To proceed:

- **resolve the PR** (fix + merge, or close), **OR**
- **mark the item `skipped`/`abandoned`** in `## Queue` (§5),

then `--resume`.

---

## §10 — Trusted auto-merge gate (5 conditions, fail CLOSED)

> **Execute via the helper, not a re-implementation:** the loop pre-resolves the five conditions into a `ctx.json` (via the `gh` reads described below) and hands it to `automate-helpers.sh gate-eval <pr_url> <ctx.json>` (§1.5) — the **single** implementation of this gate and the **only** code path that executes `gh pr merge --squash`. It prints `MERGE` (after merging) or `PARK: <reason>` and is self-tested for fail-closed behaviour on every condition. The conditions below are the SPEC `gate-eval` implements.

`gh pr merge --squash` fires **ONLY** when **ALL 5** conditions hold. If any fails, is null, or is unreadable ⇒ fail **CLOSED** → park (`pause_reason: awaiting_merge`/`escalated`) + notify. (This gate — implemented in `automate-helpers.sh gate-eval` — is the **only** sanctioned, EXECUTED `gh pr merge --squash` in the plugin — §11.)

1. **Owned drain == `READY`.** The engine's own inline `/review-pr --until-mergeable` (§7) returned `READY` (not `ESCALATED`).

2. **Head SHA still == the `READY` SHA AND base == `main`.** Re-read `gh pr view <url> --json headRefOid,baseRefName`; if the head moved since the drain declared `READY` (a new commit landed), or the base is not `main`, **do not merge** (the approved state is stale).

3. **`reviewDecision` clean AND no unresolved human-authored review thread.**
   - `gh pr view <url> --json reviewDecision` ⇒ **NOT** in `{CHANGES_REQUESTED, REVIEW_REQUIRED}`; **null / unreadable `reviewDecision` ⇒ park** (fail closed).
   - **No unresolved human-authored review thread.** Threads are **GraphQL-only** (there is **no** `gh pr view --json reviewThreads` flag — see `review-heal/SKILL.md` §"Step U1 — All-Channel Read" GraphQL block, and the Anti-Pattern at `review-heal/SKILL.md:544` "Inventing a `gh pr view --json reviewThreads` flag"):
     ```
     gh api graphql -f query='
       query($owner:String!,$repo:String!,$number:Int!){
         repository(owner:$owner,name:$repo){
           pullRequest(number:$number){
             reviewThreads(first:100){
               nodes{ isResolved comments(first:1){ nodes{ author{ login __typename } } } }
             }
           }
         }
       }' -F owner=<owner> -F repo=<repo> -F number=<number>
     ```
     For each `isResolved == false` thread, classify the first comment's author: **bot iff `author.__typename == "Bot"` OR `author.login` matches `*[bot]`** — a bot-authored unresolved thread does NOT block (the drain handles bots); **otherwise BLOCK** (human-authored unresolved thread). **Unreadable ⇒ do-not-merge** (fail closed).

4. **Enforceable branch protection (OR explicit `--trust-unprotected`).** `gh api repos/<owner>/<repo>/branches/main/protection` ⇒ protection is **enforceable** when `required_approving_review_count >= 1` **OR** there are required status checks. **Toothless / unreadable protection ⇒ treated as UNPROTECTED** → do not merge **unless** `--trust-unprotected` was passed. **GitHub rulesets are out of scope in v1** (only classic branch protection is read).

5. **Required checks green AND rubric satisfied.**
   - Required checks (the §10-condition-4 required contexts) are all green in `statusCheckRollup`.
   - **Rubric satisfied — read from `SUPERVISOR_RESULT.rubric_score`** (the Supervisor Phase 4.5 Rubric Grader, which **runs even under single-iteration `/autonomous`**). **Do NOT rely on the autonomous EVALUATE rubric loop** — single-iteration short-circuits EVALUATE (`autonomous-loop/SKILL.md` §"AC-2 single-iteration short-circuit"), so its rubric gate never fires. Satisfied = **N == M**. A **null / absent `rubric_score`** (the item had no `## Outcomes Rubric`) makes this condition **N/A — NOT a blocker**.

On all 5 holding: `gh pr merge --squash <url>`. Then SYNC (`git checkout main && git pull`) so the next item branches fresh (§6).

---

## §11 — Invariant preservation

- **`review-heal` / `/review-pr` / Supervisor Phase 4.5 still NEVER merge.** They terminate at `PASS` / `READY` / `ESCALATED` and leave the PR open. The **invariant — the ONLY place in the plugin that EXECUTES `gh pr merge --squash` is this `automate-loop` `--auto-merge` gate, implemented in `automate-helpers.sh gate-eval`** (§10) — holds regardless of how many docs *describe* it. As a check, a positive-form grep — `grep -rn "gh pr merge --squash" ai-agent-manager-plugin/ | grep -viE "no |never |not "` — must resolve to ONLY these sanctioned surfaces (the executor + the docs/tests that describe it; the negative-assertion mentions in `review-heal`/`review-pr`/`RESULT_SCHEMAS` are correctly excluded by the filter, and `commands/automate.md`'s two mentions are also excluded because both sit beside "NOT"/"NEVER"):
  - `skills/automate-loop/SKILL.md` — this contract (§10/§11).
  - `scripts/automate-helpers.sh` — the **actual executor** (`gate-eval`, the only code path that runs the command).
  - `scripts/test-automate-helpers.sh` — the self-test that exercises the gate.
  - `commands/agent-help.md` — describes the `--auto-merge` gate as the one place the squash-merge runs.
- **All `/autonomous` correctness gates bubble up** — NO-GO, Plan Review FAIL×3, Supervisor adjudication, the rubric gate — exactly as they do for a direct `/autonomous` run. The engine never auto-picks an adjudication option.
- **`--notify` / `--non-interactive-fallback` pass through** to the inner `/autonomous` invocation (forwarded on the RUN step). `--non-interactive-fallback` also governs the engine's own gates (queue-confirm skipped, ambiguous resume fails closed — §2/§4).
- **Concurrent-run constraint (documented):** the `.auto_review:false` window (§7) is **repo-global** while set. **Do NOT run two `/automate` loops in one repo** — they would collide on the toggle. Single-run-per-repo is an assumed constraint, not enforced.

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
/automate ... --trust-unprotected            # allow auto-merge onto a branch without enforceable protection (§10 cond. 4)
/automate ... --notify                       # passthrough to inner /autonomous (gate webhooks)
/automate ... --non-interactive-fallback     # passthrough to inner /autonomous + engine gates fail closed
```

### `/loop` driver (namespaced form required headless)

The engine is designed to be driven continuously by Claude's `/loop`. Use the **namespaced** form (bare `/automate` is "Unknown command" under detached `claude -p`):

```
/loop /ai-agent-manager-plugin:automate [...]
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
- **Merging on bare `READY`.** `READY` ignores `REVIEW_REQUIRED` and human threads; `--auto-merge` must pass ALL 5 conditions of the trusted gate (§10) — fail CLOSED otherwise.
- **Inventing a `gh pr view --json reviewThreads` flag.** Unresolved threads + author type are GraphQL-only (§10 cond. 3; `review-heal/SKILL.md:544`).
- **Gating rubric on the autonomous EVALUATE loop.** Single-iteration short-circuits EVALUATE; read the rubric from `SUPERVISOR_RESULT.rubric_score` (Phase 4.5 Rubric Grader), which runs under single-iteration (§10 cond. 5).
- **Stacking a second PR on `escalated`.** An escalated PR parks the run; resolve it or mark the item `skipped`/`abandoned`, then `--resume` (§5/§9).
- **Running two `/automate` loops in one repo.** The `.auto_review:false` window is repo-global; single-run-per-repo (§11).
- **Letting the engine merge anywhere but the §10 gate.** `gh pr merge --squash` lives ONLY in the `--auto-merge` gate; `review-heal`/Supervisor Phase 4.5 never merge (§11).

---

## Related Skills

- `skills/autonomous-loop/SKILL.md` — the `/autonomous` inner loop the per-item RUN step drives `--single-iteration`; its Rubric Grader feeds §10 condition 5, and EVALUATE short-circuit is why we read `rubric_score` from `SUPERVISOR_RESULT`.
- `skills/review-heal/SKILL.md` — the authority for the OWNED `/review-pr --until-mergeable` drain (§7), the READY semantics (§9), the GraphQL review-thread query and bot-vs-human classification (§10 cond. 3), and the env-var dispatch signal contract (`AI_AGENT_MANAGER_UNTIL_MERGEABLE` etc.).
- `skills/state-management/SKILL.md` — `.supervisor/` state-file conventions (atomic writes, append-only logs).
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
- `--auto-merge` executes `gh pr merge --squash` ONLY when ALL 5 trusted-gate conditions hold; fails CLOSED (park + notify) on any blocker (unprotected/toothless, moved SHA, `CHANGES_REQUESTED`/`REVIEW_REQUIRED`, null/unreadable `reviewDecision`, unresolved human thread).
- `READY`/`PASS` from `review-heal`/`review-pr`/Supervisor Phase 4.5 NEVER merge; the ONLY executed `gh pr merge --squash` is the §10 gate implemented in `automate-helpers.sh gate-eval`.
- All `/autonomous` correctness gates bubble up; `--notify` / `--non-interactive-fallback` pass through to the inner `/autonomous`.
- Termination: Queue fully resolved ⇒ `## Status: done` / `remaining: 0`; `limit` reached ⇒ `## Status: paused` / `pause_reason: limit_reached` / `remaining: <unchecked>`.
