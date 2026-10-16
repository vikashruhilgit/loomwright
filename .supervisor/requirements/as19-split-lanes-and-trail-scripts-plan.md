# Task Plan — as19-split-lanes-and-trail-scripts

Source brief: .supervisor/jobs/in-progress/2026-10-16-split-lanes-and-trail-scripts.md (Plan-Review PASSED)
Base: main @ 051553e (supersedes every `142540b` in the brief — AC3, AC5, AC6, AC11)
Review gate: deterministic outputs_verified + tests/lint per task; Phase 4.5 integrated review once after FINALIZE (no per-subtask reviewer).

## EPIC as19 — split automate-lanes.sh / automate-trail.sh into sourced modules (move-only, D6)

- [ ] as19-1 lanes split (AC1, AC3, AC4, AC5, AC6, AC13 lanes halves) — blocked by: none
  - Base sizes at 051553e: automate-lanes.sh 3862, test-automate-lanes.sh 3172 (brief's 3852/3149 predate PR #569)
  - Re-measure base test total on a clean 051553e worktree before splitting
- [ ] as19-2 trail split (AC2, AC3, AC4, AC5, AC6, AC13 trail halves) — blocked by: none
  - Base sizes: automate-trail.sh 2241, test-automate-trail.sh 3511
  - ADDED constraint: the `ASM="$HERE/fixtures/automate-loop-split/assemble.sh"` line and its two assemble calls stay in the RUNNER (shared setup) — test-automate-loop-split.sh §H greps the runner file for `fixtures/automate-loop-split/assemble.sh`
- [ ] as19-3 integration (AC7, AC8, AC9, AC10, AC11, AC12, AC14) — blocked by: as19-1, as19-2
  - ADDED: re-point test-no-fixed-sleep-race.sh BASELINE row `3 loomwright/scripts/test-automate-lanes.sh` to the runner/part paths that hold those sleeps after AC7 widens the scan (sum stays 3; never raised)
  - ADDED: run test-automate-loop-split.sh (its §H READERS names test-automate-trail.sh) in the AC10 consumer sweep
  - DECISION FOR SUPERVISOR: §H's raw-read wiring checks scan only the trail runner, so moved parts escape them (weakening, not breakage). Either add test-automate-loop-split.sh to as19-3 lanes to also scan test-automate-trail.d/*.sh, or record it as a follow-up in the evidence file
