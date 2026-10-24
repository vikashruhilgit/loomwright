<!-- bump: patch -->
Telemetry pins MEDIUM/LOW and per-category code-review counts, and Rubric B describes only reachable scores
`test-telemetry-threads.sh` gains a `mixed` code-review fixture (HIGH, MEDIUM and LOW `new` findings plus a LOW
`nit`, placeholder text only). T2 asserts its per-severity and per-category counts through the real core's dry-run,
and a new T8 mutant (e), which counts severities only at BLOCKING/HIGH, proves those assertions catch the regression
that read only rendered BLOCKING/HIGH lines. Before this, the suite pinned only the per-round total and the drift
category. `score_code_review()` loses its unreachable `base = 7.0` branch, whose condition was a strict subset of the
`9.0` branch before it, and the unused `new_medium`/`new_low` counts. `docs/TELEMETRY.md` §"Rubric B" drops the
matching table row, and its worked example now gives the score the code has always returned for that input (`9`,
bucket `high`). No score changes, and every golden is byte-identical. Evidence:
`docs/evidence/af15-telemetry-count-pins.md`.
