<!-- bump: minor -->
A stranded brief no longer reads as a live run at question time, and done/ briefs missing their Outcome are reported
`notify-desktop.sh` (marker 1) and `send-webhook.sh`'s paused-event gate used to treat any brief in
`.supervisor/jobs/in-progress/` as "Supervisor is active". A brief stranded there by a run that died before the
completion tail's move therefore turned every later AskUserQuestion in that repo into a banner and a paused webhook.
Both gates now ask the new `reconcile-jobs.sh --not-stranded-count`, which reuses the reconciler's offline
classification with no forge call and no network. A brief counts only when it is not proven `stranded_merged` or
`stranded_closed`, and `unknown` still counts. Both gates fail toward notifying: an unreadable reconciler or an empty
answer means "live". Both run their two cheap markers first, so a live run rarely pays the reconciler's cost (about
170ms per in-progress brief on a 300-merge history). New `reconcile-jobs.sh --missing-outcome [--porcelain]` lists the
`done/` briefs that have no `## Outcome` section and writes nothing. It uses a strict heading rule: `## Outcome`
exactly, or followed by whitespace or a colon, outside a code fence. A variant `## Outcome (Supervisor v4 — …)`
counts, and `## Outcomes Rubric` does not. The repair guard now uses the same rule, so a brief that already carries a
variant Outcome heading is no longer stamped a second time. Re-measured on this repo's `done/` on 2026-10-12, the
strict rule finds 27 of 187 briefs missing an Outcome; the earlier loose prefix match reported 10. Executed tests and
in-suite mutants in `test-notify-desktop.sh`, `test-webhook.sh` and `test-reconcile-jobs.sh` cover all of this.
