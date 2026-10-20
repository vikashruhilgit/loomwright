<!-- bump: minor -->
`/automate` prompts carry rules, not stories; the run-file template and driver-owned steps load only when used
The automate-loop group's runtime prompts (`skills/automate-loop/*.md` other than `helpers.md`, and
`commands/automate.md`) are cut to instructions and short rules (automate-speed/16). Every story and history note
moved to the new `loomwright/docs/rationale/automate-loop.md`, and every `story` row of
`docs/loop-inventory/automate-loop.md` is now homed there. Prose that only restated what `automate-next-step.sh`,
`automate-helpers.sh`, `automate-lanes.sh`, `automate-wave.sh`, `lane-policy.sh` or `meta-sync.sh` already run is
replaced by one line wherever the coordinator could otherwise act by hand, and the rule rows point at the script
arm that runs them. The run-file template, item lifecycle and `## Current` transition table left the always-read
`SKILL.md` index for a new split file, `skills/automate-loop/run-file.md`, read only under its own Step 0
**Only when** trigger; the skill's second copy of the command's flag list became a pointer to it. Every pinned
needle, heading, numbered step and existing Step 0 trigger stays byte-identical, and one test read was repointed
(path only) to `run-file.md`. No behaviour change. The before and after byte counts, history-reference counts, gate
results and mutation controls are recorded in `docs/evidence/as16-diet-automate-loop.md`.
