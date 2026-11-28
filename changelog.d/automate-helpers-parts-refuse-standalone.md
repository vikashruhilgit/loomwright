<!-- bump: patch -->
The automate-helpers test parts refuse to run on their own, and their fixture `cd` groups stop when the `cd` fails
A part under `test-automate-helpers.d/` is meant to be sourced by `test-automate-helpers.sh`, which builds the
helper bundle and the `ok` / `no` counters its legs use. Most parts had no guard, so run on their own with
`bash <part>` they found none of that, ran whatever fixture commands they could in the caller's directory and
exited 0, the same shape that deleted a live `/automate` run file in the trail parts (issue #994). Every part's
first command is now the re-exec guard four of them already carried: run on its own, the part hands off to
`test-automate-helpers.sh <its own name>`, so its real legs run and nothing else does, which keeps a pin mutation
that names a part working. The fixture `cd` groups that ran a `find` after `cd "$X" &&` now open with
`cd "$X" || exit 1`, and the runner defines, before it sources any part, the same empty-operand-refusing `cd` as
`test-automate-trail.sh`, because macOS `/bin/bash` 3.2 treats `cd ""` as a successful no-op. A new part,
`20-standalone-guard`, carries the trail runner's static scan for a `cd` group that would run on after a failed
`cd` (with its planted-shape control), a leg that checks a group stops for an empty and for a missing directory
and that `cd` is the runner's function, and a replay: each part is first checked to have the exact guard as its
first command, and a part without it is reported as a failure and never run; a copy of each guarded part is then
run on its own from a scratch checkout holding sentinel `.supervisor/automate/` files beside a stub runner, which
must log the part's own name while the sentinels stay. The new part reads the runner's own part list. Test-only;
no runtime script changed.
