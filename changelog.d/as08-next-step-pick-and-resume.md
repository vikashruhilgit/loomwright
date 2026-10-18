<!-- bump: minor -->
/automate's next-step driver runs PICK, RECONCILE and resume
`automate-next-step.sh` now drives the head of the per-item loop as well as its tail (automate-speed/08). The
new `--resume <automate_dir> [--run <run_id>|latest]` entry runs `closeout-others` and `resume-glob --finalize`
itself. It then asks AUT-RESUME (Continue, Start new or Archive). A run that cannot ask fails closed: one
incomplete run with no `--run` gets the `automate: resume_requires_flag_non_interactive <run_id>` stop and
nothing is written, and more than one gets the `resume_ambiguous` park. On continue it runs `current-rebuild`
and records the start's close-out lines. The new `--start pick` entry takes the run lock first and runs
`pick-guard`, the token ceiling, the `meta-push-failed` report and the pending-decisions ask (AUT-PENDING /
AUT-SUMMARY). RECONCILE restores a stranded config backup, runs the skip/abandon `trail-pr`, checks the
`drain_died` marker, closes a merged PR out through `closeout --session-id` and `closeout-classify`, re-checks
an unrun validation step, and parks on an open PR without picking. Then come the trail gate, the trail
un-stage, `current-set` before the `picked` line, and RUN. Fourteen PICK / RECONCILE / resume golden cases now
replay through the driver byte for byte, and new legs and mutation controls in `test-automate-next-step.sh`
cover the open-PR park, the leftover gate, the resume stops and the pick order.
The `--legacy` flag and its prose tail (`skills/automate-loop/legacy-tail.md`) are retired, so every run takes
the driver path. `/automate`'s Step 0 now reads only `SKILL.md` (which carries the new coordinator loop) and
`invariants.md` up front; the driver-owned `per-item-loop.md`, `modes-and-merge-gate.md`, `resume.md` and the
§1.5 helper table (moved verbatim to `helpers.md`) are read only when a driver call fails or the owner asks for
the step they hold, which cuts the default read set from 180686 to 50412 bytes.
