# proposed/ - candidate work items, not a queue

These files are written by `loomwright/scripts/propose-work.sh` from
`.supervisor/floor/floor.json`. Each one states a pattern the ledger already records and
cites the entries it rests on. None of them has been decided on.

A second writer shares this directory: `/automate`'s gate writes
`<run_id>--<item>-<ih6>--dismissed-*.md` drafts for dismissed review findings; same contract:
propose-only, never enqueued. Their owner decisions live in the run's gitignored
`<run_id>.dismissed-decisions` ledger, not in an `evidence-set:` token.

`.supervisor/requirements/proposed/` is deliberately NOT an `/automate --folder` target;
promotion is a human moving a file out of it.

Nothing in this directory is enqueued, dispatched, or started by anything.

## Deleting a file here is not a durable dismissal

Deleting a proposal silences it only until the next run, which recomputes the same
evidence set and writes the same file again. The cited coordinates are the earliest
entries for that pair, so the `evidence-set:` token is stable as the ledger grows.

To dismiss a candidate permanently, paste its `evidence-set:` line into a requirement
file stamped `## Status: done` anywhere under `.supervisor/requirements/`. The next run
finds that token and suppresses the candidate, naming the file it found it in.
