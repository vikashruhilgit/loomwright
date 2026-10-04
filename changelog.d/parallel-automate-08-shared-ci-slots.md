<!-- bump: minor -->
Every checkout of one repo shares N CI slots, one fair queue and one pass cache
`scripts/ci-local.sh` kept its one-run-at-a-time lock and its PASS cache in the git-common-dir, so each lane clone
had its own lock and cache and every run took every CPU: two lanes on a 12-core Mac ran 490-820 s instead of 190-380
s at a load average of 27. The new shipped helper `loomwright/scripts/ci-slot.sh` keys its state by repository
identity (a hash of the normalised `origin` URL, host included; the git-common-dir only when there is no `origin`)
under `${XDG_STATE_HOME:-$HOME/.local/state}/loomwright/ci-slots/<repo-key>/`, so the primary checkout, linked
worktrees and lane clones of one repo share one pool of N slots (default `max(1, floor(CPUs / 6))`, override
`LOOMWRIGHT_CI_SLOTS`). Slots are claimed by count: a run with N starts only while fewer than N live suites run
across the whole pool. A waiter takes a ticket under an atomic `ln -s <pid>` mutex (it carries its holder pid from
the moment it exists, so a TERM can never strand a pid-less lock, and every lock wait honours the acquire deadline)
and goes ahead of a later ticket unless that earlier waiter is at its own cap; dead holders, dead queued pids and a
mutex left by a killed process are taken over. A slot is recorded under
the caller's `--pid`, never the helper's own short-lived pid. `ci-local.sh` now acquires a slot (still bounded by
`CI_LOCAL_LOCK_WAIT`), prints its queue position every 30 s while waiting, runs with `SELF_TEST_JOBS = max(2,
floor(CPUs / N))` unless the caller set `SELF_TEST_JOBS`, and keeps its PASS stamps in the shared dir, so a tree that
passed in any clone returns `PASS (cached)` in every other. Sharing assumes every checkout's `origin` is the same
remote URL. On a machine with 12 or more CPUs a solo run now gets a share of them rather than all of them;
`SELF_TEST_JOBS` restores every-CPU runs, and `LOOMWRIGHT_CI_SLOTS=1` makes a run wait until no other suite runs and
then use every CPU. Strict one-at-a-time across sessions needs the same `LOOMWRIGHT_CI_SLOTS` value in every session,
because a session with a larger N may still start next to it, and a waiter with a smaller N can be passed while the
pool is at its cap. New self-test `loomwright/scripts/test-ci-slot.sh` with mutation controls for the repo key, the
ticket order and claim-by-count, plus arms for a stranded or stuck mutex;
`scripts/test-ci-local.sh` gains cross-clone cache, job-share and queued-waiter arms. `AGENT_GUIDELINES.md`
§"Pre-push: one command" and `CLAUDE.md` §"Pre-push test run?" describe the shared slots.
