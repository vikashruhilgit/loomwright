<!-- bump: patch -->
The review-heal drain re-opens its round when the PR head moves during the scoped wait
While draining PR #646 on 2026-10-20 the PR head moved from 5f6925e to ec3c490 after the driver's `round` step had
pinned `head_sha`. `wait-for-checks.sh` reads the live `headRefOid`, never treats a rollup for another sha as
settled, and printed `CONTINUE … pending=sha_mismatch` on every call, so `review-heal-next-step.sh` exited 3 until the
1200 s `--check-wait-timeout` ran out and the run ended ESCALATED, with every check green on the new head. The only
recovery was moving the sidecar aside, because `--start drain` refuses while a wait is armed. Now the `wait` step
reads the line through `wait-for-checks-line.sh`, and on `pending=sha_mismatch` it re-reads the head itself, because
an unreadable live head also prints `sha_mismatch`. When the re-read is a different valid sha, the call exits 3 and
the next call re-opens the same round at `round` on the new head, with a fresh wait (no `--continue`, since the new sha
is a new deadline key). The ledger check there is read-only and the round is still open, so the round is bumped once,
when it ends. The 4th re-open in one round ends ESCALATED `head_unstable`, so a head that keeps moving cannot hold the
drain open forever. The `confirm` step stays bound to the pushed sha and never re-binds. A head that moved past it,
neither the pushed sha nor the round's pre-push head, now ends ESCALATED `pushed_sha_superseded` at once instead of
after the bound. A re-read that still shows the pre-push head is a read lagging the push, and the wait goes on. Limit:
`wait-for-checks.sh` reports only at its per-call ceiling, so detecting a move costs up to one `--call-max` (540 s).
New W-leg cases in `test-review-heal-next-step.sh` cover the move, an unchanged re-read, the re-open cap, and both
`confirm` branches. Against the pre-fix driver, the five cases that test the new behavior fail.
