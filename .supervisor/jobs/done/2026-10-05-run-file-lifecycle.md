# Supervisor Job: Run-file lifecycle — `## Current` set by a helper, finished runs finalize themselves, close-out leftovers are never silently skipped

## Environment
- **Project:** repo root of this checkout (lane s3-a)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main @ 3217da0 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2
- **Source requirement:** .supervisor/requirements/automate-followups/32-run-file-lifecycle.md
- **Base commit:** 3217da0a7fa49a315d60625321be2ae6b20637b9

> **Warning 1:** this repo is in **branch mode** (`setup-memory.sh mode` ⇒ `on loomwright-meta-s3w1`): `trail-pr`
> meta-pushes run history. Every test and every "running system" check that can reach `trail-pr` MUST run in a scratch
> clone whose `origin` is a local bare repo (or with `gh`/`git push` stubbed) — NEVER against this checkout's live
> `.supervisor/automate/` (a finalize or closeout there would push to the real metadata branch and mutate real runs).
>
> **Warning 2:** sibling lanes (other clones) may run `ci-local.sh` concurrently on this machine. Never `cd` outside
> this checkout; never bare `git stash`.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + jq + awk, the existing `automate-helpers.sh` / `automate-trail.sh` / `session-resume.sh` idiom; co-located static `test-*.sh` with PATH stubs for `gh`. |
| 2 | Dependency Availability | GO | `jq`, `gh` (stubbed in tests via `LOOMWRIGHT_GH_BIN`), `git`, `ps`, `run-lock.sh`, `worktree-salvage.sh` all present. |
| 3 | Architecture Fit | GO | Every new mutation goes through the existing validated install path (`_runfile_install`), every new step is a helper subcommand (tested code = executed code, SKILL §1.5), SKILL prose is the spec. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~10 files, three coherent parts on the SAME files, est. > 800 changed lines (helpers + three test suites + SKILL + RESULT_SCHEMAS). Split into 3 serialized subtasks (context-bound; file-conflict forces serial order anyway). |
| 5 | Hard Blockers | CAUTION | Part B scope 2 names "item 05's coordinator" (`parallel-automate/05`, lane fleet closeout) — no such coordinator exists on `main` (no lane/fleet script under `loomwright/scripts/`). Resolved: ship the callable (`finalize-empty`) the coordinator will call; wiring it into a coordinator is out of scope and listed under "Not done" in the PR body (D7). |

**Overall Verdict:** GO (2 CAUTION carried into Risk Assessment)

## Task
**Goal:** Make the `/automate` run file's state machine self-consistent: (C) `## Current` moves only through a helper and a stale/unset one is caught and repaired; (B) a paused run whose Queue is fully done and whose `## Current` is closed out is finalized by the engine itself instead of lingering as "incomplete"; (A) before any PICK, every item any run left merged is closed out, and anything close-out could not safely finish is put to the owner (interactive) or parks the run (non-interactive) — never silently skipped. One branch, one PR.

**Problem Statement:** (verbatim detail in the source requirement's Parts A/B/C)
- A: `closeout` refusals (kept worktree/branch, skipped sync) are only `## Progress` lines and PICK proceeds; close-out is per-run, so a merged item of ANOTHER paused run is never closed out; SessionStart surfaces neither merged-not-closed-out items nor live merge watchers.
- B: `closeout` never writes `done` (invariant), so every finished single-item lane run stays `paused / awaiting_go` with an empty Queue and every later RESUME lists it (seen 2026-10-04 and again at this run's own start: 7 such runs listed).
- C: setting `## Current` at PICK is prose only; lane w1-10 never updated it (one `runfile-write` at creation, everything else `progress-append`), so RESUME would read "nothing in flight" while a PR was open mid-drain.

## Design decisions (binding on the worker)
- **D1 — `current-set` (Part C, subtask 1).** New `automate-helpers.sh current-set <runfile> [--item <path|null> --status <s|null>] [--pr <url|null>] [--branch <b|null>] [--pause-reason <r>]`. Two legal forms: (a) ITEM form — `--item` and `--status` both given (either may be the literal `null` only when BOTH are `null`, i.e. "nothing in flight"); (b) RUN-LEVEL form — neither given, `--pause-reason` required, for run-level parks (`run_lock_held`, `token_ceiling`, `trail_pr_open`, `closeout_leftover`, `limit_reached`, `resume_ambiguous`, `meta_unreachable`) that must not touch the item line. Rewrites ONLY the `## Current` block's `- item: … | status: … | pr: … | branch: …` line (form a) and/or its `- pause_reason:` line (when `--pause-reason` given); every other line of the file — and every other `## Current` line (`owned_drain_*`, `pending_decisions`, `reason_hint`, …) — byte-unchanged. **pr/branch retention:** when `--item` equals the line's current item, an omitted `--pr`/`--branch` keeps the existing value; when `--item` CHANGES, omitted `--pr`/`--branch` reset to `null` (never carry the previous item's PR into a new item — gate-eval and closeout key on it). The item value is stored exactly as passed (no `./` normalization). Values are validated against the documented enums (item-level `status`: `running|awaiting_merge|escalated|failed|rate_limit|drain_died|done`, plus `null` only in the both-null form; `pause_reason`: the §3 vocabulary + `null` + D6's new `closeout_leftover`) — an unknown value, a half-null item form, an item form missing one of `--item`/`--status`, a run-level form missing `--pause-reason`, a value containing `|` or a newline, a non-run file, or a file with no `## Current` heading ⇒ exit 1, file byte-unchanged. A file whose `## Current` lacks a `- pause_reason:` line gets one appended to the block when `--pause-reason` is given. The write goes through the same `_runfile_install … full` validation `runfile-write` uses (pass values via the environment, never `awk -v` — SKILL Anti-Patterns). Idempotent: setting the values already present rewrites nothing (byte-identical file).
- **D2 — `progress-append` guard (Part C).** After a SUCCESSFUL append, if the appended line matches `^([^ ]+ )?(picked |ran /autonomous|owned drain started)` (one optional leading timestamp/tag token — real engine lines are `<ts> picked <item>`) AND the file's `## Current` item value is `null`, empty or the line is absent, print `current_not_set: <line>` to stderr and exit **3** (distinct from the refusal exit 1). The line IS appended (loud, not lossy). **`parked ` is deliberately NOT in the prefix set** (run-level PICK parks on a fresh run legitimately have a null item — Plan Review attempt 1); item-level parks are covered because they follow a `picked`/`ran /autonomous` line that already fired. Additionally (closes the first-item-only gap): a `picked <X>` line while `## Current` names a DIFFERENT non-null item whose status is not `done` ALSO exits 3 with `current_not_set` (PICK skipped `current-set` on a later item). Existing fixtures (`test-automate-helpers.sh` group B appends `t1 ran /autonomous` with `item: a.md`; `test-automate-trail.sh` fixtures append `t0 picked` directly to a heredoc with a set Current) must stay green unedited. Grep every in-repo `progress-append` caller (`automate-trail.sh`, `automate-dismissed.sh`, `automate-merge-watch.sh`, `automate-helpers.sh` itself, others) and confirm none emits a matching prefix with a null Current; list them in the PR body. SKILL wording for every run-level park Progress line must not start with a guarded prefix.
- **D3 — `current-rebuild` (Part C RECONCILE repair).** New `automate-helpers.sh current-rebuild <runfile>`: when `## Current` item is null/absent AND `## Progress` has a `picked ` line. **Item:** from the LAST Progress line matching `^- ([^ ]+ )?picked ` — the item is the first whitespace-delimited token after `picked ` with a trailing `;` or `,` stripped (real lines carry suffixes such as `picked <path>; suppressed auto_review…` and `picked <path> (owner …)`); it must be a Queue row (`- [ ] <item>` or `- [x] <item>…`), else no rebuild (`skipped — picked item not in Queue`). **PR:** ONLY from a `ran /autonomous` line AFTER that last `picked` line (the first `https?://…/pull/<n>` token on that line) — NEVER from any other Progress line (closeout step lines, `cross-run closeout …` lines (D7), trail lines and reconcile-status lines carry OTHER PRs' URLs; Plan Review attempt 1 HIGH). **Branch:** when a pr is found, one `gh pr view <pr> --json headRefName,state,mergedAt`. **Status:** no pr ⇒ `running`; pr found ⇒ `running` in EVERY case (OPEN, MERGED, CLOSED or unreadable) with the pr and branch recorded — a rebuild never claims `awaiting_merge`/READY/`escalated`, and never itself triggers a close-out; the owner (or the next RECONCILE reading `## Current`) decides, and the `current_rebuilt` line states the PR's observed state (`state=<OPEN|MERGED|CLOSED|unknown>`) so a human sees it. Writes via `current-set`, then `progress-append "current_rebuilt: <item> pr <url|null> state <s>"` and prints the same line. Current already set ⇒ `current-rebuild: skipped — ## Current set` and nothing written. Always exit 0 except a refused write (exit 1). SKILL §4: after a `current_rebuilt` line the RESUME stops at the continue/new/archive ask with the rebuilt Current shown (interactive) or parks `resume_ambiguous`-style (non-interactive: one Progress line, no auto close-out).
- **D4 — wire `current-set` into the prose + closeout (Part C scope 2).** SKILL §6 PICK (`current-set --item <path> --status running --pr null --branch null --pause-reason null`), RUN-done (`--pr <url> --branch <b>`), DRAIN-start (status unchanged — `owned_drain_started` stays its own line), every item park (rate-limit, drain_died, awaiting_merge, escalated) and every run-level park (run-level form) name the exact `current-set` call; §4 RECONCILE calls `current-rebuild` before the reconcile-item step. `automate-trail.sh`'s closeout `## Current` reconcile step (`_co_current`) keeps its guards and output lines byte-identical but performs its write through `automate-helpers.sh current-set`, with these constraints from the existing `test-automate-trail.sh` mutation controls (Plan Review attempt 1): pass the RAW stored item field of the CURRENT line (`--item "<raw cur item>"`, not the closed-out item and not the `./`-stripped comparison value — the guard mutant replacing the item/PR guard with `if false; then` expects the LATER item to stay named); pass `--status done --pause-reason "$want"`; keep byte-identical the item/PR guard line, the `cu="$(_co_current …)"` call line and the `if [ "$run_status" = "paused" ]; then want=…` line (sed-targeted by mutants). The closeout groups of `test-automate-trail.sh` must pass with no existing assertion edited.
- **D5 — `finalize-empty` + `resume-glob --finalize` (Part B, subtask 2).** New `finalize-empty <runfile>` implemented in **`automate-trail.sh`** (it takes the run lock, rewrites `## Status` and calls `trail-pr`, a git/PR mutator — `automate-helpers.sh` stays read-only toward git per its header carve-out), dispatched from `automate-helpers.sh` exactly the way `closeout` is. Fires ONLY when ALL hold — `## Status: paused`, `pause_reason: awaiting_go`, `remaining` = 0, and the `## Current` item line's status is `done`. Then, in this order: `run-lock.sh acquire --owner automate-finalize:<run_id>` (held ⇒ `finalize-empty: skipped — run lock held by <owner>`, nothing written); write `## Status: done` and `pause_reason: null` (one validated rewrite through `runfile-write`/`current-set`); `progress-append "auto-finalized: queue empty after closeout"`; then `trail-pr <runfile> --reason done` — the SAME call the Queue-resolved `## Status: done` termination makes (§6 Termination); `progress-append` the trail line; **then, in branch mode OFF only, `trail-unstage <runfile>` for that run** (a foreign run's staged trail blobs must not survive into the current run's index — they would ride into the next item's commit and make `_sync_primary` see uncommitted changes; Plan Review attempt 1 HIGH); release the lock in a trap. Prints `finalize-empty: finalized <runfile>` (+ the trail and unstage lines) or ONE `finalize-empty: skipped — <reason>` line; always exit 0 (fail-SAFE emitter). Idempotent: a second call is `skipped — not paused`. `resume-glob <dir> --finalize` runs `finalize-empty` on each candidate and lists only the ones NOT finalized (plain `resume-glob <dir>` output byte-unchanged). `closeout` STILL never writes `done` — add an invariant leg that a closeout which checks off the last item leaves `## Status: paused`. SKILL §4 step 1 (and the `commands/automate.md` overview) call `resume-glob --finalize`. **Mode-off trail PRs:** with branch mode off, finalizing N runs opens/pushes up to N `chore/<run_id>-trail-<n>` PRs (one per run, each idempotent, never merged by the engine) — ACCEPTED and documented in SKILL §4 and the Risk table; the PICK-time `trail-gate` covers only the current run's own trail PR, so these do not park the current run.
- **D6 — close-out completion gate (Part A(a), subtask 3).** New pure-logic `automate-helpers.sh closeout-classify [--run <run_id> --item <path> --pr <url>]` reading ONE closeout invocation's output on stdin (run it once per closeout call — never on interleaved output of several). Classifies ONLY lines starting `closeout: ` (pass-through `brief-repair:` / `trail-pr:` lines are ignored — they have their own surfacing). Build an explicit table in the code from EVERY `closeout: …` string `automate-trail.sh` can print (enumerate them by reading the source; test each string). **Precedence: a line containing `kept` anywhere is a leftover whatever its verb** (`closeout: removed — worktree A; kept B` is real output of the worktree step). **complete** = `removed|synced|stamped|checked|reconciled` lines with no `kept`, and idempotent `skipped — already …` / `skipped — ## Current already done` / `skipped — ## Current is <other> …` (a watcher fired after a later pick). **leftover** = any `kept`, any refusal, sync `skipped` because the primary is dirty / on another branch / pull refused, stamp `skipped — no done brief`, `skipped — run lock held …`, `skipped — gh unavailable`, `skipped — pr not merged …` (the caller only runs closeout after reconcile-item said `merged`, so a not-merged answer here means gh disagreed or was unreadable — fail toward asking), and **any line not in the table**. Output: `complete` (one line) or one `leftover\t<run_id>\t<item>\t<pr>\t<step>\t<detail>` row per leftover (the `--run/--item/--pr` values, so "Clean up now" has a target); exit 0. **New `pause_reason: closeout_leftover`** (add to §3, RESULT_SCHEMAS `## Current` enum + its prose row, `current-set`'s enum; run-level park, written with current-set's run-level form). SKILL §6 step 1: after RECONCILE's `closeout` (and each of D7's cross-run close-outs), classify that invocation; `complete` ⇒ the engine appends `closeout: nothing to close out` ONLY when no step of that closeout changed anything AND that exact line is not already the last `closeout: nothing to close out` occurrence in this run's Progress since the last `picked` line (dedupe by an exact-line grep scoped per item; at most one per item per run); leftovers ⇒ interactive: ONE `AskUserQuestion` call batching ≤4 leftovers (options **Clean up now** / **Keep and continue** / **Stop**); "Clean up now" = re-run `closeout <that run's file> <item> <pr>` (idempotent; it re-applies its own safety checks — tip == merged head, `worktree-salvage.sh` before any remove, no `--force`, no reset, no `-D` on a foreign tip) then re-classify ONCE; a leftover that survives is reported and asked Keep/Stop only (no loop). "Keep" ⇒ `progress-append "closeout leftover kept: <run_id> <step> <detail>"`; "Stop" ⇒ park `closeout_leftover`. Non-interactive ⇒ park `closeout_leftover` (`## Status: paused`, current-set run-level form, one Progress line per leftover, run-lock released) — never proceed silently.
- **D7 — cross-run close-out (Part A(b)).** New `closeout-others <automate_dir> [--record <runfile>]` in `automate-trail.sh` beside `closeout`, dispatched from `automate-helpers.sh` like `closeout`: for every `resume-glob` run file other than `--record`'s, read its `## Current` item + pr; act ONLY when pr is non-null, the item-line status is not `done`, and `reconcile-item` says `merged` ⇒ run `closeout <that runfile> <item> <pr>` (no `--session-id` — its own `automate-closeout:<run_id>` lock, its own trail); **then, in branch mode OFF only, `trail-unstage <that runfile>`** (same foreign-staged-blob hazard as D5); print `closeout-others: <run_id> <item> <pr>` followed by that closeout's lines (and the unstage line); with `--record`, `progress-append` ONE `cross-run closeout <run_id> <item>: <complete | first leftover>` line into the recording run per close-out performed — **the recorded line carries NO PR URL** (so D3 can never mistake another run's PR for this run's). Open / closed-unmerged / gone / unreadable ⇒ untouched, no line. Never touches another run's Queue beyond its in-flight item's check-off (which `closeout` does). Always exit 0. Each close-out's lines are classified by D6 individually (the engine splits on the `closeout-others:` header lines, or calls `closeout-classify` per run). SKILL §4: start/resume order is `meta-entry` → `closeout-others` → `resume-glob --finalize` → list/ask; for a new run the `--record` lines are appended right after the run file is created (the helper prints them; record once the file exists). **Concurrency:** `run-lock.sh` is per checkout (`<root>/.supervisor/run.lock`); two lanes (separate clones) can close out / finalize the SAME run file content in their own clones — in branch mode both meta-push the same paths; `meta-sync.sh push` is the arbiter (line-union / conflict ⇒ loud `meta-push FAILED`). Accepted and recorded as a Risk row; the worker confirms meta-sync's behaviour on a concurrent identical push from its source/tests and lists it under "Not verified" if not exercised.
- **D8 — SessionStart surfacing (Part A(c)).** `session-resume.sh` adds, read-only and fail-SAFE (always exit 0): (1) one line per run file whose `## Current` has a pr, item-line status not `done`, and whose PR reads MERGED: `automate: <run_id> item <item> PR <url> merged but not closed out — /automate --resume closes it out`; (2) one line per LIVE merge watcher (`<run_id>.merge-watch` marker whose pid is alive AND `ps -ww -p <pid> -o command=` shows `automate-merge-watch.sh` with the marker's pr_url — the same liveness test the watcher uses): `automate: merge watcher live pid=<p> PR <url> (run <run_id>)`. Bounded: at most 5 `gh pr view` calls per SessionStart; `gh` absent or a call failing ⇒ that item prints `… merge state unverified` instead (never a guess). Nothing to report ⇒ nothing printed (no header, no "none"). Stale markers are ignored, never cleaned. Use `LOOMWRIGHT_GH_BIN`-style stubbing consistent with the file's existing test seams.
- **D9 — docs.** SKILL `skills/automate-loop/SKILL.md`: §1.5 table rows for `current-set`, `current-rebuild`, `finalize-empty` (+ `resume-glob --finalize`), `closeout-classify`, `closeout-others`; §3 template/status semantics (`closeout_leftover`; finalize path to `done`); §4 order (D7) and repair (D3); §6 step 1/2/3/4 `current-set` calls (D4) and the leftover gate (D6); §8 note that cross-run close-out runs before PICK. `docs/RESULT_SCHEMAS.md` §AUTOMATE_RUN enum + prose row. `commands/automate.md` overview step 1 (surface only — no contract restated). `changelog.d/automate-followups-32-run-file-lifecycle.md` with `<!-- bump: minor -->` (new subcommands). No version file hand-edited. Use descriptive anchors or `[pins: …]`, never a bare `file:N` (test-citation-drift). If another doc enumerates `session-resume.sh` output lines or `automate-helpers.sh` subcommands (grep `docs/`, `skills/`, `README.md`), update it in the same change and name it in the PR body (it may be outside `## Touches`).

## Acceptance Criteria
**Part C (subtask 1)**
- [ ] Given a run file, when `current-set` runs with valid args, then only the `## Current` item/pause_reason lines change (byte-diff fixture with `owned_drain_*`/`pending_decisions` lines present), and an invalid status / pause_reason / half-null item form / item form missing `--item` or `--status` / run-level form missing `--pause-reason` / `|`-bearing value / non-run file exits 1 with the file byte-unchanged; re-setting identical values is byte-identical; changing `--item` without `--pr`/`--branch` resets both to `null`, same item keeps them; the run-level form (`--pause-reason closeout_leftover` only) leaves the item line byte-unchanged.
- [ ] Given `## Current: item: null`, when `progress-append` appends `<ts> picked <item>` (and each of `ran /autonomous`, `owned drain started`, `parked `), then it exits 3 with `current_not_set` on stderr AND the line is in `## Progress`; with Current set it exits 0; a `<ts> parked …` / run-level park line with a null item exits 0 (not guarded); `picked B` while Current names a different non-done item A exits 3. Replaying w1-10's run-file history (fixture shaped like `automate-2026-10-04-103627.md`: creation write, then Progress-only updates) refuses at the first `picked` line.
- [ ] Given a w1-10-shaped run (Current null, Progress has `picked` + `ran /autonomous → PR <url>`), when `current-rebuild` runs with a stubbed `gh` (OPEN / MERGED / CLOSED / failing), then `## Current` is rebuilt as `status: running` with the pr + branch recorded and a `current_rebuilt … state <s>` Progress line; a second run prints `skipped — ## Current set` and writes nothing. Negative legs: a later Progress line carrying a FOREIGN PR URL (a closeout step line, a trail line, a `cross-run closeout` line) and no `ran /autonomous` line ⇒ pr stays `null`; a `picked <path>; suppressed auto_review…` / `picked <path> (owner …)` suffix parses to `<path>`; a picked item not in the Queue ⇒ skipped, nothing written.
- [ ] `closeout`'s `## Current` reconcile writes through `current-set`; `test-automate-trail.sh` closeout groups pass with no existing assertion edited.
**Part B (subtask 2)**
- [ ] Given a paused / awaiting_go / remaining-0 / Current-done run, when `resume-glob --finalize` runs (scratch clone, stubbed push; legs in BOTH branch mode on and off), then it is finalized (`## Status: done`, `auto-finalized: queue empty after closeout` line, a `trail-pr --reason done` call identical to the Queue-resolved termination's) and NOT listed; one unchecked item ⇒ listed, untouched; another pause reason ⇒ listed, untouched; a held run lock ⇒ skipped and listed; plain `resume-glob` output unchanged; a second finalize is a no-op. Mode-off leg: after finalizing a foreign run the primary index carries NO staged path of that run (`git diff --cached --name-only` empty for its trail paths), and a following `closeout` of the current run's item classifies `complete`.
- [ ] Invariant leg: a `closeout` that checks off the last Queue item leaves `## Status: paused` (`awaiting_go`); a mutant that makes closeout write `done` turns that leg red (mutation recorded verbatim in the PR body).
- [ ] Running system: against a COPY of today's run files in a scratch clone (origin = local bare repo), `resume-glob --finalize` finalizes every paused/awaiting_go/remaining-0/Current-done run (8 at authoring time: 2026-10-04-072706, -072926, -103627, -103628, -145742, 2026-10-05-002721, -002749, -055807) and lists only `automate-2026-09-30-054439` (plus this lane's own run if copied) — paste the finalized lines and the shortened list.
**Part A (subtask 3)**
- [ ] Given a close-out that kept a worktree (tip ≠ merged head) and a branch — including the mixed `removed — worktree A; kept B` line — when classified, then it yields one leftover row per kept step carrying run_id/item/pr; `skipped — pr not merged …` and any unknown `closeout:` line are leftovers; SKILL text names the interactive ask (Clean up now / Keep / Stop) and the non-interactive `closeout_leftover` park (fixture test + SKILL-text leg).
- [ ] Given an already fully closed-out item (closeout re-run, all idempotent skips), then `closeout-classify` says `complete`, nothing is asked, nothing mutated, and at most one `closeout: nothing to close out` line exists for that item after two passes (fixture test).
- [ ] Given run A paused `awaiting_merge` on a now-merged PR (stubbed `gh`) and run B starting, when `closeout-others … --record B` runs, then A's item is closed out (stamp, check-off, cleanup, trail call) and both A's Progress (closeout lines) and B's Progress (`cross-run closeout` line, carrying no PR URL) record it; A's OPEN / CLOSED-unmerged / unreadable variants are byte-untouched; mode-off leg: no A trail path left staged in the primary index afterwards (fixture tests).
- [ ] "Clean up now" negative legs: never removes a worktree or deletes a branch whose tip ≠ the merged head, never removes a worktree before `worktree-salvage.sh`, never force-pushes, resets or stashes (assert on stub logs / git state).
- [ ] `session-resume.sh` prints the merged-not-closed-out line and the live-watcher line in fixtures, prints `… merge state unverified` with `gh` absent/failing, prints nothing extra with nothing to report, caps `gh` calls at 5, and exits 0 in every leg.
**Whole change**
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to exactly the five sanctioned surfaces (unchanged); `gate-eval` is not modified.
- [ ] `bash scripts/ci-local.sh` is green on the branch (includes `check-doc-currency.sh`, `test-citation-drift.sh`); the three touched test suites also pass under `/bin/bash` (3.2); PR body pastes `<passed>/<total>` and SKIP counts for base and branch per touched suite, labelled by part.
- [ ] `changelog.d/automate-followups-32-run-file-lifecycle.md` exists with `<!-- bump: minor -->`; no version file hand-edited.
- [ ] PR body has a "Not verified" section listing anything not run (incl. Part B scope 2 coordinator wiring, Feasibility CAUTION 5; meta-sync behaviour on two lanes finalizing the same run concurrently, if not exercised; any doc that enumerates `session-resume.sh` lines or helper subcommands that was found and updated outside `## Touches`) and the Part C "real sequential `/automate` item" check, which this very run provides (the owner can read this run's `## Current` at PICK / after RUN / at park).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Part C — `current-set`, `progress-append` guard, `current-rebuild`, closeout writes via `current-set`, SKILL/RESULT_SCHEMAS prose | Part C + changelog fragment | 5 modify, 1 create | `unit-testing`, `quality-checklist` | LAUNCHABLE |
| 2 | Part B — `finalize-empty` (in automate-trail.sh) + `resume-glob --finalize`, mode-off unstage, closeout-never-done invariant leg, SKILL/command prose | Part B | 6 modify | `unit-testing`, `quality-checklist` | BLOCKED (1) |
| 3 | Part A — `closeout-classify`, `closeout_leftover`, `closeout-others`, `session-resume.sh` surfacing, SKILL §4/§6/§8 + RESULT_SCHEMAS + command, whole-change gates | Part A + Whole change | 8 modify | `unit-testing`, `quality-checklist`, `error-handling` | BLOCKED (2) |

### Subtask Contracts

```yaml
# Subtask 1 — Part C: ## Current moves only through a helper (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "current_set"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "current_rebuild"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "current_not_set"}
  - {kind: "file", path: "changelog.d/automate-followups-32-run-file-lifecycle.md"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "closeout_leftover"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "changelog.d/automate-followups-32-run-file-lifecycle.md"
external_requires: []

# Subtask 2 — Part B: finished runs finalize themselves (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "finalize_empty"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "auto-finalized"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "current_set"}
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "changelog.d/automate-followups-32-run-file-lifecycle.md"
external_requires: []

# Subtask 3 — Part A: close-out leftovers, cross-run close-out, SessionStart surfacing (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "closeout_classify"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "closeout_others"}
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "merge watcher live"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "closeout_leftover"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "current_set"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/automate-trail.sh", name: "finalize_empty"}
lanes:
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/test-automate-trail.sh"
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/commands/automate.md"
  - "changelog.d/automate-followups-32-run-file-lifecycle.md"
external_requires: []
```

**Exact-name mandate:** the bash function names `current_set`, `current_rebuild`, `finalize_empty`, `closeout_classify`, `closeout_others` and the dispatcher subcommands `current-set`, `current-rebuild`, `finalize-empty`, `closeout-classify`, `closeout-others` are literal; `current_not_set` is the literal stderr token; `closeout_leftover` the literal new `pause_reason`. Subtasks 2 and 3 each append to the SAME changelog fragment (one headline; extend the body).

## Parallelism Analysis

### Dependency Graph
1 → 2 → 3 (strict chain: 2 uses `current-set`; 3 uses `current-set` and must order after 2's `resume-glob --finalize` in the §4 start sequence).

### File Overlap Matrix
All three share `automate-helpers.sh`, `test-automate-helpers.sh`, `SKILL.md` and the changelog fragment — legal only because the chain orders them (reachable in the `requires` DAG).

### Batch Plan
Three batches, one worker each, strictly sequential. **Split reason recorded in `## Configuration`.**

## Skill References

| Skill | Why |
|---|---|
| `skills/unit-testing/SKILL.md` | Non-vacuous assertions, fixtures, mutation controls |
| `skills/quality-checklist/SKILL.md` | Pre/post-implementation gates |
| `skills/error-handling/SKILL.md` | Fail-SAFE vs fail-CLOSED placement (D2 exit 3, D5/D7/D8 always-exit-0) |
| `skills/automate-loop/SKILL.md` | The spec being amended — change the prose first, then make the helper conform (§1.5) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope > one worker's context (Feasibility CAUTION 4) | MEDIUM | Split context-bound into 3 serialized subtasks; each subtask ends with its own touched suites green |
| Part B scope 2 coordinator does not exist (Feasibility CAUTION 5) | MEDIUM | Ship `finalize-empty` as the callable; coordinator wiring listed under "Not done"/"Not verified" |
| Tests or a running-system check reach `trail-pr` in branch mode and push to the real metadata branch / mutate live runs | HIGH | Warning 1: scratch clone with a local bare `origin`, or stubbed `gh`/push; never the live `.supervisor/automate/` |
| Cross-run close-out mutates another run wrongly | HIGH | Only merged (`reconcile-item`) + non-done Current items; closeout's own evidence gate + its own lock owner; byte-untouched legs for open/closed/unreadable |
| A rebuilt `## Current` attaches a foreign PR and a close-out then stamps an unmerged item (Plan Review 1 HIGH) | HIGH | D3 reads the PR only from a `ran /autonomous` line after the last `picked`; rebuild always writes `running`, never triggers a close-out; D7 record lines carry no PR URL; foreign-URL negative leg |
| Branch mode OFF: finalize/cross-run closeout stage FOREIGN trail blobs in the primary index (Plan Review 1 HIGH) | HIGH | D5/D7 run `trail-unstage <that runfile>` after each foreign trail; mode-off fixture legs assert a clean index and a `complete` classification after |
| Mode off: finalizing N runs opens up to N trail PRs at once | MEDIUM | Accepted (one idempotent PR per run, never merged by the engine, does not trip the current run's `trail-gate`); documented in SKILL §4 |
| Two lanes (separate clones) finalize/close out the same run concurrently in branch mode | MEDIUM | `run-lock.sh` is per checkout; `meta-sync.sh push` arbitrates (line-union / loud conflict); worker confirms from meta-sync source/tests or lists under Not verified |
| False "leftover" on an idempotent re-run makes every resume ask | MEDIUM | Explicit classifier table built from every closeout string, each string tested; AC "already closed-out ⇒ complete, ≤1 line" |
| D2 guard breaks an existing caller (exit 3 under `set -e`) | MEDIUM | Grep every `progress-append` caller; fixtures unedited; guard keyed on Current null only |
| `current-set` regex rewrite corrupts other `## Current` lines | MEDIUM | Byte-diff fixture with `owned_drain_*`/`pending_decisions` lines present |
| SessionStart latency / network | LOW | Cap 5 `gh` calls; unverified fallback; no call when nothing in flight |
| Bare `file:N` citation fails `test-citation-drift.sh` | LOW | Descriptive anchors or `[pins: …]` |
| Prior lesson: PASS is not drain-clean; `contract_conformance_status: skipped` is unverified | LOW | Ground truth via `## Executable Acceptance` corpus tasks; full `ci-local.sh` |

## Configuration
- **Workers:** 1
- **Mode:** sequential (3 subtasks, chain)
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-05-run-file-lifecycle.md
```

## Plan Review
- **Decision:** PASS (attempt 2 of 3; attempt 1 FAIL on 2 HIGH — D3 foreign-PR rebuild and branch-mode-off foreign staged trail blobs — fixed in-brief)
- **Owner decision:** save with the notes below as BINDING worker instructions (no third review). Where a note and the text above disagree, the note wins.
  - MEDIUM 1 — Part C AC bullet 2: `parked ` is NOT guarded. Read its exit-3 list as "(and each of `ran /autonomous`, `owned drain started`)"; a `<ts> parked …` line with a null item exits 0 (D2 is authoritative).
  - MEDIUM 2 — D2 picked-mismatch arm: extract X exactly as D3 does (first whitespace-delimited token after `picked `, trailing `;`/`,` stripped) and compare with the `## Current` item after stripping a leading `./` on BOTH sides. Add an AC leg: `<ts> picked <path> (run-lock acquired; …)` with Current item `<path>` (and `./<path>`) exits 0.
  - MEDIUM 3 — D8 session-resume.sh: the `startup` arm stays OFFLINE ("no forge call, ever" is preserved) — on `startup` print only the local-only live-watcher line and, for run files with an in-flight PR whose status is not `done`, NO merge check. The merged-but-not-closed-out check (with `gh`) runs only on the `resume|clear|compact` arm, capped at 5 calls, each call time-bounded on bash 3.2 (background `gh` + bounded poll + kill, ~5 s each; a timeout ⇒ `merge state unverified`). This introduces a NEW gh stub seam in session-resume.sh (e.g. `LOOMWRIGHT_GH_BIN`) — say so in the header; do not claim it was reused. Update the file's header "at most N advisory blocks" claim if the count changes. Test: startup arm makes zero gh calls (stub records invocations), resume arm honors the cap and the timeout.
  - LOW 1 — Est. Files counts are approximate; the lanes lists are authoritative.
  - LOW 2 — move the `closeout_leftover` enum additions (SKILL §3 vocabulary, RESULT_SCHEMAS §AUTOMATE_RUN enum + prose row) into SUBTASK 1, together with current-set's enum; subtask 3 owns only the gate semantics.
  - LOW 3 — the w1-10 fixture takes only the creation-time write plus the Progress-only history of `automate-2026-10-04-103627.md`, with `## Current` explicitly `item: null | status: null | pr: null | branch: null` (the live file's Current has since been set by closeout).
  - ORCHESTRATOR (Phase 2) — also include `verify-helpers.sh` / `test-verify-queue.sh` in the D2 `progress-append` caller audit; if `verify-helpers.sh`'s comment claiming "byte-for-byte the same awk idiom as automate-helpers.sh's progress-append" becomes false, fix that comment and name it in the PR body as outside `## Touches`.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T17:56:09Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/395
- **Branch:** feature/automate-followups-32-run-file-lifecycle
- **Files changed:** 12
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Part C current-set/current-rebuild/progress-append guard, Part B finalize-empty + resume-glob --finalize, Part A closeout-classify/closeout-others/session-resume surfacing. Resumed by /automate --resume after the original session (14050ab7) died mid-EXECUTE; Phase 4.5 iteration 1 fixed 2 HIGH (trail-suite pass-counter clobber; current-rebuild stale-done backstop), iteration 2 PASS. risk_classification high_risk=true (size, commands/, skills/); ground_truth 2/2 pass; contract_conformance skipped (empty twin store = unverified).

## Not verified
- **real sequential /automate item ## Current at PICK/RUN/park** — fixtures only (subtask 1)
- **Part B running-system check against a copy of today's run files** — worker result absent, unconfirmed (subtask 2)
- **interactive /automate close-out leftover ask (Clean up now / Keep / Stop)** — SKILL prose only (subtask 3)
- **meta-sync push when two lanes finalize/close out the same run concurrently** — source-read only (subtask 3)
- **mode-off cross-run close-out sync with another run's locally modified run file** — not exercised (subtask 3)
