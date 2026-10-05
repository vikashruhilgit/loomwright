<!-- bump: patch -->
test-lens-run.sh case H no longer fails when two suites run at once
Case H ("hung CLI times out, process group killed, no leftover children") failed whenever two `ci-local.sh --force`
runs overlapped (the normal case since shared CI slots): its leftover check was a machine-wide
`pgrep -f loomwright-test-stub-cli`, so the other suite's live stub counted as a leftover, and its 1-second timeout
could expire before a loaded machine even exec'd the stub. Every per-run name now carries `RUN_TAG` (the run's pid):
the stub CLI and the provider-table entry `provider-teststub<RUN_TAG>.sh`, so concurrent runs in one checkout no longer
delete each other's provider file. The leftover check is scoped to what this run started: `kill -0` on the recorded
leader and child, plus `pgrep -g` on the recorded pgid after checking it is the leader's own group and not the test's.
The stub records its pid/pgid first, the timeout is now 5 s, and the kill check polls for up to 10 s. New case K holds
a second `lens-run.sh` instance alive on a release file while case H's hung CLI times out, and asserts the scoped
checks pass beside it. `test-lens-compare.sh` names its provider-table entries per run the same way. `lens-run.sh` is
unchanged.
