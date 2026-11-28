# A lane whose PR the owner merged by hand closes out

## Status: pending

Source: GitHub issue vikashruhilgit/loomwright#964, "Related gaps seen in the same run", first bullet. Seen on loomwright 18.1.2, branch mode on, `/automate --parallel 3`.

**As an** owner running `/automate --parallel N`,
**I want** a lane whose PR I merged by hand to be closed out by the engine, whatever state the lane was parked or stuck in,
**so that** its lane, its rows in the parent Queue and the primary's run lock don't stay open waiting for a step nobody can take.

### Problem (checked against origin/main, c9fd2f8)

1. `lane-status` (`automate-lanes.d/status-read.sh`, the parked-PR read) reads a parked lane's live PR. A MERGED PR turns the state into `merged` only for `awaiting_merge` and `ready_for_release` parks. For `escalated`, `failed` and `drain_died` it keeps the park and only adds the reason `PR merged outside the run while parked <park> — a human checks it before closing the lane out`.
2. A lane whose process died mid-phase (state `died`, `stalled` or `lost_to_reset`, run file still reading `running`) is never checked against its PR at all.
3. `fleet-closeout` (`automate-lanes.d/wave.sh`) closes out only `merged` / `awaiting_go` / `done` lanes. Everything else prints `waiting — <lane> <state>` on every resume.
4. `lane-convert-ready` (`automate-lanes.d/remove.sh`) refuses any run file that is not `ready_for_release`. So nothing closes such a lane, even after a human has checked it: no Queue check-off, no `lane-remove`, and no wave end, so the run lock is kept.

## Acceptance Criteria

**Happy path**
- [ ] Given a lane parked `escalated`, `failed` or `drain_died` whose recorded PR reads MERGED, when `fleet-closeout` runs, then the engine closes the lane out through the same sanctioned path a merged ready lane takes (close-out, Queue check-off, `lane-remove`). It prints one `fleet-closeout:` line naming the park the lane was in and that the owner merged the PR outside the run.
- [ ] Given a lane whose process died mid-phase (`died`, `stalled`, `lost_to_reset`) with a PR recorded or adoptable from its run file, and that PR reads MERGED, when `fleet-closeout` runs, then it is closed out the same way.
- [ ] Given every lane of the wave is now closed out, when `fleet-closeout` reaches wave end, then the parent run finalizes (when the Queue is empty) and the primary's run lock is released, as for a normal wave.
- [ ] Given such a lane, when `lane-status` reads it, then it no longer shows "a human checks it". It shows that the PR was merged outside the run and that the next `fleet-closeout` closes the lane out.

**Ask the owner only when something doesn't add up**
- [ ] Given the merged PR's head is not the lane's recorded or local branch head (the lane has commits that never reached the PR), when the close-out runs, then the engine does not close the lane. It puts one question to the owner naming the lane, the PR and the commits left out, with options to close out anyway (the commits are salvaged first), or to keep the lane open.
- [ ] Given the lane has unpushed metadata, a `.meta-push-failed` or `.closeout-leftover` marker, or a live lane process or merge watcher, when the close-out runs, then today's refusals and `human —` lines apply unchanged. A merged PR is never a reason to skip them.
- [ ] Given the run cannot ask (`--non-interactive`, or a coordinator without the ask tool), when a question above is due, then the lane stays open, nothing is closed, and the reason is named in `lane-status` and the `fleet-closeout` output.

**Must not change**
- [ ] Given a lane whose PR reads OPEN, or CLOSED unmerged (`gone`), when `fleet-closeout` runs, then the output is the same as today (`waiting — …` / `human — <lane> gone …: lane-remove <lane_dir> --abandon`).
- [ ] Given the change, nothing in it merges a PR. The `--auto-merge` gate stays the only executor of `gh pr merge --squash` (CLAUDE.md invariant), and the close-out only reads a merge the owner already made.

## Non-goals
- Requirement drift in a held lane: `2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md` (runs in the wave before this one).
- Resuming a killed Supervisor phase instead of re-planning: `2026-11-21-052813-killed-supervisor-phase-resumes-instead-of-replanning.md` (runs in the same wave).
- [#710](https://github.com/vikashruhilgit/loomwright/issues/710) (an `escalated` `check_red` park never re-gates after CI turns green while its PR is still open). That's a different trigger, on an open PR.
- Sequential (non-lane) `/automate` runs. Their RECONCILE already closes out a merged in-flight item.
- Merging anything. This story only closes out merges the owner already made.

## Owner decisions
- 2026-11-21 (PO-ASSUME answer, this session): the engine checks whether the PR merged and closes the lane out itself. It does not wait for a human to confirm. It asks the owner only when a check finds something missing or inconsistent. This replaces the current "a human checks it before closing the lane out" rule for merged-outside-the-run lanes.

## Priority: MVP
**Rationale:** Every hand-merged lane in a non-ready park blocks its wave's end and holds the primary's run lock, so the next wave can't start without manual clean-up. The owner merging by hand is a normal way out of an escalated park.

## Assumptions
- Defect evidence: observed — the #964 run: a lane whose PR the owner merged while it was parked `escalated` (and one whose run file still read `running` after a killed phase) stayed open with its parent Queue rows and the primary's run lock. On origin/main (c9fd2f8), `status-read.sh` keeps `escalated` / `failed` / `drain_died` as is on a MERGED PR, `fleet-closeout` waits on them, and `lane-convert-ready` refuses anything but `ready_for_release`.
- The safest change is to let `lane-status` read these lanes as `merged` (with the original park kept in the reason), so `fleet-closeout`'s existing merged branch and `lane-convert-ready`'s close-out do the work. The planner may choose another shape if the AC holds.
- A merged PR that left lane commits out is the main "doesn't add up" case. Others the planner finds (for example, the lane's item already checked off by another lane) also become owner questions, never silent closes.
- The new owner question needs a gate row in `docs/LANE_GATES.md` and the question-gate inventory, like other lane gates.

## Dependencies
- Depends on: `2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md` (shares the lane docs and gate catalog; runs after it).
- Blocks: none.

## Risks
- **Closing a lane the owner meant to keep.** An `escalated` park meant review left findings open. Merging the PR is the owner accepting them. Any dismissed findings the lane recorded should still be surfaced in the close-out line, not dropped.
- **Lost work.** A lane with commits not in the merged PR must never be removed silently. That is why the head check is an owner question and salvage comes first.
- **Mirror drift.** The lane-state list is restated in `skills/automate-loop/lanes.md` and the `automate-lanes.sh` usage header. House rule: a restating copy changes in the same PR as its authority.

## Validation (must pass before merge)
1. **Static — close-out of hand-merged lanes:** `scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh` gains cases (with `gh` stubbed): an `escalated`, a `failed`, a `drain_died` and a `died`-mid-phase lane, each with a MERGED PR, are closed out, checked off and removed, and the wave lock is released once all are. An OPEN PR and a CLOSED PR give today's output. A merged PR whose head is behind the lane's branch is not closed and raises the owner question. A non-interactive run keeps it open with the reason named.
2. **Static — lane-status reads them:** the `lane-status` fixtures (`scripts/test-automate-lanes.sh` or its `.d/` parts) assert the new state and reason for each park.
3. **Static — merge invariant:** `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` prints only the sanctioned surfaces enumerated in `skills/automate-loop/SKILL.md` §11.
4. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes; `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment.
5. **Running system — a hand-merged escalated lane closes out:** in a sandbox repo, run `/automate --parallel 2` until one lane parks `escalated`, merge its PR by hand on GitHub, then `/automate --resume`. `fleet-closeout` closes that lane out, checks off its Queue row and, once the other lane is done, releases the run lock. Record the output in `docs/evidence/hand-merged-lane-closeout.md` with its verdict line.

## Depends on
2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md

## Touches
loomwright/scripts/automate-lanes.d/status-read.sh
loomwright/scripts/automate-lanes.d/wave.sh
loomwright/scripts/automate-lanes.d/remove.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/scripts/test-automate-lanes.d/04-fleet-closeout-to-optout.sh
loomwright/scripts/lane-policy.sh
loomwright/skills/automate-loop/lanes.md
loomwright/docs/LANE_GATES.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
docs/evidence/hand-merged-lane-closeout.md
changelog.d/hand-merged-lane-closeout.md
