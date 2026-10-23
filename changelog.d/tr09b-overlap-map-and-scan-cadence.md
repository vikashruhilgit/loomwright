The native overlap decisions are recorded, and a minor or major bump reminds you to re-scan the platform
A new `loomwright/docs/NATIVE_OVERLAP.md` records the native-vs-ours verdicts, and every platform claim in it
cites a `CAPABILITY_BASELINE.json` entry or is marked unverified. The Execute Manager poll loop vs native
background completion notifications (2b) is KEEP OURS: the baseline records that capability only by name, and
whether a notification reaches a subagent is unverified. Supervisor's worker worktrees vs native
`isolation: worktree` (2d) is BLOCKED, because the native worktree branches from the default branch, not the
parent session's HEAD; an owner-run re-probe in a reinstalled-plugin session is the trigger to revisit. The
Workflow tool and nested spawning (2c) and Agent Teams (2e) are KEEP OURS. The agent-teams skill's dated
graduation snapshot is replaced by the 2e verdict and a pointer. `bash scripts/bump-version.sh` now prints
`bump-version: capability baseline last scanned at <X.Y.Z>; run /capability-check` on every minor or major bump
and its first-bump `--dry-run`, reading `plugin_version_at_last_scan` live from the baseline. A patch bump,
`--check`, a `--refold` no-op, a re-fold `--dry-run` and a missing or invalid baseline print nothing, and the
line never changes the exit status.
