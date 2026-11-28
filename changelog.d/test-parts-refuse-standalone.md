<!-- bump: patch -->
The trail and meta-sync test parts refuse to run on their own, and their fixture `cd` groups stop when the `cd` fails
A part under `test-automate-trail.d/` or `test-meta-sync.d/` is meant to be sourced by its runner, which sets up the
temp root its fixtures live in. Run on its own with `bash <part>`, it had no temp root, and a fixture step such as
`( cd "$P" && git checkout -q -- README; rm -f stray.txt; rm -f "$AUTD"/*.md )` ran its `rm` in the caller's
directory, because a `;` does not stop after a failed `cd`. Run from a live checkout, that deleted the `/automate`
run file and its run history (issue #994). Each part's first command now checks that its runner sourced it (the
runner's part loader is defined and its temp root exists), and otherwise prints one line naming the runner and
exits 2 before running anything, the guard the lanes parts already carry. Every fixture `cd` group in those parts
now opens with `cd "$X" || exit 1`, and each runner defines a `cd` that refuses an empty operand before it sources
any part, because macOS `/bin/bash` 3.2 treats `cd ""` as a successful no-op and would run the group on in the
caller's directory. Each runner gains a static scan of its own parts for a `cd` group that would run
on after a failed `cd`, with a control that plants the unsafe shapes, and a replay leg. The replay first checks that each part's first
command is the exact guard, and reports a part without it as a failure without ever running it. It then runs each
part on its own from a scratch checkout holding sentinel `.supervisor/automate/` files and checks the exit code, the
runner line and that the sentinels are still there. A further leg checks that a group stops for an empty and for a
missing directory, and `test-meta-sync.sh` checks that the scan, the first-command check and that `cd` are
byte-identical in the two runners. Test-only; no runtime script changed. Evidence:
`docs/evidence/test-parts-standalone-guard.md`.
