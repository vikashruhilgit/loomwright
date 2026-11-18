<!-- bump: patch -->
A reviewed QA-removal manifest and a per-row checker for it (qa-split 11a)
`loomwright/docs/qa-removal-manifest.md` lists every QA path and named QA reference outside `selvedge/` — 433 rows,
each marked `delete`, `re-point` or `keep` with the item that acts on it (11b1, 11b2 or 12) — plus the rollback
tag `pre-qa-removal` (created by 11b1, not here) and the exact search that generated the list.
`loomwright/scripts/check-qa-removal-manifest.sh` turns it into a gate: with no `--expect` it reports and exits 0;
`--expect 11b1|11b2|12` fails on any selected `delete` path still present, `keep` path missing, or (at 12)
`re-point` reference still present, and it refuses a malformed manifest (exit 2) instead of skipping a row. Keep
rows protect `verify-provides.sh`, the `outputs_verified` gate, the `unit-testing` and `quality-checklist` skills and
the deferred `qa-executor:` Executable Acceptance kind. Nothing is deleted or re-pointed by this change.
