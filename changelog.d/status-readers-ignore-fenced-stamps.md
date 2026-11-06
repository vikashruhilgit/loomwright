<!-- bump: patch -->
A stamp quoted in a code fence no longer makes a requirement read as done, and `/propose` honours every done stamp
Requirement files quote stamps as examples. `is_done` matched any line, fences included, so an unstarted proposal that showed the closeout block in a code fence was listed done by `/backlog` and never queued by `resolve-folder`.
`propose-work.sh` and `propose-domain.sh` had the opposite gap: they only accepted a bare `## Status: done`, so a `done (PR #N, merge <sha>)` or `done_with_escalation` stamp did not supersede a candidate and finished work could be proposed again.
The new `automate-helpers.d/status-stamp.sh` is now the one reader for `is_done`, `is_not_ready`, `reconcile-jobs.sh`, the lane removal check and both `/propose` bases. A fence that never closes is not treated as a fence and a failing filter keeps the plain answer, so a real stamp is never hidden and merged work is not re-run.
