<!-- bump: minor -->
One registry for every detached process the plugin starts (proc-registry.sh register / list / reap)
The new `loomwright/scripts/proc-registry.sh` records each background process the plugin launches in a
user-scope registry (`~/.claude/loomwright/procs/`, `LOOMWRIGHT_PROC_REGISTRY_DIR` overrides it, and under
`HERMETIC_TEST_ENV=1` it lives in the hermetic shim dir). `list` classifies every entry `running`, `overdue`,
`orphaned` or `finished`, and `reap` (a dry run unless `--apply`) stops only overdue or orphaned entries whose
live start time and command line still match, so a recycled pid is never signalled. Its header comment is the
contract, including the per-kind lifetime caps. Every launcher now registers, fail-safe and fully redirected, so a
registry failure never changes a launch: the merge watcher (its own pid, its own cap), the review drain wrapper
(its own pid, from inside the detached wrapper), the auto-postmortem `claude -p` (registered asynchronously after
its exec), each lane's `_lane-run` wrapper and each phase session's wrapper. Each launcher has a hermetic test leg
with a mutation control that deletes its one registration line. `run-self-tests.sh`'s watchdog now starts each
test in its own process group and stops the whole group on a timeout, so a double-forked child of a timed-out test
no longer outlives it.
