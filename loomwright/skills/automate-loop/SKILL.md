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

> **Split layout (parallel-automate/22, move-only).** This file is the skill's index. A section below that carries only a `See [<file>](<file>).` line was moved verbatim to that file in this directory — read the file for the section; every `§N` number and heading is unchanged. `commands/automate.md` Step 0 reads every split file, so the inline engine still loads the whole protocol. `scripts/test-automate-loop-split.sh` keeps this index and the files in step.
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
| `runfile-write` | §3 | Atomic temp+rename write of the run file (content on stdin), **fail-CLOSED on the payload** (§3 "Crash-safety contract" → "Validate before rename"): refuses (exit 1, temp removed, run file byte-unchanged) empty content, content missing the `# Automate Run:` title / `## Status:` line / `## Queue` heading, and a rewrite that does not keep the existing `## Progress` block as its prefix. |
| `progress-append` | §3 | Append-only `## Progress` line (never rewrites a prior line). Refuses (exit 1, file untouched) a target with no `# Automate Run:` title — never fabricates a `## Progress` section on a non-run file. **`current_not_set` guard** (§3 "`## Current` moves only through `current-set`"): after a successful append, a line starting (after one optional timestamp token) `picked `, `ran /autonomous` or `owned drain started` while `## Current`'s item is `null`/empty/absent — or a `picked <X>` line while `## Current` names a different item whose status is not `done` — prints `current_not_set: <line>` to stderr and exits **3**; the line IS appended (loud, not lossy). `parked ` lines are not guarded. |
| `current-set` | §3 | The ONLY writer of `## Current`'s `- item:` and `- pause_reason:` lines (§3 "`## Current` moves only through `current-set`"). `current-set <runfile> [--item <path\|null> --status <s\|null>] [--pr <url\|null>] [--branch <b\|null>] [--pause-reason <r>]` — ITEM form (both `--item` and `--status`; `null` only when both are `null`) or RUN-LEVEL form (neither; `--pause-reason` only). Values validated against the §3 enums; a changed `--item` resets an omitted `--pr`/`--branch` to `null`, the same item keeps them; every other line byte-unchanged; refusals exit 1 with the file byte-unchanged; identical values print `current-set: unchanged` and write nothing. |
| `current-rebuild` | §4 step 2 | RECONCILE repair for a `## Current` that was never set, or left stale: a `picked` Progress line AND an item that is null/absent — or `status: done` and different (after a leading `./` strip) from the LAST `picked` line's item, a PICK after a close-out that skipped its `current-set` ⇒ item from the LAST `picked` line (must be a Queue row), PR ONLY from a `ran /autonomous` line after it, branch from one `gh pr view`; always `status: running` with `pause_reason: null` (a stale pause reason such as `awaiting_go` never sits beside `status: running` — automate-followups/36 A3); writes via `current-set`, appends + prints `current_rebuilt: <item> pr <url\|null> state <OPEN\|MERGED\|CLOSED\|unknown\|none>`. Set and not `done`, or `done` and naming the last picked item ⇒ `current-rebuild: skipped — ## Current set`. |
| `queue-checkoff` | §3 | Flip `- [ ]` → `- [x]` (optional `# skipped:`/`# abandoned: <reason>` form via the `mark` arg, default `skipped`, §5). Refuses (exit 1, file untouched) a target with no `# Automate Run:` title. |
| `remaining` | §3 | Count of `- [ ]` Queue items (COMPUTED — not a stored run-file field). |
| `resolve-folder` | §2 | List `*.md` in a folder not stamped `## Status: done` and not `## Status: proposed\|parked` (harness-port/02). |
| `resolve-backlog` | §2 | Dependency-ordered items honoring `done`/✅ markers AND the referenced file's own `## Status: done`/`done_with_escalation` stamp (`is_done`); dir-scan fallback also skips `## Status: proposed\|parked` (harness-port/02) — a checklist line naming a file directly is unaffected by that not-ready stamp (by design). |
| `queue-confirm` | §2 | Gate `AUT-QUEUE` ask-or-skip, READ-ONLY (automate-speed/01, owner decision D1). `queue-confirm <source> <n> <limit>` prints ONE line: `skip — backlog queue <n> ≤ limit <limit>` when `<source>` is `backlog` and `<n> ≤ <limit>`; `ask` for `folder` / `prompt` at any count, `<n> > <limit>`, a value that is not a plain count (`0` or 1–9 digits, no sign or leading zero), or an unknown source (fail toward asking). `queue-confirm --lane-backlog` prints `skip — lane backlog written by lane-create from the owner's --parallel command` (the lane's B8 skip). The engine writes the reason after `skip — ` as ONE `skipped AUT-QUEUE: <reason>` `## Progress` line. Exit 0; a missing argument exits 1. |
| `resume-glob` | §4 | List run files not stamped `## Status: done`. A run file is a `*.md` carrying the `# Automate Run:` title line anywhere (`is_run_file`) — so the §6 steps 2–3 result sidecars (`<run_id>.review-heal-result.md`, `<run_id>.supervisor-result.md`) are never listed because they carry no `# Automate Run:` line (the title is matched anywhere in the file, so a sidecar that did carry one would be listed; tolerant title forms: §4 step 1). **`resume-glob <automate_dir> --finalize`** (§4 step 1) first runs `finalize-empty` on each listed run and then lists only the ones still not `## Status: done` (stdout stays one path per line; a finalized run's output lines, and a `not finalized` line for a lock-held / refused finalize, go to stderr); plain `resume-glob <dir>` output is byte-unchanged. |
| `reconcile-item` | §4 | Reconcile one item's belief vs `gh` ground truth ⇒ `merged`/`awaiting_merge`/`gone`. |
| `gate-eval` | §10 | The fail-CLOSED trusted auto-merge gate (conditions enumerated in §10) — the **only** executor of `gh pr merge --squash`. **SELF-RESOLVING (red-team-hardening item 03):** the gate re-derives every condition from 2 on itself from live `gh`/GraphQL/`scripts/classify-risk.sh`/`scripts/rules-gate-verdict.sh` reads and two artifact-file reads — the loop passes only what it alone knows (`drain_result`, `termination_reason`, `ready_sha`, `trust_unprotected`, `review_heal_result_path`, `supervisor_result_path`). A ctx carrying any gate-owned key (`high_risk`, `risk_reasons`, `head_sha`, `base`, `review_decision`, `unresolved_human_thread`, `protection_enforceable`, `checks_green`, `rubric_satisfied`, `rules_gate`, `rules_ok`, `rules_check`) is refused (`PARK: ctx_carries_gate_owned_key`), never trusted. Condition 6 (`high_risk`) is computed by the gate itself via `scripts/classify-risk.sh`, and condition 7 (a stamped, gate-countable `must`-rule check failing — `rules_check_failed` and its sibling PARK reasons) via `scripts/rules-gate-verdict.sh`; nothing overrides either. |
| `learning-emit` | §6 step 3 | Fail-SAFE (always exit 0) engine-native ground-truth line: appends ONE full valid `schema_version: 1` POSTMORTEM_RESULT (`source: "automate_drain"` + `automate_key`) per processed PR from `REVIEW_HEAL_RESULT` + `SUPERVISOR_RESULT` data already in hand; idempotent on `run_id`+item+`pr_url`+`source`+completeness (a `changed_paths: []` degraded line never blocks a later complete one — §6 "Learning-emit at end-of-DRAIN"). |
| `brief-repair` | §6 steps 1 & 5 | Fail-SAFE (always exit 0) evidence-positive brief lifecycle repair: `brief-repair <item> <pr_url>` re-reads merge state (`gh pr view`), and ONLY on `MERGED` (or a non-empty `mergedAt`) hands the evidence to the sibling `reconcile-jobs.sh --repair --evidence <item>=<pr_url>` — the one mover, scoped to that item, refusing an ambiguous match. Prints ONE line (`repaired …` / `skipped — <reason>`) for `## Progress` (§6 "Brief-repair at RECONCILE and SYNC"). |
| `reconcile-status` | §4 step 7 | Dry-run-default `reconcile-status <requirements_root> [--apply]` (queue-hygiene/01): stamps a not-done requirement's `## Status:` from a merged PR (a `proposed` draft or `parked` item — `is_not_ready` — is never stamped, and a top-level `<slug>-plan.md` Orchestrator task plan is never a candidate; state via `reconcile-item`; an IMPLEMENTS-line body citation or done/-brief branch-slug evidence. A body citation counts only on a line that opens with `Implements`, `Closes`, `Resolves`, `Fixes`, `Ships`, `Lands`, `Requirement:` or `Source requirement:` (after any list, quote or bold marker), and only before that line's first `;` or `. `; the path may carry or drop the `.supervisor/requirements/` prefix and the `.md` suffix, must sit on a path boundary (`qh/2` never matches `qh/20-x`), and the candidate search uses that short form because GitHub search does not find the full path (PR #484's `Implements \`automate-followups/27-…\`` was invisible to it). A path that is merely listed, quoted as an example or named as a follow-up is not evidence: on 2026-10-11 the any-mention rule planned five false stamps — three from PR #470's `plan-waves` example, one from PR #482 naming a follow-up draft, one from PR #457 naming a task plan — never from the engine's own `chore/<run_id>-trail-<n>` PR, whose body lists every path it commits, so a citation there means "committed", not "shipped"; the same rule is enforced on the PR's diff for every PR: a body citation from a PR whose own changed files include that requirement is not evidence (PR #359 queued `meta-sync-followups/04` and its body cited it), a PR whose changed files are all under `.supervisor/` is never evidence, and an unreadable or incomplete diff — `gh pr view` returns at most 100 files, so a longer one is re-read through the paginated REST endpoint — is no evidence) or an owner `# abandoned:` Queue row, byte-for-byte in the §6 stamp shape; NEVER downgrades an existing `done`/`done_with_escalation`; a `brief-shipped` file (the `stamp-requirement-status.sh` job-landed heading) is held to the same evidence — the stamp is appended under its kept heading — and is only LISTED (`info`) without it. Prints `plan\t…`/`stamped\t…`/`info\t…` rows; writes nothing without `--apply`. Every path it prints or writes — the stamped `- **Brief:**` line (`.supervisor/jobs/done/<brief>.md`) and an abandoned row's run-file field (`.supervisor/automate/<run_id>.md`) included — is repo-relative, never an absolute home path, which the metadata branch's home-path scrub refuses (automate-followups/36 B-B). |
| `sidecar-check` | §6 trail | Delegated to the sibling `automate-trail.sh`. `sidecar-check <path>` prints ONE line, `ok <path>` or `fail <path>: <reason>`, always exit 0: locates the LAST `REVIEW_HEAL_RESULT`/`SUPERVISOR_RESULT` block with `result_block_parser.py` and checks it against key tables that mirror `docs/RESULT_SCHEMAS.md` (a missing required key — v2 `rounds` included — any non-schema key such as `ready_sha`, a non-canonical `channels_scanned` token, `risk_classification` without `reasons`) — and, since automate-followups/20, the same required/allowed key check one level down on every nested object (`ground_truth`, `contract_conformance`, `benchmark_result`, `risk_classification`, and the items of `heal_dismissed`, `dismissed`, `checks_untrusted`, the findings lists; tables in `docs/result-schemas/supervisor-result.md` / `review-heal-result.md` "Nested-object key sets"), so a `ground_truth` without `checked` fails. `trail-pr` never commits a `fail` sidecar. |
| `trail-pr` | §6 trail | Delegated to `automate-trail.sh`. `trail-pr <runfile> [--reason <reason>]` commits this run's explicit trail paths as ONE PR (`chore/<run_id>-trail-<n>`) from a temporary worktree off fresh `origin/main` and prints ONE line (`opened`/`pushed`/`skipped — <reason>`), always exit 0. Called ONLY by `closeout` (after its merge evidence gate), at the `## Status: done` termination, and when an item is checked off `# skipped:`/`# abandoned:` — never at a park (§14's lane wave end and `lane-remove --abandon` run it inside the lane, `--reason wave-end` / `--reason abandoned`, through the same evidence gate); a done-stamped requirement or done/ brief rides only when its PR reads merged (`; excluded <path> — pr not merged` otherwise) — see "Trail PR after merge and at run end". |
| `closeout` | §6 post-merge, §6 step 5 SYNC, §14 | Delegated to `automate-trail.sh`. `closeout <runfile> <item> <pr_url> [--session-id <sid>] [--no-trail]` — the evidence-gated (`reconcile-item` says `merged`), idempotent, fail-SAFE post-merge close-out: brief repair, PR-head worktree cleanup, `main` sync, squash-safe local-branch cleanup, requirement stamp, queue check-off, then `trail-pr` (check-off first, so the trail PR records the closed-out item); one `<verb> — …` line per step, always exit 0. Just before `trail-pr` it silently appends ONE `item_timing` event (the `phase-timing.sh --run` record: per-phase wall-clock, owner vs machine time — derived from logged timestamps, never computed by a model) to the item's session log; it prints nothing and changes no step's verb (`docs/result-schemas/session-end-jsonl.md`). `--no-trail` (any position) skips ONLY the `trail-pr` step, printing `trail-pr: skipped — --no-trail` in its place — not a `closeout:` line, so `closeout-classify` reads such a run as `complete`; `--auto-merge` SYNC (§6 step 5) and a merged lane's `lane-convert-ready` re-run (§14) pass it. Never merges, never picks the next item. |
| `closeout-classify` | §6 step 1 "Close-out leftover gate" | Pure logic over ONE `closeout` invocation's output on stdin — run it once per `closeout` call, never on the interleaved output of several. `closeout-classify [--run <run_id> --item <path> --pr <url>] [--record <runfile>]` classifies ONLY the lines starting `closeout: ` (the passed-through `brief-repair:` / `trail-pr:` lines have their own surfacing) against an explicit table in the helper built from every `closeout: …` string `automate-trail.sh` prints. **The partial-removal form `closeout: removed — worktree A; kept B` is a leftover whatever its verb, and a NAME containing `kept` does not make a line a leftover** (the partial-removal form is real output of the worktree step; an item or branch name that merely contains `kept` is classified by its row like any other line). **complete** = a `removed`/`synced`/`stamped`/`checked`/`reconciled` line not in that partial-removal form, and the idempotent `skipped — already …`, `skipped — ## Current already done` and `skipped — ## Current is <other> …` (a watcher that fired after a later pick). **leftover** = the partial-removal form, `skipped — kept worktree …`, any refusal, a sync skipped because the primary is dirty / detached / on another branch / its fetch or pull refused, `skipped — no done brief`, `skipped — run lock held by <owner> (holder pid <p> not running)` (a dead or unreadable holder — `run-lock.sh` reclaims only a dead pid at age ≥ 1800 s, so a dead-but-young lock still refuses), `skipped — gh unavailable`, `skipped — pr not merged …` (the caller runs `closeout` only after `reconcile-item` said `merged`, so a not-merged answer here means `gh` disagreed or was unreadable — fail toward asking), **any `closeout:` line not in the table**, and an input carrying no `closeout:` line at all. **run_lock_held** (automate-followups/36 A1) = `skipped — run lock held by <owner> (live pid <p>)`: `closeout` met the run lock held by a LIVE process (it reads the holder's pid from `run-lock.sh`'s refusal — the same `owner=… pid=… age=…` fields `run-lock.sh status` prints — and asks `run-lock.sh liveness --pid <p>` at refusal time — run-lock's own `holder_alive` rule, so a reused pid or a lock that changed hands reads `not running`); usually another lane's run in this checkout. It is neither `complete` nor a leftover: nothing ran, nothing needs cleaning up, and it is retried later. Prints `complete` (one line), or one `leftover<TAB><run_id><TAB><item><TAB><pr><TAB><step><TAB><detail>` row per leftover followed by one `run_lock_held<TAB>…` row (same columns, step `lock`) per live-holder line (`-` for an omitted value; `<step>` ∈ `guard`, `gate`, `lock`, `worktree`, `sync`, `branch`, `stamp`, `checkoff`, `current`, `unknown`, `none`). Exit 0 (a usage error exits 1 — the caller reads anything but exactly `complete` as a leftover, except that at start `closeout-others` treats an answer of `run_lock_held` rows alone as not a leftover — §6 step 1). `--record <runfile>`: on `complete` when NO step changed anything (no `removed`/`stamped`/`checked`/`reconciled` line, no non-skip `brief-repair:` line), `progress-append`s `<ts> closeout: nothing to close out — <item>` unless that run's `## Progress` already carries that exact line for the item — at most one per item per run, so an idempotent re-run adds nothing. |
| `closeout-others` | §4 start order / §8 | Delegated to `automate-trail.sh` (it runs `closeout`, a git mutator). `closeout-others <automate_dir> [--record <runfile>]` — the cross-run close-out: for every `resume-glob` run file other than `--record`'s whose `## Current` item line has a non-null `pr`, a `status` other than `done`, and a PR `reconcile-item` reads `merged`, runs `closeout <that runfile> <item> <pr>` (NO `--session-id`: its own `automate-closeout:<run_id>` lock, its own trail), then — branch mode OFF only — `trail-unstage <that runfile>` (that run's staged trail blobs must not ride into the current run's next commit). Per close-out it prints `closeout-others: <run_id> <item> <pr>`, that closeout's lines, the unstage line, that closeout's own `closeout-classify` answer (`complete`, its `leftover` rows, or a `run_lock_held` row) and ONE record line: `closeout-others: recorded — cross-run closeout <run_id> <item>: <complete \| leftover <step> — <detail> \| run_lock_held — <detail>; retried at the next start>` when it appended that line to `--record`'s run file, `closeout-others: record — …` when there is no such file yet (the engine appends it once the run file exists). The recorded line carries NO PR URL (a URL inside a leftover detail is written `<url>`), so `current-rebuild` can never take another run's PR from it. An OPEN / closed-unmerged / unreadable PR, a `done` item, a `null` item or PR ⇒ that run is untouched and prints nothing. Never touches another run's Queue beyond the in-flight item's check-off `closeout` itself does. Always exit 0. |
| `finalize-empty` | §3 / §4 step 1 | Delegated to `automate-trail.sh` (it takes the run lock, rewrites `## Status` and calls `trail-pr`). `finalize-empty <runfile>` finalizes a run `closeout` finished but may not mark done (§3 "After a close-out"): ONLY when ALL hold — `## Status: paused`, `pause_reason: awaiting_go`, `remaining` 0, and the `## Current` item line's `status: done` — it acquires `run-lock.sh --owner automate-finalize:<run_id>` (held ⇒ `finalize-empty: skipped — run lock held by <owner>`, nothing written), writes `## Status: done` + `pause_reason: null` in ONE validated `runfile-write` (the `pause_reason` line authored by `current-set --pause-reason null` on the staged copy — §3), appends `<ts> auto-finalized: queue empty after closeout`, runs `trail-pr <runfile> --reason done` (the SAME call §6 "Termination" makes) and appends its line — **in that order on purpose** (automate-followups/36 A4): the trail PR carries the `done` stamp, so `done` is written first; a FAILED `trail-pr` is therefore not retried by a later `--finalize` (the run is no longer paused) — its line sits in `## Progress` and the recovery is a hand `trail-pr <runfile> --reason done`, exactly as after the Termination exit — then — branch mode OFF only — `trail-unstage <runfile>` (that run's staged trail blobs must not ride into the current run's next commit), releasing the lock in a trap. Prints `finalize-empty: finalized <runfile>` plus the trail (and unstage) lines, or ONE `finalize-empty: skipped — <reason>` line; idempotent (a second call is `skipped — not paused`); always exit 0. |
| `trail-unstage` | §6 step 1 PICK | Delegated to `automate-trail.sh`. `trail-unstage <runfile>` drops the primary-index entries `trail-pr` staged for this run's trail paths — the current candidates plus every path in `<run_id>.trail-staged` (`git restore --staged -- <path>`, working copies untouched) and prints ONE line (`trail-unstage: unstaged <n> path(s) — <paths>` / `trail-unstage: skipped — <reason>`), always exit 0 — run at PICK before RUN so the next item's branch and commit cannot sweep them. See "Trail PR after merge and at run end". |
| `trail-gate` | §6 step 1 PICK / §8 | Delegated to `automate-trail.sh`. `trail-gate <runfile>` — the single-open-PR invariant counts this run's own trail PR. Run at PICK after RECONCILE (and any `closeout` / skip-abandon `trail-pr` it ran), BEFORE `trail-unstage`. One line, always exit 0: `trail-gate: PARK — trail PR open <url>[, …] (merge or close it, then --resume)` while a `chore/<run_id>-trail-<n>` PR is open (the same lookup `trail-pr` reuses), `trail-gate: PARK — <reason>` when that state cannot be read (gh/jq/git missing, `gh pr list` failing — fail CLOSED), else `trail-gate: clear — no open trail PR; synced — <base> at <sha>` / `…; sync skipped — <reason>` after running `closeout`'s own step-4 sync (`.trail-staged` re-stage, `git checkout <base>`, `git pull --ff-only`; a refusal is reported, never a park). See §8. |
| `dismissed-drafts` | §6 "Dismissed-findings decision step (before the park)" | Delegated to the sibling `automate-dismissed.sh`. `dismissed-drafts <runfile> <item> <pr_url> [--after-fix-now]` reads `<run_id>.supervisor-result.md` (`heal_dismissed`, origin `phase_4_5`, round = `heal_iterations`) then `<run_id>.review-heal-result.md` (`dismissed`, origin `drain`, round = `rounds`) with `result_block_parser.py`, dedupes on (origin, source, whitespace-normalized finding), applies the threshold (the subsection) and writes one propose-only draft per finding over it plus a summary draft for the rest into `.supervisor/requirements/proposed/` through `pc_guarded_write`, content-addressed `<run_id>--<item_stem>-<ih6>--dismissed-<h8>.md` (ih6 = first 6 hex of sha1 of the FULL Queue item path, so two items sharing a basename never share drafts, summary slots or ledger rows, and a draft whose `- **Item:**` line names another item is never rewritten or retired; h8 = first 8 hex of sha1 of `origin\tsource\tnormalized finding`) / summary slots `…--dismissed-summary.md`, `…--dismissed-summary-2.md`, …. The `<run_id>.dismissed-decisions` ledger decides what is (re)written — decisions are never reset; a DECIDED summary covers exactly the entries its `summary-member` ledger rows name (recorded by `dismissed-decide` from the summary's `- **Key:** <h8>` lines), and every below-threshold entry no decided summary covers is (re)written into the first slot with no ledger row, so a decided summary never hides a finding it did not list and an item has at most one undecided summary. **Decisions are per finding, across own/summary drafts** (h8 omits severity, so a rewritten sidecar can move one finding between buckets): a decision on its own-draft name governs it wherever the threshold now puts it (a fix-now finding is never listed in a summary — drain-origin + `--after-fix-now` re-writes its OWN draft `undecided (fix-now unconfirmed)`), else a decided summary that listed it does (follow-up ⇒ not re-asked, drop ⇒ not recreated); an undecided finding is placed by the threshold and an UNDECIDED draft of it left in the other bucket is retired (a `moved` ledger row first — a placement record, never a decision — then removed; a `retired <name>` line), so no finding is listed, asked or counted twice; a new h8 is always drafted. A retire runs only AFTER the finding's new draft was written in the same pass (a `pc_guarded_write` refusal keeps the old draft), only while the old draft's on-disk `- **Decision:**` still starts with `undecided` (a hand-edited one is kept), and an undecided summary slot only when every entry it lists is a current finding (honest limits in the subsection). The ledger missing ⇒ empty; EXISTING but unreadable (EACCES, a non-UTF-8 byte) ⇒ ONE `dismissed-drafts: skipped — unreadable ledger <path>` line and nothing written, retired or appended (read as empty it would reset every decision). Prints one `draft\t<k\|summary>\t<severity\|->\t<path>` row per file written or kept, `no <sidecar> — skipped` / `unreadable <path>` / `refused <name> — <reason>` / `retired <name> — its finding moved to the other bucket` / `kept <name> — <why not retired>` lines, then ONE `dismissed-drafts: <n> per-finding + <s> summary (<m> listed in summary)` line (`<s>` summary files written or kept, `<m>` current entries listed in one of them); always exit 0. |
| `dismissed-decide` | §6 "Dismissed-findings decision step (before the park)" / §6 step 1 | Delegated to `automate-dismissed.sh`. `dismissed-decide <runfile> <draft_path> <fix-now\|follow-up\|drop>` refuses (`dismissed-decide: refused — <reason>`) any path not directly under `proposed/` named `<this run_id>--*--dismissed-*.md`, `fix-now` on a summary draft (Keep / Drop only), and any decision while the ledger EXISTS but cannot be read back (a row nobody can read is no record, yet drop / fix-now delete the draft on it); appends the ledger row FIRST (for a summary, preceded in the same append by one `summary-member\t<h8>\t<name>` row per listed entry), then rewrites the draft's `- **Decision:**` line (`follow-up`) or deletes the draft (`drop` / `fix-now`), then `progress-append`s ONE `dismissed: <decision> <draft_name> — <first 80 chars of finding>` line; always exit 0. |
| `dismissed-pending` | §6 step 1 PICK | Delegated to `automate-dismissed.sh`. `dismissed-pending <runfile>` prints the count of this RUN's drafts (every item's, not only `## Current`'s) whose `- **Decision:**` value starts with `undecided` (so `undecided (fix-now unconfirmed)` counts), or `unknown` when it cannot tell (including a draft with no readable `- **Decision:**` value, and an existing but unreadable ledger) — the caller treats `unknown` as non-zero (fail closed toward asking); always exit 0. |
| `dismissed-cost` | §6 "Dismissed-findings decision step (before the park)" step 2 | Delegated to `automate-dismissed.sh`; READ-ONLY, advisory (never feeds a gate). `dismissed-cost <runfile>` prints exactly ONE line `fix_now_cost: <estimate> (<basis>)` — the median and range of this repo's recorded fix-now re-drains (ledger `fix-now` ts → the step 3 re-drain terminal `## Progress` line; a span with end ≤ start or > 12 h dropped), else loomwright's own labelled 2026-10 baseline; always exit 0. |
| `park-ask-gate` | §6 "Dismissed-findings decision step (before the park)" | The "park before ask" gate of a sequential interactive READY park, READ-ONLY (automate-speed/01, owner decisions D2/D3). `park-ask-gate <runfile> <item> <pr_url> [--wait <seconds>]` prints ONE line: `ask — fix-now allowed: …` only when `## Current` names this item and PR at `status: awaiting_merge`, a `<run_id>.merge-watch` marker beside the run file carries this `pr_url`, and its OWN `gh pr view <pr> --json state` reads exactly `OPEN`; `ask — fix-now unavailable: PR MERGED\|CLOSED\|state <s>\|state unreadable` on any other read (fail closed toward no fix-now push — never `reconcile-item`, which maps an unreadable read to `awaiting_merge`); `ask — fix-now unavailable: closed out` when the item reads `status: done`; else `refuse — <reason>` (a missing/unreadable run file, no or another item/PR, a status that is not `awaiting_merge`/`done`, no marker for this PR within `--wait`) and the engine asks nothing. `--wait <s>` re-judges every 1 s for up to `<s>` s while only the marker is missing (the watcher writes it asynchronously, up to 60 s late when it replaces a watcher for another PR); the engine passes `--wait 75`, the default `0` judges once. Exit 0; a usage error exits 1. |
| `ceiling-check` | §6 step 1 | PICK-time token-ceiling check (red-team-hardening/06): `ceiling-check <runfile> <max_tokens> [--root <checkout>]` sums the run's ledger via `scripts/read-token-ledger.sh --run-id <runfile>` and compares TOTAL against `<max_tokens>`; prints `OK total=<n> max=<n>`, `PARK: token_ceiling total=<n> max=<n>`, or `PARK: ledger_unreadable` — always exits 0 (a PARK is a normal outcome, same convention as `gate-eval`). |
| `fleet-closeout` | §14 "Wave close" | Delegated to `automate-lanes.sh`. `fleet-closeout <parent_runfile>` — the coordinator's stepwise, idempotent wave close in the primary checkout, re-run on each `--resume`: per-lane backstop `lane-convert-ready`, parent Queue check-off, primary sync, `lane-remove`, then leaks, main health and — once the parent Queue is empty — the parent finalize (`## Status: done`, the wave line cleared, `trail-pr --reason done`) and the lock release. One `fleet-closeout: <step> — <detail>` line per lane and step; stops at the first step that must wait. Never merges and never pushes a lane branch. |
| `wave-plan` | §14 "Wave close" | Delegated to `automate-lanes.sh`. `wave-plan <parent_runfile> [--wave-branch <name>]` — READ-ONLY: prints the owner's wave-branch integration commands for the current wave and the conflict rules. Runs no git mutation, no push and no `gh` write. |
| `wave-build` | §14 "Wave close" | Delegated to `automate-wave.sh` (the one writer of a wave branch). `wave-build <parent_runfile> [--wave-branch <name>]` — builds the wave `wave-plan` prints in a temporary worktree off fresh `origin/<base>` (`--no-ff` lane merges, `ci-local.sh`, the release commit last), pushes ONLY the wave branch and opens the wave PR; one `wave-build: <step> — <detail>` line per step, result last. Exit 0 opened / done (already open) · 1 refused (nothing created) · 2 STOPPED (worktree kept, nothing pushed). Never merges a PR, never pushes a lane branch, never force-pushes. Run as a BACKGROUND command. |
| `lane-policy.sh catalog\|wave-set\|resolve\|decide` (standalone script) | §14 "Policy answers" | NOT an `automate-helpers.sh` subcommand: `scripts/lane-policy.sh` holds the ONE authoritative gate catalog (`catalog`), writes the owner's per-wave policy (`wave-set`), resolves the stamped project policy plus the wave policy at `lane-create` (`resolve`) and is the lane relay hook's exact lookup (`decide`). Its header is the contract. |
| `plan-waves` | `--parallel N>1` only (item 05) | **Read-only wave planner (parallel-automate/04).** `plan-waves <runfile\|dir\|item-list> --max N [--root <checkout>]`. **Input:** a run file ⇒ its unchecked `- [ ]` Queue rows (checked rows say which dependencies are merged-done); a directory ⇒ `resolve-folder`'s output; any other file ⇒ one item path per non-blank, non-`#` line (rows/lines resolved against `--root`, default `git rev-parse --show-toplevel`, else `$PWD`). **Grammar** (outside ```` ``` ```` fences, blank lines ignored, a section ends at the next `#`/`##` heading): `## Touches` = one repo-relative path per line (`[A-Za-z0-9._/@+-]`, no leading `/`, no `.` or `..` segment, no `//`; trailing `/` = directory) or the sole line `unknown` — any bad line, `unknown` mixed in, an empty or doubled section ⇒ the whole section is unknown; `## Depends on` = `none`, a 1–3 digit same-folder id, or a relative `*.md` path, one per line — unparseable = missing. **Rules:** a missing `Depends on` depends on every earlier plan-set item; an out-of-set dependency must be merged-done (plain `- [x]` Queue row, or `is_done` on ANY `## Status:` line; an `ABANDONED` stamp and a `# skipped:`/`# abandoned:` row mark both win over a done stamp) else the item prints `blocked` (`waits on <id>` / `… (<skipped\|abandoned> — never landed)` / `depends on <parked\|proposed> <id>`), and dependents of a blocked item are blocked; every comparison uses the physical absolute path; waves fill greedily in input order, ≤ N items, no two whose companion-expanded `Touches` sets intersect (literal prefix: equal, or one is the other plus `/…`), a missing/`unknown` `Touches` item alone in its wave. **Companions:** `<root>/.agent/companions.json`, strict shape `{"schema_version":1,"companions":[{"when":"<case glob>",["new":true,]"add":["<path>",…]},…]}` — `when` is an unquoted, case-sensitive bash `case` pattern (`*` crosses `/`) for a file entry (`"new": true` only when the file is absent under `--root`); `when`/`add` obey the `Touches` path rules (no leading `/`, `//`, `.` or `..` segment) or the table is malformed; a directory entry `D/` fires a rule whose literal prefix (text before the first glob character) starts with `D/` or prefixes it; ONE pass. This repo's `.agent/companions.json` is the shipped example; its `"new": true` `add` lists copy `scripts/check-doc-currency.sh`'s `FILES` array, which is the authority (a `test-automate-helpers.sh` assertion fails on drift). **Exit:** 0 with `wave <k>: <item> …` lines then `blocked <item>: …` lines; 1 with nothing on stdout on usage errors, `item not found: <item>` (a plan-set entry — Queue row, item-list line or resolve-folder result — names no file on disk), `unknown dependency <id> in <item>`, `dependency cycle: <items>`, or `companions_malformed <reason>` (malformed table or `jq` missing — fail CLOSED); an absent table is one stderr note and no expansion. **Read-only; called only by `--parallel N>1` (item 05); never called when N = 1 (`--max 1` is not queue order once an item depends on a later-numbered one); the sequential loop never calls it.** **`--explain`** (parallel-automate/10, read-only, same inputs and `--max`): the `wave`/`blocked` lines and exit codes are unchanged; then, for each PLACED item not in wave 1 (wave order, then input order), `explain <item> (wave <k>):` and one indented line per distinct reason it stayed out of an earlier wave — `conflicts with <item> on <path> (declared)` / `(companion: <when>)` (the contained path of the intersecting pair; companion when either side's entry came from a rule), `depends on <item>`, `runs alone: Touches unknown (missing)` / `(unparsable line <N>: "<text>")` / `(declared unknown)`, `runs alone: Depends on missing ⇒ depends on every earlier item`, `wave <w> full (--max <N>)`, `wave <w> runs <item> alone (Touches unknown)`; a blocked item's reason is its `blocked` line. **`plan-waves --lint`** (parallel-automate/10, read-only; `plan-waves <item\|dir\|runfile\|item-list> --lint [--root <checkout>]`, `--max` not needed): a directory ⇒ the `resolve-folder` set (what the folder intake would enqueue), a run file ⇒ its unchecked Queue rows, any other `*.md` ⇒ that one item, any other file ⇒ an item list; prints ONE line per item `<item>: Touches <v>; Depends on <v>` with `<v>` = `ok`, `ok (declared unknown)` (a sole `unknown` Touches — legal), `missing section`, or `line <N>: "<text>" — <reason>` (N = 1-based line in the item file; ` (+<k> more)` when more lines are bad; reasons: `"- " bullet`, `backticks`, `parenthetical/prose`, `comma list`, `leading/trailing whitespace`, `leading /`, `. or .. segment`, `//`, `character outside [A-Za-z0-9._/@+-]`, `unknown mixed with paths`, `empty section`, `duplicated section`, `fenced block inside the section`; for `Depends on` also `none mixed with ids`, `none repeated`, `not an id or *.md path`), then `<k> of <n> items will run alone: <items\|none>` (Touches not known, declared included) and `<m> of <n> items depend on every earlier item: <items\|none>`. **Exit 1** when either section of any item is missing or unparsable (a bad `Touches` runs it alone, a bad `Depends on` serialises it), else 0; exit 1 with nothing on stdout on usage / `item not found`. Lint and explain take their verdict from the SAME awk pass the planner reads (one grammar), so lint `ok` ⇔ the planner reads the section as known. Grammar only — `--lint` does not resolve dependency ids (an unresolvable one still fails the planner run itself). |

`scripts/read-token-ledger.sh --session <id> | --run-id <run_id> [--root <checkout>]` and `scripts/run-lock.sh acquire|release|status --owner <label> [--session-id <id>] [--root <checkout>] [--force-unlock]` are **standalone scripts, not `automate-helpers.sh` subcommands** (they are shared with `/autonomous` and `/supervisor`, so they live at the top level of `scripts/` rather than inside this engine's own helper). `read-token-ledger.sh` is the fail-SAFE reader `ceiling-check` shells out to (row above) — `--session <id>` and `--run-id <id>` both print `INPUT=<n> OUTPUT=<n> CACHE_READ=<n> CACHE_CREATE=<n> TOTAL=<n> EVENTS=<n>` (plus `LEDGER_UNREADABLE=1` when nothing could be read); see the script's own header for the proxy-line honest limit. `run-lock.sh` is the single-run-per-repo lock (§11) acquired at PICK below, released at item completion/park. `scripts/automate-merge-watch.sh <runfile> <item> <pr_url>` is this engine's detached merge watcher (§6 "Post-merge close-out") — a standalone script too, because it runs OUTSIDE any Claude session and calls `automate-helpers.sh closeout` itself.

> `automate-helpers.sh` is READ-ONLY toward the work it drives (no source-repo edits, no git mutations; the sole exception is `gate-eval`'s explicit `gh pr merge --squash` — and `brief-repair`, whose only write is the brief lifecycle move performed by `reconcile-jobs.sh --repair` under `.supervisor/jobs/`, never a source-repo or git mutation). **The one carve-out:** `trail-pr`/`closeout`/`closeout-others`/`finalize-empty`/`trail-unstage`/`trail-gate` (and the read-only `sidecar-check` beside them) are delegated to the sibling `automate-trail.sh`, which IS a git/`gh pr create` mutator — bounded to this run's `chore/<run_id>-trail-<n>` branch, this PR's local branch/worktree, and, in the primary checkout, index-only entries for this run's own trail paths plus `closeout`'s (and `trail-gate`'s PICK-time) `git checkout <base>` + `git pull --ff-only` sync (never a commit, reset or stash there); never a force push, never `gh pr merge`. It is an **uncounted plain script** (not an agent/command/skill/hook). **The second carve-out:** `dismissed-drafts`/`dismissed-decide`/`dismissed-pending` are delegated to the sibling `automate-dismissed.sh`, a writer of this run's `proposed/` draft files only (every write through `propose-common.sh`'s `pc_guarded_write`, plus deleting its own draft on a `drop`/`fix-now` decision), its gitignored `<run_id>.dismissed-decisions` ledger and its own `## Progress` lines — never git (only `git rev-parse --show-toplevel`), never `gh`, never a merge. Also an uncounted plain script.

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
- parallel: <N|absent>            # parallel-automate/05 — ONLY present on a --parallel N>1 parent run (§14); absent on every sequential run and inside every lane
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
queued (- [ ]) → running → rate_limit (parks, no PR yet) | pr-open → awaiting_merge → merged (- [x]) | ready_for_release (a lane's READY park, §14) | escalated (parks) | failed | skipped
```

### `## Status` semantics

- **`running`** — the loop is actively processing (or is the freshly-created run).
- **`paused`** — stopped with work remaining; always paired with a `pause_reason` (`awaiting_merge` | `ready_for_release` — a lane's terminal READY park, inside a lane only, §14 | `awaiting_go` | `escalated` | `limit_reached` | `resume_ambiguous` | `rate_limit` | `drain_died` | `token_ceiling` | `run_lock_held` | `meta_unreachable` — branch mode's `meta-entry` failed on a `--resume` of an existing run, §13 | `trail_pr_open` — §6 step 1's trail gate | `closeout_leftover` — a close-out could not safely finish a step (a kept worktree/branch, a refused sync, an unknown result line) and the owner chose Stop or the run is non-interactive — §6 step 1 "Close-out leftover gate"; a RUN-level park written with `current-set`'s run-level form | `live_lane` — §6 step 1's lane guard (`pick-guard`) found a live lane of an open `--parallel` wave in this checkout, §14; a RUN-level park written with `current-set`'s run-level form).
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
| §6 step 2 RUN produced a PR (BEFORE its `ran /autonomous → PR` line) | `current-set <rf> --item <path> --status running --pr <url> --branch <b>` |
| §6 step 3 DRAIN start | none — item `status` stays `running`; `owned_drain_started` stays its own line |
| Rate-limit park (§6) | `current-set <rf> --item <path> --status rate_limit --pause-reason rate_limit` |
| `drain_died` park (§4) | `current-set <rf> --item <path> --status drain_died --pause-reason drain_died` |
| Lane READY park (§14 — inside a lane only, replaces the `awaiting_merge` park) | `current-set <rf> --item <path> --status ready_for_release --pause-reason ready_for_release` |
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

### Rate-limit park (end of RUN, before DRAIN)

See [per-item-loop.md](per-item-loop.md).

### Termination (two exits)

See [per-item-loop.md](per-item-loop.md).

### Learning-emit at end-of-DRAIN (engine-native ground-truth signal)

See [per-item-loop.md](per-item-loop.md).

### Brief-repair at RECONCILE and SYNC (merge-evidenced lifecycle repair)

See [per-item-loop.md](per-item-loop.md).

### Dismissed-findings decision step (before the park)

See [per-item-loop.md](per-item-loop.md).

### Trail PR after merge and at run end

See [per-item-loop.md](per-item-loop.md).

### Post-merge close-out (`closeout` + the merge watcher)

See [per-item-loop.md](per-item-loop.md).

## §7 — Single drain (no double-dispatch) + the config-toggle contract

See [per-item-loop.md](per-item-loop.md).

### Suppress window (wrap the RUN phase)

See [per-item-loop.md](per-item-loop.md).

### Config-toggle contract (byte-for-byte; absent-delete; malformed-abort)

See [per-item-loop.md](per-item-loop.md).

### Own ONE inline drain

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
/automate ... --auto-merge                   # opt-in trusted-merge at the gate (gated; default OFF)
/automate ... --trust-unprotected            # allow auto-merge onto a branch without enforceable protection (§10 cond. 4 ONLY — never overrides cond. 6, the high-risk park; nothing does)
/automate ... --notify                       # passthrough to inner /autonomous (gate webhooks)
/automate ... --non-interactive-fallback     # passthrough to inner /autonomous + engine gates fail closed
/automate ... --cheap                        # passthrough to inner /autonomous (Sonnet cost profile → /supervisor; not persisted — re-pass on --resume)
/automate ... --max-tokens N                 # opt-in spend ceiling (red-team-hardening/06) — PARKS before PICK on breach; PERSISTED in ## Run Config (unlike --cheap/--notify)
/automate ... --parallel N                   # opt-in lanes (§14): up to N independent items at once, each in its own local clone; absent or N = 1 ⇒ no lane code path; refused with --auto-merge
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
