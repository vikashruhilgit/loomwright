<!-- bump: patch -->
Review-gate rounds measured before and after v17.2.0 (evidence only)
`docs/evidence/review-gate-rounds.md` (automate-speed/23) reports, for every `/automate` item whose PR merged on
plugin v17.2.0 or later, the Phase 4.5 rounds and duration, the termination reason, the Plan Review attempts and the
Launch Pad duration, next to the items before v17.2.0. 5 of the 16 post-v17.2.0 items hit 3/3 rounds, against 7 of 7
on plugin 16.0.0 to 17.0.2 and 15 of 58 across all earlier items with recorded rounds. That is under half, so no
follow-up draft was filed. A cell whose source does not record a value reads `not recorded (<source>)`. The file
holds the inline `jq`/`awk` commands that print every table from local `.supervisor/` data (carried on
`loomwright-meta`), pinned to a frozen ledger cutoff and PR list. No plugin code, prompt or cap changes.
