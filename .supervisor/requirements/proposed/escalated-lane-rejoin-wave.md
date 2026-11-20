# An escalated lane has a sanctioned path back into its wave once a human resolves its PR

## Status: proposed

> Propose-only. Raised by run `automate-2026-11-01-195532` (backlog `_BACKLOG-2026-11-01-092114-review-loop-convergence.md`,
> `--parallel 3`, 2026-11-01/02). Not enqueued.

## Problem (read 2026-11-02 against `main` at `38eb8e4`)
Lane L1 (PR #781) parked `escalated` with `escalation_cause: findings`. The one open finding was AC17, live evidence
that only the owner could produce. The owner produced it: a shadow run, commit `4dad1a0` pushed to the PR branch,
and a standalone `/review-pr --until-mergeable` that ended `READY` (converged, round 1, CI green). After that the
plugin offered no way to put L1 back into wave 1:

- `lane-convert-ready` (`loomwright/scripts/automate-lanes.d/remove.sh`, the `case "$status/$pause"` guard) accepts
  only `ready_for_release/ready_for_release` (or an already-converted `awaiting_merge`). Anything else is refused:
  `run file reads status … / pause_reason …, not ready_for_release`.
- `wave-build` (`loomwright/scripts/automate-wave.sh`, header step 4 `refuse`) refuses a wave whose lane is not
  parked `awaiting_merge` or `ready_for_release`.
- The coordinator may not write into a lane after launch (`skills/automate-loop/lanes.md` §"The per-wave loop"
  step 6), so it cannot rewrite the lane's park itself.
- Resuming the lane (`lane-launch --resume-run`) re-reconciles an open PR and stays parked. The only `escalated`
  re-check at RECONCILE is `escalation_cause: validation_unrun` (`skills/automate-loop/per-item-loop.md`
  §"Re-check at RECONCILE"). Nothing re-drains a `findings` escalation after the head moves.
- `skills/automate-loop/lanes.md` documents this only for single-lane mode ("the owner resolves the PR or abandons
  the lane"). For an N > 1 wave it says nothing.

What happened instead: the coordinator narrowed wave 1 by hand (`current-wave --wave 1 --items <L2,L3>`, a Progress
line naming the owner's decision), built a two-lane wave PR (#793), and #781 merged on its own. That cost a
separate merge, a separate release step, and a lane left `escalated` until its merge watcher closed it out.

## Invariants to keep
- The coordinator never writes into a lane's run file; a lane's park changes only through the lane's own engine or
  a sanctioned helper (`lane-convert-ready`, `lane-remove --abandon`).
- `escalated` never becomes merge-ready on the owner's word alone: a re-drain verdict on the current PR head is the
  evidence (fail CLOSED).
- Single drain per pass, at most one owner-requested re-drain per item, strictly sequential (CLAUDE.md
  §"`/automate` single-drain ownership").
- The owner's launch authority for any lane resume (`lanes.md` §"Launch authority").

## Suggested direction (to decide at promotion)
1. **Lane re-drain on resume.** `lane-launch <lane_dir> --owner-command '<cmd>' --redrain`: for a lane parked
   `escalated` whose PR is OPEN and whose head moved since `owned_drain_started`, the lane runs one owned drain on
   the new head. `READY` ⇒ the normal GATE (validation gate, dismissed-findings step) ⇒ `ready_for_release`.
   `ESCALATED` ⇒ parks `escalated` again. This counts against the item's one re-drain allowance.
2. **Or a narrower helper.** `lane-convert-ready <lane_dir> --from-escalated` converts only when the lane's
   `review-heal-result` sidecar reads `READY` with `ready_sha` equal to the PR's current head (live `gh` read).
   Otherwise it refuses and names what is missing. This needs a lane-side sidecar from a re-drain, so 1 is probably
   still required.
3. **Name the fallback.** Document "narrow the wave" (`current-wave` with the remaining items, plus a Progress line)
   as the sanctioned way to ship the rest of a wave while one lane stays escalated, so it is not improvised again.

## Tests
- An escalated lane with a moved head and a READY re-drain reaches `ready_for_release` and then `wave-build`
  accepts it.
- An escalated lane with an unmoved head is refused, by name.
- A second re-drain is refused (the allowance is used up).
- A coordinator-side write into the lane is never needed: assert the lane's run file is written only by its own
  engine.
- Mutation control: drop the head-moved check ⇒ the unmoved-head leg turns red.

## Likely touches
`loomwright/scripts/automate-lanes.sh`, `loomwright/scripts/automate-lanes.d/launch.sh`,
`loomwright/scripts/automate-lanes.d/remove.sh`, `loomwright/scripts/automate-next-step.sh`,
`loomwright/skills/automate-loop/lanes.md`, `loomwright/skills/automate-loop/per-item-loop.md`,
`loomwright/scripts/test-automate-lanes.d/`
