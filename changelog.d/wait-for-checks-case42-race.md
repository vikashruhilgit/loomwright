<!-- bump: patch -->
`test-wait-for-checks.sh` case 42 can no longer pass a mutant that never slept
Case 42 ran the wait with a 1 s per-call limit. Bash's `SECONDS` counts whole seconds, so on a busy CI runner
the first poll could cross that limit before the loop reached its sleep, and the mutation control then saw no
difference between the script with the sleep clamp and without it. The case now uses a 3 s limit, the stub
counts its polls, and a run that never reached the sleep is inconclusive: retried up to 3 times, then failed as
inconclusive, never read as a pass or as an overshoot. Test-only; no runtime script changed.
