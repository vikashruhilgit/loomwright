<!-- bump: minor -->
Loop inventory: every branch and rule in the loop prose, kept honest by a test (automate-speed/04)
Four new tables under `loomwright/docs/loop-inventory/` (automate-loop, supervisor, review-heal,
launch-pad-autonomous) list every branch and rule the `/automate` → `/autonomous` → Launch Pad / Supervisor →
`/review-pr` prose states, one row each, with its kind, where it lives, what implements it and what tests it,
plus a gap list of untested rows ordered by risk. The new `loomwright/scripts/test-loop-inventory.sh` fails
whenever the prose and the tables disagree: a `###`/`####` heading with no row (fenced and split-index blocks
exempt), a prose anchor that no longer exists, a `script:<file> <sub>` cell with no matching `case` arm, a
duplicate id, a test cell naming a missing file, or a gap list or count that differs from the table, which the
test recomputes. Its fixture legs prove each check red on scratch copies. Nothing in the loop changes; the
vendor-coupling manifest gains measured allowances for the four tables, which quote their source prose
verbatim.
