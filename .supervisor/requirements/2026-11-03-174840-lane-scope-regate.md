# Lane scope re-gate (issue #808)

## Merged from (2026-11-03)
- Part A: `2026-11-03-174029-one-question-for-files-outside-touches.md` — One question for files outside Touches
- Part B: `2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md` — Re-check lane overlap before coding starts

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted one level, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Goal
Ask once about files outside Touches and re-check lane overlap before coding starts

## Part A — One question for files outside Touches

**Story: One question for files outside Touches** (type: story)

**As a** plugin owner answering Launch Pad's questions for an `/automate` item,
**I want** every "this work needs files outside the item's `## Touches`" moment to reach me as ONE catalog question carrying the complete list,
**so that** I decide the widening once, knowingly, and never accept extra files by picking "Save and exit".

#### Problem
Issue vikashruhilgit/loomwright#808 (and its 2026-11-03 comment), run `automate-2026-11-02-150636` wave 3 in
loomwright-studio: one Launch Pad pass for item 06 asked about files outside Touches four times, under four
headers — `LP-NO-GO` (feasibility), `GET list` and `Grant form` (improvised, not catalog codes), and folded into
`LP-SAVE-NOTE`, where "Save and exit" also accepted four new files. Each answer covered only what that pass had
found; the item grew from 10 declared files to 25. A header that is not a catalog code is always human, so no
lane policy can answer it, and `check-gate-headers.sh` cannot see a question that no prompt text spells out.

#### Owner decisions (2026-11-03)
- Approved the design in issue #808's analysis session: one catalog code for "needs files outside Touches", the
  list computed rather than asked piecemeal, never folded into a save question.
- The new code starts `human-only`. Making it `allowed` (policy-answerable) waits until the cross-lane re-check
  (`2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md`) has shipped — pre-answering "Extend" before
  then would bring back the unseen overlap.

#### Acceptance Criteria

**Happy Path:**
- [ ] Given a brief whose files include paths outside the item's Touches (as `plan-waves <item> --touches` reads
      them, companions included), when Launch Pad reaches its save step, then it asks ONE question under a new
      catalog code with the complete outside-Touches list, BEFORE the `LP-SAVE` / `LP-SAVE-NOTE` question.
- [ ] Given that question, then its options are one fixed label set covering extend / revise / stop, and the code,
      labels and policy appear in `lane-policy.sh catalog` and the regenerated `docs/LANE_GATES.md` table.
- [ ] Given the owner chooses extend, then the brief records the accepted outside-Touches paths in one place a
      later reader can find, and the save question that follows no longer mentions them.

**Edge Cases:**
- [ ] Given every brief path is inside Touches, then no scope question is asked (zero new questions on the
      common path).
- [ ] Given feasibility's only blocker is files outside Touches, then Launch Pad does not ask `LP-NO-GO`; the
      files are carried to the one scope question instead. A NO-GO for any other reason is unchanged.
- [ ] Given the item's Touches is `unknown`, then no scope question is asked (there is no declared set to be
      outside of).
- [ ] Given Launch Pad needs a free-form answer that is not a catalog gate (a design or contract question such
      as item 06's `Grant form`), then it asks under `LP-CLARIFY`, never an improvised header.

**Error Scenarios:**
- [ ] Given the Touches set cannot be read (`plan-waves --touches` fails), then the scope question is still
      asked, listing every brief path and saying the declared set was unreadable — never silently skipped.
- [ ] Given Launch Pad cannot ask (a subagent, or `--non-interactive`), then it takes a named can't-ask branch
      that persists nothing it was not allowed to, per `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory".

#### Priority
- [x] MVP — the other two stories build on this question's code and wording.

#### Assumptions
- A brief's file list is readable the same way `readiness.sh`'s `_lanes_declared` reads it (its `path:` lines).
- Launch Pad can compute "brief paths minus Touches" from existing readers without a new script; if it cannot,
  the plan adds one.

#### Dependencies
- Depends on: none.
- Blocks: `2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md` (the lane-mode routing of this question).

#### Risks
- The prompt-only form leans on the model computing a set difference; a deterministic helper may be needed.
- Adding a gate grows `agents/launch-pad.md`; its token budget must be re-measured in the same change.

#### Success Metrics
- On a re-run of an item like loomwright-studio item 06, the owner sees one scope question with the full list,
  not three or four partial ones.

#### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-03-174029-one-question-for-files-outside-touches.md"`

### Validation (must pass before merge)
1. **Static — catalog and headers:** `bash loomwright/scripts/test-lane-policy.sh` and `bash loomwright/scripts/check-gate-headers.sh` pass with the new code; `bash scripts/ci-local.sh --affected` passes.
2. **Running system — one scope question:** a live `/launch-pad` on a fixture item whose ACs need a file outside its Touches asks exactly one scope question under the new code, listing that file, before the save question.

## Part B — Re-check lane overlap before coding starts

**Story: Re-check lane overlap before coding starts** (type: story)

**As a** plugin owner running `/automate --parallel N`,
**I want** the coordinator to compare a lane's final file set with every other live lane in the wave before that lane starts coding,
**so that** two lanes never edit the same files at once without my knowing, and I don't find out only at `wave-build`.

#### Problem
Issue vikashruhilgit/loomwright#808: `plan-waves` puts items in one wave from their declared Touches. When a lane's
Launch Pad widens its set (items 05 and 06 went from 11 to 26 and 10 to 25 files), nothing re-checks the wave:
both lanes then edited `kernel.ts`, `sessions/policy.ts`, `triggers/poll.ts` and `phase-8-foundation.test.ts`
in parallel. The only cross-lane check, `_lanes_wave_overlap` in `automate-lanes.d/wave.sh`, runs at `wave-build`
after every PR is open, and warns only. Each lane's real set already exists on disk once its brief is saved
(`_lanes_declared` in `automate-lanes.d/readiness.sh`: Touches plus the brief's `path:` lines); nothing compares
those sets mid-wave. Widening happens in steps inside Launch Pad, but Launch Pad writes no code, so one check at
the end of Launch Pad sees the final set before any clash can happen.

#### Owner decisions (2026-11-03)
- Approved: check once per brief save at the end of Launch Pad, before the Supervisor phase, not on every
  in-Launch-Pad answer.
- In a lane, the owner gets ONE question about a widening, from the coordinator (the only party that sees other
  lanes), with the options serialize / continue in parallel / defer to next wave / revise.
- `wave-build`'s warn-only overlap check stays as the final safety net.
- No second stored copy of a lane's set (no `touches_effective` field): the brief is the source, read through the
  existing `_lanes_declared` reader.

#### Acceptance Criteria

**Happy Path:**
- [ ] Given a lane's Launch Pad has saved its brief, when the lane would start its Supervisor phase, then it does
      not start until the coordinator has compared the lane's declared set (`_lanes_declared`) with every other
      live lane of the wave.
- [ ] Given no overlap, then the lane continues with no question to the owner.
- [ ] Given an overlap, then the coordinator receives a lane event naming the lane, the other lane(s) and the
      shared files, and the owner gets one question under one human-only catalog code with the labels
      serialize / continue in parallel / defer to next wave / revise.
- [ ] Given "serialize", then the lane waits until the other lane's PR is merged into the wave, and starts from
      that state; given "defer", then the item leaves this wave and is planned into a later one; given
      "continue in parallel", then the choice is recorded in the parent run file's `## Progress` and the lane starts.
- [ ] The overlap comparison uses the same matcher as `wave-build`'s overlap check, so a file the two call
      "shared" is the same file.

**Edge Cases:**
- [ ] Given the other lane has not saved its brief yet, then the comparison uses that lane's planner-reserved
      Touches, and that lane's own later save re-checks against this one (the check is two-way).
- [ ] Given a lane's brief is saved again (a re-plan), then the check runs again on the new set.
- [ ] Given a single-lane run (`--parallel 1`) or a sequential run, then no check and no hold happen.
- [ ] Given `--inline-phases` (no `launch-pad saved` line is written), then the limit is stated in the docs and
      the run behaves as today; it is not a silent pass.
- [ ] Given the lane's Launch Pad asks the scope question from
      `2026-11-03-174029-one-question-for-files-outside-touches.md`, then in a lane the owner is not asked twice
      about the same widening.

**Error Scenarios:**
- [ ] Given a lane's set cannot be read (brief or Touches unreadable), then the coordinator does not treat the
      lane as clear: it asks the owner (fail CLOSED), naming what was unreadable.
- [ ] Given the coordinator session is gone while a lane is held, then the hold survives and `/automate --resume`
      shows it in `lane-status` and its `--inbox`.

#### Priority
- [x] MVP — this is the fix for the issue's main failure (an unseen overlap mid-wave).

#### Assumptions
- A lane can be held between the `plan-result` step (`launch-pad saved <brief>`) and the `run` step of the
  per-item loop in fresh-phase mode; that the step exists is checked, a hold mechanism there is not.
- "Serialize" can reuse wave mechanics that already exist; if it cannot, the plan states the smallest new piece.

#### Dependencies
- Depends on: `2026-11-03-174029-one-question-for-files-outside-touches.md`.
- Blocks: none.

#### Risks
- A new lane state or event reaches every consumer of lane states, the optional `loomwright-lanes` pane included.
- A hold that is never released stalls the wave; `lane-wait` and the `Stop` guard must surface it.

#### Success Metrics
- In a replay of wave 3 of `automate-2026-11-02-150636`, the owner is asked about the shared `kernel.ts` and
  `sessions/policy.ts` before either lane writes code.

#### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md"`

### Validation (must pass before merge)
1. **Static — lanes and next-step suites:** `bash loomwright/scripts/test-automate-lanes.sh`, `bash loomwright/scripts/test-automate-next-step.sh`, `bash loomwright/scripts/test-lane-policy.sh` and `bash scripts/test-lanes-addon.sh` pass, including a case with two lanes whose saved briefs share a file; `bash scripts/ci-local.sh --affected` passes.
2. **Running system — held lane and one question:** a live `/automate --parallel 2` on two fixture items whose declared Touches are disjoint but whose briefs share a file shows the second lane held before its Supervisor phase and one coordinator question naming the shared file.

## Depends on
none

## Touches
changelog.d/2026-11-03-174840-lane-scope-regate.md
loomwright-lanes/hooks/register.tsx
loomwright-lanes/tests/pane.test.tsx
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/LANE_GATES.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/result-schemas/automate-run.md
loomwright/scripts/automate-lanes.d/phase.sh
loomwright/scripts/automate-lanes.d/readiness.sh
loomwright/scripts/automate-lanes.d/relay.sh
loomwright/scripts/automate-lanes.d/status-read.sh
loomwright/scripts/automate-lanes.d/status.sh
loomwright/scripts/automate-lanes.d/wave.sh
loomwright/scripts/automate-lanes.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/guard-lane-wait-armed.sh
loomwright/scripts/lane-policy.sh
loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh
loomwright/scripts/test-automate-lanes.d/05-timeline-and-gate.sh
loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh
loomwright/scripts/test-automate-next-step.d/05-fresh-phases.sh
loomwright/scripts/test-lane-policy.sh
loomwright/skills/automate-loop/lanes.md
loomwright/skills/automate-loop/per-item-loop.md
