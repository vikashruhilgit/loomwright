<!-- bump: patch -->
The two longest self-tests run as concurrent pool groups
`test-automate-next-step.sh` and `test-automate-trail.sh` each ran every leg in one process: 700–755 s on a quiet
machine, 78–84 % of `run-self-tests.sh`'s 900 s per-test cap. At load average 32–34 on 2026-11-02 both hit the cap
(exit 124) and stopped `wave-build` before its push, although every assertion they reached passed. The pool runs
one job per `test-*.sh`, so each suite is now three groups of its `.d/` parts: group 1 from the suite file, groups
2 and 3 from `test-<x>.2.sh` / `test-<x>.3.sh`, which only exec `--group <g>`. The new
`loomwright/scripts/part-groups-lib.sh` holds the one group map check, which fails closed on a part in no group,
a missing or extra pool entry, or an unknown argument (self-test `test-part-groups-lib.sh`, with mutation controls).
`--all` still runs a whole suite in one process. Every leg, assertion and mutation control moved verbatim: the
next-step sections went into `test-automate-next-step.d/`, and the trail helpers several parts share went into
`test-automate-trail.d/00-shared.sh`. `ci-local.sh --affected` now maps a changed script or `test-<x>.d/` part to
`test-<x>.sh` and its `test-<x>.<g>.sh` siblings too, and the CI shard weights list the new entries.
