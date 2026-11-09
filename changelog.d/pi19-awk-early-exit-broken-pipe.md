PI19 no longer fails on a broken pipe, and a lint rule keeps writers out of early-exiting awks
`test-read-token-ledger.sh`'s PI19 helper piped `printf '%s\n' "$1"` into an awk that exits at the first
row past the item. When awk exited while printf was still writing, printf failed with EPIPE, and under
`pipefail` that became the helper's verdict, so a correct report read as "phase row exceeds item" (ci run
42559229895, `printf: write error: Broken pipe`). The helper and its sibling `pi_rows_after` now read a
here-string. `test-no-pipefail-grep-q.sh` gains rule 4: a builtin writer (printf / echo) piped into an awk
whose inline program has an `exit` outside its END blocks is flagged in every shell script. The 25 other
sites it found (17 files, among them `proc-registry.sh`'s `_pr_snap_get`, `janitor-report.sh`'s
`_jr_snap_get` and `setup-routing.sh`'s `verdict_of`, functions whose return status was that pipeline's)
were rewritten to the same here-string form, so its baseline is empty.
