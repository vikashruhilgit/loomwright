# Small commands document their exit codes

## Status: pending

## Goal
A user of `/janitor`, `/handoff` or `/obsidian` can see on the command's own page what each exit code means, without reading the script behind it.

## Acceptance Criteria
- [ ] **AC1.** Given `loomwright/commands/janitor.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/janitor` can return and what it means.
- [ ] **AC2.** Given `loomwright/commands/handoff.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/handoff` can return and what it means.
- [ ] **AC3.** Given `loomwright/commands/obsidian.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/obsidian` can return and what it means.
- [ ] **AC4.** Given any of the three tables, when it is compared with the script the command runs, then every code the script can return is in the table and the table names no code the script never returns.

## Non-goals
- No change to any exit code, or to any script behind these commands.
- No `## Exit codes` section on any other command.

## Validation (must pass before merge)
1. **Static — doc currency:** `bash scripts/check-doc-currency.sh` passes.

## Depends on
none
