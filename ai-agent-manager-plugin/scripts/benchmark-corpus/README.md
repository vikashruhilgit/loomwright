# benchmark-corpus — fixed deterministic inputs for run-benchmark.sh

This directory holds a small, fixed corpus that `run-benchmark.sh` validates to produce a
**deterministic** "provable-done" metric (`selftest_pass_count`).

## What the corpus is

Each `*.jsonl` file is a single candidate `session_end` event (the System Twin hard-signal event,
see `docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields"). The benchmark applies a
fixed conformance check to each file and counts how many **conform** to the hard-signal field
contract. Because both the corpus and the check are fixed, the same corpus always yields the same
count — there is no wall-clock or environment sensitivity in the primary metric.

The corpus intentionally contains BOTH conforming and non-conforming fixtures so the metric is a
meaningful count (not trivially "all pass"):

| file | conforms? | why |
|------|-----------|-----|
| `valid-pass.jsonl`            | yes | all 6 flat hard-signal fields present, valid enums/types |
| `valid-advisory.jsonl`        | yes | advisory_violations + regressed, with delta |
| `valid-skipped-nulls.jsonl`   | yes | skipped/unverified with null value+delta (the no-data case) |
| `valid-improved.jsonl`        | yes | improved benchmark with positive delta |
| `bad-missing-field.jsonl`     | no  | omits `benchmark_status` (a required flat field) |
| `bad-enum.jsonl`              | no  | `contract_conformance_status` has an out-of-enum value |
| `bad-not-session-end.jsonl`   | no  | `event` is not `session_end` |

## Adding fixtures

Add a fixture and (if it should count) make it conform to the contract checked by
`run-benchmark.sh`. Re-run `test-benchmark.sh`; the self-test recomputes the expected pass count
from the corpus itself, so it stays green as long as `run-benchmark.sh`'s checker and the corpus
agree. Keep fixtures deterministic — no timestamps that affect the verdict.
