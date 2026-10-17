<!-- bump: patch -->
lane-create takes a fresh lane number 1..99 for every --parallel N
`lane-create` capped the lane number at 1..10 for every caller except single-lane mode, so a multi-wave
`--parallel 4` run ran out of numbers after its tenth lane (run automate-2026-10-15-163325 used L1–L9
across waves 1–2, so wave 3 got only L10 and its next lane died `lane number must be 1..10 (got '11')`). The lane number is the lane's
identity across the whole run, not the parallel count: every caller now takes 1..99, and a number already
in the run's lane table (live, removed or abandoned) is refused with `refused — lane L<n> already used in
this run (each lane takes a fresh number)`, nothing created. Before, an N > 1 run silently replaced the
table row and would have overwritten the earlier lane's `<run_id>-L<n>` run file and sidecars on the
metadata branch. The check is repeated under the table lock. `--parallel` itself stays 1..10, and omitting
it (N defaults to n) now names the missing flag for n > 10. `test-automate-lanes-modules.sh`'s
verbatim-move checks compare the split commit, not the working tree, with the pre-split file, so a later
edit to a lane module no longer fails them. The coordinator picks n = 1 + the highest number in the table
(`skills/automate-loop/lanes.md` §14 step 6).
