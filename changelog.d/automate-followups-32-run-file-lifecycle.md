<!-- bump: minor -->
/automate run-file lifecycle — `## Current` moves only through a helper
Part C: new `automate-helpers.sh current-set` is the only writer of the run file's `## Current` item and
`pause_reason` lines. It has an item form and a run-level form, validates values against the enums, and resets an
omitted `pr`/`branch` to `null` when the item changes. It refuses bad input with exit 1 and leaves the file
byte-unchanged. `closeout`'s `## Current` reconcile now writes through it. `progress-append` exits 3 with
`current_not_set: <line>` (and still appends the line) when a `picked`, `ran /autonomous` or `owned drain started`
line lands on an unset `## Current`, or when a `picked` line names a different item while the current one is not
done. New `current-rebuild` repairs an unset `## Current` at RESUME: it takes the item from the last `picked` line
and the PR only from a later `ran /autonomous` line, and it always sets `status: running`. The new
`closeout_leftover` `pause_reason` is added to the SKILL §3 enum and to the RESULT_SCHEMAS §AUTOMATE_RUN enum and
table. Lane w1-10 (run `automate-2026-10-04-103627`) wrote `## Current` only once, at creation; that is the bug this
fixes.
