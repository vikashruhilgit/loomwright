<!-- bump: patch -->
closeout re-run after its own trail PR merged no longer opens a skip-only trail PR
`automate-trail.sh closeout` gated its `## Progress` append on "some step did something", and the `main` sync
counted. A sync is checkout housekeeping, and `main` moves for reasons unrelated to the item, most often because
the owner merged this run's own trail PR. So a `--resume` RECONCILE re-run whose item steps all skipped still
appended its six skip lines, which gave `trail-pr --reason closeout` a diff and opened a fresh trail PR holding only
those lines (run automate-2026-10-01-142337: trail PR #329 merged, then the re-run opened #330). Every later re-run
would repeat it. A `synced` line no longer counts: the step lines reach `## Progress` only when an item step
(removed / stamped / checked / reconciled, or a non-skip brief repair) changed something, so the re-run leaves the
run file byte-identical and its trail reads `skipped — trail already up to date`. SKILL §6 "Post-merge close-out"
now states the idempotency contract with the sync carve-out. `test-automate-trail.sh` gains a leg that runs closeout,
squash-merges its trail PR, re-runs closeout and asserts the sync moved, the run file and requirement are
byte-identical, the trail line is the up-to-date skip and no PR was opened, with a mutation control that restores
`did=1` on the synced line and turns it red.
