<!-- bump: minor -->
`/automate --merge-parked <run_id>` merges one parked item through the existing gate
`automate-next-step.sh --merge-parked <automate_dir> --run <run_id>` takes ONE item parked `awaiting_merge` after a
READY drain and puts it through `gate-eval`, the one merge executor, unchanged. On `MERGE` it closes the item out
with its trail, checks it off and stops: the run pauses `awaiting_go` while items remain, or ends `done`. It never
starts a drain, a lane or the next item, and `## Run Config` keeps `mode: safe`. It refuses a lane, a `--parallel`
parent and any other `## Current`, and nothing is written. Before the gate it holds the run lock and parks the item
(still `awaiting_merge`) when the recorded `ready_sha` is missing or is no longer the live head, when the checkout
is not on the PR head, when there is PR feedback newer than `ready_at`, or when the base moved (`behind_by` > 0).
The gate inputs now live in the run file, because a `--resume` wipes the sidecar: `drain-result` records a READY
drain's `- ready_sha: | ready_at: | termination_reason:` line in `## Current`, and `current-set` drops it when the
item changes. `--resume --auto-merge` on a parked open PR now says the flag was not applied and names
`--merge-parked`. Documented in `skills/automate-loop/resume.md` "Merging one parked item", `run-file.md`,
`helpers.md` and `commands/automate.md`; issue #829.
