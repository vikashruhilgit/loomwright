<!-- bump: patch -->
`/automate --parallel N --cheap` now applies the Sonnet cost profile inside every lane
Before this fix `--cheap` never reached a lane: `lane-launch` sent each lane a fixed `/loomwright:automate --backlog …`
command with no flags, so every worker and code-reviewer in a lane ran on the session's default model. Now
`lane-create --cheap` records `"cheap": true` in the lane's `lane.json`, `lane-launch` adds `--cheap` to every
`/loomwright:automate` command it sends (launch, and `--resume-run` in the last session or the fresh fallback), and
the in-lane `automate-next-step.sh` reads the same record, so a `--continue` or answer resume keeps the profile too.
Without `--cheap` nothing changes: `lane.json` has no `cheap` key and no spawn carries the flag. A sequential run's
`--cheap` stays passthrough-only and is still not written to `## Run Config`.
