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

## lanes and branch mode

### Why the primary stays locked for a whole wave

The run lock's liveness is the session's pid, and a wave outlives a session: the coordinator's `automate-lanes:<run_id>` lock alone is reclaimable once its session ends. So every sequential PICK and every new run's start in the primary also runs `pick-guard`, which refuses while a lane's process is alive (`lanes_proc_alive`) or a lane holds a pending question. A coordinator's own `--resume` is not guarded, because it is resuming those very lanes.

### Why single-lane mode needs branch mode

Lanes arrived with parallel-automate/05; single-lane mode (`--parallel 1`) with twin-remediation/08b (owner decisions 2026-10-14). With branch mode off, a single lane's close-out would open its own trail PR that the parent never sees, and `fleet-closeout` could never finalize the lane, so `init-check` fails closed on N = 1 unless `setup-memory.sh mode` (read with `--root` = the checkout's top level) prints `on <branch>`. A lane never runs the §10 merge gate, which is why `--auto-merge` is refused with any N.

### Why the coordinator arms a lane watcher

Without a watcher a lane's question sat unseen until the owner looked: in wave W3 (2026-10-11) two lanes waited 22–24 minutes. `lane-wait` blocks, token-free, until a lane needs the owner — a new pending question, or a lane entering any state that is neither live (`created`, `running`, `held_for_load`, `answer_pending`) nor coordinator-driven (`awaiting_merge`, `awaiting_go`, `done`, `removed`, `abandoned`) — so every other park, failure or unknown state wakes the coordinator. It prints one `lane-wait: …` line per event and a hint per event kind (`act` for a state, `relay` for a question). It never answers or launches anything, so it needs no launch authority. The re-arm was prose only until the `Stop` hook `guard-lane-wait-armed.sh` made it enforced for the coordinator session.

### How lane-status reads a lane's step timeline

`lane-status --json` gives every lane a `timeline` of steps (`pick` · `plan` · `build` · `heal` · `drain` · `decide` · `merge`), each with its `state` (`done`, `pending`, or the current step's `active` / `waiting` / `held` / `trouble`, taken from the lane state; every step `done` once `merged`), `started_at`, `ended_at`, `duration_s` and its last few lines, plus a `label` for the current step (`Build · EXECUTE`, `Drain · round 2`). It is read from the lane run file's dated `## Progress` lines and, for the Supervisor phase, the lane's `.supervisor/state.md` — only when that state is this item's (its `## Session` `session_id` is the lane's own session, it was created at or after the pick, or it reads running while the lane runs), so a previous item's never shows and a lane that stopped keeps its phase. The `picked` line starts Plan, a Launch Pad "brief saved" line starts Build, and a step passed with no line of its own reads `done` with null times. The state's `phase:` reads EXECUTE until the session ends, so Heal is read from the Supervisor's first `pr_created` session-log event at or after the pick (which dates Heal's start) and from the Decisions Log's SELF_HEAL / LOOP rows (which only show that Heal was reached). A step whose only dated line comes after it ended reads a null start. The document also carries `waves` — every wave PR the run opened, oldest first, as `{wave, branch, pr, built_at}`, read from `wave-build`'s `wave built: <branch> — PR <url>` `## Progress` record — and makes no `gh` call for it, so the wave PR's own state is not shown.

### Honest limits of lane answers and resumes

A kept (`answer_pending`) answer's re-check proves that the stored answer is a VALID label for the question still pending, not that the owner chose it — the same trust level as the lane inbox's answer file the relay hook reads. The pending file is not owner-authenticated, which is why it never carries, or stands in for, an owner command. A `--resume-run` resumes the lane's LAST session (a `--resume <session id>` spawn) so the lane's own `run.lock` — re-entrant only for the same session id — does not stall it; the fresh-session fallback still waits on a dead session's lock until `run-lock.sh`'s own reclaim (dead pid AND age at least its TTL).

### Why the wave end pushes a lane's non-claim files by exact list

`lane-convert-ready` pushes a lane's non-claim files by an exact list — its run file, `<run_id>.merge-readiness.md`, `<run_id>.dismissed-decisions`, `<run_id>.brief-draft.md`, the Orchestrator's task plans and the requirement drafts the lane filed under `.supervisor/requirements/proposed/` — and everything else through `trail-pr --reason wave-end`'s evidence gate, never a whole-lane push, so a done claim rides only for MERGED work. Each list entry exists because a path no other push carried stranded a lane: without the brief draft, L5 and L9 of run `automate-2026-10-15-163325` each read `local_ahead 1` until a hand push; without the task plans, `lane-remove` refused a lane forever; wave W4's `twin-remediation-11` draft rode neither push and needed a hand push. This is the wave end's metadata step, not a fourth §6 trail trigger: the lane's item is parked and the gate drops every unmerged claim. The re-run after the merge runs `closeout … --no-trail` before the pushes (automate-followups/38) so the done stamp rides them, and the lane finalize (parallel-automate/21 A1) follows only in branch mode — with it off, finalize would open a trail PR.

### Watcher survival in single-lane mode

Owner decision 2 of twin-remediation/08b: the merge watcher is armed by the lane, never by the coordinator. `test-automate-lanes.sh` proves a watcher launched with the documented launch line outlives the process that launched it and a hang-up; whether it outlives a real headless lane's exit is the operator's running-system check. The `--resume` → `fleet-closeout` → `lane-convert-ready` path is the fallback either way. Owner decision 3 made `--max-tokens` a whole-run ceiling; a removed lane's spend is read from its parent `fleet closeout: <lane> tokens TOTAL=<n>` line, and an abandoned lane writes that line too so the ceiling never sticks at `ledger_unreadable`.

### Honest limits of the wave close

The mechanical integration is the engine's and only merging the wave PR stays the owner's (parallel-automate/21 Part A; owner decision 2026-10-11). A lane counts as merged only when its OWN PR reads `MERGED` (`reconcile-item`): GitHub marks a lane PR merged when the wave PR is merged with a merge commit (its head is then an ancestor of the base); a squash merge does not. A lane PR the wave integration left open keeps reading `awaiting_merge`, and `fleet-closeout` waits on it.

### Honest limits of policy answers

Policy answers arrived with parallel-automate/21 Part B; their full contract and limits are in `docs/LANE_GATES.md`. Removing the stamp turns policy answering off at the NEXT `lane-create`; a lane already created keeps the policy carried at its creation. `lane.json` is writable inside the lane (the lane's deny list is a tripwire, not a sandbox): the worst a tampered policy can do is answer an `allowed` gate with one of that gate's own labels, because codes are checked against the catalog at `wave-set`, at `resolve` and again at `decide`, and `decide` rejects a policy whose `policy_sha` does not match its answers. The wave-policy file is not owner-authenticated either. The stamp hashes the whole selected must-rule set and `/rules check --confirm` runs every must-check, so a project's `lane-policy` rule keeps a check that is trivially true on a valid file.

### Why lane token totals are real now

Before parallel-automate/24 F8 every ledger line was a transcript-byte proxy and every TOTAL read 0, so no ceiling could trip — sequential runs included. `emit-token-ledger.sh` now reads each subagent's own transcript usage, once per message id, and the worker hook matcher runs the emitter too (before the PR #435 fix-now it did not, so the usually-largest share never reached `--max-tokens`). `TOTAL` includes cache-read tokens. Still not counted: the main thread's own tokens, CI-side review spend, a `--parallel` coordinator's own run, and the output tokens of a message whose final transcript line is absent (an under-count). No "checked between waves" claim is made — a one-wave run would never be checked.

### Why the leak check reads markers and this run's processes

The `merge-watch` section lists live watchers from the `*.merge-watch` markers of the primary and every lane, never a process-name match, which also caught any process merely naming the script (wave W3 read `leaks: found — merge-watch` with no watcher running); a watcher with no marker is not listed. The `claude-p` section lists only this run's processes, from one `ps` read (a lane's `_lane-run` wrapper, its headless children, and any headless session whose working directory is a lane), never a machine-wide match, which read another repo's healthy wave as `leaks: found — claude-p` (closing wave 1 of `automate-2026-10-15-163325`); a session whose wrapper is gone and whose working directory is outside every lane is not listed. A snapshot written before either format reads `not compared` for that section, never a false `found`. The `lanes-dir` section excludes the kept salvage and log artifacts by name, never by glob.

### What keep-awake counts

`machine.keep_awake` reads macOS power assertions, not only a `caffeinate` process: the desktop app's "Keep computer awake while Claude works" hold counts as `held`, but it lasts only while a Code session works and headless lanes are not Code sessions, so `keep_awake_lasting` is true for a `caffeinate` holder alone and `--keep-awake` still starts one when only the app holds.

### Why the command body keeps only a lanes pointer

The command body's lanes block (`command-lanes.md`, its split target) was a second, longer copy of skill §14 — the per-subcommand detail of `lane-create`, `wave-build`, `fleet-closeout` and the policy lookup — read under the same trigger as `lanes.md` itself. It is now a short owner-facing summary that points at §14. Launch authority was a new stance when lanes arrived: before them the plugin had no notion of which session may start a headless session on the owner's behalf.

### Honest limits of branch mode

(1) A manual whole-set `meta-sync.sh push` bypasses the evidence gate — only `trail-pr` applies it; a `--parallel` lane's metadata therefore never takes that route. (2) A done claim already on the branch for work later reverted stays there — no retroactive retraction on this path; `reconcile-status` is the tool. (3) `meta-entry`'s pull needs the network, so an offline machine in branch mode cannot start or resume a run — deliberate; the alternative is silent amnesia (every reader answers empty with exit 0 and a second run starts beside a paused one). (4) The SessionStart hint reads only `meta-base` presence, so a stale-but-once-synced clone gets no hint (the entry pull covers it); it never calls `meta-sync.sh status`, which fetches. (5) `meta-sync.sh push` plans over the WHOLE managed set even under `--paths-from`, so a conflict on ANY managed path blocks this run's trail push until a human resolves it; a twin-set conflict is the one exception. (6) That abort ignores consent: an agent-memory proposal both sides changed fails `meta-entry`'s pull and any push, even on a machine that declined to publish the learning stores. Extending the twin set's hold-don't-abort rule to the other learning stores is a follow-up candidate. Switching the mode never untracks already-committed run history (a separate operator step).

## merge gate and intake

### Why the merge is the engine's own step

Nothing in the plugin merges a PR on its own: `/review-pr`, `review-heal` and Supervisor Phase 4.5 all stop at `READY`/`PASS` and leave the PR open. But a loop that never merged would branch each next item from a stale base, or stack item PRs into a tower, so `/automate` owns the merge decision as its GATE step — a park for a human in safe mode, the trusted gate under `--auto-merge`.

### Why the merge gate is self-resolving

Before red-team-hardening item 03 every gate condition validated only the SHAPE of a value the model-authored loop wrote into `ctx.json` (`has()` + `type == "boolean"`, exact-string checks); none re-derived the value from reality, so a `ctx.json` claiming `"high_risk": false` with no `classify-risk.sh` run at all would have merged a genuinely high-risk diff. The gate now computes every condition it can from live ground truth itself, the ctx shrank to the six values only the drain and loop can know, and every former key the gate now computes is refused outright rather than ignored, so a caller trying to hand it a verdict is caught instead of silently overruled.

### How condition 1 treats unusual drain results

A `sub_floor_converged` READY is not merge-eligible because its final round skipped the all-channel bot-finding re-scan (`review-heal/SKILL.md` §"Termination-only severity floor"). A `ci_untrusted` termination (ci-trust-probe-01) always pairs with `drain_result: ESCALATED` — `ci-run-probe.sh` classifying a required check `untrusted_infra` still blocks READY — so a well-formed ctx already parks through the `!= "READY"` check; `gate_eval()` also carries a separate defense-in-depth park for that value (its condition 1c, beside the `sub_floor_converged` check), so a corrupted ctx claiming READY with `ci_untrusted` still cannot merge. `owned_drain_result: died` / `superseded_by_merge` (automate-followups/20) never reach the gate: a died item parks `drain_died` at RECONCILE and a superseded item skips GATE for `closeout`. The artifact cross-check exists because the drain's self-report about its own outcome is corroborated against the artifact it actually produced, never trusted blind; `result_block_parser.py` is a library with no CLI, so the gate uses a bounded grep/awk extraction.

### How the checkout pin reads a clean tree

Condition 7's checkout pin (automate-followups/16) reads, from the repo's top level so a subdirectory checkout still sees dirt anywhere: `git rev-parse HEAD` against the live head; `git status --porcelain -uall --ignore-submodules=none`; `git ls-files -v` for assume-unchanged and skip-worktree flags (so a sparse checkout parks); and untracked files with `--exclude-per-directory=.gitignore` plus the user's own global excludes file — `core.excludesFile` read from the global config with `--includes` (followed as git follows an `[include]` / `[includeIf]`), else the default XDG git ignore path, honoured only as an absolute path to a readable file physically outside the checkout (symlinks and directory aliases such as `/tmp` vs `/private/tmp` resolved, the checkout matched by device + inode). So `.git/info/exclude`, a repo-local `core.excludesFile` and an env-injected one cannot hide an untracked file, and an untracked `.gitignore` git actually reads (a self-ignoring `*`) is dirt. The git calls unset the `GIT_CONFIG_*` env injection family and force `core.fsmonitor=false` / `core.untrackedCache=false`. Every checked-out submodule gets the same reads, recursively (an owner fix-now), so a committed `.gitmodules` `ignore = all`, a submodule's own `info/exclude` or its flags cannot hide dirt. The two excluded paths are the engine's own: it rewrites its run file and sidecars under `.supervisor/` mid-item (tracked in a repo not in branch mode), and the agent-memory store directory holds the stores of `memory: project` agents — code-reviewer among them, which runs in Phase 4.5 and in the drain — written through `scripts/write-agent-memory.sh` and made tracked by `setup-memory.sh`'s managed block. Counting either would park every `--auto-merge` that touched them mid-item.

### Honest limits of the checkout pin

A rule whose `binds` path lies under one of the two excluded paths is not covered by the cleanliness pin. Settings in the repo's own `.git/config` that redefine a modification (`core.fileMode=false`, `core.autocrlf`, clean filters) are honoured as configured. Any other engine or agent write outside the two paths parks `rules_gate_dirty_tree` by design. A file in the user's global ignore (`.DS_Store`, `.idea/`, a host's local settings file) is trusted not to be a bound file, and the environment running the gate (`HOME`/`XDG_CONFIG_HOME`) chooses that file just as it chooses `PATH`. A hard link from the global excludes path to an in-repo file is not detected (symlinks and directory aliases are). An un-initialised submodule is not descended into, and a submodule path git has to quote parks. The untracked-`.gitignore` park relies on `git ls-files -o -i --directory` listing the contents of a directory no rule ignores rather than collapsing it; `test-automate-helpers.sh` R11f asserts that as a precondition, so a git that collapses fails CI instead of silently missing the park. A tool cache that writes its own self-ignoring `.gitignore` (`.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`, a Python `.venv/`) parks unless a committed or global ignore covers its directory.

### The checkout pin's premise

On the normal path the owned inline `/review-pr` drain checks the PR branch out on the main-thread checkout (`review-heal/SKILL.md` §"Step 1 — PR-URL → head resolution (isolation-aware)"), so the checkout is at the PR head when GATE runs. A later change to that checkout behaviour would turn every `--auto-merge` into a `rules_gate_head_mismatch` park, never a merge.

### Honest limits of the high-risk and rules conditions

The high-risk heuristic is pattern-based, not semantic: a comment containing `token` trips it, and in an agent-orchestration repo nearly every PR touches `agents/`, `commands/` or `skills/`, so nearly every PR parks at condition 6 by construction. That is the intent: high-risk stays behind a human. Condition 7 (automate-followups/07, owner decisions D1–D4, 2026-09-28) is dormant on a readable store with no countable `must` rule — this repo's own store today: the verdict is `none` and the condition holds, so the gate has teeth only once a human declares `binds` on a checkable `must` rule and confirms it with `/rules check --confirm`. `none` needs a readable store: a non-parseable store is `unreadable` and a recorded stamp whose live countable set drifted to empty is `unstamped` (`countable_set_drift`) — both park. A legacy stamp (one predating the recorded countable set) with an empty live set is not drift: it reads `none` (the `rules-gate-verdict.sh` header, THE COUNTABLE-SET BINDING).

### Why the Queue is confirmed, and when the confirm is skipped

The confirm exists so a prompt that explodes into forty files never runs silently. `queue-confirm` (automate-speed/01, owner decision D1) skips it in two cases where the owner already chose the work: a `--backlog` doc whose Queue holds at most `--limit` items (the owner wrote and ordered that doc, and `--limit` already caps the run), and a lane on its own `lane-create` backlog (parallel-automate/21 B8 — the owner chose the item by typing the coordinator's `--parallel` command). Every other source, and any count the helper cannot read as a plain integer, still asks. The `--limit` default follows "pull 5–10 and start".

### Why a named file's stamp counts as done, and why the engine never ticks the backlog doc

The file stamp is the evidence-gated truth: `closeout` writes it after reading the PR `MERGED`, and `trail-pr`'s evidence gate polices it. An unresolvable path stays queued because a silently hidden item is the worse failure (the full Queue is shown before processing). Only `is_done` applies to a checklist line's file: a checklist line is a human's explicit inclusion decision for a not-yet-ready item, but no one includes merged work on purpose. Ticking `_BACKLOG.md` would add a second, ungated done claim — nothing polices a checklist tick, and a tick written for work whose PR is later reverted or retracted would hide it from every future `--backlog` run — so with the stamp already sufficient, a tick would add a writer without adding truth. The not-ready skips (harness-port/02) use a separate predicate from `is_done` on purpose: `is_done` is shared with `resume-glob`, whose run files use a different status vocabulary.

### Why the parallel intake lint is information only

Under `--parallel N>1` the lint shows the owner, before approving, which items will not parallelise and the exact bad line of each. It does not block: the planner already runs such items alone or serialised, which is safe.
