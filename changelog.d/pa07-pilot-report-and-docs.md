The parallel pilot report, and the standing docs now describe `/automate --parallel`
The 2026-10-15 run `automate-2026-10-15-163325` (24 items, `--parallel 4`, 8 waves) is the parallel pilot. Its
report is `docs/evidence/pa07-parallel-pilot-report.md`, built only from the run's record on the metadata branch.
Every figure it takes from the run cites a run-file line. It covers wall-clock from first PICK to merge per wave
and overall, the PRs opened, every lane park and its cause, the hand steps, the wave-close stops, the leak checks
and the weekly-cap stop. Tokens per lane and a sequential baseline are listed as not measurable from the record,
with what a future run would need to log for each. The record shows no invariant broken during the run; one
invariant is not held in the shipped tree (`wave-build` runs `scripts/ci-local.sh` and `scripts/bump-version.sh` by
fixed path when the wave worktree has them); the report names it and the gitignored draft
`.supervisor/requirements/proposed/wave-build-release-command-stamp-valve.md` it was filed as, and it is not fixed here. `CLAUDE.md`'s single-drain invariant now states that it holds
per lane, that a parallel run never uses the merge executor, and that lane PRs carry fragments while one wave PR
carries the bump when the project has a release script. `README.md`'s `/automate` block gains `--parallel N` and a lanes and waves bullet, and its "will
not pick a new item" sentence is scoped to sequential mode. `PITFALLS.md` gains "A lane parked at a human gate?"
and a meta-push failed entry. Docs only, no behaviour change.
