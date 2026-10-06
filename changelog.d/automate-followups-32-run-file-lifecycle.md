<!-- bump: minor -->
/automate run-file lifecycle — `## Current` moves only through a helper
Part C: new `automate-helpers.sh current-set` is the only writer of the run file's `## Current` item and
`pause_reason` lines. It has an item form and a run-level form, validates values against the enums, and resets an
omitted `pr`/`branch` to `null` when the item changes. It refuses bad input with exit 1 and leaves the file
byte-unchanged. `closeout`'s `## Current` reconcile now writes through it. `progress-append` exits 3 with
`current_not_set: <line>` (and still appends the line) when a `picked`, `ran /autonomous` or `owned drain started`
line lands on an unset `## Current`, or when a `picked` line names a different item while the current one is not
done. New `current-rebuild` repairs an unset `## Current` at RESUME, and a `done` one that still names the previous item after a later `picked` line (the case the `progress-append` check lets through): it takes the item from the last `picked` line
and the PR only from a later `ran /autonomous` line, and it always sets `status: running`. The new
`closeout_leftover` `pause_reason` is added to the SKILL §3 enum and to the RESULT_SCHEMAS §AUTOMATE_RUN enum and
table. Lane w1-10 (run `automate-2026-10-04-103627`) wrote `## Current` only once, at creation; that is the bug this
fixes.
Part B: a finished run now finalizes itself. `closeout` still never writes `done`, even after checking off the last
Queue item, so every finished single-item run stayed `paused` / `awaiting_go` with an empty Queue and every later
RESUME listed it. New `finalize-empty <runfile>` (in `automate-trail.sh`, dispatched like `closeout`) acts only on a
run that is `paused` with `pause_reason: awaiting_go`, has no unchecked Queue row, and whose `## Current` item reads
`status: done`. Under its own run lock it writes `## Status: done` and `pause_reason: null` in one validated
`runfile-write`, appends `auto-finalized: queue empty after closeout`, and runs `trail-pr --reason done` (the same call
the Queue-resolved termination makes). With branch mode off it then un-stages that run's trail paths so they cannot
ride into the current run's next commit. It always exits 0, and a second call is a no-op. `resume-glob <dir>
--finalize` (SKILL §4 step 1) runs it on each candidate and lists only the runs it did not finalize; plain
`resume-glob` output is unchanged. With branch mode off, finalizing N runs can open up to N trail PRs (one per run,
never merged by the engine). This is accepted and documented in SKILL §4.
Part A: close-out leftovers are never silently skipped. New `automate-helpers.sh closeout-classify` reads one
`closeout` invocation's output and checks every `closeout:` line against an explicit table of every string
`automate-trail.sh` prints. A line containing `kept`, any refusal, a refused sync, and any line not in the table is a
leftover. It prints `complete`, or one `leftover` row per leftover carrying the run id, item and PR. With `--record` it
appends `closeout: nothing to close out — <item>` (at most once per item per run) when an idempotent re-run changed
nothing. SKILL §6 step 1 adds the close-out leftover gate. Interactive runs ask once for up to 4 leftovers (Clean up
now / Keep and continue / Stop); "Clean up now" re-runs `closeout`, which keeps its own safety checks. Non-interactive
runs park with the new `pause_reason: closeout_leftover`. New `closeout-others` (in `automate-trail.sh`) runs at
start, before the run lock. It closes out every other run whose `## Current` item has a merged PR, then un-stages that
run's trail paths when branch mode is off, and records one `cross-run closeout <run_id> <item>: …` line (with no PR
URL) in the current run. `session-resume.sh` now prints a line per live merge watcher on every SessionStart (local
only, so startup stays offline). On resume, clear and compact it also prints a line per in-flight item whose PR is
merged but not closed out. That check makes at most 5 time-bounded `gh pr view` calls and prints `merge state
unverified` when `gh` is absent, failing or slow.
