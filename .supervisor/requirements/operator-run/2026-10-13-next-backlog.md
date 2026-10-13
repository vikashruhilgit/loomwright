# Backlog 2026-10-13 — verified-rule-checks, af/39b run-lock, tr/08b, af/39a janitor, pa/18 board (sequential, no --parallel)

## Status: parked (operator-run backlog doc: run it with `/loomwright:automate --backlog .supervisor/requirements/operator-run/2026-10-13-next-backlog.md` AFTER af36-remainder/03 has merged)

Sequential on purpose (owner 2026-10-13): no wave for single items. One PR per item; merge it, then `--resume <run_id>` for the next.

Corrected 2026-10-13: af/39 and pa/18 were removed after reading their Re-scope sections. pa/18's remaining
Parts A and B are PARKED (Part C shipped in #488). af/39's Part C shipped (#490); Parts A and B are to be split
into separate items and Part B has two open owner decisions (wrapper skip-list; where skip rows are logged).
af36-remainder/03 runs on its own first: `/loomwright:automate --folder .supervisor/requirements/af36-remainder`.

- [ ] .supervisor/requirements/verified-rule-checks.md
- [ ] .supervisor/requirements/automate-followups/39b-run-lock-and-guard-arm.md
- [ ] .supervisor/requirements/twin-remediation/08b-single-lane-sequential.md
- [ ] .supervisor/requirements/automate-followups/39a-sweep-and-janitor.md
- [ ] .supervisor/requirements/parallel-automate/18-backlog-board-and-right-size.md

Not in this backlog: af/39 A/B (split + decisions first); pa/18 A/B (parked); twin-remediation/09 (shipped in #489,
needs only its stamp); twin-remediation/08 items 1 and 4 (owner design decision); verify-walkthrough/operator-run/08
(manual dogfood run).

Added 2026-10-13 (owner): tr/08b (tr/08 items 1+4 as single-lane mode), af/39a (Part A split out: sweep + registry +
/janitor), pa/18 Parts A+B un-parked (Part C shipped #488). af/39 Part B queued second as af/39b (owner decisions made 2026-10-13).
