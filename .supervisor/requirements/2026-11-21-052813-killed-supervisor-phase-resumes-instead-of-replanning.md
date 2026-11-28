# A killed Supervisor phase resumes instead of re-planning

## Status: pending

Source: GitHub issue vikashruhilgit/loomwright#964, "Related gaps seen in the same run", second bullet. Seen on loomwright 18.1.2, branch mode on, `/automate --parallel 3`.

**As an** owner running `/automate` (lanes or sequential),
**I want** an item whose Supervisor phase session was killed mid-build to resume that Supervisor run on the brief it already has,
**so that** finished subtasks are kept and the item isn't re-planned and rebuilt from a fresh Launch Pad.

### Problem (checked against origin/main, c9fd2f8)

1. On a re-pick, `ns_picked` in `automate-next-step.sh` sends the item to RUN (Supervisor) only when `ns_checkpoint_task` returns a task. Otherwise it sends it to a fresh Launch Pad phase.
2. `ns_checkpoint_task` returns a task only when the item's last `ran /autonomous` line is a `no PR: checkpoint (` or `no PR: supervisor_checkpoint (` line, and that task's brief is in `.supervisor/jobs/in-progress/`.
3. A Supervisor phase that is killed writes no checkpoint. The driver records `ran /autonomous — no PR: phase_died (…)`. If the phase opened a PR, the adopt path (`ns_died_line_pr`) keeps it. If it opened none yet (mid-build), the re-pick runs a fresh Launch Pad, even though the brief is still in `jobs/in-progress/` and its finished subtasks sit on their branches.

### Scope note for the planner
`loomwright/docs/prompt-token-budgets.json` belongs to the close-out item in this item's wave. Keep `skills/automate-loop/per-item-loop.md` within its current budget and leave that JSON file alone. If the budget truly cannot hold the change, stop and say so rather than editing it.

## Acceptance Criteria

**Happy path**
- [ ] Given an item whose Supervisor phase died with no PR (the last `ran /autonomous` line is `no PR: phase_died`, written by the Supervisor phase), and whose brief is in `.supervisor/jobs/in-progress/`, when the item is picked again, then the driver resumes that Supervisor run (`--continue task: <id>`, as for a checkpoint). It does not start a Launch Pad phase, and one `## Progress` line names the resume and the died phase it resumes.
- [ ] Given the Supervisor phase died before it moved the brief out of `.supervisor/jobs/pending/`, when the item is picked again, then the driver starts a Supervisor phase on that same saved brief (the item's `launch-pad saved` line). It does not start a new Launch Pad.
- [ ] Given the resumed Supervisor run, when it completes, then subtasks that were already done are not re-run (Supervisor's existing `--continue` behaviour).
- [ ] Given a lane resumed this way, when its RUN step starts, then it still passes the requirement-drift check from `2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md`.

**Unchanged**
- [ ] Given a Launch Pad phase died (no brief saved), when the item is picked again, then it re-plans as today.
- [ ] Given a Supervisor phase died after opening a PR, when the item is picked again, then today's adopt path applies unchanged.
- [ ] Given a `launch-pad saved` line later than the died phase (a newer plan, for example after a `revise`), when the item is picked again, then the newer brief wins as today.

**Fail closed**
- [ ] Given the brief named by the died phase is in neither `jobs/pending/` nor `jobs/in-progress/` (moved to `done/` or `failed/`, or gone), when the item is picked again, then the driver does not guess. It re-plans as today and the `## Progress` line says why the resume was not possible.
- [ ] Given a resume that dies again, when the item is picked again, then the resume is tried at most a bounded number of times (the planner names the bound) before the item parks with a named reason for the owner, instead of looping.

## Non-goals
- Requirement drift in a held lane: `2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md` (runs in the wave before this one).
- Closing out a lane whose PR the owner merged by hand: `2026-11-21-052813-lane-with-hand-merged-pr-closes-out.md` (runs in the same wave).
- [#942](https://github.com/vikashruhilgit/loomwright/issues/942) (a PR opened by FINALIZE orphaned when the session stops before the Supervisor hand-back). That's the after-the-PR case; this story covers the before-the-PR case. They touch the same driver area, so they should not run in parallel lanes.
- Changing how Supervisor itself resumes. This story only routes the driver to the resume Supervisor already has.

## Owner decisions
- 2026-11-21 (this session): the owner asked for the #964 related gaps to be written as requirements and planned with the drift item as one set.

## Priority: MVP
**Rationale:** A killed phase is a normal event (a machine sleep, a rate limit, an owner's stop). Today each one throws away finished work and pays for a full re-plan and rebuild.

## Assumptions
- Defect evidence: observed — the #964 run: after a Supervisor phase session was killed mid-build, the lane's re-pick asked for a fresh Launch Pad instead of resuming. On origin/main (c9fd2f8), `ns_checkpoint_task` accepts only `checkpoint` / `supervisor_checkpoint` lines, and `ns_picked` sends everything else without a PR to a fresh plan.
- The driver can tell a died Supervisor phase from a died Launch Pad phase from the run file: a `launch-pad saved` line before the `phase_died` line, in the same `picked` segment. The planner confirms this or records the phase in the died line.
- Supervisor's `--continue task: <id>` resumes from its state file and skips finished subtasks, as it does for a checkpoint today.

## Dependencies
- Depends on: `2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md` (same driver file; runs after it).
- Blocks: none.

## Risks
- **Resuming a broken run.** A Supervisor run killed in a bad state may die again. That is why the resume count is bounded and ends in a park.
- **Same file as other work.** `automate-next-step.sh` is also the area #942 will change. Running them in parallel lanes would conflict.
- **Mirror drift.** The re-pick rule is restated in `skills/automate-loop/per-item-loop.md` and `docs/loop-inventory/automate-loop.md`. House rule: a restating copy changes in the same PR as its authority.

## Validation (must pass before merge)
1. **Static — re-pick after a died Supervisor phase:** `scripts/test-automate-next-step.d/05-fresh-phases.sh` (or a new `.d/` part) asserts: died Supervisor phase with the brief in `jobs/in-progress/` ⇒ RUN with `--continue task: <id>`; brief still in `jobs/pending/` ⇒ RUN on that brief; died Launch Pad phase ⇒ plan as today; brief in `done/` ⇒ plan, with the reason line; a resume that died the bounded number of times ⇒ the named park.
2. **Static — checkpoint behaviour unchanged:** the existing checkpoint and adopt cases in `scripts/test-automate-next-step.sh` and `.d/10-mutants-pick-fresh.sh` still pass.
3. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`; `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment.
4. **Running system — a killed Supervisor phase resumes:** in a sandbox repo, run `/automate` on a two-subtask item. Kill the Supervisor phase session after the first subtask finishes, then `/automate --resume`. The driver starts a Supervisor `--continue` run (not a Launch Pad phase) and the first subtask is not re-run. Record the output in `docs/evidence/killed-supervisor-phase-resumes.md` with its verdict line.

## Depends on
2026-11-21-045234-held-lane-checks-requirement-drift-before-it-builds.md

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/test-automate-next-step.d
loomwright/skills/automate-loop/per-item-loop.md
loomwright/docs/loop-inventory/automate-loop.md
docs/evidence/killed-supervisor-phase-resumes.md
changelog.d/killed-supervisor-phase-resumes.md
