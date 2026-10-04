# 05 — Lane coordinator: `/automate --parallel N`

## Status: parked (waits on S1 — write the spike's answers under "Spike findings" below, then set `## Status: pending`)

## Depends on
03
04
../agnostic-phase1/04-non-interactive-gates.md
../meta-sync-followups/01-untested-push-and-base-fallbacks.md
../meta-sync-followups/02-symlinked-file-under-requirements.md
../meta-sync-followups/03-untested-hardening-branches.md
../meta-sync-followups/04-scrub-safe-briefs-and-push-rehearsal.md
../meta-sync-followups/05-carry-the-learning-stores.md

## Also waits on (operator-run — not machine-read)
- S1 (two-lane spike) — its answers go under "Spike findings" before this item is un-parked.
- M2 (carry the learning stores to `loomwright-meta`) — its runbook is written by `meta-sync-followups/05` part D.
- Why the `meta-sync-followups/*` lines above were added (owner, 2026-10-03): lanes are separate clones, all
  pushing to `loomwright-meta`. They need the travelling allowlist, the two-writer conflict rules and the
  hardened push paths first. See `00-overview.md` § Order, amendment.

## Touches
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/read-token-ledger.sh
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/SKILLS_INDEX.md
loomwright/commands/automate.md
loomwright/commands/agent-help.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md

## Problem
One `/automate` run processes one item at a time: RUN took 1h14–4h37 per item across the last four run files, and
nothing else starts until that item's PR is merged and the owner resumes. Independent items (item 04 can now say
which) still wait in line.

## Goal
`/automate --parallel N` runs up to N independent items at once, each in its own isolated lane, tracked by one
coordinator. Without the flag, or with `--parallel 1`, no lane code runs at all.

## Design (decisions P1, P2, P4, P6, P8 in 00-overview)
- **Parallelism sits ABOVE the per-item loop.** A lane runs the existing loop for one item; the loop's contracts
  (§7 single drain + toggle, §3 run file) hold inside the lane. The only loop behaviour a lane changes is its
  terminal park — see Scope 5.
- **A lane is a local clone** at `<primary>-lanes/<run_id>/L<n>/` — its own primary checkout, so run lock,
  `state.md`, the `auto_review` toggle, the owned drain and the sidecars are lane-local.
- **The coordinator writes into a lane exactly once, at `lane-create`.** After launch it only reads.
- **Lane shape (P8)** is whichever S1 chose: (A) whole loop headless, or (B) brief-first — the coordinator runs
  Launch Pad for each wave item interactively in the primary, and the lane runs Supervisor + the owned drain.
  Write the chosen shape into this file before un-parking; do not build both.

## Scope
1. **`automate-lanes.sh`** (sibling of `automate-trail.sh`, dispatched from `automate-helpers.sh`):
   - **`lane-create <runfile> <item> <n>`**
     - clone; **set `origin` to the primary's GitHub URL before any fetch**; prune the stale `origin/*` refs a
       `--local` clone inherits;
     - `meta-sync.sh pull` (non-zero ⇒ abort the lane, remove the clone);
     - **carry over what a clone lacks** (all gitignored in the primary): `.supervisor/config.json`,
       `notify-config.json` — copied byte-for-byte; record in the lane table that `.claude/settings.local.json`,
       the rules stamp and Claude auto-memory do NOT carry (S1 question 5 says what that costs);
     - write the lane's intake as a ONE-LINE backlog doc naming the item's canonical path (never a copied
       requirement in another folder — closeout stamps and `brief-repair` match on the canonical path);
     - assign the lane run id `<parent_run_id>-L<n>` (run ids have one-second resolution; lanes minting their own
       can collide);
     - deterministic path; a leftover directory is salvaged then refused, never reused.
   - **`lane-launch <lane>`** — detached headless launch (nohup wrapper, `claude -p`, namespaced command,
     `CLAUDE_PID`/`CLAUDECODE` unset, a `.died` marker when the process exits without a terminal state) with:
     - an **explicit lane allowlist declared in this script** — NOT `dispatch-pr-review.sh`'s review allowlist,
       which cannot edit files. The list is the minimum S1 found sufficient, with `gh pr merge`, `--admin`,
       `git push --force` and pushes to the base branch in `--disallowedTools`;
     - `--plugin-dir` pinned to the coordinator's `CLAUDE_PLUGIN_ROOT`, so a lane never runs an older installed
       engine than the coordinator;
     - refusal to launch when the CLI does not advertise a pinnable permission regime.
   - **`lane-status <runfile>`** — one line per lane: item, path, status, PR — read from the lane's run file and
     reconciled against `gh`.
   - **`lane-remove <lane>`** — only when the lane's metadata push reported nothing left, no meta-push failure
     marker is set (item 03 Scope 6), and the lane has no unpushed commits; salvage first. Never `rm -rf` a dirty
     lane. **Also refuses (amended 2026-10-03, owner, from S1):**
     - **while any process still lives in the lane.** That means the lane's merge watcher (its
       `<run_id>.merge-watch` marker pid, checked the way `automate-merge-watch.sh` checks it: `ps -ww` shows that
       script carrying the marker's `pr_url`, so a recycled pid is never trusted) and the lane's `claude -p` (the
       pid `lane-launch` records in the lane table, same command-line check). S1 lane A arms a watcher INSIDE its
       clone; deleting the clone first leaves an orphan whose closeout fails as `run file not found`. The refusal
       names the process. `lane-remove --stop` TERMs it first (KILL after 60s, as the watcher-replace path does)
       and then removes; there is no silent kill.
     - **while the lane is parked waiting for an answer** (`pause_reason: awaiting_input` from the ask-user relay,
       or any deferred tool call recorded in the lane table). A deferred session IS the pending question, and
       removing the lane discards it. The refusal names the question.
     - **A lane whose PR closed unmerged** (`gone`, item 06 Scope 8) stays refused until a human runs
       `lane-remove --abandon <lane>`. That form still salvages, still refuses a dirty or process-holding lane,
       and logs one `## Progress` line naming what was abandoned.
   - **`lane-launch` records what `lane-remove` checks:** the launched `claude -p` pid, its start time and the
     session id (read from the stream-json `system/init` event) in the lane table, so liveness and resume never
     depend on the launching session still being alive.
2. **Parent run file.** `## Run Config` gains `parallel: N`. The lane table is an UNTRACKED sidecar
   (`<run_id>.lanes`, a non-`.md` name). `## Current` names the wave.
3. **Lane run files must not pollute the parent's resume.** A lane's run file is a managed `.md` under
   `.supervisor/automate/` and reaches the primary on the next pull. Therefore lane closeout writes
   `## Status: done` to the lane run file BEFORE its metadata push, and `resume-glob` skips any run file whose
   title carries a lane id (`-L<n>`) — both, pinned by a test that a finished AND an unfinished lane file are
   never listed as a resumable run.
4. **The loop, per wave:** `meta-sync pull` → RECONCILE every lane → `plan-waves --max N` → (shape B: Launch Pad
   per item, interactive, in the primary) → `lane-create` + `lane-launch` per item → poll `lane-status`.
   - **The primary is locked for the whole wave**: hold `automate-lanes:<run_id>` in the primary's run lock so a
     plain `/automate` / `/supervisor` there is refused while lanes are live. Because the lock's liveness is the
     session's `claude` pid and a wave outlives a session, ALSO make PICK/INIT refuse when the `.lanes` sidecar of
     any run shows a live lane (`lane-status` reconciled) — the lock alone is reclaimable after the session ends.
   - Polling is a resumable step, not an in-session wait: each `/automate --resume` reconciles and reports; the
     skill's own "an in-session until-loop dies with the session" rule applies.
5. **Terminal park of a lane = `ready_for_release`, not `awaiting_merge`.** In a parallel run a READY lane writes
   `ready_for_release`, arms NO merge watcher, and its notify says "do not merge yet — wave open". Item 06 decides
   which lanes may then be merged as they are and which is the release lane. (This prevents a push racing an
   armed watcher or a human merge.) Until item 06 lands, the coordinator simply converts every
   `ready_for_release` lane to `awaiting_merge` at wave end — PRs then carry fragments and no bump, which P7
   allows.
6. **Parks are per lane.** A gate that fails closed, `escalated`, `died` park that lane only. A **rate-limit park
   in any lane pauses launching and reports all lanes** — the cap is account-wide; the owner decides whether the
   others continue.
7. **Dismissed findings.** `automate-dismissed.sh` scopes drafts and decisions to `<run_id>--*--dismissed-*.md` of
   the run file it is given, so lane drafts (keyed by the lane id) are invisible to the parent. Extend
   `dismissed-pending` / `dismissed-decide` to accept the parent run file and include its lanes' ids
   (`<parent>-L*`); make the `.dismissed-decisions` record a managed metadata path so it survives `lane-remove`.
8. **Token ceiling.** `read-token-ledger.sh` reads `<root>/.supervisor/logs/` under ONE root, and lane ledgers
   live in lane directories. `--max-tokens N` on a parallel run is passed to each lane as `N / lanes` (enforced
   inside the lane as today) and the parent total is summed with `--root <lane>` per lane. No "checked between
   waves" claim — a one-wave run would never be checked.
9. **`--auto-merge` with `--parallel N>1` is refused at INIT** (decision P1) — permanently in this queue.
10. **RESUME.** RECONCILE rebuilds lane belief from lane run files + `gh`; a lane directory that vanished is
    `gone` and needs a human.
11. **Tests** (`test-automate-lanes.sh`, hermetic, `claude` stubbed): create/launch/status/remove round trip;
    no flag ⇒ no lane code path entered; origin is the remote URL, not the primary path; config carried over;
    lane run id shape; one lane dying leaves the other's status unchanged; `lane-remove` refuses on unpushed
    metadata and on the failure marker; INIT refusal of `--auto-merge --parallel 2`; a plain `/automate` PICK in
    the primary is refused while a lane is live, including after the lock was reclaimed; lane run files never
    listed by `resume-glob`; parent `dismissed-pending` counts a lane's draft. `lane-remove` refuses on a live
    watcher, on a live `claude -p`, on `awaiting_input` and on `gone` without `--abandon`, and does NOT refuse on
    a recycled pid whose command line is not the lane's process. **Mutation controls:** dropping the `-L<n>`
    skip in `resume-glob` must fail; a coordinator write into a launched lane must fail a checksum test; deleting
    the live-process check (or the `awaiting_input` check) from `lane-remove` must fail its leg.
12. **Docs:** skill — a NEW §"Lanes" plus the non-goal and §8 wording ("one open PR per lane"), §11 concurrent-run
    paragraph; `commands/automate.md`; `agent-help.md`; `RESULT_SCHEMAS.md` §AUTOMATE_RUN (`ready_for_release`,
    `parallel`). `SKILLS_INDEX.md` in the same commit. No new agent.

## Non-goals
Merging and the release bump (item 06). More than one wave at once. Lanes on other machines. A `-runner` agent.
Making the rules stamp or Claude auto-memory follow a clone — record the gap; a lane whose requirement needs a
stamped countable rule check parks `rules_unstamped` and that is correct.

## Acceptance criteria
- A two-item fixture queue with disjoint `Touches` reaches two READY PRs in one `--parallel 2` run, each lane's
  run file showing its own `owned_drain_result` and `suppressed_default_dispatch: true`, both `ready_for_release`.
- `/automate` with no `--parallel`: the helper suites pass with no edit to existing assertions and no lane
  directory is created.
- Killing one lane's process leaves the other running and shows that lane as `died`.
- Full test loop + root checks green.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch; `<passed>/<total>` and `SKIP` counts for both.
2. **Unchanged path (no flag):** `git diff --stat origin/main -- loomwright/scripts/test-automate-helpers.sh
   loomwright/scripts/test-automate-trail.sh loomwright/scripts/test-dispatch-pr-review.sh` shows only ADDED test
   groups (no changed assertion). The skill/command prose diff is confined to new flag-gated sections plus the
   named one-line edits — paste `git diff --stat` and say so. Then ONE real single-item `/automate` on this repo:
   no lane directory, no `.lanes` sidecar, no `parallel:` line.
3. **Invariant checks, pasted:** the positive-form `gh pr merge --squash` grep resolves to the same five surfaces;
   `git grep -nE 'gh pr merge|--admin' loomwright/scripts/automate-lanes.sh` shows only the DISALLOW list.
4. **Running system:** `/automate --parallel 2` on two real, disjoint, small items. Paste `lane-status` at launch
   and at the end, each lane's `## Current`, `run-lock.sh status` from the primary and each lane while both run,
   and the refusal of a second `/automate` started in the primary meanwhile. Kill one lane once; paste the result.
5. **Leak check:** after the run, `git worktree list`, `ls <primary>-lanes/`, `pgrep -lf 'claude -p'`,
   `pgrep -lf automate-merge-watch`, the primary's `.supervisor/config.json` checksum and `git status --porcelain`
   are as before the run. The same check ships as `lane-status --leaks` (amended 2026-10-03), so the Fleet
   closeout (item 06) prints it rather than leaving it to a validation step.
6. **A failure this must catch:** the two mutation controls in Scope 11, shown failing.
7. **Rollback:** `git revert`. A run with live lanes is finished or abandoned first: `lane-status`; close or merge
   each lane PR by hand; metadata push in each lane; remove the lane directories. Written in the PR body.

## Spike findings
_(fill in from S1 before un-parking: isolation; pre-flight classification with and without the sibling PR open;
where a headless lane stops; state missing in a clone; contention; the chosen lane shape and the exact allowlist)_

## Verified premises (re-check before starting)
- `run-lock.sh` "resolve root" block and `build-state.sh` "Worktree-safe anchoring" block; 12 non-test scripts
  match `git worktree list --porcelain`.
- `agents/launch-pad.md` flag table: `--non-interactive` is "currently wired for exactly TWO Phase 6 gates, both on
  the NEEDS_HUMAN path" — the ordinary Phase 6 save/refine/discard ask has no non-interactive branch. That is what
  `agnostic-phase1/04` fixes and why shape A depends on it.
- `automate-dismissed.sh` matches `"$run_id"--*--dismissed-*.md` (its draft-name header and the `case` in its
  scan).
- `automate-loop/SKILL.md` §6: fix-now is offered only before the merge watcher is armed, so no push can race it;
  and the note that an in-session wait loop dies with the session.
- Red-team report, NOT re-verified by the author — check each before relying on it: `dispatch-pr-review.sh`'s
  `build_allowed_tools()` is review-only; `read-token-ledger.sh` reads one root; `closeout` never writes
  `## Status: done` to a run file; the rules stamp is keyed by git-common-dir; the ledger allowlist lives in
  gitignored `.supervisor/config.json`.

## Status note
Parked until S1 is run. Do not start from this file as written.
