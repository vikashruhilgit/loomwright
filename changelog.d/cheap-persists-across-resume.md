<!-- bump: minor -->
/automate --cheap stays on across --resume and reaches the /review-pr drain, until --no-cheap
A sequential `/automate` run started with `--cheap` now records `- cheap: true` in its `## Run Config`, so a bare
`--resume` keeps the Sonnet cost profile instead of silently reverting the rest of the Queue to full cost.
`scripts/automate-next-step.sh` writes the line when it is called with `--cheap`, reads it on every spawn, and
puts `--cheap` on the `/autonomous` and Supervisor spawns and on every drain spawn (the owned drain, inline or as a
fresh phase, and the fix-now re-drain's `/review-pr <pr> --until-mergeable --no-auto-postmortem --cheap`).
`--no-cheap` is the off switch: it removes the line and writes one `cheap mode off (--no-cheap)` `## Progress`
line. Both flags on one command are refused as `cheap_flags_conflict` (exit 2, nothing written). A `cheap:` value
other than `true` reads as off, with one `cheap_value_unrecognised` warning on stderr. Inside a lane,
`.supervisor/lane.json` is the only record: the driver ignores a command-line `--cheap` and never writes the run
file's `cheap` line, and `lane-launch … --no-cheap` (launch, `--resume-run` or `--continue`) removes `cheap` from
`lane.json` before it spawns. Without either flag every spawn is byte-identical to before. The new
`scripts/test-automate-next-step.d/14-cheap-persist.sh` part and the `Z-CHl`–`Z-CHr` legs of the lanes suite pin it.
`commands/automate.md`, the automate-loop skill files, the run-file template, `docs/result-schemas/automate-run.md`
and the loop inventory now say the profile is persisted and name `--no-cheap`.
