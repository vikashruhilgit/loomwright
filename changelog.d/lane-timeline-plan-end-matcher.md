<!-- bump: patch -->
/lanes Build step shows its start time again: one plan-end matcher for the timeline and the token ledger
The /lanes step timeline only recognised a Launch Pad Progress line containing the words "brief saved", but the
fresh-phase driver writes the pinned line `launch-pad saved <brief>`, so every fresh-phase lane's Build step read
"no time recorded" (run automate-2026-10-15-163325, L21–L25). The new `scripts/progress-line-match.sh` holds the
one plan-end matcher (a jq `def plan_end`), and both `automate-lanes.d/status-read.sh` and
`read-token-ledger.sh --per-item` now use it in place of their own patterns. If the file cannot be read, the
timeline fails safe (no Build start) and the ledger prints a `progress_matcher_unreadable` note with Launch Pad
`not recorded`. `per-item-loop.md` step 2 now pins the line's wording, and test-automate-next-step.sh R12 scans the
shared file. Older free-form lines that say "brief saved" in mid-sentence no longer start Build, which matches
what the ledger already did.
