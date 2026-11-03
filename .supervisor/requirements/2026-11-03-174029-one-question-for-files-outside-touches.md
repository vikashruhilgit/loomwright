# One question for files outside Touches

## Status: pending

**Story: One question for files outside Touches** (type: story)

**As a** plugin owner answering Launch Pad's questions for an `/automate` item,
**I want** every "this work needs files outside the item's `## Touches`" moment to reach me as ONE catalog question carrying the complete list,
**so that** I decide the widening once, knowingly, and never accept extra files by picking "Save and exit".

### Problem
Issue vikashruhilgit/loomwright#808 (and its 2026-11-03 comment), run `automate-2026-11-02-150636` wave 3 in
loomwright-studio: one Launch Pad pass for item 06 asked about files outside Touches four times, under four
headers — `LP-NO-GO` (feasibility), `GET list` and `Grant form` (improvised, not catalog codes), and folded into
`LP-SAVE-NOTE`, where "Save and exit" also accepted four new files. Each answer covered only what that pass had
found; the item grew from 10 declared files to 25. A header that is not a catalog code is always human, so no
lane policy can answer it, and `check-gate-headers.sh` cannot see a question that no prompt text spells out.

### Owner decisions (2026-11-03)
- Approved the design in issue #808's analysis session: one catalog code for "needs files outside Touches", the
  list computed rather than asked piecemeal, never folded into a save question.
- The new code starts `human-only`. Making it `allowed` (policy-answerable) waits until the cross-lane re-check
  (`2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md`) has shipped — pre-answering "Extend" before
  then would bring back the unseen overlap.

### Acceptance Criteria

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

### Priority
- [x] MVP — the other two stories build on this question's code and wording.

### Assumptions
- A brief's file list is readable the same way `readiness.sh`'s `_lanes_declared` reads it (its `path:` lines).
- Launch Pad can compute "brief paths minus Touches" from existing readers without a new script; if it cannot,
  the plan adds one.

### Dependencies
- Depends on: none.
- Blocks: `2026-11-03-174030-re-check-lane-overlap-before-coding-starts.md` (the lane-mode routing of this question).

### Risks
- The prompt-only form leans on the model computing a set difference; a deterministic helper may be needed.
- Adding a gate grows `agents/launch-pad.md`; its token budget must be re-measured in the same change.

### Success Metrics
- On a re-run of an item like loomwright-studio item 06, the owner sees one scope question with the full list,
  not three or four partial ones.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-03-174029-one-question-for-files-outside-touches.md"`

## Validation (must pass before merge)
1. **Static — catalog and headers:** `bash loomwright/scripts/test-lane-policy.sh` and `bash loomwright/scripts/check-gate-headers.sh` pass with the new code; `bash scripts/ci-local.sh --affected` passes.
2. **Running system — one scope question:** a live `/launch-pad` on a fixture item whose ACs need a file outside its Touches asks exactly one scope question under the new code, listing that file, before the save question.

## Depends on
none

## Touches
loomwright/agents/launch-pad.md
loomwright/commands/launch-pad.md
loomwright/scripts/lane-policy.sh
loomwright/scripts/test-lane-policy.sh
loomwright/docs/LANE_GATES.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/prompt-token-budgets.json
changelog.d/one-question-for-files-outside-touches.md
