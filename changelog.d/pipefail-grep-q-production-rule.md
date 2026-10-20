<!-- bump: patch -->
The pipefail `grep -q` gate now covers production scripts
`test-no-pipefail-grep-q.sh` had two rules. Rule 1 banned any producer piped into `grep -q` under `pipefail`, but
only in test files. Rule 2 banned only the builtin writers (`printf`, `echo`) piped into `grep -q`. A non-builtin
producer in a production script fell between them, and that is how the wave-7 lane L22 false `.died` shipped:
`lanes_run_wrapper` in `automate-lanes.d/launch.sh` decided `.died` from `tail | grep -q` under automate-lanes.sh's
`set -uo pipefail` (fixed in PR #643). The new rule 3 covers every shell script outside rule 1's set that runs under
`pipefail`. A script is in scope when it sets pipefail with `set` at a command position, or when a script in scope
sources it, followed transitively. It counts as sourced when it is an `X.d/<m>.sh` module of `X.sh`, when a
`. <path>/<name>.sh` line names it, or when a `. "$VAR"` line sources a VAR assigned a `*.sh` path in the same file.
Today that is 153 scripts, 48 of them through sourcing only. Builtin-writer sites stay with rule 2, so no site is
counted twice. Pre-existing sites use a per-file ratchet, `PROD_BASELINE`, with rule 2's OVER / UNDER / STALE contract.
The baseline is empty because all eight live sites were rewritten to `grep -q PAT < <(producer)`: three in
`automate-next-step.sh` (the 429 hint, the validation-gate tail check and the checkoff queue check), three in
`build-capabilities.sh`, one in `build-insights.sh`, and the launch.sh line, rewritten exactly as PR #643 does so
the two PRs merge cleanly in either order. Against the pre-fix tree the gate flags exactly those eight. New detector
controls cover the L22 module shape (flagged, and missed by rules 1 and 2 alone), a planted production violation, the
`< <(producer)` form (not flagged), literal, variable, glob-named and two-hop sources, and five scripts that never run
under pipefail. Rule 1's test-part lookup now checks the parent directory's own name, so a file under any `test-…`
directory, such as the gate's own mktemp dir, is no longer taken for a test part. Known limits: a source path built
any other way, and a production script sourced only by tests, are not followed.
