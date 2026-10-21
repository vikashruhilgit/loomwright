An owner wait in /automate no longer reads as a failure
`close-stranded-run.sh` (SessionEnd) now exempts a fresh `/automate` phase session that ended to ask
the owner, as it already exempted a `--parallel` lane. A phase dir under the checkout's
`.supervisor/automate/<run_id>.phase/<phase>/` is the session's when `LOOMWRIGHT_PHASE_DIR` names it, or
when its `session` file records the payload's `session_id`. If that dir's inbox holds an unanswered
question, the hook writes nothing. Before, the hook marked the run `failed`, and the resumed
Supervisor's FINALIZE write-marker then refused `no_active_session` (#652). Both scopes read one inbox
predicate. `lane-convert-ready`'s awaiting-merge re-run treats closeout's `pr not merged` gate skip as
the wait for the owner's merge (`closeout waits for the merge`). It used to name that skip a close-out
leftover and send an `automate-closeout` `leftover_gate` warn on every retry (#659).
