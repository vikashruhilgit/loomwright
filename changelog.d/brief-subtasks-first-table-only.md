<!-- bump: patch -->
Supervisor's next-step driver reads only the subtask table as the plan
`sn_brief_subtasks` in `supervisor-next-step.sh` read every table under `## Subtask Structure`, so the
`### File Impact Map` table that briefs put in the same section added its header cell (`Group`) and any single-word
group names to the plan as extra subtask ids. The provider-routing write-seats brief planned `[1,2,3,"Group"]`, and
12 of the 248 archived briefs parsed wrong. The parser now reads only the section's first table and skips that
table's header row by position, not by whether the cell happens to fail the id pattern.
`test-supervisor-next-step.sh` case B1b pins the two-table shape.
