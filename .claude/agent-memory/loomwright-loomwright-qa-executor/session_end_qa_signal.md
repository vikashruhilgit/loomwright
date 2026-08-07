---
name: session-end-qa-signal
description: The durable per-session QA record is the session_end JSON line in .supervisor/logs/{id}.jsonl
metadata:
  type: reference
---
The structured QA/quality record per supervisor session is one JSON line in
`.supervisor/logs/{session_id}.jsonl` carrying: heal_decision, heal_iterations,
contract_conformance_status, contract_violations, benchmark_status,
benchmark_metric (=selftest_pass_count).
Advisory tiers (contract_violations, rubric, benchmark) NEVER gate a PASS — an
intended contract change shows as `contract_violations:1` with `heal_iterations:0`
and self-heals next run. Conformance is `skipped` unless the brief authored an
`## Executable Acceptance` ground-truth surface (skipped 5 / pass 1 / advisory 2
across the 11 reviewed sessions). ~21 verified contracts in .supervisor/twin/contracts/.
**How to apply:** read this line for retrospective QA signal; don't treat advisory
violations as failures.
