<!-- bump: patch -->
Fix the case21, FU3c and BL9 CI flakes: the `mkdir` command is not an exclusive lock on Ubuntu 26.04
uutils `mkdir`, the default on `ubuntu-latest`, exits 0 when mkdir(2) returns EEXIST and the path is a directory, not only under `-p`, so two racers can both hold a `mkdir` lock.
Measured on a GitHub runner: 24 double wins in 4000 two-way races for `mkdir` and 0 in 4000 for a bash noclobber create. The token ledger's widened pair duplicated in 261 of 293 idle trials, every one with both firings holding the lock at `tries=0`, and no trial in any run timed out on the wait (highest `tries` 10 of 20).
`emit-token-ledger.sh` (shell and python steps), `followup-bundle` and `backlog-stamp` now take an O_EXCL lock file, which needs no coreutils. A stale lock directory left by an older build still reads as held and still ages out.
The ledger's wait also rises to about 10 s in both steps, because a holder stalled past the old bound (1 s in the shell, 2 s in python) still produced a duplicate. An unwritable log dir skips the wait.
New tests shim a `mkdir` that always lets racers win, and stall the holder past the old bounds. Each comes with a control that restores the old behaviour and sees the duplicate return.
The other non-recursive `mkdir` locks in `scripts/` are not changed here.
