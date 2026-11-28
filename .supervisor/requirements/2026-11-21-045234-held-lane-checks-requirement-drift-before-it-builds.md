# A held lane checks for requirement drift before it builds

## Status: pending

Source: GitHub issue vikashruhilgit/loomwright#964. Seen on loomwright 18.1.2, branch mode on, `/automate --parallel 3`.

**As an** owner running `/automate --parallel N` in branch mode,
**I want** a lane to stop before it builds when its requirement changed on the metadata branch after its brief was saved,
**so that** a lane never builds, drains and opens a PR for behaviour I already replaced, and I find out before any code is written, not at wave end as a meta-push conflict.

### Problem (checked against origin/main, c9fd2f8)

1. A lane's requirement is the copy `lane-create` pulled from the metadata branch (`automate-lanes.d/create.sh`, the `meta-sync pull --branch` step). Nothing pulls it again before a later phase.
2. When the Launch Pad save step in `automate-next-step.sh` saves the brief, it records the brief path and checks the rubric. It does not record which version of the requirement the brief was planned from.
3. `lane-scope-check` (`automate-lanes.d/scope.sh`) compares only the lane's file set with the other lanes (`unreadable` / `overlap` / `clear` / `widening`). It never compares the requirement.
4. `lane-scope-decide continue`, `lane-launch --continue` / `--resume-run` and an answer resume all re-enter the driver's RUN step (`ns_run`) on the saved brief. The guards there refuse only `no_pr_stop` and `scope_hold`. None of them checks the requirement.

In #964, L3's brief was saved on day 1. The owner rewrote the requirement on the metadata branch on day 2 ("one-save create" replaced "create, then attach"). L3 was then released with `continue` (`lane-scope-check` printed `clear`). It built and drained the old flow and parked `ready_for_release`. The first signal was `lane-convert-ready` failing with a meta-push conflict on the requirement file.

## Acceptance Criteria

**Happy path**
- [ ] Given a lane's Launch Pad phase saves a brief, when the driver records the save, then a script (never a model) also records which version of the item's requirement the brief was planned from (a content hash or the metadata-branch blob sha), in a place `lane-scope-check` and the RUN step can read back.
- [ ] Given a held lane (`scope_hold`) whose requirement on `origin/<meta-branch>` differs from the recorded version, when the coordinator runs `lane-scope-check <lane>`, then it prints `drift — <requirement> changed since the brief was saved (<old>..<new>)` and does not print `clear`.
- [ ] Given that drift, when the coordinator puts it to the owner, then the question offers Revise (re-plan with the current requirement), Continue anyway, and Defer. It is human-only: no lane policy and no `auto` tier answer can settle it.
- [ ] Given the owner picks Revise, when `lane-scope-decide <lane> revise` runs, then the lane's requirement copy is first refreshed from `origin/<meta-branch>`, so the new Launch Pad phase reads the current text, and the recorded version is replaced at that phase's save.
- [ ] Given the owner picks Continue anyway, when `lane-scope-decide <lane> continue` runs on a drifted lane, then it is accepted only with the gate the owner answered named on the command line. Without it the command is refused, exits non-zero and writes nothing. When accepted, one lane line and one parent line record that the lane continues on a superseded requirement.
- [ ] Given a lane whose requirement has not changed, when `lane-scope-check` runs, then its output is the same as today: no drift line, and `clear` when nothing else is found.

**Resume paths (every way into the build)**
- [ ] Given a lane with a recorded version, when the driver's RUN step starts through any path (`lane-scope-decide continue`, `lane-launch --continue`, `lane-launch --resume-run`, an answer resume, a stall resume, or a checkpointed Supervisor run resuming), then it compares the requirement first. On drift without the owner's recorded Continue-anyway, it starts nothing and parks the lane with a named reason. The coordinator sees that reason in `lane-status` and puts the same question to the owner.
- [ ] Given the owner already chose Continue anyway for this drift (same old..new pair), when the lane resumes later, then it is not asked again. A further change to the requirement (a new `<new>`) is new drift and is asked again.

**Fail closed**
- [ ] Given the metadata branch cannot be fetched, or the requirement is missing on it, when the check runs, then it reads `unreadable — …` (never `clear`, never "no drift") and the lane stays held.
- [ ] Given a brief saved before this change, so no version was recorded, when the check runs, then it reports the version as unrecorded and treats it as drift to ask about. It never treats it as a match.
- [ ] Given a `--non-interactive` run, or a coordinator that cannot ask, when drift is found, then the lane stays held, no decision is recorded, and the existing Stop guard (`guard-lane-wait-armed.sh`) keeps the coordinator from ending its turn as if the lane were decided.

**Catalog and mirrors**
- [ ] Given the new drift question, when the PR lands, then `docs/LANE_GATES.md` (catalog row), `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" (can't-ask row), `lane-policy.sh` (human-only), `skills/automate-loop/lanes.md` (the coordinator's scope re-gate step) and `automate-lanes.sh`'s usage header all name it in the same change.

## Non-goals
- Closing out a lane whose PR the owner merged by hand: `2026-11-21-052813-lane-with-hand-merged-pr-closes-out.md`.
- Resuming a killed Supervisor phase instead of re-planning: `2026-11-21-052813-killed-supervisor-phase-resumes-instead-of-replanning.md`. Once both land, its resume also passes this item's RUN check.
- Sequential `/automate` runs (no lanes). The primary pulls the requirement at `meta-entry`. Drift during a sequential run is out of scope here.
- Auto-revising. The engine never re-plans without the owner's answer.
- Detecting drift after a lane's PR is open or drained. This story stops the build before it starts. `lane-convert-ready`'s meta-push conflict stays as the last line of defence.

## Owner decisions
- 2026-11-21 (issue #964, filed by the owner): before a held lane leaves `scope_hold`, and before any resume into Supervisor, the engine detects a requirement change since the brief was saved and does not build silently. It asks Revise / Continue anyway / Defer, fails closed when it cannot ask, keeps a `--non-interactive` lane held, and refreshes the lane's requirement copy before Revise.
- 2026-11-21 (this session): the owner asked for this to be written as a requirement after reviewing the sizing ("yes write it"), and for the two related gaps to be planned with it as one set.

## Priority: MVP
**Rationale:** A drifted lane spends a full build, an owned drain and a PR on behaviour the owner already replaced. Today nothing catches it until wave end. The fix is one check at points the engine already has.

## Assumptions
- Defect evidence: observed — the #964 run timeline: L3 released with `continue` after the requirement changed on the metadata branch, built and drained the old flow, then `lane-convert-ready` failed with `trail-pr: meta-push FAILED — conflict .supervisor/requirements/<item>.md`. On origin/main (c9fd2f8), no requirement version is recorded at the save, and `lane-scope-check` / `ns_run` have no requirement comparison.
- Recording the version from the driver's Launch Pad save step (where it already writes `launch-pad saved <brief>`) is preferred to having Launch Pad write it into the brief. That keeps a model out of the step. The planner may choose the exact place if the AC holds.
- The driver's RUN step (`ns_run`) is the one place every resume path passes through. One check there covers all of them. `lane-scope-check` then only needs to show the drift line.
- Whether the drift question gets its own gate code or extends `AUT-OVERLAP`'s labels is a planning choice. Either way it is human-only and listed in the catalog.
- With branch mode off, the reference copy is the primary checkout's requirement file, where the owner edits it. If a lane cannot read it, the check reads `unreadable`.

## Dependencies
- Depends on: none.
- Blocks: both related-gap items (they share files with this one and run in the next wave).

## Risks
- **Holding every lane after an upgrade.** Lanes whose briefs were saved before this change have no recorded version and will all ask once. This is intended (fail closed), but the changelog fragment should say so.
- **A noisy drift line.** A metadata-branch change that only touches the requirement's `## Status` stamp or close-out block would read as drift. The planner should decide whether to compare the whole file or the requirement body without the close-out block, and test that choice.
- **Mirror drift.** The gate is restated in five surfaces (Catalog and mirrors AC). House rule: a restating copy changes in the same PR as its authority.
- **Prompt growth.** `skills/automate-loop/lanes.md` has a declared token budget (`docs/prompt-token-budgets.json`); `check-token-budget.sh` fails CI if it is exceeded.

## Validation (must pass before merge)
1. **Static — scope re-gate drift cases:** `scripts/test-automate-lanes.d/08-scope-regate.sh` gains cases with a fixture metadata branch: an unchanged requirement prints `clear` as today; a changed one prints the `drift — …` line and no `clear`; an unfetchable branch prints `unreadable`; a brief with no recorded version reads as drift; `continue` on a drifted lane without the gate is refused and writes nothing; `continue` with the gate records the lane and parent lines; `revise` refreshes the lane's requirement copy before releasing.
2. **Static — driver RUN guard:** a `scripts/test-automate-next-step.d/` case shows the Launch Pad save records the requirement version, and that RUN on a drifted lane starts nothing and parks with the named reason. A recorded Continue-anyway for the same old..new pair lets RUN start; a newer change parks again.
3. **Static — gate policy:** `scripts/test-lane-policy.sh` asserts the drift question is human-only (a policy answer for it is dropped).
4. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh` and `test-citation-drift.sh`; `bash scripts/check-version-bump.sh` passes with a `changelog.d/` fragment.
5. **Running system — a held lane catches a live requirement change:** in a sandbox repo with branch mode on, run `/automate --parallel 2` with two lanes that share a file so one is held `scope_hold`. Commit a change to the held lane's requirement on the metadata branch, then run `lane-scope-check` and try `lane-scope-decide continue`. The drift line appears, `continue` without the gate is refused, and Revise starts a new Launch Pad phase whose brief reflects the new text. Record the output in `docs/evidence/held-lane-requirement-drift.md` with its verdict line.

## Depends on
none

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/automate-lanes.d/scope.sh
loomwright/scripts/automate-lanes.d/status.sh
loomwright/scripts/automate-lanes.d/launch.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/lane-policy.sh
loomwright/scripts/guard-lane-wait-armed.sh
loomwright/scripts/test-automate-lanes.d/08-scope-regate.sh
loomwright/scripts/test-automate-next-step.d
loomwright/scripts/test-lane-policy.sh
loomwright/skills/automate-loop/lanes.md
loomwright/docs/LANE_GATES.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
docs/evidence/held-lane-requirement-drift.md
changelog.d/held-lane-requirement-drift.md
