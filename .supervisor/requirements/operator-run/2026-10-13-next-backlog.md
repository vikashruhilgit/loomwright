# Backlog 2026-10-13 — af36-remainder/03, af/39, pa/18, verified-rule-checks (sequential, no --parallel)

## Status: parked (operator-run backlog doc: run it with `/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-13-next-backlog.md`)

Sequential on purpose (owner 2026-10-13): no wave for single items. One PR per item; merge it, then
`/loomwright:automate --resume <run_id>` for the next. af/39 and pa/18 share files, so they could not run in
parallel anyway.

Prep done 2026-10-13: af36-remainder/03 moved out of run `automate-2026-10-12-181635` (checked off `# skipped`,
run finalized); af/39 and pa/18 Touches re-pointed to `fixtures/automate-helpers-help/` and
`skills/automate-loop/` (both split since they were written); verified-rule-checks' Touches notes moved out of the
machine-read section. All four lint clean.

- [ ] .supervisor/requirements/af36-remainder/03-meta-sync-learning-stores.md
- [ ] .supervisor/requirements/automate-followups/39-engine-hygiene.md
- [ ] .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md
- [ ] .supervisor/requirements/verified-rule-checks.md

Not in this backlog: twin-remediation/09 (shipped in #489, needs only its stamp); twin-remediation/08 (items 1 and 4
need an owner design decision); verify-walkthrough/operator-run/08 (manual dogfood run).
