<!-- bump: patch -->
/rules audit: a retracted supersedes target is a resolved supersession, not a dangling one (#430)
Superseding a rule made `audit-rules.sh` block on `dead_rule`, and the recommended retract then made it block on
`dangling_supersedes`, so no state reachable through `add --supersedes` and `retract` was clean. The audit could not
tell a target retracted on purpose from an id that never existed. It now decides that from the store's git history:
a `supersedes` target that some committed version of the store held as a rule id is listed under a new
`## Resolved supersessions` section (not a finding, never exit-bearing); an id that never existed stays BLOCKING
`dangling_supersedes`; a shallow clone or a store outside git, where "never existed" is unproven, reports the dangle
UNKNOWN (exit 2). The `dead_rule` remedy now names the one step to that clean end state, and says to commit first
when the superseded rule was never committed. `skills/rules/SKILL.md` §11.4 documents the end state.
