<!-- bump: minor -->
Phase 4.5 reviewer replays its own past misses before a reviewer change ships
New on-demand `claude plugin eval` suite `loomwright/evals/phase45-reviewer/`: each case stages one merged PR's
pre-drain diff in a scratch repo, renders the exact round-1 Phase 4.5 reviewer prompt from the plugin under test, and
spawns the current code-reviewer once. `lib/run.sh` grades the replies deterministically after the run against the
repo-root table `docs/evidence/phase45-reviewer-corpus.tsv`, so no expectation enters the sandbox, and prints
`caught: X/Y` with per-case rows and the clean controls' noise. New `loomwright/scripts/build-reviewer-replay-case.sh`
proposes miss and control candidates from local git (`--list`), dry-runs a case (`--pr <N>`), and writes one case
dir and one table row only with `--confirm`. `AGENT_GUIDELINES.md` and the PR template now require the before/after
caught count for a PR that edits the code-reviewer prompt, `skills/self-heal-advisory/` or Phase 4.5 routing. CI
runs only the model-free selftest, plus an always-CAUGHT grader mutant that must turn it red, in
`test-build-reviewer-replay-case.sh`; no workflow or test runs the model-backed eval. This release ships two clean
controls. The miss cases and the model-backed baseline are pending owner confirmation
(`docs/evidence/phase45-reviewer-replay.md` §Baseline).
