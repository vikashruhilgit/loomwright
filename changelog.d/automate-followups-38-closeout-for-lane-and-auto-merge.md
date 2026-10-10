<!-- bump: minor -->
Every merged `/automate` item is stamped done by `closeout`, including `--auto-merge` and `--parallel` lanes (automate-followups/38)
`automate-helpers.sh closeout` gains `--no-trail` (accepted in any argument position, like `--session-id`):
every step runs exactly as before (evidence gate, brief repair, cleanup, sync, requirement stamp, check-off,
`## Current` reconcile, `## Progress`, `item_timing`) except the trail step, which prints
`trail-pr: skipped — --no-trail` instead. That line is not a `closeout:` line, so `closeout-classify` reads
such a run as `complete`. Plain `closeout` is byte-unchanged. Two callers use the flag. (1) `--auto-merge`
§6 step 5 SYNC now runs `closeout <runfile> <item> <pr_url> --no-trail --session-id <sid>` after
`gate-eval` printed `MERGE`. This replaces the bare `brief-repair` call and SYNC's own
`git checkout main && git pull`: closeout's ff-only sync does the pull, and a sync skip reaches the same
close-out leftover gate as RECONCILE. SYNC passes `--no-trail` in both branch modes. A trail PR would make
the next PICK park `trail_pr_open`, and a per-merge meta push would be a fourth trail trigger, so the
item's trail still ships at the existing triggers. Step 6 finds the item already checked off. (2) A
`--parallel` lane's `lane-convert-ready`, re-run once its PR merged (`awaiting_merge`), now runs
`closeout <lane run file> <item> <## Current pr> --no-trail` inside the lane. It runs under the launch
lock and before the pushes, and no `current-set` follows it. The run echoes closeout's lines indented and
names any leftover in its last line, and its exit codes are unchanged. A lane already reconciled to
`done` / `awaiting_go` is accepted on a re-run, which retries only the pushes. closeout's "already stamped"
check now counts only a real stamp block: the sentinel alone on its line, followed by a `## Status: done` /
`done_with_escalation` heading. A sentinel quoted in prose (as automate-followups/37's own requirement
does) no longer blocks the stamp. That check was the only `requirement-closeout` reader in
`loomwright/scripts`. With this change the honest limit "an `--auto-merge` item gets no done stamp" is
retired in the `automate-loop` skill, `self-heal-advisory` step 2.5 and `ground-truth-json.md`. New legs:
`test-automate-trail.sh` NT1–NT6 and `test-automate-lanes.sh` AB1–AB6.
