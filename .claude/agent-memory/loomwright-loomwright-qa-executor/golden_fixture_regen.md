---
name: golden-fixture-regen
description: Golden fixtures need a WRITE_GOLDENS=1 regen path + a normalise rule for every release-varying value
metadata:
  type: feedback
---
Rule: any golden-file self-test (e.g. test-telemetry.sh) must regenerate goldens via
`WRITE_GOLDENS=1` whenever the captured payload gains/loses a key, and every
release-varying value must have a `normalise_for_golden` rule (e.g. plugin_version →
"<NORMALISED>").
**Why:** goldens silently rot on the next additive change or version bump and produce
false failures or, worse, lock in a stale shape.
**How to apply:** when a payload schema changes, flag missing regen + missing
normalise rule as a coverage gap. Source: worker-summary ST4 (setup-observability).
