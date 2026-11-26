# Selvedge app-aware checks: response reads, read-only and ready, and a setup scout (plan doc, not an implementable item)

## Status: pending (index document — nothing to implement)

## Why now
The 2026-11-23 review of hub's `e2e-ticket` skill and e2e scripts found three ideas Selvedge lacks:
- reading the HTTP response an action caused;
- a read-only switch for local apps on shared data;
- a named "app not ready" result.

The first is aimed at the Phase 2 gate. Held-out abstention is 0.587 against a 0.20 limit, and 16 of 72 tuning cases are `side_effect_not_observable` for want of a status or cookie read. The owner then asked for one agent that learns the app, asks only what it can't find in plain words, and keeps up as the app changes. That is the setup scout.

## Owner decisions
none recorded

## Order
| Item | Delivers | Depends on | Can run in parallel with |
|---|---|---|---|
| 2026-11-23-100810-selvedge-reads-the-response-an-action-caused | a response-read step plus the snapshot's request list; measured on the tuning set | none | none (shares the release files and README with the next item) |
| 2026-11-23-100810-selvedge-read-only-mode-and-ready-check | `read_only` (on for new configs) and `ready`, with `read_only_mutation_refused`, `env_hooks_read_only` and `target_not_ready` | none | none (same reason) |
| 2026-11-23-100810-selvedge-setup-scout-learns-the-app-and-asks-only-what-it-cannot-find | `/selvedge:setup`: the scout proposes settings and asks only what it can't find; a rerun is the checkup (differences and run-history suggestions) | both above | none |

## Run
/automate --backlog .supervisor/requirements/_BACKLOG-2026-11-23-100810-selvedge-app-aware-checks.md

Run it sequentially in safe mode (no `--auto-merge`). Each item is its own Selvedge release, bumped in its own `plugin.json` and `CHANGELOG.md`, with no `changelog.d/` fragment. The wave plan puts read-only first only because it sorts first. Take the response read first: it is the one that moves the gate.

## Considered and not queued
- Screenshots posted to Jira or the PR (as hub does): ruled out by qa-split D13. The PR comment stays text-only.
- A per-run "prove the check can fail" mutation step: needs a human to break the code. The known-answer set covers it engine-wide.
- Hub-specific diagnosis (Redis throttle, gateway cache, VPN): these belong in a project's approved hooks.
- Criteria fetched straight from Jira or Linear by the adapter: small, adapter-only, not asked for yet.
- A layer hint in the planner's rewrite (a backend rule needs a unit test): small prompt change; fold it into the response-read item if it fits.
- Hub as a dogfood target: the owner's call. It needs the read-only item first.

## Revisit when
- The response-read tuning run does not lower `side_effect_not_observable`, or raises false-PASS above 0 of 12. Re-plan before the scout.
- The Phase 2 gate's second engine revision misses (plan §8 review).

## Checklist
- [ ] .supervisor/requirements/2026-11-23-100810-selvedge-reads-the-response-an-action-caused.md
- [ ] .supervisor/requirements/2026-11-23-100810-selvedge-read-only-mode-and-ready-check.md
- [ ] .supervisor/requirements/2026-11-23-100810-selvedge-setup-scout-learns-the-app-and-asks-only-what-it-cannot-find.md
