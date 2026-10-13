<!-- bump: minor -->
`reconcile-status --apply` promotes a merged `brief-shipped` requirement
`stamp-requirement-status.sh` writes `## Status: brief-shipped` on a requirement with no status once its brief reaches
`.supervisor/jobs/done/`, and `reconcile-status` used to answer that heading with an `info` row and return before it
looked for evidence. That return hid every plain `/supervisor` or `/autonomous` requirement from the one recovery path
its honest limit names, so merged work stayed not-done and `resolve-folder` and `plan-waves` offered it again (27 such
files in the owner's checkout; #447). By owner decision (2026-10-13) a `brief-shipped` file now takes the same evidence
path as any other requirement that is not done: a merged PR that cites it on an implements line, or whose head branch
matches its done brief's slug, with the same exclusions (trail PRs, PRs that only touch `.supervisor/`, PRs whose own
diff changes the requirement, unreadable diffs). The dry run prints a `plan` row for it. `--apply` appends the §6 done
stamp below the `brief-shipped` heading, which stays in place. With no evidence, or when the file is also `parked` or
`proposed`, it still gets only the `info` row. `stamp-requirement-status.sh` is unchanged. Tests H6a–H6d in
`test-automate-helpers.sh`, plus a mutation control that restores the early return.
