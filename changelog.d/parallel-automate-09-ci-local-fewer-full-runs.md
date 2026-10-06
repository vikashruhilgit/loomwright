<!-- bump: minor -->
ci-local.sh keeps every run's log, reads it back with --last, and adds an --affected inner-loop check
Lanes ran the full local suite several times per push, partly to re-read output a finished run had not kept, partly
as an inner-loop check after small fixes. Every `scripts/ci-local.sh` run that starts the pool now writes its whole
transcript (stdout and stderr, FAIL banners included) to `runs/` in the repo-keyed shared state dir, prints the log
path as its first and last line (a log removed mid-run by something else is reported instead), and ends the log with
its verdict line; at most 20 logs are kept, every still-running run's log among them (a live transcript is never
pruned; only more than 20 live runs at once leave more). `--last` prints the newest full-run log for the current tree
with PASS, FAIL, UNVERIFIED (the run passed but the tree changed under it, so nothing was cached; exit 1), INCOMPLETE
(no verdict: interrupted or still running) or stale-key, and runs nothing. `--affected` maps the files changed since the merge-base with origin/main
(untracked included) to their suites, adds the cheap check-* and validate-version gates, runs that subset through
the same pool under a CI slot, lists unmapped files as not covered, never touches a pass stamp, and always ends with
the affected-only marker. With no flag the gate list, cache key, stamp rule and slot behaviour are unchanged.
`AGENT_GUIDELINES.md` and the worker prompt now say: iterate with the affected-only check, run the full pre-push
command once per push, read a saved result instead of re-running.
