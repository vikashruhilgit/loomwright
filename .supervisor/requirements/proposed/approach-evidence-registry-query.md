# design decisions: decide whether a package-registry query is an allowed evidence source

## Status: proposed

> Propose-only follow-up from run `automate-2026-11-11-173032` (approach-decisions/02, PR #895). Not enqueued.
> Raised by the CI `claude-review` on 8e40962 (Medium, carried over from f063e40).

## Problem (observed 2026-11-12, V4 run in `docs/evidence/design-decisions.md`)
`skills/supervisor-readiness/design-decisions.md` §"Evidence sources" allows exactly three sources: the repo,
Context7 and `WebSearch`. In V4, Launch Pad Phase 2.7 ran `npm view express-rate-limit@8.7.4 exports
peerDependencies …; npm view rate-limiter-flexible version` through Bash and quoted it in the T1 entry's
`evidence:` line. Plan Review Criterion 23 passed the entry. So the closed list is not enforced by either side,
and the run shows a registry query is the cheapest way to answer "does this version support X".

## Scope (owner picks one)
A. Allow it: add "the package registry (`npm view`, `pip index`, …), read-only" as a source, with the same
   quote-what-it-returned rule; Criterion 23 accepts it.
B. Reject it: Criterion 23 (23b or a new sub-check) fails an `evidence:` line whose quoted command is outside the
   three sources; Launch Pad's Phase 2.7 text says so.
Either way: a fixture brief with an `npm view` evidence line and a test leg that pins the chosen verdict.
