# Rationale — automate-loop

Stories, history, examples and explanations moved out of the runtime prompts of the `automate-loop` group: the `skills/automate-loop/` skill (its index `SKILL.md` and every split file) and the `commands/automate.md` command body. Nothing here is read at runtime and nothing here is a rule: every rule stayed in a runtime prompt, at the step that uses it, or is executed by a script (`scripts/automate-next-step.sh` and the helpers it calls). Each inventory row of kind `story` in `docs/loop-inventory/automate-loop.md` points at the heading below that holds its text.

## Index, invariants and command body

### Purpose and layering

The plugin can drive **one** requirement deep (`/autonomous`), but nothing walked **arbitrary** work from any starting point. `/automate` is the outermost loop, and the layering is strictly nested:

```
/autonomous (one requirement)  ⊂  per-item loop  ⊂  /automate (source → Queue → loop)
```

- **`/autonomous`** runs one requirement end-to-end to a PR (Launch Pad → Supervisor, with Phase 4.5 self-heal + Rubric Grader). Under `--inline-phases` the engine drives it `--single-iteration`; by default the driver runs its two phases itself, Launch Pad and then Supervisor, each as its own fresh headless session, and applies `/autonomous` PLAN's result handling (the skill's Coordinator loop).
- **The per-item loop** wraps a single `/autonomous` run with an owned until-mergeable drain, a trusted-merge-or-park gate, and a `main` re-sync (skill §6).
- **`/automate`** resolves a source into a `## Queue` once, materializes ONE run file, and drives each Queue item through the per-item loop.

The per-item engine is source-agnostic — only the intake differs, and intake is just "convert the source into the run file's Queue, once" (skill §2). Further sources (issues, Beads `bd ready`, Jira) would each just populate the Queue; none needs a framework. For a `--parallel N` wave the engine builds the wave branch (lane merges, local CI, the release bump) and opens the wave PR; the owner merges it.

### The command body's purpose section

`/automate` converts any source — a prompt (via `/product-owner`), a requirements folder, or a backlog/plan doc — into a full Queue with a per-run processing cap inside ONE markdown run file (`.supervisor/automate/<run_id>.md`, which is the contract, the dashboard and the resume state). It then drives each Queue item through the per-item loop: Launch Pad → Supervisor → an owned `/review-pr --until-mergeable` drain, each a fresh session (under `--inline-phases`: `/autonomous --single-iteration` + an inline drain) → trusted-merge-or-park → pull `main` → check the item off and append to `## Progress`. It is smart about resume: on start it globs `.supervisor/automate/*.md` for incomplete runs, reconciles them against ground truth (`gh`/`git`/`## Status: done`), and offers continue / start new / archive.

The command body states this once as a surface summary. Every contract it names — intake, the run-file model, RESUME, the per-item loop, the single drain and its config toggle, the single-open-PR invariant, the two modes and the fail-closed trusted auto-merge gate — is coined in the skill; the command body previously restated "defined ONCE in the skill" three times, and now says it once.

### Why Step 0 re-reads the bodies every run

Step 0 guards against prompt drift: if the loop protocol, `/autonomous` or `/review-pr` evolves between releases, `/automate` picks up the change because it re-reads them every run rather than executing remembered shapes.

### Why the command keeps a short overview

The command body's overview is a map of the steps `scripts/automate-next-step.sh` runs, not the contract. It stays in the command body (shortened to one line per step) because several tests assert that the command body itself mirrors the surface — that it names `trail-gate`, `closeout`, `closeout-classify`, `closeout-others`, `closeout --no-trail`, `trail-pr`, the "never at a park" trail rule, the qualified single-drain claim, and the derived wall-clock cost of a fix-now option. Each step it names is executed by the driver, and the skill's Coordinator loop forbids re-running one by hand.

### Why the flag list lives in the command only

The skill's §12 used to carry its own copy of the `/automate` flag list, line for line beside the command body's Usage block. Two copies of one list drift silently, so the skill now points at the command's Usage block (always read with the skill) and keeps the `/loop` driver rules, which the command does not state.

### Why the run file is driver-owned

The coordinator never writes the run file: `scripts/automate-next-step.sh` runs every step that changes it, through the helpers. The run-file section (§3: template, item lifecycle, `## Status` semantics, the crash-safety contract and the `## Current` transition table) is therefore read only when it is needed — a new run's intake writes the first run file from the template, a run-file helper or a driver call fails, or the owner asks for a check-off by hand — and not on every start.

### Why Current moves only through current-set

`## Current` is the resume state RESUME trusts first, so it is never left to prose. Lane w1-10 (run `automate-2026-10-04-103627`) wrote `## Current` once at creation and never again — every later event was a `progress-append` — so a RESUME mid-drain would have read "nothing in flight" while a PR was open. That incident is why every write of the item line and the `pause_reason` line is one `automate-helpers.sh current-set` call, and why `progress-append` refuses to record a `picked` / `ran /autonomous` / `owned drain started` line over an unset `## Current` (exit 3, `current_not_set`).

### Why runfile-write validates before rename

Temp + rename protects against a crash mid-write, but it installs whatever the temp file holds. The engine builds rewrites as `<generator> "$RF" | automate-helpers.sh runfile-write "$RF"`, and a generator that errors — BSD awk rejecting a newline in a `-v` value, an unescaped delimiter in a `sed`, a failed redirect — prints nothing while the helper cannot see its exit status. Validating the staged payload before the `mv` is what keeps such a failure from replacing the only copy of resume state with an empty or truncated file. A shrinking line count is deliberately not a refusal reason (unlike `/verify`'s `queue-write`), because `## Current` legitimately loses lines, e.g. `pending_decisions:` disappears when the next item is picked.

### Why a clean bot review is not a dismissed finding

A bot review that says "no new findings" carries no finding to decide on, so `dismissed-drafts` never drafts one from it (#617). The skill's Quality Gates line keeps the rule; the PR reference lives here.

## per-item-loop and resume

### Why the PICK-time trail gate syncs the primary

Before the trail gate existed nothing synced the primary checkout at PICK, and a hand `git pull` after the trail un-stage refused: run `automate-2026-10-01-142337` item 02 had to re-stage the trail blobs by hand with `git update-index --cacheinfo`. The gate now syncs with `closeout`'s own sync, which re-stages the recorded trail blobs that landed (`<run_id>.trail-staged`) before its `git pull --ff-only`, so the merged trail fast-forwards and the next item branches off a base that carries it; the un-stage then drops whatever did not land. A `sync skipped` answer never parks, because the sync is checkout housekeeping: RUN then proceeds from the primary as it is, which is what every PICK did before the gate.

### Brief-repair covers only engine-processed items

Only items the engine processed have engine-held merge evidence. A `/supervisor` or `/autonomous` run outside the engine still has no online repair: its stranded brief is classified offline by `session-resume.sh`'s `reconcile-jobs.sh` call (the reconciler makes no forge call; the hook's only forge read is the `/automate` in-flight check), and it stays a manual `reconcile-jobs.sh --repair` or a SessionStart classification. The `--evidence` key is compared exactly against the brief's `- **Source requirement:**` token, so a Queue item spelled `./…` or as an absolute path never matches Launch Pad's repo-root-relative pointer and lands on a `skipped` line.

### Why no park opens a trail PR

At a park the item's PR is unmerged. Before automate-followups/37, Phase 4.5's completion tail had already stamped the requirement `## Status: done` by then, and a park-time trail PR carried that stamp to `main` ahead of the feature PR. An owner who merged the trail PR and then closed or reworked the feature PR left `main` saying the item was done, and `is_done` keeps `resolve-folder` / `reconcile-status` from ever re-queueing it: two PRs per item, with an ordering trap. Phase 4.5 now writes nothing to the requirement, `closeout` is the only engine writer of the stamp, and a parked item's trail lands with its `closeout`, a skip/abandon check-off or the run end.

The cost is stated plainly: under `--auto-merge` a gate-merged item is closed out at SYNC by `closeout … --no-trail` (in both branch modes; the driver's `sync` step). Its requirement is stamped behind the same evidence gate and checked off, but its trail, stamp included, rides the next `closeout`, skip/abandon check-off or run end. A run that parks for good after auto-merged items leaves their trail uncommitted until one of those fires (`/automate --resume`, or a hand `trail-pr --reason done`).

### The trail checkout contract and its limits

A plain `git pull` refuses to overwrite untracked or modified local copies of the paths a merged trail PR brings in. So after a push (and on the no-diff skip against an open trail PR) `trail-pr` sets the primary index entry of every path the trail branch changes to that path's blob at the trail-branch tip and leaves the working copies alone: the owner's `git checkout main && git pull` fast-forwards, and the bytes that differ by design (Progress lines added after the push, other runs' ledger lines) stay as unstaged local modifications — no reset, no stash, no byte discarded. Those staged entries would ride along in any commit made from the primary index (`git checkout -b` carries them, and a plain `git commit` commits the whole index), which is why PICK drops them (`trail-unstage`) and `closeout`'s sync re-stages, just before its pull, each recorded blob that `origin/main` now carries.

The trail-after-merge re-examination (v15.114.2) checked every piece by fixture and removed none: `closeout`'s own trail still stages into the primary index, so the next PICK still needs `trail-unstage`; the owner's hand pull after merging that trail PR refuses without the staged tip blobs; and the next `closeout`'s sync refuses without the `.trail-staged` re-stage (`scripts/test-automate-trail.sh` leg D3, each with a control that turns red).

Limits: between a PICK and the next `trail-pr`, a hand-run `git pull` over a merged trail PR refuses (`closeout`'s sync does not); a trail PR closed unmerged leaves its entries staged until the next PICK; and the trail branch is never rebased, so once `origin/main` moves the postmortem ledger after the trail branch was cut, a later re-trail stages a ledger blob that lacks main's new line — the trail PR then conflicts at the ledger's end of file and both a hand pull and `closeout`'s sync refuse (fail-safe) until the owner resolves that trail PR by hand.

### Why a sync line alone never appends to Progress

A sync is checkout housekeeping, not close-out progress. When `closeout` counted a `synced — main at <sha>` line as progress, every re-run after the owner merged that run's own trail PR appended its skip lines and opened a fresh trail PR holding only them (run `automate-2026-10-01-142337`, trail PR #330). A re-run now prints only `skipped` item lines and leaves the run file byte-identical.

### Why the merge watcher is a detached script

An in-session `Monitor` until-loop dies with the session and is not verified headless, so the watcher is pure bash, launched detached with no Claude session and no tokens. The launcher and the watcher both drop the host session's identity variables and pin the lock holder to the closeout process itself: closeout's lock must name that process, or a closeout that died without its trap leaves a lock nobody can reclaim while its recorded holder (the launching session, or any live non-shell ancestor) lives. With the holder pinned, the lock meta records `pid_source holder_env`, a pid that is dead once closeout exits, so a crashed closeout's lock is reclaimable. Lane close-out does the same (`automate-lanes.sh` `_lanes_no_host_identity`); the resolution order is `docs/ARCHITECTURE_CONTRACTS.md` §"Run lock". Watchers are counted by the marker pid, never `pgrep -f`: every `$(…)` subshell of the watcher shares its argv, and the one "two watchers" sighting was that counting artifact. The CI rerun the settle re-check reports stays a human act (owner decision, 2026-10-07).

### Why PICK refuses while the trail PR is open

`closeout` opens the trail PR right after the item's merge. If the owner gives the next go first and merges the trail PR while the next item's PR is open, that merge moves the base under it; with `strict` required status checks the item PR then reads `mergeStateStatus: BEHIND` and cannot merge until the base is merged into it (run `automate-2026-10-01-142337`: trail PR #345 under PR #347). The PICK-time trail gate is option (b)'s first form — PICK refuses while the trail PR is open. Options considered:

- **(a) Refresh a READY-but-BEHIND PR by a regular merge of `origin/main` plus one confirming required-check pass — rejected.** It is not the drain's job: `review-heal`'s READY is defined over review signals and required checks, `mergeStateStatus` is corroborating-only, the drain pushes only fixes for validated findings, and `/review-pr` also runs on PRs outside this engine, where merging the base into the head branch is the repository owner's call. As an engine step at GATE it would cover only a base that moved before the park, and under `--auto-merge` the merge commit is a new head the drain never verified, so `gate-eval`'s `head_sha_moved` would have to accept a `ready_sha` the drain did not produce — a weaker condition 2, an owner decision rather than a fix.
- **(b)'s second form, hold the trail until run end — rejected.** `closeout`'s trail exists so a merged item's stamp, run file and drafts reach `main` per item, before the next one starts; holding it would leave every stamp off `main` for a run that parks for good, and the run-end trail PR would carry the whole run at once.
- **(c) Exempt `.supervisor/**`-only changes from the up-to-date requirement — impossible.** Classic branch protection's `required_status_checks.strict` is one boolean per protected branch with no path filter, and a ruleset's "require branches to be up to date" has none either: any commit on the base makes every open PR `BEHIND`.

The gate covers this run's trail PR only; another merge to the base while an item's PR is open (a hand-merged PR, another run's trail PR) still leaves it `BEHIND` under `strict`, and the owner updates the branch.

### Honest limits of the validation gate

`gate-eval` itself does not run the validation gate: the driver's `validation` step runs it before `gate-eval` and before every READY park, so a caller that skips the driver bypasses it. Classification is by title and first line: a step titled "Running system" is always gated, while a step whose first line names a mutation or a repro (and whose title does not) is classified `repro` and is not gated. The gate matches evidence in the PR body text and never runs the step itself; evidence is attributed to a step by a `validation <n>` line, or by its title only when no other entry shares it, so two steps both titled "Running system" each need their own `validation <n>` line.

### Why post-release writes take the run lock

The dismissed-findings writes after a sequential READY park run after the park released the run lock, while the merge watcher may run `closeout`, which holds the same lock across its steps. `progress-append`, `current-set` and `dismissed-decide` each rewrite and rename the whole run file without taking a lock, so a lock-free engine write racing a `closeout` can lose one of the two whole-file writes: with the real helpers, a concurrent `progress-append` lost `closeout`'s `status: done` 60 times in 60, leaving `## Current` at `awaiting_merge` after the watcher exited. Every engine write after the release therefore sits inside an `automate:<run_id>` run-lock window, which makes it mutually exclusive with `closeout` (the watcher's `closeout` passes no `--session-id`, so it never re-enters the engine's hold). The limits: a merge landing between the lock-held `park-ask-gate` read and a fix worker's push is not prevented (a human merge takes no lock), and the lock is cooperative — a writer that skips it can still lose a whole-file write.

### Honest limits of the dismissed-findings step

A fix-now re-drain re-initializes the per-PR round ledger, so one item can take up to twice the configured drain rounds. The engine-native learning line is written once per run, item, PR and source, so it reflects the first drain, not the re-drain. The re-dismissed fix-now check reads only the drain's own result: the Supervisor result sidecar is written once per item, so a fix-now name that came from Phase 4.5 stays suppressed.

### Why RESUME finalizes before listing

Before `resume-glob --finalize`, every finished single-item run stayed `paused` / `awaiting_go` and every later RESUME listed it as incomplete. Finalizing first writes `## Status: done` for a run whose Queue is resolved and whose last item `closeout` marked `done`, so a finished lane run is never offered. With branch mode off each finalized run opens or pushes its own trail PR, so finalizing several runs can open several trail PRs at once — accepted, because the PICK-time trail gate counts only the current run's own trail PR, and `finalize-empty` un-stages each finalized run's trail paths right after its trail. The run-file shape check (a title line, not a filename) exists because the result sidecars carry no `## Status:` line: without it each would read as an incomplete run and make resume ambiguous.

### Why a lane clone skips the cross-run close-out

`run-lock.sh` is per checkout, so two lanes — separate clones — could once close out or finalize the same run file each in its own clone. Inside a lane clone `closeout-others` now closes nothing and `resume-glob --finalize` finalizes only the lane's own run; the coordinator runs `closeout-others` once in the primary before it launches a wave. In branch mode `meta-sync.sh push` still arbitrates any residual double push (a conflict fails loudly, never a silent overwrite).
