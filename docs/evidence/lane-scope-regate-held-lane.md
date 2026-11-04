# Evidence — lane-scope-regate Part B, Validation 2 (a held lane and one AUT-OVERLAP question)

**Status: NOT RUN.** The live `/automate --parallel 2` run that Validation 2 asks for (two fixture items whose
declared Touches are disjoint but whose briefs share a file) has not been run yet. This file therefore carries no
verdict line, and the validation gate reads the step as unrun until a live run's output is recorded here.

## What is covered without the live run (deterministic, hermetic)

These suites run the real scripts on fixture lanes. They are not a live `/automate` session:

- `bash loomwright/scripts/test-automate-next-step.sh` leg F4k: inside a lane whose `lane.json` reads `parallel: 2`, a saved
  Launch Pad report writes `launch-pad saved <brief>` and then parks `scope_hold` (`## Status: paused`, the item still
  `running`, no Supervisor spawn). Once released, a bare driver call resumes at the Supervisor phase on that brief.
  `parallel: 1` and no lane.json do not hold. There are three pin mutants.
- `bash loomwright/scripts/test-automate-lanes.sh` part 08, groups SG / SD / SI / SGd / SM: two lanes whose saved
  briefs share `src/shared.ts` print `overlap — src/shared.ts shared with L1 (saved brief)`. `lane-status --inbox`
  lists the held lane under `AUT-OVERLAP` with the catalog's four labels, and `--json` reads `scope_hold` as a
  waiting step. `lane-scope-decide` handles continue, serialize, defer and revise, and the coordinator's Stop hook blocks
  while the hold is undecided. There are seven pin mutants.

## To record when the live run happens

1. The fixture items and the exact `/automate --parallel 2` command.
2. `lane-status <parent_runfile>` output showing the second lane in `scope_hold` before its Supervisor phase.
3. The ONE coordinator `AUT-OVERLAP` question (header, text naming the shared file, labels).
4. Only then, the column-0 verdict line the validation gate reads.
