<!-- bump: minor -->
An unrun must-pass running-system Validation step blocks READY (validation_unrun)
Before an `/automate` item's READY park (`awaiting_merge`, or `ready_for_release` inside a lane) the engine now runs
`automate-helpers.sh validation-gate <runfile> <item> <pr_url>`, which checks that every "Running system" step of the
item's `## Validation` section has pasted, fenced evidence in the PR body. A step with no evidence, a step listed under a
"Not verified" / "Not run" PR-body heading, a FAIL, or an unreadable item file or PR body reads `unrun` (fail CLOSED),
and the item parks `escalated` with the new engine-side `escalation_cause: validation_unrun` naming the step, until the
step is evidenced (RECONCILE re-checks on `--resume`) or the owner waives it through the new human-only `AUT-WAIVE`
gate. The waiver is one `## Progress` line carrying the step and the owner's own words; a run that cannot ask never
waives. `lane-readiness` and the gate share one Validation reader, which now also parses `- ` bullet entries and treats
a "Not verified" heading as NOT-RUN. `current-escalation` accepts `validation_unrun`, and the merge watcher never
reports such a park as now mergeable. Honest limit: `gate-eval` does not run the validation gate itself; the engine's
GATE prose runs it before `gate-eval` and before every READY park.
