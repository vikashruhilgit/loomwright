# twin-remediation/11 — Migrate the remaining direct harness-root readers onto `LOOMWRIGHT_ROOT`

## Status: proposed

> Propose-only follow-up filed by twin-remediation/10 (the core contract PR). Not enqueued; a human promotes it by
> moving it out of `proposed/`. Named in `loomwright/docs/CORE_CONTRACT.md` §"Root resolution".

## Problem
`loomwright/scripts/resolve-loomwright-root.sh` is meant to be the ONE place the harness install-root variable
(`CLAUDE_PLUGIN_ROOT`) is read. It publishes the vendor-neutral `LOOMWRIGHT_ROOT`. Scripts still read the harness
variable directly, so a non-Claude adapter has to set the harness's own variable instead of the neutral name.

## Measured list (base commit 0aa53c37ac59fe86a99bd590b36b379d24f9956b)
Command: `git grep -c -F CLAUDE_PLUGIN_ROOT HEAD -- loomwright/scripts/ scripts/`, excluding the resolver itself and
its fixtures. Each line is classified as a code line or a comment-only line (a line whose first non-blank character
is `#`). A "code" line can be a string literal, for example inside an error message. Check each one by hand before
migrating it.

Non-test scripts (code lines / comment lines):
- loomwright/scripts/add-orientation.sh 2/0
- loomwright/scripts/add-rule.sh 2/0
- loomwright/scripts/audit-rules.sh 4/0
- loomwright/scripts/automate-lanes.sh 1/1
- loomwright/scripts/build-capabilities.sh 1/0
- loomwright/scripts/build-handoff.sh 1/3
- loomwright/scripts/build-insights.sh 2/0
- loomwright/scripts/emit-progress-event.sh 0/1 (comment only)
- loomwright/scripts/guard-finalize-publish.sh 1/0
- loomwright/scripts/propose-domain.sh 1/0
- loomwright/scripts/set-otel-resource-attrs.sh 2/0
- loomwright/scripts/validate-entry.sh 2/4
- loomwright/scripts/write-agent-memory.sh 2/0
- loomwright/scripts/write-lessons.sh 2/0
- loomwright/scripts/write-project-memory.sh 2/0
- loomwright/scripts/write-system-contract.sh 2/0
- scripts/check-contract-parity.sh 1/0

Test scripts:
- loomwright/scripts/test-automate-lanes.sh 1/0
- loomwright/scripts/test-automate-loop-split.sh 1/0
- loomwright/scripts/test-build-capabilities.sh 2/0
- loomwright/scripts/test-build-handoff.sh 10/4
- loomwright/scripts/test-check-contract-parity.sh 4/0
- loomwright/scripts/test-guard-lane-wait-armed.sh 1/0
- loomwright/scripts/test-host-mode.sh 1/0
- loomwright/scripts/test-product-seam.sh 3/0
- loomwright/scripts/test-propose-domain.sh 2/0
- loomwright/scripts/test-rules-audit-line.sh 2/0
- loomwright/scripts/test-rules-gate-seams.sh 2/0
- loomwright/scripts/test-set-otel-resource-attrs.sh 5/3
- loomwright/scripts/test-setup-memory.sh 0/1 (comment only)
- loomwright/scripts/test-validate-entry.sh 4/1

Fixture data that also matches (do not migrate; it is recorded data): loomwright/scripts/fixtures/corpus-briefs/done/2026-05-31-p4-consume-path.md, loomwright/scripts/fixtures/harvest-ledger/results.jsonl.

Out of scope for this item: the prompt layer (agents/commands/skills) and `loomwright/hooks/hooks.json`. The hook
manifest is ADAPTER-classed and may name the harness. The prompt layer is ratcheted by
`scripts/check-vendor-coupling.sh`.

## Goal
Each listed non-test script sources `resolve-loomwright-root.sh` and uses `LOOMWRIGHT_ROOT`. Each test exercises
both the harness-variable path and the pre-set neutral-name path. The ratchet's counts for the migrated files fall
(allowances lowered in the same PR, reasons updated).

## Acceptance criteria
- No non-test script under `loomwright/scripts/` or `scripts/` reads the harness root variable outside the resolver.
  Re-measure with the command above; comment-only mentions may stay.
- Claude-path compatibility verified: marketplace installs still resolve (`test-resolve-loomwright-root.sh` + each
  migrated script's own suite green).
- `bash scripts/ci-local.sh` green.

## Notes
Run this ALONE, after the engine items: the sweep touches many scripts and conflicts with every script-touching item
(requirement twin-remediation/10, Re-scope 2026-10-10).

## Depends on
../twin-remediation/10-harness-portability.md

## Touches
unknown
