# 11 — The post-park lifecycle, owned by the engine: a trail PR at every park and at run end, and a merge watcher that runs a scripted close-out when the owner merges

## Status: pending

> **Merged item (2026-09-29).** Combines the former `11-automated-trail-pr.md` (Part A) and
> `14-merge-detected-closeout.md` (Part B) on the owner's instruction. They are one lifecycle — park → trail PR →
> owner merges → close-out — touch the same surfaces (`scripts/automate-helpers.sh`, `skills/automate-loop/SKILL.md`
> §1.5/§6/§8/§9/§12, `commands/automate.md`, one test suite) and share fixtures (stubbed `gh`, fixture worktrees).
> Part B's close-out calls Part A's `trail-pr`, so the former 14's "if 11 is not merged yet, skip" workaround is
> gone. **Planning note:** this is larger than one worker's context — Launch Pad should split it into two
> sequential subtasks inside ONE PR (`Split reason: context-bound`): Subtask 1 = Part A, Subtask 2 = Part B
> (`requires:` Subtask 1's `trail-pr`).

> **Origins.**
> - **Part A (2026-09-28, recovered 2026-09-29).** Proposed in the item-04 session of run
>   `automate-2026-09-26-115755` after the owner asked why the run records needed a manual cleanup PR (#291):
>   *"at each park or at run end, the engine opens a trail PR like this one from a worktree, and releases the lock
>   only after it's done."* Asked twice, never written down; recovered from the transcript when the owner asked
>   where item 11 was. Five more trail PRs were hand-built in the meantime (#293, #295, #298, #300, #303), and #303
>   shipped two hand-reconstructed result sidecars that drifted from `RESULT_SCHEMAS.md` (caught only by the
>   `claude-review` bot, fixed in d8662b3).
> - **Part B (2026-09-29).** Owner: *"we have a cleanup flow when we merged the PR. It only triggers when I ask it,
>   like 'it's merged'. I want that automated — we can use the hooks, right?"* Then: *"in the Claude desktop app I
>   see an indicator when a PR merged … check how Claude desktop is checking that."* Findings, verified in-session:
>   (1) the close-out exists only as a memory note (`automate-merge-closeout-before-next-item`), not in the spec;
>   (2) no Claude Code hook can observe a merge done in the GitHub web UI — hooks fire on session events only;
>   (3) the desktop app's PR indicator is the app's own PR monitor (`mcp__ccd_pr__*`), which documents waking a
>   session only on CI failures, merge conflicts and review comments — a merge only triggers
>   `auto_archive_on_close` — and it does not exist under the CLI or detached `claude -p`.

## Problem

**Part A — nothing commits the run trail.**
1. Since #243 the trail is tracked (`.gitignore` re-includes `.supervisor/automate/*.md`, `.supervisor/jobs/done/`,
   `jobs/failed/`, `.supervisor/requirements/`, and — repo-allowlist-gated — `.supervisor/postmortem/results.jsonl`),
   but `grep -ciE 'trail (pr|commit)|trail-pr'` over `skills/automate-loop/SKILL.md`,
   `scripts/automate-helpers.sh` and `commands/automate.md` = **0**. Every trail commit so far has been a manual
   chore PR: #246, #268, #291, #293, #295, #298, #300, #303.
2. **The manual step is where the trail gets damaged.** Tracked trail files written on a feature branch are deleted
   from the working tree on `git checkout main`, and `git pull` refuses over hand-restored copies (memory
   `tracked-trail-vanishes-on-branch-switch`), so every close-out needs a hand-run reset. #303's sidecars were
   retyped rather than copied and dropped the v2 `rounds` field, used non-canonical `channels_scanned` names, added
   `ready_sha` (a `gate-eval` ctx key), and omitted `risk_classification.reasons`.
3. **No shape check exists on the sidecars** (`<run_id>.review-heal-result.md`, `<run_id>.supervisor-result.md`),
   even though `gate-eval` treats the first as ground truth for the drain's self-report.

**Part B — a safe-mode park is a dead end until a human speaks.**
4. At GATE, `READY` ⇒ `pause_reason: awaiting_merge` and the run STOPS (§9). §12 says a `paused` status stops the
   `/loop` driver too, so nothing re-ticks. §8's sentence "RECONCILE re-checks the PR each tick and resumes once it
   merges" describes a tick that never happens — a claim no mechanism backs.
5. **The post-merge close-out is a memory note, not a step.** `grep -ciE 'closeout|close-out|worktree (remove|cleanup)'`
   over `skills/automate-loop/SKILL.md`, `scripts/automate-helpers.sh`, `commands/automate.md` finds no post-merge
   cleanup. RECONCILE's only merge follow-up is `brief-repair`. Worktree + local-branch removal, `main` sync, and the
   trail update happen only when the owner types "merged" and the session remembers the note.
6. **The memory note's own safety guard is wrong for this repo.** It says remove a branch after checking it has
   "0 commits outside `origin/main`". PRs here are **squash-merged**, so a merged feature branch's commits are never
   ancestors of `origin/main` — `git branch --merged origin/main` does not list them (verified: none of the local
   `feature/*` / `fix/*` branches appear). A script built on that guard would either refuse every cleanup or, if
   loosened carelessly, delete unmerged work.

## Goal
When an `/automate` item parks, the engine commits its own trail as one PR from a worktree off fresh `origin/main`,
then releases the run-lock. When the park is `awaiting_merge`, the owner's only action is merging the PR on GitHub:
within a bounded poll interval the engine sees `MERGED`, runs one deterministic close-out (repair, cleanup, sync,
stamp, trail, check-off), records it in `## Progress`, and notifies — and still does **not** pick the next Queue
item without an explicit go. The owner never hand-builds a trail PR or resets their checkout again, and a sidecar
that does not match its schema cannot be committed.

## Scope (recommendation, not pre-decided)

### Part A — trail PR (Subtask 1)

**(a) A `trail-pr` subcommand in `scripts/automate-helpers.sh`**, spec'd in a new `skills/automate-loop/SKILL.md`
section (+ a §1.5 helper-table row) and called at each park (`awaiting_merge`, `escalated`, `limit_reached`,
`rate_limit`, `drain_died`, `token_ceiling`) and at termination (`## Status: done`), BEFORE the run-lock release. It:
creates a temporary worktree on `chore/<run_id>-trail[-<item>]` off `origin/main`; copies in only the trail paths
this run touched (derived from the run file's Queue items + their briefs + the two sidecars + the run file itself +
the ledger lines keyed by this run's `automate_key`), never a `git add -A`; commits; pushes; opens the PR (or pushes
to the already-open trail PR for this run); removes the worktree. Fail-SAFE (always exit 0, one `## Progress` line
naming the PR URL or the skip reason) — a trail failure must never block a park or change a gate decision.

**(b) The main checkout stops holding divergent trail copies.** Define how the checkout is left after the trail PR
opens so that `git checkout main && git pull` after the owner's merge needs no manual reset (e.g. restore the trail
paths to `HEAD` once they are safely on the trail branch, byte-compared first). Document the contract.

**(c) Sidecars are written VERBATIM, and shape-checked before commit.** The sidecars must be the raw emitted result
blocks (already the §6 step 2/3 contract — the engine must not re-type them). Add a shape check against
`docs/RESULT_SCHEMAS.md` (required keys present, `channels_scanned` from the canonical vocabulary, no non-schema keys
such as `ready_sha`, `risk_classification.reasons` present when the object is) that `trail-pr` runs first; a failing
sidecar is NOT committed and is reported in `## Progress`.

**(d) Idempotent + resumable.** A crash between commit and PR-open, or a `--resume`, reconciles against the remote
trail branch/PR and never opens a second PR for the same park.

**(e) Never merges.** The trail PR is opened for a human; the `gh pr merge --squash` single-executor invariant
(CLAUDE.md §Failure-Mode Invariants) is untouched.

### Part B — merge-detected close-out (Subtask 2, requires `trail-pr`)

**(f) A `closeout` subcommand in `scripts/automate-helpers.sh`**, spec'd in `skills/automate-loop/SKILL.md` (new §6
sub-section + a §1.5 helper-table row): `closeout <runfile> <item> <pr_url>`. Order:
1. **Evidence-positive gate** — reuse `reconcile-item`; anything but `merged` ⇒ `skipped — <reason>` and stop.
2. **`brief-repair <item> <pr_url>`** (existing, unchanged).
3. **Local cleanup, squash-safe guard.** For the PR's head branch and any worktree checked out on it: remove only if
   (i) the worktree has no uncommitted changes (`worktree-salvage.sh` first, as every plugin-owned removal already
   does), AND (ii) the local branch tip equals the PR's `headRefOid` from `gh pr view --json headRefOid` (nothing
   local that the merge did not include). Use `git branch -D` only after (ii) passes — `-d` refuses squash-merged
   branches by design. Never touch a branch or worktree not tied to this PR.
4. **Sync** — `git checkout main && git pull --ff-only` in the primary checkout; on refusal (e.g. divergent trail
   copies) record the skip, do not reset.
5. **Requirement stamp** — append the `<!-- loomwright:requirement-closeout -->` footer (existing self-heal-advisory
   completion-tail contract); never rewrite the heading.
6. **Trail** — call Part A's `trail-pr` to push the close-out's changes to the run's trail PR.
7. **Check off** — `queue-checkoff` with the correct arity (the third argument is a SKIP REASON, so passing `done`
   writes `# skipped: done`), then one `## Progress` line per step's outcome.
Fail-SAFE: always exit 0; each step prints one `repaired|removed|synced|stamped|trailed|skipped — <reason>` line.
Idempotent: re-running on an already-closed-out item is all `skipped — already …` lines.

**(g) A merge watcher armed at the `awaiting_merge` park.** Recommended shape: a detached, pure-bash
`scripts/automate-merge-watch.sh <runfile> <item> <pr_url>` launched at GATE when the park is written — no Claude
session, no tokens, survives the session ending, identical under CLI / desktop / headless. It polls
`gh pr view --json state` on an interval (default 60s, back-off on `gh` errors), and:
- `MERGED` ⇒ runs `closeout`, fires the existing notifier (`notify-desktop.sh` / `send-webhook.sh`), exits;
- `CLOSED` ⇒ records `gone` in `## Progress`, notifies, exits (no cleanup — §4's `gone` rules stand);
- lifetime cap (default 72h) ⇒ exits with a `## Progress` line; `/automate --resume` still works as today.
Single instance per run (pid/marker under `.supervisor/automate/`, stale-pid safe); `/automate --resume` and
SessionStart detect a live watcher instead of starting a second one. **Alternative to weigh in planning:** an
in-session `Monitor` until-loop — simpler, but dies with the session and is not verified to exist headless.

**(h) Resume path runs the same close-out.** §6 step 1 RECONCILE: when `reconcile-item` returns `merged` for an
`awaiting_merge`/`escalated` item, call `closeout` (which subsumes the current `brief-repair` call there) before
anything else. So a watcher that expired, or a machine that was off, still converges on the next `--resume`.

**(i) Fix the §8 sentence** to describe the real mechanism (the watcher + resume), not a tick that does not exist.

**(j) Retire the memory note's procedure** once shipped — the note should point at `closeout`, and its wrong
"0 commits outside origin/main" guard must be corrected there too.

## Acceptance criteria

**Part A**
- [ ] Each park path and the run-end path invoke `trail-pr` before `run-lock.sh release`; asserted by a test that
      stubs `gh`/`git push` and checks call order.
- [ ] `trail-pr` stages only the run's trail paths (a stray untracked or unrelated modified file in the checkout is
      NOT committed — fixture test).
- [ ] Re-running `trail-pr` for the same park (crash/resume) opens no second PR (stubbed `gh pr list` fixture).
- [ ] A sidecar missing `rounds`, or carrying `ready_sha`, or with `risk_classification` lacking `reasons`, fails the
      shape check and is not committed (three fixture legs + a valid-sidecar positive control).
- [ ] After a simulated owner merge, `git checkout main && git pull` in the fixture checkout succeeds with no manual
      reset.
- [ ] `trail-pr` always exits 0; a `gh` failure produces a `## Progress` skip line and the park still completes.

**Part B**
- [ ] `closeout` on a fixture repo with a squash-merged PR (stubbed `gh`: `MERGED`, `headRefOid` = local tip)
      removes that PR's worktree and local branch, leaves an unrelated branch and worktree untouched.
- [ ] Guard legs, each a fixture: local tip ≠ `headRefOid` ⇒ branch kept + `skipped`; dirty worktree ⇒ salvaged
      before removal (or kept — whichever the plan picks, asserted); `gh` says `OPEN` ⇒ nothing removed.
- [ ] `closeout` is idempotent (second run all `skipped — already …`) and always exits 0, including with `gh`
      absent / failing.
- [ ] `closeout` step 6 calls `trail-pr` (spy/stub asserted), not an inline re-implementation.
- [ ] `queue-checkoff` is called so the item reads `- [x] <path>` — never `# skipped: done` (asserted on the file).
- [ ] The watcher: stubbed `gh` flipping `OPEN → MERGED` ⇒ exactly one `closeout` run + one notify, then exit;
      `CLOSED` ⇒ no cleanup, `gone` line; lifetime cap ⇒ clean exit; a second launch for the same run does not start
      a second poller.
- [ ] RECONCILE on `--resume` with an already-merged `awaiting_merge` item runs `closeout` before PICK (call-order
      test with stubs).
- [ ] §8 no longer claims a per-tick re-check that the `/loop` driver does not perform.

**Both**
- [ ] Neither `trail-pr`, `closeout` nor the watcher ever runs `gh pr merge` or picks/RUNs a Queue item. The
      `gh pr merge --squash` positive grep (CLAUDE.md §Failure-Mode Invariants) still resolves to exactly the same
      5 surfaces. No new agent/command/skill/hook.
- [ ] `commands/automate.md` mirrors only the surface (agent↔command mirror rule); `docs/RESULT_SCHEMAS.md`
      §AUTOMATE_RUN updated for any new run-file line.
- [ ] New scripts are bash-3.2 safe (no `timeout`, BSD `stat`/`date`/`sed`), validated with `bash file.sh`.
- [ ] Full test loop green — `loomwright/scripts/test-*.sh`, adapter tests, root `scripts/test-*.sh`,
      `scripts/check-vendor-coupling.sh` (after `git add`), `scripts/check-doc-currency.sh`; hermetic
      (`hermetic-test-env.sh` as the first executable line of every new test).

## Out of scope
- Auto-merging the trail PR or the feature PR (a human merges; `--auto-merge` already merges at the gate and runs
  SYNC itself — this item is safe mode's missing half).
- Picking the next Queue item automatically after a merge. The owner's explicit-go rule stands.
- Committing trail for runs outside `/automate` (direct `/supervisor` or `/autonomous`).
- Changing which paths are tracked (`.gitignore` stays as is).
- Using the Claude desktop app's PR monitor (`mcp__ccd_pr__set_monitor` / `<ci-monitor-event>`) as a trigger. It is
  desktop-only and does not document a merge event. A one-off probe (enable `auto_fix` on a trail PR, merge, see
  whether an event arrives) may be run separately; if it fires, adding it as an OPTIONAL extra trigger is a follow-up.
- GitHub webhooks / a GitHub Action on `pull_request: closed`. A webhook needs a public listener or tunnel; an Action
  runs in the cloud and cannot remove local worktrees or read the local `.supervisor/` data.

## Risks
- **Deleting unmerged work.** The only acceptable guard is `gh` MERGED + local tip == `headRefOid` + clean
  worktree. Any fallback that infers "merged" from `git` ancestry is wrong under squash merges (Problem 6).
- **An unattended process with push rights.** The watcher pushes (via `trail-pr`) without a session present. Bound
  it: only this run's paths, only its trail branch, lifetime-capped, never a force-push.
- **Racing the owner.** If the owner is working in the primary checkout when the merge lands, `git checkout main`
  could disrupt them. `closeout` must refuse the sync (skip line) when the primary checkout has uncommitted changes
  or is on a branch other than the PR's head / `main`.
- **Orphaned watchers.** A crashed or forgotten poller is a silent `gh` caller. The pid marker + lifetime cap +
  SessionStart surfacing ("merge watcher running for #NNN since …") keep it visible.
- **Two remote writers.** The engine now pushes feature and trail branches; the trail branch name must not collide
  with feature branches or a concurrent run (the run-lock serialises runs per checkout only).
- **Postmortem ledger conflicts.** `results.jsonl` is append-only and shared; two trail PRs open at once would both
  append. "Only this run's `automate_key` lines" plus a rebase-on-conflict rule must keep it append-only.
- **Worktree reality.** Gitignored `.supervisor/` scratch does not exist in a fresh worktree (memory
  `gitignored-scratch-absent-in-worktrees`); copy from the main checkout by explicit path.
- **Size.** Two subcommands + a detached watcher + a shape check; hence the planning note's two-subtask split.

## Verified premises (main @ 4b4885a, 2026-09-29)
- 0 hits for trail-PR or post-merge close-out logic in `skills/automate-loop/SKILL.md`, `scripts/automate-helpers.sh`,
  `commands/automate.md`. The dispatcher's verbs: config-suppress, config-restore, config-orig, runfile-write,
  progress-append, queue-checkoff, remaining, ceiling-check, resolve-folder, resolve-backlog, resume-glob,
  reconcile-item, gate-eval, learning-emit, brief-repair, reconcile-status.
- Manual trail PRs merged: #291, #293, #295, #298, #300, #303 (this run) plus #246, #268 (earlier runs).
- `.gitignore` tracks `.supervisor/automate/*.md`, `jobs/done/`, `jobs/failed/`, `requirements/`, `memory/`.
- #303's first commit (437c9fe) sidecars drifted from `RESULT_SCHEMAS.md`; corrected in d8662b3.
- `skills/automate-loop/SKILL.md` §9: safe mode `READY` ⇒ `## Status: paused`, `pause_reason: awaiting_merge`.
  §12: `paused` (limit / awaiting_merge / escalated) stops the `/loop` driver. §8 claims RECONCILE "re-checks the
  PR each tick and resumes once it merges". §6 step 1 RECONCILE: on `merged`, only `brief-repair` runs.
- `hooks/hooks.json` events: SubagentStop, Stop, TaskCompleted, StopFailure, PostToolUse, PreToolUse, Notification,
  SessionEnd, SessionStart — none can observe a GitHub-side merge.
- `scripts/session-resume.sh`'s startup arm is offline by design ("no forge call, ever").
- `scripts/worktree-salvage.sh` exists and is the convention before every plugin-owned `git worktree remove`.
- `git branch --merged origin/main` lists none of the squash-merged `feature/*` / `fix/*` branches.
- Desktop PR monitor (`mcp__ccd_pr__set_monitor` tool description): `auto_fix` wakes the session "on CI failures,
  merge conflicts and review comments"; `auto_archive_on_close` archives the session "once the PR merges or closes".

<!-- loomwright:requirement-closeout -->
## Status: done_with_escalation
- **Completed:** 2026-09-30T03:17:39Z
- **Brief:** .supervisor/jobs/done/2026-09-30-post-park-lifecycle.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/305
- **Heal:** max_iterations_reached — 1 remaining
