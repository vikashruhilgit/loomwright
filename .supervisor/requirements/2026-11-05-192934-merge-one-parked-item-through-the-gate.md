# Merge one parked awaiting_merge item through the existing gate

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/842

**Story: Merge one parked awaiting_merge item through the existing gate** (type: story)

**As an** owner (or Loomwright Studio's opt-in "merge when ready" playbook) with an `/automate` item parked `awaiting_merge`,
**I want** one documented command that puts that item through the existing `--auto-merge` gate,
**so that** a safe-mode run can finish one reviewed item with no hand edits and no second merge path.

Source: GitHub issue vikashruhilgit/loomwright#829. It blocks two Studio phase 8 items.

## Problem

Safe mode parks a ready PR, and from there the docs name only a human merge. Trying `--resume <run> --auto-merge` on studio-sandbox PR 6 (17.31.0) parked again without merging. A mode check on the resume path would not fix it, because four things are in the way.

## Evidence (read on origin/main at 17.31.0, 2026-11-05)

Line numbers drift, so search for the named functions.

- **Routing:** `ns_reconcile` sends an open PR to `ns_reconcile_open` then `ns_open_pr_park` with no mode check. `gate-eval` is reached only through `ns_after_validation`, after a drain (`scripts/automate-next-step.sh`).
- **`--resume` erases the gate's inputs:** the resume entry runs `NS_STATE='{}'`, wiping `ready_sha`, `drain_result` and `termination_reason` from `<run_id>.next-step.json`. `ready_sha` exists nowhere else: not in the run file, not in `<run_id>.review-heal-result.md` (checked on run automate-2026-11-04-220637). Condition 2 would therefore always park `head_sha_moved`.
- **Condition 7 pins the checkout:** `gate_eval` parks `rules_gate_head_mismatch` unless `git -C <root> rev-parse HEAD` equals the live head, and the driver never checks anything out. That holds right after a drain but not once the owner has moved back to `main`.
- **The normal merge tail breaks two criteria:** `ns_terminate` returns `running` when items remain under the limit, so the loop continues. `ns_sync` closes out with `--no-trail`, and `ns_terminate` writes the trail only when no items remain, so stopping after it strands the trail.
- **The silent no-op:** `--resume --auto-merge` on a parked item records `flag_mode: auto-merge` while `## Run Config` still reads `mode: safe`, and nothing tells the owner it did nothing.
- **The gate cannot see late findings:** condition 3 reads review threads only, while the CI review lens also posts ordinary PR comments (`channels_scanned` includes `issue_comments`). A finding posted after READY on the same head is invisible to it.

## Goal

One invocation re-enters one parked item, checks that its READY is still current, runs the existing `gate-eval`, and on `MERGE` finishes the item through the normal `closeout`. It starts no drain, no lane and no next item. `## Run Config` stays `mode: safe`.

## Scope

- **A new one-time entry,** `/automate --merge-parked <run_id>` (the name may change if a house convention says otherwise; it must not be a `--resume` form). It runs inside the driver and spawns no phase session, so it also works under `--inline-phases` in host mode.
- **Durable READY record:** when a drain ends READY (and when a fix-now re-drain does), record `ready_sha`, `ready_at` and `termination_reason` in one `## Current` line. `drain_result` comes from the existing `owned_drain_result`. A READY report with no `ready_sha` writes no line, and an item change drops the line. Any input a later session's gate pass needs lives in the run file, never only in the sidecar; say so in `skills/automate-loop/run-file.md`.
- **Pre-gate guard (this entry only):** before `gate-eval`, park with a named reason if a PR comment or review is newer than `ready_at`, or if the base has moved since READY (compare API `behind_by` > 0; never `mergeStateStatus`, which reads differently with strict protection off).
- **Gate unchanged:** the entry calls the existing `automate-helpers.sh gate-eval`, feeding `drain_result`, `termination_reason` and `ready_sha` into the existing ctx from `## Current`, never from the sidecar `--resume` wipes. No edit to `gate_eval`, its seven conditions or its ctx keys; `gate-eval` stays the only executor of `gh pr merge --squash`.
- **Locking:** take the run lock before `gate-eval` and hold it through closeout, so the merge watcher's closeout reads "run lock held" (already treated as transient) and retries.
- **After `MERGE`:** the closeout `ns_reconcile_merged` uses (with trail), then CHECK OFF, then stop. Items remaining ⇒ `## Status: paused`, `pause_reason: awaiting_go`, with this entry's own message (`ns_awaiting_go`'s default text describes a superseded drain). None remaining ⇒ the existing done termination.
- **Tests:** a new part, `scripts/test-automate-next-step.d/13-merge-parked.sh`, registered in `test-automate-next-step.sh`. The golden fixtures copy `## Current`, so a replay that records a READY drain carrying `ready_sha` gains the new line in its `expected.md`, and no other byte changes.
- **`--resume --auto-merge` on a parked open PR:** the park message names `--merge-parked` and states that the flag was not applied; `flag_mode` is not recorded. This flag's behaviour on a run with no open PR is unchanged.
- **Docs:** `commands/automate.md`, `skills/automate-loop/resume.md` under a section titled exactly `### Merging one parked item`, `run-file.md`, `helpers.md`, `docs/result-schemas/automate-run.md`, and the steps and park reasons in `docs/loop-inventory/automate-loop.md`.

**Leave alone in this story (a companion item in the same wave owns them):** `scripts/automate-helpers.sh` and `skills/automate-loop/modes-and-merge-gate.md`.

## Non-goals

- Changing run mode: this is one-time, and the run stays safe mode.
- Any `gate_eval` change, or `--trust-unprotected` on private Free repos (the companion item `2026-11-05-192935-trust-unprotected-private-free-and-empty-checks.md`).
- Starting a drain for any reason, including a moved head.
- Switching branches in the owner's checkout.
- Lanes: an item parked in a lane or `--parallel` run is refused (parallel runs never use the gate).

## Owner decisions (2026-11-05)

- One-time merge, not a change to the run's mode.
- Staleness: park on a comment or review newer than READY, and on a base that moved since READY.
- Checkout not on the PR head: touch nothing, park naming the branch to check out. Studio's playbook makes sure of the checkout.
- Head moved since READY: park on `head_sha_moved`, saying a person must decide. Never start a drain.

## Acceptance criteria

**Happy path:**
- [ ] Given an item parked `awaiting_merge` whose READY is current and whose seven conditions hold, when `--merge-parked <run_id>` runs, then `gate-eval` prints `MERGE`, the PR is squash-merged by `gate-eval` alone, closeout runs with its trail, and the item is checked off with no hand edit.
- [ ] Given items remain after that merge, when the entry finishes, then `## Status: paused`, `pause_reason: awaiting_go`, and no item is picked.
- [ ] Given no items remain, when the entry finishes, then the run reaches the existing done termination, trail included.
- [ ] Given any outcome, when the entry finishes, then `## Run Config` still reads `mode: safe` and no drain, lane or phase session was spawned.

**Edge cases:**
- [ ] Given a parked item, when `--resume` runs first and `--merge-parked` after, then the ctx handed to `gate-eval` carries the recorded `ready_sha`, `drain_result: READY` and the recorded `termination_reason` (a test pins all three: the sidecar wipe cannot lose a gate input).
- [ ] Given a fix-now re-drain that ended READY on a new head, when the entry runs, then the recorded `ready_sha` and `termination_reason` are the re-drain's.
- [ ] Given a READY report with no `ready_sha`, when the drain result is recorded, then no READY line is written. Given `## Current` moves to another item, then the line is dropped.
- [ ] Given the live head differs from the recorded `ready_sha`, when the entry runs, then it parks `PARK: head_sha_moved`, says a person must decide, and spawns nothing.
- [ ] Given a PR comment or review newer than `ready_at`, when the entry runs, then it parks with a named reason and `gate-eval` does not run.
- [ ] Given `behind_by` > 0 for the PR's base, when the entry runs, then it parks with a named reason and `gate-eval` does not run.
- [ ] Given the checkout is not on the PR head, when the entry runs, then it parks naming the branch to check out, and HEAD and the working tree are unchanged.
- [ ] Given a live merge watcher, when the entry merges, then one closeout does the work, the check-off appears once, and the watcher exits without a second closeout (a test covers the watcher polling during the merge, and after it).
- [ ] Given a condition parks, when the entry finishes, then the run stays `awaiting_merge` with its `PARK: <reason>` recorded, exactly one watcher is live, and the run lock is released.
- [ ] Given undecided per-finding dismissed drafts, when the entry merges, then they stay pending for the next interactive PICK, as after any `--auto-merge` `MERGE`.
- [ ] Given `--resume --auto-merge` on a parked open PR, when it parks, then the message names `--merge-parked` and says the flag was not applied, and `flag_mode` is not recorded.

**Error scenarios:**
- [ ] Given a run parked before this change (no recorded `ready_sha`), when the entry runs, then it parks with a named reason and never substitutes the live head.
- [ ] Given `## Current` is anything but `awaiting_merge` with a READY drain (`escalated`, `ready_for_release`, `running`, `done`), when the entry runs, then it refuses naming the status and writes nothing.
- [ ] Given a lane or a `--parallel` parent, when the entry runs, then it refuses by name and writes nothing.
- [ ] Given the PR already reads MERGED, when the entry runs, then it closes the item out with no gate and no merge. Given it reads CLOSED, then it reports it the way RECONCILE does and never checks the item off.
- [ ] Given `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`, when it runs on the branch, then every path is a surface `skills/automate-loop/invariants.md` already enumerates.

## Validation (must pass before merge)

1. **Static — the project's gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh` and `test-citation-drift.sh`; `bash scripts/check-version-bump.sh` passes, with a `changelog.d/` fragment and no hand-edited version.
2. **Running system — Studio's p14 on a freshly parked item:** using this branch's plugin copy, park a NEW item on `vikashruhilgit/studio-sandbox` and re-enter it per `probes/p14-loomwright-merge-one-parked-item.md` in `vikashruhilgit/loomwright-studio`, merging only through the gate. The answer is yes only if one invocation merges, finishes the item, starts no drain and needs no hand edit. The output goes in `docs/evidence/merge-one-parked-item.md` with `Verdict: PASS for Validation 2`. If the run cannot be completed, the file records exactly what ran with no `Verdict: PASS` line, so the validation gate parks for the owner. PR 6 cannot serve: its failed resume should already have erased its `ready_sha` (from reading the code; no clone was available to confirm it), so it should park.

### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** it blocks two Studio phase 8 items, and Studio cannot work around it because it never merges itself.

### Assumptions
- A parked item's drafts keep the existing `--auto-merge` rule: merging does not wait for them, and fix-now is no longer possible once merged, so they become follow-ups.
- Comments Loomwright's own drain posts come before `ready_at`, so they do not trip the guard. Verify this while building; a drain line posted at or after READY would make every re-entry park.
- A host-mode session needs no rate-limit check here, because that check belongs to the RUN step this entry skips. Whether run state moves under `LOOMWRIGHT_HOST_STATE_DIR` was not checked: test it.

### Dependencies
- Depends on: none
- Blocks: Studio phase 8 items
- Should land with: `2026-11-05-192935-trust-unprotected-private-free-and-empty-checks.md` (same wave). The one shared file is `docs/loop-inventory/automate-loop.md`: on 2026-11-06 the owner had that item edit the rule cells of rows AL-420 and AL-421 there. This item adds its own rows and leaves those two alone.

### Risks
- A busy `main` sends most re-entries back to the owner. Accepted (owner decision); it fails toward a person.
- `commands/automate.md` is near its token budget: rewrite rows rather than extend them, and raise the budget only with its mirror row.
- `automate-next-step.sh` is the plugin's hotspot; open PR 822 changes it too, so this should branch after 822 merges.

### Success Metrics
- p14 answers yes on a fresh sandbox item.

### Plan Review history
Launch Pad failed Plan Review on all 3 attempts on 2026-11-06 (run `automate-2026-11-06-131342`, lane L1). The last HIGH finding: the gate also needs `drain_result` and `termination_reason`, so the record above now covers them. The unreviewed draft with the reviewer's fixes may still exist at `/private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-ai-agent-manager-lanes-automate-2026-11-06-131342-L1/198e0ddf-9090-41c6-98d8-433bf2d9929f/scratchpad/brief.md`. Use it as a starting point if it is there, and re-check it against the code; this requirement wins on any difference.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-05-192934-merge-one-parked-item-through-the-gate.md"`, or the plan doc's `/automate --backlog` line.

## Depends on
none

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/automate-helpers.d/runfile.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/test-automate-next-step.d/13-merge-parked.sh
loomwright/scripts/fixtures/automate-golden/dismissed-fix-now-re-drain/expected.md
loomwright/commands/automate.md
loomwright/skills/automate-loop/resume.md
loomwright/skills/automate-loop/run-file.md
loomwright/skills/automate-loop/helpers.md
loomwright/docs/result-schemas/automate-run.md
loomwright/docs/loop-inventory/automate-loop.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
docs/evidence/merge-one-parked-item.md
changelog.d/merge-one-parked-item.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-07T07:34:07Z
- **Brief:** .supervisor/jobs/done/2026-11-06-merge-one-parked-item-through-the-gate.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/842
