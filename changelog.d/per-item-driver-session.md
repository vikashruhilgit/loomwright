<!-- bump: patch -->
read-token-ledger.sh --per-item counts the /automate driver session
With fresh phase sessions (the default) the `/automate` coordinator that drives an item's phases is a Claude Code
session of its own, and the run file never named it: `read-token-ledger.sh --per-item` resolved only the
launch-pad, supervisor and drain sessions, so every fresh-phase item under-counted by the coordinator's share
(7.4M of 55.6M tokens, 13%, on lane L2 of automate-2026-10-27-125907; sequential fresh-phase runs had the same
gap). `automate-next-step.sh` now writes `session_id <--session-id> (<item>) phase=driver` once per coordinator
session per item, before the first phase spawn it prints, and the report reads it like any other session line.
`phase-timing.sh` skips that line, so the coordinator is never mistaken for the Supervisor session it times.
`--inline-phases` writes none: there the coordinator runs `/autonomous` itself and is already resolved. Run files
written before this change still name no driver.
