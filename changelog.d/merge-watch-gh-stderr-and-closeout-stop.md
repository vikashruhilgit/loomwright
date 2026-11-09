Merge watcher names why gh fails, reports a failure streak, and closeout stops it
The `/automate` merge watcher (`automate-merge-watch.sh`) discarded `gh pr view`'s stderr, so a watcher whose
every poll failed (run automate-2026-11-08-175120, 18 polls over seven hours, PR merged unnoticed) logged only
"gh pr view failed". Each failed poll now logs gh's exit status and stderr on one line (captured to the gitignored
`<run_id>.merge-watch.gh-stderr`, removed on exit), and `LOOMWRIGHT_MERGE_WATCH_FAIL_NOTIFY` (default 4, about 14
minutes of backoff) consecutive failures write one `## Progress` line and send one notify naming the last error,
saying "every poll since launch" when no read ever succeeded; a later good read records "works again" and re-arms
it. Closeout also ends the watcher from every caller: its new step 7c runs `automate-merge-watch.sh --stop <runfile>
<pr_url>`, which signals the run's marker pid only when `is_our_watcher` confirms it watches that same PR, never a
recycled pid, another PR's watcher or the watcher running that closeout, so `/automate --resume` no longer leaves
a live watcher polling a merged PR.
