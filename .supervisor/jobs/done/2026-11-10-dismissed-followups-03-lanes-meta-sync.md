# Supervisor Job: Dismissed follow-ups 03 — lanes, fleet close-out, meta-sync, plan-waves, janitor and sweep (23 findings)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (an unrelated worktree `wt-842` on `fix-842` in another session's scratchpad — not touched by this job)
- **Source requirement:** .supervisor/requirements/dismissed-followups/03-lanes-and-meta-sync-defects.md
- **Base commit:** f071613abefa18cb4e4a94e2191364771db5e458

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2 scripts, awk, jq, git plumbing; no new stack |
| 2 | Dependency Availability | GO | Every fix edits an existing script; the suites already stub `gh`, `lsof`, `ps` and the metadata remote on PATH / through seams |
| 3 | Architecture Fit | GO | Each fix stays inside one script's own guard, classify or report code; fail-safe emitters stay exit 0, fail-CLOSED refusals stay refusals; the auto-merge gate is untouched |
| 4 | Scope vs Supervisor Capability | CAUTION | 23 findings over ~34 files (≈17 scripts/docs + 13 test files + 3 evidence files + 1 fragment): past one worker's context, so split `context-bound` into 3 zero-overlap groups |
| 5 | Hard Blockers | CAUTION | Regression legs land in test files, F351's admission half is in `automate-lanes.d/launch.sh`, F003/F004/F005 live in the `meta-sync.d/` modules (`commands.sh`, `scrub.sh`, `lock.sh` — the Touches names only `meta-sync.sh`), F105's usage line is in `automate-trail.sh`, and the dispositions live in `docs/evidence/` — all outside the requirement's `## Touches` — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Close the 23 owner-deferred review findings of `dismissed-followups/03`: re-verify each on the base commit, fix it with a regression leg that fails on the pre-fix code, or record a one-line reason it is not reproducible / not worth fixing.

**Problem Statement:**
The owner needs the 23 `follow-up` findings bundled from 15 `/automate` dismissed drafts acted on, because "follow-up" decisions were never turned into work.
Currently 22 of them are still present on `main` (re-verified at f071613 by Launch Pad: every quoted anchor in `## Touched-file invariants` greps in its file; F355 is already fixed — `_jr_snap_get` feeds awk a here-string). They are a wave close-out that can silently drop a requirement's done stamp, a metadata-mode-off wave that can never close, a push that can re-create a deleted metadata branch, scrub and lock edge cases, `--explain` blocks that omit a co-existing reason, a readiness score inflated by an n/a row, a memory-guard trip file that outlives its sampler, and small CLI validators that accept empty or extra arguments.
Success looks like: every finding has one disposition (fixed + regression leg, or recorded with a reason) in a committed evidence file, and CI is green.

**Design (chosen at planning; the evidence file records any deviation with its reason):**
- **Dispositions live in committed evidence files, not in the requirement file.** `.supervisor/requirements/` is gitignored (`.gitignore` rule `.supervisor/*`), so a record written there is not in the PR diff. Each subtask writes `docs/evidence/dismissed-followups-03-<group>.md` (`lanes` / `engine` / `meta-sync`) with one row per finding it owns: `F<id> | fixed | <test file> :: <leg name>` or `F<id> | recorded | <one-line reason>`, plus the re-verify command it ran on the base commit.
- **F101 (MEDIUM) — a close-out leftover becomes a persisted marker, never a silent removal.** `closeout` returns early on `## Current already done` (closeout.sh's first step, outside every lane), so a skipped stamp can never be retried by a re-run of `lane-convert-ready` (phase `closed` runs no closeout at all). Therefore: when the closeout phase classifies a `leftover` (the `cs="; closeout leftover: …"` branch), `lane-convert-ready` writes `<lane>/.supervisor/automate/<run_id>.closeout-leftover` (line 1: the leftover detail) and removes it when a later closeout reads `complete`; `fleet-closeout` checks that marker exactly like `.meta-push-failed` (`human — <lane> closeout leftover: <line 1> — fix it by hand, then remove the marker`) and never adds the lane to `closed`; `lane-remove` (without `--abandon`) refuses while the marker exists, beside its `meta-push failure marker is set` refusal. The marker is listed in `automate-lanes.sh`'s header `Files` and in `lanes.md` §"Wave close". No new `_fc_ev` event code (the line is `human —`, a known class).
- **F105 (MEDIUM) — metadata mode off: the lane finalizes without a trail push.** `finalize-empty` gains `--no-trail` (any position; skips ONLY the `trail-pr … --reason done` step and prints the literal closeout already prints, `trail-pr: skipped — --no-trail`); `lane-convert-ready` in mode off, on a re-run whose `## Current` reads `done`, runs `finalize-empty <rf> --no-trail` through `_lanes_no_host_identity` exactly as the mode-on call does, so the lane reads `## Status: done` and `fleet-closeout` closes and removes it. `lanes.md` documents the mode-off wave close: the lane's run history and done stamp stay in its salvage and are not published (branch mode is what publishes them). The AE4/AE4b/AE4d pins of the old behavior are rewritten to the new contract, never deleted.
- **F109 — `fleet-closeout` re-reads the lock after `release`.** `run-lock.sh release` is kept idempotent (exit 0 on a not-ours lock — `test-run-lock.sh` pins it); `fleet-closeout` runs `run-lock.sh status --root <primary>` after a successful release and prints `wave closed — lock released` only on `UNLOCKED`, else `wave closed — lock still held by another owner (<status line>)` (still `pass ok`: nothing failed).
- **F103 — the extras commit message names the phase:** `convert` keeps `ready_for_release -> awaiting_merge (wave end)`; `closeout` ⇒ `chore(supervisor): <run> wave-end re-run (closeout, reads <status> / <pause>)`; `closed` ⇒ `chore(supervisor): <run> wave-end re-run (metadata push retry)`.
- **F111 — `--wave-branch` is refused outside `[A-Za-z0-9._/-]`** (`'<name>' holds a character outside [A-Za-z0-9._/-]`), beside the existing `git check-ref-format --branch` check, so the printed plan never carries a shell metacharacter; the default `wave/<parent>-w<k>` is always inside the class.
- **F068 — a generated-file conflict is regenerated, never hand-resolved:** `lanes.md` §"Wave close" and `wave-plan`'s printed `# Conflict rules` gain one rule: a conflict on a generated file (this plugin: `loomwright/capabilities.json`) is resolved by re-running its generator on the merged tree (`bash loomwright/scripts/build-capabilities.sh`) and committing the result. Doc + echoed text only.
- **F076 — one authority for the after-launch write exceptions:** `docs/ARCHITECTURE_CONTRACTS.md`'s `Single write` row is the list. The worker first diffs the three current lists (the row; `automate-lanes.sh`'s `lane.json` comment items (1)–(4); `lanes.md` step 6) and the row gains every item any of them names that it lacks — today: branch-mode `finalize-empty`'s `## Status: done` + Progress lines, `lane-launch --no-cheap`'s removal of `cheap` from `lane.json` (`_lanes_cheap_clear`), `lane-scope-decide`'s writes — plus the new `.closeout-leftover` marker; then `automate-lanes.sh`'s comment and `lanes.md` step 6 keep one sentence each and cite that row by section name instead of restating the list, so no exception is dropped from every surface. `status.sh`'s "Never answers, launches, resumes or writes into a lane" describes `lane-status` itself and stays.
- **F262 — documented, not merged:** `lanes.md` §"Dismissed findings, tokens, RESUME, removal" states that the coordinator-model ledger (`<automate_dir>/coordinator-model.jsonl`) is per lane — it resets with each lane and travels only into the lane's salvage; `lane-remove` never merges it into the primary's. (Merging would let one lane's FAILs escalate the next lane's session — a behavior change the owner has not asked for.)
- **F077 — an n/a headline-repro is not scored:** when the Validation names no repro the row reads `headline-repro: N/A — the Validation names no repro (not scored)` and the score's total is 4 (`score: x/4`); a named repro keeps `/5`. `status-read.sh` parses `score: N/M` generically (`sed -n 's/^- score: \([0-9]*\/[0-9]*\).*/\1/p'`) and needs no change.
- **F133 — a count-prefixed `N skipped` is a result, not a not-run statement:** in `_lanes_rd_section`'s awk, `nrl()` no longer raises NL for `skipped` immediately preceded by a digit (`2 skipped`, `40 passed, 2 skipped`); a bare `skipped` and every heading rule are unchanged (fail-closed stays the default — the header's phrase list is updated to say so).
- **F351 — the trip file carries its sampler's pid and dies with it:** `write_trip` adds line 3 `sampler_pid: <pid>`; the sampler's `TERM INT HUP` trap removes the trip file before `exit 0` (a reaped or stopped sampler holds no lane); one shared reader, `_lanes_trip_live <trip file>` in `automate-lanes.d/common.sh` (true when the file exists and either has no `sampler_pid:` line — legacy, or hand-written as test G4 does — or names a pid that `kill -0` finds alive; fail-closed), is what BOTH readers of the trip file call: `_lanes_admission` (`launch.sh`) holds `memory_pressure` only when it is true, and `lane-status`'s `memory_pressure` field / `memory_pressure: new launches held` line (`status-read.sh`'s `--arg mp` read) reports true only when it is true — so `lane-status` never says "held" while `lane-launch` admits. `lanes.md` says the trip holds every launch and resume while its sampler is alive. Registration stays `--kind lane` (its 24 h cap now reaps only the sampler, which no longer wedges the wave).
- **F023 / F025 — `--explain` records every reason where the decision is made:** in the full-wave branch, after `wave <w> full (--max <N>)`, also run the same `_pw_conflicts` loop the placed-branch uses against the wave's members and record each `conflicts with …` line; in the deps-unmet branch, also record `runs alone: Touches unknown (<why>)` when `TS[i] != known`. The X1 legs' exact outputs stay green (their fixtures have no co-existing conflict); new legs add one.
- **F142 — flush unconditionally** (`if (path != "")`), relying on the explicit `[ "$cp" = "$SW_PRI" ] && continue`; git always lists the primary first and the sweep has no git seam, so the change is behavior-neutral and gets no leg — recorded as `fixed (no observable change; no leg)`.
- **F137 — `--apply` re-reads liveness before each removal:** in the apply branch, right before `git worktree remove`, reset `SW_LIVE_STATE=""`, call `_sw_live_read` again and re-run `_sw_live`; a process that cd'd in after the first snapshot keeps the worktree (`live process <pid> has its cwd here`). The dry run keeps its single read.
- **F138 — recorded, not fixed:** the run-end sweep is dry, memoised per branch (`SW_PR_CACHE`), and the cost was accepted by the PR that added it; bounding it would hide branches from the run-end report.
- **F353 — `act` rejects an empty id explicitly:** `'')` arm before the malformed-id check prints `act — empty row id` and returns 2 (the existing usage error path); `act --confirm ''` can no longer reach the checkout guard.
- **F355 — recorded: already fixed on main** (`_jr_snap_get` uses `<<<"$JR_SNAP"`, no printf pipe).
- **F058 — `valid-branch` refuses extra positionals:** any further non-option argument after the name sets a flag the valid-branch block refuses (`valid-branch takes only a name (got an extra argument '<arg>'); nothing was judged`, exit 1), the same shape as its `--branch-mode / --ledger / --allow` refusal.
- **F003 — the push expects the fetched tip:** `g push -q --force-with-lease="refs/heads/$BRANCH:$R" origin "$commit:refs/heads/$BRANCH"` (`R` = `REMOTE_SHA`, the tip the plan was built on); a branch deleted (or moved) between fetch and push is refused, the retry re-fetches, and nothing is ever created — `init` stays the only creator (`meta-sync.sh` header unchanged).
- **F004 — reserved first segments and an all-dot repo still check the owner:** for a first segment in `orgs`, `users` or `sponsors` the owner is the NEXT segment; for an all-dot repo segment the owner is still checked; an owner passes only when some allow-file line starts with `<owner>/`. Other reserved words (`about`, `blog`, …) keep `continue`.
- **F005 — the locked message tells the owner what to do when the holder is dead:** when `lock_is_stale` says the holder is not running but the reclaim did not succeed (a marker chain deeper than 4), the `die` adds ` — the holder is not running: remove <LOCK_DIR> (and any <LOCK_DIR>.reclaim.* markers) by hand`. The depth bound stays.
- **F134 — a drift pin, not an extraction:** `04-learning-stores.sh` gains a leg asserting `learning-twin.sh`'s `twin_field` sed expression and `read-system-contract.sh`'s `field` expression are byte-identical, and that both walks start at `prev="GENESIS"`; extracting a sourced lib into the provenance-gated, fail-DARK twin read path buys no behavior for the risk — disposition `fixed (drift pin; no behavior change)`.

## Acceptance Criteria

**Every finding (all subtasks)**
- [ ] AC1. Given a finding this brief assigns to a subtask, when the worker starts, then it re-runs the finding's anchor check on its own base (the `grep -nF` of the quoted anchor in `## Touched-file invariants`, or the finding's repro) and a committed evidence file `docs/evidence/dismissed-followups-03-<group>.md` (`lanes` / `engine` / `meta-sync`) contains, per finding, the check run and exactly one disposition: `fixed` naming the test file and leg, or `recorded` with a one-line reason; the PR body links to the three files.
- [ ] AC2. Given every finding dispositioned `fixed` that changes behavior (all except the doc-only F068, F076, F262, the behavior-neutral F142 and the drift-pin F134), when its new regression leg runs against the base-commit version of the script (`git show f071613:<path>` copied into a scratch dir beside the suite's fixtures), then the leg fails, and it passes on the fixed script — the leg name and the pre-fix red result are listed in the evidence file.

**Subtask 1 — lanes, fleet close-out and readiness (`lanes`)**
- [ ] AC3 (F101, MEDIUM). Given a merged lane whose re-run closeout classifies a `leftover` (fixture: the lane's requirement file made unwritable, so closeout prints `closeout: skipped — requirement not writable`), when `lane-convert-ready` runs, then `<lane>/.supervisor/automate/<run_id>.closeout-leftover` exists with that detail on line 1, `fleet-closeout` prints `human — <lane> closeout leftover: …` and neither checks the item off nor removes the lane, and `lane-remove <lane_dir>` is refused naming the marker; given the marker removed by hand, when `fleet-closeout` re-runs, then the lane is removed — legs in `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` (and the marker write/clear in `03-fixes-to-finalize.sh`).
- [ ] AC4 (F105, MEDIUM). Given `finalize-empty <runfile> --no-trail`, when it runs on an eligible paused run, then it writes `## Status: done`, prints `trail-pr: skipped — --no-trail` and calls no `trail-pr` — leg in `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh`; and given a metadata-mode-off lane whose merged re-run reconciled `## Current` to done, when `lane-convert-ready` re-runs, then its finalize line reads `lane-convert-ready: finalize — finalize-empty: finalized …`, the lane run file reads `## Status: done`, and `fleet-closeout` in mode off closes it out, checks the item off and removes the lane — AE4/AE4b/AE4d rewritten and a fleet leg added in `04-fleet-closeout-to-optout.sh`.
- [ ] AC5 (F109). Given the wave lock held by another owner at wave end, when `fleet-closeout` reaches the release, then its last line reads `wave closed — lock still held by another owner (LOCKED …)` and `run-lock.sh status` still reads LOCKED; the existing AF4/AF4b/AF… legs (`wave closed — lock released` + UNLOCKED) stay green — leg in `04-fleet-closeout-to-optout.sh`.
- [ ] AC6 (F103). Given a mode-on lane re-run in phase `closeout` and one in phase `closed`, when `lane-convert-ready` pushes the extras, then the metadata branch's newest commit message names the re-run phase (`wave-end re-run (closeout, reads …)` / `wave-end re-run (metadata push retry)`), and a `convert` run keeps `ready_for_release -> awaiting_merge (wave end)` — legs in `03-fixes-to-finalize.sh`.
- [ ] AC7 (F111). Given `wave-plan <rf> --wave-branch 'a$(id)b'` (and `x&&y`), when it runs, then it prints `wave-plan: refused — 'a$(id)b' holds a character outside [A-Za-z0-9._/-]` and nothing else; `--wave-branch release/w2` still prints `git checkout -b release/w2 origin/main` (AG3b) — leg in `04-fleet-closeout-to-optout.sh`.
- [ ] AC8 (F068, F076, F262). Given `lanes.md`, `automate-lanes.sh`'s header and `docs/ARCHITECTURE_CONTRACTS.md`, when read, then: the `Single write` row is the only list of after-launch writes — the union of the three current lists (now including branch-mode `finalize-empty`'s `## Status: done`, `lane-launch --no-cheap`'s `cheap` removal from `lane.json`, `lane-scope-decide`'s writes) plus the `.closeout-leftover` marker, with the diff of the three lists recorded in the evidence file — and the other two surfaces cite it by section name; `lanes.md` §"Wave close" and `wave-plan`'s `# Conflict rules` carry the regenerate-a-generated-file rule naming `loomwright/capabilities.json` / `build-capabilities.sh`; `lanes.md` states the coordinator-model ledger is per lane and salvaged, never merged; `lanes.md`'s sampler paragraph says the trip file holds every launch and resume while its sampler is alive (F351's contract, owned by Subtask 2's code) — `04-fleet-closeout-to-optout.sh` pins the new echoed conflict rule.
- [ ] AC9 (F077). Given a Validation that names no repro, when `lane-readiness` writes the report, then the row reads `headline-repro: N/A — the Validation names no repro (not scored)` and the score line's total is 4 (e.g. `score: 4/4`); given a named repro, then the total stays 5 — legs in `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh`, with Z-F5b in `03-fixes-to-finalize.sh` rewritten to the new line.
- [ ] AC10 (F133). Given a matched Validation line `tests: 40 passed, 2 skipped` (non-fenced), when `_lanes_rd_section … nv` runs, then it prints nothing (the step is not NOT-RUN); given a bare `skipped` on such a line, then it still prints `NL` — legs in `02-readiness-to-convert.sh`.

**Subtask 2 — sampler, plan-waves, sweep, janitor, setup-memory (`engine`)**
- [ ] AC11 (F351). Given the sampler trips, when the trip file is read, then line 3 is `sampler_pid: <its pid>`; given the sampler receives TERM while tripped, then the trip file is gone after it exits; given a trip file whose `sampler_pid:` names a dead pid, when `lane-launch` admits, then it is not HELD `memory_pressure` and `lane-status <rf> --json` reads `memory_pressure: false` (no `new launches held` text); given one with a live pid, or none (G4), then it is HELD and `lane-status` reads `memory_pressure: true` — both readers go through `_lanes_trip_live` in `common.sh` — legs in `loomwright/scripts/test-lane-sampler.sh` and `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh`.
- [ ] AC12 (F023, F025). Given `plan-waves --explain` with an item held out of a full wave that also declares a Touches path a wave member declares, when it runs, then that item's explain block carries both `wave <w> full (--max <N>)` and `conflicts with <member> on <path> (declared)`; given an item with an unmet dependency and a missing `## Touches`, then its block carries both `depends on <x>` and `runs alone: Touches unknown (missing)`; the X1 legs stay byte-identical — legs in `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh`.
- [ ] AC13 (F142, F137). Given the worktree-list awk, when read, then `flush()` is unconditional on `path != ""` (F142, no leg — recorded as behavior-neutral); given `sweep --apply` with two removable worktrees and an `lsof` stub that reports a live cwd in the SECOND worktree only from its second call on, when the sweep runs, then the first is removed and the second is kept `live process … has its cwd here` (the dry run still calls the stub once) — leg in `loomwright/scripts/test-automate-trail.d/06-sweep.sh`.
- [ ] AC14 (F353). Given `janitor-report.sh act --confirm ''` (and `act ''`), when it parses, then it exits 2 with `act — empty row id` on stderr and never prints the `refused — not a git checkout` line — leg in `loomwright/scripts/test-janitor-report.sh`.
- [ ] AC15 (F058). Given `setup-memory.sh valid-branch loomwright-meta extra`, when it runs, then it exits 1 with ONE stderr line `valid-branch takes only a name (got an extra argument 'extra'); nothing was judged`; `valid-branch loomwright-meta` still exits 0 — leg in `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh`.
- [ ] AC16 (F138, F355). Given the evidence file, when read, then F138 is `recorded` (accepted dry, memoised run-end cost) and F355 is `recorded` (already fixed at f071613: `<<<"$JR_SNAP"`), each with the re-verify command.

**Subtask 3 — meta-sync (`meta-sync`)**
- [ ] AC17 (F003). Given a `pre-push` hook (injected through `core.hooksPath` in the pushing checkout) that deletes `refs/heads/<branch>` in `origin.git` after the fetch and before the push, when `meta-sync.sh push` runs, then it ends `push_failed` (nothing forced), `refs/heads/<branch>` is still absent in `origin.git`, and meta-base is untouched; the normal push leg still passes — leg in `loomwright/scripts/test-meta-sync.d/01-sync-core.sh`.
- [ ] AC18 (F004). Given a file carrying `https://github.com/orgs/evilcorp/repos` and one carrying `https://github.com/evilcorp/.../pull/3` with `evilcorp` not allowlisted, when the scrub runs, then both are `forge_slug` hits; given `github.com/orgs/owner/…` with `owner/repo` allowlisted, then no hit — legs in `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh`.
- [ ] AC19 (F005). Given a lock dir holding a dead pid under a reclaim-marker chain 5 deep (each marker holding a dead pid), when `meta-sync.sh` waits out `LOCK_WAIT`, then it dies with the locked message carrying `the holder is not running: remove … by hand`, nothing was changed; a live holder's message carries no such hint — leg in `01-sync-core.sh`.
- [ ] AC20 (F134). Given `learning-twin.sh` and `read-system-contract.sh`, when the new leg runs, then it extracts both STRING-field sed expressions and both `prev="GENESIS"` starts and asserts they are byte-identical (a mutation control that edits one copy in a scratch dir turns it red) — leg in `loomwright/scripts/test-meta-sync.d/04-learning-stores.sh`.

**Validation**
- [ ] V1. `bash scripts/ci-local.sh --affected` passes for each subtask's files, including `check-prompt-history-refs.sh` (no finding id, PR number or incident story added to `lanes.md` or any other prompt file), `check-token-budget.sh` (`automate-loop` has 4140 tokens of headroom; the `lanes.md` additions stay well under it), `test-citation-drift.sh` (no bare `file:N` in new prose) and `check-doc-currency.sh` (the `ARCHITECTURE_CONTRACTS.md` row edit restates no count).
- [ ] V2. `bash scripts/check-version-bump.sh` passes; the PR carries `changelog.d/dismissed-followups-03-lanes-and-meta-sync-defects.md` and no hand-edited version file.

## Scope widening
- docs/evidence/dismissed-followups-03-engine.md
- docs/evidence/dismissed-followups-03-lanes.md
- docs/evidence/dismissed-followups-03-meta-sync.md
- loomwright/scripts/automate-helpers.sh
- loomwright/scripts/automate-lanes.d/launch.sh
- loomwright/scripts/automate-lanes.d/status-read.sh
- loomwright/scripts/automate-trail.sh
- loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden
- loomwright/scripts/meta-sync.d/commands.sh
- loomwright/scripts/meta-sync.d/lock.sh
- loomwright/scripts/meta-sync.d/scrub.sh
- loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh
- loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh
- loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh
- loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh
- loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh
- loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh
- loomwright/scripts/test-automate-trail.d/06-sweep.sh
- loomwright/scripts/test-janitor-report.sh
- loomwright/scripts/test-lane-sampler.sh
- loomwright/scripts/test-meta-sync.d/01-sync-core.sh
- loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh
- loomwright/scripts/test-meta-sync.d/04-learning-stores.sh
- loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh
- accepted: LP-SCOPE 2026-11-10

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| lanes (Subtask 1) | `loomwright/scripts/automate-lanes.d/wave.sh` (492 — single home of `lanes_fleet_closeout` and `lanes_wave_plan`; the marker check, the post-release status read, the branch-name class check and one echoed conflict rule are edited in place), `loomwright/scripts/automate-lanes.d/remove.sh` (504 — single home of `lanes_convert_ready` and `lane-remove`'s refusals; the marker write/clear, the mode-off finalize call, the per-phase commit message and one refusal are edited in place), `loomwright/scripts/automate-trail.d/finalize.sh` (263 — `finalize_empty` gains the `--no-trail` arm beside its existing argument loop), `loomwright/scripts/automate-trail.sh` (255 — its usage header's `finalize-empty <runfile>` line gains `[--no-trail]`; dispatch untouched), `loomwright/scripts/automate-helpers.sh` (1256 — ONE `#:` usage row, `finalize-empty   <runfile>`, gains `[--no-trail]` beside its `closeout` sibling; nothing else in the file, the merge executor included, is touched), `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` (13 — the hand-kept golden of that usage block; the one row edited to match, `#:  ` as two spaces), `loomwright/scripts/automate-lanes.d/readiness.sh` (588 — the `headline-repro` row/score and `nrl()` edited in place; its header phrase list updated), `loomwright/scripts/automate-lanes.sh` (447 — header comment only), `loomwright/skills/automate-loop/lanes.md` (110), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066 — one table row), `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` (687), `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` (966 — AE4/AE4b/AE4d and Z-F5b rewritten in place, legs appended), `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` (562), `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` (914) — each the script's own suite with the fixtures the new legs need; legs appended | `docs/evidence/dismissed-followups-03-lanes.md` | HIGH |
| engine (Subtask 2) | `loomwright/scripts/lane-sampler.sh` (360 — `write_trip` and the signal trap), `loomwright/scripts/automate-lanes.d/common.sh` (330 — the shared module every `automate-lanes.d/` file sources; extract `_lanes_trip_live` into it, the one trip-file reader), `loomwright/scripts/automate-lanes.d/launch.sh` (345 — `_lanes_admission`'s trip read, now a call), `loomwright/scripts/automate-lanes.d/status-read.sh` (799 — the one `--arg mp` read, now a call), `loomwright/scripts/automate-helpers.d/plan-waves.sh` (656 — the two `--explain` branches), `loomwright/scripts/automate-trail.d/sweep.sh` (337 — the awk `flush()` and the apply branch), `loomwright/scripts/janitor-report.sh` (971 — one `case` arm in `jr_act`), `loomwright/scripts/setup-memory.sh` (457 — the `valid-branch` parse arm and refusal block), `loomwright/scripts/test-lane-sampler.sh` (317), `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` (801), `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` (786), `loomwright/scripts/test-automate-trail.d/06-sweep.sh` (443), `loomwright/scripts/test-janitor-report.sh` (819), `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh` (557) — legs appended | `docs/evidence/dismissed-followups-03-engine.md` | HIGH |
| meta-sync (Subtask 3) | `loomwright/scripts/meta-sync.d/commands.sh` (318 — the one push line), `loomwright/scripts/meta-sync.d/scrub.sh` (151 — the forge-slug owner loop), `loomwright/scripts/meta-sync.d/lock.sh` (103 — the `die` in `acquire_lock`), `loomwright/scripts/test-meta-sync.d/01-sync-core.sh` (615), `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh` (671), `loomwright/scripts/test-meta-sync.d/04-learning-stores.sh` (503) — legs appended | `docs/evidence/dismissed-followups-03-meta-sync.md`, `changelog.d/dismissed-followups-03-lanes-and-meta-sync-defects.md` | HIGH |

New responsibilities get no new module: every fix is a guard, a classify branch or a report line inside the one function that owns it, so appending to the large files is the single-authority form noted above. No helper is copied: F101 reuses the `.meta-push-failed` marker idiom (write, `fleet-closeout` check, `lane-remove` refusal), F105 reuses closeout's `--no-trail` literal and `_lanes_no_host_identity`, F109 reuses `run-lock.sh status`, F137 reuses `_sw_live_read` / `_sw_live`. One extract row: F351's trip-file liveness rule would otherwise be copied by `launch.sh` and `status-read.sh`, so it is extracted as `_lanes_trip_live` into the existing shared module `automate-lanes.d/common.sh` (a `kill -0` liveness probe, the idiom `launch.sh`, `remove.sh` and `lane-sampler.sh` already use; `common.sh`'s own `lanes_proc_alive` is the stricter `ps -o lstart=` + command match, deliberately pid-reuse safe, which the trip file cannot use because it records no start time) and both call it. Not modified although listed in the requirement's Touches: `automate-lanes.d/create.sh`, `status.sh`, `capabilities.json`, `build-capabilities.sh`, `meta-sync.sh`, `meta-sync.d/learning-twin.sh`, `proc-registry.sh`, `read-system-contract.sh`, `run-lock.sh` (each either unaffected by the chosen design or pinned to stay as is).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Touched-file invariants

> Grounded at base `f071613abefa18cb4e4a94e2191364771db5e458`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-lanes.d/wave.sh`** — keep: every per-lane line is `_fc "<class> — <lane> …"` and a `human —`/`waiting —` lane is `continue`d before `closed` grows (`if [ -f "$mk" ]; then _fc "human — $lane meta-push-failed:` — the new marker check sits right beside it); the detail grep stays (`grep -E '^lane-convert-ready: (finalize|refused|FAILED)'`); the release stays under `[ "$fc_bad" = 1 ] || _fc_ev pass ok` with no new event code; the branch-name check extends `git check-ref-format --branch "$wb" >/dev/null 2>&1 || { WV_WHY=`; the printed rules keep `echo "#   - a marker-only conflict is resolved in the merge commit itself"`. Pinned by: `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` (`fleet-closeout: wave closed — lock released`, `git checkout -b release/w2 origin/main`).
- **`loomwright/scripts/automate-lanes.d/remove.sh`** — keep: the phase `case` (`ready_for_release/ready_for_release) phase=convert ;;`), the leftover suffix shape (`else cs="; closeout leftover: $(printf '%s\n' "$cv" | awk -F'\t' '$1 == "leftover"`), the `pr not merged` wait (`cs="; closeout waits for the merge — pr not merged $gw"`), the mode-off early return (`echo "lane-convert-ready: $did (metadata mode off — no metadata branch to push)$cs"`), the finalize call shape (`_lanes_no_host_identity LOOMWRIGHT_META_SYNC_BIN="$META_SYNC"`) and the refusal idiom (`_refuse "meta-push failure marker is set"`); the extras push line being split by phase: `_lanes_meta_extras "$mb" "chore(supervisor): $LN_RUN ready_for_release -> awaiting_merge (wave end)"`. Pinned by: `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` (`retrying the metadata push only`, `a re-run converts nothing`), `04-fleet-closeout-to-optout.sh`.
- **`loomwright/scripts/automate-trail.d/finalize.sh`** — keep: the EXIT-trap release (`trap fe_release EXIT`), the skipped form (`fe_release; trap - EXIT; echo "$S $why"; return 0`), the trail call being the step `--no-trail` skips (`l="$(bash "$HLP" trail-pr "$rf_abs" --reason done 2>/dev/null | tail -n1)"`), and the dry sweep (`sw="$( (sweep_run --root "$root") 2>/dev/null | tail -n1)"`). Mirror: the `--no-trail` literal closeout prints (`echo "trail-pr: skipped — --no-trail"` in `automate-trail.d/closeout.sh`) and `resume.sh`'s reader of finalize-empty's lines (`"finalize-empty: skipped — not paused"|"finalize-empty: skipped — pause_reason "*`) — the new line is a `trail-pr:` line, never a `finalize-empty:` one. Pinned by: `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh`.
- **`loomwright/scripts/automate-trail.sh`** — keep: the dispatch line untouched (`finalize-empty) finalize_empty "$@" ;;`), the seams (`LSOF="${LOOMWRIGHT_LSOF_BIN:-lsof}"`); only the usage header line `#   finalize-empty <runfile>` gains `[--no-trail]`, worded like its `closeout` sibling (`#   closeout <runfile> <item> <pr_url> [--session-id <sid>] [--no-trail]`). Pinned by: `loomwright/scripts/test-automate-trail.sh` (dispatch).
- **`loomwright/scripts/automate-helpers.sh`** — keep: everything but ONE `#:` usage row — in particular the sanctioned `gh pr merge --squash` executor and `gate-eval` are not touched; the row `#:  finalize-empty   <runfile>                          # §3/§4 step 1: delegated to automate-trail.sh` gains `[--no-trail]` in its argument column, worded like `#:  closeout         <runfile> <item> <pr_url> [--session-id <sid>] [--no-trail]`; the fail-SAFE subcommand list (`meta-entry and meta-push-failed are the fail-SAFE`) is unchanged. Mirror: `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` holds that usage block byte-for-byte (`  finalize-empty   <runfile>                          # §3/§4 step 1`) and is edited in the same change (the one row, `#:  ` replaced by two spaces, at the same position — the fixture is a hand-kept per-segment golden, not generated). Pinned by: `loomwright/scripts/test-automate-helpers-dispatch.sh` (`fixtures/automate-helpers-help/<segment>.golden` byte-for-byte, and each `#:  ` row at the same position in its segment's golden).
- **`loomwright/scripts/automate-lanes.d/readiness.sh`** — keep: the repro rows' states (`case "$st" in FAIL) eworst=FAIL ;; NOT-RUN) [ "$eworst" = FAIL ] || eworst=NOT-RUN ;; esac`), the score loop's label form (`for w in "validation:$vworst" "carried-notes:$cworst" "scope-fence:$fworst" "gates:$gworst" "headline-repro:$eworst"; do`), the score line (`echo "- score: $pass/$total | summary: $summary"`), `nrv()` unchanged (`function nrl(s) { return nrv(s) || ph(s, "skipped") }` is the one line F133 edits), fenced lines never raising NL. Mirror: `status-read.sh` reads `score: N/M` (`sed -n 's/^- score: \([0-9]*\/[0-9]*\).*/\1/p'`). Pinned by: `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` (`- score: 2/5 | summary:`), `03-fixes-to-finalize.sh` (`headline-repro: PASS — n/a (the Validation names no repro)` — rewritten).
- **`loomwright/scripts/automate-lanes.sh`** — keep: the header's `Files` list form (`#   <lane>/.supervisor/lane.json        D2 marker — the ONE marker lane-create writes`); only comment text changes (`coordinator never writes into the lane again, EXCEPT (1) the answer`). Pinned by: `loomwright/scripts/test-automate-lanes.sh` (dispatch, not this comment).
- **`loomwright/skills/automate-loop/lanes.md`** — keep: history-free prose (`scripts/check-prompt-history-refs.sh` baseline may only go down — no finding id, PR number or date); the step-6 sentence (`After launch the coordinator never writes into the lane again, except`) becomes a pointer; the wave-plan paragraph (`Then the conflict rules: resolve a marker-only conflict in the merge commit`) gains the regenerate rule. Pinned by: `loomwright/scripts/test-automate-loop-split.sh`, `loomwright/scripts/test-wave-build.sh` (token budget: `scripts/check-token-budget.sh`, skill `automate-loop`).
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: the row stays one table line (`| Single write | \`lane-create\` writes into a lane only \`lane.json\``); no count restated. Pinned by: `scripts/check-doc-currency.sh` (doc surface).
- **`loomwright/scripts/lane-sampler.sh`** — keep: the trip file's first two lines (`{ printf 'tripped_utc: %s\n' "$(utc)"; printf 'sample: %s\n' "$1"; } > "$t"`), the clear rule (`tripped=0; rm -f "$TRIP" 2>/dev/null; note "memory guard cleared $(utc)"`), the adopt rule (`[ -f "$TRIP" ] && tripped=1`), the temp-dir EXIT trap (`trap 'rm -rf "$TMPD"' EXIT`); fix site `trap 'exit 0' TERM INT HUP`; registration stays (`register --pid "$$" --kind lane --owner-pid "$PARENT_PID"`). Mirror: `launch.sh`'s read of the trip file. Pinned by: `loomwright/scripts/test-lane-sampler.sh` (`trip file line 1 = UTC ts`, `(R) ... kind lane`).
- **`loomwright/scripts/automate-lanes.d/launch.sh`** — keep: `_lanes_admission` prints the HELD reason and returns 1 (`[ -e "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.memory-pressure" ] && { printf 'memory_pressure'; return 1; }` is the line F351 turns into a `_lanes_trip_live` call); the load checks after it unchanged. Pinned by: `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` (`G4 memory trip ⇒ HELD memory_pressure`).
- **`loomwright/scripts/automate-lanes.d/status-read.sh`** — keep: the JSON document shape (`memory_pressure: ($mp == "true"), keep_awake_suggestion:`) and the verbose line (`" — memory_pressure: new launches held"`); only the value fed in changes: `--arg mp "$([ -e "$primary/.supervisor/automate/$parent.memory-pressure" ] && echo true || echo false)"` becomes a `_lanes_trip_live` call; the `score: N/M` parse stays (`sed -n 's/^- score: \([0-9]*\/[0-9]*\).*/\1/p'`). Mirror: `launch.sh`'s admission reads the same helper. Pinned by: `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` (new legs), `05-timeline-and-gate.sh` (`lane-status --json` shape).
- **`loomwright/scripts/automate-lanes.d/common.sh`** — keep: sourced by every `automate-lanes.d/` module, helpers are `_lanes_*` functions with no top-level side effects (`_lanes_salvage() { # <dir> <dest_parent> <label> — prints the destination`); the new `_lanes_trip_live` sits beside `lanes_proc_alive() {` (which stays the `ps -o lstart=` + command-match check for lane processes — unchanged), uses a `kill -0` probe as `launch.sh` / `remove.sh` do (`kill -0` occurs nowhere in `common.sh` today), and returns 0/1 only. Pinned by: `loomwright/scripts/test-automate-lanes-modules.sh` (it pins the subcommand → function dispatch map and the module split, not `common.sh`'s helper list — a new helper in the existing module needs no entry there; the function itself is pinned by `01-create-to-wait.sh`'s new legs).
- **`loomwright/scripts/automate-helpers.d/plan-waves.sh`** — keep: `_PW_EXPLAIN` reset per call (`_PW_EXPLAIN=0   # reset per call`), the full-wave record (`printf 'wave %s full (--max %s)\n' "$k" "$max" >> "$_PW_TMP/why.$i"`), the conflict loop idiom (`_pw_conflicts "$_PW_TMP/s.$i.why" "$_PW_TMP/s.$m.why" | while IFS="$tab" read -r p a; do`), the deps record (`for j in $waitj; do printf 'depends on %s\n' "${DISP[j]}" >> "$_PW_TMP/why.$i"; done`); the header's reason list (`\`runs alone: Touches unknown (missing)\``) names every reason. Pinned by: `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` (X1 legs, exact output).
- **`loomwright/scripts/automate-trail.d/sweep.sh`** — keep: exit 0 fail-SAFE, every read failure keeps (`SW_LIVE_STATE=fail`), the once-per-sweep read (`[ -z "$SW_LIVE_STATE" ] || return 0`) for the dry run, the `_sw_live` return codes (`elif [ "$lrc" -eq 2 ]; then v="liveness unverifiable (lsof absent or failing)"`); fix sites `function flush() { if (n > 1 && path != "")` and `if [ -z "$v" ] && git -C "$SW_PRI" worktree remove "$p" >/dev/null 2>&1; then`; seam `LSOF="${LOOMWRIGHT_LSOF_BIN:-lsof}"` (in `automate-trail.sh`). Pinned by: `loomwright/scripts/test-automate-trail.d/06-sweep.sh` (`lsof -a -d cwd -F pn` stub).
- **`loomwright/scripts/janitor-report.sh`** — keep: the act guard order (`[ -n "$ids" ] || { echo "$JR_ME: act — no row id given" >&2; jr_usage >&2; return 2; }`) and the malformed arm (`*) case "$a" in *[!A-Za-z0-9-]*) echo "$JR_ME: act — malformed row id $a" >&2; return 2 ;; esac`); the non-interactive guard untouched. Pinned by: `loomwright/scripts/test-janitor-report.sh`.
- **`loomwright/scripts/setup-memory.sh`** — keep: the name is the NEXT argument even when option-shaped (`[ $# -ge 2 ] && { VB_NAME="$2"; shift; }`), the refusal block shape (`echo "setup-memory: valid-branch takes only a name (got --branch-mode / --ledger / --allow); nothing was judged" >&2`), exit 0 in every non-`valid-branch` path. Pinned by: `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh` (`(vb)` legs).
- **`loomwright/scripts/meta-sync.d/commands.sh`** — keep: the retry loop (`warn "rejected (attempt $attempt/$MAX_ATTEMPTS) — re-fetching and recomputing"`), `die "push_failed — rejected $MAX_ATTEMPTS times; nothing forced, meta-base untouched"`, tree_guard and scrub before the commit; fix site `if g push -q origin "$commit:refs/heads/$BRANCH" 2>"$WORK/push.err"; then`; `R` is `R="$REMOTE_SHA"` (`managed.sh`). Pinned by: `loomwright/scripts/test-meta-sync.d/01-sync-core.sh`.
- **`loomwright/scripts/meta-sync.d/scrub.sh`** — keep: the slug extraction (`grep -ioE '(github\.com|gitlab\.com|bitbucket\.org)[/:](repos/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+'`), the exact-line allow check for an ordinary slug (`grep -F -x -q -e "$s" "$ALLOW_FILE" 2>/dev/null || { bad=1; break; }`), `RESERVED_OWNERS` as data; fix sites `case "$RESERVED_OWNERS" in *" $owner "*) continue ;; esac` and `case "${s#*/}" in *[!.]*) : ;; *) continue ;; esac`. Pinned by: `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh` (`forge_slug`).
- **`loomwright/scripts/meta-sync.d/lock.sh`** — keep: the reclaim bound (`[ "$depth" -le 4 ] || return 0`), the O_EXCL stamp idiom, `RECLAIMED` semantics; fix site `die "locked — another meta-sync (pid ${holder:-unknown}) holds $LOCK_DIR; waited ${LOCK_WAIT}s, nothing was changed"`. Pinned by: `loomwright/scripts/test-meta-sync.d/01-sync-core.sh` (`reclaimed a stale lock`).
- **`loomwright/scripts/meta-sync.d/learning-twin.sh` / `loomwright/scripts/read-system-contract.sh`** — not modified; the new drift pin reads `twin_field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }` and `field() { printf '%s' "$1" | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"; }` (and both `prev="GENESIS"`). Pinned by: `loomwright/scripts/test-meta-sync.d/04-learning-stores.sh`.
- **Appended-only test files** (`04-fleet-closeout-to-optout.sh`, `02-readiness-to-convert.sh`, `05-finalize-closeout-others.sh`, `test-lane-sampler.sh`, `01-create-to-wait.sh`, `13-plan-waves.sh`, `06-sweep.sh`, `test-janitor-report.sh`, `05-branch-mode-consent.sh`, `01-sync-core.sh`, `03-mutants-scrub-allowlist.sh`, `04-learning-stores.sh`) — keep: existing legs unchanged; each new leg reuses its suite's own fixtures and stubs (`ae`/`ae_lane` in `03-fixes-to-finalize.sh`, `sw_run` + the `lsof` stub in `06-sweep.sh`, `vb_run` in `05-branch-mode-consent.sh`, `og`/`put` in the meta-sync suites) rather than a new harness; `03-fixes-to-finalize.sh` rewrites AE4/AE4b/AE4d and Z-F5b in place with replacement assertions (the test-integrity guard: never an assertion removed without one).

## Closed enumerations touched

> Sibling grep at base `f071613abefa18cb4e4a94e2191364771db5e458`: `grep -rnF 'meta-push-failed' --exclude=CHANGELOG.md loomwright/ | grep -v /test-` → 30 hits in 16 files (the lane-marker kind the new `.closeout-leftover` marker joins).

- **`<run_id>.closeout-leftover`** (sibling: `<run_id>.meta-push-failed`) — must be named in:
  - `loomwright/scripts/automate-lanes.d/wave.sh` — the fleet-closeout per-lane checks (`mk="$path/.supervisor/automate/$run.meta-push-failed"`) and its header step 2 (`A \`.meta-push-failed\` marker ⇒`) — extend.
  - `loomwright/scripts/automate-lanes.d/remove.sh` — `lane-remove`'s refusals (`_refuse "meta-push failure marker is set"`) — extend.
  - `loomwright/scripts/automate-lanes.sh` — the header `Files` list — extend (one line).
  - `loomwright/skills/automate-loop/lanes.md` — §"Wave close" step 2 (`a \`merged\` lane is closed out by the backstop`) — extend (one sentence).
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — the `Single write` row — extend (the marker is a coordinator write into the lane).
  - `loomwright/scripts/janitor-report.sh` — enumerates `*.meta-push-failed` markers for its report (`for m in "$ad"/*.meta-push-failed; do`) — no change: a leftover marker is reported by `fleet-closeout`'s `human —` line on every `--resume`, which is the owner's surface for a lane; the janitor's row is for the parent run's own push failure.
  - `loomwright/scripts/automate-trail.sh`, `automate-helpers.sh` (its fail-SAFE subcommand list, `meta-entry and meta-push-failed are the fail-SAFE`), `automate-helpers.d/meta.sh`, `trail-pr.sh`, `automate-next-step.sh`, `docs/PITFALLS.md`, `docs/loop-inventory/automate-loop.md`, `docs/result-schemas/automate-run.md`, `skills/automate-loop/branch-mode.md`, `fixtures/automate-helpers-help/meta.golden` — no change: these describe the parent run's `trail-pr` push-failure marker (or its read-only reporter subcommand), not a lane marker kind list.

> Sibling grep: `grep -rnF 'headline-repro' --exclude=CHANGELOG.md loomwright/ | grep -v /test-` → 4 hits in 1 file (`readiness.sh` header line, the two row forms, the score loop) — all extend in place; no other surface enumerates the readiness row states.

> Sibling grep: `grep -rnF -- '--no-trail' --exclude=CHANGELOG.md loomwright/ | grep -v /test-` → hits in `automate-trail.sh` (usage header), `automate-trail.d/closeout.sh` (the emitter), `automate-helpers.sh` (the `#:  closeout` usage row), `fixtures/automate-helpers-help/hdr-trail.golden`, `automate-lanes.d/remove.sh`, `skills/automate-loop/helpers.md`, `per-item-loop.md`, `lanes.md` (prose naming closeout's flag).

- **`finalize-empty … [--no-trail]`** (sibling: `closeout … [--no-trail]`) — must be named in:
  - `loomwright/scripts/automate-trail.sh` — the usage header (`#   finalize-empty <runfile>`) — extend.
  - `loomwright/scripts/automate-helpers.sh` — the `#:` usage row `#:  finalize-empty   <runfile>` (its sibling `#:  closeout` row lists `[--no-trail]`) — extend.
  - `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` — the byte-for-byte golden of that usage block (`  finalize-empty   <runfile>`) — extend (hand-edited in the same change, pinned by `test-automate-helpers-dispatch.sh`).
  - `loomwright/scripts/automate-trail.d/closeout.sh`, `automate-lanes.d/remove.sh`, `skills/automate-loop/helpers.md`, `per-item-loop.md`, `lanes.md` — no change: they name closeout's own flag; `lanes.md` gains the mode-off sentence under F105 (which names `finalize-empty … --no-trail` as the lane's call), not a flag list.

> Sibling grep: `grep -nF 'tripped_utc' loomwright/scripts/lane-sampler.sh` → the header's trip-file line list (`line 1 \`tripped_utc: <ts>\``) and `write_trip`.

- **trip file line 3 `sampler_pid: <pid>`** (sibling: line 2 `sample: <the triggering sample line>`) — must be named in:
  - `loomwright/scripts/lane-sampler.sh` — the header `FILES` entry for `<id>.memory-pressure` (`line 2 \`sample: <the triggering sample line>\``) — extend with line 3 and the "removed on TERM" rule.
  - `loomwright/scripts/lane-sampler.sh` — `write_trip` — extend (the emitter).
  - `loomwright/skills/automate-loop/lanes.md` — the sampler paragraph — extend (one clause: holds while its sampler is alive; Subtask 1's edit).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` — F101 leftover marker ⇒ `human —`, no removal | delete the `.closeout-leftover` marker check in `lanes_fleet_closeout` in `loomwright/scripts/automate-lanes.d/wave.sh` |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` — F101 `lane-remove` refused on the marker | delete `_refuse "closeout leftover marker is set"` in `loomwright/scripts/automate-lanes.d/remove.sh` |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` — F101 marker written on a leftover | delete the marker write in the `closeout leftover:` branch of `lanes_convert_ready` in `remove.sh` |
| `loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh` — F105 `finalize-empty --no-trail` skips trail-pr | delete the `--no-trail` arm in `finalize_empty` in `loomwright/scripts/automate-trail.d/finalize.sh` |
| `loomwright/scripts/test-automate-helpers-dispatch.sh` — `--help` golden (`hdr-trail.golden`) names `finalize-empty … [--no-trail]` | delete `[--no-trail]` from the `#:  finalize-empty` usage row in `loomwright/scripts/automate-helpers.sh` |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` — F105 mode-off re-run finalizes (`## Status: done`) | flip the mode-off finalize call back to `fin="lane-convert-ready: finalize skipped — metadata mode off"` in `remove.sh` |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` — F109 not-ours lock named after release | delete the post-release `run-lock.sh status` read in `lanes_fleet_closeout` in `wave.sh` |
| `loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh` — F103 re-run commit message names the phase | flip `wave-end re-run` → `ready_for_release -> awaiting_merge (wave end)` in the `closeout`-phase message in `remove.sh` |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` — F111 `a$(id)b` refused | delete the `[A-Za-z0-9._/-]` class check beside `git check-ref-format --branch "$wb"` in `wave.sh` |
| `loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` — F068 echoed regenerate rule | delete the `build-capabilities.sh` conflict-rule `echo` in `lanes_wave_plan` in `wave.sh` |
| `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` — F077 n/a row not scored (`/4`) | flip `total=4` → `total=5` on the no-repro path in `loomwright/scripts/automate-lanes.d/readiness.sh` |
| `loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh` — F133 `2 skipped` is not NOT-RUN | flip `nrl()` back to `return nrv(s) || ph(s, "skipped")` in `readiness.sh` |
| `loomwright/scripts/test-lane-sampler.sh` — F351 trip line 3 `sampler_pid:` / TERM removes the trip | delete the `sampler_pid:` printf in `write_trip` (resp. the `rm -f "$TRIP"` in the TERM trap) in `loomwright/scripts/lane-sampler.sh` |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` — F351 dead-sampler trip ignored, live/legacy trip holds | flip `_lanes_trip_live` → `[ -e` (the bare existence test) in `_lanes_admission` in `loomwright/scripts/automate-lanes.d/launch.sh` |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` — F351 `lane-status --json` `memory_pressure` false on a dead-sampler trip | flip `_lanes_trip_live` → `[ -e` in the `--arg mp` read in `loomwright/scripts/automate-lanes.d/status-read.sh` |
| `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` — F351 legacy trip (no `sampler_pid:`) still holds | delete the no-`sampler_pid:`-line ⇒ live branch in `_lanes_trip_live` in `loomwright/scripts/automate-lanes.d/common.sh` |
| `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` — F023 full wave + conflict both named | delete the `_pw_conflicts` loop in the full-wave `--explain` branch in `loomwright/scripts/automate-helpers.d/plan-waves.sh` |
| `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` — F025 deps-unmet + Touches unknown both named | delete the `runs alone: Touches unknown` printf in the deps-unmet branch in `plan-waves.sh` |
| `loomwright/scripts/test-automate-trail.d/06-sweep.sh` — F137 apply re-reads liveness | delete the `SW_LIVE_STATE=""` reset before `git worktree remove` in `loomwright/scripts/automate-trail.d/sweep.sh` |
| `loomwright/scripts/test-janitor-report.sh` — F353 `act ''` is a usage error | delete the `'')` arm in `jr_act` in `loomwright/scripts/janitor-report.sh` |
| `loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh` — F058 extra positional refused | delete the extra-argument refusal in the `valid-branch` block in `loomwright/scripts/setup-memory.sh` |
| `loomwright/scripts/test-meta-sync.d/01-sync-core.sh` — F003 deleted-between-fetch-and-push branch stays absent | flip `--force-with-lease="refs/heads/$BRANCH:$R"` → nothing (plain refspec) in `loomwright/scripts/meta-sync.d/commands.sh` |
| `loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh` — F004 `orgs/<owner>` and `<owner>/...` hit | flip the `orgs|users|sponsors` next-segment owner read back to `continue` in `loomwright/scripts/meta-sync.d/scrub.sh` |
| `loomwright/scripts/test-meta-sync.d/01-sync-core.sh` — F005 dead-holder hint | delete the `the holder is not running: remove` suffix in `acquire_lock`'s `die` in `loomwright/scripts/meta-sync.d/lock.sh` |
| `loomwright/scripts/test-meta-sync.d/04-learning-stores.sh` — F134 drift pin | flip `\"([^\"]*)\"` → `\"([^\"]+)\"` in `twin_field` in a scratch copy of `loomwright/scripts/meta-sync.d/learning-twin.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Lanes, fleet close-out, finalize and readiness (F101 F105 F109 F103 F111 F068 F076 F262 F077 F133) | AC1, AC2, AC3–AC10, V1 | 14 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Sampler admission, plan-waves explain, sweep, janitor and setup-memory validators (F351 F023 F025 F142 F137 F138 F353 F355 F058) | AC1, AC2, AC11–AC16, V1 | 14 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 3 | Meta-sync push lease, scrub owners, lock hint, twin drift pin + release fragment (F003 F004 F005 F134) | AC1, AC2, AC17–AC20, V1, V2 | 6 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-03-lanes.md"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/wave.sh", name: "closeout-leftover"}
  - {kind: "symbol", path: "loomwright/scripts/automate-trail.d/finalize.sh", name: "--no-trail"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/readiness.sh", name: "not scored"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.d/wave.sh"
  - "loomwright/scripts/automate-lanes.d/remove.sh"
  - "loomwright/scripts/automate-trail.d/finalize.sh"
  - "loomwright/scripts/automate-trail.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden"
  - "loomwright/scripts/automate-lanes.d/readiness.sh"
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/skills/automate-loop/lanes.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh"
  - "loomwright/scripts/test-automate-lanes.d/03-fixes-to-finalize.sh"
  - "loomwright/scripts/test-automate-lanes.d/02-readiness-to-convert.sh"
  - "loomwright/scripts/test-automate-trail.d/05-finalize-closeout-others.sh"
  - "docs/evidence/dismissed-followups-03-lanes.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-03-engine.md"}
  - {kind: "symbol", path: "loomwright/scripts/lane-sampler.sh", name: "sampler_pid"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/common.sh", name: "_lanes_trip_live"}
  - {kind: "symbol", path: "loomwright/scripts/janitor-report.sh", name: "empty row id"}
requires: []
lanes:
  - "loomwright/scripts/lane-sampler.sh"
  - "loomwright/scripts/automate-lanes.d/common.sh"
  - "loomwright/scripts/automate-lanes.d/launch.sh"
  - "loomwright/scripts/automate-lanes.d/status-read.sh"
  - "loomwright/scripts/automate-helpers.d/plan-waves.sh"
  - "loomwright/scripts/automate-trail.d/sweep.sh"
  - "loomwright/scripts/janitor-report.sh"
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-lane-sampler.sh"
  - "loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh"
  - "loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh"
  - "loomwright/scripts/test-automate-trail.d/06-sweep.sh"
  - "loomwright/scripts/test-janitor-report.sh"
  - "loomwright/scripts/test-setup-memory.d/05-branch-mode-consent.sh"
  - "docs/evidence/dismissed-followups-03-engine.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-03-meta-sync.md"}
  - {kind: "file", path: "changelog.d/dismissed-followups-03-lanes-and-meta-sync-defects.md"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.d/commands.sh", name: "--force-with-lease"}
requires: []
lanes:
  - "loomwright/scripts/meta-sync.d/commands.sh"
  - "loomwright/scripts/meta-sync.d/scrub.sh"
  - "loomwright/scripts/meta-sync.d/lock.sh"
  - "loomwright/scripts/test-meta-sync.d/01-sync-core.sh"
  - "loomwright/scripts/test-meta-sync.d/03-mutants-scrub-allowlist.sh"
  - "loomwright/scripts/test-meta-sync.d/04-learning-stores.sh"
  - "docs/evidence/dismissed-followups-03-meta-sync.md"
  - "changelog.d/dismissed-followups-03-lanes-and-meta-sync-defects.md"
external_requires: []
```

Subtask 1's `automate-trail.sh` and `automate-helpers.sh` lanes cover only one usage line each (the `finalize-empty <runfile> [--no-trail]` row) plus the regenerated `hdr-trail.golden`; dispatch, `gate-eval` and the merge executor are untouched. Subtask 3's fragment is the PR's only `changelog.d/` entry and covers all three groups at the group level (one clause per group naming what its fixes do, no per-finding fixed/recorded counts — a sibling worker's fix→recorded deviation then leaves it true; the three evidence files are the per-finding record Phase 4.5 reads; the version bump itself is folded by `bash scripts/bump-version.sh` at release, never hand-edited).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
Subtask 2 (independent)
Subtask 3 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel)
- **Recommended workers:** 3
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 23 findings over ~32 files exceed one worker's context | MEDIUM | `context-bound` split into 3 zero-overlap groups; each group writes its own evidence file so no shared file exists |
| Feasibility (Phase 2.5): regression legs, `launch.sh`, `automate-trail.sh`, the three `meta-sync.d/` modules and the evidence files sit outside the requirement's `## Touches` | MEDIUM | Asked once at Launch Pad Phase 6 (`LP-SCOPE`) before save |
| Prior churn (postmortem ledger): `ARCHITECTURE_CONTRACTS.md`, `automate-lanes.sh`, `lanes.md`, `setup-memory.sh` and `plan-waves.sh` carry prior churn (`drain_churn`, `self_heal_churn`, `convention_mismatch`), with a `self_heal_miss` in prior rounds | HIGH | Doc edits are one row / one sentence each and cite instead of restating (the two advisory house rules); every behavioral fix carries a leg whose pre-fix red is recorded (AC2); workers run `ci-local.sh --affected` including the doc gates before hand-back |
| F105 runs `finalize-empty` inside a mode-off lane: its dry sweep and `trail-unstage` now execute in a lane clone | MEDIUM | `--no-trail` skips only the trail step; the sweep is dry and the clone is its own primary (`git-common-dir`); the AE legs assert the run file and no trail PR, and `05-finalize-closeout-others.sh` pins `--no-trail` on its own |
| F101's marker makes a leftover lane wait for a hand fix; a leftover that cannot be fixed by hand (e.g. `requirement … not found`) holds the lane until the owner removes the marker | LOW | The `human —` line names the marker path and the fix; `lane-remove --abandon` is unchanged for `gone` lanes; documented in `lanes.md` |
| F077 changes the score total; a reader hard-coded to `/5` would misread `4/4` | LOW | `status-read.sh` parses `N/M` generically (verified); the worker greps `/5` across `automate-lanes.d/`, `lanes.md`, the `/lanes` addon and `loomwright-lanes/README.md` (its `ready 5/5` illustration is a pass-through example, not a parser) before hand-back |
| F133 loosens a fail-closed phrase match by one case (`<digit> skipped`) | LOW | Only the count-prefixed form is excluded; bare `skipped` and heading rules keep NL; both sides pinned by legs |
| F351's admission liveness read trusts `sampler_pid:` from a file in the primary's `.supervisor/automate/` | LOW | A missing/unparsable pid line holds (fail-closed); `kill -0` on a reused pid at worst holds one launch until the next sample; the sampler's own TERM trap is the primary fix |
| F003's lease could refuse a legitimate push when the remote moved between fetch and push (previously a plain rejection on non-ff anyway) | LOW | The existing retry loop re-fetches and recomputes up to `MAX_ATTEMPTS`; the deleted-branch leg and the normal-push leg both run |
| F023's full-wave conflict lines could change an X1 leg's exact output if its fixture happens to share a path | LOW | The worker runs the X1 legs first; AC12 requires them byte-identical and adds a new fixture for the co-existing case |
| Pre-fix-red proof (AC2) needs the base-commit script; a worktree has it at its base | LOW | Run each new leg against `git show f071613:<path>` copied to a scratch dir; record the red line in the evidence file |
| A concurrent session in this checkout can sweep uncommitted edits (project memory) | LOW | Workers run in their own worktrees; commit per finding group |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 1
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-10-dismissed-followups-03-lanes-meta-sync.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-10T07:50:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/865
- **Branch:** feature/dismissed-followups-03-lanes-meta-sync
- **Files changed:** 49
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unarmed (marker_missing)
- **Summary:** 23 dismissed-followups/03 findings dispositioned across three evidence files (lanes / engine / meta-sync), with regression legs; v17.35.2 folds the 02 and 03 fragments. Phase 4.5 ran 3 review→fix rounds on the F133 'N skipped' tally exemption in readiness.sh (step number read as tally → deny-list → allow-list → counted-result chain) plus two CI ratchet fixes (pipefail grep -q, fixed sleep). Round 3's MEDIUM was fixed in 20163a5 on the final iteration and not re-reviewed; 3 LOW findings dismissed below the MEDIUM floor.

## Not verified
- **ARCHITECTURE_CONTRACTS.md meta-sync prose** — now less precise after the lease change; subtask 1's lane, left by subtask 3 (subtask 3)
- **Real GitHub remote under the push lease** — not exercised; local bare remote only (subtask 3)
- **Live /automate --parallel wave close in a real repo** — not exercised; suite fixtures only (subtask 1)
