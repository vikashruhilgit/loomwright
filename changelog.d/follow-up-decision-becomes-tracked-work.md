<!-- bump: minor -->
Follow-up decisions become tracked work
A `follow-up` decision on a dismissed review finding no longer only rewrites the draft's Decision line and leaves it in `proposed/` with no age.
The `/backlog` board gains a `follow_up` state: a `proposed/*--dismissed-*.md` draft whose first Decision is `follow-up` reads `follow_up` with evidence `follow-up <N>d — run <run_id>, PR <url>`, aged from the run's `dismissed-decisions` ledger, else the file's mtime (labelled, and labelled again when the ledger is unreadable).
The new owner-run verb `automate-helpers.sh followup-bundle <draft>... --into <queue-dir>/<NN-slug>.md [--confirm]` validates every draft and the target before any write, prints the one `## Status: pending` requirement file on a dry run, and under `--confirm` writes it (provenance, `> `-quoted findings, acceptance criteria, the drafts' Touches union) and removes exactly the named drafts.
`dismissed-drafts` no longer reports or counts a kept follow-up draft that was bundled away.
`followup-nudge` prints one advisory line when the oldest follow-up is older than `LOOMWRIGHT_FOLLOWUP_NUDGE_DAYS` (default 14); the SessionStart startup arm and the interactive `/automate` PICK relay it, and neither asks nor blocks.
The `Follow-up (keep draft)` option note at both decision asks now names the `follow_up` state and `followup-bundle` instead of "promote it by hand".
Nothing is ever enqueued automatically.
